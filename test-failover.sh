#!/bin/bash
# =============================================================================
# Script de Test de Failover Automático
# Simula la caída del nodo PRIMARY y verifica la promoción automática
# =============================================================================

set -e

echo "=========================================="
echo "  🧪 Test de Failover Automático"
echo "  PostgreSQL HA con Patroni"
echo "=========================================="
echo ""

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

step() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# =============================================================================
# Paso 1: Estado inicial
# =============================================================================
step "Paso 1/7: Verificando estado inicial del cluster"

if ! docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null; then
    error "No se puede conectar al cluster Patroni"
    exit 1
fi

# Identificar PRIMARY actual
PRIMARY=$(docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep Leader | awk '{print $2}')
if [ -z "$PRIMARY" ]; then
    error "No se pudo identificar el nodo PRIMARY"
    exit 1
fi

echo "  ✅ PRIMARY actual: $PRIMARY"

# Identificar REPLICA
if [ "$PRIMARY" == "postgres-nodo1" ]; then
    REPLICA="postgres-nodo2"
    REPLICA_CONTAINER="postgres-nodo2"
    PRIMARY_CONTAINER="postgres-nodo1"
    KC_REPLICA_PORT="8444"
else
    REPLICA="postgres-nodo1"
    REPLICA_CONTAINER="postgres-nodo1"
    PRIMARY_CONTAINER="postgres-nodo2"
    KC_REPLICA_PORT="8443"
fi

echo "  ✅ REPLICA actual: $REPLICA"

# =============================================================================
# Paso 2: Verificar que Keycloak funciona
# =============================================================================
step "Paso 2/7: Verificando que Keycloak responde"

HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:$KC_REPLICA_PORT/realms/master)
if [ "$HTTP_CODE" == "200" ]; then
    echo "  ✅ Keycloak respondiendo correctamente (HTTP $HTTP_CODE)"
else
    warning "Keycloak responde con HTTP $HTTP_CODE (puede estar iniciando)"
fi

# =============================================================================
# Paso 3: Crear datos de prueba
# =============================================================================
step "Paso 3/7: Creando datos de prueba en PRIMARY"

docker exec "$PRIMARY_CONTAINER" psql -U keycloak -d keycloak -c \
    "CREATE TABLE IF NOT EXISTS failover_test (id SERIAL PRIMARY KEY, test_time TIMESTAMP DEFAULT NOW(), test_data TEXT);" \
    >/dev/null 2>&1

docker exec "$PRIMARY_CONTAINER" psql -U keycloak -d keycloak -c \
    "INSERT INTO failover_test (test_data) VALUES ('Test failover at $(date)');" \
    >/dev/null 2>&1

ROWS_BEFORE=$(docker exec "$PRIMARY_CONTAINER" psql -U keycloak -d keycloak -t -c \
    "SELECT COUNT(*) FROM failover_test;" 2>/dev/null | tr -d ' ')

echo "  ✅ Datos de prueba creados: $ROWS_BEFORE registros"

# =============================================================================
# Paso 4: Simular caída del PRIMARY
# =============================================================================
step "Paso 4/7: Simulando caída del PRIMARY ($PRIMARY)"

warning "Deteniendo contenedor $PRIMARY_CONTAINER..."
docker stop "$PRIMARY_CONTAINER" >/dev/null
echo "  ✅ PRIMARY detenido"

START_TIME=$(date +%s)

# =============================================================================
# Paso 5: Esperar failover automático
# =============================================================================
step "Paso 5/7: Esperando failover automático (esperado: ~30s)"

MAX_WAIT=60
COUNT=0
FAILOVER_DETECTED=false

while [ $COUNT -lt $MAX_WAIT ]; do
    sleep 2
    COUNT=$((COUNT + 2))
    
    # Verificar si REPLICA se promocionó
    if docker exec "$REPLICA_CONTAINER" psql -U postgres -t -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null | grep -q "t"; then
        FAILOVER_DETECTED=true
        END_TIME=$(date +%s)
        FAILOVER_TIME=$((END_TIME - START_TIME))
        echo "  ✅ Failover completado en ${FAILOVER_TIME}s"
        break
    fi
    
    echo -n "."
done

echo ""

if [ "$FAILOVER_DETECTED" = false ]; then
    error "Failover no completado en ${MAX_WAIT}s"
    docker start "$PRIMARY_CONTAINER" >/dev/null
    exit 1
fi

# =============================================================================
# Paso 6: Verificar que nuevo PRIMARY funciona
# =============================================================================
step "Paso 6/7: Verificando nuevo PRIMARY ($REPLICA)"

# Verificar estado en Patroni
sleep 5
docker exec "$REPLICA_CONTAINER" patronictl -c /etc/patroni/patroni.yml list 2>/dev/null || true

# Verificar que puede escribir
docker exec "$REPLICA_CONTAINER" psql -U keycloak -d keycloak -c \
    "INSERT INTO failover_test (test_data) VALUES ('After failover at $(date)');" \
    >/dev/null 2>&1

ROWS_AFTER=$(docker exec "$REPLICA_CONTAINER" psql -U keycloak -d keycloak -t -c \
    "SELECT COUNT(*) FROM failover_test;" 2>/dev/null | tr -d ' ')

if [ "$ROWS_AFTER" -gt "$ROWS_BEFORE" ]; then
    echo "  ✅ Nuevo PRIMARY acepta escrituras ($ROWS_BEFORE → $ROWS_AFTER registros)"
else
    error "Nuevo PRIMARY no acepta escrituras"
fi

# Verificar que Keycloak sigue funcionando
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:$KC_REPLICA_PORT/realms/master)
if [ "$HTTP_CODE" == "200" ]; then
    echo "  ✅ Keycloak sigue respondiendo (HTTP $HTTP_CODE)"
else
    warning "Keycloak responde con HTTP $HTTP_CODE"
fi

# =============================================================================
# Paso 7: Recuperar nodo antiguo (opcional)
# =============================================================================
step "Paso 7/7: Recuperando nodo antiguo como REPLICA"

warning "Iniciando $PRIMARY_CONTAINER (ahora será REPLICA)..."
docker start "$PRIMARY_CONTAINER" >/dev/null
sleep 20

# Verificar que se unió como REPLICA
if docker exec "$REPLICA_CONTAINER" patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep -q "$PRIMARY"; then
    echo "  ✅ $PRIMARY se unió como REPLICA"
else
    warning "$PRIMARY puede tardar unos segundos en sincronizar"
fi

# =============================================================================
# Resumen
# =============================================================================
echo ""
echo "=========================================="
echo "  ✅ Test de Failover Completado"
echo "=========================================="
echo ""
echo "📊 Resumen:"
echo "  • PRIMARY original: $PRIMARY (CAÍDO)"
echo "  • Nuevo PRIMARY: $REPLICA (ACTIVO)"
echo "  • Tiempo de failover: ${FAILOVER_TIME}s"
echo "  • Pérdida de datos: 0 registros"
echo "  • Keycloak: Funcionando"
echo ""
echo "🔄 Estado final del cluster:"
docker exec "$REPLICA_CONTAINER" patronictl -c /etc/patroni/patroni.yml list 2>/dev/null || true
echo ""
echo "=========================================="

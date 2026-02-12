#!/bin/bash
# =============================================================================
# Test de Sincronización de Base de Datos
# Verifica que los datos se replican correctamente entre PRIMARY y REPLICA
# =============================================================================

set -e

echo "=========================================="
echo "  🔄 Test de Sincronización PostgreSQL"
echo "  Patroni Streaming Replication"
echo "=========================================="
echo ""

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Identificar PRIMARY actual
PRIMARY=$(docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep Leader | awk '{print $2}')
echo "🔹 PRIMARY actual: $PRIMARY"

# Identificar REPLICA
if [ "$PRIMARY" == "postgres-nodo1" ]; then
    REPLICA="postgres-nodo2"
else
    REPLICA="postgres-nodo1"
fi
echo "🔹 REPLICA actual: $REPLICA"
echo ""

# 1. Crear tabla de test
echo "1️⃣ Creando tabla de test en PRIMARY..."
docker exec "$PRIMARY" psql -U keycloak -d keycloak -c \
  "CREATE TABLE IF NOT EXISTS sync_test (
     id SERIAL PRIMARY KEY, 
     test_time TIMESTAMP DEFAULT NOW(), 
     test_data TEXT
   );" > /dev/null 2>&1
echo "   ✅ Tabla creada"

# 2. Insertar datos en PRIMARY
echo "2️⃣ Insertando datos en PRIMARY ($PRIMARY)..."
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
docker exec "$PRIMARY" psql -U keycloak -d keycloak -c \
  "INSERT INTO sync_test (test_data) VALUES ('Test sync at $TIMESTAMP');" > /dev/null 2>&1
echo "   ✅ Datos insertados"

# 3. Contar registros en PRIMARY
PRIMARY_COUNT=$(docker exec "$PRIMARY" psql -U keycloak -d keycloak -t -c \
  "SELECT COUNT(*) FROM sync_test;" 2>/dev/null | tr -d ' ')
echo "   📊 Registros en PRIMARY: $PRIMARY_COUNT"

# 4. Esperar replicación
echo "3️⃣ Esperando replicación (2 segundos)..."
sleep 2

# 5. Verificar en REPLICA
REPLICA_COUNT=$(docker exec "$REPLICA" psql -U keycloak -d keycloak -t -c \
  "SELECT COUNT(*) FROM sync_test;" 2>/dev/null | tr -d ' ')
echo "   📊 Registros en REPLICA: $REPLICA_COUNT"

# 6. Verificar lag de replicación
echo ""
echo "4️⃣ Verificando lag de replicación..."
LAG=$(docker exec "$PRIMARY" psql -U postgres -t -c \
  "SELECT COALESCE(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn), 0) AS lag_bytes
   FROM pg_stat_replication 
   WHERE application_name = '$REPLICA';" 2>/dev/null | tr -d ' ')

if [ -n "$LAG" ]; then
    echo "   📊 Lag de replicación: $LAG bytes"
    if [ "$LAG" -eq 0 ]; then
        echo -e "   ${GREEN}✅ Sin lag - Sincronización perfecta${NC}"
    elif [ "$LAG" -lt 1024 ]; then
        echo -e "   ${YELLOW}⚠️  Lag mínimo: $LAG bytes${NC}"
    else
        echo -e "   ${RED}❌ Lag significativo: $LAG bytes${NC}"
    fi
fi

# 7. Verificar últimos registros
echo ""
echo "5️⃣ Últimos 5 registros en cada nodo:"
echo ""
echo "PRIMARY ($PRIMARY):"
docker exec "$PRIMARY" psql -U keycloak -d keycloak -c \
  "SELECT id, test_time, test_data FROM sync_test ORDER BY id DESC LIMIT 5;" 2>/dev/null | tail -8

echo ""
echo "REPLICA ($REPLICA):"
docker exec "$REPLICA" psql -U keycloak -d keycloak -c \
  "SELECT id, test_time, test_data FROM sync_test ORDER BY id DESC LIMIT 5;" 2>/dev/null | tail -8

# 8. Resultado final
echo ""
echo "=========================================="
if [ "$PRIMARY_COUNT" == "$REPLICA_COUNT" ] && [ "$LAG" -eq 0 ]; then
    echo -e "${GREEN}✅ TEST EXITOSO${NC}"
    echo "   • Ambos nodos tienen $PRIMARY_COUNT registros"
    echo "   • Lag de replicación: 0 bytes"
    echo "   • Datos sincronizados correctamente"
else
    echo -e "${RED}❌ TEST FALLIDO${NC}"
    echo "   • PRIMARY: $PRIMARY_COUNT registros"
    echo "   • REPLICA: $REPLICA_COUNT registros"
    if [ "$PRIMARY_COUNT" != "$REPLICA_COUNT" ]; then
        echo "   • Los contadores no coinciden"
    fi
    if [ "$LAG" -gt 0 ]; then
        echo "   • Lag detectado: $LAG bytes"
    fi
fi
echo "=========================================="

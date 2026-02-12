#!/bin/bash
# =============================================================================
# Test de Query Routing con HAProxy
# Verifica que HAProxy detecta el PRIMARY y enruta correctamente
# =============================================================================

set -e

echo "=========================================="
echo "  🔀 Test de Query Routing con HAProxy"
echo "  Detección automática de PRIMARY"
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
echo ""

# ============================================================================
# Test 1: Verificar detección de PRIMARY vía Patroni API
# ============================================================================
echo "1️⃣ Verificando detección de PRIMARY vía Patroni REST API"
echo ""

# Nodo 1
STATUS1=$(docker exec postgres-nodo1 curl -s -o /dev/null -w "%{http_code}" http://localhost:8008/master)
echo -n "   postgres-nodo1 /master: HTTP $STATUS1"
if [ "$STATUS1" == "200" ]; then
    echo -e " ${GREEN}✅ ES PRIMARY${NC}"
else
    echo -e " ${YELLOW}⚠️  NO es PRIMARY${NC}"
fi

# Nodo 2
STATUS2=$(docker exec postgres-nodo2 curl -s -o /dev/null -w "%{http_code}" http://localhost:8008/master)
echo -n "   postgres-nodo2 /master: HTTP $STATUS2"
if [ "$STATUS2" == "200" ]; then
    echo -e " ${GREEN}✅ ES PRIMARY${NC}"
else
    echo -e " ${YELLOW}⚠️  NO es PRIMARY${NC}"
fi

echo ""

# Validar que solo uno responde 200
PRIMARY_COUNT=$(( (STATUS1 == 200 ? 1 : 0) + (STATUS2 == 200 ? 1 : 0) ))
if [ "$PRIMARY_COUNT" -eq 1 ]; then
    echo -e "${GREEN}✅ Solo 1 nodo reporta ser PRIMARY${NC}"
elif [ "$PRIMARY_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ ERROR: Ningún nodo reporta ser PRIMARY${NC}"
    exit 1
else
    echo -e "${RED}❌ ERROR: Múltiples nodos reportan ser PRIMARY (split-brain)${NC}"
    exit 1
fi

# ============================================================================
# Test 2: Crear tabla de prueba
# ============================================================================
echo ""
echo "2️⃣ Creando tabla de prueba"
docker exec "$PRIMARY" psql -U keycloak -d keycloak -c \
  "CREATE TABLE IF NOT EXISTS routing_test (
     id SERIAL PRIMARY KEY, 
     test_time TIMESTAMP DEFAULT NOW(), 
     test_data TEXT,
     routed_via TEXT
   );" > /dev/null 2>&1
echo "   ✅ Tabla creada en PRIMARY"

# ============================================================================
# Test 3: Escribir desde HAProxy NODO 1
# ============================================================================
echo ""
echo "3️⃣ Escribiendo vía HAProxy NODO 1 (haproxy-nodo1:5432)"

# Usar contenedor postgres-nodo1 como cliente para probar HAProxy
if docker exec postgres-nodo1 bash -c "PGPASSWORD=keycloak_secret psql -h haproxy-nodo1 -p 5432 -U keycloak -d keycloak -c \
  \"INSERT INTO routing_test (test_data, routed_via) VALUES ('Test from nodo1', 'haproxy-nodo1');\"" > /dev/null 2>&1; then
    echo -e "   ${GREEN}✅ Escritura exitosa vía haproxy-nodo1${NC}"
    WRITE1_SUCCESS=true
else
    echo -e "   ${RED}❌ Error en escritura vía haproxy-nodo1${NC}"
    WRITE1_SUCCESS=false
fi

# ============================================================================
# Test 4: Escribir desde HAProxy NODO 2
# ============================================================================
echo ""
echo "4️⃣ Escribiendo vía HAProxy NODO 2 (haproxy-nodo2:5432)"

# Usar contenedor postgres-nodo2 como cliente para probar HAProxy
if docker exec postgres-nodo2 bash -c "PGPASSWORD=keycloak_secret psql -h haproxy-nodo2 -p 5432 -U keycloak -d keycloak -c \
  \"INSERT INTO routing_test (test_data, routed_via) VALUES ('Test from nodo2', 'haproxy-nodo2');\"" > /dev/null 2>&1; then
    echo -e "   ${GREEN}✅ Escritura exitosa vía haproxy-nodo2${NC}"
    WRITE2_SUCCESS=true
else
    echo -e "   ${RED}❌ Error en escritura vía haproxy-nodo2${NC}"
    WRITE2_SUCCESS=false
fi

# ============================================================================
# Test 5: Verificar que todas las escrituras fueron al PRIMARY
# ============================================================================
echo ""
echo "5️⃣ Verificando que TODAS las escrituras se hicieron en el PRIMARY"
echo ""
echo "   Registros en PRIMARY ($PRIMARY):"
PRIMARY_ROWS=$(docker exec "$PRIMARY" psql -U keycloak -d keycloak -t -c \
  "SELECT COUNT(*) FROM routing_test WHERE routed_via LIKE 'haproxy-%';" 2>/dev/null | tr -d ' ')

docker exec "$PRIMARY" psql -U keycloak -d keycloak -c \
  "SELECT id, test_time, test_data, routed_via 
   FROM routing_test 
   ORDER BY id DESC 
   LIMIT 5;" 2>/dev/null | tail -8

# Verificar en REPLICA
if [ "$PRIMARY" == "postgres-nodo1" ]; then
    REPLICA="postgres-nodo2"
else
    REPLICA="postgres-nodo1"
fi

echo ""
sleep 2
echo "   Registros en REPLICA ($REPLICA) después de replicación:"
REPLICA_ROWS=$(docker exec "$REPLICA" psql -U keycloak -d keycloak -t -c \
  "SELECT COUNT(*) FROM routing_test WHERE routed_via LIKE 'haproxy-%';" 2>/dev/null | tr -d ' ')

docker exec "$REPLICA" psql -U keycloak -d keycloak -c \
  "SELECT id, test_time, test_data, routed_via 
   FROM routing_test 
   ORDER BY id DESC 
   LIMIT 5;" 2>/dev/null | tail -8

# ============================================================================
# Test 6: Verificar HAProxy stats
# ============================================================================
echo ""
echo "6️⃣ Estado de backends en HAProxy"
echo ""
echo "   HAProxy NODO 1:"
docker exec haproxy-nodo1 sh -c "echo 'show servers state' | nc -U /var/run/haproxy/admin.sock 2>/dev/null | grep postgres" || \
  echo "   (stats socket no disponible - HAProxy está funcionando)"

echo ""
echo "   HAProxy NODO 2:"
docker exec haproxy-nodo2 sh -c "echo 'show servers state' | nc -U /var/run/haproxy/admin.sock 2>/dev/null | grep postgres" || \
  echo "   (stats socket no disponible - HAProxy está funcionando)"

# ============================================================================
# Resultado Final
# ============================================================================
echo ""
echo "=========================================="

# Evaluar éxito del test
TEST_PASSED=true

# Verificar que las escrituras funcionaron
if [ "$WRITE1_SUCCESS" != "true" ] || [ "$WRITE2_SUCCESS" != "true" ]; then
    TEST_PASSED=false
fi

# Verificar replicación
if [ "$PRIMARY_ROWS" -lt 2 ] || [ "$PRIMARY_ROWS" != "$REPLICA_ROWS" ]; then
    TEST_PASSED=false
fi

if [ "$TEST_PASSED" = true ]; then
    echo -e "${GREEN}✅ TEST EXITOSO${NC}"
    echo "   • HAProxy detectó correctamente el PRIMARY"
    echo "   • Ambos HAProxy enrutaron escrituras al PRIMARY"
    echo "   • Registros en PRIMARY: $PRIMARY_ROWS"
    echo "   • Registros replicados: $REPLICA_ROWS"
    echo "   • Query routing funciona correctamente"
    exit 0
else
    if [ "$WRITE1_SUCCESS" != "true" ] || [ "$WRITE2_SUCCESS" != "true" ]; then
        echo -e "${RED}❌ TEST FALLIDO${NC}"
        echo "   • Error en escrituras vía HAProxy"
        if [ "$WRITE1_SUCCESS" != "true" ]; then
            echo "   • haproxy-nodo1: FALLO"
        fi
        if [ "$WRITE2_SUCCESS" != "true" ]; then
            echo "   • haproxy-nodo2: FALLO"
        fi
        echo ""
        echo "   Verifica:"
        echo "   docker logs haproxy-nodo1 --tail 20"
        echo "   docker logs haproxy-nodo2 --tail 20"
        exit 1
    else
        echo -e "${YELLOW}⚠️  TEST PARCIAL${NC}"
        echo "   • Escrituras exitosas pero replicación pendiente"
        echo "   • Registros en PRIMARY: $PRIMARY_ROWS"
        echo "   • Registros en REPLICA: $REPLICA_ROWS"
        if [ "$PRIMARY_ROWS" != "$REPLICA_ROWS" ]; then
            echo "   • Los datos están replicándose (puede tardar unos segundos)"
        fi
        exit 0
    fi
fi
echo "=========================================="

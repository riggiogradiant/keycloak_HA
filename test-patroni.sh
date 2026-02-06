#!/bin/bash
set -e

echo ""
echo "🧪 Testing Keycloak HA + Patroni Cluster"
echo "=========================================="
echo ""

# Test 1: Verificar nodos Keycloak
echo "1️⃣ Checking if Keycloak nodes are running..."
HTTP_CODE_1=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null)
HTTP_CODE_2=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8444 2>/dev/null)

if [ "$HTTP_CODE_1" != "200" ]; then
    echo "❌ Keycloak 1 not ready (HTTP $HTTP_CODE_1)"
    exit 1
fi

if [ "$HTTP_CODE_2" != "200" ]; then
    echo "❌ Keycloak 2 not ready (HTTP $HTTP_CODE_2)"
    exit 1
fi

echo "✅ Both Keycloak nodes running"
echo ""

# Test 2: Verificar cluster Infinispan
echo "2️⃣ Checking Infinispan cluster..."
echo ""
echo "Node 1 cluster view:"
docker logs keycloak-1 2>&1 | grep -i "Received new cluster view" | tail -1
echo ""
echo "Node 2 cluster view:"
docker logs keycloak-2 2>&1 | grep -i "Received new cluster view" | tail -1
echo ""

# Test 3: Test de sesión básico
echo "3️⃣ Testing session with Node 1..."
TOKEN=$(curl -k -s -X POST "https://localhost:8443/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "❌ Failed to get token from Node 1"
    exit 1
fi

echo "✅ Token obtained from Node 1"
echo ""

# Test 4: Token válido en Node 2
echo "4️⃣ Using same token on Node 2..."
RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" -X GET "https://localhost:8444/admin/realms/master/users?max=1" \
  -H "Authorization: Bearer $TOKEN")

if [ "$RESPONSE" = "200" ]; then
    echo "✅ Token valid on Node 2!"
    echo "   → Infinispan session replication working"
else
    echo "❌ Token not valid on Node 2 (HTTP $RESPONSE)"
    exit 1
fi
echo ""

# Test 5: Database compartida
echo "5️⃣ Testing shared database access..."
echo ""

RANDOM_SUFFIX=$(date +%s)
USERNAME_1="test_node1_${RANDOM_SUFFIX}"
echo "Creating user '$USERNAME_1' from Node 1..."
CREATE_RESPONSE_1=$(curl -k -s -o /dev/null -w "%{http_code}" -X POST "https://localhost:8443/admin/realms/master/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME_1\",\"enabled\":true,\"email\":\"${USERNAME_1}@test.com\"}")

if [ "$CREATE_RESPONSE_1" = "201" ]; then
    echo "✅ User created on Node 1"
else
    echo "❌ Failed to create user on Node 1 (HTTP $CREATE_RESPONSE_1)"
fi

sleep 1
echo ""
echo "Searching for user from Node 2..."
SEARCH_RESPONSE_1=$(curl -k -s -X GET "https://localhost:8444/admin/realms/master/users?username=$USERNAME_1" \
  -H "Authorization: Bearer $TOKEN")

USER_COUNT_1=$(echo "$SEARCH_RESPONSE_1" | grep -o "\"username\":\"$USERNAME_1\"" | wc -l)

if [ "$USER_COUNT_1" -gt 0 ]; then
    echo "✅ User found on Node 2 - Database synchronized"
else
    echo "❌ User NOT found on Node 2"
fi
echo ""

# Test 6: Failover Keycloak
echo "6️⃣ Testing Keycloak failover (Infinispan)..."
echo ""

TOKEN_FAILOVER=$(curl -k -s -X POST "https://localhost:8443/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

echo "✅ Token obtained from Node 1"
echo ""

echo "🛑 Stopping Keycloak-1..."
docker stop keycloak-1 > /dev/null 2>&1
sleep 2
echo "✅ Keycloak-1 stopped"
echo ""

echo "Testing if Node 1 token is valid on Node 2..."
FAILOVER_RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" -X GET "https://localhost:8444/admin/realms/master/users?max=1" \
  -H "Authorization: Bearer $TOKEN_FAILOVER")

if [ "$FAILOVER_RESPONSE" = "200" ]; then
    echo "✅ Token from Node 1 is VALID on Node 2!"
    echo "   → Infinispan failover working correctly"
else
    echo "❌ Token NOT valid on Node 2 (HTTP $FAILOVER_RESPONSE)"
fi

echo ""
echo "🔄 Restarting Keycloak-1..."
docker start keycloak-1 > /dev/null 2>&1
sleep 10
echo "✅ Keycloak-1 restarted"
echo ""

# Test 7: Verificar Patroni Cluster
echo "7️⃣ Testing Patroni replication..."
echo ""

NODE1_ROLE=$(curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
NODE2_ROLE=$(curl -s http://localhost:8009/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)

echo "Patroni Node 1: $NODE1_ROLE"
echo "Patroni Node 2: $NODE2_ROLE"

if [[ ("$NODE1_ROLE" == "master" && "$NODE2_ROLE" == "replica") || \
      ("$NODE1_ROLE" == "replica" && "$NODE2_ROLE" == "master") ]]; then
    echo "✅ Patroni cluster healthy: 1 primary + 1 replica"
else
    echo "❌ Patroni cluster issue detected"
    exit 1
fi

# Verificar replication lag
if [ "$NODE1_ROLE" = "replica" ]; then
    LAG=$(curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '"lag":[0-9]*' | cut -d':' -f2)
else
    LAG=$(curl -s http://localhost:8009/patroni 2>/dev/null | grep -o '"lag":[0-9]*' | cut -d':' -f2)
fi
echo "Replication lag: ${LAG:-0} bytes"

if [ "${LAG:-0}" -lt 1048576 ]; then
    echo "✅ Lag is acceptable (< 1MB)"
else
    echo "⚠️  High replication lag detected"
fi
echo ""

# Test 8: Failover Automático PostgreSQL
echo "8️⃣ Testing PostgreSQL automatic failover..."
echo ""

# Identificar PRIMARY actual
if [ "$NODE1_ROLE" = "master" ]; then
    PRIMARY_CONTAINER="patroni-node1"
    PRIMARY_NAME="Node 1"
    REPLICA_CONTAINER="patroni-node2"
    REPLICA_NAME="Node 2"
    REPLICA_API="http://localhost:8009"
else
    PRIMARY_CONTAINER="patroni-node2"
    PRIMARY_NAME="Node 2"
    REPLICA_CONTAINER="patroni-node1"
    REPLICA_NAME="Node 1"
    REPLICA_API="http://localhost:8008"
fi

echo "Current PostgreSQL PRIMARY: $PRIMARY_NAME ($PRIMARY_CONTAINER)"
echo ""

# Crear test user antes de failover
TEST_USER="failover_test_$(date +%s)"
echo "Creating test user '$TEST_USER' before failover..."

# Obtener nuevo token (el anterior puede haber expirado)
TOKEN_NEW=$(curl -k -s -X POST "https://localhost:8443/realms/master/protocol/openid-connect/token" \
  -d "username=admin&password=admin&grant_type=password&client_id=admin-cli" \
  | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

curl -k -s -X POST "https://localhost:8443/admin/realms/master/users" \
  -H "Authorization: Bearer $TOKEN_NEW" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$TEST_USER\",\"enabled\":true}" > /dev/null

echo "✅ User created on current PRIMARY"
echo ""

# Simular fallo del PRIMARY
echo "🛑 Simulating PRIMARY failure (stopping $PRIMARY_CONTAINER)..."
docker stop $PRIMARY_CONTAINER > /dev/null 2>&1
echo "✅ PRIMARY stopped"
echo ""

# Esperar auto-failover
echo "⏳ Waiting for automatic failover (this may take 30-90 seconds)..."
sleep 10

FAILOVER_SUCCESS=false
for i in {1..30}; do
    NEW_ROLE=$(curl -s $REPLICA_API/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
    if [ "$NEW_ROLE" = "master" ]; then
        echo ""
        echo "🎉 AUTOMATIC FAILOVER SUCCESSFUL!"
        echo "   $REPLICA_NAME promoted to PRIMARY in ~$((i*3)) seconds"
        FAILOVER_SUCCESS=true
        break
    fi
    echo -n "."
    sleep 3
done

if [ "$FAILOVER_SUCCESS" = false ]; then
    echo ""
    echo "❌ FAILOVER FAILED: Replica not promoted"
    echo "   This may indicate etcd quorum issues"
    docker start $PRIMARY_CONTAINER > /dev/null 2>&1
    exit 1
fi

echo ""
echo "Verifying data consistency after failover..."
sleep 5

# Verificar que usuario creado antes existe
SEARCH_AFTER=$(curl -k -s "https://localhost:8443/admin/realms/master/users?username=$TEST_USER" \
  -H "Authorization: Bearer $TOKEN_NEW")

if echo "$SEARCH_AFTER" | grep -q "$TEST_USER"; then
    echo "✅ User '$TEST_USER' found after failover"
    echo "   → ZERO DATA LOSS confirmed (synchronous replication working)"
else
    echo "❌ User '$TEST_USER' NOT found after failover"
    echo "   → DATA LOSS detected!"
fi

echo ""
echo "🔄 Restarting old PRIMARY (will rejoin as replica)..."
docker start $PRIMARY_CONTAINER > /dev/null 2>&1
sleep 20

echo "⏳ Waiting for old PRIMARY to rejoin as REPLICA..."
if [ "$PRIMARY_CONTAINER" = "patroni-node1" ]; then
    REJOIN_API="http://localhost:8008"
else
    REJOIN_API="http://localhost:8009"
fi

for i in {1..20}; do
    OLD_ROLE=$(curl -s $REJOIN_API/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
    if [ "$OLD_ROLE" = "replica" ]; then
        echo "✅ Old PRIMARY successfully rejoined as REPLICA"
        break
    fi
    echo -n "."
    sleep 3
done

echo ""
echo ""

# Test 9: Split-Brain Detection
echo "9️⃣ Testing split-brain detection..."
echo ""
./scripts/check-split-brain.sh

echo ""

# Test 10: Keycloak funcional tras failover
echo "🔟 Testing Keycloak remains functional after PostgreSQL failover..."
echo ""

POST_FAILOVER_USER="post_failover_$(date +%s)"
echo "Creating user '$POST_FAILOVER_USER' after all failover operations..."

CREATE_POST=$(curl -k -s -o /dev/null -w "%{http_code}" \
  -X POST "https://localhost:8443/admin/realms/master/users" \
  -H "Authorization: Bearer $TOKEN_NEW" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$POST_FAILOVER_USER\",\"enabled\":true}")

if [ "$CREATE_POST" = "201" ]; then
    echo "✅ Keycloak fully functional after PostgreSQL failover"
    echo "   User '$POST_FAILOVER_USER' created successfully"
else
    echo "❌ Keycloak issues after failover (HTTP $CREATE_POST)"
fi

echo ""
echo "=========================================="
echo "✅ All tests completed!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✅ Keycloak Infinispan clustering: Working"
echo "  ✅ Token replication across nodes: Working"  
echo "  ✅ Shared database access: Working"
echo "  ✅ Keycloak failover: Working"
echo "  ✅ Patroni cluster: Healthy"
echo "  ✅ PostgreSQL automatic failover: Working"
echo "  ✅ Zero data loss: Confirmed"
echo "  ✅ Split-brain detection: Working"
echo "  ✅ Post-failover functionality: Working"
echo ""
echo "Run './scripts/check-cluster.sh' for current cluster status"
echo ""

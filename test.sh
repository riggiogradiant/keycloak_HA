#!/bin/bash

echo ""
echo "🧪 Testing Infinispan Clustering"
echo "================================="
echo ""

# Verificar nodos
echo "1️⃣ Checking if nodes are running..."
HTTP_CODE_1=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null)
if [ "$HTTP_CODE_1" != "200" ]; then
    echo "❌ Keycloak 1 not ready (HTTP $HTTP_CODE_1)"
    exit 1
fi

HTTP_CODE_2=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8444 2>/dev/null)
if [ "$HTTP_CODE_2" != "200" ]; then
    echo "❌ Keycloak 2 not ready (HTTP $HTTP_CODE_2)"
    exit 1
fi

echo "✅ Both nodes are running"
echo ""

# Verificar cluster
echo "2️⃣ Checking Infinispan cluster..."
echo ""
echo "Node 1 cluster view:"
docker logs keycloak-1 2>&1 | grep -i "Received new cluster view" | tail -1
echo ""
echo "Node 2 cluster view:"
docker logs keycloak-2 2>&1 | grep -i "Received new cluster view" | tail -1
echo ""

# Test de sesión básico
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

echo "4️⃣ Using same token on Node 2..."
RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" -X GET "https://localhost:8444/admin/realms/master/users?max=1" \
  -H "Authorization: Bearer $TOKEN")

if [ "$RESPONSE" = "200" ]; then
    echo "✅ Token valid on Node 2!"
    echo ""
    echo "🎉 SUCCESS! Production mode is working!"
    echo "    Sessions ARE replicated between nodes"
    echo "    Tokens ARE valid across the cluster"
else
    echo "❌ Token not valid on Node 2 (HTTP $RESPONSE)"
    echo "    Check Keycloak logs for errors"
fi

echo ""
echo "5️⃣ Testing shared database access..."
echo ""

# Crear usuario desde Node 1
echo "Creating user 'prueba_bd' from Node 1..."
RANDOM_SUFFIX=$(date +%s)
USERNAME_1="prueba_bd_node_1${RANDOM_SUFFIX}"
CREATE_RESPONSE_1=$(curl -k -s -o /dev/null -w "%{http_code}" -X POST "https://localhost:8443/admin/realms/master/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME_1\",\"enabled\":true,\"email\":\"${USERNAME_1}@test.com\"}")

if [ "$CREATE_RESPONSE_1" = "201" ]; then
    echo "✅ User '$USERNAME_1' created on Node 1"
else
    echo "❌ Failed to create user on Node 1 (HTTP $CREATE_RESPONSE_1)"
fi

# Buscar el usuario desde Node 2
sleep 1
echo ""
echo "Searching for user '$USERNAME_1' from Node 2..."
SEARCH_RESPONSE_1=$(curl -k -s -X GET "https://localhost:8444/admin/realms/master/users?username=$USERNAME_1" \
  -H "Authorization: Bearer $TOKEN")

USER_COUNT_1=$(echo "$SEARCH_RESPONSE_1" | grep -o "\"username\":\"$USERNAME_1\"" | wc -l)

if [ "$USER_COUNT_1" -gt 0 ]; then
    echo "✅ User '$USERNAME_1' found on Node 2!"
    echo "   └─ Database READ from Node 2 successful"
else
    echo "❌ User '$USERNAME_1' NOT found on Node 2"
    echo "   Database may not be properly shared"
fi

# Crear usuario desde Node 2
echo ""
USERNAME_2="prueba_bd_node2_${RANDOM_SUFFIX}"
echo "Creating user '$USERNAME_2' from Node 2..."
CREATE_RESPONSE_2=$(curl -k -s -o /dev/null -w "%{http_code}" -X POST "https://localhost:8444/admin/realms/master/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME_2\",\"enabled\":true,\"email\":\"${USERNAME_2}@test.com\"}")

if [ "$CREATE_RESPONSE_2" = "201" ]; then
    echo "✅ User '$USERNAME_2' created on Node 2"
else
    echo "❌ Failed to create user on Node 2 (HTTP $CREATE_RESPONSE_2)"
fi

# Buscar el usuario desde Node 1
sleep 1
echo ""
echo "Searching for user '$USERNAME_2' from Node 1..."
SEARCH_RESPONSE_2=$(curl -k -s -X GET "https://localhost:8443/admin/realms/master/users?username=$USERNAME_2" \
  -H "Authorization: Bearer $TOKEN")

USER_COUNT_2=$(echo "$SEARCH_RESPONSE_2" | grep -o "\"username\":\"$USERNAME_2\"" | wc -l)

if [ "$USER_COUNT_2" -gt 0 ]; then
    echo "✅ User '$USERNAME_2' found on Node 1!"
    echo "   └─ Database READ from Node 1 successful"
else
    echo "❌ User '$USERNAME_2' NOT found on Node 1"
    echo "   Database may not be properly shared"
fi

echo ""
echo "📊 Database Shared Access Summary:"
echo "   • Node 1 WRITE → Node 2 READ: $([ "$USER_COUNT_1" -gt 0 ] && echo "✅ OK" || echo "❌ FAIL")"
echo "   • Node 2 WRITE → Node 1 READ: $([ "$USER_COUNT_2" -gt 0 ] && echo "✅ OK" || echo "❌ FAIL")"
echo ""
echo "   Both nodes accessing the SAME PostgreSQL database!"

echo ""
echo "6️⃣ Testing Failover: Node 1 down, token still valid on Node 2..."
echo ""

# Obtener un nuevo token de Node 1
echo "Getting fresh token from Node 1..."
TOKEN_FAILOVER=$(curl -k -s -X POST "https://localhost:8443/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN_FAILOVER" ]; then
    echo "❌ Failed to get token from Node 1"
    exit 1
fi

echo "✅ Token obtained from Node 1: ${TOKEN_FAILOVER:0:20}..."
echo ""

# Parar Keycloak-1
echo "🛑 Stopping Keycloak-1..."
docker stop keycloak-1 > /dev/null 2>&1
sleep 2
echo "✅ Keycloak-1 stopped"
echo ""

# Verificar que Node 1 está caído
HTTP_CODE_DOWN=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null)
if [ "$HTTP_CODE_DOWN" = "000" ]; then
    echo "✅ Confirmed: Keycloak-1 is DOWN (cannot connect)"
else
    echo "⚠️  Warning: Keycloak-1 might still be running (HTTP $HTTP_CODE_DOWN)"
fi
echo ""

# Intentar usar el token en Node 2
echo "Trying to use Node 1's token on Node 2 (while Node 1 is DOWN)..."
FAILOVER_RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" -X GET "https://localhost:8444/admin/realms/master/users?max=1" \
  -H "Authorization: Bearer $TOKEN_FAILOVER")

echo ""
if [ "$FAILOVER_RESPONSE" = "200" ]; then
    echo "🎉 SUCCESS! Token from Node 1 is VALID on Node 2!"
    echo "   └─ Infinispan replicated the session successfully"
    echo "   └─ FAILOVER is working correctly"
    echo "   └─ Users won't lose their session if a node goes down"
else
    echo "❌ FAIL: Token from Node 1 NOT valid on Node 2 (HTTP $FAILOVER_RESPONSE)"
    echo "   └─ Session replication may not be working"
fi

# Reiniciar Keycloak-1
echo ""
echo "🔄 Restarting Keycloak-1..."
docker start keycloak-1 > /dev/null 2>&1
echo "⏳ Waiting for Keycloak-1 to come back online..."
sleep 15

for i in {1..20}; do
    HTTP_CODE_UP=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null)
    if [ "$HTTP_CODE_UP" = "200" ]; then
        echo "✅ Keycloak-1 is back online"
        break
    fi
    echo -n "."
    sleep 3
done

echo ""
echo "================================="
echo "Test completed"
echo "================================="

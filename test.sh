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
echo "================================="
echo "Test completed"
echo "================================="

#!/bin/bash

# Script to check the status of the Keycloak HA cluster

echo "🔍 Keycloak HA Cluster Status"
echo "=============================="
echo ""

# Check if containers are running
echo "📦 Container Status:"
echo "-------------------"
docker ps --filter "name=keycloak" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker ps --filter "name=postgres" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "🌐 Network Status:"
echo "------------------"
docker network inspect keycloak-ha-net --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}' 2>/dev/null || echo "Network not found"

echo ""
echo "💚 Health Status:"
echo "-----------------"

# Check Node 1
if curl -sf http://localhost:8080/health/ready > /dev/null 2>&1; then
    echo "✅ Node 1 (8080): Healthy"
else
    echo "❌ Node 1 (8080): Not responding"
fi

# Check Node 2
if curl -sf http://localhost:8081/health/ready > /dev/null 2>&1; then
    echo "✅ Node 2 (8081): Healthy"
else
    echo "❌ Node 2 (8081): Not responding"
fi

# Check PostgreSQL
if docker exec keycloak-postgres pg_isready -U keycloak > /dev/null 2>&1; then
    echo "✅ PostgreSQL: Ready"
else
    echo "❌ PostgreSQL: Not ready"
fi

echo ""
echo "🔗 Cluster Members:"
echo "-------------------"
echo "Node 1 cluster view:"
docker logs keycloak-node-1 2>&1 | grep -i "members" | tail -1 || echo "No cluster info found"

echo ""
echo "Node 2 cluster view:"
docker logs keycloak-node-2 2>&1 | grep -i "members" | tail -1 || echo "No cluster info found"

echo ""
echo "For detailed logs, run:"
echo "  docker compose -f docker-compose-node1.yml logs -f keycloak-1"
echo "  docker compose -f docker-compose-node2.yml logs -f keycloak-2"

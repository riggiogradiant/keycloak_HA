#!/bin/bash
set -e

echo "🚀 Deploying Keycloak HA with Patroni (2-Node Local Simulation)"
echo "================================================================="
echo ""

# Generar certificados si no existen
if [ ! -f "certs/keycloak.p12" ]; then
    echo "📜 Generating SSL certificates..."
    bash generate-certs.sh
    echo ""
fi

# Build imagen Keycloak
echo "🔨 Building Keycloak image..."
docker compose -f docker-compose-patroni.yml build
echo "✅ Build completed"
echo ""

# Iniciar servicios
echo "🚀 Starting services..."
docker compose -f docker-compose-patroni.yml up -d

echo ""
echo "⏳ Waiting for etcd cluster to be ready..."
sleep 10

for i in {1..20}; do
    if docker exec etcd-node1 etcdctl endpoint health > /dev/null 2>&1 && \
       docker exec etcd-node2 etcdctl endpoint health > /dev/null 2>&1; then
        echo "✅ etcd cluster ready (2 nodes)"
        break
    fi
    echo -n "."
    sleep 2
done

echo ""
echo "⏳ Waiting for Patroni cluster to initialize (30-60 seconds)..."
sleep 15

for i in {1..40}; do
    NODE1_ROLE=$(curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    NODE2_ROLE=$(curl -s http://localhost:8009/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    
    if [[ "$NODE1_ROLE" != "unknown" && "$NODE2_ROLE" != "unknown" ]]; then
        echo ""
        echo "✅ Patroni cluster initialized"
        echo "   Node 1: $NODE1_ROLE"
        echo "   Node 2: $NODE2_ROLE"
        break
    fi
    echo -n "."
    sleep 3
done

echo ""
echo "⏳ Waiting for PostgreSQL to accept connections..."
sleep 5

for i in {1..30}; do
    if docker exec patroni-node1 pg_isready -U postgres -h localhost > /dev/null 2>&1; then
        echo "✅ PostgreSQL PRIMARY ready"
        break
    fi
    echo -n "."
    sleep 2
done

echo ""
echo "⏳ Creating Keycloak database and user..."
sleep 2

# Crear usuario y base de datos de Keycloak en el PRIMARY
docker exec patroni-node1 psql -U postgres -c "CREATE USER keycloak WITH PASSWORD 'keycloak';" 2>/dev/null || echo "User may already exist"
docker exec patroni-node1 psql -U postgres -c "CREATE DATABASE keycloak OWNER keycloak;" 2>/dev/null || echo "Database may already exist"
echo "✅ Keycloak database configured"

echo ""
echo "⏳ Waiting for Keycloak nodes (1-2 minutes)..."

# Esperar Keycloak 1
for i in {1..50}; do
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Keycloak 1 ready"
        break
    fi
    echo -n "."
    sleep 3
done

# Esperar Keycloak 2
for i in {1..50}; do
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8444 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Keycloak 2 ready"
        break
    fi
    echo -n "."
    sleep 3
done

echo ""
echo "================================================================="
echo "🔍 Final Cluster Verification"
echo "================================================================="
echo ""

# Verificar cluster Patroni
echo "📊 Patroni Cluster Status:"
NODE1_ROLE=$(curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
NODE2_ROLE=$(curl -s http://localhost:8009/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4 || echo "unknown")

echo "  • Node 1: $NODE1_ROLE"
echo "  • Node 2: $NODE2_ROLE"

if [[ ("$NODE1_ROLE" == "master" && "$NODE2_ROLE" == "replica") || \
      ("$NODE2_ROLE" == "master" && "$NODE1_ROLE" == "replica") ]]; then
    echo "  ✅ Cluster healthy: 1 PRIMARY + 1 REPLICA"
else
    echo "  ⚠️  Warning: Unexpected cluster state"
fi

# Verificar lag de replicación
if [ "$NODE1_ROLE" = "replica" ]; then
    LAG=$(curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '"lag":[0-9]*' | cut -d':' -f2 || echo "0")
else
    LAG=$(curl -s http://localhost:8009/patroni 2>/dev/null | grep -o '"lag":[0-9]*' | cut -d':' -f2 || echo "0")
fi
echo "  • Replication lag: ${LAG:-0} bytes"

echo ""
echo "📊 Keycloak Cluster Status:"
KC1_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null)
KC2_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8444 2>/dev/null)

if [ "$KC1_STATUS" = "200" ]; then
    echo "  ✅ Keycloak 1: Running (HTTP $KC1_STATUS)"
else
    echo "  ⚠️  Keycloak 1: Not responding (HTTP $KC1_STATUS)"
fi

if [ "$KC2_STATUS" = "200" ]; then
    echo "  ✅ Keycloak 2: Running (HTTP $KC2_STATUS)"
else
    echo "  ⚠️  Keycloak 2: Not responding yet (HTTP $KC2_STATUS)"
    echo "     (May still be starting - wait 1-2 more minutes)"
fi

echo ""
echo "📊 Database Connectivity:"
DB_CHECK=$(docker exec patroni-node1 psql -U keycloak -d keycloak -c "SELECT 1;" 2>/dev/null | grep -c "1 row" || echo "0")
if [ "$DB_CHECK" -gt 0 ]; then
    echo "  ✅ Keycloak database accessible"
else
    echo "  ⚠️  Database connection issue"
fi

echo ""
echo "================================================================="
echo "✅ Deployment Complete!"
echo "================================================================="
echo ""
echo "📍 Services Running:"
echo ""
echo "Keycloak:"
echo "  • Node 1: https://localhost:8443"
echo "  • Node 2: https://localhost:8444"
echo ""
echo "Patroni REST API:"
echo "  • Node 1: http://localhost:8008/patroni"
echo "  • Node 2: http://localhost:8009/patroni"
echo ""
echo "PostgreSQL:"
echo "  • Node 1: localhost:5432"
echo "  • Node 2: localhost:5433"
echo ""
echo "etcd:"
echo "  • Node 1: localhost:2379"
echo "  • Node 2: localhost:23791"
echo ""
echo "🔐 Credentials:"
echo "  • Keycloak: admin / admin"
echo "  • PostgreSQL: keycloak / keycloak"
echo ""
echo "📊 Management Commands:"
echo "  • Check cluster status:  ./scripts/check-cluster.sh"
echo "  • Run tests:             ./test-patroni.sh"
echo "  • Manual failover:       ./scripts/manual-failover.sh"
echo "  • Check split-brain:     ./scripts/check-split-brain.sh"
echo ""
echo "🛑 Stop & Clean:"
echo "  • Stop cluster:          ./stop-patroni.sh"
echo "  • Stop + remove volumes: docker compose -f docker-compose-patroni.yml down -v"
echo ""
echo "📝 Logs:"
echo "  • All services:          docker compose -f docker-compose-patroni.yml logs -f"
echo "  • Specific service:      docker compose -f docker-compose-patroni.yml logs -f <service>"
echo ""

if [ "$KC1_STATUS" = "200" ] && [ "$KC2_STATUS" = "200" ]; then
    echo "🎉 All services are operational!"
elif [ "$KC2_STATUS" != "200" ]; then
    echo "⚠️  Note: Keycloak 2 may still be starting (1-2 more minutes)"
    echo "   Check with: curl -k https://localhost:8444"
fi
echo ""

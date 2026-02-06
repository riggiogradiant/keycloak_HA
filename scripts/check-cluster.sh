#!/bin/bash

echo ""
echo "🔍 Keycloak HA + Patroni Cluster Status"
echo "========================================"
echo ""

# Verificar etcd
echo "📊 etcd Cluster"
echo "----------------"
ETCD1=$(docker exec etcd-node1 etcdctl endpoint health 2>/dev/null | grep -c "healthy" || echo "0")
ETCD2=$(docker exec etcd-node2 etcdctl endpoint health 2>/dev/null | grep -c "healthy" || echo "0")

# Limpiar espacios y saltos de línea
ETCD1=$(echo "$ETCD1" | tr -d '\n\r' | xargs)
ETCD2=$(echo "$ETCD2" | tr -d '\n\r' | xargs)

if [ "$ETCD1" != "0" ] && [ -n "$ETCD1" ]; then
    echo "✅ etcd-node1: healthy"
else
    echo "❌ etcd-node1: unhealthy"
fi

if [ "$ETCD2" != "0" ] && [ -n "$ETCD2" ]; then
    echo "✅ etcd-node2: healthy"
else
    echo "❌ etcd-node2: unhealthy"
fi

echo ""
echo "📊 Patroni Cluster"
echo "-------------------"

# Node 1
NODE1_STATUS=$(curl -s http://localhost:8008/patroni 2>/dev/null)
if [ $? -eq 0 ]; then
    NODE1_ROLE=$(echo "$NODE1_STATUS" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
    NODE1_STATE=$(echo "$NODE1_STATUS" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
    NODE1_TIMELINE=$(echo "$NODE1_STATUS" | grep -o '"timeline":[0-9]*' | cut -d':' -f2)
    
    echo "Node 1 (patroni-node1):"
    echo "  Role:     $NODE1_ROLE"
    echo "  State:    $NODE1_STATE"
    echo "  Timeline: $NODE1_TIMELINE"
    
    if [ "$NODE1_ROLE" = "master" ]; then
        echo "  ✅ PRIMARY"
    else
        NODE1_LAG=$(echo "$NODE1_STATUS" | grep -o '"lag":[0-9]*' | cut -d':' -f2)
        echo "  Lag:      ${NODE1_LAG:-0} bytes"
        echo "  ✅ REPLICA"
    fi
else
    echo "Node 1 (patroni-node1):"
    echo "  ❌ Cannot connect"
fi

echo ""

# Node 2
NODE2_STATUS=$(curl -s http://localhost:8009/patroni 2>/dev/null)
if [ $? -eq 0 ]; then
    NODE2_ROLE=$(echo "$NODE2_STATUS" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
    NODE2_STATE=$(echo "$NODE2_STATUS" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
    NODE2_TIMELINE=$(echo "$NODE2_STATUS" | grep -o '"timeline":[0-9]*' | cut -d':' -f2)
    
    echo "Node 2 (patroni-node2):"
    echo "  Role:     $NODE2_ROLE"
    echo "  State:    $NODE2_STATE"
    echo "  Timeline: $NODE2_TIMELINE"
    
    if [ "$NODE2_ROLE" = "master" ]; then
        echo "  ✅ PRIMARY"
    else
        NODE2_LAG=$(echo "$NODE2_STATUS" | grep -o '"lag":[0-9]*' | cut -d':' -f2)
        echo "  Lag:      ${NODE2_LAG:-0} bytes"
        echo "  ✅ REPLICA"
    fi
else
    echo "Node 2 (patroni-node2):"
    echo "  ❌ Cannot connect"
fi

echo ""
echo "📊 Keycloak Infinispan Cluster"
echo "--------------------------------"

KC1_VIEW=$(docker logs keycloak-1 2>&1 | grep -i "Received new cluster view" | tail -1)
KC2_VIEW=$(docker logs keycloak-2 2>&1 | grep -i "Received new cluster view" | tail -1)

if [ -n "$KC1_VIEW" ]; then
    echo "Node 1: $KC1_VIEW"
else
    echo "Node 1: ⚠️  No cluster view found"
fi

if [ -n "$KC2_VIEW" ]; then
    echo "Node 2: $KC2_VIEW"
else
    echo "Node 2: ⚠️  No cluster view found"
fi

echo ""
echo "========================================"
echo "Use 'docker compose -f docker-compose-patroni.yml logs <service>' for details"
echo ""

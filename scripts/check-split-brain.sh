#!/bin/bash

echo "🔍 Checking for split-brain scenario..."
echo ""

NODE1_ROLE=$(curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
NODE2_ROLE=$(curl -s http://localhost:8009/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)

echo "Node 1 role: $NODE1_ROLE"
echo "Node 2 role: $NODE2_ROLE"
echo ""

if [ "$NODE1_ROLE" = "master" ] && [ "$NODE2_ROLE" = "master" ]; then
    echo "🚨🚨🚨 SPLIT-BRAIN DETECTED! 🚨🚨🚨"
    echo ""
    echo "Both nodes are PRIMARY! This is a critical issue."
    echo ""
    echo "Manual intervention required:"
    echo "1. Check etcd cluster health: docker exec etcd-node1 etcdctl endpoint health"
    echo "2. Demote one node manually:"
    echo "   curl -X POST http://localhost:8009/reinitialize"
    echo ""
    exit 1
elif [ "$NODE1_ROLE" = "unknown" ] || [ "$NODE2_ROLE" = "unknown" ]; then
    echo "⚠️  WARNING: Cannot determine role of one or both nodes"
    exit 2
else
    echo "✅ Cluster healthy: 1 primary, 1 replica"
    exit 0
fi

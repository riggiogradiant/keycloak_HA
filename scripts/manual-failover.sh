#!/bin/bash

echo "🔄 Manual Patroni Failover/Switchover"
echo "======================================"
echo ""

# Obtener estado actual
NODE1_ROLE=$(curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
NODE2_ROLE=$(curl -s http://localhost:8009/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)

echo "Current status:"
echo "  Node 1: $NODE1_ROLE"
echo "  Node 2: $NODE2_ROLE"
echo ""

if [ "$NODE1_ROLE" = "master" ]; then
    echo "Performing switchover: Node 1 (PRIMARY) → Node 2 (will become PRIMARY)"
    echo ""
    read -p "Are you sure? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted"
        exit 0
    fi
    
    echo "Executing switchover..."
    curl -X POST http://localhost:8008/switchover \
      -H "Content-Type: application/json" \
      -d '{"leader":"patroni-node1","candidate":"patroni-node2"}'
elif [ "$NODE2_ROLE" = "master" ]; then
    echo "Performing switchover: Node 2 (PRIMARY) → Node 1 (will become PRIMARY)"
    echo ""
    read -p "Are you sure? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted"
        exit 0
    fi
    
    echo "Executing switchover..."
    curl -X POST http://localhost:8009/switchover \
      -H "Content-Type: application/json" \
      -d '{"leader":"patroni-node2","candidate":"patroni-node1"}'
else
    echo "❌ Cannot determine current PRIMARY"
    exit 1
fi

echo ""
echo "⏳ Waiting for switchover to complete..."
sleep 10

# Verificar nuevo estado
NEW_NODE1_ROLE=$(curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)
NEW_NODE2_ROLE=$(curl -s http://localhost:8009/patroni 2>/dev/null | grep -o '"role":"[^"]*"' | cut -d'"' -f4)

echo ""
echo "New status:"
echo "  Node 1: $NEW_NODE1_ROLE"
echo "  Node 2: $NEW_NODE2_ROLE"
echo ""

if [[ ("$NODE1_ROLE" = "master" && "$NEW_NODE2_ROLE" = "master") || \
      ("$NODE2_ROLE" = "master" && "$NEW_NODE1_ROLE" = "master") ]]; then
    echo "✅ Switchover successful!"
else
    echo "⚠️  Switchover may not be complete, check cluster status"
fi

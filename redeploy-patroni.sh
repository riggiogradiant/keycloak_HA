#!/bin/bash
set -e

echo "🔄 Redeploying Keycloak HA with Patroni"
echo "========================================"
echo ""
echo "⚠️  This will:"
echo "   • Stop all running containers"
echo "   • Remove all volumes (data will be lost)"
echo "   • Redeploy the entire cluster"
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted"
    exit 0
fi

echo ""
echo "🛑 Stopping and cleaning cluster..."
docker compose -f docker-compose-patroni.yml down -v

echo ""
echo "🧹 Cleaning up dangling volumes..."
docker volume prune -f > /dev/null 2>&1 || true

echo ""
echo "✅ Cleanup complete"
echo ""
echo "🚀 Starting fresh deployment..."
echo ""

./deploy-patroni.sh

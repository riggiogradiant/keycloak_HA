#!/bin/bash

# Script para hacer el build inicial de Keycloak en modo producción
# Esto es necesario antes del primer arranque con "start --optimized"

set -e

echo "🔨 Building Keycloak for Production Mode"
echo "=========================================="
echo ""

# Cargar variables de entorno
if [ -f .env.prod ]; then
    export $(cat .env.prod | grep -v '^#' | xargs)
fi

echo "📦 Building Keycloak Node 1..."
docker compose -f docker-compose-prod.yml run --rm \
    --entrypoint /opt/keycloak/bin/kc.sh \
    keycloak-1 \
    build \
    --cache=ispn \
    --cache-stack=tcp \
    --db=postgres \
    --features=preview \
    --health-enabled=true \
    --metrics-enabled=true

echo ""
echo "✅ Keycloak build completed!"
echo ""
echo "Ahora puedes iniciar el cluster con:"
echo "  docker compose -f docker-compose-prod.yml up -d"
echo ""

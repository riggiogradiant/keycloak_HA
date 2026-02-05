#!/bin/bash

echo "🚀 Deploying 2 Keycloaks + Infinispan (Production Mode)"
echo "=========================================================="
echo ""

# Generar certificados si no existen
if [ ! -f "certs/keycloak.p12" ]; then
    echo "📜 Generating SSL certificates..."
    bash generate-certs.sh
    echo ""
fi

# Build imagen personalizada de Keycloak
echo "🔨 Building Keycloak image with PostgreSQL..."
docker compose build
echo "✅ Build completed"
echo ""

# Iniciar servicios
docker compose up -d

echo ""
echo "⏳ Waiting for services to start..."
sleep 15

# Verificar PostgreSQL
for i in {1..20}; do
    if docker exec postgres pg_isready -U keycloak > /dev/null 2>&1; then
        echo "✅ PostgreSQL database ready"
        break
    fi
    echo -n "."
    sleep 2
done

echo ""
echo "⏳ Waiting for Keycloak nodes (1-2 minutes)..."

# Esperar Keycloak 1
for i in {1..40}; do
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Keycloak 1 ready"
        break
    fi
    echo -n "."
    sleep 3
done

# Esperar Keycloak 2
for i in {1..40}; do
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8444 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Keycloak 2 ready"
        break
    fi
    echo -n "."
    sleep 3
done

echo ""
echo "========================================"
echo "✅ Deployment complete!"
echo "========================================"
echo ""
echo "📍 Access:"
echo "   Keycloak 1: https://localhost:8443"
echo "   Keycloak 2: https://localhost:8444"
echo ""
echo "🔐 Credentials:"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "⚠️  SSL Warning:"
echo "   Self-signed certificates - Accept in browser"
echo ""
echo "🧪 Test: ./test.sh"
echo "🛑 Stop: ./stop.sh"
echo ""

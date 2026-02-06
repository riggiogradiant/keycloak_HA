#!/bin/bash

echo "🛑 Stopping Keycloak HA + Patroni cluster..."
docker compose -f docker-compose-patroni.yml down

echo "✅ Cluster stopped"
echo ""
echo "To remove volumes: docker compose -f docker-compose-patroni.yml down -v"

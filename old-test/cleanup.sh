#!/bin/bash

echo ""
echo "========================================================================="
echo "  Eliminando Keycloak HA"
echo "========================================================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🗑️  Deteniendo y eliminando contenedores..."
docker compose -f docker-compose.yaml down -v 2>/dev/null || true
echo "  ✅ Contenedores eliminados"
echo ""

echo "🗑️  Eliminando red Docker..."
docker network rm keycloak-ha-net 2>/dev/null || true
echo "  ✅ Red eliminada"
echo ""

echo "========================================================================="
echo "  ✅ Limpieza completada"
echo "========================================================================="
echo ""
echo "  Verificar con:"
echo "    docker ps                # Debe estar vacío"
echo "    docker volume ls         # Sin volúmenes postgres_*"
echo ""

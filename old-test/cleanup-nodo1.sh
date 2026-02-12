#!/bin/bash
set -e

echo ""
echo "========================================================================="
echo "  Cleanup NODO 1 - Eliminar todos los servicios"
echo "========================================================================="
echo ""
echo "  ⚠️  ADVERTENCIA: Esto eliminará:"
echo "    • Todos los contenedores de NODO 1"
echo "    • Volumen de PostgreSQL PRIMARY (DATOS PERMANENTES)"
echo "    • Red Docker (si no está en uso)"
echo ""

read -p "¿Estás seguro? Esta acción NO se puede deshacer (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Operación cancelada"
    exit 0
fi

echo ""
echo "[1/4] Deteniendo servicios..."
docker compose -f docker-compose-nodo1.yaml down -v 2>/dev/null || echo "  ℹ️  Servicios ya detenidos"
echo "  ✅ Servicios detenidos"
echo ""

echo "[2/4] Eliminando contenedores..."
docker rm -f postgres-primary haproxy pgpool keycloak-1 2>/dev/null || echo "  ℹ️  Contenedores ya eliminados"
echo "  ✅ Contenedores eliminados"
echo ""

echo "[3/4] Eliminando volúmenes..."
docker volume rm -f keycloak_ha_postgres_primary_data 2>/dev/null || echo "  ℹ️  Volúmenes ya eliminados"
echo "  ✅ Volúmenes eliminados"
echo ""

echo "[4/4] Eliminando red (si no está en uso)..."
docker network rm keycloak-ha-net 2>/dev/null || echo "  ℹ️  Red en uso o ya eliminada"
echo ""

echo "========================================================================="
echo "  ✅ NODO 1 Limpio"
echo "========================================================================="
echo ""
echo "  📝 Para volver a desplegar: ./deploy-nodo1.sh"
echo ""

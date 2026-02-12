#!/bin/bash
# =============================================================================
# Script de Despliegue - Keycloak HA con PostgreSQL + Patroni + HAProxy + etcd
# =============================================================================

set -e

echo "=========================================="
echo "  🚀 Keycloak HA Deployment"
echo "  PostgreSQL + Patroni + HAProxy + etcd"
echo "========================================="
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

step() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

wait_for_healthy() {
    local container=$1
    local max_wait=${2:-60}
    local count=0
    
    step "Esperando que $container esté saludable..."
    while [ $count -lt $max_wait ]; do
        if docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null | grep -q "healthy"; then
            echo -e "  ✅ $container está saludable"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    echo -e "  ❌ Timeout esperando $container"
    return 1
}

# =============================================================================
# Paso 1: Preparación
# =============================================================================
step "Paso 1/7: Preparación del entorno"

# Crear red si no existe
if ! docker network inspect keycloak_net >/dev/null 2>&1; then
    docker network create keycloak_net
    echo "  ✅ Red keycloak_net creada"
else
    echo "  ℹ️  Red keycloak_net ya existe"
fi

# Generar certificados
if [ ! -f "certs/tls.crt" ]; then
    step "Generando certificados SSL..."
    ./generate-certs.sh
else
    echo "  ℹ️  Certificados ya existen"
fi

# =============================================================================
# Paso 2: Build Keycloak
# =============================================================================
step "Paso 2/7: Construyendo imagen de Keycloak"
docker build -t keycloak_ha-keycloak . -q
echo "  ✅ Imagen keycloak_ha-keycloak construida"

# =============================================================================
# Paso 3: Detener despliegue anterior (si existe)
# =============================================================================
step "Paso 3/7: Limpiando despliegue anterior"
docker compose -p nodo1 -f docker-compose-nodo1.yaml down -v 2>/dev/null || true
docker compose -p nodo2 -f docker-compose-nodo2.yaml down -v 2>/dev/null || true
echo "  ✅ Limpieza completada"

# =============================================================================
# Paso 4: Levantar etcd cluster
# =============================================================================
step "Paso 4/7: Iniciando cluster etcd"
docker compose -p nodo1 -f docker-compose-nodo1.yaml up -d etcd
docker compose -p nodo2 -f docker-compose-nodo2.yaml up -d etcd
sleep 10

# Verificar etcd
if docker exec etcd-nodo1 etcdctl member list 2>/dev/null | grep -q "started"; then
    echo "  ✅ Cluster etcd iniciado correctamente"
    docker exec etcd-nodo1 etcdctl member list
else
    echo "  ⚠️  etcd puede tardar unos segundos en sincronizar"
fi

# =============================================================================
# Paso 5: Levantar PostgreSQL con Patroni
# =============================================================================
step "Paso 5/7: Iniciando PostgreSQL con Patroni (NODO 1 - PRIMARY)"
docker compose -p nodo1 -f docker-compose-nodo1.yaml up -d postgres
sleep 15
wait_for_healthy postgres-nodo1 90

step "Iniciando PostgreSQL con Patroni (NODO 2 - REPLICA)"
docker compose -p nodo2 -f docker-compose-nodo2.yaml up -d postgres
sleep 20
wait_for_healthy postgres-nodo2 90

# Verificar cluster Patroni
step "Verificando cluster Patroni..."
if docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null; then
    echo "  ✅ Cluster Patroni formado correctamente"
else
    echo "  ⚠️  No se pudo verificar el cluster Patroni (puede estar inicializándose)"
fi

# =============================================================================
# Paso 6: Levantar HAProxy y Keycloak
# =============================================================================
step "Paso 6/7: Iniciando HAProxy y Keycloak NODO 1"
docker compose -p nodo1 -f docker-compose-nodo1.yaml up -d haproxy keycloak
sleep 20

step "Iniciando HAProxy y Keycloak NODO 2"
docker compose -p nodo2 -f docker-compose-nodo2.yaml up -d haproxy keycloak
sleep 10

# =============================================================================
# Paso 7: Verificación final
# =============================================================================
step "Paso 7/7: Verificación del despliegue"

echo ""
echo "=========================================="
echo "  ✅ Despliegue Completado"
echo "=========================================="
echo ""
echo "📊 Estado de los Contenedores:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|nodo"
echo ""
echo "🔗 Acceso a Keycloak:"
echo "  • NODO 1: https://localhost:8443"
echo "  • NODO 2: https://localhost:8444"
echo "  • Usuario: admin / admin"
echo ""
echo "🧪 Comandos Útiles:"
echo "  • Ver cluster Patroni:"
echo "    docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list"
echo ""
echo "  • Ver cluster Infinispan:"
echo "    docker logs keycloak-nodo1 2>&1 | grep 'cluster view'"
echo ""
echo "  • Test de failover:"
echo "    ./test-failover.sh"
echo ""
echo "⚠️  Nota: Keycloak puede tardar 1-2 minutos en iniciar completamente"
echo "=========================================="

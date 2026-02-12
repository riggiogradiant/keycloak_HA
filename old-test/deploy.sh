#!/bin/bash
set -e

# Configurar password para PostgreSQL
export PGPASSWORD="postgres_admin"

echo ""
echo "========================================================================="
echo "  Keycloak HA - PostgreSQL Streaming Replication Nativo"
echo "========================================================================="
echo ""
echo "  Arquitectura simplificada:"
echo "    - PostgreSQL PRIMARY (R/W) + REPLICA (R/O)"
echo "    - HAProxy (detección automática PRIMARY/REPLICA)"
echo "    - Keycloak 1 + Keycloak 2 (cluster cache distribuido)"
echo ""
echo "  Sin Patroni, sin etcd - Solo PostgreSQL nativo"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# =========================================================================
# 1. Crear red Docker
# =========================================================================
echo "[1/6] Creando red Docker..."
docker network create keycloak-ha-net 2>/dev/null || true
echo "  ✅ Red lista"
echo ""

# =========================================================================
# 2. Generar certificados si no existen
# =========================================================================
if [ ! -f "certs/keycloak.p12" ]; then
    echo "[2/6] Generando certificados SSL..."
    bash generate-certs.sh
else
    echo "[2/6] Certificados SSL ya existen"
fi
echo ""

# =========================================================================
# 3. Construir imágenes
# =========================================================================
echo "[3/6] Construyendo imágenes Docker..."
docker compose -f docker-compose.yaml build
echo "  ✅ Imágenes construidas"
echo ""

# =========================================================================
# 4. Iniciar servicios
# =========================================================================
echo "[4/6] Iniciando servicios (PostgreSQL PRIMARY → REPLICA → HAProxy → Keycloak)..."
docker compose -f docker-compose.yaml up -d
echo "  ✅ Servicios iniciados"
echo ""

# =========================================================================
# 5. Esperar PostgreSQL PRIMARY
# =========================================================================
echo "[5/6] Esperando PostgreSQL PRIMARY (30s)..."
sleep 10

for i in {1..30}; do
    if docker exec postgres-primary pg_isready -U postgres > /dev/null 2>&1; then
        echo "  ✅ PRIMARY listo"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Verificar que PRIMARY no está en recovery
IS_PRIMARY=$(docker exec -e PGPASSWORD=postgres_admin postgres-primary psql -h 127.0.0.1 -U postgres -t -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')
if [ "$IS_PRIMARY" = "t" ]; then
    echo "  ✅ Confirmado: postgres-primary es PRIMARY (R/W)"
else
    echo "  ⚠️  WARN: postgres-primary parece estar en recovery mode"
fi
echo ""

# =========================================================================
# 6. Verificar REPLICA
# =========================================================================
echo "[6/6] Verificando PostgreSQL REPLICA..."
sleep 5

for i in {1..30}; do
    if docker exec postgres-replica pg_isready -U postgres > /dev/null 2>&1; then
        echo "  ✅ REPLICA lista"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

IS_REPLICA=$(docker exec -e PGPASSWORD=postgres_admin postgres-replica psql -h 127.0.0.1 -U postgres -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')
if [ "$IS_REPLICA" = "t" ]; then
    echo "  ✅ Confirmado: postgres-replica es REPLICA (R/O)"
else
    echo "  ⚠️  WARN: postgres-replica NO está en recovery mode"
fi
echo ""

# Verificar LAG de replicación
echo "📊 Estado de Replicación:"
echo ""
docker exec -e PGPASSWORD=postgres_admin postgres-primary psql -h 127.0.0.1 -U postgres -x -c "
    SELECT 
        client_addr AS replica_ip,
        state,
        sync_state,
        pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS send_lag_bytes,
        pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes
    FROM pg_stat_replication;
" 2>/dev/null || echo "  ⚠️  No hay réplicas conectadas aún"
echo ""

# =========================================================================
# Esperar Keycloak
# =========================================================================
echo "🔑 Esperando Keycloak (1-2 minutos)..."

KC1_READY=false
KC2_READY=false

for i in {1..60}; do
    if [ "$KC1_READY" = false ]; then
        HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            echo "  ✅ Keycloak-1 ready (https://localhost:8443)"
            KC1_READY=true
        fi
    fi

    if [ "$KC2_READY" = false ]; then
        HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8444 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            echo "  ✅ Keycloak-2 ready (https://localhost:8444)"
            KC2_READY=true
        fi
    fi

    if [ "$KC1_READY" = true ] && [ "$KC2_READY" = true ]; then
        break
    fi
    echo -n "."
    sleep 3
done
echo ""

# =========================================================================
# Resumen Final
# =========================================================================
echo ""
echo "========================================================================="
echo "  ✅ Despliegue Completado"
echo "========================================================================="
echo ""
echo "  📊 Servicios:"
echo "  ────────────────────────────────────────────────────────────────"
echo "  Keycloak:           https://localhost:8443  |  https://localhost:8444"
echo "  Admin:              admin / admin"
echo ""
echo "  HAProxy Stats:      http://localhost:7000"
echo "  HAProxy PRIMARY:    localhost:5000 (escrituras - usa PRIMARY)"
echo "  HAProxy REPLICA:    localhost:5001 (lecturas - usa REPLICA preferente)"
echo ""
echo "  ⭐ pgpool-II:        localhost:9999 (ROUTING AUTOMÁTICO)"
echo "     └─ Detecta queries y redirige: INSERT/UPDATE/DELETE → PRIMARY"
echo "                                     SELECT → REPLICA"
echo ""
echo "  PostgreSQL PRIMARY: localhost:5432 (directo)"
echo "  PostgreSQL REPLICA: localhost:5433 (directo)"
echo ""
echo "  🔧 Comandos útiles:"
echo "  ────────────────────────────────────────────────────────────────"
echo "  ./test.sh                        # ⭐ Tests completos (23 tests totales)"
echo "                                      • Básicos: replicación, LAG, Keycloak"
echo "                                      • HAProxy: routing por puerto"
echo "                                      • pgpool-II: routing automático"
echo "  ./check-replication.sh           # Ver estado de replicación"
echo "  ./promote-replica.sh             # Failover manual (promocionar REPLICA)"
echo "  ./cleanup.sh                     # Eliminar todo"
echo ""
echo "  📝 Logs:"
echo "  ────────────────────────────────────────────────────────────────"
echo "  docker logs postgres-primary -f  # PRIMARY logs"
echo "  docker logs postgres-replica -f  # REPLICA logs"
echo "  docker logs haproxy -f           # HAProxy routing"
echo ""

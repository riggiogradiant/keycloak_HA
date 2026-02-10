#!/bin/bash
set -e

# Configurar password para PostgreSQL
export PGPASSWORD="postgres_admin"

echo ""
echo "========================================================================="
echo "  NODO 2 - Keycloak HA - PostgreSQL REPLICA"
echo "========================================================================="
echo ""
echo "  Componentes:"
echo "    - PostgreSQL REPLICA (R/O) - Replica desde NODO 1"
echo "    - HAProxy (Proxy a PRIMARY remoto + REPLICA local)"
echo "    - pgpool-II (Query routing: escrituras→PRIMARY, lecturas→REPLICA)"
echo "    - Keycloak-2 (HTTPS 8443)"
echo ""
echo "  ⚠️  NODO 1 debe estar corriendo primero"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# =========================================================================
# 0. Solicitar IP del NODO 1
# =========================================================================
echo "[0/8] Configuración de NODO 1..."
echo ""
read -p "Ingresa la IP del NODO 1 (PRIMARY): " NODO1_IP

if [ -z "$NODO1_IP" ]; then
    echo "  ❌ La IP del NODO 1 es obligatoria"
    exit 1
fi

echo "  ✅ IP del NODO 1: $NODO1_IP"
echo ""

# =========================================================================
# 1. Test de conectividad a NODO 1
# =========================================================================
echo "[1/8] Verificando conectividad al NODO 1..."

if command -v nc &> /dev/null; then
    if nc -zv $NODO1_IP 5432 2>&1 | grep -q "succeeded\|open"; then
        echo "  ✅ Puerto 5432 accesible en $NODO1_IP"
    else
        echo "  ⚠️  No se puede conectar a $NODO1_IP:5432"
        echo "  ⚠️  Verifica que NODO 1 esté corriendo y el firewall permita conexiones"
        read -p "¿Continuar de todas formas? (yes/no): " FORCE
        if [ "$FORCE" != "yes" ]; then
            exit 1
        fi
    fi
else
    echo "  ℹ️  'nc' no disponible, omitiendo test de conectividad"
fi
echo ""

# =========================================================================
# 2. Actualizar configuraciones con IP del NODO 1
# =========================================================================
echo "[2/8] Configurando archivos con IP del NODO 1..."

# Actualizar docker-compose-nodo2.yaml
sed -i "s/<NODO1_IP>/$NODO1_IP/g" docker-compose-nodo2.yaml

# Actualizar pgpool-nodo2.conf
sed -i "s/<NODO1_IP>/$NODO1_IP/g" pgpool/pgpool-nodo2.conf

# Actualizar haproxy-nodo2.cfg
sed -i "s/<NODO1_IP>/$NODO1_IP/g" haproxy/haproxy-nodo2.cfg

echo "  ✅ Configuraciones actualizadas"
echo ""

# =========================================================================
# 3. Crear red Docker
# =========================================================================
echo "[3/8] Creando red Docker..."
docker network create keycloak-ha-net 2>/dev/null || echo "  ℹ️  Red ya existe"
echo "  ✅ Red lista"
echo ""

# =========================================================================
# 4. Verificar certificados
# =========================================================================
if [ ! -f "certs/keycloak.p12" ]; then
    echo "[4/8] Generando certificados SSL..."
    bash generate-certs.sh
else
    echo "[4/8] Certificados SSL ya existen"
fi
echo ""

# =========================================================================
# 5. Construir imágenes
# =========================================================================
echo "[5/8] Construyendo imágenes Docker..."
docker compose -f docker-compose-nodo2.yaml build
echo "  ✅ Imágenes construidas"
echo ""

# =========================================================================
# 6. Iniciar servicios
# =========================================================================
echo "[6/8] Iniciando servicios (REPLICA → HAProxy → pgpool → Keycloak)..."
docker compose -f docker-compose-nodo2.yaml up -d
echo "  ✅ Servicios iniciados"
echo ""

# =========================================================================
# 7. Esperar PostgreSQL REPLICA
# =========================================================================
echo "[7/8] Esperando PostgreSQL REPLICA..."
sleep 15

for i in {1..45}; do
    if docker exec postgres-replica pg_isready -U postgres > /dev/null 2>&1; then
        echo "  ✅ REPLICA está lista"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Verificar que es REPLICA
IS_REPLICA=$(docker exec -e PGPASSWORD=postgres_admin postgres-replica psql -h 127.0.0.1 -U postgres -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')
if [ "$IS_REPLICA" = "t" ]; then
    echo "  ✅ Confirmado: postgres-replica es REPLICA (R/O)"
    echo "  ✅ Replicando desde: $NODO1_IP:5432"
else
    echo "  ⚠️  WARN: postgres-replica NO está en recovery mode"
fi
echo ""

# Verificar LAG de replicación
echo "  📊 Estado de Replicación:"
LAG=$(docker exec -e PGPASSWORD=postgres_admin postgres-replica psql -h 127.0.0.1 -U postgres -t -c "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));" 2>/dev/null | tr -d ' ' | cut -d'.' -f1)
if [ ! -z "$LAG" ]; then
    echo "  ✅ LAG de replicación: $LAG segundos"
else
    echo "  ℹ️  LAG no disponible aún"
fi
echo ""

# =========================================================================
# 8. Esperar Keycloak
# =========================================================================
echo "[8/8] Esperando Keycloak (puede tomar 1-2 minutos)..."

for i in {1..60}; do
    KC_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null || echo "000")
    
    if [ "$KC_STATUS" = "200" ]; then
        echo "  ✅ Keycloak está listo"
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        echo "  ⏳ Esperando Keycloak... ($i/60)"
    fi
    sleep 3
done
echo ""

# =========================================================================
# Resumen Final
# =========================================================================
echo ""
echo "========================================================================="
echo "  ✅ NODO 2 Desplegado Correctamente"
echo "========================================================================="
echo ""
echo "  📊 Servicios en NODO 2:"
echo "  ────────────────────────────────────────────────────────────────"
echo "  PostgreSQL REPLICA: localhost:5432 (replicando desde $NODO1_IP)"
echo "  HAProxy PRIMARY:    localhost:5000 (proxy a $NODO1_IP:5432)"
echo "  HAProxy REPLICA:    localhost:5001 (REPLICA local)"
echo "  HAProxy Stats:      http://localhost:7000"
echo "  pgpool-II:          localhost:9999 (routing inteligente)"
echo "    ├─ Escrituras  → PRIMARY remoto ($NODO1_IP)"
echo "    └─ Lecturas    → REPLICA local (rápido)"
echo "  Keycloak:           https://localhost:8443"
echo "  Admin:              admin / admin"
echo ""
echo "  ✅ Cluster Keycloak formado con NODO 1"
echo "  ✅ Replicación PostgreSQL activa desde $NODO1_IP"
echo ""
echo "  🔧 Comandos útiles:"
echo "  ────────────────────────────────────────────────────────────────"
echo "  docker logs postgres-replica -f  # Ver logs REPLICA"
echo "  docker logs keycloak-2 -f        # Ver logs Keycloak"
echo "  docker logs pgpool -f            # Ver logs pgpool (routing)"
echo ""
echo "  # Verificar pgpool backends"
echo "  docker exec pgpool psql -h localhost -p 9999 -U postgres \\"
echo "    -c 'SHOW pool_nodes;'"
echo ""
echo "  # Ver LAG de replicación"
echo "  docker exec -e PGPASSWORD=postgres_admin postgres-replica \\"
echo "    psql -h 127.0.0.1 -U postgres -c \\"
echo "    'SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));'"
echo ""
echo "  📝 Ambos nodos están activos:"
echo "    • Usuario → NODO 1 → Escrituras/Lecturas rápidas (PRIMARY local)"
echo "    • Usuario → NODO 2 → Lecturas rápidas (REPLICA local)"
echo "                       → Escrituras lentas (PRIMARY remoto +latencia red)"
echo ""

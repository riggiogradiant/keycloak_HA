#!/bin/bash
set -e

# Configurar password para PostgreSQL
export PGPASSWORD="postgres_admin"

echo ""
echo "========================================================================="
echo "  NODO 1 - Keycloak HA - PostgreSQL PRIMARY"
echo "========================================================================="
echo ""
echo "  Componentes:"
echo "    - PostgreSQL PRIMARY (R/W) - Puerto 5432 EXPUESTO"
echo "    - HAProxy (Routing local)"
echo "    - pgpool-II (Query routing local)"
echo "    - Keycloak-1 (HTTPS 8443)"
echo ""
echo "  ⚠️  Este nodo debe desplegarse PRIMERO"
echo "  ⚠️  Puerto 5432 debe estar accesible desde NODO 2 para replicación"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# =========================================================================
# 0. Obtener IP del servidor
# =========================================================================
echo "[0/7] Detectando IP del servidor..."
SERVER_IP=$(hostname -I | awk '{print $1}')

if [ -z "$SERVER_IP" ]; then
    echo "  ⚠️  No se pudo detectar la IP automáticamente"
    read -p "Ingresa la IP de este servidor (NODO 1): " SERVER_IP
fi

echo "  ✅ IP del NODO 1: $SERVER_IP"
echo ""
echo "  📝 IMPORTANTE: Configura NODO 2 con esta IP: $SERVER_IP"
echo "  📝 Asegúrate de que el puerto 5432 esté abierto en firewall"
echo ""

read -p "¿Continuar con el despliegue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Despliegue cancelado"
    exit 0
fi
echo ""

# =========================================================================
# 1. Crear red Docker
# =========================================================================
echo "[1/7] Creando red Docker..."
docker network create keycloak-ha-net 2>/dev/null || echo "  ℹ️  Red ya existe"
echo "  ✅ Red lista"
echo ""

# =========================================================================
# 2. Generar certificados si no existen
# =========================================================================
if [ ! -f "certs/keycloak.p12" ]; then
    echo "[2/7] Generando certificados SSL..."
    bash generate-certs.sh
else
    echo "[2/7] Certificados SSL ya existen"
fi
echo ""

# =========================================================================
# 3. Configurar Keycloak cluster con IP detectada
# =========================================================================
echo "[3/7] Configurando Keycloak cluster..."
# Actualizar JGROUPS_DISCOVERY_PROPERTIES con IP real
sed -i "s/<NODO2_IP>/$SERVER_IP/g" docker-compose-nodo1.yaml 2>/dev/null || true
echo "  ✅ Configuración actualizada"
echo ""

# =========================================================================
# 4. Construir imágenes
# =========================================================================
echo "[4/7] Construyendo imágenes Docker..."
docker compose -f docker-compose-nodo1.yaml build
echo "  ✅ Imágenes construidas"
echo ""

# =========================================================================
# 5. Iniciar servicios
# =========================================================================
echo "[5/7] Iniciando servicios (PRIMARY → HAProxy → pgpool → Keycloak)..."
docker compose -f docker-compose-nodo1.yaml up -d
echo "  ✅ Servicios iniciados"
echo ""

# =========================================================================
# 6. Esperar PostgreSQL PRIMARY
# =========================================================================
echo "[6/7] Esperando PostgreSQL PRIMARY..."
sleep 10

for i in {1..30}; do
    if docker exec postgres-primary pg_isready -U postgres > /dev/null 2>&1; then
        echo "  ✅ PRIMARY está listo"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Verificar que es PRIMARY
IS_PRIMARY=$(docker exec -e PGPASSWORD=postgres_admin postgres-primary psql -h 127.0.0.1 -U postgres -t -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')
if [ "$IS_PRIMARY" = "t" ]; then
    echo "  ✅ Confirmado: postgres-primary es PRIMARY (R/W)"
else
    echo "  ⚠️  WARN: postgres-primary parece estar en recovery mode"
fi
echo ""

# =========================================================================
# 7. Esperar Keycloak
# =========================================================================
echo "[7/7] Esperando Keycloak (puede tomar 1-2 minutos)..."

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
echo "  ✅ NODO 1 Desplegado Correctamente"
echo "========================================================================="
echo ""
echo "  📊 Servicios en NODO 1:"
echo "  ────────────────────────────────────────────────────────────────"
echo "  PostgreSQL PRIMARY: $SERVER_IP:5432 (⚠️ EXPUESTO para replicación)"
echo "  HAProxy:            localhost:5000 (PRIMARY local)"
echo "  HAProxy Stats:      http://localhost:7000"
echo "  pgpool-II:          localhost:9999 (routing local)"
echo "  Keycloak:           https://localhost:8443"
echo "  Admin:              admin / admin"
echo "  JGroups Cluster:    $SERVER_IP:7800"
echo ""
echo "  📝 Siguiente Paso: Desplegar NODO 2"
echo "  ────────────────────────────────────────────────────────────────"
echo "  1. Ve al servidor del NODO 2"
echo "  2. Ejecuta: ./deploy-nodo2.sh"
echo "  3. Cuando se solicite, ingresa la IP del NODO 1: $SERVER_IP"
echo ""
echo "  🔧 Comandos útiles:"
echo "  ────────────────────────────────────────────────────────────────"
echo "  docker logs postgres-primary -f  # Ver logs PRIMARY"
echo "  docker logs keycloak-1 -f        # Ver logs Keycloak"
echo "  docker logs pgpool -f            # Ver logs pgpool"
echo ""
echo "  docker exec -e PGPASSWORD=postgres_admin postgres-primary \\"
echo "    psql -h 127.0.0.1 -U postgres -c 'SELECT * FROM pg_stat_replication;'"
echo "  # Ver réplicas conectadas (después de desplegar NODO 2)"
echo ""

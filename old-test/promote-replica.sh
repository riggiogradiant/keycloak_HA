#!/bin/bash
set -e

# Configurar password para PostgreSQL
export PGPASSWORD="postgres_admin"

echo ""
echo "========================================================================="
echo "  🚨 FAILOVER MANUAL: Promocionar REPLICA a PRIMARY"
echo "========================================================================="
echo ""
echo "  ADVERTENCIA: Este script promoverá postgres-replica a PRIMARY."
echo "  Usar solo si postgres-primary ha fallado completamente."
echo ""

read -p "  ¿Continuar con la promoción? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "  ❌ Operación cancelada"
    exit 0
fi

echo ""
echo "─────────────────────────────────────────────────────────────────────"
echo "  PASO 1: Verificar estado actual"
echo "─────────────────────────────────────────────────────────────────────"

# Verificar que replica está en recovery mode
IS_REPLICA=$(docker exec -e PGPASSWORD=postgres_admin postgres-replica psql -h 127.0.0.1 -U postgres -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')

if [ "$IS_REPLICA" != "t" ]; then
    echo "  ❌ ERROR: postgres-replica NO está en recovery mode"
    echo "           Ya es PRIMARY o hay un problema"
    exit 1
fi

echo "  ✅ postgres-replica confirmado en modo REPLICA"
echo ""

# Verificar que PRIMARY está caído (opcional, pero recomendado)
if docker exec postgres-primary pg_isready -U postgres > /dev/null 2>&1; then
    echo "  ⚠️  ADVERTENCIA: postgres-primary sigue respondiendo"
    echo "      Asegúrate de detenerlo antes de continuar"
    echo ""
    read -p "  ¿PRIMARY está realmente caído? (yes/no): " PRIMARY_DOWN
    
    if [ "$PRIMARY_DOWN" != "yes" ]; then
        echo "  ❌ Operación cancelada"
        exit 0
    fi
fi

echo ""
echo "─────────────────────────────────────────────────────────────────────"
echo "  PASO 2: Promocionar REPLICA a PRIMARY"
echo "─────────────────────────────────────────────────────────────────────"

# Promocionar usando pg_ctl
echo "  🔄 Ejecutando: pg_ctl promote..."
docker exec postgres-replica su - postgres -c "pg_ctl promote -D /var/lib/postgresql/data"

# Esperar confirmación
echo "  ⏳ Esperando promoción (10 segundos)..."
sleep 10

# Verificar que ya NO está en recovery
IS_NOW_PRIMARY=$(docker exec -e PGPASSWORD=postgres_admin postgres-replica psql -h 127.0.0.1 -U postgres -t -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null | tr -d ' ')

if [ "$IS_NOW_PRIMARY" = "t" ]; then
    echo "  ✅ postgres-replica ahora es PRIMARY"
else
    echo "  ❌ ERROR: La promoción falló"
    exit 1
fi

echo ""
echo "─────────────────────────────────────────────────────────────────────"
echo "  PASO 3: Actualizar configuración"
echo "─────────────────────────────────────────────────────────────────────"

echo "  ℹ️  El archivo standby.signal fue eliminado automáticamente"
echo "  ℹ️  postgres-replica ahora acepta escrituras"
echo ""

# Test de escritura
echo "  🧪 Test de escritura en nuevo PRIMARY..."
docker exec -e PGPASSWORD=postgres_admin postgres-replica psql -h 127.0.0.1 -U postgres -d keycloak -c "
    CREATE TABLE IF NOT EXISTS failover_test (
        id SERIAL PRIMARY KEY,
        promoted_at TIMESTAMP DEFAULT NOW()
    );
    INSERT INTO failover_test DEFAULT VALUES;
" > /dev/null 2>&1

echo "  ✅ Escritura exitosa en nuevo PRIMARY"
echo ""

echo "========================================================================="
echo "  ✅ FAILOVER COMPLETADO"
echo "========================================================================="
echo ""
echo "  Estado actual:"
echo "    • postgres-replica: AHORA ES PRIMARY (acepta R/W)"
echo "    • postgres-primary: CAÍDO o DESCONECTADO"
echo ""
echo "  📋 Próximos pasos:"
echo "  ─────────────────────────────────────────────────────────────────────"
echo "  1. Actualizar aplicaciones para apuntar a nuevo PRIMARY:"
echo "       Host: localhost:5433 (o postgres-replica)"
echo ""
echo "  2. Cuando postgres-primary se recupere, convertirlo en REPLICA:"
echo "       ./convert-to-replica.sh postgres-primary postgres-replica"
echo ""
echo "  3. Actualizar HAProxy para detectar nuevo PRIMARY:"
echo "       HAProxy debería detectarlo automáticamente vía health checks"
echo ""
echo "  4. Verificar con:"
echo "       ./check-replication.sh"
echo ""

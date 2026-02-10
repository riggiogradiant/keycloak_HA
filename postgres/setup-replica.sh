#!/bin/bash
set -e

PGDATA="/var/lib/postgresql/data"
PRIMARY_HOST="${PRIMARY_HOST:-postgres-primary}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"

echo "🔄 Configurando PostgreSQL REPLICA..."

# Si el directorio de datos está vacío, clonar desde PRIMARY
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "📥 Clonando datos desde PRIMARY ($PRIMARY_HOST:$PRIMARY_PORT)..."
    
    # Esperar a que PRIMARY esté disponible
    until pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U postgres 2>/dev/null; do
        echo "⏳ Esperando PRIMARY disponible..."
        sleep 2
    done
    
    echo "✅ PRIMARY disponible, iniciando pg_basebackup..."
    
    # Clonar datos desde PRIMARY
    PGPASSWORD="replicator_pass" pg_basebackup \
        -h "$PRIMARY_HOST" \
        -p "$PRIMARY_PORT" \
        -U replicator \
        -D "$PGDATA" \
        -P \
        -v \
        -R \
        -X stream \
        -C \
        -S replica_1
    
    echo "✅ Datos clonados exitosamente"
    
    # Arreglar permisos del data directory (pg_basebackup puede dejar permisos incorrectos)
    chmod 0700 "$PGDATA"
    
    # Crear standby.signal (indica modo réplica)
    touch "$PGDATA/standby.signal"
    
    # Copiar configuración
    cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
    cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
    
    echo "✅ REPLICA configurada correctamente (permisos 0700)"
else
    echo "ℹ️  Datos ya existen, iniciando en modo REPLICA..."
    
    # Asegurar permisos correctos
    chmod 0700 "$PGDATA"
fi

# Asegurar que standby.signal existe
if [ ! -f "$PGDATA/standby.signal" ]; then
    echo "⚠️  standby.signal no existe, creándolo..."
    touch "$PGDATA/standby.signal"
fi

# Asegurar que el dueño es postgres
chown -R postgres:postgres "$PGDATA"

echo "✅ REPLICA lista para iniciar"

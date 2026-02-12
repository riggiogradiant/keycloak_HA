#!/bin/bash
set -e

# Script de inicialización para PostgreSQL PRIMARY
# Se ejecuta solo la primera vez que arranca el contenedor

echo "📦 Inicializando PostgreSQL PRIMARY..."

# Copiar configuraciones al data directory
cp /etc/postgresql/pg_hba.conf /var/lib/postgresql/data/pg_hba.conf
cp /etc/postgresql/postgresql.conf /var/lib/postgresql/data/postgresql.conf

echo "✅ Configuraciones copiadas a data directory"

# Crear usuario de replicación
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    -- Usuario para replicación
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_pass';
    
    -- NO creamos el replication slot aquí - lo crea pg_basebackup automáticamente
    
    -- Usuario y base de datos para Keycloak
    CREATE USER keycloak WITH PASSWORD 'keycloak';
    CREATE DATABASE keycloak OWNER keycloak;
    
    -- Permisos
    GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
EOSQL

# Recargar configuración
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -c "SELECT pg_reload_conf();"

echo "✅ PRIMARY inicializado correctamente"
echo "   - Usuario replicator creado"
echo "   - Base de datos 'keycloak' creada"
echo "   - Configuración pg_hba.conf aplicada"
echo "   - Replication slot será creado por pg_basebackup"

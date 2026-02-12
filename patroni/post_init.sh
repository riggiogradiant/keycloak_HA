#!/bin/bash
set -e

# Script ejecutado por Patroni después de inicializar el cluster
# Solo se ejecuta en el nodo que hace bootstrap (el primero en iniciar)

echo "=== Patroni Post-Init: Creando usuarios y base de datos ==="

# Crear usuario de replicación
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    -- Usuario para replicación
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
            CREATE ROLE replicator WITH REPLICATION PASSWORD 'replicator_secret' LOGIN;
            RAISE NOTICE 'Usuario replicator creado';
        END IF;
    END
    \$\$;

    -- Usuario para Keycloak
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'keycloak') THEN
            CREATE ROLE keycloak WITH SUPERUSER CREATEDB PASSWORD 'keycloak_secret' LOGIN;
            RAISE NOTICE 'Usuario keycloak creado';
        END IF;
    END
    \$\$;
EOSQL

# Crear base de datos Keycloak
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    SELECT 'CREATE DATABASE keycloak OWNER keycloak'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'keycloak')\gexec
EOSQL

echo "=== Post-Init completado ==="

#!/bin/bash
set -e

# Este script se ejecuta al iniciar el contenedor de la réplica
# Primero ejecuta el setup si es necesario, luego inicia PostgreSQL

PGDATA="/var/lib/postgresql/data"

# Si el directorio está vacío o no tiene PG_VERSION, ejecutar setup
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "🔄 Primera ejecución - Configurando REPLICA..."
    # Ejecutar el script de setup como root
    bash /docker-entrypoint-initdb.d/setup-replica.sh
fi

# Ahora ejecutar el entrypoint original de PostgreSQL
# que se encargará de iniciar el servidor correctamente como usuario postgres
exec docker-entrypoint.sh postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf

#!/bin/bash
set -e

# Configurar password para PostgreSQL
export PGPASSWORD="postgres_admin"

echo ""
echo "========================================================================="
echo "  Estado de Replicación PostgreSQL"
echo "========================================================================="
echo ""

# Verificar que PRIMARY no está en recovery
echo "🔍 Verificando rol de servidores..."
echo ""

PRIMARY_STATUS=$(docker exec -e PGPASSWORD=postgres_admin postgres-primary psql -h 127.0.0.1 -U postgres -t -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'REPLICA' ELSE 'PRIMARY' END;" 2>/dev/null | tr -d ' ')
REPLICA_STATUS=$(docker exec -e PGPASSWORD=postgres_admin postgres-replica psql -h 127.0.0.1 -U postgres -t -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'REPLICA' ELSE 'PRIMARY' END;" 2>/dev/null | tr -d ' ')

echo "  postgres-primary: $PRIMARY_STATUS"
echo "  postgres-replica: $REPLICA_STATUS"
echo ""

if [ "$PRIMARY_STATUS" != "PRIMARY" ]; then
    echo "  ⚠️  WARN: postgres-primary NO es PRIMARY!"
fi

if [ "$REPLICA_STATUS" != "REPLICA" ]; then
    echo "  ⚠️  WARN: postgres-replica NO es REPLICA!"
fi

# Ver réplicas conectadas al PRIMARY
echo "========================================================================="
echo "  Réplicas Conectadas al PRIMARY"
echo "========================================================================="
echo ""

docker exec -e PGPASSWORD=postgres_admin postgres-primary psql -h 127.0.0.1 -U postgres -c "
    SELECT 
        application_name AS replica,
        client_addr AS ip,
        state,
        sync_state,
        pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS send_lag_bytes,
        pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
        EXTRACT(EPOCH FROM (now() - reply_time)) AS last_reply_seconds
    FROM pg_stat_replication;
" 2>/dev/null

echo ""

# LAG de replicación en la REPLICA
echo "========================================================================="
echo "  LAG de Replicación (visto desde REPLICA)"
echo "========================================================================="
echo ""

docker exec -e PGPASSWORD=postgres_admin postgres-replica psql -h 127.0.0.1 -U postgres -c "
    SELECT 
        EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag_seconds,
        pg_last_xact_replay_timestamp() AS last_replay_time,
        pg_is_in_recovery() AS is_replica
    ;
" 2>/dev/null

echo ""

# Replication slots
echo "========================================================================="
echo "  Replication Slots"
echo "========================================================================="
echo ""

docker exec -e PGPASSWORD=postgres_admin postgres-primary psql -h 127.0.0.1 -U postgres -c "
    SELECT 
        slot_name,
        slot_type,
        active,
        pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_wal_bytes
    FROM pg_replication_slots;
" 2>/dev/null

echo ""

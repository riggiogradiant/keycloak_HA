---
description: Keycloak HA Project Context - High Availability Identity Management System
applyTo: '**/*'
---

# Keycloak HA - Project Context

## Project Overview

This is a **production-ready Keycloak Identity and Access Management (IAM)** system with **High Availability (HA)** architecture featuring:

- ✅ **Zero downtime failover** (< 40 seconds recovery)
- ✅ **Zero data loss** (PostgreSQL streaming replication)
- ✅ **Distributed session replication** (Infinispan cluster)
- ✅ **Automatic failure detection and recovery** (Patroni orchestration)
- ✅ **Active-Active Keycloak nodes** (both nodes serve traffic simultaneously)

**Full documentation**: See [SYSTEM_CONTEXT.md](../../SYSTEM_CONTEXT.md) for complete technical details.

---

## Technology Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| **Keycloak** | 26.0.0 | Identity & Access Management (IAM) |
| **PostgreSQL** | 15 | Persistent data storage with streaming replication |
| **Patroni** | 3.2.2 | PostgreSQL HA orchestrator (auto-failover) |
| **HAProxy** | 2.9 | Smart query router (directs traffic to PRIMARY) |
| **etcd** | 3.5.10 | Distributed consensus store (Raft algorithm) |
| **Infinispan** | Built-in Keycloak | Distributed cache for session replication |
| **JGroups** | Built-in | TCP-based cluster communication protocol |
| **Docker** | Latest | Container orchestration |

---

## Architecture Overview

### Deployment Topology

```
2 Complete Nodes (each with all services):

NODO 1:
├── etcd-nodo1 (port 2379, 2380)
├── postgres-nodo1 (port 5432) + Patroni (8008)
├── haproxy-nodo1 (port 5432, 5433, 7000)
└── keycloak-nodo1 (port 8443, 7800)

NODO 2:
├── etcd-nodo2 (port 2379, 2380)
├── postgres-nodo2 (port 5432) + Patroni (8008)
├── haproxy-nodo2 (port 5432, 5433, 7000)
└── keycloak-nodo2 (port 8444, 7801)
```

### Key Architectural Decisions

1. **PostgreSQL PRIMARY/REPLICA with Patroni**:
   - ONE node is PRIMARY (accepts writes), ONE is REPLICA (read-only standby)
   - Patroni monitors health and promotes REPLICA to PRIMARY if PRIMARY fails
   - Streaming replication ensures data consistency (typical lag: 0 bytes)

2. **HAProxy as Query Router**:
   - Queries Patroni REST API (`GET /master`) to detect PRIMARY
   - Routes ALL Keycloak traffic to current PRIMARY
   - No SQL parsing needed - trusts Patroni as source of truth
   - **CRITICAL**: Requires DNS resolver configured (Docker's 127.0.0.11:53)

3. **Keycloak Active-Active with Infinispan**:
   - Both Keycloak nodes process requests simultaneously
   - Sessions replicated via JGroups TCP (port 7800) using TCPPING discovery
   - Users can switch between nodes without re-authentication

4. **etcd for Cluster Coordination**:
   - Stores cluster state (who is PRIMARY/REPLICA)
   - Enables Patroni to make coordinated decisions
   - Uses Raft consensus algorithm for distributed agreement

---

## Project Structure

```
keycloak_HA/
├── docker-compose-nodo1.yaml    # Node 1 services definition
├── docker-compose-nodo2.yaml    # Node 2 services definition
├── Dockerfile                   # Optimized Keycloak image
├── Dockerfile.patroni           # PostgreSQL + Patroni image
├── deploy-ha.sh                 # Automated deployment script (orchestrates everything)
├── generate-certs.sh            # SSL/TLS certificate generator
├── test-failover.sh             # Automated failover test
├── .env.example                 # Environment variables template
├── SYSTEM_CONTEXT.md            # Complete technical documentation
├── README.md                    # User-facing documentation
│
├── certs/                       # SSL/TLS certificates (auto-generated)
│   ├── tls.crt
│   └── tls.key
│
├── haproxy/
│   └── haproxy.cfg             # HAProxy configuration (with DNS resolver)
│
├── patroni/
│   ├── patroni-nodo1.yml       # Patroni config for node 1
│   ├── patroni-nodo2.yml       # Patroni config for node 2
│   └── post_init.sh            # Post-bootstrap script (creates users/DB)
│
└── tests/                       # Automated test suite
    ├── run-all-tests.sh        # Master test runner
    ├── test-sync.sh            # PostgreSQL replication test
    ├── test-routing.sh         # HAProxy routing test
    └── test-infinispan.sh      # Keycloak clustering test
```

---

## Coding Guidelines & Conventions

### Shell Scripts (Bash)

**Style**:
- Use `set -e` at the beginning to exit on errors
- Color codes for output: `GREEN='\033[0;32m'`, `RED='\033[0;31m'`, `YELLOW='\033[1;33m'`
- Helper functions: `step()` for progress messages, `error()` for failures
- Use `2>/dev/null || true` for commands that may fail gracefully

**Example Pattern**:
```bash
#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'

step() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

step "Starting operation..."
docker exec container_name command 2>/dev/null || true
echo "  ✅ Operation completed"
```

### Docker Compose Files

**Naming Conventions**:
- Service names: lowercase with hyphens (e.g., `etcd`, `postgres`, `haproxy`, `keycloak`)
- Container names: component-nodo1/nodo2 (e.g., `etcd-nodo1`, `postgres-nodo2`)
- Volume names: descriptive_data (e.g., `postgres_data`, `etcd_data`)
- Network: Always use `keycloak_net` (external network)

**Service Order**:
1. etcd (no dependencies)
2. postgres (depends on etcd healthy)
3. haproxy (depends on postgres healthy)
4. keycloak (depends on haproxy healthy)

**Health Checks**:
- Always define health checks with appropriate `start_period` (services need time to initialize)
- Use `curl` or `wget` for HTTP checks, not `nc` or `telnet`

**Example**:
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:8008/health || exit 1"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s  # Important: give service time to start
```

### Configuration Files

**Patroni YAML**:
- `scope`: Always `keycloak-postgres-cluster` (cluster name)
- `name`: Unique per node (`postgres-nodo1` or `postgres-nodo2`)
- `ttl: 30`: Leader lease duration (30 seconds)
- `loop_wait: 10`: Health check interval

**HAProxy Config**:
- **CRITICAL**: Always include DNS resolver section:
  ```cfg
  resolvers docker
      nameserver dns1 127.0.0.11:53
  ```
- Health check: `option httpchk OPTIONS /master` to Patroni port 8008
- Backend servers: Use `resolvers docker init-addr libc,none`

**Keycloak Environment**:
- Database URL: Always via HAProxy (`jdbc:postgresql://haproxy-nodo1:5432/keycloak`)
- Cache: `KC_CACHE=ispn`, `KC_CACHE_STACK=tcp`
- JGroups discovery: `JGROUPS_DISCOVERY_PROTOCOL=TCPPING` with explicit host list

---

## Critical Configuration Details

### 1. HAProxy DNS Resolution (SOLVED ISSUE)

**Problem**: Without DNS resolver, HAProxy puts backends in `MAINT` state and Keycloak cannot connect.

**Solution**: Always include in `haproxy/haproxy.cfg`:
```cfg
resolvers docker
    nameserver dns1 127.0.0.11:53
    resolve_retries 3
    timeout resolve 1s
    hold valid 10s

# Then in backend:
default-server ... resolvers docker init-addr libc,none
```

### 2. External Docker Network

All services communicate via `keycloak_net` network:
```bash
docker network create keycloak_net
```

In docker-compose:
```yaml
networks:
  keycloak_net:
    external: true  # Network must exist before deploy
```

### 3. Patroni Post-Init Script

File: `patroni/post_init.sh` - Executed ONLY by first node during bootstrap.

Creates:
- User `replicator` (for streaming replication)
- User `keycloak` (for application connections)
- Database `keycloak` (owned by keycloak user)

### 4. JGroups TCPPING Configuration

For Keycloak clustering without multicast:
```yaml
JGROUPS_DISCOVERY_PROTOCOL: TCPPING
JGROUPS_DISCOVERY_PROPERTIES: initial_hosts="keycloak-nodo1[7800]\\,keycloak-nodo2[7800]",port_range=0
```

Port 7800 must be exposed in docker-compose for inter-node communication.

---

## Common Operational Patterns

### Deploying the System

```bash
# Automated (recommended):
./deploy-ha.sh

# Manual (step by step):
./generate-certs.sh
docker network create keycloak_net
docker compose -f docker-compose-nodo1.yaml up -d
docker compose -f docker-compose-nodo2.yaml up -d
```

### Verifying Cluster Health

```bash
# PostgreSQL cluster status
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list

# HAProxy backends status
curl http://localhost:7000

# Keycloak cluster formation
docker logs keycloak-nodo1 2>&1 | grep "cluster view"
```

### Checking Replication

```bash
# On PRIMARY
docker exec postgres-nodo1 psql -U postgres -c \
  "SELECT application_name, state, 
          pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
   FROM pg_stat_replication;"

# Expected: lag_bytes = 0 or very small
```

---

## Troubleshooting Common Issues

### Issue: Keycloak Crash Loop (Cannot Connect to DB)

**Diagnosis**:
```bash
docker logs keycloak-nodo2  # Shows: "Failed to obtain JDBC connection"
docker exec haproxy-nodo1 wget -O- -q http://127.0.0.1:7000 | grep MAINT
```

**Solution**: Check HAProxy has DNS resolver configured (see Critical Configuration #1)

### Issue: Infinispan Cluster Has Only 1 Member

**Diagnosis**:
```bash
docker logs keycloak-nodo1 | grep "cluster view"
# Shows: (1) [keycloak-nodo1-xxxxx]  ← Only 1 member
```

**Solutions**:
1. Verify port 7800 is exposed in docker-compose
2. Check connectivity: `docker exec keycloak-nodo1 ping keycloak-nodo2`
3. Restart both Keycloak nodes: `docker restart keycloak-nodo1 keycloak-nodo2`

### Issue: Replication Lag

**Diagnosis**:
```bash
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list
# Shows: | Replica | ... | Lag in MB: 5120 |
```

**Solutions**:
1. Check network latency between nodes
2. Check disk I/O on REPLICA
3. Consider enabling synchronous replication for zero lag guarantee

---

## Test Suite

### Running Tests

```bash
# All tests (recommended)
./tests/run-all-tests.sh

# Individual tests
./tests/test-sync.sh        # PostgreSQL replication
./tests/test-routing.sh     # HAProxy routing
./tests/test-infinispan.sh  # Keycloak clustering
./test-failover.sh          # Automated failover (destructive, 90s)
```

### Expected Test Results

- ✅ **test-sync.sh**: Both nodes have identical data, lag = 0 bytes
- ✅ **test-routing.sh**: HAProxy routes to PRIMARY, both HAProxy instances work
- ✅ **test-infinispan.sh**: 2 members in cluster (warnings about ping/netstat are NORMAL)
- ✅ **test-failover.sh**: Failover < 40s, no data loss

**Note**: Warnings like "no netstat/ss available" or "ping not found" are expected and harmless.

---

## Security Considerations

**Current setup is for DEVELOPMENT/TESTING**. For production:

1. ✅ Change ALL default passwords in `.env`
2. ✅ Use valid SSL certificates (not self-signed)
3. ✅ Enable synchronous replication for zero data loss guarantee
4. ✅ Configure firewalls and limit exposed ports
5. ✅ Implement automated backups
6. ✅ Set up monitoring/alerting (Prometheus, Grafana)
7. ✅ Review `pg_hba.conf` permissions (currently accepts any IP)
8. ✅ Use persistent volumes (not local driver in production)

---

## Important Files to Reference

When making changes, always consult:

1. **SYSTEM_CONTEXT.md**: Complete technical documentation with all details
2. **README.md**: User-facing documentation and quick start guide
3. **haproxy/haproxy.cfg**: HAProxy configuration (especially DNS resolver)
4. **patroni/patroni-nodo1.yml**: Patroni configuration (DCS settings, bootstrap)
5. **deploy-ha.sh**: Deployment order and timing (critical for startup sequence)

---

## Key Environment Variables

Default values from `.env.example`:

```bash
# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin

# PostgreSQL
POSTGRES_PASSWORD=keycloak_secret
POSTGRES_ADMIN_PASSWORD=postgres_admin
REPLICATION_PASSWORD=replicator_secret

# Logging
KC_LOG_LEVEL=info
```

---

## Deployment Workflow

The `deploy-ha.sh` script orchestrates deployment in this order:

1. Create network and generate certificates
2. Build Docker images (Keycloak, Patroni)
3. Clean up previous deployment (`down -v`)
4. Start etcd cluster (both nodes) → wait 10s
5. Start PostgreSQL + Patroni NODO 1 → wait for healthy (~90s max)
6. Start PostgreSQL + Patroni NODO 2 → wait for healthy (~90s max)
7. Start HAProxy + Keycloak NODO 1 → wait 20s
8. Start HAProxy + Keycloak NODO 2 → wait 10s
9. Verify deployment

**Total deployment time**: ~2-3 minutes

---

## Port Reference

| Service | Host Port | Purpose |
|---------|-----------|---------|
| Keycloak NODO 1 | 8443 | HTTPS web UI |
| Keycloak NODO 2 | 8444 | HTTPS web UI |
| JGroups NODO 1 | 7800 | Cluster communication |
| JGroups NODO 2 | 7801 | Cluster communication |
| HAProxy Stats | 7000 | Web statistics interface |

Internal ports (not exposed to host):
- PostgreSQL: 5432
- Patroni API: 8008
- etcd Client: 2379
- etcd Peer: 2380
- HAProxy Primary: 5432 (internal routing)

---

## Failover Behavior

When PRIMARY fails:

1. **Detection**: 0-10s (Patroni health checks every 10s)
2. **Promotion**: 10-30s (Patroni promotes REPLICA to PRIMARY)
3. **HAProxy Detection**: 30-35s (health checks every 3s, needs 3 failures)
4. **Keycloak Reconnection**: 35-40s (connection pool retry)

**Result**:
- Total downtime: ~35-40 seconds
- Data loss: 0 (streaming replication was up-to-date)
- Sessions preserved: Yes (Infinispan distributed cache)

---

## When Modifying Code

### Adding a New Service

1. Add to both `docker-compose-nodo1.yaml` and `docker-compose-nodo2.yaml`
2. Ensure proper `depends_on` with health checks
3. Add to `keycloak_net` network
4. Update `deploy-ha.sh` deployment order if needed
5. Create corresponding test in `tests/`

### Changing Configuration

1. Update both node configurations (nodo1 and nodo2)
2. Test with `./deploy-ha.sh`
3. Run full test suite: `./tests/run-all-tests.sh`
4. Update `SYSTEM_CONTEXT.md` documentation

### Modifying Health Checks

1. Ensure sufficient `start_period` (services need startup time)
2. Use reliable commands (`curl`, not `nc`)
3. Test failure scenarios (stop service, should detect and mark unhealthy)

---

## Best Practices

1. **Always use the external network**: Services must communicate via `keycloak_net`
2. **Never skip health checks**: Proper health checks prevent cascading failures
3. **Document configuration changes**: Update SYSTEM_CONTEXT.md
4. **Test after changes**: Run test suite to verify everything works
5. **Use meaningful names**: Follow naming conventions (service-nodoX format)
6. **Handle startup timing**: Services need time to initialize (use depends_on with health checks)
7. **Log everything**: Scripts use `step()` function for clear progress tracking

---

## Quick Command Reference

```bash
# View cluster status
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list

# Check replication lag
docker exec postgres-nodo1 psql -U postgres -c \
  "SELECT application_name, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag 
   FROM pg_stat_replication;"

# View HAProxy stats
curl http://localhost:7000

# Check Keycloak cluster
docker logs keycloak-nodo1 2>&1 | grep "cluster view" | tail -1

# Clean everything (DESTROYS DATA)
docker compose -p nodo1 -f docker-compose-nodo1.yaml down -v
docker compose -p nodo2 -f docker-compose-nodo2.yaml down -v
```

---

**For complete technical details, diagrams, and troubleshooting**: See [SYSTEM_CONTEXT.md](../../SYSTEM_CONTEXT.md)
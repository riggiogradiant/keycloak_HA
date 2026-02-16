# Keycloak HA - Contexto Completo del Sistema

## 📑 Índice
1. [Resumen Ejecutivo](#resumen-ejecutivo)
2. [Arquitectura Global](#arquitectura-global)
3. [Componentes Detallados](#componentes-detallados)
4. [Configuraciones Críticas](#configuraciones-críticas)
5. [Flujos Operacionales](#flujos-operacionales)
6. [Troubleshooting](#troubleshooting)
7. [Referencias Rápidas](#referencias-rápidas)

---

## 📋 Resumen Ejecutivo

### ¿Qué es este sistema?
Sistema de autenticación **Keycloak** en **Alta Disponibilidad (HA)** con:
- ✅ **Tolerancia a fallos**: Si un componente falla, el sistema continúa operando
- ✅ **Failover automático**: Recuperación automática en < 30 segundos
- ✅ **Zero data loss**: Replicación síncrona de datos
- ✅ **Session replication**: Usuarios no pierden sesión durante failovers
- ✅ **Active-Active**: Ambos nodos Keycloak procesan tráfico simultáneamente

### Stack Tecnológico
- **Keycloak 26.0.0**: Identity & Access Management
- **PostgreSQL 15**: Base de datos con streaming replication
- **Patroni 3.2.2**: Orquestador de alta disponibilidad para PostgreSQL
- **HAProxy 2.9**: Balanceador de carga inteligente
- **etcd 3.5.10**: Almacenamiento distribuido de consenso
- **Infinispan**: Caché distribuida para sesiones (incluido en Keycloak)
- **JGroups TCP**: Protocolo de comunicación del cluster

### Arquitectura de Despliegue
```
2 Nodos Completos (cada uno tiene todos los servicios):
├── NODO 1
│   ├── etcd-nodo1           (puerto 2379, 2380)
│   ├── postgres-nodo1       (puerto 5432) + Patroni (8008)
│   ├── haproxy-nodo1        (puerto 5432, 5433, 7000)
│   └── keycloak-nodo1       (puerto 8443, 7800)
└── NODO 2
    ├── etcd-nodo2           (puerto 2379, 2380)
    ├── postgres-nodo2       (puerto 5432) + Patroni (8008)
    ├── haproxy-nodo2        (puerto 5432, 5433, 7000)
    └── keycloak-nodo2       (puerto 8444, 7801)
```

---

## 🏗️ Arquitectura Global

### Diagrama de Componentes y Flujos

```
┌─────────────────────────────────────────────────────────────────┐
│                      CAPA DE USUARIOS                           │
│              https://localhost:8443 | 8444                      │
└──────────────────────┬──────────────────────────────────────────┘
                       │
    ┌──────────────────┴───────────────────┐
    │                                      │
    ▼                                      ▼
┌────────────────────┐                ┌────────────────────┐
│  Keycloak NODO 1   │◄───Infinispan─►│  Keycloak NODO 2   │
│    (Active)        │   JGroups:7800 │    (Active)        │
│  HTTPS/TLS:8443    │                │  HTTPS/TLS:8444    │
└─────────┬──────────┘                └─────────┬──────────┘
          │                                     │
          │  JDBC (PostgreSQL)                  │
          └─────────────┬───────────────────────┘
                        │
                        ▼
            ┌──────────────────────┐
            │   HAProxy NODO 1/2   │  ← Cada Keycloak usa su HAProxy local
            │  Query Router        │
            │  Port 5432 (writes)  │
            │  Port 5433 (reads)   │
            │  Port 7000 (stats)   │
            └──────────┬───────────┘
                       │
                       │ HTTP Health Checks cada 3s
                       │ GET /master → 200 = is PRIMARY
                       ▼
      ┌────────────────────────────────────┐
      │     Patroni REST API (8008)        │
      │  /master  /replica  /health        │
      └────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
        ▼                             ▼
┌───────────────────┐         ┌───────────────────┐
│ Patroni NODO 1    │         │ Patroni NODO 2    │
│ ┌───────────────┐ │         │ ┌───────────────┐ │
│ │ PostgreSQL 15 │◄┼─────────┼─┤ PostgreSQL 15 │ │
│ │   PRIMARY     │ │Streaming│ │   REPLICA     │ │
│ │   Port 5432   │ │Repl.    │ │   Port 5432   │ │
│ └───────────────┘ │         │ └───────────────┘ │
└─────────┬─────────┘         └─────────┬─────────┘
          │                             │
          │       etcd Cluster          │
          └────────────┬────────────────┘
                       │
                       ▼
              ┌─────────────────┐
              │  etcd NODO 1/2  │  ← Consensus store (Raft)
              │  Port 2379/2380 │     Coordinación del cluster
              └─────────────────┘
```

---

## 🔧 Componentes Detallados

### 1. etcd - Distributed Consensus Store

**Propósito**: Sistema de coordinación distribuida (cerebro del cluster).

**Funcionalidades**:
- ✅ Almacena el estado del cluster PostgreSQL (quién es PRIMARY/REPLICA)
- ✅ Coordination store para elecciones de líder (algoritmo Raft)
- ✅ Key-Value store distribuido y consistente
- ✅ Permite a Patroni tomar decisiones coordinadas

**Puertos**:
- `2379`: Cliente (Patroni se conecta aquí)
- `2380`: Peer-to-peer (comunicación entre nodos etcd)

**Configuración Clave**:
```yaml
--initial-cluster=etcd-nodo1=http://etcd-nodo1:2380,etcd-nodo2=http://etcd-nodo2:2380
--initial-cluster-state=new
--initial-cluster-token=keycloak-etcd-cluster
```

**Health Check**:
```bash
docker exec etcd-nodo1 etcdctl endpoint health
docker exec etcd-nodo1 etcdctl member list
```

---

### 2. Patroni - PostgreSQL HA Orchestrator

**Propósito**: Orquestador que gestiona automáticamente el cluster PostgreSQL.

**Funcionalidades**:
- 🔄 **Auto-failover**: Si PRIMARY falla → promueve REPLICA a PRIMARY (< 30s)
- 💓 **Health monitoring**: Monitorea constantemente cada nodo PostgreSQL
- 🔌 **Configuración dinámica**: Reconfigura replicación automáticamente
- 📡 **REST API**: Expone endpoints para HAProxy y diagnóstico

**REST API (Puerto 8008)**:
| Endpoint | Descripción | Respuesta |
|----------|-------------|-----------|
| `/master` | ¿Es este nodo el PRIMARY? | HTTP 200 si es PRIMARY, 503 si no |
| `/replica` | ¿Es este nodo una REPLICA? | HTTP 200 si es REPLICA, 503 si no |
| `/health` | Estado general del nodo | HTTP 200 + JSON con detalles |
| `/leader` | ¿Es este nodo el LEADER? | Similar a /master |

**Configuración Patroni** (`patroni/patroni-nodo1.yml`):
```yaml
scope: keycloak-postgres-cluster  # Nombre del cluster
name: postgres-nodo1              # Nombre único del nodo

etcd3:
  hosts: etcd-nodo1:2379,etcd-nodo2:2379  # Cluster etcd

bootstrap:
  dcs:
    ttl: 30                      # Tiempo antes de considerar nodo muerto
    loop_wait: 10                # Intervalo de health checks
    retry_timeout: 10
    maximum_lag_on_failover: 1048576  # Max lag para permitir failover (1MB)
    postgresql:
      use_pg_rewind: true        # Permite reincorporar nodo antiguo
      use_slots: true            # Slots de replicación (evita pérdida WAL)
```

**Comandos Útiles**:
```bash
# Ver estado del cluster
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list

# Forzar switchover (cambio manual de PRIMARY)
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml switchover

# Reiniciar Patroni (NO reinicia PostgreSQL)
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml restart postgres-nodo1
```

---

### 3. PostgreSQL 15 - Relational Database

**Propósito**: Almacenamiento persistente de todos los datos de Keycloak.

**Roles**:
- **PRIMARY** (Leader): Acepta escrituras y lecturas
- **REPLICA** (Standby): Réplica en streaming (solo lecturas)

**Replicación Streaming**:
- Método: Streaming Replication (async por defecto, configurable a sync)
- WAL (Write-Ahead Log) se transmite en tiempo real
- Lag típico: **0 bytes** (sincronización instantánea)
- Usuario replicación: `replicator` (password: replicator_secret)

**Usuarios y Base de Datos**:
| Usuario | Rol | Propósito |
|---------|-----|-----------|
| `postgres` | Superuser | Administración (Patroni) |
| `replicator` | Replication | Streaming replication y pg_rewind |
| `keycloak` | Superuser | Usado por Keycloak para conectarse |
| **DB** | keycloak | Base de datos de la aplicación |

**Configuración de Rendimiento** (`patroni/patroni-nodoX.yml`):
```yaml
postgresql:
  parameters:
    # Replication
    wal_level: replica
    max_wal_senders: 10
    max_replication_slots: 10
    wal_keep_size: 512MB
    hot_standby: on
    
    # Performance
    max_connections: 200
    shared_buffers: 256MB
    effective_cache_size: 1GB
    work_mem: 2621kB
```

**Query para Verificar Replicación**:
```sql
-- En PRIMARY, ver estado de REPLICAs conectadas
SELECT application_name, client_addr, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- En REPLICA, ver lag de replicación
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

---

### 4. HAProxy - Query Router & Load Balancer

**Propósito**: Enrutar automáticamente todo el tráfico al nodo PRIMARY de PostgreSQL.

**Estrategia de Routing**:
1. HAProxy hace health checks a Patroni de cada nodo: `OPTIONS /master`
2. Solo el nodo PRIMARY responde HTTP 200
3. HAProxy marca ese nodo como "UP"
4. Todo el tráfico va al nodo "UP"

**Ventaja**: HAProxy NO necesita parsear SQL ni entender base de datos. Solo confía en Patroni.

**Configuración DNS Resolver** (`haproxy/haproxy.cfg`):

**CRÍTICO**: Sin resolver DNS, HAProxy pone backends en MAINT (maintenance).

```cfg
# Docker DNS resolver
resolvers docker
    nameserver dns1 127.0.0.11:53        # DNS embebido de Docker
    resolve_retries 3
    timeout resolve 1s
    timeout retry   1s
    hold valid      10s

listen postgres_primary
    bind *:5432
    option httpchk OPTIONS /master        # Health check a Patroni
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions \
                   resolvers docker init-addr libc,none
    server postgres-nodo1 postgres-nodo1:5432 maxconn 100 check port 8008
    server postgres-nodo2 postgres-nodo2:5432 maxconn 100 check port 8008
```

**Parámetros Clave**:
- `inter 3s`: Health check cada 3 segundos
- `fall 3`: Marcar DOWN después de 3 fallos consecutivos
- `rise 2`: Marcar UP después de 2 éxitos consecutivos
- `check port 8008`: Verificar en puerto de Patroni (no PostgreSQL)
- `resolvers docker init-addr libc,none`: Usar DNS de Docker para resolver nombres

**Puertos**:
- `5432`: Tráfico hacia PRIMARY (usado por Keycloak)
- `5433`: Tráfico hacia REPLICAs (para lecturas, actualmente sin uso)
- `7000`: Stats web interface (http://localhost:7000)

**Monitoreo**:
```bash
# Ver estadísticas web
curl http://localhost:7000

# Ver estado de backends (desde dentro del contenedor)
docker exec haproxy-nodo1 wget -O- -q http://127.0.0.1:7000 | grep postgres
```

**Detección de Failover**:
- Tiempo de detección: ~9 segundos (3s interval × 3 health checks)
- Reconexiones de Keycloak: automáticas via connection pool

---

### 5. Keycloak 26.0.0 - Identity and Access Management

**Propósito**: Sistema de autenticación, autorización y gestión de identidades.

**Modo de Operación**: **Active-Active**
- Ambos nodos procesan requests simultáneamente
- Load balancing externo (no incluido en este setup, puede ser nginx/traefik)
- Sesiones replicadas vía Infinispan

**Conexión a Base de Datos**:
```yaml
environment:
  KC_DB: postgres
  KC_DB_URL: jdbc:postgresql://haproxy-nodo1:5432/keycloak  # Vía HAProxy
  KC_DB_USERNAME: keycloak
  KC_DB_PASSWORD: keycloak_secret
```

**Clustering con Infinispan**:
```yaml
environment:
  KC_CACHE: ispn                    # Usar Infinispan
  KC_CACHE_STACK: tcp               # Stack de JGroups (TCP en vez de UDP)
  
  # JGroups TCPPING (discovery de nodos)
  JGROUPS_DISCOVERY_PROTOCOL: TCPPING
  JGROUPS_DISCOVERY_PROPERTIES: initial_hosts="keycloak-nodo1[7800]\\,keycloak-nodo2[7800]",port_range=0
  
  # JGroups bind address
  JAVA_OPTS_APPEND: >-
    -Djava.net.preferIPv4Stack=true
    -Djgroups.tcp.port=7800
```

**Explicación TCPPING**:
- **TCPPING**: Discovery estático de nodos (para entornos sin multicast)
- `initial_hosts`: Lista explícita de nodos del cluster
- `port_range=0`: No buscar en puertos alternativos (exactamente 7800)

**Build Optimizado** (`Dockerfile`):
```dockerfile
FROM quay.io/keycloak/keycloak:26.0.0 AS builder
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
RUN /opt/keycloak/bin/kc.sh build  # Pre-build para arranque rápido

FROM quay.io/keycloak/keycloak:26.0.0
COPY --from=builder /opt/keycloak/ /opt/keycloak/
CMD ["start", "--optimized"]
```

**Health Checks**:
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f -k https://localhost:8443/health/ready || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 120s  # Keycloak tarda ~60-90s en iniciar
```

**Acceso**:
- NODO 1: https://localhost:8443
- NODO 2: https://localhost:8444
- Usuario: `admin` / `admin` (configurable en `.env`)

---

### 6. Infinispan - Distributed Cache (Embebido en Keycloak)

**Propósito**: Replicar sesiones y cachés entre nodos Keycloak.

**Datos Replicados**:
- ✅ Sesiones de usuario activas
- ✅ Tokens (access, refresh, ID, offline)
- ✅ Metadata de cachés
- ✅ Eventos de invalidación

**Protocolo de Comunicación**: **JGroups TCP**
- Puerto: `7800` (expuesto en docker-compose)
- Modo: TCP directo entre nodos (sin multicast)
- Discovery: TCPPING (lista estática de hosts)

**Verificación del Cluster**:
```bash
# Ver logs de formación del cluster
docker logs keycloak-nodo1 2>&1 | grep "cluster view"

# Salida esperada:
# ISPN000094: Received new cluster view for channel ISPN: 
#   [keycloak-nodo1-12345|1] (2) [keycloak-nodo1-12345, keycloak-nodo2-67890]
#                          ^^^     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#                       2 miembros         Lista de miembros
```

**Cachés Distribuidas**:
| Caché | Propósito | Modo |
|-------|-----------|------|
| `sessions` | Sesiones de usuario | Distribuida |
| `clientSessions` | Sesiones de clients OAuth | Distribuida |
| `offlineSessions` | Sesiones offline | Distribuida |
| `loginFailures` | Intentos de login fallidos | Distribuida |
| `work` | Trabajo en background | Distribuida |

---

## ⚙️ Configuraciones Críticas

### 1. Problema Resuelto: HAProxy DNS Resolution

**Síntoma**: 
- Backends PostgreSQL en estado `MAINT` (maintenance)
- Error en logs: `resolution` failure
- Keycloak no puede conectarse a la base de datos

**Causa**:
HAProxy con `init-addr none` sin resolver DNS configurado no puede resolver nombres de contenedores.

**Solución** (ya aplicada en `haproxy/haproxy.cfg`):
```cfg
# Agregar sección de resolver
resolvers docker
    nameserver dns1 127.0.0.11:53
    resolve_retries 3
    timeout resolve 1s
    hold valid 10s

# Actualizar default-server
default-server ... resolvers docker init-addr libc,none
```

### 2. Red Docker Externa

**Propósito**: Permitir comunicación entre servicios de nodo1 y nodo2.

```bash
docker network create keycloak_net
```

**En docker-compose**:
```yaml
networks:
  keycloak_net:
    external: true  # Red ya creada externamente
```

### 3. Certificados TLS Autofirmados

**Generación** (`generate-certs.sh`):
```bash
openssl req -new -x509 \
  -key certs/tls.key \
  -out certs/tls.crt \
  -days 3650 \
  -addext "subjectAltName=DNS:localhost,DNS:keycloak-nodo1,DNS:keycloak-nodo2"
```

**Montaje en Keycloak**:
```yaml
volumes:
  - ./certs/tls.crt:/opt/keycloak/conf/tls.crt:ro
  - ./certs/tls.key:/opt/keycloak/conf/tls.key:ro
```

### 4. Script de Post-Inicialización de Patroni

**Archivo**: `patroni/post_init.sh`

Ejecutado SOLO por el primer nodo que hace bootstrap del cluster.

```bash
# Crear usuarios
CREATE ROLE replicator WITH REPLICATION PASSWORD 'replicator_secret' LOGIN;
CREATE ROLE keycloak WITH SUPERUSER CREATEDB PASSWORD 'keycloak_secret' LOGIN;

# Crear base de datos
CREATE DATABASE keycloak OWNER keycloak;
```

---

## 🔄 Flujos Operacionales

### Flujo 1: Arranque Normal del Sistema

**Orden de Inicio** (gestionado por `deploy-ha.sh`):

```
1. Red Docker (keycloak_net)
   ↓
2. Certificados SSL/TLS
   ↓
3. Build de imágenes (Keycloak, Patroni)
   ↓
4. etcd cluster (nodo1 + nodo2)
   ↓ Espera 10s para sincronización
5. PostgreSQL + Patroni NODO 1
   ↓ Espera hasta healthy (max 90s)
6. PostgreSQL + Patroni NODO 2
   ↓ Espera hasta healthy (max 90s)
7. HAProxy NODO 1 + Keycloak NODO 1
   ↓ Espera 20s
8. HAProxy NODO 2 + Keycloak NODO 2
   ↓ Espera 10s
9. Verificación del despliegue
```

**Tiempo total de arranque**: ~2-3 minutos

### Flujo 2: Request de Usuario a Keycloak

```
1. Usuario navega a https://localhost:8443
   ↓
2. Keycloak procesa request (autenticación, tokens, etc.)
   ↓
3. Keycloak necesita acceder a BD para verificar usuario
   ↓
4. Keycloak → HAProxy (jdbc:postgresql://haproxy-nodo1:5432/keycloak)
   ↓
5. HAProxy consulta Patroni: GET /master
   ├─ postgres-nodo1: HTTP 200 → ES PRIMARY → marcado como UP
   └─ postgres-nodo2: HTTP 503 → NO es PRIMARY → marcado como DOWN
   ↓
6. HAProxy enruta query a postgres-nodo1 (PRIMARY)
   ↓
7. PostgreSQL PRIMARY procesa query
   ↓
8. Resultado → HAProxy → Keycloak → Usuario
```

### Flujo 3: Escritura en PostgreSQL

```
1. Keycloak inserta nuevo usuario
   ↓
2. INSERT ejecutado en PRIMARY (postgres-nodo1)
   ↓
3. PRIMARY escribe cambios en WAL (Write-Ahead Log)
   ↓
4. WAL se transmite vía streaming a REPLICA (postgres-nodo2)
   ↓
5. REPLICA aplica cambios del WAL
   ↓
6. Replicación completada (lag = 0 bytes)
   ↓
7. Ambos nodos tienen datos idénticos
```

### Flujo 4: Replicación de Sesión (Infinispan)

```
1. Usuario hace login en keycloak-nodo1
   ↓
2. Keycloak crea sesión y la almacena localmente
   ↓
3. Infinispan detecta nueva entrada en caché "sessions"
   ↓
4. JGroups propaga cambio a keycloak-nodo2 vía TCP:7800
   ↓
5. keycloak-nodo2 recibe actualización y crea réplica de la sesión
   ↓
6. Usuario hace request a keycloak-nodo2
   ↓
7. keycloak-nodo2 encuentra sesión localmente (replicada)
   ↓
8. Usuario autenticado sin re-login
```

### Flujo 5: Failover Automático (PRIMARY Falla)

**Fase 1: Detección de Fallo** (0-10 segundos)
```
0s:  postgres-nodo1 (PRIMARY) falla/se detiene
     ↓
3s:  Patroni nodo1 pierde conexión con PostgreSQL local
     ↓
6s:  Patroni nodo1 no puede renovar su lease en etcd (TTL=30s)
     ↓
10s: Patroni nodo2 detecta que el leader no renueva su lease
```

**Fase 2: Elección de Nuevo PRIMARY** (10-30 segundos)
```
10s: Patroni nodo2 consulta etcd para consenso del cluster
     ↓
12s: Patroni nodo2 verifica que:
     - Tiene replicación al día (lag < 1MB)
     - No hay split-brain (solo un nodo puede ser PRIMARY)
     ↓
15s: Patroni nodo2 promueve postgres-nodo2 a PRIMARY:
     - Ejecuta: SELECT pg_promote()
     - Actualiza estado en etcd
     ↓
20s: postgres-nodo2 ahora acepta escrituras
     ↓
23s: Patroni actualiza configuración de pg_hba.conf si necesario
```

**Fase 3: HAProxy Detecta Cambio** (30-35 segundos)
```
30s: HAProxy hace health check a postgres-nodo2:8008/master
     ↓
31s: Patroni nodo2 responde HTTP 200 (soy PRIMARY)
     ↓
     HAProxy hace health check a postgres-nodo1:8008/master
     ↓
     Sin respuesta (contenedor detenido)
     ↓
34s: Después de 3 health checks fallidos (fall=3), HAProxy marca:
     - postgres-nodo1: DOWN
     - postgres-nodo2: UP
     ↓
35s: Todo el tráfico ahora va a postgres-nodo2
```

**Fase 4: Keycloak se Reconecta** (35-40 segundos)
```
35s: Conexiones JDBC de Keycloak fallan (PRIMARY anterior caído)
     ↓
36s: Connection pool de Keycloak intenta reconectar
     ↓
37s: Nueva conexión establecida con HAProxy
     ↓
38s: HAProxy enruta a postgres-nodo2 (nuevo PRIMARY)
     ↓
40s: Keycloak operando normalmente
```

**Resultado**:
- ✅ Downtime total: ~35-40 segundos
- ✅ Pérdida de datos: 0 (replicación estaba al día)
- ✅ Sesiones de usuario: conservadas (gracias a Infinispan)
- ✅ Keycloak sigue respondiendo en ambos puertos (8443, 8444)

### Flujo 6: Recuperación del Nodo Antiguo

```
1. Administrador inicia postgres-nodo1 nuevamente
   ↓
2. Patroni nodo1 se inicia y consulta etcd
   ↓
3. Detecta que postgres-nodo2 es el nuevo PRIMARY
   ↓
4. Patroni ejecuta pg_rewind para sincronizar datos:
   - Revierte cambios divergentes (si hay)
   - Se pone al día con el nuevo PRIMARY
   ↓
5. Patroni configura postgres-nodo1 como REPLICA
   ↓
6. Inicia streaming replication desde postgres-nodo2
   ↓
7. postgres-nodo1 ahora es REPLICA del nuevo PRIMARY
   ↓
8. Cluster restaurado con 2 nodos
```

---

## 🔍 Troubleshooting

### Problema 1: Keycloak no Inicia (Crash Loop)

**Síntomas**:
```bash
docker ps  # keycloak-nodo2 en estado "Restarting"
docker logs keycloak-nodo2  # ERROR: Failed to obtain JDBC connection
```

**Causa Raíz**: HAProxy no puede enrutar a PostgreSQL PRIMARY.

**Diagnóstico**:
```bash
# 1. Verificar backends de HAProxy
docker exec haproxy-nodo1 wget -O- -q http://127.0.0.1:7000 | grep postgres

# Buscar: <td class=ac>8m38s MAINT</td>  ← MAL (maintenance)
# Buscar: <td class=ac>8m38s UP</td>     ← BIEN

# Si backends en MAINT, verificar resolución DNS
docker exec haproxy-nodo1 nslookup postgres-nodo1  # Debe resolver a IP

# 2. Verificar Patroni responde
docker exec postgres-nodo1 curl -i http://localhost:8008/master
# Debe responder HTTP 200 si es PRIMARY, 503 si no
```

**Solución**: Ver sección "Configuraciones Críticas #1" (ya resuelto con DNS resolver).

### Problema 2: Cluster Infinispan con 1 Solo Miembro

**Síntomas**:
```bash
docker logs keycloak-nodo1 | grep "cluster view"
# ISPN000094: ... (1) [keycloak-nodo1-12345]  ← Solo 1 miembro
```

**Posibles Causas**:
1. **Puerto 7800 no expuesto**: Verificar docker-compose tiene `ports: - "7800:7800"`
2. **Firewall bloqueando**: En entornos cloud/VM
3. **Configuración JGroups incorrecta**: TCPPING mal configurado
4. **Nodos iniciaron en momentos muy diferentes**: Reiniciar ambos

**Diagnóstico**:
```bash
# Verificar puerto expuesto
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep keycloak

# Debe mostrar: 0.0.0.0:7800->7800/tcp

# Verificar conectividad entre nodos
docker exec keycloak-nodo1 ping -c 2 keycloak-nodo2  # Debe responder

# Ver logs de JGroups
docker logs keycloak-nodo1 2>&1 | grep -i jgroups
```

**Solución**:
```bash
# Reiniciar ambos nodos Keycloak
docker restart keycloak-nodo1 keycloak-nodo2

# Esperar 60 segundos y verificar
docker logs keycloak-nodo2 2>&1 | grep "cluster view" | tail -1
# Debe mostrar (2) miembros
```

### Problema 3: Lag de Replicación PostgreSQL

**Síntomas**:
```bash
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list
# | postgres-nodo2 | ... | Replica | running | 1 |  5120  |  ← Lag en MB
```

**Diagnóstico**:
```sql
-- En PRIMARY
docker exec postgres-nodo1 psql -U postgres -c \
  "SELECT application_name, state, sync_state,
          pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
   FROM pg_stat_replication;"
```

**Causas Comunes**:
- RED lenta entre nodos
- REPLICA sobrecargada (I/O disk)
- PRIMARY generando WAL muy rápido (writes masivos)

**Solución**:
```bash
# 1. Verificar conectividad de red
docker exec postgres-nodo1 ping -c 10 postgres-nodo2

# 2. Verificar uso de disco en REPLICA
docker exec postgres-nodo2 df -h /home/postgres/pgdata

# 3. Si lag es persistente, considerar replicación síncrona
# Editar patroni/patroni-nodo1.yml:
synchronous_mode: true
synchronous_commit: on
```

### Problema 4: Tests Fallan con "No se Encontró Información"

**Tests con Advertencias Inocuas**:
- ⚠️ "No se encontraron logs de cachés distribuidas"
- ⚠️ "Sin conectividad" (ping no instalado en contenedores slim)
- ⚠️ "Puerto 7800 no detectado" (netstat/ss no disponible)

**Estas advertencias son normales** si:
- ✅ Cluster Infinispan tiene **2 miembros**
- ✅ Endpoints Keycloak responden **HTTP 200**
- ✅ Tests de sincronización y routing **pasan**

**No requieren acción**.

### Problema 5: Failover No Ocurre Automáticamente

**Síntomas**:
```bash
docker stop postgres-nodo1  # Simular fallo
sleep 60
docker exec postgres-nodo2 patronictl -c /etc/patroni/patroni.yml list
# postgres-nodo2 sigue siendo "Replica" (no promovido)
```

**Diagnóstico**:
```bash
# 1. Verificar etcd está operativo
docker exec etcd-nodo2 etcdctl endpoint health

# 2. Ver logs de Patroni
docker logs postgres-nodo2 --tail 50 | grep -i failover

# 3. Verificar configuración de failover
docker exec postgres-nodo2 cat /etc/patroni/patroni.yml | grep -A3 tags
# Debe mostrar: nofailover: false
```

**Causas Comunes**:
- `nofailover: true` en configuración (error de config)
- etcd no responde (cluster sin consenso)
- Lag de replicación > `maximum_lag_on_failover` (1MB)

---

## 📚 Referencias Rápidas

### Comandos de Administración

```bash
# ============================================================================
# PATRONI - Gestión del Cluster PostgreSQL
# ============================================================================

# Ver estado del cluster
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list

# Switchover manual (cambiar PRIMARY)
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml switchover \
  --master postgres-nodo1 --candidate postgres-nodo2

# Reiniciar un nodo (sin afectar PostgreSQL)
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml restart postgres-nodo1

# Recargar configuración de Patroni
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml reload postgres-nodo1

# Ver configuración DCS (stored in etcd)
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml show-config

# ============================================================================
# POSTGRESQL - Queries de Diagnóstico
# ============================================================================

# Verificar replicación (ejecutar en PRIMARY)
docker exec postgres-nodo1 psql -U postgres -c \
  "SELECT application_name, client_addr, state, sync_state,
          pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
   FROM pg_stat_replication;"

# Ver lag en REPLICA (ejecutar en REPLICA)
docker exec postgres-nodo2 psql -U postgres -c \
  "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"

# Conectarse a base de datos Keycloak
docker exec -it postgres-nodo1 psql -U keycloak -d keycloak

# Ver tamaño de la BD
docker exec postgres-nodo1 psql -U keycloak -d keycloak -c \
  "SELECT pg_size_pretty(pg_database_size('keycloak'));"

# ============================================================================
# HAPROXY - Monitoreo
# ============================================================================

# Ver stats web (navegador)
curl http://localhost:7000

# Ver estado de un backend específico
docker exec haproxy-nodo1 sh -c \
  "echo 'show stat' | socat stdio /var/run/haproxy.sock" 2>/dev/null | \
  grep postgres

# Recargar configuración (sin downtime)
docker exec haproxy-nodo1 kill -HUP 1

# ============================================================================
# KEYCLOAK - Verificación
# ============================================================================

# Verificar que Keycloak responde
curl -k https://localhost:8443/realms/master

# Ver logs de Keycloak
docker logs keycloak-nodo1 --tail 100 -f

# Ver formación de cluster Infinispan
docker logs keycloak-nodo1 2>&1 | grep "cluster view"

# Ver uso de memoria JVM
docker exec keycloak-nodo1 sh -c \
  "jcmd 1 VM.native_memory summary" 2>/dev/null

# ============================================================================
# ETCD - Diagnóstico
# ============================================================================

# Ver miembros del cluster etcd
docker exec etcd-nodo1 etcdctl member list

# Health check
docker exec etcd-nodo1 etcdctl endpoint health

# Ver keys de Patroni en etcd
docker exec etcd-nodo1 etcdctl get --prefix "/db/"

# ============================================================================
# DOCKER - Gestión de Contenedores
# ============================================================================

# Ver estado de todos los contenedores
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Ver uso de recursos
docker stats --no-stream

# Limpiar volúmenes (DESTRUYE DATOS)
docker compose -p nodo1 -f docker-compose-nodo1.yaml down -v
docker compose -p nodo2 -f docker-compose-nodo2.yaml down -v
docker volume prune -f

# ============================================================================
# TESTS - Verificación del Sistema
# ============================================================================

# Ejecutar todos los tests
./tests/run-all-tests.sh

# Tests individuales
./tests/test-sync.sh        # Replicación PostgreSQL
./tests/test-routing.sh     # HAProxy routing
./tests/test-infinispan.sh  # Cluster Keycloak
./test-failover.sh          # Failover automático (destructivo, 90s)
```

### Puertos del Sistema

| Servicio | Puerto Host | Puerto Container | Propósito |
|----------|-------------|------------------|-----------|
| **Keycloak NODO 1** | 8443 | 8443 | HTTPS web UI |
| **Keycloak NODO 2** | 8444 | 8443 | HTTPS web UI |
| **JGroups NODO 1** | 7800 | 7800 | Clustering Infinispan |
| **JGroups NODO 2** | 7801 | 7800 | Clustering Infinispan |
| **HAProxy Stats** | 7000 | 7000 | Web UI de estadísticas |
| **HAProxy Primary** | N/A | 5432 | Routing a PostgreSQL PRIMARY (interno) |
| **Patroni API** | N/A | 8008 | REST API para health checks (interno) |
| **PostgreSQL** | N/A | 5432 | Base de datos (interno) |
| **etcd Client** | N/A | 2379 | Cliente etcd (interno) |
| **etcd Peer** | N/A | 2380 | Comunicación entre nodos etcd (interno) |

### Variables de Entorno Clave

**Archivo**: `.env` (copiar de `.env.example`)

```bash
# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin

# PostgreSQL
POSTGRES_PASSWORD=keycloak_secret           # Usuario keycloak
POSTGRES_ADMIN_PASSWORD=postgres_admin      # Usuario postgres
REPLICATION_PASSWORD=replicator_secret      # Usuario replicator

# Logging
KC_LOG_LEVEL=info  # debug, info, warn, error
```

### Estructura de Archivos

```
keycloak_HA/
├── docker-compose-nodo1.yaml      # Servicios del Nodo 1
├── docker-compose-nodo2.yaml      # Servicios del Nodo 2
├── Dockerfile                     # Keycloak optimizado
├── Dockerfile.patroni             # PostgreSQL + Patroni
├── deploy-ha.sh                   # Script de despliegue automatizado
├── generate-certs.sh              # Generador de certificados
├── test-failover.sh               # Test de failover
├── .env.example                   # Plantilla de variables de entorno
├── README.md                      # Documentación de usuario
├── SYSTEM_CONTEXT.md              # Este archivo (contexto técnico)
│
├── certs/                         # Certificados SSL/TLS
│   ├── tls.crt
│   └── tls.key
│
├── haproxy/                       # Configuración HAProxy
│   └── haproxy.cfg               # Config con DNS resolver
│
├── patroni/                       # Configuración Patroni
│   ├── patroni-nodo1.yml         # Config nodo 1 (inicial PRIMARY)
│   ├── patroni-nodo2.yml         # Config nodo 2 (inicial REPLICA)
│   └── post_init.sh              # Script post-bootstrap (crea users/DB)
│
└── tests/                         # Suite de tests
    ├── run-all-tests.sh          # Ejecuta todos los tests
    ├── test-sync.sh              # Replicación PostgreSQL
    ├── test-routing.sh           # HAProxy routing
    └── test-infinispan.sh        # Cluster Infinispan
```

---

## 🎯 Checklist de Sistema Saludable

```
✅ etcd Cluster
   □ 2 nodos reportando healthy
   □ Consenso establecido (member list)

✅ PostgreSQL + Patroni
   □ 1 nodo en rol "Leader" (PRIMARY)
   □ 1 nodo en rol "Replica" (REPLICA)
   □ State: "running" en ambos
   □ Lag en MB: 0 (o muy cercano a 0)
   □ Streaming replication: state="streaming"

✅ HAProxy
   □ Backend postgres_primary: 1 servidor UP (el PRIMARY)
   □ Backend postgres_primary: 1 servidor DOWN (la REPLICA)
   □ Stats accesible en http://localhost:7000

✅ Keycloak
   □ Ambos nodos respondiendo HTTP 200 en /realms/master
   □ Cluster Infinispan formado con 2 miembros
   □ Login funcional en ambos puertos (8443, 8444)

✅ Tests
   □ test-sync.sh: EXITOSO
   □ test-routing.sh: EXITOSO
   □ test-infinispan.sh: EXITOSO (ignorar advertencias de ping/netstat)
   □ test-failover.sh: EXITOSO (failover < 40s, 0 data loss)
```

---

## 📖 Glosario

| Término | Definición |
|---------|------------|
| **PRIMARY** | Nodo PostgreSQL que acepta escrituras (Leader en Patroni) |
| **REPLICA** | Nodo PostgreSQL en modo standby, solo lecturas |
| **Streaming Replication** | Replicación continua de WAL de PRIMARY a REPLICA |
| **WAL** | Write-Ahead Log, registro de transacciones de PostgreSQL |
| **Failover** | Proceso de promover REPLICA a PRIMARY cuando PRIMARY falla |
| **Switchover** | Cambio planeado de PRIMARY (sin fallo) |
| **Split-brain** | Situación donde 2 nodos piensan que son PRIMARY (BAD) |
| **Consensus** | Acuerdo distribuido sobre el estado del cluster (etcd/Raft) |
| **DCS** | Distributed Configuration Store (etcd en este caso) |
| **TTL** | Time To Live, tiempo antes de considerar un nodo muerto |
| **Lag** | Retraso de replicación entre PRIMARY y REPLICA |
| **pg_rewind** | Herramienta para resincronizar nodo divergente |
| **TCPPING** | Protocolo de discovery de JGroups (lista estática de hosts) |
| **Infinispan** | Caché distribuida embebida en Keycloak |
| **JGroups** | Framework de comunicación de cluster en Java |
| **Health Check** | Verificación periódica de estado de un servicio |

---

## 🔐 Seguridad (Consideraciones para Producción)

**ADVERTENCIA**: Este setup es para **desarrollo/testing**. Para producción:

1. **Cambiar todas las contraseñas** en `.env`
2. **Usar certificados válidos** (Let's Encrypt, CA corporativa)
3. **Habilitar firewall** y limitar puertos expuestos
4. **Configurar replicación síncrona** para garantizar zero data loss:
   ```yaml
   # patroni/patroni-nodoX.yml
   bootstrap:
     dcs:
       synchronous_mode: true
       synchronous_commit: on
   ```
5. **Implementar backups** automatizados de PostgreSQL
6. **Monitoreo y alertas** (Prometheus, Grafana, Alertmanager)
7. **Usar volúmenes persistentes** (no `driver: local` en producción)
8. **Considerar pgpool** para balanceo de lecturas entre nodos
9. **Revisar permisos** de `pg_hba.conf` (actualmente acepta cualquier IP)

---

**Documento Creado**: 2026-02-16  
**Versión del Sistema**: Keycloak 26.0.0, PostgreSQL 15, Patroni 3.2.2  
**Autor**: Contexto generado automáticamente del deployment

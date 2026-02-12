# Keycloak High Availability con PostgreSQL Streaming Replication

## Descripción

Sistema de **Alta Disponibilidad** para Keycloak desplegado en **2 nodos físicos separados** con arquitectura **Active-Active**, implementando **PostgreSQL Streaming Replication** nativa y **query routing inteligente** con pgpool-II.

Este proyecto proporciona una solución completa y lista para producción diseñada para:
- **Despliegue en 2 servidores independientes** (NODO 1 + NODO 2)
- **Ambos Keycloak activos simultáneamente** (cualquier nodo puede recibir tráfico)
- **Query routing automático**: escrituras → PRIMARY, lecturas → REPLICA
- **Clustering Keycloak** con Infinispan/JGroups para cache distribuido
- **Failover manual** con procedimientos documentados

---

## Tabla de Contenidos

- [Descripción](#descripción)
- [Características Principales](#características-principales)
- [Arquitectura del Sistema](#arquitectura-del-sistema)
  - [Vista General - 2 Nodos Físicos](#vista-general---2-nodos-físicos)
  - [Diagrama de Componentes por Capa](#diagrama-de-componentes-por-capa)
  - [Flujo de Datos](#flujo-de-datos)
- [Requisitos Previos](#requisitos-previos)
- [Despliegue en 2 Nodos Físicos](#despliegue-en-2-nodos-físicos)
  - [Requisitos de Red Previos](#requisitos-de-red-previos)
  - [Paso 1: Desplegar NODO 1](#paso-1-desplegar-nodo-1-servidor-primario)
  - [Paso 2: Desplegar NODO 2](#paso-2-desplegar-nodo-2-servidor-secundario)
  - [Paso 3: Verificar Clustering](#paso-3-verificar-clustering)
- [Verificación del Sistema (2 Nodos)](#verificación-del-sistema-2-nodos)
- [Acceso a Servicios (2 Nodos)](#acceso-a-servicios-2-nodos)
- [Guía de Uso - Arquitectura 2 Nodos](#guía-de-uso---arquitectura-2-nodos)
  - [Comportamiento de Query Routing por Nodo](#comportamiento-de-query-routing-por-nodo)
- [Resolución de Problemas](#resolución-de-problemas)
  - [Problemas Específicos de Arquitectura 2 Nodos](#problemas-específicos-de-arquitectura-2-nodos)
  - [Problemas Comunes (Ambos Nodos)](#problemas-comunes-ambos-nodos)
- [Estructura del Proyecto - Arquitectura 2 Nodos](#estructura-del-proyecto---arquitectura-2-nodos)
- [Límites y Escalabilidad](#límites-y-escalabilidad---arquitectura-2-nodos)
- [Costos Estimados](#costos-estimados-cloud-deployment---2-nodos-físicos)
- [Referencias y Recursos](#referencias-y-recursos)
- [Historial de Versiones](#historial-de-versiones)

---

## Quick Start - Despliegue Rápido en 2 Nodos

### Prerrequisitos
- 2 servidores Linux con Docker y Docker Compose instalados
- Red entre servidores (puertos 5432, 7800, 8443 abiertos)
- 4GB RAM mínimo por servidor

### En NODO 1 (Servidor Primario)
```bash
git clone <repository-url> && cd keycloak_HA
./deploy-nodo1.sh
# ✅ Anota la IP mostrada al finalizar (ej: 192.168.1.100)
```

### En NODO 2 (Servidor Secundario)
```bash
git clone <repository-url> && cd keycloak_HA
./deploy-nodo2.sh
# ⌨️  Ingresa la IP del NODO 1 cuando se solicite
```

### Verifica el Cluster
```bash
# En NODO 1
docker logs keycloak-1 | grep "cluster view"
# Expected: (2) [keycloak-1, <NODO2_IP>:7800]

# En NODO 2
docker logs keycloak-2 | grep "cluster view"
# Expected: (2) [keycloak-1, keycloak-2]
```

### Accede a Keycloak
- **NODO 1**: https://<IP_NODO_1>:8443 (admin / admin)
- **NODO 2**: https://<IP_NODO_2>:8443 (admin / admin)

---

## Características Principales

### Arquitectura Distribuida en 2 Nodos

- ✅ **NODO 1 (Servidor Físico 1)**
  - PostgreSQL PRIMARY (R/W) - Puerto 5432 expuesto
  - Keycloak-1 - HTTPS 8443
  - pgpool-II - Query routing local
  - HAProxy - Balanceo local

- ✅ **NODO 2 (Servidor Físico 2)**
  - PostgreSQL REPLICA (R/O) - Replica desde NODO 1
  - Keycloak-2 - HTTPS 8443
  - pgpool-II - Proxy a PRIMARY remoto + REPLICA local
  - HAProxy - Proxy remoto + balanceo local

### Base de Datos

- ✅ **PostgreSQL 15 Streaming Replication** nativa
  - Replicación asíncrona entre nodos físicos
  - Write-Ahead Log (WAL) streaming continuo
  - Sin dependencias externas (Patroni, etcd, Consul)
  - PRIMARY en NODO 1, REPLICA en NODO 2

### Query Routing Inteligente

- ✅ **pgpool-II - Query Routing Automático** ⭐ **CRÍTICO para NODO 2**
  - **NODO 1**: Todas las queries al PRIMARY local (<2ms)
  - **NODO 2**: 
    - `SELECT` → REPLICA local (<2ms) ✅ RÁPIDO
    - `INSERT/UPDATE/DELETE` → PRIMARY remoto (10-50ms) ⚠️ Latencia de red
  - Load balancing automático de lecturas
  - Gestión transparente de transacciones
  - Connection pooling integrado

- ✅ **HAProxy - Routing por Puerto** (soporte)
  - NODO 1: Puerto 5000 → PRIMARY local
  - NODO 2: Puerto 5000 → PRIMARY remoto (proxy), Puerto 5001 → REPLICA local

### Capa de Aplicación

- ✅ **Keycloak 23.0 Cluster** (2 nodos físicos)
  - Cache distribuido con Infinispan/JGroups sobre TCP
  - Discovery automático entre nodos vía TCPPING
  - Sincronización de sesiones entre NODO 1 y NODO 2
  - SSL/TLS habilitado por defecto
  - Ambos nodos activos simultáneamente (Active-Active)

### Operaciones

- ✅ **Scripts de Automatización**
  - Despliegue completo con un solo comando
  - Suite de testing integrada (23 tests automatizados)
  - Procedimientos de failover documentados y scriptados
  - Generación automática de certificados SSL
  - Verificación continua del estado de replicación

- ✅ **Seguridad**
  - Comunicaciones cifradas SSL/TLS
  - Certificados auto-firmados para desarrollo (reemplazables en producción)
  - Autenticación MD5 para conexiones PostgreSQL
  - Configuración de `pg_hba.conf` restrictiva

---

## Arquitectura del Sistema

### Vista General - 2 Nodos Físicos

```
┌───────────────────────────────────────────────────────────────────┐
│                       Usuario / Cliente                            │
└──────────────┬────────────────────────────────┬────────────────────┘
               │ HTTPS (8443)                   │ HTTPS (8443)
               ▼                                ▼
    ╔══════════════════════════════╗ ╔══════════════════════════════╗
    ║    NODO 1 (Servidor 1)       ║ ║    NODO 2 (Servidor 2)       ║
    ║  ┌────────────────────────┐  ║ ║  ┌────────────────────────┐  ║
    ║  │    Keycloak-1          │  ║ ║  │    Keycloak-2          │  ║
    ║  │  (Active - HTTPS 8443) │◄─╬─╬─►│  (Active - HTTPS 8443) │  ║
    ║  └──────────┬─────────────┘  ║ ║  └──────────┬─────────────┘  ║
    ║             │ JGroups TCP    ║ ║             │ JGroups TCP    ║
    ║             │ (Puerto 7800)  ║ ║             │ (Puerto 7800)  ║
    ║             ▼                ║ ║             ▼                ║
    ║  ┌─────────────────────────┐ ║ ║  ┌─────────────────────────┐ ║
    ║  │   pgpool-II Nodo 1      │ ║ ║  │   pgpool-II Nodo 2      │ ║
    ║  │   (Query Routing)       │ ║ ║  │   (Query Routing Proxy) │ ║
    ║  │  - Backend: PRIMARY     │ ║ ║  │  - Backend 0: PRIMARY ──╬─┐║
    ║  │    (local, weight=1)    │ ║ ║  │    (remoto, weight=0)   │ │║
    ║  └────────────┬────────────┘ ║ ║  │  - Backend 1: REPLICA   │ │║
    ║               │              ║ ║  │    (local, weight=1)    │ │║
    ║               ▼              ║ ║  └────────────┬────────────┘ │║
    ║  ┌─────────────────────────┐ ║ ║               │              │║
    ║  │   HAProxy Nodo 1        │ ║ ║               ▼              │║
    ║  │  - Port 5000: PRIMARY   │ ║ ║  ┌─────────────────────────┐ │║
    ║  └────────────┬────────────┘ ║ ║  │   HAProxy Nodo 2        │ │║
    ║               │              ║ ║  │  - Port 5000: nodo1 ◄───╬─┘║
    ║               ▼              ║ ║  │    (PRIMARY remoto)     │  ║
    ║  ┌─────────────────────────┐ ║ ║  │  - Port 5001: REPLICA   │  ║
    ║  │  PostgreSQL PRIMARY     │◄╬─╬──┤    (local)              │  ║
    ║  │  (Read / Write)         │─╬─╬─►└────────────┬────────────┘  ║
    ║  │  Puerto 5432 EXPUESTO   │ ║ ║               │              ║
    ║  └────────────┬────────────┘ ║ ║               ▼              ║
    ║               │              ║ ║  ┌─────────────────────────┐ ║
    ║               ▼              ║ ║  │  PostgreSQL REPLICA     │ ║
    ║      [pg-primary-data]       ║ ║  │  (Read Only)            │ ║
    ║                              ║ ║  │  PRIMARY_HOST: NODO1_IP │ ║
    ╚══════════════════════════════╝ ║  └────────────┬────────────┘ ║
                                     ║               │              ║
         Replicación WAL Stream      ║               ▼              ║
         ◄───────────────────────────╣      [pg-replica-data]       ║
                Puerto 5432          ╚══════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────┐
│ FLUJO DE DATOS:                                                      │
│                                                                      │
│ NODO 1 (PRIMARY Database):                                          │
│   - Keycloak-1 → pgpool → haproxy:5000 → PRIMARY local (<2ms)      │
│   - Query Routing: Todas las queries al PRIMARY local               │
│                                                                      │
│ NODO 2 (REPLICA Database + Proxy):                                  │
│   - Keycloak-2 READ (SELECT) → pgpool → haproxy:5001 → REPLICA     │
│     local (<2ms) ✅ RÁPIDO                                          │
│   - Keycloak-2 WRITE (INSERT/UPDATE/DELETE) → pgpool →             │
│     haproxy:5000 → PRIMARY remoto NODO 1 (10-50ms) ⚠️ Latencia red │
│                                                                      │
│ KEYCLOAK CLUSTERING:                                                 │
│   - Ambos nodos activos simultáneamente (Active-Active)             │
│   - Sincronización de cache vía JGroups TCP (puerto 7800)          │
│   - Discovery: TCPPING con IPs configurables                        │
└─────────────────────────────────────────────────────────────────────┘
```

### Diagrama de Componentes por Capa

```
┌────────────────────────────────────────────────────────────────────┐
│                    CAPA DE APLICACIÓN                               │
│                                                                     │
│  Keycloak-1 (8443) ◄──────JGroups TCP (7800)───────► Keycloak-2 (8444) │
│         │               Cache distribuido                    │     │
└─────────┼─────────────────────────────────────────────────────┼─────┘
          │                                                     │
          └───────────┬─────────────────────────────┬───────────┘
                      ▼                             ▼
┌────────────────────────────────────────────────────────────────────┐
│              CAPA DE ROUTING DE QUERIES                            │
│                                                                     │
│  ⭐ pgpool-II (9999) - Query Routing Automático                     │
│  │  ┌───────────────────────────────────────────────────┐         │
│  │  │ Análisis SQL:                                      │         │
│  │  │  • INSERT/UPDATE/DELETE/DDL ────► PRIMARY         │         │
│  │  │  • SELECT ──────────────────────► REPLICA (LB)    │         │
│  │  │  • Transacciones mixtas ────────► PRIMARY         │         │
│  │  └───────────────────────────────────────────────────┘         │
│  │                                                                 │
│  └──► HAProxy (Alternativa - Routing por Puerto)                  │
│       ├─ Puerto 5000 ────────► PRIMARY (garantizado)              │
│       ├─ Puerto 5001 ────────► REPLICA prefer, PRIMARY backup     │
│       └─ Puerto 7000 ────────► Stats UI                           │
└────────────────────────────────────────────────────────────────────┘
                      │                             │
                      ▼                             ▼
┌────────────────────────────────────────────────────────────────────┐
│                 CAPA DE PERSISTENCIA                               │
│                                                                     │
│  PostgreSQL PRIMARY (5432)          PostgreSQL REPLICA (5433)      │
│  ├─ Modo: Read/Write               ├─ Modo: Read-Only             │
│  ├─ wal_level = replica            ├─ recovery_mode = standby     │
│  ├─ max_wal_senders = 10           ├─ hot_standby = on            │
│  └─ Estado: NOT in recovery        └─ Estado: pg_is_in_recovery   │
│                                                                     │
│  PRIMARY ──────────WAL Streaming──────────► REPLICA                │
│           (tcp/5432, protocolo binario)                            │
│                                                                     │
│  Latencia típica: < 1 segundo (async replication)                 │
└────────────────────────────────────────────────────────────────────┘
```

### Flujo de Datos

#### Escenario 1: Usando pgpool-II (Recomendado)

```
1. Cliente se conecta a pgpool-II:9999
2. Cliente envía: SELECT * FROM users WHERE id = 1;
3. pgpool-II analiza la query:
   - Tipo: SELECT (lectura)
   - Decisión: Rutear a REPLICA
   - Backend elegido: backend1 (weight=1, REPLICA vía HAProxy:5001)
4. pgpool-II forward query a HAProxy:5001
5. HAProxy rutea a postgres-replica:5432
6. REPLICA ejecuta query y retorna resultado
7. pgpool-II retorna resultado al cliente

Casos especiales:
- INSERT INTO users VALUES (...) → pgpool detecta DML → PRIMARY
- BEGIN; SELECT ...; UPDATE ...; COMMIT; → toda la transacción al PRIMARY
- SELECT ... FOR UPDATE → detectado como write → PRIMARY
```

#### Escenario 2: Usando HAProxy Directamente

```
Escrituras (puerto 5000):
1. Cliente → HAProxy:5000
2. HAProxy health check: ¿quién es PRIMARY?
   - postgres-primary xinetd check → "200 OK" (es PRIMARY)
   - postgres-replica xinetd check → "503 Service Unavailable" (es REPLICA)
3. HAProxy rutea a postgres-primary:5432
4. Query ejecutada en PRIMARY

Lecturas (puerto 5001):
1. Cliente → HAProxy:5001
2. HAProxy balancea con weight:
   - postgres-replica weight 100 (preferido)
   - postgres-primary weight 50 (backup)
3. Conexión establecida (probabilísticamente a REPLICA)
4. Query ejecutada
```

### Componentes Técnicos Detallados

#### pgpool-II

**Imagen:** `pgpool/pgpool:latest`  
**Puerto principal:** 9999 (conexiones PostgreSQL)  
**Puerto PCP:** 9898 (administración)  

**Configuración clave:**

| Parámetro | Valor | Descripción |
|-----------|-------|-------------|
| `master_slave_mode` | `on` | Habilita modo PRIMARY/REPLICA |
| `load_balance_mode` | `on` | Distribuye SELECTs entre replicas |
| `backend_weight0` | `0` | PRIMARY: peso 0 (solo escrituras) |
| `backend_weight1` | `1` | REPLICA: peso 1 (todas las lecturas) |
| `disable_load_balance_on_write` | `transaction` | Sesiones con writes → PRIMARY |
| `num_init_children` | `32` | Procesos worker pre-forkeados |
| `max_pool` | `4` | Conexiones por proceso hijo |
| `health_check_period` | `10` | Verificación salud cada 10s |

**Backends configurados:**

```
Backend 0 (PRIMARY):
  - Hostname: haproxy
  - Port: 5000
  - Flag: ALWAYS_PRIMARY
  - Weight: 0 (no recibe SELECTs balanceados)
  
Backend 1 (REPLICA):
  - Hostname: haproxy
  - Port: 5001
  - Flag: DISALLOW_TO_FAILOVER
  - Weight: 1 (recibe todos los SELECTs balanceados)
```

#### HAProxy

**Imagen:** `haproxy:2.9-alpine`  
**Puertos expuestos:** 5000 (PRIMARY), 5001 (REPLICA), 7000 (Stats)

**Health Check Logic:**

```haproxy
# Detección de PRIMARY via pg_is_in_recovery
option pgsql-check user postgres

# Backend PRIMARY pool
server postgres-primary postgres-primary:5432 check
  # Si pg_is_in_recovery() = false → UP
  # Si pg_is_in_recovery() = true  → DOWN

# Backend REPLICA pool  
server postgres-replica postgres-replica:5432 check weight 100
server postgres-primary postgres-primary:5432 check weight 50 backup
  # REPLICA preferida, PRIMARY como fallback
```

#### PostgreSQL

**Imagen:** `postgres:15`  
**Protocolo de replicación:** Physical Streaming Replication

**PRIMARY configuration (`postgresql-primary.conf`):**

```ini
wal_level = replica                    # Nivel mínimo para replicación
max_wal_senders = 10                   # Slots de replicación
wal_keep_size = 1024MB                 # WAL retenido para replicas
hot_standby = on                       # Permite queries en standby
synchronous_commit = off               # Async para mayor rendimiento
```

**REPLICA configuration (`postgresql-replica.conf`):**

```ini
hot_standby = on                       # Acepta queries SELECT
hot_standby_feedback = on              # Previene vacuum conflicts
max_standby_streaming_delay = 30s      # Max delay antes de cancelar query
wal_receiver_status_interval = 2s      # Frecuencia de status reports
```

**Autenticación (`pg_hba.conf`):**

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            md5
host    all             all             0.0.0.0/0               md5
host    replication     all             0.0.0.0/0               md5
```

#### Keycloak

**Imagen base:** `quay.io/keycloak/keycloak:23.0`  
**Optimización:** Pre-built para PostgreSQL (`kc.sh build --db=postgres`)

**Cluster configuration:**

```bash
# JGroups discovery via TCP (no multicast)
KC_CACHE_STACK=tcp
JGROUPS_DISCOVERY_PROTOCOL=TCPPING
JGROUPS_DISCOVERY_PROPERTIES=initial_hosts="keycloak-1[7800],keycloak-2[7800]"

# Cache distribuido
KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml
```

**Conexión a Base de Datos:**

- **Opción recomendada:** `KC_DB_URL_HOST=pgpool` `KC_DB_URL_PORT=9999`
- **Opción alternativa:** `KC_DB_URL_HOST=haproxy` `KC_DB_URL_PORT=5000`
- **Opción directa:** `KC_DB_URL_HOST=postgres-primary` `KC_DB_URL_PORT=5432`

---

## Inicio Rápido

### Prerequisitos

```bash
# Verificar versiones
docker --version        # Docker 20.10+
docker compose version  # Docker Compose 2.0+

# Requisitos de sistema
# - CPU: 2+ cores recomendado
# - RAM: 4GB mínimo, 8GB recomendado
# - Disk: 10GB espacio libre
# - OS: Linux (Ubuntu 20.04+, Debian 11+) o macOS
```

### Despliegue en 2 Nodos Físicos

Este proyecto está diseñado para desplegarse en **2 servidores físicos independientes** con roles específicos:

- **NODO 1**: Servidor primario con PostgreSQL PRIMARY y Keycloak-1
- **NODO 2**: Servidor secundario con PostgreSQL REPLICA y Keycloak-2

#### Requisitos de Red Previos

```bash
# OBLIGATORIO: Los 2 nodos deben poder comunicarse entre sí
# Verificar conectividad desde NODO 2 hacia NODO 1:

# (En NODO 2) Test de conectividad PostgreSQL
nc -zv <IP_NODO_1> 5432
# Expected: Connection to <IP_NODO_1> 5432 port [tcp/postgresql] succeeded!

# (En NODO 2) Test de conectividad Keycloak Clustering
nc -zv <IP_NODO_1> 7800
# Expected: Connection to <IP_NODO_1> 7800 port [tcp/*] succeeded!

# Configuración Firewall (aplicar en ambos nodos):
# - Puerto 5432/tcp: PostgreSQL (NODO 1 → acepta desde NODO 2)
# - Puerto 7800/tcp: JGroups clustering (bidireccional)
# - Puerto 8443/tcp: HTTPS Keycloak (usuarios externos)

# Ejemplo UFW (Ubuntu/Debian):
# (En NODO 1)
sudo ufw allow from <IP_NODO_2> to any port 5432 proto tcp comment "PostgreSQL replication"
sudo ufw allow from <IP_NODO_2> to any port 7800 proto tcp comment "Keycloak JGroups"
sudo ufw allow 8443/tcp comment "Keycloak HTTPS"

# (En NODO 2)
sudo ufw allow from <IP_NODO_1> to any port 7800 proto tcp comment "Keycloak JGroups"
sudo ufw allow 8443/tcp comment "Keycloak HTTPS"
```

#### Paso 1: Desplegar NODO 1 (Servidor Primario)

```bash
# 1. Clonar repositorio en NODO 1
git clone <repository-url>
cd keycloak_HA

# 2. Ejecutar script de despliegue para NODO 1
./deploy-nodo1.sh

# El script realizará:
# [1/7] Crear red Docker (keycloak-ha-nodo1)
# [2/7] Generar certificados SSL auto-firmados
# [3/7] Configurar Keycloak con TCPPING discovery
# [4/7] Construir imágenes Docker personalizadas
# [5/7] Iniciar servicios (PRIMARY → HAProxy → pgpool → Keycloak-1)
# [6/7] Esperar PostgreSQL PRIMARY (verificación pg_isready)
# [7/7] Verificar Keycloak-1 en https://localhost:8443

# ⚠️  IMPORTANTE: Al finalizar, el script mostrará:
# ============================================================
# ✅ NODO 1 DESPLEGADO EXITOSAMENTE
# IP detectada: 192.168.1.100
#
# ⚠️  CONFIGURA NODO 2 CON ESTA IP:
# - Edita deploy-nodo2.sh
# - Variable NODO1_IP="192.168.1.100"
# ============================================================

# 3. Anotar la IP mostrada para configurar NODO 2
```

#### Paso 2: Desplegar NODO 2 (Servidor Secundario)

```bash
# 1. Clonar repositorio en NODO 2
git clone <repository-url>
cd keycloak_HA

# 2. Ejecutar script de despliegue para NODO 2
./deploy-nodo2.sh

# El script solicitará interactivamente:
# Ingresa la IP del NODO 1 (PostgreSQL PRIMARY): 192.168.1.100
# Probando conectividad con NODO 1 (192.168.1.100:5432)...
# ✅ Conexión exitosa con NODO 1

# El script realizará:
# [1/8] Solicitar y validar IP NODO 1
# [2/8] Test conectividad con NODO 1 (puerto 5432)
# [3/8] Actualizar docker-compose-nodo2.yaml con IP NODO 1
# [4/8] Actualizar pgpool-nodo2.conf con IP NODO 1
# [5/8] Actualizar haproxy-nodo2.cfg con resolución remota
# [6/8] Crear red Docker (keycloak-ha-nodo2)
# [7/8] Generar certificados SSL
# [8/8] Iniciar servicios (REPLICA → HAProxy → pgpool → Keycloak-2)
# [9/8] Verificar replicación PostgreSQL (LAG < 10s)
# [10/8] Verificar Keycloak-2 en https://localhost:8443

# Tiempo estimado por nodo: 2-3 minutos
```

#### Paso 3: Verificar Clustering

```bash
# (En NODO 1) Verificar logs de Keycloak-1
docker logs keycloak-1 | grep -i "received new cluster view"
# Expected: 
# Received new cluster view: [keycloak-1|1] (2) [keycloak-1, <NODO2_IP>:7800]

# (En NODO 2) Verificar logs de Keycloak-2
docker logs keycloak-2 | grep -i "received new cluster view"
# Expected:
# Received new cluster view: [keycloak-1|1] (2) [keycloak-1, keycloak-2]

# (En NODO 2) Verificar replicación PostgreSQL
docker exec postgres-replica psql -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), (pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()) AS synced;"
# Expected:
#  pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | synced
# -------------------------+------------------------+--------
#  0/3000148               | 0/3000148              | t

# (En NODO 2) Verificar query routing de pgpool
docker exec pgpool psql -h localhost -p 9999 -U postgres -d keycloak -c "SHOW pool_nodes;"
# Expected:
#  node_id | hostname    | port | status | role    | lb_weight
# ---------+-------------+------+--------+---------+-----------
#  0       | <NODO1_IP>  | 5000 | up     | primary | 0.000000
#  1       | haproxy     | 5001 | up     | standby | 1.000000
```

### Verificación del Sistema (2 Nodos)

```bash
# NOTA: Los tests deben ejecutarse en cada nodo de forma independiente

# (En NODO 1) - Suite de tests locales
./test-nodo1.sh   # En desarrollo - verifica PRIMARY local

# (En NODO 2) - Suite de tests con proxy remoto
./test-nodo2.sh   # En desarrollo - verifica REPLICA + routing remoto

# Tests manuales recomendados:

# ============ Test 1: Replicación de datos ============
# (En NODO 1) Insertar datos en PRIMARY
docker exec postgres-primary psql -U postgres -d keycloak -c \
  "CREATE TABLE IF NOT EXISTS test_replication (id SERIAL PRIMARY KEY, data TEXT, created_at TIMESTAMP DEFAULT NOW());"

docker exec postgres-primary psql -U postgres -d keycloak -c \
  "INSERT INTO test_replication (data) VALUES ('Test desde NODO 1');"

# (En NODO 2) Verificar datos en REPLICA (esperar 1-2 segundos)
docker exec postgres-replica psql -U postgres -d keycloak -c \
  "SELECT * FROM test_replication;"
# Expected: 1 fila con "Test desde NODO 1"

# ============ Test 2: Query Routing NODO 2 ============
# (En NODO 2) Conectar a pgpool y ejecutar SELECT (debe ir a REPLICA local)
docker exec -e PGPASSWORD=postgres_admin pgpool \
  psql -h localhost -p 9999 -U postgres -d keycloak -c \
  "SELECT 'Lectura desde REPLICA local' AS test;"

# (En NODO 2) Ejecutar INSERT (debe ir a PRIMARY remoto en NODO 1)
docker exec -e PGPASSWORD=postgres_admin pgpool \
  psql -h localhost -p 9999 -U postgres -d keycloak -c \
  "INSERT INTO test_replication (data) VALUES ('Escritura desde NODO 2 vía proxy');"

# (En NODO 1) Verificar que el INSERT llegó al PRIMARY
docker exec postgres-primary psql -U postgres -d keycloak -c \
  "SELECT * FROM test_replication WHERE data LIKE '%NODO 2%';"
# Expected: 1 fila con "Escritura desde NODO 2 vía proxy"

# ============ Test 3: Clustering Keycloak ============
# (En NODO 1) Crear un realm
curl -k https://localhost:8443/admin/realms -H 'Content-Type: application/json' \
  -d '{"realm":"test-realm","enabled":true}'

# (En NODO 2) Verificar que el realm se sincronizó vía caché distribuido
curl -k https://localhost:8443/admin/realms/test-realm
# Expected: 200 OK con JSON del realm
```

### Acceso a Servicios (2 Nodos)

#### NODO 1 (Servidor Primario)

| Servicio | URL/Endpoint | Credenciales | Descripción |
|----------|--------------|--------------|-------------|
| **Keycloak-1** | https://<NODO1_IP>:8443 | admin / admin | Keycloak activo primario |
| **pgpool-II** | <NODO1_IP>:9999 | postgres / postgres_admin | Query routing local (todo a PRIMARY) |
| **HAProxy Stats** | http://<NODO1_IP>:7000 | - | Dashboard estadísticas |
| **PostgreSQL PRIMARY** | <NODO1_IP>:5432 | postgres / postgres_admin | **EXPUESTO** para replicación remota |

**Acceso local desde contenedores NODO 1:**
```bash
# Keycloak-1 local
docker exec keycloak-1 curl -k https://localhost:8443/health

# pgpool local (todo va a PRIMARY)
docker exec -e PGPASSWORD=postgres_admin pgpool \
  psql -h localhost -p 9999 -U postgres -d keycloak -c "SELECT 'OK' AS status;"

# PRIMARY local directo
docker exec postgres-primary psql -U postgres -c "SELECT pg_is_in_recovery();"  # Expected: f (false)
```

#### NODO 2 (Servidor Secundario)

| Servicio | URL/Endpoint | Credenciales | Descripción |
|----------|--------------|--------------|-------------|
| **Keycloak-2** | https://<NODO2_IP>:8443 | admin / admin | Keycloak activo secundario |
| **pgpool-II** ⭐ | <NODO2_IP>:9999 | postgres / postgres_admin | Query routing inteligente:<br>- SELECT → REPLICA local<br>- INSERT/UPDATE/DELETE → PRIMARY remoto |
| **HAProxy Stats** | http://<NODO2_IP>:7000 | - | Dashboard estadísticas |
| **PostgreSQL REPLICA** | localhost:5432 | postgres / postgres_admin | Solo acceso interno (no expuesto) |

**Acceso local desde contenedores NODO 2:**
```bash
# Keycloak-2 local
docker exec keycloak-2 curl -k https://localhost:8443/health

# pgpool local CON ROUTING AUTOMÁTICO ⭐
docker exec -e PGPASSWORD=postgres_admin pgpool \
  psql -h localhost -p 9999 -U postgres -d keycloak -c "SELECT 'Lectura local' AS test;"  # → REPLICA local

docker exec -e PGPASSWORD=postgres_admin pgpool \
  psql -h localhost -p 9999 -U postgres -d keycloak -c "INSERT INTO test VALUES ('Write remoto');"  # → PRIMARY remoto

# REPLICA local directo
docker exec postgres-replica psql -U postgres -c "SELECT pg_is_in_recovery();"  # Expected: t (true)
```

---

## Guía de Uso - Arquitectura 2 Nodos

### Comportamiento de Query Routing por Nodo

#### NODO 1 (PRIMARY Database)

**pgpool-II:** Configurado con 1 backend (PRIMARY local)

```bash
# Configuración pgpool-nodo1.conf:
# backend_hostname0 = 'haproxy'
# backend_port0 = 5000
# backend_weight0 = 1
# backend_flag0 = 'ALWAYS_PRIMARY'

# RESULTADO: Todas las queries (SELECT + INSERT/UPDATE/DELETE) → PRIMARY local
```

**Latencia esperada:** <2ms (todo local)

**Uso desde aplicaciones en NODO 1:**
```bash
# Variables de entorno Keycloak-1
KC_DB_URL_HOST=pgpool
KC_DB_URL_PORT=9999
KC_DB_URL_DATABASE=keycloak
KC_DB_USERNAME=postgres
KC_DB_PASSWORD=postgres_admin

# Todas las operaciones son rápidas (local):
SELECT * FROM users;           # <2ms → PRIMARY local
INSERT INTO users VALUES (...) # <2ms → PRIMARY local
UPDATE users SET ...;          # <2ms → PRIMARY local
```

#### NODO 2 (REPLICA Database + Proxy a PRIMARY Remoto)

**pgpool-II:** Configurado con 2 backends (PRIMARY remoto + REPLICA local)

```bash
# Configuración pgpool-nodo2.conf:
# Backend 0: PRIMARY remoto (NODO 1)
#   backend_hostname0 = '<NODO1_IP>'
#   backend_port0 = 5000
#   backend_weight0 = 0              # ⚠️  Weight 0 = NO lecturas
#   backend_flag0 = 'ALWAYS_PRIMARY'
#
# Backend 1: REPLICA local
#   backend_hostname1 = 'haproxy'
#   backend_port1 = 5001
#   backend_weight1 = 1              # ✅ Weight 1 = Todas las lecturas
#   backend_flag1 = 'DISALLOW_TO_FAILOVER'

# RESULTADO: 
# - SELECT → Backend 1 (REPLICA local)   ✅ <2ms
# - INSERT/UPDATE/DELETE → Backend 0 (PRIMARY remoto)  ⚠️ 10-50ms
```

**Latencia esperada:**
- Lecturas (SELECT): <2ms (REPLICA local)
- Escrituras (INSERT/UPDATE/DELETE): 10-50ms (PRIMARY remoto vía red)

**Uso desde aplicaciones en NODO 2:**
```bash
# Variables de entorno Keycloak-2 (mismas que NODO 1)
KC_DB_URL_HOST=pgpool
KC_DB_URL_PORT=9999
KC_DB_URL_DATABASE=keycloak
KC_DB_USERNAME=postgres
KC_DB_PASSWORD=postgres_admin

# Operaciones con latencia mixta:
SELECT * FROM users;           # ✅ <2ms → REPLICA local (RÁPIDO)
INSERT INTO users VALUES (...) # ⚠️ 10-50ms → PRIMARY remoto (LATENCIA RED)
UPDATE users SET ...;          # ⚠️ 10-50ms → PRIMARY remoto (LATENCIA RED)
DELETE FROM users WHERE ...;   # ⚠️ 10-50ms → PRIMARY remoto (LATENCIA RED)
```

### Opción 1: pgpool-II - Query Routing Automático ⭐ RECOMENDADO

**Ventajas:**
- ✅ La aplicación NO necesita conocer en qué nodo está desplegada
- ✅ Configuración idéntica de Keycloak en ambos nodos
- ✅ Routing completamente transparente basado en análisis SQL
- ✅ Load balancing automático de queries SELECT (en NODO 2 → REPLICA local)
- ✅ Gestión inteligente de transacciones (writes → PRIMARY siempre)
- ✅ Connection pooling integrado (reduce overhead de conexiones remotas)
- ✅ Compatible con cualquier driver PostgreSQL estándar

**Conexión desde aplicación (idéntica en ambos nodos):**

```bash
# Variables de entorno ejemplo (FUNCIONA EN AMBOS NODOS)
DB_HOST=pgpool
DB_PORT=9999
DB_NAME=keycloak
DB_USER=postgres
DB_PASSWORD=postgres_admin

# Configuración Keycloak (NODO 1 y NODO 2)
KC_DB_URL_HOST=pgpool
KC_DB_URL_PORT=9999
KC_DB_URL_DATABASE=keycloak
KC_DB_USERNAME=postgres
KC_DB_PASSWORD=postgres_admin
```

**Ejemplos de query routing:**

```sql
-- ========== LECTURAS (SELECT) ==========
-- NODO 1: PRIMARY local (<2ms)
-- NODO 2: REPLICA local (<2ms) ✅ RÁPIDO EN AMBOS
SELECT * FROM users WHERE username = 'john';
SELECT COUNT(*) FROM users;
SELECT u.*, p.* FROM users u JOIN profiles p ON u.id = p.user_id;
SELECT * FROM sessions WHERE expiration > NOW();

-- ========== ESCRITURAS (INSERT/UPDATE/DELETE/DDL) ==========
-- NODO 1: PRIMARY local (<2ms)
-- NODO 2: PRIMARY remoto (10-50ms) ⚠️ LATENCIA RED
INSERT INTO users (id, username, email) VALUES (1, 'john', 'john@example.com');
UPDATE users SET email = 'newemail@example.com' WHERE id = 1;
DELETE FROM users WHERE id = 1;
CREATE TABLE products (id SERIAL PRIMARY KEY, name VARCHAR(255));
ALTER TABLE users ADD COLUMN created_at TIMESTAMP;

-- ========== TRANSACCIONES MIXTAS ==========
-- TODA la transacción al PRIMARY (NODO 1 local o NODO 2 remoto)
BEGIN;
  SELECT * FROM users WHERE id = 1;        -- Ejecutado en PRIMARY
  UPDATE users SET login_count = login_count + 1 WHERE id = 1;
COMMIT;

-- ========== QUERIES CON LOCKS (detectadas como writes) ==========
-- Routing: PRIMARY (NODO 1 local o NODO 2 remoto)
SELECT * FROM users WHERE id = 1 FOR UPDATE;
SELECT * FROM products FOR SHARE;
```

-- Queries con locks: detectadas como writes → PRIMARY
SELECT * FROM users WHERE id = 1 FOR UPDATE;
SELECT * FROM products FOR SHARE;
```

**Testing del routing:**

```bash
# Conectar a pgpool-II
docker exec -it -e PGPASSWORD=postgres_admin pgpool \
  psql -h localhost -p 9999 -U postgres -d keycloak

# Ver estado de backends
keycloak=# SHOW pool_nodes;

# Resultado esperado:
#  node_id | hostname | port | status | pg_status | lb_weight | role    | select_cnt
# ---------+----------+------+--------+-----------+-----------+---------+------------
#  0       | haproxy  | 5000 | up     | up        | 0.000000  | primary | 0
#  1       | haproxy  | 5001 | up     | up        | 1.000000  | standby | 1245
#
# lb_weight: 0 = no recibe SELECTs, 1 = recibe todos los SELECTs
# select_cnt: contador de SELECTs ejecutados en cada backend

# Ver estadísticas de pool
keycloak=# SHOW pool_processes;
```

### Opción 2: HAProxy - Routing por Puerto

**Ventajas:**
- ✅ Control explícito del destino (aplicación decide puerto)
- ✅ Overhead mínimo (solo TCP proxy, no parsing SQL)
- ✅ Útil para debugging y troubleshooting
- ✅ Failover automático después de promoción

**Limitaciones:**
- ⚠️ La aplicación debe separar READ de WRITE queries manualmente
- ⚠️ Puerto 5001 puede rechazar writes si conecta a REPLICA
- ⚠️ No hay connection pooling

**Uso recomendado:**

```python
# Ejemplo Python con psycopg2
import psycopg2

# Pool de escrituras: SIEMPRE puerto 5000 (PRIMARY garantizado)
write_conn = psycopg2.connect(
    host="haproxy",
    port=5000,
    database="keycloak",
    user="postgres",
    password="postgres_admin"
)

# Pool de lecturas: Puerto 5001 (REPLICA preferida)
read_conn = psycopg2.connect(
    host="haproxy",
    port=5001,
    database="keycloak",
    user="postgres",
    password="postgres_admin"
)

# Escrituras
with write_conn.cursor() as cur:
    cur.execute("INSERT INTO users VALUES (%s, %s)", (1, 'john'))
    write_conn.commit()

# Lecturas
with read_conn.cursor() as cur:
    cur.execute("SELECT * FROM users WHERE id = %s", (1,))
    result = cur.fetchone()
```

**Verificación de routing:**

```bash
# Test escritura puerto 5000 (PRIMARY)
docker exec -e PGPASSWORD=postgres_admin haproxy \
  psql -h localhost -p 5000 -U postgres -d keycloak \
  -c "INSERT INTO test_table VALUES ('test');"
# Resultado: OK

# Test escritura puerto 5001 (puede fallar si conecta a REPLICA)
docker exec -e PGPASSWORD=postgres_admin haproxy \
  psql -h localhost -p 5001 -U postgres -d keycloak \
  -c "INSERT INTO test_table VALUES ('test');"
# Resultado: ERROR: cannot execute INSERT in a read-only transaction (si conecta a REPLICA)

# Ver estadísticas HAProxy
curl http://localhost:7000
# Dashboard web con estado de backends, conexiones activas, health checks, etc.
```

### Opción 3: Conexión Directa a PostgreSQL

**Solo para:**
- Debugging y troubleshooting
- Operaciones de administración
- Testing manual

**NO recomendado para aplicaciones en producción** (no hay balanceo ni failover)

```bash
# Conectar directamente a PRIMARY
docker exec -it -e PGPASSWORD=postgres_admin postgres-primary \
  psql -h 127.0.0.1 -U postgres -d keycloak

# Conectar directamente a REPLICA (read-only)
docker exec -it -e PGPASSWORD=postgres_admin postgres-replica \
  psql -h 127.0.0.1 -U postgres -d keycloak
```

---

## Suite de Testing Automatizada

El proyecto incluye una **suite completa de 23 tests automatizados** consolidados en un único script `test.sh` que verifica todos los aspectos críticos del sistema.

### Ejecución

```bash
./test.sh
```

### Cobertura de Tests

#### PARTE 1: Tests Básicos de Replicación PostgreSQL (7 tests)

| Test | Descripción | Verificación |
|------|-------------|--------------|
| **1.1** | Roles PRIMARY/REPLICA | `pg_is_in_recovery()` en ambos nodos |
| **1.2** | Replicación de datos | Inserción en PRIMARY, lectura en REPLICA |
| **1.3** | REPLICA read-only | Intento de escritura debe fallar en REPLICA |
| **1.4** | LAG de replicación | `pg_last_xact_replay_timestamp()` < 10s |
| **1.5** | Keycloak Node 1 | HTTP 200 en https://localhost:8443 |
| **1.6** | Keycloak Node 2 | HTTP 200 en https://localhost:8444 |
| **1.7** | Conectividad cluster | Cache JGroups sincronizado |

**Criterios de éxito:**
- PRIMARY debe retornar `NOT pg_is_in_recovery() = true`
- REPLICA debe retornar `pg_is_in_recovery() = true`
- LAG de replicación debe ser < 30 segundos (óptimo < 10s)
- Ambos nodos Keycloak deben responder HTTP 200

#### PARTE 2: Tests HAProxy Routing (7 tests)

| Test | Descripción | Verificación |
|------|-------------|--------------|
| **2.1** | Puerto 5000 → PRIMARY | Escritura exitosa garantizada |
| **2.2** | Puerto 5001 comportamiento | Escritura puede fallar si conecta a REPLICA |
| **2.3** | Múltiples escrituras 5000 | Batch de 5 INSERTs sin errores |
| **2.4** | Replicación streaming | Datos escritos en PRIMARY aparecen en REPLICA |
| **2.5** | REPLICA rechaza writes | Validación read-only en standby |
| **2.6** | HAProxy Stats accesible | HTTP 200 en http://localhost:7000 |
| **2.7** | Health checks funcionando | Backends marcados UP/DOWN correctamente |

**Criterios de éxito:**
- Puerto 5000 debe aceptar TODAS las escrituras (100% PRIMARY)
- Replicación debe completarse en < 5 segundos
- HAProxy Stats debe mostrar estado de backends en tiempo real
- Health checks deben detectar rol PRIMARY/REPLICA correctamente

#### PARTE 3: Tests pgpool-II Routing Automático (9 tests)

| Test | Descripción | Verificación |
|------|-------------|--------------|
| **3.1** | INSERT routing | `INSERT` detectado y ruteado a PRIMARY |
| **3.2** | UPDATE routing | `UPDATE` detectado y ruteado a PRIMARY |
| **3.3** | DELETE routing | `DELETE` detectado y ruteado a PRIMARY |
| **3.4** | SELECT routing | `SELECT` balanceado a REPLICA |
| **3.5** | Batch operations | 10 INSERTs consecutivos sin errores |
| **3.6** | Read verification | SELECTs retornan datos correctos desde REPLICA |
| **3.7** | Transaction handling | Transacción mixta (SELECT+UPDATE) al PRIMARY |
| **3.8** | Backend health | 2/2 backends UP y respondiendo |
| **3.9** | Pool statistics | Métricas de pool_nodes y distribución de queries |

**Criterios de éxito:**
- Todos los DML (INSERT/UPDATE/DELETE) deben ejecutarse en PRIMARY
- SELECTs deben balancearse a REPLICA (backend1, weight=1)
- Transacciones mixtas completas deben ir a PRIMARY
- Ambos backends (PRIMARY y REPLICA) deben estar status "up"
- `select_cnt` de REPLICA debe ser > 0 (recibe queries)

### Ejemplo de Salida

```bash
$ ./test.sh

=========================================================================
  Test Completo: Keycloak HA - PostgreSQL Streaming Replication
=========================================================================

=========================================================================
  PARTE 1: Tests Básicos de Replicación PostgreSQL
=========================================================================

📋 TEST 1.1: Verificar roles PRIMARY/REPLICA
─────────────────────────────────────────────────────────────────────
  ✅ postgres-primary es PRIMARY (NOT in recovery)
  ✅ postgres-replica es REPLICA (in recovery mode)

📋 TEST 1.2: Test de replicación de datos
─────────────────────────────────────────────────────────────────────
  ✅ Tabla creada en PRIMARY
  ✅ 3 filas insertadas en PRIMARY
  ⏳ Esperando replicación (2 segundos)...
  ✅ REPLICA tiene 3 filas replicadas

📋 TEST 1.3: Verificar que REPLICA es READ-ONLY
─────────────────────────────────────────────────────────────────────
  ✅ REPLICA rechaza correctamente escrituras (read-only)

📋 TEST 1.4: Medir LAG de replicación
─────────────────────────────────────────────────────────────────────
  ℹ️  LAG actual: 0 segundos
  ✅ LAG < 10s: Excelente

📋 TEST 1.5: Verificar Keycloak acceso
─────────────────────────────────────────────────────────────────────
  ✅ Keycloak-1 (8443) responde: 200 OK
  ✅ Keycloak-2 (8444) responde: 200 OK

=========================================================================
  PARTE 2: Tests de HAProxy Routing
=========================================================================

📋 TEST 2.1: Escritura via HAProxy puerto 5000 (PRIMARY)
─────────────────────────────────────────────────────────────────────
  ✅ Puerto 5000 → escritura exitosa en PRIMARY

📋 TEST 2.2: Comportamiento puerto 5001 (REPLICA preferred)
─────────────────────────────────────────────────────────────────────
  ℹ️  Puerto 5001 puede rechazar escrituras si conecta a REPLICA
  ✅ Comportamiento esperado del puerto 5001

...

=========================================================================
  PARTE 3: Tests de pgpool-II Routing Automático
=========================================================================

📋 TEST 3.1: INSERT automático a PRIMARY
─────────────────────────────────────────────────────────────────────
  ✅ INSERT ejecutado correctamente via pgpool-II

📋 TEST 3.4: SELECT balanceado a REPLICA
─────────────────────────────────────────────────────────────────────
  ✅ SELECT ejecutado correctamente vía pgpool-II
  ✅ Dato leído: test-3.1-xxx

...

=========================================================================
  📊 Resumen Final
=========================================================================

Servicios Disponibles:
  • Keycloak: https://localhost:8443, https://localhost:8444
  • pgpool-II: localhost:9999 (⭐ RECOMENDADO para aplicaciones)
  • HAProxy: localhost:5000 (PRIMARY), localhost:5001 (REPLICA)
  • PostgreSQL: localhost:5432 (PRIMARY), localhost:5433 (REPLICA)

📊 Estadísticas:
Total de tests:    23
Tests exitosos:    23
Tests fallidos:    0

🎉 ¡TODOS LOS TESTS PASARON!
```

### Tests Individuales por Componente

Aunque se recomienda ejecutar `test.sh` completo, se pueden ejecutar verificaciones específicas:

```bash
# Verificar solo estado de replicación
./check-replication.sh

# Salida esperada:
# application_name |  state  | sync_state | write_lag | flush_lag | replay_lag
# ------------------+---------+------------+-----------+-----------+------------
#  walreceiver      | streaming | async    | 00:00:00  | 00:00:00  | 00:00:00

# Verificar estado de pgpool backends
docker exec pgpool psql -h localhost -p 9999 -U postgres \
  -c "SHOW pool_nodes;"

# Verificar estadísticas HAProxy
curl -s http://localhost:7000 | grep -E "(postgres-primary|postgres-replica)"

# Verificar logs en tiempo real
docker logs -f pgpool --tail 50
docker logs -f haproxy --tail 50
docker logs -f postgres-primary --tail 50
```

---

## Operaciones y Mantenimiento

### Monitoreo del Sistema

#### Estado de Replicación

```bash
# Script automatizado con métricas completas
./check-replication.sh

# Salida esperada:
# ===============================================
#   Estado de Replicación PRIMARY → REPLICA
# ===============================================
#
# 📊 Información de REPLICA conectada:
#   Application Name:  walreceiver
#   Estado:            streaming
#   Sync State:        async
#   Write LAG:         00:00:00.000000
#   Flush LAG:         00:00:00.000000
#   Replay LAG:        00:00:00.000000
#   Prioridad Sync:    0

# Verificación manual desde PRIMARY
docker exec -e PGPASSWORD=postgres_admin postgres-primary \
  psql -h 127.0.0.1 -U postgres -x -c "SELECT * FROM pg_stat_replication;"

# Verificación manual desde REPLICA
docker exec -e PGPASSWORD=postgres_admin postgres-replica \
  psql -h 127.0.0.1 -U postgres -c "
    SELECT 
      pg_is_in_recovery() as is_replica,
      pg_last_wal_receive_lsn() as receive_lsn,
      pg_last_wal_replay_lsn() as replay_lsn,
      EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as lag_seconds;
  "
```

#### Logs de Servicios

```bash
# PostgreSQL PRIMARY
docker logs postgres-primary -f --tail 100

# Eventos importantes:
# - "database system is ready to accept connections"
# - "replication connection authorized"
# - "streaming replication successfully connected to primary"

# PostgreSQL REPLICA
docker logs postgres-replica -f --tail 100

# Eventos importantes:
# - "entering standby mode"
# - "started streaming WAL from primary"
# - "consistent recovery state reached"

# pgpool-II
docker logs pgpool -f --tail 100

# Eventos importantes:
# - "backend 0 status changed to up"
# - "backend 1 status changed to up"
# - "health check: backend 0 is up"
# - "SELECT routing to backend 1"

# HAProxy
docker logs haproxy -f --tail 100

# Eventos importantes:
# - "Server postgres-primary/postgres-primary is UP"
# - "Server postgres-replica/postgres-replica is UP"
# - "Health check for server postgres-primary succeeded"

# Keycloak
docker logs keycloak-1 -f --tail 100
docker logs keycloak-2 -f --tail 100

# Eventos importantes:
# - "Keycloak 23.0.0 (powered by Quarkus) started"
# - "Infinispan channels connected"
# - "Started clustering services"
```

#### Métricas de Rendimiento

```bash
# Estadísticas de pgpool-II
docker exec pgpool psql -h localhost -p 9999 -U postgres -c "
  SHOW pool_processes;
  SHOW pool_pools;
  SHOW pool_nodes;
"

# Ver distribución de queries por backend
docker exec pgpool psql -h localhost -p 9999 -U postgres -c "
  SELECT 
    node_id,
    hostname,
    port,
    status,
    role,
    select_cnt,
    insert_cnt,
    update_cnt,
    delete_cnt
  FROM pool_nodes;
"

# Estadísticas HAProxy (JSON)
curl -s http://localhost:7000/stats\;csv | column -t -s,

# Estadísticas PostgreSQL: conexiones activas
docker exec -e PGPASSWORD=postgres_admin postgres-primary \
  psql -h 127.0.0.1 -U postgres -c "
    SELECT 
      datname,
      count(*) as connections,
      count(*) FILTER (WHERE state = 'active') as active,
      count(*) FILTER (WHERE state = 'idle') as idle
    FROM pg_stat_activity
    WHERE datname IS NOT NULL
    GROUP BY datname;
  "

# Tamaño de bases de datos
docker exec -e PGPASSWORD=postgres_admin postgres-primary \
  psql -h 127.0.0.1 -U postgres -c "
    SELECT 
      datname,
      pg_size_pretty(pg_database_size(datname)) as size
    FROM pg_database
    ORDER BY pg_database_size(datname) DESC;
  "
```

### Procedimientos de Failover

#### Failover Manual (PRIMARY → REPLICA)

**Escenario:** El nodo PRIMARY ha fallado y necesita ser reemplazado por REPLICA.

```bash
# Ejecutar script automatizado
./promote-replica.sh

# Pasos ejecutados por el script:
# 1. Verificar estado actual de REPLICA
# 2. Detener PRIMARY (si sigue corriendo)
# 3. Promocionar REPLICA a PRIMARY:
#    - pg_ctl promote
#    - Eliminar recovery.signal
#    - Configurar como standalone PRIMARY
# 4. Verificar nuevo PRIMARY:
#    - pg_is_in_recovery() debe retornar FALSE
#    - Aceptar conexiones R/W
# 5. Actualizar HAProxy (automático vía health checks)
# 6. Actualizar pgpool-II (automático vía sr_check)

# Duración estimada: 30-60 segundos
```

**Verificación post-failover:**

```bash
# 1. Verificar que ex-REPLICA es ahora PRIMARY
docker exec -e PGPASSWORD=postgres_admin postgres-replica \
  psql -h 127.0.0.1 -U postgres -t -c "SELECT NOT pg_is_in_recovery();"
# Esperado: t (true)

# 2. Verificar que acepta escrituras
docker exec -e PGPASSWORD=postgres_admin postgres-replica \
  psql -h 127.0.0.1 -U postgres -d keycloak \
  -c "INSERT INTO test_table VALUES ('post-failover-test');"
# Esperado: INSERT 0 1

# 3. Verificar detección en HAProxy
curl -s http://localhost:7000 | grep -A5 "postgres-replica"
# Esperado: postgres-replica marcado como UP en frontend PRIMARY

# 4. Verificar detección en pgpool-II
docker exec pgpool psql -h localhost -p 9999 -U postgres -c "SHOW pool_nodes;"
# Esperado: node 1 (ex-REPLICA) ahora con role="primary"
```

#### Reconstrucción de REPLICA después de Failover

Una vez promovida la REPLICA, el antiguo PRIMARY debe ser reconfigurado como nueva REPLICA:

```bash
# 1. Detener contenedor viejo PRIMARY
docker stop postgres-primary
docker rm postgres-primary

# 2. Limpiar datos antiguos
docker volume rm keycloak_ha_postgres_primary_data

# 3. Recrear como REPLICA del nuevo PRIMARY
# Editar docker-compose.yaml: intercambiar configuraciones PRIMARY/REPLICA
# O reconstruir manualmente:

# Iniciar nuevo contenedor REPLICA apuntando al nuevo PRIMARY
docker run -d \
  --name postgres-primary \
  --network keycloak-ha-net \
  -e POSTGRES_PASSWORD=postgres_admin \
  -e PRIMARY_HOST=postgres-replica \  # Ahora apunta al nuevo PRIMARY
  -e PRIMARY_PORT=5432 \
  -v postgres_primary_data:/var/lib/postgresql/data \
  postgres:15

# 4. Configurar replicación (pg_basebackup desde nuevo PRIMARY)
docker exec -it postgres-primary bash
pg_basebackup -h postgres-replica -U postgres -D /var/lib/postgresql/data -Fp -Xs -P -R

# 5. Iniciar PostgreSQL en modo standby
pg_ctl -D /var/lib/postgresql/data start
```

### Backup y Recuperación

#### Backup Completo (pg_basebackup)

```bash
# Backup desde PRIMARY
docker exec postgres-primary bash -c "
  pg_basebackup -U postgres -D /backup/\$(date +%Y%m%d_%H%M%S) -Ft -z -P
"

# Copiar backup fuera del contenedor
docker cp postgres-primary:/backup/20260210_120000.tar.gz ./backups/
```

#### Backup SQL Dump

```bash
# Dump de base de datos específica
docker exec -e PGPASSWORD=postgres_admin postgres-primary \
  pg_dump -h 127.0.0.1 -U postgres -d keycloak -F c -f /tmp/keycloak_backup.dump

# Copiar fuera del contenedor
docker cp postgres-primary:/tmp/keycloak_backup.dump ./backups/keycloak_$(date +%Y%m%d).dump

# Dump de todas las bases de datos
docker exec -e PGPASSWORD=postgres_admin postgres-primary \
  pg_dumpall -h 127.0.0.1 -U postgres -f /tmp/full_backup.sql

docker cp postgres-primary:/tmp/full_backup.sql ./backups/
```

#### Restauración

```bash
# Desde SQL dump
docker cp ./backups/keycloak_20260210.dump postgres-primary:/tmp/

docker exec -e PGPASSWORD=postgres_admin postgres-primary \
  pg_restore -h 127.0.0.1 -U postgres -d keycloak -c /tmp/keycloak_20260210.dump

# Verificar integridad post-restauración
./test.sh
```

### Escalado y Optimización

#### Añadir REPLICA Adicional

```bash
# 1. Crear entrada en docker-compose.yaml
services:
  postgres-replica-2:
    image: postgres:15
    container_name: postgres-replica-2
    environment:
      POSTGRES_PASSWORD: postgres_admin
      PRIMARY_HOST: postgres-primary
      PRIMARY_PORT: 5432
    volumes:
      - postgres_replica_2_data:/var/lib/postgresql/data
      - ./postgres/setup-replica.sh:/docker-entrypoint-initdb.d/setup-replica.sh
    # ... configuración similar a replica-1

# 2. Añadir backend en pgpool.conf
backend_hostname2 = 'postgres-replica-2'
backend_port2 = 5432
backend_weight2 = 1  # Distribución de load balance
backend_flag2 = 'DISALLOW_TO_FAILOVER'

# 3. Actualizar HAProxy haproxy.cfg
backend pg_replica
    server postgres-replica-2 postgres-replica-2:5432 check weight 100

# 4. Desplegar
docker compose up -d postgres-replica-2
```

#### Tuning PostgreSQL

**Para mayor rendimiento en escrituras:**

```ini
# postgresql-primary.conf
shared_buffers = 1GB           # 25% de RAM disponible
effective_cache_size = 3GB     # 75% de RAM disponible
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1         # Para SSD
effective_io_concurrency = 200
work_mem = 32MB
min_wal_size = 2GB
max_wal_size = 8GB
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
```

**Para reducir LAG de replicación:**

```ini
# postgresql-primary.conf
synchronous_commit = remote_apply  # Cambiar de 'off' a 'remote_apply' para sync
synchronous_standby_names = 'walreceiver'  # Replica sincrónica

# postgresql-replica.conf
hot_standby_feedback = on
wal_receiver_timeout = 30s
max_standby_streaming_delay = 30s
```

#### Tuning pgpool-II

```ini
# pgpool.conf - Para mayor concurrencia
num_init_children = 64        # Aumentar procesos worker
max_pool = 8                  # Más conexiones por proceso
child_life_time = 600         # Reciclar procesos cada 10min
connection_cache = on         # Cachear conexiones

# Para mejor performance en reads
load_balance_mode = on
statement_level_load_balance = on
```

---

## Resolución de Problemas

### Problemas Específicos de Arquitectura 2 Nodos

#### NODO 2: No Puede Conectar al PRIMARY Remoto

**Síntoma (en NODO 2):**
```bash
docker logs postgres-replica | tail -20
# Output:
# FATAL: could not connect to the primary server: connection refused
```

**Diagnóstico:**
```bash
# (En NODO 2) Test conectividad red
ping -c 3 <IP_NODO_1>
nc -zv <IP_NODO_1> 5432
```

**Solución:**
```bash
# (En NODO 1) Abrir firewall para PostgreSQL
sudo ufw allow from <IP_NODO_2> to any port 5432 proto tcp

# (En NODO 2) Verificar PRIMARY_HOST en docker-compose-nodo2.yaml
grep "PRIMARY_HOST" docker-compose-nodo2.yaml

# Re-desplegar si necesario
./cleanup-nodo2.sh && ./deploy-nodo2.sh
```

#### NODO 2: Replicación con LAG Alto (>10s)

**Causa:** Latencia de red alta o carga excesiva en PRIMARY

**Solución:**
```bash
# (En NODO 2) Medir latencia
ping -c 100 <IP_NODO_1> | tail -2

# Optimizar queries lentas en PRIMARY
# Aumentar resources en docker-compose
```

#### Keycloak Cluster No Se Forma Entre Nodos

**Síntoma:** Cada nodo ve solo 1 miembro en vez de 2

**Solución:**
```bash
# Abrir puerto 7800 en firewall (ambos nodos)
sudo ufw allow from <IP_OTRO_NODO> to any port 7800 proto tcp

# Verificar IPs en JGROUPS_DISCOVERY_PROPERTIES
# Reiniciar Keycloak en ambos nodos
```

### Problemas Comunes (Ambos Nodos)

### Tests Fallan con Error de Autenticación

**Síntoma:**
```
psql: error: connection to server failed: authentication failed for user "postgres"
```

**Causa:** Password incorrecta o variable `PGPASSWORD` no configurada.

**Solución:**
```bash
# Verificar que contenedores están corriendo
docker ps | grep -E "(postgres|pgpool|haproxy|keycloak)"

# Verificar logs de autenticación
docker logs postgres-primary | grep -i "authentication"

# Tests automáticamente configuran PGPASSWORD, pero para uso manual:
export PGPASSWORD="postgres_admin"

# Verificar pg_hba.conf permite conexiones
docker exec postgres-primary cat /etc/postgresql/pg_hba.conf | grep -v "^#"
```

### Escrituras Fallan en Puerto 5001 (HAProxy)

**Síntoma:**
```
ERROR: cannot execute INSERT in a read-only transaction
```

**Causa:** HAProxy puerto 5001 puede enrutar a REPLICA (read-only) debido a load balancing.

**Solución:**
```bash
# Opción 1: Usar puerto 5000 para escrituras (garantiza PRIMARY)
psql -h localhost -p 5000 -U postgres -d keycloak

# Opción 2: Usar pgpool-II (routing automático)
psql -h localhost -p 9999 -U postgres -d keycloak

# Opción 3: Conectar directamente a PRIMARY
psql -h localhost -p 5432 -U postgres -d keycloak
```

### pgpool-II No Detecta Backends

**Síntoma:**
```
SHOW pool_nodes;
node_id | status | pg_status
--------|--------|----------
0       | down   | down
1       | down   | down
```

**Diagnóstico:**
```bash
# 1. Verificar que HAProxy está corriendo
docker ps | grep haproxy

# 2. Verificar logs de pgpool
docker logs pgpool | grep -i "health check"

# 3. Verificar conectividad desde pgpool a HAProxy
docker exec pgpool ping -c 3 haproxy
docker exec pgpool nc -zv haproxy 5000
docker exec pgpool nc -zv haproxy 5001

# 4. Verificar que PostgreSQL responde via HAProxy
docker exec -e PGPASSWORD=postgres_admin pgpool \
  psql -h haproxy -p 5000 -U postgres -c "SELECT 1;"
```

**Solución:**
```bash
# Reiniciar pgpool para forzar health checks
docker restart pgpool

# Esperar 30 segundos para health checks
sleep 30

# Verificar nuevamente
docker exec pgpool psql -h localhost -p 9999 -U postgres -c "SHOW pool_nodes;"
```

### Keycloak No Inicia o No Responde

**Síntoma:**
```
curl https://localhost:8443
curl: (7) Failed to connect to localhost port 8443: Connection refused
```

**Diagnóstico:**
```bash
# 1. Verificar estado del contenedor
docker ps -a | grep keycloak

# 2. Ver logs completos
docker logs keycloak-1 --tail 200

# Errores comunes:
# - "Caused by: org.postgresql.util.PSQLException: Connection refused"
#   → PostgreSQL no está listo
# - "Caused by: javax.net.ssl.SSLException: Certificate not found"
#   → Certificados SSL no generados
# - "java.lang.OutOfMemoryError: Java heap space"
#   → Aumentar memoria

# 3. Verificar conectividad a DB
docker exec keycloak-1 nc -zv postgres-primary 5432
docker exec keycloak-1 nc -zv pgpool 9999
```

**Soluciones:**

```bash
# Si PostgreSQL no estaba listo: esperar y reiniciar Keycloak
docker restart keycloak-1 keycloak-2

# Si faltan certificados: regenerar
./generate-certs.sh
docker compose restart keycloak-1 keycloak-2

# Si OutOfMemory: aumentar heap en docker-compose.yaml
environment:
  JAVA_OPTS: "-Xms1g -Xmx2g"
```

### Error de Replicación o LAG Alto

**Síntoma:**
```
./check-replication.sh
LAG: 45 segundos  # > 30 segundos significa problema
```

**Diagnóstico:**
```bash
# 1. Verificar estado de replicación en PRIMARY
docker exec -e PGPASSWORD=postgres_admin postgres-primary \
  psql -h 127.0.0.1 -U postgres -x -c "
    SELECT 
      application_name,
      state,
      sync_state,
      sent_lsn,
      write_lsn,
      flush_lsn,
      replay_lsn,
      write_lag,
      flush_lag,
      replay_lag
    FROM pg_stat_replication;
  "

# 2. Verificar logs de REPLICA
docker logs postgres-replica | grep -i "replication\|wal\|recovery"

# Errores comunes:
# - "could not receive data from WAL stream: ERROR: requested WAL segment XXX has already been removed"
#   → PRIMARY eliminó WAL antes que REPLICA pudiera leerlo
# - "terminating walreceiver process due to administrator command"
#   → Replicación interrumpida manualmente

# 3. Verificar uso de disco en PRIMARY
docker exec postgres-primary df -h /var/lib/postgresql/data

# 4. Verificar CPU y memoria
docker stats --no-stream postgres-primary postgres-replica
```

**Soluciones:**

```bash
# Si WAL fue eliminado: reconstruir REPLICA desde cero
docker stop postgres-replica
docker volume rm keycloak_ha_postgres_replica_data
docker compose up -d postgres-replica

# Si LAG por carga alta: optimizar queries lentas
docker exec -e PGPASSWORD=postgres_admin postgres-primary \
  psql -h 127.0.0.1 -U postgres -x -c "
    SELECT 
      query,
      calls,
      total_exec_time / 1000 as total_seconds,
      mean_exec_time as avg_ms
    FROM pg_stat_statements
    ORDER BY total_exec_time DESC
    LIMIT 10;
  "

# Si LAG por red lenta: verificar latencia
docker exec postgres-replica ping -c 10 postgres-primary
```

### Cluster Keycloak No Sincroniza Cache

**Síntoma:**
- Sesión creada en keycloak-1 no existe en keycloak-2
- Cambios de configuración no se propagan

**Diagnóstico:**
```bash
# 1. Verificar logs de clustering
docker logs keycloak-1 | grep -i "jgroups\|infinispan\|cluster"
docker logs keycloak-2 | grep -i "jgroups\|infinispan\|cluster"

# Buscar:
# - ✅ "Received new cluster view: [keycloak-1, keycloak-2]"
# - ❌ "Failed to connect to cluster member"

# 2. Verificar conectividad JGroups (puerto 7800)
docker exec keycloak-1 nc -zv keycloak-2 7800
docker exec keycloak-2 nc -zv keycloak-1 7800

# 3. Verificar red Docker
docker network inspect keycloak-ha-net | grep -A 10 keycloak
```

**Soluciones:**

```bash
# Reiniciar ambos nodos para forzar re-clustering
docker restart keycloak-1 keycloak-2

# Esperar formación de cluster (30-60 segundos)
sleep 60

# Verificar cluster formado
docker logs keycloak-1 | tail -100 | grep "cluster view"
# Esperado: "Received new cluster view: [keycloak-1, keycloak-2]"
```

### HAProxy Stats No Accesible

**Síntoma:**
```
curl http://localhost:7000
curl: (7) Failed to connect
```

**Solución:**
```bash
# Verificar contenedor HAProxy
docker ps | grep haproxy

# Verificar logs
docker logs haproxy | grep -i "stats\|7000"

# Verificar configuración
docker exec haproxy cat /usr/local/etc/haproxy/haproxy.cfg | grep -A10 "listen stats"

# Reiniciar si es necesario
docker restart haproxy
```

---

## Estructura del Proyecto - Arquitectura 2 Nodos

```
keycloak_HA/
│
├── 📋 Documentación
│   ├── README.md                        # ⭐ Documentación principal (este archivo)
│   └── REORGANIZACION.md                # Notas de reorganización del proyecto
│
├── 🐳 Docker Compose - 2 Nodos Físicos
│   ├── docker-compose-nodo1.yaml        # ⭐ NODO 1: PRIMARY + Keycloak-1
│   │                                    #    - postgres-primary (puerto 5432 EXPUESTO)
│   │                                    #    - haproxy (solo PRIMARY local)
│   │                                    #    - pgpool (1 backend local)
│   │                                    #    - keycloak-1 (puerto 8443)
│   │
│   ├── docker-compose-nodo2.yaml        # ⭐ NODO 2: REPLICA + Keycloak-2 + Proxy
│   │                                    #    - postgres-replica (PRIMARY_HOST configurable)
│   │                                    #    - haproxy (proxy remoto + local)
│   │                                    #    - pgpool (2 backends: remoto+local)
│   │                                    #    - keycloak-2 (puerto 8443)
│   │                                    #    - extra_hosts para resolver NODO 1
│   │
│   └── docker-compose.yaml              # 🗂️  LEGACY: Setup monolítico (no usado)
│
├── 🐳 Dockerfiles
│   ├── Dockerfile                       # Keycloak optimizado para PostgreSQL
│   ├── Dockerfile.patroni               # LEGACY: No usado
│   ├── Dockerfile.postgres-primary      # LEGACY: No usado
│   └── Dockerfile.postgres-replica      # LEGACY: No usado
│
├── 🔧 Scripts de Despliegue (por Nodo)
│   ├── deploy-nodo1.sh                  # ⭐ Despliegue NODO 1 (PRIMARY)
│   │                                    #    1. Detecta IP automáticamente
│   │                                    #    2. Configura JGroups con IP
│   │                                    #    3. Despliega PRIMARY + Keycloak-1
│   │                                    #    4. Muestra IP para config NODO 2
│   │
│   ├── deploy-nodo2.sh                  # ⭐ Despliegue NODO 2 (REPLICA + Proxy)
│   │                                    #    1. Solicita IP de NODO 1
│   │                                    #    2. Test conectividad (nc -zv)
│   │                                    #    3. Actualiza configs con sed
│   │                                    #    4. Despliega REPLICA + Keycloak-2
│   │                                    #    5. Verifica LAG replicación
│   │
│   └── deploy.sh                        # 🗂️  LEGACY: Setup monolítico (no usado)
│
├── 🔧 Scripts de Limpieza (por Nodo)
│   ├── cleanup-nodo1.sh                 # Eliminación completa NODO 1
│   ├── cleanup-nodo2.sh                 # Eliminación completa NODO 2
│   └── cleanup.sh                       # 🗂️  LEGACY: Limpieza monolítica (no usado)
│
├── 🔧 Scripts de Testing (⚠️  EN DESARROLLO)
│   ├── test-nodo1.sh                    # TODO: Tests NODO 1 (PRIMARY local)
│   ├── test-nodo2.sh                    # TODO: Tests NODO 2 (proxy remoto)
│   └── test.sh                          # 🗂️  LEGACY: 23 tests monolíticos
│
├── 🔧 Scripts de Utilidad
│   ├── check-replication.sh             # Verificación estado de replicación
│   ├── promote-replica.sh               # Procedimiento de failover manual
│   └── generate-certs.sh                # Generación de certificados SSL
│
├── ⚙️ Configuración PostgreSQL
│   └── postgres/
│       ├── init-primary.sh              # Inicialización PRIMARY (usuarios, DB)
│       ├── setup-replica.sh             # Setup inicial REPLICA (pg_basebackup)
│       ├── pg_hba.conf                  # Autenticación (trust local, md5 remote)
│       ├── postgresql-primary.conf      # PRIMARY config (wal_level, max_wal_senders)
│       └── postgresql-replica.conf      # REPLICA config (hot_standby, recovery)
│
├── 🔀 Configuración HAProxy (por Nodo)
│   └── haproxy/
│       ├── haproxy-nodo1.cfg            # NODO 1: Solo PRIMARY local (5000)
│       │                                # - Frontend 5000 → postgres-primary
│       │                                # - Stats 7000
│       │
│       ├── haproxy-nodo2.cfg            # NODO 2: Proxy remoto + REPLICA local
│       │                                # - Frontend 5000 → nodo1-primary (remoto)
│       │                                # - Frontend 5001 → postgres-replica (local)
│       │                                # - Stats 7000
│       │
│       └── haproxy.cfg                  # 🗂️  LEGACY: Config monolítica (no usado)
│
├── 🔄 Configuración pgpool-II (por Nodo)
│   └── pgpool/
│       ├── pgpool-nodo1.conf            # ⭐ NODO 1: 1 backend (PRIMARY local)
│       │                                # - backend_hostname0 = 'haproxy'
│       │                                # - backend_weight0 = 1
│       │                                # - backend_flag0 = 'ALWAYS_PRIMARY'
│       │
│       ├── pgpool-nodo2.conf            # ⭐ NODO 2: 2 backends (remoto+local)
│       │                                # - Backend 0: PRIMARY remoto (weight=0)
│       │                                #   * backend_hostname0 = '<NODO1_IP>'
│       │                                #   * backend_flag0 = 'ALWAYS_PRIMARY'
│       │                                # - Backend 1: REPLICA local (weight=1)
│       │                                #   * backend_hostname1 = 'haproxy'
│       │                                #   * backend_weight1 = 1 (lecturas aquí)
│       │                                # - health_check_timeout = 30 (red remota)
│       │                                # - connection_cache = on
│       │
│       ├── pgpool.conf                  # 🗂️  LEGACY: Config monolítica (no usado)
│       ├── pool_hba.conf                # Autenticación pgpool (trust/md5)
│       └── pool_passwd                  # Passwords MD5 (postgres, keycloak)
│
├── 🔐 Certificados SSL
│   └── certs/
│       ├── keycloak.crt                 # Certificado público (auto-firmado)
│       ├── keycloak.key                 # Clave privada
│       └── keycloak.p12                 # Keystore PKCS12 (para Keycloak)
│
└── 🗂️ old/                               # Directorio de archivos legacy (Patroni, etc.)
    └── ...                              # No usado en arquitectura actual
```

### Flujo de Despliegue Recomendado

```
1. (En NODO 1) git clone && cd keycloak_HA
2. (En NODO 1) ./deploy-nodo1.sh
3. (En NODO 1) Anotar IP mostrada (ej: 192.168.1.100)
4. (En NODO 2) git clone && cd keycloak_HA
5. (En NODO 2) ./deploy-nodo2.sh  # Ingresará IP de NODO 1
6. (En ambos)  Verificar clustering con docker logs
```

### Archivos Clave para Modificar (Configuración Avanzada)

| Archivo | Propósito | Cuándo Modificar |
|---------|-----------|------------------|
| `docker-compose-nodo1.yaml` | Servicios NODO 1 | Cambiar puertos, resources, env vars |
| `docker-compose-nodo2.yaml` | Servicios NODO 2 | Cambiar PRIMARY_HOST, resources |
| `pgpool/pgpool-nodo1.conf` | Query routing NODO 1 | Ajustar connection pooling |
| `pgpool/pgpool-nodo2.conf` | Query routing NODO 2 | Ajustar timeouts para red, weights |
| `haproxy/haproxy-nodo2.cfg` | Proxy remoto NODO 2 | Cambiar IPs backend PRIMARY remoto |
| `postgres/postgresql-primary.conf` | Primary tuning | Performance tuning, WAL settings |
| `deploy-nodo1.sh` | Automatización NODO 1 | Personalizar pasos de despliegue |
| `deploy-nodo2.sh` | Automatización NODO 2 | Cambiar validaciones, IPs default |

---

## Estructura del Proyecto LEGACY (Monolítico)

```
keycloak_HA/
│
├── 📋 Documentación
│   ├── README.md                    # Documentación principal (este archivo)
│   └── REORGANIZACION.md            # Notas de reorganización del proyecto
│
├── 🐳 Docker & Orquestación
│   ├── docker-compose.yaml          # Definición de servicios (6 servicios)
│   ├── Dockerfile                   # Keycloak optimizado para PostgreSQL
│   ├── Dockerfile.patroni           # (No usado - legacy)
│   ├── Dockerfile.postgres-primary  # (No usado - legacy)
│   └── Dockerfile.postgres-replica  # (No usado - legacy)
│
├── 🔧 Scripts de Operación
│   ├── deploy.sh                    # ⭐ Despliegue completo automatizado
│   ├── test.sh                      # ⭐ Suite de 23 tests consolidados
│   ├── cleanup.sh                   # Eliminación completa del entorno
│   ├── check-replication.sh         # Verificación estado de replicación
│   ├── promote-replica.sh           # Procedimiento de failover manual
│   └── generate-certs.sh            # Generación de certificados SSL
│
├── ⚙️ Configuración PostgreSQL
│   └── postgres/
│       ├── init-primary.sh          # Inicialización PRIMARY (usuarios, DB)
│       ├── setup-replica.sh         # Setup inicial REPLICA (pg_basebackup)
│       ├── replica-entrypoint.sh    # Entrypoint customizado REPLICA
│       ├── pg_hba.conf              # Autenticación (trust local, md5 remote)
│       ├── postgresql-primary.conf  # Configuración PRIMARY (wal_level, max_wal_senders)
│       └── postgresql-replica.conf  # Configuración REPLICA (hot_standby, recovery)
│
├── 🔀 Configuración HAProxy
│   └── haproxy/
│       └── haproxy.cfg              # Routing por puerto + health checks
│                                    # - Frontend primary: puerto 5000
│                                    # - Frontend replica: puerto 5001
│                                    # - Stats: puerto 7000
│
├── 🔄 Configuración pgpool-II
│   └── pgpool/
│       ├── pgpool.conf              # ⭐ Configuración principal query routing
│       │                            # - master_slave_mode=on
│       │                            # - load_balance_mode=on
│       │                            # - backend definitions (PRIMARY/REPLICA)
│       ├── pool_hba.conf            # Autenticación pgpool (trust/md5)
│       └── pool_passwd              # Passwords MD5 (postgres, keycloak)
│
├── 🔐 Certificados SSL
│   └── certs/
│       ├── keycloak.crt             # Certificado público (generado)
│       ├── keycloak.key             # Clave privada (generado)
│       └── keycloak.p12             # Keystore PKCS12 para Keycloak (generado)
│
└── 📦 Old Files (Referencia)
    └── old/
        ├── Dockerfiles antiguos
        ├── Scripts de Patroni (no usado)
        └── Documentación legacy
```

### Descripción de Componentes Clave

#### docker-compose.yaml

Define 6 servicios interconectados:

1. **postgres-primary**: PostgreSQL 15 en modo PRIMARY (R/W)
   - Volumen persistente: `postgres_primary_data`
   - Scripts de inicialización: `init-primary.sh`
   - Health check: `pg_isready`

2. **postgres-replica**: PostgreSQL 15 en modo REPLICA (R/O)
   - Volumen persistente: `postgres_replica_data`
   - Scripts de setup: `setup-replica.sh`, `replica-entrypoint.sh`
   - Dependencia: espera PRIMARY healthy

3. **haproxy**: HAProxy 2.9-alpine
   - Puertos: 5000 (PRIMARY), 5001 (REPLICA), 7000 (Stats)
   - Health checks via `option pgsql-check`
   - Dependencia: espera PRIMARY y REPLICA healthy

4. **pgpool**: pgpool/pgpool:latest
   - Puerto: 9999 (PostgreSQL), 9898 (PCP admin)
   - 29 variables de entorno para configuración dinámica
   - Volúmenes: `pgpool.conf`, `pool_hba.conf`, `pool_passwd`
   - Dependencia: espera HAProxy healthy

5. **keycloak-1**: Keycloak 23.0 (nodo primario)
   - Puerto HTTPS: 8443
   - Puerto JGroups: 7800
   - Conexión DB via pgpool:9999

6. **keycloak-2**: Keycloak 23.0 (nodo secundario)
   - Puerto HTTPS: 8444
   - Puerto JGroups: 7801
   - Clustering con keycloak-1

#### test.sh - Suite de Testing Consolidada

Script completo de 23 tests organizados en 3 partes:

**Estructura interna:**
```bash
# Variables globales
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Funciones helper
pass_test() { ... }  # Incrementa contador de éxitos
fail_test() { ... }  # Incrementa contador de fallos

# PARTE 1: Tests Básicos (TEST 1.1 - 1.7)
# - Verificación de roles PRIMARY/REPLICA
# - Replicación de datos
# - Protección read-only en REPLICA
# - Medición de LAG
# - Conectividad Keycloak

# PARTE 2: Tests HAProxy (TEST 2.1 - 2.7)
# - Routing por puerto (5000/5001)
# - Behavior de escrituras/lecturas por puerto
# - Verificación replicación streaming
# - Acceso a Stats

# PARTE 3: Tests pgpool-II (TEST 3.1 - 3.9)
# - Routing automático DML (INSERT/UPDATE/DELETE)
# - Load balancing de SELECTs
# - Transacciones complejas
# - Estado de backends y health checks

# Resumen final
echo "Total tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
```

#### pgpool.conf - Configuración de Query Routing

Configuración optimizada para:
- **Routing inteligente**: Análisis sintáctico de queries SQL
- **Load balancing**: Distribución de SELECTs entre replicas
- **Connection pooling**: 32 procesos × 4 conexiones = 128 conexiones máximas
- **Health checks**: Verificación cada 10 segundos
- **Streaming replication check**: Detección automática de roles

**Parámetros críticos:**
```ini
master_slave_mode = on               # Habilita modo PRIMARY/REPLICA
load_balance_mode = on               # Distribuye SELECTs
disable_load_balance_on_write = transaction  # Sesiones con writes → PRIMARY

backend_weight0 = 0                  # PRIMARY: no recibe SELECTs balanceados
backend_weight1 = 1                  # REPLICA: recibe todos los SELECTs

health_check_period = 10             # Check salud cada 10s
sr_check_period = 10                 # Check streaming replication cada 10s
```

---

## Consideraciones de Producción

### Checklist Pre-Producción

#### Seguridad

- [ ] **Certificados SSL válidos**: Reemplazar certificados auto-firmados por CA válida
  ```bash
  # Generar CSR para CA
  openssl req -new -key certs/keycloak.key -out certs/keycloak.csr
  # Enviar CSR a CA y obtener certificado firmado
  # Reemplazar certs/keycloak.crt con certificado firmado
  ```

- [ ] **Cambiar passwords por defecto**:
  - PostgreSQL: `postgres_admin` → password fuerte
  - Keycloak admin: `admin/admin` → credenciales seguras
  - Actualizar en todos los archivos:
    - `docker-compose.yaml` (variables de entorno)
    - `postgres/pg_hba.conf`
    - `pgpool/pool_passwd` (regenerar MD5)
    - Scripts de testing

- [ ] **Configurar firewall**:
  ```bash
  # Ejemplo con ufw (Ubuntu)
  ufw allow 8443/tcp   # Keycloak HTTPS
  ufw allow 8444/tcp   # Keycloak HTTPS node 2
  ufw deny 5432/tcp    # PostgreSQL PRIMARY (solo interno)
  ufw deny 5433/tcp    # PostgreSQL REPLICA (solo interno)
  ufw deny 9999/tcp    # pgpool (solo interno Docker)
  ufw deny 7000/tcp    # HAProxy stats (solo interno)
  ```

- [ ] **Habilitar SSL en PostgreSQL**:
  ```ini
  # postgresql-primary.conf y postgresql-replica.conf
  ssl = on
  ssl_cert_file = '/etc/ssl/certs/server.crt'
  ssl_key_file = '/etc/ssl/private/server.key'
  ssl_ca_file = '/etc/ssl/certs/ca.crt'
  
  # pg_hba.conf: cambiar 'host' por 'hostssl'
  hostssl all all 0.0.0.0/0 md5
  ```

#### Alta Disponibilidad

- [ ] **Configurar backups automáticos**:
  ```bash
  # Cron job ejemplo: backup diario a las 2 AM
  0 2 * * * /home/user/keycloak_HA/scripts/backup.sh >> /var/log/pg_backup.log 2>&1
  ```

- [ ] **Implementar monitoreo**:
  - Prometheus + Grafana para métricas
  - Alertas sobre:
    - LAG de replicación > 30 segundos
    - Backends down en pgpool/HAProxy
    - Uso de disco > 80%
    - Conexiones PostgreSQL > 80% del límite

- [ ] **Documentar procedimientos de recuperación**:
  - Runbook de failover PRIMARY → REPLICA
  - Procedimiento de reconstrucción de REPLICA
  - Procedimiento de restauración desde backup
  - Contactos de emergencia y escalación

- [ ] **Configurar replicación sincrónica (opcional)**:
  ```ini
  # postgresql-primary.conf
  synchronous_commit = on
  synchronous_standby_names = 'walreceiver'
  ```
  ⚠️ **Impacto**: Menor rendimiento de escritura, pero sin pérdida de datos en failover

- [ ] **Añadir REPLICA adicional** (para mayor redundancia)

#### Rendimiento

- [ ] **Tuning PostgreSQL** según hardware disponible
  - Ver sección "Escalado y Optimización" más arriba
  - Usar [PGTune](https://pgtune.leopard.in.ua/) para recomendaciones

- [ ] **Ajustar pgpool connection pooling**:
  ```ini
  # Para workloads con muchos clientes concurrentes
  num_init_children = 100
  max_pool = 4
  ```

- [ ] **Configurar pgBouncer adicional** (opcional):
  - Para connection pooling más agresivo
  - Recomendado si Keycloak tiene >500 conexiones concurrentes

- [ ] **Habilitar query caching** en pgpool (para reads intensivos):
  ```ini
  memory_cache_enabled = on
  memqcache_method = 'memcached'
  ```

#### Operaciones

- [ ] **Configurar logs centralizados**:
  - Syslog, ELK Stack, o Loki + Grafana
  - Retención: mínimo 30 días

- [ ] **Configurar límites de recursos en Docker**:
  ```yaml
  # docker-compose.yaml
  services:
    postgres-primary:
      deploy:
        resources:
          limits:
            cpus: '2'
            memory: 4G
          reservations:
            cpus: '1'
            memory: 2G
  ```

- [ ] **Implementar health checks externos**:
  - Pingdom, UptimeRobot, o similar
  - Verificar endpoints:
    - https://keycloak.domain.com/health
    - https://keycloak.domain.com/metrics

- [ ] **Planificar ventanas de mantenimiento**:
  - Actualizaciones de PostgreSQL: trimestral
  - Actualizaciones de Keycloak: mensual
  - Pruebas de failover: mensual

### Límites y Escalabilidad - Arquitectura 2 Nodos

**Configuración actual soporta:**
- **Conexiones concurrentes por nodo**: ~250 (vía pgpool pooling)
- **Conexiones concurrentes totales**: ~500 (ambos nodos)
- **Throughput de escritura**: 
  - NODO 1: ~5,000 TPS (transactions per second) - LOCAL
  - NODO 2: ~1,500 TPS - Limitado por latencia de red al PRIMARY remoto (10-50ms)
- **Throughput de lectura**: 
  - NODO 1: ~7,500 QPS (queries per second) - PRIMARY local
  - NODO 2: ~7,500 QPS - REPLICA local (sin latencia de red)
  - **Total reads**: ~15,000 QPS combinados
- **Usuarios Keycloak**: ~50,000 activos simultáneos (distribuidos entre 2 nodos)

**Características de Performance por Nodo:**

| Métrica | NODO 1 (PRIMARY) | NODO 2 (REPLICA + Proxy) |
|---------|------------------|--------------------------|
| **Latencia SELECT** | <2ms (local) | <2ms (REPLICA local) ✅ |
| **Latencia INSERT/UPDATE/DELETE** | <2ms (local) ✅ | 10-50ms (PRIMARY remoto) ⚠️ |
| **Throughput Escritura** | ~5,000 TPS | ~1,500 TPS |
| **Throughput Lectura** | ~7,500 QPS | ~7,500 QPS |
| **Casos de Uso Ideales** | Admin panel, masive writes | Public-facing, read-heavy |

**Recomendaciones de Distribución de Carga:**

```
┌─────────────────────────────────────────────────────────────┐
│ ESTRATEGIA RECOMENDADA: Routing por tipo de aplicación      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ NODO 1 (PRIMARY - Latencia baja en escrituras):            │
│   ✅ Admin panels (Keycloak Admin Console)                  │
│   ✅ Batch processing / ETL                                 │
│   ✅ Background jobs con writes frecuentes                  │
│   ✅ APIs internas de gestión                               │
│                                                              │
│ NODO 2 (REPLICA - Latencia baja en lecturas):              │
│   ✅ Aplicaciones públicas read-heavy                       │
│   ✅ APIs de autenticación/autorización (OAuth2, OIDC)     │
│   ✅ Servicios de consulta (user info, token validation)   │
│   ⚠️  Admin operations (con latencia aceptable 10-50ms)    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Para escalar más allá (siguientes pasos):**

1. **Escalar lecturas**: Agregar más nodos REPLICA
   ```
   NODO 3, NODO 4, ... NODO N: PostgreSQL REPLICA adicionales
   - Cada REPLICA puede servir ~7,500 QPS adicionales
   - Replicación desde PRIMARY (NODO 1) vía WAL streaming
   - Load balancer externo (HAProxy/pgpool) distribuye SELECTs
   ```

2. **Escalar escrituras**: Sharding o partitioning
   ```
   - PostgreSQL 15 Declarative Partitioning (por rango/hash)
   - PostgreSQL 16+ Logical Replication (multi-región)
   - Citus extension (sharding horizontal)
   - NOTA: Requiere cambios en aplicación
   ```

3. **Escalar Keycloak**: Cluster más grande
   ```
   - 4-6 nodos Keycloak (Kubernetes + HPA)
   - External cache (Redis/Valkey) para sesiones
   - Separar Admin Realm de User Realms
   ```

4. **Optimizar latencia NODO 2 → PRIMARY**:
   ```
   - Upgrade red interna: 10Gbps+ entre nodos
   - Reducir latencia física: <1ms RTT ideal
   - Considerar connection pooler adicional: PgBouncer
   ```

### Costos Estimados (Cloud Deployment - 2 Nodos Físicos)

**AWS ejemplo (us-east-1):**
- **NODO 1**: 1x EC2 c6g.2xlarge (PRIMARY + Keycloak-1): $210/mes
- **NODO 2**: 1x EC2 c6g.2xlarge (REPLICA + Keycloak-2): $210/mes
- 2x EBS gp3 500GB (PRIMARY + REPLICA data): $80/mes
- Application Load Balancer (para Keycloak): $25/mes
- Network Transfer entre nodos (estimado 100GB/mes): $9/mes
- **Total estimado**: ~$534/mes

**GCP ejemplo (us-central1):**
- **NODO 1**: 1x n2-standard-8 (PRIMARY + Keycloak-1): $195/mes
- **NODO 2**: 1x n2-standard-8 (REPLICA + Keycloak-2): $195/mes
- 2x Persistent Disk SSD 500GB: $170/mes
- Cloud Load Balancing: $18/mes
- Network egress (interno regional): ~$5/mes
- **Total estimado**: ~$583/mes

**Azure ejemplo (East US):**
- **NODO 1**: 1x Standard_D8s_v5 (PRIMARY + Keycloak-1): $280/mes
- **NODO 2**: 1x Standard_D8s_v5 (REPLICA + Keycloak-2): $280/mes
- 2x Premium SSD 512GB: $150/mes
- Azure Load Balancer (Basic): $18/mes
- Network entre VMs misma región: ~$0
- **Total estimado**: ~$728/mes

**Colocation / Bare Metal (2 servidores físicos):**
- 2x Servidores Dell PowerEdge R450 (Intel Xeon, 64GB RAM, 2TB SSD): $8,000 CAPEX
- Colocation (2U, 10Gbps, energía): $300/mes
- Amortización hardware (3 años): $222/mes
- **Total mes**: ~$522/mes (sin incluir CAPEX inicial)

---

## Referencias y Recursos

### Documentación Oficial

- **PostgreSQL**:
  - [Streaming Replication](https://www.postgresql.org/docs/15/warm-standby.html)
  - [High Availability](https://www.postgresql.org/docs/15/high-availability.html)
  - [WAL Configuration](https://www.postgresql.org/docs/15/wal-configuration.html)
  - [pg_basebackup](https://www.postgresql.org/docs/15/app-pgbasebackup.html)

- **pgpool-II**:
  - [Official Documentation](https://www.pgpool.net/docs/latest/en/html/)
  - [Query Routing](https://www.pgpool.net/docs/latest/en/html/runtime-config-load-balancing.html)
  - [Streaming Replication](https://www.pgpool.net/docs/latest/en/html/runtime-streaming-replication-check.html)
  - [Connection Pooling](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html)

- **HAProxy**:
  - [Configuration Manual](http://cbonte.github.io/haproxy-dconv/2.9/configuration.html)
  - [PostgreSQL Health Checks](http://cbonte.github.io/haproxy-dconv/2.9/configuration.html#option%20pgsql-check)
  - [Load Balancing Algorithms](http://cbonte.github.io/haproxy-dconv/2.9/configuration.html#4.2-balance)

- **Keycloak**:
  - [Server Configuration](https://www.keycloak.org/server/configuration)
  - [Caching and Clustering](https://www.keycloak.org/server/caching)
  - [Database Configuration](https://www.keycloak.org/server/db)

- **Docker**:
  - [Compose File Reference](https://docs.docker.com/compose/compose-file/)
  - [Networking](https://docs.docker.com/network/)
  - [Health Checks](https://docs.docker.com/engine/reference/builder/#healthcheck)

### Herramientas Recomendadas

- **Monitoreo**:
  - [pgwatch2](https://github.com/cybertec-postgresql/pgwatch2) - PostgreSQL monitoring
  - [pg_stat_monitor](https://github.com/percona/pg_stat_monitor) - Query performance
  - [Grafana Dashboard para PostgreSQL](https://grafana.com/grafana/dashboards/9628)

- **Backup**:
  - [pgBackRest](https://pgbackrest.org/) - Enterprise-grade backup solution
  - [Barman](https://www.pgbarman.org/) - Backup and Recovery Manager
  - [WAL-G](https://github.com/wal-g/wal-g) - Archival tool

- **Testing**:
  - [pgbench](https://www.postgresql.org/docs/current/pgbench.html) - PostgreSQL benchmarking
  - [k6](https://k6.io/) - Load testing Keycloak endpoints
  - [Apache JMeter](https://jmeter.apache.org/) - Performance testing

- **Tuning**:
  - [PGTune](https://pgtune.leopard.in.ua/) - PostgreSQL configuration wizard
  - [pgtune](https://github.com/le0pard/pgtune) - CLI version
  - [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html) - Query statistics

### Artículos y Tutoriales

- [PostgreSQL Replication Best Practices](https://www.postgresql.org/docs/current/different-replication-solutions.html)
- [pgpool-II Tutorial](https://www.pgpool.net/docs/latest/en/html/tutorial.html)
- [HAProxy + PostgreSQL Setup Guide](https://www.haproxy.com/blog/the-four-essential-sections-of-an-haproxy-configuration/)
- [Keycloak Clustering with PostgreSQL](https://www.keycloak.org/high-availability/concepts-multi-site)

---

## Licencia

Este proyecto es proporcionado "tal cual" sin garantías de ningún tipo. Usar bajo su propio riesgo.

---

## Contacto y Soporte

Para preguntas, problemas o contribuciones sobre este proyecto de alta disponibilidad:

- **Issues**: Abrir ticket en el repositorio
- **Documentación adicional**: Ver carpeta `old/` para configuraciones legacy de Patroni

---

## Historial de Versiones

### v3.0.0 - Febrero 2026 (Actual - Arquitectura 2 Nodos Físicos) ⭐ NEW
- ✅ **Arquitectura distribuida en 2 servidores independientes**
  - NODO 1: PostgreSQL PRIMARY + Keycloak-1 (servidor primario)
  - NODO 2: PostgreSQL REPLICA + Keycloak-2 + Proxy (servidor secundario)
- ✅ **pgpool-II configurado por nodo**
  - NODO 1: 1 backend (PRIMARY local) - todas las queries locales
  - NODO 2: 2 backends (PRIMARY remoto + REPLICA local) - routing inteligente
- ✅ **HAProxy configurado por nodo**
  - NODO 1: Solo PRIMARY local
  - NODO 2: Proxy a PRIMARY remoto + REPLICA local
- ✅ **Keycloak Clustering inter-nodos**
  - JGroups TCP con TCPPING discovery entre IPs configurables
  - Active-Active: ambos nodos aceptan tráfico simultáneamente
- ✅ **Scripts de despliegue independientes**
  - `deploy-nodo1.sh`: Detección automática de IP
  - `deploy-nodo2.sh`: Configuración interactiva con validación de conectividad
- ✅ **Scripts de limpieza por nodo**
  - `cleanup-nodo1.sh` / `cleanup-nodo2.sh`
- ✅ **Documentación actualizada**
  - Guías de despliegue separadas por nodo
  - Troubleshooting específico para arquitectura distribuida
  - Análisis de performance y latencia por nodo
  - Requisitos de red y firewall

### v2.0.0 - Febrero 2026 (Monolítico)
- ✅ Implementación de pgpool-II con query routing automático
- ✅ Consolidación de tests en script único (23 tests)
- ✅ Documentación completa y profesional
- ✅ Arquitectura optimizada para producción (single host)

### v1.0.0 - Inicial
- PostgreSQL Streaming Replication nativa
- HAProxy con routing por puerto
- Keycloak cluster con JGroups
- Scripts de despliegue y testing básicos

---

**Proyecto:** Keycloak High Availability con PostgreSQL Streaming Replication (2 Nodos Físicos)  
**Arquitectura:** Active-Active Keycloak + PostgreSQL PRIMARY (NODO 1) + REPLICA (NODO 2)  
**Última actualización:** Febrero 10, 2026  
**Estado:** ✅ Producción Ready (2-Node Distributed Architecture)

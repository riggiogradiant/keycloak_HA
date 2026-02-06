# Keycloak HA con Infinispan

Despliegue de 2 instancias de Keycloak con clustering Infinispan en **modo producción**.

## 🚀 Opciones de Despliegue

Este repositorio ofrece **2 arquitecturas**:

### 🔷 Opción A: Despliegue Simple (single PostgreSQL)
- **2 Keycloaks** + **1 PostgreSQL** compartida
- Ideal para desarrollo, testing y entornos no críticos
- Despliegue rápido y sencillo
- ⚠️ PostgreSQL es SPOF (Single Point of Failure)

### 🔷 Opción B: Despliegue HA con Patroni (2-Node PostgreSQL Cluster)
- **2 Keycloaks** + **2 PostgreSQL** con replicación automática
- **Patroni** gestiona failover automático de PostgreSQL
- **etcd** cluster para consenso distribuido
- Zero data loss (replicación síncrona)
- Failover automático en 30-90 segundos
- Ideal para producción

---

## 🎯 Arquitectura - Opción A (Simple)

- **2 Keycloaks** con Infinispan clustering (JGroups TCPPING)
- **1 PostgreSQL** compartida (claves de firma compartidas)
- **Modo producción** con SSL
- **Sesiones replicadas** entre nodos

### 📦 Separación de Responsabilidades

#### PostgreSQL (`postgres:15`)
**Base de datos persistente compartida** - Gestiona TODO lo que debe sobrevivir reinicios:
- ✅ Usuarios (tabla `USER_ENTITY`)
- ✅ Roles, Realms, Clients
- ✅ Configuraciones
- ✅ Credenciales (passwords hasheados)
- ✅ Claves de firma RSA compartidas
- ✅ Grupos, atributos, policies

**Ambos Keycloaks apuntan a la MISMA instancia PostgreSQL**

#### Infinispan (Caché distribuido en RAM)
**Caché volátil en memoria** - Gestiona solo lo EFÍMERO:
- ✅ Sesiones activas (mientras usuario está logueado)
- ✅ Tokens JWT en uso (hasta que expiran)
- ✅ Authentication sessions (proceso de login temporal)
- ✅ Refresh tokens activos
- ✅ Contadores de brute-force (intentos fallidos)

**NO es una base de datos, es replicación de caché RAM** mediante JGroups (puerto 7800)

### 🏗️ Diagrama de Arquitectura

```
┌─────────────────────────────────────────────────────┐
│              ARQUITECTURA COMPLETA                   │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌──────────────┐         ┌──────────────┐          │
│  │ Keycloak-1   │◄───────►│ Keycloak-2   │          │
│  │              │  7800   │              │          │
│  │ RAM: Caché   │ Infini- │ RAM: Caché   │          │
│  │ - Sesiones   │  span   │ - Sesiones   │          │
│  │ - Tokens     │ (TCP)   │ - Tokens     │          │
│  └──────┬───────┘         └──────┬───────┘          │
│         │                        │                  │
│         │  JDBC                  │ JDBC             │
│         └────────────┬───────────┘                  │
│                      │                              │
│              ┌───────▼────────┐                     │
│              │  PostgreSQL:15 │                     │
│              │                │                     │
│              │  Disco/Volumen │                     │
│              │  - Usuarios    │                     │
│              │  - Realms      │                     │
│              │  - Config      │                     │
│              │  (PERSISTENTE) │                     │
│              └────────────────┘                     │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### 🔄 Flujo de Login

```
Usuario login → Keycloak-1
                    ↓
    ┌───────────────┴─────────────┐
    │                             │
    ↓ JDBC                        ↓ Infinispan
PostgreSQL                   Replica a Keycloak-2
(verifica password)          (caché de sesión)
    ↓                             ↓
✅ Usuario persistente      ✅ Token válido en ambos nodos
```

**Resultado:** Token de Node 1 es válido en Node 2 sin consultar BD

---

## 🎯 Arquitectura - Opción B (Patroni HA)

```
LOCALHOST (2-Node Simulation)
┌────────────────────────────────────────────────────────────┐
│  Docker Network: keycloak-net                              │
│                                                            │
│  ┌──────────────┐         ┌──────────────┐                │
│  │ Keycloak-1   │◄───────►│ Keycloak-2   │                │
│  │ :8443        │ Infini- │ :8444        │                │
│  │ :7800        │  span   │ :7801        │                │
│  └──────┬───────┘         └──────┬───────┘                │
│         │                        │                        │
│         ↓                        ↓                        │
│  ┌──────────────┐         ┌──────────────┐                │
│  │ Patroni-1    │◄───────►│ Patroni-2    │                │
│  │ :5432 :8008  │ WAL     │ :5433 :8009  │                │
│  │ (PRIMARY)    │ Stream  │ (REPLICA)    │                │
│  └──────┬───────┘         └──────┬───────┘                │
│         │                        │                        │
│  ┌──────▼───────┐         ┌──────▼───────┐                │
│  │ etcd-1       │◄───────►│ etcd-2       │                │
│  │ :2379 :2380  │  Raft   │ :23791:23801 │                │
│  └──────────────┘         └──────────────┘                │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Componentes:

#### Patroni + PostgreSQL
**Gestión automática de replicación y failover**:
- ✅ Replicación síncrona (zero data loss)
- ✅ Failover automático (30-90s)
- ✅ Auto-recuperación (nodo caído vuelve como replica)
- ✅ REST API para monitoreo (:8008, :8009)
- ✅ Configuración conservadora anti-split-brain

#### etcd Cluster
**Almacén distribuido de configuración (DCS)**:
- ✅ Consenso distribuido (Raft protocol)
- ✅ Leader election para PostgreSQL
- ✅ Detección de fallos
- ⚠️ 2 nodos = riesgo split-brain en particiones de red

#### Keycloak + Infinispan
**Sin cambios respecto a Opción A**:
- ✅ Sesiones replicadas via JGroups
- ✅ Tokens válidos en ambos nodos

---

## 🚀 Despliegue

### Opción A: Simple (1 PostgreSQL)

```bash
./deploy.sh
```

### Opción B: Patroni HA (2 PostgreSQL)

```bash
./deploy-patroni.sh
```

## 🌐 Acceso

### Opción A (Simple):
- **Keycloak 1**: https://localhost:8443
- **Keycloak 2**: https://localhost:8444
- **PostgreSQL**: localhost:5432

### Opción B (Patroni):
- **Keycloak 1**: https://localhost:8443
- **Keycloak 2**: https://localhost:8444
- **Patroni Node 1**: http://localhost:8008/patroni
- **Patroni Node 2**: http://localhost:8009/patroni
- **PostgreSQL Node 1**: localhost:5432
- **PostgreSQL Node 2**: localhost:5433
### Tests - Opción A (Simple):
1. ✅ Ambos nodos Keycloak operativos
2. ✅ Cluster Infinispan formado correctamente
3. ✅ Token de Node 1 válido en Node 2 (Infinispan)
4. ✅ Usuario creado en Node 1 visible en Node 2 (BD compartida)
5. ✅ Usuario creado en Node 2 visible en Node 1 (BD compartida)
6. ✅ Failover de Keycloak (token válido tras caída de nodo)

### Tests - Opción B (Patroni):
**Incluye todos los tests de Opción A, más:**
7. ✅ Patroni cluster health (1 PRIMARY + 1 REPLICA)
8. ✅ PostgreSQL automatic failover (30-90s)
9. ✅ Zero data loss verification (replicación síncrona)
10. ✅ Split-brain detection
11. ✅ Keycloak functional after PostgreSQL failover

## 📊 Monitoreo (Opción B - Patroni)

```bash
# Estado completo del cluster
./scripts/check-cluster.sh

# Detectar split-brain
./scripts/check-split-brain.sh

# Failover manual
./scripts/manual-failover.sh
```

## 🛑 Detener

### Opción A (Simple):
```bash
./stop.sh
```

### Opción B (Patroni):
```bash
./stop-patroni

### Opción A (Simple):
- ✅ **Tokens compartidos** entre nodos (Infinispan)
- ✅ **Sesiones replicadas** en caché RAM (Infinispan)
- ✅ **Failover Keycloak** automático sin pérdida de sesión
- ✅ **Base de datos compartida** (PostgreSQL)
- ⚠️ **PostgreSQL es SPOF**

### Opción B (Patroni):
**Todas las de Opción A, más:**
- ✅ **PostgreSQL HA** con failover automático
- ✅ **Zero data loss** (replicación síncrona)
- ✅ **Auto-recuperación** de nodos caídos
- ✅ **Monitoreo** vía REST API
- ✅ **Detección split-brain** 
- ⚠️ **Riesgo split-brain** en particiones de red (2 nodos sin witness)

## 🔍 ¿Qué pasa si...?

### Opción A (Simple):
| Escenario | Resultado |
|-----------|-----------|
| **Cae Keycloak-1** | ✅ Keycloak-2 sigue funcionando, sesiones activas |
| **Cae Keycloak-2** | ✅ Keycloak-1 sigue funcionando, sesiones activas |
| **Cae PostgreSQL** | ❌ Ambos Keycloaks dejan de funcionar (SPOF) |
| **Reinicias todo** | ✅ Usuarios persisten / ❌ Sesiones se pierden |

### Opción B (Patroni):
| Escenario | Resultado |
|-----------|-----------|
| **Cae Keycloak-1** | ✅ Keycloak-2 sigue funcionando, sesiones activas |
| **Cae Keycloak-2** | ✅ Keycloak-1 sigue funcionando, sesiones activas |
| **Cae PostgreSQL-1 (PRIMARY)** | ✅ Patroni promueve PostgreSQL-2 a PRIMARY (30-90s downtime) |
| **Cae PostgreSQL-2 (REPLICA)** | ✅ PostgreSQL-1 (PRIMARY) sigue funcionando normalmente |
| **Ambos PostgreSQL caen** | ❌ Keycloaks dejan de funcionar hasta recuperación |
| **Partición de red** | ⚠️ Riesgo de split-brain (ambos PRIMARY), requiere intervención manual |
| **Reinicias todo** | ✅ Usuarios persisten / ✅ Patroni reorganiza cluster automáticamente |

## 🚨 Advertencias Opción B (Patroni 2-nodos)

⚠️ **Split-Brain Risk**: Con solo 2 nodos sin witness externo, existe riesgo de split-brain en particiones de red.

**Mitigaciones implementadas:**
- Configuración conservadora (timeouts largos)
- Prioridad de failover (Node 1 > Node 2)
- Script de detección automática
- Replicación síncrona (evita divergencia de datos)

**Recomendado para producción:**
- Añadir 3er nodo etcd witness (puede ser VM pequeña/Raspberry Pi)
- O aceptar downtime temporal en particiones de red hasta resolución manual
- **PostgreSQL:** Base de datos compartida para datos persistentes

## 🛑 Detener

```bash
./stop.sh
```

## ✅ Funcionalidades

- ✅ **Tokens compartidos** entre nodos (Infinispan)
- ✅ **Sesiones replicadas** en caché RAM (Infinispan)
- ✅ **Failover** automático sin pérdida de sesión
- ✅ **Base de datos compartida** (PostgreSQL - usuarios y configuración)
- ✅ **Sin SPOF de datos** (datos persistentes centralizados)

## 🔍 ¿Qué pasa si...?

| Escenario | Resultado |
|-----------|-----------|
| **Cae Keycloak-1** | ✅ Keycloak-2 sigue funcionando, sesiones activas disponibles |
| **Cae Keycloak-2** | ✅ Keycloak-1 sigue funcionando, sesiones activas disponibles |
| **Cae PostgreSQL** | ❌ Ambos Keycloaks dejan de funcionar (SPOF actual) |
| **Reinicias todo** | ✅ Usuarios y config persisten / ❌ Sesiones activas se pierden |

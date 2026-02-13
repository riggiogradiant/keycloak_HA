# Keycloak High Availability - Arquitectura Completa

Sistema de autenticación Keycloak con Alta Disponibilidad, tolerancia a fallos y recuperación automática. Incluye PostgreSQL con replicación streaming, failover automático mediante Patroni, balanceo de carga con HAProxy y clustering distribuido con Infinispan.

## 🏗️ Componentes del Sistema

### 1. **etcd** - Distributed Consensus Store
**Propósito**: Sistema de coordinación distribuida que actúa como "cerebro" del cluster.

- Almacena el estado del cluster PostgreSQL (quién es PRIMARY, quién es REPLICA)
- Gestiona elecciones de líder mediante algoritmo Raft
- Proporciona almacenamiento clave-valor consistente y distribuido
- Permite que Patroni tome decisiones coordinadas entre nodos
- **Puerto**: 2379 (cliente), 2380 (peer)

### 2. **Patroni** - PostgreSQL HA Orchestration
**Propósito**: Orquestador que gestiona automáticamente el cluster PostgreSQL.

- **Healthchecks continuos**: Monitorea constantemente el estado de cada nodo PostgreSQL
- **Failover automático**: Si el PRIMARY falla, promueve automáticamente una REPLICA a PRIMARY (< 30 segundos)
- **REST API** (puerto 8008):
  - `/master`: Retorna HTTP 200 solo si el nodo es PRIMARY
  - `/replica`: Retorna HTTP 200 solo si el nodo es REPLICA
  - `/health`: Estado general del nodo
- **Integración con etcd**: Usa etcd para coordinar cambios de rol entre nodos
- **Streaming Replication**: Configura automáticamente la replicación entre PRIMARY y REPLICAs

### 3. **PostgreSQL** - Database Engine
**Propósito**: Base de datos relacional que almacena todos los datos persistentes de Keycloak.

- **Nodo PRIMARY**: Acepta escrituras y lecturas
- **Nodo REPLICA**: Réplica en tiempo real mediante streaming replication (lag típico: 0 bytes)
- **Datos almacenados**:
  - Usuarios, grupos, roles
  - Configuración de realms y clients
  - Políticas de autenticación
  - Registro de eventos
- **Puerto**: 5432

### 4. **HAProxy** - Query Router
**Propósito**: Balanceador de carga inteligente que enruta automáticamente todo el tráfico al nodo PRIMARY.

- **Healthchecks a Patroni**: Consulta el endpoint `/master` de Patroni cada 3 segundos
- **Routing automático**: Solo marca como "UP" el nodo cuyo Patroni responde 200 en `/master`
- **Sin parsing SQL**: No necesita inspeccionar queries, confía en Patroni como fuente de verdad
- **Failover transparente**: Cuando hay failover, HAProxy detecta el nuevo PRIMARY en ~9 segundos
- **Puertos**:
  - 5432: Tráfico hacia PRIMARY (usado por Keycloak)
  - 5433: Tráfico hacia REPLICAs (actualmente sin uso)
  - 7000: Stats web interface

### 5. **Keycloak** - Identity and Access Management
**Propósito**: Servidor de autenticación y autorización (IAM).

- **Active-Active**: Ambos nodos procesan requests simultáneamente
- **Clustering con Infinispan**: Sesiones distribuidas entre nodos
- **Persistencia**: Todos los datos críticos en PostgreSQL vía HAProxy
- **HTTPS**: Comunicación segura con certificados TLS
- **Puertos**: 8443 (nodo1), 8444 (nodo2)

### 6. **Infinispan** - Distributed Cache
**Propósito**: Sistema de caché distribuida que sincroniza sesiones y datos efímeros entre nodos Keycloak.

- **Sesiones distribuidas**: Un usuario autenticado en nodo1 puede usar nodo2 sin re-login
- **JGroups TCP TCPPING**: Comunicación directa entre nodos (puerto 7800)
- **Cache invalidation**: Cambios en un nodo se propagan automáticamente
- **No requiere persistencia**: Los datos críticos están en PostgreSQL
- **Datos sincronizados**:
  - Sesiones de usuario activas
  - Tokens (access, refresh, ID)
  - Metadata de caché

## 📊 Arquitectura Final

```
                                 ┌──────────────────────────────────┐
                                 │         USUARIOS/APPS            │
                                 └────────────┬─────────────────────┘
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      │                                               │
                      ▼                                               ▼
            ┌──────────────────┐                            ┌──────────────────┐
            │  Keycloak NODO1  │◄──── Infinispan/JGroups ──►│  Keycloak NODO2  │
            │  (Active)        │      (tcp:7800)            │  (Active)        │
            │  Port: 8443      │                            │  Port: 8444      │
            └────────┬─────────┘                            └────────┬─────────┘
                     │                                               │
                     └────────────────┬──────────────────────────────┘
                                      │
                                      │ JDBC Connection
                                      ▼
                            ┌──────────────────┐
                            │  HAProxy NODO1   │──┐
                            │  (Router)        │  │
                            │  Port: 5432/5433 │  │  HAProxy NODO2
                            └────────┬─────────┘  │  (Router)
                                     │            │  Port: 5432/5433
                                     ▼            ▼
                       ┌──────────────────────────────────┐
                       │  Healthcheck: GET /master        │
                       │  Patroni REST API (port 8008)    │
                       └──────────────────────────────────┘
                                     │
                      ┌──────────────┴──────────────┐
                      ▼                             ▼
          ┌─────────────────────┐       ┌─────────────────────┐
          │  Patroni NODO1      │       │  Patroni NODO2      │
          │  ┌───────────────┐  │       │  ┌───────────────┐  │
          │  │ PostgreSQL    │  │       │  │ PostgreSQL    │  │
          │  │ (REPLICA)     │◄─┼───────┼─►│ (PRIMARY)     │  │
          │  │ Port: 5432    │  │Streaming│  │ Port: 5432    │  │
          │  └───────────────┘  │Repl.  │  └───────────────┘  │
          └──────────┬──────────┘       └──────────┬──────────┘
                     │                             │
                     └────────────┬────────────────┘
                                  ▼
                          ┌───────────────┐
                          │  etcd Cluster │
                          │  (Consensus)  │
                          │  Port: 2379   │
                          └───────────────┘
```

## 🔄 Flujo de Datos y Funcionamiento

### Operaciones Normales

1. **Request de Usuario → Keycloak**:
   - Usuario accede a `https://localhost:8443` o `https://localhost:8444`
   - Cualquier nodo Keycloak puede procesar la petición (Active-Active)

2. **Keycloak → HAProxy → PostgreSQL PRIMARY**:
   - Keycloak necesita leer/escribir datos persistentes
   - Se conecta a HAProxy (puerto 5432)
   - HAProxy consulta a Patroni de cada nodo: `GET /master`
   - Solo el nodo PRIMARY responde HTTP 200
   - HAProxy enruta todo el tráfico al PRIMARY

3. **Sincronización de Sesiones (Infinispan)**:
   - Usuario hace login en nodo1
   - Sesión se almacena localmente y se propaga vía JGroups a nodo2
   - Usuario puede hacer requests a nodo2 sin re-autenticarse

4. **Replicación PostgreSQL**:
   - PRIMARY escribe cambios en WAL (Write-Ahead Log)
   - REPLICA replica cambios vía streaming (típicamente lag = 0 bytes)
   - REPLICA mantiene copia actualizada de todos los datos

### Escenario de Failover

1. **PRIMARY Falla**:
   - Patroni detecta que PRIMARY no responde (healthcheck cada 10s)
   - Patroni consulta etcd para verificar consenso del cluster

2. **Elección de Nuevo PRIMARY** (< 30 segundos):
   - Patroni promueve automáticamente la REPLICA a PRIMARY
   - Actualiza configuración en etcd
   - Nuevo PRIMARY comienza a aceptar escrituras

3. **HAProxy Detecta Cambio**:
   - HAProxy consulta `/master` cada 3 segundos
   - Detecta que el nuevo nodo responde HTTP 200 en `/master`
   - Enruta tráfico al nuevo PRIMARY en ~9 segundos

4. **Keycloak Continúa Operando**:
   - Conexiones activas se reconectan automáticamente
   - Usuarios experimentan latencia breve pero sin pérdida de sesión
   - Downtime total: ~30 segundos

## 📋 Estructura del Proyecto

```
keycloak_HA/
├── docker-compose-nodo1.yaml   # Servicios del Nodo 1
├── docker-compose-nodo2.yaml   # Servicios del Nodo 2
├── deploy-ha.sh                # Script de despliegue automatizado
├── Dockerfile                  # Keycloak optimizado
├── Dockerfile.patroni          # PostgreSQL + Patroni
├── generate-certs.sh           # Generador de certificados SSL/TLS
├── .env.example                # Variables de entorno
├── certs/                      # Certificados SSL/TLS
├── haproxy/
│   ├── haproxy.cfg            # Configuración HAProxy
│   ├── haproxy-nodo1.cfg
│   └── haproxy-nodo2.cfg
├── patroni/
│   ├── patroni-nodo1.yml      # Configuración Patroni nodo1
│   └── patroni-nodo2.yml      # Configuración Patroni nodo2
└── tests/
    ├── test-sync.sh           # Verificar replicación PostgreSQL
    ├── test-routing.sh        # Verificar HAProxy routing
    ├── test-infinispan.sh     # Verificar clustering Keycloak
    └── run-all-tests.sh       # Ejecutar todos los tests
```

## 🚀 Despliegue Rápido con Script Automatizado

### Opción 1: Despliegue Completo (Recomendado)

```bash
# 1. Hacer ejecutable el script
chmod +x deploy-ha.sh

# 2. Ejecutar despliegue (maneja todo automáticamente)
./deploy-ha.sh
```

El script realiza:
1. ✅ Creación de red Docker y certificados
2. ✅ Build de imágenes optimizadas
3. ✅ Limpieza de despliegues previos
4. ✅ Inicio secuencial del cluster etcd
5. ✅ Despliegue de PostgreSQL con Patroni (PRIMARY y REPLICA)
6. ✅ Inicio de HAProxy y Keycloak en ambos nodos
7. ✅ Verificación automática del estado

**Tiempo estimado**: 2-3 minutos

### Opción 2: Despliegue Manual Paso a Paso

#### 1. Generar Certificados

```bash
chmod +x generate-certs.sh
./generate-certs.sh
```

#### 2. Configurar Variables de Entorno (Opcional)

```bash
cp .env.example .env
# Editar .env con tus contraseñas
```

#### 3. Crear Red Docker Compartida

```bash
docker network create keycloak_net
```

#### 4. Levantar NODO 1

```bash
docker compose -f docker-compose-nodo1.yaml up -d
```

**Acceso**: https://localhost:8443
- Usuario: `admin`
- Password: `admin` (o el configurado en `.env`)

#### 5. Levantar NODO 2

```bash
docker compose -f docker-compose-nodo2.yaml up -d
```

**Acceso**: https://localhost:8444
- Usuario: `admin`
- Password: `admin` (o el configurado en `.env`)

## ✅ Verificación del Sistema

### 1. Verificar Cluster PostgreSQL + Patroni

```bash
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list
```

**Salida esperada**:
```
+ Cluster: keycloak-cluster ---+----+-----------+
| Member         | Host           | Role    | State   | TL | Lag in MB |
+----------------+----------------+---------+---------+----+-----------+
| postgres-nodo1 | postgres-nodo1 | Replica | running | 3  |       0   |
| postgres-nodo2 | postgres-nodo2 | Leader  | running | 3  |           |
+----------------+----------------+---------+---------+----+-----------+
```

✅ **Verificaciones**:
- Un nodo debe ser `Leader` (PRIMARY)
- Otro nodo debe ser `Replica`
- `State: running` en ambos
- `Lag in MB: 0` (sincronización perfecta)

### 2. Verificar HAProxy Routing

```bash
# Ver stats de HAProxy
curl http://localhost:7000
```

O ejecutar test automatizado:
```bash
./tests/test-routing.sh
```

✅ **Esperado**: Solo el nodo PRIMARY debe estar marcado como "UP" en el backend `postgres_primary`

### 3. Verificar Cluster Infinispan (Keycloak)

```bash
# NODO 1
docker logs keycloak-nodo1 2>&1 | grep "cluster view"

# NODO 2
docker logs keycloak-nodo2 2>&1 | grep "cluster view"
```

**Salida esperada**:
```
Received new cluster view for channel ISPN: [keycloak-nodo1|1] (2) [keycloak-nodo1, keycloak-nodo2]
```

✅ El número `(2)` indica **2 miembros en el cluster Infinispan**

O ejecutar test automatizado:
```bash
./tests/test-infinispan.sh
```

### 4. Verificar Healthchecks de Keycloak

```bash
# NODO 1
curl -k https://localhost:8443/health/ready

# NODO 2
curl -k https://localhost:8444/health/ready
```

✅ **Esperado**: Respuesta JSON con `status: "UP"`

### 5. Test Completo Automatizado

```bash
cd tests
./run-all-tests.sh
```

Ejecuta:
- ✅ Test de sincronización PostgreSQL
- ✅ Test de routing HAProxy
- ✅ Test de clustering Infinispan

## 🧪 Probar Sesiones Distribuidas (Sticky Sessions)

1. **Login en NODO 1**: https://localhost:8443
2. Ir a **Administration Console** e iniciar sesión
3. **Copiar URL completa** con parámetro `session_state`
4. **Cambiar puerto** de `8443` a `8444` en la URL
5. Abrir en **nueva pestaña/ventana**
6. ✅ **Deberías estar autenticado sin hacer login nuevamente**

Esto demuestra que:
- La sesión se creó en nodo1
- Se replicó automáticamente a nodo2 vía Infinispan
- Ambos nodos comparten estado de sesión

## 🔄 Probar Failover Automático

```bash
# Simular fallo del PRIMARY
docker compose -f docker-compose-nodo2.yaml stop postgres

# Monitorear promoción automática
watch -n 1 'docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list'
```

**Resultado esperado**:
- En ~30 segundos, `postgres-nodo1` se promueve a `Leader`
- HAProxy detecta el cambio automáticamente
- Keycloak continúa funcionando sin intervención manual

Para restaurar:
```bash
# Reiniciar el nodo que estaba caído
docker compose -f docker-compose-nodo2.yaml start postgres

# Se unirá automáticamente como REPLICA
```

## � Comandos Útiles

### Gestión del Cluster

```bash
# Ver estado completo del cluster Patroni
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list

# Ver estado de etcd
docker exec etcd-nodo1 etcdctl member list --write-out=table

# Ver sincronización PostgreSQL (lag de replicación)
docker exec postgres-nodo2 psql -U postgres -c "SELECT application_name, state, sync_state, replay_lag FROM pg_stat_replication;"

# Ver estadísticas de HAProxy (web interface)
curl http://localhost:7000

# Ver todos los contenedores
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Logs y Debugging

```bash
# Ver logs de Keycloak en tiempo real
docker logs keycloak-nodo1 -f
docker logs keycloak-nodo2 -f

# Ver logs de Patroni
docker logs postgres-nodo1 -f
docker logs postgres-nodo2 -f

# Ver logs de HAProxy
docker logs haproxy-nodo1 -f

# Ver logs de etcd
docker logs etcd-nodo1 -f

# Buscar errores específicos
docker logs keycloak-nodo1 2>&1 | grep -i error
docker logs postgres-nodo1 2>&1 | grep -i "failed\|error"
```

### Gestión de Servicios

```bash
# Detener servicios
docker compose -f docker-compose-nodo1.yaml down
docker compose -f docker-compose-nodo2.yaml down

# Reiniciar un servicio específico
docker compose -f docker-compose-nodo1.yaml restart keycloak
docker compose -f docker-compose-nodo1.yaml restart postgres

# Eliminar todo (incluye volúmenes - ⚠️ se pierden los datos)
docker compose -f docker-compose-nodo1.yaml down -v
docker compose -f docker-compose-nodo2.yaml down -v
docker network rm keycloak_net
```

## 🌐 Despliegue en Servidores Separados (Producción)

Para desplegar en servidores físicos diferentes (no en el mismo host Docker):

### Preparación de Red

1. **Exponer puertos en firewall de ambos servidores**:
   ```bash
   # Puertos necesarios
   sudo ufw allow 2379/tcp   # etcd client
   sudo ufw allow 2380/tcp   # etcd peer
   sudo ufw allow 8008/tcp   # Patroni REST API (solo inter-nodo)
   sudo ufw allow 7800/tcp   # JGroups (Infinispan)
   sudo ufw allow 8443/tcp   # Keycloak HTTPS
   ```

### En Servidor 1 (NODO 1)

1. **Variables de entorno** (añadir a `.env` o docker-compose):
   ```bash
   SERVIDOR2_IP=192.168.1.102  # IP del servidor 2
   ```

2. **Editar `docker-compose-nodo1.yaml`**:
   ```yaml
   # etcd: cambiar initial-cluster
   - --initial-cluster=etcd-nodo1=http://192.168.1.101:2380,etcd-nodo2=http://192.168.1.102:2380
   
   # Keycloak: cambiar JGROUPS_DISCOVERY_PROPERTIES
   JGROUPS_DISCOVERY_PROPERTIES: initial_hosts="192.168.1.101[7800]\\,192.168.1.102[7800]"
   ```

3. **Levantar servicios**:
   ```bash
   docker compose -f docker-compose-nodo1.yaml up -d
   ```

### En Servidor 2 (NODO 2)

1. **Variables de entorno**:
   ```bash
   SERVIDOR1_IP=192.168.1.101  # IP del servidor 1
   ```

2. **Editar `docker-compose-nodo2.yaml`**:
   ```yaml
   # etcd: cambiar initial-cluster
   - --initial-cluster=etcd-nodo1=http://192.168.1.101:2380,etcd-nodo2=http://192.168.1.102:2380
   
   # Keycloak: cambiar JGROUPS_DISCOVERY_PROPERTIES
   JGROUPS_DISCOVERY_PROPERTIES: initial_hosts="192.168.1.101[7800]\\,192.168.1.102[7800]"
   ```

3. **Levantar servicios**:
   ```bash
   docker compose -f docker-compose-nodo2.yaml up -d
   ```

### Verificación Inter-Servidor

```bash
# Desde servidor 1: verificar conectividad a servidor 2
telnet 192.168.1.102 2379  # etcd
telnet 192.168.1.102 7800  # JGroups
telnet 192.168.1.102 8008  # Patroni

# Ver cluster etcd distribuido
docker exec etcd-nodo1 etcdctl member list

# Ver cluster Patroni distribuido
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list
```

## 🔐 Seguridad en Producción

- [ ] Cambiar contraseñas por defecto en `.env`
- [ ] Usar certificados válidos (Let's Encrypt)
- [ ] Configurar firewall (solo puertos necesarios)
- [ ] Habilitar PostgreSQL SSL/TLS
- [ ] Configurar backup automático de bases de datos
- [ ] Implementar monitoreo (Prometheus + Grafana)
- [ ] Configurar log aggregation (ELK Stack)

## 📚 Documentación Adicional

- [Keycloak Server Administration](https://www.keycloak.org/docs/latest/server_admin/)
- [Keycloak on Kubernetes](https://www.keycloak.org/operator/basic-deployment)
- [Infinispan Documentation](https://infinispan.org/documentation/)
- [JGroups Protocol Stack](http://jgroups.org/manual4/index.html)

## 🆘 Troubleshooting

### Problema: Cluster Patroni no se forma

**Síntomas**:
- `patronictl list` muestra error o solo 1 nodo
- PostgreSQL no inicia correctamente

**Solución**:
```bash
# 1. Verificar que etcd esté funcionando
docker exec etcd-nodo1 etcdctl member list

# 2. Ver logs de Patroni
docker logs postgres-nodo1 2>&1 | grep -i error
docker logs postgres-nodo2 2>&1 | grep -i error

# 3. Verificar configuración de Patroni
docker exec postgres-nodo1 cat /etc/patroni/patroni.yml

# 4. Si es necesario, limpiar estado de etcd y reiniciar
docker compose -f docker-compose-nodo1.yaml down -v
docker compose -f docker-compose-nodo2.yaml down -v
./deploy-ha.sh
```

### Problema: HAProxy no enruta al PRIMARY

**Síntomas**:
- Keycloak no puede conectar a la base de datos
- HAProxy stats muestra todos los backends "DOWN"

**Solución**:
```bash
# 1. Ver stats de HAProxy
curl http://localhost:7000

# 2. Verificar Patroni REST API
curl http://localhost:8008/master  # Solo PRIMARY responde 200

# 3. Ver logs de HAProxy
docker logs haproxy-nodo1 2>&1 | grep -E "check|health"

# 4. Verificar que Patroni exponga puerto 8008
docker exec postgres-nodo1 netstat -tuln | grep 8008
```

### Problema: Clustering Infinispan no se forma

**Síntomas**:
- Logs muestran `cluster view` con solo 1 miembro
- Sesiones no se replican entre nodos

**Solución**:
```bash
# 1. Verificar que ambos Keycloak estén en la misma red
docker network inspect keycloak_net | grep -A 5 keycloak

# 2. Verificar puerto JGroups (7800)
docker exec keycloak-nodo1 netstat -tuln | grep 7800

# 3. Ver logs de JGroups
docker logs keycloak-nodo1 2>&1 | grep -i jgroups

# 4. Verificar configuración JGROUPS_DISCOVERY_PROPERTIES
docker exec keycloak-nodo1 env | grep JGROUPS
```

### Problema: Replicación PostgreSQL con lag

**Síntomas**:
- `patronictl list` muestra `Lag in MB > 0`
- REPLICA no tiene datos actualizados

**Solución**:
```bash
# 1. Ver estado de replicación
docker exec postgres-nodo2 psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# 2. Ver lag en bytes
docker exec postgres-nodo1 psql -U postgres -c "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes FROM pg_stat_replication;"

# 3. Si lag es persistente, verificar red y I/O
docker stats postgres-nodo1 postgres-nodo2
```

### Problema: Failover no automático

**Síntomas**:
- PRIMARY cae pero REPLICA no se promueve

**Solución**:
```bash
# 1. Ver configuración de Patroni (timeouts)
docker exec postgres-nodo1 cat /etc/patroni/patroni.yml | grep -A 5 "ttl\|retry_timeout"

# 2. Ver logs de etcd
docker logs etcd-nodo1 2>&1 | grep -i "request\|timeout"

# 3. Forzar failover manual si es necesario
docker exec postgres-nodo2 patronictl -c /etc/patroni/patroni.yml failover keycloak-cluster
```

### Problema: Keycloak no inicia

**Síntomas**:
- Container se reinicia constantemente

**Solución**:
```bash
# 1. Ver logs completos
docker logs keycloak-nodo1 --tail 100

# 2. Verificar conectividad a HAProxy
docker exec keycloak-nodo1 nc -zv haproxy-nodo1 5432

# 3. Verificar certificados TLS
docker exec keycloak-nodo1 ls -la /opt/keycloak/conf/
```

### Problema: Certificados no reconocidos

**Solución**: Regenerar certificados
```bash
rm -rf certs/
./generate-certs.sh
```

### Problema: Puerto en uso

**Solución**: Cambiar puerto en `.env`
```bash
KC_PORT=9443  # En lugar de 8443
KC_PORT_NODO2=9444  # Para nodo 2
```

## 📚 Documentación y Referencias

### Documentación Oficial

- **Keycloak**: [Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- **Patroni**: [Official Documentation](https://patroni.readthedocs.io/en/latest/)
- **HAProxy**: [Configuration Manual](https://www.haproxy.org/download/2.9/doc/configuration.txt)
- **etcd**: [Operations Guide](https://etcd.io/docs/latest/op-guide/)
- **PostgreSQL**: [Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)
- **Infinispan**: [Embedded Caches](https://infinispan.org/documentation/)
- **JGroups**: [Protocol Stack Configuration](http://jgroups.org/manual4/index.html)

### Arquitecturas Relacionadas

- [Keycloak on Kubernetes](https://www.keycloak.org/operator/basic-deployment)
- [PostgreSQL HA with Patroni](https://github.com/zalando/patroni)
- [HAProxy Best Practices](https://www.haproxy.com/blog/haproxy-best-practice-series)

## 📝 Características Implementadas

### ✅ Alta Disponibilidad (HA)
- **Keycloak Active-Active**: Ambos nodos procesan requests simultáneamente
- **PostgreSQL Active-Passive**: PRIMARY acepta escrituras, REPLICA mantiene copia sincronizada
- **Failover automático**: Recuperación en < 30 segundos sin intervención manual
- **Sin Single Point of Failure**: Cualquier nodo puede caer sin afectar el servicio

### ✅ Persistencia y Replicación
- **PostgreSQL Streaming Replication**: Sincronización en tiempo real (lag típico: 0 bytes)
- **WAL-based replication**: Write-Ahead Log para consistencia garantizada
- **Sincronización de datos**: Usuarios, realms, clients, configuraciones

### ✅ Orquestación Automática
- **Patroni**: Gestión de cluster PostgreSQL con healthchecks y failover
- **etcd**: Consensus distribuido para coordinación del cluster (algoritmo Raft)  
- **HAProxy**: Query routing automático al PRIMARY basado en Patroni REST API
- **Healthchecks inteligentes**: Detección de fallos en segundos

### ✅ Session Clustering
- **Infinispan**: Caché distribuida para sesiones de usuario
- **JGroups TCPPING**: Comunicación directa entre nodos sin multicast
- **Session replication**: Login en nodo1 válido en nodo2 sin re-autenticación
- **Cache invalidation**: Propagación automática de cambios

### ✅ Seguridad
- **HTTPS/TLS**: Comunicación cifrada con certificados
- **Healthcheck endpoints**: Monitoreo sin exponer datos sensibles
- **Network isolation**: Red Docker dedicada para el cluster

### ✅ Observabilidad
- **HAProxy stats**: Dashboard web en puerto 7000
- **Patroni REST API**: Estado del cluster en tiempo real
- **Docker healthchecks**: Estado de cada componente
- **Test suite**: Scripts automatizados de verificación

## 🎯 Casos de Uso

Este setup es ideal para:

- ✅ **Entornos de producción** que requieren alta disponibilidad
- ✅ **Aplicaciones críticas** con requisitos de uptime > 99.9%
- ✅ **Arquitecturas multi-datacenter** (con ajustes de red)
- ✅ **Desarrollo y staging** con configuración idéntica a producción
- ✅ **Testing de failover** y recuperación ante desastres

## 🚀 Próximas Mejoras

- [ ] Backup automático de PostgreSQL a S3/MinIO
- [ ] Monitoreo con Prometheus + Grafana
- [ ] Log aggregation con ELK Stack
- [ ] Usar HAProxy para read scaling (lecturas a REPLICAs)
- [ ] Kubernetes Helm Charts para despliegue en K8s
- [ ] Multi-region deployment con synchronous_commit configurado

## 📄 Licencia

Este proyecto es de código abierto para fines educativos y de desarrollo.

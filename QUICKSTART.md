# 🚀 Quickstart - Keycloak HA Cluster
## PostgreSQL + Patroni + HAProxy + etcd + Infinispan

## 🏭️ Arquitectura

Este despliegue incluye:
- **etcd**: Coordinación distribuida para el cluster PostgreSQL
- **Patroni**: Gestión automática de PostgreSQL con failover automático
- **PostgreSQL**: Base de datos con streaming replication
- **HAProxy**: Query routing automático al nodo PRIMARY
- **Keycloak**: Servidor de autenticación con Infinispan clustering

**Características:**
- ✅ Failover automático de PostgreSQL (< 30 segundos)
- ✅ Query routing inteligente con HAProxy (detecta PRIMARY dinámicamente)
- ✅ Alta disponibilidad real (sistema funciona si 1 nodo cae)
- ✅ Cluster Infinispan para sesiones y caché

---

## 📋 Opción 1: Despliegue Automático (Recomendado)

```bash
# Ejecutar script de deployment todo-en-uno
./deploy-ha.sh
```

El script ejecutará automáticamente todos los pasos necesarios y mostrará el estado final.

---

## 📋 Opción 2: Despliegue Manual Paso a Paso

## 📋 Opción 2: Despliegue Manual Paso a Paso

⚠️ **ADVERTENCIA**: El despliegue manual requiere atención especial al timing del cluster etcd. **Se recomienda usar el script automatizado `./deploy-ha.sh`** que maneja correctamente la sincronización.

### Paso 1: Requisitos Previos

```bash
# 1. Crear la red Docker compartida
docker network create keycloak_net

# 2. Generar certificados SSL
./generate-certs.sh

# 3. Construir la imagen de Keycloak
docker build -t keycloak_ha-keycloak .
```

### Paso 2: Levantar el Cluster

⚠️ **IMPORTANTE**: etcd requiere que ambos nodos inicien simultáneamente para formar el cluster inicial.

```bash
# 2.1. Levantar AMBOS etcd al mismo tiempo (CRÍTICO)
docker compose -p nodo1 -f docker-compose-nodo1.yaml up -d etcd &
docker compose -p nodo2 -f docker-compose-nodo2.yaml up -d etcd &
wait

# Esperar formación del cluster etcd
sleep 15

# 2.2. Levantar PostgreSQL/Patroni NODO 1 (PRIMARY)
docker compose -p nodo1 -f docker-compose-nodo1.yaml up -d postgres
sleep 30

# 2.3. Levantar PostgreSQL/Patroni NODO 2 (REPLICA)
docker compose -p nodo2 -f docker-compose-nodo2.yaml up -d postgres
sleep 30

# 2.4. Levantar HAProxy y Keycloak en ambos nodos
docker compose -p nodo1 -f docker-compose-nodo1.yaml up -d haproxy keycloak
docker compose -p nodo2 -f docker-compose-nodo2.yaml up -d haproxy keycloak

# Esperar inicialización completa
sleep 30
```

---

## ✅ Verificar el Cluster

### Verificar Contenedores

```bash
# Ver estado de todos los contenedores
docker ps --format "table {{.Names}}\t{{.Status}}"

# Esperado: 8 contenedores corriendo
# - etcd-nodo1, etcd-nodo2
# - postgres-nodo1, postgres-nodo2  
# - haproxy-nodo1, haproxy-nodo2
# - keycloak-nodo1, keycloak-nodo2
```

### Verificar Cluster Patroni (PostgreSQL HA)

```bash
# Ver estado del cluster PostgreSQL
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list

# Salida esperada:
# + Cluster: keycloak-postgres-cluster
# | Member         | Host           | Role    | State   | Lag in MB |
# +----------------+----------------+---------+---------+-----------+
# | postgres-nodo1 | postgres-nodo1 | Leader  | running |           |
# | postgres-nodo2 | postgres-nodo2 | Replica | running |         0 |
```

### Verificar HAProxy (Query Routing)

```bash
# Ver estado de backends de HAProxy
docker exec haproxy-nodo1 sh -c "echo 'show stat' | nc -U /var/run/haproxy/admin.sock | grep postgres"

# O verificar via API REST de Patroni
docker exec postgres-nodo1 curl -s http://localhost:8008/master
# Esperado: HTTP 200 si es PRIMARY, 503 si no

docker exec postgres-nodo2 curl -s http://localhost:8008/master
# Esperado: HTTP 200 o 503 dependiendo de quién sea PRIMARY
```

### Verificar Cluster Infinispan (Keycloak)

```bash
# Ver formación del cluster (esperado: 2 miembros)
docker logs keycloak-nodo1 2>&1 | grep "cluster view"
docker logs keycloak-nodo2 2>&1 | grep "cluster view"

# Salida esperada:
# ISPN000094: Received new cluster view for channel ISPN: 
# [keycloak-nodo1-xxx|1] (2) [keycloak-nodo1-xxx, keycloak-nodo2-xxx]
```

### Verificar Endpoints HTTP

```bash
# Verificar que ambos nodos responden
curl -k -s -o /dev/null -w "NODO 1: %{http_code}\n" https://localhost:8443/realms/master
curl -k -s -o /dev/null -w "NODO 2: %{http_code}\n" https://localhost:8444/realms/master

# Esperado: HTTP 200 en ambos
```

---

## 🌐 Acceso Web

- **NODO 1:** https://localhost:8443
- **NODO 2:** https://localhost:8444
- **Credenciales:** `admin` / `admin`

---

## 🧪 Test de Failover Automático

```bash
# Ejecutar test de failover
./test-failover.sh
```

Este script:
1. Verifica estado inicial del cluster
2. Simula caída del PRIMARY (detiene contenedor)
3. Verifica promoción automática de REPLICA (~30s)
4. Confirma que Keycloak sigue funcionando
5. Recupera el nodo antiguo como nueva REPLICA

---

## ⏹️ Detener el Cluster

```bash
# Detener ambos nodos (con limpieza completa)
docker compose -p nodo1 -f docker-compose-nodo1.yaml down --remove-orphans -v
docker compose -p nodo2 -f docker-compose-nodo2.yaml down --remove-orphans -v

# Opcional: Limpiar red
docker network rm keycloak_net
```

---

## 🔧 Troubleshooting

### Patroni no inicia

```bash
# Ver logs de Patroni
docker logs postgres-nodo1
docker logs postgres-nodo2

# Verificar que etcd está funcionando
docker exec etcd-nodo1 etcdctl member list
```

### HAProxy no detecta backend PRIMARY

```bash
# Ver logs de HAProxy
docker logs haproxy-nodo1

# Verificar que Patroni REST API responde
docker exec postgres-nodo1 curl -s http://localhost:8008/health
docker exec postgres-nodo2 curl -s http://localhost:8008/health

# Verificar detección de PRIMARY
docker exec postgres-nodo1 curl -s http://localhost:8008/master
docker exec postgres-nodo2 curl -s http://localhost:8008/master
```

### Keycloak no inicia

```bash
# Ver logs de Keycloak
docker logs keycloak-nodo1 --tail 50

# Verificar conexión a HAProxy
docker exec keycloak-nodo1 ping -c 3 haproxy-nodo1

# Verificar que HAProxy tiene backend healthy
docker logs haproxy-nodo1 | grep postgres
```

### Diferentes tiempos de inicio

- **etcd**: ~10 segundos
- **Patroni/PostgreSQL**: ~30-40 segundos (PRIMARY), ~50-60 segundos (REPLICA)
- **HAProxy**: ~5 segundos (después de PostgreSQL)
- **Keycloak**: ~60-90 segundos

---

## 📚 Más Información

- Ver [README.md](README.md) para arquitectura completa
- Configuración de Patroni: `patroni/patroni-nodo*.yml`
- Configuración de HAProxy: `haproxy/haproxy.cfg`

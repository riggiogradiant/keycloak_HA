# Keycloak High Availability con Infinispan

Despliegue de Keycloak en Alta Disponibilidad usando Infinispan para clustering distribuido.

## 📋 Estructura del Proyecto

```
keycloak_HA/
├── docker-compose-nodo1.yaml   # Nodo 1: PostgreSQL + Keycloak
├── docker-compose-nodo2.yaml   # Nodo 2: PostgreSQL + Keycloak
├── Dockerfile                  # Keycloak optimizado para producción
├── generate-certs.sh           # Generador de certificados SSL/TLS
├── .env.example                # Variables de entorno (ejemplo)
├── certs/                      # Certificados SSL/TLS (generados)
└── old-test/                   # Archivos antiguos de pruebas
```

## 🚀 Despliegue Rápido en Local

### 1. Generar Certificados

```bash
chmod +x generate-certs.sh
./generate-certs.sh
```

### 2. Configurar Variables de Entorno (Opcional)

```bash
cp .env.example .env
# Editar .env con tus contraseñas
```

### 3. Crear Red Docker Compartida

```bash
docker network create keycloak_net
```

### 4. Levantar NODO 1

```bash
docker compose -f docker-compose-nodo1.yaml up -d
```

**Acceso**: https://localhost:8443
- Usuario: `admin`
- Password: `admin` (o el configurado en `.env`)

### 5. Levantar NODO 2

```bash
docker compose -f docker-compose-nodo2.yaml up -d
```

**Acceso**: https://localhost:8444
- Usuario: `admin`
- Password: `admin` (o el configurado en `.env`)

## ✅ Verificar Clustering

### Ver logs de clustering

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

El número `(2)` indica que hay **2 miembros en el cluster** ✅

### Healthchecks

```bash
# NODO 1
curl -k https://localhost:8443/health/ready

# NODO 2
curl -k https://localhost:8444/health/ready
```

## 🧪 Probar Sesiones Distribuidas

1. Login en NODO 1: https://localhost:8443
2. Ir a Administration Console
3. Copiar URL completa con `session_state`
4. Cambiar puerto a `8444` en la URL
5. Abrir en nueva pestaña
6. ✅ Deberías estar autenticado sin hacer login nuevamente

## 📊 Arquitectura

```
┌─────────────────────┐         ┌─────────────────────┐
│      NODO 1         │         │      NODO 2         │
│                     │         │                     │
│  Keycloak-nodo1    │◄────────►│  Keycloak-nodo2    │
│  (port 8443)       │  JGroups │  (port 8444)       │
│       ↓            │  TCP:7800│       ↓            │
│  PostgreSQL-nodo1  │         │  PostgreSQL-nodo2  │
└─────────────────────┘         └─────────────────────┘
         ↓                               ↓
    BD Independiente              BD Independiente
```

### Sincronización Infinispan

**✅ Se sincroniza**:
- Sesiones de usuario
- Tokens (access, refresh, ID)
- Metadata en caché

**❌ NO se sincroniza**:
- Usuarios y roles (datos persistentes)
- Configuración de realms/clients (BD)

> **Nota**: Cada nodo tiene su propia base de datos PostgreSQL independiente. Para sincronizar datos persistentes, implementar PostgreSQL Streaming Replication (próximo paso).

## 🔧 Comandos Útiles

### Ver todos los contenedores

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Ver logs en tiempo real

```bash
# NODO 1
docker logs keycloak-nodo1 -f

# NODO 2
docker logs keycloak-nodo2 -f
```

### Detener servicios

```bash
# NODO 1
docker compose -f docker-compose-nodo1.yaml down

# NODO 2
docker compose -f docker-compose-nodo2.yaml down
```

### Eliminar todo (incluye volúmenes)

```bash
docker compose -f docker-compose-nodo1.yaml down -v
docker compose -f docker-compose-nodo2.yaml down -v
docker network rm keycloak_net
```

## 🌐 Despliegue en Servidores Separados

### En Servidor 1 (NODO 1)

1. Editar `docker-compose-nodo1.yaml`:
   ```yaml
   JGROUPS_DISCOVERY_PROPERTIES: initial_hosts="keycloak-nodo1[7800]\\,<IP_SERVIDOR2>\\:7800"
   ```

2. Exponer puerto JGroups en firewall:
   ```bash
   sudo ufw allow 7800/tcp
   ```

3. Levantar servicios:
   ```bash
   docker compose -f docker-compose-nodo1.yaml up -d
   ```

### En Servidor 2 (NODO 2)

1. Editar `docker-compose-nodo2.yaml`:
   ```yaml
   JGROUPS_DISCOVERY_PROPERTIES: initial_hosts="<IP_SERVIDOR1>\\:7800\\,keycloak-nodo2[7800]"
   ```

2. Exponer puerto JGroups:
   ```bash
   sudo ufw allow 7800/tcp
   ```

3. Levantar servicios:
   ```bash
   docker compose -f docker-compose-nodo2.yaml up -d
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

### Problema: Clustering no se forma

**Solución**: Verificar red Docker
```bash
docker network inspect keycloak_net
```

Asegurar que ambos contenedores estén en la misma red.

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
```

## 📝 Características Implementadas

✅ **PostgreSQL Streaming Replication**: Sincronización en tiempo real entre PRIMARY y REPLICA  
✅ **Patroni**: Gestión automática de cluster PostgreSQL con failover automático (< 30s)  
✅ **HAProxy**: Query routing automático al nodo PRIMARY basado en Patroni REST API  
✅ **etcd**: Consensus distribuido para coordinación del cluster  
✅ **Keycloak Clustering**: Infinispan distribuido para sesiones compartidas  

## 📄 Licencia

Este proyecto es de código abierto para fines educativos y de desarrollo.

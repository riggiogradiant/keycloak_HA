# Keycloak High Availability con Infinispan

## 🎯 Objetivo del Proyecto

Desplegar 2 instancias de Keycloak en **modo producción** con SSL, clustering Infinispan, load balancer Nginx y PostgreSQL compartida para alta disponibilidad real.

## ✅ Características

- ✅ **2 nodos Keycloak** en cluster
- ✅ **Modo producción** (`start --optimized`)
- ✅ **SSL/HTTPS** con certificados auto-generados
- ✅ **Infinispan distribuido** - Sesiones replicadas
- ✅ **JGroups TCPPING** - Clustering entre nodos
- ✅ **Nginx Load Balancer** - Sticky sessions
- ✅ **PostgreSQL compartida** - Datos sincronizados
- ✅ **Failover automático** - Zero downtime

## 🚀 Despliegue Rápido

```bash
./deploy-prod.sh
```

## 🌐 Acceso

- 🔀 **Load Balancer**: https://localhost
- 🔵 **Nodo 1**: https://localhost:8443
- 🟢 **Nodo 2**: https://localhost:8444

**Credenciales**: admin / (ver `.env.prod`)

## 🧪 Pruebas

```bash
# Test completo
./test-ha-realistic.sh

# Ver estado
./status.sh

# Detener
./stop.sh
```

## 📚 Documentación Completa

- **[PRODUCCION.md](PRODUCCION.md)** - Guía completa de producción ⭐
- **[LIMITACIONES.md](LIMITACIONES.md)** - Diferencias desarrollo vs producción

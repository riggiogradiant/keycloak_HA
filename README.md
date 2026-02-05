# Keycloak HA con Infinispan

Despliegue de 2 instancias de Keycloak con clustering Infinispan en **modo producción**.

## 🎯 Arquitectura

- **2 Keycloaks** con Infinispan clustering (JGroups TCPPING)
- **1 PostgreSQL** compartida (claves de firma compartidas)
- **Modo producción** con SSL
- **Sesiones replicadas** entre nodos

## 🚀 Despliegue

```bash
./deploy.sh
```

## 🌐 Acceso

- **Keycloak 1**: https://localhost:8443
- **Keycloak 2**: https://localhost:8444
- **Credenciales**: admin / admin

⚠️ Certificados auto-firmados: aceptar en navegador

## 🧪 Pruebas

```bash
./test.sh
```

Verifica que los tokens sean válidos entre nodos.

## 🛑 Detener

```bash
./stop.sh
```

## ✅ Funcionalidades

- ✅ **Tokens compartidos** entre nodos
- ✅ **Sesiones replicadas** con Infinispan
- ✅ **Failover** automático
- ✅ Base de datos compartida (usuarios y claves replicadas)

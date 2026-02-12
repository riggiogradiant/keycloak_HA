# 🧪 Tests de Verificación - Keycloak HA

Esta carpeta contiene scripts de prueba para verificar el correcto funcionamiento del cluster Keycloak HA.

## 📋 Scripts Disponibles

### 1. test-sync.sh
**Verifica la sincronización de base de datos entre PRIMARY y REPLICA**

```bash
./tests/test-sync.sh
```

**Qué verifica:**
- ✅ Identificación correcta de PRIMARY y REPLICA
- ✅ Creación y escritura de datos en PRIMARY
- ✅ Replicación automática a REPLICA
- ✅ Lag de replicación (debe ser 0 bytes)
- ✅ Consistencia de datos entre nodos

**Duración:** ~5 segundos

---

### 2. test-routing.sh
**Verifica el query routing de HAProxy**

```bash
./tests/test-routing.sh
```

**Qué verifica:**
- ✅ Detección del PRIMARY vía Patroni REST API
- ✅ HAProxy enruta escrituras al PRIMARY correcto
- ✅ Escrituras desde ambos nodos van al mismo PRIMARY
- ✅ No hay split-brain (solo un PRIMARY activo)
- ✅ Replicación de datos después del routing

**Duración:** ~10 segundos

---

### 3. test-infinispan.sh
**Verifica el cluster Infinispan de Keycloak**

```bash
./tests/test-infinispan.sh
```

**Qué verifica:**
- ✅ Formación del cluster (2 miembros esperados)
- ✅ Protocolo JGroups configurado correctamente
- ✅ Cachés distribuidas activas
- ✅ Conectividad de red entre nodos
- ✅ Puertos JGroups (7800) escuchando
- ✅ Endpoints Keycloak respondiendo (HTTP 200)
- ℹ️ Instrucciones para test manual de sesión compartida

**Duración:** ~10 segundos

---

### 4. Test de Failover
**El script de failover está en la raíz del proyecto**

```bash
./test-failover.sh
```

**Qué verifica:**
- ✅ Estado inicial del cluster Patroni
- ✅ Simulación de caída del PRIMARY
- ✅ Promoción automática de REPLICA a PRIMARY (~30s)
- ✅ Escritura en nuevo PRIMARY
- ✅ Keycloak sigue funcionando después del failover
- ✅ Recuperación del nodo antiguo como nueva REPLICA

**Duración:** ~90 segundos (incluye tiempos de espera)

---

## 🚀 Ejecución Rápida

### Ejecutar todos los tests básicos

```bash
# Sincronización BD
./tests/test-sync.sh

# Query routing
./tests/test-routing.sh

# Cluster Infinispan
./tests/test-infinispan.sh

# Failover (más largo, ejecutar al final)
./test-failover.sh
```

### Ejecución en secuencia

```bash
for test in tests/test-*.sh; do
    echo ""
    echo "=================================================="
    echo "Ejecutando: $test"
    echo "=================================================="
    bash "$test"
    echo ""
    read -p "Presiona ENTER para continuar al siguiente test..."
done
```

---

## 📊 Interpretación de Resultados

### ✅ Test Exitoso
```
========================================
✅ TEST EXITOSO
   • [descripción de validaciones pasadas]
========================================
```

### ⚠️ Test Parcial
```
========================================
⚠️  TEST PARCIAL
   • [descripción de estado intermedio]
   • [recomendaciones]
========================================
```

### ❌ Test Fallido
```
========================================
❌ TEST FALLIDO
   • [descripción del error]
   • [posibles causas]
========================================
```

---

## 🔍 Solución de Problemas

### test-sync.sh falla

**Síntomas:**
- Lag > 0 bytes
- Contadores diferentes entre PRIMARY y REPLICA

**Soluciones:**
```bash
# Verificar estado del cluster
docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list

# Ver logs de replicación
docker logs postgres-nodo2 --tail 50 | grep replication
```

---

### test-routing.sh falla

**Síntomas:**
- HAProxy no detecta PRIMARY
- Múltiples nodos responden como PRIMARY

**Soluciones:**
```bash
# Verificar Patroni API
docker exec postgres-nodo1 curl http://localhost:8008/health
docker exec postgres-nodo2 curl http://localhost:8008/health

# Verificar HAProxy logs
docker logs haproxy-nodo1 --tail 30
docker logs haproxy-nodo2 --tail 30
```

---

### test-infinispan.sh falla

**Síntomas:**
- Solo 1 miembro en el cluster
- No se encuentra información de cluster view

**Soluciones:**
```bash
# Verificar que ambos Keycloak están iniciados
docker ps | grep keycloak

# Ver logs completos
docker logs keycloak-nodo1 --tail 100
docker logs keycloak-nodo2 --tail 100

# Verificar conectividad
docker exec keycloak-nodo1 ping -c 3 keycloak-nodo2
```

---

## 📝 Notas Importantes

1. **Orden de ejecución**: Los tests son independientes pero recomendamos ejecutarlos en el orden listado.

2. **Tiempos de espera**: Algunos tests esperan unos segundos para la replicación. Si los sistemas están bajo carga, pueden necesitar más tiempo.

3. **Test de sesión compartida**: El test de Infinispan incluye instrucciones para un test manual de sesión compartida que requiere interacción del usuario.

4. **Limpieza de datos**: Los tests crean tablas temporales (`sync_test`, `routing_test`). Puedes limpiarlas con:
   ```bash
   docker exec postgres-nodo1 psql -U keycloak -d keycloak -c \
     "DROP TABLE IF EXISTS sync_test, routing_test CASCADE;"
   ```

5. **Repetición de tests**: Puedes ejecutar los tests múltiples veces. Cada ejecución añade nuevos registros a las tablas de prueba.

---

## 🎯 Checklist de Verificación Completa

```
□ test-sync.sh ✅
  └─ Replicación funcionando con lag = 0

□ test-routing.sh ✅  
  └─ HAProxy detecta PRIMARY correctamente

□ test-infinispan.sh ✅
  └─ Cluster formado con 2 miembros

□ Test manual de sesión compartida ✅
  └─ Login en NODO 1 funciona en NODO 2

□ test-failover.sh ✅
  └─ Failover automático en ~30s

□ Endpoints HTTP ✅
  └─ https://localhost:8443 (200)
  └─ https://localhost:8444 (200)
```

---

## 📚 Más Información

- Ver [QUICKSTART.md](../QUICKSTART.md) para guía de despliegue
- Ver [README.md](../README.md) para arquitectura completa
- Ver logs en tiempo real: `docker logs -f <container_name>`

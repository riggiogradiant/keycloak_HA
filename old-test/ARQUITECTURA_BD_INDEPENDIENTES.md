# Arquitectura con Bases de Datos Independientes

## 📋 Resumen del Cambio

**Decisión Arquitectónica**: Cada nodo de Keycloak tiene su propia base de datos PostgreSQL independiente.

### ¿Por qué este cambio?

1. **Keycloak requiere base de datos**: No puede funcionar sin PostgreSQL
2. **Simplicidad en Paso 1**: Facilita el aprendizaje incremental
3. **Preparación para replicación**: En el Paso 2 se añadirá PostgreSQL Streaming Replication

---

## 🏗️ Arquitectura Actual (Paso 1)

```
┌─────────────────────────────┐         ┌─────────────────────────────┐
│        NODO 1               │         │        NODO 2               │
│                             │         │                             │
│  ┌──────────────────────┐  │         │  ┌──────────────────────┐  │
│  │   Keycloak-1         │◄─┼─────────┼─►│   Keycloak-2         │  │
│  │   Puerto: 8443       │  │         │  │   Puerto: 8443       │  │
│  │                      │  │         │  │                      │  │
│  │  Infinispan Cache    │  │  JGroups│  │  Infinispan Cache    │  │
│  │  JGroups: 7800       │◄─┼─────────┼─►│  JGroups: 7800       │  │
│  └──────────┬───────────┘  │         │  └──────────┬───────────┘  │
│             │               │         │             │               │
│  ┌──────────▼───────────┐  │         │  ┌──────────▼───────────┐  │
│  │ PostgreSQL PRIMARY   │  │   ❌    │  │ PostgreSQL NODO 2    │  │
│  │ Puerto: 5432         │  │   NO    │  │ Puerto: 5432         │  │
│  │                      │  │ REPLICA │  │                      │  │
│  │ BD: keycloak         │  │         │  │ BD: keycloak         │  │
│  │ Usuarios: user1...   │  │         │  │ Usuarios: VACÍA      │  │
│  └──────────────────────┘  │         │  └──────────────────────┘  │
└─────────────────────────────┘         └─────────────────────────────┘
         DATOS INDEPENDIENTES                DATOS INDEPENDIENTES
```

### Componentes por Nodo

#### NODO 1
- **postgres-primary**: Base de datos PostgreSQL independiente (puerto 5432)
- **keycloak-1**: Conecta a postgres-primary
- **Infinispan**: Sincroniza caché con Keycloak-2

#### NODO 2
- **postgres-nodo2**: Base de datos PostgreSQL independiente (puerto 5432)
- **keycloak-2**: Conecta a postgres-nodo2
- **Infinispan**: Sincroniza caché con Keycloak-1

---

## 🔍 ¿Qué se Sincroniza y Qué NO?

### ✅ Lo que SÍ se sincroniza (Infinispan)

Infinispan distribuye el **caché en memoria** entre los nodos:

1. **Sesiones de usuario**:
   - Login en NODO 1 → sesión disponible en NODO 2
   - Tokens de acceso compartidos
   - Cookies de sesión válidas en ambos nodos

2. **Tokens y códigos temporales**:
   - Authorization codes
   - Access tokens
   - Refresh tokens
   - ID tokens

3. **Metadata de configuración en caché**:
   - Configuración de realms (en memoria)
   - Configuración de clients (en memoria)
   - Cache de consultas frecuentes

### ❌ Lo que NO se sincroniza (Datos persistentes)

Cada base de datos PostgreSQL mantiene sus **datos persistentes independientes**:

1. **Usuarios**:
   - Usuario creado en NODO 1 → NO existe en NODO 2
   - Contraseñas, emails, atributos

2. **Roles y grupos**:
   - Roles definidos en NODO 1 → NO existen en NODO 2
   - Asignaciones de roles

3. **Configuración persistente**:
   - Realms (estructura en BD)
   - Clients (estructura en BD)
   - Identity Providers
   - Authentication flows

4. **Eventos y logs**:
   - Login events
   - Admin events
   - Audit logs

---

## 🧪 Pruebas de Funcionamiento

### Test 1: Verificar Clustering de Infinispan ✅

```bash
# Ver logs de cluster
docker logs keycloak-1 | grep "cluster view"
docker logs keycloak-2 | grep "cluster view"

# Esperado: (2) [keycloak-1, keycloak-2]
```

### Test 2: Sesiones Compartidas ✅

1. Login en NODO 1 (https://localhost:8443)
2. Copiar cookie de sesión del navegador
3. Usar misma cookie en NODO 2 (https://localhost:8444)
4. ✅ **Resultado**: Sesión válida en ambos nodos (gracias a Infinispan)

### Test 3: Usuarios NO Compartidos ❌

1. Crear usuario "alice" en NODO 1
2. Buscar usuario "alice" en NODO 2
3. ❌ **Resultado**: Usuario NO existe (bases de datos independientes)

---

## 🚀 Evolución Arquitectónica (Roadmap)

### Paso 1: Clustering Simple (ACTUAL)
```
NODO 1 (postgres-primary) ⚡ Infinispan ⚡ NODO 2 (postgres-nodo2)
         ↓                                         ↓
    BD independiente                         BD independiente
```

- ✅ Infinispan funcional
- ❌ Datos NO sincronizados
- **Uso**: Desarrollo, pruebas de clustering

---

### Paso 2: PostgreSQL Streaming Replication (PRÓXIMO)

```
NODO 1 (PRIMARY)                    NODO 2 (REPLICA)
      ↓                                    ↓
  postgres-primary ─── WAL Streaming ───→ postgres-replica
      │                                          ↑
      └─────────────────────────────────────────┘
              Replicación continua de datos
```

**Cambios a implementar**:
1. Convertir postgres-primary a modo PRIMARY (wal_level=replica)
2. Convertir postgres-nodo2 a modo REPLICA (hot_standby=on)
3. Configurar replication slot
4. Inicializar REPLICA con pg_basebackup

**Resultado**:
- ✅ Datos sincronizados automáticamente
- ✅ Usuario creado en PRIMARY → aparece en REPLICA
- ⚠️ REPLICA es read-only

---

### Paso 3: pgpool-II + HAProxy (FUTURO)

```
NODO 1                              NODO 2
  ↓                                    ↓
Keycloak-1                          Keycloak-2
  ↓                                    ↓
pgpool-II                           pgpool-II
  ↓                                    ↓
HAProxy                             HAProxy
  ↓                                    ↓
PRIMARY (R/W) ─── Replication ───→ REPLICA (R)
```

**Ventajas**:
- ✅ Lecturas locales (baja latencia)
- ✅ Escrituras centralizadas (consistencia)
- ✅ Failover automático de queries

---

## ⚙️ Configuración Técnica

### Docker Compose NODO 1

```yaml
services:
  postgres-primary:
    image: postgres:15
    container_name: postgres-primary
    ports:
      - "5432:5432"
    # Configuración simple (aún no PRIMARY)
    
  keycloak-1:
    container_name: keycloak-1
    environment:
      KC_DB_URL: jdbc:postgresql://postgres-primary:5432/keycloak
      JGROUPS_DISCOVERY_PROPERTIES: initial_hosts="keycloak-1[7800],<NODO2_IP>:7800"
```

### Docker Compose NODO 2

```yaml
services:
  postgres-nodo2:
    image: postgres:15
    container_name: postgres-nodo2
    ports:
      - "5432:5432"
    # Base de datos independiente (aún no REPLICA)
    
  keycloak-2:
    container_name: keycloak-2
    environment:
      KC_DB_URL: jdbc:postgresql://postgres-nodo2:5432/keycloak
      JGROUPS_DISCOVERY_PROPERTIES: initial_hosts="<NODO1_IP>:7800,keycloak-2[7800]"
```

---

## 🔧 Comandos Útiles

### Verificar Estado de Clustering

```bash
# Ver miembros del cluster
docker logs keycloak-1 2>&1 | grep "received new cluster view"

# Verificar caché Infinispan
docker exec keycloak-1 /opt/keycloak/bin/kcadm.sh config credentials \
  --server https://localhost:8443 \
  --realm master \
  --user admin \
  --password admin
```

### Inspeccionar Bases de Datos

```bash
# NODO 1: Ver usuarios en postgres-primary
docker exec -e PGPASSWORD=keycloak postgres-primary \
  psql -U keycloak -d keycloak \
  -c "SELECT username, email FROM user_entity;"

# NODO 2: Ver usuarios en postgres-nodo2 (debería estar vacía)
docker exec -e PGPASSWORD=keycloak postgres-nodo2 \
  psql -U keycloak -d keycloak \
  -c "SELECT username, email FROM user_entity;"
```

### Limpieza

```bash
# NODO 1
./cleanup-nodo1.sh

# NODO 2
./cleanup-nodo2.sh

# Prueba local (ambos nodos)
docker compose -f docker-compose-nodo1-local.yaml down -v
docker compose -f docker-compose-nodo2-local.yaml down -v
```

---

## 📚 Preguntas Frecuentes

### ¿Por qué no usar una sola base de datos compartida?

En el Paso 1, podríamos:
- NODO 1: postgres-primary (expuesta en puerto 5432)
- NODO 2: Keycloak-2 conecta remotamente a postgres-primary del NODO 1

**Problema**: Si el NODO 1 falla, el NODO 2 pierde acceso a la base de datos.

**Solución actual**: Cada nodo tiene su propia BD. En el Paso 2, se sincronizarán con Streaming Replication.

### ¿Infinispan puede sincronizar datos persistentes?

**NO**. Infinispan es un caché distribuido en memoria, diseñado para:
- Datos temporales (sesiones, tokens)
- Baja latencia (microsegundos)
- Alta volatilidad (datos que cambian frecuentemente)

Para datos persistentes, se usa PostgreSQL Streaming Replication.

### ¿Cuánto lag hay en Infinispan?

- **Sincronización**: Prácticamente instantánea (~1-5ms en red local)
- **Consistencia**: Eventual (no ACID)
- **Modo**: Asíncrono (por defecto)

### ¿Qué pasa si se cae un nodo?

**Paso 1 (Actual - Sin Replicación)**:
- NODO 1 cae → Solo NODO 2 disponible (con sus propios datos)
- NODO 2 cae → Solo NODO 1 disponible (con sus propios datos)
- **Limitación**: Datos no compartidos entre nodos

**Paso 2 (Con Replicación)**:
- PRIMARY cae → REPLICA se puede promover manualmente
- REPLICA cae → PRIMARY continúa funcionando normalmente
- **Ventaja**: Datos sincronizados, failover posible

---

## ✅ Checklist de Implementación

- [x] Crear docker-compose-nodo1.yaml con postgres-primary
- [x] Crear docker-compose-nodo2.yaml con postgres-nodo2
- [x] Script prueba_infinispan_local.sh con BD independientes
- [x] Actualizar deploy-nodo1.sh
- [x] Actualizar deploy-nodo2.sh
- [x] Actualizar cleanup-nodo1.sh
- [x] Actualizar cleanup-nodo2.sh
- [x] Documentar arquitectura (este archivo)
- [ ] Testing: Verificar clustering Infinispan
- [ ] Testing: Confirmar sesiones compartidas
- [ ] Testing: Confirmar datos NO compartidos
- [ ] Paso 2: Implementar PostgreSQL Streaming Replication

---

## 📖 Referencias

- [Keycloak Clustering](https://www.keycloak.org/high-availability/concepts-infinispan-cli-crossdc)
- [Infinispan Cache Modes](https://infinispan.org/docs/stable/titles/configuring/configuring.html)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/15/warm-standby.html)
- [JGroups TCPPING Protocol](http://www.jgroups.org/manual4/index.html#TCPPING_Prot)

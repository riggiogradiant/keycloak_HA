# 🔐 Keycloak HA - Modo Producción con SSL

## 📊 Comparación: Ejemplo vs Nuestra Implementación

### Docker Compose Original (Ejemplo)

```yaml
keycloak:
  command: start --features=preview
  environment:
    KC_HOSTNAME: ${KC_HOSTNAME}
    KC_HTTPS_KEY_STORE_FILE: /opt/keycloak/conf/keycloak.p12
    KC_DB: postgres
  volumes:
    - ./docker/keycloak/keycloak.p12:/opt/keycloak/conf/keycloak.p12
```

**Características**:
- ✅ Modo producción con SSL
- ❌ Solo 1 nodo (sin HA)
- ❌ Sin clustering
- ✅ Certificado PKCS12

### Nuestra Implementación HA

```yaml
keycloak-1:
  command: start --optimized --features=preview
  environment:
    KC_HOSTNAME: ${KC_HOSTNAME}
    KC_HTTPS_KEY_STORE_FILE: /opt/keycloak/conf/keycloak.p12
    KC_CACHE: ispn
    KC_CACHE_STACK: tcp
    JAVA_OPTS_APPEND: -Djgroups.tcpping.initial_hosts=...
```

**Mejoras**:
- ✅ Modo producción con SSL
- ✅ **2 nodos** (HA real)
- ✅ **Clustering Infinispan**
- ✅ **JGroups TCPPING**
- ✅ **Load Balancer Nginx** con sticky sessions
- ✅ Certificados compartidos

---

## 🎯 Análisis del Docker Compose Original

### 1. **Certificado SSL (PKCS12)**

```yaml
volumes:
  - ./docker/keycloak/keycloak.p12:/opt/keycloak/conf/keycloak.p12

environment:
  KC_HTTPS_KEY_STORE_FILE: /opt/keycloak/conf/keycloak.p12
  KC_HTTPS_KEY_STORE_PASSWORD: ${KEY_STORE_PASS}
```

**¿Qué es PKCS12?**
- Formato estándar para almacenar certificados y claves privadas
- Archivo `.p12` contiene: certificado + clave privada + contraseña
- Compatible con Java/Keycloak
- Se genera con `keytool`

**Nuestro script `generate-certs.sh` genera esto automáticamente**

### 2. **Hostname Estricto**

```yaml
KC_HOSTNAME: ${KC_HOSTNAME}  # ej: keycloak.midominio.com
KC_HOSTNAME_PORT: ${KC_HOSTNAME_PORT}  # ej: 8443
KC_HOSTNAME_STRICT_HTTPS: true
```

**¿Por qué es importante?**
- Keycloak valida que las peticiones vengan del hostname correcto
- Previene ataques de redirección
- Necesario para tokens JWT válidos

**En producción**: Usa un dominio real (ej: `auth.miempresa.com`)
**En desarrollo**: Puedes usar `localhost` o agregar entrada en `/etc/hosts`

### 3. **Comando `start` vs `start-dev`**

```yaml
# Ejemplo original
command: start --features=preview

# Modo desarrollo (actual)
command: start-dev
```

| Aspecto | start-dev | start (producción) |
|---------|-----------|-------------------|
| **SSL** | Opcional | **Obligatorio** |
| **Hostname** | Flexible | **Estricto** |
| **Build** | Automático | **Manual** (kc.sh build) |
| **Caché** | Mayormente local | **Distribuida** |
| **Performance** | Lenta | **Optimizada** |

### 4. **Features Preview**

```yaml
command: start --features=preview
```

Habilita características experimentales:
- Token exchange
- Admin fine-grained permissions
- Client policies
- etc.

---

## 🚀 Cómo Usar Nuestra Implementación

### Paso 1: Detener Setup Desarrollo

```bash
# Detener nodos actuales
./stop.sh
```

### Paso 2: Generar Certificados SSL

```bash
./generate-certs.sh
```

Esto genera:
- `certs/keycloak.p12` - Certificado PKCS12 para Keycloak
- `certs/nginx.crt` / `certs/nginx.key` - Certificados PEM para Nginx

### Paso 3: Configurar Variables de Entorno

```bash
# Edita .env.prod
nano .env.prod
```

Cambia al menos:
- `KEYCLOAK_ADMIN_PASSWORD`
- `KC_DB_PASSWORD`
- `KEY_STORE_PASS`

### Paso 4: Deploy Automático

```bash
./deploy-prod.sh
```

Este script:
1. ✅ Verifica prerrequisitos
2. ✅ Genera certificados (si no existen)
3. ✅ Hace el build de Keycloak
4. ✅ Inicia todos los servicios
5. ✅ Espera a que estén healthy

---

## 🔍 Arquitectura de Producción

```
                    ┌─────────────────────┐
                    │  Nginx Load Balancer │
                    │   https://localhost  │
                    │  (Puerto 443)        │
                    └──────────┬───────────┘
                               │
                ┌──────────────┴──────────────┐
                │    Sticky Sessions (IP)     │
                └──────────────┬──────────────┘
                               │
         ┌─────────────────────┴─────────────────────┐
         │                                           │
    ┌────▼────┐                                 ┌────▼────┐
    │ Node 1  │◄────── JGroups TCPPING ────────►│ Node 2  │
    │ :8443   │        (Puerto 7800)            │ :8444   │
    └────┬────┘                                 └────┬────┘
         │                                           │
         └─────────────────┬───────────────────────┘
                           │
                    ┌──────▼──────┐
                    │  PostgreSQL  │
                    │   :5432      │
                    └──────────────┘

Certificados SSL: Auto-firmados (certs/)
Replicación: Infinispan distribuido
Sesiones: Compartidas entre nodos ✅
```

---

## 📋 Diferencias Clave vs Modo Desarrollo

| Característica | start-dev | start (producción) |
|----------------|-----------|-------------------|
| **Sesiones compartidas** | ❌ No | ✅ **Sí** (Infinispan real) |
| **Tokens válidos entre nodos** | ❌ No | ✅ **Sí** |
| **SSL** | Opcional | ✅ **Obligatorio** |
| **Clustering real** | ⚠️ Limitado | ✅ **Completo** |
| **Failover sesiones** | ❌ No | ✅ **Sí** |
| **Performance** | Baja | ✅ **Alta** |
| **Load balancer** | No incluido | ✅ **Nginx incluido** |

---

## 🧪 Pruebas de HA Real

### Test 1: Sticky Sessions

```bash
# 1. Accede a https://localhost
# 2. Inicia sesión como admin
# 3. Nginx te asigna a un nodo y te mantiene allí
# 4. Refresca la página varias veces
# ✅ Siempre en el mismo nodo (gracias a ip_hash)
```

### Test 2: Failover de Sesión

```bash
# 1. Inicia sesión en https://localhost
# 2. Identifica tu nodo en los logs de Nginx
# 3. Detén ese nodo:
docker compose -f docker-compose-prod.yml stop keycloak-1

# 4. Refresca en https://localhost
# ✅ Nginx te redirige al nodo 2
# ✅ Tu sesión sigue activa (replicada por Infinispan)
```

### Test 3: Sincronización de Configuración

```bash
# 1. Accede a Node 1: https://localhost:8443
# 2. Crea un usuario "test_prod"
# 3. Accede a Node 2: https://localhost:8444
# 4. Busca el usuario
# ✅ Usuario visible inmediatamente (PostgreSQL compartida)
```

---

## 🔧 Configuración Avanzada

### Usar Certificados Reales (Let's Encrypt)

```bash
# 1. Instalar certbot
apt install certbot

# 2. Generar certificados
certbot certonly --standalone -d keycloak.midominio.com

# 3. Convertir a PKCS12
openssl pkcs12 -export \
  -in /etc/letsencrypt/live/keycloak.midominio.com/fullchain.pem \
  -inkey /etc/letsencrypt/live/keycloak.midominio.com/privkey.pem \
  -out certs/keycloak.p12 \
  -name keycloak \
  -passout pass:changeit

# 4. Copiar certificados Nginx
cp /etc/letsencrypt/live/keycloak.midominio.com/fullchain.pem certs/nginx.crt
cp /etc/letsencrypt/live/keycloak.midominio.com/privkey.pem certs/nginx.key

# 5. Actualizar .env.prod
KC_HOSTNAME=keycloak.midominio.com
KC_HOSTNAME_PORT=443
```

### Agregar Más Nodos

Edita `docker-compose-prod.yml` y agrega:

```yaml
keycloak-3:
  # ... misma config que keycloak-2
  ports:
    - "8445:8443"
  environment:
    # ... 
    JAVA_OPTS_APPEND: >-
      -Djgroups.tcpping.initial_hosts=keycloak-node-1[7800],keycloak-node-2[7800],keycloak-node-3[7800]
```

Actualiza también `initial_hosts` en keycloak-1 y keycloak-2.

---

## 🐛 Troubleshooting

### Error: "Keystore not found"

```bash
# Verifica que el certificado existe
ls -la certs/keycloak.p12

# Regenera certificados
rm -rf certs/
./generate-certs.sh
```

### Error: "Address already in use"

```bash
# Detén el setup de desarrollo primero
./stop.sh

# O usa puertos diferentes en docker-compose-prod.yml
```

### Nodos no forman cluster

```bash
# Verifica logs de JGroups
docker logs keycloak-node-1-prod 2>&1 | grep -i "jgroups\|members"

# Verifica conectividad entre nodos
docker exec keycloak-node-1-prod ping keycloak-node-2
```

### Certificado SSL no válido en navegador

Esto es **normal con certificados auto-firmados**. Opciones:

1. **Aceptar el riesgo** (solo desarrollo): Click en "Avanzado" → "Continuar"
2. **Agregar certificado al sistema**: `sudo cp certs/nginx.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`
3. **Usar Let's Encrypt** para producción

---

## 📚 Referencias

- [Keycloak Production Configuration](https://www.keycloak.org/server/configuration-production)
- [Keycloak Clustering](https://www.keycloak.org/server/caching)
- [JGroups TCPPING](http://jgroups.org/manual4/index.html#TCPPING_Prot)
- [Nginx Load Balancing](https://docs.nginx.com/nginx/admin-guide/load-balancer/http-load-balancer/)

---

## 🎓 Resumen

**Lo que hemos logrado**:

✅ **Modo producción real** (`start --optimized`)
✅ **SSL/HTTPS** con certificados PKCS12
✅ **2 nodos Keycloak** en cluster
✅ **Infinispan distribuido** (sesiones compartidas)
✅ **JGroups TCPPING** (descubrimiento de nodos)
✅ **Load balancer Nginx** con sticky sessions
✅ **PostgreSQL compartida**
✅ **Failover automático** de sesiones

**Diferencia vs setup desarrollo**:
- Sesiones SÍ se replican ✅
- Tokens SÍ son válidos entre nodos ✅
- Performance optimizada ✅
- Listo para producción (con certificados reales) ✅

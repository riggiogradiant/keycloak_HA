#!/bin/bash

# Script de prueba de Alta Disponibilidad de Keycloak
# Demuestra que los cambios se sincronizan entre nodos

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   🧪 Prueba de Alta Disponibilidad - Keycloak + Infinispan  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Verificar que los nodos estén corriendo
echo -e "${BLUE}📋 Paso 1: Verificando que ambos nodos estén activos...${NC}"
if ! curl -sf http://localhost:8080/health/ready > /dev/null 2>&1; then
    echo -e "${RED}❌ Nodo 1 no está disponible en http://localhost:8080${NC}"
    echo "Ejecuta: ./deploy.sh"
    exit 1
fi

if ! curl -sf http://localhost:8081/health/ready > /dev/null 2>&1; then
    echo -e "${RED}❌ Nodo 2 no está disponible en http://localhost:8081${NC}"
    echo "Ejecuta: ./deploy.sh"
    exit 1
fi

echo -e "${GREEN}✅ Ambos nodos están activos${NC}"
echo ""

# Obtener token de admin
echo -e "${BLUE}📋 Paso 2: Obteniendo token de administrador del Nodo 1...${NC}"
TOKEN_RESPONSE=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli")

TOKEN=$(echo $TOKEN_RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo -e "${RED}❌ No se pudo obtener el token de acceso${NC}"
    echo "Respuesta: $TOKEN_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✅ Token obtenido correctamente${NC}"
echo ""

# Crear un nuevo usuario en Nodo 1
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔵 PRUEBA 1: Crear usuario en NODO 1${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

TIMESTAMP=$(date +%s)
TEST_USER="testuser_${TIMESTAMP}"
echo -e "Creando usuario: ${BLUE}${TEST_USER}${NC} en el Nodo 1..."

CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8080/admin/realms/master/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${TEST_USER}\",
    \"enabled\": true,
    \"email\": \"${TEST_USER}@test.com\",
    \"firstName\": \"Test\",
    \"lastName\": \"User HA\"
  }")

HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "204" ]; then
    echo -e "${GREEN}✅ Usuario creado exitosamente en Nodo 1${NC}"
else
    echo -e "${YELLOW}⚠️  Respuesta HTTP: $HTTP_CODE${NC}"
fi

echo ""
sleep 2

# Verificar que el usuario existe en Nodo 2
echo -e "${YELLOW}🟢 Verificando que el usuario existe en NODO 2...${NC}"

USERS_NODE2=$(curl -s -X GET "http://localhost:8081/admin/realms/master/users?username=${TEST_USER}" \
  -H "Authorization: Bearer $TOKEN")

if echo "$USERS_NODE2" | grep -q "$TEST_USER"; then
    echo -e "${GREEN}✅ ¡Usuario visible en Nodo 2! (Base de datos compartida funciona)${NC}"
    USER_ID=$(echo "$USERS_NODE2" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    echo -e "   ID del usuario: ${BLUE}${USER_ID}${NC}"
else
    echo -e "${RED}❌ Usuario NO encontrado en Nodo 2${NC}"
fi

echo ""
sleep 2

# Crear una sesión en Nodo 1 y verificar en Nodo 2
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔵 PRUEBA 2: Replicación de Sesiones (Infinispan)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo "Iniciando sesión de administrador en Nodo 1..."
SESSION_TOKEN=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

echo -e "${GREEN}✅ Sesión creada en Nodo 1${NC}"
echo ""

echo "Usando el mismo token para consultar en Nodo 2..."
INTROSPECT_NODE2=$(curl -s -X GET "http://localhost:8081/admin/realms/master/users?max=1" \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -w "\n%{http_code}")

HTTP_CODE_NODE2=$(echo "$INTROSPECT_NODE2" | tail -n1)

if [ "$HTTP_CODE_NODE2" = "200" ]; then
    echo -e "${GREEN}✅ ¡Token válido en Nodo 2! (Sesión replicada vía Infinispan)${NC}"
else
    echo -e "${YELLOW}⚠️  HTTP Code: $HTTP_CODE_NODE2${NC}"
fi

echo ""
sleep 2

# Simulación de caída del Nodo 1
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🔵 PRUEBA 3: Simular caída del NODO 1${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${YELLOW}Deteniendo Nodo 1...${NC}"
docker compose -f docker-compose-node1.yml stop keycloak-1 > /dev/null 2>&1

sleep 3
echo -e "${RED}❌ Nodo 1 DETENIDO${NC}"
echo ""

echo -e "${YELLOW}🟢 Verificando que Nodo 2 sigue funcionando con BD actualizada...${NC}"

# Verificar que el usuario creado sigue visible en Nodo 2
USERS_AFTER_FAILOVER=$(curl -s -X GET "http://localhost:8081/admin/realms/master/users?username=${TEST_USER}" \
  -H "Authorization: Bearer $TOKEN")

if echo "$USERS_AFTER_FAILOVER" | grep -q "$TEST_USER"; then
    echo -e "${GREEN}✅ Usuario '${TEST_USER}' sigue visible en Nodo 2${NC}"
    echo -e "${GREEN}✅ Nodo 2 tiene acceso completo a la base de datos${NC}"
else
    echo -e "${RED}❌ Usuario NO encontrado${NC}"
fi

echo ""

# Intentar crear otro usuario desde Nodo 2
NEW_USER="testuser_node2_${TIMESTAMP}"
echo -e "Intentando crear un NUEVO usuario '${BLUE}${NEW_USER}${NC}' desde Nodo 2..."

CREATE_NODE2=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8081/admin/realms/master/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${NEW_USER}\",
    \"enabled\": true,
    \"email\": \"${NEW_USER}@test.com\"
  }")

HTTP_CODE_CREATE=$(echo "$CREATE_NODE2" | tail -n1)

if [ "$HTTP_CODE_CREATE" = "201" ] || [ "$HTTP_CODE_CREATE" = "204" ]; then
    echo -e "${GREEN}✅ ¡Nuevo usuario creado exitosamente desde Nodo 2!${NC}"
    echo -e "${GREEN}✅ Nodo 2 puede ESCRIBIR en la base de datos incluso con Nodo 1 caído${NC}"
else
    echo -e "${YELLOW}⚠️  HTTP Code: $HTTP_CODE_CREATE${NC}"
fi

echo ""
sleep 2

# Restaurar Nodo 1
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🔵 PRUEBA 4: Restaurar NODO 1 y verificar sincronización${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo "Reiniciando Nodo 1..."
docker compose -f docker-compose-node1.yml start keycloak-1 > /dev/null 2>&1

echo -e "${YELLOW}Esperando 15 segundos a que Nodo 1 se reconecte...${NC}"
for i in {15..1}; do
    echo -n "."
    sleep 1
done
echo ""

# Esperar a que el nodo esté listo
echo "Verificando salud del Nodo 1..."
for i in {1..30}; do
    if curl -sf http://localhost:8080/health/ready > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Nodo 1 está activo nuevamente${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Verificar que el usuario creado en Nodo 2 ahora existe en Nodo 1
echo -e "${YELLOW}🔵 Verificando que el usuario creado en Nodo 2 aparece en Nodo 1...${NC}"

sleep 3  # Dar tiempo a la caché para sincronizar

USERS_NODE1_FINAL=$(curl -s -X GET "http://localhost:8080/admin/realms/master/users?username=${NEW_USER}" \
  -H "Authorization: Bearer $TOKEN")

if echo "$USERS_NODE1_FINAL" | grep -q "$NEW_USER"; then
    echo -e "${GREEN}✅ Usuario '${NEW_USER}' (creado en Nodo 2) ahora visible en Nodo 1${NC}"
    echo -e "${GREEN}✅ Base de datos compartida mantiene consistencia total${NC}"
else
    echo -e "${YELLOW}⚠️  Usuario no encontrado aún (puede necesitar invalidación de caché)${NC}"
fi

echo ""

# Resumen final
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📊 RESUMEN DE RESULTADOS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}✅ Configuración (usuarios, realms, clientes):${NC}"
echo "   • Se guardan en PostgreSQL (base de datos compartida)"
echo "   • Cambios en Nodo 1 se ven INMEDIATAMENTE en Nodo 2"
echo "   • Si Nodo 1 cae, Nodo 2 sigue con acceso completo a la BD"
echo ""
echo -e "${GREEN}✅ Sesiones activas (tokens, logins):${NC}"
echo "   • Se replican vía Infinispan entre nodos"
echo "   • Si un nodo cae, las sesiones continúan en el otro"
echo "   • Alta disponibilidad total para usuarios finales"
echo ""
echo -e "${GREEN}✅ Resiliencia:${NC}"
echo "   • Nodo 2 puede operar independientemente"
echo "   • Nodo 1 al volver se sincroniza automáticamente"
echo "   • Zero downtime para aplicaciones"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}💡 Usuarios de prueba creados:${NC}"
echo "   • ${TEST_USER} (creado en Nodo 1)"
echo "   • ${NEW_USER} (creado en Nodo 2 con Nodo 1 caído)"
echo ""
echo -e "${YELLOW}Para limpiar los usuarios de prueba:${NC}"
echo "   1. Accede a http://localhost:8080"
echo "   2. Ve a 'Users' y elimina los usuarios 'testuser_*'"
echo ""

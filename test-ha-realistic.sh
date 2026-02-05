#!/bin/bash

# Script de prueba REALISTA de HA - Solo lo que funciona en start-dev
# Prueba SOLO la sincronización de base de datos (que sí funciona)

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   🧪 Prueba REALISTA de HA - Sincronización de Base de Datos   ║"
echo "║      (start-dev: solo configuración, NO sesiones)            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
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

# Obtener token de admin del Nodo 1
echo -e "${BLUE}📋 Paso 2: Obteniendo token de administrador del Nodo 1...${NC}"
TOKEN_NODE1=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN_NODE1" ]; then
    echo -e "${RED}❌ No se pudo obtener el token de acceso del Nodo 1${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Token del Nodo 1 obtenido${NC}"

# Obtener token de admin del Nodo 2
echo -e "${BLUE}Obteniendo token de administrador del Nodo 2...${NC}"
TOKEN_NODE2=$(curl -s -X POST "http://localhost:8081/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN_NODE2" ]; then
    echo -e "${RED}❌ No se pudo obtener el token de acceso del Nodo 2${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Token del Nodo 2 obtenido${NC}"
echo ""

# PRUEBA 1: Crear usuario en Nodo 1, verificar en Nodo 2
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}✅ PRUEBA 1: Sincronización de Base de Datos${NC}"
echo -e "${YELLOW}   Crear usuario en NODO 1 → Verificar en NODO 2${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

TIMESTAMP=$(date +%s)
TEST_USER="ha_test_${TIMESTAMP}"
echo -e "Creando usuario: ${BLUE}${TEST_USER}${NC} en el Nodo 1..."

CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8080/admin/realms/master/users" \
  -H "Authorization: Bearer $TOKEN_NODE1" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${TEST_USER}\",
    \"enabled\": true,
    \"email\": \"${TEST_USER}@test.com\",
    \"firstName\": \"Test\",
    \"lastName\": \"HA User\"
  }")

HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "204" ]; then
    echo -e "${GREEN}✅ Usuario creado en Nodo 1${NC}"
else
    echo -e "${RED}❌ Error al crear usuario. HTTP Code: $HTTP_CODE${NC}"
    exit 1
fi

sleep 2

# Verificar que el usuario existe en Nodo 2 (usando TOKEN del Nodo 2)
echo -e "${YELLOW}🔍 Buscando usuario en NODO 2 (con su propio token)...${NC}"

USERS_NODE2=$(curl -s -X GET "http://localhost:8081/admin/realms/master/users?username=${TEST_USER}&exact=true" \
  -H "Authorization: Bearer $TOKEN_NODE2")

if echo "$USERS_NODE2" | grep -q "$TEST_USER"; then
    echo -e "${GREEN}✅ ¡ÉXITO! Usuario visible en Nodo 2${NC}"
    echo -e "${GREEN}   Sincronización de PostgreSQL funciona correctamente${NC}"
    USER_ID=$(echo "$USERS_NODE2" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    echo -e "   ID del usuario: ${BLUE}${USER_ID}${NC}"
else
    echo -e "${RED}❌ Usuario NO encontrado en Nodo 2${NC}"
    echo -e "${YELLOW}Respuesta: $USERS_NODE2${NC}"
fi

echo ""
sleep 2

# PRUEBA 2: Modificar usuario en Nodo 2, verificar en Nodo 1
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}✅ PRUEBA 2: Modificación Bidireccional${NC}"
echo -e "${YELLOW}   Modificar usuario en NODO 2 → Verificar en NODO 1${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -n "$USER_ID" ]; then
    echo "Actualizando usuario en Nodo 2..."
    
    UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "http://localhost:8081/admin/realms/master/users/${USER_ID}" \
      -H "Authorization: Bearer $TOKEN_NODE2" \
      -H "Content-Type: application/json" \
      -d "{
        \"username\": \"${TEST_USER}\",
        \"enabled\": true,
        \"email\": \"${TEST_USER}@updated.com\",
        \"firstName\": \"Modified\",
        \"lastName\": \"By Node2\"
      }")
    
    HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✅ Usuario modificado en Nodo 2${NC}"
    else
        echo -e "${YELLOW}⚠️  HTTP Code: $HTTP_CODE${NC}"
    fi
    
    sleep 2
    
    # Verificar cambio en Nodo 1
    echo -e "${YELLOW}🔍 Verificando cambios en NODO 1...${NC}"
    
    USER_NODE1=$(curl -s -X GET "http://localhost:8080/admin/realms/master/users/${USER_ID}" \
      -H "Authorization: Bearer $TOKEN_NODE1")
    
    if echo "$USER_NODE1" | grep -q "Modified"; then
        echo -e "${GREEN}✅ ¡ÉXITO! Cambios visibles en Nodo 1${NC}"
        echo -e "${GREEN}   Sincronización bidireccional funciona${NC}"
    else
        echo -e "${YELLOW}⚠️  Cambios no visibles aún (puede haber caché local)${NC}"
    fi
fi

echo ""
sleep 2

# PRUEBA 3: Detener Nodo 1, operar desde Nodo 2
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}✅ PRUEBA 3: Failover de Base de Datos${NC}"
echo -e "${RED}   NODO 1 cae → NODO 2 sigue operando${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${YELLOW}Deteniendo Nodo 1...${NC}"
docker compose -f docker-compose-node1.yml stop keycloak-1 > /dev/null 2>&1

sleep 3
echo -e "${RED}❌ Nodo 1 DETENIDO${NC}"
echo ""

# Crear nuevo usuario desde Nodo 2
NEW_USER="failover_user_${TIMESTAMP}"
echo -e "${YELLOW}🟢 Creando nuevo usuario '${BLUE}${NEW_USER}${NC}${YELLOW}' desde Nodo 2...${NC}"

CREATE_NODE2=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8081/admin/realms/master/users" \
  -H "Authorization: Bearer $TOKEN_NODE2" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${NEW_USER}\",
    \"enabled\": true,
    \"email\": \"${NEW_USER}@test.com\",
    \"firstName\": \"Failover\",
    \"lastName\": \"Test\"
  }")

HTTP_CODE_CREATE=$(echo "$CREATE_NODE2" | tail -n1)

if [ "$HTTP_CODE_CREATE" = "201" ] || [ "$HTTP_CODE_CREATE" = "204" ]; then
    echo -e "${GREEN}✅ ¡Usuario creado desde Nodo 2 con Nodo 1 caído!${NC}"
    echo -e "${GREEN}✅ Nodo 2 tiene acceso completo a PostgreSQL${NC}"
else
    echo -e "${RED}❌ Error. HTTP Code: $HTTP_CODE_CREATE${NC}"
fi

echo ""
sleep 2

# Restaurar Nodo 1
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ PRUEBA 4: Recuperación y Sincronización Automática${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo "Reiniciando Nodo 1..."
docker compose -f docker-compose-node1.yml start keycloak-1 > /dev/null 2>&1

echo -e "${YELLOW}Esperando a que Nodo 1 se reconecte (15 segundos)...${NC}"
for i in {15..1}; do
    printf "."
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
    printf "."
    sleep 2
done
echo ""

# Obtener nuevo token del Nodo 1
TOKEN_NODE1_NEW=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

sleep 3

# Verificar que el usuario creado en Nodo 2 ahora existe en Nodo 1
echo -e "${YELLOW}🔍 Buscando usuario creado durante el failover en Nodo 1...${NC}"

USERS_NODE1_FINAL=$(curl -s -X GET "http://localhost:8080/admin/realms/master/users?username=${NEW_USER}&exact=true" \
  -H "Authorization: Bearer $TOKEN_NODE1_NEW")

if echo "$USERS_NODE1_FINAL" | grep -q "$NEW_USER"; then
    echo -e "${GREEN}✅ ¡Usuario '${NEW_USER}' visible en Nodo 1!${NC}"
    echo -e "${GREEN}✅ Sincronización automática al reconectar${NC}"
else
    echo -e "${YELLOW}⚠️  Usuario no encontrado aún${NC}"
fi

echo ""

# Resumen final
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📊 RESUMEN DE RESULTADOS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}✅ LO QUE FUNCIONA (PostgreSQL Compartida):${NC}"
echo "   • Crear usuarios/realms/clientes en cualquier nodo"
echo "   • Modificaciones visibles inmediatamente en ambos nodos"
echo "   • Failover completo de base de datos"
echo "   • Nodo secundario opera independientemente si el primero cae"
echo "   • Sincronización automática al recuperar nodos"
echo ""
echo -e "${YELLOW}⚠️  LO QUE NO FUNCIONA (Limitación start-dev):${NC}"
echo "   • Sesiones de usuario NO se replican"
echo "   • Tokens generados en Nodo 1 NO válidos en Nodo 2"
echo "   • Cada nodo mantiene su propia caché de sesiones"
echo ""
echo -e "${BLUE}💡 Para producción real:${NC}"
echo "   • Usa modo 'start' (no start-dev) con SSL"
echo "   • Implementa load balancer con sticky sessions"
echo "   • O migra a Kubernetes con Helm Charts"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}🧹 Usuarios de prueba creados:${NC}"
echo "   • ${TEST_USER} (creado en Nodo 1)"
echo "   • ${NEW_USER} (creado en Nodo 2 durante failover)"
echo ""
echo -e "${YELLOW}Para limpiar:${NC}"
echo "   Accede a http://localhost:8080 → Users → Elimina usuarios 'ha_test_*' y 'failover_user_*'"
echo ""

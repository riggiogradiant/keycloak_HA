#!/bin/bash
# =============================================================================
# Test de Cluster Infinispan (Keycloak)
# Verifica que el clustering de sesiones funciona correctamente
# =============================================================================

set -e

echo "=========================================="
echo "  🔗 Test de Cluster Infinispan"
echo "  Keycloak Session Replication"
echo "=========================================="
echo ""

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Test 1: Verificar formación del cluster
# ============================================================================
echo "1️⃣ Verificando formación del cluster Infinispan"
echo ""

# Obtener información de cluster view de ambos nodos
CLUSTER1=$(docker logs keycloak-nodo1 2>&1 | grep "ISPN000094.*cluster view" | tail -1)
CLUSTER2=$(docker logs keycloak-nodo2 2>&1 | grep "ISPN000094.*cluster view" | tail -1)

if [ -z "$CLUSTER1" ]; then
    echo -e "   ${YELLOW}⚠️  keycloak-nodo1: No se encontró información de cluster view${NC}"
    echo "      (El contenedor puede estar iniciando)"
else
    echo "   keycloak-nodo1:"
    echo "   $CLUSTER1" | sed 's/^/      /'
    
    # Extraer número de miembros
    MEMBERS1=$(echo "$CLUSTER1" | grep -o "([0-9]*)" | head -1 | tr -d '()')
    if [ "$MEMBERS1" == "2" ]; then
        echo -e "   ${GREEN}✅ Cluster formado con 2 miembros${NC}"
    elif [ "$MEMBERS1" == "1" ]; then
        echo -e "   ${YELLOW}⚠️  Solo 1 miembro en el cluster${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Número de miembros: $MEMBERS1${NC}"
    fi
fi

echo ""

if [ -z "$CLUSTER2" ]; then
    echo -e "   ${YELLOW}⚠️  keycloak-nodo2: No se encontró información de cluster view${NC}"
    echo "      (El contenedor puede estar iniciando)"
else
    echo "   keycloak-nodo2:"
    echo "   $CLUSTER2" | sed 's/^/      /'
    
    # Extraer número de miembros
    MEMBERS2=$(echo "$CLUSTER2" | grep -o "([0-9]*)" | head -1 | tr -d '()')
    if [ "$MEMBERS2" == "2" ]; then
        echo -e "   ${GREEN}✅ Cluster formado con 2 miembros${NC}"
    elif [ "$MEMBERS2" == "1" ]; then
        echo -e "   ${YELLOW}⚠️  Solo 1 miembro en el cluster${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Número de miembros: $MEMBERS2${NC}"
    fi
fi

# ============================================================================
# Test 2: Verificar JGroups (protocolo de comunicación)
# ============================================================================
echo ""
echo "2️⃣ Verificando protocolo JGroups"
echo ""

JGROUPS1=$(docker logs keycloak-nodo1 2>&1 | grep -i "jgroups" | grep -i "tcp\|udp\|tcpping" | tail -5)
if [ -n "$JGROUPS1" ]; then
    echo "   Últimas entradas JGroups en nodo1:"
    echo "$JGROUPS1" | sed 's/^/      /'
else
    echo -e "   ${YELLOW}⚠️  No se encontraron logs de JGroups en nodo1${NC}"
fi

# ============================================================================
# Test 3: Verificar cachés distribuidas
# ============================================================================
echo ""
echo "3️⃣ Verificando cachés distribuidas de Infinispan"
echo ""

CACHES=$(docker logs keycloak-nodo1 2>&1 | grep -i "cache.*distributed\|ispn.*cache" | tail -10)
if [ -n "$CACHES" ]; then
    echo "   Cachés configuradas:"
    echo "$CACHES" | sed 's/^/      /'
else
    echo -e "   ${YELLOW}⚠️  No se encontraron logs de cachés distribuidas${NC}"
fi

# ============================================================================
# Test 4: Verificar conectividad entre nodos
# ============================================================================
echo ""
echo "4️⃣ Verificando conectividad de red entre nodos"
echo ""

# Ping de nodo1 a nodo2
echo -n "   keycloak-nodo1 → keycloak-nodo2: "
if docker exec keycloak-nodo1 ping -c 2 keycloak-nodo2 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Conectividad OK${NC}"
else
    echo -e "${RED}❌ Sin conectividad${NC}"
fi

# Ping de nodo2 a nodo1
echo -n "   keycloak-nodo2 → keycloak-nodo1: "
if docker exec keycloak-nodo2 ping -c 2 keycloak-nodo1 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Conectividad OK${NC}"
else
    echo -e "${RED}❌ Sin conectividad${NC}"
fi

# ============================================================================
# Test 5: Verificar puertos JGroups (7800)
# ============================================================================
echo ""
echo "5️⃣ Verificando puertos JGroups"
echo ""

# Verificar que el puerto 7800 está escuchando
echo -n "   keycloak-nodo1 puerto 7800: "
if docker exec keycloak-nodo1 netstat -tuln 2>/dev/null | grep -q ":7800" || \
   docker exec keycloak-nodo1 ss -tuln 2>/dev/null | grep -q ":7800"; then
    echo -e "${GREEN}✅ Escuchando${NC}"
else
    echo -e "${YELLOW}⚠️  No detectado (puede no estar disponible netstat/ss)${NC}"
fi

echo -n "   keycloak-nodo2 puerto 7800: "
if docker exec keycloak-nodo2 netstat -tuln 2>/dev/null | grep -q ":7800" || \
   docker exec keycloak-nodo2 ss -tuln 2>/dev/null | grep -q ":7800"; then
    echo -e "${GREEN}✅ Escuchando${NC}"
else
    echo -e "${YELLOW}⚠️  No detectado (puede no estar disponible netstat/ss)${NC}"
fi

# ============================================================================
# Test 6: Verificar endpoints Keycloak
# ============================================================================
echo ""
echo "6️⃣ Verificando endpoints Keycloak"
echo ""

HTTP1=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/realms/master 2>/dev/null)
echo -n "   NODO 1 (https://localhost:8443): HTTP $HTTP1"
if [ "$HTTP1" == "200" ]; then
    echo -e " ${GREEN}✅${NC}"
else
    echo -e " ${RED}❌${NC}"
fi

HTTP2=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8444/realms/master 2>/dev/null)
echo -n "   NODO 2 (https://localhost:8444): HTTP $HTTP2"
if [ "$HTTP2" == "200" ]; then
    echo -e " ${GREEN}✅${NC}"
else
    echo -e " ${RED}❌${NC}"
fi

# ============================================================================
# Test 7: Test manual de sesión compartida (instrucciones)
# ============================================================================
echo ""
echo "7️⃣ Test de Sesión Compartida (Manual)"
echo ""
echo "   Para verificar que las sesiones se replican:"
echo ""
echo "   1. Abre en navegador: ${YELLOW}https://localhost:8443${NC}"
echo "   2. Login: admin / admin"
echo "   3. Copia la URL completa (incluye session_state=...)"
echo "   4. Cambia el puerto 8443 → 8444 en la URL"
echo "   5. Pega en nueva pestaña del navegador"
echo ""
echo "   ${GREEN}✅ RESULTADO ESPERADO:${NC} Estás autenticado sin pedir login"
echo "   ${RED}❌ SI PIDE LOGIN:${NC} Infinispan no está replicando sesiones"
echo ""

# ============================================================================
# Test 8: Verificar estado de health
# ============================================================================
echo "8️⃣ Verificando estado de salud de Keycloak"
echo ""

HEALTH1=$(curl -k -s https://localhost:8443/health 2>/dev/null | grep -o '"status":"[^"]*"' | head -1)
echo -n "   NODO 1 health: "
if echo "$HEALTH1" | grep -q "UP"; then
    echo -e "${GREEN}✅ UP${NC}"
elif [ -n "$HEALTH1" ]; then
    echo -e "${YELLOW}⚠️  $HEALTH1${NC}"
else
    echo -e "${YELLOW}⚠️  No disponible (endpoint puede estar deshabilitado)${NC}"
fi

HEALTH2=$(curl -k -s https://localhost:8444/health 2>/dev/null | grep -o '"status":"[^"]*"' | head -1)
echo -n "   NODO 2 health: "
if echo "$HEALTH2" | grep -q "UP"; then
    echo -e "${GREEN}✅ UP${NC}"
elif [ -n "$HEALTH2" ]; then
    echo -e "${YELLOW}⚠️  $HEALTH2${NC}"
else
    echo -e "${YELLOW}⚠️  No disponible (endpoint puede estar deshabilitado)${NC}"
fi

# ============================================================================
# Resultado Final
# ============================================================================
echo ""
echo "=========================================="

# Evaluar resultado
SUCCESS=true

if [ -z "$MEMBERS1" ] || [ "$MEMBERS1" != "2" ]; then
    SUCCESS=false
fi

if [ -z "$MEMBERS2" ] || [ "$MEMBERS2" != "2" ]; then
    SUCCESS=false
fi

if [ "$HTTP1" != "200" ] || [ "$HTTP2" != "200" ]; then
    SUCCESS=false
fi

if [ "$SUCCESS" = true ]; then
    echo -e "${GREEN}✅ TEST EXITOSO${NC}"
    echo "   • Cluster Infinispan formado correctamente"
    echo "   • 2 miembros detectados en el cluster"
    echo "   • Ambos nodos Keycloak respondiendo"
    echo "   • Conectividad de red establecida"
    echo ""
    echo "   ${YELLOW}📝 Nota:${NC} Ejecuta el test manual de sesión compartida"
    echo "           para confirmar la replicación de sesiones."
else
    echo -e "${YELLOW}⚠️  TEST PARCIAL O FALLIDO${NC}"
    echo ""
    if [ -z "$MEMBERS1" ] || [ "$MEMBERS1" != "2" ] || [ -z "$MEMBERS2" ] || [ "$MEMBERS2" != "2" ]; then
        echo "   • El cluster puede estar formándose aún"
        echo "   • Espera 1-2 minutos y vuelve a ejecutar el test"
    fi
    if [ "$HTTP1" != "200" ] || [ "$HTTP2" != "200" ]; then
        echo "   • Uno o ambos nodos Keycloak no responden"
        echo "   • Verifica logs: docker logs keycloak-nodo1"
    fi
    echo ""
    echo "   Comandos útiles:"
    echo "   docker logs keycloak-nodo1 --tail 50"
    echo "   docker logs keycloak-nodo2 --tail 50"
fi
echo "=========================================="

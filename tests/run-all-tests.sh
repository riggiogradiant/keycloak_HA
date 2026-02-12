#!/bin/bash
# =============================================================================
# Script Maestro - Ejecutar Todos los Tests
# Ejecuta todos los tests de verificación en secuencia
# =============================================================================

set -e

echo "=========================================="
echo "  🧪 Suite Completa de Tests"
echo "  Keycloak HA - Verificación Integral"
echo "=========================================="
echo ""

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_PARTIAL=0

run_test() {
    local test_name=$1
    local test_file=$2
    
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "  🔬 $test_name"
    echo -e "==========================================${NC}"
    echo ""
    
    if [ ! -f "$test_file" ]; then
        echo -e "${RED}❌ Test no encontrado: $test_file${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    if bash "$test_file"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo ""
        echo -e "${GREEN}✅ $test_name - COMPLETADO${NC}"
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            TESTS_PARTIAL=$((TESTS_PARTIAL + 1))
            echo ""
            echo -e "${YELLOW}⚠️  $test_name - PARCIAL (revisar resultados)${NC}"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Presiona ENTER para continuar al siguiente test (o Ctrl+C para cancelar)...${NC}"
    read -r
}

# Verificar que el despliegue está activo
echo "📋 Verificando despliegue..."
if ! docker ps | grep -q "keycloak-nodo1"; then
    echo -e "${RED}❌ ERROR: El cluster no está desplegado${NC}"
    echo ""
    echo "Ejecuta primero:"
    echo "  ./deploy-ha.sh"
    echo ""
    exit 1
fi
echo -e "${GREEN}✅ Contenedores activos${NC}"
echo ""

# Esperar a que Keycloak esté completamente iniciado
echo "⏳ Esperando que Keycloak esté listo (30 segundos)..."
sleep 30

# ============================================================================
# Ejecutar Tests
# ============================================================================

# Test 1: Sincronización de BD
run_test "Test 1: Sincronización de Base de Datos" "tests/test-sync.sh"

# Test 2: Query Routing con HAProxy
run_test "Test 2: Query Routing con HAProxy" "tests/test-routing.sh"

# Test 3: Cluster Infinispan
run_test "Test 3: Cluster Infinispan (Keycloak)" "tests/test-infinispan.sh"

# Test 4: Failover Automático (opcional - más largo)
echo ""
echo -e "${YELLOW}=========================================="
echo "  ⚠️  Test de Failover Automático"
echo "==========================================${NC}"
echo ""
echo "El test de failover:"
echo "  • Toma ~90 segundos"
echo "  • Detiene temporalmente el PRIMARY"
echo "  • Verifica la promoción automática"
echo ""
echo -n "¿Ejecutar test de failover? (s/N): "
read -r RESPONSE

if [[ "$RESPONSE" =~ ^[Ss]$ ]]; then
    run_test "Test 4: Failover Automático" "./test-failover.sh"
else
    echo -e "${YELLOW}⏭️  Test de failover omitido${NC}"
fi

# ============================================================================
# Resumen Final
# ============================================================================
echo ""
echo ""
echo "=========================================="
echo "  📊 RESUMEN DE TESTS"
echo "=========================================="
echo ""
echo -e "Tests ejecutados:  $((TESTS_PASSED + TESTS_FAILED + TESTS_PARTIAL))"
echo -e "${GREEN}✅ Exitosos:       $TESTS_PASSED${NC}"
echo -e "${YELLOW}⚠️  Parciales:      $TESTS_PARTIAL${NC}"
echo -e "${RED}❌ Fallidos:       $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ] && [ $TESTS_PARTIAL -eq 0 ]; then
    echo -e "${GREEN}🎉 TODOS LOS TESTS PASARON EXITOSAMENTE${NC}"
    echo ""
    echo "Tu cluster Keycloak HA está funcionando correctamente:"
    echo "  ✅ Replicación de base de datos: OK"
    echo "  ✅ Query routing con HAProxy: OK"
    echo "  ✅ Cluster Infinispan: OK"
    if [ $TESTS_PASSED -eq 4 ]; then
        echo "  ✅ Failover automático: OK"
    fi
elif [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${YELLOW}⚠️  ALGUNOS TESTS REQUIEREN REVISIÓN${NC}"
    echo ""
    echo "El cluster está operativo pero revisa los tests parciales"
else
    echo -e "${RED}❌ HAY TESTS FALLIDOS QUE REQUIEREN ATENCIÓN${NC}"
    echo ""
    echo "Revisa los logs de los servicios:"
    echo "  docker logs keycloak-nodo1 --tail 50"
    echo "  docker logs keycloak-nodo2 --tail 50"
    echo "  docker logs postgres-nodo1 --tail 50"
    echo "  docker logs haproxy-nodo1 --tail 50"
fi

echo ""
echo "=========================================="

#!/bin/bash

# Script para desplegar Keycloak HA en modo producción con SSL

set -e

echo "🚀 Keycloak HA - Production Deployment"
echo "======================================="
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paso 1: Verificar prerrequisitos
echo -e "${BLUE}📋 Step 1: Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    exit 1
fi

if ! command -v keytool &> /dev/null; then
    echo -e "${RED}❌ keytool is not installed${NC}"
    echo "Install Java JDK: apt install default-jdk"
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    echo -e "${RED}❌ openssl is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites met${NC}"
echo ""

# Paso 2: Generar certificados si no existen
if [ ! -f "./certs/keycloak.p12" ]; then
    echo -e "${YELLOW}📜 Step 2: Generating SSL certificates...${NC}"
    bash generate-certs.sh
else
    echo -e "${GREEN}✅ Certificates already exist${NC}"
fi
echo ""

# Paso 3: Build Keycloak
echo -e "${YELLOW}🔨 Step 3: Building Keycloak (one-time setup)...${NC}"
if [ ! -f ".keycloak-built" ]; then
    bash build-keycloak.sh
    touch .keycloak-built
    echo -e "${GREEN}✅ Keycloak built successfully${NC}"
else
    echo -e "${GREEN}✅ Keycloak already built (delete .keycloak-built to rebuild)${NC}"
fi
echo ""

# Paso 4: Iniciar servicios
echo -e "${YELLOW}🐳 Step 4: Starting services...${NC}"
docker compose -f docker-compose-prod.yml up -d

echo ""
echo -e "${YELLOW}⏳ Waiting for services to be healthy...${NC}"

# Esperar PostgreSQL
for i in {1..30}; do
    if docker exec keycloak-postgres-prod pg_isready -U keycloak > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PostgreSQL is ready${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

echo ""
echo -e "${YELLOW}⏳ Waiting for Keycloak nodes (this may take 2-3 minutes)...${NC}"

# Esperar Keycloak Node 1
for i in {1..60}; do
    if curl -k -sf https://localhost:8443/health/ready > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Keycloak Node 1 is ready${NC}"
        break
    fi
    echo -n "."
    sleep 3
done

# Esperar Keycloak Node 2
for i in {1..60}; do
    if curl -k -sf https://localhost:8444/health/ready > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Keycloak Node 2 is ready${NC}"
        break
    fi
    echo -n "."
    sleep 3
done

echo ""
echo ""
echo "================================================"
echo -e "${GREEN}🎉 Keycloak HA Cluster Deployed!${NC}"
echo "================================================"
echo ""
echo -e "${BLUE}📍 Access URLs:${NC}"
echo "   🔵 Node 1: https://localhost:8443"
echo "   🟢 Node 2: https://localhost:8444"
echo "   🔀 Load Balancer: https://localhost (Nginx)"
echo ""
echo -e "${BLUE}🔐 Admin Credentials:${NC}"
echo "   Username: admin"
echo "   Password: (ver .env.prod)"
echo ""
echo -e "${YELLOW}⚠️  SSL Certificate Warning:${NC}"
echo "   Los certificados son auto-firmados."
echo "   Tu navegador mostrará una advertencia de seguridad."
echo "   Haz clic en 'Avanzado' y 'Continuar' para acceder."
echo ""
echo -e "${BLUE}📊 Useful Commands:${NC}"
echo "   View logs:"
echo "     docker compose -f docker-compose-prod.yml logs -f keycloak-1"
echo "     docker compose -f docker-compose-prod.yml logs -f keycloak-2"
echo ""
echo "   Stop all:"
echo "     docker compose -f docker-compose-prod.yml down"
echo ""
echo "   Check clustering:"
echo "     docker logs keycloak-node-1-prod 2>&1 | grep -i 'members'"
echo ""

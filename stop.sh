#!/bin/bash

# Script to stop all Keycloak HA components

set -e

echo "🛑 Stopping Keycloak HA Cluster"
echo "================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Stopping Node 2...${NC}"
docker compose -f docker-compose-node2.yml down

echo -e "${YELLOW}Stopping Node 1 and PostgreSQL...${NC}"
docker compose -f docker-compose-node1.yml down

echo ""
echo -e "${GREEN}✅ All services stopped${NC}"
echo ""
echo "To remove the network as well, run:"
echo "  docker network rm keycloak-ha-net"
echo ""
echo "To remove volumes (WARNING: deletes all data), run:"
echo "  docker compose -f docker-compose-node1.yml down -v"

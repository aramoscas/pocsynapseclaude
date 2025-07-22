#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Déploiement SynapseGrid${NC}"

# 1. Build
echo -e "${YELLOW}Build du gateway...${NC}"
docker-compose build gateway

# 2. Start services
echo -e "${YELLOW}Démarrage des services...${NC}"
docker-compose up -d

# 3. Wait for services
echo -e "${YELLOW}Attente des services...${NC}"
sleep 10

# 4. Configure Redis
echo -e "${YELLOW}Configuration Redis...${NC}"
docker exec synapse_redis redis-cli << 'REDIS'
DEL nodes:registered
SADD nodes:registered "node_default"
SET node:node_default:info '{"node_id":"node_default","status":"available","capacity":1.0}'
REDIS

# 5. Test
echo -e "${YELLOW}Test de santé...${NC}"
curl -s http://localhost:8080/health | jq .

echo -e "${GREEN}✅ Déploiement terminé!${NC}"
echo ""
echo "Logs: docker-compose logs -f gateway"

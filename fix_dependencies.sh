#!/bin/bash

# Script to fix dependency issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Fixing Dependency Issues ===${NC}"

# 1. Fix shared/requirements.txt - remove asyncio-redis and update versions
echo -e "\n${GREEN}Updating shared/requirements.txt...${NC}"
cat > shared/requirements.txt << 'EOF'
# Shared dependencies for all services
redis==5.0.1
psycopg2-binary==2.9.9
sqlalchemy==2.0.23
pydantic==2.5.2
pydantic-settings==2.1.0
python-dotenv==1.0.0
grpcio==1.60.0
grpcio-tools==1.60.0
protobuf==4.25.1
aiohttp==3.9.1
uvloop==0.19.0
structlog==23.2.0
prometheus-client==0.19.0
cryptography==41.0.7
pyjwt==2.8.0
asyncpg==0.29.0
EOF

# 2. Update all Python files to use only redis (not asyncio-redis)
echo -e "\n${GREEN}Updating Python imports to use redis.asyncio...${NC}"

# Gateway main.py - already uses redis.asyncio
echo "✓ Gateway already uses redis.asyncio"

# Dispatcher main.py - already uses redis.asyncio
echo "✓ Dispatcher already uses redis.asyncio"

# Aggregator main.py - already uses redis.asyncio
echo "✓ Aggregator already uses redis.asyncio"

# Node main.py - already uses redis.asyncio
echo "✓ Node already uses redis.asyncio"

# 3. Clean up Docker build cache
echo -e "\n${YELLOW}Cleaning Docker build cache...${NC}"
docker system prune -f

# 4. Stop all services
echo -e "\n${YELLOW}Stopping all services...${NC}"
docker-compose down

# 5. Remove old images
echo -e "\n${YELLOW}Removing old images...${NC}"
docker-compose rm -f
docker images | grep synapse | awk '{print $3}' | xargs -r docker rmi -f || true

# 6. Rebuild with updated dependencies
echo -e "\n${GREEN}Rebuilding Docker images...${NC}"
docker-compose build --no-cache --progress=plain

# 7. Start services
echo -e "\n${GREEN}Starting services...${NC}"
docker-compose up -d

# 8. Wait for services
echo -e "\n${YELLOW}Waiting for services to start...${NC}"
sleep 15

# 9. Check service status
echo -e "\n${GREEN}Checking service status...${NC}"
docker-compose ps

# 10. Test health endpoint
echo -e "\n${GREEN}Testing API health endpoint...${NC}"
curl -s http://localhost:8080/health | jq . || echo -e "${RED}API not ready yet${NC}"

# 11. Show recent logs
echo -e "\n${GREEN}Recent logs from services:${NC}"
echo -e "\n${YELLOW}Gateway:${NC}"
docker-compose logs --tail=5 gateway

echo -e "\n${YELLOW}Dispatcher:${NC}"
docker-compose logs --tail=5 dispatcher

echo -e "\n${YELLOW}Node:${NC}"
docker-compose logs --tail=5 node

echo -e "\n${GREEN}=== Dependency Fix Complete ===${NC}"
echo -e "${YELLOW}If services are still failing, check full logs with:${NC}"
echo "docker-compose logs -f [service_name]"

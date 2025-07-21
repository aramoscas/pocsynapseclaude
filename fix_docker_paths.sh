#!/bin/bash

# Script to fix Docker path issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Fixing Docker Path Issues ===${NC}"

# 1. Stop all services
echo -e "\n${YELLOW}Stopping all services...${NC}"
docker-compose down

# 2. Update all Dockerfiles to fix the CMD path
echo -e "\n${GREEN}Updating Dockerfiles...${NC}"

# Fix Gateway Dockerfile
echo -e "${GREEN}Fixing services/gateway/Dockerfile...${NC}"
cat > services/gateway/Dockerfile << 'EOF'
FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy shared dependencies first
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/gateway/requirements.txt /app/services/gateway/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/gateway/requirements.txt

# Copy shared code
COPY shared /app/shared

# Copy service code
COPY services/gateway /app/services/gateway

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH

EXPOSE 8080

CMD ["python", "services/gateway/main.py"]
EOF

# Fix Dispatcher Dockerfile
echo -e "${GREEN}Fixing services/dispatcher/Dockerfile...${NC}"
cat > services/dispatcher/Dockerfile << 'EOF'
FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy shared dependencies first
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/dispatcher/requirements.txt /app/services/dispatcher/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/dispatcher/requirements.txt

# Copy shared code
COPY shared /app/shared

# Copy service code
COPY services/dispatcher /app/services/dispatcher

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH

CMD ["python", "services/dispatcher/main.py"]
EOF

# Fix Aggregator Dockerfile
echo -e "${GREEN}Fixing services/aggregator/Dockerfile...${NC}"
cat > services/aggregator/Dockerfile << 'EOF'
FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy shared dependencies first
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/aggregator/requirements.txt /app/services/aggregator/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/aggregator/requirements.txt

# Copy shared code
COPY shared /app/shared

# Copy service code
COPY services/aggregator /app/services/aggregator

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH

CMD ["python", "services/aggregator/main.py"]
EOF

# Fix Node Dockerfile
echo -e "${GREEN}Fixing services/node/Dockerfile...${NC}"
cat > services/node/Dockerfile << 'EOF'
FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies for ONNX and compute
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libgomp1 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Copy shared dependencies first
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/node/requirements.txt /app/services/node/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/node/requirements.txt

# Copy shared code
COPY shared /app/shared

# Copy service code
COPY services/node /app/services/node

# Create models directory
RUN mkdir -p /app/models

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH
ENV OMP_NUM_THREADS=1

CMD ["python", "services/node/main.py"]
EOF

# 3. Update docker-compose.override.yml to fix volumes
echo -e "\n${GREEN}Updating docker-compose.override.yml...${NC}"
cat > docker-compose.override.yml << 'EOF'
# Development overrides for docker-compose

services:
  gateway:
    environment:
      - LOG_LEVEL=DEBUG
      - PYTHONUNBUFFERED=1
    volumes:
      - ./services/gateway:/app/services/gateway
      - ./shared:/app/shared
    command: python -u services/gateway/main.py

  dispatcher:
    environment:
      - LOG_LEVEL=DEBUG
      - PYTHONUNBUFFERED=1
    volumes:
      - ./services/dispatcher:/app/services/dispatcher
      - ./shared:/app/shared
    command: python -u services/dispatcher/main.py

  aggregator:
    environment:
      - LOG_LEVEL=DEBUG
      - PYTHONUNBUFFERED=1
    volumes:
      - ./services/aggregator:/app/services/aggregator
      - ./shared:/app/shared
    command: python -u services/aggregator/main.py

  node:
    environment:
      - LOG_LEVEL=DEBUG
      - PYTHONUNBUFFERED=1
      - REDIS_URL=redis://redis:6379
    volumes:
      - ./services/node:/app/services/node
      - ./shared:/app/shared
    command: python -u services/node/main.py
    
  # Additional node for testing
  node-2:
    build:
      context: .
      dockerfile: services/node/Dockerfile
    container_name: synapse_node_2
    environment:
      - GATEWAY_URL=http://gateway:8080
      - NODE_ID=node-002
      - REGION=eu-west-1
      - REDIS_URL=redis://redis:6379
      - LOG_LEVEL=DEBUG
      - PYTHONUNBUFFERED=1
    depends_on:
      - gateway
      - dispatcher
    volumes:
      - ./services/node:/app/services/node
      - ./shared:/app/shared
    networks:
      - synapse_network
    command: python -u services/node/main.py
EOF

# 4. Fix the Python imports in main.py files to use absolute paths
echo -e "\n${GREEN}Fixing Python import paths...${NC}"

# Update imports in all main.py files
for service in gateway dispatcher aggregator node; do
    if [ -f "services/$service/main.py" ]; then
        echo -e "${GREEN}Updating imports in services/$service/main.py...${NC}"
        # Change the sys.path.append line
        sed -i.bak 's|sys.path.append.*|# Path already set by PYTHONPATH env variable|' "services/$service/main.py"
        rm -f "services/$service/main.py.bak"
    fi
done

# 5. Remove asyncio from dispatcher requirements (it's built-in)
echo -e "\n${GREEN}Fixing dispatcher requirements.txt...${NC}"
cat > services/dispatcher/requirements.txt << 'EOF'
# Dispatcher specific dependencies
apscheduler==3.10.4
EOF

# 6. Rebuild Docker images
echo -e "\n${YELLOW}Rebuilding Docker images...${NC}"
docker-compose build --no-cache

# 7. Start services
echo -e "\n${GREEN}Starting services...${NC}"
docker-compose up -d

# 8. Wait for services to start
echo -e "\n${YELLOW}Waiting for services to start...${NC}"
sleep 10

# 9. Check service status
echo -e "\n${GREEN}Checking service status...${NC}"
docker-compose ps

# 10. Check logs for errors
echo -e "\n${GREEN}Checking for errors in logs...${NC}"
echo -e "${YELLOW}Gateway logs:${NC}"
docker-compose logs --tail=10 gateway | grep -E "(error|Error|ERROR)" || echo "No errors found"

echo -e "\n${YELLOW}Dispatcher logs:${NC}"
docker-compose logs --tail=10 dispatcher | grep -E "(error|Error|ERROR)" || echo "No errors found"

echo -e "\n${YELLOW}Node logs:${NC}"
docker-compose logs --tail=10 node | grep -E "(error|Error|ERROR)" || echo "No errors found"

echo -e "\n${YELLOW}Aggregator logs:${NC}"
docker-compose logs --tail=10 aggregator | grep -E "(error|Error|ERROR)" || echo "No errors found"

# 11. Test the API
echo -e "\n${GREEN}Testing API health endpoint...${NC}"
sleep 5
curl -s http://localhost:8080/health | jq . || echo -e "${RED}API not responding yet${NC}"

echo -e "\n${GREEN}=== Fix Complete ===${NC}"
echo -e "${YELLOW}Run 'docker-compose logs -f' to see all logs${NC}"
echo -e "${YELLOW}Run './test_system.py' to test the system${NC}"

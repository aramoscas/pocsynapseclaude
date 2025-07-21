#!/bin/bash

# Script to fix aiohttp build issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Fixing aiohttp Build Issues ===${NC}"

# 1. Update shared requirements with compatible versions
echo -e "\n${GREEN}Updating shared/requirements.txt with compatible versions...${NC}"
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
# Use aiohttp 3.8.6 which has better wheel support
aiohttp==3.8.6
uvloop==0.19.0
structlog==23.2.0
prometheus-client==0.19.0
cryptography==41.0.7
pyjwt==2.8.0
asyncpg==0.29.0
EOF

# 2. Update Dockerfiles to install build dependencies and use wheels
echo -e "\n${GREEN}Updating Gateway Dockerfile...${NC}"
cat > services/gateway/Dockerfile << 'EOF'
FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies and build tools
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip to get better wheel support
RUN pip install --upgrade pip setuptools wheel

# Copy requirements files
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/gateway/requirements.txt /app/services/gateway/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/gateway/requirements.txt

# Copy application code
COPY shared /app/shared
COPY services/gateway /app/services/gateway

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH

EXPOSE 8080

CMD ["python", "services/gateway/main.py"]
EOF

echo -e "\n${GREEN}Updating Dispatcher Dockerfile...${NC}"
cat > services/dispatcher/Dockerfile << 'EOF'
FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Copy requirements files
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/dispatcher/requirements.txt /app/services/dispatcher/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/dispatcher/requirements.txt

# Copy application code
COPY shared /app/shared
COPY services/dispatcher /app/services/dispatcher

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH

CMD ["python", "services/dispatcher/main.py"]
EOF

echo -e "\n${GREEN}Updating Aggregator Dockerfile...${NC}"
cat > services/aggregator/Dockerfile << 'EOF'
FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Copy requirements files
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/aggregator/requirements.txt /app/services/aggregator/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/aggregator/requirements.txt

# Copy application code
COPY shared /app/shared
COPY services/aggregator /app/services/aggregator

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH

CMD ["python", "services/aggregator/main.py"]
EOF

echo -e "\n${GREEN}Updating Node Dockerfile...${NC}"
cat > services/node/Dockerfile << 'EOF'
FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies for ONNX and compute
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    libgomp1 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Copy requirements files
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/node/requirements.txt /app/services/node/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/node/requirements.txt

# Copy application code
COPY shared /app/shared
COPY services/node /app/services/node

# Create models directory
RUN mkdir -p /app/models

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH
ENV OMP_NUM_THREADS=1

CMD ["python", "services/node/main.py"]
EOF

# 3. Create a simplified test service first
echo -e "\n${GREEN}Creating test requirements for debugging...${NC}"
cat > test_requirements.txt << 'EOF'
redis==5.0.1
fastapi==0.104.1
uvicorn==0.24.0
EOF

# 4. Clean everything
echo -e "\n${YELLOW}Cleaning Docker environment...${NC}"
docker-compose down -v
docker system prune -af --volumes

# 5. Try building just the gateway first
echo -e "\n${GREEN}Building gateway service first...${NC}"
docker-compose build gateway

# 6. If gateway builds successfully, build the rest
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}Gateway built successfully! Building other services...${NC}"
    docker-compose build
else
    echo -e "\n${RED}Gateway build failed. Trying alternative approach...${NC}"
    
    # Alternative: Use a different base image with pre-built wheels
    echo -e "\n${GREEN}Using alternative Dockerfile with pre-built dependencies...${NC}"
    cat > services/gateway/Dockerfile.alternative << 'EOF'
FROM python:3.11

WORKDIR /app

# Copy requirements files
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/gateway/requirements.txt /app/services/gateway/requirements.txt

# Install Python dependencies using pre-built wheels where possible
RUN pip install --upgrade pip && \
    pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt && \
    pip install --prefer-binary --no-cache-dir -r /app/services/gateway/requirements.txt

# Copy application code
COPY shared /app/shared
COPY services/gateway /app/services/gateway

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH

EXPOSE 8080

CMD ["python", "services/gateway/main.py"]
EOF
    
    echo -e "${YELLOW}Try building with: docker build -f services/gateway/Dockerfile.alternative -t synapse-gateway .${NC}"
fi

# 7. Start services if build succeeded
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}Starting services...${NC}"
    docker-compose up -d
    
    sleep 10
    
    echo -e "\n${GREEN}Checking service status...${NC}"
    docker-compose ps
    
    echo -e "\n${GREEN}Testing API...${NC}"
    curl -s http://localhost:8080/health | jq . || echo -e "${RED}API not ready${NC}"
fi

echo -e "\n${GREEN}=== Fix Complete ===${NC}"
echo -e "${YELLOW}If build still fails, try:${NC}"
echo "1. Use the alternative Dockerfile"
echo "2. Build on x86_64 architecture"
echo "3. Use pre-built Docker images from Docker Hub"

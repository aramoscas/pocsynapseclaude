#!/bin/bash

# Complete setup script for SynapseGrid MVP
# This script creates all necessary files and directories

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== SynapseGrid Complete Setup Script ===${NC}"
echo "This script will create all necessary files and directories"
echo ""

# Function to create directory
create_dir() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        echo -e "${GREEN}✓${NC} Created directory: $1"
    else
        echo -e "${YELLOW}→${NC} Directory exists: $1"
    fi
}

# Function to create file
create_file() {
    local file_path="$1"
    local file_content="$2"
    
    if [ ! -f "$file_path" ]; then
        echo "$file_content" > "$file_path"
        echo -e "${GREEN}✓${NC} Created file: $file_path"
    else
        echo -e "${YELLOW}→${NC} File exists: $file_path (skipping)"
    fi
}

# 1. Create directory structure
echo -e "\n${GREEN}Step 1: Creating directory structure...${NC}"
create_dir "services/gateway"
create_dir "services/dispatcher"
create_dir "services/aggregator"
create_dir "services/node"
create_dir "services/dashboard"
create_dir "shared"
create_dir "sql"
create_dir "nginx"
create_dir "monitoring/grafana/provisioning/dashboards"
create_dir "monitoring/grafana/provisioning/datasources"
create_dir "models"

# 2. Create __init__.py files
echo -e "\n${GREEN}Step 2: Creating Python __init__.py files...${NC}"
touch shared/__init__.py
touch services/__init__.py
touch services/gateway/__init__.py
touch services/dispatcher/__init__.py
touch services/aggregator/__init__.py
touch services/node/__init__.py
echo -e "${GREEN}✓${NC} Created all __init__.py files"

# 3. Create Dockerfiles
echo -e "\n${GREEN}Step 3: Creating Dockerfiles...${NC}"

# Gateway Dockerfile
create_file "services/gateway/Dockerfile" 'FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy shared dependencies first
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/gateway/requirements.txt /app/service/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/service/requirements.txt

# Copy shared code
COPY shared /app/shared

# Copy service code
COPY services/gateway /app/service

WORKDIR /app/service

ENV PYTHONPATH=/app:$PYTHONPATH

EXPOSE 8080

CMD ["python", "main.py"]'

# Dispatcher Dockerfile
create_file "services/dispatcher/Dockerfile" 'FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy shared dependencies first
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/dispatcher/requirements.txt /app/service/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/service/requirements.txt

# Copy shared code
COPY shared /app/shared

# Copy service code
COPY services/dispatcher /app/service

WORKDIR /app/service

ENV PYTHONPATH=/app:$PYTHONPATH

CMD ["python", "main.py"]'

# Aggregator Dockerfile
create_file "services/aggregator/Dockerfile" 'FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy shared dependencies first
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/aggregator/requirements.txt /app/service/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/service/requirements.txt

# Copy shared code
COPY shared /app/shared

# Copy service code
COPY services/aggregator /app/service

WORKDIR /app/service

ENV PYTHONPATH=/app:$PYTHONPATH

CMD ["python", "main.py"]'

# Node Dockerfile
create_file "services/node/Dockerfile" 'FROM python:3.11-slim-bullseye

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
COPY services/node/requirements.txt /app/service/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/service/requirements.txt

# Copy shared code
COPY shared /app/shared

# Copy service code
COPY services/node /app/service

# Create models directory
RUN mkdir -p /app/models

WORKDIR /app/service

ENV PYTHONPATH=/app:$PYTHONPATH
ENV OMP_NUM_THREADS=1

CMD ["python", "main.py"]'

# 4. Create requirements.txt files
echo -e "\n${GREEN}Step 4: Creating requirements.txt files...${NC}"

# Shared requirements
create_file "shared/requirements.txt" '# Shared dependencies for all services
redis==5.0.1
asyncio-redis==0.16.1
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
pyjwt==2.8.0'

# Gateway requirements
create_file "services/gateway/requirements.txt" '# Gateway specific dependencies
fastapi==0.104.1
uvicorn==0.24.0
httpx==0.25.2
websockets==12.0
python-multipart==0.0.6
slowapi==0.1.9'

# Dispatcher requirements
create_file "services/dispatcher/requirements.txt" '# Dispatcher specific dependencies
apscheduler==3.10.4
asyncio==3.4.3'

# Aggregator requirements
create_file "services/aggregator/requirements.txt" '# Aggregator specific dependencies
# (empty for now, using only shared dependencies)'

# Node requirements
create_file "services/node/requirements.txt" '# Node specific dependencies
onnxruntime==1.16.3
numpy==1.24.3
pillow==10.1.0
psutil==5.9.6
aiofiles==23.2.1'

# 5. Create Python service files
echo -e "\n${GREEN}Step 5: Creating Python service files...${NC}"
echo -e "${YELLOW}Note: Service Python files are too large to include inline.${NC}"
echo -e "${YELLOW}Please copy the main.py files from the artifacts provided earlier.${NC}"

# Create placeholder files
touch services/gateway/main.py
touch services/dispatcher/main.py
touch services/aggregator/main.py
touch services/node/main.py
touch shared/models.py
touch shared/utils.py

# 6. Create SQL init file
echo -e "\n${GREEN}Step 6: Creating SQL initialization file...${NC}"
create_file "sql/init.sql" '-- Initial database schema for SynapseGrid

-- Jobs table
CREATE TABLE IF NOT EXISTS jobs (
    job_id VARCHAR(255) PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    input_data JSONB NOT NULL,
    priority INTEGER DEFAULT 1,
    client_id VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    submitted_at TIMESTAMP NOT NULL,
    assigned_node VARCHAR(255),
    assigned_at TIMESTAMP,
    completed_at TIMESTAMP,
    result JSONB,
    error TEXT,
    region VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Nodes table
CREATE TABLE IF NOT EXISTS nodes (
    node_id VARCHAR(255) PRIMARY KEY,
    region VARCHAR(50) NOT NULL,
    status VARCHAR(50) NOT NULL,
    capabilities JSONB NOT NULL,
    registered_at TIMESTAMP NOT NULL,
    last_heartbeat FLOAT NOT NULL,
    cpu_usage FLOAT DEFAULT 0,
    memory_available FLOAT DEFAULT 100,
    success_rate FLOAT DEFAULT 100,
    avg_response_time FLOAT DEFAULT 0,
    uptime_hours FLOAT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_client ON jobs(client_id);
CREATE INDEX idx_jobs_region ON jobs(region);
CREATE INDEX idx_nodes_region ON nodes(region);
CREATE INDEX idx_nodes_status ON nodes(status);'

# 7. Create Nginx config
echo -e "\n${GREEN}Step 7: Creating Nginx configuration...${NC}"
create_file "nginx/nginx.conf" 'worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    upstream gateway {
        server gateway:8080;
        keepalive 32;
    }

    server {
        listen 80;
        server_name _;

        location /api/ {
            proxy_pass http://gateway/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        location /health {
            proxy_pass http://gateway/health;
            access_log off;
        }
    }
}'

# 8. Create monitoring files
echo -e "\n${GREEN}Step 8: Creating monitoring configuration...${NC}"
create_file "monitoring/prometheus.yml" 'global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: gateway
    static_configs:
      - targets: [gateway:8080]
    metrics_path: /metrics'

create_file "monitoring/grafana/provisioning/datasources/prometheus.yml" 'apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true'

create_file "monitoring/grafana/provisioning/dashboards/dashboard.yml" 'apiVersion: 1

providers:
  - name: default
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /etc/grafana/provisioning/dashboards'

# 9. Create .env.example
echo -e "\n${GREEN}Step 9: Creating environment file...${NC}"
create_file ".env.example" '# Environment variables for SynapseGrid

# Database
POSTGRES_DB=synapse
POSTGRES_USER=synapse
POSTGRES_PASSWORD=synapse123

# Redis
REDIS_URL=redis://redis:6379

# JWT
JWT_SECRET=your-super-secret-jwt-key-change-this

# Node Configuration
NODE_REGION=eu-west-1
NODE_RANKING_INTERVAL=30

# Monitoring
GRAFANA_ADMIN_PASSWORD=admin123

# Development
LOG_LEVEL=INFO
ENVIRONMENT=development'

# Copy .env.example to .env if it doesn't exist
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo -e "${GREEN}✓${NC} Created .env from .env.example"
fi

# 10. Create docker-compose.override.yml
echo -e "\n${GREEN}Step 10: Creating docker-compose override...${NC}"
create_file "docker-compose.override.yml" '# Development overrides for docker-compose

services:
  gateway:
    environment:
      - LOG_LEVEL=DEBUG
      - PYTHONUNBUFFERED=1
    command: python -u main.py

  dispatcher:
    environment:
      - LOG_LEVEL=DEBUG
      - PYTHONUNBUFFERED=1
    command: python -u main.py

  aggregator:
    environment:
      - LOG_LEVEL=DEBUG
      - PYTHONUNBUFFERED=1
    command: python -u main.py

  node:
    environment:
      - LOG_LEVEL=DEBUG
      - PYTHONUNBUFFERED=1
    command: python -u main.py'

# 11. Make scripts executable
echo -e "\n${GREEN}Step 11: Making scripts executable...${NC}"
chmod +x setup_complete.sh 2>/dev/null || true
chmod +x debug.sh 2>/dev/null || true
chmod +x fix_common_issues.sh 2>/dev/null || true
chmod +x test_system.py 2>/dev/null || true

# 12. Final message
echo -e "\n${GREEN}=== Setup Complete! ===${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: The Python service files (main.py) were not created automatically.${NC}"
echo -e "${YELLOW}Please copy the content of these files from the artifacts provided earlier:${NC}"
echo "  - services/gateway/main.py"
echo "  - services/dispatcher/main.py"
echo "  - services/aggregator/main.py"
echo "  - services/node/main.py"
echo "  - shared/models.py"
echo "  - shared/utils.py"
echo ""
echo -e "${GREEN}After copying the Python files, run:${NC}"
echo "  1. make build    # Build Docker images"
echo "  2. make start    # Start all services"
echo "  3. make test     # Test the API"
echo ""
echo -e "${GREEN}Or use Docker directly:${NC}"
echo "  1. docker-compose build"
echo "  2. docker-compose up -d"
echo "  3. ./test_system.py"

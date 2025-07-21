#!/bin/bash
# clean_and_rebuild.sh
# Nettoie complètement et reconstruit le projet

set -e

echo "🧹 Nettoyage et reconstruction complète de SynapseGrid"
echo "===================================================="
echo ""

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Étape 1: Arrêter tous les conteneurs
print_info "Arrêt de tous les conteneurs..."
docker-compose down -v 2>/dev/null || true
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Étape 2: Nettoyer les images Docker
print_info "Nettoyage des images Docker..."
docker rmi $(docker images -q) -f 2>/dev/null || true
docker system prune -af --volumes

# Étape 3: Supprimer node-2 et tout nettoyer
print_info "Suppression des fichiers problématiques..."
rm -rf services/node-2
rm -rf services/node-*

# Étape 4: Créer un docker-compose.yml propre
print_info "Création d'un nouveau docker-compose.yml..."

cat > docker-compose.yml << 'EOF'
services:
  # === DATA LAYER ===
  redis:
    image: redis:7-alpine
    container_name: synapse_redis
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    networks:
      - synapse_network

  postgres:
    image: postgres:15-alpine
    container_name: synapse_postgres
    environment:
      POSTGRES_DB: synapse
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: synapse123
    ports:
      - "5432:5432"
    volumes:
      - ./sql:/docker-entrypoint-initdb.d
    networks:
      - synapse_network

  # === CORE SERVICES ===
  gateway:
    build: ./services/gateway
    container_name: synapse_gateway
    ports:
      - "8080:8080"
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://synapse:synapse123@postgres:5432/synapse
    depends_on:
      - redis
      - postgres
    networks:
      - synapse_network

  dispatcher:
    build: ./services/dispatcher
    container_name: synapse_dispatcher
    ports:
      - "8001:8001"
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
    networks:
      - synapse_network

  aggregator:
    build: ./services/aggregator
    container_name: synapse_aggregator
    ports:
      - "8002:8002"
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
    networks:
      - synapse_network

  node1:
    build: ./services/node
    container_name: synapse_node1
    ports:
      - "8003:8003"
    environment:
      - REDIS_URL=redis://redis:6379
      - NODE_ID=node1
    depends_on:
      - redis
    networks:
      - synapse_network

  # === FRONTEND ===
  dashboard:
    image: node:18-alpine
    container_name: synapse_dashboard
    working_dir: /app
    volumes:
      - ./dashboard:/app
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://localhost:8080
    command: sh -c "npm install && npm start"
    networks:
      - synapse_network
    depends_on:
      - gateway

networks:
  synapse_network:
    driver: bridge
EOF

print_status "docker-compose.yml créé"

# Étape 5: Créer le service node (un seul)
print_info "Création du service node..."

mkdir -p services/node

cat > services/node/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

EXPOSE 8003

CMD ["python", "main.py"]
EOF

cat > services/node/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
redis[hiredis]==5.0.1
EOF

cat > services/node/main.py << 'EOF'
# services/node/main.py
import asyncio
import json
import logging
import time
import uuid
import random
import os
import redis.asyncio as aioredis
from fastapi import FastAPI
import uvicorn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SynapseGrid Node")

redis_client = None
node_id = os.getenv("NODE_ID", f"node_{uuid.uuid4().hex[:8]}")

async def startup():
    global redis_client
    redis_client = aioredis.from_url("redis://redis:6379", decode_responses=True)
    
    # Register node
    node_info = {
        "id": node_id,
        "name": f"Docker Node {node_id}",
        "status": "active",
        "gpu_model": "NVIDIA RTX 3080",
        "cpu_cores": 16,
        "memory_gb": 32,
        "load": 0.0,
        "jobs_completed": 0,
        "capabilities": ["llm", "vision"],
        "region": "docker-local",
        "lat": 40.7128,
        "lng": -74.0060
    }
    
    await redis_client.hset(f"node:{node_id}:info", mapping=node_info)
    await redis_client.incr("metrics:total_nodes")
    
    logger.info(f"Node {node_id} started and registered")

@app.on_event("startup")
async def on_startup():
    await startup()

@app.get("/health")
async def health():
    return {"status": "healthy", "node_id": node_id}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8003)
EOF

print_status "Service node créé"

# Étape 6: Vérifier que les autres services existent
for service in gateway dispatcher aggregator; do
    if [ ! -f "services/$service/main.py" ]; then
        print_warning "Service $service manquant - utilisez fix_docker_compose.sh pour le créer"
    else
        print_status "Service $service OK"
    fi
done

# Étape 7: Créer un Makefile simple
print_info "Création d'un Makefile simple..."

cat > Makefile << 'EOF'
.PHONY: help build start stop logs clean

help:
	@echo "Commands:"
	@echo "  make build  - Build all services"
	@echo "  make start  - Start all services"
	@echo "  make stop   - Stop all services"
	@echo "  make logs   - View logs"
	@echo "  make clean  - Clean everything"

build:
	docker-compose build

start:
	docker-compose up -d

stop:
	docker-compose down

logs:
	docker-compose logs -f

clean:
	docker-compose down -v
	docker system prune -af
EOF

print_status "Makefile créé"

# Instructions finales
echo ""
echo "🎉 Nettoyage terminé!"
echo "===================="
echo ""
echo "Structure simplifiée:"
echo "- Un seul service 'node' (node1)"
echo "- Pas de node-2 ou autres variants"
echo "- docker-compose.yml propre"
echo ""
echo "🚀 Pour démarrer:"
echo ""
echo "1. Vérifier que gateway, dispatcher et aggregator existent:"
echo "   ls services/"
echo ""
echo "2. Si des services manquent, exécutez d'abord:"
echo "   ./fix_docker_compose.sh"
echo ""
echo "3. Construire:"
echo "   make build"
echo ""
echo "4. Démarrer:"
echo "   make start"
echo ""
echo "5. Vérifier:"
echo "   make logs"
echo ""
print_warning "Note: Si 'make' ne fonctionne pas, utilisez directement docker-compose"

#!/bin/bash
# verify_and_fix.sh
# Vérifie et corrige la structure des fichiers

set -e

echo "🔍 Vérification de la structure du projet"
echo "========================================"
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

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Fonction pour vérifier et créer un service
check_and_create_service() {
    local service=$1
    local port=$2
    
    if [ ! -f "services/$service/main.py" ]; then
        print_warning "Service $service manquant - création..."
        mkdir -p "services/$service"
        
        # Créer le fichier Python selon le service
        case $service in
            "gateway")
                # Le gateway a déjà été créé, on vérifie juste
                if [ ! -f "services/gateway/main.py" ]; then
                    print_error "Gateway main.py manquant!"
                    return 1
                fi
                ;;
            "dispatcher")
                cat > "services/$service/main.py" << 'EOF'
# services/dispatcher/main.py
import asyncio
import json
import logging
import time
from typing import Dict, List
import redis.asyncio as aioredis
from fastapi import FastAPI
import uvicorn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SynapseGrid Dispatcher")

redis_client = None
node_scores = {}

async def startup():
    global redis_client
    redis_client = aioredis.from_url("redis://redis:6379", decode_responses=True)
    logger.info("Dispatcher started")

async def calculate_node_scores():
    """Calculate node scores based on load and capabilities"""
    while True:
        try:
            # Get all nodes
            node_keys = await redis_client.keys("node:*:info")
            
            for key in node_keys:
                node_data = await redis_client.hgetall(key)
                if node_data and node_data.get("status") == "active":
                    node_id = key.split(":")[1]
                    
                    # Simple scoring: inverse of load
                    load = float(node_data.get("load", 1.0))
                    score = 1.0 - load
                    
                    node_scores[node_id] = score
                    
                    # Store in Redis
                    await redis_client.zadd("node_scores", {node_id: score})
            
            await asyncio.sleep(5)
        except Exception as e:
            logger.error(f"Error calculating scores: {e}")
            await asyncio.sleep(5)

async def dispatch_jobs():
    """Dispatch jobs to nodes"""
    while True:
        try:
            # Get pending jobs
            job_id = await redis_client.rpop("jobs:queue:1")
            if job_id:
                # Get best node
                best_nodes = await redis_client.zrevrange("node_scores", 0, 0)
                if best_nodes:
                    node_id = best_nodes[0]
                    
                    # Assign job to node
                    await redis_client.hset(f"job:{job_id}:info", "node_id", node_id)
                    await redis_client.hset(f"job:{job_id}:info", "status", "assigned")
                    
                    # Notify node
                    await redis_client.lpush(f"node:{node_id}:jobs", job_id)
                    
                    logger.info(f"Dispatched job {job_id} to node {node_id}")
            
            await asyncio.sleep(1)
        except Exception as e:
            logger.error(f"Error dispatching jobs: {e}")
            await asyncio.sleep(1)

@app.on_event("startup")
async def on_startup():
    await startup()
    asyncio.create_task(calculate_node_scores())
    asyncio.create_task(dispatch_jobs())

@app.get("/health")
async def health():
    return {"status": "healthy", "node_scores": len(node_scores)}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
EOF
                ;;
            "aggregator")
                cat > "services/$service/main.py" << 'EOF'
# services/aggregator/main.py
import asyncio
import json
import logging
import redis.asyncio as aioredis
from fastapi import FastAPI
import uvicorn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SynapseGrid Aggregator")

redis_client = None

async def startup():
    global redis_client
    redis_client = aioredis.from_url("redis://redis:6379", decode_responses=True)
    logger.info("Aggregator started")

async def aggregate_results():
    """Aggregate job results"""
    while True:
        try:
            # Check for completed jobs
            job_keys = await redis_client.keys("job:*:info")
            
            for key in job_keys:
                job_data = await redis_client.hgetall(key)
                if job_data and job_data.get("status") == "completed":
                    job_id = key.split(":")[1]
                    
                    # Process result (placeholder)
                    logger.info(f"Aggregating results for job {job_id}")
                    
                    # Update metrics
                    await redis_client.incr("metrics:jobs_completed")
                    
                    # Mark as aggregated
                    await redis_client.hset(key, "status", "aggregated")
            
            await asyncio.sleep(5)
        except Exception as e:
            logger.error(f"Error aggregating results: {e}")
            await asyncio.sleep(5)

@app.on_event("startup")
async def on_startup():
    await startup()
    asyncio.create_task(aggregate_results())

@app.get("/health")
async def health():
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8002)
EOF
                ;;
            "node"|"node-2")
                cat > "services/$service/main.py" << 'EOF'
# services/node/main.py
import asyncio
import json
import logging
import time
import uuid
import random
import redis.asyncio as aioredis
from fastapi import FastAPI
import uvicorn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SynapseGrid Node")

redis_client = None
node_id = f"node_{uuid.uuid4().hex[:8]}"
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

async def startup():
    global redis_client
    redis_client = aioredis.from_url("redis://redis:6379", decode_responses=True)
    
    # Register node
    await redis_client.hset(f"node:{node_id}:info", mapping=node_info)
    await redis_client.incr("metrics:total_nodes")
    
    logger.info(f"Node {node_id} started and registered")

async def send_heartbeat():
    """Send heartbeat to keep node active"""
    while True:
        try:
            await redis_client.hset(f"node:{node_id}:info", "last_heartbeat", str(time.time()))
            await redis_client.expire(f"node:{node_id}:info", 60)  # Expire after 60s if no heartbeat
            await asyncio.sleep(10)
        except Exception as e:
            logger.error(f"Heartbeat error: {e}")
            await asyncio.sleep(10)

async def process_jobs():
    """Process assigned jobs"""
    while True:
        try:
            # Check for assigned jobs
            job_id = await redis_client.rpop(f"node:{node_id}:jobs")
            if job_id:
                logger.info(f"Processing job {job_id}")
                
                # Update job status
                await redis_client.hset(f"job:{job_id}:info", "status", "running")
                
                # Simulate processing
                for progress in range(0, 101, 20):
                    await redis_client.hset(f"job:{job_id}:info", "progress", progress)
                    await asyncio.sleep(1)
                
                # Complete job
                await redis_client.hset(f"job:{job_id}:info", mapping={
                    "status": "completed",
                    "progress": 100,
                    "completed_at": str(time.time())
                })
                
                # Update node stats
                jobs_completed = int(node_info.get("jobs_completed", 0)) + 1
                node_info["jobs_completed"] = jobs_completed
                await redis_client.hset(f"node:{node_id}:info", "jobs_completed", jobs_completed)
                
                logger.info(f"Completed job {job_id}")
            
            # Update load
            load = random.uniform(0.1, 0.9)
            node_info["load"] = load
            await redis_client.hset(f"node:{node_id}:info", "load", load)
            
            await asyncio.sleep(2)
        except Exception as e:
            logger.error(f"Job processing error: {e}")
            await asyncio.sleep(2)

@app.on_event("startup")
async def on_startup():
    await startup()
    asyncio.create_task(send_heartbeat())
    asyncio.create_task(process_jobs())

@app.on_event("shutdown")
async def on_shutdown():
    # Unregister node
    await redis_client.delete(f"node:{node_id}:info")
    await redis_client.decr("metrics:total_nodes")
    logger.info(f"Node {node_id} shutdown")

@app.get("/health")
async def health():
    return {"status": "healthy", "node_id": node_id}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8003)
EOF
                ;;
        esac
        
        # Créer requirements.txt
        cat > "services/$service/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
redis[hiredis]==5.0.1
EOF

        # Créer Dockerfile
        cat > "services/$service/Dockerfile" << EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE $port
CMD ["python", "main.py"]
EOF
        
        print_status "Service $service créé"
    else
        print_status "Service $service existe déjà"
    fi
}

# Vérifier la structure des services
print_info "Vérification des services..."

check_and_create_service "gateway" 8080
check_and_create_service "dispatcher" 8001
check_and_create_service "aggregator" 8002
check_and_create_service "node" 8003

# Si node-2 existe, le renommer ou le supprimer
if [ -d "services/node-2" ]; then
    print_warning "Service node-2 trouvé - suppression..."
    rm -rf "services/node-2"
fi

# Vérifier le docker-compose.yml
print_info "Vérification du docker-compose.yml..."

# Si node-2 est référencé dans docker-compose.yml, créer un nouveau fichier corrigé
if grep -q "node-2:" docker-compose.yml; then
    print_warning "Référence à node-2 trouvée - création d'un docker-compose.yml corrigé..."
    
    cat > docker-compose.fixed.yml << 'EOF'
# SynapseGrid Docker Compose Configuration

services:
  # === DATA LAYER ===
  redis:
    image: redis:7-alpine
    container_name: synapse_redis
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - synapse_network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

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
      - postgres_data:/var/lib/postgresql/data
      - ./sql:/docker-entrypoint-initdb.d
    networks:
      - synapse_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 5s
      timeout: 3s
      retries: 5

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
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
    networks:
      - synapse_network
    restart: unless-stopped

  dispatcher:
    build: ./services/dispatcher
    container_name: synapse_dispatcher
    ports:
      - "8001:8001"
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - synapse_network
    restart: unless-stopped

  aggregator:
    build: ./services/aggregator
    container_name: synapse_aggregator
    ports:
      - "8002:8002"
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - synapse_network
    restart: unless-stopped

  node:
    build: ./services/node
    container_name: synapse_node_1
    ports:
      - "8003:8003"
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - synapse_network
    restart: unless-stopped

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
      - WDS_SOCKET_PORT=0
    command: sh -c "npm install && npm start"
    networks:
      - synapse_network
    depends_on:
      - gateway

  # === MONITORING ===
  prometheus:
    image: prom/prometheus:latest
    container_name: synapse_prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    networks:
      - synapse_network

  grafana:
    image: grafana/grafana:latest
    container_name: synapse_grafana
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning
    networks:
      - synapse_network

networks:
  synapse_network:
    driver: bridge

volumes:
  redis_data:
  postgres_data:
  prometheus_data:
  grafana_data:
EOF
    
    print_status "docker-compose.fixed.yml créé"
    print_info "Utilisez: mv docker-compose.fixed.yml docker-compose.yml"
fi

# Afficher la structure actuelle
echo ""
print_info "Structure actuelle des services:"
echo ""
ls -la services/

echo ""
print_info "Contenu de chaque service:"
for service in gateway dispatcher aggregator node; do
    echo ""
    echo "=== Service: $service ==="
    if [ -d "services/$service" ]; then
        ls -la "services/$service/"
    else
        print_error "Service $service manquant!"
    fi
done

# Instructions finales
echo ""
echo "🎯 Prochaines étapes:"
echo "===================="
echo ""

if [ -f "docker-compose.fixed.yml" ]; then
    echo "1. Remplacer docker-compose.yml:"
    echo "   mv docker-compose.fixed.yml docker-compose.yml"
    echo ""
fi

echo "2. Nettoyer les builds Docker:"
echo "   docker-compose down"
echo "   docker system prune -f"
echo ""
echo "3. Reconstruire:"
echo "   docker-compose build --no-cache"
echo ""
echo "4. Démarrer:"
echo "   docker-compose up -d"
echo ""
echo "5. Vérifier les logs:"
echo "   docker-compose logs -f"
echo ""

print_status "Vérification terminée!"

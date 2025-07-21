#!/bin/bash
# apply_node_fix.sh
# Applique la correction au service node

set -e

echo "🔧 Application de la correction au service node"
echo "============================================="
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

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Étape 1: Arrêter le node
print_info "Arrêt du service node..."
docker-compose stop node

# Étape 2: Sauvegarder l'ancien fichier
print_info "Sauvegarde de l'ancien fichier..."
cp services/node/main.py services/node/main.py.backup_$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# Étape 3: Créer le nouveau fichier corrigé
print_info "Création du fichier corrigé..."

cat > services/node/main.py << 'EOF'
# services/node/main.py - Version corrigée
import asyncio
import json
import logging
import time
import uuid
import random
import os
from contextlib import asynccontextmanager
import redis.asyncio as aioredis
from fastapi import FastAPI
import uvicorn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global variables
redis_client = None
node_id = os.getenv("NODE_ID", f"node_{uuid.uuid4().hex[:8]}")

# Node info avec toutes les valeurs en string
node_info_template = {
    "id": node_id,
    "name": f"Docker Node {node_id}",
    "status": "active",
    "gpu_model": "NVIDIA RTX 3080",
    "cpu_cores": "16",
    "memory_gb": "32",
    "load": "0.0",
    "jobs_completed": "0",
    "capabilities": '["llm", "vision"]',  # JSON string, pas une liste!
    "region": "docker-local",
    "lat": "40.7128",
    "lng": "-74.0060",
    "uptime_hours": "0",
    "last_heartbeat": str(time.time())
}

async def register_node():
    """Register node in Redis"""
    try:
        # S'assurer que toutes les valeurs sont des strings
        node_info = {}
        for key, value in node_info_template.items():
            if isinstance(value, (list, dict)):
                node_info[key] = json.dumps(value)
            else:
                node_info[key] = str(value)
        
        # Store node info
        await redis_client.hset(f"node:{node_id}:info", mapping=node_info)
        
        # Increment total nodes counter
        total_nodes = await redis_client.incr("metrics:total_nodes")
        
        # Set node as active
        await redis_client.setex(f"node:{node_id}:active", 60, "1")
        
        logger.info(f"✅ Node {node_id} registered successfully. Total nodes: {total_nodes}")
        
        # Log what was stored for debugging
        stored_data = await redis_client.hgetall(f"node:{node_id}:info")
        logger.debug(f"Stored node data: {stored_data}")
        
    except Exception as e:
        logger.error(f"❌ Failed to register node: {e}")
        logger.error(f"Error type: {type(e)}")
        logger.error(f"Node info that failed: {node_info_template}")
        raise

async def send_heartbeat():
    """Send heartbeat to keep node active"""
    while True:
        try:
            # Update heartbeat
            await redis_client.hset(f"node:{node_id}:info", "last_heartbeat", str(time.time()))
            
            # Refresh active status
            await redis_client.setex(f"node:{node_id}:active", 60, "1")
            
            # Update load randomly for demo
            load = random.uniform(0.1, 0.9)
            await redis_client.hset(f"node:{node_id}:info", "load", f"{load:.2f}")
            
            # Update uptime
            uptime_hours = await redis_client.hget(f"node:{node_id}:info", "uptime_hours")
            if uptime_hours:
                new_uptime = float(uptime_hours) + (10/3600)  # 10 seconds in hours
                await redis_client.hset(f"node:{node_id}:info", "uptime_hours", f"{new_uptime:.2f}")
            
            logger.debug(f"Heartbeat sent for node {node_id}")
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
                logger.info(f"🔄 Processing job {job_id}")
                
                # Update job status
                await redis_client.hset(f"job:{job_id}:info", "status", "running")
                await redis_client.hset(f"job:{job_id}:info", "node_id", node_id)
                
                # Simulate processing with progress updates
                for progress in range(0, 101, 20):
                    await redis_client.hset(f"job:{job_id}:info", "progress", str(progress))
                    await asyncio.sleep(1)
                
                # Complete job
                await redis_client.hset(f"job:{job_id}:info", mapping={
                    "status": "completed",
                    "progress": "100",
                    "completed_at": str(time.time()),
                    "result": json.dumps({"success": True, "node": node_id})
                })
                
                # Update node stats
                jobs_str = await redis_client.hget(f"node:{node_id}:info", "jobs_completed") or "0"
                jobs_completed = int(jobs_str) + 1
                await redis_client.hset(f"node:{node_id}:info", "jobs_completed", str(jobs_completed))
                
                # Decrement active jobs counter
                active_jobs = await redis_client.decr("metrics:active_jobs")
                
                logger.info(f"✅ Completed job {job_id}. Active jobs: {active_jobs}")
            
            await asyncio.sleep(2)
        except Exception as e:
            logger.error(f"Job processing error: {e}")
            await asyncio.sleep(2)

# Lifespan context manager (modern FastAPI approach)
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global redis_client
    
    try:
        # Connect to Redis with retry
        max_retries = 5
        for attempt in range(max_retries):
            try:
                redis_client = aioredis.from_url(
                    "redis://redis:6379",
                    encoding="utf-8",
                    decode_responses=True
                )
                
                # Test connection
                await redis_client.ping()
                logger.info("✅ Connected to Redis successfully")
                break
            except Exception as e:
                if attempt < max_retries - 1:
                    logger.warning(f"Redis connection attempt {attempt + 1} failed, retrying...")
                    await asyncio.sleep(2)
                else:
                    raise Exception(f"Could not connect to Redis after {max_retries} attempts")
        
        # Register node
        await register_node()
        
        # Start background tasks
        heartbeat_task = asyncio.create_task(send_heartbeat())
        job_processor_task = asyncio.create_task(process_jobs())
        
        logger.info(f"🚀 Node {node_id} started successfully")
        
    except Exception as e:
        logger.error(f"❌ Startup failed: {e}")
        raise
    
    yield  # Server is running
    
    # Shutdown
    try:
        logger.info(f"Shutting down node {node_id}...")
        
        # Cancel background tasks
        heartbeat_task.cancel()
        job_processor_task.cancel()
        
        # Wait for tasks to complete
        await asyncio.gather(heartbeat_task, job_processor_task, return_exceptions=True)
        
        # Unregister node
        if redis_client:
            try:
                await redis_client.delete(f"node:{node_id}:info")
                await redis_client.delete(f"node:{node_id}:active")
                total_nodes = await redis_client.decr("metrics:total_nodes")
                logger.info(f"✅ Node {node_id} unregistered. Remaining nodes: {total_nodes}")
            except Exception as e:
                logger.error(f"Error during unregistration: {e}")
            
            # Close Redis connection
            await redis_client.close()
            
    except Exception as e:
        logger.error(f"Shutdown error: {e}")

# Create FastAPI app with lifespan
app = FastAPI(
    title="SynapseGrid Node",
    version="2.0.0",
    lifespan=lifespan
)

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "node_id": node_id,
        "service": "node",
        "timestamp": time.time()
    }

@app.get("/status")
async def status():
    """Detailed status endpoint"""
    try:
        if redis_client:
            node_data = await redis_client.hgetall(f"node:{node_id}:info")
            return {
                "node_id": node_id,
                "info": node_data,
                "redis_connected": True,
                "uptime_seconds": time.time() - float(node_info_template["last_heartbeat"])
            }
        else:
            return {
                "node_id": node_id,
                "info": node_info_template,
                "redis_connected": False,
                "error": "Redis not connected"
            }
    except Exception as e:
        return {
            "node_id": node_id,
            "error": str(e),
            "redis_connected": False
        }

@app.get("/capabilities")
async def capabilities():
    """Get node capabilities"""
    return {
        "node_id": node_id,
        "capabilities": json.loads(node_info_template["capabilities"]),
        "gpu_model": node_info_template["gpu_model"],
        "cpu_cores": int(node_info_template["cpu_cores"]),
        "memory_gb": int(node_info_template["memory_gb"])
    }

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8003,
        reload=False,
        log_level="info"
    )
EOF

print_status "Fichier main.py créé"

# Étape 4: Vérifier le fichier
print_info "Vérification du fichier..."
if grep -q "lifespan" services/node/main.py && grep -q "json.dumps" services/node/main.py; then
    print_status "Le fichier contient les corrections nécessaires"
else
    print_error "Le fichier ne semble pas contenir toutes les corrections"
fi

# Étape 5: Reconstruire l'image Docker
print_info "Reconstruction de l'image Docker..."
docker-compose build --no-cache node

# Étape 6: Redémarrer le service
print_info "Redémarrage du service node..."
docker-compose up -d node

# Étape 7: Attendre un peu
print_info "Attente du démarrage (5 secondes)..."
sleep 5

# Étape 8: Vérifier les logs
print_info "Vérification des logs..."
echo ""
echo "=== Derniers logs du node ==="
docker-compose logs --tail=30 node | grep -E "(ERROR|WARNING|INFO|Failed|Successfully|✅|❌)" || true

# Étape 9: Tester la santé
print_info "Test de santé du node..."
echo ""
if curl -s http://localhost:8003/health > /dev/null 2>&1; then
    print_status "Le node répond correctement"
    echo "Réponse health:"
    curl -s http://localhost:8003/health | jq .
else
    print_error "Le node ne répond pas"
fi

# Étape 10: Vérifier les métriques
print_info "Vérification des métriques..."
echo ""
echo "Métriques actuelles:"
curl -s http://localhost:8080/metrics | jq . || echo "Gateway non accessible"

echo ""
print_status "Correction appliquée!"
echo ""
echo "🎯 Pour surveiller les logs en temps réel:"
echo "   docker-compose logs -f node"
echo ""
echo "📊 Pour vérifier le statut du node:"
echo "   curl http://localhost:8003/status | jq ."
echo ""
echo "Si le problème persiste, vérifiez:"
echo "1. Que Docker a bien reconstruit l'image: docker images | grep node"
echo "2. Les logs complets: docker-compose logs node"
echo "3. L'état de Redis: docker exec synapse_redis redis-cli KEYS 'node:*'"

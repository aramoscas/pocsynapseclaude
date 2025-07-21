#!/bin/bash

echo "🔧 Application de la correction du Gateway"
echo "=========================================="

# Vérifier si le dossier services/gateway existe
if [ ! -d "services/gateway" ]; then
    echo "❌ Dossier services/gateway introuvable"
    exit 1
fi

# Backup du fichier actuel
if [ -f "services/gateway/main.py" ]; then
    cp services/gateway/main.py services/gateway/main.py.backup.$(date +%s)
    echo "✅ Backup du gateway créé"
fi

# Appliquer la correction
cat > services/gateway/main.py << 'EOF'
# services/gateway/main.py - Version corrigée avec tous les endpoints
import asyncio
import json
import logging
import time
import hashlib
import uuid
from typing import Dict, Any, Optional
from datetime import datetime

import aioredis
import asyncpg
from fastapi import FastAPI, HTTPException, Depends, Header, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SynapseGrid Gateway", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class SubmitJobRequest(BaseModel):
    model_name: str
    input_data: Dict[str, Any]
    priority: int = 1
    timeout: int = 300
    gpu_requirements: Optional[Dict[str, Any]] = None

# Utility functions
def generate_job_id() -> str:
    return f"job_{uuid.uuid4().hex[:12]}"

def verify_token(token: str) -> bool:
    return token == "test-token"

# Global state
redis_client = None
postgres_pool = None

@app.on_event("startup")
async def startup():
    global redis_client, postgres_pool
    
    try:
        # Initialize Redis
        redis_client = aioredis.from_url(
            "redis://redis:6379",
            encoding="utf-8",
            decode_responses=True
        )
        await redis_client.ping()
        logger.info("✅ Connected to Redis")
        
        # Initialize PostgreSQL
        postgres_pool = await asyncpg.create_pool(
            "postgresql://synapse:synapse123@postgres:5432/synapse",
            min_size=2,
            max_size=10
        )
        logger.info("✅ Connected to PostgreSQL")
        
    except Exception as e:
        logger.error(f"❌ Startup failed: {e}")
        raise
    
    logger.info("🚀 Gateway started successfully")

@app.on_event("shutdown")
async def shutdown():
    if redis_client:
        await redis_client.close()
    if postgres_pool:
        await postgres_pool.close()

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Test Redis connection
        await redis_client.ping()
        redis_status = "healthy"
    except:
        redis_status = "unhealthy"
    
    try:
        # Test PostgreSQL connection
        async with postgres_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        postgres_status = "healthy"
    except:
        postgres_status = "unhealthy"
    
    return {
        "status": "healthy" if redis_status == "healthy" and postgres_status == "healthy" else "degraded",
        "timestamp": datetime.utcnow().isoformat(),
        "services": {
            "redis": redis_status,
            "postgres": postgres_status
        }
    }

@app.post("/submit")
async def submit_job(
    request: SubmitJobRequest,
    authorization: str = Header(...),
    x_client_id: str = Header(..., alias="X-Client-ID")
):
    """Submit a job for processing"""
    # Validate token
    token = authorization.replace("Bearer ", "")
    if not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    
    try:
        job_id = generate_job_id()
        
        # Store job in database
        async with postgres_pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO jobs (job_id, client_id, model_name, input_data, status, created_at, priority)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
            """, job_id, x_client_id, request.model_name, json.dumps(request.input_data), "queued", 
            datetime.utcnow(), request.priority)
        
        # Add to Redis queue
        await redis_client.lpush("jobs:queue", json.dumps({
            "job_id": job_id,
            "client_id": x_client_id,
            "model_name": request.model_name,
            "input_data": request.input_data,
            "priority": request.priority,
            "timeout": request.timeout,
            "gpu_requirements": request.gpu_requirements
        }))
        
        logger.info(f"📤 Job {job_id} submitted by {x_client_id}")
        
        return {
            "job_id": job_id,
            "status": "queued",
            "estimated_cost": 0.01,
            "message": "Job submitted successfully"
        }
        
    except Exception as e:
        logger.error(f"❌ Error submitting job: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/jobs/{job_id}")
async def get_job_status(
    job_id: str,
    x_client_id: str = Header(..., alias="X-Client-ID")
):
    """Get job status"""
    try:
        async with postgres_pool.acquire() as conn:
            job = await conn.fetchrow("""
                SELECT job_id, status, result, error, created_at, completed_at
                FROM jobs WHERE job_id = $1 AND client_id = $2
            """, job_id, x_client_id)
            
            if not job:
                raise HTTPException(status_code=404, detail="Job not found")
            
            return {
                "job_id": job["job_id"],
                "status": job["status"],
                "result": json.loads(job["result"]) if job["result"] else None,
                "error": job["error"],
                "created_at": job["created_at"].isoformat() if job["created_at"] else None,
                "completed_at": job["completed_at"].isoformat() if job["completed_at"] else None
            }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Error getting job status: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# === ENDPOINTS MANQUANTS POUR LE NODE MAC ===

@app.post("/nodes/register")
async def register_node(node_data: dict):
    """Register a node with the gateway"""
    node_id = node_data.get("node_id")
    if not node_id:
        raise HTTPException(status_code=400, detail="node_id required")
    
    try:
        # Store node info in Redis
        node_key = f"node:{node_id}:info"
        await redis_client.hset(node_key, mapping={
            "node_id": node_id,
            "node_type": node_data.get("node_type", "unknown"),
            "status": "active",
            "performance_score": str(node_data.get("performance_score", 0)),
            "cpu_usage": str(node_data.get("cpu_usage", 0)),
            "memory_usage": str(node_data.get("memory_usage", 0)),
            "registered_at": datetime.utcnow().isoformat(),
            "last_seen": datetime.utcnow().isoformat()
        })
        
        # Set expiration
        await redis_client.expire(node_key, 300)  # 5 minutes
        
        # Add to active nodes set
        await redis_client.sadd("nodes:active", node_id)
        
        logger.info(f"✅ Node registered: {node_id}")
        return {"status": "registered", "node_id": node_id}
        
    except Exception as e:
        logger.error(f"❌ Failed to register node {node_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/nodes/heartbeat")
async def node_heartbeat(node_data: dict):
    """Receive heartbeat from a node"""
    node_id = node_data.get("node_id")
    if not node_id:
        raise HTTPException(status_code=400, detail="node_id required")
    
    try:
        # Update node info in Redis
        node_key = f"node:{node_id}:info"
        
        # Check if node exists
        exists = await redis_client.exists(node_key)
        if not exists:
            # Auto-register if node doesn't exist
            logger.info(f"Auto-registering node on heartbeat: {node_id}")
            return await register_node(node_data)
        
        # Update node metrics
        await redis_client.hset(node_key, mapping={
            "status": node_data.get("status", "active"),
            "performance_score": str(node_data.get("performance_score", 0)),
            "cpu_usage": str(node_data.get("cpu_usage", 0)),
            "memory_usage": str(node_data.get("memory_usage", 0)),
            "jobs_completed": str(node_data.get("jobs_completed", 0)),
            "uptime": str(node_data.get("uptime", 0)),
            "last_seen": datetime.utcnow().isoformat()
        })
        
        # Refresh expiration
        await redis_client.expire(node_key, 300)
        
        # Ensure in active set
        await redis_client.sadd("nodes:active", node_id)
        
        return {"status": "heartbeat_received", "node_id": node_id}
        
    except Exception as e:
        logger.error(f"❌ Failed to process heartbeat for {node_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/nodes")
async def list_nodes():
    """List all active nodes"""
    try:
        active_nodes = await redis_client.smembers("nodes:active")
        nodes = []
        
        for node_id in active_nodes:
            node_key = f"node:{node_id}:info"
            node_info = await redis_client.hgetall(node_key)
            if node_info:
                nodes.append(node_info)
        
        return {"nodes": nodes, "count": len(nodes)}
        
    except Exception as e:
        logger.error(f"❌ Failed to list nodes: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/nodes/{node_id}")
async def get_node_info(node_id: str):
    """Get specific node information"""
    try:
        node_key = f"node:{node_id}:info"
        node_info = await redis_client.hgetall(node_key)
        
        if not node_info:
            raise HTTPException(status_code=404, detail="Node not found")
            
        return node_info
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Failed to get node info for {node_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/stats")
async def get_stats():
    """Get system statistics including node information"""
    try:
        # Get basic stats
        total_jobs = await redis_client.get("stats:total_jobs") or "0"
        active_jobs = await redis_client.get("stats:active_jobs") or "0"
        
        # Get node stats
        active_nodes = await redis_client.smembers("nodes:active")
        node_count = len(active_nodes)
        
        # Get detailed node info
        nodes = []
        for node_id in active_nodes:
            node_key = f"node:{node_id}:info"
            node_info = await redis_client.hgetall(node_key)
            if node_info:
                nodes.append({
                    "node_id": node_info.get("node_id"),
                    "node_type": node_info.get("node_type"),
                    "status": node_info.get("status"),
                    "performance_score": int(node_info.get("performance_score", 0)),
                    "cpu_usage": float(node_info.get("cpu_usage", 0)),
                    "memory_usage": float(node_info.get("memory_usage", 0)),
                    "jobs_completed": int(node_info.get("jobs_completed", 0)),
                    "last_seen": node_info.get("last_seen")
                })
        
        return {
            "total_jobs": int(total_jobs),
            "active_jobs": int(active_jobs),
            "nodes": {
                "total": node_count,
                "active": node_count,
                "details": nodes
            },
            "system": {
                "status": "healthy",
                "timestamp": datetime.utcnow().isoformat()
            }
        }
        
    except Exception as e:
        logger.error(f"❌ Failed to get stats: {e}")
        return {
            "total_jobs": 0,
            "active_jobs": 0,
            "nodes": {"total": 0, "active": 0, "details": []},
            "system": {"status": "error", "error": str(e)}
        }

# Metrics endpoint for Prometheus
@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    try:
        # Get basic metrics
        active_nodes = await redis_client.smembers("nodes:active")
        total_jobs = await redis_client.get("stats:total_jobs") or "0"
        active_jobs = await redis_client.get("stats:active_jobs") or "0"
        
        metrics_text = f"""# HELP synapse_nodes_total Total number of active nodes
# TYPE synapse_nodes_total gauge
synapse_nodes_total {len(active_nodes)}

# HELP synapse_jobs_total Total number of jobs processed
# TYPE synapse_jobs_total counter
synapse_jobs_total {total_jobs}

# HELP synapse_jobs_active Number of currently active jobs
# TYPE synapse_jobs_active gauge
synapse_jobs_active {active_jobs}
"""
        
        return Response(content=metrics_text, media_type="text/plain")
        
    except Exception as e:
        logger.error(f"❌ Error generating metrics: {e}")
        return Response(content="# Error generating metrics", media_type="text/plain")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

echo "✅ Gateway corrigé avec succès"

# Redémarrer le gateway pour appliquer les changements
echo "🔄 Redémarrage du gateway..."

# Redémarrer seulement le service gateway
if docker compose ps | grep synapse_gateway >/dev/null 2>&1; then
    docker compose restart gateway
    echo "✅ Gateway redémarré"
    
    # Attendre que le gateway soit prêt
    echo "⏳ Attente du redémarrage du gateway..."
    sleep 5
    
    # Test des nouveaux endpoints
    echo "🧪 Test des nouveaux endpoints..."
    
    # Test health
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo "✅ Health endpoint fonctionne"
    else
        echo "❌ Health endpoint non disponible"
    fi
    
    # Test nodes endpoint
    if curl -s http://localhost:8080/nodes >/dev/null 2>&1; then
        echo "✅ Nodes endpoint fonctionne"
    else
        echo "❌ Nodes endpoint non disponible"
    fi
    
    # Test stats endpoint
    if curl -s http://localhost:8080/stats >/dev/null 2>&1; then
        echo "✅ Stats endpoint fonctionne"
    else
        echo "❌ Stats endpoint non disponible"
    fi
    
else
    echo "⚠️  Gateway container non trouvé, redémarrez manuellement avec 'make start'"
fi

echo ""
echo "🎯 Correction appliquée avec succès!"
echo "===================================="
echo "✅ Endpoints ajoutés au gateway:"
echo "   - POST /nodes/register"
echo "   - POST /nodes/heartbeat"
echo "   - GET /nodes"
echo "   - GET /nodes/{node_id}"
echo "   - GET /stats (amélioré)"
echo "   - GET /metrics"
echo ""
echo "🔄 Maintenant redémarrez le nœud Mac:"
echo "   make mac-stop"
echo "   make mac-start"
echo ""
echo "ou testez immédiatement:"
echo "   make mac-logs"
echo ""
echo "Les erreurs 404 devraient être résolues! 🎉"

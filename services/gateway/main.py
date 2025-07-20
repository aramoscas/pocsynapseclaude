# services/gateway/main.py - Self-contained version
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
from fastapi import FastAPI, HTTPException, Depends, Header
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

# Utility functions (inline instead of shared import)
def generate_job_id() -> str:
    return f"job_{uuid.uuid4().hex[:12]}"

def verify_token(token: str) -> bool:
    # Simplified token verification
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
    logger.info("Gateway shutdown complete")

@app.get("/health")
async def health_check():
    try:
        # Check Redis
        await redis_client.ping()
        
        # Check PostgreSQL
        async with postgres_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        
        return {
            "status": "healthy", 
            "timestamp": datetime.utcnow().isoformat(),
            "services": {
                "redis": "healthy",
                "postgres": "healthy"
            }
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Health check failed: {str(e)}")

@app.post("/submit")
async def submit_job(
    request: SubmitJobRequest,
    authorization: str = Header(...),
    x_client_id: str = Header(..., alias="X-Client-ID")
):
    # Verify token
    token = authorization.replace("Bearer ", "")
    if not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    
    # Generate job
    job_id = generate_job_id()
    
    job_data = {
        "job_id": job_id,
        "client_id": x_client_id,
        "model_name": request.model_name,
        "input_data": request.input_data,
        "priority": request.priority,
        "timeout": request.timeout,
        "gpu_requirements": request.gpu_requirements or {},
        "created_at": datetime.utcnow().isoformat(),
        "status": "queued"
    }
    
    try:
        # Push to queue
        await redis_client.lpush("jobs:queue:eu-west-1", json.dumps(job_data))
        
        # Store in database
        async with postgres_pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO jobs (job_id, client_id, model_name, input_data, 
                                status, created_at, estimated_cost, priority)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """, 
            job_id, x_client_id, request.model_name, 
            json.dumps(request.input_data), "queued", 
            datetime.utcnow(), 0.01, request.priority)
        
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

@app.post("/nodes/register")
async def register_node(node_data: dict):
    node_id = node_data.get("node_id")
    node_type = node_data.get("node_type", "docker")
    
    if not node_id:
        raise HTTPException(status_code=400, detail="node_id required")
    
    try:
        # Register in Redis
        node_key = f"node:{node_id}:local:info"
        await redis_client.hmset(node_key, {
            "node_id": node_id,
            "node_type": node_type,
            "status": "available",
            "last_seen": datetime.utcnow().isoformat()
        })
        await redis_client.expire(node_key, 60)
        
        if node_type == "mac_m2_native":
            await redis_client.sadd("native_nodes", node_id)
        
        logger.info(f"✅ Registered {node_type} node: {node_id}")
        
        return {"status": "registered", "node_id": node_id, "node_type": node_type}
        
    except Exception as e:
        logger.error(f"❌ Registration error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/jobs/submit/native")
async def submit_native_job(
    request: SubmitJobRequest,
    authorization: str = Header(...),
    x_client_id: str = Header(..., alias="X-Client-ID")
):
    # Verify token
    token = authorization.replace("Bearer ", "")
    if not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    
    # Check native nodes available
    try:
        native_nodes = await redis_client.smembers("native_nodes")
        if not native_nodes:
            raise HTTPException(status_code=503, detail="No native nodes available")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error checking native nodes: {e}")
    
    job_id = generate_job_id()
    
    job_data = {
        "job_id": job_id,
        "client_id": x_client_id,
        "model_name": request.model_name,
        "input_data": request.input_data,
        "priority": request.priority,
        "timeout": request.timeout,
        "gpu_requirements": request.gpu_requirements or {},
        "created_at": datetime.utcnow().isoformat(),
        "status": "queued",
        "target_node_type": "native"
    }
    
    try:
        await redis_client.lpush("jobs:queue:native", json.dumps(job_data))
        
        logger.info(f"📤 Native job {job_id} submitted by {x_client_id}")
        
        return {
            "job_id": job_id,
            "status": "queued",
            "target_type": "native",
            "estimated_cost": 0.15,
            "message": "Job submitted to native queue"
        }
        
    except Exception as e:
        logger.error(f"❌ Error submitting native job: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/nodes")
async def list_nodes():
    try:
        node_keys = await redis_client.keys("node:*:*:info")
        nodes = []
        
        for key in node_keys:
            node_data = await redis_client.hgetall(key)
            if node_data:
                nodes.append({
                    "node_id": node_data.get("node_id"),
                    "node_type": node_data.get("node_type", "docker"),
                    "status": node_data.get("status"),
                    "last_seen": node_data.get("last_seen")
                })
        
        return nodes
        
    except Exception as e:
        logger.error(f"❌ Error listing nodes: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/nodes/native")
async def list_native_nodes():
    try:
        native_node_ids = await redis_client.smembers("native_nodes")
        nodes = []
        
        for node_id in native_node_ids:
            node_keys = await redis_client.keys(f"node:{node_id}:*:info")
            if node_keys:
                node_data = await redis_client.hgetall(node_keys[0])
                if node_data:
                    nodes.append({
                        "node_id": node_data.get("node_id"),
                        "node_type": node_data.get("node_type"),
                        "status": node_data.get("status"),
                        "last_seen": node_data.get("last_seen")
                    })
        
        return {"native_nodes": nodes, "count": len(nodes)}
        
    except Exception as e:
        logger.error(f"❌ Error listing native nodes: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=True, log_level="info")

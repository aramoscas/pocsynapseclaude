#!/usr/bin/env python3
"""Gateway service amélioré pour SynapseGrid"""

import os
import json
import asyncio
import aioredis
import asyncpg
from fastapi import FastAPI, HTTPException, Header, Request
from pydantic import BaseModel
from datetime import datetime
import hashlib
import uuid
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SynapseGrid Gateway")

# Global connections
redis_pool = None
db_pool = None

class JobSubmission(BaseModel):
    model_name: str
    input_data: dict
    priority: int = 1
    gpu_requirements: dict = {}

@app.on_event("startup")
async def startup():
    global redis_pool, db_pool
    
    # Redis connection
    redis_pool = await aioredis.create_redis_pool(
        'redis://redis:6379',
        encoding='utf-8'
    )
    logger.info("✅ Connected to Redis")
    
    # PostgreSQL connection
    db_pool = await asyncpg.create_pool(
        host='postgres',
        port=5432,
        user='synapse',
        password='synapse123',
        database='synapse',
        min_size=10,
        max_size=20
    )
    logger.info("✅ Connected to PostgreSQL")

@app.on_event("shutdown")
async def shutdown():
    redis_pool.close()
    await redis_pool.wait_closed()
    await db_pool.close()

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "gateway"}

@app.post("/submit")
async def submit_job(
    job: JobSubmission,
    authorization: str = Header(None),
    x_client_id: str = Header(None)
):
    """Submit a new job to the system"""
    
    # Validate authorization
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization")
    
    token = authorization.replace("Bearer ", "")
    client_id = x_client_id or "anonymous"
    
    # Verify client exists
    async with db_pool.acquire() as conn:
        client = await conn.fetchrow(
            "SELECT client_id, nrg_balance FROM clients WHERE client_id = $1",
            client_id
        )
        
        if not client:
            # Create client if not exists
            await conn.execute(
                """INSERT INTO clients (client_id, api_key_hash, nrg_balance) 
                   VALUES ($1, $2, 100.0) ON CONFLICT DO NOTHING""",
                client_id, hashlib.sha256(token.encode()).hexdigest()
            )
            nrg_balance = 100.0
        else:
            nrg_balance = float(client['nrg_balance'])
        
        # Check balance
        if nrg_balance < job.priority * 0.01:
            raise HTTPException(status_code=402, detail="Insufficient NRG balance")
        
        # Create job
        job_id = f"job_{int(datetime.utcnow().timestamp() * 1000)}_{uuid.uuid4().hex[:8]}"
        
        # Insert into PostgreSQL
        await conn.execute("""
            INSERT INTO jobs (
                job_id, client_id, model_name, input_data, 
                status, priority, estimated_cost, gpu_requirements,
                region_preference
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        """, job_id, client_id, job.model_name, json.dumps(job.input_data),
            'pending', job.priority, job.priority * 0.01, json.dumps(job.gpu_requirements),
            'eu-west-1'
        )
        
        # Add to Redis queue
        job_data = {
            'job_id': job_id,
            'client_id': client_id,
            'model_name': job.model_name,
            'input_data': job.input_data,
            'priority': job.priority,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        await redis_pool.lpush('jobs:queue:eu-west-1', json.dumps(job_data))
        
        # Publish event
        await redis_pool.publish('jobs:new', job_id)
        
        logger.info(f"✅ Job {job_id} submitted by {client_id}")
        
    return {
        "job_id": job_id,
        "status": "pending",
        "estimated_cost": job.priority * 0.01,
        "message": "Job submitted successfully",
        "submitted_at": datetime.utcnow().isoformat()
    }

@app.get("/job/{job_id}/status")
async def get_job_status(job_id: str):
    """Get job status"""
    async with db_pool.acquire() as conn:
        job = await conn.fetchrow("""
            SELECT job_id, status, assigned_node, created_at, 
                   started_at, completed_at, error_message
            FROM jobs WHERE job_id = $1
        """, job_id)
        
        if not job:
            raise HTTPException(status_code=404, detail="Job not found")
        
        return dict(job)

@app.get("/nodes")
async def get_nodes():
    """Get list of active nodes"""
    nodes = []
    node_ids = await redis_pool.smembers('nodes:registered')
    
    for node_id in node_ids:
        node_info = await redis_pool.get(f'node:{node_id}:info')
        if node_info:
            nodes.append(json.loads(node_info))
    
    return nodes

@app.get("/metrics")
async def get_metrics():
    """Get system metrics"""
    async with db_pool.acquire() as conn:
        metrics = await conn.fetchrow("""
            SELECT 
                COUNT(*) FILTER (WHERE status = 'pending') as pending_jobs,
                COUNT(*) FILTER (WHERE status = 'processing') as processing_jobs,
                COUNT(*) FILTER (WHERE status = 'completed') as completed_jobs,
                COUNT(DISTINCT assigned_node) as active_nodes
            FROM jobs
            WHERE created_at > NOW() - INTERVAL '1 hour'
        """)
        
    queue_length = await redis_pool.llen('jobs:queue:eu-west-1')
    
    return {
        "pending_jobs": metrics['pending_jobs'],
        "processing_jobs": metrics['processing_jobs'],
        "completed_jobs": metrics['completed_jobs'],
        "active_nodes": metrics['active_nodes'],
        "queue_length": queue_length
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)

#!/usr/bin/env python3
"""Gateway Service - Entry point for job submissions"""

import os
import sys
import asyncio
import json
import time
from datetime import datetime
from typing import Dict, Any, Optional

import redis.asyncio as redis
import uvicorn
from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import structlog
from prometheus_client import Counter, Histogram, generate_latest
from fastapi.responses import Response

# Add shared module to path
# Path already set by PYTHONPATH env variable
from shared.utils import get_redis_client, get_postgres_engine
from shared.models import Job, JobStatus

# Configure structured logging
logger = structlog.get_logger()

# Metrics
job_counter = Counter('gateway_jobs_received', 'Total jobs received')
job_latency = Histogram('gateway_job_processing_seconds', 'Job processing latency')
auth_failures = Counter('gateway_auth_failures', 'Authentication failures')

app = FastAPI(title="SynapseGrid Gateway", version="0.1.0")

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Redis client
redis_client = None

class JobSubmission(BaseModel):
    model_name: str
    input_data: Dict[str, Any]
    priority: int = 1
    client_id: Optional[str] = None

class JobResponse(BaseModel):
    job_id: str
    status: str
    submitted_at: str
    estimated_completion: Optional[str] = None

@app.on_event("startup")
async def startup_event():
    """Initialize connections on startup"""
    global redis_client
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
    redis_client = await redis.from_url(redis_url, decode_responses=True)
    logger.info("Gateway started", redis_url=redis_url)

@app.on_event("shutdown")
async def shutdown_event():
    """Clean up connections"""
    if redis_client:
        await redis_client.close()
    logger.info("Gateway shutdown")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        await redis_client.ping()
        return {"status": "healthy", "service": "gateway"}
    except Exception as e:
        logger.error("Health check failed", error=str(e))
        raise HTTPException(status_code=503, detail="Service unhealthy")

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(content=generate_latest(), media_type="text/plain")

async def verify_token(token: str) -> bool:
    """Verify client token (simplified for MVP)"""
    # In production, verify JWT and check $NRG balance
    if not token or token == "Bearer ":
        return False
    
    # Check cached balance in Redis
    try:
        # For MVP, just check if token exists
        cached = await redis_client.get(f"token:{token}")
        if cached:
            return True
        
        # In production, verify with blockchain
        # For now, accept any non-empty token
        await redis_client.setex(f"token:{token}", 300, "valid")
        return True
    except Exception as e:
        logger.error("Token verification failed", error=str(e))
        return False

@app.post("/submit", response_model=JobResponse)
async def submit_job(
    job: JobSubmission,
    authorization: str = Header(None),
    x_client_id: str = Header(None)
):
    """Submit a new job for processing"""
    job_counter.inc()
    
    with job_latency.time():
        # Verify authorization
        if not authorization or not await verify_token(authorization.replace("Bearer ", "")):
            auth_failures.inc()
            raise HTTPException(status_code=401, detail="Invalid authorization")
        
        # Generate job ID
        job_id = f"job_{int(time.time() * 1000)}_{x_client_id or 'anonymous'}"
        
        # Create job object
        job_data = {
            "job_id": job_id,
            "model_name": job.model_name,
            "input_data": job.input_data,
            "priority": job.priority,
            "client_id": x_client_id or "anonymous",
            "status": JobStatus.PENDING.value,
            "submitted_at": datetime.utcnow().isoformat(),
            "region": os.getenv("REGION", "us-east")
        }
        
        try:
            # Store job in Redis
            await redis_client.hset(f"job:{job_id}", mapping=job_data)
            
            # Add to job queue
            queue_key = f"jobs:queue:{job_data['region']}"
            await redis_client.zadd(queue_key, {job_id: job.priority})
            
            # Publish job event
            await redis_client.publish("job:submitted", json.dumps({
                "job_id": job_id,
                "model_name": job.model_name,
                "region": job_data['region']
            }))
            
            logger.info("Job submitted", 
                       job_id=job_id, 
                       model=job.model_name,
                       client=x_client_id)
            
            return JobResponse(
                job_id=job_id,
                status=JobStatus.PENDING.value,
                submitted_at=job_data['submitted_at'],
                estimated_completion=None
            )
            
        except Exception as e:
            logger.error("Job submission failed", error=str(e), job_id=job_id)
            raise HTTPException(status_code=500, detail="Failed to submit job")

@app.get("/job/{job_id}")
async def get_job_status(job_id: str):
    """Get job status"""
    try:
        job_data = await redis_client.hgetall(f"job:{job_id}")
        if not job_data:
            raise HTTPException(status_code=404, detail="Job not found")
        
        return job_data
    except Exception as e:
        logger.error("Failed to get job status", error=str(e), job_id=job_id)
        raise HTTPException(status_code=500, detail="Failed to get job status")

@app.websocket("/ws")
async def websocket_endpoint(websocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()
    try:
        # Subscribe to job updates
        pubsub = redis_client.pubsub()
        await pubsub.subscribe("job:*")
        
        while True:
            message = await pubsub.get_message(ignore_subscribe_messages=True)
            if message:
                await websocket.send_json({
                    "channel": message['channel'],
                    "data": message['data']
                })
            await asyncio.sleep(0.1)
            
    except Exception as e:
        logger.error("WebSocket error", error=str(e))
    finally:
        await websocket.close()

if __name__ == "__main__":
    port = int(os.getenv("HTTP_PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")

@app.get("/api/stats")
async def get_stats():
    """Get system statistics"""
    try:
        # Get node count
        node_keys = await redis_client.keys("node:*")
        active_nodes = 0
        for key in node_keys:
            node_data = await redis_client.hgetall(key)
            if node_data.get('status') == 'online':
                active_nodes += 1
        
        # Get job statistics
        pending_jobs = await redis_client.zcard("jobs:queue:us-east")
        
        # Get completed jobs count
        completed_jobs = 0
        job_keys = await redis_client.keys("job:*")
        for key in job_keys:
            job_data = await redis_client.hgetall(key)
            if job_data.get('status') == 'completed':
                completed_jobs += 1
        
        return {
            "totalNodes": active_nodes,
            "activeJobs": pending_jobs,
            "completedJobs": completed_jobs,
            "avgLatency": 250,  # TODO: Calculate from real data
            "throughput": 1500,  # TODO: Calculate from real data
        }
    except Exception as e:
        logger.error("Failed to get stats", error=str(e))
        return {"totalNodes": 0, "activeJobs": 0, "completedJobs": 0}

@app.get("/api/nodes")
async def get_nodes():
    """Get list of active nodes"""
    try:
        node_keys = await redis_client.keys("node:*")
        nodes = []
        for key in node_keys:
            node_data = await redis_client.hgetall(key)
            if node_data:
                nodes.append(node_data)
        return nodes
    except Exception as e:
        logger.error("Failed to get nodes", error=str(e))
        return []

@app.get("/api/jobs/queue")
async def get_job_queue():
    """Get jobs in queue"""
    try:
        jobs = await redis_client.zrange("jobs:queue:us-east", 0, -1)
        return {"queue": jobs, "count": len(jobs)}
    except Exception as e:
        logger.error("Failed to get job queue", error=str(e))
        return {"queue": [], "count": 0}

@app.get("/api/stats")
async def get_stats():
    """Get system statistics"""
    try:
        # Get node count
        node_keys = await redis_client.keys("node:*")
        active_nodes = 0
        for key in node_keys:
            node_data = await redis_client.hgetall(key)
            if node_data.get('status') == 'online':
                active_nodes += 1
        
        # Get job statistics
        pending_jobs = await redis_client.zcard("jobs:queue:us-east")
        
        # Get completed jobs count
        completed_jobs = 0
        job_keys = await redis_client.keys("job:*")
        for key in job_keys:
            job_data = await redis_client.hgetall(key)
            if job_data.get('status') == 'completed':
                completed_jobs += 1
        
        return {
            "totalNodes": active_nodes,
            "activeJobs": pending_jobs,
            "completedJobs": completed_jobs,
            "avgLatency": 250,  # TODO: Calculate from real data
            "throughput": 1500,  # TODO: Calculate from real data
        }
    except Exception as e:
        logger.error("Failed to get stats", error=str(e))
        return {"totalNodes": 0, "activeJobs": 0, "completedJobs": 0}

@app.get("/api/nodes")
async def get_nodes():
    """Get list of active nodes"""
    try:
        node_keys = await redis_client.keys("node:*")
        nodes = []
        for key in node_keys:
            node_data = await redis_client.hgetall(key)
            if node_data:
                nodes.append(node_data)
        return nodes
    except Exception as e:
        logger.error("Failed to get nodes", error=str(e))
        return []

@app.get("/api/jobs/queue")
async def get_job_queue():
    """Get jobs in queue"""
    try:
        jobs = await redis_client.zrange("jobs:queue:us-east", 0, -1)
        return {"queue": jobs, "count": len(jobs)}
    except Exception as e:
        logger.error("Failed to get job queue", error=str(e))
        return {"queue": [], "count": 0}

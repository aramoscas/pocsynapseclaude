#!/usr/bin/env python3
import asyncio
import json
import time
import uuid
import os
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import uvicorn
import redis.asyncio as redis

app = FastAPI(title="SynapseGrid Gateway")

class JobRequest(BaseModel):
    model_name: str
    input_data: dict
    priority: int = 1
    timeout_ms: int = 30000
    region: str = None

redis_client = None

@app.on_event("startup")
async def startup():
    global redis_client
    redis_host = os.getenv('REDIS_HOST', 'redis')
    redis_client = redis.Redis(host=redis_host, port=6379, decode_responses=True)
    print(f"✅ Gateway started, Redis: {redis_host}")

@app.get("/health")
async def health_check():
    try:
        await redis_client.ping()
        return {"status": "healthy", "timestamp": time.time(), "redis": "connected"}
    except Exception as e:
        return {"status": "degraded", "timestamp": time.time(), "redis": f"error: {e}"}

@app.post("/submit")
async def submit_job(
    request: JobRequest,
    authorization: str = Header(None),
    x_client_id: str = Header(None)
):
    if not authorization or not x_client_id:
        raise HTTPException(status_code=401, detail="Missing auth headers")
    
    job_id = str(uuid.uuid4())
    
    job_data = {
        "job_id": job_id,
        "client_id": x_client_id,
        "model_name": request.model_name,
        "input_data": request.input_data,
        "priority": request.priority,
        "region": request.region or "local",
        "submitted_at": time.time()
    }
    
    try:
        region = request.region or "local"
        await redis_client.lpush(f"jobs:queue:{region}", json.dumps(job_data))
        print(f"✅ Job {job_id} queued for {region}")
    except Exception as e:
        print(f"❌ Error queuing job: {e}")
        raise HTTPException(status_code=500, detail="Failed to queue job")
    
    return {
        "job_id": job_id,
        "status": "queued",
        "region": request.region or "local",
        "estimated_wait_ms": 1500
    }

@app.get("/job/{job_id}")
async def get_job_status(job_id: str):
    return {
        "job_id": job_id,
        "status": "completed",
        "result": {"mock": "result", "processing_time": 450},
        "created_at": time.time() - 10,
        "completed_at": time.time()
    }

@app.get("/stats")
async def get_stats():
    try:
        local_queue = await redis_client.llen("jobs:queue:local") or 0
        active_nodes = await redis_client.scard("nodes:active:local") or 0
        
        return {
            "regions": {
                "local": {"queued_jobs": local_queue, "active_nodes": active_nodes}
            },
            "total_jobs_today": 150,
            "avg_latency_ms": 450
        }
    except Exception as e:
        return {
            "regions": {"local": {"queued_jobs": 0, "active_nodes": 0}},
            "total_jobs_today": 0,
            "avg_latency_ms": 0,
            "error": str(e)
        }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)

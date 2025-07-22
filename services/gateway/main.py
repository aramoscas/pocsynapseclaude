# services/gateway/main_fixed.py - Version avec meilleure gestion PostgreSQL
import asyncio
import json
import logging
import time
import uuid
from typing import Dict, Any, Optional, Set
import datetime
from contextlib import asynccontextmanager

import redis.asyncio as aioredis
import asyncpg
from fastapi import FastAPI, HTTPException, Depends, Header, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict
import uvicorn

def safe_datetime_format(dt):
    """Formate un datetime en string de façon sécurisée"""
    if isinstance(dt, str):
        return dt
    if hasattr(dt, 'isoformat'):
        return dt.isoformat()
    return str(dt)
# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global state
redis_client = None
postgres_pool = None
websocket_clients: Set[WebSocket] = set()

# Pydantic models avec ConfigDict pour éviter le warning
class SubmitJobRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    
    model_name: str
    input_data: Dict[str, Any]
    priority: int = 1
    timeout: int = 300
    gpu_requirements: Optional[Dict[str, Any]] = None

class JobResponse(BaseModel):
    job_id: str
    status: str
    message: str
    submitted_at: str

# WebSocket manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: Set[WebSocket] = set()
        self.subscriptions: Dict[WebSocket, Set[str]] = {}

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.add(websocket)
        self.subscriptions[websocket] = set()
        logger.info(f"WebSocket client connected. Total connections: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        self.active_connections.discard(websocket)
        self.subscriptions.pop(websocket, None)
        logger.info(f"WebSocket client disconnected. Total connections: {len(self.active_connections)}")

    async def subscribe(self, websocket: WebSocket, channels: list):
        self.subscriptions[websocket].update(channels)
        logger.info(f"Client subscribed to channels: {channels}")

    async def broadcast(self, message: dict, channel: str = None):
        if self.active_connections:
            message_str = json.dumps(message)
            disconnected = set()
            
            for connection in self.active_connections:
                try:
                    if channel and channel not in self.subscriptions.get(connection, set()):
                        continue
                    await connection.send_text(message_str)
                except Exception as e:
                    logger.error(f"Error sending message: {e}")
                    disconnected.add(connection)
            
            for conn in disconnected:
                self.disconnect(conn)

manager = ConnectionManager()

# Utility functions
def generate_job_id() -> str:
    return f"job_{uuid.uuid4().hex[:12]}"

def verify_token(token: str) -> bool:
    return token == "test-token"

# Lifespan context manager avec retry pour PostgreSQL
@asynccontextmanager
async def lifespan(app: FastAPI):
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
        
        # Initialize PostgreSQL avec retry
        postgres_connected = False
        for attempt in range(5):
            try:
                postgres_pool = await asyncpg.create_pool(
                    "postgresql://synapse:synapse123@postgres:5432/synapse",
                    min_size=2,
                    max_size=10,
                    timeout=10,
                    command_timeout=10
                )
                logger.info("✅ Connected to PostgreSQL")
                postgres_connected = True
                break
            except Exception as e:
                logger.warning(f"PostgreSQL connection attempt {attempt + 1} failed: {e}")
                if attempt < 4:
                    await asyncio.sleep(5)
                else:
                    logger.error("❌ Could not connect to PostgreSQL after 5 attempts")
                    # Continue sans PostgreSQL
        
        # Start background tasks
        asyncio.create_task(metrics_updater())
        
    except Exception as e:
        logger.error(f"❌ Startup failed: {e}")
        # Continue quand même sans certains services
    
    logger.info("🚀 Gateway started successfully")
    
    yield
    
    # Shutdown
    if redis_client:
        await redis_client.close()
    if postgres_pool:
        await postgres_pool.close()
    logger.info("Gateway shutdown complete")

# Create FastAPI app
app = FastAPI(
    title="SynapseGrid Gateway",
    version="2.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Background task pour mettre à jour les métriques
async def metrics_updater():
    while True:
        try:
            await asyncio.sleep(5)
            
            if not redis_client:
                continue
                
            # Compter les nodes actifs
            node_keys = await redis_client.keys("node:*:info")
            if node_keys:
                await redis_client.set("metrics:total_nodes", len(node_keys))
            
            # Broadcast metrics
            metrics = await get_current_metrics()
            await manager.broadcast({
                "type": "metrics_update",
                "payload": metrics
            }, channel="metrics")
            
        except Exception as e:
            logger.error(f"Error in metrics updater: {e}")

async def get_current_metrics():
    """Helper pour obtenir les métriques actuelles"""
    try:
        if not redis_client:
            return {"totalNodes": 0, "activeJobs": 0, "avgLatency": 0, "throughput": 0}
            
        # Compter directement si les métriques n'existent pas
        total_nodes = await redis_client.get("metrics:total_nodes")
        if not total_nodes:
            node_keys = await redis_client.keys("node:*:info")
            total_nodes = len(node_keys)
            await redis_client.set("metrics:total_nodes", total_nodes)
        
        active_jobs = await redis_client.get("metrics:active_jobs") or "0"
        avg_latency = await redis_client.get("metrics:avg_latency") or "0"
        throughput = await redis_client.get("metrics:throughput") or "0"
        
        return {
            "totalNodes": int(total_nodes),
            "activeJobs": int(active_jobs),
            "avgLatency": float(avg_latency),
            "throughput": float(throughput)
        }
    except Exception as e:
        logger.error(f"Error getting metrics: {e}")
        return {"totalNodes": 0, "activeJobs": 0, "avgLatency": 0, "throughput": 0}

# REST API Endpoints
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "services": {
            "redis": redis_client is not None,
            "postgres": postgres_pool is not None,
            "websocket_clients": len(manager.active_connections)
        }
    }

@app.get("/metrics")
async def get_metrics():
    return await get_current_metrics()

@app.get("/nodes")
async def get_nodes():
    """Get all registered nodes"""
    try:
        if not redis_client:
            return []
            
        nodes = []
        node_keys = await redis_client.keys("node:*:info")
        
        for key in node_keys:
            node_data = await redis_client.hgetall(key)
            if node_data:
                node_id = key.split(":")[1]
                nodes.append({
                    "id": node_data.get("id", node_id),
                    "name": node_data.get("name", f"Node {node_id}"),
                    "location": {
                        "lat": float(node_data.get("lat", 0)),
                        "lng": float(node_data.get("lng", 0))
                    },
                    "region": node_data.get("region", "unknown"),
                    "status": node_data.get("status", "offline"),
                    "gpu_model": node_data.get("gpu_model", "Unknown"),
                    "cpu_cores": int(node_data.get("cpu_cores", 0)),
                    "memory_gb": int(node_data.get("memory_gb", 0)),
                    "load": float(node_data.get("load", 0)),
                    "jobs_completed": int(node_data.get("jobs_completed", 0)),
                    "uptime_hours": int(node_data.get("uptime_hours", 0)),
                    "capabilities": json.loads(node_data.get("capabilities", "[]"))
                })
        
        return nodes
        
    except Exception as e:
        logger.error(f"Error fetching nodes: {e}")
        return []

@app.get("/jobs")
async def get_jobs():
    """Get active jobs"""
    try:
        if not redis_client:
            return []
            
        jobs = []
        job_keys = await redis_client.keys("job:*:info")
        
        for key in job_keys[:20]:
            job_data = await redis_client.hgetall(key)
            if job_data:
                job_id = key.split(":")[1]
                jobs.append({
                    "id": job_id,
                    "model_name": job_data.get("model_name", "unknown"),
                    "node_id": job_data.get("node_id", "unassigned"),
                    "status": job_data.get("status", "pending"),
                    "progress": int(job_data.get("progress", 0)),
                    "duration": int(time.time() - float(job_data.get("start_time", time.time()))),
                    "priority": int(job_data.get("priority", 1)),
                    "submitted_at": job_data.get("submitted_at", "")
                })
        
        return jobs
        
    except Exception as e:
        logger.error(f"Error fetching jobs: {e}")
        return []

@app.post("/submit", response_model=JobResponse)
async def submit_job(
    request: SubmitJobRequest,
    authorization: str = Header(None),
    x_client_id: str = Header(None)
):
    """Submit a new job"""
    try:
        if not redis_client:
            raise HTTPException(status_code=503, detail="Service temporarily unavailable")
            
        # Verify token
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Invalid authorization")
        
        token = authorization.split(" ")[1]
        if not verify_token(token):
            raise HTTPException(status_code=401, detail="Invalid token")
        
        # Generate job ID
        job_id = generate_job_id()
        submitted_at = datetime.datetime.utcnow().isoformat()
        submitted_at_str = submitted_at.isoformat()
        
        # Store job in Redis
        job_data = {
            "id": job_id,
            "model_name": request.model_name,
            "input_data": json.dumps(request.input_data),
            "priority": request.priority,
            "timeout": request.timeout,
            "status": "pending",
            "progress": 0,
            "client_id": x_client_id or "unknown",
            "submitted_at": submitted_at_str,
            "start_time": str(time.time())
        }
        
        await redis_client.hset(f"job:{job_id}:info", mapping=job_data)
        await redis_client.lpush(f"jobs:queue:{request.priority}", job_id)
        await redis_client.incr("metrics:active_jobs")
        
        # Broadcast job creation
        await manager.broadcast({
            "type": "job_update",
            "job_id": job_id,
            "payload": job_data
        }, channel="jobs")
        
        # Log to PostgreSQL if available
        if postgres_pool:
            try:
                async with postgres_pool.acquire() as conn:
                    await conn.execute("""
                        INSERT INTO jobs (id, model_name, client_id, status, submitted_at, priority)
                        VALUES ($1, $2, $3, $4, $5, $6)
                    """, job_id, request.model_name, x_client_id, "pending", submitted_at, request.priority)
            except Exception as e:
                logger.error(f"Error logging to PostgreSQL: {e}")
                # Continue sans PostgreSQL
        
        logger.info(f"Job {job_id} submitted successfully")
        
        return JobResponse(
            job_id=job_id,
            status="pending",
            message="Job submitted successfully",
            submitted_at=submitted_at
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error submitting job: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# WebSocket endpoint
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message.get("type") == "subscribe":
                channels = message.get("channels", [])
                await manager.subscribe(websocket, channels)
                await websocket.send_text(json.dumps({
                    "type": "subscribed",
                    "channels": channels
                }))
            
            elif message.get("type") == "ping":
                await websocket.send_text(json.dumps({
                    "type": "pong",
                    "timestamp": time.time()
                }))
                
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        manager.disconnect(websocket)

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8080,
        reload=False,
        log_level="info"
    )

#!/bin/bash

# Script to create all Python files for SynapseGrid MVP

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}=== Creating Python Service Files ===${NC}"

# 1. Create services/gateway/main.py
echo -e "\n${GREEN}Creating services/gateway/main.py...${NC}"
cat > services/gateway/main.py << 'EOF'
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
sys.path.append('/app')
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
EOF

# 2. Create services/dispatcher/main.py
echo -e "\n${GREEN}Creating services/dispatcher/main.py...${NC}"
cat > services/dispatcher/main.py << 'EOF'
#!/usr/bin/env python3
"""Dispatcher Service - Assigns jobs to nodes based on scoring"""

import os
import sys
import asyncio
import json
import time
from datetime import datetime
from typing import Dict, List, Optional

import redis.asyncio as redis
import structlog
from apscheduler.schedulers.asyncio import AsyncIOScheduler

# Add shared module to path
sys.path.append('/app')
from shared.utils import get_redis_client
from shared.models import JobStatus, NodeStatus

# Configure structured logging
logger = structlog.get_logger()

class Dispatcher:
    def __init__(self):
        self.redis_client = None
        self.region = os.getenv("REGION", "us-east")
        self.scheduler = AsyncIOScheduler()
        self.running = True
        
    async def initialize(self):
        """Initialize connections and scheduler"""
        redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        self.redis_client = await redis.from_url(redis_url, decode_responses=True)
        
        # Schedule periodic tasks
        self.scheduler.add_job(
            self.rank_nodes,
            'interval',
            seconds=int(os.getenv("NODE_RANKING_INTERVAL", "30"))
        )
        self.scheduler.start()
        
        logger.info("Dispatcher initialized", region=self.region)
    
    async def rank_nodes(self):
        """Rank nodes based on availability and performance"""
        try:
            # Get all nodes in region
            node_keys = await self.redis_client.keys(f"node:*:{self.region}")
            
            node_scores = []
            for key in node_keys:
                node_data = await self.redis_client.hgetall(key)
                if node_data.get('status') == NodeStatus.ONLINE.value:
                    # Calculate score based on various factors
                    score = self.calculate_node_score(node_data)
                    node_scores.append((node_data['node_id'], score))
            
            # Sort by score (higher is better)
            node_scores.sort(key=lambda x: x[1], reverse=True)
            
            # Store ranked list in Redis
            ranked_key = f"top_nodes:{self.region}"
            await self.redis_client.delete(ranked_key)
            
            for node_id, score in node_scores[:20]:  # Keep top 20 nodes
                await self.redis_client.zadd(ranked_key, {node_id: score})
            
            logger.info("Nodes ranked", region=self.region, count=len(node_scores))
            
        except Exception as e:
            logger.error("Failed to rank nodes", error=str(e))
    
    def calculate_node_score(self, node_data: Dict) -> float:
        """Calculate node score based on multiple factors"""
        score = 100.0
        
        # CPU usage (lower is better)
        cpu_usage = float(node_data.get('cpu_usage', 50))
        score -= cpu_usage * 0.5
        
        # Memory availability
        memory_available = float(node_data.get('memory_available', 50))
        score += memory_available * 0.3
        
        # Success rate
        success_rate = float(node_data.get('success_rate', 95))
        score += success_rate * 0.2
        
        # Response time (lower is better)
        avg_response_time = float(node_data.get('avg_response_time', 1000))
        score -= (avg_response_time / 1000) * 10
        
        # Uptime bonus
        uptime_hours = float(node_data.get('uptime_hours', 0))
        score += min(uptime_hours, 24) * 0.5
        
        return max(score, 0)
    
    async def dispatch_jobs(self):
        """Main dispatch loop"""
        while self.running:
            try:
                # Get pending jobs from queue
                queue_key = f"jobs:queue:{self.region}"
                job_ids = await self.redis_client.zrange(queue_key, 0, 10, desc=True)
                
                if job_ids:
                    # Get available nodes
                    ranked_key = f"top_nodes:{self.region}"
                    top_nodes = await self.redis_client.zrange(
                        ranked_key, 0, -1, desc=True, withscores=True
                    )
                    
                    for job_id in job_ids:
                        await self.assign_job_to_node(job_id, top_nodes)
                
                await asyncio.sleep(0.5)  # Check every 500ms
                
            except Exception as e:
                logger.error("Dispatch error", error=str(e))
                await asyncio.sleep(1)
    
    async def assign_job_to_node(self, job_id: str, available_nodes: List):
        """Assign a job to the best available node"""
        for node_id, score in available_nodes:
            try:
                # Try to claim the node for this job
                lock_key = f"node_lock:{node_id}"
                locked = await self.redis_client.setnx(lock_key, job_id)
                
                if locked:
                    # Set expiry on lock (30 seconds)
                    await self.redis_client.expire(lock_key, 30)
                    
                    # Update job status
                    await self.redis_client.hset(
                        f"job:{job_id}",
                        mapping={
                            "status": JobStatus.ASSIGNED.value,
                            "assigned_node": node_id,
                            "assigned_at": datetime.utcnow().isoformat()
                        }
                    )
                    
                    # Remove from pending queue
                    queue_key = f"jobs:queue:{self.region}"
                    await self.redis_client.zrem(queue_key, job_id)
                    
                    # Add to node's job queue
                    node_queue = f"node_jobs:{node_id}"
                    await self.redis_client.lpush(node_queue, job_id)
                    
                    # Publish assignment event
                    await self.redis_client.publish(
                        f"job:assigned:{node_id}",
                        json.dumps({
                            "job_id": job_id,
                            "node_id": node_id,
                            "timestamp": time.time()
                        })
                    )
                    
                    logger.info("Job assigned", 
                               job_id=job_id, 
                               node_id=node_id,
                               score=score)
                    break
                    
            except Exception as e:
                logger.error("Failed to assign job", 
                           error=str(e),
                           job_id=job_id,
                           node_id=node_id)
    
    async def run(self):
        """Run the dispatcher"""
        await self.initialize()
        
        # Start dispatch task
        dispatch_task = asyncio.create_task(self.dispatch_jobs())
        
        try:
            await dispatch_task
        except KeyboardInterrupt:
            logger.info("Shutting down dispatcher")
            self.running = False
            self.scheduler.shutdown()
            await self.redis_client.close()

async def main():
    dispatcher = Dispatcher()
    await dispatcher.run()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 3. Create services/aggregator/main.py
echo -e "\n${GREEN}Creating services/aggregator/main.py...${NC}"
cat > services/aggregator/main.py << 'EOF'
#!/usr/bin/env python3
"""Aggregator Service - Collects results and triggers reward distribution"""

import os
import sys
import asyncio
import json
import time
from datetime import datetime
from typing import Dict, Any

import redis.asyncio as redis
import structlog
from prometheus_client import Counter, Histogram

# Add shared module to path
sys.path.append('/app')
from shared.utils import get_redis_client
from shared.models import JobStatus

# Configure structured logging
logger = structlog.get_logger()

# Metrics
results_received = Counter('aggregator_results_received', 'Total results received')
results_validated = Counter('aggregator_results_validated', 'Results validated')
rewards_triggered = Counter('aggregator_rewards_triggered', 'Rewards triggered')

class Aggregator:
    def __init__(self):
        self.redis_client = None
        self.running = True
        
    async def initialize(self):
        """Initialize connections"""
        redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        self.redis_client = await redis.from_url(redis_url, decode_responses=True)
        
        logger.info("Aggregator initialized")
    
    async def process_results(self):
        """Process incoming results from nodes"""
        # Subscribe to result channel
        pubsub = self.redis_client.pubsub()
        await pubsub.subscribe("job:result:*")
        
        while self.running:
            try:
                message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
                
                if message and message['data']:
                    await self.handle_result(message['channel'], message['data'])
                    
            except Exception as e:
                logger.error("Result processing error", error=str(e))
                await asyncio.sleep(1)
    
    async def handle_result(self, channel: str, data: str):
        """Handle a job result"""
        try:
            result_data = json.loads(data)
            job_id = result_data['job_id']
            node_id = result_data['node_id']
            
            results_received.inc()
            logger.info("Result received", job_id=job_id, node_id=node_id)
            
            # Get job data
            job_data = await self.redis_client.hgetall(f"job:{job_id}")
            if not job_data:
                logger.error("Job not found", job_id=job_id)
                return
            
            # Validate result
            if await self.validate_result(result_data, job_data):
                results_validated.inc()
                
                # Update job status
                await self.redis_client.hset(
                    f"job:{job_id}",
                    mapping={
                        "status": JobStatus.COMPLETED.value,
                        "completed_at": datetime.utcnow().isoformat(),
                        "result": json.dumps(result_data.get('result', {})),
                        "execution_time": result_data.get('execution_time', 0)
                    }
                )
                
                # Trigger reward distribution
                await self.trigger_rewards(job_id, node_id, result_data)
                
                # Notify client
                await self.redis_client.publish(
                    f"job:completed:{job_data['client_id']}",
                    json.dumps({
                        "job_id": job_id,
                        "status": JobStatus.COMPLETED.value,
                        "result": result_data.get('result', {})
                    })
                )
                
            else:
                # Mark job as failed
                await self.redis_client.hset(
                    f"job:{job_id}",
                    mapping={
                        "status": JobStatus.FAILED.value,
                        "failed_at": datetime.utcnow().isoformat(),
                        "error": "Result validation failed"
                    }
                )
                
        except Exception as e:
            logger.error("Failed to handle result", error=str(e))
    
    async def validate_result(self, result_data: Dict, job_data: Dict) -> bool:
        """Validate the result"""
        # Basic validation for MVP
        if not result_data.get('result'):
            return False
        
        if result_data.get('status') != 'success':
            return False
        
        # In production, verify:
        # - Result signature
        # - Result format matches model output
        # - Execution proof
        
        return True
    
    async def trigger_rewards(self, job_id: str, node_id: str, result_data: Dict):
        """Trigger reward distribution"""
        try:
            rewards_triggered.inc()
            
            # Calculate rewards (simplified for MVP)
            base_reward = 10  # Base $NRG tokens
            performance_bonus = 0
            
            # Performance bonus based on execution time
            execution_time = result_data.get('execution_time', 0)
            if execution_time < 0.5:
                performance_bonus = 5
            elif execution_time < 1.0:
                performance_bonus = 2
            
            total_reward = base_reward + performance_bonus
            
            # Store reward info
            reward_data = {
                "job_id": job_id,
                "node_id": node_id,
                "amount": total_reward,
                "timestamp": time.time(),
                "status": "pending"
            }
            
            await self.redis_client.hset(
                f"reward:{job_id}",
                mapping=reward_data
            )
            
            # Queue for blockchain submission
            await self.redis_client.lpush("rewards:pending", json.dumps(reward_data))
            
            # Update node stats
            await self.redis_client.hincrby(f"node:{node_id}:stats", "completed_jobs", 1)
            await self.redis_client.hincrbyfloat(f"node:{node_id}:stats", "total_rewards", total_reward)
            
            logger.info("Rewards triggered", 
                       job_id=job_id,
                       node_id=node_id,
                       amount=total_reward)
            
        except Exception as e:
            logger.error("Failed to trigger rewards", error=str(e))
    
    async def submit_rewards_to_blockchain(self):
        """Periodically submit rewards to blockchain"""
        while self.running:
            try:
                # Get pending rewards
                reward_json = await self.redis_client.rpop("rewards:pending")
                
                if reward_json:
                    reward_data = json.loads(reward_json)
                    
                    # In production: Submit to smart contract
                    # For MVP: Mark as distributed
                    await self.redis_client.hset(
                        f"reward:{reward_data['job_id']}",
                        "status", "distributed"
                    )
                    
                    logger.info("Reward distributed", 
                               job_id=reward_data['job_id'],
                               amount=reward_data['amount'])
                
                await asyncio.sleep(5)  # Check every 5 seconds
                
            except Exception as e:
                logger.error("Blockchain submission error", error=str(e))
                await asyncio.sleep(10)
    
    async def run(self):
        """Run the aggregator"""
        await self.initialize()
        
        # Start tasks
        tasks = [
            asyncio.create_task(self.process_results()),
            asyncio.create_task(self.submit_rewards_to_blockchain())
        ]
        
        try:
            await asyncio.gather(*tasks)
        except KeyboardInterrupt:
            logger.info("Shutting down aggregator")
            self.running = False
            await self.redis_client.close()

async def main():
    aggregator = Aggregator()
    await aggregator.run()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 4. Create services/node/main.py
echo -e "\n${GREEN}Creating services/node/main.py...${NC}"
cat > services/node/main.py << 'EOF'
#!/usr/bin/env python3
"""Node Service - Executes AI workloads"""

import os
import sys
import asyncio
import json
import time
import psutil
from datetime import datetime
from typing import Dict, Any, Optional

import redis.asyncio as redis
import numpy as np
import onnxruntime as ort
import structlog
from prometheus_client import Counter, Histogram, Gauge

# Add shared module to path
sys.path.append('/app')
from shared.utils import get_redis_client
from shared.models import NodeStatus

# Configure structured logging
logger = structlog.get_logger()

# Metrics
jobs_executed = Counter('node_jobs_executed', 'Total jobs executed')
jobs_failed = Counter('node_jobs_failed', 'Jobs failed')
execution_time = Histogram('node_execution_seconds', 'Job execution time')
node_utilization = Gauge('node_utilization', 'Node resource utilization')

class ComputeNode:
    def __init__(self):
        self.redis_client = None
        self.node_id = os.getenv("NODE_ID", f"node_{int(time.time())}")
        self.region = os.getenv("REGION", "us-east")
        self.gateway_url = os.getenv("GATEWAY_URL", "http://gateway:8080")
        self.running = True
        self.models = {}
        self.capabilities = self._get_capabilities()
        
    def _get_capabilities(self) -> Dict:
        """Determine node capabilities"""
        return {
            "models": ["resnet50", "mobilenet"],  # Supported models
            "memory": psutil.virtual_memory().total // (1024**2),  # MB
            "cpu_cores": psutil.cpu_count(),
            "gpu": False,  # Simplified for MVP
            "max_batch_size": 1
        }
    
    async def initialize(self):
        """Initialize connections and models"""
        redis_url = os.getenv("REDIS_URL", "redis://redis:6379")
        self.redis_client = await redis.from_url(redis_url, decode_responses=True)
        
        # Load ONNX models
        await self.load_models()
        
        # Register node
        await self.register_node()
        
        logger.info("Node initialized", 
                   node_id=self.node_id,
                   region=self.region,
                   capabilities=self.capabilities)
    
    async def load_models(self):
        """Load ONNX models"""
        models_path = os.getenv("ONNX_MODELS_PATH", "/app/models")
        
        # For MVP, create dummy models if not present
        for model_name in self.capabilities['models']:
            model_path = f"{models_path}/{model_name}.onnx"
            
            try:
                if os.path.exists(model_path):
                    session = ort.InferenceSession(model_path)
                    self.models[model_name] = session
                    logger.info(f"Loaded model: {model_name}")
                else:
                    # For MVP, create a dummy "model" function
                    self.models[model_name] = self.create_dummy_model(model_name)
                    logger.info(f"Created dummy model: {model_name}")
                    
            except Exception as e:
                logger.error(f"Failed to load model {model_name}", error=str(e))
    
    def create_dummy_model(self, model_name: str):
        """Create a dummy model for testing"""
        def dummy_inference(input_data):
            # Simulate processing time
            time.sleep(0.1 + np.random.random() * 0.4)
            
            # Return dummy results based on model
            if model_name == "resnet50":
                # Classification result
                return {
                    "class": np.random.randint(0, 1000),
                    "confidence": float(np.random.random()),
                    "top_5": [
                        {"class": i, "confidence": float(np.random.random())}
                        for i in np.random.randint(0, 1000, 5)
                    ]
                }
            else:
                # Generic result
                return {
                    "output": np.random.randn(1, 10).tolist(),
                    "processing_time": 0.1 + np.random.random() * 0.4
                }
        
        return dummy_inference
    
    async def register_node(self):
        """Register node with the system"""
        node_data = {
            "node_id": self.node_id,
            "region": self.region,
            "status": NodeStatus.ONLINE.value,
            "capabilities": json.dumps(self.capabilities),
            "registered_at": datetime.utcnow().isoformat(),
            "last_heartbeat": time.time()
        }
        
        key = f"node:{self.node_id}:{self.region}"
        await self.redis_client.hset(key, mapping=node_data)
        
        # Add to region's node set
        await self.redis_client.sadd(f"nodes:{self.region}", self.node_id)
    
    async def send_heartbeat(self):
        """Send periodic heartbeat"""
        while self.running:
            try:
                # Update node stats
                stats = {
                    "cpu_usage": psutil.cpu_percent(),
                    "memory_available": psutil.virtual_memory().percent,
                    "last_heartbeat": time.time(),
                    "status": NodeStatus.ONLINE.value
                }
                
                key = f"node:{self.node_id}:{self.region}"
                await self.redis_client.hset(key, mapping=stats)
                
                # Update utilization metric
                node_utilization.set(stats['cpu_usage'])
                
                await asyncio.sleep(10)  # Every 10 seconds
                
            except Exception as e:
                logger.error("Heartbeat failed", error=str(e))
                await asyncio.sleep(5)
    
    async def process_jobs(self):
        """Main job processing loop"""
        # Subscribe to job assignments
        pubsub = self.redis_client.pubsub()
        await pubsub.subscribe(f"job:assigned:{self.node_id}")
        
        while self.running:
            try:
                # Check for assigned jobs
                job_queue = f"node_jobs:{self.node_id}"
                job_id = await self.redis_client.rpop(job_queue)
                
                if job_id:
                    await self.execute_job(job_id)
                else:
                    # Check for pubsub messages
                    message = await pubsub.get_message(
                        ignore_subscribe_messages=True, 
                        timeout=0.1
                    )
                    
                await asyncio.sleep(0.1)
                
            except Exception as e:
                logger.error("Job processing error", error=str(e))
                await asyncio.sleep(1)
    
    async def execute_job(self, job_id: str):
        """Execute a single job"""
        start_time = time.time()
        
        try:
            # Get job data
            job_data = await self.redis_client.hgetall(f"job:{job_id}")
            if not job_data:
                logger.error("Job not found", job_id=job_id)
                return
            
            logger.info("Executing job", 
                       job_id=job_id,
                       model=job_data.get('model_name'))
            
            # Update job status
            await self.redis_client.hset(
                f"job:{job_id}",
                "status", "running"
            )
            
            # Execute model
            model_name = job_data.get('model_name')
            input_data = json.loads(job_data.get('input_data', '{}'))
            
            if model_name not in self.models:
                raise ValueError(f"Model {model_name} not supported")
            
            # Run inference
            model = self.models[model_name]
            
            if callable(model):
                # Dummy model
                result = model(input_data)
            else:
                # Real ONNX model
                # Convert input data to numpy array
                # This is simplified - real implementation would handle various input formats
                input_array = np.random.randn(1, 3, 224, 224).astype(np.float32)
                inputs = {model.get_inputs()[0].name: input_array}
                outputs = model.run(None, inputs)
                result = {"output": outputs[0].tolist()}
            
            execution_duration = time.time() - start_time
            execution_time.observe(execution_duration)
            jobs_executed.inc()
            
            # Send result
            result_data = {
                "job_id": job_id,
                "node_id": self.node_id,
                "status": "success",
                "result": result,
                "execution_time": execution_duration,
                "timestamp": time.time()
            }
            
            # Publish result
            await self.redis_client.publish(
                "job:result:aggregator",
                json.dumps(result_data)
            )
            
            # Release node lock
            await self.redis_client.delete(f"node_lock:{self.node_id}")
            
            logger.info("Job completed", 
                       job_id=job_id,
                       execution_time=execution_duration)
            
        except Exception as e:
            jobs_failed.inc()
            logger.error("Job execution failed", 
                        error=str(e),
                        job_id=job_id)
            
            # Send failure result
            result_data = {
                "job_id": job_id,
                "node_id": self.node_id,
                "status": "failed",
                "error": str(e),
                "timestamp": time.time()
            }
            
            await self.redis_client.publish(
                "job:result:aggregator",
                json.dumps(result_data)
            )
            
            # Release node lock
            await self.redis_client.delete(f"node_lock:{self.node_id}")
    
    async def cleanup(self):
        """Cleanup on shutdown"""
        # Update node status
        key = f"node:{self.node_id}:{self.region}"
        await self.redis_client.hset(key, "status", NodeStatus.OFFLINE.value)
        
        # Remove from region's node set
        await self.redis_client.srem(f"nodes:{self.region}", self.node_id)
        
        logger.info("Node cleanup completed", node_id=self.node_id)
    
    async def run(self):
        """Run the compute node"""
        await self.initialize()
        
        # Start tasks
        tasks = [
            asyncio.create_task(self.send_heartbeat()),
            asyncio.create_task(self.process_jobs())
        ]
        
        try:
            await asyncio.gather(*tasks)
        except KeyboardInterrupt:
            logger.info("Shutting down node")
            self.running = False
            await self.cleanup()
            await self.redis_client.close()

async def main():
    node = ComputeNode()
    await node.run()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 5. Create shared/models.py
echo -e "\n${GREEN}Creating shared/models.py...${NC}"
cat > shared/models.py << 'EOF'
"""Shared data models"""

from enum import Enum
from datetime import datetime
from typing import Dict, Any, Optional
from pydantic import BaseModel

class JobStatus(Enum):
    PENDING = "pending"
    ASSIGNED = "assigned"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

class NodeStatus(Enum):
    ONLINE = "online"
    OFFLINE = "offline"
    BUSY = "busy"
    MAINTENANCE = "maintenance"

class Job(BaseModel):
    job_id: str
    model_name: str
    input_data: Dict[str, Any]
    priority: int = 1
    client_id: str
    status: JobStatus = JobStatus.PENDING
    submitted_at: datetime
    assigned_node: Optional[str] = None
    assigned_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    region: str

class Node(BaseModel):
    node_id: str
    region: str
    status: NodeStatus = NodeStatus.OFFLINE
    capabilities: Dict[str, Any]
    registered_at: datetime
    last_heartbeat: float
    cpu_usage: float = 0.0
    memory_available: float = 100.0
    success_rate: float = 100.0
    avg_response_time: float = 0.0
    uptime_hours: float = 0.0
EOF

# 6. Create shared/utils.py
echo -e "\n${GREEN}Creating shared/utils.py...${NC}"
cat > shared/utils.py << 'EOF'
"""Shared utilities for all services"""

import os
import redis.asyncio as redis
from sqlalchemy import create_engine
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

async def get_redis_client():
    """Get Redis client"""
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
    return await redis.from_url(redis_url, decode_responses=True)

def get_postgres_engine():
    """Get PostgreSQL engine"""
    postgres_url = os.getenv("POSTGRES_URL", "postgresql://synapse:synapse123@localhost:5432/synapse")
    return create_engine(postgres_url)

async def get_async_postgres_session():
    """Get async PostgreSQL session"""
    postgres_url = os.getenv("POSTGRES_URL", "postgresql://synapse:synapse123@localhost:5432/synapse")
    # Convert to async URL
    async_url = postgres_url.replace("postgresql://", "postgresql+asyncpg://")
    
    engine = create_async_engine(async_url)
    async_session = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )
    
    async with async_session() as session:
        yield session
EOF

# 7. Create test_system.py
echo -e "\n${GREEN}Creating test_system.py...${NC}"
cat > test_system.py << 'EOF'
#!/usr/bin/env python3
"""Test script for SynapseGrid MVP"""

import requests
import json
import time
import sys
from datetime import datetime

BASE_URL = "http://localhost:8080"

def test_health():
    """Test health endpoint"""
    print("Testing health endpoint...")
    try:
        response = requests.get(f"{BASE_URL}/health")
        if response.status_code == 200:
            print("✓ Health check passed:", response.json())
        else:
            print("✗ Health check failed:", response.status_code)
            return False
    except Exception as e:
        print("✗ Cannot connect to gateway:", str(e))
        return False
    return True

def test_submit_job():
    """Test job submission"""
    print("\nTesting job submission...")
    
    job_data = {
        "model_name": "resnet50",
        "input_data": {
            "image": "test_image.jpg",
            "format": "jpeg"
        },
        "priority": 1
    }
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer test-token-123",
        "X-Client-ID": "test-client"
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/submit",
            json=job_data,
            headers=headers
        )
        
        if response.status_code == 200:
            job_response = response.json()
            print("✓ Job submitted successfully:")
            print(f"  Job ID: {job_response['job_id']}")
            print(f"  Status: {job_response['status']}")
            print(f"  Submitted at: {job_response['submitted_at']}")
            return job_response['job_id']
        else:
            print("✗ Job submission failed:", response.status_code)
            print("  Response:", response.text)
            return None
            
    except Exception as e:
        print("✗ Error submitting job:", str(e))
        return None

def test_job_status(job_id):
    """Test job status retrieval"""
    print(f"\nChecking status for job {job_id}...")
    
    max_attempts = 30  # Wait up to 30 seconds
    for i in range(max_attempts):
        try:
            response = requests.get(f"{BASE_URL}/job/{job_id}")
            
            if response.status_code == 200:
                job_data = response.json()
                status = job_data.get('status', 'unknown')
                print(f"  Attempt {i+1}: Status = {status}")
                
                if status == 'completed':
                    print("✓ Job completed successfully!")
                    print(f"  Result: {job_data.get('result', {})}")
                    print(f"  Execution time: {job_data.get('execution_time', 0):.2f}s")
                    return True
                elif status == 'failed':
                    print("✗ Job failed!")
                    print(f"  Error: {job_data.get('error', 'Unknown error')}")
                    return False
                    
            time.sleep(1)
            
        except Exception as e:
            print(f"  Error checking status: {str(e)}")
            time.sleep(1)
    
    print("✗ Job did not complete within timeout")
    return False

def main():
    """Run all tests"""
    print("=== SynapseGrid MVP Test Suite ===")
    print(f"Timestamp: {datetime.now().isoformat()}")
    print(f"Target: {BASE_URL}\n")
    
    # Test 1: Health check
    if not test_health():
        print("\nGateway is not responding. Make sure services are running:")
        print("  docker-compose ps")
        print("  docker-compose logs gateway")
        sys.exit(1)
    
    # Test 2: Submit job
    job_id = test_submit_job()
    if job_id:
        # Test 3: Check job status
        test_job_status(job_id)
    
    print("\n=== Test Suite Complete ===")

if __name__ == "__main__":
    main()
EOF

# Make all Python files executable
chmod +x services/gateway/main.py
chmod +x services/dispatcher/main.py
chmod +x services/aggregator/main.py
chmod +x services/node/main.py
chmod +x test_system.py

echo -e "\n${GREEN}=== All Python files created successfully! ===${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Build Docker images: docker-compose build"
echo "2. Start services: docker-compose up -d"
echo "3. Check status: docker-compose ps"
echo "4. Run tests: ./test_system.py"
echo ""
echo -e "${YELLOW}Note: Make sure you have already run setup_complete.sh first${NC}"

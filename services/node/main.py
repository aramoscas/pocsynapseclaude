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
# Path already set by PYTHONPATH env variable
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

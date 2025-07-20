# services/dispatcher/main.py - Self-contained
import asyncio
import json
import logging
from datetime import datetime

import aioredis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Dispatcher:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        self.redis = aioredis.from_url("redis://redis:6379", encoding="utf-8", decode_responses=True)
        await self.redis.ping()
        self.running = True
        logger.info("✅ Dispatcher started")
        
        await self.dispatch_loop()
    
    async def dispatch_loop(self):
        while self.running:
            try:
                # Process regular jobs
                await self.process_queue("jobs:queue:eu-west-1")
                # Process native jobs
                await self.process_native_queue()
                await asyncio.sleep(0.1)
            except Exception as e:
                logger.error(f"❌ Dispatch error: {e}")
                await asyncio.sleep(1)
    
    async def process_queue(self, queue_key):
        job_data = await self.redis.brpop(queue_key, timeout=1)
        if job_data:
            job = json.loads(job_data[1])
            await self.dispatch_to_docker_node(job)
    
    async def process_native_queue(self):
        job_data = await self.redis.brpop("jobs:queue:native", timeout=1)
        if job_data:
            job = json.loads(job_data[1])
            await self.dispatch_to_native_node(job)
    
    async def dispatch_to_docker_node(self, job):
        logger.info(f"📤 Dispatching job {job['job_id']} to Docker node")
        # Simulate job execution for Docker nodes
        await asyncio.sleep(1)
        result_data = {
            "job_id": job["job_id"],
            "node_id": "docker_node_001",
            "success": "true",
            "execution_time": "1.0",
            "result": json.dumps({"message": "Docker simulation complete"}),
            "timestamp": datetime.utcnow().isoformat()
        }
        await self.redis.xadd("job_results", result_data)
    
    async def dispatch_to_native_node(self, job):
        # Find available native nodes
        native_nodes = await self.redis.smembers("native_nodes")
        
        if native_nodes:
            node_id = list(native_nodes)[0]
            node_queue = f"node_jobs:{node_id}"
            await self.redis.lpush(node_queue, json.dumps(job))
            logger.info(f"📤 Dispatched job {job['job_id']} to Mac M2 node {node_id}")
        else:
            # Requeue if no native nodes
            await self.redis.lpush("jobs:queue:native", json.dumps(job))
            logger.warning(f"⚠️ No native nodes available, requeued job {job['job_id']}")

async def main():
    dispatcher = Dispatcher()
    try:
        await dispatcher.start()
    except KeyboardInterrupt:
        logger.info("🛑 Dispatcher shutdown")
        dispatcher.running = False

if __name__ == "__main__":
    asyncio.run(main())

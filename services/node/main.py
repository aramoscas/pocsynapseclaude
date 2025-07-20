# services/node/main.py - Self-contained Docker Node
import asyncio
import json
import logging
import time
from datetime import datetime

import aioredis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DockerNode:
    def __init__(self):
        self.node_id = "docker_node_001"
        self.redis = None
        self.running = False
        self.jobs_completed = 0
    
    async def start(self):
        self.redis = aioredis.from_url("redis://redis:6379", encoding="utf-8", decode_responses=True)
        await self.redis.ping()
        
        # Register node
        await self.register()
        
        self.running = True
        logger.info(f"✅ Docker node {self.node_id} started")
        
        await asyncio.gather(
            self.heartbeat_loop(),
            self.job_simulation_loop()
        )
    
    async def register(self):
        node_key = f"node:{self.node_id}:eu-west-1:info"
        await self.redis.hmset(node_key, {
            "node_id": self.node_id,
            "node_type": "docker",
            "status": "available",
            "last_seen": datetime.utcnow().isoformat()
        })
        await self.redis.expire(node_key, 60)
        logger.info(f"📝 Registered Docker node {self.node_id}")
    
    async def heartbeat_loop(self):
        while self.running:
            try:
                node_key = f"node:{self.node_id}:eu-west-1:info"
                await self.redis.hset(node_key, "last_seen", datetime.utcnow().isoformat())
                await self.redis.hset(node_key, "jobs_completed", str(self.jobs_completed))
                await self.redis.expire(node_key, 60)
                await asyncio.sleep(10)
            except Exception as e:
                logger.error(f"❌ Heartbeat error: {e}")
                await asyncio.sleep(5)
    
    async def job_simulation_loop(self):
        """Simulate processing jobs (since this is a demo Docker node)"""
        while self.running:
            try:
                # Check if there are jobs in queue (just for logging)
                queue_length = await self.redis.llen("jobs:queue:eu-west-1")
                if queue_length > 0:
                    logger.info(f"📊 Docker node ready to process {queue_length} queued jobs")
                
                await asyncio.sleep(5)
            except Exception as e:
                logger.error(f"❌ Job simulation error: {e}")
                await asyncio.sleep(5)

async def main():
    node = DockerNode()
    try:
        await node.start()
    except KeyboardInterrupt:
        logger.info("🛑 Docker node shutdown")
        node.running = False

if __name__ == "__main__":
    asyncio.run(main())

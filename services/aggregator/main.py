# services/aggregator/main.py - Self-contained
import asyncio
import json
import logging
from datetime import datetime

import aioredis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Aggregator:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        self.redis = aioredis.from_url("redis://redis:6379", encoding="utf-8", decode_responses=True)
        await self.redis.ping()
        self.running = True
        logger.info("✅ Aggregator started")
        
        await self.process_results_loop()
    
    async def process_results_loop(self):
        while self.running:
            try:
                # Read from results stream
                streams = {"job_results": "$"}
                results = await self.redis.xread(streams, count=10, block=1000)
                
                for stream_name, messages in results:
                    for message_id, fields in messages:
                        await self.process_result(fields)
                        await self.redis.xdel("job_results", message_id)
                        
            except Exception as e:
                logger.error(f"❌ Aggregator error: {e}")
                await asyncio.sleep(1)
    
    async def process_result(self, result_data):
        job_id = result_data.get("job_id")
        success = result_data.get("success") == "true"
        node_id = result_data.get("node_id")
        execution_time = result_data.get("execution_time", "0")
        result = result_data.get("result")
        
        logger.info(f"📥 Processed result for job {job_id} from node {node_id}: {'✅' if success else '❌'} ({execution_time}s)")
        
        # Simulate reward distribution
        if success:
            reward = 0.008  # 80% of 0.01 cost goes to node
            logger.info(f"💰 Distributed {reward} $NRG to node {node_id}")

async def main():
    aggregator = Aggregator()
    try:
        await aggregator.start()
    except KeyboardInterrupt:
        logger.info("🛑 Aggregator shutdown")
        aggregator.running = False

if __name__ == "__main__":
    asyncio.run(main())

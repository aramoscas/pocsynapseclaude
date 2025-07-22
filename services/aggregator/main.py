import asyncio
import json
import logging
from datetime import datetime
import redis.asyncio as redis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class AggregatorWorker:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        try:
            self.redis = redis.Redis(host='redis', port=6379, decode_responses=True)
            await self.redis.ping()
            self.running = True
            logger.info("✅ Aggregator Worker started")
            await self.process_results()
        except Exception as e:
            logger.error(f"❌ Error: {e}")
    
    async def process_results(self):
        logger.info("📊 Processing results...")
        while self.running:
            try:
                result_data = await self.redis.brpop("job_results", timeout=5)
                if result_data:
                    _, result_json = result_data
                    result = json.loads(result_json)
                    job_id = result.get('job_id')
                    logger.info(f"📊 Storing result for {job_id}")
                    
                    # Store result
                    await self.redis.setex(f"result:{job_id}", 3600, result_json)
                    logger.info(f"✅ Result stored for {job_id}")
                    
            except Exception as e:
                logger.error(f"❌ Error processing: {e}")
                await asyncio.sleep(5)

async def main():
    worker = AggregatorWorker()
    await worker.start()

if __name__ == "__main__":
    asyncio.run(main())

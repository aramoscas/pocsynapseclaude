import asyncio
import json
import logging
from datetime import datetime
import redis.asyncio as redis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DispatcherWorker:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        try:
            self.redis = redis.Redis(host='redis', port=6379, decode_responses=True)
            await self.redis.ping()
            self.running = True
            logger.info("✅ Dispatcher Worker started")
            await self.process_jobs()
        except Exception as e:
            logger.error(f"❌ Error: {e}")
    
    async def process_jobs(self):
        logger.info("🔄 Processing jobs...")
        while self.running:
            try:
                job_data = await self.redis.brpop("jobs:queue:eu-west-1", timeout=5)
                if job_data:
                    _, job_json = job_data
                    job = json.loads(job_json)
                    job_id = job.get('job_id')
                    logger.info(f"🚀 Processing job {job_id}")
                    
                    # Simulate work
                    await asyncio.sleep(2)
                    
                    # Send result
                    result = {
                        "job_id": job_id,
                        "status": "completed",
                        "result": {"predictions": [0.8, 0.2]},
                        "completed_at": datetime.utcnow().isoformat()
                    }
                    await self.redis.lpush("job_results", json.dumps(result))
                    logger.info(f"✅ Job {job_id} completed")
                    
            except Exception as e:
                logger.error(f"❌ Error processing: {e}")
                await asyncio.sleep(5)

async def main():
    worker = DispatcherWorker()
    await worker.start()

if __name__ == "__main__":
    asyncio.run(main())

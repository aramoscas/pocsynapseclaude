#!/usr/bin/env python3
import asyncio
import json
import time
import os
import redis.asyncio as redis

async def main():
    print("🚀 Dispatcher service starting...")
    
    redis_host = os.getenv('REDIS_HOST', 'redis')
    client = redis.Redis(host=redis_host, port=6379, decode_responses=True)
    
    print(f"✅ Dispatcher connected to Redis at {redis_host}")
    
    while True:
        try:
            job_data = await client.brpop("jobs:queue:local", timeout=5)
            
            if job_data:
                _, job_json = job_data
                job = json.loads(job_json)
                job_id = job['job_id']
                
                print(f"🔄 Processing job {job_id} - {job['model_name']}")
                
                await asyncio.sleep(0.5)
                
                result = {
                    "job_id": job_id,
                    "result": {"predictions": [0.8, 0.2], "processing_time": 500},
                    "completed_at": time.time(),
                    "node_id": "dispatcher-sim"
                }
                
                await client.lpush("results:queue:local", json.dumps(result))
                print(f"✅ Job {job_id} completed")
            
        except Exception as e:
            print(f"❌ Dispatcher error: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())

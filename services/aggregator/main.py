#!/usr/bin/env python3
import asyncio
import json
import time
import os
import redis.asyncio as redis

async def main():
    print("📊 Aggregator service starting...")
    
    redis_host = os.getenv('REDIS_HOST', 'redis')
    client = redis.Redis(host=redis_host, port=6379, decode_responses=True)
    
    print(f"✅ Aggregator connected to Redis at {redis_host}")
    
    while True:
        try:
            result_data = await client.brpop("results:queue:local", timeout=5)
            
            if result_data:
                _, result_json = result_data
                result = json.loads(result_json)
                job_id = result['job_id']
                
                print(f"📊 Aggregating result for job {job_id}")
                
                await client.setex(f"result:{job_id}", 3600, result_json)
                
                print(f"✅ Result for {job_id} stored")
            
        except Exception as e:
            print(f"❌ Aggregator error: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())

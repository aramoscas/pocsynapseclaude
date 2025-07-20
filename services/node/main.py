#!/usr/bin/env python3
import asyncio
import time
import os
import redis.asyncio as redis

async def main():
    node_id = os.getenv('NODE_ID', 'sim-node-001')
    redis_host = os.getenv('REDIS_HOST', 'redis')
    
    print(f"🖥️ Node {node_id} starting...")
    
    client = redis.Redis(host=redis_host, port=6379, decode_responses=True)
    
    print(f"✅ Node {node_id} connected to Redis at {redis_host}")
    
    await client.sadd("nodes:active:local", node_id)
    
    while True:
        try:
            await client.setex(f"node:{node_id}:heartbeat", 30, str(time.time()))
            print(f"💓 Node {node_id} heartbeat sent")
            await asyncio.sleep(10)
        except Exception as e:
            print(f"❌ Node {node_id} error: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())

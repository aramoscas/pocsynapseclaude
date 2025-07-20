#!/usr/bin/env python3
"""Test Redis connection from Mac M2 node"""
import asyncio
import aioredis
import sys

async def test_redis_connection():
    print("🔍 Testing Redis connection...")
    
    # Test different connection methods
    test_configs = [
        ("localhost", 6379),
        ("127.0.0.1", 6379),
        ("0.0.0.0", 6379),
    ]
    
    for host, port in test_configs:
        try:
            print(f"Testing {host}:{port}...")
            redis_url = f"redis://{host}:{port}"
            redis = aioredis.from_url(redis_url, encoding="utf-8", decode_responses=True)
            
            # Test ping
            await redis.ping()
            print(f"✅ Successfully connected to {host}:{port}")
            
            # Test basic operations
            await redis.set("test_key", "test_value")
            value = await redis.get("test_key")
            await redis.delete("test_key")
            
            if value == "test_value":
                print(f"✅ Redis operations working on {host}:{port}")
                await redis.close()
                return host, port
            
            await redis.close()
            
        except Exception as e:
            print(f"❌ Failed to connect to {host}:{port}: {e}")
    
    print("❌ All Redis connection attempts failed")
    return None, None

if __name__ == "__main__":
    try:
        host, port = asyncio.run(test_redis_connection())
        if host:
            print(f"\n🎉 Redis is accessible at {host}:{port}")
            sys.exit(0)
        else:
            print(f"\n💥 Redis is not accessible")
            sys.exit(1)
    except Exception as e:
        print(f"💥 Test failed: {e}")
        sys.exit(1)

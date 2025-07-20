#!/usr/bin/env python3
import asyncio
import aiohttp
import time
import json

async def submit_job(session, client_id):
    payload = {
        "model_name": "resnet50",
        "input_data": {"test": "data"},
        "priority": 5
    }
    
    headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer test-token',
        'X-Client-ID': client_id
    }
    
    start = time.time()
    try:
        async with session.post('http://localhost:8080/submit', 
                               json=payload, headers=headers) as resp:
            duration = time.time() - start
            return resp.status == 200, duration
    except Exception as e:
        return False, time.time() - start

async def load_test(concurrent=10, total=100):
    print(f"Running load test: {concurrent} concurrent, {total} total requests")
    
    async with aiohttp.ClientSession() as session:
        semaphore = asyncio.Semaphore(concurrent)
        
        async def limited_request(i):
            async with semaphore:
                return await submit_job(session, f"load-test-{i}")
        
        start_time = time.time()
        results = await asyncio.gather(*[limited_request(i) for i in range(total)])
        total_time = time.time() - start_time
        
        successes = sum(1 for success, _ in results if success)
        avg_duration = sum(duration for _, duration in results) / len(results)
        
        print(f"Results:")
        print(f"  Successful: {successes}/{total} ({successes/total*100:.1f}%)")
        print(f"  Average duration: {avg_duration*1000:.0f}ms")
        print(f"  Total time: {total_time:.2f}s")
        print(f"  Requests/sec: {total/total_time:.2f}")

if __name__ == "__main__":
    asyncio.run(load_test())

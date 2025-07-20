#!/usr/bin/env python3
"""Integration test for complete system"""
import asyncio
import aiohttp
import json
import time

async def test_integration():
    print("🧪 SynapseGrid Integration Test")
    print("=" * 40)
    
    gateway_url = "http://localhost:8080"
    success_count = 0
    total_tests = 4
    
    async with aiohttp.ClientSession() as session:
        # Test 1: Gateway health
        print("1. Testing gateway health...")
        try:
            async with session.get(f"{gateway_url}/health") as resp:
                if resp.status == 200:
                    print("✅ Gateway healthy")
                    success_count += 1
                else:
                    print(f"❌ Gateway unhealthy: {resp.status}")
        except Exception as e:
            print(f"❌ Gateway connection failed: {e}")
        
        # Test 2: Submit regular job
        print("2. Testing regular job submission...")
        try:
            job_data = {
                "model_name": "resnet50",
                "input_data": {"image": "test.jpg"}
            }
            headers = {
                "Content-Type": "application/json",
                "Authorization": "Bearer test-token",
                "X-Client-ID": "test-client"
            }
            
            async with session.post(f"{gateway_url}/submit", json=job_data, headers=headers) as resp:
                if resp.status == 200:
                    result = await resp.json()
                    print(f"✅ Regular job submitted: {result.get('job_id')}")
                    success_count += 1
                else:
                    print(f"❌ Regular job failed: {resp.status}")
        except Exception as e:
            print(f"❌ Regular job error: {e}")
        
        # Test 3: Check nodes
        print("3. Testing node listing...")
        try:
            async with session.get(f"{gateway_url}/nodes") as resp:
                if resp.status == 200:
                    nodes = await resp.json()
                    print(f"✅ Found {len(nodes)} nodes")
                    success_count += 1
                else:
                    print(f"❌ Node listing failed: {resp.status}")
        except Exception as e:
            print(f"❌ Node listing error: {e}")
        
        # Test 4: Submit Mac job (if native endpoint exists)
        print("4. Testing Mac M2 job submission...")
        try:
            job_data = {
                "model_name": "resnet50",
                "input_data": {"image": "test.jpg"},
                "gpu_requirements": {"supports_metal": True}
            }
            headers = {
                "Content-Type": "application/json",
                "Authorization": "Bearer test-token",
                "X-Client-ID": "mac-test-client"
            }
            
            async with session.post(f"{gateway_url}/jobs/submit/native", json=job_data, headers=headers) as resp:
                if resp.status == 200:
                    result = await resp.json()
                    print(f"✅ Mac M2 job submitted: {result.get('job_id')}")
                    success_count += 1
                elif resp.status == 404:
                    print("⚠️  Mac M2 endpoint not available yet")
                else:
                    print(f"❌ Mac M2 job failed: {resp.status}")
        except Exception as e:
            print(f"❌ Mac M2 job error: {e}")
    
    print(f"\n📊 Test Results: {success_count}/{total_tests} passed")
    return success_count == total_tests

if __name__ == "__main__":
    success = asyncio.run(test_integration())
    exit(0 if success else 1)

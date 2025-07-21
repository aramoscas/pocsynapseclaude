#!/usr/bin/env python3
"""Test script for SynapseGrid MVP"""

import requests
import json
import time
import sys
from datetime import datetime

BASE_URL = "http://localhost:8080"

def test_health():
    """Test health endpoint"""
    print("Testing health endpoint...")
    try:
        response = requests.get(f"{BASE_URL}/health")
        if response.status_code == 200:
            print("✓ Health check passed:", response.json())
        else:
            print("✗ Health check failed:", response.status_code)
            return False
    except Exception as e:
        print("✗ Cannot connect to gateway:", str(e))
        return False
    return True

def test_submit_job():
    """Test job submission"""
    print("\nTesting job submission...")
    
    job_data = {
        "model_name": "resnet50",
        "input_data": {
            "image": "test_image.jpg",
            "format": "jpeg"
        },
        "priority": 1
    }
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer test-token-123",
        "X-Client-ID": "test-client"
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/submit",
            json=job_data,
            headers=headers
        )
        
        if response.status_code == 200:
            job_response = response.json()
            print("✓ Job submitted successfully:")
            print(f"  Job ID: {job_response['job_id']}")
            print(f"  Status: {job_response['status']}")
            print(f"  Submitted at: {job_response['submitted_at']}")
            return job_response['job_id']
        else:
            print("✗ Job submission failed:", response.status_code)
            print("  Response:", response.text)
            return None
            
    except Exception as e:
        print("✗ Error submitting job:", str(e))
        return None

def test_job_status(job_id):
    """Test job status retrieval"""
    print(f"\nChecking status for job {job_id}...")
    
    max_attempts = 30  # Wait up to 30 seconds
    for i in range(max_attempts):
        try:
            response = requests.get(f"{BASE_URL}/job/{job_id}")
            
            if response.status_code == 200:
                job_data = response.json()
                status = job_data.get('status', 'unknown')
                print(f"  Attempt {i+1}: Status = {status}")
                
                if status == 'completed':
                    print("✓ Job completed successfully!")
                    print(f"  Result: {job_data.get('result', {})}")
                    print(f"  Execution time: {job_data.get('execution_time', 0):.2f}s")
                    return True
                elif status == 'failed':
                    print("✗ Job failed!")
                    print(f"  Error: {job_data.get('error', 'Unknown error')}")
                    return False
                    
            time.sleep(1)
            
        except Exception as e:
            print(f"  Error checking status: {str(e)}")
            time.sleep(1)
    
    print("✗ Job did not complete within timeout")
    return False

def main():
    """Run all tests"""
    print("=== SynapseGrid MVP Test Suite ===")
    print(f"Timestamp: {datetime.now().isoformat()}")
    print(f"Target: {BASE_URL}\n")
    
    # Test 1: Health check
    if not test_health():
        print("\nGateway is not responding. Make sure services are running:")
        print("  docker-compose ps")
        print("  docker-compose logs gateway")
        sys.exit(1)
    
    # Test 2: Submit job
    job_id = test_submit_job()
    if job_id:
        # Test 3: Check job status
        test_job_status(job_id)
    
    print("\n=== Test Suite Complete ===")

if __name__ == "__main__":
    main()

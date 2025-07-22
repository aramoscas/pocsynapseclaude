#!/usr/bin/env python3
"""Test simple du gateway"""

import requests
import json
import time

BASE_URL = "http://localhost:8080"

def test_health():
    """Test health endpoint"""
    try:
        resp = requests.get(f"{BASE_URL}/health")
        print(f"✅ Health: {resp.json()}")
        return resp.status_code == 200
    except Exception as e:
        print(f"❌ Health failed: {e}")
        return False

def test_submit():
    """Test job submission"""
    try:
        headers = {
            "Authorization": "Bearer test-token",
            "X-Client-ID": "test-client"
        }
        data = {
            "model_name": "test-model",
            "input_data": {"test": "data"}
        }
        resp = requests.post(f"{BASE_URL}/submit", 
                           headers=headers, 
                           json=data)
        result = resp.json()
        print(f"✅ Submit: {result}")
        
        # Test status
        if 'job_id' in result:
            status_resp = requests.get(f"{BASE_URL}/job/{result['job_id']}/status")
            print(f"✅ Status: {status_resp.json()}")
        
        return resp.status_code == 200
    except Exception as e:
        print(f"❌ Submit failed: {e}")
        return False

if __name__ == "__main__":
    print("🧪 Test du Gateway...")
    time.sleep(2)  # Attendre que tout soit prêt
    
    if test_health() and test_submit():
        print("\n✅ Tous les tests passent!")
    else:
        print("\n❌ Certains tests ont échoué")

#!/usr/bin/env python3
"""SynapseGrid Node - Worker qui exécute les jobs"""

import asyncio
import json
import logging
import os
import time
import random
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

import redis
import requests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
NODE_ID = os.getenv("NODE_ID", f"node-{os.getpid()}")
NODE_TYPE = os.getenv("NODE_TYPE", "docker")
REGION = os.getenv("REGION", "eu-west-1")
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://gateway:8080")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
MAX_CONCURRENT = int(os.getenv("MAX_CONCURRENT_JOBS", "2"))

# Connexions
redis_client = None
executor = ThreadPoolExecutor(max_workers=MAX_CONCURRENT)
current_jobs = 0

def get_redis():
    return redis.StrictRedis(host=REDIS_HOST, port=6379, decode_responses=True)

async def redis_async(func, *args):
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, func, *args)

async def register_node():
    """Enregistre le node auprès du gateway"""
    try:
        node_info = {
            "node_id": NODE_ID,
            "node_type": NODE_TYPE,
            "region": REGION,
            "capabilities": {
                "models": ["test-model", "resnet50", "bert-base"],
                "max_batch_size": 32
            },
            "gpu_info": {
                "available": False,
                "model": "CPU"
            },
            "cpu_cores": os.cpu_count(),
            "memory_gb": 16.0,
            "max_concurrent": MAX_CONCURRENT
        }
        
        # Enregistrer via API
        response = requests.post(
            f"{GATEWAY_URL}/nodes/register",
            json=node_info,
            timeout=10
        )
        
        if response.status_code == 200:
            logger.info(f"✅ Node {NODE_ID} enregistré")
        else:
            logger.warning(f"Erreur enregistrement: {response.status_code}")
            
    except Exception as e:
        logger.error(f"Erreur enregistrement node: {e}")

async def update_heartbeat():
    """Met à jour le heartbeat du node"""
    while True:
        try:
            node_key = f"node:{NODE_ID}:{REGION}:info"
            node_info = {
                "node_id": NODE_ID,
                "node_type": NODE_TYPE,
                "region": REGION,
                "status": "online",
                "current_load": current_jobs,
                "max_concurrent": MAX_CONCURRENT,
                "last_seen": datetime.utcnow().isoformat()
            }
            
            await redis_async(redis_client.hmset, node_key, node_info)
            await redis_async(redis_client.expire, node_key, 60)
            
            await asyncio.sleep(10)
            
        except Exception as e:
            logger.error(f"Erreur heartbeat: {e}")
            await asyncio.sleep(10)

async def execute_job(job_data):
    """Exécute un job (simulation)"""
    global current_jobs
    current_jobs += 1
    
    job_id = job_data.get("job_id")
    model_name = job_data.get("model_name")
    
    logger.info(f"🔧 Exécution job {job_id} (model: {model_name})")
    
    start_time = time.time()
    
    try:
        # Simulation d'exécution
        await asyncio.sleep(random.uniform(1, 5))
        
        # Générer un résultat
        result = {
            "job_id": job_id,
            "node_id": NODE_ID,
            "success": True,
            "result": {
                "prediction": random.random(),
                "confidence": random.uniform(0.7, 0.99),
                "model": model_name,
                "processed_at": datetime.utcnow().isoformat()
            },
            "execution_time_ms": int((time.time() - start_time) * 1000)
        }
        
        # Envoyer le résultat
        await redis_async(redis_client.lpush, "results:queue", json.dumps(result))
        
        logger.info(f"✅ Job {job_id} complété en {result['execution_time_ms']}ms")
        
    except Exception as e:
        logger.error(f"Erreur exécution job: {e}")
        
        # Envoyer l'erreur
        error_result = {
            "job_id": job_id,
            "node_id": NODE_ID,
            "success": False,
            "error": str(e),
            "execution_time_ms": int((time.time() - start_time) * 1000)
        }
        await redis_async(redis_client.lpush, "results:queue", json.dumps(error_result))
    
    finally:
        current_jobs -= 1

async def job_processing_loop():
    """Boucle de traitement des jobs"""
    logger.info(f"🔄 Node {NODE_ID} en attente de jobs...")
    
    node_queue = f"node:{NODE_ID}:jobs"
    
    while True:
        try:
            # Vérifier si on peut prendre un job
            if current_jobs < MAX_CONCURRENT:
                job_json = await redis_async(redis_client.rpop, node_queue)
                
                if job_json:
                    job_data = json.loads(job_json)
                    # Lancer l'exécution en parallèle
                    asyncio.create_task(execute_job(job_data))
                else:
                    await asyncio.sleep(1)
            else:
                await asyncio.sleep(1)
                
        except Exception as e:
            logger.error(f"Erreur processing loop: {e}")
            await asyncio.sleep(5)

async def main():
    """Main node worker"""
    global redis_client
    
    logger.info(f"🚀 Démarrage du Node {NODE_ID} ({NODE_TYPE}) dans {REGION}")
    
    # Connexion Redis
    redis_client = get_redis()
    redis_client.ping()
    logger.info("✅ Redis connecté")
    
    # Enregistrer le node
    await register_node()
    
    # Lancer les tâches
    await asyncio.gather(
        update_heartbeat(),
        job_processing_loop()
    )

if __name__ == "__main__":
    asyncio.run(main())

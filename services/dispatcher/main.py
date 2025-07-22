#!/usr/bin/env python3
"""SynapseGrid Dispatcher - Distribue les jobs aux nodes"""

import asyncio
import json
import logging
import time
import os
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

import redis
import psycopg2
from psycopg2.extras import RealDictCursor

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "postgres")
DISPATCH_INTERVAL = int(os.getenv("DISPATCH_INTERVAL", "5"))

# Connexions
redis_client = None
pg_conn = None
executor = ThreadPoolExecutor(max_workers=5)

def get_redis():
    return redis.StrictRedis(host=REDIS_HOST, port=6379, decode_responses=True)

def get_postgres():
    return psycopg2.connect(
        host=POSTGRES_HOST,
        database="synapse",
        user="synapse",
        password="synapse123",
        cursor_factory=RealDictCursor
    )

async def redis_async(func, *args):
    """Wrapper async pour Redis"""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, func, *args)

async def select_best_node(region="eu-west-1"):
    """Sélectionne le meilleur node disponible"""
    try:
        # Récupérer les nodes actifs depuis Redis
        pattern = f"node:*:{region}:info"
        keys = await redis_async(redis_client.keys, pattern)
        
        best_node = None
        best_score = -1
        
        for key in keys:
            node_info = await redis_async(redis_client.hgetall, key)
            if node_info.get("status") == "online":
                # Score simple basé sur la charge
                load = int(node_info.get("current_load", 0))
                max_load = int(node_info.get("max_concurrent", 1))
                score = (max_load - load) / max_load
                
                if score > best_score:
                    best_score = score
                    best_node = node_info.get("node_id")
        
        return best_node
    except Exception as e:
        logger.error(f"Erreur sélection node: {e}")
        return None

async def dispatch_job(job_data):
    """Dispatche un job vers un node"""
    job_id = job_data.get("job_id")
    
    try:
        # Sélectionner un node
        node_id = await select_best_node()
        if not node_id:
            logger.warning(f"Aucun node disponible pour {job_id}")
            return False
        
        logger.info(f"📤 Dispatch job {job_id} vers {node_id}")
        
        # Assigner le job au node
        job_data["assigned_node"] = node_id
        job_data["status"] = "dispatched"
        job_data["dispatched_at"] = datetime.utcnow().isoformat()
        
        # Pousser vers la queue du node
        node_queue = f"node:{node_id}:jobs"
        await redis_async(redis_client.lpush, node_queue, json.dumps(job_data))
        
        # Mettre à jour la DB
        try:
            with pg_conn.cursor() as cur:
                cur.execute("""
                    UPDATE jobs 
                    SET status = 'dispatched', 
                        assigned_node = %s,
                        started_at = CURRENT_TIMESTAMP
                    WHERE job_id = %s
                """, (node_id, job_id))
                pg_conn.commit()
        except Exception as e:
            logger.warning(f"Erreur update DB: {e}")
        
        return True
        
    except Exception as e:
        logger.error(f"Erreur dispatch: {e}")
        return False

async def dispatch_loop():
    """Boucle principale de dispatch"""
    logger.info("🔄 Démarrage de la boucle de dispatch...")
    
    while True:
        try:
            # Récupérer les jobs en attente
            regions = ["eu-west-1", "us-east-1", "ap-south-1", "local"]
            
            for region in regions:
                queue_key = f"jobs:queue:{region}"
                
                # Récupérer un job de la queue
                job_json = await redis_async(redis_client.rpop, queue_key)
                if job_json:
                    job_data = json.loads(job_json)
                    await dispatch_job(job_data)
            
            await asyncio.sleep(DISPATCH_INTERVAL)
            
        except Exception as e:
            logger.error(f"Erreur dans la boucle: {e}")
            await asyncio.sleep(DISPATCH_INTERVAL)

async def main():
    """Main dispatcher"""
    global redis_client, pg_conn
    
    logger.info("🚀 Démarrage du Dispatcher...")
    
    # Connexions
    redis_client = get_redis()
    pg_conn = get_postgres()
    
    # Test connexions
    redis_client.ping()
    logger.info("✅ Redis connecté")
    
    with pg_conn.cursor() as cur:
        cur.execute("SELECT 1")
    logger.info("✅ PostgreSQL connecté")
    
    # Lancer la boucle de dispatch
    await dispatch_loop()

if __name__ == "__main__":
    asyncio.run(main())

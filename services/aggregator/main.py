#!/usr/bin/env python3
"""SynapseGrid Aggregator - Collecte et agrège les résultats"""

import asyncio
import json
import logging
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
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, func, *args)

async def process_result(result_data):
    """Traite un résultat de job"""
    job_id = result_data.get("job_id")
    node_id = result_data.get("node_id")
    
    logger.info(f"📊 Traitement résultat {job_id} de {node_id}")
    
    try:
        # Mettre à jour la DB
        with pg_conn.cursor() as cur:
            if result_data.get("success"):
                cur.execute("""
                    UPDATE jobs 
                    SET status = 'completed',
                        result = %s,
                        completed_at = CURRENT_TIMESTAMP,
                        execution_time_ms = %s
                    WHERE job_id = %s
                """, (
                    json.dumps(result_data.get("result", {})),
                    result_data.get("execution_time_ms", 0),
                    job_id
                ))
            else:
                cur.execute("""
                    UPDATE jobs 
                    SET status = 'failed',
                        error = %s,
                        completed_at = CURRENT_TIMESTAMP
                    WHERE job_id = %s
                """, (result_data.get("error", "Unknown error"), job_id))
            
            pg_conn.commit()
        
        # Mettre à jour Redis
        job_key = f"job:{job_id}:info"
        await redis_async(redis_client.hset, job_key, "status", 
                         "completed" if result_data.get("success") else "failed")
        
        # Stats du node
        if result_data.get("success"):
            stats_key = f"node:{node_id}:stats"
            await redis_async(redis_client.hincrby, stats_key, "completed_jobs", 1)
            await redis_async(redis_client.hincrby, stats_key, "total_time_ms", 
                            result_data.get("execution_time_ms", 0))
        
        logger.info(f"✅ Résultat {job_id} traité")
        
    except Exception as e:
        logger.error(f"Erreur traitement résultat: {e}")

async def aggregation_loop():
    """Boucle principale d'agrégation"""
    logger.info("🔄 Démarrage de la boucle d'agrégation...")
    
    while True:
        try:
            # Écouter la queue des résultats
            result_json = await redis_async(redis_client.rpop, "results:queue")
            
            if result_json:
                result_data = json.loads(result_json)
                await process_result(result_data)
            else:
                await asyncio.sleep(1)
                
        except Exception as e:
            logger.error(f"Erreur agrégation: {e}")
            await asyncio.sleep(5)

async def main():
    """Main aggregator"""
    global redis_client, pg_conn
    
    logger.info("🚀 Démarrage de l'Aggregator...")
    
    # Connexions
    redis_client = get_redis()
    pg_conn = get_postgres()
    
    # Test connexions
    redis_client.ping()
    logger.info("✅ Redis connecté")
    
    with pg_conn.cursor() as cur:
        cur.execute("SELECT 1")
    logger.info("✅ PostgreSQL connecté")
    
    # Lancer la boucle
    await aggregation_loop()

if __name__ == "__main__":
    asyncio.run(main())

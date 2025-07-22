#!/usr/bin/env python3
"""
SynapseGrid Dispatcher - Version propre sans aioredis
"""

import asyncio
import redis
import asyncpg
import json
import logging
from datetime import datetime
import os
from functools import partial

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class AsyncRedisWrapper:
    """Wrapper pour Redis sync dans contexte async"""
    def __init__(self, redis_client):
        self.redis = redis_client
        self.loop = asyncio.get_event_loop()
    
    async def brpop(self, key: str, timeout: int = 5):
        return await self.loop.run_in_executor(
            None, partial(self.redis.brpop, key, timeout=timeout)
        )
    
    async def smembers(self, key: str):
        return await self.loop.run_in_executor(
            None, self.redis.smembers, key
        )
    
    async def get(self, key: str):
        return await self.loop.run_in_executor(
            None, self.redis.get, key
        )
    
    async def hincrby(self, name: str, key: str, amount: int = 1):
        return await self.loop.run_in_executor(
            None, self.redis.hincrby, name, key, amount
        )
    
    async def publish(self, channel: str, message: str):
        return await self.loop.run_in_executor(
            None, self.redis.publish, channel, message
        )
    
    async def lpush(self, key: str, value: str):
        return await self.loop.run_in_executor(
            None, self.redis.lpush, key, value
        )
    
    async def setex(self, key: str, time: int, value: str):
        return await self.loop.run_in_executor(
            None, self.redis.setex, key, time, value
        )

class Dispatcher:
    def __init__(self):
        self.redis_client = None
        self.async_redis = None
        self.db_pool = None
        self.running = True
        
    async def start(self):
        """Initialize connections"""
        # Redis sync client
        self.redis_client = redis.Redis(
            host=os.getenv('REDIS_HOST', 'redis'),
            port=int(os.getenv('REDIS_PORT', 6379)),
            decode_responses=True
        )
        self.async_redis = AsyncRedisWrapper(self.redis_client)
        logger.info("✅ Connected to Redis")
        
        # PostgreSQL
        self.db_pool = await asyncpg.create_pool(
            host=os.getenv('POSTGRES_HOST', 'postgres'),
            port=int(os.getenv('POSTGRES_PORT', 5432)),
            user=os.getenv('POSTGRES_USER', 'synapse'),
            password=os.getenv('POSTGRES_PASSWORD', 'synapse123'),
            database=os.getenv('POSTGRES_DB', 'synapse')
        )
        logger.info("✅ Connected to PostgreSQL")
        
        # Ensure at least one node exists
        await self.ensure_default_node()
        
    async def ensure_default_node(self):
        """S'assurer qu'au moins un node existe"""
        nodes = await self.async_redis.smembers('nodes:registered')
        if not nodes:
            default_node = "node_dispatcher_default"
            self.redis_client.sadd('nodes:registered', default_node)
            self.redis_client.set(
                f'node:{default_node}:info',
                json.dumps({
                    'node_id': default_node,
                    'status': 'available',
                    'capacity': 1.0,
                    'current_load': 0
                })
            )
            logger.info(f"✅ Created default node: {default_node}")
    
    async def get_best_node(self, job_data):
        """Find the best available node"""
        nodes = await self.async_redis.smembers('nodes:registered')
        
        best_node = None
        best_score = -1
        
        for node_id in nodes:
            if isinstance(node_id, bytes):
                node_id = node_id.decode('utf-8')
                
            node_info_raw = await self.async_redis.get(f'node:{node_id}:info')
            if not node_info_raw:
                continue
                
            try:
                node_info = json.loads(node_info_raw)
                if node_info.get('status') != 'available':
                    continue
                    
                load = float(node_info.get('current_load', 1.0))
                capacity = float(node_info.get('capacity', 1.0))
                score = capacity * (1 - load)
                
                if score > best_score:
                    best_score = score
                    best_node = node_id
            except:
                continue
                
        return best_node
        
    async def dispatch_job(self, job_data):
        """Dispatch a job to a node"""
        job_id = job_data['job_id']
        
        # Find best node
        node_id = await self.get_best_node(job_data)
        
        if not node_id:
            logger.warning(f"❌ No available nodes for job {job_id}")
            return False
            
        logger.info(f"📍 Assigning job {job_id} to node {node_id}")
        
        try:
            async with self.db_pool.acquire() as conn:
                # Mettre à jour le job - gérer les différentes structures de table
                result = await conn.execute("""
                    UPDATE jobs 
                    SET status = 'assigned',
                        node_id = $1
                    WHERE job_id = $2 OR id = $2
                """, node_id, job_id)
                
                # Si la colonne assigned_node existe, la mettre à jour aussi
                await conn.execute("""
                    UPDATE jobs 
                    SET assigned_node = $1
                    WHERE (job_id = $2 OR id = $2) 
                    AND EXISTS (
                        SELECT 1 FROM information_schema.columns 
                        WHERE table_name='jobs' AND column_name='assigned_node'
                    )
                """, node_id, job_id)
            
            # Update node load
            await self.async_redis.hincrby('nodes:load', node_id, 1)
            
            # Send job to node
            await self.async_redis.publish(f'node:{node_id}:jobs', json.dumps(job_data))
            
            # Track assignment
            await self.async_redis.setex(f'job:{job_id}:assigned', 300, node_id)
            
            logger.info(f"✅ Job {job_id} dispatched to {node_id}")
            return True
            
        except Exception as e:
            logger.error(f"Error dispatching job: {e}")
            return False
            
    async def process_queue(self):
        """Main processing loop"""
        logger.info("🚀 Dispatcher started - processing queue")
        
        while self.running:
            try:
                # Get job from queue
                result = await self.async_redis.brpop('jobs:queue:eu-west-1', timeout=5)
                
                if result:
                    _, job_json = result
                    job_data = json.loads(job_json)
                    
                    logger.info(f"📥 Processing job {job_data['job_id']}")
                    
                    # Try to dispatch
                    if not await self.dispatch_job(job_data):
                        # Put back in queue if dispatch failed
                        await self.async_redis.lpush('jobs:queue:eu-west-1', job_json)
                        await asyncio.sleep(5)
                else:
                    # Check for stuck jobs every 30 seconds
                    await self.check_stuck_jobs()
                        
            except Exception as e:
                logger.error(f"Error in dispatcher loop: {e}")
                await asyncio.sleep(5)
                
    async def check_stuck_jobs(self):
        """Check for jobs stuck in pending state"""
        try:
            async with self.db_pool.acquire() as conn:
                # Requête adaptée aux différentes structures de table
                stuck_jobs = await conn.fetch("""
                    SELECT 
                        COALESCE(job_id, id) as job_id,
                        client_id,
                        model_name,
                        input_data,
                        priority
                    FROM jobs
                    WHERE status = 'pending'
                    AND (
                        (created_at IS NOT NULL AND created_at < NOW() - INTERVAL '5 minutes')
                        OR (submitted_at IS NOT NULL AND submitted_at < NOW() - INTERVAL '5 minutes')
                    )
                    LIMIT 10
                """)
                
                for job in stuck_jobs:
                    job_data = {
                        'job_id': job['job_id'],
                        'client_id': job['client_id'],
                        'model_name': job['model_name'],
                        'input_data': json.loads(job['input_data']) if isinstance(job['input_data'], str) else job['input_data'],
                        'priority': job['priority']
                    }
                    await self.async_redis.lpush('jobs:queue:eu-west-1', json.dumps(job_data))
                    logger.info(f"🔄 Re-queued stuck job {job['job_id']}")
                    
        except Exception as e:
            logger.error(f"Error checking stuck jobs: {e}")
                
    async def run(self):
        """Run the dispatcher"""
        await self.start()
        
        try:
            await self.process_queue()
        finally:
            self.redis_client.close()
            await self.db_pool.close()

if __name__ == "__main__":
    dispatcher = Dispatcher()
    asyncio.run(dispatcher.run())

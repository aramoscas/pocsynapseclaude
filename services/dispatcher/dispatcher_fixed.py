#!/usr/bin/env python3
"""Dispatcher service amélioré pour SynapseGrid"""

import asyncio
import aioredis
import asyncpg
import json
import logging
from datetime import datetime
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Dispatcher:
    def __init__(self):
        self.redis = None
        self.db_pool = None
        self.running = True
        
    async def start(self):
        """Initialize connections"""
        self.redis = await aioredis.create_redis_pool(
            'redis://redis:6379',
            encoding='utf-8'
        )
        logger.info("✅ Connected to Redis")
        
        self.db_pool = await asyncpg.create_pool(
            host='postgres',
            port=5432,
            user='synapse',
            password='synapse123',
            database='synapse'
        )
        logger.info("✅ Connected to PostgreSQL")
        
    async def get_best_node(self, job_data):
        """Find the best available node for a job"""
        nodes = await self.redis.smembers('nodes:registered')
        
        best_node = None
        best_score = -1
        
        for node_id in nodes:
            # Get node info
            node_info_raw = await self.redis.get(f'node:{node_id}:info')
            if not node_info_raw:
                continue
                
            node_info = json.loads(node_info_raw)
            
            # Check if node is available
            if node_info.get('status') != 'available':
                continue
                
            # Calculate score (simple for now)
            load = node_info.get('current_load', 1.0)
            capacity = node_info.get('capacity', 1.0)
            score = capacity * (1 - load)
            
            if score > best_score:
                best_score = score
                best_node = node_id
                
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
        
        # Update job status in database
        async with self.db_pool.acquire() as conn:
            await conn.execute("""
                UPDATE jobs 
                SET status = 'assigned',
                    assigned_node = $1,
                    updated_at = NOW(),
                    queue_time_ms = EXTRACT(EPOCH FROM (NOW() - created_at)) * 1000
                WHERE job_id = $2
            """, node_id, job_id)
            
        # Update node load
        await self.redis.hincrby('nodes:load', node_id, 1)
        
        # Send job to node via pub/sub
        await self.redis.publish(f'node:{node_id}:jobs', json.dumps(job_data))
        
        # Track assignment
        await self.redis.setex(f'job:{job_id}:assigned', 300, node_id)
        
        logger.info(f"✅ Job {job_id} dispatched to {node_id}")
        return True
        
    async def process_queue(self):
        """Main processing loop"""
        logger.info("🚀 Dispatcher started - processing queue")
        
        while self.running:
            try:
                # Get job from queue (blocking pop with timeout)
                result = await self.redis.brpop('jobs:queue:eu-west-1', timeout=5)
                
                if result:
                    _, job_json = result
                    job_data = json.loads(job_json)
                    
                    logger.info(f"📥 Processing job {job_data['job_id']}")
                    
                    # Try to dispatch
                    if not await self.dispatch_job(job_data):
                        # Put back in queue if dispatch failed
                        await self.redis.lpush('jobs:queue:eu-west-1', job_json)
                        await asyncio.sleep(5)  # Wait before retry
                        
                else:
                    # No jobs in queue, check for stuck jobs
                    await self.check_stuck_jobs()
                    
            except Exception as e:
                logger.error(f"Error in dispatcher: {e}")
                await asyncio.sleep(5)
                
    async def check_stuck_jobs(self):
        """Check for jobs that are stuck in pending state"""
        async with self.db_pool.acquire() as conn:
            stuck_jobs = await conn.fetch("""
                SELECT job_id, client_id, model_name, input_data, priority
                FROM jobs
                WHERE status = 'pending'
                AND created_at < NOW() - INTERVAL '5 minutes'
                LIMIT 10
            """)
            
            for job in stuck_jobs:
                job_data = {
                    'job_id': job['job_id'],
                    'client_id': job['client_id'],
                    'model_name': job['model_name'],
                    'input_data': json.loads(job['input_data']),
                    'priority': job['priority']
                }
                await self.redis.lpush('jobs:queue:eu-west-1', json.dumps(job_data))
                logger.info(f"🔄 Re-queued stuck job {job['job_id']}")
                
    async def run(self):
        """Run the dispatcher"""
        await self.start()
        
        try:
            await self.process_queue()
        finally:
            self.redis.close()
            await self.redis.wait_closed()
            await self.db_pool.close()

if __name__ == "__main__":
    dispatcher = Dispatcher()
    asyncio.run(dispatcher.run())

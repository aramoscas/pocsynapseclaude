#!/usr/bin/env python3
"""Aggregator Service - Collects results and triggers reward distribution"""

import os
import sys
import asyncio
import json
import time
from datetime import datetime
from typing import Dict, Any

import redis.asyncio as redis
import structlog
from prometheus_client import Counter, Histogram

# Add shared module to path
# Path already set by PYTHONPATH env variable
from shared.utils import get_redis_client
from shared.models import JobStatus

# Configure structured logging
logger = structlog.get_logger()

# Metrics
results_received = Counter('aggregator_results_received', 'Total results received')
results_validated = Counter('aggregator_results_validated', 'Results validated')
rewards_triggered = Counter('aggregator_rewards_triggered', 'Rewards triggered')

class Aggregator:
    def __init__(self):
        self.redis_client = None
        self.running = True
        
    async def initialize(self):
        """Initialize connections"""
        redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        self.redis_client = await redis.from_url(redis_url, decode_responses=True)
        
        logger.info("Aggregator initialized")
    
    async def process_results(self):
        """Process incoming results from nodes"""
        # Subscribe to result channel
        pubsub = self.redis_client.pubsub()
        await pubsub.subscribe("job:result:*")
        
        while self.running:
            try:
                message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
                
                if message and message['data']:
                    await self.handle_result(message['channel'], message['data'])
                    
            except Exception as e:
                logger.error("Result processing error", error=str(e))
                await asyncio.sleep(1)
    
    async def handle_result(self, channel: str, data: str):
        """Handle a job result"""
        try:
            result_data = json.loads(data)
            job_id = result_data['job_id']
            node_id = result_data['node_id']
            
            results_received.inc()
            logger.info("Result received", job_id=job_id, node_id=node_id)
            
            # Get job data
            job_data = await self.redis_client.hgetall(f"job:{job_id}")
            if not job_data:
                logger.error("Job not found", job_id=job_id)
                return
            
            # Validate result
            if await self.validate_result(result_data, job_data):
                results_validated.inc()
                
                # Update job status
                await self.redis_client.hset(
                    f"job:{job_id}",
                    mapping={
                        "status": JobStatus.COMPLETED.value,
                        "completed_at": datetime.utcnow().isoformat(),
                        "result": json.dumps(result_data.get('result', {})),
                        "execution_time": result_data.get('execution_time', 0)
                    }
                )
                
                # Trigger reward distribution
                await self.trigger_rewards(job_id, node_id, result_data)
                
                # Notify client
                await self.redis_client.publish(
                    f"job:completed:{job_data['client_id']}",
                    json.dumps({
                        "job_id": job_id,
                        "status": JobStatus.COMPLETED.value,
                        "result": result_data.get('result', {})
                    })
                )
                
            else:
                # Mark job as failed
                await self.redis_client.hset(
                    f"job:{job_id}",
                    mapping={
                        "status": JobStatus.FAILED.value,
                        "failed_at": datetime.utcnow().isoformat(),
                        "error": "Result validation failed"
                    }
                )
                
        except Exception as e:
            logger.error("Failed to handle result", error=str(e))
    
    async def validate_result(self, result_data: Dict, job_data: Dict) -> bool:
        """Validate the result"""
        # Basic validation for MVP
        if not result_data.get('result'):
            return False
        
        if result_data.get('status') != 'success':
            return False
        
        # In production, verify:
        # - Result signature
        # - Result format matches model output
        # - Execution proof
        
        return True
    
    async def trigger_rewards(self, job_id: str, node_id: str, result_data: Dict):
        """Trigger reward distribution"""
        try:
            rewards_triggered.inc()
            
            # Calculate rewards (simplified for MVP)
            base_reward = 10  # Base $NRG tokens
            performance_bonus = 0
            
            # Performance bonus based on execution time
            execution_time = result_data.get('execution_time', 0)
            if execution_time < 0.5:
                performance_bonus = 5
            elif execution_time < 1.0:
                performance_bonus = 2
            
            total_reward = base_reward + performance_bonus
            
            # Store reward info
            reward_data = {
                "job_id": job_id,
                "node_id": node_id,
                "amount": total_reward,
                "timestamp": time.time(),
                "status": "pending"
            }
            
            await self.redis_client.hset(
                f"reward:{job_id}",
                mapping=reward_data
            )
            
            # Queue for blockchain submission
            await self.redis_client.lpush("rewards:pending", json.dumps(reward_data))
            
            # Update node stats
            await self.redis_client.hincrby(f"node:{node_id}:stats", "completed_jobs", 1)
            await self.redis_client.hincrbyfloat(f"node:{node_id}:stats", "total_rewards", total_reward)
            
            logger.info("Rewards triggered", 
                       job_id=job_id,
                       node_id=node_id,
                       amount=total_reward)
            
        except Exception as e:
            logger.error("Failed to trigger rewards", error=str(e))
    
    async def submit_rewards_to_blockchain(self):
        """Periodically submit rewards to blockchain"""
        while self.running:
            try:
                # Get pending rewards
                reward_json = await self.redis_client.rpop("rewards:pending")
                
                if reward_json:
                    reward_data = json.loads(reward_json)
                    
                    # In production: Submit to smart contract
                    # For MVP: Mark as distributed
                    await self.redis_client.hset(
                        f"reward:{reward_data['job_id']}",
                        "status", "distributed"
                    )
                    
                    logger.info("Reward distributed", 
                               job_id=reward_data['job_id'],
                               amount=reward_data['amount'])
                
                await asyncio.sleep(5)  # Check every 5 seconds
                
            except Exception as e:
                logger.error("Blockchain submission error", error=str(e))
                await asyncio.sleep(10)
    
    async def run(self):
        """Run the aggregator"""
        await self.initialize()
        
        # Start tasks
        tasks = [
            asyncio.create_task(self.process_results()),
            asyncio.create_task(self.submit_rewards_to_blockchain())
        ]
        
        try:
            await asyncio.gather(*tasks)
        except KeyboardInterrupt:
            logger.info("Shutting down aggregator")
            self.running = False
            await self.redis_client.close()

async def main():
    aggregator = Aggregator()
    await aggregator.run()

if __name__ == "__main__":
    asyncio.run(main())

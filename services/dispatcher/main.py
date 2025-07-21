#!/usr/bin/env python3
"""Dispatcher Service - Assigns jobs to nodes based on scoring"""

import os
import sys
import asyncio
import json
import time
from datetime import datetime
from typing import Dict, List, Optional

import redis.asyncio as redis
import structlog
from apscheduler.schedulers.asyncio import AsyncIOScheduler

# Add shared module to path
# Path already set by PYTHONPATH env variable
from shared.utils import get_redis_client
from shared.models import JobStatus, NodeStatus

# Configure structured logging
logger = structlog.get_logger()

class Dispatcher:
    def __init__(self):
        self.redis_client = None
        self.region = os.getenv("REGION", "eu-west-1")
        self.scheduler = AsyncIOScheduler()
        self.running = True
        
    async def initialize(self):
        """Initialize connections and scheduler"""
        redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        self.redis_client = await redis.from_url(redis_url, decode_responses=True)
        
        # Schedule periodic tasks
        self.scheduler.add_job(
            self.rank_nodes,
            'interval',
            seconds=int(os.getenv("NODE_RANKING_INTERVAL", "30"))
        )
        self.scheduler.start()
        
        logger.info("Dispatcher initialized", region=self.region)
    
    async def rank_nodes(self):
        """Rank nodes based on availability and performance"""
        try:
            # Get all nodes in region
            node_keys = await self.redis_client.keys(f"node:*:{self.region}")
            
            node_scores = []
            for key in node_keys:
                node_data = await self.redis_client.hgetall(key)
                if node_data.get('status') == NodeStatus.ONLINE.value:
                    # Calculate score based on various factors
                    score = self.calculate_node_score(node_data)
                    node_scores.append((node_data['node_id'], score))
            
            # Sort by score (higher is better)
            node_scores.sort(key=lambda x: x[1], reverse=True)
            
            # Store ranked list in Redis
            ranked_key = f"top_nodes:{self.region}"
            await self.redis_client.delete(ranked_key)
            
            for node_id, score in node_scores[:20]:  # Keep top 20 nodes
                await self.redis_client.zadd(ranked_key, {node_id: score})
            
            logger.info("Nodes ranked", region=self.region, count=len(node_scores))
            
        except Exception as e:
            logger.error("Failed to rank nodes", error=str(e))
    
    def calculate_node_score(self, node_data: Dict) -> float:
        """Calculate node score based on multiple factors"""
        score = 100.0
        
        # CPU usage (lower is better)
        cpu_usage = float(node_data.get('cpu_usage', 50))
        score -= cpu_usage * 0.5
        
        # Memory availability
        memory_available = float(node_data.get('memory_available', 50))
        score += memory_available * 0.3
        
        # Success rate
        success_rate = float(node_data.get('success_rate', 95))
        score += success_rate * 0.2
        
        # Response time (lower is better)
        avg_response_time = float(node_data.get('avg_response_time', 1000))
        score -= (avg_response_time / 1000) * 10
        
        # Uptime bonus
        uptime_hours = float(node_data.get('uptime_hours', 0))
        score += min(uptime_hours, 24) * 0.5
        
        return max(score, 0)
    
    async def dispatch_jobs(self):
        """Main dispatch loop"""
        while self.running:
            try:
                # Get pending jobs from queue
                queue_key = f"jobs:queue:{self.region}"
                job_ids = await self.redis_client.zrange(queue_key, 0, 10, desc=True)
                
                if job_ids:
                    # Get available nodes
                    ranked_key = f"top_nodes:{self.region}"
                    top_nodes = await self.redis_client.zrange(
                        ranked_key, 0, -1, desc=True, withscores=True
                    )
                    
                    for job_id in job_ids:
                        await self.assign_job_to_node(job_id, top_nodes)
                
                await asyncio.sleep(0.5)  # Check every 500ms
                
            except Exception as e:
                logger.error("Dispatch error", error=str(e))
                await asyncio.sleep(1)
    
    async def assign_job_to_node(self, job_id: str, available_nodes: List):
        """Assign a job to the best available node"""
        for node_id, score in available_nodes:
            try:
                # Try to claim the node for this job
                lock_key = f"node_lock:{node_id}"
                locked = await self.redis_client.setnx(lock_key, job_id)
                
                if locked:
                    # Set expiry on lock (30 seconds)
                    await self.redis_client.expire(lock_key, 30)
                    
                    # Update job status
                    await self.redis_client.hset(
                        f"job:{job_id}",
                        mapping={
                            "status": JobStatus.ASSIGNED.value,
                            "assigned_node": node_id,
                            "assigned_at": datetime.utcnow().isoformat()
                        }
                    )
                    
                    # Remove from pending queue
                    queue_key = f"jobs:queue:{self.region}"
                    await self.redis_client.zrem(queue_key, job_id)
                    
                    # Add to node's job queue
                    node_queue = f"node_jobs:{node_id}"
                    await self.redis_client.lpush(node_queue, job_id)
                    
                    # Publish assignment event
                    await self.redis_client.publish(
                        f"job:assigned:{node_id}",
                        json.dumps({
                            "job_id": job_id,
                            "node_id": node_id,
                            "timestamp": time.time()
                        })
                    )
                    
                    logger.info("Job assigned", 
                               job_id=job_id, 
                               node_id=node_id,
                               score=score)
                    break
                    
            except Exception as e:
                logger.error("Failed to assign job", 
                           error=str(e),
                           job_id=job_id,
                           node_id=node_id)
    
    async def run(self):
        """Run the dispatcher"""
        await self.initialize()
        
        # Start dispatch task
        dispatch_task = asyncio.create_task(self.dispatch_jobs())
        
        try:
            await dispatch_task
        except KeyboardInterrupt:
            logger.info("Shutting down dispatcher")
            self.running = False
            self.scheduler.shutdown()
            await self.redis_client.close()

async def main():
    dispatcher = Dispatcher()
    await dispatcher.run()

if __name__ == "__main__":
    asyncio.run(main())

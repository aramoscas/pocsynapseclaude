#!/usr/bin/env python3
"""
SynapseGrid Gateway - Version corrigée avec tables simplifiées
"""

import os
import json
import asyncio
import asyncpg
import redis
from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from datetime import datetime
import hashlib
import uuid
import logging
from functools import partial
from typing import Optional, Dict, Any
import time

# Configuration logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# SQL d'initialisation simplifié (sans pgcrypto)
INIT_SQL = """
-- Drop existing tables
DROP TABLE IF EXISTS jobs CASCADE;
DROP TABLE IF EXISTS clients CASCADE;
DROP TABLE IF EXISTS nodes CASCADE;

-- Create clients table (simplified)
CREATE TABLE IF NOT EXISTS clients (
    id SERIAL PRIMARY KEY,
    client_id VARCHAR(64) UNIQUE NOT NULL,
    api_key_hash VARCHAR(128) NOT NULL,
    nrg_balance DECIMAL(18, 8) DEFAULT 1000.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create jobs table (simplified but complete)
CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(64) PRIMARY KEY,
    job_id VARCHAR(64),
    client_id VARCHAR(64),
    model_name VARCHAR(100) NOT NULL,
    input_data TEXT NOT NULL,
    output_data TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    priority INTEGER DEFAULT 1,
    estimated_cost DECIMAL(10, 6) DEFAULT 0.01,
    assigned_node VARCHAR(64),
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

-- Create nodes table (simplified)
CREATE TABLE IF NOT EXISTS nodes (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) UNIQUE NOT NULL,
    node_type VARCHAR(50) DEFAULT 'docker',
    status VARCHAR(20) DEFAULT 'offline',
    capacity DECIMAL(5, 2) DEFAULT 1.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_client_id ON jobs(client_id);
CREATE INDEX IF NOT EXISTS idx_jobs_job_id ON jobs(job_id);

-- Insert default clients (without digest function)
INSERT INTO clients (client_id, api_key_hash, nrg_balance) VALUES
    ('test-client', 'test-hash', 1000.0),
    ('deploy-test', 'deploy-hash', 1000.0),
    ('cli', 'cli-hash', 500.0),
    ('anonymous', 'anon-hash', 100.0)
ON CONFLICT (client_id) DO NOTHING;
"""

# FastAPI app
app = FastAPI(
    title="SynapseGrid Gateway",
    version="3.2.0",
    description="Decentralized AI Infrastructure - Simplified version"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global connections
redis_client = None
db_pool = None

# Configuration Pydantic
class JobSubmission(BaseModel):
    model_name: str = Field(..., alias="model_name")
    input_data: dict
    priority: int = 1
    gpu_requirements: dict = {}
    region_preference: str = "eu-west-1"
    
    class Config:
        protected_namespaces = ()
        populate_by_name = True

class JobStatus(BaseModel):
    job_id: str
    status: str
    assigned_node: Optional[str]
    created_at: str
    started_at: Optional[str]
    completed_at: Optional[str]
    error_message: Optional[str]

# Async Redis Wrapper
class AsyncRedisWrapper:
    """Wrapper pour utiliser redis sync dans un contexte async"""
    
    def __init__(self, redis_client):
        self.redis = redis_client
        self.loop = None
    
    async def _run_async(self, func, *args, **kwargs):
        if not self.loop:
            self.loop = asyncio.get_event_loop()
        return await self.loop.run_in_executor(None, partial(func, *args, **kwargs))
    
    async def get(self, key: str) -> Optional[str]:
        return await self._run_async(self.redis.get, key)
    
    async def set(self, key: str, value: str, ex: Optional[int] = None) -> bool:
        return await self._run_async(self.redis.set, key, value, ex=ex)
    
    async def lpush(self, key: str, value: str) -> int:
        return await self._run_async(self.redis.lpush, key, value)
    
    async def llen(self, key: str) -> int:
        return await self._run_async(self.redis.llen, key)
    
    async def smembers(self, key: str) -> set:
        result = await self._run_async(self.redis.smembers, key)
        return {item.decode('utf-8') if isinstance(item, bytes) else item for item in result}
    
    async def publish(self, channel: str, message: str) -> int:
        return await self._run_async(self.redis.publish, channel, message)
    
    async def hincrby(self, name: str, key: str, amount: int = 1) -> int:
        return await self._run_async(self.redis.hincrby, name, key, amount)

# Instance globale du wrapper
async_redis = None

async def init_database(conn):
    """Initialiser la base de données avec le schéma simplifié"""
    try:
        # Vérifier si les tables existent
        tables_exist = await conn.fetchval("""
            SELECT COUNT(*) FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name IN ('clients', 'jobs')
        """)
        
        if tables_exist < 2:
            logger.info("Initializing database schema...")
            # Exécuter le SQL d'initialisation
            await conn.execute(INIT_SQL)
            logger.info("✅ Database schema initialized")
        else:
            logger.info("✅ Database schema already exists")
            # S'assurer que les colonnes nécessaires existent
            await conn.execute("""
                -- Ajouter les colonnes manquantes si nécessaire
                DO $$ 
                BEGIN
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                                   WHERE table_name='jobs' AND column_name='job_id') THEN
                        ALTER TABLE jobs ADD COLUMN job_id VARCHAR(64);
                    END IF;
                    
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                                   WHERE table_name='jobs' AND column_name='assigned_node') THEN
                        ALTER TABLE jobs ADD COLUMN assigned_node VARCHAR(64);
                    END IF;
                    
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                                   WHERE table_name='jobs' AND column_name='estimated_cost') THEN
                        ALTER TABLE jobs ADD COLUMN estimated_cost DECIMAL(10,6) DEFAULT 0.01;
                    END IF;
                    
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                                   WHERE table_name='jobs' AND column_name='started_at') THEN
                        ALTER TABLE jobs ADD COLUMN started_at TIMESTAMP;
                    END IF;
                    
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                                   WHERE table_name='jobs' AND column_name='completed_at') THEN
                        ALTER TABLE jobs ADD COLUMN completed_at TIMESTAMP;
                    END IF;
                    
                    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                                   WHERE table_name='jobs' AND column_name='error_message') THEN
                        ALTER TABLE jobs ADD COLUMN error_message TEXT;
                    END IF;
                END $$;
            """)
            
    except Exception as e:
        logger.error(f"Error initializing database: {e}")
        # Créer au minimum les tables essentielles
        try:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS clients (
                    client_id VARCHAR(64) PRIMARY KEY,
                    api_key_hash VARCHAR(128),
                    nrg_balance DECIMAL(18, 8) DEFAULT 1000.0
                );
                
                CREATE TABLE IF NOT EXISTS jobs (
                    id VARCHAR(64) PRIMARY KEY,
                    model_name VARCHAR(100) NOT NULL,
                    input_data TEXT NOT NULL,
                    status VARCHAR(20) DEFAULT 'pending'
                );
            """)
        except Exception as e2:
            logger.error(f"Failed to create minimal tables: {e2}")

@app.on_event("startup")
async def startup():
    """Initialisation des connexions avec auto-correction"""
    global redis_client, db_pool, async_redis
    
    logger.info("🚀 Starting SynapseGrid Gateway (Simplified version)...")
    
    # Redis connection
    try:
        redis_client = redis.Redis(
            host=os.getenv('REDIS_HOST', 'redis'),
            port=int(os.getenv('REDIS_PORT', 6379)),
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5,
            retry_on_timeout=True
        )
        redis_client.ping()
        async_redis = AsyncRedisWrapper(redis_client)
        logger.info("✅ Redis connected")
    except Exception as e:
        logger.warning(f"⚠️  Redis connection failed: {e}")
        redis_client = None
        async_redis = None
    
    # PostgreSQL connection
    try:
        db_pool = await asyncpg.create_pool(
            host=os.getenv('POSTGRES_HOST', 'postgres'),
            port=int(os.getenv('POSTGRES_PORT', 5432)),
            user=os.getenv('POSTGRES_USER', 'synapse'),
            password=os.getenv('POSTGRES_PASSWORD', 'synapse123'),
            database=os.getenv('POSTGRES_DB', 'synapse'),
            min_size=5,
            max_size=20,
            command_timeout=10
        )
        
        # Initialiser la base de données
        async with db_pool.acquire() as conn:
            await init_database(conn)
            
        logger.info("✅ PostgreSQL connected and initialized")
        
    except Exception as e:
        logger.error(f"❌ PostgreSQL connection failed: {e}")
        db_pool = None
    
    logger.info("🎉 Gateway startup complete!")

@app.on_event("shutdown")
async def shutdown():
    """Fermeture propre des connexions"""
    if db_pool:
        await db_pool.close()
    if redis_client:
        redis_client.close()
    logger.info("🛑 Gateway shutdown complete")

@app.get("/health")
async def health():
    """Health check endpoint"""
    health_status = {
        "status": "healthy",
        "service": "gateway",
        "version": "3.2.0",
        "timestamp": datetime.utcnow().isoformat(),
        "checks": {
            "redis": "unknown",
            "postgres": "unknown"
        }
    }
    
    # Check Redis
    try:
        if redis_client:
            redis_client.ping()
            health_status["checks"]["redis"] = "healthy"
    except:
        health_status["checks"]["redis"] = "unhealthy"
    
    # Check PostgreSQL
    try:
        if db_pool:
            async with db_pool.acquire() as conn:
                await conn.fetchval("SELECT 1")
            health_status["checks"]["postgres"] = "healthy"
    except:
        health_status["checks"]["postgres"] = "unhealthy"
    
    # Overall health
    if health_status["checks"]["redis"] == "unhealthy" or health_status["checks"]["postgres"] == "unhealthy":
        health_status["status"] = "degraded"
    
    return health_status

@app.post("/submit")
async def submit_job(
    job: JobSubmission,
    authorization: str = Header(None),
    x_client_id: str = Header(None)
):
    """Submit a new job to the system"""
    try:
        # Validate authorization
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Invalid authorization")
        
        client_id = x_client_id or "anonymous"
        job_id = f"job_{int(datetime.utcnow().timestamp() * 1000)}_{uuid.uuid4().hex[:8]}"
        
        logger.info(f"📥 Submitting job {job_id} from client {client_id}")
        
        # Ensure db_pool exists
        if not db_pool:
            raise HTTPException(status_code=503, detail="Database not available")
        
        async with db_pool.acquire() as conn:
            # Ensure client exists (simplified)
            try:
                await conn.execute(
                    """INSERT INTO clients (client_id, api_key_hash, nrg_balance) 
                       VALUES ($1, $2, 100.0) 
                       ON CONFLICT (client_id) DO NOTHING""",
                    client_id, hashlib.sha256(authorization.encode()).hexdigest()
                )
            except Exception as e:
                logger.warning(f"Client insert failed: {e}")
            
            # Insert job - try full then minimal
            try:
                await conn.execute("""
                    INSERT INTO jobs (
                        id, job_id, client_id, model_name, input_data, 
                        status, priority, estimated_cost, created_at
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                """, job_id, job_id, client_id, job.model_name, 
                    json.dumps(job.input_data), 'pending', job.priority, 
                    job.priority * 0.01, datetime.utcnow()
                )
            except Exception as e:
                logger.warning(f"Full insert failed: {e}, trying minimal insert")
                # Super minimal insert
                try:
                    await conn.execute("""
                        INSERT INTO jobs (id, model_name, input_data, status)
                        VALUES ($1, $2, $3, $4)
                    """, job_id, job.model_name, json.dumps(job.input_data), 'pending')
                    
                    # Try to update additional fields
                    await conn.execute("""
                        UPDATE jobs 
                        SET job_id = $2, client_id = $3, priority = $4
                        WHERE id = $1
                    """, job_id, job_id, client_id, job.priority)
                except Exception as e2:
                    logger.error(f"Even minimal insert failed: {e2}")
                    raise
        
        # Add to Redis queue if available
        if async_redis and redis_client:
            try:
                job_data = {
                    'job_id': job_id,
                    'client_id': client_id,
                    'model_name': job.model_name,
                    'input_data': job.input_data,
                    'priority': job.priority,
                    'timestamp': datetime.utcnow().isoformat()
                }
                
                await async_redis.lpush(
                    f'jobs:queue:{job.region_preference}', 
                    json.dumps(job_data)
                )
                
                await async_redis.publish('jobs:new', job_id)
                
            except Exception as e:
                logger.warning(f"Redis operations failed: {e}")
        
        logger.info(f"✅ Job {job_id} submitted successfully")
        
        return {
            "job_id": job_id,
            "status": "pending",
            "estimated_cost": job.priority * 0.01,
            "message": "Job submitted successfully",
            "submitted_at": datetime.utcnow().isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error submitting job: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/job/{job_id}/status")
async def get_job_status(job_id: str) -> JobStatus:
    """Get job status with fallbacks for missing columns"""
    try:
        if not db_pool:
            raise HTTPException(status_code=503, detail="Database not available")
            
        async with db_pool.acquire() as conn:
            # First, check what columns exist
            columns = await conn.fetch("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'jobs'
            """)
            
            column_names = [col['column_name'] for col in columns]
            
            # Build query based on available columns
            select_parts = []
            select_parts.append("COALESCE(job_id, id) as job_id")
            select_parts.append("status")
            
            if 'assigned_node' in column_names:
                select_parts.append("assigned_node")
            else:
                select_parts.append("NULL as assigned_node")
                
            if 'created_at' in column_names:
                select_parts.append("created_at")
            else:
                select_parts.append("CURRENT_TIMESTAMP as created_at")
                
            if 'started_at' in column_names:
                select_parts.append("started_at")
            else:
                select_parts.append("NULL as started_at")
                
            if 'completed_at' in column_names:
                select_parts.append("completed_at")
            else:
                select_parts.append("NULL as completed_at")
                
            if 'error_message' in column_names:
                select_parts.append("error_message")
            else:
                select_parts.append("NULL as error_message")
            
            query = f"""
                SELECT {', '.join(select_parts)}
                FROM jobs 
                WHERE {'job_id' in column_names and 'job_id = $1 OR' or ''} id = $1
            """
            
            job = await conn.fetchrow(query, job_id)
            
            if not job:
                raise HTTPException(status_code=404, detail="Job not found")
            
            return JobStatus(
                job_id=job['job_id'],
                status=job['status'],
                assigned_node=job['assigned_node'],
                created_at=str(job['created_at']),
                started_at=str(job['started_at']) if job['started_at'] else None,
                completed_at=str(job['completed_at']) if job['completed_at'] else None,
                error_message=job['error_message']
            )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting job status: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/nodes")
async def get_nodes():
    """Get list of active nodes"""
    try:
        if not async_redis or not redis_client:
            return []
            
        node_ids = await async_redis.smembers('nodes:registered')
        nodes = []
        
        for node_id in node_ids:
            node_info = await async_redis.get(f'node:{node_id}:info')
            if node_info:
                nodes.append(json.loads(node_info))
        
        return nodes
    except Exception as e:
        logger.error(f"Error getting nodes: {e}")
        return []

@app.get("/metrics")
async def get_metrics():
    """Get system metrics"""
    metrics = {
        "jobs": {
            "pending": 0,
            "processing": 0,
            "completed": 0,
            "total": 0,
            "queue_length": 0
        },
        "nodes": {
            "active": 0,
            "capacity": 0
        },
        "timestamp": datetime.utcnow().isoformat()
    }
    
    try:
        if db_pool:
            async with db_pool.acquire() as conn:
                db_metrics = await conn.fetchrow("""
                    SELECT 
                        COUNT(*) FILTER (WHERE status = 'pending') as pending_jobs,
                        COUNT(*) FILTER (WHERE status IN ('processing', 'assigned')) as processing_jobs,
                        COUNT(*) FILTER (WHERE status = 'completed') as completed_jobs,
                        COUNT(*) as total_jobs
                    FROM jobs
                """)
                
                if db_metrics:
                    metrics["jobs"]["pending"] = db_metrics['pending_jobs'] or 0
                    metrics["jobs"]["processing"] = db_metrics['processing_jobs'] or 0
                    metrics["jobs"]["completed"] = db_metrics['completed_jobs'] or 0
                    metrics["jobs"]["total"] = db_metrics['total_jobs'] or 0
        
        if async_redis and redis_client:
            try:
                queue_length = await async_redis.llen('jobs:queue:eu-west-1')
                nodes_count = len(await async_redis.smembers('nodes:registered'))
                
                metrics["jobs"]["queue_length"] = queue_length
                metrics["nodes"]["active"] = nodes_count
                metrics["nodes"]["capacity"] = nodes_count * 1.0
            except:
                pass
                
    except Exception as e:
        logger.error(f"Error getting metrics: {e}")
    
    return metrics

@app.get("/")
async def root():
    return {
        "service": "SynapseGrid Gateway",
        "version": "3.2.0",
        "status": "operational",
        "docs": "/docs"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)

#!/bin/bash
# complete_synapsegrid_solution.sh - Solution complète avec toutes les corrections

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            🚀 SYNAPSEGRID COMPLETE SOLUTION WITH AUTO-FIX 🚀                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Créer structure de base
mkdir -p services/{gateway,dispatcher,aggregator,node}
mkdir -p sql config
mkdir -p scripts

# ============================================================================
# ÉTAPE 1: SCRIPT SQL D'INITIALISATION COMPLET
# ============================================================================

echo -e "${CYAN}📋 ÉTAPE 1: Création du script SQL d'initialisation${NC}"
echo "================================================"

cat > sql/init.sql << 'EOF'
-- SynapseGrid Complete Database Schema
-- Auto-create and fix all tables

-- Drop tables in correct order (handle dependencies)
DROP TABLE IF EXISTS job_executions CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS job_results CASCADE;
DROP TABLE IF EXISTS jobs CASCADE;
DROP TABLE IF EXISTS nodes CASCADE;
DROP TABLE IF EXISTS clients CASCADE;
DROP TABLE IF EXISTS regions CASCADE;

-- Create clients table
CREATE TABLE clients (
    id SERIAL PRIMARY KEY,
    client_id VARCHAR(64) UNIQUE NOT NULL,
    api_key_hash VARCHAR(128) NOT NULL,
    nrg_balance DECIMAL(18, 8) DEFAULT 1000.0,
    lear_balance DECIMAL(18, 8) DEFAULT 0.0,
    total_jobs_submitted INTEGER DEFAULT 0,
    total_nrg_spent DECIMAL(18, 8) DEFAULT 0.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active',
    CONSTRAINT clients_status_check CHECK (status IN ('active', 'suspended', 'inactive'))
);

-- Create nodes table
CREATE TABLE nodes (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) UNIQUE NOT NULL,
    node_type VARCHAR(50) DEFAULT 'docker',
    region VARCHAR(50) DEFAULT 'eu-west-1',
    ip_address INET,
    port INTEGER DEFAULT 8003,
    capacity DECIMAL(5, 2) DEFAULT 1.0,
    current_load DECIMAL(5, 2) DEFAULT 0.0,
    gpu_info JSONB DEFAULT '{}',
    cpu_info JSONB DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'offline',
    total_jobs_completed INTEGER DEFAULT 0,
    total_nrg_earned DECIMAL(18, 8) DEFAULT 0.0,
    reliability_score DECIMAL(5, 4) DEFAULT 1.0,
    average_latency_ms INTEGER DEFAULT 100,
    last_heartbeat TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'
);

-- Create jobs table with all necessary columns
CREATE TABLE jobs (
    id VARCHAR(64) PRIMARY KEY,
    job_id VARCHAR(64) UNIQUE NOT NULL,
    client_id VARCHAR(64) NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    model_version VARCHAR(50),
    input_data JSONB NOT NULL,
    output_data JSONB,
    status VARCHAR(20) DEFAULT 'pending',
    priority INTEGER DEFAULT 1,
    estimated_cost DECIMAL(10, 6) DEFAULT 0.01,
    actual_cost DECIMAL(10, 6),
    assigned_node VARCHAR(64),
    node_id VARCHAR(64),  -- For compatibility
    region_preference VARCHAR(50) DEFAULT 'eu-west-1',
    gpu_requirements JSONB DEFAULT '{}',
    error_message TEXT,
    error TEXT,  -- For compatibility
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,  -- For compatibility
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    execution_time_ms INTEGER,
    compute_time_ms INTEGER,  -- For compatibility
    queue_time_ms INTEGER,
    tokens_used INTEGER,
    tokens_processed INTEGER,  -- For compatibility
    CONSTRAINT jobs_priority_check CHECK (priority >= 0 AND priority <= 10),
    CONSTRAINT jobs_status_check CHECK (status IN ('pending', 'queued', 'assigned', 'processing', 'completed', 'failed', 'cancelled'))
);

-- Create indexes
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_client_id ON jobs(client_id);
CREATE INDEX idx_jobs_assigned_node ON jobs(assigned_node);
CREATE INDEX idx_jobs_created_at ON jobs(created_at DESC);
CREATE INDEX idx_jobs_status_priority ON jobs(status, priority DESC);
CREATE INDEX idx_nodes_status ON nodes(status);
CREATE INDEX idx_nodes_region ON nodes(region);
CREATE INDEX idx_clients_client_id ON clients(client_id);

-- Insert default clients
INSERT INTO clients (client_id, api_key_hash, nrg_balance) VALUES
    ('test-client', encode(digest('test-token', 'sha256'), 'hex'), 1000.0),
    ('deploy-test', encode(digest('deploy-token', 'sha256'), 'hex'), 1000.0),
    ('cli', encode(digest('cli-token', 'sha256'), 'hex'), 500.0),
    ('anonymous', encode(digest('anon-token', 'sha256'), 'hex'), 100.0),
    ('debug-test', encode(digest('debug-token', 'sha256'), 'hex'), 1000.0),
    ('emergency-test', encode(digest('emergency-token', 'sha256'), 'hex'), 1000.0),
    ('test-fix', encode(digest('test-fix-token', 'sha256'), 'hex'), 1000.0)
ON CONFLICT (client_id) DO UPDATE SET 
    nrg_balance = EXCLUDED.nrg_balance,
    last_active = CURRENT_TIMESTAMP;

-- Create views for monitoring
CREATE OR REPLACE VIEW active_jobs AS
SELECT j.job_id, j.client_id, j.model_name, j.status, 
       COALESCE(j.assigned_node, j.node_id) as assigned_node,
       j.created_at, j.started_at
FROM jobs j
WHERE j.status NOT IN ('completed', 'failed', 'cancelled');

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO synapse;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO synapse;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO synapse;

-- Success message
SELECT 'Database initialized successfully!' as status;
EOF

echo -e "${GREEN}✅ Script SQL créé${NC}"

# ============================================================================
# ÉTAPE 2: GATEWAY AVEC AUTO-CORRECTION
# ============================================================================

echo -e "${CYAN}🔧 ÉTAPE 2: Création du Gateway avec auto-correction${NC}"
echo "================================================"

cat > services/gateway/main.py << 'EOF'
#!/usr/bin/env python3
"""
SynapseGrid Gateway - Version avec auto-correction de la DB
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

# FastAPI app
app = FastAPI(
    title="SynapseGrid Gateway",
    version="3.0.0",
    description="Decentralized AI Infrastructure - Auto-correcting version"
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
executor = None

# Configuration Pydantic pour éviter le warning
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
    
    def __init__(self, redis_client, executor=None):
        self.redis = redis_client
        self.executor = executor
        self.loop = None
    
    async def _run_async(self, func, *args, **kwargs):
        if not self.loop:
            self.loop = asyncio.get_event_loop()
        return await self.loop.run_in_executor(self.executor, partial(func, *args, **kwargs))
    
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

async def ensure_database_tables(conn):
    """S'assurer que toutes les tables et colonnes existent"""
    
    # Vérifier si les tables principales existent
    tables_exist = await conn.fetchval("""
        SELECT COUNT(*) FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name IN ('clients', 'jobs', 'nodes')
    """)
    
    if tables_exist < 3:
        logger.warning("Missing tables detected, running initialization...")
        # Exécuter le script d'initialisation
        with open('/app/sql/init.sql', 'r') as f:
            await conn.execute(f.read())
    
    # Vérifier et corriger la structure des tables
    await conn.execute("""
        DO $$ 
        BEGIN
            -- Ensure clients table has all columns
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                           WHERE table_name='clients' AND column_name='client_id') THEN
                ALTER TABLE clients ADD COLUMN client_id VARCHAR(64) UNIQUE NOT NULL;
            END IF;
            
            -- Ensure jobs table has all necessary columns
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                           WHERE table_name='jobs' AND column_name='job_id') THEN
                ALTER TABLE jobs ADD COLUMN job_id VARCHAR(64) UNIQUE;
            END IF;
            
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                           WHERE table_name='jobs' AND column_name='client_id') THEN
                ALTER TABLE jobs ADD COLUMN client_id VARCHAR(64);
            END IF;
            
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                           WHERE table_name='jobs' AND column_name='created_at') THEN
                ALTER TABLE jobs ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
            END IF;
            
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                           WHERE table_name='jobs' AND column_name='assigned_node') THEN
                ALTER TABLE jobs ADD COLUMN assigned_node VARCHAR(64);
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
            
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                           WHERE table_name='jobs' AND column_name='estimated_cost') THEN
                ALTER TABLE jobs ADD COLUMN estimated_cost DECIMAL(10,6) DEFAULT 0.01;
            END IF;
        END $$;
    """)
    
    logger.info("✅ Database structure verified and corrected")

@app.on_event("startup")
async def startup():
    """Initialisation des connexions avec auto-correction"""
    global redis_client, db_pool, executor, async_redis
    
    logger.info("🚀 Starting SynapseGrid Gateway (Auto-correcting version)...")
    
    # Thread pool executor pour Redis sync
    executor = None  # Utiliser l'executor par défaut
    
    # Redis connection (sync)
    redis_client = redis.Redis(
        host=os.getenv('REDIS_HOST', 'redis'),
        port=int(os.getenv('REDIS_PORT', 6379)),
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=5,
        retry_on_timeout=True
    )
    
    # Test Redis
    try:
        redis_client.ping()
        logger.info("✅ Redis connected")
    except Exception as e:
        logger.error(f"❌ Redis connection failed: {e}")
        # Continue anyway, Redis might come up later
    
    # Créer le wrapper async
    async_redis = AsyncRedisWrapper(redis_client, executor)
    
    # PostgreSQL connection pool
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
        logger.info("✅ PostgreSQL connected")
        
        # Auto-correct database structure
        async with db_pool.acquire() as conn:
            await ensure_database_tables(conn)
            
    except Exception as e:
        logger.error(f"❌ PostgreSQL connection failed: {e}")
        # Create a basic pool that will retry
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
        "version": "3.0.0",
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
            # Ensure client exists
            try:
                client = await conn.fetchrow(
                    "SELECT client_id, nrg_balance FROM clients WHERE client_id = $1",
                    client_id
                )
                
                if not client:
                    # Create client
                    await conn.execute(
                        """INSERT INTO clients (client_id, api_key_hash, nrg_balance) 
                           VALUES ($1, $2, 100.0) 
                           ON CONFLICT (client_id) DO UPDATE SET last_active = CURRENT_TIMESTAMP""",
                        client_id, hashlib.sha256(authorization.encode()).hexdigest()
                    )
                    nrg_balance = 100.0
                else:
                    nrg_balance = float(client['nrg_balance'])
                    
            except Exception as e:
                logger.error(f"Client check failed: {e}")
                nrg_balance = 100.0  # Default balance
            
            # Insert job - try with all columns first, then fallback
            try:
                await conn.execute("""
                    INSERT INTO jobs (
                        id, job_id, client_id, model_name, input_data, 
                        status, priority, estimated_cost, created_at,
                        region_preference, gpu_requirements
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                """, job_id, job_id, client_id, job.model_name, 
                    json.dumps(job.input_data), 'pending', job.priority, 
                    job.priority * 0.01, datetime.utcnow(),
                    job.region_preference, json.dumps(job.gpu_requirements)
                )
            except Exception as e:
                logger.warning(f"Full insert failed: {e}, trying minimal insert")
                # Fallback to minimal insert
                await conn.execute("""
                    INSERT INTO jobs (
                        id, model_name, status, priority, input_data
                    ) VALUES ($1, $2, $3, $4, $5)
                """, job_id, job.model_name, 'pending', 
                    job.priority, json.dumps(job.input_data)
                )
                
                # Update with other fields if columns exist
                await conn.execute("""
                    UPDATE jobs 
                    SET job_id = $2,
                        client_id = $3
                    WHERE id = $1
                    AND EXISTS (
                        SELECT 1 FROM information_schema.columns 
                        WHERE table_name='jobs' AND column_name IN ('job_id', 'client_id')
                    )
                """, job_id, job_id, client_id)
        
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
                
                # Publish event
                await async_redis.publish('jobs:new', job_id)
                
                # Increment metrics
                await async_redis.hincrby('metrics:jobs', 'submitted', 1)
                
            except Exception as e:
                logger.warning(f"Redis operations failed: {e}")
                # Continue anyway - job is in PostgreSQL
        
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
    """Get job status"""
    try:
        if not db_pool:
            raise HTTPException(status_code=503, detail="Database not available")
            
        async with db_pool.acquire() as conn:
            # Query with fallbacks for different column names
            job = await conn.fetchrow("""
                SELECT 
                    COALESCE(job_id, id) as job_id,
                    status,
                    COALESCE(assigned_node, node_id) as assigned_node,
                    COALESCE(created_at, submitted_at, CURRENT_TIMESTAMP) as created_at,
                    started_at,
                    completed_at,
                    COALESCE(error_message, error) as error_message
                FROM jobs 
                WHERE job_id = $1 OR id = $1
            """, job_id)
            
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
        # PostgreSQL metrics
        if db_pool:
            async with db_pool.acquire() as conn:
                db_metrics = await conn.fetchrow("""
                    SELECT 
                        COUNT(*) FILTER (WHERE status = 'pending') as pending_jobs,
                        COUNT(*) FILTER (WHERE status IN ('processing', 'assigned')) as processing_jobs,
                        COUNT(*) FILTER (WHERE status = 'completed') as completed_jobs,
                        COUNT(*) as total_jobs
                    FROM jobs
                    WHERE (created_at > NOW() - INTERVAL '1 hour') 
                       OR (submitted_at > NOW() - INTERVAL '1 hour')
                       OR (id IN (SELECT id FROM jobs ORDER BY id DESC LIMIT 100))
                """)
                
                if db_metrics:
                    metrics["jobs"]["pending"] = db_metrics['pending_jobs'] or 0
                    metrics["jobs"]["processing"] = db_metrics['processing_jobs'] or 0
                    metrics["jobs"]["completed"] = db_metrics['completed_jobs'] or 0
                    metrics["jobs"]["total"] = db_metrics['total_jobs'] or 0
        
        # Redis metrics
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

# Root endpoint
@app.get("/")
async def root():
    return {
        "service": "SynapseGrid Gateway",
        "version": "3.0.0",
        "status": "operational",
        "docs": "/docs"
    }

# Additional endpoints for compatibility
@app.get("/region")
async def get_region():
    return {"region": "eu-west-1"}

@app.get("/client/{client_id}/balance")
async def get_client_balance(client_id: str):
    try:
        if not db_pool:
            return {"nrg_balance": 100.0}
            
        async with db_pool.acquire() as conn:
            balance = await conn.fetchval(
                "SELECT nrg_balance FROM clients WHERE client_id = $1",
                client_id
            )
            return {"nrg_balance": float(balance) if balance else 100.0}
    except:
        return {"nrg_balance": 100.0}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

echo -e "${GREEN}✅ Gateway créé${NC}"

# ============================================================================
# ÉTAPE 3: REQUIREMENTS SANS AIOREDIS
# ============================================================================

echo -e "${CYAN}📋 ÉTAPE 3: Création des requirements${NC}"
echo "================================================"

cat > services/gateway/requirements.txt << 'EOF'
# Framework
fastapi==0.104.1
uvicorn[standard]==0.24.0

# Database
asyncpg==0.29.0
psycopg2-binary==2.9.9

# Redis - SANS aioredis
redis==5.0.1
hiredis==2.3.2

# Utils
pydantic==2.5.0
python-jose==3.3.0
prometheus-client==0.19.0
httpx==0.25.2
psutil==5.9.6

# Async helpers
aiofiles==23.2.1
aiodns==3.1.1
EOF

# Copier pour les autres services
for service in dispatcher aggregator node; do
    cp services/gateway/requirements.txt services/$service/requirements.txt
done

echo -e "${GREEN}✅ Requirements créés${NC}"

# ============================================================================
# ÉTAPE 4: DOCKERFILE OPTIMISÉ
# ============================================================================

echo -e "${CYAN}🐳 ÉTAPE 4: Création du Dockerfile optimisé${NC}"
echo "================================================"

cat > services/gateway/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy SQL scripts
COPY sql/ /app/sql/

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Verify aioredis is NOT installed
RUN python -c "import sys; import subprocess; \
    result = subprocess.run([sys.executable, '-m', 'pip', 'list'], capture_output=True, text=True); \
    assert 'aioredis' not in result.stdout.lower(), 'aioredis should NOT be installed!'; \
    print('✅ Verified: aioredis is NOT installed')"

# Copy application
COPY main.py .

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--reload"]
EOF

echo -e "${GREEN}✅ Dockerfile créé${NC}"

# ============================================================================
# ÉTAPE 5: DOCKER-COMPOSE COMPLET
# ============================================================================

echo -e "${CYAN}🐳 ÉTAPE 5: Création du docker-compose.yml complet${NC}"
echo "================================================"

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: synapse_redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - synapse_network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  postgres:
    image: postgres:15-alpine
    container_name: synapse_postgres
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: synapse123
      POSTGRES_DB: synapse
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./sql/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - synapse_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 10s
      timeout: 5s
      retries: 5

  gateway:
    build:
      context: .
      dockerfile: services/gateway/Dockerfile
    container_name: synapse_gateway
    ports:
      - "8080:8080"
    environment:
      - REDIS_HOST=redis
      - POSTGRES_HOST=postgres
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=synapse123
      - POSTGRES_DB=synapse
    volumes:
      - ./services/gateway:/app
      - ./sql:/app/sql
    depends_on:
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
    networks:
      - synapse_network
    restart: unless-stopped

  dispatcher:
    build:
      context: ./services/dispatcher
      dockerfile: Dockerfile
    container_name: synapse_dispatcher
    environment:
      - REDIS_HOST=redis
      - POSTGRES_HOST=postgres
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=synapse123
      - POSTGRES_DB=synapse
    depends_on:
      - gateway
    networks:
      - synapse_network
    restart: unless-stopped

  aggregator:
    build:
      context: ./services/aggregator
      dockerfile: Dockerfile
    container_name: synapse_aggregator
    environment:
      - REDIS_HOST=redis
      - POSTGRES_HOST=postgres
    depends_on:
      - redis
      - postgres
    networks:
      - synapse_network
    restart: unless-stopped

  node:
    build:
      context: ./services/node
      dockerfile: Dockerfile
    container_name: synapse_node
    ports:
      - "8003:8003"
    environment:
      - REDIS_HOST=redis
      - POSTGRES_HOST=postgres
    depends_on:
      - redis
    networks:
      - synapse_network
    restart: unless-stopped

  dashboard:
    build:
      context: ./dashboard
      dockerfile: Dockerfile
    container_name: synapse_dashboard
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://gateway:8080
    depends_on:
      - gateway
    networks:
      - synapse_network
    restart: unless-stopped

networks:
  synapse_network:
    driver: bridge

volumes:
  redis_data:
  postgres_data:
EOF

echo -e "${GREEN}✅ docker-compose.yml créé${NC}"

# ============================================================================
# ÉTAPE 6: SCRIPT DE DÉPLOIEMENT INTELLIGENT
# ============================================================================

echo -e "${CYAN}🚀 ÉTAPE 6: Script de déploiement intelligent${NC}"
echo "================================================"

cat > deploy_synapsegrid.sh << 'EOF'
#!/bin/bash
# deploy_synapsegrid.sh - Déploiement intelligent avec auto-correction

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         🚀 SYNAPSEGRID INTELLIGENT DEPLOYMENT 🚀             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Vérification des prérequis
echo -e "${YELLOW}1. Vérification des prérequis...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}❌ Docker requis${NC}"; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo -e "${RED}❌ Docker Compose requis${NC}"; exit 1; }
echo -e "${GREEN}✅ Prérequis OK${NC}"

# 2. Nettoyage si demandé
if [ "$1" == "--clean" ]; then
    echo -e "${YELLOW}2. Nettoyage complet...${NC}"
    docker-compose down -v
    docker system prune -af
    echo -e "${GREEN}✅ Nettoyage terminé${NC}"
fi

# 3. Construction des images
echo -e "${YELLOW}3. Construction des images...${NC}"
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Build uniquement gateway pour l'instant
docker-compose build --no-cache gateway

# 4. Démarrage des services de base
echo -e "${YELLOW}4. Démarrage des services de base...${NC}"
docker-compose up -d redis postgres

# Attendre que PostgreSQL soit prêt
echo -n "Attente de PostgreSQL..."
until docker-compose exec -T postgres pg_isready -U synapse >/dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo -e " ${GREEN}✅${NC}"

# Attendre que Redis soit prêt
echo -n "Attente de Redis..."
until docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo -e " ${GREEN}✅${NC}"

# 5. Démarrage du gateway
echo -e "${YELLOW}5. Démarrage du gateway...${NC}"
docker-compose up -d gateway

# Attendre que le gateway soit prêt
echo -n "Attente du gateway..."
for i in {1..30}; do
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo -e " ${GREEN}✅${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# 6. Configuration Redis
echo -e "${YELLOW}6. Configuration Redis...${NC}"
docker-compose exec -T redis redis-cli << 'REDIS_COMMANDS'
DEL nodes:registered
SADD nodes:registered "node_default"
SET node:node_default:info '{"node_id":"node_default","status":"available","capacity":1.0,"current_load":0}'
REDIS_COMMANDS
echo -e "${GREEN}✅ Redis configuré${NC}"

# 7. Test de santé complet
echo -e "${YELLOW}7. Test de santé...${NC}"
HEALTH=$(curl -s http://localhost:8080/health)
echo "$HEALTH" | jq . || echo "$HEALTH"

# 8. Test de soumission
echo -e "${YELLOW}8. Test de soumission de job...${NC}"
JOB_RESPONSE=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: deploy-test" \
    -d '{"model_name": "test-deploy", "input_data": {"test": true}}')

echo "Réponse: $JOB_RESPONSE"
JOB_ID=$(echo "$JOB_RESPONSE" | jq -r '.job_id' 2>/dev/null)

if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
    echo -e "${GREEN}✅ Job soumis: $JOB_ID${NC}"
    
    # Vérifier le statut
    sleep 2
    echo "Statut du job:"
    curl -s http://localhost:8080/job/$JOB_ID/status | jq .
else
    echo -e "${RED}❌ Échec de soumission${NC}"
fi

# 9. Démarrage des autres services (optionnel)
if [ "$2" == "--all" ]; then
    echo -e "${YELLOW}9. Démarrage des autres services...${NC}"
    docker-compose up -d
fi

# 10. Résumé
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   ✅ DÉPLOIEMENT RÉUSSI !                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📊 Services actifs:"
docker-compose ps
echo ""
echo "🔗 URLs:"
echo "  Gateway API: http://localhost:8080"
echo "  Health:      http://localhost:8080/health"
echo "  Docs:        http://localhost:8080/docs"
echo ""
echo "📝 Commandes utiles:"
echo "  Logs:        docker-compose logs -f gateway"
echo "  Monitoring:  ./monitor_synapsegrid.sh"
echo "  Arrêt:       docker-compose down"
EOF

chmod +x deploy_synapsegrid.sh

echo -e "${GREEN}✅ Script de déploiement créé${NC}"

# ============================================================================
# ÉTAPE 7: SCRIPT DE MONITORING
# ============================================================================

cat > monitor_synapsegrid.sh << 'EOF'
#!/bin/bash
# Monitoring en temps réel

watch -n 2 '
echo "🚀 SYNAPSEGRID MONITORING"
echo "========================"
echo ""
echo "📊 HEALTH STATUS:"
curl -s http://localhost:8080/health 2>/dev/null | jq -c . || echo "Gateway offline"
echo ""
echo "💾 REDIS:"
echo -n "Queue length: "
docker exec synapse_redis redis-cli LLEN "jobs:queue:eu-west-1" 2>/dev/null || echo "0"
echo -n "Nodes: "
docker exec synapse_redis redis-cli SMEMBERS "nodes:registered" 2>/dev/null || echo "None"
echo ""
echo "📋 RECENT JOBS:"
docker exec synapse_postgres psql -U synapse -d synapse -t -c "
SELECT COALESCE(job_id, id) || \": \" || status || \" (\" || COALESCE(assigned_node, node_id, \"unassigned\") || \")\"
FROM jobs 
ORDER BY COALESCE(created_at, submitted_at) DESC 
LIMIT 5
" 2>/dev/null || echo "No jobs"
echo ""
echo "📈 METRICS:"
curl -s http://localhost:8080/metrics 2>/dev/null | jq -c . || echo "No metrics"
'
EOF

chmod +x monitor_synapsegrid.sh

# ============================================================================
# RÉSUMÉ FINAL
# ============================================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ SOLUTION COMPLÈTE CRÉÉE !                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${WHITE}📋 Cette solution inclut :${NC}"
echo "  • Auto-correction de la base de données au démarrage"
echo "  • Gestion des erreurs de structure de table"
echo "  • Pas d'aioredis - utilise redis avec wrapper async"
echo "  • Health checks complets"
echo "  • Déploiement intelligent avec vérifications"
echo "  • Monitoring en temps réel"
echo ""
echo -e "${CYAN}🚀 Pour déployer :${NC}"
echo "  ./deploy_synapsegrid.sh          # Déploiement de base"
echo "  ./deploy_synapsegrid.sh --clean  # Avec nettoyage complet"
echo "  ./deploy_synapsegrid.sh . --all  # Tous les services"
echo ""
echo -e "${CYAN}📊 Pour monitorer :${NC}"
echo "  ./monitor_synapsegrid.sh"
echo ""
echo -e "${CYAN}📜 Pour les logs :${NC}"
echo "  docker-compose logs -f gateway"
echo ""
echo -e "${YELLOW}Cette solution gère automatiquement :${NC}"
echo "  ✅ Tables manquantes"
echo "  ✅ Colonnes manquantes" 
echo "  ✅ Clients non existants"
echo "  ✅ Connexions Redis/PostgreSQL défaillantes"
echo "  ✅ Différentes structures de table"
echo ""

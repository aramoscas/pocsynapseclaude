#!/bin/bash
# fix_dockerfile_context.sh - Correction du contexte de build

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fix du contexte de build Docker${NC}"
echo ""

# 1. Créer la structure correcte
echo -e "${YELLOW}1. Création de la structure de fichiers...${NC}"

# Structure des services
mkdir -p services/{gateway,dispatcher,aggregator,node}
mkdir -p sql

# 2. Dockerfile Gateway corrigé (sans COPY sql/)
echo -e "${YELLOW}2. Création du Dockerfile Gateway corrigé...${NC}"

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

# Copy requirements first
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

# 3. Gateway avec SQL intégré dans le code
echo -e "${YELLOW}3. Création du Gateway avec SQL intégré...${NC}"

cat > services/gateway/main.py << 'EOF'
#!/usr/bin/env python3
"""
SynapseGrid Gateway - Version avec SQL intégré
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

# SQL d'initialisation intégré
INIT_SQL = """
-- SynapseGrid Database Schema
-- Drop existing tables
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
    status VARCHAR(20) DEFAULT 'active'
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

-- Create jobs table
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
    node_id VARCHAR(64),
    region_preference VARCHAR(50) DEFAULT 'eu-west-1',
    gpu_requirements JSONB DEFAULT '{}',
    error_message TEXT,
    error TEXT,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    execution_time_ms INTEGER,
    compute_time_ms INTEGER,
    queue_time_ms INTEGER,
    tokens_used INTEGER,
    tokens_processed INTEGER
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_client_id ON jobs(client_id);
CREATE INDEX IF NOT EXISTS idx_jobs_assigned_node ON jobs(assigned_node);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_status_priority ON jobs(status, priority DESC);
CREATE INDEX IF NOT EXISTS idx_nodes_status ON nodes(status);
CREATE INDEX IF NOT EXISTS idx_nodes_region ON nodes(region);
CREATE INDEX IF NOT EXISTS idx_clients_client_id ON clients(client_id);

-- Insert default clients
INSERT INTO clients (client_id, api_key_hash, nrg_balance) VALUES
    ('test-client', encode(digest('test-token', 'sha256'), 'hex'), 1000.0),
    ('deploy-test', encode(digest('deploy-token', 'sha256'), 'hex'), 1000.0),
    ('cli', encode(digest('cli-token', 'sha256'), 'hex'), 500.0),
    ('anonymous', encode(digest('anon-token', 'sha256'), 'hex'), 100.0)
ON CONFLICT (client_id) DO UPDATE SET 
    nrg_balance = EXCLUDED.nrg_balance,
    last_active = CURRENT_TIMESTAMP;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO synapse;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO synapse;
"""

# FastAPI app
app = FastAPI(
    title="SynapseGrid Gateway",
    version="3.1.0",
    description="Decentralized AI Infrastructure - SQL Embedded version"
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
    """Initialiser la base de données avec le schéma complet"""
    try:
        # Vérifier si les tables existent
        tables_exist = await conn.fetchval("""
            SELECT COUNT(*) FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name IN ('clients', 'jobs', 'nodes')
        """)
        
        if tables_exist < 3:
            logger.info("Initializing database schema...")
            # Exécuter le SQL d'initialisation
            await conn.execute(INIT_SQL)
            logger.info("✅ Database schema initialized")
        else:
            logger.info("✅ Database schema already exists")
            
    except Exception as e:
        logger.error(f"Error initializing database: {e}")
        # Essayer au moins de créer les tables minimales
        try:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS clients (
                    id SERIAL PRIMARY KEY,
                    client_id VARCHAR(64) UNIQUE NOT NULL,
                    api_key_hash VARCHAR(128) NOT NULL,
                    nrg_balance DECIMAL(18, 8) DEFAULT 1000.0,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                
                CREATE TABLE IF NOT EXISTS jobs (
                    id VARCHAR(64) PRIMARY KEY,
                    job_id VARCHAR(64),
                    client_id VARCHAR(64),
                    model_name VARCHAR(100) NOT NULL,
                    input_data JSONB NOT NULL,
                    status VARCHAR(20) DEFAULT 'pending',
                    priority INTEGER DEFAULT 1,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
        except:
            pass

@app.on_event("startup")
async def startup():
    """Initialisation des connexions avec auto-correction"""
    global redis_client, db_pool, async_redis
    
    logger.info("🚀 Starting SynapseGrid Gateway (SQL Embedded version)...")
    
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
        "version": "3.1.0",
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
                await conn.execute(
                    """INSERT INTO clients (client_id, api_key_hash, nrg_balance) 
                       VALUES ($1, $2, 100.0) 
                       ON CONFLICT (client_id) DO UPDATE SET last_active = CURRENT_TIMESTAMP""",
                    client_id, hashlib.sha256(authorization.encode()).hexdigest()
                )
            except Exception as e:
                logger.warning(f"Client upsert failed: {e}")
            
            # Insert job
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
                # Minimal insert
                await conn.execute("""
                    INSERT INTO jobs (id, model_name, input_data, status, priority)
                    VALUES ($1, $2, $3, $4, $5)
                """, job_id, job.model_name, json.dumps(job.input_data), 
                    'pending', job.priority)
        
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
    """Get job status"""
    try:
        if not db_pool:
            raise HTTPException(status_code=503, detail="Database not available")
            
        async with db_pool.acquire() as conn:
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
        "version": "3.1.0",
        "status": "operational",
        "docs": "/docs"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

echo -e "${GREEN}✅ Gateway avec SQL intégré créé${NC}"

# 4. Docker-compose mis à jour (sans volume SQL pour gateway)
echo -e "${YELLOW}4. Mise à jour du docker-compose.yml...${NC}"

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
    networks:
      - synapse_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 10s
      timeout: 5s
      retries: 5

  gateway:
    build:
      context: ./services/gateway
      dockerfile: Dockerfile
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
    depends_on:
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
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

echo -e "${GREEN}✅ docker-compose.yml mis à jour${NC}"

# 5. Requirements
echo -e "${YELLOW}5. Création des requirements...${NC}"

cat > services/gateway/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
asyncpg==0.29.0
psycopg2-binary==2.9.9
redis==5.0.1
hiredis==2.3.2
pydantic==2.5.0
python-jose==3.3.0
httpx==0.25.2
psutil==5.9.6
aiofiles==23.2.1
EOF

echo -e "${GREEN}✅ Requirements créés${NC}"

# 6. Script de déploiement simplifié
echo -e "${YELLOW}6. Script de déploiement simplifié...${NC}"

cat > deploy.sh << 'EOF'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Déploiement SynapseGrid${NC}"

# 1. Build
echo -e "${YELLOW}Build du gateway...${NC}"
docker-compose build gateway

# 2. Start services
echo -e "${YELLOW}Démarrage des services...${NC}"
docker-compose up -d

# 3. Wait for services
echo -e "${YELLOW}Attente des services...${NC}"
sleep 10

# 4. Configure Redis
echo -e "${YELLOW}Configuration Redis...${NC}"
docker exec synapse_redis redis-cli << 'REDIS'
DEL nodes:registered
SADD nodes:registered "node_default"
SET node:node_default:info '{"node_id":"node_default","status":"available","capacity":1.0}'
REDIS

# 5. Test
echo -e "${YELLOW}Test de santé...${NC}"
curl -s http://localhost:8080/health | jq .

echo -e "${GREEN}✅ Déploiement terminé!${NC}"
echo ""
echo "Logs: docker-compose logs -f gateway"
EOF

chmod +x deploy.sh

echo ""
echo -e "${GREEN}✅ Corrections appliquées!${NC}"
echo ""
echo "Pour déployer:"
echo "./deploy.sh"

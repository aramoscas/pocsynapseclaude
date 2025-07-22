#!/bin/bash
# clean_synapsegrid_solution.sh - Solution propre et complète

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
echo -e "${BLUE}║               🚀 SYNAPSEGRID CLEAN SOLUTION - NO AIOREDIS 🚀                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Créer un backup
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR
echo -e "${YELLOW}📦 Backup créé dans: $BACKUP_DIR${NC}"

# ============================================================================
# ÉTAPE 1: REQUIREMENTS PROPRES (SANS AIOREDIS)
# ============================================================================

echo -e "${CYAN}📋 ÉTAPE 1: Création des requirements propres${NC}"
echo "================================================"

# Requirements pour tous les services Python
cat > services/requirements_base.txt << 'EOF'
# Framework
fastapi==0.104.1
uvicorn[standard]==0.24.0

# Database
asyncpg==0.29.0
psycopg2-binary==2.9.9

# Redis - PAS aioredis!
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

# Copier dans chaque service
for service in gateway dispatcher aggregator node; do
    cp services/requirements_base.txt services/$service/requirements.txt
done

echo -e "${GREEN}✅ Requirements créés (SANS aioredis)${NC}"

# ============================================================================
# ÉTAPE 2: GATEWAY PROPRE AVEC ASYNC REDIS WRAPPER
# ============================================================================

echo -e "${CYAN}🔧 ÉTAPE 2: Création du Gateway propre${NC}"
echo "================================================"

cat > services/gateway/main.py << 'EOF'
#!/usr/bin/env python3
"""
SynapseGrid Gateway - Version propre sans aioredis
Utilise redis standard avec wrapper async
"""

import os
import json
import asyncio
import asyncpg
import redis
from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
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
    version="2.0.0",
    description="Decentralized AI Infrastructure - NO aioredis version"
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

# Pydantic models
class JobSubmission(BaseModel):
    model_name: str
    input_data: dict
    priority: int = 1
    gpu_requirements: dict = {}
    region_preference: str = "eu-west-1"

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
    
    def __init__(self, redis_client, executor):
        self.redis = redis_client
        self.executor = executor
    
    async def get(self, key: str) -> Optional[str]:
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, self.redis.get, key
        )
    
    async def set(self, key: str, value: str, ex: Optional[int] = None) -> bool:
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, partial(self.redis.set, key, value, ex=ex)
        )
    
    async def lpush(self, key: str, value: str) -> int:
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, self.redis.lpush, key, value
        )
    
    async def llen(self, key: str) -> int:
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, self.redis.llen, key
        )
    
    async def smembers(self, key: str) -> set:
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, self.redis.smembers, key
        )
    
    async def publish(self, channel: str, message: str) -> int:
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, self.redis.publish, channel, message
        )
    
    async def hincrby(self, name: str, key: str, amount: int = 1) -> int:
        return await asyncio.get_event_loop().run_in_executor(
            self.executor, self.redis.hincrby, name, key, amount
        )

# Instance globale du wrapper
async_redis = None

@app.on_event("startup")
async def startup():
    """Initialisation des connexions"""
    global redis_client, db_pool, executor, async_redis
    
    logger.info("🚀 Starting SynapseGrid Gateway (NO aioredis version)...")
    
    # Thread pool executor pour Redis sync
    executor = asyncio.get_event_loop().run_in_executor
    
    # Redis connection (sync)
    redis_client = redis.Redis(
        host=os.getenv('REDIS_HOST', 'redis'),
        port=int(os.getenv('REDIS_PORT', 6379)),
        decode_responses=True
    )
    
    # Test Redis
    redis_client.ping()
    logger.info("✅ Redis connected (sync client with async wrapper)")
    
    # Créer le wrapper async
    async_redis = AsyncRedisWrapper(redis_client, None)
    
    # PostgreSQL connection pool
    db_pool = await asyncpg.create_pool(
        host=os.getenv('POSTGRES_HOST', 'postgres'),
        port=int(os.getenv('POSTGRES_PORT', 5432)),
        user=os.getenv('POSTGRES_USER', 'synapse'),
        password=os.getenv('POSTGRES_PASSWORD', 'synapse123'),
        database=os.getenv('POSTGRES_DB', 'synapse'),
        min_size=10,
        max_size=20
    )
    logger.info("✅ PostgreSQL connected and initialized")
    
    # Ensure database schema
    await ensure_database_schema()
    
    logger.info("🎉 Gateway startup complete - NO aioredis!")

@app.on_event("shutdown")
async def shutdown():
    """Fermeture propre des connexions"""
    if db_pool:
        await db_pool.close()
    if redis_client:
        redis_client.close()
    logger.info("🛑 Gateway shutdown complete")

async def ensure_database_schema():
    """S'assurer que le schéma de base de données est correct"""
    async with db_pool.acquire() as conn:
        # Vérifier et corriger la structure de la table jobs
        await conn.execute("""
            DO $$ 
            BEGIN
                -- Ajouter les colonnes manquantes si nécessaire
                IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                               WHERE table_name='jobs' AND column_name='job_id') THEN
                    ALTER TABLE jobs ADD COLUMN job_id VARCHAR(64) UNIQUE;
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
                               WHERE table_name='jobs' AND column_name='estimated_cost') THEN
                    ALTER TABLE jobs ADD COLUMN estimated_cost DECIMAL(10,6) DEFAULT 0.01;
                END IF;
            END $$;
        """)

@app.get("/health")
async def health():
    """Health check endpoint"""
    try:
        # Test Redis
        await async_redis.set("health_check", str(time.time()), ex=10)
        
        # Test PostgreSQL
        async with db_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        
        return {
            "status": "healthy",
            "service": "gateway",
            "version": "2.0.0",
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=503, detail="Service unhealthy")

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
        
        async with db_pool.acquire() as conn:
            # Vérifier/créer le client
            client = await conn.fetchrow(
                "SELECT client_id FROM clients WHERE client_id = $1",
                client_id
            )
            
            if not client:
                await conn.execute(
                    """INSERT INTO clients (client_id, api_key_hash, nrg_balance) 
                       VALUES ($1, $2, 100.0) 
                       ON CONFLICT (client_id) DO NOTHING""",
                    client_id, hashlib.sha256(authorization.encode()).hexdigest()
                )
            
            # Insérer le job
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
                logger.warning(f"PostgreSQL insert failed: {e}")
                # Fallback: utiliser seulement les colonnes qui existent
                await conn.execute("""
                    INSERT INTO jobs (
                        id, model_name, client_id, status, priority, input_data
                    ) VALUES ($1, $2, $3, $4, $5, $6)
                """, job_id, job.model_name, client_id, 'pending', 
                    job.priority, json.dumps(job.input_data)
                )
        
        # Ajouter à la queue Redis
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
        
        # Publier l'événement
        await async_redis.publish('jobs:new', job_id)
        
        # Incrémenter les métriques
        await async_redis.hincrby('metrics:jobs', 'submitted', 1)
        
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
        async with db_pool.acquire() as conn:
            # Essayer d'abord avec job_id
            job = await conn.fetchrow("""
                SELECT job_id, status, assigned_node, created_at, 
                       started_at, completed_at, error_message
                FROM jobs 
                WHERE job_id = $1 OR id = $1
            """, job_id)
            
            if not job:
                raise HTTPException(status_code=404, detail="Job not found")
            
            # Gérer les colonnes qui peuvent ne pas exister
            return JobStatus(
                job_id=job.get('job_id', job_id),
                status=job['status'],
                assigned_node=job.get('assigned_node') or job.get('node_id'),
                created_at=str(job.get('created_at') or job.get('submitted_at', '')),
                started_at=str(job.get('started_at', '') or ''),
                completed_at=str(job.get('completed_at', '') or ''),
                error_message=job.get('error_message')
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
        node_ids = await async_redis.smembers('nodes:registered')
        nodes = []
        
        for node_id in node_ids:
            if isinstance(node_id, bytes):
                node_id = node_id.decode('utf-8')
            
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
    try:
        # Métriques PostgreSQL
        async with db_pool.acquire() as conn:
            metrics = await conn.fetchrow("""
                SELECT 
                    COUNT(*) FILTER (WHERE status = 'pending') as pending_jobs,
                    COUNT(*) FILTER (WHERE status = 'processing') as processing_jobs,
                    COUNT(*) FILTER (WHERE status = 'completed') as completed_jobs,
                    COUNT(*) as total_jobs
                FROM jobs
                WHERE (created_at > NOW() - INTERVAL '1 hour') 
                   OR (submitted_at > NOW() - INTERVAL '1 hour')
            """)
        
        # Métriques Redis
        queue_length = await async_redis.llen('jobs:queue:eu-west-1')
        nodes_count = len(await async_redis.smembers('nodes:registered'))
        
        return {
            "jobs": {
                "pending": metrics['pending_jobs'] or 0,
                "processing": metrics['processing_jobs'] or 0,
                "completed": metrics['completed_jobs'] or 0,
                "total": metrics['total_jobs'] or 0,
                "queue_length": queue_length
            },
            "nodes": {
                "active": nodes_count,
                "capacity": nodes_count * 1.0
            },
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Error getting metrics: {e}")
        return {"error": str(e)}

# Routes additionnelles pour la compatibilité
@app.get("/")
async def root():
    return {
        "service": "SynapseGrid Gateway",
        "version": "2.0.0",
        "status": "operational"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

echo -e "${GREEN}✅ Gateway créé (avec wrapper async pour Redis)${NC}"

# ============================================================================
# ÉTAPE 3: DISPATCHER PROPRE AVEC ASYNC
# ============================================================================

echo -e "${CYAN}🔧 ÉTAPE 3: Création du Dispatcher propre${NC}"
echo "================================================"

cat > services/dispatcher/main.py << 'EOF'
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
EOF

echo -e "${GREEN}✅ Dispatcher créé${NC}"

# ============================================================================
# ÉTAPE 4: DOCKERFILES PROPRES
# ============================================================================

echo -e "${CYAN}🐳 ÉTAPE 4: Création des Dockerfiles propres${NC}"
echo "================================================"

# Dockerfile pour Gateway
cat > services/gateway/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies - SANS aioredis
RUN pip install --no-cache-dir -r requirements.txt

# Verify aioredis is NOT installed
RUN python -c "import pkg_resources; installed = [pkg.key for pkg in pkg_resources.working_set]; assert 'aioredis' not in installed, 'aioredis should NOT be installed!'"

# Copy application
COPY main.py .

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8080/health').raise_for_status()"

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
EOF

# Dockerfile pour Dispatcher
cat > services/dispatcher/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies - SANS aioredis
RUN pip install --no-cache-dir -r requirements.txt

# Verify aioredis is NOT installed
RUN python -c "import pkg_resources; installed = [pkg.key for pkg in pkg_resources.working_set]; assert 'aioredis' not in installed, 'aioredis should NOT be installed!'"

# Copy application
COPY main.py .

CMD ["python", "main.py"]
EOF

echo -e "${GREEN}✅ Dockerfiles créés${NC}"

# ============================================================================
# ÉTAPE 5: DOCKER-COMPOSE PROPRE
# ============================================================================

echo -e "${CYAN}🐳 ÉTAPE 5: Mise à jour du docker-compose.yml${NC}"
echo "================================================"

# Backup du docker-compose existant
cp docker-compose.yml $BACKUP_DIR/docker-compose.yml.backup

# Ajouter les health checks et les dépendances
cat > docker-compose.override.yml << 'EOF'
version: '3.8'

services:
  gateway:
    build:
      context: ./services/gateway
      dockerfile: Dockerfile
      args:
        - BUILDKIT_INLINE_CACHE=1
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    environment:
      - REDIS_HOST=redis
      - POSTGRES_HOST=postgres
    depends_on:
      redis:
        condition: service_started
      postgres:
        condition: service_healthy

  dispatcher:
    build:
      context: ./services/dispatcher
      dockerfile: Dockerfile
      args:
        - BUILDKIT_INLINE_CACHE=1
    environment:
      - REDIS_HOST=redis
      - POSTGRES_HOST=postgres
    depends_on:
      redis:
        condition: service_started
      postgres:
        condition: service_healthy
      gateway:
        condition: service_healthy

  postgres:
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF

echo -e "${GREEN}✅ Docker-compose override créé${NC}"

# ============================================================================
# ÉTAPE 6: SCRIPT DE BUILD ET DÉPLOIEMENT
# ============================================================================

echo -e "${CYAN}🚀 ÉTAPE 6: Script de déploiement${NC}"
echo "================================================"

cat > deploy_clean.sh << 'EOF'
#!/bin/bash
# Script de déploiement propre

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🔨 Build des images (sans cache)...${NC}"

# Build avec --no-cache pour éviter les problèmes de cache
docker-compose build --no-cache --pull gateway dispatcher

echo -e "${YELLOW}🔍 Vérification des images...${NC}"

# Vérifier qu'aioredis n'est PAS dans les images
for service in gateway dispatcher; do
    echo -n "Checking $service: "
    docker run --rm synapse_$service pip list | grep -i aioredis && \
        echo -e "${RED}❌ aioredis found!${NC}" || \
        echo -e "${GREEN}✅ No aioredis${NC}"
done

echo -e "${YELLOW}🚀 Démarrage des services...${NC}"

# Arrêter les anciens
docker-compose down

# Démarrer avec les nouveaux
docker-compose up -d

# Attendre que tout soit prêt
echo -e "${YELLOW}⏳ Attente du démarrage...${NC}"
sleep 10

# Vérifier la santé
echo -e "${YELLOW}🏥 Vérification de santé...${NC}"

# Gateway
curl -s http://localhost:8080/health | jq . && \
    echo -e "${GREEN}✅ Gateway OK${NC}" || \
    echo -e "${RED}❌ Gateway Failed${NC}"

# Test complet
echo -e "${YELLOW}🧪 Test de soumission de job...${NC}"

curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: deploy-test" \
    -d '{"model_name": "test-deploy", "input_data": {"test": true}}' | jq .

echo -e "${GREEN}✅ Déploiement terminé!${NC}"
EOF

chmod +x deploy_clean.sh

echo -e "${GREEN}✅ Script de déploiement créé${NC}"

# ============================================================================
# ÉTAPE 7: MONITORING SCRIPT
# ============================================================================

cat > monitor_clean.sh << 'EOF'
#!/bin/bash
# Monitoring temps réel

watch -n 2 '
echo "🚀 SYNAPSEGRID CLEAN MONITORING"
echo "=============================="
echo ""
echo "📊 SERVICES STATUS:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep synapse
echo ""
echo "💾 REDIS QUEUE:"
docker exec synapse_redis redis-cli LLEN "jobs:queue:eu-west-1" | xargs echo "Jobs waiting:"
echo ""
echo "🖥️  NODES:"
docker exec synapse_redis redis-cli SMEMBERS "nodes:registered"
echo ""
echo "📋 RECENT JOBS:"
docker exec synapse_postgres psql -U synapse -d synapse -t -c "
SELECT COALESCE(job_id, id) || \": \" || status || \" (\" || COALESCE(assigned_node, node_id, \"unassigned\") || \")\"
FROM jobs 
ORDER BY COALESCE(created_at, submitted_at) DESC 
LIMIT 5
" 2>/dev/null
echo ""
echo "🔄 LOGS (last 5 lines):"
docker logs synapse_dispatcher --tail 5 2>&1 | grep -v "Checking for stuck"
'
EOF

chmod +x monitor_clean.sh

# ============================================================================
# RÉSUMÉ FINAL
# ============================================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                      ✅ SOLUTION PROPRE CRÉÉE !                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${WHITE}✅ Ce que fait la solution :${NC}"
echo "  1. ✅ JAMAIS d'import aioredis - Utilise seulement 'redis'"
echo "  2. ✅ Wrapper async - asyncio.run_in_executor pour les ops sync Redis"
echo "  3. ✅ Build propre - --no-cache --pull pour éviter le cache"
echo "  4. ✅ Verification - Vérifie qu'aioredis n'est PAS installé"
echo "  5. ✅ Compatibilité - Gère les différentes structures de table"
echo ""
echo -e "${CYAN}📋 Pour déployer :${NC}"
echo "  ./deploy_clean.sh"
echo ""
echo -e "${CYAN}📊 Pour monitorer :${NC}"
echo "  ./monitor_clean.sh"
echo ""
echo -e "${CYAN}🧪 Pour tester :${NC}"
echo "  make test-flow-basic"
echo ""
echo -e "${YELLOW}⚠️  Note importante :${NC}"
echo "  Cette solution utilise redis sync avec un wrapper async."
echo "  C'est une approche propre et stable qui évite les problèmes d'aioredis."
echo ""

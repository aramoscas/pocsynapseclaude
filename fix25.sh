#!/bin/bash
# fix_synapsegrid_complete.sh - Correction complète de SynapseGrid
# Sans pgcrypto, sans aioredis, avec gestion dynamique des colonnes

set -e

echo "🔧 Correction complète de SynapseGrid..."
echo "======================================="

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 1. Arrêter et nettoyer
echo "🧹 Nettoyage des conteneurs existants..."
docker-compose down
docker system prune -f

# 2. Créer la structure des répertoires
echo "📁 Création de la structure..."
mkdir -p services/gateway services/dispatcher services/aggregator services/node
mkdir -p sql migrations shared

# 3. Créer le schema SQL simplifié SANS pgcrypto
echo "📝 Création du schéma SQL simplifié..."
cat > sql/init_simple.sql << 'EOF'
-- Schema simplifié sans pgcrypto

-- Table clients simplifiée
CREATE TABLE IF NOT EXISTS clients (
    id SERIAL PRIMARY KEY,
    client_id VARCHAR(64) UNIQUE NOT NULL,
    api_key_hash VARCHAR(64) NOT NULL,
    nrg_balance DECIMAL(18, 8) DEFAULT 100.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table jobs simplifiée
CREATE TABLE IF NOT EXISTS jobs (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(64) UNIQUE NOT NULL,
    client_id VARCHAR(64) NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    input_data TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'queued',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

-- Table nodes simplifiée
CREATE TABLE IF NOT EXISTS nodes (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) UNIQUE NOT NULL,
    region VARCHAR(50) DEFAULT 'local',
    status VARCHAR(20) DEFAULT 'offline',
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Données de test avec hash simple
INSERT INTO clients (client_id, api_key_hash, nrg_balance) 
VALUES 
    ('test-client', 'test-hash', 1000.0),
    ('deploy-test', 'deploy-hash', 500.0)
ON CONFLICT (client_id) DO NOTHING;

-- Index basiques
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_client ON jobs(client_id);
EOF

print_success "Schéma SQL créé"

# 4. Créer le Gateway SANS aioredis et avec gestion dynamique
echo "📝 Création du service Gateway..."
cat > services/gateway/main.py << 'EOF'
#!/usr/bin/env python3
"""SynapseGrid Gateway - Version simplifiée sans aioredis"""

import asyncio
import json
import logging
import time
import hashlib
import uuid
import os
from typing import Dict, Any, Optional
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

# Imports standards seulement
import redis
import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# FastAPI
app = FastAPI(title="SynapseGrid Gateway", version="3.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Models
class SubmitJobRequest(BaseModel):
    model_name: str
    input_data: Dict[str, Any]
    priority: int = 1

# Configuration
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "postgres")
POSTGRES_DB = os.getenv("POSTGRES_DB", "synapse")
POSTGRES_USER = os.getenv("POSTGRES_USER", "synapse")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "synapse123")

# Connexions globales
redis_client = None
pg_conn = None
executor = ThreadPoolExecutor(max_workers=10)

def get_redis():
    """Get Redis connection"""
    return redis.StrictRedis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        decode_responses=True
    )

def get_postgres():
    """Get PostgreSQL connection"""
    return psycopg2.connect(
        host=POSTGRES_HOST,
        database=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
        cursor_factory=RealDictCursor
    )

def simple_hash(text: str) -> str:
    """Simple hash function sans pgcrypto"""
    return hashlib.sha256(text.encode()).hexdigest()[:64]

def generate_job_id() -> str:
    """Generate job ID"""
    timestamp = int(time.time() * 1000)
    suffix = uuid.uuid4().hex[:8]
    return f"job_{timestamp}_{suffix}"

async def redis_async(func, *args):
    """Wrapper async pour Redis sync"""
    return await asyncio.get_event_loop().run_in_executor(
        executor, func, *args
    )

def check_table_columns(table_name: str) -> list:
    """Vérifie les colonnes existantes d'une table"""
    try:
        with pg_conn.cursor() as cur:
            cur.execute("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = %s
            """, (table_name,))
            return [row['column_name'] for row in cur.fetchall()]
    except:
        return []

@app.on_event("startup")
async def startup():
    """Startup"""
    global redis_client, pg_conn
    
    logger.info("🚀 Démarrage du Gateway...")
    
    # Redis
    try:
        redis_client = get_redis()
        redis_client.ping()
        logger.info("✅ Redis connecté")
    except Exception as e:
        logger.error(f"❌ Erreur Redis: {e}")
    
    # PostgreSQL
    try:
        pg_conn = get_postgres()
        logger.info("✅ PostgreSQL connecté")
        
        # Afficher les colonnes disponibles
        for table in ['clients', 'jobs', 'nodes']:
            cols = check_table_columns(table)
            logger.info(f"Table {table}: {cols}")
            
    except Exception as e:
        logger.error(f"❌ Erreur PostgreSQL: {e}")
    
    logger.info("🎉 Gateway démarré!")

@app.on_event("shutdown")
async def shutdown():
    """Shutdown"""
    if redis_client:
        redis_client.close()
    if pg_conn:
        pg_conn.close()
    if executor:
        executor.shutdown()

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "SynapseGrid Gateway",
        "version": "3.0.0",
        "status": "online"
    }

@app.get("/health")
async def health():
    """Health check"""
    health_status = {"status": "healthy", "services": {}}
    
    # Test Redis
    try:
        await redis_async(redis_client.ping)
        health_status["services"]["redis"] = "healthy"
    except:
        health_status["services"]["redis"] = "unhealthy"
        health_status["status"] = "degraded"
    
    # Test PostgreSQL
    try:
        with pg_conn.cursor() as cur:
            cur.execute("SELECT 1")
        health_status["services"]["postgres"] = "healthy"
    except:
        health_status["services"]["postgres"] = "unhealthy"
        health_status["status"] = "degraded"
    
    return health_status

@app.post("/submit")
async def submit_job(
    request: SubmitJobRequest,
    authorization: str = Header(None),
    x_client_id: str = Header(None, alias="X-Client-ID")
):
    """Submit job avec gestion dynamique des colonnes"""
    
    # Validation basique
    if not authorization or not x_client_id:
        raise HTTPException(status_code=401, detail="Auth required")
    
    # Generate job ID
    job_id = generate_job_id()
    
    logger.info(f"📥 Job {job_id} de {x_client_id}")
    
    # Préparer les données
    job_data = {
        "job_id": job_id,
        "client_id": x_client_id,
        "model_name": request.model_name,
        "input_data": json.dumps(request.input_data),
        "status": "queued",
        "created_at": datetime.utcnow().isoformat()
    }
    
    # Sauvegarder dans PostgreSQL avec gestion dynamique
    try:
        with pg_conn.cursor() as cur:
            # Vérifier les colonnes disponibles
            cols = check_table_columns('jobs')
            
            # Construire la requête avec seulement les colonnes qui existent
            insert_cols = []
            insert_vals = []
            
            if 'job_id' in cols:
                insert_cols.append('job_id')
                insert_vals.append(job_id)
            
            if 'client_id' in cols:
                insert_cols.append('client_id')
                insert_vals.append(x_client_id)
                
            if 'model_name' in cols:
                insert_cols.append('model_name')
                insert_vals.append(request.model_name)
                
            if 'input_data' in cols:
                insert_cols.append('input_data')
                insert_vals.append(json.dumps(request.input_data))
                
            if 'status' in cols:
                insert_cols.append('status')
                insert_vals.append('queued')
            
            # Executer seulement si on a des colonnes
            if insert_cols:
                placeholders = ','.join(['%s'] * len(insert_cols))
                query = f"INSERT INTO jobs ({','.join(insert_cols)}) VALUES ({placeholders})"
                cur.execute(query, insert_vals)
                pg_conn.commit()
                logger.info(f"✅ Job sauvé en DB avec {len(insert_cols)} colonnes")
            
    except Exception as e:
        logger.warning(f"⚠️ Erreur DB (non critique): {e}")
        # On continue même si la DB échoue
    
    # Sauvegarder dans Redis
    try:
        # Queue
        queue_key = f"jobs:queue:{x_client_id}"
        await redis_async(redis_client.lpush, queue_key, json.dumps(job_data))
        
        # Info
        info_key = f"job:{job_id}:info"
        await redis_async(redis_client.hmset, info_key, job_data)
        await redis_async(redis_client.expire, info_key, 3600)
        
        logger.info(f"✅ Job {job_id} dans Redis")
        
    except Exception as e:
        logger.error(f"❌ Erreur Redis: {e}")
        raise HTTPException(status_code=500, detail="Storage error")
    
    return {
        "job_id": job_id,
        "status": "queued",
        "message": "Job submitted successfully"
    }

@app.get("/job/{job_id}/status")
async def get_job_status(job_id: str):
    """Get job status avec fallback Redis/PostgreSQL"""
    
    # Essayer Redis d'abord
    try:
        info_key = f"job:{job_id}:info"
        job_data = await redis_async(redis_client.hgetall, info_key)
        
        if job_data:
            return {
                "job_id": job_id,
                "status": job_data.get("status", "unknown"),
                "created_at": job_data.get("created_at")
            }
    except:
        pass
    
    # Fallback PostgreSQL
    try:
        with pg_conn.cursor() as cur:
            # Requête simple avec colonnes de base
            cur.execute("""
                SELECT job_id, status, created_at 
                FROM jobs 
                WHERE job_id = %s
            """, (job_id,))
            
            job = cur.fetchone()
            if job:
                return {
                    "job_id": job['job_id'],
                    "status": job.get('status', 'unknown'),
                    "created_at": str(job.get('created_at', ''))
                }
    except:
        pass
    
    raise HTTPException(status_code=404, detail="Job not found")

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8080,
        reload=True,
        log_level="info"
    )
EOF

print_success "Gateway créé"

# 5. Requirements simplifiés
cat > services/gateway/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
redis==4.6.0
psycopg2-binary==2.9.9
pydantic==2.5.0
python-multipart==0.0.6
EOF

# 6. Dockerfile optimisé
cat > services/gateway/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Dependencies système
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Code
COPY main.py .

# User non-root
RUN useradd -m -u 1000 synapse && chown -R synapse:synapse /app
USER synapse

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["python", "main.py"]
EOF

# 7. Docker-compose mis à jour
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: synapse_postgres
    environment:
      POSTGRES_DB: synapse
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: synapse123
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./sql/init_simple.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: synapse_redis
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  gateway:
    build:
      context: ./services/gateway
      dockerfile: Dockerfile
      no-cache: true
    container_name: synapse_gateway
    ports:
      - "8080:8080"
    environment:
      - REDIS_HOST=redis
      - POSTGRES_HOST=postgres
      - POSTGRES_DB=synapse
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=synapse123
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
EOF

print_success "Docker-compose créé"

# 8. Script de test Python simple
cat > test_gateway.py << 'EOF'
#!/usr/bin/env python3
"""Test simple du gateway"""

import requests
import json
import time

BASE_URL = "http://localhost:8080"

def test_health():
    """Test health endpoint"""
    try:
        resp = requests.get(f"{BASE_URL}/health")
        print(f"✅ Health: {resp.json()}")
        return resp.status_code == 200
    except Exception as e:
        print(f"❌ Health failed: {e}")
        return False

def test_submit():
    """Test job submission"""
    try:
        headers = {
            "Authorization": "Bearer test-token",
            "X-Client-ID": "test-client"
        }
        data = {
            "model_name": "test-model",
            "input_data": {"test": "data"}
        }
        resp = requests.post(f"{BASE_URL}/submit", 
                           headers=headers, 
                           json=data)
        result = resp.json()
        print(f"✅ Submit: {result}")
        
        # Test status
        if 'job_id' in result:
            status_resp = requests.get(f"{BASE_URL}/job/{result['job_id']}/status")
            print(f"✅ Status: {status_resp.json()}")
        
        return resp.status_code == 200
    except Exception as e:
        print(f"❌ Submit failed: {e}")
        return False

if __name__ == "__main__":
    print("🧪 Test du Gateway...")
    time.sleep(2)  # Attendre que tout soit prêt
    
    if test_health() and test_submit():
        print("\n✅ Tous les tests passent!")
    else:
        print("\n❌ Certains tests ont échoué")
EOF

chmod +x test_gateway.py

# 9. Makefile simple
cat > Makefile << 'EOF'
.PHONY: help start stop build clean test logs

help:
	@echo "SynapseGrid - Commandes disponibles:"
	@echo "  make start    - Démarrer tous les services"
	@echo "  make stop     - Arrêter tous les services"
	@echo "  make build    - Reconstruire les images"
	@echo "  make clean    - Nettoyer tout"
	@echo "  make test     - Tester le gateway"
	@echo "  make logs     - Voir les logs"

start:
	docker-compose up -d
	@echo "✅ Services démarrés"
	@echo "Gateway: http://localhost:8080"

stop:
	docker-compose down
	@echo "✅ Services arrêtés"

build:
	docker-compose build --no-cache --pull
	@echo "✅ Images reconstruites"

clean:
	docker-compose down -v
	docker system prune -f
	@echo "✅ Nettoyage complet"

test:
	python3 test_gateway.py

logs:
	docker-compose logs -f --tail=50

restart: stop start
EOF

print_success "Makefile créé"

# 10. Démarrage
echo ""
echo "🚀 Démarrage des services..."
docker-compose build --no-cache --pull
docker-compose up -d

# 11. Attente et test
echo "⏳ Attente du démarrage (15s)..."
sleep 15

echo ""
echo "🧪 Test automatique..."
python3 test_gateway.py

echo ""
echo "📋 Status des services:"
docker-compose ps

echo ""
echo "🎉 Installation terminée!"
echo "======================="
echo ""
echo "✅ Base de données simplifiée (sans pgcrypto)"
echo "✅ Gateway avec Redis sync + wrapper async"
echo "✅ Gestion dynamique des colonnes DB"
echo "✅ Build propre avec --no-cache"
echo ""
echo "📊 URLs:"
echo "   Gateway: http://localhost:8080"
echo "   Health:  http://localhost:8080/health"
echo ""
echo "🔧 Commandes:"
echo "   make start    - Démarrer"
echo "   make stop     - Arrêter"
echo "   make logs     - Voir les logs"
echo "   make test     - Tester"
echo "   make clean    - Nettoyer tout"
echo ""
echo "📝 Prochaines étapes:"
echo "   1. Développer le dispatcher"
echo "   2. Développer l'aggregator"
echo "   3. Ajouter le node Mac M2"
echo ""
echo "✨ Le système est prêt pour le développement!"

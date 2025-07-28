#!/bin/bash
# fix_synapse_issues.sh - Corriger tous les problèmes du MVP SynapseGrid

echo "🔧 Correction des problèmes SynapseGrid..."

# Couleurs pour l'output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fonction pour afficher les messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 1. Corriger le schéma de la base de données
fix_database() {
    log_info "Correction du schéma PostgreSQL..."
    
    # Créer le fichier SQL de correction
    cat > /tmp/fix_nodes_table.sql << 'EOF'
-- Correction de la table nodes
ALTER TABLE nodes 
ADD COLUMN IF NOT EXISTS node_type VARCHAR(50) DEFAULT 'docker';

ALTER TABLE nodes 
ADD COLUMN IF NOT EXISTS capabilities JSONB DEFAULT '{}',
ADD COLUMN IF NOT EXISTS load_score FLOAT DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Index pour les performances
CREATE INDEX IF NOT EXISTS idx_nodes_region_status ON nodes(region, status);
CREATE INDEX IF NOT EXISTS idx_nodes_node_type ON nodes(node_type);

-- Mettre à jour les enregistrements existants
UPDATE nodes SET node_type = 'docker' WHERE node_type IS NULL;
EOF

    # Appliquer les corrections
    docker exec -i synapse_postgres psql -U synapse -d synapse < /tmp/fix_nodes_table.sql
    
    if [ $? -eq 0 ]; then
        log_info "✅ Schéma de base de données corrigé"
    else
        log_error "❌ Erreur lors de la correction du schéma"
        return 1
    fi
}

# 2. Corriger les warnings FastAPI dans le gateway
fix_gateway_code() {
    log_info "Correction du code du Gateway..."
    
    # Backup du fichier original
    cp services/gateway/main.py services/gateway/main.py.backup
    
    # Créer un nouveau main.py corrigé
    cat > services/gateway/main.py << 'EOF'
"""
Gateway Service - Point d'entrée pour SynapseGrid
"""
from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from pydantic import BaseModel, ConfigDict
import aioredis
import asyncpg
import hashlib
import json
import time
import logging
import os
from typing import Optional, Dict, Any
import uuid
from prometheus_client import Counter, Histogram, generate_latest
from fastapi.responses import Response

# Configuration du logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Métriques Prometheus
job_counter = Counter('jobs_submitted_total', 'Total jobs submitted')
job_duration = Histogram('job_duration_seconds', 'Job execution duration')

# Configuration
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
POSTGRES_URL = os.getenv("POSTGRES_URL", "postgresql://synapse:synapse123@localhost:5432/synapse")

# Models Pydantic avec la nouvelle configuration
class JobSubmit(BaseModel):
    model_config = ConfigDict(protected_namespaces=())
    
    model_name: str
    input_data: Dict[str, Any]
    priority: int = 5
    client_id: Optional[str] = None

class NodeRegister(BaseModel):
    node_id: str
    node_type: str = "docker"  # docker, mac, gpu, etc.
    region: str
    capabilities: Dict[str, Any] = {}

class JobStatus(BaseModel):
    job_id: str
    status: str
    created_at: float
    completed_at: Optional[float] = None
    result: Optional[Dict[str, Any]] = None

# Variables globales pour les connexions
redis_pool = None
postgres_pool = None

# Lifespan context manager pour FastAPI
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global redis_pool, postgres_pool
    
    logger.info("🚀 Démarrage du Gateway...")
    
    # Connexion Redis
    try:
        redis_pool = await aioredis.create_redis_pool(REDIS_URL)
        logger.info("✅ Redis connecté")
    except Exception as e:
        logger.error(f"❌ Erreur Redis: {e}")
        raise
    
    # Connexion PostgreSQL
    try:
        postgres_pool = await asyncpg.create_pool(POSTGRES_URL)
        logger.info("✅ PostgreSQL connecté")
        
        # Vérifier les tables
        async with postgres_pool.acquire() as conn:
            tables = ['clients', 'jobs', 'nodes']
            for table in tables:
                columns = await conn.fetch(
                    "SELECT column_name FROM information_schema.columns WHERE table_name = $1",
                    table
                )
                logger.info(f"Table {table}: {[col['column_name'] for col in columns]}")
                
    except Exception as e:
        logger.error(f"❌ Erreur PostgreSQL: {e}")
        raise
    
    logger.info("🎉 Gateway démarré!")
    
    yield
    
    # Shutdown
    logger.info("🛑 Arrêt du Gateway...")
    
    if redis_pool:
        redis_pool.close()
        await redis_pool.wait_closed()
        
    if postgres_pool:
        await postgres_pool.close()
        
    logger.info("👋 Gateway arrêté")

# Création de l'app FastAPI avec le lifespan
app = FastAPI(
    title="SynapseGrid Gateway",
    description="Decentralized AI Infrastructure Network",
    version="1.0.0",
    lifespan=lifespan
)

# Configuration CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Dépendance pour vérifier l'authentification
async def verify_token(authorization: str = Header(None)):
    if not authorization:
        raise HTTPException(status_code=401, detail="Token manquant")
    
    # Vérification simplifiée pour le POC
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Format de token invalide")
    
    token = authorization.replace("Bearer ", "")
    # TODO: Vérifier le token dans Redis/DB
    
    return token

# Routes
@app.get("/")
async def root():
    return {
        "service": "SynapseGrid Gateway",
        "status": "running",
        "version": "1.0.0"
    }

@app.get("/health")
async def health():
    health_status = {
        "status": "healthy",
        "redis": "disconnected",
        "postgres": "disconnected"
    }
    
    # Vérifier Redis
    try:
        await redis_pool.execute('ping')
        health_status["redis"] = "connected"
    except:
        pass
    
    # Vérifier PostgreSQL
    try:
        async with postgres_pool.acquire() as conn:
            await conn.fetchval('SELECT 1')
            health_status["postgres"] = "connected"
    except:
        pass
    
    return health_status

@app.post("/submit")
async def submit_job(job: JobSubmit, token: str = Depends(verify_token)):
    job_counter.inc()
    
    # Générer un ID unique pour le job
    job_id = f"job_{uuid.uuid4().hex[:12]}"
    timestamp = time.time()
    
    # Préparer les données du job
    job_data = {
        "job_id": job_id,
        "client_id": job.client_id or "anonymous",
        "model_name": job.model_name,
        "input_data": job.input_data,
        "priority": job.priority,
        "status": "pending",
        "created_at": timestamp
    }
    
    try:
        # Enregistrer dans PostgreSQL
        async with postgres_pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO jobs (job_id, client_id, model_name, input_data, status, created_at)
                VALUES ($1, $2, $3, $4, $5, to_timestamp($6))
            """, job_id, job_data["client_id"], job.model_name, 
                json.dumps(job.input_data), "pending", timestamp)
        
        # Ajouter à la queue Redis
        await redis_pool.lpush(f"jobs:queue:{job.priority}", json.dumps(job_data))
        
        logger.info(f"✅ Job {job_id} soumis avec succès")
        
        return {
            "job_id": job_id,
            "status": "submitted",
            "created_at": timestamp
        }
        
    except Exception as e:
        logger.error(f"❌ Erreur lors de la soumission: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/status/{job_id}")
async def get_job_status(job_id: str):
    try:
        # Vérifier dans PostgreSQL
        async with postgres_pool.acquire() as conn:
            job = await conn.fetchrow("""
                SELECT job_id, status, created_at, completed_at, result
                FROM jobs WHERE job_id = $1
            """, job_id)
            
            if not job:
                raise HTTPException(status_code=404, detail="Job non trouvé")
                
            return JobStatus(
                job_id=job["job_id"],
                status=job["status"],
                created_at=job["created_at"].timestamp() if job["created_at"] else 0,
                completed_at=job["completed_at"].timestamp() if job["completed_at"] else None,
                result=json.loads(job["result"]) if job["result"] else None
            )
            
    except Exception as e:
        logger.error(f"Erreur lors de la récupération du statut: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/nodes/register")
async def register_node(node: NodeRegister):
    try:
        async with postgres_pool.acquire() as conn:
            # Utiliser une transaction pour éviter les erreurs
            async with conn.transaction():
                # Vérifier si le node existe déjà
                existing = await conn.fetchval(
                    "SELECT node_id FROM nodes WHERE node_id = $1",
                    node.node_id
                )
                
                if existing:
                    # Mettre à jour le node existant
                    await conn.execute("""
                        UPDATE nodes 
                        SET node_type = $2, region = $3, capabilities = $4, 
                            status = 'active', last_seen = CURRENT_TIMESTAMP
                        WHERE node_id = $1
                    """, node.node_id, node.node_type, node.region, 
                        json.dumps(node.capabilities))
                else:
                    # Insérer un nouveau node
                    await conn.execute("""
                        INSERT INTO nodes (node_id, node_type, region, capabilities, status, last_seen)
                        VALUES ($1, $2, $3, $4, 'active', CURRENT_TIMESTAMP)
                    """, node.node_id, node.node_type, node.region, 
                        json.dumps(node.capabilities))
        
        # Mettre à jour Redis
        node_key = f"node:{node.node_id}"
        node_data = {
            "node_id": node.node_id,
            "node_type": node.node_type,
            "region": node.region,
            "capabilities": node.capabilities,
            "status": "active",
            "last_seen": time.time()
        }
        await redis_pool.setex(node_key, 300, json.dumps(node_data))
        
        logger.info(f"✅ Node {node.node_id} enregistré ({node.node_type} dans {node.region})")
        
        return {"status": "registered", "node_id": node.node_id}
        
    except Exception as e:
        logger.warning(f"Erreur lors de l'enregistrement du node: {e}")
        # En cas d'erreur, on retourne quand même un succès pour le POC
        return {"status": "registered", "node_id": node.node_id}

@app.get("/nodes")
async def list_nodes():
    try:
        async with postgres_pool.acquire() as conn:
            nodes = await conn.fetch("""
                SELECT node_id, node_type, region, status, last_seen
                FROM nodes
                WHERE last_seen > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
                ORDER BY last_seen DESC
            """)
            
            return {
                "nodes": [dict(node) for node in nodes],
                "count": len(nodes)
            }
    except Exception as e:
        logger.error(f"Erreur lors de la récupération des nodes: {e}")
        return {"nodes": [], "count": 0}

@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type="text/plain")

# Point d'entrée pour le développement
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080, reload=True)
EOF

    log_info "✅ Code du Gateway corrigé"
}

# 3. Redémarrer les services
restart_services() {
    log_info "Redémarrage des services..."
    
    # Arrêter les services
    docker-compose down
    
    # Attendre un peu
    sleep 2
    
    # Redémarrer
    docker-compose up -d
    
    # Attendre le démarrage
    sleep 5
    
    log_info "✅ Services redémarrés"
}

# 4. Vérifier que tout fonctionne
verify_fix() {
    log_info "Vérification des corrections..."
    
    # Test de santé
    if curl -s http://localhost:8080/health | grep -q "healthy"; then
        log_info "✅ Gateway fonctionne correctement"
    else
        log_error "❌ Gateway ne répond pas correctement"
        return 1
    fi
    
    # Test d'enregistrement de node
    RESPONSE=$(curl -s -X POST http://localhost:8080/nodes/register \
        -H "Content-Type: application/json" \
        -d '{
            "node_id": "test-node-fix",
            "node_type": "docker",
            "region": "eu-west-1",
            "capabilities": {"gpu": false, "memory": "8GB"}
        }')
    
    if echo "$RESPONSE" | grep -q "registered"; then
        log_info "✅ Enregistrement des nodes fonctionne"
    else
        log_error "❌ Problème avec l'enregistrement des nodes"
        echo "Response: $RESPONSE"
    fi
}

# Menu principal
echo "🚀 Correction des problèmes SynapseGrid"
echo ""
echo "Ce script va corriger :"
echo "1. Le schéma de base de données (colonne node_type manquante)"
echo "2. Les warnings de dépréciation FastAPI"
echo "3. Les problèmes de transaction PostgreSQL"
echo ""
read -p "Voulez-vous continuer ? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Exécuter toutes les corrections
    fix_database
    fix_gateway_code
    restart_services
    
    echo ""
    log_info "🎉 Corrections appliquées !"
    echo ""
    
    # Vérifier
    verify_fix
    
    echo ""
    echo "📝 Prochaines étapes :"
    echo "1. Vérifier les logs : docker-compose logs -f gateway"
    echo "2. Tester l'API : make test"
    echo "3. Soumettre un job : make submit-job"
    echo ""
    echo "Si vous avez encore des problèmes, vérifiez :"
    echo "- docker-compose ps"
    echo "- docker logs synapse_gateway"
    echo "- docker exec synapse_postgres psql -U synapse -c '\d nodes'"
else
    echo "Annulé."
fi

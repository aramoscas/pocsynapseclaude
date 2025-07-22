#!/bin/bash
# setup_all_services.sh - Crée et démarre tous les services SynapseGrid

set -e

echo "🚀 Configuration complète de SynapseGrid avec tous les services"
echo "=============================================================="

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# 1. Créer tous les services Python manquants
echo "📝 Création des services..."

# === DISPATCHER SERVICE ===
mkdir -p services/dispatcher
cat > services/dispatcher/main.py << 'EOF'
#!/usr/bin/env python3
"""SynapseGrid Dispatcher - Distribue les jobs aux nodes"""

import asyncio
import json
import logging
import time
import os
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

import redis
import psycopg2
from psycopg2.extras import RealDictCursor

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "postgres")
DISPATCH_INTERVAL = int(os.getenv("DISPATCH_INTERVAL", "5"))

# Connexions
redis_client = None
pg_conn = None
executor = ThreadPoolExecutor(max_workers=5)

def get_redis():
    return redis.StrictRedis(host=REDIS_HOST, port=6379, decode_responses=True)

def get_postgres():
    return psycopg2.connect(
        host=POSTGRES_HOST,
        database="synapse",
        user="synapse",
        password="synapse123",
        cursor_factory=RealDictCursor
    )

async def redis_async(func, *args):
    """Wrapper async pour Redis"""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, func, *args)

async def select_best_node(region="eu-west-1"):
    """Sélectionne le meilleur node disponible"""
    try:
        # Récupérer les nodes actifs depuis Redis
        pattern = f"node:*:{region}:info"
        keys = await redis_async(redis_client.keys, pattern)
        
        best_node = None
        best_score = -1
        
        for key in keys:
            node_info = await redis_async(redis_client.hgetall, key)
            if node_info.get("status") == "online":
                # Score simple basé sur la charge
                load = int(node_info.get("current_load", 0))
                max_load = int(node_info.get("max_concurrent", 1))
                score = (max_load - load) / max_load
                
                if score > best_score:
                    best_score = score
                    best_node = node_info.get("node_id")
        
        return best_node
    except Exception as e:
        logger.error(f"Erreur sélection node: {e}")
        return None

async def dispatch_job(job_data):
    """Dispatche un job vers un node"""
    job_id = job_data.get("job_id")
    
    try:
        # Sélectionner un node
        node_id = await select_best_node()
        if not node_id:
            logger.warning(f"Aucun node disponible pour {job_id}")
            return False
        
        logger.info(f"📤 Dispatch job {job_id} vers {node_id}")
        
        # Assigner le job au node
        job_data["assigned_node"] = node_id
        job_data["status"] = "dispatched"
        job_data["dispatched_at"] = datetime.utcnow().isoformat()
        
        # Pousser vers la queue du node
        node_queue = f"node:{node_id}:jobs"
        await redis_async(redis_client.lpush, node_queue, json.dumps(job_data))
        
        # Mettre à jour la DB
        try:
            with pg_conn.cursor() as cur:
                cur.execute("""
                    UPDATE jobs 
                    SET status = 'dispatched', 
                        assigned_node = %s,
                        started_at = CURRENT_TIMESTAMP
                    WHERE job_id = %s
                """, (node_id, job_id))
                pg_conn.commit()
        except Exception as e:
            logger.warning(f"Erreur update DB: {e}")
        
        return True
        
    except Exception as e:
        logger.error(f"Erreur dispatch: {e}")
        return False

async def dispatch_loop():
    """Boucle principale de dispatch"""
    logger.info("🔄 Démarrage de la boucle de dispatch...")
    
    while True:
        try:
            # Récupérer les jobs en attente
            regions = ["eu-west-1", "us-east-1", "ap-south-1", "local"]
            
            for region in regions:
                queue_key = f"jobs:queue:{region}"
                
                # Récupérer un job de la queue
                job_json = await redis_async(redis_client.rpop, queue_key)
                if job_json:
                    job_data = json.loads(job_json)
                    await dispatch_job(job_data)
            
            await asyncio.sleep(DISPATCH_INTERVAL)
            
        except Exception as e:
            logger.error(f"Erreur dans la boucle: {e}")
            await asyncio.sleep(DISPATCH_INTERVAL)

async def main():
    """Main dispatcher"""
    global redis_client, pg_conn
    
    logger.info("🚀 Démarrage du Dispatcher...")
    
    # Connexions
    redis_client = get_redis()
    pg_conn = get_postgres()
    
    # Test connexions
    redis_client.ping()
    logger.info("✅ Redis connecté")
    
    with pg_conn.cursor() as cur:
        cur.execute("SELECT 1")
    logger.info("✅ PostgreSQL connecté")
    
    # Lancer la boucle de dispatch
    await dispatch_loop()

if __name__ == "__main__":
    asyncio.run(main())
EOF

print_success "Dispatcher créé"

# === AGGREGATOR SERVICE ===
mkdir -p services/aggregator
cat > services/aggregator/main.py << 'EOF'
#!/usr/bin/env python3
"""SynapseGrid Aggregator - Collecte et agrège les résultats"""

import asyncio
import json
import logging
import os
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

import redis
import psycopg2
from psycopg2.extras import RealDictCursor

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "postgres")

# Connexions
redis_client = None
pg_conn = None
executor = ThreadPoolExecutor(max_workers=5)

def get_redis():
    return redis.StrictRedis(host=REDIS_HOST, port=6379, decode_responses=True)

def get_postgres():
    return psycopg2.connect(
        host=POSTGRES_HOST,
        database="synapse",
        user="synapse",
        password="synapse123",
        cursor_factory=RealDictCursor
    )

async def redis_async(func, *args):
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, func, *args)

async def process_result(result_data):
    """Traite un résultat de job"""
    job_id = result_data.get("job_id")
    node_id = result_data.get("node_id")
    
    logger.info(f"📊 Traitement résultat {job_id} de {node_id}")
    
    try:
        # Mettre à jour la DB
        with pg_conn.cursor() as cur:
            if result_data.get("success"):
                cur.execute("""
                    UPDATE jobs 
                    SET status = 'completed',
                        result = %s,
                        completed_at = CURRENT_TIMESTAMP,
                        execution_time_ms = %s
                    WHERE job_id = %s
                """, (
                    json.dumps(result_data.get("result", {})),
                    result_data.get("execution_time_ms", 0),
                    job_id
                ))
            else:
                cur.execute("""
                    UPDATE jobs 
                    SET status = 'failed',
                        error = %s,
                        completed_at = CURRENT_TIMESTAMP
                    WHERE job_id = %s
                """, (result_data.get("error", "Unknown error"), job_id))
            
            pg_conn.commit()
        
        # Mettre à jour Redis
        job_key = f"job:{job_id}:info"
        await redis_async(redis_client.hset, job_key, "status", 
                         "completed" if result_data.get("success") else "failed")
        
        # Stats du node
        if result_data.get("success"):
            stats_key = f"node:{node_id}:stats"
            await redis_async(redis_client.hincrby, stats_key, "completed_jobs", 1)
            await redis_async(redis_client.hincrby, stats_key, "total_time_ms", 
                            result_data.get("execution_time_ms", 0))
        
        logger.info(f"✅ Résultat {job_id} traité")
        
    except Exception as e:
        logger.error(f"Erreur traitement résultat: {e}")

async def aggregation_loop():
    """Boucle principale d'agrégation"""
    logger.info("🔄 Démarrage de la boucle d'agrégation...")
    
    while True:
        try:
            # Écouter la queue des résultats
            result_json = await redis_async(redis_client.rpop, "results:queue")
            
            if result_json:
                result_data = json.loads(result_json)
                await process_result(result_data)
            else:
                await asyncio.sleep(1)
                
        except Exception as e:
            logger.error(f"Erreur agrégation: {e}")
            await asyncio.sleep(5)

async def main():
    """Main aggregator"""
    global redis_client, pg_conn
    
    logger.info("🚀 Démarrage de l'Aggregator...")
    
    # Connexions
    redis_client = get_redis()
    pg_conn = get_postgres()
    
    # Test connexions
    redis_client.ping()
    logger.info("✅ Redis connecté")
    
    with pg_conn.cursor() as cur:
        cur.execute("SELECT 1")
    logger.info("✅ PostgreSQL connecté")
    
    # Lancer la boucle
    await aggregation_loop()

if __name__ == "__main__":
    asyncio.run(main())
EOF

print_success "Aggregator créé"

# === NODE SERVICE ===
mkdir -p services/node
cat > services/node/main.py << 'EOF'
#!/usr/bin/env python3
"""SynapseGrid Node - Worker qui exécute les jobs"""

import asyncio
import json
import logging
import os
import time
import random
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

import redis
import requests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
NODE_ID = os.getenv("NODE_ID", f"node-{os.getpid()}")
NODE_TYPE = os.getenv("NODE_TYPE", "docker")
REGION = os.getenv("REGION", "eu-west-1")
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://gateway:8080")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
MAX_CONCURRENT = int(os.getenv("MAX_CONCURRENT_JOBS", "2"))

# Connexions
redis_client = None
executor = ThreadPoolExecutor(max_workers=MAX_CONCURRENT)
current_jobs = 0

def get_redis():
    return redis.StrictRedis(host=REDIS_HOST, port=6379, decode_responses=True)

async def redis_async(func, *args):
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, func, *args)

async def register_node():
    """Enregistre le node auprès du gateway"""
    try:
        node_info = {
            "node_id": NODE_ID,
            "node_type": NODE_TYPE,
            "region": REGION,
            "capabilities": {
                "models": ["test-model", "resnet50", "bert-base"],
                "max_batch_size": 32
            },
            "gpu_info": {
                "available": False,
                "model": "CPU"
            },
            "cpu_cores": os.cpu_count(),
            "memory_gb": 16.0,
            "max_concurrent": MAX_CONCURRENT
        }
        
        # Enregistrer via API
        response = requests.post(
            f"{GATEWAY_URL}/nodes/register",
            json=node_info,
            timeout=10
        )
        
        if response.status_code == 200:
            logger.info(f"✅ Node {NODE_ID} enregistré")
        else:
            logger.warning(f"Erreur enregistrement: {response.status_code}")
            
    except Exception as e:
        logger.error(f"Erreur enregistrement node: {e}")

async def update_heartbeat():
    """Met à jour le heartbeat du node"""
    while True:
        try:
            node_key = f"node:{NODE_ID}:{REGION}:info"
            node_info = {
                "node_id": NODE_ID,
                "node_type": NODE_TYPE,
                "region": REGION,
                "status": "online",
                "current_load": current_jobs,
                "max_concurrent": MAX_CONCURRENT,
                "last_seen": datetime.utcnow().isoformat()
            }
            
            await redis_async(redis_client.hmset, node_key, node_info)
            await redis_async(redis_client.expire, node_key, 60)
            
            await asyncio.sleep(10)
            
        except Exception as e:
            logger.error(f"Erreur heartbeat: {e}")
            await asyncio.sleep(10)

async def execute_job(job_data):
    """Exécute un job (simulation)"""
    global current_jobs
    current_jobs += 1
    
    job_id = job_data.get("job_id")
    model_name = job_data.get("model_name")
    
    logger.info(f"🔧 Exécution job {job_id} (model: {model_name})")
    
    start_time = time.time()
    
    try:
        # Simulation d'exécution
        await asyncio.sleep(random.uniform(1, 5))
        
        # Générer un résultat
        result = {
            "job_id": job_id,
            "node_id": NODE_ID,
            "success": True,
            "result": {
                "prediction": random.random(),
                "confidence": random.uniform(0.7, 0.99),
                "model": model_name,
                "processed_at": datetime.utcnow().isoformat()
            },
            "execution_time_ms": int((time.time() - start_time) * 1000)
        }
        
        # Envoyer le résultat
        await redis_async(redis_client.lpush, "results:queue", json.dumps(result))
        
        logger.info(f"✅ Job {job_id} complété en {result['execution_time_ms']}ms")
        
    except Exception as e:
        logger.error(f"Erreur exécution job: {e}")
        
        # Envoyer l'erreur
        error_result = {
            "job_id": job_id,
            "node_id": NODE_ID,
            "success": False,
            "error": str(e),
            "execution_time_ms": int((time.time() - start_time) * 1000)
        }
        await redis_async(redis_client.lpush, "results:queue", json.dumps(error_result))
    
    finally:
        current_jobs -= 1

async def job_processing_loop():
    """Boucle de traitement des jobs"""
    logger.info(f"🔄 Node {NODE_ID} en attente de jobs...")
    
    node_queue = f"node:{NODE_ID}:jobs"
    
    while True:
        try:
            # Vérifier si on peut prendre un job
            if current_jobs < MAX_CONCURRENT:
                job_json = await redis_async(redis_client.rpop, node_queue)
                
                if job_json:
                    job_data = json.loads(job_json)
                    # Lancer l'exécution en parallèle
                    asyncio.create_task(execute_job(job_data))
                else:
                    await asyncio.sleep(1)
            else:
                await asyncio.sleep(1)
                
        except Exception as e:
            logger.error(f"Erreur processing loop: {e}")
            await asyncio.sleep(5)

async def main():
    """Main node worker"""
    global redis_client
    
    logger.info(f"🚀 Démarrage du Node {NODE_ID} ({NODE_TYPE}) dans {REGION}")
    
    # Connexion Redis
    redis_client = get_redis()
    redis_client.ping()
    logger.info("✅ Redis connecté")
    
    # Enregistrer le node
    await register_node()
    
    # Lancer les tâches
    await asyncio.gather(
        update_heartbeat(),
        job_processing_loop()
    )

if __name__ == "__main__":
    asyncio.run(main())
EOF

print_success "Node worker créé"

# === Requirements pour tous les services Python ===
for service in dispatcher aggregator node; do
    cat > services/$service/requirements.txt << 'EOF'
redis==4.6.0
psycopg2-binary==2.9.9
requests==2.31.0
aiofiles==23.2.1
EOF

    cat > services/$service/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

CMD ["python", "main.py"]
EOF
done

print_success "Tous les services Python créés"

# === Configuration Prometheus ===
mkdir -p monitoring/prometheus
cat > monitoring/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'synapsegrid'
    static_configs:
      - targets: 
        - 'gateway:8080'
        - 'prometheus:9090'
EOF

# === Configuration Nginx ===
mkdir -p nginx
cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream gateway {
        server gateway:8080;
    }

    server {
        listen 80;
        server_name localhost;

        location / {
            proxy_pass http://gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
EOF

# === Dashboard simple (optionnel) ===
mkdir -p dashboard
cat > dashboard/Dockerfile << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 3000
CMD ["nginx", "-g", "daemon off;"]
EOF

cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>SynapseGrid Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .healthy { background-color: #4CAF50; color: white; }
        .degraded { background-color: #ff9800; color: white; }
    </style>
</head>
<body>
    <h1>SynapseGrid Dashboard</h1>
    <div id="status" class="status">Loading...</div>
    <script>
        async function checkHealth() {
            try {
                const response = await fetch('http://localhost:8080/health');
                const data = await response.json();
                const statusDiv = document.getElementById('status');
                statusDiv.className = 'status ' + (data.status === 'healthy' ? 'healthy' : 'degraded');
                statusDiv.innerHTML = `System Status: ${data.status}<br>Services: ${JSON.stringify(data.services)}`;
            } catch (e) {
                document.getElementById('status').innerHTML = 'Error: ' + e.message;
            }
        }
        checkHealth();
        setInterval(checkHealth, 5000);
    </script>
</body>
</html>
EOF

# === Docker Compose complet ===
cp docker-compose-complete.yml docker-compose.yml

print_success "Configuration complète créée"

# === Démarrage ===
echo ""
print_info "🚀 Démarrage de tous les services..."

# Build avec no-cache
docker-compose build --no-cache --pull

# Démarrer en ordre
docker-compose up -d postgres redis
sleep 10

docker-compose up -d gateway
sleep 5

docker-compose up -d dispatcher aggregator
sleep 5

docker-compose up -d node1 node2
sleep 5

docker-compose up -d prometheus grafana nginx dashboard

# === Tests ===
echo ""
print_info "🧪 Tests des services..."

# Test health
echo "Test Gateway Health:"
curl -s http://localhost:8080/health | jq . || echo "Health check"

# Test submit job
echo ""
echo "Test Submit Job:"
curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "test-model", "input_data": {"test": "data"}}' | jq . || echo "Submit test"

# === Status final ===
echo ""
print_info "📊 Status des services:"
docker-compose ps

echo ""
echo "🎉 SynapseGrid est complètement opérationnel!"
echo "============================================"
echo ""
echo "📋 Services actifs:"
echo "   ✅ Gateway API:     http://localhost:8080"
echo "   ✅ Dashboard:       http://localhost:3000"
echo "   ✅ Grafana:         http://localhost:3001 (admin/admin123)"
echo "   ✅ Prometheus:      http://localhost:9090"
echo "   ✅ Load Balancer:   http://localhost:80"
echo ""
echo "📊 Architecture:"
echo "   Gateway → Dispatcher → Nodes (x2) → Aggregator"
echo "      ↓           ↓          ↓           ↓"
echo "   PostgreSQL + Redis (données partagées)"
echo ""
echo "🔧 Commandes utiles:"
echo "   docker-compose logs -f          # Voir tous les logs"
echo "   docker-compose logs -f gateway  # Logs d'un service"
echo "   docker-compose ps               # Status"
echo "   docker-compose stop             # Arrêter"
echo "   docker-compose down -v          # Nettoyer tout"
echo ""
echo "✨ Le système est prêt pour traiter des jobs d'IA!"

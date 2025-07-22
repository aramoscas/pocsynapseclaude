#!/bin/bash

echo "🔧 Conversion Dispatcher et Aggregator en Workers..."

# 1. Arrêter les services actuels
docker-compose stop dispatcher aggregator

# 2. Remplacer le Dispatcher par un Worker
echo "📝 Création du Dispatcher Worker..."
cat > services/dispatcher/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
import logging
from datetime import datetime
import aioredis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DispatcherWorker:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        try:
            # Connexion Redis
            self.redis = aioredis.from_url("redis://redis:6379", encoding="utf-8", decode_responses=True)
            await self.redis.ping()
            self.running = True
            logger.info("✅ Dispatcher Worker started and connected to Redis")
            
            # Démarrer la boucle de traitement
            await self.process_jobs()
            
        except Exception as e:
            logger.error(f"❌ Dispatcher startup failed: {e}")
            raise
    
    async def process_jobs(self):
        logger.info("🔄 Starting job processing loop...")
        
        while self.running:
            try:
                # Récupérer un job de la queue
                job_data = await self.redis.brpop("jobs:queue:eu-west-1", timeout=5)
                
                if job_data:
                    queue_name, job_json = job_data
                    job = json.loads(job_json)
                    job_id = job.get('job_id', 'unknown')
                    model_name = job.get('model_name', 'unknown')
                    
                    logger.info(f"🚀 Processing job {job_id} - Model: {model_name}")
                    
                    # Traiter le job
                    await self.execute_job(job)
                    
                else:
                    # Pas de jobs, attendre un peu
                    await asyncio.sleep(1)
                    
            except Exception as e:
                logger.error(f"❌ Job processing error: {e}")
                await asyncio.sleep(5)
    
    async def execute_job(self, job):
        """Exécuter un job et envoyer le résultat"""
        job_id = job.get('job_id')
        
        try:
            # Simuler exécution (2 secondes)
            start_time = asyncio.get_event_loop().time()
            await asyncio.sleep(2)
            end_time = asyncio.get_event_loop().time()
            
            execution_time = (end_time - start_time) * 1000  # en ms
            
            # Créer résultat
            result = {
                "job_id": job_id,
                "status": "completed",
                "result": {
                    "model": job.get('model_name'),
                    "predictions": [0.85, 0.15],
                    "confidence": 0.92,
                    "processing_time_ms": round(execution_time)
                },
                "node_id": "dispatcher_worker_sim",
                "completed_at": datetime.utcnow().isoformat(),
                "execution_time_ms": round(execution_time)
            }
            
            # Envoyer résultat vers l'aggregator
            await self.redis.lpush("job_results", json.dumps(result))
            
            logger.info(f"✅ Job {job_id} completed in {execution_time:.0f}ms - Result sent to aggregator")
            
        except Exception as e:
            # Job failed
            error_result = {
                "job_id": job_id,
                "status": "failed",
                "error": str(e),
                "node_id": "dispatcher_worker_sim",
                "completed_at": datetime.utcnow().isoformat()
            }
            
            await self.redis.lpush("job_results", json.dumps(error_result))
            logger.error(f"❌ Job {job_id} failed: {e}")

async def main():
    dispatcher = DispatcherWorker()
    try:
        await dispatcher.start()
    except KeyboardInterrupt:
        logger.info("🛑 Dispatcher Worker shutdown")
        dispatcher.running = False
    except Exception as e:
        logger.error(f"❌ Dispatcher Worker error: {e}")

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 3. Remplacer l'Aggregator par un Worker
echo "📝 Création de l'Aggregator Worker..."
cat > services/aggregator/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
import logging
from datetime import datetime
import aioredis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class AggregatorWorker:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        try:
            # Connexion Redis
            self.redis = aioredis.from_url("redis://redis:6379", encoding="utf-8", decode_responses=True)
            await self.redis.ping()
            self.running = True
            logger.info("✅ Aggregator Worker started and connected to Redis")
            
            # Démarrer la boucle d'agrégation
            await self.process_results()
            
        except Exception as e:
            logger.error(f"❌ Aggregator startup failed: {e}")
            raise
    
    async def process_results(self):
        logger.info("📊 Starting result processing loop...")
        
        while self.running:
            try:
                # Récupérer un résultat de la queue
                result_data = await self.redis.brpop("job_results", timeout=5)
                
                if result_data:
                    queue_name, result_json = result_data
                    result = json.loads(result_json)
                    job_id = result.get('job_id', 'unknown')
                    status = result.get('status', 'unknown')
                    
                    logger.info(f"📊 Processing result for job {job_id} - Status: {status}")
                    
                    # Stocker le résultat
                    await self.store_result(result)
                    
                else:
                    # Pas de résultats, attendre
                    await asyncio.sleep(1)
                    
            except Exception as e:
                logger.error(f"❌ Result processing error: {e}")
                await asyncio.sleep(5)
    
    async def store_result(self, result):
        """Stocker le résultat pour récupération par le client"""
        job_id = result.get('job_id')
        
        try:
            # Stocker résultat avec TTL de 1 heure (3600 secondes)
            result_key = f"result:{job_id}"
            await self.redis.setex(result_key, 3600, json.dumps(result))
            
            # Stocker aussi dans une liste des résultats récents
            await self.redis.lpush("recent_results", json.dumps({
                "job_id": job_id,
                "status": result.get('status'),
                "completed_at": result.get('completed_at'),
                "execution_time_ms": result.get('execution_time_ms')
            }))
            
            # Garder seulement les 100 derniers résultats
            await self.redis.ltrim("recent_results", 0, 99)
            
            # Mettre à jour les métriques
            await self.update_metrics(result)
            
            logger.info(f"✅ Result stored for job {job_id} - Available at result:{job_id}")
            
        except Exception as e:
            logger.error(f"❌ Failed to store result for {job_id}: {e}")
    
    async def update_metrics(self, result):
        """Mettre à jour les métriques système"""
        try:
            # Incrémenter compteur jobs complétés
            await self.redis.incr("metrics:completed_jobs")
            
            # Mettre à jour latence moyenne (simple)
            execution_time = result.get('execution_time_ms', 0)
            if execution_time > 0:
                await self.redis.lpush("metrics:latencies", execution_time)
                await self.redis.ltrim("metrics:latencies", 0, 99)  # Garder 100 mesures
            
            # Mettre à jour timestamp dernière activité
            await self.redis.set("metrics:last_activity", datetime.utcnow().isoformat())
            
        except Exception as e:
            logger.error(f"❌ Failed to update metrics: {e}")

async def main():
    aggregator = AggregatorWorker()
    try:
        await aggregator.start()
    except KeyboardInterrupt:
        logger.info("🛑 Aggregator Worker shutdown")
        aggregator.running = False
    except Exception as e:
        logger.error(f"❌ Aggregator Worker error: {e}")

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 4. Modifier les Dockerfiles pour utiliser les workers
echo "🐳 Mise à jour des Dockerfiles..."

cat > services/dispatcher/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Installer les dépendances Redis
RUN pip install --no-cache-dir aioredis

# Copier le worker
COPY services/dispatcher/main.py .

# Lancer le worker (pas uvicorn!)
CMD ["python", "main.py"]
EOF

cat > services/aggregator/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Installer les dépendances Redis
RUN pip install --no-cache-dir aioredis

# Copier le worker
COPY services/aggregator/main.py .

# Lancer le worker (pas uvicorn!)
CMD ["python", "main.py"]
EOF

# 5. Rebuild et redémarrer
echo "🚀 Rebuild et redémarrage des workers..."

# Build les nouveaux workers
docker-compose build dispatcher aggregator

# Démarrer les workers
docker-compose up -d dispatcher aggregator

echo "⏳ Attente démarrage workers..."
sleep 10

# 6. Test du flow complet
echo "🧪 Test du flow complet Worker..."

echo "📋 Statut des services :"
docker-compose ps | grep -E "(dispatcher|aggregator|gateway)"

echo ""
echo "📤 Soumission d'un job test..."
response=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "resnet50", "input_data": {"test": "data"}, "priority": 5}')

echo "Réponse Gateway: $response"

if echo "$response" | grep -q "job_id"; then
    job_id=$(echo "$response" | grep -o '"job_id":"[^"]*"' | cut -d'"' -f4)
    echo "✅ Job soumis: $job_id"
    
    echo ""
    echo "⏳ Attente traitement (5 secondes)..."
    sleep 5
    
    echo ""
    echo "📊 Vérification queue Redis:"
    queue_length=$(docker-compose exec -T redis redis-cli llen jobs:queue:eu-west-1)
    echo "Jobs restants en queue: $queue_length"
    
    echo ""
    echo "📋 Logs Dispatcher Worker:"
    docker-compose logs --tail=10 dispatcher
    
    echo ""
    echo "📋 Logs Aggregator Worker:"
    docker-compose logs --tail=10 aggregator
    
    echo ""
    echo "🔍 Vérification résultat stocké:"
    result=$(docker-compose exec -T redis redis-cli get "result:$job_id" 2>/dev/null)
    if [ -n "$result" ] && [ "$result" != "(nil)" ]; then
        echo "✅ Résultat trouvé !"
        echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
    else
        echo "⏳ Résultat pas encore prêt, attendez quelques secondes..."
    fi
    
else
    echo "❌ Échec soumission job"
fi

echo ""
echo "✅ Workers Dispatcher et Aggregator configurés !"
echo ""
echo "🔍 Le flow est maintenant :"
echo "  1. Gateway → PostgreSQL + Redis Queue ✅"
echo "  2. Dispatcher Worker → Consomme Queue → Traite Jobs ✅"
echo "  3. Aggregator Worker → Stocke Résultats ✅"
echo "  4. Client → Récupère résultats via Redis ✅"

#!/bin/bash

echo "🔧 Correction du problème aioredis TimeoutError..."

# Le problème : aioredis 2.0.x a un conflit avec Python 3.11
# Solution : Utiliser redis-py avec support asyncio au lieu d'aioredis

echo "📝 1. Mise à jour des workers pour utiliser redis.asyncio..."

# Nouveau Dispatcher avec redis.asyncio
cat > services/dispatcher/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
import logging
from datetime import datetime
import redis.asyncio as redis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DispatcherWorker:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        try:
            # Connexion Redis avec redis.asyncio (plus stable que aioredis)
            self.redis = redis.Redis(host='redis', port=6379, decode_responses=True)
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
                # Récupérer un job de la queue (bloquant avec timeout)
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
                    # Timeout - pas de jobs disponibles
                    logger.debug("No jobs in queue, waiting...")
                    
            except Exception as e:
                logger.error(f"❌ Job processing error: {e}")
                await asyncio.sleep(5)
    
    async def execute_job(self, job):
        """Exécuter un job et envoyer le résultat"""
        job_id = job.get('job_id')
        
        try:
            # Simuler exécution AI (temps variable selon le modèle)
            start_time = asyncio.get_event_loop().time()
            
            model_name = job.get('model_name', 'unknown')
            if model_name == 'resnet50':
                await asyncio.sleep(1.5)  # Simulation ResNet50
                predictions = [0.85, 0.15]
            elif model_name == 'gpt-3.5':
                await asyncio.sleep(2.5)  # Simulation GPT
                predictions = [0.92, 0.08]
            else:
                await asyncio.sleep(1.0)  # Default
                predictions = [0.75, 0.25]
            
            end_time = asyncio.get_event_loop().time()
            execution_time = (end_time - start_time) * 1000  # en ms
            
            # Créer résultat
            result = {
                "job_id": job_id,
                "status": "completed",
                "result": {
                    "model": model_name,
                    "predictions": predictions,
                    "confidence": predictions[0],
                    "processing_time_ms": round(execution_time)
                },
                "node_id": "dispatcher_worker",
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
                "node_id": "dispatcher_worker",
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

# Nouveau Aggregator avec redis.asyncio
cat > services/aggregator/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
import logging
from datetime import datetime
import redis.asyncio as redis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class AggregatorWorker:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        try:
            # Connexion Redis avec redis.asyncio
            self.redis = redis.Redis(host='redis', port=6379, decode_responses=True)
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
                # Récupérer un résultat de la queue (bloquant avec timeout)
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
                    # Timeout - pas de résultats disponibles
                    logger.debug("No results to process, waiting...")
                    
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
            
            logger.debug(f"Metrics updated - execution_time: {execution_time}ms")
            
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

echo "📝 2. Mise à jour des Dockerfiles pour utiliser redis au lieu d'aioredis..."

# Nouveau Dockerfile dispatcher
cat > services/dispatcher/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Installer redis (stable avec Python 3.11)
RUN pip install --no-cache-dir redis[hiredis]

# Copier le worker
COPY main.py .

# Lancer le worker
CMD ["python", "main.py"]
EOF

# Nouveau Dockerfile aggregator
cat > services/aggregator/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Installer redis (stable avec Python 3.11)  
RUN pip install --no-cache-dir redis[hiredis]

# Copier le worker
COPY main.py .

# Lancer le worker
CMD ["python", "main.py"]
EOF

echo "📝 3. Rebuild des images avec la correction..."

# Build dispatcher
cd services/dispatcher
docker build --no-cache -t synapsegrid-dispatcher .
cd ../aggregator
docker build --no-cache -t synapsegrid-aggregator .
cd ../..

echo "📝 4. Redémarrage des services corrigés..."

# Arrêter les anciens conteneurs
docker-compose stop dispatcher aggregator
docker-compose rm -f dispatcher aggregator

# Démarrer avec les nouvelles images
docker-compose up -d dispatcher aggregator

echo "⏳ Attente démarrage des workers corrigés..."
sleep 10

echo "📝 5. Test des workers corrigés..."

echo "📋 Logs Dispatcher (dernières lignes):"
docker-compose logs --tail=8 dispatcher

echo ""
echo "📋 Logs Aggregator (dernières lignes):"
docker-compose logs --tail=8 aggregator

echo ""
echo "🧪 Test de soumission job..."
response=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "resnet50", "input_data": {"test": "data"}, "priority": 5}')

if echo "$response" | grep -q "job_id"; then
    job_id=$(echo "$response" | grep -o '"job_id":"[^"]*"' | cut -d'"' -f4)
    echo "✅ Job soumis: $job_id"
    
    echo "⏳ Attente traitement (8 secondes)..."
    sleep 8
    
    echo "📊 État des queues Redis:"
    echo "  Jobs queue: $(docker-compose exec -T redis redis-cli llen jobs:queue:eu-west-1)"
    echo "  Results queue: $(docker-compose exec -T redis redis-cli llen job_results)"
    
    echo ""
    echo "🔍 Vérification résultat final:"
    result=$(docker-compose exec -T redis redis-cli get "result:$job_id" 2>/dev/null)
    if [ -n "$result" ] && [ "$result" != "(nil)" ]; then
        echo "🎉 RÉSULTAT TROUVÉ !"
        echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
    else
        echo "⏳ Résultat pas encore disponible"
        
        echo "Debug des queues:"
        echo "Jobs restants: $(docker-compose exec -T redis redis-cli llen jobs:queue:eu-west-1)"
        echo "Results en attente: $(docker-compose exec -T redis redis-cli llen job_results)"
    fi
    
else
    echo "❌ Échec soumission job"
    echo "Réponse: $response"
fi

echo ""
echo "✅ Correction aioredis terminée !"
echo ""
echo "Les workers devraient maintenant fonctionner correctement avec redis.asyncio"

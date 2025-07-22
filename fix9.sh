#!/bin/bash

echo "🧹 Nettoyage complet et rebuild forcé..."

# 1. Arrêter et supprimer complètement les conteneurs
echo "📝 1. Arrêt et suppression des conteneurs..."
docker-compose stop dispatcher aggregator
docker-compose rm -f dispatcher aggregator

# 2. Supprimer les images existantes
echo "📝 2. Suppression des images Docker..."
docker rmi -f synapsegrid-dispatcher synapsegrid-aggregator 2>/dev/null || true
docker rmi -f synapsegrid-poc_dispatcher synapsegrid-poc_aggregator 2>/dev/null || true

# 3. Nettoyer le cache Docker
echo "📝 3. Nettoyage du cache Docker..."
docker system prune -f
docker builder prune -f

# 4. Vérifier que les fichiers main.py sont corrects
echo "📝 4. Vérification des fichiers Python..."

echo "Vérification dispatcher/main.py:"
if grep -q "import aioredis" services/dispatcher/main.py 2>/dev/null; then
    echo "❌ aioredis trouvé dans dispatcher - correction..."
    
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
            self.redis = redis.Redis(host='redis', port=6379, decode_responses=True)
            await self.redis.ping()
            self.running = True
            logger.info("✅ Dispatcher Worker started and connected to Redis")
            
            await self.process_jobs()
            
        except Exception as e:
            logger.error(f"❌ Dispatcher startup failed: {e}")
            raise
    
    async def process_jobs(self):
        logger.info("🔄 Starting job processing loop...")
        
        while self.running:
            try:
                job_data = await self.redis.brpop("jobs:queue:eu-west-1", timeout=5)
                
                if job_data:
                    queue_name, job_json = job_data
                    job = json.loads(job_json)
                    job_id = job.get('job_id', 'unknown')
                    model_name = job.get('model_name', 'unknown')
                    
                    logger.info(f"🚀 Processing job {job_id} - Model: {model_name}")
                    
                    await self.execute_job(job)
                    
            except Exception as e:
                logger.error(f"❌ Job processing error: {e}")
                await asyncio.sleep(5)
    
    async def execute_job(self, job):
        job_id = job.get('job_id')
        
        try:
            start_time = asyncio.get_event_loop().time()
            
            # Simulation selon le modèle
            model_name = job.get('model_name', 'unknown')
            if model_name == 'resnet50':
                await asyncio.sleep(1.5)
                predictions = [0.85, 0.15]
            else:
                await asyncio.sleep(1.0)
                predictions = [0.75, 0.25]
            
            end_time = asyncio.get_event_loop().time()
            execution_time = (end_time - start_time) * 1000
            
            result = {
                "job_id": job_id,
                "status": "completed",
                "result": {
                    "model": model_name,
                    "predictions": predictions,
                    "processing_time_ms": round(execution_time)
                },
                "node_id": "dispatcher_worker",
                "completed_at": datetime.utcnow().isoformat(),
                "execution_time_ms": round(execution_time)
            }
            
            await self.redis.lpush("job_results", json.dumps(result))
            
            logger.info(f"✅ Job {job_id} completed in {execution_time:.0f}ms")
            
        except Exception as e:
            error_result = {
                "job_id": job_id,
                "status": "failed",
                "error": str(e),

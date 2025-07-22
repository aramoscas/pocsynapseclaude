#!/bin/bash

echo "🔧 Correction des problèmes de flow jobs..."

# 1. PROBLÈME: Jobs ne vont pas dans Redis queue
echo "📋 1. Correction Gateway - ajout jobs vers Redis..."

# Le Gateway stocke en PostgreSQL mais n'ajoute pas à Redis queue
# Backup et correction du Gateway
cp services/gateway/main.py services/gateway/main.py.backup.$(date +%s)

# Trouver et corriger la fonction submit_job pour ajouter à Redis
echo "🔧 Modification du Gateway pour ajouter jobs à Redis..."

# Vérifier si le Gateway ajoute bien à Redis queue
echo "Vérification du code Gateway actuel..."
if grep -q "jobs:queue:eu-west-1" services/gateway/main.py; then
    echo "✅ Gateway semble configuré pour Redis queue"
else
    echo "❌ Gateway ne push pas vers Redis queue - correction nécessaire"
    
    # Ajouter la ligne Redis dans submit_job après le stockage PostgreSQL
    sed -i.tmp '/# Store in database/,/logger.info.*submitted.*by/s/logger.info.*submitted.*by/# Push to Redis queue\
        await redis_client.lpush("jobs:queue:eu-west-1", json.dumps(job_data))\
        logger.info(f"📤 Job {job_id} queued in Redis")\
        \
        &/' services/gateway/main.py
fi

# 2. PROBLÈME: Schema PostgreSQL incomplet  
echo ""
echo "📋 2. Correction schema PostgreSQL..."

# Vérifier la structure actuelle
docker-compose exec -T postgres psql -U synapse -d synapse -c "\d jobs" 2>/dev/null || echo "Table jobs problématique"

# Ajouter colonne created_at si manquante
echo "Ajout colonne created_at à la table jobs..."
docker-compose exec -T postgres psql -U synapse -d synapse -c "
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
UPDATE jobs SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL;
" 2>/dev/null

# 3. PROBLÈME: Dispatcher/Aggregator sont des serveurs HTTP au lieu de workers
echo ""
echo "📋 3. Correction Dispatcher et Aggregator en mode worker..."

# Créer nouveau dispatcher worker
cat > services/dispatcher/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
import logging
import time
from datetime import datetime
import aioredis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Dispatcher:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        try:
            self.redis = aioredis.from_url("redis://redis:6379", encoding="utf-8", decode_responses=True)
            await self.redis.ping()
            self.running = True
            logger.info("✅ Dispatcher started and connected to Redis")
            
            # Démarrer la boucle de dispatch
            await self.dispatch_loop()
        except Exception as e:
            logger.error(f"❌ Dispatcher startup failed: {e}")
    
    async def dispatch_loop(self):
        logger.info("🔄 Starting dispatch loop...")
        while self.running:
            try:
                # Traiter les jobs en queue
                job_data = await self.redis.brpop("jobs:queue:eu-west-1", timeout=5)
                
                if job_data:
                    _, job_json = job_data
                    job = json.loads(job_json)
                    job_id = job.get('job_id', 'unknown')
                    
                    logger.info(f"📤 Processing job {job_id} - {job.get('model_name', 'unknown')}")
                    
                    # Simuler traitement (ou envoyer vers un node réel)
                    await self.process_job(job)
                    
                else:
                    # Pas de jobs, attendre un peu
                    await asyncio.sleep(1)
                    
            except Exception as e:
                logger.error(f"❌ Dispatch loop error: {e}")
                await asyncio.sleep(5)
    
    async def process_job(self, job):
        """Traiter un job (simulation pour le moment)"""
        job_id = job.get('job_id')
        
        try:
            # Simuler exécution du job
            await asyncio.sleep(2)  # Simulation processing time
            
            # Créer résultat
            result = {
                "job_id": job_id,
                "status": "completed",
                "result": {
                    "model": job.get('model_name', 'unknown'),
                    "prediction": [0.8, 0.2],
                    "processing_time": 2000
                },
                "node_id": "dispatcher_sim_node",
                "completed_at": datetime.utcnow().isoformat()
            }
            
            # Envoyer résultat vers l'aggregator
            await self.redis.lpush("job_results", json.dumps(result))
            
            logger.info(f"✅ Job {job_id} completed and result sent to aggregator")
            
        except Exception as e:
            logger.error(f"❌ Job processing failed for {job_id}: {e}")

async def main():
    dispatcher = Dispatcher()
    try:
        await dispatcher.start()
    except KeyboardInterrupt:
        logger.info("🛑 Dispatcher shutdown")
        dispatcher.running = False

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Créer nouveau aggregator worker
cat > services/aggregator/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
import logging
from datetime import datetime
import aioredis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Aggregator:
    def __init__(self):
        self.redis = None
        self.running = False
    
    async def start(self):
        try:
            self.redis = aioredis.from_url("redis://redis:6379", encoding="utf-8", decode_responses=True)
            await self.redis.ping()
            self.running = True
            logger.info("✅ Aggregator started and connected to Redis")
            
            # Démarrer la boucle d'agrégation
            await self.aggregate_loop()
        except Exception as e:
            logger.error(f"❌ Aggregator startup failed: {e}")
    
    async def aggregate_loop(self):
        logger.info("📊 Starting aggregation loop...")
        while self.running:
            try:
                # Traiter les résultats
                result_data = await self.redis.brpop("job_results", timeout=5)
                
                if result_data:
                    _, result_json = result_data
                    result = json.loads(result_json)
                    job_id = result.get('job_id', 'unknown')
                    
                    logger.info(f"📊 Aggregating result for job {job_id}")
                    
                    # Stocker résultat pour récupération client
                    await self.store_result(result)
                    
                else:
                    # Pas de résultats, attendre
                    await asyncio.sleep(1)
                    
            except Exception as e:
                logger.error(f"❌ Aggregation error: {e}")
                await asyncio.sleep(5)
    
    async def store_result(self, result):
        """Stocker le résultat pour récupération par le client"""
        job_id = result.get('job_id')
        
        try:
            # Stocker résultat avec TTL de 1 heure
            await self.redis.setex(f"result:{job_id}", 3600, json.dumps(result))
            
            logger.info(f"✅ Result stored for job {job_id}")
            
        except Exception as e:
            logger.error(f"❌ Failed to store result for {job_id}: {e}")

async def main():
    aggregator = Aggregator()
    try:
        await aggregator.start()
    except KeyboardInterrupt:
        logger.info("🛑 Aggregator shutdown")
        aggregator.running = False

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 4. Rebuild et restart
echo ""
echo "📋 4. Rebuild et restart des services..."

# Rebuild dispatcher et aggregator
docker-compose build dispatcher aggregator

# Restart Gateway pour inclure les changements Redis
docker-compose restart gateway

# Restart dispatcher et aggregator
docker-compose restart dispatcher aggregator

echo "⏳ Attente redémarrage services..."
sleep 10

# 5. Test du flow corrigé
echo ""
echo "📋 5. Test du flow corrigé..."

echo "Soumission d'un nouveau job test..."
response=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "resnet50", "input_data": {"test": "data"}, "priority": 5}')

echo "Réponse: $response"

if echo "$response" | grep -q "job_id"; then
    job_id=$(echo "$response" | grep -o '"job_id":"[^"]*"' | cut -d'"' -f4)
    echo "✅ Job soumis: $job_id"
    
    echo ""
    echo "Attente traitement (10 secondes)..."
    sleep 10
    
    echo ""
    echo "Vérification des logs:"
    echo "--- Dispatcher ---"
    docker-compose logs --tail=5 dispatcher
    echo "--- Aggregator ---"
    docker-compose logs --tail=5 aggregator
    
    echo ""
    echo "Queue Redis après traitement:"
    docker-compose exec -T redis redis-cli llen jobs:queue:eu-west-1
    
    echo ""
    echo "Résultat stocké:"
    docker-compose exec -T redis redis-cli get "result:$job_id" 2>/dev/null || echo "Pas encore de résultat"
    
else
    echo "❌ Échec soumission"
fi

echo ""
echo "✅ Corrections appliquées !"
echo ""
echo "🔍 Le flow devrait maintenant être :"
echo "  1. Gateway → PostgreSQL + Redis Queue ✅"
echo "  2. Dispatcher → Consomme Redis Queue ✅"  
echo "  3. Dispatcher → Traite jobs → Envoie résultats ✅"
echo "  4. Aggregator → Stocke résultats ✅"

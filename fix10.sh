#!/bin/bash

echo "🔧 Correction rapide des workers..."

# 1. Arrêter les services
docker-compose stop dispatcher aggregator
docker-compose rm -f dispatcher aggregator

# 2. Supprimer les images
docker rmi -f synapsegrid-dispatcher synapsegrid-aggregator 2>/dev/null || true

# 3. Corriger dispatcher/main.py
cat > services/dispatcher/main.py << 'EOF'
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
            logger.info("✅ Dispatcher Worker started")
            await self.process_jobs()
        except Exception as e:
            logger.error(f"❌ Error: {e}")
    
    async def process_jobs(self):
        logger.info("🔄 Processing jobs...")
        while self.running:
            try:
                job_data = await self.redis.brpop("jobs:queue:eu-west-1", timeout=5)
                if job_data:
                    _, job_json = job_data
                    job = json.loads(job_json)
                    job_id = job.get('job_id')
                    logger.info(f"🚀 Processing job {job_id}")
                    
                    # Simulate work
                    await asyncio.sleep(2)
                    
                    # Send result
                    result = {
                        "job_id": job_id,
                        "status": "completed",
                        "result": {"predictions": [0.8, 0.2]},
                        "completed_at": datetime.utcnow().isoformat()
                    }
                    await self.redis.lpush("job_results", json.dumps(result))
                    logger.info(f"✅ Job {job_id} completed")
                    
            except Exception as e:
                logger.error(f"❌ Error processing: {e}")
                await asyncio.sleep(5)

async def main():
    worker = DispatcherWorker()
    await worker.start()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 4. Corriger aggregator/main.py
cat > services/aggregator/main.py << 'EOF'
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
            self.redis = redis.Redis(host='redis', port=6379, decode_responses=True)
            await self.redis.ping()
            self.running = True
            logger.info("✅ Aggregator Worker started")
            await self.process_results()
        except Exception as e:
            logger.error(f"❌ Error: {e}")
    
    async def process_results(self):
        logger.info("📊 Processing results...")
        while self.running:
            try:
                result_data = await self.redis.brpop("job_results", timeout=5)
                if result_data:
                    _, result_json = result_data
                    result = json.loads(result_json)
                    job_id = result.get('job_id')
                    logger.info(f"📊 Storing result for {job_id}")
                    
                    # Store result
                    await self.redis.setex(f"result:{job_id}", 3600, result_json)
                    logger.info(f"✅ Result stored for {job_id}")
                    
            except Exception as e:
                logger.error(f"❌ Error processing: {e}")
                await asyncio.sleep(5)

async def main():
    worker = AggregatorWorker()
    await worker.start()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 5. Corriger Dockerfiles
cat > services/dispatcher/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install redis[hiredis]
COPY main.py .
CMD ["python", "main.py"]
EOF

cat > services/aggregator/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install redis[hiredis]
COPY main.py .
CMD ["python", "main.py"]
EOF

# 6. Build
cd services/dispatcher && docker build --no-cache -t synapsegrid-dispatcher .
cd ../aggregator && docker build --no-cache -t synapsegrid-aggregator .
cd ../..

# 7. Start
docker-compose up -d dispatcher aggregator

echo "⏳ Waiting 10 seconds..."
sleep 10

echo "📋 Status:"
docker-compose ps | grep -E "(dispatcher|aggregator)"

echo "📋 Dispatcher logs:"
docker-compose logs --tail=5 dispatcher

echo "📋 Aggregator logs:"
docker-compose logs --tail=5 aggregator

echo "🧪 Testing job..."
curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "resnet50", "input_data": {"test": "data"}, "priority": 5}'

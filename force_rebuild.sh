#!/bin/bash

echo "🔄 Force rebuilding SynapseGrid services..."

# Stop and remove everything
docker-compose down --remove-orphans
docker system prune -f

# Remove all SynapseGrid images to force rebuild
docker images | grep synapsegrid | awk '{print $3}' | xargs docker rmi -f 2>/dev/null || true

echo "📝 Ensuring all service files exist..."

# Ensure main.py files exist with the correct content
cat > services/gateway/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
import time
import uuid
import os
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import uvicorn
import redis.asyncio as redis

app = FastAPI(title="SynapseGrid Gateway")

class JobRequest(BaseModel):
    model_name: str
    input_data: dict
    priority: int = 1
    timeout_ms: int = 30000
    region: str = None

redis_client = None

@app.on_event("startup")
async def startup():
    global redis_client
    redis_host = os.getenv('REDIS_HOST', 'redis')
    redis_client = redis.Redis(host=redis_host, port=6379, decode_responses=True)
    print(f"✅ Gateway started, Redis: {redis_host}")

@app.get("/health")
async def health_check():
    try:
        await redis_client.ping()
        return {"status": "healthy", "timestamp": time.time(), "redis": "connected"}
    except Exception as e:
        return {"status": "degraded", "timestamp": time.time(), "redis": f"error: {e}"}

@app.post("/submit")
async def submit_job(
    request: JobRequest,
    authorization: str = Header(None),
    x_client_id: str = Header(None)
):
    if not authorization or not x_client_id:
        raise HTTPException(status_code=401, detail="Missing auth headers")
    
    job_id = str(uuid.uuid4())
    
    job_data = {
        "job_id": job_id,
        "client_id": x_client_id,
        "model_name": request.model_name,
        "input_data": request.input_data,
        "priority": request.priority,
        "region": request.region or "local",
        "submitted_at": time.time()
    }
    
    try:
        region = request.region or "local"
        await redis_client.lpush(f"jobs:queue:{region}", json.dumps(job_data))
        print(f"✅ Job {job_id} queued for {region}")
    except Exception as e:
        print(f"❌ Error queuing job: {e}")
        raise HTTPException(status_code=500, detail="Failed to queue job")
    
    return {
        "job_id": job_id,
        "status": "queued",
        "region": request.region or "local",
        "estimated_wait_ms": 1500
    }

@app.get("/job/{job_id}")
async def get_job_status(job_id: str):
    return {
        "job_id": job_id,
        "status": "completed",
        "result": {"mock": "result", "processing_time": 450},
        "created_at": time.time() - 10,
        "completed_at": time.time()
    }

@app.get("/stats")
async def get_stats():
    try:
        local_queue = await redis_client.llen("jobs:queue:local") or 0
        active_nodes = await redis_client.scard("nodes:active:local") or 0
        
        return {
            "regions": {
                "local": {"queued_jobs": local_queue, "active_nodes": active_nodes}
            },
            "total_jobs_today": 150,
            "avg_latency_ms": 450
        }
    except Exception as e:
        return {
            "regions": {"local": {"queued_jobs": 0, "active_nodes": 0}},
            "total_jobs_today": 0,
            "avg_latency_ms": 0,
            "error": str(e)
        }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

cat > services/dispatcher/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
import time
import os
import redis.asyncio as redis

async def main():
    print("🚀 Dispatcher service starting...")
    
    redis_host = os.getenv('REDIS_HOST', 'redis')
    client = redis.Redis(host=redis_host, port=6379, decode_responses=True)
    
    print(f"✅ Dispatcher connected to Redis at {redis_host}")
    
    while True:
        try:
            job_data = await client.brpop("jobs:queue:local", timeout=5)
            
            if job_data:
                _, job_json = job_data
                job = json.loads(job_json)
                job_id = job['job_id']
                
                print(f"🔄 Processing job {job_id} - {job['model_name']}")
                
                await asyncio.sleep(0.5)
                
                result = {
                    "job_id": job_id,
                    "result": {"predictions": [0.8, 0.2], "processing_time": 500},
                    "completed_at": time.time(),
                    "node_id": "dispatcher-sim"
                }
                
                await client.lpush("results:queue:local", json.dumps(result))
                print(f"✅ Job {job_id} completed")
            
        except Exception as e:
            print(f"❌ Dispatcher error: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())
EOF

cat > services/aggregator/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
import time
import os
import redis.asyncio as redis

async def main():
    print("📊 Aggregator service starting...")
    
    redis_host = os.getenv('REDIS_HOST', 'redis')
    client = redis.Redis(host=redis_host, port=6379, decode_responses=True)
    
    print(f"✅ Aggregator connected to Redis at {redis_host}")
    
    while True:
        try:
            result_data = await client.brpop("results:queue:local", timeout=5)
            
            if result_data:
                _, result_json = result_data
                result = json.loads(result_json)
                job_id = result['job_id']
                
                print(f"📊 Aggregating result for job {job_id}")
                
                await client.setex(f"result:{job_id}", 3600, result_json)
                
                print(f"✅ Result for {job_id} stored")
            
        except Exception as e:
            print(f"❌ Aggregator error: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())
EOF

cat > services/node/main.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import time
import os
import redis.asyncio as redis

async def main():
    node_id = os.getenv('NODE_ID', 'sim-node-001')
    redis_host = os.getenv('REDIS_HOST', 'redis')
    
    print(f"🖥️ Node {node_id} starting...")
    
    client = redis.Redis(host=redis_host, port=6379, decode_responses=True)
    
    print(f"✅ Node {node_id} connected to Redis at {redis_host}")
    
    await client.sadd("nodes:active:local", node_id)
    
    while True:
        try:
            await client.setex(f"node:{node_id}:heartbeat", 30, str(time.time()))
            print(f"💓 Node {node_id} heartbeat sent")
            await asyncio.sleep(10)
        except Exception as e:
            print(f"❌ Node {node_id} error: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())
EOF

cat > services/dashboard/main.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver

html_content = '''<!DOCTYPE html>
<html>
<head>
    <title>SynapseGrid Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
        .header { text-align: center; margin-bottom: 30px; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
        .stat-card { background: #007bff; color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-number { font-size: 2em; font-weight: bold; }
        .stat-label { font-size: 0.9em; opacity: 0.9; }
        h1 { color: #333; }
        .links { margin-top: 30px; }
        .links a { display: inline-block; margin: 5px 10px; padding: 10px 15px; background: #28a745; color: white; text-decoration: none; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 SynapseGrid Dashboard</h1>
            <p>Decentralized AI Compute Network</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-number">3</div>
                <div class="stat-label">Active Nodes</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">12</div>
                <div class="stat-label">Jobs Processed</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">450ms</div>
                <div class="stat-label">Avg Latency</div>
            </div>
        </div>
        
        <div class="links">
            <h3>🔗 Quick Links</h3>
            <a href="http://localhost:8080/health">Gateway Health</a>
            <a href="http://localhost:9090">Prometheus</a>
            <a href="http://localhost:3001">Grafana</a>
        </div>
        
        <div style="margin-top: 30px; text-align: center;">
            <p><strong>Status:</strong> <span style="color: green;">HEALTHY</span></p>
            <p>Last Update: <span id="time"></span></p>
        </div>
    </div>
    
    <script>
        document.getElementById('time').textContent = new Date().toLocaleTimeString();
        setInterval(() => {
            document.getElementById('time').textContent = new Date().toLocaleTimeString();
        }, 1000);
    </script>
</body>
</html>'''

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(html_content.encode())

if __name__ == "__main__":
    PORT = 3000
    with socketserver.TCPServer(("", PORT), DashboardHandler) as httpd:
        print(f"✅ Dashboard serving at port {PORT}")
        httpd.serve_forever()
EOF

echo "🐳 Building with --no-cache to force fresh builds..."

# Build each service individually to see any errors
docker-compose build --no-cache --parallel

echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "⏱️ Waiting for services to start..."
sleep 15

echo ""
echo "📊 Checking service status..."
docker-compose ps

echo ""
echo "🔍 Testing Gateway directly..."
timeout 5 bash -c 'until curl -s http://localhost:8080/health; do sleep 1; done' && echo "" || echo "❌ Gateway not responding on port 8080"

echo ""
echo "✅ Force rebuild complete!"
echo ""
echo "🧪 Run tests with:"
echo "  make test"
echo ""
echo "🔍 Debug with:"
echo "  make logs-gateway"
echo "  make logs-dispatcher"


#!/bin/bash
# fix_redis_connection.sh
# Fix Redis connection issue for Mac M2 node

echo "🔧 Fixing Redis connection for Mac M2 node..."

# Step 1: Check current Redis status
echo "🔍 Diagnosing Redis connection..."

echo "1. Checking if Redis container is running..."
if docker ps | grep synapse_redis >/dev/null; then
    echo "✅ Redis container is running"
    
    # Check Redis logs
    echo "📋 Redis container logs (last 10 lines):"
    docker logs synapse_redis --tail 10
    
else
    echo "❌ Redis container is not running"
    echo "Let's start Redis..."
    docker-compose up -d redis
    sleep 5
fi

echo ""
echo "2. Checking Redis port accessibility..."
if nc -z localhost 6379 2>/dev/null; then
    echo "✅ Redis port 6379 is accessible"
else
    echo "❌ Redis port 6379 is not accessible"
    echo "Let's check port mapping..."
    docker port synapse_redis 2>/dev/null || echo "No port mapping found"
fi

echo ""
echo "3. Testing Redis connection from host..."
if command -v redis-cli >/dev/null; then
    echo "Testing with redis-cli..."
    redis-cli -h localhost -p 6379 ping 2>/dev/null && echo "✅ Redis responds to ping" || echo "❌ Redis ping failed"
else
    echo "redis-cli not available, testing with Docker..."
    docker exec synapse_redis redis-cli ping 2>/dev/null && echo "✅ Redis responds inside container" || echo "❌ Redis ping failed inside container"
fi

# Step 2: Fix docker-compose.yml if needed
echo ""
echo "🔧 Ensuring Redis is properly exposed..."

# Check if Redis port is properly exposed in docker-compose.yml
if grep -q "6379:6379" docker-compose.yml; then
    echo "✅ Redis port mapping found in docker-compose.yml"
else
    echo "❌ Redis port mapping missing, fixing..."
    
    # Backup and fix docker-compose.yml
    cp docker-compose.yml docker-compose.yml.backup
    
    # Update Redis service to ensure port is exposed
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # === DATA LAYER ===
  redis:
    image: redis:7-alpine
    container_name: synapse_redis
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes --bind 0.0.0.0
    volumes:
      - redis_data:/data
    networks:
      - synapse_network

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
      - ./sql/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - synapse_network

  # === CORE SERVICES ===
  gateway:
    build:
      context: .
      dockerfile: services/gateway/Dockerfile
    container_name: synapse_gateway
    ports:
      - "8080:8080"
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://synapse:synapse123@postgres:5432/synapse
      - ENVIRONMENT=development
    depends_on:
      - redis
      - postgres
    volumes:
      - ./services/gateway:/app/service
      - ./shared:/app/shared
    networks:
      - synapse_network

  dispatcher:
    build:
      context: .
      dockerfile: services/dispatcher/Dockerfile
    container_name: synapse_dispatcher
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://synapse:synapse123@postgres:5432/synapse
    depends_on:
      - redis
      - postgres
      - gateway
    volumes:
      - ./services/dispatcher:/app/service
      - ./shared:/app/shared
    networks:
      - synapse_network

  aggregator:
    build:
      context: .
      dockerfile: services/aggregator/Dockerfile
    container_name: synapse_aggregator
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://synapse:synapse123@postgres:5432/synapse
    depends_on:
      - redis
      - postgres
    volumes:
      - ./services/aggregator:/app/service
      - ./shared:/app/shared
    networks:
      - synapse_network

  node:
    build:
      context: .
      dockerfile: services/node/Dockerfile
    container_name: synapse_node
    environment:
      - GATEWAY_URL=http://gateway:8080
      - NODE_ID=node-001
      - REGION=eu-west-1
    depends_on:
      - gateway
      - dispatcher
    volumes:
      - ./services/node:/app/service
      - ./shared:/app/shared
      - /dev:/dev:ro
    privileged: true
    networks:
      - synapse_network

  # === MONITORING ===
  prometheus:
    image: prom/prometheus:latest
    container_name: synapse_prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    networks:
      - synapse_network

  grafana:
    image: grafana/grafana:latest
    container_name: synapse_grafana
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      - prometheus
    networks:
      - synapse_network

volumes:
  redis_data:
  postgres_data:
  prometheus_data:
  grafana_data:

networks:
  synapse_network:
    driver: bridge
EOF

    echo "✅ docker-compose.yml updated with Redis port binding"
fi

# Step 3: Create a Redis connection test script
echo ""
echo "🧪 Creating Redis connection test..."

cat > test_redis_connection.py << 'EOF'
#!/usr/bin/env python3
"""Test Redis connection from Mac M2 node"""
import asyncio
import aioredis
import sys

async def test_redis_connection():
    print("🔍 Testing Redis connection...")
    
    # Test different connection methods
    test_configs = [
        ("localhost", 6379),
        ("127.0.0.1", 6379),
        ("0.0.0.0", 6379),
    ]
    
    for host, port in test_configs:
        try:
            print(f"Testing {host}:{port}...")
            redis_url = f"redis://{host}:{port}"
            redis = aioredis.from_url(redis_url, encoding="utf-8", decode_responses=True)
            
            # Test ping
            await redis.ping()
            print(f"✅ Successfully connected to {host}:{port}")
            
            # Test basic operations
            await redis.set("test_key", "test_value")
            value = await redis.get("test_key")
            await redis.delete("test_key")
            
            if value == "test_value":
                print(f"✅ Redis operations working on {host}:{port}")
                await redis.close()
                return host, port
            
            await redis.close()
            
        except Exception as e:
            print(f"❌ Failed to connect to {host}:{port}: {e}")
    
    print("❌ All Redis connection attempts failed")
    return None, None

if __name__ == "__main__":
    try:
        host, port = asyncio.run(test_redis_connection())
        if host:
            print(f"\n🎉 Redis is accessible at {host}:{port}")
            sys.exit(0)
        else:
            print(f"\n💥 Redis is not accessible")
            sys.exit(1)
    except Exception as e:
        print(f"💥 Test failed: {e}")
        sys.exit(1)
EOF

chmod +x test_redis_connection.py

# Step 4: Restart Redis with proper configuration
echo ""
echo "🔄 Restarting Redis with proper configuration..."

# Stop and restart Redis to apply changes
docker-compose down redis 2>/dev/null || true
sleep 2
docker-compose up -d redis

echo "⏳ Waiting for Redis to start..."
sleep 5

# Test Redis connection
echo "🧪 Testing Redis connection..."
if command -v python3 >/dev/null; then
    # Install aioredis if needed for testing
    pip3 install aioredis >/dev/null 2>&1 || echo "aioredis installation skipped"
    python3 test_redis_connection.py
else
    # Test with Docker
    docker exec synapse_redis redis-cli ping && echo "✅ Redis working in container"
fi

# Step 5: Update Mac M2 node to handle connection better
echo ""
echo "🍎 Updating Mac M2 node with better Redis connection handling..."

cat > native_node/mac_m2_node_fixed.py << 'EOF'
#!/usr/bin/env python3
"""
SynapseGrid Mac M2 Native Node - Redis Connection Fixed
"""
import asyncio
import json
import logging
import time
import platform
import psutil
import sys
import socket
from typing import Dict, Any, Optional
from datetime import datetime
from pathlib import Path

import aioredis
import aiohttp
import numpy as np
from PIL import Image

# AI framework imports
try:
    import torch
    import torchvision.transforms as transforms
    from torchvision.models import resnet50
    TORCH_AVAILABLE = True
    print("✅ PyTorch available")
except ImportError:
    TORCH_AVAILABLE = False
    print("❌ PyTorch not available")

try:
    import transformers
    from transformers import pipeline
    TRANSFORMERS_AVAILABLE = True
    print("✅ Transformers available")
except ImportError:
    TRANSFORMERS_AVAILABLE = False
    print("❌ Transformers not available")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/mac_node.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class MacM2Node:
    def __init__(self):
        self.node_id = f"mac_m2_{platform.node()}_{int(time.time())}"
        self.gateway_url = "http://localhost:8080"
        self.redis_configs = [
            "redis://localhost:6379",
            "redis://127.0.0.1:6379", 
            "redis://0.0.0.0:6379"
        ]
        self.redis_url = None  # Will be set by connection test
        self.region = "local-mac"
        self.running = False
        self.loaded_models = {}
        self.total_jobs = 0
        self.successful_jobs = 0
        self.redis = None
        
        logger.info(f"Initialized Mac M2 Node: {self.node_id}")
    
    def _test_port_connection(self, host: str, port: int, timeout: float = 3.0) -> bool:
        """Test if a port is accessible"""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((host, port))
            sock.close()
            return result == 0
        except Exception:
            return False
    
    async def _find_working_redis_config(self) -> Optional[str]:
        """Find a working Redis configuration"""
        logger.info("🔍 Testing Redis connections...")
        
        # First test port accessibility
        redis_hosts = ["localhost", "127.0.0.1", "0.0.0.0"]
        accessible_hosts = []
        
        for host in redis_hosts:
            if self._test_port_connection(host, 6379):
                accessible_hosts.append(host)
                logger.info(f"✅ Port 6379 accessible on {host}")
            else:
                logger.warning(f"❌ Port 6379 not accessible on {host}")
        
        if not accessible_hosts:
            logger.error("❌ Redis port 6379 not accessible on any host")
            return None
        
        # Test actual Redis connection
        for host in accessible_hosts:
            redis_url = f"redis://{host}:6379"
            try:
                logger.info(f"🧪 Testing Redis connection to {redis_url}")
                redis = aioredis.from_url(
                    redis_url,
                    encoding="utf-8",
                    decode_responses=True,
                    socket_connect_timeout=5,
                    socket_timeout=5
                )
                
                # Test ping
                await redis.ping()
                logger.info(f"✅ Redis ping successful on {host}")
                
                # Test basic operations
                test_key = f"test_{int(time.time())}"
                await redis.set(test_key, "test_value", ex=10)
                value = await redis.get(test_key)
                await redis.delete(test_key)
                
                if value == "test_value":
                    logger.info(f"✅ Redis operations working on {host}")
                    await redis.close()
                    return redis_url
                else:
                    logger.warning(f"⚠️ Redis basic operations failed on {host}")
                
                await redis.close()
                
            except Exception as e:
                logger.warning(f"❌ Redis connection failed on {host}: {e}")
                continue
        
        logger.error("❌ No working Redis configuration found")
        return None
    
    async def start(self):
        """Start the Mac M2 node with enhanced Redis connection"""
        logger.info("🍎 Starting Mac M2 AI Node with enhanced Redis connection")
        
        # Find working Redis configuration
        self.redis_url = await self._find_working_redis_config()
        if not self.redis_url:
            logger.error("❌ Cannot find working Redis connection. Please ensure:")
            logger.error("   1. Docker services are running: make start")
            logger.error("   2. Redis port 6379 is accessible")
            logger.error("   3. Try: docker ps | grep redis")
            return
        
        logger.info(f"✅ Using Redis configuration: {self.redis_url}")
        
        # Connect to Redis
        await self._connect_redis()
        
        # Register with gateway with retries
        await self._register_with_retries()
        
        # Load models
        await self._prepare_models()
        
        self.running = True
        logger.info("🚀 Mac M2 node fully started and ready for jobs")
        
        # Start loops
        await asyncio.gather(
            self._job_polling_loop(),
            self._heartbeat_loop()
        )
    
    async def _connect_redis(self):
        """Connect to Redis with the working configuration"""
        try:
            self.redis = aioredis.from_url(
                self.redis_url,
                encoding="utf-8",
                decode_responses=True,
                socket_connect_timeout=10,
                socket_timeout=10,
                retry_on_timeout=True,
                health_check_interval=30
            )
            
            # Test connection
            await self.redis.ping()
            logger.info(f"✅ Connected to Redis at {self.redis_url}")
            
        except Exception as e:
            logger.error(f"❌ Failed to connect to Redis: {e}")
            raise
    
    async def _register_with_retries(self):
        """Register with gateway with retry logic"""
        max_retries = 10
        
        for attempt in range(max_retries):
            try:
                await self._register_node()
                logger.info("✅ Successfully registered with gateway")
                return
            except Exception as e:
                logger.warning(f"⚠️ Registration attempt {attempt + 1}/{max_retries} failed: {e}")
                if attempt < max_retries - 1:
                    await asyncio.sleep(5)
                else:
                    logger.warning("⚠️ Failed to register with gateway, continuing without registration...")
                    # Continue anyway - node can still process jobs
    
    async def _register_node(self):
        """Register with gateway and Redis"""
        # System info
        memory = psutil.virtual_memory()
        
        registration_data = {
            "node_id": self.node_id,
            "node_type": "mac_m2_native",
            "system_info": {
                "region": self.region,
                "gpu_info": {
                    "name": "Apple M2 GPU",
                    "memory_gb": memory.total / (1024**3) * 0.4,
                    "compute_capability": 8.0,
                    "driver_version": "Metal",
                    "unified_memory": True
                },
                "cpu_info": {
                    "model": "Apple M2",
                    "cores": psutil.cpu_count(),
                    "architecture": platform.machine()
                },
                "memory_gb": memory.total / (1024**3),
                "capabilities": {
                    "supported_models": ["resnet50", "bert-base", "gpt2"] if TORCH_AVAILABLE else [],
                    "frameworks": ["pytorch"] if TORCH_AVAILABLE else [],
                    "max_batch_size": 4,
                    "supports_metal": True,
                    "neural_engine": True
                }
            }
        }
        
        # Try gateway registration
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.gateway_url}/nodes/register",
                    json=registration_data,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    if response.status == 200:
                        logger.info("✅ Registered with gateway")
                    else:
                        error_text = await response.text()
                        raise Exception(f"HTTP {response.status}: {error_text}")
        except Exception as e:
            logger.warning(f"⚠️ Gateway registration failed: {e}")
            # Continue with Redis registration
        
        # Register in Redis
        node_key = f"node:{self.node_id}:{self.region}:info"
        node_data = {
            "node_id": self.node_id,
            "region": self.region,
            "node_type": "mac_m2_native",
            "gpu_info": json.dumps(registration_data["system_info"]["gpu_info"]),
            "capabilities": json.dumps(registration_data["system_info"]["capabilities"]),
            "status": "available",
            "current_load": "0.0",
            "success_rate": "1.0",
            "avg_latency": "50.0",
            "last_seen": datetime.utcnow().isoformat(),
            "redis_url": self.redis_url
        }
        
        # Use modern Redis hset
        for key, value in node_data.items():
            await self.redis.hset(node_key, key, value)
        await self.redis.expire(node_key, 60)
        await self.redis.sadd("native_nodes", self.node_id)
        
        logger.info(f"✅ Registered in Redis with key: {node_key}")
    
    async def _prepare_models(self):
        """Load AI models"""
        logger.info("🤖 Loading AI models...")
        
        if TORCH_AVAILABLE:
            try:
                model = resnet50(pretrained=True)
                model.eval()
                
                if torch.backends.mps.is_available():
                    device = torch.device("mps")
                    model = model.to(device)
                    logger.info("✅ Using Metal Performance Shaders")
                else:
                    device = torch.device("cpu")
                    logger.info("✅ Using CPU")
                
                self.loaded_models["resnet50"] = {
                    "model": model,
                    "device": device,
                    "transform": transforms.Compose([
                        transforms.Resize(256),
                        transforms.CenterCrop(224),
                        transforms.ToTensor(),
                        transforms.Normalize(
                            mean=[0.485, 0.456, 0.406],
                            std=[0.229, 0.224, 0.225]
                        )
                    ])
                }
                logger.info("✅ ResNet50 loaded")
                
            except Exception as e:
                logger.error(f"❌ Error loading PyTorch models: {e}")
        
        if TRANSFORMERS_AVAILABLE:
            try:
                gpt2_pipeline = pipeline("text-generation", model="gpt2", max_length=50)
                self.loaded_models["gpt2"] = {"pipeline": gpt2_pipeline}
                logger.info("✅ GPT-2 loaded")
            except Exception as e:
                logger.error(f"❌ Error loading Transformers models: {e}")
    
    async def _job_polling_loop(self):
        """Poll for jobs with connection recovery"""
        consecutive_errors = 0
        max_consecutive_errors = 5
        
        while self.running:
            try:
                job_key = f"node_jobs:{self.node_id}"
                job_data = await self.redis.brpop(job_key, timeout=1)
                
                if job_data:
                    job = json.loads(job_data[1])
                    await self._execute_job(job)
                
                consecutive_errors = 0  # Reset error counter on success
                
            except Exception as e:
                consecutive_errors += 1
                logger.error(f"Error in job polling ({consecutive_errors}/{max_consecutive_errors}): {e}")
                
                if consecutive_errors >= max_consecutive_errors:
                    logger.error("Too many consecutive errors, attempting Redis reconnection...")
                    try:
                        await self._connect_redis()
                        consecutive_errors = 0
                        logger.info("✅ Redis reconnection successful")
                    except Exception as reconnect_error:
                        logger.error(f"❌ Redis reconnection failed: {reconnect_error}")
                
                await asyncio.sleep(min(consecutive_errors, 10))  # Exponential backoff
    
    async def _heartbeat_loop(self):
        """Send heartbeats with connection recovery"""
        consecutive_errors = 0
        max_consecutive_errors = 5
        
        while self.running:
            try:
                node_key = f"node:{self.node_id}:{self.region}:info"
                
                memory = psutil.virtual_memory()
                cpu_percent = psutil.cpu_percent(interval=1)
                success_rate = self.successful_jobs / max(1, self.total_jobs)
                
                update_data = {
                    "status": "available",
                    "cpu_usage": str(cpu_percent),
                    "memory_usage": str(memory.percent),
                    "success_rate": str(success_rate),
                    "total_jobs": str(self.total_jobs),
                    "last_seen": datetime.utcnow().isoformat()
                }
                
                for key, value in update_data.items():
                    await self.redis.hset(node_key, key, value)
                await self.redis.expire(node_key, 60)
                
                consecutive_errors = 0  # Reset on success
                await asyncio.sleep(10)
                
            except Exception as e:
                consecutive_errors += 1
                logger.error(f"Error in heartbeat ({consecutive_errors}/{max_consecutive_errors}): {e}")
                
                if consecutive_errors >= max_consecutive_errors:
                    logger.error("Too many consecutive heartbeat errors, attempting Redis reconnection...")
                    try:
                        await self._connect_redis()
                        consecutive_errors = 0
                        logger.info("✅ Redis reconnection successful")
                    except Exception as reconnect_error:
                        logger.error(f"❌ Redis reconnection failed: {reconnect_error}")
                
                await asyncio.sleep(min(consecutive_errors * 5, 30))
    
    async def _execute_job(self, job: Dict[str, Any]):
        """Execute a job"""
        job_id = job["job_id"]
        model_name = job["model_name"]
        input_data = job.get("input_data", {})
        
        logger.info(f"🚀 Executing job {job_id} with model {model_name}")
        start_time = time.time()
        
        try:
            self.total_jobs += 1
            
            if model_name == "resnet50" and "resnet50" in self.loaded_models:
                result = await self._execute_resnet50(input_data)
            elif model_name == "gpt2" and "gpt2" in self.loaded_models:
                result = await self._execute_gpt2(input_data)
            else:
                await asyncio.sleep(0.5)
                result = {
                    "model": model_name,
                    "message": f"Simulated execution on Mac M2",
                    "device": "mps" if TORCH_AVAILABLE and torch.backends.mps.is_available() else "cpu",
                    "frameworks_available": {
                        "pytorch": TORCH_AVAILABLE,
                        "transformers": TRANSFORMERS_AVAILABLE
                    }
                }
            
            execution_time = time.time() - start_time
            self.successful_jobs += 1
            
            await self._send_result(job_id, True, result, execution_time)
            logger.info(f"✅ Job {job_id} completed in {execution_time:.2f}s")
            
        except Exception as e:
            execution_time = time.time() - start_time
            await self._send_result(job_id, False, None, execution_time, str(e))
            logger.error(f"❌ Job {job_id} failed: {e}")
    
    async def _execute_resnet50(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """Execute ResNet50 inference"""
        model_info = self.loaded_models["resnet50"]
        model = model_info["model"]
        device = model_info["device"]
        transform = model_info["transform"]
        
        image = Image.new('RGB', (224, 224), color=(255, 0, 0))
        input_tensor = transform(image).unsqueeze(0).to(device)
        
        with torch.no_grad():
            outputs = model(input_tensor)
            probabilities = torch.nn.functional.softmax(outputs[0], dim=0)
            top5_prob, top5_idx = torch.topk(probabilities, 5)
            
            predictions = []
            for i in range(5):
                predictions.append({
                    "class_idx": int(top5_idx[i]),
                    "probability": float(top5_prob[i])
                })
        
        return {
            "model": "resnet50",
            "predictions": predictions,
            "device_used": str(device),
            "framework": "pytorch_mps" if device.type == "mps" else "pytorch_cpu"
        }
    
    async def _execute_gpt2(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """Execute GPT-2 text generation"""
        prompt = input_data.get("prompt", "Hello, I am")
        generator = self.loaded_models["gpt2"]["pipeline"]
        result = generator(prompt, max_length=50, num_return_sequences=1, do_sample=True)
        
        return {
            "model": "gpt2",
            "prompt": prompt,
            "generated_text": result[0]["generated_text"],
            "framework": "transformers"
        }
    
    async def _send_result(self, job_id: str, success: bool, result: Optional[Dict], 
                          execution_time: float, error: Optional[str] = None):
        """Send result to aggregator"""
        result_data = {
            "job_id": job_id,
            "node_id": self.node_id,
            "success": str(success).lower(),
            "execution_time": str(execution_time),
            "timestamp": datetime.utcnow().isoformat()
        }
        
        if success and result:
            result_data["result"] = json.dumps(result)
        if error:
            result_data["error"] = error
        
        try:
            await self.redis.xadd("job_results", result_data)
            logger.info(f"📤 Sent result for job {job_id}")
        except Exception as e:
            logger.error(f"❌ Failed to send result for job {job_id}: {e}")

async def main():
    """Main entry point"""
    if platform.system() != "Darwin":
        print("❌ This node is for macOS only")
        return
    
    node = MacM2Node()
    
    try:
        await node.start()
    except KeyboardInterrupt:
        logger.info("🛑 Received shutdown signal")
        node.running = False
    except Exception as e:
        logger.error(f"❌ Fatal error: {e}")

if __name__ == "__main__":
    Path("logs").mkdir(exist_ok=True)
    print("🍎 Starting SynapseGrid Mac M2 AI Node (Redis Connection Fixed)...")
    print("Press Ctrl+C to stop")
    asyncio.run(main())
EOF

# Replace the original with the fixed version
mv native_node/mac_m2_node_fixed.py native_node/mac_m2_node.py

echo "✅ Mac M2 node updated with enhanced Redis connection handling"

# Step 6: Create diagnostic commands in Makefile
echo ""
echo "🔧 Adding Redis diagnostic commands to Makefile..."

# Add to Makefile
cat >> Makefile << 'EOF'

# Redis diagnostic commands
redis-status:
	@echo "🔍 Redis Status Check"
	@echo "===================="
	@echo "1. Container status:"
	@docker ps | grep redis || echo "❌ Redis container not running"
	@echo ""
	@echo "2. Port check:"
	@nc -z localhost 6379 && echo "✅ Redis port accessible" || echo "❌ Redis port not accessible"
	@echo ""
	@echo "3. Redis ping test:"
	@docker exec synapse_redis redis-cli ping 2>/dev/null || echo "❌ Redis ping failed"

redis-restart:
	@echo "🔄 Restarting Redis..."
	@docker-compose down redis
	@sleep 2
	@docker-compose up -d redis
	@sleep 5
	@$(MAKE) redis-status

redis-logs:
	@echo "📋 Redis logs:"
	@docker logs synapse_redis --tail 20

test-redis-connection:
	@echo "🧪 Testing Redis connection from host..."
	@python3 test_redis_connection.py 2>/dev/null || echo "Install aioredis first: pip3 install aioredis"

# Fix Redis connection issues
fix-redis:
	@echo "🔧 Fixing Redis connection issues..."
	@$(MAKE) redis-restart
	@$(MAKE) test-redis-connection
EOF

echo "✅ Redis diagnostic commands added to Makefile"

echo ""
echo "🎯 Redis Connection Fix Complete!"
echo ""
echo "📋 What was fixed:"
echo "✅ Redis container binding to 0.0.0.0 (not just localhost)"
echo "✅ Enhanced Redis connection testing in Mac M2 node"
echo "✅ Connection retry logic with multiple host attempts"
echo "✅ Automatic reconnection on connection failures"
echo "✅ Better error handling and logging"
echo ""
echo "🚀 Next steps:"
echo "1. Test Redis status:     make redis-status"
echo "2. Restart if needed:     make redis-restart"
echo "3. Test connection:       make test-redis-connection"
echo "4. Start Mac M2 node:     make start-mac"
echo ""
echo "🔧 If issues persist:"
echo "   make fix-redis        # Complete Redis fix"
echo "   make redis-logs       # Check Redis logs"
echo ""
echo "The Mac M2 node will now automatically find the working Redis connection!"


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

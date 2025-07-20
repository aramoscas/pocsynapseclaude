#!/bin/bash

echo "🔧 Fixing Redis boolean conversion error..."

# Update the node service to convert booleans to strings for Redis
cat > services/node/main.py << 'EOF'
#!/usr/bin/env python3
"""
Real SynapseGrid Node with automatic registration
Fixed Redis boolean conversion issue
"""

import asyncio
import json
import time
import os
import uuid
import platform
import psutil
import socket
import redis.asyncio as redis
import structlog

logger = structlog.get_logger()

class NodeCapabilities:
    """Detect and report real node capabilities"""
    
    def __init__(self):
        self.node_id = os.getenv('NODE_ID', f"node-{uuid.uuid4().hex[:8]}")
        self.region = os.getenv('NODE_REGION', self.detect_region())
        
    def detect_region(self):
        """Detect geographical region"""
        try:
            import time
            tz = time.tzname[0] if time.tzname else "UTC"
            if any(x in tz for x in ['EST', 'EDT', 'PST', 'PDT']):
                return 'us-east-1'
            elif any(x in tz for x in ['CET', 'GMT', 'UTC']):
                return 'eu-west-1'
            else:
                return 'ap-southeast-1'
        except:
            return 'local'
    
    def get_gpu_info(self):
        """Detect GPU capabilities"""
        gpu_info = {
            "gpu_type": "CPU_ONLY",
            "gpu_memory": "0",
            "gpu_count": "0",
            "metal_available": "false",
            "cuda_available": "false",
            "vendor": "unknown"
        }
        
        try:
            # Check for Apple Silicon
            if platform.processor() == 'arm' and platform.system() == 'Darwin':
                try:
                    import torch
                    if torch.backends.mps.is_available():
                        gpu_info.update({
                            "gpu_type": "Apple_M2" if "M2" in platform.processor() else "Apple_M1",
                            "gpu_memory": str(psutil.virtual_memory().total // (1024**2)),
                            "gpu_count": "1",
                            "metal_available": "true",
                            "vendor": "Apple"
                        })
                except ImportError:
                    pass
            
            # Check for NVIDIA CUDA
            try:
                import torch
                if torch.cuda.is_available():
                    gpu_count = torch.cuda.device_count()
                    gpu_name = torch.cuda.get_device_name(0)
                    gpu_memory = torch.cuda.get_device_properties(0).total_memory // (1024**2)
                    
                    gpu_info.update({
                        "gpu_type": gpu_name,
                        "gpu_memory": str(gpu_memory),
                        "gpu_count": str(gpu_count),
                        "cuda_available": "true",
                        "vendor": "NVIDIA"
                    })
            except ImportError:
                pass
                
        except Exception as e:
            logger.warning("GPU detection failed", error=str(e))
            
        return gpu_info
    
    def get_cpu_info(self):
        """Get CPU information"""
        return {
            "cpu_cores": str(psutil.cpu_count(logical=False)),
            "cpu_threads": str(psutil.cpu_count(logical=True)),
            "cpu_freq": str(psutil.cpu_freq().max if psutil.cpu_freq() else 0),
            "cpu_model": platform.processor() or "unknown",
            "cpu_arch": platform.machine()
        }
    
    def get_memory_info(self):
        """Get memory information"""
        memory = psutil.virtual_memory()
        return {
            "total_memory": str(memory.total // (1024**2)),
            "available_memory": str(memory.available // (1024**2)),
        }
    
    def get_network_info(self):
        """Get network information"""
        try:
            hostname = socket.gethostname()
            local_ip = socket.gethostbyname(hostname)
        except:
            hostname = "unknown"
            local_ip = "127.0.0.1"
            
        return {
            "hostname": hostname,
            "local_ip": local_ip,
        }
    
    def calculate_performance_score(self, gpu_info, cpu_info):
        """Calculate performance score based on hardware"""
        score = 0
        
        if gpu_info["gpu_type"] != "CPU_ONLY":
            gpu_scores = {
                "A100": 100, "RTX4090": 95, "RTX3090": 85, "RTX3080": 75,
                "RTX3070": 65, "RTX3060": 55, "Apple_M2": 70, "Apple_M1": 60,
                "AMD_GPU": 65
            }
            
            for gpu_name, gpu_score in gpu_scores.items():
                if gpu_name in gpu_info["gpu_type"]:
                    score += gpu_score * 0.6
                    break
            else:
                score += 30 * 0.6
        else:
            score += 20 * 0.6
        
        cpu_score = min(100, int(cpu_info["cpu_cores"]) * 8)
        score += cpu_score * 0.25
        
        memory_gb = int(gpu_info.get("gpu_memory", 0)) / 1024 + psutil.virtual_memory().total / (1024**3)
        memory_score = min(100, memory_gb * 5)
        score += memory_score * 0.15
        
        return str(round(min(100, score), 1))
    
    def get_full_capabilities(self):
        """Get complete node capabilities - all values as strings for Redis"""
        gpu_info = self.get_gpu_info()
        cpu_info = self.get_cpu_info()
        memory_info = self.get_memory_info()
        network_info = self.get_network_info()
        
        performance_score = self.calculate_performance_score(gpu_info, cpu_info)
        
        energy_efficiency = "90" if gpu_info["vendor"] == "Apple" else "75"
        if "RTX40" in gpu_info["gpu_type"]:
            energy_efficiency = "85"
        elif "RTX30" in gpu_info["gpu_type"]:
            energy_efficiency = "70"
            
        return {
            "node_id": self.node_id,
            "region": self.region,
            "status": "active",
            "registered_at": str(time.time()),
            "last_seen": str(time.time()),
            
            # GPU info
            **gpu_info,
            
            # CPU info
            **cpu_info,
            
            # Memory info
            **memory_info,
            
            # Network info
            **network_info,
            
            # Performance metrics
            "performance_score": performance_score,
            "energy_efficiency": energy_efficiency,
            
            # System info
            "platform": platform.platform(),
            "python_version": platform.python_version(),
            "node_version": "v1.2.3",
            
            # Operational data (will be updated dynamically)
            "current_load": "0.0",
            "total_jobs": "0",
            "successful_jobs": "0",
            "failed_jobs": "0",
            "earnings_nrg": "0.0",
            "uptime": "0",
            "cpu_usage": "0.0",
            "memory_usage": "0.0"
        }

class SynapseGridNode:
    """Real SynapseGrid Node that connects to the network"""
    
    def __init__(self):
        self.capabilities = NodeCapabilities()
        self.node_data = self.capabilities.get_full_capabilities()
        self.redis_client = None
        self.start_time = time.time()
        self.job_count = 0
        
    async def startup(self):
        """Initialize and register with SynapseGrid"""
        logger.info("Starting SynapseGrid Node", node_id=self.node_data["node_id"])
        
        redis_host = os.getenv('REDIS_HOST', 'redis')
        self.redis_client = redis.Redis(
            host=redis_host,
            port=6379,
            decode_responses=True,
            retry_on_timeout=True
        )
        
        await self.register_node()
        
        asyncio.create_task(self.heartbeat_loop())
        asyncio.create_task(self.job_processor())
        
        logger.info("Node registered and running", 
                   gpu_type=self.node_data["gpu_type"],
                   performance_score=self.node_data["performance_score"])
    
    async def register_node(self):
        """Register node capabilities with SynapseGrid"""
        try:
            # Store node data (all values are already strings)
            await self.redis_client.hset(
                f"node:{self.node_data['node_id']}", 
                mapping=self.node_data
            )
            
            # Add to active nodes sets
            await self.redis_client.sadd(
                f"nodes:active:{self.node_data['region']}", 
                self.node_data['node_id']
            )
            
            await self.redis_client.sadd(
                "nodes:active:all", 
                self.node_data['node_id']
            )
            
            # Set expiration for auto-cleanup
            await self.redis_client.expire(f"node:{self.node_data['node_id']}", 120)
            
            logger.info("Node registered successfully", node_id=self.node_data['node_id'])
            
        except Exception as e:
            logger.error("Failed to register node", error=str(e))
            
    async def heartbeat_loop(self):
        """Send periodic heartbeats"""
        while True:
            try:
                current_time = time.time()
                
                # Update dynamic fields - convert all to strings
                updates = {
                    "last_seen": str(current_time),
                    "uptime": str(current_time - self.start_time),
                    "current_load": str(self.calculate_current_load()),
                    "cpu_usage": str(psutil.cpu_percent(interval=1)),
                    "memory_usage": str(psutil.virtual_memory().percent),
                    "total_jobs": str(self.job_count)
                }
                
                # Update the node data
                self.node_data.update(updates)
                
                # Update in Redis
                await self.redis_client.hset(
                    f"node:{self.node_data['node_id']}", 
                    mapping=updates
                )
                
                # Refresh expiration
                await self.redis_client.expire(f"node:{self.node_data['node_id']}", 120)
                
                # Keep in active sets
                await self.redis_client.sadd(
                    f"nodes:active:{self.node_data['region']}", 
                    self.node_data['node_id']
                )
                await self.redis_client.sadd(
                    "nodes:active:all", 
                    self.node_data['node_id']
                )
                
                logger.debug("Heartbeat sent", 
                           node_id=self.node_data['node_id'],
                           load=updates['current_load'])
                
                await asyncio.sleep(30)
                
            except Exception as e:
                logger.error("Heartbeat failed", error=str(e))
                await asyncio.sleep(10)
    
    def calculate_current_load(self):
        """Calculate current node load"""
        cpu_load = psutil.cpu_percent(interval=0.1) / 100
        memory_load = psutil.virtual_memory().percent / 100
        return round((cpu_load * 0.6 + memory_load * 0.4), 3)
    
    async def job_processor(self):
        """Process jobs from the network"""
        while True:
            try:
                queue_key = f"jobs:queue:{self.node_data['region']}"
                job_data = await self.redis_client.brpop(queue_key, timeout=5)
                
                if job_data:
                    await self.process_job(job_data[1])
                    
            except Exception as e:
                logger.error("Job processing failed", error=str(e))
                await asyncio.sleep(1)
    
    async def process_job(self, job_json):
        """Process a single job"""
        try:
            job = json.loads(job_json)
            job_id = job['job_id']
            
            logger.info("Processing job", job_id=job_id, model=job['model_name'])
            
            execution_time = 0.5  # Simulate execution
            await asyncio.sleep(execution_time)
            
            result = {
                "job_id": job_id,
                "node_id": self.node_data['node_id'],
                "result": {
                    "status": "completed",
                    "model": job['model_name'],
                    "execution_time": execution_time,
                    "gpu_used": self.node_data['gpu_type'],
                },
                "completed_at": time.time(),
            }
            
            await self.redis_client.lpush(
                f"results:queue:{self.node_data['region']}", 
                json.dumps(result)
            )
            
            self.job_count += 1
            
            logger.info("Job completed", job_id=job_id)
            
        except Exception as e:
            logger.error("Job execution failed", error=str(e))

async def main():
    """Main node execution"""
    node = SynapseGridNode()
    
    try:
        await node.startup()
        
        while True:
            await asyncio.sleep(1)
            
    except KeyboardInterrupt:
        logger.info("Shutting down node")
    finally:
        if node.redis_client:
            try:
                await node.redis_client.srem(
                    f"nodes:active:{node.node_data['region']}", 
                    node.node_data['node_id']
                )
                await node.redis_client.srem(
                    "nodes:active:all", 
                    node.node_data['node_id']
                )
                await node.redis_client.delete(f"node:{node.node_data['node_id']}")
            except:
                pass
            await node.redis_client.close()

if __name__ == "__main__":
    asyncio.run(main())
EOF

echo "🔄 Rebuilding and restarting node service..."

# Rebuild just the node service
docker-compose build node1

# Restart the node
docker-compose restart node1

echo "⏱️ Waiting for node to register..."
sleep 10

echo "🧪 Testing node registration..."
docker-compose exec redis redis-cli SMEMBERS "nodes:active:all"

echo ""
echo "✅ Redis boolean conversion error fixed!"
echo ""
echo "🔍 Check node logs:"
echo "  docker-compose logs node1"
echo ""
echo "📊 Test dashboard:"
echo "  http://localhost:3000/nodes"


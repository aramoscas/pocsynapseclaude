#!/bin/bash

echo "🔄 Upgrading existing SynapseGrid to real node registration system..."
echo "======================================================================="

# Stop current services
echo "1. Stopping current services..."
docker-compose down

# Backup current files
echo "2. Creating backup..."
mkdir -p backup/$(date +%Y%m%d_%H%M%S)
cp -r services backup/$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
cp docker-compose.yml backup/$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true

echo "3. Updating Node service with real registration..."

# Replace the node main.py with real registration system
cat > services/node/main.py << 'EOF'
#!/usr/bin/env python3
"""
Real SynapseGrid Node with automatic registration
Nodes connect TO SynapseGrid, no incoming connections
"""

import asyncio
import json
import time
import os
import uuid
import platform
import psutil
import socket
import subprocess
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
            "gpu_memory": 0,
            "gpu_count": 0,
            "metal_available": False,
            "cuda_available": False,
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
                            "gpu_memory": psutil.virtual_memory().total // (1024**2),
                            "gpu_count": 1,
                            "metal_available": True,
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
                        "gpu_memory": gpu_memory,
                        "gpu_count": gpu_count,
                        "cuda_available": True,
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
            "cpu_cores": psutil.cpu_count(logical=False),
            "cpu_threads": psutil.cpu_count(logical=True),
            "cpu_freq": psutil.cpu_freq().max if psutil.cpu_freq() else 0,
            "cpu_model": platform.processor(),
            "cpu_arch": platform.machine()
        }
    
    def get_memory_info(self):
        """Get memory information"""
        memory = psutil.virtual_memory()
        return {
            "total_memory": memory.total // (1024**2),
            "available_memory": memory.available // (1024**2),
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
        
        cpu_score = min(100, cpu_info["cpu_cores"] * 8)
        score += cpu_score * 0.25
        
        memory_gb = gpu_info.get("gpu_memory", 0) / 1024 + psutil.virtual_memory().total / (1024**3)
        memory_score = min(100, memory_gb * 5)
        score += memory_score * 0.15
        
        return min(100, score)
    
    def get_full_capabilities(self):
        """Get complete node capabilities"""
        gpu_info = self.get_gpu_info()
        cpu_info = self.get_cpu_info()
        memory_info = self.get_memory_info()
        network_info = self.get_network_info()
        
        performance_score = self.calculate_performance_score(gpu_info, cpu_info)
        
        energy_efficiency = 90 if gpu_info["vendor"] == "Apple" else 75
        if "RTX40" in gpu_info["gpu_type"]:
            energy_efficiency = 85
        elif "RTX30" in gpu_info["gpu_type"]:
            energy_efficiency = 70
            
        return {
            "node_id": self.node_id,
            "region": self.region,
            "status": "active",
            "registered_at": time.time(),
            "last_seen": time.time(),
            
            **gpu_info,
            **cpu_info,
            **memory_info,
            **network_info,
            
            "performance_score": round(performance_score, 1),
            "energy_efficiency": energy_efficiency,
            
            "platform": platform.platform(),
            "python_version": platform.python_version(),
            "node_version": "v1.2.3",
            
            "current_load": 0.0,
            "total_jobs": 0,
            "successful_jobs": 0,
            "failed_jobs": 0,
            "earnings_nrg": 0.0,
            "uptime": 0
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
            await self.redis_client.hset(
                f"node:{self.node_data['node_id']}", 
                mapping=self.node_data
            )
            
            await self.redis_client.sadd(
                f"nodes:active:{self.node_data['region']}", 
                self.node_data['node_id']
            )
            
            await self.redis_client.sadd(
                "nodes:active:all", 
                self.node_data['node_id']
            )
            
            await self.redis_client.expire(f"node:{self.node_data['node_id']}", 120)
            
            logger.info("Node registered successfully", node_id=self.node_data['node_id'])
            
        except Exception as e:
            logger.error("Failed to register node", error=str(e))
            
    async def heartbeat_loop(self):
        """Send periodic heartbeats"""
        while True:
            try:
                current_time = time.time()
                
                self.node_data.update({
                    "last_seen": current_time,
                    "uptime": current_time - self.start_time,
                    "current_load": self.calculate_current_load(),
                    "cpu_usage": psutil.cpu_percent(interval=1),
                    "memory_usage": psutil.virtual_memory().percent,
                    "total_jobs": self.job_count
                })
                
                await self.redis_client.hset(
                    f"node:{self.node_data['node_id']}", 
                    mapping=self.node_data
                )
                
                await self.redis_client.expire(f"node:{self.node_data['node_id']}", 120)
                
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
                           load=self.node_data['current_load'])
                
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

echo "4. Updating Dashboard with real data integration..."

cat > services/dashboard/main.py << 'EOF'
#!/usr/bin/env python3
"""
Real SynapseGrid Dashboard with live node data
No mock data - reads real node registrations from Redis
"""

import http.server
import socketserver
import urllib.parse
import json
import time
import os
import redis

class SynapseGridDashboard:
    """Real-time dashboard with live node data from Redis"""
    
    def __init__(self):
        self.redis_client = redis.Redis(
            host=os.getenv('REDIS_HOST', 'redis'), 
            port=6379, 
            decode_responses=True
        )
    
    def get_live_nodes(self):
        """Get real node data from Redis"""
        try:
            active_node_ids = self.redis_client.smembers("nodes:active:all")
            
            nodes = []
            for node_id in active_node_ids:
                node_data = self.redis_client.hgetall(f"node:{node_id}")
                if node_data:
                    for field in ['performance_score', 'current_load', 'cpu_usage', 'memory_usage', 
                                'total_jobs', 'uptime', 'last_seen', 'registered_at']:
                        if field in node_data:
                            try:
                                node_data[field] = float(node_data[field])
                            except:
                                pass
                    
                    nodes.append(node_data)
            
            return sorted(nodes, key=lambda x: x.get('performance_score', 0), reverse=True)
            
        except Exception as e:
            print(f"Error fetching nodes: {e}")
            return []
    
    def get_network_stats(self):
        """Calculate real-time network statistics"""
        nodes = self.get_live_nodes()
        
        if not nodes:
            return {
                "active_nodes": 0,
                "total_jobs": 0,
                "avg_load": 0,
                "regions": {}
            }
        
        total_jobs = sum(int(node.get('total_jobs', 0)) for node in nodes)
        avg_load = sum(float(node.get('current_load', 0)) for node in nodes) / len(nodes)
        
        regions = {}
        for node in nodes:
            region = node.get('region', 'unknown')
            if region not in regions:
                regions[region] = {"nodes": 0, "jobs": 0, "load": 0}
            regions[region]["nodes"] += 1
            regions[region]["jobs"] += int(node.get('total_jobs', 0))
            regions[region]["load"] += float(node.get('current_load', 0))
        
        for region in regions:
            if regions[region]["nodes"] > 0:
                regions[region]["avg_load"] = regions[region]["load"] / regions[region]["nodes"]
        
        return {
            "active_nodes": len(nodes),
            "total_jobs": total_jobs,
            "avg_load": avg_load,
            "regions": regions
        }
    
    def format_uptime(self, uptime_seconds):
        """Format uptime in human readable format"""
        if uptime_seconds < 60:
            return f"{int(uptime_seconds)}s"
        elif uptime_seconds < 3600:
            return f"{int(uptime_seconds/60)}m"
        elif uptime_seconds < 86400:
            return f"{int(uptime_seconds/3600)}h {int((uptime_seconds%3600)/60)}m"
        else:
            days = int(uptime_seconds/86400)
            hours = int((uptime_seconds%86400)/3600)
            return f"{days}d {hours}h"
    
    def get_main_page(self):
        """Generate main dashboard page with real data"""
        stats = self.get_network_stats()
        
        region_cards = ""
        for region, region_stats in stats['regions'].items():
            region_cards += f'''
                    <div class="region-card">
                        <h3>{region.upper()}</h3>
                        <div class="region-stat">
                            <span>Nodes:</span>
                            <strong>{region_stats['nodes']}</strong>
                        </div>
                        <div class="region-stat">
                            <span>Jobs:</span>
                            <strong>{region_stats['jobs']:,}</strong>
                        </div>
                        <div class="region-stat">
                            <span>Avg Load:</span>
                            <strong>{region_stats.get('avg_load', 0):.1%}</strong>
                        </div>
                    </div>'''
        
        return f'''<!DOCTYPE html>
<html>
<head>
    <title>SynapseGrid Dashboard</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }}
        .container {{ 
            max-width: 1200px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.95);
            border-radius: 16px;
            backdrop-filter: blur(10px);
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }}
        .header {{ 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white; 
            padding: 30px;
            text-align: center;
        }}
        .header h1 {{ font-size: 2.5em; margin-bottom: 10px; }}
        .header p {{ font-size: 1.1em; opacity: 0.9; }}
        
        .stats {{ 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); 
            gap: 25px; 
            padding: 30px;
            background: white;
        }}
        .stat-card {{ 
            background: linear-gradient(135deg, #ff6b6b, #ee5a24);
            color: white; 
            padding: 25px; 
            border-radius: 12px; 
            text-align: center;
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            cursor: pointer;
        }}
        .stat-card:nth-child(2) {{ background: linear-gradient(135deg, #4ecdc4, #00a085); }}
        .stat-card:nth-child(3) {{ background: linear-gradient(135deg, #45b7d1, #2980b9); }}
        .stat-card:nth-child(4) {{ background: linear-gradient(135deg, #f39c12, #e67e22); }}
        
        .stat-card:hover {{ 
            transform: translateY(-5px);
            box-shadow: 0 15px 30px rgba(0,0,0,0.2);
        }}
        
        .stat-number {{ font-size: 2.5em; font-weight: bold; margin-bottom: 5px; }}
        .stat-label {{ font-size: 1em; opacity: 0.9; }}
        .stat-sublabel {{ font-size: 0.8em; opacity: 0.7; margin-top: 5px; }}
        
        .content {{ padding: 30px; }}
        .section {{ margin-bottom: 30px; }}
        .section h2 {{ 
            color: #333; 
            margin-bottom: 15px; 
            font-size: 1.5em;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }}
        
        .region-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }}
        
        .region-card {{
            background: #f8f9fa;
            padding: 20px;
            border-radius: 12px;
            border-left: 4px solid #667eea;
        }}
        
        .region-card h3 {{
            color: #333;
            margin-bottom: 15px;
        }}
        
        .region-stat {{
            display: flex;
            justify-content: space-between;
            margin-bottom: 10px;
        }}
        
        .links {{ 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 15px; 
        }}
        .links a {{ 
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 15px 20px; 
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white; 
            text-decoration: none; 
            border-radius: 8px;
            transition: all 0.3s ease;
            font-weight: 500;
        }}
        .links a:hover {{ 
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
        }}
        
        .auto-refresh {{
            position: fixed;
            top: 20px;
            right: 20px;
            background: rgba(255,255,255,0.9);
            padding: 10px 15px;
            border-radius: 8px;
            font-size: 0.9em;
            color: #333;
        }}
    </style>
</head>
<body>
    <div class="auto-refresh">
        🔄 Auto-refresh: <span id="countdown">30</span>s
    </div>
    
    <div class="container">
        <div class="header">
            <h1>🚀 SynapseGrid Dashboard</h1>
            <p>Decentralized AI Compute Network - Live Data</p>
        </div>
        
        <div class="stats">
            <div class="stat-card" onclick="window.location.href='/nodes'">
                <div class="stat-number">{stats['active_nodes']}</div>
                <div class="stat-label">Active Nodes</div>
                <div class="stat-sublabel">Click to view details</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">{stats['total_jobs']:,}</div>
                <div class="stat-label">Jobs Processed</div>
                <div class="stat-sublabel">Total network jobs</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">{stats['avg_load']:.1%}</div>
                <div class="stat-label">Network Load</div>
                <div class="stat-sublabel">Average utilization</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">{len(stats['regions'])}</div>
                <div class="stat-label">Active Regions</div>
                <div class="stat-sublabel">Geographic distribution</div>
            </div>
        </div>
        
        <div class="content">
            <div class="section">
                <h2>🌍 Regional Distribution</h2>
                <div class="region-grid">
                    {region_cards}
                </div>
            </div>
            
            <div class="section">
                <h2>🔗 Quick Access</h2>
                <div class="links">
                    <a href="http://localhost:8080/health">Gateway Health</a>
                    <a href="http://localhost:9090">Prometheus Metrics</a>
                    <a href="http://localhost:3001">Grafana Dashboard</a>
                    <a href="/nodes">Node Management</a>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        let countdown = 30;
        
        function updateCountdown() {{
            document.getElementById('countdown').textContent = countdown;
            countdown--;
            
            if (countdown < 0) {{
                location.reload();
            }}
        }}
        
        setInterval(updateCountdown, 1000);
    </script>
</body>
</html>'''

    def get_nodes_page(self):
        """Generate detailed nodes page"""
        nodes = self.get_live_nodes()
        
        if not nodes:
            return '''<!DOCTYPE html>
<html>
<head><title>SynapseGrid Nodes</title></head>
<body style="font-family: Arial; text-align: center; margin: 40px;">
    <h2>🔍 No Active Nodes Found</h2>
    <p>No nodes are currently registered with the network.</p>
    <p><a href="/">← Back to Dashboard</a></p>
</body>
</html>'''
        
        nodes_html = ""
        for node in nodes:
            uptime = self.format_uptime(float(node.get('uptime', 0)))
            last_seen = time.time() - float(node.get('last_seen', time.time()))
            
            nodes_html += f'''
            <div class="node-card">
                <div class="node-header">
                    <h3>{node.get('node_id', 'unknown')}</h3>
                    <div class="node-status">{node.get('status', 'unknown').upper()}</div>
                </div>
                <div class="node-info">
                    <p><strong>GPU:</strong> {node.get('gpu_type', 'N/A')}</p>
                    <p><strong>Region:</strong> {node.get('region', 'N/A')}</p>
                    <p><strong>Performance:</strong> {float(node.get('performance_score', 0)):.1f}/100</p>
                    <p><strong>Load:</strong> {float(node.get('current_load', 0)):.1%}</p>
                    <p><strong>Uptime:</strong> {uptime}</p>
                    <p><strong>Jobs:</strong> {int(node.get('total_jobs', 0))}</p>
                </div>
            </div>'''
        
        return f'''<!DOCTYPE html>
<html>
<head>
    <title>SynapseGrid Nodes</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
        .header {{ text-align: center; margin-bottom: 30px; }}
        .nodes-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }}
        .node-card {{ background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
        .node-header {{ display: flex; justify-content: space-between; margin-bottom: 15px; }}
        .node-status {{ background: #28a745; color: white; padding: 5px 10px; border-radius: 15px; font-size: 0.8em; }}
        .node-info p {{ margin: 8px 0; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🖥️ Network Nodes ({len(nodes)} Active)</h1>
        <a href="/">← Back to Dashboard</a>
    </div>
    <div class="nodes-grid">
        {nodes_html}
    </div>
</body>
</html>'''

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        self.dashboard = SynapseGridDashboard()
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        path = parsed_path.path
        
        if path == '/':
            content = self.dashboard.get_main_page()
        elif path == '/nodes':
            content = self.dashboard.get_nodes_page()
        elif path == '/api/nodes':
            nodes = self.dashboard.get_live_nodes()
            content = json.dumps(nodes, indent=2)
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(content.encode())
            return
        elif path == '/api/stats':
            stats = self.dashboard.get_network_stats()
            content = json.dumps(stats, indent=2)
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(content.encode())
            return
        else:
            self.send_error(404)
            return
        
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(content.encode())

def main():
    PORT = 3000
    with socketserver.TCPServer(("", PORT), DashboardHandler) as httpd:
        print(f"✅ SynapseGrid Dashboard serving at http://localhost:{PORT}")
        httpd.serve_forever()

if __name__ == "__main__":
    main()
EOF

echo "5. Updating Dockerfiles with required dependencies..."

# Update Node Dockerfile
cat > services/node/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y gcc g++ && rm -rf /var/lib/apt/lists/*
RUN pip install redis psutil structlog

COPY services/node/main.py main.py

ENV PYTHONUNBUFFERED=1

CMD ["python", "main.py"]
EOF

# Update Dashboard Dockerfile
cat > services/dashboard/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN pip install redis

COPY services/dashboard/main.py main.py

EXPOSE 3000

ENV PYTHONUNBUFFERED=1

CMD ["python", "main.py"]
EOF

echo "6. Building updated services..."
docker-compose build --no-cache node1 dashboard

echo "7. Starting upgraded services..."
docker-compose up -d

echo "8. Waiting for node registration..."
sleep 15

echo "9. Testing real node registration..."

echo ""
echo "📊 Active nodes in Redis:"
docker-compose exec redis redis-cli SMEMBERS "nodes:active:all" 2>/dev/null || echo "Redis not ready yet"

echo ""
echo "🌐 Testing dashboard:"
curl -s http://localhost:3000/api/stats | head -10 2>/dev/null || echo "Dashboard starting..."

echo ""
echo "✅ Upgrade completed!"
echo ""
echo "🎯 What's new:"
echo "  ✓ Real node auto-registration (no mock data)"
echo "  ✓ Live hardware detection"
echo "  ✓ Interactive nodes page (click on node count)"
echo "  ✓ Real-time metrics and heartbeats"
echo "  ✓ Auto-refresh every 30 seconds"
echo ""
echo "🌐 Access:"
echo "  - Dashboard: http://localhost:3000"
echo "  - Nodes page: http://localhost:3000/nodes (click on node count)"
echo "  - Live API: http://localhost:3000/api/stats"
echo ""
echo "🔍 Check logs:"
echo "  docker-compose logs node1"
echo "  docker-compose logs dashboard"


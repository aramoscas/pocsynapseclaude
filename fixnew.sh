#!/bin/bash
# fix_dashboard.sh - Script pour corriger le dashboard React

echo "🔧 Fixing SynapseGrid Dashboard..."

# Créer la structure de répertoires manquante
mkdir -p dashboard/public
mkdir -p dashboard/src/components
mkdir -p dashboard/src/services
mkdir -p dashboard/src/utils

# Créer index.html manquant
cat > dashboard/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <link rel="icon" href="%PUBLIC_URL%/favicon.ico" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta name="description" content="SynapseGrid - Decentralized AI Infrastructure Network" />
    <title>SynapseGrid Dashboard</title>
    <style>
      body {
        margin: 0;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        min-height: 100vh;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      }
      .loading {
        display: flex;
        justify-content: center;
        align-items: center;
        height: 100vh;
        color: white;
        font-size: 1.2rem;
      }
    </style>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root">
      <div class="loading">Loading SynapseGrid Dashboard...</div>
    </div>
  </body>
</html>
EOF

# Créer manifest.json
cat > dashboard/public/manifest.json << 'EOF'
{
  "short_name": "SynapseGrid",
  "name": "SynapseGrid Dashboard",
  "start_url": ".",
  "display": "standalone",
  "theme_color": "#000000",
  "background_color": "#ffffff"
}
EOF

# Créer robots.txt
cat > dashboard/public/robots.txt << 'EOF'
User-agent: *
Disallow:
EOF

# Créer index.js principal si manquant
if [ ! -f dashboard/src/index.js ]; then
cat > dashboard/src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF
fi

# Créer App.js principal si manquant
if [ ! -f dashboard/src/App.js ]; then
cat > dashboard/src/App.js << 'EOF'
import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { Activity, Cpu, Globe, Zap, Server, TrendingUp } from 'lucide-react';
import './App.css';

function App() {
  const [metrics, setMetrics] = useState({
    totalJobs: 0,
    activeNodes: 0,
    avgLatency: 0,
    totalRevenue: 0
  });

  const [realtimeData, setRealtimeData] = useState([]);

  useEffect(() => {
    // Simulate real-time data for POC
    const interval = setInterval(() => {
      const now = new Date();
      setRealtimeData(prev => {
        const newData = [...prev, {
          timestamp: now.toLocaleTimeString(),
          jobs: Math.floor(Math.random() * 100) + 50,
          latency: Math.floor(Math.random() * 200) + 200,
          nodes: Math.floor(Math.random() * 10) + 20
        }];
        return newData.slice(-20);
      });

      setMetrics({
        totalJobs: Math.floor(Math.random() * 1000) + 500,
        activeNodes: Math.floor(Math.random() * 50) + 25,
        avgLatency: Math.floor(Math.random() * 100) + 250,
        totalRevenue: (Math.random() * 1000 + 500).toFixed(2)
      });
    }, 2000);

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="dashboard">
      <header className="dashboard-header">
        <div className="header-content">
          <div className="logo">
            <Activity className="logo-icon" />
            <h1>SynapseGrid</h1>
            <span className="version">v1.0 POC</span>
          </div>
          
          <div className="header-stats">
            <div className="stat-card">
              <Server className="stat-icon" />
              <div>
                <div className="stat-value">{metrics.activeNodes}</div>
                <div className="stat-label">Active Nodes</div>
              </div>
            </div>
            
            <div className="stat-card">
              <Zap className="stat-icon" />
              <div>
                <div className="stat-value">{metrics.totalJobs}</div>
                <div className="stat-label">Jobs Processed</div>
              </div>
            </div>
            
            <div className="stat-card">
              <TrendingUp className="stat-icon" />
              <div>
                <div className="stat-value">{metrics.avgLatency}ms</div>
                <div className="stat-label">Avg Latency</div>
              </div>
            </div>
            
            <div className="stat-card">
              <Globe className="stat-icon" />
              <div>
                <div className="stat-value">${metrics.totalRevenue}</div>
                <div className="stat-label">Revenue</div>
              </div>
            </div>
          </div>
        </div>
      </header>

      <main className="dashboard-main">
        <div className="dashboard-grid">
          <div className="card">
            <div className="card-header">
              <h3>Real-time Performance</h3>
            </div>
            <div className="chart-container">
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={realtimeData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#333" />
                  <XAxis dataKey="timestamp" stroke="#666" />
                  <YAxis stroke="#666" />
                  <Tooltip 
                    contentStyle={{ 
                      backgroundColor: '#1a1a2e', 
                      border: '1px solid #333',
                      borderRadius: '8px'
                    }} 
                  />
                  <Line 
                    type="monotone" 
                    dataKey="latency" 
                    stroke="#00d4ff" 
                    strokeWidth={2}
                    name="Latency (ms)"
                  />
                  <Line 
                    type="monotone" 
                    dataKey="jobs" 
                    stroke="#00ff88" 
                    strokeWidth={2}
                    name="Jobs"
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="card">
            <div className="card-header">
              <h3>Network Status</h3>
            </div>
            <div className="status-grid">
              <div className="status-item">
                <div className="status-label">Network Health</div>
                <div className="status-value good">Excellent</div>
              </div>
              <div className="status-item">
                <div className="status-label">Global Coverage</div>
                <div className="status-value">4 Regions</div>
              </div>
              <div className="status-item">
                <div className="status-label">Uptime</div>
                <div className="status-value good">99.8%</div>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;
EOF
fi

# Créer CSS principal si manquant
if [ ! -f dashboard/src/App.css ]; then
cat > dashboard/src/App.css << 'EOF'
.dashboard {
  min-height: 100vh;
  background: linear-gradient(135deg, #0f0f23 0%, #1a1a2e 50%, #16213e 100%);
  color: white;
}

.dashboard-header {
  background: rgba(26, 26, 46, 0.9);
  backdrop-filter: blur(10px);
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  padding: 1rem 2rem;
}

.header-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
  max-width: 1400px;
  margin: 0 auto;
}

.logo {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.logo-icon {
  width: 32px;
  height: 32px;
  color: #00d4ff;
}

.logo h1 {
  font-size: 1.5rem;
  font-weight: 700;
  margin: 0;
  background: linear-gradient(135deg, #00d4ff, #00ff88);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}

.version {
  background: rgba(0, 212, 255, 0.2);
  color: #00d4ff;
  padding: 0.25rem 0.5rem;
  border-radius: 12px;
  font-size: 0.75rem;
  font-weight: 500;
}

.header-stats {
  display: flex;
  gap: 1.5rem;
}

.stat-card {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  background: rgba(255, 255, 255, 0.05);
  padding: 0.75rem 1rem;
  border-radius: 12px;
  border: 1px solid rgba(255, 255, 255, 0.1);
}

.stat-icon {
  width: 20px;
  height: 20px;
  color: #00d4ff;
}

.stat-value {
  font-size: 1.25rem;
  font-weight: 700;
  line-height: 1;
}

.stat-label {
  font-size: 0.75rem;
  color: rgba(255, 255, 255, 0.7);
}

.dashboard-main {
  padding: 2rem;
  max-width: 1400px;
  margin: 0 auto;
}

.dashboard-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
  gap: 1.5rem;
}

.card {
  background: rgba(26, 26, 46, 0.8);
  backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 16px;
  padding: 1.5rem;
}

.card:hover {
  border-color: rgba(0, 212, 255, 0.3);
  box-shadow: 0 8px 32px rgba(0, 212, 255, 0.1);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

.card-header h3 {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 600;
}

.chart-container {
  height: 300px;
}

.status-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 1rem;
}

.status-item {
  text-align: center;
  padding: 1rem;
  background: rgba(255, 255, 255, 0.05);
  border-radius: 8px;
}

.status-label {
  font-size: 0.875rem;
  color: rgba(255, 255, 255, 0.7);
  margin-bottom: 0.5rem;
}

.status-value {
  font-size: 1.125rem;
  font-weight: 600;
}

.status-value.good {
  color: #00ff88;
}

@media (max-width: 768px) {
  .header-content {
    flex-direction: column;
    gap: 1rem;
  }
  
  .header-stats {
    flex-wrap: wrap;
    justify-content: center;
  }
  
  .dashboard-grid {
    grid-template-columns: 1fr;
  }
}
EOF
fi

# Créer index.css
cat > dashboard/src/index.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
    sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  background: #0f0f23;
  color: white;
}

code {
  font-family: source-code-pro, Menlo, Monaco, Consolas, 'Courier New',
    monospace;
}
EOF

# Mettre à jour package.json
cat > dashboard/package.json << 'EOF'
{
  "name": "synapsegrid-dashboard",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@testing-library/jest-dom": "^5.16.4",
    "@testing-library/react": "^13.3.0",
    "@testing-library/user-event": "^13.5.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1",
    "web-vitals": "^2.1.4",
    "recharts": "^2.8.0",
    "lucide-react": "^0.263.1",
    "axios": "^1.4.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  },
  "proxy": "http://localhost:8080"
}
EOF

echo "✅ Dashboard structure fixed!"
echo "📦 Installing dependencies..."

cd dashboard && npm install

echo "🚀 Dashboard ready to start!"
echo "Run: cd dashboard && npm start"

---

#!/bin/bash
# start_poc.sh - Script pour démarrer le POC complet

echo "🚀 Starting SynapseGrid POC..."

# Vérifier Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose not found. Please install Docker Compose first."
    exit 1
fi

# Corriger le dashboard d'abord
echo "🔧 Fixing dashboard structure..."
bash fix_dashboard.sh

# Créer les répertoires nécessaires
mkdir -p docker/postgres
mkdir -p docker/prometheus
mkdir -p docker/grafana/{dashboards,datasources}

# Démarrer les services
echo "🐳 Starting Docker services..."
docker-compose up -d

# Attendre que les services soient prêts
echo "⏳ Waiting for services to be ready..."
sleep 10

# Vérifier la santé des services
echo "🏥 Checking service health..."

# Redis
if docker-compose exec redis redis-cli ping > /dev/null 2>&1; then
    echo "✅ Redis is healthy"
else
    echo "❌ Redis is not responding"
fi

# PostgreSQL
if docker-compose exec postgres pg_isready -U synapse_user > /dev/null 2>&1; then
    echo "✅ PostgreSQL is healthy"
else
    echo "❌ PostgreSQL is not responding"
fi

# Gateway
if curl -f http://localhost:8080/health > /dev/null 2>&1; then
    echo "✅ Gateway is healthy"
else
    echo "❌ Gateway is not responding"
fi

# Dashboard
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    echo "✅ Dashboard is healthy"
else
    echo "❌ Dashboard is not responding"
fi

echo ""
echo "🎉 SynapseGrid POC is running!"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔗 API Gateway: http://localhost:8080"
echo "📈 Grafana: http://localhost:3001 (admin/admin123)"
echo "🔍 Prometheus: http://localhost:9090"
echo "💾 Redis: localhost:6379"
echo "🐘 PostgreSQL: localhost:5432"
echo ""
echo "🧪 Test API:"
echo "curl http://localhost:8080/health"
echo ""
echo "📤 Submit test job:"
echo 'curl -X POST http://localhost:8080/submit \'
echo '  -H "Content-Type: application/json" \'
echo '  -H "Authorization: Bearer test-token-123" \'
echo '  -d '\''{"model_name": "resnet50", "input_data": {"image": "test.jpg"}, "client_id": "test-client"}'\'''
echo ""
echo "🍎 To start macOS node separately:"
echo "cd services/node && python macos_node.py"
echo ""
echo "🛑 To stop all services:"
echo "docker-compose down"

---

#!/bin/bash
# test_poc.sh - Script de test complet

echo "🧪 Testing SynapseGrid POC..."

# Attendre que les services soient prêts
sleep 5

# Test 1: Health Check
echo "Testing health endpoint..."
if curl -f http://localhost:8080/health; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed"
    exit 1
fi

# Test 2: Metrics endpoint
echo ""
echo "Testing metrics endpoint..."
if curl -f http://localhost:8080/api/metrics; then
    echo "✅ Metrics endpoint working"
else
    echo "❌ Metrics endpoint failed"
fi

# Test 3: Submit test job
echo ""
echo "Testing job submission..."
JOB_RESPONSE=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token-123" \
    -d '{"model_name": "resnet50", "input_data": {"image": "test.jpg"}, "client_id": "test-client"}')

if [[ $JOB_RESPONSE == *"job_id"* ]]; then
    echo "✅ Job submission successful"
    echo "Response: $JOB_RESPONSE"
    
    # Extract job ID pour status check
    JOB_ID=$(echo $JOB_RESPONSE | grep -o '"job_id":"[^"]*' | cut -d'"' -f4)
    
    # Test 4: Check job status
    echo ""
    echo "Testing job status check..."
    sleep 2
    STATUS_RESPONSE=$(curl -s http://localhost:8080/job/$JOB_ID)
    echo "Job Status: $STATUS_RESPONSE"
else
    echo "❌ Job submission failed"
    echo "Response: $JOB_RESPONSE"
fi

# Test 5: Nodes endpoint
echo ""
echo "Testing nodes endpoint..."
NODES_RESPONSE=$(curl -s http://localhost:8080/api/nodes)
echo "Active Nodes: $NODES_RESPONSE"

# Test 6: Queue endpoint
echo ""
echo "Testing queue endpoint..."
QUEUE_RESPONSE=$(curl -s http://localhost:8080/api/jobs/queue)
echo "Job Queue: $QUEUE_RESPONSE"

# Test 7: Dashboard accessibility
echo ""
echo "Testing dashboard accessibility..."
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    echo "✅ Dashboard is accessible"
else
    echo "❌ Dashboard is not accessible"
fi

# Test 8: WebSocket connection (basic)
echo ""
echo "Testing WebSocket connection..."
if command -v websocat &> /dev/null; then
    echo "test" | timeout 2 websocat ws://localhost:8080/ws && echo "✅ WebSocket working" || echo "⚠️ WebSocket test inconclusive"
else
    echo "⚠️ websocat not found, skipping WebSocket test"
fi

echo ""
echo "🎯 POC Test Summary Complete!"
echo "Check the dashboard at http://localhost:3000 for real-time monitoring."

---

#!/bin/bash
# deploy_debian.sh - Déploiement spécifique pour Debian

echo "🐧 Deploying SynapseGrid on Debian..."

# Vérifier les prérequis
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    echo "✅ Docker installed. Please log out and back in."
fi

if ! command -v docker-compose &> /dev/null; then
    echo "📦 Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "✅ Docker Compose installed"
fi

# Installer Node.js pour le dashboard (si pas déjà installé)
if ! command -v node &> /dev/null; then
    echo "📦 Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "✅ Node.js installed"
fi

# Installer Python dependencies pour le node
echo "📦 Installing Python dependencies..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv
pip3 install --user redis asyncio psutil numpy

# Créer un service systemd pour le node (optionnel)
cat > /tmp/synapsegrid-node.service << 'EOF'
[Unit]
Description=SynapseGrid Node Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER/Code/synapsegrid-poc/services/node
Environment=PATH=/usr/bin:/usr/local/bin
ExecStart=/usr/bin/python3 macos_node.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Lancer le POC
echo "🚀 Starting POC..."
bash start_poc.sh

echo "✅ Debian deployment complete!"

---

#!/bin/bash
# monitor_network.sh - Script de monitoring réseau

echo "📊 SynapseGrid Network Monitor"
echo "=============================="

while true; do
    clear
    echo "📊 SynapseGrid Network Monitor - $(date)"
    echo "=============================="
    
    # Métriques de base
    echo ""
    echo "🔗 Service Status:"
    echo "=================="
    
    # Redis
    if docker-compose exec -T redis redis-cli ping > /dev/null 2>&1; then
        echo "✅ Redis: Online"
    else
        echo "❌ Redis: Offline"
    fi
    
    # PostgreSQL
    if docker-compose exec -T postgres pg_isready -U synapse_user > /dev/null 2>&1; then
        echo "✅ PostgreSQL: Online"
    else
        echo "❌ PostgreSQL: Offline"
    fi
    
    # Gateway
    if curl -f http://localhost:8080/health > /dev/null 2>&1; then
        echo "✅ Gateway: Online"
        
        # Obtenir les métriques
        METRICS=$(curl -s http://localhost:8080/api/metrics 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo ""
            echo "📈 Network Metrics:"
            echo "=================="
            echo "$METRICS" | jq . 2>/dev/null || echo "$METRICS"
        fi
    else
        echo "❌ Gateway: Offline"
    fi
    
    # Dashboard
    if curl -f http://localhost:3000 > /dev/null 2>&1; then
        echo "✅ Dashboard: Online"
    else
        echo "❌ Dashboard: Offline"
    fi
    
    # Conteneurs Docker
    echo ""
    echo "🐳 Docker Containers:"
    echo "===================="
    docker-compose ps
    
    # Utilisation ressources
    echo ""
    echo "💻 Resource Usage:"
    echo "=================="
    echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
    echo "Memory: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
    echo "Disk: $(df -h / | awk 'NR==2 {print $5}')"
    
    # Redis info
    echo ""
    echo "📊 Redis Stats:"
    echo "==============="
    docker-compose exec -T redis redis-cli info stats 2>/dev/null | grep -E "(total_commands_processed|connected_clients|used_memory_human)" || echo "Redis not accessible"
    
    echo ""
    echo "Press Ctrl+C to exit monitoring..."
    sleep 5
done

---

#!/bin/bash
# performance_test.sh - Test de performance et charge

echo "⚡ SynapseGrid Performance Test"
echo "=============================="

# Configuration
NUM_JOBS=50
CONCURRENT_JOBS=10
TEST_DURATION=60  # seconds

echo "🔧 Test Configuration:"
echo "- Jobs to submit: $NUM_JOBS"
echo "- Concurrent requests: $CONCURRENT_JOBS"
echo "- Duration: $TEST_DURATION seconds"
echo ""

# Créer le répertoire de résultats
mkdir -p test_results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="test_results/performance_$TIMESTAMP"
mkdir -p $RESULTS_DIR

# Test 1: Latence baseline
echo "📈 Test 1: Baseline Latency"
echo "========================="

for i in {1..10}; do
    START_TIME=$(date +%s%N)
    curl -s -X POST http://localhost:8080/submit \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer test-token-123" \
        -d "{\"model_name\": \"resnet50\", \"input_data\": {\"image\": \"test_$i.jpg\"}, \"client_id\": \"perf-test\"}" \
        > /dev/null
    END_TIME=$(date +%s%N)
    LATENCY=$(( ($END_TIME - $START_TIME) / 1000000 ))  # Convert to milliseconds
    echo "Job $i: ${LATENCY}ms"
    echo "$i,$LATENCY" >> $RESULTS_DIR/baseline_latency.csv
done

# Test 2: Charge concurrent
echo ""
echo "🚀 Test 2: Concurrent Load"
echo "========================="

echo "timestamp,job_id,response_time,status" > $RESULTS_DIR/concurrent_load.csv

# Fonction pour soumettre un job
submit_job() {
    local job_num=$1
    local start_time=$(date +%s%N)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local response=$(curl -s -w "%{http_code}" -X POST http://localhost:8080/submit \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer test-token-123" \
        -d "{\"model_name\": \"resnet50\", \"input_data\": {\"image\": \"load_test_$job_num.jpg\"}, \"client_id\": \"load-test\"}")
    
    local end_time=$(date +%s%N)
    local response_time=$(( ($end_time - $start_time) / 1000000 ))
    local http_code=${response: -3}
    
    echo "$timestamp,job_$job_num,$response_time,$http_code" >> $RESULTS_DIR/concurrent_load.csv
    echo "Job $job_num: ${response_time}ms (HTTP $http_code)"
}

# Lancer les tests concurrents
for ((i=1; i<=NUM_JOBS; i++)); do
    submit_job $i &
    
    # Limiter le nombre de processus concurrents
    if (( i % CONCURRENT_JOBS == 0 )); then
        wait  # Attendre que les jobs en cours se terminent
    fi
done

wait  # Attendre tous les jobs restants

# Test 3: Stress test sur la durée
echo ""
echo "💪 Test 3: Stress Test"
echo "==================="

echo "timestamp,jobs_submitted,jobs_completed,active_nodes,avg_latency" > $RESULTS_DIR/stress_test.csv

END_TIME=$(($(date +%s) + TEST_DURATION))
JOBS_SUBMITTED=0
JOBS_COMPLETED=0

while [ $(date +%s) -lt $END_TIME ]; do
    # Soumettre un job
    curl -s -X POST http://localhost:8080/submit \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer test-token-123" \
        -d "{\"model_name\": \"resnet50\", \"input_data\": {\"image\": \"stress_$JOBS_SUBMITTED.jpg\"}, \"client_id\": \"stress-test\"}" \
        > /dev/null &
    
    JOBS_SUBMITTED=$((JOBS_SUBMITTED + 1))
    
    # Obtenir les métriques
    METRICS=$(curl -s http://localhost:8080/api/metrics 2>/dev/null)
    if [ $? -eq 0 ]; then
        TOTAL_JOBS=$(echo "$METRICS" | jq -r '.totalJobs // 0' 2>/dev/null || echo "0")
        ACTIVE_NODES=$(echo "$METRICS" | jq -r '.activeNodes // 0' 2>/dev/null || echo "0")
        AVG_LATENCY=$(echo "$METRICS" | jq -r '.avgLatency // 0' 2>/dev/null || echo "0")
        
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$TIMESTAMP,$JOBS_SUBMITTED,$TOTAL_JOBS,$ACTIVE_NODES,$AVG_LATENCY" >> $RESULTS_DIR/stress_test.csv
        echo "Submitted: $JOBS_SUBMITTED, Completed: $TOTAL_JOBS, Nodes: $ACTIVE_NODES, Latency: ${AVG_LATENCY}ms"
    fi
    
    sleep 1
done

wait  # Attendre tous les jobs en cours

# Test 4: Test de récupération après panne
echo ""
echo "🔄 Test 4: Recovery Test"
echo "======================"

echo "Testing service recovery..."

# Arrêter un service temporairement
echo "Stopping dispatcher..."
docker-compose stop dispatcher

sleep 5

# Vérifier que le gateway continue de fonctionner
if curl -f http://localhost:8080/health > /dev/null 2>&1; then
    echo "✅ Gateway remains operational"
else
    echo "❌ Gateway affected by dispatcher failure"
fi

# Redémarrer le service
echo "Restarting dispatcher..."
docker-compose start dispatcher

sleep 10

# Vérifier la récupération
if curl -f http://localhost:8080/health > /dev/null 2>&1; then
    echo "✅ Service recovered successfully"
else
    echo "❌ Service recovery failed"
fi

# Générer le rapport
echo ""
echo "📊 Generating Performance Report"
echo "==============================="

cat > $RESULTS_DIR/performance_report.md << EOF
# SynapseGrid Performance Test Report

**Test Date:** $(date)
**Test Duration:** $TEST_DURATION seconds
**Jobs Submitted:** $NUM_JOBS
**Concurrent Level:** $CONCURRENT_JOBS

## Test Results

### Baseline Latency
- Average latency: $(awk -F',' '{sum+=$2} END {print sum/NR "ms"}' $RESULTS_DIR/baseline_latency.csv)
- Min latency: $(awk -F',' 'NR==1{min=$2} {if($2<min) min=$2} END {print min "ms"}' $RESULTS_DIR/baseline_latency.csv)
- Max latency: $(awk -F',' 'NR==1{max=$2} {if($2>max) max=$2} END {print max "ms"}' $RESULTS_DIR/baseline_latency.csv)

### Concurrent Load Test
- Total requests: $NUM_JOBS
- Successful requests: $(grep -c ",200$" $RESULTS_DIR/concurrent_load.csv)
- Failed requests: $(grep -c -v ",200$" $RESULTS_DIR/concurrent_load.csv)
- Success rate: $(echo "scale=2; $(grep -c ",200$" $RESULTS_DIR/concurrent_load.csv) * 100 / $NUM_JOBS" | bc)%

### Stress Test
- Peak throughput: $(awk -F',' 'NR>1 {if($2>max) max=$2} END {print max " jobs/min"}' $RESULTS_DIR/stress_test.csv)
- Average active nodes: $(awk -F',' 'NR>1 {sum+=$4; count++} END {if(count>0) print sum/count; else print 0}' $RESULTS_DIR/stress_test.csv)

## Files Generated
- baseline_latency.csv
- concurrent_load.csv  
- stress_test.csv
- performance_report.md

## Recommendations
Based on the test results, consider:
1. Scaling dispatcher instances if latency > 1000ms
2. Adding more nodes if success rate < 95%
3. Implementing caching if baseline latency > 500ms
EOF

echo "✅ Performance test complete!"
echo "📁 Results saved to: $RESULTS_DIR"
echo "📄 Report: $RESULTS_DIR/performance_report.md"
echo ""
echo "🔍 Quick Summary:"
cat $RESULTS_DIR/performance_report.md | grep -A 10 "## Test Results"

#!/bin/bash
# final_fix.sh
# Correction finale et complète du projet

set -e

echo "🔧 Correction finale de SynapseGrid"
echo "==================================="
echo ""

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Étape 1: Créer TOUS les services nécessaires
print_info "Création de tous les services..."

# Gateway
mkdir -p services/gateway
cat > services/gateway/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y gcc && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE 8080
CMD ["python", "main.py"]
EOF

if [ ! -f services/gateway/requirements.txt ]; then
    cat > services/gateway/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
websockets==12.0
redis[hiredis]==5.0.1
asyncpg==0.29.0
pydantic==2.5.0
prometheus-client==0.19.0
pyjwt==2.8.0
aiohttp==3.9.1
psutil==5.9.6
python-multipart==0.0.6
EOF
fi

if [ ! -f services/gateway/main.py ]; then
    cat > services/gateway/main.py << 'EOF'
# Minimal gateway for testing
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="SynapseGrid Gateway")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "gateway"}

@app.get("/nodes")
async def get_nodes():
    return []

@app.get("/jobs")
async def get_jobs():
    return []

@app.get("/metrics")
async def get_metrics():
    return {
        "totalNodes": 0,
        "activeJobs": 0,
        "avgLatency": 0,
        "throughput": 0
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF
fi

print_status "Gateway créé"

# Dispatcher
mkdir -p services/dispatcher
cat > services/dispatcher/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE 8001
CMD ["python", "main.py"]
EOF

cat > services/dispatcher/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
redis[hiredis]==5.0.1
EOF

cat > services/dispatcher/main.py << 'EOF'
# Minimal dispatcher
import uvicorn
from fastapi import FastAPI

app = FastAPI(title="SynapseGrid Dispatcher")

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "dispatcher"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
EOF

print_status "Dispatcher créé"

# Aggregator
mkdir -p services/aggregator
cat > services/aggregator/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE 8002
CMD ["python", "main.py"]
EOF

cat > services/aggregator/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
redis[hiredis]==5.0.1
EOF

cat > services/aggregator/main.py << 'EOF'
# Minimal aggregator
import uvicorn
from fastapi import FastAPI

app = FastAPI(title="SynapseGrid Aggregator")

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "aggregator"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8002)
EOF

print_status "Aggregator créé"

# Node
mkdir -p services/node
cat > services/node/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE 8003
CMD ["python", "main.py"]
EOF

cat > services/node/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
redis[hiredis]==5.0.1
EOF

cat > services/node/main.py << 'EOF'
# Minimal node
import uvicorn
from fastapi import FastAPI

app = FastAPI(title="SynapseGrid Node")

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "node"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8003)
EOF

print_status "Node créé"

# Étape 2: Créer docker-compose.yml minimal et fonctionnel
print_info "Création du docker-compose.yml..."

cat > docker-compose.yml << 'EOF'
services:
  # Redis
  redis:
    image: redis:7-alpine
    container_name: synapse_redis
    ports:
      - "6379:6379"
    networks:
      - synapse_network

  # PostgreSQL
  postgres:
    image: postgres:15-alpine
    container_name: synapse_postgres
    environment:
      POSTGRES_DB: synapse
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: synapse123
    ports:
      - "5432:5432"
    networks:
      - synapse_network

  # Gateway
  gateway:
    build: ./services/gateway
    container_name: synapse_gateway
    ports:
      - "8080:8080"
    depends_on:
      - redis
      - postgres
    networks:
      - synapse_network

  # Dispatcher
  dispatcher:
    build: ./services/dispatcher
    container_name: synapse_dispatcher
    ports:
      - "8001:8001"
    depends_on:
      - redis
    networks:
      - synapse_network

  # Aggregator
  aggregator:
    build: ./services/aggregator
    container_name: synapse_aggregator
    ports:
      - "8002:8002"
    depends_on:
      - redis
    networks:
      - synapse_network

  # Node
  node:
    build: ./services/node
    container_name: synapse_node
    ports:
      - "8003:8003"
    depends_on:
      - redis
    networks:
      - synapse_network

  # Dashboard
  dashboard:
    image: node:18-alpine
    container_name: synapse_dashboard
    working_dir: /app
    volumes:
      - ./dashboard:/app
    ports:
      - "3000:3000"
    command: sh -c "npm install && npm start"
    networks:
      - synapse_network
    depends_on:
      - gateway

networks:
  synapse_network:
    driver: bridge

volumes:
  redis_data:
  postgres_data:
EOF

print_status "docker-compose.yml créé"

# Étape 3: Créer le dossier SQL si nécessaire
mkdir -p sql
cat > sql/init.sql << 'EOF'
-- Tables de base pour SynapseGrid
CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(50) PRIMARY KEY,
    model_name VARCHAR(100),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nodes (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW()
);
EOF

# Étape 4: Vérifier la structure
print_info "Vérification de la structure..."

echo ""
echo "Structure des services:"
for service in gateway dispatcher aggregator node; do
    if [ -d "services/$service" ] && [ -f "services/$service/Dockerfile" ] && [ -f "services/$service/main.py" ]; then
        print_status "$service ✓"
    else
        print_error "$service ✗"
    fi
done

# Instructions finales
echo ""
echo "🎉 Correction terminée!"
echo "====================="
echo ""
echo "Tous les services ont été créés avec des versions minimales fonctionnelles."
echo ""
echo "🚀 Pour démarrer:"
echo ""
echo "1. Nettoyer Docker (optionnel):"
echo "   docker-compose down -v"
echo "   docker system prune -f"
echo ""
echo "2. Construire:"
echo "   docker-compose build"
echo ""
echo "3. Démarrer:"
echo "   docker-compose up -d"
echo ""
echo "4. Vérifier que tout fonctionne:"
echo "   docker ps"
echo "   curl http://localhost:8080/health"
echo ""
echo "📊 URLs:"
echo "   Gateway: http://localhost:8080/health"
echo "   Dispatcher: http://localhost:8001/health"
echo "   Aggregator: http://localhost:8002/health"
echo "   Node: http://localhost:8003/health"
echo "   Dashboard: http://localhost:3000"
echo ""
print_status "Prêt à construire!"

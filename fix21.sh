#!/bin/bash
# fix_dockerfiles.sh - Correction des Dockerfiles avec gcc

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Correction des Dockerfiles avec les dépendances de compilation${NC}"
echo ""

# ============================================================================
# DOCKERFILE POUR GATEWAY
# ============================================================================

echo -e "${YELLOW}📝 Création du Dockerfile Gateway...${NC}"

cat > services/gateway/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies including gcc for compilation
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Verify aioredis is NOT installed
RUN python -c "import sys; import subprocess; \
    result = subprocess.run([sys.executable, '-m', 'pip', 'list'], capture_output=True, text=True); \
    assert 'aioredis' not in result.stdout.lower(), 'aioredis should NOT be installed!'; \
    print('✅ Verified: aioredis is NOT installed')"

# Copy application
COPY main.py .

# Create non-root user for security
RUN useradd -m -u 1000 synapse && chown -R synapse:synapse /app
USER synapse

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
EOF

# ============================================================================
# DOCKERFILE POUR DISPATCHER
# ============================================================================

echo -e "${YELLOW}📝 Création du Dockerfile Dispatcher...${NC}"

cat > services/dispatcher/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Verify aioredis is NOT installed
RUN python -c "import sys; import subprocess; \
    result = subprocess.run([sys.executable, '-m', 'pip', 'list'], capture_output=True, text=True); \
    assert 'aioredis' not in result.stdout.lower(), 'aioredis should NOT be installed!'; \
    print('✅ Verified: aioredis is NOT installed')"

# Copy application
COPY main.py .

# Create non-root user
RUN useradd -m -u 1000 synapse && chown -R synapse:synapse /app
USER synapse

CMD ["python", "main.py"]
EOF

# ============================================================================
# DOCKERFILE POUR AGGREGATOR
# ============================================================================

echo -e "${YELLOW}📝 Création du Dockerfile Aggregator...${NC}"

cat > services/aggregator/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application
COPY main.py .

# Create non-root user
RUN useradd -m -u 1000 synapse && chown -R synapse:synapse /app
USER synapse

CMD ["python", "main.py"]
EOF

# ============================================================================
# DOCKERFILE POUR NODE
# ============================================================================

echo -e "${YELLOW}📝 Création du Dockerfile Node...${NC}"

cat > services/node/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application
COPY main.py .

# Create non-root user
RUN useradd -m -u 1000 synapse && chown -R synapse:synapse /app
USER synapse

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8003/health || exit 1

EXPOSE 8003

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8003"]
EOF

echo -e "${GREEN}✅ Dockerfiles corrigés avec gcc et dépendances${NC}"

# ============================================================================
# DOCKER-COMPOSE BUILD ARGS
# ============================================================================

echo -e "${YELLOW}📝 Création du docker-compose.build.yml pour les build args...${NC}"

cat > docker-compose.build.yml << 'EOF'
version: '3.8'

services:
  gateway:
    build:
      context: ./services/gateway
      dockerfile: Dockerfile
      args:
        - BUILDKIT_PROGRESS=plain
    image: synapsegrid/gateway:latest

  dispatcher:
    build:
      context: ./services/dispatcher
      dockerfile: Dockerfile
      args:
        - BUILDKIT_PROGRESS=plain
    image: synapsegrid/dispatcher:latest

  aggregator:
    build:
      context: ./services/aggregator
      dockerfile: Dockerfile
      args:
        - BUILDKIT_PROGRESS=plain
    image: synapsegrid/aggregator:latest

  node:
    build:
      context: ./services/node
      dockerfile: Dockerfile
      args:
        - BUILDKIT_PROGRESS=plain
    image: synapsegrid/node:latest
EOF

echo -e "${GREEN}✅ docker-compose.build.yml créé${NC}"

# ============================================================================
# SCRIPT DE BUILD AMÉLIORÉ
# ============================================================================

echo -e "${YELLOW}📝 Création du script de build amélioré...${NC}"

cat > build_services.sh << 'EOF'
#!/bin/bash
# build_services.sh - Build des services avec gestion d'erreurs

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔨 Build des services SynapseGrid${NC}"
echo ""

# Activer BuildKit pour de meilleures performances
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Build chaque service individuellement pour mieux gérer les erreurs
for service in gateway dispatcher aggregator node; do
    echo -e "${YELLOW}Building $service...${NC}"
    
    if docker-compose -f docker-compose.yml -f docker-compose.build.yml build --no-cache $service; then
        echo -e "${GREEN}✅ $service built successfully${NC}"
    else
        echo -e "${RED}❌ Failed to build $service${NC}"
        echo "Trying alternative build method..."
        
        # Méthode alternative avec docker build direct
        docker build --no-cache -t synapsegrid/$service:latest ./services/$service/
    fi
    echo ""
done

# Vérifier les images
echo -e "${YELLOW}📋 Images créées:${NC}"
docker images | grep synapsegrid

echo ""
echo -e "${GREEN}✅ Build terminé!${NC}"
EOF

chmod +x build_services.sh

echo -e "${GREEN}✅ Script de build créé${NC}"

# ============================================================================
# RÉSUMÉ
# ============================================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 ✅ DOCKERFILES CORRIGÉS !                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${WHITE}Les corrections apportées :${NC}"
echo "  • Ajout de gcc, g++ et python3-dev pour compiler psutil"
echo "  • Ajout de build-essential pour les outils de compilation"
echo "  • Mise à jour de pip avant l'installation"
echo "  • Ajout d'un utilisateur non-root pour la sécurité"
echo "  • Health checks pour gateway et node"
echo ""
echo -e "${CYAN}Pour builder :${NC}"
echo "  ./build_services.sh"
echo ""
echo -e "${CYAN}Ou directement :${NC}"
echo "  docker-compose build --no-cache"
echo ""

#!/bin/bash

# Script pour Mac M2 (Apple Silicon) avec Docker Desktop

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Configuration pour Mac M2 (Apple Silicon) ===${NC}"

# 1. Nettoyer complètement l'environnement Docker
echo -e "\n${YELLOW}Nettoyage de l'environnement Docker...${NC}"
docker-compose down -v
docker system prune -af --volumes

# 2. Créer un docker-compose pour Mac M2
echo -e "\n${GREEN}Création d'un docker-compose.m2.yml optimisé pour Apple Silicon...${NC}"
cat > docker-compose.m2.yml << 'EOF'
version: '3.8'

services:
  # === DATA LAYER ===
  redis:
    image: redis:7-alpine
    platform: linux/arm64
    container_name: synapse_redis
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - synapse_network

  postgres:
    image: postgres:15-alpine
    platform: linux/arm64
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
      dockerfile: services/gateway/Dockerfile.m2
      platforms:
        - linux/arm64
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
      - ./services/gateway:/app/services/gateway
      - ./shared:/app/shared
    networks:
      - synapse_network

  dispatcher:
    build:
      context: .
      dockerfile: services/dispatcher/Dockerfile.m2
      platforms:
        - linux/arm64
    container_name: synapse_dispatcher
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://synapse:synapse123@postgres:5432/synapse
    depends_on:
      - redis
      - postgres
      - gateway
    volumes:
      - ./services/dispatcher:/app/services/dispatcher
      - ./shared:/app/shared
    networks:
      - synapse_network

  aggregator:
    build:
      context: .
      dockerfile: services/aggregator/Dockerfile.m2
      platforms:
        - linux/arm64
    container_name: synapse_aggregator
    environment:
      - REDIS_URL=redis://redis:6379
      - POSTGRES_URL=postgresql://synapse:synapse123@postgres:5432/synapse
    depends_on:
      - redis
      - postgres
    volumes:
      - ./services/aggregator:/app/services/aggregator
      - ./shared:/app/shared
    networks:
      - synapse_network

  node:
    build:
      context: .
      dockerfile: services/node/Dockerfile.m2
      platforms:
        - linux/arm64
    container_name: synapse_node
    environment:
      - GATEWAY_URL=http://gateway:8080
      - NODE_ID=node-001
      - REGION=eu-west-1
      - REDIS_URL=redis://redis:6379
    depends_on:
      - gateway
      - dispatcher
    volumes:
      - ./services/node:/app/services/node
      - ./shared:/app/shared
    networks:
      - synapse_network

  # === MONITORING ===
  prometheus:
    image: prom/prometheus:latest
    platform: linux/arm64
    container_name: synapse_prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    networks:
      - synapse_network

  grafana:
    image: grafana/grafana:latest
    platform: linux/arm64
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

# 3. Créer des requirements.txt simplifiés sans aiohttp
echo -e "\n${GREEN}Création de requirements.txt sans aiohttp...${NC}"
cat > shared/requirements.txt << 'EOF'
# Shared dependencies optimized for ARM64
redis==5.0.1
psycopg2-binary==2.9.9
sqlalchemy==2.0.23
pydantic==2.5.2
pydantic-settings==2.1.0
python-dotenv==1.0.0
# Skip grpcio for now - problematic on ARM64
# grpcio==1.60.0
# grpcio-tools==1.60.0
protobuf==4.25.1
# Use starlette instead of aiohttp
starlette==0.27.0
uvloop==0.19.0
structlog==23.2.0
prometheus-client==0.19.0
pyjwt==2.8.0
asyncpg==0.29.0
httpx==0.25.2
EOF

# 4. Créer des Dockerfiles optimisés pour M2
echo -e "\n${GREEN}Création du Dockerfile Gateway pour M2...${NC}"
cat > services/gateway/Dockerfile.m2 << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install minimal dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Copy requirements
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/gateway/requirements.txt /app/services/gateway/requirements.txt

# Install dependencies with --prefer-binary flag
RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/gateway/requirements.txt || true

# Copy code
COPY shared /app/shared
COPY services/gateway /app/services/gateway

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

EXPOSE 8080

CMD ["python", "-u", "services/gateway/main.py"]
EOF

echo -e "\n${GREEN}Création du Dockerfile Dispatcher pour M2...${NC}"
cat > services/dispatcher/Dockerfile.m2 << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN pip install --upgrade pip setuptools wheel

COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/dispatcher/requirements.txt /app/services/dispatcher/requirements.txt

RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/dispatcher/requirements.txt || true

COPY shared /app/shared
COPY services/dispatcher /app/services/dispatcher

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "services/dispatcher/main.py"]
EOF

echo -e "\n${GREEN}Création du Dockerfile Aggregator pour M2...${NC}"
cat > services/aggregator/Dockerfile.m2 << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN pip install --upgrade pip setuptools wheel

COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/aggregator/requirements.txt /app/services/aggregator/requirements.txt

RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/aggregator/requirements.txt || true

COPY shared /app/shared
COPY services/aggregator /app/services/aggregator

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "services/aggregator/main.py"]
EOF

echo -e "\n${GREEN}Création du Dockerfile Node pour M2...${NC}"
cat > services/node/Dockerfile.m2 << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip setuptools wheel

COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/node/requirements.txt /app/services/node/requirements.txt

RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/node/requirements.txt || true

COPY shared /app/shared
COPY services/node /app/services/node

RUN mkdir -p /app/models

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "services/node/main.py"]
EOF

# 5. Créer un Makefile pour M2
echo -e "\n${GREEN}Création d'un Makefile spécifique M2...${NC}"
cat > Makefile.m2 << 'EOF'
.PHONY: build start stop logs clean test

# Use the M2 compose file
COMPOSE_FILE = docker-compose.m2.yml

build:
	docker-compose -f $(COMPOSE_FILE) build --no-cache

start:
	docker-compose -f $(COMPOSE_FILE) up -d

stop:
	docker-compose -f $(COMPOSE_FILE) down

logs:
	docker-compose -f $(COMPOSE_FILE) logs -f

clean:
	docker-compose -f $(COMPOSE_FILE) down -v
	docker system prune -af

test:
	@echo "Testing API health..."
	@curl -s http://localhost:8080/health | jq . || echo "API not ready"

status:
	docker-compose -f $(COMPOSE_FILE) ps
EOF

# 6. Build avec le nouveau setup
echo -e "\n${GREEN}Construction des images Docker pour M2...${NC}"
docker-compose -f docker-compose.m2.yml build --no-cache

# 7. Démarrer les services
echo -e "\n${GREEN}Démarrage des services...${NC}"
docker-compose -f docker-compose.m2.yml up -d

# 8. Attendre le démarrage
echo -e "\n${YELLOW}Attente du démarrage des services (20 secondes)...${NC}"
sleep 20

# 9. Vérifier le statut
echo -e "\n${GREEN}Vérification du statut...${NC}"
docker-compose -f docker-compose.m2.yml ps

# 10. Tester l'API
echo -e "\n${GREEN}Test de l'API...${NC}"
curl -s http://localhost:8080/health | jq . || echo -e "${YELLOW}L'API n'est pas encore prête${NC}"

echo -e "\n${GREEN}=== Configuration M2 terminée ===${NC}"
echo -e "${YELLOW}Utiliser les commandes suivantes:${NC}"
echo "  make -f Makefile.m2 build    # Construire"
echo "  make -f Makefile.m2 start    # Démarrer"
echo "  make -f Makefile.m2 logs     # Voir les logs"
echo "  make -f Makefile.m2 status   # Vérifier le statut"

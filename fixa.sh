#!/bin/bash

# 1. Vérifier la structure attendue par Docker
docker compose config

# 2. Corriger les Dockerfiles avec le bon contexte
cat > services/gateway/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copier requirements en premier pour le cache Docker
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copier TOUT le contenu du service
COPY . .

EXPOSE 8080

CMD ["python", "main.py"]
EOF

# 3. Même chose pour les autres services
for service in dispatcher aggregator node; do
    cat > services/$service/Dockerfile << EOF
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["python", "main.py"]
EOF
done

# 4. Reconstruction forcée
docker compose down
docker compose build --no-cache
docker compose up -d

# 5. Vérifier que ça marche
sleep 10
docker compose ps
curl http://localhost:8080/health

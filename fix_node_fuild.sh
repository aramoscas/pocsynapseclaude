#!/bin/bash

# Script pour corriger le problème de build du node

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Correction du build du service Node ===${NC}"

# 1. Arrêter le node
echo -e "\n${YELLOW}Arrêt du service node...${NC}"
docker-compose -f docker-compose.m2.yml stop node

# 2. Corriger le Dockerfile.m2
echo -e "\n${GREEN}Correction du Dockerfile.m2...${NC}"
cat > services/node/Dockerfile.m2 << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Installer les dépendances système incluant gcc pour compiler psutil
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip setuptools wheel

COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/node/requirements.txt /app/services/node/requirements.txt

# Installer les dépendances sans || true pour voir les erreurs
RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/node/requirements.txt

COPY shared /app/shared
COPY services/node /app/services/node

RUN mkdir -p /app/models

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "services/node/main.py"]
EOF

echo -e "${GREEN}✓ Dockerfile.m2 corrigé${NC}"

# 3. Supprimer l'ancienne image
echo -e "\n${YELLOW}Suppression de l'ancienne image...${NC}"
docker-compose -f docker-compose.m2.yml rm -f node
docker rmi synapsegrid-poc-node:latest || true

# 4. Reconstruire avec logs détaillés
echo -e "\n${GREEN}Reconstruction du service node...${NC}"
docker-compose -f docker-compose.m2.yml build --no-cache --progress=plain node

# 5. Démarrer le node
echo -e "\n${GREEN}Démarrage du service node...${NC}"
docker-compose -f docker-compose.m2.yml up -d node

# 6. Attendre un peu
echo -e "\n${YELLOW}Attente de 5 secondes...${NC}"
sleep 5

# 7. Vérifier le statut
echo -e "\n${GREEN}Vérification du statut...${NC}"
docker-compose -f docker-compose.m2.yml ps node

# 8. Afficher les logs
echo -e "\n${GREEN}Logs du service node :${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=20 node

# 9. Vérifier si le node est enregistré
echo -e "\n${GREEN}Vérification de l'enregistrement du node dans Redis...${NC}"
docker exec synapse_redis redis-cli KEYS "node:*" || echo -e "${RED}Impossible de vérifier Redis${NC}"

# 10. Afficher un résumé
echo -e "\n${GREEN}=== Correction terminée ===${NC}"
echo -e "${YELLOW}Si le node fonctionne, vous devriez voir :${NC}"
echo "- 'Node initialized' dans les logs"
echo "- Le node devrait s'enregistrer dans Redis"
echo "- Le dispatcher devrait le détecter"
echo ""
echo -e "${GREEN}Pour suivre les logs en temps réel :${NC}"
echo "docker-compose -f docker-compose.m2.yml logs -f node"
echo ""
echo -e "${GREEN}Pour vérifier que le node est détecté par le dispatcher :${NC}"
echo "docker-compose -f docker-compose.m2.yml logs dispatcher | grep 'Nodes ranked'"

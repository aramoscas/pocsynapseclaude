#!/bin/bash

# Script pour corriger le problème onnxruntime

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Correction du problème onnxruntime ===${NC}"

# 1. Deux options possibles
echo -e "\n${YELLOW}Choisissez une option :${NC}"
echo "1. Commenter l'import onnxruntime dans le code (recommandé pour tester rapidement)"
echo "2. Installer onnxruntime (peut être long sur ARM64)"
echo -n "Votre choix (1 ou 2) : "
read choice

if [ "$choice" = "1" ]; then
    echo -e "\n${GREEN}Option 1 : Désactivation temporaire d'ONNX...${NC}"
    
    # Créer une copie de main.py avec onnxruntime commenté
    sed -i.bak 's/^import onnxruntime as ort/# import onnxruntime as ort/' services/node/main.py
    
    # Commenter aussi les lignes qui utilisent ort
    sed -i 's/session = ort.InferenceSession/# session = ort.InferenceSession/' services/node/main.py
    
    echo -e "${GREEN}✓ Import onnxruntime commenté${NC}"
    
elif [ "$choice" = "2" ]; then
    echo -e "\n${GREEN}Option 2 : Installation d'onnxruntime...${NC}"
    
    # Mettre à jour requirements.txt pour inclure onnxruntime
    cat > services/node/requirements.txt << 'EOF'
# Node dependencies
numpy==1.24.3
psutil==5.9.6
aiofiles==23.2.1
onnxruntime==1.16.3
EOF
    
    # Mettre à jour le Dockerfile pour installer les dépendances d'onnxruntime
    cat > services/node/Dockerfile.m2 << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Installer les dépendances système pour onnxruntime et psutil
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    g++ \
    python3-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip setuptools wheel

COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/node/requirements.txt /app/services/node/requirements.txt

# Installer les dépendances
RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/node/requirements.txt

COPY shared /app/shared
COPY services/node /app/services/node

RUN mkdir -p /app/models

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "services/node/main.py"]
EOF
    
    echo -e "${GREEN}✓ Configuration mise à jour pour onnxruntime${NC}"
else
    echo -e "${RED}Choix invalide${NC}"
    exit 1
fi

# 2. Arrêter le node
echo -e "\n${YELLOW}Arrêt du service node...${NC}"
docker-compose -f docker-compose.m2.yml stop node

# 3. Reconstruire si option 2
if [ "$choice" = "2" ]; then
    echo -e "\n${YELLOW}Reconstruction avec onnxruntime (peut prendre du temps)...${NC}"
    docker-compose -f docker-compose.m2.yml build --no-cache node
fi

# 4. Redémarrer le node
echo -e "\n${GREEN}Redémarrage du service node...${NC}"
docker-compose -f docker-compose.m2.yml up -d node

# 5. Attendre
echo -e "\n${YELLOW}Attente de 10 secondes...${NC}"
sleep 10

# 6. Vérifier les logs
echo -e "\n${GREEN}Vérification des logs :${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=30 node

# 7. Vérifier l'enregistrement du node
echo -e "\n${GREEN}Vérification dans Redis :${NC}"
docker exec synapse_redis redis-cli --raw KEYS "node:*" | head -5

# 8. Vérifier le dispatcher
echo -e "\n${GREEN}Vérification du dispatcher :${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=5 dispatcher | grep -i "nodes ranked" || echo "Pas encore de ranking"

echo -e "\n${GREEN}=== Correction terminée ===${NC}"
if [ "$choice" = "1" ]; then
    echo -e "${YELLOW}Note: ONNX est désactivé. Les modèles utiliseront des données simulées.${NC}"
else
    echo -e "${YELLOW}Note: ONNX est installé. Vérifiez que les modèles .onnx sont disponibles.${NC}"
fi

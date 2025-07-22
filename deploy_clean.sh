#!/bin/bash
# Script de déploiement propre

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🔨 Build des images (sans cache)...${NC}"

# Build avec --no-cache pour éviter les problèmes de cache
docker-compose build --no-cache --pull gateway dispatcher

echo -e "${YELLOW}🔍 Vérification des images...${NC}"

# Vérifier qu'aioredis n'est PAS dans les images
for service in gateway dispatcher; do
    echo -n "Checking $service: "
    docker run --rm synapse_$service pip list | grep -i aioredis && \
        echo -e "${RED}❌ aioredis found!${NC}" || \
        echo -e "${GREEN}✅ No aioredis${NC}"
done

echo -e "${YELLOW}🚀 Démarrage des services...${NC}"

# Arrêter les anciens
docker-compose down

# Démarrer avec les nouveaux
docker-compose up -d

# Attendre que tout soit prêt
echo -e "${YELLOW}⏳ Attente du démarrage...${NC}"
sleep 10

# Vérifier la santé
echo -e "${YELLOW}🏥 Vérification de santé...${NC}"

# Gateway
curl -s http://localhost:8080/health | jq . && \
    echo -e "${GREEN}✅ Gateway OK${NC}" || \
    echo -e "${RED}❌ Gateway Failed${NC}"

# Test complet
echo -e "${YELLOW}🧪 Test de soumission de job...${NC}"

curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: deploy-test" \
    -d '{"model_name": "test-deploy", "input_data": {"test": true}}' | jq .

echo -e "${GREEN}✅ Déploiement terminé!${NC}"

#!/bin/bash

# Script pour corriger les modules manquants

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Correction des modules manquants ===${NC}"

# 1. Vérifier quels services ont des problèmes
echo -e "\n${YELLOW}État actuel des services:${NC}"
docker-compose -f docker-compose.m2.yml ps

# 2. Corriger les requirements manquants
echo -e "\n${GREEN}Mise à jour des requirements.txt...${NC}"

# Gateway requirements - ajouter uvicorn
cat > services/gateway/requirements.txt << 'EOF'
# Gateway dependencies
fastapi==0.104.1
uvicorn[standard]==0.24.0
httpx==0.25.2
python-multipart==0.0.6
websockets==12.0
EOF

# Node requirements - ajouter psutil
cat > services/node/requirements.txt << 'EOF'
# Node dependencies
numpy==1.24.3
psutil==5.9.6
aiofiles==23.2.1
# ONNX désactivé temporairement pour M2
# onnxruntime==1.16.3
EOF

# 3. Reconstruire seulement les services qui ont échoué
echo -e "\n${GREEN}Reconstruction du service Gateway...${NC}"
docker-compose -f docker-compose.m2.yml build gateway

echo -e "\n${GREEN}Reconstruction du service Node...${NC}"
docker-compose -f docker-compose.m2.yml build node

# 4. Redémarrer les services
echo -e "\n${GREEN}Redémarrage des services...${NC}"
docker-compose -f docker-compose.m2.yml up -d gateway node

# 5. Attendre un peu
echo -e "\n${YELLOW}Attente de 10 secondes...${NC}"
sleep 10

# 6. Vérifier les logs
echo -e "\n${GREEN}Vérification des services:${NC}"
echo -e "\n${YELLOW}Gateway:${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=10 gateway

echo -e "\n${YELLOW}Node:${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=10 node

echo -e "\n${YELLOW}Dispatcher (déjà fonctionnel):${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=5 dispatcher

echo -e "\n${YELLOW}Aggregator (déjà fonctionnel):${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=5 aggregator

# 7. Tester l'API
echo -e "\n${GREEN}Test de l'API Gateway...${NC}"
curl -s http://localhost:8080/health | jq . || echo -e "${RED}API pas encore prête${NC}"

# 8. Afficher le statut final
echo -e "\n${GREEN}Statut final des services:${NC}"
docker-compose -f docker-compose.m2.yml ps

# 9. Instructions supplémentaires
echo -e "\n${GREEN}=== Correction terminée ===${NC}"
echo -e "${YELLOW}Si des problèmes persistent:${NC}"
echo "1. Vérifier les logs complets: docker-compose -f docker-compose.m2.yml logs -f [service]"
echo "2. Redémarrer tout: docker-compose -f docker-compose.m2.yml restart"
echo "3. Reconstruire avec cache: docker-compose -f docker-compose.m2.yml build --no-cache [service]"

# 10. Test supplémentaire pour soumettre un job
echo -e "\n${GREEN}Pour tester la soumission d'un job:${NC}"
echo 'curl -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -H "X-Client-ID: test-client" \
  -d '"'"'{"model_name": "resnet50", "input_data": {"image": "test.jpg"}}'"'"''

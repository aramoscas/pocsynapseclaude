#!/bin/bash

# Script pour corriger le problème de région (version macOS)

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Correction du problème de région ===${NC}"

# 1. Vérifier les régions actuelles
echo -e "\n${YELLOW}Configuration actuelle :${NC}"
echo "Node région : eu-west-1"
echo "Dispatcher région : us-east"
echo "Gateway région : us-east"

# 2. Mettre à jour docker-compose.m2.yml pour aligner les régions
echo -e "\n${GREEN}Alignement des régions sur 'us-east'...${NC}"

# Sauvegarder le fichier original
cp docker-compose.m2.yml docker-compose.m2.yml.bak

# Remplacer la région du node de eu-west-1 à us-east (compatible macOS)
sed -i '' 's/REGION=eu-west-1/REGION=us-east/g' docker-compose.m2.yml

echo -e "${GREEN}✓ Régions alignées sur 'us-east'${NC}"

# 3. Nettoyer les anciennes données dans Redis
echo -e "\n${YELLOW}Nettoyage des anciennes données Redis...${NC}"
docker exec synapse_redis redis-cli DEL "node:node-001:eu-west-1" || true
docker exec synapse_redis redis-cli SREM "nodes:eu-west-1" "node-001" || true

# 4. Redémarrer les services concernés
echo -e "\n${GREEN}Redémarrage des services...${NC}"
docker-compose -f docker-compose.m2.yml restart node
docker-compose -f docker-compose.m2.yml restart dispatcher

# 5. Attendre un peu
echo -e "\n${YELLOW}Attente de 10 secondes...${NC}"
sleep 10

# 6. Vérifier l'enregistrement du node
echo -e "\n${GREEN}Vérification de l'enregistrement du node :${NC}"
echo -e "${YELLOW}Nodes dans Redis :${NC}"
docker exec synapse_redis redis-cli KEYS "node:*" || echo "Erreur Redis"

echo -e "\n${YELLOW}Contenu du node :${NC}"
docker exec synapse_redis redis-cli HGETALL "node:node-001:us-east" || echo "Node non trouvé"

# 7. Vérifier le dispatcher
echo -e "\n${GREEN}Vérification du dispatcher :${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=5 dispatcher | grep "Nodes ranked"

# 8. Tester la soumission d'un job
echo -e "\n${GREEN}Test de soumission d'un job :${NC}"
curl -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -H "X-Client-ID: test-client" \
  -d '{"model_name": "resnet50", "input_data": {"image": "test.jpg"}}' | jq . || echo -e "${RED}Erreur de soumission${NC}"

# 9. Attendre un peu et vérifier le traitement
echo -e "\n${YELLOW}Attente de 5 secondes pour le traitement...${NC}"
sleep 5

# 10. Vérifier les logs du node pour voir s'il a reçu le job
echo -e "\n${GREEN}Logs récents du node :${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=10 node | grep -E "(Executing job|Job completed)" || echo "Pas de job exécuté"

# 11. Vérifier aussi l'aggregator
echo -e "\n${GREEN}Logs récents de l'aggregator :${NC}"
docker-compose -f docker-compose.m2.yml logs --tail=5 aggregator | grep -E "(Result received|Rewards triggered)" || echo "Pas de résultat reçu"

echo -e "\n${GREEN}=== Correction terminée ===${NC}"
echo -e "${YELLOW}Si tout fonctionne, vous devriez voir :${NC}"
echo "- Le dispatcher afficher 'Nodes ranked count=1'"
echo "- Le job être assigné au node"
echo "- Le node exécuter le job"
echo "- Le dashboard afficher les métriques réelles"

echo -e "\n${GREEN}Pour suivre en temps réel :${NC}"
echo "docker-compose -f docker-compose.m2.yml logs -f dispatcher node"

echo -e "\n${GREEN}Pour voir toutes les clés Redis :${NC}"
echo "docker exec synapse_redis redis-cli KEYS '*'"

#!/bin/bash
# deploy_synapsegrid.sh - Déploiement intelligent avec auto-correction

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         🚀 SYNAPSEGRID INTELLIGENT DEPLOYMENT 🚀             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Vérification des prérequis
echo -e "${YELLOW}1. Vérification des prérequis...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}❌ Docker requis${NC}"; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo -e "${RED}❌ Docker Compose requis${NC}"; exit 1; }
echo -e "${GREEN}✅ Prérequis OK${NC}"

# 2. Nettoyage si demandé
if [ "$1" == "--clean" ]; then
    echo -e "${YELLOW}2. Nettoyage complet...${NC}"
    docker-compose down -v
    docker system prune -af
    echo -e "${GREEN}✅ Nettoyage terminé${NC}"
fi

# 3. Construction des images
echo -e "${YELLOW}3. Construction des images...${NC}"
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Build uniquement gateway pour l'instant
docker-compose build --no-cache gateway

# 4. Démarrage des services de base
echo -e "${YELLOW}4. Démarrage des services de base...${NC}"
docker-compose up -d redis postgres

# Attendre que PostgreSQL soit prêt
echo -n "Attente de PostgreSQL..."
until docker-compose exec -T postgres pg_isready -U synapse >/dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo -e " ${GREEN}✅${NC}"

# Attendre que Redis soit prêt
echo -n "Attente de Redis..."
until docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo -e " ${GREEN}✅${NC}"

# 5. Démarrage du gateway
echo -e "${YELLOW}5. Démarrage du gateway...${NC}"
docker-compose up -d gateway

# Attendre que le gateway soit prêt
echo -n "Attente du gateway..."
for i in {1..30}; do
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo -e " ${GREEN}✅${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# 6. Configuration Redis
echo -e "${YELLOW}6. Configuration Redis...${NC}"
docker-compose exec -T redis redis-cli << 'REDIS_COMMANDS'
DEL nodes:registered
SADD nodes:registered "node_default"
SET node:node_default:info '{"node_id":"node_default","status":"available","capacity":1.0,"current_load":0}'
REDIS_COMMANDS
echo -e "${GREEN}✅ Redis configuré${NC}"

# 7. Test de santé complet
echo -e "${YELLOW}7. Test de santé...${NC}"
HEALTH=$(curl -s http://localhost:8080/health)
echo "$HEALTH" | jq . || echo "$HEALTH"

# 8. Test de soumission
echo -e "${YELLOW}8. Test de soumission de job...${NC}"
JOB_RESPONSE=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: deploy-test" \
    -d '{"model_name": "test-deploy", "input_data": {"test": true}}')

echo "Réponse: $JOB_RESPONSE"
JOB_ID=$(echo "$JOB_RESPONSE" | jq -r '.job_id' 2>/dev/null)

if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
    echo -e "${GREEN}✅ Job soumis: $JOB_ID${NC}"
    
    # Vérifier le statut
    sleep 2
    echo "Statut du job:"
    curl -s http://localhost:8080/job/$JOB_ID/status | jq .
else
    echo -e "${RED}❌ Échec de soumission${NC}"
fi

# 9. Démarrage des autres services (optionnel)
if [ "$2" == "--all" ]; then
    echo -e "${YELLOW}9. Démarrage des autres services...${NC}"
    docker-compose up -d
fi

# 10. Résumé
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   ✅ DÉPLOIEMENT RÉUSSI !                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📊 Services actifs:"
docker-compose ps
echo ""
echo "🔗 URLs:"
echo "  Gateway API: http://localhost:8080"
echo "  Health:      http://localhost:8080/health"
echo "  Docs:        http://localhost:8080/docs"
echo ""
echo "📝 Commandes utiles:"
echo "  Logs:        docker-compose logs -f gateway"
echo "  Monitoring:  ./monitor_synapsegrid.sh"
echo "  Arrêt:       docker-compose down"

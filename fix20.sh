#!/bin/bash
# deploy_clean_fixed.sh - Script de déploiement corrigé

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           🚀 SYNAPSEGRID CLEAN DEPLOYMENT 🚀                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Obtenir le nom du projet depuis docker-compose
PROJECT_NAME=$(docker-compose config | grep -m1 "name:" | cut -d: -f2 | tr -d ' ' || echo "pocsynapseclaude")
echo -e "${YELLOW}📦 Project name: $PROJECT_NAME${NC}"

echo -e "${YELLOW}🔨 Build des images (sans cache)...${NC}"

# Build avec --no-cache pour éviter les problèmes de cache
docker-compose build --no-cache --pull gateway dispatcher aggregator node

echo -e "${YELLOW}🔍 Vérification des images...${NC}"

# Les images sont nommées selon le pattern: projectname-servicename ou projectname_servicename
for service in gateway dispatcher; do
    echo -n "Checking $service: "
    
    # Essayer différents patterns de nommage
    IMAGE_NAME=""
    for pattern in "${PROJECT_NAME}-${service}" "${PROJECT_NAME}_${service}" "synapse-${service}" "synapse_${service}"; do
        if docker image inspect "$pattern" >/dev/null 2>&1; then
            IMAGE_NAME="$pattern"
            break
        fi
    done
    
    if [ -z "$IMAGE_NAME" ]; then
        echo -e "${YELLOW}⚠️  Image not found, checking with docker-compose...${NC}"
        IMAGE_NAME=$(docker-compose config | grep -A5 "  $service:" | grep "image:" | cut -d: -f2 | tr -d ' ' || echo "")
    fi
    
    if [ -n "$IMAGE_NAME" ]; then
        docker run --rm --entrypoint pip "$IMAGE_NAME" list 2>/dev/null | grep -i aioredis && \
            echo -e "${RED}❌ aioredis found in $service!${NC}" || \
            echo -e "${GREEN}✅ No aioredis in $service${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not verify $service (image name not found)${NC}"
    fi
done

echo ""
echo -e "${YELLOW}🛑 Arrêt des anciens services...${NC}"
docker-compose down

echo ""
echo -e "${YELLOW}🚀 Démarrage des services...${NC}"
docker-compose up -d

# Attendre que PostgreSQL soit prêt
echo -e "${YELLOW}⏳ Attente de PostgreSQL...${NC}"
until docker-compose exec -T postgres pg_isready -U synapse >/dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo -e " ${GREEN}✅ PostgreSQL ready${NC}"

# Attendre que Redis soit prêt
echo -e "${YELLOW}⏳ Attente de Redis...${NC}"
until docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo -e " ${GREEN}✅ Redis ready${NC}"

# Attendre un peu plus pour les services
echo -e "${YELLOW}⏳ Attente du démarrage complet des services...${NC}"
sleep 10

# Enregistrer un node par défaut dans Redis
echo -e "${YELLOW}🖥️  Enregistrement d'un node par défaut...${NC}"
docker-compose exec -T redis redis-cli << 'EOF'
DEL nodes:registered
SADD nodes:registered "node_default"
SET node:node_default:info '{"node_id":"node_default","status":"available","capacity":1.0,"current_load":0}'
SMEMBERS nodes:registered
EOF
echo -e "${GREEN}✅ Node par défaut enregistré${NC}"

echo ""
echo -e "${YELLOW}🏥 Vérification de santé...${NC}"

# Gateway health check
echo -n "Gateway: "
if curl -s http://localhost:8080/health >/dev/null 2>&1; then
    HEALTH=$(curl -s http://localhost:8080/health)
    echo -e "${GREEN}✅ OK${NC}"
    echo "$HEALTH" | jq -c '{status, version}' 2>/dev/null || echo "$HEALTH"
else
    echo -e "${RED}❌ Failed${NC}"
    echo "Logs Gateway:"
    docker-compose logs --tail=20 gateway
fi

echo ""
echo -e "${YELLOW}🧪 Test de soumission de job...${NC}"

TEST_RESPONSE=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: deploy-test" \
    -d '{"model_name": "test-deploy", "input_data": {"test": true, "timestamp": "'$(date +%s)'"}}' 2>/dev/null)

if [ -n "$TEST_RESPONSE" ]; then
    echo "$TEST_RESPONSE" | jq . 2>/dev/null || echo "$TEST_RESPONSE"
    JOB_ID=$(echo "$TEST_RESPONSE" | jq -r '.job_id' 2>/dev/null)
    
    if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
        echo -e "${GREEN}✅ Job submitted: $JOB_ID${NC}"
        
        # Attendre un peu et vérifier le statut
        sleep 3
        echo ""
        echo "Job status:"
        curl -s http://localhost:8080/job/$JOB_ID/status 2>/dev/null | jq . 2>/dev/null || echo "Status check failed"
    fi
else
    echo -e "${RED}❌ Job submission failed${NC}"
fi

echo ""
echo -e "${YELLOW}📊 État des services:${NC}"
docker-compose ps

echo ""
echo -e "${YELLOW}📋 Jobs dans la queue:${NC}"
docker-compose exec -T redis redis-cli LLEN "jobs:queue:eu-west-1" | xargs echo "Queue length:"

echo ""
echo -e "${YELLOW}🖥️  Nodes enregistrés:${NC}"
docker-compose exec -T redis redis-cli SMEMBERS "nodes:registered"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  ✅ DÉPLOIEMENT TERMINÉ !                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📊 Pour monitorer en temps réel:${NC}"
echo "  ./monitor_clean.sh"
echo ""
echo -e "${CYAN}📜 Pour voir les logs:${NC}"
echo "  docker-compose logs -f gateway"
echo "  docker-compose logs -f dispatcher"
echo ""
echo -e "${CYAN}🧪 Pour plus de tests:${NC}"
echo "  make test-flow-basic"
echo "  make test-flow-e2e"

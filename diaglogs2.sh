#!/bin/bash
# check_real_status.sh - Vérifier le statut réel des services

echo "🔍 Vérification du statut réel des services"
echo "=========================================="

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Vérifier l'état des conteneurs
echo -e "\n${YELLOW}📊 État des conteneurs Docker:${NC}"
docker-compose ps

# 2. Vérifier les ports exposés
echo -e "\n${YELLOW}🔌 Ports exposés:${NC}"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep synapse

# 3. Vérifier les logs récents de chaque service
echo -e "\n${YELLOW}📋 Dernières lignes des logs:${NC}"

check_service() {
    local service=$1
    echo -e "\n--- $service ---"
    
    # Vérifier si le conteneur existe et est en cours d'exécution
    if docker-compose ps | grep -E "synapse[_-]$service.*Up" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Container UP${NC}"
        # Afficher les dernières lignes
        docker-compose logs --tail=5 $service 2>&1 | grep -v "Attaching to"
    else
        echo -e "${RED}❌ Container DOWN${NC}"
        # Afficher les erreurs
        docker-compose logs --tail=10 $service 2>&1 | grep -E "ERROR|Error|error|Exception|Failed" || echo "Pas de logs d'erreur trouvés"
    fi
}

for service in dispatcher aggregator node1 node2 dashboard; do
    check_service $service
done

# 4. Vérifier la configuration Docker Compose
echo -e "\n${YELLOW}🔧 Configuration des services (docker-compose.yml):${NC}"
echo "Dispatcher:"
grep -A5 "dispatcher:" docker-compose.yml | grep -E "ports:|environment:" || echo "  Pas de ports exposés"
echo -e "\nAggregator:"
grep -A5 "aggregator:" docker-compose.yml | grep -E "ports:|environment:" || echo "  Pas de ports exposés"
echo -e "\nNode1:"
grep -A5 "node1:" docker-compose.yml | grep -E "ports:|environment:" || echo "  Pas de ports exposés"

# 5. Solution proposée
echo -e "\n${YELLOW}💡 ANALYSE:${NC}"
echo "Le Makefile cherche des endpoints health sur des ports spécifiques:"
echo "- Dispatcher: port 8001"
echo "- Aggregator: port 8002"
echo "- Node: port 8003"
echo ""
echo "MAIS ces services ne sont probablement pas des API HTTP!"
echo "Ce sont des workers/services backend qui communiquent via Redis/PostgreSQL."
echo ""
echo -e "${GREEN}✅ C'est NORMAL qu'ils n'aient pas d'endpoints HTTP health!${NC}"
echo ""
echo "Pour vérifier leur santé réelle:"
echo "1. Vérifier qu'ils sont 'Up' dans docker-compose ps"
echo "2. Vérifier qu'ils traitent des jobs dans les logs"
echo "3. Vérifier leur activité dans Redis"

# 6. Créer un health check adapté
cat > proper_health_check.sh << 'EOF'
#!/bin/bash
# proper_health_check.sh - Health check adapté pour SynapseGrid

echo "🏥 Health Check SynapseGrid"
echo "=========================="

# Gateway (API HTTP)
echo -n "Gateway API:     "
if curl -s http://localhost:8080/health >/dev/null 2>&1; then
    echo "✅ OK (HTTP)"
else
    echo "❌ DOWN"
fi

# Services backend (vérifier via Docker)
for service in dispatcher aggregator node1 node2; do
    printf "%-15s: " "$service"
    if docker ps | grep -q "synapse[_-]$service"; then
        echo "✅ Running (Docker)"
    else
        echo "❌ Not running"
    fi
done

# Dashboard
echo -n "Dashboard:       "
if curl -s http://localhost:3000 >/dev/null 2>&1; then
    echo "✅ OK (HTTP)"
else
    echo "❌ DOWN"
fi

# Redis
echo -n "Redis:           "
if docker exec synapse_redis redis-cli ping >/dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ DOWN"
fi

# PostgreSQL
echo -n "PostgreSQL:      "
if docker exec synapse_postgres pg_isready >/dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ DOWN"
fi

# Activité du système
echo ""
echo "📊 Activité du système:"
echo -n "Jobs en queue: "
docker exec synapse_redis redis-cli llen "jobs:queue:eu-west-1" 2>/dev/null || echo "0"
echo -n "Nodes actifs:  "
docker exec synapse_redis redis-cli keys "node:*:*:info" 2>/dev/null | wc -l || echo "0"
EOF

chmod +x proper_health_check.sh

echo -e "\n${GREEN}✅ Script de health check adapté créé: ./proper_health_check.sh${NC}"

# 7. Mettre à jour le Makefile
echo -e "\n${YELLOW}📝 Pour corriger le Makefile, remplacez la target health-check par:${NC}"
cat << 'EOF'

health-check:
	@echo "$(YELLOW)[HEALTH] Vérification de la santé des services...$(NC)"
	@echo -n "Gateway API:     " && (curl -s http://localhost:8080/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "Dispatcher:      " && (docker ps | grep -q synapse_dispatcher && echo "$(GREEN)✅ Running$(NC)" || echo "$(RED)❌ Not running$(NC)")
	@echo -n "Aggregator:      " && (docker ps | grep -q synapse_aggregator && echo "$(GREEN)✅ Running$(NC)" || echo "$(RED)❌ Not running$(NC)")
	@echo -n "Node1:           " && (docker ps | grep -q synapse_node1 && echo "$(GREEN)✅ Running$(NC)" || echo "$(RED)❌ Not running$(NC)")
	@echo -n "Node2:           " && (docker ps | grep -q synapse_node2 && echo "$(GREEN)✅ Running$(NC)" || echo "$(RED)❌ Not running$(NC)")
	@echo -n "Dashboard:       " && (curl -s http://localhost:3000 >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "Redis:           " && (docker exec synapse_redis redis-cli ping >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "PostgreSQL:      " && (docker exec synapse_postgres pg_isready >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
EOF

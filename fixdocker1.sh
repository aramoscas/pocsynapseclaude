#!/bin/bash

# 🧪 Script de test pour vérifier que tous les fixes fonctionnent

echo "🧪 Test des corrections SynapseGrid"
echo "=================================="

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[TEST]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; }

TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    if [ $1 -eq 0 ]; then
        success "$2"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        error "$2"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo ""
log "1. Test Makefile"
echo "----------------"

# Test Makefile existe et syntaxe
if [ -f "Makefile" ]; then
    make help >/dev/null 2>&1
    test_result $? "Makefile syntaxe valide"
    
    if grep -q "dashboard-start" Makefile; then
        test_result 0 "Makefile contient dashboard-start"
    else
        test_result 1 "Makefile ne contient pas dashboard-start"
    fi
    
    if grep -q "docker compose" Makefile; then
        test_result 0 "Makefile utilise 'docker compose' moderne"
    else
        test_result 1 "Makefile utilise encore 'docker-compose' obsolète"
    fi
else
    test_result 1 "Makefile manquant"
fi

echo ""
log "2. Test Docker Compose"
echo "---------------------"

if [ -f "docker-compose.yml" ]; then
    if grep -q "^version:" docker-compose.yml; then
        test_result 1 "docker-compose.yml contient encore 'version' obsolète"
    else
        test_result 0 "Attribut 'version' obsolète supprimé"
    fi
    
    if command -v docker >/dev/null 2>&1; then
        docker compose config >/dev/null 2>&1
        test_result $? "docker-compose.yml syntaxe valide"
    else
        warn "Docker non disponible pour test syntaxe"
    fi
else
    test_result 1 "docker-compose.yml manquant"
fi

echo ""
log "3. Test Dashboard"
echo "----------------"

if [ -d "dashboard" ]; then
    test_result 0 "Répertoire dashboard existe"
    
    if [ -f "dashboard/package.json" ]; then
        test_result 0 "package.json présent"
    else
        test_result 1 "package.json manquant"
    fi
    
    if [ -f "dashboard/public/index.html" ]; then
        test_result 0 "index.html présent (problème résolu)"
    else
        test_result 1 "index.html manquant"
    fi
    
    if [ -d "dashboard/node_modules" ]; then
        test_result 0 "Dépendances npm installées"
    else
        test_result 1 "Dépendances npm manquantes"
    fi
else
    test_result 1 "Répertoire dashboard manquant"
fi

echo ""
log "4. Test Dockerfiles"
echo "------------------"

for service in gateway dispatcher aggregator node; do
    dockerfile="services/$service/Dockerfile"
    if [ -f "$dockerfile" ]; then
        if grep -q "HEALTHCHECK.*\\\\\\\\.*CMD" "$dockerfile"; then
            test_result 1 "Dockerfile $service: HEALTHCHECK malformé"
        else
            test_result 0 "Dockerfile $service: Syntaxe correcte"
        fi
        
        if [ -f "services/$service/requirements.txt" ]; then
            test_result 0 "requirements.txt $service présent"
        else
            test_result 1 "requirements.txt $service manquant"
        fi
    else
        warn "Dockerfile $service manquant (optionnel)"
    fi
done

echo ""
log "5. Test Ports"
echo "------------"

check_port() {
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i:$1 >/dev/null 2>&1; then
            test_result 1 "Port $1 occupé"
        else
            test_result 0 "Port $1 disponible"
        fi
    else
        warn "lsof non disponible pour test ports"
    fi
}

check_port 3000  # Dashboard
check_port 8080  # Gateway

echo ""
log "6. Test Node.js"
echo "--------------"

if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -ge 16 ]; then
        test_result 0 "Node.js version OK ($(node --version))"
    else
        test_result 1 "Node.js version trop ancienne ($(node --version))"
    fi
else
    test_result 1 "Node.js non installé"
fi

if command -v npm >/dev/null 2>&1; then
    test_result 0 "npm disponible"
else
    test_result 1 "npm non disponible"
fi

echo ""
log "7. Test Scripts"
echo "--------------"

for script in start_synapse.sh stop_synapse.sh; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        test_result 0 "Script $script présent et exécutable"
    else
        test_result 1 "Script $script manquant ou non exécutable"
    fi
done

echo ""
echo "=================================="
echo "📊 RÉSULTATS DES TESTS"
echo "=================================="
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 TOUS LES TESTS PASSÉS !${NC}"
    echo -e "✅ $TESTS_PASSED tests réussis"
    echo ""
    echo -e "${GREEN}🚀 Votre système est prêt !${NC}"
    echo ""
    echo "Commandes pour démarrer :"
    echo "  make start"
    echo "  ./start_synapse.sh"
    echo ""
    echo "URLs après démarrage :"
    echo "  Dashboard : http://localhost:3000"
    echo "  Gateway   : http://localhost:8080"
else
    echo -e "${RED}❌ CERTAINS TESTS ONT ÉCHOUÉ${NC}"
    echo -e "✅ $TESTS_PASSED tests réussis"
    echo -e "❌ $TESTS_FAILED tests échoués"
    echo ""
    echo -e "${YELLOW}🔧 Actions recommandées :${NC}"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo "  1. Exécutez à nouveau : ./ultimate_fix.sh"
        echo "  2. Vérifiez les logs : cat dashboard.log"
        echo "  3. Testez Docker : docker compose config"
        echo "  4. Vérifiez Node.js : node --version"
    fi
fi

echo ""
echo "📝 Pour plus de détails :"
echo "  make status    # Statut des services"
echo "  make logs      # Logs détaillés"
echo "  make help      # Aide complète"

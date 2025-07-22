#!/bin/bash
# diagnose_services.sh - Diagnostic complet des services SynapseGrid

set -e

echo "🔍 Diagnostic des services SynapseGrid"
echo "======================================"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# 1. Vérifier l'état des conteneurs
print_info "État des conteneurs Docker:"
echo ""
docker-compose ps

# 2. Vérifier les logs de chaque service
echo ""
print_info "Analyse des logs des services défaillants..."

# Fonction pour analyser les logs d'un service
check_service_logs() {
    local service=$1
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Service: $service"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Récupérer les dernières lignes de log
    local logs=$(docker-compose logs --tail=20 $service 2>&1)
    
    # Identifier les erreurs communes
    if echo "$logs" | grep -q "ModuleNotFoundError"; then
        print_error "Module Python manquant"
        echo "$logs" | grep -A2 -B2 "ModuleNotFoundError"
    elif echo "$logs" | grep -q "cannot import name"; then
        print_error "Erreur d'import"
        echo "$logs" | grep -A2 -B2 "cannot import"
    elif echo "$logs" | grep -q "Connection refused"; then
        print_error "Connexion refusée"
        echo "$logs" | grep -A2 -B2 "Connection refused"
    elif echo "$logs" | grep -q "No such file or directory"; then
        print_error "Fichier manquant"
        echo "$logs" | grep -A2 -B2 "No such file"
    elif echo "$logs" | grep -q "SyntaxError"; then
        print_error "Erreur de syntaxe Python"
        echo "$logs" | grep -A2 -B2 "SyntaxError"
    else
        # Afficher les dernières lignes si pas d'erreur identifiée
        echo "Dernières lignes du log:"
        echo "$logs" | tail -10
    fi
}

# Analyser chaque service défaillant
for service in dispatcher aggregator node1 node2 dashboard; do
    check_service_logs $service
done

# 3. Vérifier la structure des fichiers
echo ""
print_info "Vérification de la structure des fichiers..."

for service in dispatcher aggregator node dashboard; do
    echo ""
    echo "Service $service:"
    if [ -f "services/$service/main.py" ]; then
        print_success "main.py existe"
        # Vérifier la syntaxe Python
        if python3 -m py_compile "services/$service/main.py" 2>/dev/null; then
            print_success "Syntaxe Python correcte"
        else
            print_error "Erreur de syntaxe dans main.py"
        fi
    else
        print_error "main.py manquant!"
    fi
    
    if [ -f "services/$service/requirements.txt" ]; then
        print_success "requirements.txt existe"
    else
        print_warning "requirements.txt manquant"
    fi
    
    if [ -f "services/$service/Dockerfile" ]; then
        print_success "Dockerfile existe"
    else
        print_error "Dockerfile manquant!"
    fi
done

# 4. Vérifier les connexions réseau
echo ""
print_info "Test des connexions réseau..."

# Test Redis
if docker exec synapse_redis redis-cli ping > /dev/null 2>&1; then
    print_success "Redis accessible"
else
    print_error "Redis inaccessible"
fi

# Test PostgreSQL
if docker exec synapse_postgres pg_isready -U synapse > /dev/null 2>&1; then
    print_success "PostgreSQL accessible"
else
    print_error "PostgreSQL inaccessible"
fi

# 5. Solutions proposées
echo ""
echo "🔧 SOLUTIONS PROPOSÉES"
echo "====================="

# Identifier les problèmes les plus courants
if docker-compose logs | grep -q "ModuleNotFoundError.*redis"; then
    echo ""
    print_warning "Problem: Module redis manquant"
    echo "Solution: Vérifier que redis est dans requirements.txt"
fi

if docker-compose logs | grep -q "No such file or directory.*main.py"; then
    echo ""
    print_warning "Problem: Fichiers main.py manquants"
    echo "Solution: Créer les fichiers services manquants"
fi

if docker-compose logs | grep -q "python.*not found"; then
    echo ""
    print_warning "Problem: Python non trouvé dans l'image"
    echo "Solution: Vérifier les Dockerfiles"
fi

# 6. Créer un script de réparation rapide
cat > quick_fix.sh << 'EOF'
#!/bin/bash
# quick_fix.sh - Réparation rapide des services

echo "🔧 Réparation rapide des services..."

# S'assurer que tous les fichiers requirements.txt existent
for service in dispatcher aggregator node dashboard; do
    if [ ! -f "services/$service/requirements.txt" ]; then
        echo "redis==4.6.0" > services/$service/requirements.txt
        echo "psycopg2-binary==2.9.9" >> services/$service/requirements.txt
        echo "✅ requirements.txt créé pour $service"
    fi
done

# Reconstruire les images
echo "🔨 Reconstruction des images..."
docker-compose build --no-cache dispatcher aggregator node1 node2 dashboard

# Redémarrer les services
echo "🚀 Redémarrage des services..."
docker-compose up -d

echo "✅ Réparation terminée!"
EOF

chmod +x quick_fix.sh

echo ""
print_info "Script de réparation rapide créé: ./quick_fix.sh"

# 7. Afficher le résumé
echo ""
echo "📊 RÉSUMÉ DU DIAGNOSTIC"
echo "======================"

working=0
failed=0

for service in gateway dispatcher aggregator node1 node2 dashboard; do
    if docker-compose ps | grep -E "^synapse[_-]$service.*Up" > /dev/null 2>&1; then
        echo "✅ $service: UP"
        ((working++))
    else
        echo "❌ $service: DOWN"
        ((failed++))
    fi
done

echo ""
echo "Services actifs: $working/$((working + failed))"

if [ $failed -gt 0 ]; then
    echo ""
    print_warning "Pour réparer rapidement: ./quick_fix.sh"
    echo ""
    echo "Pour une analyse détaillée d'un service spécifique:"
    echo "  docker-compose logs -f <service_name>"
fi

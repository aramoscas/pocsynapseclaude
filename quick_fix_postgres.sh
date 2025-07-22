#!/bin/bash
# quick_fix_postgres.sh
# Correction rapide des tables PostgreSQL

set -e

echo "🚀 Correction rapide PostgreSQL"
echo "=============================="
echo ""

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Option 1: Créer les tables directement (rapide)
if [ "$1" == "--quick" ] || [ "$1" == "" ]; then
    print_info "Création directe des tables dans PostgreSQL existant..."
    
    docker exec synapse_postgres psql -U synapse -d synapse << 'EOF'
-- Création rapide des tables essentielles

-- Table jobs (la plus importante)
CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(50) PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    client_id VARCHAR(100),
    node_id VARCHAR(50),
    status VARCHAR(20) DEFAULT 'pending',
    priority INTEGER DEFAULT 1,
    submitted_at TIMESTAMP DEFAULT NOW(),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    input_data JSONB,
    output_data JSONB,
    error_message TEXT
);

-- Table nodes
CREATE TABLE IF NOT EXISTS nodes (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    region VARCHAR(50),
    status VARCHAR(20) DEFAULT 'offline',
    gpu_model VARCHAR(100),
    cpu_cores INTEGER,
    memory_gb INTEGER,
    capabilities JSONB,
    last_heartbeat TIMESTAMP DEFAULT NOW()
);

-- Table metrics
CREATE TABLE IF NOT EXISTS metrics (
    id SERIAL PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value FLOAT NOT NULL,
    timestamp TIMESTAMP DEFAULT NOW()
);

-- Index essentiels
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_submitted_at ON jobs(submitted_at);
CREATE INDEX IF NOT EXISTS idx_nodes_status ON nodes(status);

-- Vérification
\dt

SELECT 'Tables créées avec succès!' as status;
EOF

    print_status "Tables créées!"
    
    # Redémarrer le gateway pour qu'il prenne en compte les changements
    print_info "Redémarrage du gateway..."
    docker-compose restart gateway
    
    print_status "Correction appliquée!"
    
# Option 2: Réinitialisation complète
elif [ "$1" == "--reset" ]; then
    print_warning "Réinitialisation complète de PostgreSQL..."
    
    # Arrêter les services
    print_info "Arrêt des services..."
    docker-compose stop
    
    # Supprimer le conteneur et le volume PostgreSQL
    print_info "Suppression du volume PostgreSQL..."
    docker-compose rm -f postgres
    docker volume rm synapsegrid-poc_postgres_data 2>/dev/null || true
    docker volume rm $(docker volume ls -q | grep postgres) 2>/dev/null || true
    
    # S'assurer que le script d'init est en place
    print_info "Mise en place des scripts d'initialisation..."
    mkdir -p sql
    
    # Créer le script d'init s'il n'existe pas
    if [ ! -f "sql/00-init-synapsegrid.sql" ]; then
        ./setup_postgres_auto_init.sh 2>/dev/null || true
    fi
    
    # Redémarrer PostgreSQL
    print_info "Redémarrage de PostgreSQL..."
    docker-compose up -d postgres
    
    # Attendre que PostgreSQL soit prêt
    print_info "Attente de l'initialisation de PostgreSQL..."
    sleep 15
    
    # Vérifier
    docker exec synapse_postgres psql -U synapse -d synapse -c '\dt' || true
    
    # Redémarrer tous les services
    print_info "Redémarrage de tous les services..."
    docker-compose up -d
    
    print_status "Réinitialisation complète terminée!"
    
else
    echo "Usage: $0 [--quick|--reset]"
    echo ""
    echo "Options:"
    echo "  --quick  : Créer les tables dans PostgreSQL existant (par défaut)"
    echo "  --reset  : Réinitialiser complètement PostgreSQL"
    echo ""
    exit 1
fi

# Test final
echo ""
print_info "Test de soumission de job..."

# Attendre un peu
sleep 5

# Soumettre un job de test
response=$(curl -s -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -H "X-Client-ID: quick-fix-test" \
  -d '{"model_name": "test-model", "input_data": {"test": true}}')

if echo "$response" | grep -q "job_id"; then
    print_status "Job soumis avec succès!"
    echo "Réponse: $response"
    
    # Vérifier dans PostgreSQL
    echo ""
    print_info "Vérification dans PostgreSQL..."
    docker exec synapse_postgres psql -U synapse -d synapse -c "SELECT id, model_name, status FROM jobs ORDER BY submitted_at DESC LIMIT 5;"
else
    print_warning "Erreur lors de la soumission du job"
    echo "Réponse: $response"
fi

echo ""
print_status "Script terminé!"
echo ""
echo "📊 Commandes utiles:"
echo "  Voir les jobs:     docker exec synapse_postgres psql -U synapse -d synapse -c 'SELECT * FROM jobs;'"
echo "  Voir les nodes:    docker exec synapse_postgres psql -U synapse -d synapse -c 'SELECT * FROM nodes;'"
echo "  Logs du gateway:   docker-compose logs -f gateway"
echo "  Soumettre un job:  make submit-job"

#!/bin/bash
# force_create_tables.sh
# Force la création des tables PostgreSQL

set -e

echo "🔨 Création forcée des tables PostgreSQL"
echo "======================================="
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

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Attendre que PostgreSQL soit prêt
print_info "Attente de PostgreSQL..."
until docker exec synapse_postgres pg_isready -U synapse -d synapse > /dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo ""
print_status "PostgreSQL est prêt"

# Créer les tables directement
print_info "Création des tables..."

docker exec -i synapse_postgres psql -U synapse -d synapse << 'EOF'
-- Script de création des tables SynapseGrid
-- Version simplifiée et corrigée

-- Drop des tables existantes pour repartir proprement (optionnel)
-- DROP TABLE IF EXISTS job_results CASCADE;
-- DROP TABLE IF EXISTS jobs CASCADE;
-- DROP TABLE IF EXISTS nodes CASCADE;
-- DROP TABLE IF EXISTS metrics CASCADE;
-- DROP TABLE IF EXISTS clients CASCADE;

-- Table clients
CREATE TABLE IF NOT EXISTS clients (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100),
    api_key VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
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

-- Table jobs
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

-- Données par défaut
INSERT INTO clients (id, name, api_key) VALUES 
    ('test-client', 'Test Client', 'test-token'),
    ('dashboard', 'Dashboard Client', 'dashboard-token'),
    ('cli', 'CLI Client', 'cli-token')
ON CONFLICT (id) DO NOTHING;

-- Afficher les tables créées
\echo ''
\echo 'Tables créées:'
\dt

-- Compter les enregistrements
\echo ''
\echo 'Clients existants:'
SELECT COUNT(*) as count FROM clients;

\echo ''
\echo '✅ Création des tables terminée!'
EOF

if [ $? -eq 0 ]; then
    print_status "Tables créées avec succès"
else
    print_error "Erreur lors de la création des tables"
    exit 1
fi

# Redémarrer le gateway pour qu'il prenne en compte les tables
print_info "Redémarrage du gateway..."
docker-compose restart gateway

# Attendre un peu
sleep 5

# Test de soumission de job
print_info "Test de soumission d'un job..."

response=$(curl -s -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -H "X-Client-ID: force-create-test" \
  -d '{
    "model_name": "test-model",
    "input_data": {"message": "Test après création forcée"},
    "priority": 1
  }')

echo "Réponse: $response"

if echo "$response" | grep -q "job_id"; then
    print_status "Job soumis avec succès!"
    
    # Extraire le job_id
    job_id=$(echo "$response" | grep -o '"job_id":"[^"]*"' | cut -d'"' -f4)
    
    # Vérifier dans PostgreSQL
    echo ""
    print_info "Vérification dans PostgreSQL..."
    docker exec synapse_postgres psql -U synapse -d synapse -c "SELECT id, model_name, status, client_id FROM jobs WHERE id = '$job_id';"
    
else
    print_error "Échec de la soumission du job"
    echo ""
    echo "Vérification des tables:"
    docker exec synapse_postgres psql -U synapse -d synapse -c "\dt"
fi

# Résumé final
echo ""
print_status "Configuration terminée!"
echo ""
echo "📊 Commandes utiles:"
echo ""
echo "Voir toutes les tables:"
echo "  docker exec synapse_postgres psql -U synapse -d synapse -c '\\dt'"
echo ""
echo "Voir les jobs:"
echo "  docker exec synapse_postgres psql -U synapse -d synapse -c 'SELECT * FROM jobs ORDER BY submitted_at DESC;'"
echo ""
echo "Voir les nodes:"
echo "  docker exec synapse_postgres psql -U synapse -d synapse -c 'SELECT * FROM nodes;'"
echo ""
echo "Soumettre un job:"
echo "  make submit-job"
echo ""
echo "Si vous avez encore des erreurs, vérifiez les logs:"
echo "  docker-compose logs -f gateway"

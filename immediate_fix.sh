#!/bin/bash
# immediate_fix.sh
# Solution immédiate pour créer les tables

set -e

echo "🚀 Solution immédiate pour SynapseGrid"
echo "====================================="
echo ""

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Option 1: Remplacer le fichier SQL problématique
print_info "Option 1: Remplacer le fichier SQL"
if [ -f "sql/00-init-synapsegrid.sql" ]; then
    mv sql/00-init-synapsegrid.sql sql/00-init-synapsegrid.sql.problematic
    print_status "Ancien fichier sauvegardé"
fi

# Copier la version corrigée
cat > sql/00-init-synapsegrid.sql << 'EOF'
-- Script d'initialisation simplifié et fonctionnel

\echo 'Creating SynapseGrid tables...'

-- Tables essentielles seulement, sans complications
CREATE TABLE IF NOT EXISTS clients (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100),
    api_key VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

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
    ('dashboard', 'Dashboard Client', 'dashboard-token')
ON CONFLICT (id) DO NOTHING;

\echo 'Tables created successfully!'
EOF

print_status "Nouveau fichier SQL créé (version simplifiée)"

# Option 2: Créer les tables directement maintenant
print_info "Option 2: Création directe des tables"

# Attendre que PostgreSQL soit prêt
until docker exec synapse_postgres pg_isready -U synapse > /dev/null 2>&1; do
    echo -n "."
    sleep 1
done
echo ""

# Créer les tables
docker exec synapse_postgres psql -U synapse -d synapse << 'EOF'
-- Création directe et simple des tables

CREATE TABLE IF NOT EXISTS clients (
    id VARCHAR(50) PRIMARY KEY,
    api_key VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(50) PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    client_id VARCHAR(100),
    status VARCHAR(20) DEFAULT 'pending',
    priority INTEGER DEFAULT 1,
    submitted_at TIMESTAMP DEFAULT NOW(),
    input_data JSONB
);

INSERT INTO clients VALUES ('test-client', 'test-token') ON CONFLICT DO NOTHING;

\dt
EOF

print_status "Tables créées directement dans PostgreSQL"

# Redémarrer les services
print_info "Redémarrage des services..."
docker-compose restart gateway
sleep 5

# Test
print_info "Test de soumission de job..."
response=$(curl -s -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -d '{"model_name": "test-immediate", "input_data": {"message": "Fix appliqué!"}}')

echo "Réponse: $response"

if echo "$response" | grep -q "job_id"; then
    print_status "✅ SUCCÈS! Les jobs fonctionnent!"
    
    # Vérifier dans la DB
    echo ""
    print_info "Jobs dans PostgreSQL:"
    docker exec synapse_postgres psql -U synapse -d synapse -c "SELECT id, model_name, status FROM jobs ORDER BY submitted_at DESC LIMIT 5;"
else
    echo ""
    echo "Si ça ne fonctionne toujours pas, exécutez:"
    echo ""
    echo "# Réinitialiser complètement PostgreSQL:"
    echo "docker-compose down -v"
    echo "docker-compose up -d"
fi

echo ""
print_status "Terminé!"
echo ""
echo "Le système devrait maintenant fonctionner."
echo "Pour soumettre d'autres jobs: make submit-job"

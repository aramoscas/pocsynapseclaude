#!/bin/bash
# init_postgres_tables.sh
# Initialise les tables PostgreSQL pour SynapseGrid

set -e

echo "🗄️  Initialisation des tables PostgreSQL"
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

# Étape 1: Vérifier que PostgreSQL est accessible
print_info "Vérification de PostgreSQL..."

if ! docker exec synapse_postgres pg_isready -U synapse > /dev/null 2>&1; then
    print_error "PostgreSQL n'est pas prêt"
    print_info "Démarrage de PostgreSQL..."
    docker-compose up -d postgres
    sleep 10
fi

# Étape 2: Créer le fichier SQL d'initialisation
print_info "Création du fichier SQL d'initialisation..."

mkdir -p sql

cat > sql/init_tables.sql << 'EOF'
-- SynapseGrid Database Schema
-- Drop tables if they exist (for clean reset)
DROP TABLE IF EXISTS job_results CASCADE;
DROP TABLE IF EXISTS jobs CASCADE;
DROP TABLE IF EXISTS node_capabilities CASCADE;
DROP TABLE IF EXISTS nodes CASCADE;
DROP TABLE IF EXISTS metrics CASCADE;
DROP TABLE IF EXISTS clients CASCADE;

-- Create clients table
CREATE TABLE clients (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100),
    api_key VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create nodes table
CREATE TABLE nodes (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    region VARCHAR(50),
    status VARCHAR(20) DEFAULT 'offline',
    gpu_model VARCHAR(100),
    cpu_cores INTEGER,
    memory_gb INTEGER,
    capabilities JSONB,
    metadata JSONB,
    registered_at TIMESTAMP DEFAULT NOW(),
    last_heartbeat TIMESTAMP DEFAULT NOW(),
    total_jobs_completed INTEGER DEFAULT 0,
    total_compute_time_seconds BIGINT DEFAULT 0
);

-- Create jobs table
CREATE TABLE jobs (
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
    error_message TEXT,
    compute_time_ms INTEGER,
    tokens_processed INTEGER,
    cost_nrg DECIMAL(20, 8),
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE SET NULL
);

-- Create job_results table for detailed results
CREATE TABLE job_results (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(50) NOT NULL,
    result_type VARCHAR(50),
    result_data JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
);

-- Create node_capabilities table
CREATE TABLE node_capabilities (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(50) NOT NULL,
    capability VARCHAR(50) NOT NULL,
    version VARCHAR(20),
    performance_score FLOAT,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    UNIQUE(node_id, capability)
);

-- Create metrics table for time-series data
CREATE TABLE metrics (
    id SERIAL PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value FLOAT NOT NULL,
    tags JSONB,
    timestamp TIMESTAMP DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_client_id ON jobs(client_id);
CREATE INDEX idx_jobs_node_id ON jobs(node_id);
CREATE INDEX idx_jobs_submitted_at ON jobs(submitted_at);
CREATE INDEX idx_jobs_status_priority ON jobs(status, priority DESC);

CREATE INDEX idx_nodes_status ON nodes(status);
CREATE INDEX idx_nodes_region ON nodes(region);
CREATE INDEX idx_nodes_last_heartbeat ON nodes(last_heartbeat);

CREATE INDEX idx_metrics_name_timestamp ON metrics(metric_name, timestamp DESC);
CREATE INDEX idx_metrics_timestamp ON metrics(timestamp DESC);

-- Create views for common queries
CREATE OR REPLACE VIEW active_nodes AS
SELECT * FROM nodes 
WHERE status = 'active' 
AND last_heartbeat > NOW() - INTERVAL '1 minute';

CREATE OR REPLACE VIEW pending_jobs AS
SELECT * FROM jobs 
WHERE status IN ('pending', 'assigned')
ORDER BY priority DESC, submitted_at ASC;

CREATE OR REPLACE VIEW job_statistics AS
SELECT 
    DATE_TRUNC('hour', submitted_at) as hour,
    COUNT(*) as total_jobs,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_jobs,
    COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed_jobs,
    AVG(CASE WHEN compute_time_ms IS NOT NULL THEN compute_time_ms END) as avg_compute_time_ms
FROM jobs
GROUP BY DATE_TRUNC('hour', submitted_at);

-- Create functions
CREATE OR REPLACE FUNCTION update_node_heartbeat(node_id_param VARCHAR)
RETURNS VOID AS $$
BEGIN
    UPDATE nodes 
    SET last_heartbeat = NOW(), status = 'active'
    WHERE id = node_id_param;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_node_load(node_id_param VARCHAR)
RETURNS FLOAT AS $$
DECLARE
    active_jobs_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO active_jobs_count
    FROM jobs
    WHERE node_id = node_id_param
    AND status IN ('running', 'assigned');
    
    RETURN active_jobs_count::FLOAT / 10.0; -- Normalize to 0-1 scale
END;
$$ LANGUAGE plpgsql;

-- Insert some initial data for testing
INSERT INTO clients (id, name, api_key) VALUES 
    ('test-client', 'Test Client', 'test-token'),
    ('dashboard', 'Dashboard Client', 'dashboard-token')
ON CONFLICT (id) DO NOTHING;

-- Success message
SELECT 'Database tables created successfully!' as status;
EOF

print_status "Fichier SQL créé"

# Étape 3: Exécuter le script SQL
print_info "Création des tables dans PostgreSQL..."

docker exec -i synapse_postgres psql -U synapse -d synapse < sql/init_tables.sql

# Étape 4: Vérifier que les tables ont été créées
print_info "Vérification des tables créées..."

echo ""
echo "Tables créées:"
docker exec synapse_postgres psql -U synapse -d synapse -c "\dt" | grep -E "(jobs|nodes|metrics|clients)"

# Étape 5: Vérifier les vues
echo ""
echo "Vues créées:"
docker exec synapse_postgres psql -U synapse -d synapse -c "\dv" | grep -E "(active_nodes|pending_jobs|job_statistics)"

# Étape 6: Tester l'insertion
print_info "Test d'insertion dans la table jobs..."

docker exec synapse_postgres psql -U synapse -d synapse << 'EOF'
-- Test d'insertion
INSERT INTO jobs (id, model_name, client_id, status, priority) 
VALUES ('test-job-1', 'test-model', 'test-client', 'pending', 1)
ON CONFLICT (id) DO NOTHING;

-- Vérifier
SELECT id, model_name, status FROM jobs WHERE id = 'test-job-1';
EOF

# Étape 7: Créer un fichier docker-entrypoint-initdb.d pour les futures initialisations
print_info "Configuration de l'initialisation automatique..."

cp sql/init_tables.sql sql/01-init-tables.sql

# Étape 8: Résumé
echo ""
print_status "Initialisation terminée!"
echo ""
echo "📊 Tables créées:"
echo "  - clients: Gestion des clients API"
echo "  - nodes: Informations sur les nodes"
echo "  - jobs: File d'attente et historique des jobs"
echo "  - job_results: Résultats détaillés des jobs"
echo "  - node_capabilities: Capacités des nodes"
echo "  - metrics: Métriques time-series"
echo ""
echo "📈 Vues créées:"
echo "  - active_nodes: Nodes actuellement actifs"
echo "  - pending_jobs: Jobs en attente"
echo "  - job_statistics: Statistiques horaires"
echo ""
echo "🎯 Prochaines étapes:"
echo "1. Redémarrer le gateway pour qu'il utilise les tables:"
echo "   docker-compose restart gateway"
echo ""
echo "2. Soumettre un job de test:"
echo "   make submit-job"
echo ""
echo "3. Vérifier les jobs dans PostgreSQL:"
echo "   docker exec synapse_postgres psql -U synapse -d synapse -c 'SELECT * FROM jobs;'"
echo ""
echo "4. Pour réinitialiser complètement la base:"
echo "   docker-compose down -v postgres"
echo "   docker-compose up -d postgres"
echo "   ./init_postgres_tables.sh"

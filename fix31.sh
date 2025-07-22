#!/bin/bash
# apply_db_fix.sh - Remplace le script d'initialisation SQL avec la version corrigée

set -e

echo "🔧 Application de la correction du schéma PostgreSQL"
echo "=================================================="

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 1. Vérifier si le répertoire sql existe
if [ ! -d "sql" ]; then
    mkdir -p sql
    print_success "Répertoire sql créé"
fi

# 2. Sauvegarder l'ancien fichier s'il existe
if [ -f "sql/init.sql" ]; then
    cp sql/init.sql sql/init.sql.backup.$(date +%Y%m%d_%H%M%S)
    print_success "Backup de l'ancien init.sql créé"
fi

# 3. Créer le nouveau fichier init.sql corrigé
cat > sql/init.sql << 'EOF'
-- init.sql - Script d'initialisation PostgreSQL pour SynapseGrid
-- Ce fichier est exécuté automatiquement au démarrage du conteneur PostgreSQL

-- Table clients
CREATE TABLE IF NOT EXISTS clients (
    id SERIAL PRIMARY KEY,
    client_id VARCHAR(64) UNIQUE NOT NULL,
    api_key_hash VARCHAR(64) NOT NULL,
    nrg_balance DECIMAL(18, 8) DEFAULT 100.0,
    lear_balance DECIMAL(18, 8) DEFAULT 10.0,
    total_jobs INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table jobs avec TOUTES les colonnes nécessaires
CREATE TABLE IF NOT EXISTS jobs (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(64) UNIQUE NOT NULL,
    client_id VARCHAR(64) NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    input_data TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'queued',
    priority INTEGER DEFAULT 1,
    estimated_cost DECIMAL(10, 6) DEFAULT 0.01,
    assigned_node VARCHAR(64),
    result TEXT,
    error TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    execution_time_ms INTEGER
);

-- Table nodes
CREATE TABLE IF NOT EXISTS nodes (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) UNIQUE NOT NULL,
    node_type VARCHAR(50) DEFAULT 'docker',
    region VARCHAR(50) DEFAULT 'eu-west-1',
    status VARCHAR(20) DEFAULT 'offline',
    capabilities TEXT DEFAULT '{}',
    gpu_info TEXT DEFAULT '{}',
    cpu_cores INTEGER DEFAULT 4,
    memory_gb DECIMAL(8, 2) DEFAULT 16.0,
    success_rate DECIMAL(5, 4) DEFAULT 1.0,
    total_jobs INTEGER DEFAULT 0,
    avg_latency_ms INTEGER DEFAULT 100,
    current_load INTEGER DEFAULT 0,
    max_concurrent INTEGER DEFAULT 1,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table job_executions
CREATE TABLE IF NOT EXISTS job_executions (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(64) NOT NULL,
    node_id VARCHAR(64) NOT NULL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    execution_time_ms INTEGER,
    tokens_used INTEGER DEFAULT 0,
    cost_nrg DECIMAL(10, 6) DEFAULT 0.0,
    reward_lear DECIMAL(10, 6) DEFAULT 0.0,
    success BOOLEAN DEFAULT false,
    error TEXT
);

-- Index pour les performances
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_client_id ON jobs(client_id);
CREATE INDEX IF NOT EXISTS idx_jobs_priority ON jobs(priority);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at);
CREATE INDEX IF NOT EXISTS idx_nodes_status ON nodes(status);
CREATE INDEX IF NOT EXISTS idx_nodes_region ON nodes(region);

-- Vue pour éviter l'erreur COALESCE
CREATE OR REPLACE VIEW v_pending_jobs AS
SELECT 
    job_id,  -- PAS de COALESCE(job_id, id)
    client_id,
    model_name,
    input_data,
    priority,
    created_at,
    submitted_at
FROM jobs
WHERE status = 'queued'  -- PAS 'pending'
ORDER BY priority DESC, created_at ASC;

-- Données de test
INSERT INTO clients (client_id, api_key_hash, nrg_balance, lear_balance) VALUES
    ('test-client', 'test-hash', 1000.0, 100.0),
    ('deploy-test', 'deploy-hash', 500.0, 50.0),
    ('demo-client', 'demo-hash', 100.0, 10.0)
ON CONFLICT (client_id) DO NOTHING;

-- Permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO synapse;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO synapse;
EOF

print_success "Nouveau fichier sql/init.sql créé"

# 4. Si la base de données existe déjà, appliquer les corrections
if docker ps | grep -q synapse_postgres; then
    print_warning "PostgreSQL est en cours d'exécution. Application des corrections..."
    
    # Créer un script de migration pour les bases existantes
    cat > sql/migrate_existing.sql << 'EOF'
-- Script de migration pour les bases existantes

-- Ajouter les colonnes manquantes si elles n'existent pas
DO $$ 
BEGIN
    -- Table jobs
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='jobs' AND column_name='priority') THEN
        ALTER TABLE jobs ADD COLUMN priority INTEGER DEFAULT 1;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='jobs' AND column_name='estimated_cost') THEN
        ALTER TABLE jobs ADD COLUMN estimated_cost DECIMAL(10, 6) DEFAULT 0.01;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='jobs' AND column_name='assigned_node') THEN
        ALTER TABLE jobs ADD COLUMN assigned_node VARCHAR(64);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='jobs' AND column_name='submitted_at') THEN
        ALTER TABLE jobs ADD COLUMN submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='jobs' AND column_name='execution_time_ms') THEN
        ALTER TABLE jobs ADD COLUMN execution_time_ms INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='jobs' AND column_name='updated_at') THEN
        ALTER TABLE jobs ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
    END IF;
    
    -- Table clients
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='clients' AND column_name='last_active') THEN
        ALTER TABLE clients ADD COLUMN last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='clients' AND column_name='total_jobs') THEN
        ALTER TABLE clients ADD COLUMN total_jobs INTEGER DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='clients' AND column_name='lear_balance') THEN
        ALTER TABLE clients ADD COLUMN lear_balance DECIMAL(18, 8) DEFAULT 10.0;
    END IF;
END $$;

-- Recréer la vue
DROP VIEW IF EXISTS v_pending_jobs;
CREATE VIEW v_pending_jobs AS
SELECT 
    job_id,
    client_id,
    model_name,
    input_data,
    priority,
    created_at,
    submitted_at
FROM jobs
WHERE status = 'queued'
ORDER BY priority DESC, created_at ASC;

-- Mettre à jour les jobs 'pending' en 'queued'
UPDATE jobs SET status = 'queued' WHERE status = 'pending';
EOF
    
    # Appliquer la migration
    docker exec -i synapse_postgres psql -U synapse -d synapse < sql/migrate_existing.sql
    print_success "Migration appliquée à la base existante"
fi

# 5. Instructions finales
echo ""
echo "🎉 Correction appliquée avec succès!"
echo "==================================="
echo ""
echo "Le fichier sql/init.sql a été mis à jour avec:"
echo "  ✅ Toutes les colonnes nécessaires (priority, estimated_cost, etc.)"
echo "  ✅ Vue v_pending_jobs sans COALESCE problématique"
echo "  ✅ Status 'queued' au lieu de 'pending'"
echo "  ✅ Index de performance"
echo ""

if docker ps | grep -q synapse_postgres; then
    echo "📝 Pour appliquer les changements à la base existante:"
    echo "   docker exec -i synapse_postgres psql -U synapse -d synapse < sql/migrate_existing.sql"
    echo ""
    echo "🔄 Ou pour réinitialiser complètement:"
    echo "   docker-compose down -v"
    echo "   docker-compose up -d"
else
    echo "📝 Pour démarrer avec la nouvelle configuration:"
    echo "   docker-compose up -d"
fi

echo ""
echo "✨ La base de données sera automatiquement initialisée correctement au prochain démarrage!"

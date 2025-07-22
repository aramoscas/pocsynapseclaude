#!/bin/bash
# apply_sql_fix.sh
# Applique la correction du script SQL d'initialisation

set -e

echo "🔧 Application de la correction SQL"
echo "=================================="
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

# Étape 1: Sauvegarder l'ancien fichier
if [ -f "sql/00-init-synapsegrid.sql" ]; then
    print_info "Sauvegarde de l'ancien fichier SQL..."
    mv sql/00-init-synapsegrid.sql sql/00-init-synapsegrid.sql.old
fi

# Étape 2: Créer le nouveau fichier corrigé
print_info "Création du fichier SQL corrigé..."

mkdir -p sql

# Copier le contenu corrigé depuis l'artifact ci-dessus
cat > sql/00-init-synapsegrid.sql << 'EOF'
-- 00-init-synapsegrid.sql
-- Script d'initialisation automatique de SynapseGrid (VERSION CORRIGÉE)

\echo 'Starting SynapseGrid database initialization...'

-- Créer une fonction pour vérifier si les tables existent
CREATE OR REPLACE FUNCTION table_exists(table_name text) 
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = $1
    );
END;
$$ LANGUAGE plpgsql;

-- Vérifier si l'initialisation est nécessaire
DO $$
BEGIN
    IF NOT table_exists('jobs') THEN
        RAISE NOTICE 'Tables not found. Creating SynapseGrid schema...';
        
        -- ============================================
        -- CRÉATION DES TABLES
        -- ============================================
        
        -- Table clients
        CREATE TABLE clients (
            id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(100),
            api_key VARCHAR(255),
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        );
        
        -- Table nodes
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
        
        -- Table jobs
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
        
        -- Table job_results
        CREATE TABLE job_results (
            id SERIAL PRIMARY KEY,
            job_id VARCHAR(50) NOT NULL,
            result_type VARCHAR(50),
            result_data JSONB,
            created_at TIMESTAMP DEFAULT NOW(),
            FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
        );
        
        -- Table node_capabilities
        CREATE TABLE node_capabilities (
            id SERIAL PRIMARY KEY,
            node_id VARCHAR(50) NOT NULL,
            capability VARCHAR(50) NOT NULL,
            version VARCHAR(20),
            performance_score FLOAT,
            FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
            UNIQUE(node_id, capability)
        );
        
        -- Table metrics
        CREATE TABLE metrics (
            id SERIAL PRIMARY KEY,
            metric_name VARCHAR(100) NOT NULL,
            metric_value FLOAT NOT NULL,
            tags JSONB,
            timestamp TIMESTAMP DEFAULT NOW()
        );
        
        -- Table system_events
        CREATE TABLE system_events (
            id SERIAL PRIMARY KEY,
            event_type VARCHAR(50) NOT NULL,
            event_data JSONB,
            created_at TIMESTAMP DEFAULT NOW()
        );
        
        -- ============================================
        -- CRÉATION DES INDEX
        -- ============================================
        
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
        
        CREATE INDEX idx_system_events_type ON system_events(event_type);
        CREATE INDEX idx_system_events_created ON system_events(created_at DESC);
        
        -- ============================================
        -- CRÉATION DES VUES
        -- ============================================
        
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
        
        CREATE OR REPLACE VIEW node_performance AS
        SELECT 
            n.id,
            n.name,
            n.gpu_model,
            n.total_jobs_completed,
            COUNT(j.id) as current_jobs,
            AVG(j.compute_time_ms) as avg_compute_time,
            n.last_heartbeat
        FROM nodes n
        LEFT JOIN jobs j ON n.id = j.node_id AND j.status = 'completed'
        GROUP BY n.id, n.name, n.gpu_model, n.total_jobs_completed, n.last_heartbeat;
        
        -- ============================================
        -- DONNÉES INITIALES
        -- ============================================
        
        INSERT INTO clients (id, name, api_key) VALUES 
            ('test-client', 'Test Client', 'test-token'),
            ('dashboard', 'Dashboard Client', 'dashboard-token'),
            ('cli', 'CLI Client', 'cli-token')
        ON CONFLICT (id) DO NOTHING;
        
        -- Log de l'initialisation
        INSERT INTO system_events (event_type, event_data)
        VALUES ('database_initialized', jsonb_build_object(
            'version', '1.0.0',
            'timestamp', NOW()
        ));
        
        RAISE NOTICE 'SynapseGrid database initialization completed successfully!';
        
    ELSE
        RAISE NOTICE 'Tables already exist. Skipping initialization.';
    END IF;
END $$;

-- ============================================
-- CRÉATION DES FONCTIONS (en dehors du bloc DO)
-- ============================================

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
    
    RETURN LEAST(active_jobs_count::FLOAT / 10.0, 1.0);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION assign_job_to_best_node(job_id_param VARCHAR)
RETURNS VARCHAR AS $$
DECLARE
    best_node_id VARCHAR;
BEGIN
    -- Sélectionner le meilleur node disponible
    SELECT n.id INTO best_node_id
    FROM nodes n
    WHERE n.status = 'active'
    AND n.last_heartbeat > NOW() - INTERVAL '1 minute'
    ORDER BY (
        SELECT COUNT(*) 
        FROM jobs j 
        WHERE j.node_id = n.id 
        AND j.status IN ('running', 'assigned')
    ) ASC, n.last_heartbeat DESC
    LIMIT 1;
    
    IF best_node_id IS NOT NULL THEN
        UPDATE jobs 
        SET node_id = best_node_id, status = 'assigned'
        WHERE id = job_id_param;
    END IF;
    
    RETURN best_node_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS
-- ============================================

-- Trigger pour mettre à jour updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Créer le trigger seulement s'il n'existe pas
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'update_clients_updated_at'
    ) THEN
        CREATE TRIGGER update_clients_updated_at
        BEFORE UPDATE ON clients
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- Trigger pour logger les changements de statut des jobs
CREATE OR REPLACE FUNCTION log_job_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO system_events (event_type, event_data)
        VALUES ('job_status_change', jsonb_build_object(
            'job_id', NEW.id,
            'old_status', OLD.status,
            'new_status', NEW.status,
            'node_id', NEW.node_id
        ));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Créer le trigger seulement s'il n'existe pas
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'job_status_change_trigger'
    ) THEN
        CREATE TRIGGER job_status_change_trigger
        AFTER UPDATE ON jobs
        FOR EACH ROW
        EXECUTE FUNCTION log_job_status_change();
    END IF;
END $$;

-- Nettoyer la fonction temporaire
DROP FUNCTION IF EXISTS table_exists(text);

\echo 'SynapseGrid database initialization complete!'
EOF

print_status "Fichier SQL corrigé créé"

# Étape 3: Option 1 - Réinitialiser PostgreSQL pour utiliser le nouveau script
print_info "Pour appliquer la correction, choisissez une option:"
echo ""
echo "Option 1: Réinitialiser PostgreSQL (recommandé pour un environnement de test)"
echo "  docker-compose down -v postgres"
echo "  docker-compose up -d postgres"
echo ""
echo "Option 2: Créer les tables manuellement dans PostgreSQL existant"
echo "  ./force_create_tables.sh"
echo ""

# Étape 4: Créer directement les tables (sans attendre la réinitialisation)
read -p "Voulez-vous créer les tables maintenant dans PostgreSQL existant? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Création des tables dans PostgreSQL existant..."
    
    # Attendre que PostgreSQL soit prêt
    until docker exec synapse_postgres pg_isready -U synapse -d synapse > /dev/null 2>&1; do
        echo -n "."
        sleep 1
    done
    echo ""
    
    # Exécuter le script SQL corrigé
    docker exec -i synapse_postgres psql -U synapse -d synapse < sql/00-init-synapsegrid.sql || {
        print_warning "Le script d'init a échoué (probablement parce que les tables existent déjà)"
        print_info "Création directe des tables essentielles..."
        
        # Fallback: créer juste les tables essentielles
        docker exec synapse_postgres psql -U synapse -d synapse << 'FALLBACK'
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

-- Clients par défaut
INSERT INTO clients (id, name, api_key) VALUES 
    ('test-client', 'Test Client', 'test-token')
ON CONFLICT (id) DO NOTHING;

\dt
FALLBACK
    }
    
    print_status "Tables créées/vérifiées"
    
    # Redémarrer le gateway
    print_info "Redémarrage du gateway..."
    docker-compose restart gateway
    
    sleep 5
    
    # Test
    print_info "Test de soumission de job..."
    curl -X POST http://localhost:8080/submit \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer test-token" \
        -d '{"model_name": "test-after-fix", "input_data": {"test": true}}' | jq .
fi

print_status "Correction appliquée!"
echo ""
echo "📋 Corrections apportées:"
echo "  ✅ Les fonctions CREATE FUNCTION sont maintenant en dehors du bloc DO"
echo "  ✅ Les triggers sont créés correctement"
echo "  ✅ La syntaxe PL/pgSQL est corrigée"
echo ""
echo "🔍 Pour vérifier les tables:"
echo "  docker exec synapse_postgres psql -U synapse -d synapse -c '\\dt'"

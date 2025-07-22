#!/bin/bash
# setup_postgres_auto_init.sh
# Configure l'initialisation automatique de PostgreSQL

set -e

echo "🗄️  Configuration de l'initialisation automatique PostgreSQL"
echo "=========================================================="
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

# Étape 1: Créer le répertoire sql s'il n'existe pas
print_info "Création du répertoire sql..."
mkdir -p sql

# Étape 2: Créer le script d'initialisation principal
print_info "Création du script d'initialisation..."

cat > sql/00-init-synapsegrid.sql << 'EOF'
-- 00-init-synapsegrid.sql
-- Script d'initialisation automatique de SynapseGrid
-- Ce script est exécuté automatiquement par PostgreSQL au démarrage si la base est vide

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
        
        -- Table system_events (nouvelle table pour l'audit)
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
        -- CRÉATION DES FONCTIONS
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
            SELECT n.id INTO best_node_id
            FROM active_nodes n
            LEFT JOIN (
                SELECT node_id, COUNT(*) as job_count
                FROM jobs
                WHERE status IN ('running', 'assigned')
                GROUP BY node_id
            ) j ON n.id = j.node_id
            ORDER BY COALESCE(j.job_count, 0) ASC, n.last_heartbeat DESC
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
        
        CREATE TRIGGER update_clients_updated_at
        BEFORE UPDATE ON clients
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
        
        -- Trigger pour logger les événements importants
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
        
        CREATE TRIGGER job_status_change_trigger
        AFTER UPDATE ON jobs
        FOR EACH ROW
        EXECUTE FUNCTION log_job_status_change();
        
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

-- Nettoyer la fonction temporaire
DROP FUNCTION IF EXISTS table_exists(text);

\echo 'SynapseGrid database initialization complete!'
EOF

print_status "Script d'initialisation créé"

# Étape 3: Créer un script de vérification de santé
print_info "Création du script de vérification..."

cat > sql/99-health-check.sql << 'EOF'
-- 99-health-check.sql
-- Script de vérification de santé exécuté après l'initialisation

\echo 'Performing database health check...'

DO $$
DECLARE
    table_count INTEGER;
    view_count INTEGER;
    function_count INTEGER;
BEGIN
    -- Compter les tables
    SELECT COUNT(*) INTO table_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_type = 'BASE TABLE';
    
    -- Compter les vues
    SELECT COUNT(*) INTO view_count
    FROM information_schema.views
    WHERE table_schema = 'public';
    
    -- Compter les fonctions
    SELECT COUNT(*) INTO function_count
    FROM information_schema.routines
    WHERE routine_schema = 'public'
    AND routine_type = 'FUNCTION';
    
    RAISE NOTICE 'Database health check:';
    RAISE NOTICE '  Tables: %', table_count;
    RAISE NOTICE '  Views: %', view_count;
    RAISE NOTICE '  Functions: %', function_count;
    
    IF table_count >= 7 AND view_count >= 4 AND function_count >= 4 THEN
        RAISE NOTICE 'Health check: PASSED ✓';
    ELSE
        RAISE WARNING 'Health check: FAILED - Some objects may be missing';
    END IF;
END $$;

\echo 'Health check complete!'
EOF

# Étape 4: Mettre à jour docker-compose.yml pour monter le répertoire sql
print_info "Mise à jour de docker-compose.yml..."

# Vérifier si le volume sql est déjà monté
if ! grep -q "./sql:/docker-entrypoint-initdb.d" docker-compose.yml; then
    print_info "Ajout du volume sql dans docker-compose.yml..."
    
    # Créer un nouveau docker-compose avec le volume sql
    sed -i.bak '/postgres_data:\/var\/lib\/postgresql\/data/a\
      - ./sql:/docker-entrypoint-initdb.d' docker-compose.yml
    
    print_status "docker-compose.yml mis à jour"
else
    print_status "Volume sql déjà configuré dans docker-compose.yml"
fi

# Étape 5: Créer un README pour le dossier sql
cat > sql/README.md << 'EOF'
# Scripts d'initialisation PostgreSQL

Ce dossier contient les scripts d'initialisation automatique de PostgreSQL pour SynapseGrid.

## Scripts

- `00-init-synapsegrid.sql` : Initialisation principale (tables, vues, fonctions)
- `99-health-check.sql` : Vérification de santé après initialisation

## Fonctionnement

Ces scripts sont automatiquement exécutés par PostgreSQL au démarrage si :
1. Le volume de données est vide (première initialisation)
2. Les scripts sont dans `/docker-entrypoint-initdb.d/`

Les scripts sont exécutés dans l'ordre alphabétique.

## Pour réinitialiser la base de données

```bash
# Arrêter et supprimer le volume PostgreSQL
docker-compose down -v postgres

# Redémarrer PostgreSQL (les scripts s'exécuteront automatiquement)
docker-compose up -d postgres

# Vérifier les logs
docker-compose logs postgres
```

## Pour ajouter de nouveaux scripts

Nommez-les avec un préfixe numérique pour contrôler l'ordre d'exécution :
- `01-xxx.sql` : Après l'init principale
- `50-xxx.sql` : Au milieu
- `98-xxx.sql` : Avant le health check
EOF

# Étape 6: Tester si PostgreSQL est en cours d'exécution
if docker ps | grep -q synapse_postgres; then
    print_info "PostgreSQL est en cours d'exécution"
    
    echo ""
    echo "Pour appliquer les changements, vous devez :"
    echo "1. Arrêter PostgreSQL et supprimer son volume :"
    echo "   ${YELLOW}docker-compose down -v postgres${NC}"
    echo ""
    echo "2. Redémarrer PostgreSQL :"
    echo "   ${YELLOW}docker-compose up -d postgres${NC}"
    echo ""
    echo "Les tables seront créées automatiquement au démarrage!"
else
    print_info "PostgreSQL n'est pas en cours d'exécution"
    echo "Démarrez-le avec : ${YELLOW}docker-compose up -d postgres${NC}"
fi

# Résumé
echo ""
print_status "Configuration terminée!"
echo ""
echo "📋 Ce qui a été configuré :"
echo "  ✅ Script d'initialisation automatique (00-init-synapsegrid.sql)"
echo "  ✅ Script de vérification de santé (99-health-check.sql)"
echo "  ✅ Volume monté dans docker-compose.yml"
echo "  ✅ Documentation dans sql/README.md"
echo ""
echo "🚀 Les scripts s'exécuteront automatiquement :"
echo "  - Au premier démarrage de PostgreSQL"
echo "  - Après un 'docker-compose down -v postgres'"
echo "  - Si la base de données est vide"
echo ""
echo "📊 Pour vérifier l'initialisation :"
echo "  ${YELLOW}docker-compose logs postgres | grep -i 'synapsegrid'${NC}"
echo ""
echo "🔍 Pour voir les tables créées :"
echo "  ${YELLOW}docker exec synapse_postgres psql -U synapse -d synapse -c '\\dt'${NC}"

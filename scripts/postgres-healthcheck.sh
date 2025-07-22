#!/bin/bash
# postgres-healthcheck.sh
# Healthcheck qui crée les tables si nécessaire

# Attendre un peu au premier démarrage
if [ ! -f /tmp/healthcheck_done ]; then
    sleep 5
    touch /tmp/healthcheck_done
fi

# Vérifier si PostgreSQL est prêt
pg_isready -U synapse -d synapse -h localhost || exit 1

# Vérifier et créer les tables si nécessaire
psql -U synapse -d synapse -h localhost << 'SQL' 2>/dev/null || true

-- Créer les tables seulement si elles n'existent pas
DO $$
BEGIN
    -- Table jobs
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'jobs') THEN
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
            error_message TEXT
        );
        RAISE NOTICE 'Table jobs créée';
    END IF;

    -- Table nodes
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'nodes') THEN
        CREATE TABLE nodes (
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
        RAISE NOTICE 'Table nodes créée';
    END IF;

    -- Table metrics
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'metrics') THEN
        CREATE TABLE metrics (
            id SERIAL PRIMARY KEY,
            metric_name VARCHAR(100) NOT NULL,
            metric_value FLOAT NOT NULL,
            timestamp TIMESTAMP DEFAULT NOW()
        );
        RAISE NOTICE 'Table metrics créée';
    END IF;

    -- Table clients
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'clients') THEN
        CREATE TABLE clients (
            id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(100),
            api_key VARCHAR(255),
            created_at TIMESTAMP DEFAULT NOW()
        );
        
        -- Insérer les clients par défaut
        INSERT INTO clients (id, name, api_key) VALUES 
            ('test-client', 'Test Client', 'test-token'),
            ('dashboard', 'Dashboard Client', 'dashboard-token')
        ON CONFLICT (id) DO NOTHING;
        
        RAISE NOTICE 'Table clients créée';
    END IF;

    -- Créer les index
    CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
    CREATE INDEX IF NOT EXISTS idx_jobs_submitted_at ON jobs(submitted_at);
END $$;

SQL

exit 0

-- Ajouter les colonnes manquantes à la table jobs
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 1;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS estimated_cost DECIMAL(10, 6) DEFAULT 0.01;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS assigned_node VARCHAR(64);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS result TEXT;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS error TEXT;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS started_at TIMESTAMP;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS execution_time_ms INTEGER;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Ajouter les colonnes manquantes à la table clients
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lear_balance DECIMAL(18, 8) DEFAULT 10.0;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS total_jobs INTEGER DEFAULT 0;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Ajouter les colonnes manquantes à la table nodes
ALTER TABLE nodes ADD COLUMN IF NOT EXISTS node_type VARCHAR(50) DEFAULT 'docker';
ALTER TABLE nodes ADD COLUMN IF NOT EXISTS endpoint VARCHAR(255);
ALTER TABLE nodes ADD COLUMN IF NOT EXISTS capabilities TEXT DEFAULT '{}';
ALTER TABLE nodes ADD COLUMN IF NOT EXISTS cpu_cores INTEGER DEFAULT 4;
ALTER TABLE nodes ADD COLUMN IF NOT EXISTS memory_gb DECIMAL(8, 2) DEFAULT 16.0;
ALTER TABLE nodes ADD COLUMN IF NOT EXISTS max_concurrent INTEGER DEFAULT 1;
ALTER TABLE nodes ADD COLUMN IF NOT EXISTS current_load INTEGER DEFAULT 0;

-- Créer la vue sans COALESCE
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

-- Créer les index manquants
CREATE INDEX IF NOT EXISTS idx_jobs_priority ON jobs(priority);
CREATE INDEX IF NOT EXISTS idx_jobs_assigned_node ON jobs(assigned_node);
CREATE INDEX IF NOT EXISTS idx_nodes_node_type ON nodes(node_type);

-- Afficher le résultat
SELECT 'Jobs columns:' as info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'jobs' 
ORDER BY ordinal_position;

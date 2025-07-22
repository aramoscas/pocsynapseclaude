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

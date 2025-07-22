-- Requêtes SQL corrigées pour SynapseGrid

-- 1. Récupérer les jobs en attente (sans COALESCE problématique)
-- Ancienne requête problématique:
-- SELECT COALESCE(job_id, id) as job_id, ... WHERE status = 'pending'

-- Nouvelle requête corrigée:
SELECT 
    job_id,
    client_id,
    model_name,
    input_data,
    COALESCE(priority, 1) as priority,  -- OK car même type
    created_at
FROM jobs
WHERE status = 'queued'  -- Pas 'pending'
AND created_at < NOW() - INTERVAL '5 minutes'
ORDER BY priority DESC, created_at ASC
LIMIT 10;

-- 2. Insérer un job (colonnes compatibles seulement)
INSERT INTO jobs (
    job_id, 
    client_id, 
    model_name, 
    input_data, 
    status, 
    priority,
    created_at
) VALUES (
    $1, $2, $3, $4, 'queued', $5, CURRENT_TIMESTAMP
);

-- 3. Mettre à jour le statut d'un job
UPDATE jobs 
SET 
    status = $1,
    started_at = CASE WHEN $1 = 'running' THEN CURRENT_TIMESTAMP ELSE started_at END,
    completed_at = CASE WHEN $1 IN ('completed', 'failed') THEN CURRENT_TIMESTAMP ELSE completed_at END
WHERE job_id = $2;

-- 4. Récupérer les infos d'un job (colonnes sûres)
SELECT 
    job_id,
    client_id,
    model_name,
    status,
    created_at,
    completed_at
FROM jobs 
WHERE job_id = $1;

-- Requêtes correctes pour remplacer les problématiques

-- Récupérer les jobs en attente (sans COALESCE)
PREPARE get_pending_jobs AS
SELECT 
    job_id,
    client_id,
    model_name,
    input_data,
    priority
FROM jobs
WHERE status = 'queued'
AND created_at < NOW() - INTERVAL '5 minutes'
ORDER BY priority DESC, created_at ASC
LIMIT 10;

-- Récupérer un job spécifique
PREPARE get_job_by_id AS
SELECT 
    job_id,
    client_id,
    status,
    model_name,
    created_at
FROM jobs
WHERE job_id = $1;

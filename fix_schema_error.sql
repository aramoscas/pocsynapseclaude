-- Correction du schéma pour éviter l'erreur COALESCE

-- 1. S'assurer que la colonne submitted_at existe (alias de created_at)
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMP;

-- 2. Mettre à jour submitted_at avec les valeurs de created_at si elle est vide
UPDATE jobs 
SET submitted_at = created_at 
WHERE submitted_at IS NULL;

-- 3. Créer une vue qui évite le problème COALESCE
CREATE OR REPLACE VIEW v_pending_jobs AS
SELECT 
    job_id,  -- Utiliser seulement job_id, pas id
    client_id,
    model_name,
    input_data::text,
    COALESCE(priority, 1) as priority,
    created_at,
    submitted_at
FROM jobs
WHERE status = 'queued'  -- Utiliser 'queued' au lieu de 'pending'
AND created_at < NOW() - INTERVAL '5 minutes';

-- 4. Vérifier les statuts valides dans la table
SELECT DISTINCT status, COUNT(*) 
FROM jobs 
GROUP BY status;

-- 5. Afficher la structure de la table jobs
\d jobs

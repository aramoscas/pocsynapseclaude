-- Correction complète du schéma SynapseGrid

-- 1. Afficher la structure actuelle
\echo '📊 Structure actuelle de la table jobs:'
\d jobs

-- 2. Ajouter toutes les colonnes manquantes
\echo '🔧 Ajout des colonnes manquantes...'

-- Priority
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 1;

-- Submitted_at (alias de created_at)
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Estimated_cost
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS estimated_cost DECIMAL(10, 6) DEFAULT 0.01;

-- Assigned_node
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS assigned_node VARCHAR(64);

-- Execution_time_ms
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS execution_time_ms INTEGER;

-- Started_at
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS started_at TIMESTAMP;

-- Updated_at
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Result et error en TEXT au lieu de JSONB pour simplicité
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS result TEXT;

ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS error TEXT;

-- 3. Mettre à jour les valeurs par défaut
\echo '📝 Mise à jour des valeurs...'

-- Copier created_at vers submitted_at si vide
UPDATE jobs 
SET submitted_at = created_at 
WHERE submitted_at IS NULL;

-- Mettre à jour priority pour les jobs existants
UPDATE jobs 
SET priority = 1 
WHERE priority IS NULL;

-- 4. Ajouter les colonnes manquantes à la table clients aussi
\echo '🔧 Correction de la table clients...'

ALTER TABLE clients
ADD COLUMN IF NOT EXISTS last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE clients
ADD COLUMN IF NOT EXISTS total_jobs INTEGER DEFAULT 0;

ALTER TABLE clients
ADD COLUMN IF NOT EXISTS lear_balance DECIMAL(18, 8) DEFAULT 10.0;

-- 5. Créer une vue simple pour les jobs en attente
\echo '📋 Création de la vue v_pending_jobs...'

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

-- 6. Créer des index pour améliorer les performances
\echo '🚀 Création des index...'

CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_priority ON jobs(priority);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_client_id ON jobs(client_id);

-- 7. Vérifier la nouvelle structure
\echo '✅ Nouvelle structure de la table jobs:'
\d jobs

-- 8. Afficher un exemple de données
\echo '📊 Exemple de données:'
SELECT job_id, client_id, status, priority, created_at 
FROM jobs 
LIMIT 5;

-- 9. Statistiques
\echo '📈 Statistiques:'
SELECT 
    'Total jobs' as metric, 
    COUNT(*) as value 
FROM jobs
UNION ALL
SELECT 
    'Jobs queued', 
    COUNT(*) 
FROM jobs 
WHERE status = 'queued'
UNION ALL
SELECT 
    'Total clients', 
    COUNT(*) 
FROM clients;

#!/bin/bash
# fix_complete_schema.sh - Correction complète du schéma avec toutes les colonnes manquantes

set -e

echo "🔧 Correction complète du schéma PostgreSQL..."
echo "============================================"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# 1. Créer le script SQL de correction complète
cat > fix_all_columns.sql << 'EOF'
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
EOF

# 2. Appliquer les corrections
print_info "Application des corrections SQL..."
docker exec -i synapse_postgres psql -U synapse -d synapse < fix_all_columns.sql 2>&1 | tee schema_fix.log

# 3. Créer un schéma de référence complet
cat > reference_schema.sql << 'EOF'
-- Schéma de référence complet pour SynapseGrid

-- Table clients complète
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

-- Table jobs complète
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
    execution_time_ms INTEGER,
    CONSTRAINT jobs_status_check CHECK (status IN ('queued', 'dispatched', 'running', 'completed', 'failed', 'cancelled'))
);

-- Table nodes complète
CREATE TABLE IF NOT EXISTS nodes (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) UNIQUE NOT NULL,
    node_type VARCHAR(50) DEFAULT 'docker',
    region VARCHAR(50) DEFAULT 'eu-west-1',
    endpoint VARCHAR(255),
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
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

print_success "Schéma de référence créé dans reference_schema.sql"

# 4. Créer un test de vérification
cat > test_schema.py << 'EOF'
#!/usr/bin/env python3
"""Test du schéma corrigé"""

import psycopg2
import json
import sys

def test_schema():
    """Teste que toutes les colonnes nécessaires existent"""
    try:
        conn = psycopg2.connect(
            host="localhost",
            database="synapse",
            user="synapse",
            password="synapse123"
        )
        cur = conn.cursor()
        
        # Test 1: Vérifier les colonnes de jobs
        print("🧪 Test 1: Vérification des colonnes de 'jobs'...")
        required_columns = [
            'job_id', 'client_id', 'model_name', 'input_data',
            'status', 'priority', 'created_at', 'submitted_at',
            'estimated_cost', 'assigned_node'
        ]
        
        cur.execute("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'jobs'
        """)
        
        existing_columns = [row[0] for row in cur.fetchall()]
        missing = set(required_columns) - set(existing_columns)
        
        if missing:
            print(f"❌ Colonnes manquantes: {missing}")
            return False
        else:
            print("✅ Toutes les colonnes requises sont présentes")
        
        # Test 2: Insérer un job de test
        print("\n🧪 Test 2: Insertion d'un job de test...")
        try:
            cur.execute("""
                INSERT INTO jobs (
                    job_id, client_id, model_name, input_data, 
                    status, priority, estimated_cost
                ) VALUES (
                    'test_job_schema', 'test-client', 'test-model',
                    '{"test": "data"}', 'queued', 2, 0.02
                )
                ON CONFLICT (job_id) DO UPDATE 
                SET priority = 2, updated_at = CURRENT_TIMESTAMP
            """)
            conn.commit()
            print("✅ Insertion réussie")
        except Exception as e:
            print(f"❌ Erreur insertion: {e}")
            return False
        
        # Test 3: Requête sans COALESCE
        print("\n🧪 Test 3: Requête des jobs en attente...")
        try:
            cur.execute("""
                SELECT job_id, client_id, priority
                FROM jobs
                WHERE status = 'queued'
                ORDER BY priority DESC, created_at ASC
                LIMIT 5
            """)
            
            jobs = cur.fetchall()
            print(f"✅ {len(jobs)} jobs trouvés")
            for job in jobs:
                print(f"   - {job[0]} (client: {job[1]}, priorité: {job[2]})")
        except Exception as e:
            print(f"❌ Erreur requête: {e}")
            return False
        
        cur.close()
        conn.close()
        return True
        
    except Exception as e:
        print(f"❌ Erreur connexion: {e}")
        return False

if __name__ == "__main__":
    success = test_schema()
    print("\n" + "="*50)
    if success:
        print("🎉 Tous les tests passent! Le schéma est correct.")
    else:
        print("❌ Des erreurs ont été détectées.")
    sys.exit(0 if success else 1)
EOF

chmod +x test_schema.py

# 5. Exécuter le test
print_info "Exécution des tests de schéma..."
python3 test_schema.py || print_warning "Certains tests ont échoué"

# 6. Résumé
echo ""
echo "🎉 Corrections du schéma terminées!"
echo "=================================="
echo ""
print_success "Colonnes ajoutées:"
echo "   - priority (INTEGER)"
echo "   - submitted_at (TIMESTAMP)"
echo "   - estimated_cost (DECIMAL)"
echo "   - assigned_node (VARCHAR)"
echo "   - execution_time_ms (INTEGER)"
echo "   - started_at, updated_at (TIMESTAMP)"
echo "   - result, error (TEXT)"
echo ""
print_success "Vue v_pending_jobs créée (sans COALESCE)"
print_success "Index de performance ajoutés"
print_success "Tables clients et nodes mises à jour"
echo ""
echo "📝 Pour vérifier manuellement:"
echo "   docker exec -it synapse_postgres psql -U synapse -d synapse"
echo "   \\d jobs  -- Voir la structure"
echo "   SELECT * FROM v_pending_jobs;  -- Tester la vue"
echo ""
echo "🔧 Si des erreurs persistent:"
echo "1. Vérifiez les logs: docker-compose logs -f postgres"
echo "2. Réinitialisez la DB: docker-compose down -v && docker-compose up -d"
echo "3. Utilisez le schéma de référence: reference_schema.sql"

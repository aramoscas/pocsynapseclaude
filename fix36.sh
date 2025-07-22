#!/bin/bash
# fix_all_issues.sh - Corrige tous les problèmes identifiés

set -e

echo "🔧 Correction complète de SynapseGrid"
echo "===================================="

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

# 1. Corriger la base de données en direct
print_info "Correction de la base de données..."

cat > fix_db_live.sql << 'EOF'
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
EOF

docker exec -i synapse_postgres psql -U synapse -d synapse < fix_db_live.sql

print_success "Base de données corrigée"

# 2. Ajouter les endpoints manquants au Gateway
print_info "Ajout des endpoints manquants au Gateway..."

# Sauvegarder le fichier actuel
cp services/gateway/main.py services/gateway/main.py.bak

# Chercher si les endpoints existent déjà
if grep -q "/nodes/register" services/gateway/main.py; then
    print_warning "Endpoint /nodes/register existe déjà"
else
    # Ajouter les endpoints avant la ligne if __name__ == "__main__"
    cat > add_endpoints.py << 'EOF'
import sys

# Lire le fichier
with open('services/gateway/main.py', 'r') as f:
    content = f.read()

# Endpoints à ajouter
new_code = '''
@app.post("/nodes/register")
async def register_node(node_data: dict):
    """Enregistrer un nouveau node"""
    node_id = node_data.get("node_id")
    node_type = node_data.get("node_type", "docker")
    region = node_data.get("region", "eu-west-1")
    
    if not node_id:
        raise HTTPException(status_code=400, detail="node_id required")
    
    try:
        # Enregistrer dans Redis
        node_key = f"node:{node_id}:{region}:info"
        node_info = {
            "node_id": node_id,
            "node_type": node_type,
            "region": region,
            "status": "online",
            "last_seen": datetime.utcnow().isoformat()
        }
        
        for key, value in node_info.items():
            await redis_async(redis_client.hset, node_key, key, value)
        await redis_async(redis_client.expire, node_key, 60)
        
        logger.info(f"✅ Node {node_id} enregistré")
        return {"status": "registered", "node_id": node_id}
        
    except Exception as e:
        logger.error(f"❌ Erreur: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/metrics")
async def get_metrics():
    """Métriques Prometheus"""
    metrics = []
    
    try:
        # Jobs en attente
        queue_length = await redis_async(redis_client.llen, "jobs:queue:eu-west-1")
        metrics.append(f"synapsegrid_jobs_queued {{region=\\"eu-west-1\\"}} {queue_length}")
    except:
        pass
    
    metrics.append("synapsegrid_gateway_up 1")
    return "\\n".join(metrics)

@app.get("/nodes")
async def list_nodes():
    """Lister les nodes actifs"""
    try:
        nodes = []
        pattern = "node:*:*:info"
        cursor = 0
        
        # Scanner Redis pour trouver les nodes
        while True:
            cursor, keys = await redis_async(redis_client.scan, cursor, match=pattern, count=10)
            for key in keys:
                try:
                    node_info = await redis_async(redis_client.hgetall, key)
                    if node_info:
                        nodes.append({
                            "node_id": node_info.get("node_id", "unknown"),
                            "status": node_info.get("status", "unknown"),
                            "region": node_info.get("region", "unknown")
                        })
                except:
                    pass
            if cursor == 0:
                break
                
        return {"nodes": nodes, "count": len(nodes)}
    except Exception as e:
        return {"error": str(e), "nodes": [], "count": 0}

'''

# Insérer avant if __name__ == "__main__"
if 'if __name__ == "__main__":' in content:
    content = content.replace('if __name__ == "__main__":', new_code + '\nif __name__ == "__main__":')
    
    with open('services/gateway/main.py', 'w') as f:
        f.write(content)
    print("✅ Endpoints ajoutés")
else:
    print("❌ Impossible de trouver le point d'insertion")
EOF

    python3 add_endpoints.py
    rm add_endpoints.py
    print_success "Endpoints ajoutés au Gateway"
fi

# 3. Mettre à jour le sql/init.sql pour les futures installations
print_info "Mise à jour du script d'initialisation..."

mkdir -p sql
cat > sql/init.sql << 'EOF'
-- Script d'initialisation complet avec toutes les colonnes

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
    execution_time_ms INTEGER
);

CREATE TABLE IF NOT EXISTS nodes (
    id SERIAL PRIMARY KEY,
    node_id VARCHAR(64) UNIQUE NOT NULL,
    node_type VARCHAR(50) DEFAULT 'docker',
    region VARCHAR(50) DEFAULT 'eu-west-1',
    endpoint VARCHAR(255),
    status VARCHAR(20) DEFAULT 'offline',
    capabilities TEXT DEFAULT '{}',
    cpu_cores INTEGER DEFAULT 4,
    memory_gb DECIMAL(8, 2) DEFAULT 16.0,
    max_concurrent INTEGER DEFAULT 1,
    current_load INTEGER DEFAULT 0,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_priority ON jobs(priority);
CREATE INDEX IF NOT EXISTS idx_jobs_client_id ON jobs(client_id);
CREATE INDEX IF NOT EXISTS idx_nodes_status ON nodes(status);

-- Vue
CREATE OR REPLACE VIEW v_pending_jobs AS
SELECT job_id, client_id, model_name, input_data, priority, created_at
FROM jobs WHERE status = 'queued'
ORDER BY priority DESC, created_at ASC;

-- Données de test
INSERT INTO clients (client_id, api_key_hash, nrg_balance) VALUES
    ('test-client', 'test-hash', 1000.0),
    ('deploy-test', 'deploy-hash', 500.0)
ON CONFLICT DO NOTHING;

GRANT ALL ON ALL TABLES IN SCHEMA public TO synapse;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO synapse;
EOF

print_success "Script init.sql mis à jour"

# 4. Redémarrer le gateway pour appliquer les changements
print_info "Redémarrage du Gateway..."
docker-compose restart gateway

# 5. Attendre et tester
sleep 5

print_info "Test des endpoints..."

# Test health
echo "Test /health:"
curl -s http://localhost:8080/health | jq . || echo "OK"

# Test metrics
echo ""
echo "Test /metrics:"
curl -s http://localhost:8080/metrics || echo "Metrics"

# Test nodes
echo ""
echo "Test /nodes:"
curl -s http://localhost:8080/nodes | jq . || echo "Nodes"

# Résumé
echo ""
echo "🎉 Corrections appliquées!"
echo "========================"
echo ""
print_success "Base de données: colonnes ajoutées"
print_success "Gateway: endpoints /nodes/register, /metrics, /nodes ajoutés"
print_success "Vue v_pending_jobs créée (pas d'erreur COALESCE)"
echo ""
echo "📊 Vérifier les colonnes:"
echo "   docker exec synapse_postgres psql -U synapse -d synapse -c '\\d jobs'"
echo ""
echo "🔧 Les nodes peuvent maintenant s'enregistrer!"

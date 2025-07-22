#!/bin/bash
# fix_synapsegrid_issues.sh - Diagnostic et correction des problèmes SynapseGrid

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          🔧 SynapseGrid Diagnostic & Repair Tool 🔧          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Vérifier l'état des services
echo -e "${YELLOW}📊 1. Vérification de l'état des services...${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep synapse
echo ""

# 2. Vérifier la structure de la base de données
echo -e "${YELLOW}🗄️  2. Vérification de la structure PostgreSQL...${NC}"
echo "Tables existantes:"
docker exec synapse_postgres psql -U synapse -d synapse -c "\dt"
echo ""

echo "Structure de la table 'jobs':"
docker exec synapse_postgres psql -U synapse -d synapse -c "\d jobs"
echo ""

# 3. Corriger la structure de la table jobs
echo -e "${YELLOW}🔨 3. Correction de la structure de la table jobs...${NC}"

# Créer un fichier SQL de correction
cat > /tmp/fix_jobs_table.sql << 'EOF'
-- Vérifier si la colonne job_id existe, sinon l'ajouter
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name='jobs' AND column_name='job_id') THEN
        -- Si la table a une colonne 'id' mais pas 'job_id'
        IF EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name='jobs' AND column_name='id') THEN
            -- Ajouter la colonne job_id
            ALTER TABLE jobs ADD COLUMN job_id VARCHAR(64) UNIQUE;
            -- Mettre à jour les enregistrements existants
            UPDATE jobs SET job_id = 'job_' || id WHERE job_id IS NULL;
            -- Rendre la colonne NOT NULL
            ALTER TABLE jobs ALTER COLUMN job_id SET NOT NULL;
        ELSE
            -- Recréer la table avec la bonne structure
            DROP TABLE IF EXISTS jobs CASCADE;
            CREATE TABLE jobs (
                id SERIAL PRIMARY KEY,
                job_id VARCHAR(64) UNIQUE NOT NULL,
                client_id VARCHAR(64) NOT NULL,
                model_name VARCHAR(100) NOT NULL,
                input_data JSONB NOT NULL,
                status VARCHAR(20) DEFAULT 'pending',
                priority INTEGER DEFAULT 1,
                estimated_cost DECIMAL(10, 6) DEFAULT 0.1,
                actual_cost DECIMAL(10, 6),
                assigned_node VARCHAR(64),
                result JSONB,
                error TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                started_at TIMESTAMP,
                completed_at TIMESTAMP
            );
        END IF;
    END IF;
END $$;

-- Créer les index nécessaires
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_client_id ON jobs(client_id);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at);
EOF

# Exécuter la correction
docker cp /tmp/fix_jobs_table.sql synapse_postgres:/tmp/
docker exec synapse_postgres psql -U synapse -d synapse -f /tmp/fix_jobs_table.sql
echo -e "${GREEN}✅ Structure de la table corrigée${NC}"
echo ""

# 4. Vérifier Redis
echo -e "${YELLOW}💾 4. Vérification de Redis...${NC}"
echo "Clés dans Redis:"
docker exec synapse_redis redis-cli KEYS "*"
echo ""

echo "Jobs dans la queue:"
docker exec synapse_redis redis-cli LLEN jobs:queue:eu-west-1
echo ""

echo "Nodes enregistrés:"
docker exec synapse_redis redis-cli SMEMBERS nodes:registered
echo ""

# 5. Vérifier la connexion entre services
echo -e "${YELLOW}🔗 5. Test de connectivité entre services...${NC}"

# Test Gateway -> Redis
echo -n "Gateway -> Redis: "
docker exec synapse_gateway redis-cli -h redis PING && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ FAILED${NC}"

# Test Dispatcher -> Redis
echo -n "Dispatcher -> Redis: "
docker exec synapse_dispatcher redis-cli -h redis PING && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ FAILED${NC}"

# Test Node -> Redis
echo -n "Node -> Redis: "
docker exec synapse_node redis-cli -h redis PING && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ FAILED${NC}"
echo ""

# 6. Vérifier les logs pour les erreurs
echo -e "${YELLOW}📜 6. Analyse des erreurs dans les logs...${NC}"
echo "Erreurs récentes du Gateway:"
docker logs synapse_gateway 2>&1 | grep -i error | tail -5
echo ""

echo "Erreurs récentes du Dispatcher:"
docker logs synapse_dispatcher 2>&1 | grep -i error | tail -5
echo ""

# 7. Tester le flow complet
echo -e "${YELLOW}🧪 7. Test du flow complet...${NC}"

# Soumettre un job de test
echo "Soumission d'un job de test..."
JOB_RESPONSE=$(curl -s -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -H "X-Client-ID: debug-test" \
  -d '{"model_name": "debug-model", "input_data": {"test": true, "timestamp": "'$(date +%s)'"}}')

echo "Réponse: $JOB_RESPONSE"
JOB_ID=$(echo $JOB_RESPONSE | jq -r '.job_id')
echo "Job ID: $JOB_ID"
echo ""

# Attendre un peu
sleep 3

# Vérifier le job dans la base
echo "Job dans PostgreSQL:"
docker exec synapse_postgres psql -U synapse -d synapse -c "SELECT job_id, status, assigned_node FROM jobs WHERE job_id = '$JOB_ID'"
echo ""

# Vérifier le job dans Redis
echo "Job dans Redis queue:"
docker exec synapse_redis redis-cli LRANGE jobs:queue:eu-west-1 0 -1 | grep $JOB_ID
echo ""

# 8. Redémarrer les services si nécessaire
echo -e "${YELLOW}🔄 8. Recommandations...${NC}"

if [ "$1" == "--fix" ]; then
    echo -e "${YELLOW}Application des corrections...${NC}"
    
    # Redémarrer le dispatcher
    echo "Redémarrage du dispatcher..."
    docker restart synapse_dispatcher
    
    # Redémarrer les nodes
    echo "Redémarrage des nodes..."
    docker restart synapse_node
    
    sleep 5
    echo -e "${GREEN}✅ Services redémarrés${NC}"
else
    echo -e "${BLUE}Pour appliquer les corrections automatiquement, lancez:${NC}"
    echo -e "${WHITE}./fix_synapsegrid_issues.sh --fix${NC}"
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    📋 Résumé du diagnostic                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

# Vérifier si tout fonctionne
POSTGRES_OK=$(docker exec synapse_postgres pg_isready -U synapse >/dev/null 2>&1 && echo "YES" || echo "NO")
REDIS_OK=$(docker exec synapse_redis redis-cli PING >/dev/null 2>&1 && echo "YES" || echo "NO")
GATEWAY_OK=$(curl -s http://localhost:8080/health >/dev/null 2>&1 && echo "YES" || echo "NO")

echo -e "PostgreSQL: $([ "$POSTGRES_OK" == "YES" ] && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ FAILED${NC}")"
echo -e "Redis: $([ "$REDIS_OK" == "YES" ] && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ FAILED${NC}")"
echo -e "Gateway: $([ "$GATEWAY_OK" == "YES" ] && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ FAILED${NC}")"

# Script pour surveiller l'activité en temps réel
cat > /tmp/monitor_synapsegrid.sh << 'EOF'
#!/bin/bash
# Monitoring en temps réel

watch -n 2 '
echo "=== JOBS IN QUEUE ==="
docker exec synapse_redis redis-cli LLEN jobs:queue:eu-west-1
echo ""
echo "=== REGISTERED NODES ==="
docker exec synapse_redis redis-cli SMEMBERS nodes:registered
echo ""
echo "=== RECENT JOBS ==="
docker exec synapse_postgres psql -U synapse -d synapse -c "SELECT job_id, status, assigned_node, created_at FROM jobs ORDER BY created_at DESC LIMIT 5"
echo ""
echo "=== NODE ACTIVITY ==="
docker logs synapse_node --tail 10 2>&1 | grep -E "Processing|Executing|Completed"
'
EOF

chmod +x /tmp/monitor_synapsegrid.sh

echo ""
echo -e "${GREEN}Pour surveiller l'activité en temps réel:${NC}"
echo -e "${WHITE}/tmp/monitor_synapsegrid.sh${NC}

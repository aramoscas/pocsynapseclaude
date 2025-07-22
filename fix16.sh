#!/bin/bash
# fix_part1.sh - Correction de la base de données et Redis

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== SYNAPSEGRID FIX - PARTIE 1 ===${NC}"
echo ""

# 1. Corriger PostgreSQL
echo -e "${YELLOW}1. Correction de la table jobs...${NC}"

docker exec synapse_postgres psql -U synapse -d synapse << 'EOF'
-- Ajouter les colonnes manquantes si elles n'existent pas
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS assigned_node VARCHAR(64);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS estimated_cost DECIMAL(10,6) DEFAULT 0.01;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Créer les index manquants
CREATE INDEX IF NOT EXISTS idx_jobs_assigned_node ON jobs(assigned_node);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at);

-- Afficher la structure
\d jobs
EOF

echo -e "${GREEN}✅ Table jobs corrigée${NC}"
echo ""

# 2. Enregistrer un node dans Redis
echo -e "${YELLOW}2. Enregistrement d'un node...${NC}"

# Créer un node ID
NODE_ID="node_$(date +%s)"

# Enregistrer le node
docker exec synapse_redis redis-cli SADD nodes:registered "$NODE_ID"
docker exec synapse_redis redis-cli SET "node:${NODE_ID}:info" '{"node_id":"'$NODE_ID'","status":"available","current_load":0,"capacity":1.0}'
docker exec synapse_redis redis-cli SET "node:${NODE_ID}:status" "available"

echo -e "${GREEN}✅ Node $NODE_ID enregistré${NC}"

# Vérifier
echo ""
echo "Nodes enregistrés:"
docker exec synapse_redis redis-cli SMEMBERS nodes:registered

echo ""
echo -e "${GREEN}Partie 1 terminée! Lancez maintenant fix_part2.sh${NC}"


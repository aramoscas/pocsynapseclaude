#!/bin/bash
# fix_part2.sh - Correction de la queue et du dispatcher

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== SYNAPSEGRID FIX - PARTIE 2 ===${NC}"
echo ""

# 1. Prendre les jobs pending et les mettre dans la queue
echo -e "${YELLOW}1. Ajout des jobs pending dans la queue Redis...${NC}"

# Récupérer les jobs pending
PENDING_JOBS=$(docker exec synapse_postgres psql -U synapse -d synapse -t -A -c "
SELECT json_build_object(
    'job_id', job_id,
    'client_id', client_id,
    'model_name', model_name,
    'input_data', input_data,
    'priority', priority
)::text
FROM jobs 
WHERE status = 'pending' 
ORDER BY created_at DESC 
LIMIT 10
")

# Ajouter chaque job à la queue
echo "$PENDING_JOBS" | while IFS= read -r job_json; do
    if [ ! -z "$job_json" ]; then
        echo "$job_json" | docker exec -i synapse_redis redis-cli -x LPUSH "jobs:queue:eu-west-1" > /dev/null
        echo "Job ajouté à la queue"
    fi
done

# Vérifier la queue
QUEUE_SIZE=$(docker exec synapse_redis redis-cli LLEN "jobs:queue:eu-west-1")
echo -e "${GREEN}✅ $QUEUE_SIZE jobs dans la queue${NC}"
echo ""

# 2. Redémarrer le dispatcher
echo -e "${YELLOW}2. Redémarrage du dispatcher...${NC}"
docker restart synapse_dispatcher
sleep 3
echo -e "${GREEN}✅ Dispatcher redémarré${NC}"
echo ""

# 3. Test avec un nouveau job
echo -e "${YELLOW}3. Test avec un nouveau job...${NC}"

# Soumettre un job
JOB_RESPONSE=$(curl -s -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -H "X-Client-ID: test-fix" \
  -d '{"model_name": "test-model", "input_data": {"test": "final"}}')

echo "Job soumis: $JOB_RESPONSE"
JOB_ID=$(echo $JOB_RESPONSE | jq -r '.job_id')

# Attendre un peu
sleep 2

# Vérifier l'état
echo ""
echo -e "${BLUE}État du système:${NC}"
echo "================"

echo "Queue Redis:"
docker exec synapse_redis redis-cli LLEN "jobs:queue:eu-west-1"

echo ""
echo "Job dans PostgreSQL:"
docker exec synapse_postgres psql -U synapse -d synapse -c "SELECT job_id, status, assigned_node FROM jobs WHERE job_id = '$JOB_ID'"

echo ""
echo "Logs du dispatcher (dernières lignes):"
docker logs synapse_dispatcher --tail 10

echo ""
echo -e "${GREEN}✅ Correction terminée!${NC}"
echo ""
echo "Pour surveiller en temps réel:"
echo "docker logs -f synapse_dispatcher"

#!/bin/bash
# Monitoring temps réel

watch -n 2 '
echo "🚀 SYNAPSEGRID CLEAN MONITORING"
echo "=============================="
echo ""
echo "📊 SERVICES STATUS:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep synapse
echo ""
echo "💾 REDIS QUEUE:"
docker exec synapse_redis redis-cli LLEN "jobs:queue:eu-west-1" | xargs echo "Jobs waiting:"
echo ""
echo "🖥️  NODES:"
docker exec synapse_redis redis-cli SMEMBERS "nodes:registered"
echo ""
echo "📋 RECENT JOBS:"
docker exec synapse_postgres psql -U synapse -d synapse -t -c "
SELECT COALESCE(job_id, id) || \": \" || status || \" (\" || COALESCE(assigned_node, node_id, \"unassigned\") || \")\"
FROM jobs 
ORDER BY COALESCE(created_at, submitted_at) DESC 
LIMIT 5
" 2>/dev/null
echo ""
echo "🔄 LOGS (last 5 lines):"
docker logs synapse_dispatcher --tail 5 2>&1 | grep -v "Checking for stuck"
'

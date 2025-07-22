#!/bin/bash
# Monitoring en temps réel

watch -n 2 '
echo "🚀 SYNAPSEGRID MONITORING"
echo "========================"
echo ""
echo "📊 HEALTH STATUS:"
curl -s http://localhost:8080/health 2>/dev/null | jq -c . || echo "Gateway offline"
echo ""
echo "💾 REDIS:"
echo -n "Queue length: "
docker exec synapse_redis redis-cli LLEN "jobs:queue:eu-west-1" 2>/dev/null || echo "0"
echo -n "Nodes: "
docker exec synapse_redis redis-cli SMEMBERS "nodes:registered" 2>/dev/null || echo "None"
echo ""
echo "📋 RECENT JOBS:"
docker exec synapse_postgres psql -U synapse -d synapse -t -c "
SELECT COALESCE(job_id, id) || \": \" || status || \" (\" || COALESCE(assigned_node, node_id, \"unassigned\") || \")\"
FROM jobs 
ORDER BY COALESCE(created_at, submitted_at) DESC 
LIMIT 5
" 2>/dev/null || echo "No jobs"
echo ""
echo "📈 METRICS:"
curl -s http://localhost:8080/metrics 2>/dev/null | jq -c . || echo "No metrics"
'

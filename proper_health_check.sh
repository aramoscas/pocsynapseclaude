#!/bin/bash
# proper_health_check.sh - Health check adapté pour SynapseGrid

echo "🏥 Health Check SynapseGrid"
echo "=========================="

# Gateway (API HTTP)
echo -n "Gateway API:     "
if curl -s http://localhost:8080/health >/dev/null 2>&1; then
    echo "✅ OK (HTTP)"
else
    echo "❌ DOWN"
fi

# Services backend (vérifier via Docker)
for service in dispatcher aggregator node1 node2; do
    printf "%-15s: " "$service"
    if docker ps | grep -q "synapse[_-]$service"; then
        echo "✅ Running (Docker)"
    else
        echo "❌ Not running"
    fi
done

# Dashboard
echo -n "Dashboard:       "
if curl -s http://localhost:3000 >/dev/null 2>&1; then
    echo "✅ OK (HTTP)"
else
    echo "❌ DOWN"
fi

# Redis
echo -n "Redis:           "
if docker exec synapse_redis redis-cli ping >/dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ DOWN"
fi

# PostgreSQL
echo -n "PostgreSQL:      "
if docker exec synapse_postgres pg_isready >/dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ DOWN"
fi

# Activité du système
echo ""
echo "📊 Activité du système:"
echo -n "Jobs en queue: "
docker exec synapse_redis redis-cli llen "jobs:queue:eu-west-1" 2>/dev/null || echo "0"
echo -n "Nodes actifs:  "
docker exec synapse_redis redis-cli keys "node:*:*:info" 2>/dev/null | wc -l || echo "0"

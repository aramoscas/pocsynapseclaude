#!/bin/bash

echo "🚀 Testing SynapseGrid API"

# Wait for services
echo "Waiting for services to start..."
sleep 5

# Test health endpoint
echo "Testing health endpoint..."
health_response=$(curl -s -w "%{http_code}" -o /tmp/health.json "http://localhost:8080/health" 2>/dev/null)

if [ "${health_response: -3}" = "200" ]; then
    echo "✅ Health check passed"
    cat /tmp/health.json 2>/dev/null | python3 -m json.tool 2>/dev/null || cat /tmp/health.json
else
    echo "❌ Health check failed (HTTP $health_response)"
    echo "Gateway may not be running on port 8080"
    exit 1
fi

echo ""

# Test job submission
echo "Testing job submission..."
job_response=$(curl -s -w "%{http_code}" \
    -X POST "http://localhost:8080/submit" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "resnet50", "input_data": {"test": "data"}, "priority": 5}' \
    -o /tmp/job.json 2>/dev/null)

if [ "${job_response: -3}" = "200" ]; then
    echo "✅ Job submission passed"
    cat /tmp/job.json 2>/dev/null | python3 -m json.tool 2>/dev/null || cat /tmp/job.json
else
    echo "❌ Job submission failed (HTTP $job_response)"
fi

echo ""

# Test stats
echo "Testing stats endpoint..."
stats_response=$(curl -s -w "%{http_code}" "http://localhost:8080/stats" -o /tmp/stats.json 2>/dev/null)

if [ "${stats_response: -3}" = "200" ]; then
    echo "✅ Stats endpoint passed"
    cat /tmp/stats.json 2>/dev/null | python3 -m json.tool 2>/dev/null || cat /tmp/stats.json
else
    echo "❌ Stats endpoint failed (HTTP $stats_response)"
fi

echo ""
echo "🎉 API tests completed!"

# Cleanup
rm -f /tmp/health.json /tmp/job.json /tmp/stats.json

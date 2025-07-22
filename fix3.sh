#!/bin/bash

echo "🔧 Correction finale du bug PostgreSQL datetime..."

# Arrêter le gateway
docker-compose stop gateway

echo "📝 Le problème exact identifié :"
echo "Dans submit_job, ligne INSERT PostgreSQL :"
echo "datetime.utcnow() passé directement au lieu d'être formaté"

# Chercher la ligne problématique
echo "🔍 Ligne problématique :"
grep -n "datetime.utcnow(), 0.01" services/gateway/main.py

# Corriger: remplacer datetime.utcnow() par datetime.datetime.utcnow() dans l'INSERT
sed -i.bak 's/datetime\.utcnow(), 0\.01/datetime.datetime.utcnow(), 0.01/g' services/gateway/main.py

echo "✅ Vérification de la correction :"
grep -n "datetime.datetime.utcnow(), 0.01" services/gateway/main.py

# Supprimer le backup
rm -f services/gateway/main.py.bak

echo "🐳 Rebuild du Gateway..."
docker-compose build --no-cache gateway

echo "🚀 Redémarrage du Gateway..."
docker-compose up -d gateway

echo "⏳ Attente du Gateway..."
sleep 10

echo "🧪 Test de soumission de job..."
response=$(curl -s -w "%{http_code}" -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "resnet50", "input_data": {"test": "data"}, "priority": 5}' \
    -o /tmp/job_test.json 2>/dev/null)

echo "Réponse HTTP: $response"
if [ "$response" = "200" ]; then
    echo "✅ Job submission enfin réussi !"
    cat /tmp/job_test.json | python3 -m json.tool 2>/dev/null || cat /tmp/job_test.json
else
    echo "❌ Réponse d'erreur :"
    cat /tmp/job_test.json 2>/dev/null
    echo ""
    echo "📋 Logs récents :"
    docker-compose logs --tail=10 gateway
fi

rm -f /tmp/job_test.json

echo ""
echo "✅ Correctif final PostgreSQL appliqué !"

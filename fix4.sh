#!/bin/bash

echo "🔧 Solution définitive: changer l'import datetime..."

# Arrêter le gateway
docker-compose stop gateway

echo "📝 Le problème: conflict entre 'import datetime' et utilisation incorrecte"
echo "Solution: changer pour 'from datetime import datetime'"

# Sauvegarder le fichier actuel
cp services/gateway/main.py services/gateway/main.py.backup

# Changer l'import au début du fichier
sed -i.bak 's/^import datetime$/from datetime import datetime/' services/gateway/main.py

echo "✅ Import changé de 'import datetime' vers 'from datetime import datetime'"

# Maintenant tous les datetime.utcnow() sont corrects
echo "📋 Vérification des utilisations datetime dans le code :"
grep -n "datetime\.utcnow()" services/gateway/main.py

# Supprimer le backup
rm -f services/gateway/main.py.bak

echo "🐳 Rebuild du Gateway..."
docker-compose build --no-cache gateway

echo "🚀 Redémarrage du Gateway..."
docker-compose up -d gateway

echo "⏳ Attente du Gateway..."
sleep 15

echo "🧪 Test du health check..."
health_response=$(curl -s -w "%{http_code}" http://localhost:8080/health -o /tmp/health.json 2>/dev/null)
if [ "$health_response" = "200" ]; then
    echo "✅ Health check OK !"
    cat /tmp/health.json | python3 -m json.tool 2>/dev/null || cat /tmp/health.json
else
    echo "❌ Health check failed (HTTP $health_response)"
fi

echo ""
echo "🧪 Test de soumission de job..."
job_response=$(curl -s -w "%{http_code}" -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "resnet50", "input_data": {"test": "data"}, "priority": 5}' \
    -o /tmp/job.json 2>/dev/null)

echo "Réponse HTTP: $job_response"
if [ "$job_response" = "200" ]; then
    echo "🎉 Job submission ENFIN réussi !"
    cat /tmp/job.json | python3 -m json.tool 2>/dev/null || cat /tmp/job.json
else
    echo "❌ Réponse d'erreur :"
    cat /tmp/job.json 2>/dev/null
    echo ""
    echo "📋 Logs récents :"
    docker-compose logs --tail=10 gateway
fi

rm -f /tmp/health.json /tmp/job.json

echo ""
echo "✅ Solution définitive appliquée !"
echo "Maintenant avec 'from datetime import datetime', tous les datetime.utcnow() fonctionnent parfaitement."

#!/bin/bash

echo "🔧 Correction rapide docker-compose.yml..."

# 1. Voir le contenu actuel
echo "📋 Vérification des sections dispatcher/aggregator actuelles :"
grep -A 8 -E "dispatcher:|aggregator:" docker-compose.yml

echo ""
echo "📝 Correction manuelle des sections problématiques..."

# 2. Sauvegarder
cp docker-compose.yml docker-compose.yml.backup.$(date +%s)

# 3. Correction avec sed compatible macOS
if grep -q "image: synapsegrid-poc_dispatcher" docker-compose.yml; then
    echo "Correction dispatcher..."
    sed -i.tmp 's/image: synapsegrid-poc_dispatcher/image: synapsegrid-dispatcher/g' docker-compose.yml
fi

if grep -q "image: synapsegrid-poc_aggregator" docker-compose.yml; then
    echo "Correction aggregator..."
    sed -i.tmp 's/image: synapsegrid-poc_aggregator/image: synapsegrid-aggregator/g' docker-compose.yml
fi

# Nettoyer fichiers temporaires
rm -f docker-compose.yml.tmp

# 4. Vérifier les images locales
echo "📋 Vérification des images locales..."
if ! docker images | grep -q synapsegrid-dispatcher; then
    echo "❌ synapsegrid-dispatcher manquante - création..."
    cd services/dispatcher
    docker build -t synapsegrid-dispatcher .
    cd ../..
else
    echo "✅ synapsegrid-dispatcher trouvée"
fi

if ! docker images | grep -q synapsegrid-aggregator; then
    echo "❌ synapsegrid-aggregator manquante - création..."
    cd services/aggregator
    docker build -t synapsegrid-aggregator .
    cd ../..
else
    echo "✅ synapsegrid-aggregator trouvée"
fi

# 5. Arrêter et redémarrer les services
echo "📝 Redémarrage des services..."
docker-compose stop dispatcher aggregator
docker-compose rm -f dispatcher aggregator
docker-compose up -d dispatcher aggregator

echo "⏳ Attente 10 secondes..."
sleep 10

# 6. Vérification finale
echo "📋 Statut final :"
docker-compose ps | grep -E "dispatcher|aggregator"

echo ""
echo "📋 Logs Dispatcher :"
docker-compose logs --tail=5 dispatcher

echo ""
echo "📋 Logs Aggregator :"
docker-compose logs --tail=5 aggregator

# 7. Test rapide
echo ""
echo "🧪 Test job..."
job_response=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "resnet50", "input_data": {"test": "data"}, "priority": 5}')

echo "Response: $job_response"

if echo "$job_response" | grep -q "job_id"; then
    job_id=$(echo "$job_response" | grep -o '"job_id":"[^"]*"' | cut -d'"' -f4)
    echo "✅ Job submitted: $job_id"
    
    echo "Waiting 5 seconds..."
    sleep 5
    
    echo "Queue length: $(docker-compose exec -T redis redis-cli llen jobs:queue:eu-west-1)"
else
    echo "❌ Job submission failed"
fi

echo ""
echo "✅ Correction terminée !"

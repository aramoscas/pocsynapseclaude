#!/bin/bash

echo "🔧 Correction des chemins Dockerfile..."

# Le problème : Docker build context ne trouve pas les fichiers
# Solution : Copier les fichiers main.py directement dans le context ou ajuster les Dockerfiles

echo "📝 1. Correction des Dockerfiles avec le bon chemin..."

# Corriger le Dockerfile dispatcher
cat > services/dispatcher/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Installer les dépendances Redis
RUN pip install --no-cache-dir aioredis

# Copier SEULEMENT le main.py depuis le répertoire parent
COPY main.py .

# Lancer le worker
CMD ["python", "main.py"]
EOF

# Corriger le Dockerfile aggregator  
cat > services/aggregator/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Installer les dépendances Redis
RUN pip install --no-cache-dir aioredis

# Copier SEULEMENT le main.py depuis le répertoire parent
COPY main.py .

# Lancer le worker
CMD ["python", "main.py"]
EOF

echo "📝 2. Vérification que les fichiers main.py existent..."
ls -la services/dispatcher/main.py
ls -la services/aggregator/main.py

echo "📝 3. Build avec context spécifique pour chaque service..."

# Build dispatcher avec son propre context
echo "🐳 Building dispatcher..."
cd services/dispatcher
docker build -t synapsegrid-poc_dispatcher .
cd ../..

# Build aggregator avec son propre context  
echo "🐳 Building aggregator..."
cd services/aggregator
docker build -t synapsegrid-poc_aggregator .
cd ../..

echo "📝 4. Mise à jour du docker-compose pour utiliser les images buildées..."

# Sauvegarder docker-compose actuel
cp docker-compose.yml docker-compose.yml.backup

# Modifier les sections dispatcher et aggregator dans docker-compose
if grep -q "build:" docker-compose.yml; then
    echo "Modification du docker-compose.yml pour utiliser les images buildées..."
    
    # Remplacer la section dispatcher
    sed -i.tmp '/dispatcher:/,/^  [a-zA-Z]/{
        s|build:.*|image: synapsegrid-poc_dispatcher|
        /context:/d
        /dockerfile:/d
    }' docker-compose.yml
    
    # Remplacer la section aggregator
    sed -i.tmp '/aggregator:/,/^  [a-zA-Z]/{
        s|build:.*|image: synapsegrid-poc_aggregator|
        /context:/d
        /dockerfile:/d
    }' docker-compose.yml
    
    rm -f docker-compose.yml.tmp
fi

echo "📝 5. Redémarrage des services avec les nouvelles images..."

# Arrêter les anciens conteneurs
docker-compose stop dispatcher aggregator

# Supprimer les anciens conteneurs
docker-compose rm -f dispatcher aggregator

# Démarrer avec les nouvelles images
docker-compose up -d dispatcher aggregator

echo "⏳ Attente démarrage des workers..."
sleep 10

echo "📝 6. Test du fonctionnement..."

echo "📋 Statut des services :"
docker-compose ps | grep -E "(dispatcher|aggregator)"

echo ""
echo "📋 Logs Dispatcher (5 dernières lignes):"
docker-compose logs --tail=5 dispatcher

echo ""
echo "📋 Logs Aggregator (5 dernières lignes):"
docker-compose logs --tail=5 aggregator

echo ""
echo "🧪 Test de soumission job..."
response=$(curl -s -X POST http://localhost:8080/submit \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test-token" \
    -H "X-Client-ID: test-client" \
    -d '{"model_name": "resnet50", "input_data": {"test": "data"}, "priority": 5}')

if echo "$response" | grep -q "job_id"; then
    job_id=$(echo "$response" | grep -o '"job_id":"[^"]*"' | cut -d'"' -f4)
    echo "✅ Job soumis: $job_id"
    
    echo "⏳ Attente traitement (5 secondes)..."
    sleep 5
    
    echo "📊 Queue Redis après traitement:"
    docker-compose exec -T redis redis-cli llen jobs:queue:eu-west-1
    
    echo "📊 Vérification résultat:"
    docker-compose exec -T redis redis-cli get "result:$job_id" 2>/dev/null || echo "Pas encore de résultat"
    
else
    echo "❌ Échec soumission job"
    echo "Réponse: $response"
fi

echo ""
echo "✅ Correction des Dockerfiles terminée !"
echo ""
echo "Si les workers fonctionnent, vous devriez voir :"
echo "  - Logs dispatcher: 'Processing job...'"  
echo "  - Logs aggregator: 'Processing result...'"
echo "  - Queue Redis vide (0)"
echo "  - Résultat stocké dans Redis"

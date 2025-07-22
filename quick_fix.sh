#!/bin/bash
# quick_fix.sh - Réparation rapide des services

echo "🔧 Réparation rapide des services..."

# S'assurer que tous les fichiers requirements.txt existent
for service in dispatcher aggregator node dashboard; do
    if [ ! -f "services/$service/requirements.txt" ]; then
        echo "redis==4.6.0" > services/$service/requirements.txt
        echo "psycopg2-binary==2.9.9" >> services/$service/requirements.txt
        echo "✅ requirements.txt créé pour $service"
    fi
done

# Reconstruire les images
echo "🔨 Reconstruction des images..."
docker-compose build --no-cache dispatcher aggregator node1 node2 dashboard

# Redémarrer les services
echo "🚀 Redémarrage des services..."
docker-compose up -d

echo "✅ Réparation terminée!"

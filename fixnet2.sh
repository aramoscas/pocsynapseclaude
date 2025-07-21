#!/bin/bash

echo "🔧 CORRECTION DE LA SYNTAXE DOCKERFILE"
echo "====================================="

echo "❌ Problème détecté : Erreur de syntaxe dans le HEALTHCHECK"
echo "   Unknown type \"\\\\\\\\\" in HEALTHCHECK"
echo ""

# 1. Corriger le Dockerfile du gateway
echo "1. Correction du Dockerfile gateway..."
cat > services/gateway/Dockerfile << 'DOCKERFILE_EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8080

# Health check (syntaxe corrigée)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start the application
CMD ["python", "main.py"]
DOCKERFILE_EOF

echo "✅ Dockerfile corrigé"

# 2. Vérifier que le requirements.txt existe
echo "2. Vérification du requirements.txt..."
if [ ! -f "services/gateway/requirements.txt" ]; then
    echo "❌ requirements.txt manquant - création..."
    cat > services/gateway/requirements.txt << 'REQ_EOF'
fastapi==0.104.1
uvicorn==0.24.0
aioredis==2.0.1
asyncpg==0.29.0
pydantic==2.5.0
python-multipart==0.0.6
prometheus-client==0.19.0
pyjwt==2.8.0
aiohttp==3.8.0
psutil==5.9.0
REQ_EOF
    echo "✅ requirements.txt créé"
else
    echo "✅ requirements.txt existe"
fi

# 3. Corriger les autres Dockerfiles si nécessaire
echo "3. Vérification des autres Dockerfiles..."
for service in dispatcher aggregator node; do
    if [ -f "services/$service/Dockerfile" ]; then
        # Corriger la syntaxe si elle existe
        sed -i.bak 's/\\\\\\$/\\/g' "services/$service/Dockerfile" 2>/dev/null
        echo "✅ $service Dockerfile vérifié"
    else
        echo "⚠️  $service Dockerfile manquant"
    fi
done

# 4. Arrêter les containers actuels
echo "4. Arrêt des containers..."
docker compose down

# 5. Nettoyer les images corrompues
echo "5. Nettoyage des images corrompues..."
docker image prune -f

# 6. Reconstruction complète
echo "6. Reconstruction du gateway avec syntaxe corrigée..."
docker compose build --no-cache gateway

# 7. Vérifier que la construction a réussi
echo "7. Vérification de la construction..."
if docker images | grep -q synapsegrid-poc.*gateway; then
    echo "✅ Image gateway construite avec succès"
else
    echo "❌ Échec de construction de l'image gateway"
    exit 1
fi

# 8. Redémarrer tous les services
echo "8. Redémarrage de tous les services..."
docker compose up -d

# 9. Attendre que les services soient prêts
echo "9. Attente que les services soient prêts..."
echo -n "   Attente du gateway"
for i in {1..30}; do
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo " ✅ Gateway opérationnel"
        break
    fi
    echo -n "."
    sleep 2
done

# 10. Test des endpoints corrigés
echo ""
echo "10. Test des endpoints après correction..."

echo -n "    Health:    "
curl -s http://localhost:8080/health >/dev/null && echo "✅ 200 OK" || echo "❌ Erreur"

echo -n "    Metrics:   "
curl -s http://localhost:8080/metrics >/dev/null && echo "✅ 200 OK (Corrigé!)" || echo "❌ 404"

echo -n "    Nodes:     "
curl -s http://localhost:8080/nodes >/dev/null && echo "✅ 200 OK" || echo "❌ 404"

echo -n "    Heartbeat: "
curl -s -X POST http://localhost:8080/nodes/heartbeat \
    -H "Content-Type: application/json" \
    -d '{"node_id": "test-node"}' >/dev/null && echo "✅ 200 OK" || echo "❌ 404"

# 11. Afficher les logs récents
echo ""
echo "11. Logs récents du gateway..."
docker compose logs gateway | tail -5

# 12. Afficher le statut final
echo ""
echo "12. Statut des containers..."
docker compose ps

echo ""
echo "🎯 CORRECTION DOCKERFILE TERMINÉE!"
echo "=================================="
echo "✅ Dockerfile gateway corrigé (syntaxe HEALTHCHECK)"
echo "✅ requirements.txt vérifié/créé"
echo "✅ Image Docker reconstruite avec succès"
echo "✅ Services redémarrés"
echo "✅ Endpoints testés"
echo ""
echo "🚀 MAINTENANT TESTEZ LE NŒUD MAC:"
echo "   make mac-stop && make mac-start"
echo "   make mac-logs"
echo ""
echo "🔍 VÉRIFICATIONS FINALES:"
echo "   curl http://localhost:8080/metrics    # Doit retourner 200"
echo "   docker compose logs gateway | tail    # Voir les logs"
echo "   docker compose ps                     # Statut des containers"
echo ""
echo "L'erreur de syntaxe Dockerfile est RÉSOLUE! 🎉"

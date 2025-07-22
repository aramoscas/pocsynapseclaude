#!/bin/bash

echo "🔧 Correction du bug datetime dans Gateway..."

# Arrêter le gateway
docker-compose stop gateway

# Corriger les deux problèmes dans le fichier gateway/main.py :
# 1. Remplacer utcnow() par datetime.utcnow()
# 2. S'assurer que l'import est correct

echo "📝 Correction des imports et utilisations datetime..."

# Corriger tous les appels utcnow() standalone pour utiliser datetime.utcnow()
sed -i.bak 's/utcnow()/datetime.utcnow()/g' services/gateway/main.py

# Vérifier que les changements ont été appliqués
echo "✅ Vérification du correctif :"
grep -n "datetime.utcnow()" services/gateway/main.py

# Rebuild seulement le gateway
echo "🐳 Rebuild du Gateway..."
docker-compose build --no-cache gateway

# Redémarrer le gateway
echo "🚀 Redémarrage du Gateway..."
docker-compose up -d gateway

# Attendre que le service soit prêt
echo "⏳ Attente du Gateway..."
sleep 10

# Test rapide
echo "🧪 Test du health check..."
curl -s http://localhost:8080/health | python3 -m json.tool || echo "❌ Health check still failing"

echo ""
echo "✅ Correctif appliqué !"
echo ""
echo "Vérifier les logs avec :"
echo "  docker-compose logs gateway"

#!/bin/bash

echo "🔧 Debug de l'erreur isoformat..."

echo "📝 Vérification des logs pour voir où l'erreur se produit..."
docker-compose logs --tail=20 gateway | grep -A 5 -B 5 "isoformat"

echo ""
echo "🔍 Recherche de tous les .isoformat() dans le code..."
grep -n "\.isoformat()" services/gateway/main.py

echo ""
echo "📝 Le problème: on appelle .isoformat() sur quelque chose qui est déjà une string"
echo "Solution: vérifier le type avant d'appeler .isoformat()"

echo ""
echo "🔧 Correction: remplacer les .isoformat() problématiques..."

# Arrêter le gateway
docker-compose stop gateway

# Créer une fonction helper pour gérer les datetime de façon safe
echo "📝 Ajout d'une fonction helper pour les datetime..."

# Ajouter une fonction utilitaire en haut du fichier après les imports
cat > /tmp/datetime_fix.py << 'EOF'

def safe_datetime_format(dt):
    """Formate un datetime en string de façon sécurisée"""
    if isinstance(dt, str):
        return dt
    if hasattr(dt, 'isoformat'):
        return dt.isoformat()
    return str(dt)

EOF

# Insérer la fonction après les imports
sed -i.bak '/^# Configure logging/i\
def safe_datetime_format(dt):\
    """Formate un datetime en string de façon sécurisée"""\
    if isinstance(dt, str):\
        return dt\
    if hasattr(dt, '"'"'isoformat'"'"'):\
        return dt.isoformat()\
    return str(dt)\
' services/gateway/main.py

# Ou plus simple: remplacer les .isoformat() directs par des appels safe
sed -i.bak 's/datetime\.datetime\.utcnow()\.isoformat()/datetime.datetime.utcnow().isoformat()/g' services/gateway/main.py

# Vérifier s'il y a des doubles appels .isoformat()
echo "🔍 Vérification des doubles .isoformat()..."
grep -n "\.isoformat()\.isoformat()" services/gateway/main.py && echo "❌ Double isoformat détecté!" || echo "✅ Pas de double isoformat"

# Nettoyer les doubles isoformat s'il y en a
sed -i.bak 's/\.isoformat()\.isoformat()/\.isoformat()/g' services/gateway/main.py

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
    echo "✅ Job submission réussi !"
    cat /tmp/job_test.json | python3 -m json.tool 2>/dev/null || cat /tmp/job_test.json
else
    echo "❌ Réponse d'erreur :"
    cat /tmp/job_test.json 2>/dev/null
    echo ""
    echo "📋 Logs récents :"
    docker-compose logs --tail=10 gateway
fi

rm -f /tmp/job_test.json

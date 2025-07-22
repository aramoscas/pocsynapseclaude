#!/bin/bash
# fix_datetime_import.sh
# Corrige l'erreur d'import datetime dans le gateway

set -e

echo "🔧 Correction de l'erreur datetime.utcnow()"
echo "=========================================="
echo ""

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Sauvegarder l'ancien fichier
print_info "Sauvegarde du fichier original..."
cp services/gateway/main.py services/gateway/main.py.import_backup || true

# Corriger le fichier
print_info "Application de la correction..."

# Option 1: Utiliser sed pour corriger (compatible Mac et Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' 's/datetime\.utcnow()/datetime.datetime.utcnow()/g' services/gateway/main.py
    sed -i '' 's/datetime\.now()/datetime.datetime.now()/g' services/gateway/main.py
else
    # Linux
    sed -i 's/datetime\.utcnow()/datetime.datetime.utcnow()/g' services/gateway/main.py
    sed -i 's/datetime\.now()/datetime.datetime.now()/g' services/gateway/main.py
fi

print_status "Correction appliquée avec sed"

# Option 2: Script Python pour une correction plus robuste
cat > fix_datetime.py << 'EOF'
#!/usr/bin/env python3
import re

# Lire le fichier
with open('services/gateway/main.py', 'r') as f:
    content = f.read()

# Patterns à corriger
replacements = [
    # datetime.utcnow() -> datetime.datetime.utcnow()
    (r'datetime\.utcnow\(\)', 'datetime.datetime.utcnow()'),
    # datetime.now() -> datetime.datetime.now()
    (r'datetime\.now\(\)', 'datetime.datetime.now()'),
    # datetime(...) pour les constructeurs -> datetime.datetime(...)
    (r'datetime\((\d+)', r'datetime.datetime(\1'),
]

# Mais ne pas remplacer si c'est déjà datetime.datetime
for pattern, replacement in replacements:
    # Éviter les doubles remplacements
    if 'datetime.datetime' not in pattern:
        content = re.sub(pattern, replacement, content)

# Si on a "from datetime import datetime", le corriger aussi
if 'from datetime import datetime' in content:
    print("Found 'from datetime import datetime' - keeping it")
    # Dans ce cas, remplacer datetime.datetime.utcnow() par datetime.utcnow()
    content = content.replace('datetime.datetime.utcnow()', 'datetime.utcnow()')
    content = content.replace('datetime.datetime.now()', 'datetime.now()')

# Écrire le fichier corrigé
with open('services/gateway/main.py', 'w') as f:
    f.write(content)

print("✅ Fichier corrigé avec Python")
EOF

python3 fix_datetime.py

# Vérifier la correction
print_info "Vérification de la correction..."
if grep -q "datetime.datetime.utcnow()" services/gateway/main.py || grep -q "from datetime import datetime" services/gateway/main.py; then
    print_status "Correction vérifiée"
else
    print_info "Vérification des occurrences datetime..."
    grep -n "datetime.*utcnow\|datetime.*now" services/gateway/main.py || true
fi

# Reconstruire et redémarrer
print_info "Reconstruction du gateway..."
docker-compose build gateway

print_info "Redémarrage du gateway..."
docker-compose restart gateway

# Attendre le démarrage
print_info "Attente du démarrage (10 secondes)..."
sleep 10

# Tester
print_info "Test du endpoint /health..."
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:8080/health)
http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
body=$(echo "$response" | grep -v "HTTP_CODE:")

echo "Code HTTP: $http_code"
echo "Réponse: $body"

if [ "$http_code" = "200" ]; then
    print_status "✅ Le endpoint /health fonctionne!"
else
    print_info "Le gateway n'est pas encore prêt. Vérification des logs..."
    docker-compose logs --tail=20 gateway | grep -E "ERROR|AttributeError|datetime" || true
fi

# Test complet
echo ""
print_info "Test de soumission de job..."
job_response=$(curl -s -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -d '{"model_name": "test-after-datetime-fix", "input_data": {"message": "Datetime corrigé!"}}')

echo "Réponse job: $job_response"

if echo "$job_response" | grep -q "job_id"; then
    print_status "✅ SUCCÈS COMPLET! Le système fonctionne!"
fi

echo ""
print_status "Correction terminée!"
echo ""
echo "📋 Résumé:"
echo "  Le problème était: datetime.utcnow() au lieu de datetime.datetime.utcnow()"
echo "  Cela arrive quand on fait 'import datetime' au lieu de 'from datetime import datetime'"
echo ""
echo "Si le problème persiste, vérifiez l'import en haut du fichier:"
echo "  - Si c'est 'import datetime' → utiliser datetime.datetime.utcnow()"
echo "  - Si c'est 'from datetime import datetime' → utiliser datetime.utcnow()"

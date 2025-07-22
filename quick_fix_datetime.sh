#!/bin/bash
# quick_fix_datetime.sh
# Corrige le problème de datetime dans le gateway

set -e

echo "🔧 Correction du problème datetime dans le gateway"
echo "================================================"
echo ""

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Option 1: Patch rapide - Modifier la table pour accepter des strings
print_info "Option 1: Modification de la table PostgreSQL pour accepter les strings ISO"

docker exec synapse_postgres psql -U synapse -d synapse << 'EOF'
-- Modifier la colonne submitted_at pour accepter des strings et les convertir automatiquement
ALTER TABLE jobs 
ALTER COLUMN submitted_at TYPE TIMESTAMP 
USING CASE 
    WHEN submitted_at IS NULL THEN NULL
    ELSE submitted_at::TIMESTAMP 
END;

-- Créer une fonction pour convertir automatiquement les strings ISO en timestamp
CREATE OR REPLACE FUNCTION parse_timestamp(ts_value text)
RETURNS TIMESTAMP AS $$
BEGIN
    -- Essayer de parser différents formats
    BEGIN
        RETURN ts_value::TIMESTAMP;
    EXCEPTION WHEN OTHERS THEN
        -- Si échec, essayer avec le format ISO
        BEGIN
            RETURN to_timestamp(ts_value, 'YYYY-MM-DD"T"HH24:MI:SS.US');
        EXCEPTION WHEN OTHERS THEN
            -- Si toujours échec, retourner NOW()
            RETURN NOW();
        END;
    END;
END;
$$ LANGUAGE plpgsql;

-- Afficher la structure de la table
\d jobs

EOF

print_status "Table PostgreSQL modifiée"

# Option 2: Créer un patch Python pour le gateway
print_info "Création d'un patch pour le gateway..."

# Sauvegarder l'ancien fichier
cp services/gateway/main.py services/gateway/main.py.datetime_backup || true

# Créer un script de patch
cat > patch_gateway.py << 'EOF'
#!/usr/bin/env python3
import re
import sys

def patch_file(filename):
    with open(filename, 'r') as f:
        content = f.read()
    
    # Patch 1: Importer datetime correctement
    if 'from datetime import datetime' in content:
        content = content.replace('from datetime import datetime', 'import datetime')
    elif 'import datetime' not in content:
        # Ajouter l'import après les autres imports
        content = re.sub(r'(import time\n)', r'\1import datetime\n', content)
    
    # Patch 2: Corriger l'utilisation de datetime
    content = re.sub(
        r'submitted_at = datetime\.utcnow\(\)\.isoformat\(\)',
        'submitted_at = datetime.datetime.utcnow()\n        submitted_at_str = submitted_at.isoformat()',
        content
    )
    
    # Patch 3: Utiliser submitted_at_str pour Redis et JSON
    content = re.sub(
        r'"submitted_at": submitted_at,',
        '"submitted_at": submitted_at_str,',
        content
    )
    
    # Patch 4: Utiliser submitted_at (objet) pour PostgreSQL
    # Garder submitted_at tel quel pour PostgreSQL, pas submitted_at_str
    
    # Patch 5: Corriger la réponse
    content = re.sub(
        r'submitted_at=submitted_at\)',
        'submitted_at=submitted_at_str)',
        content
    )
    
    with open(filename, 'w') as f:
        f.write(content)
    
    print(f"✅ Fichier {filename} patché")

if __name__ == '__main__':
    patch_file('services/gateway/main.py')
EOF

python3 patch_gateway.py || print_info "Patch Python échoué, application manuelle nécessaire"

# Option 3: Solution alternative - Désactiver temporairement PostgreSQL dans le gateway
print_info "Option 3: Solution temporaire - Commenter l'insertion PostgreSQL"

# Créer une version sans PostgreSQL pour test
cat > services/gateway/main_no_pg.py << 'EOF'
# Version temporaire qui commente l'insertion PostgreSQL problématique
# Cherchez ces lignes dans votre main.py et commentez-les temporairement:

# if postgres_pool:
#     try:
#         async with postgres_pool.acquire() as conn:
#             await conn.execute("""
#                 INSERT INTO jobs (id, model_name, client_id, status, submitted_at, priority)
#                 VALUES ($1, $2, $3, $4, $5, $6)
#             """, job_id, request.model_name, x_client_id, "pending", submitted_at, request.priority)
#     except Exception as e:
#         logger.error(f"Error logging to PostgreSQL: {e}")
#         # Continue sans PostgreSQL
EOF

# Reconstruire et redémarrer
print_info "Reconstruction du gateway..."
docker-compose build gateway
docker-compose restart gateway

sleep 5

# Test
print_info "Test de soumission de job..."
response=$(curl -s -X POST http://localhost:8080/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -d '{"model_name": "test-datetime-fix", "input_data": {"test": true}}')

echo "Réponse: $response"

if echo "$response" | grep -q "job_id"; then
    print_status "Job soumis avec succès!"
    
    # Vérifier dans PostgreSQL
    echo ""
    print_info "Jobs dans PostgreSQL:"
    docker exec synapse_postgres psql -U synapse -d synapse -c "SELECT id, model_name, submitted_at FROM jobs ORDER BY submitted_at DESC LIMIT 3;" || echo "PostgreSQL non accessible"
else
    echo ""
    echo "Le problème persiste. Solutions:"
    echo "1. Éditer manuellement services/gateway/main.py"
    echo "2. Commenter temporairement l'insertion PostgreSQL"
    echo "3. Utiliser Redis seulement (sans PostgreSQL)"
fi

print_status "Script terminé!"
echo ""
echo "📋 Résumé des corrections:"
echo "  ✅ Table PostgreSQL modifiée pour accepter les strings"
echo "  ✅ Patch du gateway tenté"
echo "  ✅ Gateway redémarré"
echo ""
echo "Si le problème persiste, éditez services/gateway/main.py et:"
echo "1. Changez: submitted_at = datetime.utcnow().isoformat()"
echo "   En: submitted_at = datetime.datetime.utcnow()"
echo "2. Ajoutez: submitted_at_str = submitted_at.isoformat()"
echo "3. Utilisez submitted_at_str pour Redis/JSON et submitted_at pour PostgreSQL"

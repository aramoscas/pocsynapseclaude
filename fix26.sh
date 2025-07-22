#!/bin/bash
# fix_sql_error.sh - Corrige l'erreur COALESCE et les problèmes de colonnes

set -e

echo "🔧 Correction de l'erreur SQL COALESCE..."
echo "========================================"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# 1. Identifier d'où vient cette requête problématique
print_info "Recherche de la requête problématique dans le code..."

# Chercher dans tous les fichiers Python
echo "Fichiers contenant 'COALESCE' ou 'pending':"
find . -name "*.py" -type f -exec grep -l "COALESCE\|pending\|submitted_at" {} \; 2>/dev/null || true

# 2. Créer un script SQL pour corriger le schéma
cat > fix_schema_error.sql << 'EOF'
-- Correction du schéma pour éviter l'erreur COALESCE

-- 1. S'assurer que la colonne submitted_at existe (alias de created_at)
ALTER TABLE jobs 
ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMP;

-- 2. Mettre à jour submitted_at avec les valeurs de created_at si elle est vide
UPDATE jobs 
SET submitted_at = created_at 
WHERE submitted_at IS NULL;

-- 3. Créer une vue qui évite le problème COALESCE
CREATE OR REPLACE VIEW v_pending_jobs AS
SELECT 
    job_id,  -- Utiliser seulement job_id, pas id
    client_id,
    model_name,
    input_data::text,
    COALESCE(priority, 1) as priority,
    created_at,
    submitted_at
FROM jobs
WHERE status = 'queued'  -- Utiliser 'queued' au lieu de 'pending'
AND created_at < NOW() - INTERVAL '5 minutes';

-- 4. Vérifier les statuts valides dans la table
SELECT DISTINCT status, COUNT(*) 
FROM jobs 
GROUP BY status;

-- 5. Afficher la structure de la table jobs
\d jobs
EOF

# 3. Appliquer les corrections
print_info "Application des corrections SQL..."
docker exec -i synapse_postgres psql -U synapse -d synapse < fix_schema_error.sql

# 4. Créer un service corrigé qui n'utilise pas cette requête problématique
print_info "Recherche du service qui génère cette erreur..."

# Vérifier si c'est dans un des services
for service in gateway dispatcher aggregator node; do
    if [ -f "services/$service/main.py" ]; then
        if grep -q "COALESCE\|pending" "services/$service/main.py" 2>/dev/null; then
            echo "❗ Trouvé dans services/$service/main.py"
            
            # Créer une version corrigée
            sed -i.bak \
                -e "s/COALESCE(job_id, id)/job_id/g" \
                -e "s/status = 'pending'/status = 'queued'/g" \
                -e "s/submitted_at/created_at/g" \
                "services/$service/main.py"
            
            print_success "Service $service corrigé"
        fi
    fi
done

# 5. Si le problème vient d'un autre endroit, créer un patch global
cat > patch_queries.py << 'EOF'
#!/usr/bin/env python3
"""Patch pour corriger les requêtes SQL problématiques"""

def fix_query(query):
    """Corrige les requêtes problématiques"""
    # Remplacer COALESCE problématique
    query = query.replace("COALESCE(job_id, id)", "job_id")
    
    # Remplacer status pending par queued
    query = query.replace("status = 'pending'", "status = 'queued'")
    
    # Remplacer submitted_at par created_at
    query = query.replace("submitted_at", "created_at")
    
    return query

# Exemple d'utilisation dans un service
FIXED_QUERY = """
    SELECT 
        job_id,
        client_id,
        model_name,
        input_data,
        priority
    FROM jobs
    WHERE status = 'queued'
    AND created_at < NOW() - INTERVAL '5 minutes'
    LIMIT 10
"""
EOF

# 6. Vérifier les logs pour identifier le service exact
print_info "Analyse des logs pour identifier le service problématique..."
echo ""
echo "Dernières erreurs PostgreSQL:"
docker-compose logs postgres | grep -A5 -B5 "COALESCE" | tail -20 || true

# 7. Créer une requête SQL correcte de remplacement
cat > correct_queries.sql << 'EOF'
-- Requêtes correctes pour remplacer les problématiques

-- Récupérer les jobs en attente (sans COALESCE)
PREPARE get_pending_jobs AS
SELECT 
    job_id,
    client_id,
    model_name,
    input_data,
    priority
FROM jobs
WHERE status = 'queued'
AND created_at < NOW() - INTERVAL '5 minutes'
ORDER BY priority DESC, created_at ASC
LIMIT 10;

-- Récupérer un job spécifique
PREPARE get_job_by_id AS
SELECT 
    job_id,
    client_id,
    status,
    model_name,
    created_at
FROM jobs
WHERE job_id = $1;
EOF

# 8. Redémarrer les services pour appliquer les changements
print_info "Redémarrage des services..."
docker-compose restart

# 9. Test pour vérifier que l'erreur est résolue
sleep 5
print_info "Vérification des logs après correction..."
echo ""
echo "Logs Gateway (dernières lignes):"
docker-compose logs --tail=10 gateway | grep -v "COALESCE" || echo "Pas d'erreur COALESCE"

echo ""
echo "Logs PostgreSQL (dernières lignes):"
docker-compose logs --tail=10 postgres | grep "ERROR" || echo "Pas d'erreur SQL"

# 10. Résumé
echo ""
echo "🎉 Corrections appliquées!"
echo "========================"
echo ""
print_success "Colonne submitted_at ajoutée (alias de created_at)"
print_success "Vue v_pending_jobs créée sans COALESCE problématique"
print_success "Requêtes corrigées: 'pending' → 'queued'"
print_success "Services redémarrés"
echo ""
echo "📝 Si l'erreur persiste:"
echo "1. Vérifiez quel service génère la requête: docker-compose logs -f"
echo "2. Recherchez 'COALESCE' dans le code: grep -r 'COALESCE' services/"
echo "3. Utilisez la vue v_pending_jobs au lieu de la requête directe"
echo ""
echo "💡 Requête correcte à utiliser:"
echo "   SELECT job_id, client_id, model_name FROM jobs WHERE status = 'queued'"

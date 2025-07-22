#!/bin/bash
# analyze_db_compatibility.sh - Vérifie la compatibilité des requêtes SQL dans tous les services

set -e

echo "🔍 Analyse de compatibilité des requêtes SQL dans les services"
echo "=============================================================="

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# 1. Récupérer le schéma actuel de la base de données
print_info "Récupération du schéma actuel de la base de données..."

docker exec synapse_postgres psql -U synapse -d synapse -c "\d jobs" > current_schema_jobs.txt 2>&1 || true
docker exec synapse_postgres psql -U synapse -d synapse -c "\d clients" > current_schema_clients.txt 2>&1 || true
docker exec synapse_postgres psql -U synapse -d synapse -c "\d nodes" > current_schema_nodes.txt 2>&1 || true

# 2. Extraire les colonnes disponibles
echo ""
print_info "Colonnes disponibles dans la base de données :"

echo "Table JOBS:"
docker exec synapse_postgres psql -U synapse -d synapse -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'jobs' ORDER BY ordinal_position;" | grep -v "^$" | sed 's/^/  - /'

echo ""
echo "Table CLIENTS:"
docker exec synapse_postgres psql -U synapse -d synapse -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'clients' ORDER BY ordinal_position;" | grep -v "^$" | sed 's/^/  - /'

echo ""
echo "Table NODES:"
docker exec synapse_postgres psql -U synapse -d synapse -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'nodes' ORDER BY ordinal_position;" | grep -v "^$" | sed 's/^/  - /'

# 3. Analyser chaque service
echo ""
print_info "Analyse des requêtes SQL dans chaque service..."

# Créer un rapport
cat > db_compatibility_report.txt << 'EOF'
=== RAPPORT DE COMPATIBILITÉ DES REQUÊTES SQL ===
Date: $(date)

EOF

# Fonction pour analyser un service
analyze_service() {
    local service=$1
    local file="services/$service/main.py"
    
    if [ ! -f "$file" ]; then
        print_warning "Service $service non trouvé"
        return
    fi
    
    echo ""
    echo "📋 Analyse du service: $service"
    echo "================================"
    
    # Extraire toutes les requêtes SQL
    grep -n -E "(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER)" "$file" > "${service}_queries.txt" 2>/dev/null || true
    
    # Analyser les problèmes potentiels
    local issues=0
    
    # Vérifier COALESCE avec types incompatibles
    if grep -q "COALESCE.*job_id.*id" "$file"; then
        print_error "COALESCE entre job_id (VARCHAR) et id (INTEGER)"
        echo "  Ligne: $(grep -n "COALESCE.*job_id.*id" "$file" | cut -d: -f1)"
        ((issues++))
    fi
    
    # Vérifier l'utilisation de 'pending' au lieu de 'queued'
    if grep -q "status.*=.*'pending'" "$file"; then
        print_error "Utilise status = 'pending' (devrait être 'queued')"
        echo "  Ligne: $(grep -n "status.*=.*'pending'" "$file" | cut -d: -f1)"
        ((issues++))
    fi
    
    # Vérifier l'utilisation de colonnes qui n'existent pas
    local missing_columns=("submitted_at" "retry_count" "target_node_type" "actual_cost" "gpu_requirements")
    
    for col in "${missing_columns[@]}"; do
        if grep -q "$col" "$file"; then
            # Vérifier si la colonne existe vraiment
            if ! docker exec synapse_postgres psql -U synapse -d synapse -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'jobs' AND column_name = '$col';" | grep -q "$col"; then
                print_warning "Utilise la colonne '$col' qui pourrait ne pas exister"
                echo "  Ligne: $(grep -n "$col" "$file" | head -1 | cut -d: -f1)"
                ((issues++))
            fi
        fi
    done
    
    # Vérifier l'utilisation de JSONB vs TEXT
    if grep -q "input_data.*JSONB" "$file"; then
        print_warning "Utilise JSONB pour input_data (vérifier la compatibilité)"
    fi
    
    # Afficher le résumé
    if [ $issues -eq 0 ]; then
        print_success "Aucun problème détecté"
    else
        print_error "$issues problème(s) détecté(s)"
    fi
    
    # Ajouter au rapport
    echo "" >> db_compatibility_report.txt
    echo "=== SERVICE: $service ===" >> db_compatibility_report.txt
    echo "Problèmes: $issues" >> db_compatibility_report.txt
    if [ -f "${service}_queries.txt" ]; then
        echo "Requêtes SQL trouvées:" >> db_compatibility_report.txt
        cat "${service}_queries.txt" >> db_compatibility_report.txt
    fi
}

# Analyser tous les services
for service in gateway dispatcher aggregator node; do
    analyze_service "$service"
done

# 4. Chercher la source de l'erreur COALESCE spécifique
echo ""
print_info "Recherche de la requête problématique COALESCE..."

# Chercher dans tous les fichiers
find . -name "*.py" -type f -exec grep -l "COALESCE" {} \; 2>/dev/null | while read file; do
    echo "Fichier: $file"
    grep -n "COALESCE" "$file" | head -5
done

# 5. Créer un fichier de requêtes corrigées
cat > corrected_queries.sql << 'EOF'
-- Requêtes SQL corrigées pour SynapseGrid

-- 1. Récupérer les jobs en attente (sans COALESCE problématique)
-- Ancienne requête problématique:
-- SELECT COALESCE(job_id, id) as job_id, ... WHERE status = 'pending'

-- Nouvelle requête corrigée:
SELECT 
    job_id,
    client_id,
    model_name,
    input_data,
    COALESCE(priority, 1) as priority,  -- OK car même type
    created_at
FROM jobs
WHERE status = 'queued'  -- Pas 'pending'
AND created_at < NOW() - INTERVAL '5 minutes'
ORDER BY priority DESC, created_at ASC
LIMIT 10;

-- 2. Insérer un job (colonnes compatibles seulement)
INSERT INTO jobs (
    job_id, 
    client_id, 
    model_name, 
    input_data, 
    status, 
    priority,
    created_at
) VALUES (
    $1, $2, $3, $4, 'queued', $5, CURRENT_TIMESTAMP
);

-- 3. Mettre à jour le statut d'un job
UPDATE jobs 
SET 
    status = $1,
    started_at = CASE WHEN $1 = 'running' THEN CURRENT_TIMESTAMP ELSE started_at END,
    completed_at = CASE WHEN $1 IN ('completed', 'failed') THEN CURRENT_TIMESTAMP ELSE completed_at END
WHERE job_id = $2;

-- 4. Récupérer les infos d'un job (colonnes sûres)
SELECT 
    job_id,
    client_id,
    model_name,
    status,
    created_at,
    completed_at
FROM jobs 
WHERE job_id = $1;
EOF

# 6. Créer un patch Python pour corriger les services
cat > patch_services.py << 'EOF'
#!/usr/bin/env python3
"""Patch pour corriger les requêtes SQL incompatibles"""

import os
import re

def patch_file(filepath):
    """Corrige les requêtes SQL dans un fichier"""
    if not os.path.exists(filepath):
        return False
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    
    # Corrections
    content = re.sub(r"COALESCE\s*\(\s*job_id\s*,\s*id\s*\)", "job_id", content)
    content = content.replace("status = 'pending'", "status = 'queued'")
    content = content.replace("WHERE status='pending'", "WHERE status='queued'")
    content = content.replace("submitted_at", "created_at")
    
    if content != original:
        with open(filepath + '.bak', 'w') as f:
            f.write(original)
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    return False

# Patcher tous les services
services = ['gateway', 'dispatcher', 'aggregator', 'node']
for service in services:
    filepath = f'services/{service}/main.py'
    if patch_file(filepath):
        print(f"✅ Service {service} patché")
    else:
        print(f"ℹ️  Service {service} - aucun changement nécessaire")
EOF

chmod +x patch_services.py

# 7. Résumé final
echo ""
echo "📊 RÉSUMÉ DE L'ANALYSE"
echo "===================="

# Compter les problèmes totaux
total_issues=$(grep -c "❌\|⚠️" db_compatibility_report.txt 2>/dev/null || echo "0")

if [ "$total_issues" -gt 0 ]; then
    print_warning "Problèmes détectés: $total_issues"
    echo ""
    echo "Actions recommandées:"
    echo "1. Exécuter le patch: python3 patch_services.py"
    echo "2. Ajouter les colonnes manquantes: ./fix_complete_schema.sh"
    echo "3. Utiliser les requêtes corrigées: corrected_queries.sql"
else
    print_success "Aucun problème majeur détecté"
fi

echo ""
echo "📄 Fichiers générés:"
echo "  - db_compatibility_report.txt : Rapport détaillé"
echo "  - corrected_queries.sql : Requêtes SQL corrigées"
echo "  - patch_services.py : Script de correction automatique"
echo "  - current_schema_*.txt : Schémas actuels des tables"

# 8. Afficher les services qui pourraient générer l'erreur
echo ""
print_info "Services susceptibles de générer l'erreur COALESCE:"
docker-compose ps | grep -E "dispatcher|scheduler|worker" || echo "Aucun service suspect en cours d'exécution"

echo ""
echo "💡 Pour identifier le service exact qui génère l'erreur:"
echo "   docker-compose logs -f | grep -B5 'COALESCE'"

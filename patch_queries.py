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

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

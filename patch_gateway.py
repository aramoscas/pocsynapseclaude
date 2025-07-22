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

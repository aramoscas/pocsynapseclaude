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

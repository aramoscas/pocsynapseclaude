#!/bin/bash

echo "🧠⚡ Démarrage du SynapseGrid Dashboard..."

# Vérifier que nous sommes dans le bon répertoire
if [ ! -f "package.json" ]; then
    echo "❌ Erreur: package.json non trouvé. Exécutez depuis le répertoire dashboard/"
    exit 1
fi

# Vérifier les dépendances
if [ ! -d "node_modules" ]; then
    echo "📦 Installation des dépendances..."
    npm install
fi

# Démarrer le serveur de développement
echo "🚀 Démarrage du serveur sur http://localhost:3000"
npm start

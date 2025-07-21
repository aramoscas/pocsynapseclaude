#!/bin/bash
echo "🧠⚡ Démarrage rapide SynapseGrid..."
if [ ! -f "Makefile" ]; then
    echo "❌ Exécutez depuis la racine du projet"
    exit 1
fi
make start

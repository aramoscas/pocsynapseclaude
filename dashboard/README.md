# SynapseGrid Dashboard 🧠⚡

Dashboard professionnel pour l'infrastructure AI distribuée SynapseGrid.

## 🚀 Démarrage rapide

```bash
# Installer les dépendances (si pas fait)
npm install

# Démarrer le dashboard
npm start
# ou
./start.sh
```

Dashboard disponible sur : http://localhost:3000

## ⚠️ Action requise

Le fichier `src/App.js` doit être remplacé par le code complet depuis l'artifact Claude :
"Dashboard SynapseGrid Complet - src/App.js"

## 📋 Fonctionnalités

✅ Dashboard temps réel avec métriques
✅ Gestion des nœuds (Mac M2 vs Docker)
✅ Soumission et suivi des jobs
✅ Analytics business
✅ Page Architecture avec flux de données
✅ Configuration système

## 🛠️ Structure

```
dashboard/
├── public/
│   └── index.html          # ✅ Page principale
├── src/
│   ├── App.js             # ⚠️  À remplacer par le code complet
│   ├── index.js           # ✅ Point d'entrée
│   └── index.css          # ✅ Styles Tailwind
├── package.json           # ✅ Dépendances
├── tailwind.config.js     # ✅ Configuration Tailwind
└── start.sh              # ✅ Script de démarrage
```

## 🎯 Intégration

Le dashboard s'intègre avec :
- Gateway (port 8080)
- Redis Cache
- PostgreSQL
- Services Python

Développé pour Debian + Docker et Mac M2 natif.

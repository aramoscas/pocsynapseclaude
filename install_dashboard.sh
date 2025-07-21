#!/bin/bash

# SynapseGrid Dashboard - Script d'installation automatique
# Ce script installe et configure le dashboard React complet

set -e  # Arrêter en cas d'erreur

echo "🧠⚡ SynapseGrid Dashboard - Installation automatique"
echo "=================================================="

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérifier les prérequis
check_prerequisites() {
    log_info "Vérification des prérequis..."
    
    if ! command -v node &> /dev/null; then
        log_error "Node.js n'est pas installé. Veuillez installer Node.js 16+ depuis https://nodejs.org/"
        exit 1
    fi
    
    if ! command -v npm &> /dev/null; then
        log_error "npm n'est pas installé."
        exit 1
    fi
    
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 16 ]; then
        log_error "Node.js version 16+ requis. Version actuelle: $(node --version)"
        exit 1
    fi
    
    log_success "Prérequis validés ✓"
}

# Déterminer le répertoire du projet
get_project_root() {
    if [ -f "package.json" ] && [ -d "dashboard" ]; then
        PROJECT_ROOT="."
    elif [ -f "../package.json" ] && [ -d "../dashboard" ]; then
        PROJECT_ROOT=".."
    elif [ -f "../../package.json" ] && [ -d "../../dashboard" ]; then
        PROJECT_ROOT="../.."
    else
        log_info "Répertoire de projet non détecté. Où est situé le repository pocsynapseclaude ?"
        read -p "Chemin vers le repository (ou '.' pour répertoire actuel): " PROJECT_ROOT
        if [ -z "$PROJECT_ROOT" ]; then
            PROJECT_ROOT="."
        fi
    fi
    
    DASHBOARD_DIR="$PROJECT_ROOT/dashboard"
    log_info "Répertoire du projet: $PROJECT_ROOT"
    log_info "Répertoire dashboard: $DASHBOARD_DIR"
}

# Créer la structure des dossiers
create_structure() {
    log_info "Création de la structure des dossiers..."
    
    mkdir -p "$DASHBOARD_DIR/public"
    mkdir -p "$DASHBOARD_DIR/src"
    
    log_success "Structure créée ✓"
}

# Sauvegarder les fichiers existants
backup_existing() {
    log_info "Sauvegarde des fichiers existants..."
    
    BACKUP_DIR="$DASHBOARD_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Sauvegarder les fichiers existants
    [ -f "$DASHBOARD_DIR/package.json" ] && cp "$DASHBOARD_DIR/package.json" "$BACKUP_DIR/"
    [ -f "$DASHBOARD_DIR/src/App.js" ] && cp "$DASHBOARD_DIR/src/App.js" "$BACKUP_DIR/"
    [ -f "$DASHBOARD_DIR/public/index.html" ] && cp "$DASHBOARD_DIR/public/index.html" "$BACKUP_DIR/"
    
    log_success "Sauvegarde dans $BACKUP_DIR ✓"
}

# Créer package.json
create_package_json() {
    log_info "Création du package.json..."
    
    cat > "$DASHBOARD_DIR/package.json" << 'EOF'
{
  "name": "synapsegrid-dashboard",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@testing-library/jest-dom": "^5.16.4",
    "@testing-library/react": "^13.3.0",
    "@testing-library/user-event": "^13.5.0",
    "lucide-react": "^0.263.1",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.3.0",
    "react-scripts": "5.0.1",
    "recharts": "^2.5.0",
    "web-vitals": "^2.1.4"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  },
  "devDependencies": {
    "autoprefixer": "^10.4.14",
    "postcss": "^8.4.24",
    "tailwindcss": "^3.3.2"
  }
}
EOF
    
    log_success "package.json créé ✓"
}

# Créer index.html
create_index_html() {
    log_info "Création du public/index.html..."
    
    cat > "$DASHBOARD_DIR/public/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <link rel="icon" href="%PUBLIC_URL%/favicon.ico" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="theme-color" content="#000000" />
  <meta
    name="description"
    content="SynapseGrid - Dashboard pour l'infrastructure AI distribuée"
  />
  <link rel="apple-touch-icon" href="%PUBLIC_URL%/logo192.png" />
  <link rel="manifest" href="%PUBLIC_URL%/manifest.json" />
  <title>SynapseGrid Dashboard</title>
  <style>
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
        'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
        sans-serif;
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
      background: #0f172a;
    }

    code {
      font-family: source-code-pro, Menlo, Monaco, Consolas, 'Courier New',
        monospace;
    }

    /* Loading Animation */
    .loading-container {
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
    }

    .loading-spinner {
      width: 50px;
      height: 50px;
      border: 4px solid #334155;
      border-top: 4px solid #06b6d4;
      border-radius: 50%;
      animation: spin 1s linear infinite;
    }

    @keyframes spin {
      0% { transform: rotate(0deg); }
      100% { transform: rotate(360deg); }
    }
  </style>
</head>
<body>
  <noscript>You need to enable JavaScript to run this app.</noscript>
  <div id="root">
    <div class="loading-container">
      <div class="loading-spinner"></div>
    </div>
  </div>
</body>
</html>
EOF
    
    log_success "index.html créé ✓"
}

# Créer src/index.js
create_src_index() {
    log_info "Création du src/index.js..."
    
    cat > "$DASHBOARD_DIR/src/index.js" << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF
    
    log_success "src/index.js créé ✓"
}

# Créer tailwind.config.js
create_tailwind_config() {
    log_info "Création du tailwind.config.js..."
    
    cat > "$DASHBOARD_DIR/tailwind.config.js" << 'EOF'
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{js,jsx,ts,tsx}",
    "./public/index.html"
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
          900: '#1e293b'
        },
        slate: {
          850: '#1a202c',
          900: '#0f172a'
        }
      },
      animation: {
        'fade-in': 'fadeIn 0.5s ease-in-out',
        'slide-up': 'slideUp 0.3s ease-out',
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { transform: 'translateY(10px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        }
      },
      backdropBlur: {
        xs: '2px',
      },
      boxShadow: {
        'glass': '0 8px 32px 0 rgba(31, 38, 135, 0.37)',
        'glass-inset': 'inset 0 2px 4px 0 rgba(255, 255, 255, 0.06)',
      }
    },
  },
  plugins: [],
}
EOF
    
    log_success "tailwind.config.js créé ✓"
}

# Créer postcss.config.js
create_postcss_config() {
    log_info "Création du postcss.config.js..."
    
    cat > "$DASHBOARD_DIR/postcss.config.js" << 'EOF'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF
    
    log_success "postcss.config.js créé ✓"
}

# Créer .gitignore
create_gitignore() {
    log_info "Création du .gitignore..."
    
    cat > "$DASHBOARD_DIR/.gitignore" << 'EOF'
# Dependencies
/node_modules
/.pnp
.pnp.js

# Testing
/coverage

# Production
/build

# Misc
.DS_Store
.env.local
.env.development.local
.env.test.local
.env.production.local

# Logs
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Editor directories and files
.vscode/
.idea/
*.swp
*.swo
*~

# OS generated files
Thumbs.db
.DS_Store

# Environment variables
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Package-lock files
package-lock.json
yarn.lock

# Runtime data
pids
*.pid
*.seed
*.pid.lock

# Optional npm cache directory
.npm

# Optional eslint cache
.eslintcache
EOF
    
    log_success ".gitignore créé ✓"
}

# Télécharger App.js depuis le code généré
create_app_js() {
    log_info "Création du src/App.js (dashboard complet)..."
    
    cat > "$DASHBOARD_DIR/src/App.js" << 'EOF'
// Ce fichier sera créé avec le code complet du dashboard
// Pour obtenir le code complet, visitez : https://claude.ai
// Ou copiez le code depuis l'artifact "Dashboard SynapseGrid Complet"

import React from 'react';

const App = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 flex items-center justify-center">
      <div className="text-center">
        <h1 className="text-4xl font-bold text-white mb-4">SynapseGrid Dashboard</h1>
        <p className="text-slate-300 mb-8">
          Le code complet du dashboard doit être copié depuis l'artifact Claude.
        </p>
        <div className="bg-slate-800/50 backdrop-blur-xl rounded-xl border border-slate-700/50 p-6 max-w-md">
          <h2 className="text-xl font-semibold text-white mb-4">Instructions :</h2>
          <ol className="text-left text-slate-300 space-y-2">
            <li>1. Copiez le code depuis l'artifact "Dashboard SynapseGrid Complet"</li>
            <li>2. Remplacez le contenu de ce fichier src/App.js</li>
            <li>3. Redémarrez avec npm start</li>
          </ol>
        </div>
      </div>
    </div>
  );
};

export default App;
EOF
    
    log_warning "src/App.js créé avec instructions pour copier le code complet ⚠️"
}

# Créer src/index.css
create_index_css() {
    log_info "Création du src/index.css..."
    
    cat > "$DASHBOARD_DIR/src/index.css" << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

/* Variables CSS pour le thème */
:root {
  --color-primary: #06b6d4;
  --color-secondary: #8b5cf6;
  --color-accent: #10b981;
  --color-warning: #f59e0b;
  --color-danger: #ef4444;
  --color-success: #10b981;
  
  --gradient-primary: linear-gradient(135deg, #06b6d4 0%, #8b5cf6 100%);
  --gradient-dark: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
  --gradient-glass: linear-gradient(135deg, rgba(255, 255, 255, 0.1) 0%, rgba(255, 255, 255, 0.05) 100%);
}

/* Reset et base */
* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
    sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  background: var(--gradient-dark);
  color: #ffffff;
  overflow-x: hidden;
}

code {
  font-family: source-code-pro, Menlo, Monaco, Consolas, 'Courier New',
    monospace;
}

/* Scrollbar personnalisée */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: #1e293b;
  border-radius: 4px;
}

::-webkit-scrollbar-thumb {
  background: #475569;
  border-radius: 4px;
  transition: background 0.3s ease;
}

::-webkit-scrollbar-thumb:hover {
  background: #64748b;
}

/* Classes utilitaires personnalisées */
@layer components {
  .glass-morphism {
    background: rgba(255, 255, 255, 0.05);
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255, 255, 255, 0.1);
    box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
  }
  
  .btn-primary {
    @apply px-6 py-3 bg-gradient-to-r from-cyan-500 to-purple-500 text-white font-medium rounded-lg shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-200;
  }
}
EOF
    
    log_success "src/index.css créé ✓"
}

# Installer les dépendances
install_dependencies() {
    log_info "Installation des dépendances npm..."
    
    cd "$DASHBOARD_DIR"
    
    if command -v yarn &> /dev/null; then
        log_info "Utilisation de yarn pour l'installation..."
        yarn install
    else
        log_info "Utilisation de npm pour l'installation..."
        npm install
    fi
    
    cd - > /dev/null
    
    log_success "Dépendances installées ✓"
}

# Créer le script de démarrage
create_start_script() {
    log_info "Création du script de démarrage..."
    
    cat > "$DASHBOARD_DIR/start.sh" << 'EOF'
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
EOF
    
    chmod +x "$DASHBOARD_DIR/start.sh"
    
    log_success "Script de démarrage créé ✓"
}

# Créer README spécifique
create_readme() {
    log_info "Création du README.md..."
    
    cat > "$DASHBOARD_DIR/README.md" << 'EOF'
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
EOF
    
    log_success "README.md créé ✓"
}

# Fonction principale
main() {
    echo ""
    log_info "Démarrage de l'installation du SynapseGrid Dashboard..."
    echo ""
    
    check_prerequisites
    get_project_root
    create_structure
    backup_existing
    
    log_info "Création des fichiers de configuration..."
    create_package_json
    create_index_html
    create_src_index
    create_index_css
    create_app_js
    create_tailwind_config
    create_postcss_config
    create_gitignore
    create_start_script
    create_readme
    
    log_info "Installation des dépendances..."
    install_dependencies
    
    echo ""
    echo "🎉 Installation terminée avec succès !"
    echo ""
    log_info "Prochaines étapes :"
    echo "1. 📋 Copiez le code complet depuis l'artifact Claude dans src/App.js"
    echo "2. 🚀 Démarrez le dashboard :"
    echo "   cd $DASHBOARD_DIR"
    echo "   npm start"
    echo ""
    echo "3. 🌐 Ouvrez http://localhost:3000"
    echo ""
    log_success "SynapseGrid Dashboard prêt ! 🧠⚡"
}

# Exécuter le script principal
main "$@"


#!/bin/bash

# Script pour corriger l'erreur de syntaxe dans App.js

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Correction de l'erreur de syntaxe du Dashboard ===${NC}"

# 1. Vérifier si la sauvegarde existe
if [ -f "./dashboard/src/App.js.backup" ]; then
    echo -e "\n${GREEN}Restauration depuis la sauvegarde...${NC}"
    cp ./dashboard/src/App.js.backup ./dashboard/src/App.js
    echo -e "${GREEN}✓ App.js restauré${NC}"
else
    echo -e "\n${RED}Pas de sauvegarde trouvée !${NC}"
    echo -e "${YELLOW}Le fichier App.js semble avoir été modifié par le patch et contient des erreurs.${NC}"
fi

# 2. Vérifier la ligne problématique
echo -e "\n${YELLOW}Vérification de la zone problématique (lignes 110-120) :${NC}"
sed -n '110,120p' ./dashboard/src/App.js

# 3. Proposer des options
echo -e "\n${GREEN}Options disponibles :${NC}"
echo "1. Restaurer le fichier original (recommandé)"
echo "2. Essayer de corriger manuellement l'erreur"
echo "3. Créer un App.js minimal fonctionnel pour tester l'API"
echo -n "Votre choix (1, 2 ou 3) : "
read choice

case $choice in
    1)
        echo -e "\n${GREEN}Restauration du fichier original...${NC}"
        if [ -f "./dashboard/src/App.js.backup" ]; then
            cp ./dashboard/src/App.js.backup ./dashboard/src/App.js
            echo -e "${GREEN}✓ Fichier restauré${NC}"
        else
            echo -e "${RED}Erreur : Pas de fichier de sauvegarde${NC}"
        fi
        ;;
    
    2)
        echo -e "\n${GREEN}Tentative de correction automatique...${NC}"
        # Chercher et corriger les problèmes de syntaxe courants
        # Corriger les virgules manquantes ou en trop
        sed -i.fix 's/connections: 3,$/connections: 3/' ./dashboard/src/App.js
        sed -i.fix 's/y: 20$/y: 20/' ./dashboard/src/App.js
        echo -e "${GREEN}✓ Corrections appliquées${NC}"
        echo -e "${YELLOW}Vérifiez si l'erreur persiste${NC}"
        ;;
    
    3)
        echo -e "\n${GREEN}Création d'un App.js minimal avec connexion API...${NC}"
        cat > ./dashboard/src/App.js.minimal << 'EOF'
import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [apiStatus, setApiStatus] = useState('disconnected');
  const [stats, setStats] = useState({
    totalNodes: 0,
    activeJobs: 0,
    completedJobs: 0
  });

  useEffect(() => {
    // Test de connexion API
    const checkAPI = async () => {
      try {
        const response = await fetch('http://localhost:8080/health');
        const data = await response.json();
        setApiStatus(data.status === 'healthy' ? 'connected' : 'error');
      } catch (error) {
        console.error('API Error:', error);
        setApiStatus('error');
      }
    };

    checkAPI();
    const interval = setInterval(checkAPI, 5000);
    return () => clearInterval(interval);
  }, []);

  const submitTestJob = async () => {
    try {
      const response = await fetch('http://localhost:8080/submit', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer test-token',
          'X-Client-ID': 'dashboard'
        },
        body: JSON.stringify({
          model_name: 'resnet50',
          input_data: { image: 'test.jpg' }
        })
      });
      const data = await response.json();
      console.log('Job submitted:', data);
      alert(`Job submitted: ${data.job_id}`);
    } catch (error) {
      console.error('Submit error:', error);
      alert('Error submitting job');
    }
  };

  return (
    <div className="App" style={{ padding: '20px' }}>
      <h1>SynapseGrid Dashboard (Minimal)</h1>
      
      <div style={{ marginBottom: '20px' }}>
        <h2>API Status: 
          <span style={{ color: apiStatus === 'connected' ? 'green' : 'red' }}>
            {apiStatus}
          </span>
        </h2>
      </div>

      <div style={{ marginBottom: '20px' }}>
        <h3>Stats</h3>
        <p>Total Nodes: {stats.totalNodes}</p>
        <p>Active Jobs: {stats.activeJobs}</p>
        <p>Completed Jobs: {stats.completedJobs}</p>
      </div>

      <button onClick={submitTestJob} style={{ padding: '10px 20px' }}>
        Submit Test Job
      </button>
    </div>
  );
}

export default App;
EOF
        echo -e "${GREEN}✓ App.js minimal créé${NC}"
        echo -e "${YELLOW}Pour l'utiliser : cp ./dashboard/src/App.js.minimal ./dashboard/src/App.js${NC}"
        ;;
esac

# 4. Instructions finales
echo -e "\n${GREEN}=== Instructions ===${NC}"
echo "1. Redémarrez le dashboard :"
echo "   cd dashboard && npm start"
echo ""
echo "2. Si l'erreur persiste, utilisez le fichier minimal :"
echo "   cp ./dashboard/src/App.js.minimal ./dashboard/src/App.js"
echo ""
echo "3. Le dashboard minimal permet de :"
echo "   - Voir le statut de l'API"
echo "   - Soumettre des jobs de test"
echo "   - Voir les stats de base"

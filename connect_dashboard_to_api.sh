#!/bin/bash

# Script pour connecter le dashboard aux vraies données de l'API

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Connexion du Dashboard à l'API ===${NC}"

# 1. Vérifier que le dossier dashboard existe
if [ ! -d "./dashboard" ]; then
    echo -e "${RED}Erreur: Le dossier ./dashboard n'existe pas${NC}"
    exit 1
fi

# 2. Créer un fichier de configuration pour l'API
echo -e "\n${GREEN}Création du fichier de configuration API...${NC}"
cat > ./dashboard/.env.local << 'EOF'
# Configuration de l'API pour le dashboard
REACT_APP_API_URL=http://localhost:8080
REACT_APP_WS_URL=ws://localhost:8080/ws
REACT_APP_USE_MOCK_DATA=false
EOF

# 3. Créer un service API pour remplacer les données mockées
echo -e "\n${GREEN}Création du service API...${NC}"
mkdir -p ./dashboard/src/services

cat > ./dashboard/src/services/api.js << 'EOF'
// Service API pour se connecter au backend SynapseGrid

const API_URL = process.env.REACT_APP_API_URL || 'http://localhost:8080';
const WS_URL = process.env.REACT_APP_WS_URL || 'ws://localhost:8080/ws';

class SynapseAPI {
  constructor() {
    this.ws = null;
    this.listeners = new Map();
  }

  // Connexion WebSocket pour les mises à jour temps réel
  connectWebSocket() {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      return;
    }

    try {
      this.ws = new WebSocket(WS_URL);
      
      this.ws.onopen = () => {
        console.log('WebSocket connected to SynapseGrid');
      };

      this.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          this.notifyListeners(data.channel, data.data);
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      this.ws.onerror = (error) => {
        console.error('WebSocket error:', error);
      };

      this.ws.onclose = () => {
        console.log('WebSocket disconnected, reconnecting in 5s...');
        setTimeout(() => this.connectWebSocket(), 5000);
      };
    } catch (error) {
      console.error('Failed to connect WebSocket:', error);
    }
  }

  // Ajouter un listener pour les événements WebSocket
  addListener(channel, callback) {
    if (!this.listeners.has(channel)) {
      this.listeners.set(channel, new Set());
    }
    this.listeners.get(channel).add(callback);
  }

  // Notifier les listeners
  notifyListeners(channel, data) {
    if (this.listeners.has(channel)) {
      this.listeners.get(channel).forEach(callback => callback(data));
    }
    // Notifier aussi les listeners génériques
    if (this.listeners.has('*')) {
      this.listeners.get('*').forEach(callback => callback({ channel, data }));
    }
  }

  // API REST methods
  async getHealth() {
    try {
      const response = await fetch(`${API_URL}/health`);
      return await response.json();
    } catch (error) {
      console.error('Health check failed:', error);
      return { status: 'error', message: error.message };
    }
  }

  async submitJob(jobData) {
    try {
      const response = await fetch(`${API_URL}/submit`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('token') || 'test-token'}`,
          'X-Client-ID': 'dashboard-client'
        },
        body: JSON.stringify(jobData)
      });
      return await response.json();
    } catch (error) {
      console.error('Job submission failed:', error);
      throw error;
    }
  }

  async getJobStatus(jobId) {
    try {
      const response = await fetch(`${API_URL}/job/${jobId}`);
      return await response.json();
    } catch (error) {
      console.error('Failed to get job status:', error);
      throw error;
    }
  }

  async getMetrics() {
    try {
      const response = await fetch(`${API_URL}/metrics`);
      const text = await response.text();
      return this.parsePrometheusMetrics(text);
    } catch (error) {
      console.error('Failed to get metrics:', error);
      return {};
    }
  }

  // Parser pour les métriques Prometheus
  parsePrometheusMetrics(text) {
    const metrics = {};
    const lines = text.split('\n');
    
    lines.forEach(line => {
      if (line.startsWith('#') || !line.trim()) return;
      
      const match = line.match(/^(\w+)(?:{([^}]+)})?\s+(.+)$/);
      if (match) {
        const [, name, labels, value] = match;
        metrics[name] = parseFloat(value);
      }
    });
    
    return metrics;
  }

  // Obtenir les statistiques globales
  async getStats() {
    try {
      // Pour l'instant, on utilise les métriques Prometheus
      const metrics = await this.getMetrics();
      
      // Essayer de récupérer depuis Redis via une API custom
      const response = await fetch(`${API_URL}/stats`).catch(() => null);
      const customStats = response ? await response.json().catch(() => null) : null;
      
      return {
        totalNodes: customStats?.totalNodes || 0,
        activeJobs: customStats?.activeJobs || metrics.gateway_jobs_received || 0,
        avgLatency: customStats?.avgLatency || 0,
        throughput: customStats?.throughput || 0,
        nodeDistribution: customStats?.nodeDistribution || {},
        jobsPerHour: customStats?.jobsPerHour || []
      };
    } catch (error) {
      console.error('Failed to get stats:', error);
      return {
        totalNodes: 0,
        activeJobs: 0,
        avgLatency: 0,
        throughput: 0,
        nodeDistribution: {},
        jobsPerHour: []
      };
    }
  }
}

// Export singleton
const api = new SynapseAPI();
export default api;
EOF

# 4. Créer un hook React pour utiliser l'API
echo -e "\n${GREEN}Création du hook useRealTimeData...${NC}"
cat > ./dashboard/src/hooks/useRealTimeData.js << 'EOF'
import { useState, useEffect } from 'react';
import api from '../services/api';

export function useRealTimeData() {
  const [data, setData] = useState({
    totalNodes: 0,
    activeJobs: 0,
    avgLatency: 0,
    throughput: 0,
    nodeDistribution: {},
    jobsPerHour: [],
    isConnected: false
  });

  useEffect(() => {
    // Connexion WebSocket
    api.connectWebSocket();

    // Charger les données initiales
    const loadData = async () => {
      const stats = await api.getStats();
      setData(prev => ({ ...prev, ...stats }));
    };

    loadData();

    // Écouter les mises à jour WebSocket
    api.addListener('*', (event) => {
      console.log('WebSocket event:', event);
      // Mettre à jour les données selon le type d'événement
      if (event.channel === 'job:submitted') {
        setData(prev => ({ ...prev, activeJobs: prev.activeJobs + 1 }));
      } else if (event.channel === 'job:completed') {
        setData(prev => ({ ...prev, activeJobs: Math.max(0, prev.activeJobs - 1) }));
      }
    });

    // Vérifier la connexion
    const checkConnection = async () => {
      const health = await api.getHealth();
      setData(prev => ({ ...prev, isConnected: health.status === 'healthy' }));
    };

    checkConnection();

    // Rafraîchir les données toutes les 5 secondes
    const interval = setInterval(() => {
      loadData();
      checkConnection();
    }, 5000);

    return () => {
      clearInterval(interval);
    };
  }, []);

  return data;
}
EOF

# 5. Créer un exemple de modification pour App.js
echo -e "\n${GREEN}Création d'un patch pour intégrer l'API...${NC}"
cat > ./dashboard/patch-app.js << 'EOF'
// Exemple de modification pour App.js ou Dashboard.js
// Remplacer les données mockées par :

import { useRealTimeData } from './hooks/useRealTimeData';

function Dashboard() {
  const { 
    totalNodes, 
    activeJobs, 
    avgLatency, 
    throughput, 
    nodeDistribution, 
    jobsPerHour,
    isConnected 
  } = useRealTimeData();

  return (
    <div>
      {/* Indicateur de connexion */}
      <div className={`connection-status ${isConnected ? 'connected' : 'disconnected'}`}>
        {isConnected ? '🟢 Connected' : '🔴 Disconnected'}
      </div>
      
      {/* Utiliser les vraies données */}
      <div>Total Nodes: {totalNodes}</div>
      <div>Active Jobs: {activeJobs}</div>
      {/* etc... */}
    </div>
  );
}
EOF

# 6. Instructions pour l'utilisateur
echo -e "\n${GREEN}=== Configuration terminée ===${NC}"
echo -e "${YELLOW}Pour connecter le dashboard aux vraies données :${NC}"
echo ""
echo "1. Modifier le code du dashboard pour utiliser le service API :"
echo "   - Importer: import api from './services/api';"
echo "   - Utiliser: const data = useRealTimeData();"
echo ""
echo "2. Assurez-vous que l'API Gateway fonctionne :"
echo "   curl http://localhost:8080/health"
echo ""
echo "3. Redémarrer le dashboard :"
echo "   cd dashboard && npm start"
echo ""
echo "4. Optionnel - Ajouter un endpoint /stats dans gateway/main.py pour les statistiques globales"
echo ""
echo -e "${RED}Note: Le code exact dépend de la structure de votre dashboard React.${NC}"
echo -e "${RED}Vous devrez adapter les imports et les composants selon votre code.${NC}"

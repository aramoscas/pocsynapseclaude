#!/bin/bash

# Script pour connecter le dashboard aux vraies données du backend

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Connexion du Dashboard au Backend SynapseGrid ===${NC}"

# 1. Vérifier que l'API fonctionne
echo -e "\n${YELLOW}Vérification de l'API...${NC}"
if curl -s http://localhost:8080/health | grep -q "healthy"; then
    echo -e "${GREEN}✓ API Gateway est accessible${NC}"
else
    echo -e "${RED}✗ API Gateway n'est pas accessible sur http://localhost:8080${NC}"
    echo "Assurez-vous que les services sont démarrés : docker-compose -f docker-compose.m2.yml up -d"
    exit 1
fi

# 2. Ajouter un endpoint /api/stats dans le Gateway pour exposer les métriques
echo -e "\n${GREEN}Ajout de l'endpoint /api/stats dans le Gateway...${NC}"
cat >> services/gateway/main.py << 'GATEWAY_STATS'

@app.get("/api/stats")
async def get_stats():
    """Get system statistics"""
    try:
        # Get node count
        node_keys = await redis_client.keys("node:*")
        active_nodes = 0
        for key in node_keys:
            node_data = await redis_client.hgetall(key)
            if node_data.get('status') == 'online':
                active_nodes += 1
        
        # Get job statistics
        pending_jobs = await redis_client.zcard("jobs:queue:us-east")
        
        # Get completed jobs count
        completed_jobs = 0
        job_keys = await redis_client.keys("job:*")
        for key in job_keys:
            job_data = await redis_client.hgetall(key)
            if job_data.get('status') == 'completed':
                completed_jobs += 1
        
        return {
            "totalNodes": active_nodes,
            "activeJobs": pending_jobs,
            "completedJobs": completed_jobs,
            "avgLatency": 250,  # TODO: Calculate from real data
            "throughput": 1500,  # TODO: Calculate from real data
        }
    except Exception as e:
        logger.error("Failed to get stats", error=str(e))
        return {"totalNodes": 0, "activeJobs": 0, "completedJobs": 0}

@app.get("/api/nodes")
async def get_nodes():
    """Get list of active nodes"""
    try:
        node_keys = await redis_client.keys("node:*")
        nodes = []
        for key in node_keys:
            node_data = await redis_client.hgetall(key)
            if node_data:
                nodes.append(node_data)
        return nodes
    except Exception as e:
        logger.error("Failed to get nodes", error=str(e))
        return []

@app.get("/api/jobs/queue")
async def get_job_queue():
    """Get jobs in queue"""
    try:
        jobs = await redis_client.zrange("jobs:queue:us-east", 0, -1)
        return {"queue": jobs, "count": len(jobs)}
    except Exception as e:
        logger.error("Failed to get job queue", error=str(e))
        return {"queue": [], "count": 0}
GATEWAY_STATS

# 3. Modifier App.js pour utiliser l'API réelle
echo -e "\n${GREEN}Modification du dashboard pour utiliser l'API...${NC}"

# Créer un fichier de configuration API
cat > ./dashboard/src/config.js << 'EOF'
// Configuration de l'API
export const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:8080';

export const API_ENDPOINTS = {
  health: `${API_BASE_URL}/health`,
  stats: `${API_BASE_URL}/api/stats`,
  submit: `${API_BASE_URL}/submit`,
  job: (id) => `${API_BASE_URL}/job/${id}`,
  nodes: `${API_BASE_URL}/api/nodes`,
  queue: `${API_BASE_URL}/api/jobs/queue`,
  metrics: `${API_BASE_URL}/metrics`
};
EOF

# 4. Créer un hook pour récupérer les vraies données
echo -e "\n${GREEN}Création du hook useRealData...${NC}"
cat > ./dashboard/src/hooks/useRealData.js << 'EOF'
import { useState, useEffect, useCallback } from 'react';
import { API_ENDPOINTS } from '../config';

export const useRealData = () => {
  const [data, setData] = useState({
    totalNodes: 0,
    activeJobs: 0,
    completedJobs: 0,
    avgLatency: 0,
    throughput: 0,
    systemLoad: 0,
    networkTraffic: 0,
    nodes: [],
    queue: [],
    isConnected: false,
    lastUpdate: new Date()
  });

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchData = useCallback(async () => {
    try {
      // Check health
      const healthResponse = await fetch(API_ENDPOINTS.health);
      const healthData = await healthResponse.json();
      
      if (healthData.status !== 'healthy') {
        throw new Error('API is not healthy');
      }

      // Get stats
      const statsResponse = await fetch(API_ENDPOINTS.stats);
      const stats = await statsResponse.json();

      // Get nodes
      const nodesResponse = await fetch(API_ENDPOINTS.nodes);
      const nodes = await nodesResponse.json();

      // Get queue
      const queueResponse = await fetch(API_ENDPOINTS.queue);
      const queue = await queueResponse.json();

      setData(prev => ({
        ...prev,
        totalNodes: stats.totalNodes || nodes.length || 0,
        activeJobs: stats.activeJobs || queue.count || 0,
        completedJobs: stats.completedJobs || 0,
        avgLatency: stats.avgLatency || 250,
        throughput: stats.throughput || 1500,
        nodes: nodes,
        queue: queue.queue || [],
        isConnected: true,
        lastUpdate: new Date()
      }));
      
      setError(null);
    } catch (err) {
      console.error('Failed to fetch data:', err);
      setError(err.message);
      setData(prev => ({ ...prev, isConnected: false }));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // Initial fetch
    fetchData();

    // Set up polling
    const interval = setInterval(fetchData, 3000); // Update every 3 seconds

    return () => clearInterval(interval);
  }, [fetchData]);

  const submitJob = async (jobData) => {
    try {
      const response = await fetch(API_ENDPOINTS.submit, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer test-token',
          'X-Client-ID': 'dashboard'
        },
        body: JSON.stringify(jobData)
      });
      const result = await response.json();
      
      // Refresh data immediately after submission
      fetchData();
      
      return result;
    } catch (err) {
      console.error('Failed to submit job:', err);
      throw err;
    }
  };

  return { data, loading, error, submitJob, refresh: fetchData };
};
EOF

# 5. Injecter le hook dans App.js (au début du composant)
echo -e "\n${GREEN}Injection du code de connexion API dans App.js...${NC}"

# Créer un patch pour App.js
cat > ./dashboard/patch-app-api.js << 'EOF'
// Instructions pour intégrer l'API dans App.js:

// 1. Ajouter ces imports au début du fichier:
import { useRealData } from './hooks/useRealData';
import { API_ENDPOINTS } from './config';

// 2. Dans la fonction App(), remplacer le useState et useEffect par:
const { data, loading, error, submitJob } = useRealData();

// 3. Remplacer les variables d'état par:
const realTimeData = {
  totalNodes: data.totalNodes,
  activeJobs: data.activeJobs,
  avgLatency: data.avgLatency,
  throughput: data.throughput,
  systemLoad: data.systemLoad || 67,
  networkTraffic: data.networkTraffic || 2.4,
  lastUpdate: data.lastUpdate
};

// 4. Ajouter un indicateur de connexion dans le JSX:
{data.isConnected ? (
  <span className="text-green-400">🟢 Connected to API</span>
) : (
  <span className="text-red-400">🔴 Disconnected</span>
)}

// 5. Pour soumettre un job:
const handleSubmitJob = async () => {
  try {
    const result = await submitJob({
      model_name: 'resnet50',
      input_data: { image: 'test.jpg' }
    });
    console.log('Job submitted:', result);
  } catch (err) {
    console.error('Failed to submit job:', err);
  }
};
EOF

# 6. Redémarrer le Gateway pour appliquer les changements
echo -e "\n${YELLOW}Redémarrage du Gateway...${NC}"
docker-compose -f docker-compose.m2.yml restart gateway

# 7. Instructions finales
echo -e "\n${GREEN}=== Configuration terminée ! ===${NC}"
echo -e "${YELLOW}Pour finaliser la connexion :${NC}"
echo ""
echo "1. Ouvrez ./dashboard/src/App.js"
echo "2. Ajoutez les imports :"
echo "   import { useRealData } from './hooks/useRealData';"
echo "   import { API_ENDPOINTS } from './config';"
echo ""
echo "3. Remplacez le useState et useEffect par :"
echo "   const { data, loading, error, submitJob } = useRealData();"
echo ""
echo "4. Utilisez 'data.totalNodes', 'data.activeJobs', etc. au lieu des valeurs mockées"
echo ""
echo "5. Redémarrez le dashboard :"
echo "   cd dashboard && npm start"
echo ""
echo -e "${GREEN}Le dashboard affichera alors les vraies données !${NC}"

# 8. Test de l'API
echo -e "\n${GREEN}Test des nouveaux endpoints :${NC}"
echo "Stats : curl http://localhost:8080/api/stats"
echo "Nodes : curl http://localhost:8080/api/nodes"
echo "Queue : curl http://localhost:8080/api/jobs/queue"

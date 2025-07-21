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

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

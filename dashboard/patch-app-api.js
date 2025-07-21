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

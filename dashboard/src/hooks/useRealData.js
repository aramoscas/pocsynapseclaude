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

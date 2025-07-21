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

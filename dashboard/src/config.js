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

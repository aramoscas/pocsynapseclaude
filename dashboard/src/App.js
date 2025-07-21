import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { Activity, Cpu, Globe, Zap, Server, TrendingUp } from 'lucide-react';
import './App.css';

function App() {
  const [metrics, setMetrics] = useState({
    totalJobs: 0,
    activeNodes: 0,
    avgLatency: 0,
    totalRevenue: 0
  });

  const [realtimeData, setRealtimeData] = useState([]);

  useEffect(() => {
    // Simulate real-time data for POC
    const interval = setInterval(() => {
      const now = new Date();
      setRealtimeData(prev => {
        const newData = [...prev, {
          timestamp: now.toLocaleTimeString(),
          jobs: Math.floor(Math.random() * 100) + 50,
          latency: Math.floor(Math.random() * 200) + 200,
          nodes: Math.floor(Math.random() * 10) + 20
        }];
        return newData.slice(-20);
      });

      setMetrics({
        totalJobs: Math.floor(Math.random() * 1000) + 500,
        activeNodes: Math.floor(Math.random() * 50) + 25,
        avgLatency: Math.floor(Math.random() * 100) + 250,
        totalRevenue: (Math.random() * 1000 + 500).toFixed(2)
      });
    }, 2000);

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="dashboard">
      <header className="dashboard-header">
        <div className="header-content">
          <div className="logo">
            <Activity className="logo-icon" />
            <h1>SynapseGrid</h1>
            <span className="version">v1.0 POC</span>
          </div>
          
          <div className="header-stats">
            <div className="stat-card">
              <Server className="stat-icon" />
              <div>
                <div className="stat-value">{metrics.activeNodes}</div>
                <div className="stat-label">Active Nodes</div>
              </div>
            </div>
            
            <div className="stat-card">
              <Zap className="stat-icon" />
              <div>
                <div className="stat-value">{metrics.totalJobs}</div>
                <div className="stat-label">Jobs Processed</div>
              </div>
            </div>
            
            <div className="stat-card">
              <TrendingUp className="stat-icon" />
              <div>
                <div className="stat-value">{metrics.avgLatency}ms</div>
                <div className="stat-label">Avg Latency</div>
              </div>
            </div>
            
            <div className="stat-card">
              <Globe className="stat-icon" />
              <div>
                <div className="stat-value">${metrics.totalRevenue}</div>
                <div className="stat-label">Revenue</div>
              </div>
            </div>
          </div>
        </div>
      </header>

      <main className="dashboard-main">
        <div className="dashboard-grid">
          <div className="card">
            <div className="card-header">
              <h3>Real-time Performance</h3>
            </div>
            <div className="chart-container">
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={realtimeData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#333" />
                  <XAxis dataKey="timestamp" stroke="#666" />
                  <YAxis stroke="#666" />
                  <Tooltip 
                    contentStyle={{ 
                      backgroundColor: '#1a1a2e', 
                      border: '1px solid #333',
                      borderRadius: '8px'
                    }} 
                  />
                  <Line 
                    type="monotone" 
                    dataKey="latency" 
                    stroke="#00d4ff" 
                    strokeWidth={2}
                    name="Latency (ms)"
                  />
                  <Line 
                    type="monotone" 
                    dataKey="jobs" 
                    stroke="#00ff88" 
                    strokeWidth={2}
                    name="Jobs"
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="card">
            <div className="card-header">
              <h3>Network Status</h3>
            </div>
            <div className="status-grid">
              <div className="status-item">
                <div className="status-label">Network Health</div>
                <div className="status-value good">Excellent</div>
              </div>
              <div className="status-item">
                <div className="status-label">Global Coverage</div>
                <div className="status-value">4 Regions</div>
              </div>
              <div className="status-item">
                <div className="status-label">Uptime</div>
                <div className="status-value good">99.8%</div>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;

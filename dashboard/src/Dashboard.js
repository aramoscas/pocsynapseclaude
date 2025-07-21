// Dashboard.js - Version simplifiée pour le script
// Remplacez ce fichier par le composant Dashboard complet fourni précédemment

import React, { useState, useEffect } from 'react';
import { Activity, Server, Globe, Clock, TrendingUp, Wifi, WifiOff } from 'lucide-react';

const Dashboard = () => {
  const [wsConnected, setWsConnected] = useState(false);
  const [metrics, setMetrics] = useState({
    totalNodes: 0,
    activeJobs: 0,
    avgLatency: 0,
    throughput: 0,
  });

  useEffect(() => {
    // Connection WebSocket
    const ws = new WebSocket('ws://localhost:8080/ws');
    
    ws.onopen = () => {
      setWsConnected(true);
      ws.send(JSON.stringify({
        type: 'subscribe',
        channels: ['nodes', 'jobs', 'metrics']
      }));
    };

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'metrics_update') {
        setMetrics(data.payload);
      }
    };

    ws.onerror = () => setWsConnected(false);
    ws.onclose = () => setWsConnected(false);

    return () => ws.close();
  }, []);

  return (
    <div className="min-h-screen bg-gray-900 text-white p-8">
      <div className="max-w-7xl mx-auto">
        <header className="mb-8">
          <h1 className="text-4xl font-bold flex items-center">
            <Globe className="mr-3" /> SynapseGrid Dashboard
          </h1>
          <p className="text-gray-400 mt-2">Decentralized AI Infrastructure</p>
          <div className="mt-4 flex items-center">
            {wsConnected ? (
              <><Wifi className="text-green-500 mr-2" /> Connected</>
            ) : (
              <><WifiOff className="text-red-500 mr-2" /> Disconnected</>
            )}
          </div>
        </header>

        <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
          <MetricCard title="Active Nodes" value={metrics.totalNodes} icon={<Server />} />
          <MetricCard title="Running Jobs" value={metrics.activeJobs} icon={<Activity />} />
          <MetricCard title="Avg Latency" value={`${metrics.avgLatency}ms`} icon={<Clock />} />
          <MetricCard title="Throughput" value={`${metrics.throughput}/s`} icon={<TrendingUp />} />
        </div>

        <div className="mt-8 bg-gray-800 rounded-lg p-6">
          <h2 className="text-xl font-semibold mb-4">System Status</h2>
          <p>Dashboard connected to Gateway WebSocket endpoint.</p>
          <p className="text-sm text-gray-400 mt-2">
            Full dashboard component available in the main artifact.
          </p>
        </div>
      </div>
    </div>
  );
};

const MetricCard = ({ title, value, icon }) => (
  <div className="bg-gray-800 rounded-lg p-6">
    <div className="flex items-center justify-between mb-2">
      <span className="text-gray-400">{title}</span>
      <div className="text-blue-500">{icon}</div>
    </div>
    <div className="text-3xl font-bold">{value}</div>
  </div>
);

export default Dashboard;

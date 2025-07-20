#!/bin/bash

echo "🔧 Fixing Docker Compose configuration..."

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Redis Cluster for coordination
  redis-master:
    image: redis:7-alpine
    container_name: redis-master
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - synapse_network

  # Gateway Service
  gateway:
    build:
      context: .
      dockerfile: services/gateway/Dockerfile
    container_name: synapse-gateway
    ports:
      - "8080:8080"
      - "50051:50051"
    environment:
      - REDIS_HOST=redis-master
      - REDIS_PORT=6379
      - POSTGRES_HOST=postgres
      - POSTGRES_DB=synapsegrid
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=synapse123
    depends_on:
      - redis-master
      - postgres
    networks:
      - synapse_network
    volumes:
      - ./logs:/app/logs

  # Dispatcher Service (single instance)
  dispatcher:
    build:
      context: .
      dockerfile: services/dispatcher/Dockerfile
    container_name: synapse-dispatcher
    environment:
      - REDIS_HOST=redis-master
      - REDIS_PORT=6379
      - POSTGRES_HOST=postgres
      - POSTGRES_DB=synapsegrid
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=synapse123
    depends_on:
      - redis-master
      - postgres
    networks:
      - synapse_network
    volumes:
      - ./logs:/app/logs

  # Aggregator Service
  aggregator:
    build:
      context: .
      dockerfile: services/aggregator/Dockerfile
    container_name: synapse-aggregator
    ports:
      - "50052:50052"
    environment:
      - REDIS_HOST=redis-master
      - REDIS_PORT=6379
      - POSTGRES_HOST=postgres
      - POSTGRES_DB=synapsegrid
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=synapse123
    depends_on:
      - redis-master
      - postgres
    networks:
      - synapse_network
    volumes:
      - ./logs:/app/logs

  # Node Simulator 1
  node-simulator-1:
    build:
      context: .
      dockerfile: services/node/Dockerfile
    container_name: synapse-node-1
    environment:
      - GATEWAY_HOST=gateway
      - GATEWAY_PORT=50051
      - NODE_ID=sim-node-001
      - NODE_REGION=eu-west-1
      - GPU_TYPE=RTX3080
      - GPU_MEMORY=10240
    depends_on:
      - gateway
    networks:
      - synapse_network

  # Node Simulator 2
  node-simulator-2:
    build:
      context: .
      dockerfile: services/node/Dockerfile
    container_name: synapse-node-2
    environment:
      - GATEWAY_HOST=gateway
      - GATEWAY_PORT=50051
      - NODE_ID=sim-node-002
      - NODE_REGION=eu-west-1
      - GPU_TYPE=RTX3060
      - GPU_MEMORY=8192
    depends_on:
      - gateway
    networks:
      - synapse_network

  # Node Simulator 3
  node-simulator-3:
    build:
      context: .
      dockerfile: services/node/Dockerfile
    container_name: synapse-node-3
    environment:
      - GATEWAY_HOST=gateway
      - GATEWAY_PORT=50051
      - NODE_ID=sim-node-003
      - NODE_REGION=us-east-1
      - GPU_TYPE=A100
      - GPU_MEMORY=40960
    depends_on:
      - gateway
    networks:
      - synapse_network

  # PostgreSQL Database
  postgres:
    image: postgres:15-alpine
    container_name: synapse-postgres
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_DB=synapsegrid
      - POSTGRES_USER=synapse
      - POSTGRES_PASSWORD=synapse123
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./sql/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - synapse_network

  # Dashboard/Frontend
  dashboard:
    build:
      context: .
      dockerfile: services/dashboard/Dockerfile
    container_name: synapse-dashboard
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://gateway:8080
    depends_on:
      - gateway
    networks:
      - synapse_network

  # Monitoring with Prometheus
  prometheus:
    image: prom/prometheus:latest
    container_name: synapse-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    networks:
      - synapse_network

  # Grafana for dashboards
  grafana:
    image: grafana/grafana:latest
    container_name: synapse-grafana
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      - prometheus
    networks:
      - synapse_network

volumes:
  redis_data:
  postgres_data:
  prometheus_data:
  grafana_data:

networks:
  synapse_network:
    driver: bridge
EOF

echo "✅ Docker Compose fixed!"
echo ""
echo "Changes made:"
echo "  - Removed deploy.replicas conflicts"
echo "  - Created 3 separate node simulators"
echo "  - Fixed container naming"
echo "  - Simplified Redis setup"
echo ""
echo "Now run:"
echo "  make start"

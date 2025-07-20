#!/bin/bash

# Fix Makefile tabs issue

echo "🔧 Fixing Makefile tabs issue..."

cat > Makefile << 'EOF'
.PHONY: help build start stop logs test clean setup proto

help:
	@echo "SynapseGrid POC - Available commands:"
	@echo "  setup     - Initial setup"
	@echo "  proto     - Generate protobuf files"
	@echo "  build     - Build all Docker images"  
	@echo "  start     - Start all services"
	@echo "  stop      - Stop all services"
	@echo "  restart   - Restart all services"
	@echo "  logs      - Show logs"
	@echo "  test      - Run tests"
	@echo "  clean     - Clean up"
	@echo "  monitor   - Open dashboards"

setup:
	@echo "Setting up SynapseGrid POC..."
	@chmod +x scripts/*.sh 2>/dev/null || true
	@$(MAKE) create-configs

create-configs:
	@echo "Creating configuration files..."
	@mkdir -p config/grafana/dashboards config/grafana/datasources
	@echo 'sentinel monitor mymaster redis-master 6379 1' > config/sentinel.conf
	@echo 'sentinel down-after-milliseconds mymaster 5000' >> config/sentinel.conf
	@echo 'global' > config/haproxy.cfg
	@echo '    daemon' >> config/haproxy.cfg
	@echo '    maxconn 4096' >> config/haproxy.cfg
	@echo 'defaults' >> config/haproxy.cfg
	@echo '    mode http' >> config/haproxy.cfg
	@echo '    timeout connect 5000ms' >> config/haproxy.cfg
	@echo 'frontend api_frontend' >> config/haproxy.cfg
	@echo '    bind *:80' >> config/haproxy.cfg
	@echo '    default_backend api_backend' >> config/haproxy.cfg
	@echo 'backend api_backend' >> config/haproxy.cfg
	@echo '    balance roundrobin' >> config/haproxy.cfg
	@echo '    server gateway1 gateway:8080 check' >> config/haproxy.cfg
	@echo 'stats enable' >> config/haproxy.cfg
	@echo 'stats uri /stats' >> config/haproxy.cfg
	@echo 'global:' > config/prometheus.yml
	@echo '  scrape_interval: 15s' >> config/prometheus.yml
	@echo 'scrape_configs:' >> config/prometheus.yml
	@echo '  - job_name: synapse-services' >> config/prometheus.yml
	@echo '    static_configs:' >> config/prometheus.yml
	@echo '      - targets: [gateway:8000, dispatcher:8001]' >> config/prometheus.yml
	@echo 'apiVersion: 1' > config/grafana/datasources/prometheus.yml
	@echo 'datasources:' >> config/grafana/datasources/prometheus.yml
	@echo '  - name: Prometheus' >> config/grafana/datasources/prometheus.yml
	@echo '    type: prometheus' >> config/grafana/datasources/prometheus.yml
	@echo '    access: proxy' >> config/grafana/datasources/prometheus.yml
	@echo '    url: http://prometheus:9090' >> config/grafana/datasources/prometheus.yml

proto:
	@echo "Generating protobuf files..."
	@mkdir -p protos
	@echo 'syntax = "proto3";' > protos/synapse.proto
	@echo 'package synapse;' >> protos/synapse.proto
	@echo 'service SynapseGateway {' >> protos/synapse.proto
	@echo '    rpc SubmitJob(JobSubmissionRequest) returns (JobResponse);' >> protos/synapse.proto
	@echo '}' >> protos/synapse.proto
	@echo 'message JobSubmissionRequest {' >> protos/synapse.proto
	@echo '    string client_id = 1;' >> protos/synapse.proto
	@echo '    string model_name = 2;' >> protos/synapse.proto
	@echo '}' >> protos/synapse.proto
	@echo 'message JobResponse {' >> protos/synapse.proto
	@echo '    string job_id = 1;' >> protos/synapse.proto
	@echo '    string status = 2;' >> protos/synapse.proto
	@echo '}' >> protos/synapse.proto

build:
	@echo "Building Docker images..."
	docker-compose build --parallel

start:
	@echo "Starting SynapseGrid POC..."
	docker-compose up -d
	@echo "Services starting..."

stop:
	@echo "Stopping services..."
	docker-compose down

restart:
	@$(MAKE) stop
	@$(MAKE) start

status:
	@echo "=== Service Status ==="
	@docker-compose ps

logs:
	docker-compose logs -f --tail=100

test:
	@echo "Running API tests..."
	@./scripts/test_api.sh

clean:
	@echo "Cleaning up..."
	docker-compose down -v --remove-orphans
	docker system prune -f

monitor:
	@echo "Monitoring dashboards:"
	@echo "  Prometheus: http://localhost:9090"
	@echo "  Grafana: http://localhost:3001 (admin/admin123)"
	@echo "  Dashboard: http://localhost:3000"

submit-job:
	@echo "Submitting test job..."
	@curl -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: test-client" \
		-d '{"model_name": "resnet50", "input_data": {"image": "test.jpg"}, "priority": 5}'

health:
	@echo "Checking system health..."
	@curl -s http://localhost:8080/health
EOF

echo "✅ Makefile fixed! Now you can run:"
echo "   make setup"
echo "   make start"

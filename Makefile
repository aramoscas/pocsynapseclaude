# Makefile for SynapseGrid POC - Enhanced Version

.PHONY: help setup start stop restart logs test clean proto build-images

# Default target
help:
	@echo "SynapseGrid POC - Enhanced Commands:"
	@echo ""
	@echo "🚀 CORE COMMANDS:"
	@echo "  setup          - Setup development environment"
	@echo "  build-images   - Build all Docker images"
	@echo "  start          - Start all Docker services"
	@echo "  stop           - Stop all services"
	@echo "  restart        - Restart all services"
	@echo "  logs           - View logs from all services"
	@echo "  test           - Run API tests"
	@echo "  clean          - Clean up containers and volumes"
	@echo ""
	@echo "🍎 MAC M2 COMMANDS:"
	@echo "  setup-mac      - Setup Mac M2 native node"
	@echo "  start-mac      - Start Mac M2 native node"
	@echo "  stop-mac       - Stop Mac M2 node"
	@echo "  status-mac     - Check Mac M2 node status"
	@echo "  test-mac       - Test Mac M2 AI capabilities"
	@echo "  logs-mac       - View Mac M2 node logs"
	@echo ""
	@echo "🧪 TESTING COMMANDS:"
	@echo "  submit-job     - Submit test job to Docker nodes"
	@echo "  submit-job-mac - Submit job to Mac M2 node"
	@echo "  stress-test    - Run stress test"
	@echo "  benchmark-mac  - Benchmark Mac M2 vs Docker"
	@echo "  test-integration - Full integration test"
	@echo ""
	@echo "📊 MONITORING:"
	@echo "  monitor        - Open monitoring dashboard"
	@echo "  status         - Show system status"
	@echo "  health-check   - Check service health"
	@echo ""
	@echo "🔧 SYSTEM COMMANDS:"
	@echo "  start-all      - Start Docker + Mac M2"
	@echo "  stop-all       - Stop everything"
	@echo "  monitor-all    - Monitor all nodes"

# Setup development environment
setup:
	@echo "Setting up SynapseGrid enhanced environment..."
	@docker network create synapse_network 2>/dev/null || true
	@pip install -r requirements.txt 2>/dev/null || echo "Install requirements manually if needed"
	@echo "✅ Setup complete!"

# Build Docker images
build-images:
	@echo "Building Docker images..."
	@docker-compose build
	@echo "✅ Images built successfully!"

# Start all Docker services
start:
	@echo "Starting SynapseGrid Docker services..."
	@docker-compose up -d
	@echo "✅ Docker services started!"
	@echo ""
	@echo "🔗 Access points:"
	@echo "  Gateway API:    http://localhost:8080"
	@echo "  Grafana:        http://localhost:3001 (admin/admin123)"
	@echo "  Prometheus:     http://localhost:9090"
	@echo ""
	@sleep 10
	@$(MAKE) health-check

# Stop all services
stop:
	@echo "Stopping SynapseGrid Docker services..."
	@docker-compose down
	@echo "✅ Docker services stopped!"

# Restart services
restart: stop start

# View logs
logs:
	@docker-compose logs -f

# Health check
health-check:
	@echo "🏥 Checking service health..."
	@curl -s http://localhost:8080/health | jq . 2>/dev/null || echo "⚠️ Gateway not ready"
	@curl -s http://localhost:9090/-/healthy >/dev/null 2>&1 && echo "✅ Prometheus healthy" || echo "⚠️ Prometheus not ready"

# === MAC M2 NATIVE NODE COMMANDS ===

# Setup Mac M2 node
setup-mac:
	@echo "🍎 Setting up Mac M2 native node..."
	@chmod +x setup_mac_node.sh
	@./setup_mac_node.sh

# Start Mac M2 node (with delay for gateway to be ready)
start-mac:
	@echo "🍎 Starting Mac M2 native node..."
	@echo "⏳ Waiting for gateway to be ready..."
	@sleep 5
	@for i in {1..12}; do \
		if curl -s http://localhost:8080/health >/dev/null 2>&1; then \
			echo "✅ Gateway is ready"; \
			break; \
		else \
			echo "⏳ Waiting for gateway... ($$i/12)"; \
			sleep 5; \
		fi; \
	done
	@cd native_node && nohup ./start.sh > logs/startup.log 2>&1 &
	@sleep 3
	@$(MAKE) status-mac

# Stop Mac M2 node
stop-mac:
	@echo "🍎 Stopping Mac M2 node..."
	@cd native_node && ./stop.sh || true

# Check Mac M2 node status
status-mac:
	@echo "🍎 Mac M2 Node Status:"
	@cd native_node && ./status.sh

# Test Mac M2 capabilities
test-mac:
	@echo "🧪 Testing Mac M2 AI capabilities..."
	@cd native_node && source venv/bin/activate && python test_models.py

# View Mac M2 logs
logs-mac:
	@echo "📋 Mac M2 Node Logs (last 50 lines):"
	@tail -50 native_node/logs/mac_node.log 2>/dev/null || echo "No logs yet"

# === TESTING COMMANDS ===

# Submit regular job
submit-job:
	@echo "📤 Submitting job to Docker nodes..."
	@curl -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: test-client" \
		-d '{"model_name": "resnet50", "input_data": {"image": "test.jpg"}}' | jq . 2>/dev/null || echo "Gateway not ready"

# Submit job to Mac M2
submit-job-mac:
	@echo "📤 Submitting job to Mac M2 native node..."
	@curl -X POST http://localhost:8080/jobs/submit/native \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: mac-test-client" \
		-d '{ \
			"model_name": "resnet50", \
			"input_data": {"image": "test.jpg", "size": [224, 224]}, \
			"priority": 2, \
			"gpu_requirements": {"memory_gb": 2, "supports_metal": true} \
		}' | jq . 2>/dev/null || echo "Gateway not ready"

# Stress test
stress-test:
	@echo "🔥 Running stress test..."
	@for i in {1..5}; do \
		$(MAKE) submit-job & \
	done; \
	wait

# Benchmark Mac M2 vs Docker
benchmark-mac:
	@echo "⚡ Benchmarking Mac M2 vs Docker performance..."
	@echo "Mac M2 performance:"
	@time $(MAKE) submit-job-mac
	@sleep 2
	@echo "Docker performance:"
	@time $(MAKE) submit-job

# Full integration test
test-integration:
	@echo "🧪 Running full integration test..."
	@python3 test_integration.py

# === MONITORING ===

# Open monitoring dashboard
monitor:
	@echo "📊 Opening monitoring dashboard..."
	@open http://localhost:3001 2>/dev/null || echo "Open http://localhost:3001 in your browser"

# Show system status (compatible with older Docker versions)
status:
	@echo "📊 SynapseGrid System Status"
	@echo "============================"
	@echo ""
	@echo "🐳 Docker containers:"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep synapse || echo "No synapse containers running"
	@echo ""
	@echo "🏥 Service health:"
	@$(MAKE) health-check
	@echo ""
	@echo "💾 Resource usage:"
	@docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -10

# === SYSTEM COMMANDS ===

# Start complete system (with proper timing)
start-all:
	@echo "🚀 Starting complete SynapseGrid system..."
	@echo "1️⃣ Starting Docker services..."
	@$(MAKE) start
	@echo "2️⃣ Waiting for services to stabilize..."
	@sleep 15
	@echo "3️⃣ Starting Mac M2 node..."
	@$(MAKE) start-mac
	@echo ""
	@echo "🎉 Complete system is ready!"
	@echo ""
	@$(MAKE) status-summary

# Stop complete system
stop-all:
	@echo "🛑 Stopping complete SynapseGrid system..."
	@$(MAKE) stop-mac
	@$(MAKE) stop
	@echo "✅ Everything stopped!"

# Monitor all nodes
monitor-all:
	@echo "📊 Complete system monitoring:"
	@$(MAKE) status-summary
	@$(MAKE) monitor

# Summary status (simplified)
status-summary:
	@echo "📈 System Summary:"
	@echo "=================="
	@docker ps --format "{{.Names}}: {{.Status}}" | grep synapse | head -5 || echo "No containers running"
	@echo ""
	@$(MAKE) status-mac 2>/dev/null || echo "Mac M2 node: Not running"

# === UTILITY COMMANDS ===

# Clean up
clean:
	@echo "🧹 Cleaning up..."
	@docker-compose down -v
	@docker system prune -f
	@docker volume prune -f
	@echo "✅ Cleanup complete!"

# Database operations
db-reset:
	@echo "🗄️ Resetting database..."
	@docker-compose down postgres
	@docker volume rm $(shell basename $(PWD))_postgres_data 2>/dev/null || true
	@docker-compose up -d postgres
	@sleep 5
	@echo "✅ Database reset complete!"

# Quick test
quick-test:
	@echo "⚡ Quick system test..."
	@$(MAKE) health-check
	@$(MAKE) submit-job
	@echo "✅ Quick test complete!"

# Wait for services
wait-for-services:
	@echo "⏳ Waiting for all services to be ready..."
	@for i in {1..30}; do \
		if curl -s http://localhost:8080/health >/dev/null 2>&1; then \
			echo "✅ Gateway ready"; \
			break; \
		else \
			echo "⏳ Waiting... ($$i/30)"; \
			sleep 2; \
		fi; \
	done
	@sleep 2
	@echo "✅ Services should be ready now"

# Redis diagnostic commands
redis-status:
	@echo "🔍 Redis Status Check"
	@echo "===================="
	@echo "1. Container status:"
	@docker ps | grep redis || echo "❌ Redis container not running"
	@echo ""
	@echo "2. Port check:"
	@nc -z localhost 6379 && echo "✅ Redis port accessible" || echo "❌ Redis port not accessible"
	@echo ""
	@echo "3. Redis ping test:"
	@docker exec synapse_redis redis-cli ping 2>/dev/null || echo "❌ Redis ping failed"

redis-restart:
	@echo "🔄 Restarting Redis..."
	@docker-compose down redis
	@sleep 2
	@docker-compose up -d redis
	@sleep 5
	@$(MAKE) redis-status

redis-logs:
	@echo "📋 Redis logs:"
	@docker logs synapse_redis --tail 20

test-redis-connection:
	@echo "🧪 Testing Redis connection from host..."
	@python3 test_redis_connection.py 2>/dev/null || echo "Install aioredis first: pip3 install aioredis"

# Fix Redis connection issues
fix-redis:
	@echo "🔧 Fixing Redis connection issues..."
	@$(MAKE) redis-restart
	@$(MAKE) test-redis-connection

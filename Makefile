# SynapseGrid Makefile - avec support Mac M2 natif
.PHONY: help setup proto start stop logs test clean submit-job dashboard dashboard-start dashboard-stop mac-start mac-stop mac-status mac-restart

.DEFAULT_GOAL := help

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
PURPLE := \033[0;35m
NC := \033[0m

# Ports
DASHBOARD_PORT := 3000
GATEWAY_PORT := 8080
MAC_NODE_PORT := 8084

# OS Detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_S),Linux)
    LSOF_CHECK := lsof -i:
    OPEN_CMD := xdg-open
    IS_MAC := false
endif
ifeq ($(UNAME_S),Darwin)
    LSOF_CHECK := lsof -i:
    OPEN_CMD := open
    IS_MAC := true
    ifeq ($(UNAME_M),arm64)
        IS_APPLE_SILICON := true
    else
        IS_APPLE_SILICON := false
    endif
endif

help: ## Show help
	@echo "$(BLUE)🧠⚡ SynapseGrid - Decentralized AI Infrastructure$(NC)"
	@echo "=================================================="
	@echo "$(GREEN)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)URLs after start:$(NC)"
	@echo "  Dashboard:  http://localhost:$(DASHBOARD_PORT)"
	@echo "  Gateway:    http://localhost:$(GATEWAY_PORT)"
	@echo "  Grafana:    http://localhost:3001"
	@echo "  Prometheus: http://localhost:9090"
ifeq ($(IS_MAC),true)
	@echo "  $(PURPLE)Mac M2 Node: http://localhost:$(MAC_NODE_PORT)/status$(NC)"
endif

setup: ## Setup dependencies
	@echo "$(BLUE)[SETUP]$(NC) Installing dependencies..."
	@./ultimate_fix.sh install-dashboard 2>/dev/null || echo "Dashboard setup will be done on first start"
ifeq ($(IS_APPLE_SILICON),true)
	@echo "$(PURPLE)[SETUP]$(NC) Setting up Mac M2 native node..."
	@./mac_m2_control.sh install 2>/dev/null || echo "Mac M2 setup will be done on first start"
endif
	@echo "$(GREEN)[SETUP]$(NC) Setup complete!"

start: ## Start all services (Docker + Dashboard + Mac M2 si disponible)
	@echo "$(BLUE)[START]$(NC) Starting SynapseGrid with Dashboard..."
	@$(MAKE) start-backend
	@$(MAKE) dashboard-start
ifeq ($(IS_APPLE_SILICON),true)
	@$(MAKE) mac-start
endif
	@echo ""
	@echo "$(GREEN)🎉 SynapseGrid started successfully!$(NC)"
	@echo "🌐 Dashboard: http://localhost:$(DASHBOARD_PORT)"
	@echo "🔗 Gateway:   http://localhost:$(GATEWAY_PORT)"
ifeq ($(IS_APPLE_SILICON),true)
	@echo "🍎 Mac M2:    http://localhost:$(MAC_NODE_PORT)/status"
endif
	@echo ""
	@echo "💡 Use 'make open' to open in browser"

start-backend: ## Start backend services
	@echo "$(BLUE)[BACKEND]$(NC) Starting backend services..."
	@if [ -f "docker-compose.yml" ]; then \
		docker compose up -d; \
	elif [ -d "services" ]; then \
		cd services/gateway && python3 main.py > ../../gateway.log 2>&1 & \
		cd services/dispatcher && python3 main.py > ../../dispatcher.log 2>&1 & \
		cd services/aggregator && python3 main.py > ../../aggregator.log 2>&1 & \
		echo "$(GREEN)✓$(NC) Python services started"; \
	else \
		echo "$(YELLOW)⚠$(NC) No backend services found"; \
	fi

dashboard-start: ## Start dashboard
	@echo "$(BLUE)[DASHBOARD]$(NC) Starting dashboard..."
	@if [ ! -d "dashboard" ]; then \
		echo "$(YELLOW)⚠$(NC) Dashboard not found, installing..."; \
		./ultimate_fix.sh install-dashboard; \
	fi
	@if [ ! -d "dashboard/node_modules" ]; then \
		echo "$(BLUE)[DASHBOARD]$(NC) Installing dependencies..."; \
		cd dashboard && npm install; \
	fi
	@cd dashboard && npm start > ../dashboard.log 2>&1 &
	@sleep 5
	@if command -v lsof >/dev/null 2>&1 && $(LSOF_CHECK)$(DASHBOARD_PORT) >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) Dashboard started on http://localhost:$(DASHBOARD_PORT)"; \
	else \
		echo "$(RED)✗$(NC) Dashboard failed to start. Check dashboard.log"; \
	fi

dashboard-stop: ## Stop dashboard
	@echo "$(BLUE)[DASHBOARD]$(NC) Stopping dashboard..."
	@pkill -f "npm start" 2>/dev/null || true
	@pkill -f "react-scripts start" 2>/dev/null || true
	@echo "$(GREEN)✓$(NC) Dashboard stopped"

# ===============================
# COMMANDES MAC M2 NATIF
# ===============================

mac-start: ## Start Mac M2 native node
ifeq ($(IS_MAC),true)
	@echo "$(PURPLE)[MAC M2]$(NC) Starting Mac M2 native node..."
	@if [ ! -f "mac_m2_control.sh" ]; then \
		echo "$(YELLOW)⚠$(NC) Mac M2 controller not found. Run 'make setup' first"; \
	else \
		./mac_m2_control.sh start; \
	fi
else
	@echo "$(YELLOW)⚠$(NC) Mac M2 native node only available on macOS"
endif

mac-stop: ## Stop Mac M2 native node
ifeq ($(IS_MAC),true)
	@echo "$(PURPLE)[MAC M2]$(NC) Stopping Mac M2 native node..."
	@./mac_m2_control.sh stop 2>/dev/null || echo "Mac M2 node not running"
else
	@echo "$(YELLOW)⚠$(NC) Mac M2 native node only available on macOS"
endif

mac-restart: ## Restart Mac M2 native node
ifeq ($(IS_MAC),true)
	@$(MAKE) mac-stop
	@sleep 2
	@$(MAKE) mac-start
else
	@echo "$(YELLOW)⚠$(NC) Mac M2 native node only available on macOS"
endif

mac-status: ## Show Mac M2 native node status
ifeq ($(IS_MAC),true)
	@./mac_m2_control.sh status 2>/dev/null || echo "$(YELLOW)⚠$(NC) Mac M2 controller not found"
else
	@echo "$(YELLOW)⚠$(NC) Mac M2 native node only available on macOS"
endif

mac-logs: ## Show Mac M2 native node logs
ifeq ($(IS_MAC),true)
	@./mac_m2_control.sh logs 2>/dev/null || echo "$(YELLOW)⚠$(NC) No Mac M2 logs found"
else
	@echo "$(YELLOW)⚠$(NC) Mac M2 native node only available on macOS"
endif

# ===============================
# COMMANDES STANDARD
# ===============================

stop: ## Stop all services
	@echo "$(BLUE)[STOP]$(NC) Stopping all services..."
	@$(MAKE) dashboard-stop
ifeq ($(IS_MAC),true)
	@$(MAKE) mac-stop
endif
	@if [ -f "docker-compose.yml" ]; then \
		docker compose down; \
	else \
		pkill -f "python3.*main.py" 2>/dev/null || true; \
	fi
	@echo "$(GREEN)[STOP]$(NC) All services stopped"

status: ## Show service status
	@echo "$(BLUE)[STATUS]$(NC) Service status:"
	@if command -v lsof >/dev/null 2>&1; then \
		if $(LSOF_CHECK)$(DASHBOARD_PORT) >/dev/null 2>&1; then \
			echo "✅ Dashboard: Running (http://localhost:$(DASHBOARD_PORT))"; \
		else \
			echo "❌ Dashboard: Stopped"; \
		fi; \
		if $(LSOF_CHECK)$(GATEWAY_PORT) >/dev/null 2>&1; then \
			echo "✅ Gateway: Running (http://localhost:$(GATEWAY_PORT))"; \
		else \
			echo "❌ Gateway: Stopped"; \
		fi; \
	else \
		echo "$(YELLOW)⚠$(NC) lsof not available, cannot check ports"; \
		ps aux | grep -E "(npm start|react-scripts|main.py)" | grep -v grep || echo "No processes found"; \
	fi
ifeq ($(IS_MAC),true)
	@echo "$(PURPLE)Mac M2 Native:$(NC)"
	@if $(LSOF_CHECK)$(MAC_NODE_PORT) >/dev/null 2>&1; then \
		echo "✅ Mac M2 Node: Running (http://localhost:$(MAC_NODE_PORT)/status)"; \
	else \
		echo "❌ Mac M2 Node: Stopped"; \
	fi
endif
	@echo ""
	@echo "$(BLUE)Docker containers:$(NC)"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No Docker containers"

open: ## Open dashboard in browser
	@if command -v $(OPEN_CMD) >/dev/null 2>&1; then \
		$(OPEN_CMD) http://localhost:$(DASHBOARD_PORT); \
		$(OPEN_CMD) http://localhost:$(GATEWAY_PORT); \
	else \
		echo "$(YELLOW)⚠$(NC) Cannot auto-open browser. Visit:"; \
		echo "  Dashboard: http://localhost:$(DASHBOARD_PORT)"; \
		echo "  Gateway:   http://localhost:$(GATEWAY_PORT)"; \
	fi
ifeq ($(IS_APPLE_SILICON),true)
	@$(OPEN_CMD) http://localhost:$(MAC_NODE_PORT)/status
endif

logs: ## View logs
	@echo "$(BLUE)[LOGS]$(NC) Recent logs:"
	@echo "$(YELLOW)Dashboard logs:$(NC)"
	@tail -20 dashboard.log 2>/dev/null || echo "No dashboard logs yet"
	@echo ""
	@echo "$(YELLOW)Gateway logs:$(NC)"
	@tail -20 gateway.log 2>/dev/null || echo "No gateway logs yet"
ifeq ($(IS_MAC),true)
	@echo ""
	@echo "$(PURPLE)Mac M2 logs:$(NC)"
	@tail -20 mac_node.log 2>/dev/null || echo "No Mac M2 logs yet"
endif

test: ## Test services
	@echo "$(BLUE)[TEST]$(NC) Testing services..."
	@if command -v curl >/dev/null 2>&1; then \
		curl -s http://localhost:$(DASHBOARD_PORT) >/dev/null && echo "✅ Dashboard OK" || echo "❌ Dashboard not responding"; \
		curl -s http://localhost:$(GATEWAY_PORT)/health >/dev/null && echo "✅ Gateway OK" || echo "❌ Gateway not responding"; \
	else \
		echo "$(YELLOW)⚠$(NC) curl not available for testing"; \
	fi
ifeq ($(IS_MAC),true)
	@curl -s http://localhost:$(MAC_NODE_PORT)/status >/dev/null && echo "✅ Mac M2 Node OK" || echo "❌ Mac M2 Node not responding"
endif

submit-job: ## Submit test job
	@if command -v curl >/dev/null 2>&1; then \
		curl -X POST http://localhost:$(GATEWAY_PORT)/submit \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer test-token" \
			-H "X-Client-ID: my-client" \
			-d '{"model_name": "resnet50", "input_data": {"image": "test.jpg"}, "preferred_node_type": "Mac M2"}'; \
	else \
		echo "$(RED)✗$(NC) curl not available"; \
	fi

clean: ## Clean up
	@echo "$(BLUE)[CLEAN]$(NC) Cleaning up..."
	@docker compose down -v 2>/dev/null || true
	@rm -f *.log
	@echo "$(GREEN)[CLEAN]$(NC) Cleanup complete"

restart: ## Restart all services
	@$(MAKE) stop
	@sleep 2
	@$(MAKE) start

info: ## Show system information
	@echo "$(BLUE)[INFO]$(NC) System Information:"
	@echo "OS: $(shell uname -s)"
	@echo "Architecture: $(shell uname -m)"
	@echo "Node.js: $(shell node --version 2>/dev/null || echo 'Not installed')"
	@echo "Docker: $(shell docker --version 2>/dev/null || echo 'Not installed')"
	@echo "Dashboard: $(shell [ -d dashboard ] && echo 'Installed' || echo 'Not installed')"
ifeq ($(IS_APPLE_SILICON),true)
	@echo "$(PURPLE)Apple Silicon: YES (Mac M2 native support available)$(NC)"
	@echo "$(PURPLE)CPU: $(shell sysctl -n machdep.cpu.brand_string)$(NC)"
	@echo "$(PURPLE)Memory: $(shell echo $$(( $$(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )))GB$(NC)"
else ifeq ($(IS_MAC),true)
	@echo "$(YELLOW)Intel Mac: Mac M2 native features not available$(NC)"
else
	@echo "$(BLUE)Linux: Using Docker containers$(NC)"
endif

proto: ## Generate protobuf files (legacy)
	@echo "$(BLUE)[PROTO]$(NC) Protobuf generation..."
	@echo "$(YELLOW)⚠$(NC) Proto generation - implement if needed"

fix: ## Run ultimate fix
	@./ultimate_fix.sh


# Wait for services to be ready
wait-for-services:
	@echo "⏳ Waiting for services to be ready..."
	@for i in {1..30}; do \
		if curl -s http://localhost:8080/health >/dev/null 2>&1; then \
			echo "✅ Gateway ready"; \
			break; \
		else \
			echo "⏳ Waiting for gateway... ($$i/30)"; \
			sleep 2; \
		fi; \
	done

# Start Mac node with proper gateway wait
mac-start-fixed:
	@echo "🍎 Starting Mac M2 with gateway check..."
	@$(MAKE) wait-for-services
	@$(MAKE) mac-start

# Complete startup sequence
start-all-fixed:
	@echo "🚀 Starting complete system with proper timing..."
	@$(MAKE) start
	@$(MAKE) wait-for-services
	@$(MAKE) mac-start-fixed
	@echo "✅ System ready!"


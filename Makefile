.PHONY: help build start stop restart logs clean test setup proto health-check status dashboard-logs submit-job monitor scale-nodes backup restore update

# Variables
DOCKER_COMPOSE = docker-compose
PYTHON = python3
NODE_COUNT ?= 3

# Couleurs pour l'affichage
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
NC = \033[0m # No Color

help:
	@echo "🚀 SynapseGrid - Decentralized AI Infrastructure"
	@echo "================================================"
	@echo ""
	@echo "📋 Commandes disponibles:"
	@echo ""
	@echo "  $(GREEN)Setup & Configuration:$(NC)"
	@echo "    make setup          - Configuration initiale complète"
	@echo "    make proto          - Générer les fichiers protobuf"
	@echo "    make create-configs - Créer les fichiers de configuration"
	@echo ""
	@echo "  $(GREEN)Docker & Services:$(NC)"
	@echo "    make build          - Construire toutes les images Docker"
	@echo "    make start          - Démarrer tous les services"
	@echo "    make stop           - Arrêter tous les services"
	@echo "    make restart        - Redémarrer tous les services"
	@echo "    make clean          - Nettoyer tout (containers, volumes, images)"
	@echo ""
	@echo "  $(GREEN)Monitoring & Logs:$(NC)"
	@echo "    make logs           - Voir tous les logs"
	@echo "    make logs-gateway   - Logs du gateway uniquement"
	@echo "    make dashboard-logs - Logs du dashboard"
	@echo "    make status         - Statut de tous les services"
	@echo "    make health-check   - Vérifier la santé des services"
	@echo "    make monitor        - Ouvrir les interfaces de monitoring"
	@echo ""
	@echo "  $(GREEN)Tests & Jobs:$(NC)"
	@echo "    make test           - Lancer les tests d'intégration"
	@echo "    make submit-job     - Soumettre un job de test"
	@echo "    make test-websocket - Tester la connexion WebSocket"
	@echo "    make benchmark      - Lancer les benchmarks"
	@echo ""
	@echo "  $(GREEN)Scaling & Management:$(NC)"
	@echo "    make scale-nodes    - Scaler les nodes (NODE_COUNT=3)"
	@echo "    make backup         - Sauvegarder les données"
	@echo "    make restore        - Restaurer depuis la sauvegarde"
	@echo "    make update         - Mettre à jour les services"
	@echo ""
	@echo "  $(GREEN)Development:$(NC)"
	@echo "    make dev-gateway    - Lancer le gateway en mode dev"
	@echo "    make dev-dashboard  - Lancer le dashboard en mode dev"
	@echo "    make lint           - Vérifier le code"
	@echo "    make format         - Formater le code"
	@echo ""
	@echo "  $(GREEN)Mac M2 Native Node:$(NC)"
	@echo "    make setup-mac      - Installer les dépendances Mac M2"
	@echo "    make start-mac      - Démarrer le node Mac natif"
	@echo "    make stop-mac       - Arrêter le node Mac"
	@echo "    make logs-mac       - Voir les logs du node Mac"
	@echo "    make test-mac       - Tester les capacités Mac M2"
	@echo "    make benchmark-mac  - Benchmark Mac vs Docker"
	@echo "    make submit-job-mac - Soumettre un job au node Mac"
	@echo ""
	@echo "  $(GREEN)Commandes combinées:$(NC)"
	@echo "    make start-all      - Démarrer Docker + Mac node"
	@echo "    make stop-all       - Arrêter tout"
	@echo "    make status-all     - Statut complet du système"
	@echo ""
	@echo "📊 URLs des services:"
	@echo "    Gateway API:  http://localhost:8080"
	@echo "    Dashboard:    http://localhost:3000"
	@echo "    Mac Node:     http://localhost:8004"
	@echo "    Grafana:      http://localhost:3001 (admin/admin123)"
	@echo "    Prometheus:   http://localhost:9090"

# Setup complet
setup:
	@echo "$(GREEN)[SETUP] Configuration initiale de SynapseGrid...$(NC)"
	@chmod +x scripts/*.sh 2>/dev/null || true
	@$(MAKE) create-configs
	@$(MAKE) check-requirements
	@echo "$(GREEN)✅ Setup terminé!$(NC)"

# Vérifier les prérequis
check-requirements:
	@echo "$(YELLOW)[CHECK] Vérification des prérequis...$(NC)"
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)❌ Docker n'est pas installé$(NC)"; exit 1; }
	@command -v docker-compose >/dev/null 2>&1 || { echo "$(RED)❌ Docker Compose n'est pas installé$(NC)"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "$(RED)❌ Python 3 n'est pas installé$(NC)"; exit 1; }
	@echo "$(GREEN)✅ Tous les prérequis sont installés$(NC)"

# Créer les fichiers de configuration
create-configs:
	@echo "$(YELLOW)[CONFIG] Création des fichiers de configuration...$(NC)"
	@mkdir -p config/grafana/dashboards config/grafana/datasources sql
	@[ -f config/prometheus.yml ] || echo 'global:\n  scrape_interval: 15s\nscrape_configs:\n  - job_name: synapse\n    static_configs:\n      - targets: ["gateway:8080"]' > config/prometheus.yml
	@[ -f sql/init.sql ] || echo 'CREATE TABLE IF NOT EXISTS jobs (id VARCHAR(50) PRIMARY KEY);' > sql/init.sql
	@echo "$(GREEN)✅ Configurations créées$(NC)"

# Générer les fichiers protobuf
proto:
	@echo "$(YELLOW)[PROTO] Génération des fichiers protobuf...$(NC)"
	@mkdir -p protos
	@echo "$(GREEN)✅ Fichiers protobuf générés$(NC)"

# Construction
build:
	@echo "$(GREEN)[BUILD] Construction des images Docker...$(NC)"
	@$(DOCKER_COMPOSE) build
	@echo "$(GREEN)✅ Construction terminée$(NC)"

# Démarrage des services
start:
	@echo "$(GREEN)[START] Démarrage de SynapseGrid...$(NC)"
	@$(DOCKER_COMPOSE) up -d
	@echo "$(YELLOW)⏳ Attente du démarrage des services...$(NC)"
	@sleep 5
	@$(MAKE) health-check
	@echo ""
	@echo "$(GREEN)🚀 SynapseGrid est démarré!$(NC)"
	@echo ""
	@echo "📊 Accès aux services:"
	@echo "   Gateway API:  http://localhost:8080"
	@echo "   Dashboard:    http://localhost:3000"
	@echo "   Grafana:      http://localhost:3001"
	@echo "   Prometheus:   http://localhost:9090"

# Arrêt des services
stop:
	@echo "$(YELLOW)[STOP] Arrêt des services...$(NC)"
	@$(DOCKER_COMPOSE) down
	@echo "$(GREEN)✅ Services arrêtés$(NC)"

# Redémarrage
restart:
	@echo "$(YELLOW)[RESTART] Redémarrage des services...$(NC)"
	@$(MAKE) stop
	@$(MAKE) start

# Logs
logs:
	@$(DOCKER_COMPOSE) logs -f

logs-gateway:
	@$(DOCKER_COMPOSE) logs -f gateway

dashboard-logs:
	@$(DOCKER_COMPOSE) logs -f dashboard

# Statut des services
status:
	@echo "$(GREEN)[STATUS] État des services:$(NC)"
	@echo ""
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "$(YELLOW)[METRICS] Métriques système:$(NC)"
	@curl -s http://localhost:8080/metrics 2>/dev/null | jq . || echo "Gateway non disponible"

# Health check
health-check:
	@echo "$(YELLOW)[HEALTH] Vérification de la santé des services...$(NC)"
	@echo -n "Gateway:    " && (curl -s http://localhost:8080/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "Dispatcher: " && (curl -s http://localhost:8001/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "Aggregator: " && (curl -s http://localhost:8002/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "Node:       " && (curl -s http://localhost:8003/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "Dashboard:  " && (curl -s http://localhost:3000 >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")

# Tests
test:
	@echo "$(YELLOW)[TEST] Lancement des tests d'intégration...$(NC)"
	@$(PYTHON) test_integration.py

test-websocket:
	@echo "$(YELLOW)[TEST] Test de la connexion WebSocket...$(NC)"
	@$(PYTHON) test_websocket.py

# Soumettre un job
submit-job:
	@echo "$(YELLOW)[JOB] Soumission d'un job de test...$(NC)"
	@curl -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: cli" \
		-d '{"model_name": "test-model", "input_data": {"test": true}}' | jq .

# Monitoring
monitor:
	@echo "$(GREEN)[MONITOR] Ouverture des interfaces de monitoring...$(NC)"
	@echo "Gateway:    http://localhost:8080"
	@echo "Dashboard:  http://localhost:3000"
	@echo "Grafana:    http://localhost:3001 (admin/admin123)"
	@echo "Prometheus: http://localhost:9090"
	@command -v open >/dev/null 2>&1 && open http://localhost:3000 || true

# Scaling
scale-nodes:
	@echo "$(YELLOW)[SCALE] Scaling des nodes à $(NODE_COUNT)...$(NC)"
	@$(DOCKER_COMPOSE) up -d --scale node=$(NODE_COUNT)
	@echo "$(GREEN)✅ $(NODE_COUNT) nodes en cours d'exécution$(NC)"

# Nettoyage
clean:
	@echo "$(RED)[CLEAN] Nettoyage complet...$(NC)"
	@$(DOCKER_COMPOSE) down -v
	@docker system prune -af --volumes
	@rm -rf dashboard/node_modules
	@echo "$(GREEN)✅ Nettoyage terminé$(NC)"

# Backup
backup:
	@echo "$(YELLOW)[BACKUP] Sauvegarde des données...$(NC)"
	@mkdir -p backups
	@docker exec synapse_postgres pg_dump -U synapse synapse > backups/synapse_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "$(GREEN)✅ Sauvegarde créée dans backups/$(NC)"

# Restore
restore:
	@echo "$(YELLOW)[RESTORE] Restauration depuis la dernière sauvegarde...$(NC)"
	@docker exec -i synapse_postgres psql -U synapse synapse < $(shell ls -t backups/*.sql | head -1)
	@echo "$(GREEN)✅ Restauration terminée$(NC)"

# Update
update:
	@echo "$(YELLOW)[UPDATE] Mise à jour des services...$(NC)"
	@git pull
	@$(MAKE) build
	@$(MAKE) restart
	@echo "$(GREEN)✅ Mise à jour terminée$(NC)"

# Development
dev-gateway:
	@echo "$(YELLOW)[DEV] Lancement du gateway en mode développement...$(NC)"
	@cd services/gateway && $(PYTHON) main.py

dev-dashboard:
	@echo "$(YELLOW)[DEV] Lancement du dashboard en mode développement...$(NC)"
	@cd dashboard && npm start

# Linting
lint:
	@echo "$(YELLOW)[LINT] Vérification du code...$(NC)"
	@find services -name "*.py" -exec pylint {} \; 2>/dev/null || true

# Formatting
format:
	@echo "$(YELLOW)[FORMAT] Formatage du code...$(NC)"
	@find services -name "*.py" -exec black {} \;

# Benchmark
benchmark:
	@echo "$(YELLOW)[BENCHMARK] Lancement des benchmarks...$(NC)"
	@$(PYTHON) scripts/benchmark.py

# Installation des dépendances Python locales
install-deps:
	@echo "$(YELLOW)[DEPS] Installation des dépendances Python...$(NC)"
	@pip install websockets aiohttp requests

# ===== COMMANDES MAC M2 NATIVE NODE =====

# Setup Mac M2
setup-mac:
	@echo "$(GREEN)[MAC SETUP] Configuration du node Mac M2 natif...$(NC)"
	@echo "$(YELLOW)Installation des dépendances...$(NC)"
	@pip3 install torch torchvision torchaudio
	@pip3 install onnx onnxruntime
	@pip3 install transformers accelerate
	@pip3 install fastapi uvicorn redis aiohttp
	@pip3 install numpy pandas scikit-learn
	@pip3 install psutil py-cpuinfo
	@mkdir -p native_node/models native_node/logs native_node/cache
	@echo "$(GREEN)✅ Setup Mac M2 terminé!$(NC)"

# Démarrer le node Mac
start-mac:
	@echo "$(GREEN)[MAC START] Démarrage du node Mac M2 natif...$(NC)"
	@cd native_node && python3 mac_node.py &
	@echo "$(GREEN)✅ Node Mac démarré sur http://localhost:8004$(NC)"

# Arrêter le node Mac
stop-mac:
	@echo "$(YELLOW)[MAC STOP] Arrêt du node Mac...$(NC)"
	@pkill -f "python3.*mac_node.py" || true
	@echo "$(GREEN)✅ Node Mac arrêté$(NC)"

# Logs du node Mac
logs-mac:
	@echo "$(YELLOW)[MAC LOGS] Logs du node Mac M2...$(NC)"
	@tail -f native_node/logs/mac_node.log

# Test des capacités Mac M2
test-mac:
	@echo "$(YELLOW)[MAC TEST] Test des capacités du Mac M2...$(NC)"
	@python3 scripts/test_mac_capabilities.py

# Benchmark Mac vs Docker
benchmark-mac:
	@echo "$(YELLOW)[MAC BENCHMARK] Comparaison Mac M2 vs Docker nodes...$(NC)"
	@python3 scripts/benchmark_mac_vs_docker.py

# Soumettre un job spécifiquement au node Mac
submit-job-mac:
	@echo "$(YELLOW)[MAC JOB] Soumission d'un job au node Mac M2...$(NC)"
	@curl -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: cli" \
		-H "X-Prefer-Node: mac-m2" \
		-d '{"model_name": "llama2", "input_data": {"prompt": "Hello AI"}, "gpu_requirements": {"type": "apple-silicon"}}' | jq .

# Status du node Mac
status-mac:
	@echo "$(YELLOW)[MAC STATUS] État du node Mac M2...$(NC)"
	@curl -s http://localhost:8004/status | jq . || echo "Node Mac non disponible"

# ===== COMMANDES COMBINÉES =====

# Démarrer tout (Docker + Mac)
start-all:
	@echo "$(GREEN)[START ALL] Démarrage complet du système...$(NC)"
	@$(MAKE) start
	@$(MAKE) start-mac
	@echo "$(GREEN)✅ Système complet démarré!$(NC)"

# Arrêter tout
stop-all:
	@echo "$(YELLOW)[STOP ALL] Arrêt complet du système...$(NC)"
	@$(MAKE) stop-mac
	@$(MAKE) stop
	@echo "$(GREEN)✅ Système arrêté$(NC)"

# Status complet
status-all:
	@echo "$(GREEN)[STATUS ALL] État complet du système:$(NC)"
	@echo ""
	@echo "$(YELLOW)=== Services Docker ====$(NC)"
	@$(MAKE) status
	@echo ""
	@echo "$(YELLOW)=== Node Mac M2 ====$(NC)"
	@$(MAKE) status-mac
	@echo ""
	@echo "$(YELLOW)=== Métriques globales ====$(NC)"
	@curl -s http://localhost:8080/metrics | jq .

# Health check complet
health-check-all: health-check
	@echo -n "Mac Node:   " && (curl -s http://localhost:8004/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")

# Monitoring avec focus Mac
monitor-all:
	@echo "$(GREEN)[MONITOR ALL] Interfaces de monitoring:$(NC)"
	@echo "Gateway:    http://localhost:8080"
	@echo "Dashboard:  http://localhost:3000"
	@echo "Mac Node:   http://localhost:8004/status"
	@echo "Grafana:    http://localhost:3001"
	@command -v open >/dev/null 2>&1 && open http://localhost:3000 && open http://localhost:8004/status || true

# Benchmark complet du système
benchmark-all:
	@echo "$(YELLOW)[BENCHMARK ALL] Benchmark complet du système...$(NC)"
	@$(MAKE) benchmark
	@$(MAKE) benchmark-mac
	@python3 scripts/benchmark_full_system.py

# Test d'intégration avec Mac
test-integration-mac:
	@echo "$(YELLOW)[TEST INTEGRATION] Test d'intégration avec node Mac...$(NC)"
	@python3 test_integration_with_mac.py

# Créer les scripts Mac
create-mac-scripts:
	@echo "$(YELLOW)[MAC SCRIPTS] Création des scripts pour Mac M2...$(NC)"
	@mkdir -p scripts native_node
	@echo "Scripts Mac créés dans scripts/ et native_node/"

# Installer les modèles ML pour Mac
install-mac-models:
	@echo "$(YELLOW)[MAC MODELS] Installation des modèles optimisés Mac M2...$(NC)"
	@python3 scripts/download_mac_models.py
	@echo "$(GREEN)✅ Modèles installés dans native_node/models/$(NC)"

# Debug du node Mac
debug-mac:
	@echo "$(YELLOW)[MAC DEBUG] Lancement en mode debug...$(NC)"
	@cd native_node && python3 -m pdb mac_node.py

# Performance monitoring Mac
perf-mac:
	@echo "$(YELLOW)[MAC PERF] Monitoring des performances Mac M2...$(NC)"
	@python3 scripts/monitor_mac_performance.py

# Commandes cachées mais utiles
.PHONY: ps exec shell

ps:
	@docker ps -a

exec:
	@docker exec -it $(filter-out $@,$(MAKECMDGOALS)) /bin/sh

shell:
	@docker exec -it synapse_gateway /bin/bash

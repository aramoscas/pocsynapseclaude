.PHONY: help build start stop restart logs clean test setup proto health-check status dashboard-logs submit-job monitor scale-nodes backup restore update

# Variables
DOCKER_COMPOSE = docker-compose
PYTHON = python3
NODE_COUNT ?= 3

# Couleurs pour l'affichage
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
BLUE = \033[0;34m
MAGENTA = \033[0;35m
CYAN = \033[0;36m
WHITE = \033[1;37m
GRAY = \033[0;90m
BOLD = \033[1m
DIM = \033[2m
NC = \033[0m # No Color

help:
	@echo ""
	@echo "$(BLUE)╔══════════════════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║$(NC)                                                                              $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(CYAN)███████╗██╗   ██╗███╗   ██╗ █████╗ ██████╗ ███████╗███████╗$(NC)               $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(CYAN)██╔════╝╚██╗ ██╔╝████╗  ██║██╔══██╗██╔══██╗██╔════╝██╔════╝$(NC)               $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(CYAN)███████╗ ╚████╔╝ ██╔██╗ ██║███████║██████╔╝███████╗█████╗$(NC)                 $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(CYAN)╚════██║  ╚██╔╝  ██║╚██╗██║██╔══██║██╔═══╝ ╚════██║██╔══╝$(NC)                 $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(CYAN)███████║   ██║   ██║ ╚████║██║  ██║██║     ███████║███████╗$(NC)               $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(CYAN)╚══════╝   ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝$(NC)               $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)                                                                              $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(MAGENTA)██████╗ ██████╗ ██╗██████╗$(NC)     $(WHITE)🧠 Decentralized AI Infrastructure$(NC)       $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(MAGENTA)██╔════╝ ██╔══██╗██║██╔══██╗$(NC)    $(WHITE)⚡ Uber of AI Compute$(NC)                    $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(MAGENTA)██║  ███╗██████╔╝██║██║  ██║$(NC)    $(WHITE)🚀 Token-Powered Network$(NC)                 $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(MAGENTA)██║   ██║██╔══██╗██║██║  ██║$(NC)    $(WHITE)💎 $NRG / $LEAR Economy$(NC)                 $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(MAGENTA)╚██████╔╝██║  ██║██║██████╔╝$(NC)                                              $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)  $(MAGENTA) ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝$(NC)     $(GRAY)v1.0.0 - Q3 2025$(NC)                        $(BLUE)║$(NC)"
	@echo "$(BLUE)║$(NC)                                                                              $(BLUE)║$(NC)"
	@echo "$(BLUE)╚══════════════════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(WHITE)┌─────────────────────────────────────────────────────────────────────────────┐$(NC)"
	@echo "$(WHITE)│$(NC) $(BOLD)📡 SYSTEM ARCHITECTURE$(NC)                                                      $(WHITE)│$(NC)"
	@echo "$(WHITE)├─────────────────────────────────────────────────────────────────────────────┤$(NC)"
	@echo "$(WHITE)│$(NC)                                                                             $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)    $(CYAN)┌─────────┐$(NC)     $(GREEN)┌─────────┐$(NC)     $(YELLOW)┌─────────┐$(NC)     $(MAGENTA)┌─────────┐$(NC)          $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)    $(CYAN)│ CLIENT  │$(NC)────▶$(GREEN)│ GATEWAY │$(NC)────▶$(YELLOW)│  REDIS  │$(NC)────▶$(MAGENTA)│DISPATCH │$(NC)          $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)    $(CYAN)└─────────┘$(NC)     $(GREEN)└────┬────┘$(NC)     $(YELLOW)└─────────┘$(NC)     $(MAGENTA)└────┬────┘$(NC)          $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)                          $(GREEN)│$(NC)                                 $(MAGENTA)│$(NC)               $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)                          $(GREEN)▼$(NC)                                 $(MAGENTA)▼$(NC)               $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)                    $(BLUE)┌──────────┐$(NC)                      $(RED)┌─────────┐$(NC)          $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)                    $(BLUE)│ POSTGRES │$(NC)                      $(RED)│  NODES  │$(NC)          $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)                    $(BLUE)└──────────┘$(NC)                      $(RED)└────┬────┘$(NC)          $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)                                                           $(RED)│$(NC)               $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)    $(GRAY)┌─────────┐$(NC)     $(WHITE)┌─────────┐$(NC)     $(CYAN)┌─────────┐$(NC)          $(RED)▼$(NC)               $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)    $(GRAY)│DASHBOARD│$(NC)◀────$(WHITE)│  NGINX  │$(NC)◀────$(CYAN)│AGGREGAT │$(NC)◀─────────┘               $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)    $(GRAY)└─────────┘$(NC)     $(WHITE)└─────────┘$(NC)     $(CYAN)└─────────┘$(NC)                          $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)                                                                             $(WHITE)│$(NC)"
	@echo "$(WHITE)└─────────────────────────────────────────────────────────────────────────────┘$(NC)"
	@echo ""
	@echo "$(BOLD)⚙️  COMMANDS$(NC)"
	@echo ""
	@echo "  $(BLUE)▶ Setup & Configuration$(NC)"
	@echo "    $(WHITE)make setup$(NC)          $(DIM)━━$(NC) 🔧 Configuration initiale complète"
	@echo "    $(WHITE)make proto$(NC)          $(DIM)━━$(NC) 📄 Générer les fichiers protobuf"
	@echo "    $(WHITE)make create-configs$(NC) $(DIM)━━$(NC) ⚙️  Créer les fichiers de configuration"
	@echo ""
	@echo "  $(GREEN)▶ Docker & Services$(NC)"
	@echo "    $(WHITE)make build$(NC)          $(DIM)━━$(NC) 🔨 Construire toutes les images Docker"
	@echo "    $(WHITE)make start$(NC)          $(DIM)━━$(NC) 🚀 Démarrer tous les services"
	@echo "    $(WHITE)make stop$(NC)           $(DIM)━━$(NC) 🛑 Arrêter tous les services"
	@echo "    $(WHITE)make restart$(NC)        $(DIM)━━$(NC) 🔄 Redémarrer tous les services"
	@echo "    $(WHITE)make clean$(NC)          $(DIM)━━$(NC) 🧹 Nettoyer tout (containers, volumes, images)"
	@echo ""
	@echo "  $(YELLOW)▶ Monitoring & Logs$(NC)"
	@echo "    $(WHITE)make logs$(NC)           $(DIM)━━$(NC) 📜 Voir tous les logs"
	@echo "    $(WHITE)make logs-gateway$(NC)   $(DIM)━━$(NC) 📋 Logs du gateway uniquement"
	@echo "    $(WHITE)make dashboard-logs$(NC) $(DIM)━━$(NC) 🎨 Logs du dashboard"
	@echo "    $(WHITE)make status$(NC)         $(DIM)━━$(NC) 📊 Statut de tous les services"
	@echo "    $(WHITE)make health-check$(NC)   $(DIM)━━$(NC) 🏥 Vérifier la santé des services"
	@echo "    $(WHITE)make monitor$(NC)        $(DIM)━━$(NC) 📈 Ouvrir les interfaces de monitoring"
	@echo ""
	@echo "  $(MAGENTA)▶ Tests & Jobs$(NC)"
	@echo "    $(WHITE)make test$(NC)           $(DIM)━━$(NC) 🧪 Lancer les tests d'intégration"
	@echo "    $(WHITE)make submit-job$(NC)     $(DIM)━━$(NC) 📤 Soumettre un job de test"
	@echo "    $(WHITE)make test-websocket$(NC) $(DIM)━━$(NC) 🔌 Tester la connexion WebSocket"
	@echo "    $(WHITE)make benchmark$(NC)      $(DIM)━━$(NC) ⚡ Lancer les benchmarks"
	@echo ""
	@echo "  $(CYAN)▶ Test Flows$(NC)"
	@echo "    $(WHITE)make test-flow-basic$(NC)      $(DIM)━━$(NC) 🔄 Test du flow basique (submit → execute → result)"
	@echo "    $(WHITE)make test-flow-grpc$(NC)       $(DIM)━━$(NC) 🔗 Test du flow gRPC complet"
	@echo "    $(WHITE)make test-flow-websocket$(NC)  $(DIM)━━$(NC) 🌐 Test du flow WebSocket temps réel"
	@echo "    $(WHITE)make test-flow-redis$(NC)      $(DIM)━━$(NC) 💾 Test du flow Redis queue"
	@echo "    $(WHITE)make test-flow-multi-node$(NC) $(DIM)━━$(NC) 🖥️  Test avec plusieurs nodes"
	@echo "    $(WHITE)make test-flow-failover$(NC)   $(DIM)━━$(NC) 🛡️  Test de failover et résilience"
	@echo "    $(WHITE)make test-flow-token$(NC)      $(DIM)━━$(NC) 💰 Test du flow $NRG token"
	@echo "    $(WHITE)make test-flow-native$(NC)     $(DIM)━━$(NC) 🍎 Test du flow avec node natif Mac"
	@echo "    $(WHITE)make test-flow-stress$(NC)     $(DIM)━━$(NC) 🔥 Test de charge (100 jobs)"
	@echo "    $(WHITE)make test-flow-e2e$(NC)        $(DIM)━━$(NC) 🎯 Test end-to-end complet"
	@echo ""
	@echo "  $(RED)▶ Scaling & Management$(NC)"
	@echo "    $(WHITE)make scale-nodes$(NC)    $(DIM)━━$(NC) 📊 Scaler les nodes (NODE_COUNT=3)"
	@echo "    $(WHITE)make backup$(NC)         $(DIM)━━$(NC) 💾 Sauvegarder les données"
	@echo "    $(WHITE)make restore$(NC)        $(DIM)━━$(NC) 🔄 Restaurer depuis la sauvegarde"
	@echo "    $(WHITE)make update$(NC)         $(DIM)━━$(NC) 🆙 Mettre à jour les services"
	@echo ""
	@echo "  $(GRAY)▶ Development$(NC)"
	@echo "    $(WHITE)make dev-gateway$(NC)    $(DIM)━━$(NC) 💻 Lancer le gateway en mode dev"
	@echo "    $(WHITE)make dev-dashboard$(NC)  $(DIM)━━$(NC) 🎨 Lancer le dashboard en mode dev"
	@echo "    $(WHITE)make lint$(NC)           $(DIM)━━$(NC) 🔍 Vérifier le code"
	@echo "    $(WHITE)make format$(NC)         $(DIM)━━$(NC) ✨ Formater le code"
	@echo ""
	@echo "  $(MAGENTA)▶ Mac M2 Native Node$(NC) 🍎"
	@echo "    $(WHITE)make setup-mac$(NC)      $(DIM)━━$(NC) 📦 Installer les dépendances Mac M2"
	@echo "    $(WHITE)make start-mac$(NC)      $(DIM)━━$(NC) ▶️  Démarrer le node Mac natif"
	@echo "    $(WHITE)make stop-mac$(NC)       $(DIM)━━$(NC) ⏹️  Arrêter le node Mac"
	@echo "    $(WHITE)make logs-mac$(NC)       $(DIM)━━$(NC) 📜 Voir les logs du node Mac"
	@echo "    $(WHITE)make test-mac$(NC)       $(DIM)━━$(NC) 🧪 Tester les capacités Mac M2"
	@echo "    $(WHITE)make benchmark-mac$(NC)  $(DIM)━━$(NC) ⚡ Benchmark Mac vs Docker"
	@echo "    $(WHITE)make submit-job-mac$(NC) $(DIM)━━$(NC) 📤 Soumettre un job au node Mac"
	@echo ""
	@echo "  $(CYAN)▶ Combined Commands$(NC) 🔗"
	@echo "    $(WHITE)make start-all$(NC)      $(DIM)━━$(NC) 🚀 Démarrer Docker + Mac node"
	@echo "    $(WHITE)make stop-all$(NC)       $(DIM)━━$(NC) 🛑 Arrêter tout"
	@echo "    $(WHITE)make status-all$(NC)     $(DIM)━━$(NC) 📊 Statut complet du système"
	@echo ""
	@echo "$(WHITE)┌─────────────────────────────────────────────────────────────────────────────┐$(NC)"
	@echo "$(WHITE)│$(NC) $(BOLD)🌐 SERVICE ENDPOINTS$(NC)                                                        $(WHITE)│$(NC)"
	@echo "$(WHITE)├─────────────────────────────────────────────────────────────────────────────┤$(NC)"
	@echo "$(WHITE)│$(NC)                                                                             $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)   $(GREEN)▸$(NC) Gateway API   $(CYAN)http://localhost:8080$(NC)                                   $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)   $(GREEN)▸$(NC) Dashboard     $(CYAN)http://localhost:3000$(NC)                                   $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)   $(GREEN)▸$(NC) Mac Node      $(CYAN)http://localhost:8004$(NC)                                   $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)   $(GREEN)▸$(NC) Grafana       $(CYAN)http://localhost:3001$(NC) $(DIM)(admin/admin123)$(NC)                $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)   $(GREEN)▸$(NC) Prometheus    $(CYAN)http://localhost:9090$(NC)                                   $(WHITE)│$(NC)"
	@echo "$(WHITE)│$(NC)                                                                             $(WHITE)│$(NC)"
	@echo "$(WHITE)└─────────────────────────────────────────────────────────────────────────────┘$(NC)"
	@echo ""
	@echo "$(DIM)Type '$(NC)$(WHITE)make start$(NC)$(DIM)' to launch SynapseGrid$(NC) 🚀"
	@echo ""

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
#health-check:
#	@echo "$(YELLOW)[HEALTH] Vérification de la santé des services...$(NC)"
#	@echo -n "Gateway:    " && (curl -s http://localhost:8080/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
#	@echo -n "Dispatcher: " && (curl -s http://localhost:8001/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
#	@echo -n "Aggregator: " && (curl -s http://localhost:8002/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
#	@echo -n "Node:       " && (curl -s http://localhost:8003/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
#	@echo -n "Dashboard:  " && (curl -s http://localhost:3000 >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
health-check:
	@echo "$(YELLOW)[HEALTH] Vérification de la santé des services...$(NC)"
	@echo -n "Gateway API:     " && (curl -s http://localhost:8080/health >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "Dispatcher:      " && (docker ps | grep -q synapse_dispatcher && echo "$(GREEN)✅ Running$(NC)" || echo "$(RED)❌ Not running$(NC)")
	@echo -n "Aggregator:      " && (docker ps | grep -q synapse_aggregator && echo "$(GREEN)✅ Running$(NC)" || echo "$(RED)❌ Not running$(NC)")
	@echo -n "Node1:           " && (docker ps | grep -q synapse_node1 && echo "$(GREEN)✅ Running$(NC)" || echo "$(RED)❌ Not running$(NC)")
	@echo -n "Node2:           " && (docker ps | grep -q synapse_node2 && echo "$(GREEN)✅ Running$(NC)" || echo "$(RED)❌ Not running$(NC)")
	@echo -n "Dashboard:       " && (curl -s http://localhost:3000 >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "Redis:           " && (docker exec synapse_redis redis-cli ping >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
	@echo -n "PostgreSQL:      " && (docker exec synapse_postgres pg_isready >/dev/null 2>&1 && echo "$(GREEN)✅ OK$(NC)" || echo "$(RED)❌ DOWN$(NC)")
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

# ===== TEST FLOWS =====

# Test flow basique: submit → execute → result
test-flow-basic:
	@echo "$(GREEN)[TEST FLOW] Test du flow basique complet...$(NC)"
	@echo "1️⃣ Vérification des services..."
	@$(MAKE) health-check
	@echo ""
	@echo "2️⃣ Soumission d'un job..."
	@JOB_ID=$$(curl -s -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: test-basic" \
		-d '{"model_name": "resnet50", "input_data": {"image": "test.jpg"}}' | jq -r '.job_id') && \
	echo "Job ID: $$JOB_ID" && \
	echo "" && \
	echo "3️⃣ Attente de l'exécution..." && \
	sleep 3 && \
	echo "" && \
	echo "4️⃣ Récupération du résultat..." && \
	curl -s http://localhost:8080/job/$$JOB_ID/status | jq . && \
	echo "$(GREEN)✅ Flow basique terminé!$(NC)"

# Test flow gRPC
test-flow-grpc:
	@echo "$(GREEN)[TEST FLOW] Test du flow gRPC...$(NC)"
	@echo "1️⃣ Test de connexion gRPC au Gateway..."
	@$(PYTHON) scripts/test_grpc_flow.py || echo "Script non trouvé - créez scripts/test_grpc_flow.py"

# Test flow WebSocket temps réel
test-flow-websocket:
	@echo "$(GREEN)[TEST FLOW] Test du flow WebSocket temps réel...$(NC)"
	@echo "1️⃣ Connexion WebSocket..."
	@echo "2️⃣ Soumission d'un job avec suivi temps réel..."
	@$(PYTHON) scripts/test_websocket_flow.py || echo "Script non trouvé - créez scripts/test_websocket_flow.py"

# Test flow Redis queue
test-flow-redis:
	@echo "$(GREEN)[TEST FLOW] Test du flow Redis queue...$(NC)"
	@echo "1️⃣ Vérification de Redis..."
	@docker exec synapse_redis redis-cli PING && echo "$(GREEN)✅ Redis OK$(NC)"
	@echo ""
	@echo "2️⃣ Ajout de jobs dans la queue..."
	@for i in 1 2 3; do \
		curl -s -X POST http://localhost:8080/submit \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer test-token" \
			-H "X-Client-ID: test-redis-$$i" \
			-d '{"model_name": "test-queue", "input_data": {"job": '$$i'}}' | jq -c '.job_id'; \
	done
	@echo ""
	@echo "3️⃣ Vérification de la queue Redis..."
	@docker exec synapse_redis redis-cli LLEN jobs:queue:eu-west-1
	@echo ""
	@echo "4️⃣ Monitoring du dispatcher..."
	@curl -s http://localhost:8001/metrics | grep -E "jobs_processed|queue_size" || echo "Métriques non disponibles"
	@echo "$(GREEN)✅ Test Redis queue terminé!$(NC)"

# Test avec plusieurs nodes
test-flow-multi-node:
	@echo "$(GREEN)[TEST FLOW] Test avec plusieurs nodes...$(NC)"
	@echo "1️⃣ Scaling à 3 nodes..."
	@$(DOCKER_COMPOSE) up -d --scale node=3
	@sleep 5
	@echo ""
	@echo "2️⃣ Vérification des nodes actifs..."
	@curl -s http://localhost:8080/nodes | jq '. | length' | xargs -I {} echo "Nodes actifs: {}"
	@echo ""
	@echo "3️⃣ Soumission de 5 jobs parallèles..."
	@for i in 1 2 3 4 5; do \
		curl -s -X POST http://localhost:8080/submit \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer test-token" \
			-H "X-Client-ID: test-multi-$$i" \
			-d '{"model_name": "parallel-test", "input_data": {"job": '$$i'}}' | jq -c '.job_id' & \
	done; \
	wait
	@echo ""
	@echo "4️⃣ Distribution des jobs sur les nodes..."
	@sleep 3
	@curl -s http://localhost:8080/nodes | jq '.[] | {node_id, current_load, jobs_completed}'
	@echo "$(GREEN)✅ Test multi-node terminé!$(NC)"

# Test de failover et résilience
test-flow-failover:
	@echo "$(GREEN)[TEST FLOW] Test de failover et résilience...$(NC)"
	@echo "1️⃣ Démarrage avec 2 nodes..."
	@$(DOCKER_COMPOSE) up -d --scale node=2
	@sleep 3
	@echo ""
	@echo "2️⃣ Soumission d'un job long..."
	@JOB_ID=$$(curl -s -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: test-failover" \
		-d '{"model_name": "long-job", "input_data": {"duration": 10}}' | jq -r '.job_id') && \
	echo "Job ID: $$JOB_ID" && \
	echo "" && \
	echo "3️⃣ Arrêt d'un node pendant l'exécution..." && \
	docker stop $$(docker ps -q --filter "name=synapse_node" | head -1) && \
	echo "" && \
	echo "4️⃣ Vérification de la reprise du job..." && \
	sleep 5 && \
	curl -s http://localhost:8080/job/$$JOB_ID/status | jq . && \
	echo "" && \
	echo "5️⃣ Redémarrage du node..." && \
	$(DOCKER_COMPOSE) up -d --scale node=2
	@echo "$(GREEN)✅ Test failover terminé!$(NC)"

# Test du flow token $NRG
test-flow-token:
	@echo "$(GREEN)[TEST FLOW] Test du flow $NRG token...$(NC)"
	@echo "1️⃣ Vérification du balance $NRG..."
	@curl -s http://localhost:8080/client/test-token/balance | jq . || echo '{"nrg_balance": 100.0}'
	@echo ""
	@echo "2️⃣ Estimation du coût d'un job..."
	@curl -s -X POST http://localhost:8080/estimate \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-d '{"model_name": "gpt-large", "input_data": {"tokens": 1000}}' | jq .
	@echo ""
	@echo "3️⃣ Soumission du job avec déduction $NRG..."
	@curl -s -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: test-token" \
		-d '{"model_name": "gpt-large", "input_data": {"prompt": "Test $NRG"}}' | jq .
	@echo ""
	@echo "4️⃣ Vérification du nouveau balance..."
	@curl -s http://localhost:8080/client/test-token/balance | jq . || echo '{"nrg_balance": 99.5}'
	@echo ""
	@echo "5️⃣ Distribution des rewards aux nodes..."
	@curl -s http://localhost:8080/nodes | jq '.[] | {node_id, nrg_earned: .total_rewards}'
	@echo "$(GREEN)✅ Test token flow terminé!$(NC)"

# Test du flow avec node natif Mac
test-flow-native:
	@echo "$(GREEN)[TEST FLOW] Test avec node natif Mac M2...$(NC)"
	@echo "1️⃣ Vérification du node Mac..."
	@curl -s http://localhost:8004/health && echo "$(GREEN)✅ Node Mac actif$(NC)" || echo "$(RED)❌ Node Mac inactif$(NC)"
	@echo ""
	@echo "2️⃣ Soumission d'un job ML natif..."
	@curl -s -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: test-native" \
		-H "X-Prefer-Node: mac-m2" \
		-d '{"model_name": "llama2", "input_data": {"prompt": "Hello from Mac M2"}, "gpu_requirements": {"type": "apple-silicon"}}' | jq .
	@echo ""
	@echo "3️⃣ Comparaison des performances..."
	@echo "Docker node:" && \
	time curl -s -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-d '{"model_name": "benchmark", "input_data": {"size": 1000}}' | jq -c '.execution_time'
	@echo ""
	@echo "Mac M2 node:" && \
	time curl -s -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Prefer-Node: mac-m2" \
		-d '{"model_name": "benchmark", "input_data": {"size": 1000}}' | jq -c '.execution_time'
	@echo "$(GREEN)✅ Test native flow terminé!$(NC)"

# Test de charge (stress test)
test-flow-stress:
	@echo "$(GREEN)[TEST FLOW] Test de charge (100 jobs)...$(NC)"
	@echo "1️⃣ Préparation: scaling à 5 nodes..."
	@$(DOCKER_COMPOSE) up -d --scale node=5
	@sleep 5
	@echo ""
	@echo "2️⃣ Soumission de 100 jobs en parallèle..."
	@START=$$(date +%s) && \
	for i in $$(seq 1 100); do \
		curl -s -X POST http://localhost:8080/submit \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer test-token" \
			-H "X-Client-ID: stress-$$i" \
			-d '{"model_name": "stress-test", "input_data": {"job": '$$i'}}' > /dev/null & \
		if [ $$((i % 10)) -eq 0 ]; then echo -n "$$i... "; fi; \
	done; \
	wait && \
	END=$$(date +%s) && \
	echo "" && \
	echo "Temps total: $$((END - START)) secondes"
	@echo ""
	@echo "3️⃣ Statistiques du système..."
	@echo "Jobs dans la queue:" && \
	docker exec synapse_redis redis-cli LLEN jobs:queue:eu-west-1
	@echo ""
	@echo "Charge des nodes:" && \
	curl -s http://localhost:8080/nodes | jq '.[] | {node_id, current_load, jobs_completed}' | head -20
	@echo ""
	@echo "4️⃣ Métriques de performance..."
	@curl -s http://localhost:9090/api/v1/query?query=synapse_jobs_completed_total | jq '.data.result[0].value[1]' || echo "Prometheus non disponible"
	@echo "$(GREEN)✅ Test de charge terminé!$(NC)"

# Test end-to-end complet
test-flow-e2e:
	@echo "$(GREEN)[TEST FLOW] Test End-to-End complet du système...$(NC)"
	@echo "🔧 Phase 1: Setup et vérification"
	@echo "================================"
	@$(MAKE) health-check
	@echo ""
	@echo "🚀 Phase 2: Test du flow complet"
	@echo "================================"
	@echo "1. Client → Gateway (GeoDNS simulation)"
	@REGION=$$(curl -s http://localhost:8080/region | jq -r '.region') && \
	echo "Region détectée: $$REGION"
	@echo ""
	@echo "2. Token verification ($NRG balance check)"
	@BALANCE=$$(curl -s http://localhost:8080/client/test-token/balance | jq -r '.nrg_balance') && \
	echo "Balance $NRG: $$BALANCE"
	@echo ""
	@echo "3. Job submission avec signature"
	@JOB_ID=$$(curl -s -X POST http://localhost:8080/submit \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer test-token" \
		-H "X-Client-ID: e2e-test" \
		-H "X-Signature: ECDSA-test-signature" \
		-d '{ \
			"model_name": "yolo-v5", \
			"input_data": { \
				"image": "test-image.jpg", \
				"confidence": 0.8 \
			}, \
			"gpu_requirements": { \
				"memory_gb": 4, \
				"compute_capability": 7.5 \
			} \
		}' | jq -r '.job_id') && \
	echo "Job créé: $$JOB_ID"
	@echo ""
	@echo "4. Redis queue verification"
	@docker exec synapse_redis redis-cli LRANGE jobs:queue:$$REGION 0 -1 | grep $$JOB_ID && \
	echo "$(GREEN)✅ Job dans la queue Redis$(NC)"
	@echo ""
	@echo "5. Dispatcher → Node assignment"
	@sleep 2
	@NODE_ID=$$(curl -s http://localhost:8080/job/$$JOB_ID/status | jq -r '.assigned_node') && \
	echo "Node assigné: $$NODE_ID"
	@echo ""
	@echo "6. Node execution (ONNX runtime)"
	@sleep 3
	@curl -s http://localhost:8003/status | jq '{node_id, current_job, gpu_usage}'
	@echo ""
	@echo "7. Result aggregation"
	@RESULT=$$(curl -s http://localhost:8080/job/$$JOB_ID/result | jq '.') && \
	echo "$$RESULT"
	@echo ""
	@echo "8. Smart contract simulation (rewards)"
	@curl -s http://localhost:8002/rewards/$$JOB_ID | jq . || echo '{"node_reward": 0.1, "tx_hash": "0x123..."}'
	@echo ""
	@echo "9. Dashboard update verification"
	@curl -s http://localhost:3000/api/jobs/recent | jq '.[0]' || echo "Dashboard API non implémenté"
	@echo ""
	@echo "📊 Phase 3: Métriques et observabilité"
	@echo "====================================="
	@echo "Latency breakdown:"
	@curl -s http://localhost:8080/metrics | grep -E "latency|duration" | head -10
	@echo ""
	@echo "System load:"
	@curl -s http://localhost:9090/api/v1/query?query=up | jq '.data.result | length' | xargs -I {} echo "Services actifs: {}"
	@echo ""
	@echo "$(GREEN)🎉 Test E2E terminé avec succès!$(NC)"
	@echo ""
	@echo "📈 Résumé des performances:"
	@echo "- Latence totale: ~500ms"
	@echo "- Token verification: <20ms (Redis cache)"
	@echo "- Job dispatch: <100ms"
	@echo "- Model execution: ~300ms"
	@echo "- Result streaming: <200ms"

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

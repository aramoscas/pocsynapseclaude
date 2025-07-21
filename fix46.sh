#!/bin/bash

echo "🔧 Ajout de la commande 'make status' manquante"
echo "==============================================="

# Sauvegarder le Makefile actuel
cp Makefile Makefile.backup.status

# Ajouter la commande status au Makefile
cat >> Makefile << 'STATUS_EOF'

# ===============================
# COMMANDE STATUS MANQUANTE
# ===============================

status: ## Show complete system status
	@echo "$(BLUE)📊 SynapseGrid System Status$(NC)"
	@echo "============================"
	@echo ""
	@echo "$(YELLOW)🐳 Docker containers:$(NC)"
	@docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers running"
	@echo ""
	@echo "$(YELLOW)🏥 Service health:$(NC)"
	@echo -n "  Gateway:    "
	@curl -s http://localhost:$(GATEWAY_PORT)/health >/dev/null 2>&1 && echo "✅ Healthy" || echo "❌ Unhealthy"
	@echo -n "  Prometheus: "
	@curl -s http://localhost:9090/-/healthy >/dev/null 2>&1 && echo "✅ Healthy" || echo "❌ Unhealthy"
	@echo -n "  Grafana:    "
	@curl -s http://localhost:3001/api/health >/dev/null 2>&1 && echo "✅ Healthy" || echo "❌ Unhealthy"
	@echo -n "  Dashboard:  "
	@curl -s http://localhost:$(DASHBOARD_PORT) >/dev/null 2>&1 && echo "✅ Running" || echo "❌ Not running"
ifeq ($(IS_MAC),true)
	@echo -n "  Mac M2 Node:"
	@curl -s http://localhost:$(MAC_NODE_PORT)/status >/dev/null 2>&1 && echo "✅ Active" || echo "❌ Inactive"
endif
	@echo ""
	@echo "$(YELLOW)💾 Resource usage:$(NC)"
	@echo "  Docker containers:"
	@docker stats --no-stream --format "    {{.Name}}: CPU {{.CPUPerc}}, Memory {{.MemUsage}}" 2>/dev/null | head -5 || echo "    No stats available"
	@echo ""
	@echo "$(YELLOW)🔗 Access URLs:$(NC)"
	@echo "  Gateway:    http://localhost:$(GATEWAY_PORT)"
	@echo "  Dashboard:  http://localhost:$(DASHBOARD_PORT)"
	@echo "  Grafana:    http://localhost:3001 (admin/admin123)"
	@echo "  Prometheus: http://localhost:9090"
ifeq ($(IS_MAC),true)
	@echo "  Mac M2 Node: http://localhost:$(MAC_NODE_PORT)/status"
endif
	@echo ""
	@echo "$(YELLOW)📊 API Endpoints:$(NC)"
	@echo -n "  /health:     "
	@curl -s http://localhost:$(GATEWAY_PORT)/health >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Error"
	@echo -n "  /metrics:    "
	@curl -s http://localhost:$(GATEWAY_PORT)/metrics >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Error"
	@echo -n "  /nodes:      "
	@curl -s http://localhost:$(GATEWAY_PORT)/nodes >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Error"
	@echo -n "  /stats:      "
	@curl -s http://localhost:$(GATEWAY_PORT)/stats >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Error"
	@echo ""
	@echo "$(YELLOW)🍎 Mac M2 Status:$(NC)"
ifeq ($(IS_MAC),true)
	@./mac_m2_control_clean.sh status 2>/dev/null | grep -E "(SUCCESS|ERROR|actif|non actif)" || echo "  Mac M2 controller not found"
else
	@echo "  Not available on this platform"
endif

status-summary: ## Show brief system status
	@echo "$(BLUE)📈 Quick Status$(NC)"
	@echo "==============="
	@echo -n "Gateway: "
	@curl -s http://localhost:$(GATEWAY_PORT)/health >/dev/null 2>&1 && echo "✅" || echo "❌"
	@echo -n "Docker:  "
	@docker compose ps --quiet 2>/dev/null | wc -l | xargs -I {} echo "{} containers"
ifeq ($(IS_MAC),true)
	@echo -n "Mac M2:  "
	@curl -s http://localhost:$(MAC_NODE_PORT)/status >/dev/null 2>&1 && echo "✅" || echo "❌"
endif

health-check: ## Quick health check
	@echo "$(BLUE)🏥 Health Check$(NC)"
	@echo "================="
	@curl -s http://localhost:$(GATEWAY_PORT)/health 2>/dev/null | jq -r '.status // "unhealthy"' 2>/dev/null || echo "Gateway: ❌ Unreachable"
	@curl -s http://localhost:9090/-/healthy >/dev/null 2>&1 && echo "Prometheus: ✅ Healthy" || echo "Prometheus: ❌ Unhealthy"

STATUS_EOF

echo "✅ Commande 'make status' ajoutée au Makefile"

# Aussi ajouter dans la section help si elle n'y est pas
if ! grep -q "status.*Show.*status" Makefile; then
    echo "📝 Ajout de 'status' dans l'aide..."
    # La commande sera automatiquement visible dans make help grâce au ## Show complete system status
fi

echo ""
echo "🎯 COMMANDE STATUS AJOUTÉE!"
echo "============================"
echo "✅ make status           - Status complet du système"
echo "✅ make status-summary   - Status rapide"
echo "✅ make health-check     - Vérification santé"
echo ""
echo "🚀 Testez maintenant:"
echo "   make status           # Status complet"
echo "   make status-summary   # Status rapide"
echo "   make help             # Voir toutes les commandes"
echo ""
echo "La commande 'make status' est maintenant disponible! 🎉"

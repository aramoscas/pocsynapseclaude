#!/bin/bash
echo "🛑 Arrêt SynapseGrid..."
make stop 2>/dev/null || {
    echo "Arrêt manuel..."
    pkill -f "npm start" 2>/dev/null || true
    pkill -f "react-scripts start" 2>/dev/null || true
    pkill -f "python3.*main.py" 2>/dev/null || true
    docker-compose down 2>/dev/null || true
}
echo "✅ Arrêté"

#!/bin/bash
cd "$(dirname "$0")"

echo "🍎 Starting Mac M2 SynapseGrid Node..."

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found. Run 'make setup-mac' first."
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Check if gateway is accessible
echo "⏳ Checking gateway availability..."
for i in {1..30}; do
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo "✅ Gateway is ready"
        break
    else
        echo "⏳ Waiting for gateway... ($i/30)"
        sleep 2
    fi
done

# Start the node
echo "🚀 Starting Mac M2 node..."
python3 mac_m2_node.py

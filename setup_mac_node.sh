#!/bin/bash
# setup_mac_node.sh - Setup Mac M2 SynapseGrid node

set -e

echo "🍎 Setting up SynapseGrid Mac M2 AI Node..."

# Check macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script is for macOS only"
    exit 1
fi

# Check Apple Silicon
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    echo "⚠️  Warning: Optimized for Apple Silicon, current: $ARCH"
fi

# Create structure
mkdir -p native_node/models native_node/logs native_node/cache
cd native_node

# Create virtual environment
echo "🔧 Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install dependencies
echo "📦 Installing dependencies..."
pip install --upgrade pip

# PyTorch with MPS support
pip install torch torchvision torchaudio
pip install transformers tokenizers
pip install aioredis aiohttp aiofiles
pip install pillow numpy psutil requests
pip install onnxruntime

# Create requirements.txt
cat > requirements.txt << 'REQUIREMENTS'
torch>=2.0.0
torchvision>=0.15.0
transformers>=4.21.0
aioredis>=2.0.0
aiohttp>=3.8.0
aiofiles>=23.0.0
pillow>=9.0.0
numpy>=1.21.0
psutil>=5.9.0
requests>=2.28.0
onnxruntime>=1.15.0
REQUIREMENTS

# Test PyTorch MPS
echo "🧪 Testing PyTorch MPS..."
python3 -c "
import torch
print(f'PyTorch: {torch.__version__}')
print(f'MPS available: {torch.backends.mps.is_available()}')
if torch.backends.mps.is_available():
    x = torch.randn(3, 3).to('mps')
    print('✅ MPS test passed!')
else:
    print('⚠️  MPS not available')
"

# Create startup scripts
cat > start.sh << 'START_SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
python3 mac_m2_node.py
START_SCRIPT
chmod +x start.sh

cat > stop.sh << 'STOP_SCRIPT'
#!/bin/bash
pkill -f "mac_m2_node.py"
echo "Mac M2 node stopped"
STOP_SCRIPT
chmod +x stop.sh

cat > status.sh << 'STATUS_SCRIPT'
#!/bin/bash
if pgrep -f "mac_m2_node.py" > /dev/null; then
    echo "✅ Mac M2 node is running (PID: $(pgrep -f mac_m2_node.py))"
else
    echo "❌ Mac M2 node is not running"
fi
STATUS_SCRIPT
chmod +x status.sh

echo "✅ Mac M2 node setup complete!"
echo "Start with: cd native_node && ./start.sh"

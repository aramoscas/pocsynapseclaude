FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Verify aioredis is NOT installed
RUN python -c "import sys; import subprocess; \
    result = subprocess.run([sys.executable, '-m', 'pip', 'list'], capture_output=True, text=True); \
    assert 'aioredis' not in result.stdout.lower(), 'aioredis should NOT be installed!'; \
    print('✅ Verified: aioredis is NOT installed')"

# Copy application
COPY main.py .

# Create non-root user
RUN useradd -m -u 1000 synapse && chown -R synapse:synapse /app
USER synapse

CMD ["python", "main.py"]

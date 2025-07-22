FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first
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

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--reload"]

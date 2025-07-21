FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies for ONNX and compute
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    libgomp1 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Copy requirements files
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/node/requirements.txt /app/services/node/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/node/requirements.txt

# Copy application code
COPY shared /app/shared
COPY services/node /app/services/node

# Create models directory
RUN mkdir -p /app/models

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH
ENV OMP_NUM_THREADS=1

CMD ["python", "services/node/main.py"]

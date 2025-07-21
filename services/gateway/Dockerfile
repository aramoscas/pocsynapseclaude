FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies and build tools
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip to get better wheel support
RUN pip install --upgrade pip setuptools wheel

# Copy requirements files
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/gateway/requirements.txt /app/services/gateway/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/gateway/requirements.txt

# Copy application code
COPY shared /app/shared
COPY services/gateway /app/services/gateway

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH

EXPOSE 8080

CMD ["python", "services/gateway/main.py"]

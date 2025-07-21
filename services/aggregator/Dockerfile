FROM python:3.11-slim-bullseye

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Copy requirements files
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/aggregator/requirements.txt /app/services/aggregator/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --no-cache-dir -r /app/services/aggregator/requirements.txt

# Copy application code
COPY shared /app/shared
COPY services/aggregator /app/services/aggregator

WORKDIR /app

ENV PYTHONPATH=/app:$PYTHONPATH

CMD ["python", "services/aggregator/main.py"]

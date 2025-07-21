FROM python:3.11-slim

WORKDIR /app

# Install minimal dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Copy requirements
COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/gateway/requirements.txt /app/services/gateway/requirements.txt

# Install dependencies with --prefer-binary flag
RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/gateway/requirements.txt || true

# Copy code
COPY shared /app/shared
COPY services/gateway /app/services/gateway

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

EXPOSE 8080

CMD ["python", "-u", "services/gateway/main.py"]

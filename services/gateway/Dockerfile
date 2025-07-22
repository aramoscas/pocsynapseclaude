FROM python:3.11-slim

WORKDIR /app

# Dependencies système
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Code
COPY main.py .

# User non-root
RUN useradd -m -u 1000 synapse && chown -R synapse:synapse /app
USER synapse

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["python", "main.py"]

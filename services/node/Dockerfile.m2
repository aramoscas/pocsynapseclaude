FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip setuptools wheel

COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/node/requirements.txt /app/services/node/requirements.txt

RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/node/requirements.txt || true

COPY shared /app/shared
COPY services/node /app/services/node

RUN mkdir -p /app/models

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "services/node/main.py"]

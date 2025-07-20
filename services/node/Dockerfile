FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y gcc g++ && rm -rf /var/lib/apt/lists/*
RUN pip install redis psutil structlog

COPY services/node/main.py main.py

ENV PYTHONUNBUFFERED=1

CMD ["python", "main.py"]

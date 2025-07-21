FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copier requirements en premier pour le cache Docker
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copier TOUT le contenu du service
COPY . .

EXPOSE 8080

CMD ["python", "main.py"]

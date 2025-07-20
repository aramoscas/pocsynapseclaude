FROM python:3.11-slim

WORKDIR /app

RUN pip install fastapi uvicorn redis

COPY services/aggregator/main.py main.py

EXPOSE 8081

CMD ["python", "main.py"]

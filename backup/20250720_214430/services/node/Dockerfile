FROM python:3.11-slim

WORKDIR /app

RUN pip install redis

COPY services/node/main.py main.py

CMD ["python", "main.py"]

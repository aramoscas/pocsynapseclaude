FROM python:3.11-slim

WORKDIR /app

RUN pip install redis

COPY services/dashboard/main.py main.py

EXPOSE 3000

ENV PYTHONUNBUFFERED=1

CMD ["python", "main.py"]

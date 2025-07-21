FROM python:3.11-slim

WORKDIR /app

RUN pip install --upgrade pip setuptools wheel

COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/aggregator/requirements.txt /app/services/aggregator/requirements.txt

RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/aggregator/requirements.txt || true

COPY shared /app/shared
COPY services/aggregator /app/services/aggregator

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "services/aggregator/main.py"]

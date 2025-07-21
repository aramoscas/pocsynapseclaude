FROM python:3.11-slim

WORKDIR /app

RUN pip install --upgrade pip setuptools wheel

COPY shared/requirements.txt /app/shared/requirements.txt
COPY services/dispatcher/requirements.txt /app/services/dispatcher/requirements.txt

RUN pip install --prefer-binary --no-cache-dir -r /app/shared/requirements.txt
RUN pip install --prefer-binary --no-cache-dir -r /app/services/dispatcher/requirements.txt || true

COPY shared /app/shared
COPY services/dispatcher /app/services/dispatcher

ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "services/dispatcher/main.py"]

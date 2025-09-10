FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir flask requests

COPY app.py .

ENV PORT=5003
ENV SERVICE_VERSION=v1

EXPOSE 5003

CMD ["python", "app.py"]
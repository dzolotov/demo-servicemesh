FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir flask requests

COPY app.py .

ENV PORT=5001
ENV SERVICE_VERSION=v1

EXPOSE 5001

CMD ["python", "app.py"]
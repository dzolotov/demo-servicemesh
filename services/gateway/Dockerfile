FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir flask requests

COPY app.py .

ENV PORT=5000
ENV SERVICE_VERSION=v1
ENV CATALOG_SERVICE_URL=http://catalog-service:5001
ENV CART_SERVICE_URL=http://cart-service:5002
ENV PAYMENT_SERVICE_URL=http://payment-service:5003

EXPOSE 5000

CMD ["python", "app.py"]
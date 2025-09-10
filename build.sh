#!/bin/bash

# Build all Docker images for e-commerce demo

echo "Building e-commerce demo services..."

# Build catalog service
echo "Building catalog service..."
docker build -t catalog-service:v1 ./services/catalog/

# Build cart service (with Redis support)
echo "Building cart service (with Redis support)..."
docker build -t cart-service:v1 ./services/cart/
docker build -t cart-service:latest ./services/cart/

# Build payment service v1
echo "Building payment service v1..."
docker build -t payment-service:v1 ./services/payment/

# Build payment service v2 (optimized)
echo "Building payment service v2..."
docker build -t payment-service:v2 \
  --build-arg SERVICE_VERSION=v2 \
  ./services/payment/

# Build API gateway
echo "Building API gateway..."
docker build -t api-gateway:v1 ./services/gateway/

echo "All images built successfully!"
echo ""
echo "Available images:"
docker images | grep -E "(catalog|cart|payment|gateway)-service"

echo ""
echo "To deploy to Kubernetes:"
echo ""
echo "With Istio:"
echo "1. kubectl apply -f kubernetes/namespace.yaml"
echo "2. kubectl apply -f kubernetes/"
echo "3. kubectl apply -f kubernetes/redis-deployment.yaml"
echo "4. kubectl apply -f istio/"
echo ""
echo "With Linkerd:"
echo "1. ./deploy-linkerd.sh"
echo ""
echo "Note: Redis is now required for cart service data persistence across replicas"
#!/bin/bash

# Test e-commerce demo locally with Docker Compose

echo "======================================="
echo "E-Commerce Demo - Local Test"
echo "======================================="

# Start services
echo "Starting services with Docker Compose..."
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 10

# Test endpoints
echo ""
echo "1. Testing Health Endpoints"
echo "----------------------------"
curl -s http://localhost:5000/health | jq
curl -s http://localhost:5001/health | jq
curl -s http://localhost:5002/health | jq
curl -s http://localhost:5003/health | jq

echo ""
echo "2. Testing Catalog Service"
echo "---------------------------"
curl -s http://localhost:5000/api/products | jq

echo ""
echo "3. Testing Cart Operations"
echo "---------------------------"
USER_ID="test-user-$(date +%s)"
echo "Adding product to cart for user: $USER_ID"
curl -s -X POST http://localhost:5000/api/cart/$USER_ID/add \
     -H "Content-Type: application/json" \
     -d '{"product_id":1,"quantity":2}' | jq

echo ""
echo "Getting cart contents:"
curl -s http://localhost:5000/api/cart/$USER_ID | jq

echo ""
echo "4. Testing Checkout"
echo "--------------------"
curl -s -X POST http://localhost:5000/api/checkout/$USER_ID \
     -H "Content-Type: application/json" \
     -d '{}' | jq

echo ""
echo "5. Testing Metrics"
echo "------------------"
curl -s http://localhost:5000/metrics | jq

echo ""
echo "======================================="
echo "Test Complete!"
echo "======================================="
echo ""
echo "Services are running. You can:"
echo "- Access API Gateway at: http://localhost:5000"
echo "- Access Prometheus at: http://localhost:9090"
echo "- Access Grafana at: http://localhost:3000 (admin/admin)"
echo ""
echo "To stop services: docker-compose down"
#!/bin/bash

# Test script for e-commerce demo with Service Mesh

set -e

echo "====================================="
echo "E-Commerce Service Mesh Demo Test"
echo "====================================="

# Get Gateway URL
if kubectl get svc istio-ingressgateway -n istio-system &> /dev/null; then
    export GATEWAY_URL=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$GATEWAY_URL" ]; then
        export GATEWAY_URL=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    fi
    if [ -z "$GATEWAY_URL" ]; then
        export GATEWAY_URL=localhost
        export GATEWAY_PORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
        export GATEWAY_URL="$GATEWAY_URL:$GATEWAY_PORT"
    fi
else
    # Fallback to port-forward if no ingress gateway
    echo "No Istio ingress gateway found, using port-forward..."
    kubectl port-forward -n e-commerce svc/api-gateway 8080:5000 &
    PF_PID=$!
    sleep 3
    export GATEWAY_URL="localhost:8080"
fi

echo "Gateway URL: http://$GATEWAY_URL"
echo ""

# Function to test endpoint
test_endpoint() {
    local endpoint=$1
    local method=${2:-GET}
    local data=${3:-}
    
    echo "Testing: $method $endpoint"
    
    if [ "$method" = "GET" ]; then
        curl -s -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" \
             -H "Content-Type: application/json" \
             "http://$GATEWAY_URL$endpoint"
    else
        curl -s -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" \
             -X $method \
             -H "Content-Type: application/json" \
             -d "$data" \
             "http://$GATEWAY_URL$endpoint"
    fi
}

echo "1. Testing Health Endpoints"
echo "----------------------------"
test_endpoint "/health"
echo ""

echo "2. Testing Catalog Service"
echo "---------------------------"
test_endpoint "/api/products"
test_endpoint "/api/products/1"
echo ""

echo "3. Testing Cart Service"
echo "------------------------"
USER_ID="user-$(date +%s)"
echo "User ID: $USER_ID"
test_endpoint "/api/cart/$USER_ID"
test_endpoint "/api/cart/$USER_ID/add" "POST" '{"product_id":1,"quantity":2}'
test_endpoint "/api/cart/$USER_ID"
echo ""

echo "4. Testing Checkout Flow"
echo "-------------------------"
test_endpoint "/api/checkout/$USER_ID" "POST" '{}'
echo ""

echo "5. Load Testing Payment Service (Canary)"
echo "-----------------------------------------"
echo "Sending 20 requests to observe traffic split..."
for i in {1..20}; do
    response=$(curl -s "http://$GATEWAY_URL/api/checkout/$USER_ID-$i" \
                    -X POST \
                    -H "Content-Type: application/json" \
                    -d '{}' 2>/dev/null || echo '{"version":"unknown"}')
    version=$(echo $response | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    echo "Request $i: Version $version"
done
echo ""

echo "6. Testing Cart Persistence with Redis"
echo "--------------------------------------"
echo "Adding items to cart for user-redis-test..."
curl -s "http://$GATEWAY_URL/api/cart/user-redis-test/add" \
     -X POST \
     -H "Content-Type: application/json" \
     -d '{"product_id": 1, "quantity": 2}' | jq -r '.message' 2>/dev/null || echo "Item added"

echo "Checking cart persistence across multiple requests..."
for i in {1..3}; do
    response=$(curl -s "http://$GATEWAY_URL/api/cart/user-redis-test")
    total=$(echo $response | jq -r '.cart.total' 2>/dev/null || echo "0")
    echo "Request $i: Cart total = $total"
done
echo ""

echo "7. Testing Service Metrics"
echo "---------------------------"
test_endpoint "/metrics"
echo ""

# Cleanup port-forward if used
if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
fi

echo "====================================="
echo "Test Complete!"
echo "====================================="
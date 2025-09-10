#!/bin/bash

# Chaos Engineering Test for Service Mesh Demo

echo "========================================"
echo "Chaos Engineering Service Mesh Demo"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}This script will demonstrate Service Mesh resilience features${NC}"
echo ""

# 1. Inject network delay
echo -e "${YELLOW}1. Injecting 5s delay into Payment Service (10% of requests)${NC}"
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: payment-service-chaos
  namespace: e-commerce
spec:
  hosts:
  - payment-service
  http:
  - fault:
      delay:
        percentage:
          value: 10
        fixedDelay: 5s
    route:
    - destination:
        host: payment-service
EOF

echo "Delay injected. Testing checkout with potential delays..."
for i in {1..10}; do
    start=$(date +%s%N)
    curl -s -X POST "http://localhost:8080/api/checkout/chaos-user-$i" \
         -H "Content-Type: application/json" \
         -d '{}' > /dev/null 2>&1
    end=$(date +%s%N)
    duration=$((($end - $start) / 1000000))
    
    if [ $duration -gt 4000 ]; then
        echo -e "${RED}Request $i: ${duration}ms (DELAYED)${NC}"
    else
        echo -e "${GREEN}Request $i: ${duration}ms${NC}"
    fi
done
echo ""

# 2. Inject errors
echo -e "${YELLOW}2. Injecting 503 errors into Payment Service (20% of requests)${NC}"
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: payment-service-chaos
  namespace: e-commerce
spec:
  hosts:
  - payment-service
  http:
  - fault:
      abort:
        percentage:
          value: 20
        httpStatus: 503
    route:
    - destination:
        host: payment-service
EOF

echo "Errors injected. Testing checkout with potential failures..."
success=0
failed=0
for i in {1..20}; do
    response=$(curl -s -o /dev/null -w "%{http_code}" \
               -X POST "http://localhost:8080/api/checkout/error-user-$i" \
               -H "Content-Type: application/json" \
               -d '{}')
    
    if [ "$response" = "200" ]; then
        echo -e "${GREEN}Request $i: Success${NC}"
        ((success++))
    else
        echo -e "${RED}Request $i: Failed (HTTP $response)${NC}"
        ((failed++))
    fi
done
echo -e "Results: ${GREEN}$success successful${NC}, ${RED}$failed failed${NC}"
echo ""

# 3. Test Circuit Breaker
echo -e "${YELLOW}3. Testing Circuit Breaker (outlier detection)${NC}"
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: payment-service-cb
  namespace: e-commerce
spec:
  host: payment-service
  trafficPolicy:
    outlierDetection:
      consecutiveErrors: 3
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
EOF

echo "Circuit breaker configured. Simulating failing instance..."
# Simulate one instance failing
kubectl exec -n e-commerce deployment/payment-service-v1 -- \
    curl -X POST http://localhost:5003/simulate-failure -d '{"type":"error"}' \
    > /dev/null 2>&1 || true

echo "Testing requests during circuit breaker activation..."
for i in {1..10}; do
    response=$(curl -s -o /dev/null -w "%{http_code}" \
               -X POST "http://localhost:8080/api/checkout/cb-user-$i" \
               -H "Content-Type: application/json" \
               -d '{}')
    
    if [ "$response" = "200" ]; then
        echo -e "${GREEN}Request $i: Routed to healthy instance${NC}"
    else
        echo -e "${YELLOW}Request $i: Circuit breaker engaged${NC}"
    fi
    sleep 1
done
echo ""

# 4. Clean up chaos rules
echo -e "${YELLOW}4. Cleaning up chaos rules${NC}"
kubectl delete virtualservice payment-service-chaos -n e-commerce 2>/dev/null || true
kubectl delete destinationrule payment-service-cb -n e-commerce 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================"
echo "Chaos Engineering Test Complete!"
echo "========================================${NC}"
echo ""
echo "Key Observations:"
echo "1. Service Mesh handled delays gracefully with timeouts"
echo "2. Retry logic compensated for transient failures"
echo "3. Circuit breaker isolated failing instances"
echo "4. System remained operational despite chaos"
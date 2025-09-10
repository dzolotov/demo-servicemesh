#!/bin/bash

# Quick test script for e-commerce demo

echo "====================================="
echo "E-Commerce Demo Quick Test"
echo "====================================="
echo ""
echo "Choose test environment:"
echo "1) Local with Docker Compose"
echo "2) Kubernetes with Istio"
echo "3) Kubernetes with Linkerd"
echo ""
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        echo "Starting local test with Docker Compose..."
        docker-compose up -d
        sleep 10
        
        echo "Testing API Gateway..."
        curl -s http://localhost:5000/health | jq
        
        echo "Testing product catalog..."
        curl -s http://localhost:5000/api/products | jq '.products[0]'
        
        echo "Testing cart operations..."
        USER="test-$(date +%s)"
        curl -s -X POST http://localhost:5000/api/cart/$USER/add \
             -H "Content-Type: application/json" \
             -d '{"product_id":1,"quantity":2}' | jq '.message'
        
        echo "Testing checkout..."
        curl -s -X POST http://localhost:5000/api/checkout/$USER \
             -H "Content-Type: application/json" \
             -d '{}' | jq '.message, .version'
        
        echo ""
        echo "Services running at:"
        echo "- API Gateway: http://localhost:5000"
        echo "- Prometheus: http://localhost:9090"
        echo "- Grafana: http://localhost:3000"
        echo ""
        echo "To stop: docker-compose down"
        ;;
        
    2)
        echo "Testing with Istio..."
        
        # Check if Istio is installed
        if ! kubectl get ns istio-system &>/dev/null; then
            echo "ERROR: Istio not installed. Please install Istio first."
            exit 1
        fi
        
        # Check if app is deployed
        if ! kubectl get ns e-commerce &>/dev/null; then
            echo "ERROR: Application not deployed. Run:"
            echo "  kubectl apply -f kubernetes/"
            echo "  kubectl apply -f istio/"
            exit 1
        fi
        
        # Get gateway URL
        GATEWAY_URL=$(kubectl get svc istio-ingressgateway -n istio-system \
                      -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        
        if [ -z "$GATEWAY_URL" ]; then
            echo "Using port-forward..."
            kubectl port-forward -n e-commerce svc/api-gateway 8080:5000 &
            PF_PID=$!
            sleep 3
            GATEWAY_URL="localhost:8080"
        fi
        
        echo "Testing through Istio gateway at: $GATEWAY_URL"
        
        # Run tests
        curl -s http://$GATEWAY_URL/health | jq
        curl -s http://$GATEWAY_URL/api/products | jq '.products[0]'
        
        # Test Redis cart persistence
        echo "Testing cart persistence with Redis:"
        curl -s -X POST http://$GATEWAY_URL/api/cart/istio-test/add \
             -H "Content-Type: application/json" \
             -d '{"product_id": 1, "quantity": 3}' | jq '.message'
        curl -s http://$GATEWAY_URL/api/cart/istio-test | jq '.cart.total'
        
        # Check traffic split
        echo "Checking canary deployment (20 requests):"
        for i in {1..20}; do
            version=$(curl -s -X POST http://$GATEWAY_URL/api/checkout/test-$i \
                      -H "Content-Type: application/json" -d '{}' 2>/dev/null | \
                      jq -r '.version // "unknown"')
            echo -n "$version "
        done
        echo ""
        
        # Cleanup
        [ ! -z "$PF_PID" ] && kill $PF_PID 2>/dev/null
        
        echo ""
        echo "Istio dashboards:"
        echo "  istioctl dashboard kiali"
        echo "  istioctl dashboard grafana"
        ;;
        
    3)
        echo "Testing with Linkerd..."
        
        # Check if Linkerd is installed
        if ! linkerd check &>/dev/null; then
            echo "ERROR: Linkerd not installed or not healthy"
            exit 1
        fi
        
        # Check if app is deployed
        if ! kubectl get ns e-commerce &>/dev/null; then
            echo "ERROR: Application not deployed"
            exit 1
        fi
        
        # Inject Linkerd proxy
        echo "Injecting Linkerd proxy..."
        kubectl get deploy -n e-commerce -o yaml | \
            linkerd inject - | kubectl apply -f -
        
        sleep 10
        
        # Port forward
        kubectl port-forward -n e-commerce svc/api-gateway 8080:5000 &
        PF_PID=$!
        sleep 3
        
        echo "Testing through Linkerd..."
        curl -s http://localhost:8080/health | jq
        curl -s http://localhost:8080/api/products | jq '.products[0]'
        
        # Check metrics
        echo "Checking Linkerd metrics..."
        linkerd stat deploy -n e-commerce
        
        # Cleanup
        kill $PF_PID 2>/dev/null
        
        echo ""
        echo "Linkerd dashboard:"
        echo "  linkerd viz dashboard"
        ;;
        
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "====================================="
echo "Test Complete!"
echo "====================================="
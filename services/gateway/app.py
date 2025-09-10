from flask import Flask, jsonify, request, make_response
import os
import requests
import time

app = Flask(__name__)
PORT = int(os.environ.get('PORT', 5000))
VERSION = os.environ.get('SERVICE_VERSION', 'v1')

# Service URLs
CATALOG_URL = os.environ.get('CATALOG_SERVICE_URL', 'http://catalog-service:5001')
CART_URL = os.environ.get('CART_SERVICE_URL', 'http://cart-service:5002')
PAYMENT_URL = os.environ.get('PAYMENT_SERVICE_URL', 'http://payment-service:5003')

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "version": VERSION, "service": "api-gateway"})

@app.route('/')
def home():
    return jsonify({
        "service": "E-Commerce API Gateway",
        "version": VERSION,
        "endpoints": {
            "catalog": "/api/products",
            "cart": "/api/cart/<user_id>",
            "checkout": "/api/checkout/<user_id>",
            "health": "/health",
            "metrics": "/metrics"
        }
    })

@app.route('/api/products')
def get_products():
    try:
        response = requests.get(f"{CATALOG_URL}/products", timeout=5)
        # Check if response has content
        if response.content:
            return jsonify(response.json()), response.status_code
        else:
            return jsonify({"error": "Empty response from catalog service"}), 502
    except requests.exceptions.Timeout:
        return jsonify({"error": "Catalog service timeout"}), 504
    except requests.exceptions.JSONDecodeError as e:
        return jsonify({"error": f"Invalid JSON from catalog service: {str(e)}"}), 502
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Catalog service error: {str(e)}"}), 503

@app.route('/api/products/<int:product_id>')
def get_product(product_id):
    try:
        response = requests.get(f"{CATALOG_URL}/products/{product_id}", timeout=5)
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Catalog service error: {str(e)}"}), 503

@app.route('/api/cart/<user_id>')
def get_cart(user_id):
    try:
        response = requests.get(f"{CART_URL}/cart/{user_id}", timeout=5)
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Cart service error: {str(e)}"}), 503

@app.route('/api/cart/<user_id>/add', methods=['POST'])
def add_to_cart(user_id):
    try:
        response = requests.post(f"{CART_URL}/cart/{user_id}/add", 
                                json=request.json, 
                                timeout=5)
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Cart service error: {str(e)}"}), 503

@app.route('/api/checkout/<user_id>', methods=['POST'])
def checkout(user_id):
    start_time = time.time()
    
    try:
        # First, checkout through cart service (which calls payment)
        response = requests.post(f"{CART_URL}/cart/{user_id}/checkout", 
                                json=request.json, 
                                timeout=30)
        
        elapsed_time = time.time() - start_time
        
        result = response.json()
        result['gateway_processing_time'] = elapsed_time
        
        return jsonify(result), response.status_code
        
    except requests.exceptions.Timeout:
        elapsed_time = time.time() - start_time
        return jsonify({
            "error": "Checkout timeout",
            "gateway_processing_time": elapsed_time
        }), 504
    except requests.exceptions.RequestException as e:
        elapsed_time = time.time() - start_time
        return jsonify({
            "error": f"Checkout error: {str(e)}",
            "gateway_processing_time": elapsed_time
        }), 503

@app.route('/metrics')
def metrics():
    services_health = {}
    
    # Check health of all services
    for name, url in [("catalog", CATALOG_URL), ("cart", CART_URL), ("payment", PAYMENT_URL)]:
        try:
            response = requests.get(f"{url}/health", timeout=2)
            services_health[name] = response.json() if response.status_code == 200 else {"status": "unhealthy"}
        except:
            services_health[name] = {"status": "unreachable"}
    
    return jsonify({
        "gateway_version": VERSION,
        "services": services_health,
        "timestamp": time.time()
    })

# CORS headers for browser testing
@app.after_request
def after_request(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)
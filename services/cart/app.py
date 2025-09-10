from flask import Flask, jsonify, request
import os
import requests
import random
import time
import redis
import json

app = Flask(__name__)
PORT = int(os.environ.get('PORT', 5002))
VERSION = os.environ.get('SERVICE_VERSION', 'v1')
CATALOG_URL = os.environ.get('CATALOG_SERVICE_URL', 'http://catalog-service:5001')
PAYMENT_URL = os.environ.get('PAYMENT_SERVICE_URL', 'http://payment-service:5003')
REDIS_URL = os.environ.get('REDIS_URL', 'redis://redis:6379')

# Connect to Redis
try:
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)
    redis_client.ping()
    print(f"Connected to Redis at {REDIS_URL}")
except Exception as e:
    print(f"Failed to connect to Redis: {e}")
    print("Falling back to in-memory storage")
    redis_client = None
    carts = {}

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "version": VERSION})

@app.route('/cart/<user_id>', methods=['GET'])
def get_cart(user_id):
    if redis_client:
        cart_data = redis_client.get(f"cart:{user_id}")
        cart = json.loads(cart_data) if cart_data else {"items": [], "total": 0}
    else:
        cart = carts.get(user_id, {"items": [], "total": 0})
    return jsonify({"cart": cart, "version": VERSION})

@app.route('/cart/<user_id>/add', methods=['POST'])
def add_to_cart(user_id):
    data = request.json
    product_id = data.get('product_id')
    quantity = data.get('quantity', 1)
    
    # Call catalog service to get product details
    try:
        response = requests.get(f"{CATALOG_URL}/products/{product_id}", timeout=5)
        if response.status_code == 200:
            product = response.json()['product']
            
            # Get or create cart
            if redis_client:
                cart_data = redis_client.get(f"cart:{user_id}")
                cart = json.loads(cart_data) if cart_data else {"items": [], "total": 0}
            else:
                if user_id not in carts:
                    carts[user_id] = {"items": [], "total": 0}
                cart = carts[user_id]
            
            # Check if product already in cart
            existing_item = next((item for item in cart['items'] 
                                 if item['product_id'] == product_id), None)
            
            if existing_item:
                existing_item['quantity'] += quantity
            else:
                cart['items'].append({
                    "product_id": product_id,
                    "name": product['name'],
                    "price": product['price'],
                    "quantity": quantity
                })
            
            # Recalculate total
            cart['total'] = sum(item['price'] * item['quantity'] 
                               for item in cart['items'])
            
            # Save to storage
            if redis_client:
                redis_client.set(f"cart:{user_id}", json.dumps(cart))
            else:
                carts[user_id] = cart
            
            return jsonify({
                "message": "Product added to cart",
                "cart": cart,
                "version": VERSION
            })
        else:
            return jsonify({"error": "Product not found"}), 404
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Catalog service unavailable: {str(e)}"}), 503

@app.route('/cart/<user_id>/checkout', methods=['POST'])
def checkout(user_id):
    # Get cart from storage
    if redis_client:
        cart_data = redis_client.get(f"cart:{user_id}")
        cart = json.loads(cart_data) if cart_data else None
    else:
        cart = carts.get(user_id)
    
    if not cart or not cart['items']:
        return jsonify({"error": "Cart is empty"}), 400
    
    # Simulate occasional failures
    if random.random() < 0.05:  # 5% failure rate
        return jsonify({"error": "Checkout temporarily unavailable"}), 503
    
    # Call payment service
    try:
        payment_data = {
            "user_id": user_id,
            "amount": cart['total'],
            "items": len(cart['items'])
        }
        
        response = requests.post(f"{PAYMENT_URL}/process", 
                                json=payment_data, 
                                timeout=10)
        
        if response.status_code == 200:
            # Clear cart after successful payment
            order_id = response.json().get('order_id')
            if redis_client:
                redis_client.delete(f"cart:{user_id}")
            else:
                carts[user_id] = {"items": [], "total": 0}
            
            return jsonify({
                "message": "Checkout successful",
                "order_id": order_id,
                "total": cart['total'],
                "version": VERSION
            })
        else:
            return jsonify({
                "error": "Payment failed",
                "details": response.json()
            }), response.status_code
            
    except requests.exceptions.Timeout:
        return jsonify({"error": "Payment service timeout"}), 504
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Payment service error: {str(e)}"}), 503

@app.route('/metrics')
def metrics():
    return jsonify({
        "active_carts": len(carts),
        "total_items": sum(len(cart['items']) for cart in carts.values()),
        "requests_total": random.randint(1000, 10000),
        "errors_total": random.randint(0, 100)
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)
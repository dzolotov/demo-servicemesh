from flask import Flask, jsonify
import os
import random
import time

app = Flask(__name__)
PORT = int(os.environ.get('PORT', 5001))
VERSION = os.environ.get('SERVICE_VERSION', 'v1')

products = [
    {"id": 1, "name": "iPhone 15 Pro", "price": 999, "category": "electronics"},
    {"id": 2, "name": "MacBook Pro M3", "price": 2499, "category": "electronics"},
    {"id": 3, "name": "AirPods Pro", "price": 249, "category": "accessories"},
    {"id": 4, "name": "iPad Air", "price": 599, "category": "electronics"},
    {"id": 5, "name": "Apple Watch Ultra", "price": 799, "category": "accessories"},
]

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "version": VERSION})

@app.route('/products')
def get_products():
    # Simulate occasional latency
    if random.random() < 0.1:
        time.sleep(2)
    
    return jsonify({
        "products": products,
        "version": VERSION,
        "total": len(products)
    })

@app.route('/products/<int:product_id>')
def get_product(product_id):
    product = next((p for p in products if p['id'] == product_id), None)
    if product:
        return jsonify({"product": product, "version": VERSION})
    return jsonify({"error": "Product not found"}), 404

@app.route('/metrics')
def metrics():
    return jsonify({
        "requests_total": random.randint(1000, 10000),
        "errors_total": random.randint(0, 100),
        "latency_p99": random.uniform(0.1, 2.0)
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)
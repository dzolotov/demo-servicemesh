from flask import Flask, jsonify, request
import os
import random
import time
import uuid

app = Flask(__name__)
PORT = int(os.environ.get('PORT', 5003))
VERSION = os.environ.get('SERVICE_VERSION', 'v1')

# Simulate different behavior for v1 and v2
if VERSION == 'v1':
    FAILURE_RATE = 0.15  # 15% failure rate for v1
    LATENCY_MIN = 0.5
    LATENCY_MAX = 3.0
else:  # v2 - optimized version
    FAILURE_RATE = 0.02  # 2% failure rate for v2
    LATENCY_MIN = 0.1
    LATENCY_MAX = 0.5

processed_payments = []

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "version": VERSION})

@app.route('/process', methods=['POST'])
def process_payment():
    data = request.json
    user_id = data.get('user_id')
    amount = data.get('amount')
    
    if not user_id or not amount:
        return jsonify({"error": "Missing user_id or amount"}), 400
    
    # Simulate processing time
    processing_time = random.uniform(LATENCY_MIN, LATENCY_MAX)
    time.sleep(processing_time)
    
    # Simulate failures based on version
    if random.random() < FAILURE_RATE:
        error_types = [
            ("Payment gateway timeout", 504),
            ("Insufficient funds", 402),
            ("Service temporarily unavailable", 503),
            ("Invalid payment method", 400)
        ]
        error_msg, error_code = random.choice(error_types)
        
        return jsonify({
            "error": error_msg,
            "version": VERSION,
            "processing_time": processing_time
        }), error_code
    
    # Successful payment
    order_id = str(uuid.uuid4())
    payment_record = {
        "order_id": order_id,
        "user_id": user_id,
        "amount": amount,
        "status": "completed",
        "version": VERSION,
        "processing_time": processing_time
    }
    
    processed_payments.append(payment_record)
    
    return jsonify({
        "order_id": order_id,
        "status": "success",
        "amount": amount,
        "version": VERSION,
        "processing_time": processing_time,
        "message": f"Payment processed successfully by {VERSION}"
    })

@app.route('/payments/<order_id>')
def get_payment(order_id):
    payment = next((p for p in processed_payments if p['order_id'] == order_id), None)
    if payment:
        return jsonify(payment)
    return jsonify({"error": "Payment not found"}), 404

@app.route('/metrics')
def metrics():
    total_payments = len(processed_payments)
    total_amount = sum(p['amount'] for p in processed_payments)
    avg_processing_time = sum(p['processing_time'] for p in processed_payments) / max(total_payments, 1)
    
    return jsonify({
        "version": VERSION,
        "total_payments": total_payments,
        "total_amount": total_amount,
        "average_processing_time": avg_processing_time,
        "failure_rate": FAILURE_RATE,
        "requests_total": random.randint(1000, 10000),
        "errors_total": int(random.randint(1000, 10000) * FAILURE_RATE)
    })

@app.route('/simulate-failure', methods=['POST'])
def simulate_failure():
    """Endpoint to simulate failures for chaos engineering"""
    failure_type = request.json.get('type', 'random')
    
    if failure_type == 'timeout':
        time.sleep(30)
        return jsonify({"error": "Simulated timeout"}), 504
    elif failure_type == 'error':
        return jsonify({"error": "Simulated error"}), 500
    elif failure_type == 'crash':
        os._exit(1)
    else:
        return jsonify({"error": "Unknown failure type"}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)
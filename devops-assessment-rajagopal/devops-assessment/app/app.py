"""
app.py — Minimal Flask web application for assessment demo
"""
import os
import logging
from flask import Flask, jsonify

app = Flask(__name__)

# Structured logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)
logger = logging.getLogger(__name__)


@app.route("/")
def index():
    logger.info("GET / called")
    return jsonify({
        "message": "Hello from containerised Flask on AWS!",
        "environment": os.getenv("APP_ENV", "unknown"),
        "version": "1.0.0"
    })


@app.route("/health")
def health():
    """ALB health-check endpoint."""
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    port = int(os.getenv("PORT", 80))
    app.run(host="0.0.0.0", port=port)

#!/bin/bash

# Set the path to the encryption key
export ENCRYPTION_KEY_PATH="/etc/mastodon-scheduler/keyfile.key"

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Initialize the database
db_init() {
    python3 << END
from app import app, db

with app.app_context():
    db.create_all()
END
}

db_init
#!/bin/bash

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Enter and test SMTP credentials
generate_key() {
    python3 << END
# generate_key.py

from cryptography.fernet import Fernet
import os

def generate_key():
    return Fernet.generate_key()

def save_key(key, filename):
    with open(filename, 'wb') as file:
        file.write(key)

def main():
    key_path = "/etc/mastodon-scheduler/keyfile.key"
    if not os.path.exists(key_path):
        key = generate_key()
        save_key(key, key_path)

if __name__ == "__main__":
    main()
END
}

generate_key
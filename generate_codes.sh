#!/bin/bash

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

python3 /var/www/html/mastodon-scheduler.app/generate_codes.py
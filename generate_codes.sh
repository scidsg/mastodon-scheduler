#!/bin/bash

# Set the path to the encryption key
export ENCRYPTION_KEY_PATH="/etc/mastodon-scheduler/keyfile.key"

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Enter and test SMTP credentials
generate_codes() {
    python3 << END
from app import app, db, InviteCode
import secrets
from datetime import datetime, timedelta

def create_invite_code():
    code = secrets.token_urlsafe(16)
    expiration_date = datetime.utcnow() + timedelta(days=365)
    new_code = InviteCode(code=code, expiration_date=expiration_date)
    db.session.add(new_code)
    db.session.commit()
    return code

if __name__ == '__main__':
    with app.app_context():
        db.create_all()  # Ensure all tables are created
        print(create_invite_code())
END
}

generate_codes
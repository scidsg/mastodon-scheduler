import os
from app import db, InviteCode
import random
import string

def generate_code(length=10):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def create_invite_code():
    code = generate_code()
    new_code = InviteCode(code=code)
    db.session.add(new_code)
    db.session.commit()
    return code

if __name__ == "__main__":
    number_of_codes = 10  # Number of codes to generate
    for _ in range(number_of_codes):
        print(create_invite_code())

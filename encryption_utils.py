from cryptography.fernet import Fernet

def generate_key():
    """Generate a new encryption key."""
    return Fernet.generate_key()

def encrypt_data(data, key):
    """Encrypt data using the provided key."""
    f = Fernet(key)
    return f.encrypt(data.encode())

def decrypt_data(encrypted_data, key):
    """Decrypt data using the provided key."""
    f = Fernet(key)
    return f.decrypt(encrypted_data).decode()

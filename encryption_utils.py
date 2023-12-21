from cryptography.fernet import Fernet

def generate_key():
    key = Fernet.generate_key()
    with open('/etc/mastodon-scheduler/encryption.key', 'wb') as key_file:
        key_file.write(key)

def encrypt_data(data, key):
    """Encrypt data using the provided key."""
    f = Fernet(key)
    return f.encrypt(data.encode())

def decrypt_data(encrypted_data, key):
    """Decrypt data using the provided key."""
    f = Fernet(key)
    return f.decrypt(encrypted_data).decode()

# Call this function to generate and save the key
generate_key()
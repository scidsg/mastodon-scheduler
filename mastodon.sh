#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Install Python, pip, Git, and OpenSSL
apt update && apt -y dist-upgrade && apt -y autoremove
apt install -y python3 python3-pip python3-venv git libnss3-tools

# Install mkcert
wget https://github.com/FiloSottile/mkcert/releases/download/v1.4.3/mkcert-v1.4.3-linux-arm
chmod +x mkcert-v1.4.3-linux-arm
mv mkcert-v1.4.3-linux-arm /usr/local/bin/mkcert
mkcert -install

# Set up project directory
mkdir -p ~/mastodon_app
cd ~/mastodon_app

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Flask and Mastodon.py
pip install Flask Mastodon.py gunicorn

# Set up templates directory
mkdir -p templates

# Use whiptail to collect Mastodon credentials
CLIENT_KEY=$(whiptail --inputbox "Enter your Mastodon Client Key" 8 78 --title "Mastodon Client Key" 3>&1 1>&2 2>&3)
CLIENT_SECRET=$(whiptail --inputbox "Enter your Mastodon Client Secret" 8 78 --title "Mastodon Client Secret" 3>&1 1>&2 2>&3)
ACCESS_TOKEN=$(whiptail --inputbox "Enter your Mastodon Access Token" 8 78 --title "Mastodon Access Token" 3>&1 1>&2 2>&3)
INSTANCE_URL=$(whiptail --inputbox "Enter your Mastodon Instance URL" 8 78 "https://fosstodon.org" --title "Mastodon Instance URL" 3>&1 1>&2 2>&3)

# Generate a secret key
SECRET_KEY=$(openssl rand -hex 24)

# Generate local certificates using mkcert
mkcert -key-file key.pem -cert-file cert.pem tooter.local

# Create main.py using a here-document and directly input the collected values
cat > main.py <<EOF
from flask import Flask, request, render_template, redirect, url_for, flash
from mastodon import Mastodon

app = Flask(__name__)
app.secret_key = '$SECRET_KEY'

# Initialize Mastodon API with the provided credentials
mastodon = Mastodon(
    client_id='$CLIENT_KEY',
    client_secret='$CLIENT_SECRET',
    access_token='$ACCESS_TOKEN',
    api_base_url='$INSTANCE_URL'
)

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        status = request.form['status']
        mastodon.status_post(status)
        flash("Posted Successfully!")  # Flash a success message
        return redirect(url_for('index'))  # Redirect to the index page
    return render_template('index.html')

if __name__ == '__main__':
    app.run(host='tooter.local', port=5000, ssl_context=('cert.pem', 'key.pem'))
EOF

# Modify main.py to directly use these variables
sed -i "s|\\\$CLIENT_KEY|$CLIENT_KEY|g" main.py
sed -i "s|\\\$CLIENT_SECRET|$CLIENT_SECRET|g" main.py
sed -i "s|\\\$ACCESS_TOKEN|$ACCESS_TOKEN|g" main.py
sed -i "s|\\\$INSTANCE_URL|$INSTANCE_URL|g" main.py

# Create index.html
cat > templates/index.html <<"EOF"
<!DOCTYPE html>
<html>
<head>
    <title>Post to Mastodon</title>
</head>
<body>
    <h1>Post to Mastodon</h1>

    <!-- Display flash messages -->
    {% with messages = get_flashed_messages() %}
        {% if messages %}
            <ul>
            {% for message in messages %}
                <li>{{ message }}</li>
            {% endfor %}
            </ul>
        {% endif %}
    {% endwith %}

    <!-- Form for posting status -->
    <form method="post">
        <textarea name="status" placeholder="What's on your mind?"></textarea>
        <button type="submit">Post to Mastodon</button>
    </form>
</body>
</html>
EOF

# Activate the virtual environment and run the Flask app
source venv/bin/activate
gunicorn -w 4 -b tooter.local:5000 main:app --certfile=./cert.pem --keyfile=./key.pem
#!/bin/bash

#Run as root
if [[ $EUID -ne 0 ]]; then
  echo "Script needs to run as root. Elevating permissions now."
  exec sudo /bin/bash "$0" "$@"
fi

# Update and install necessary packages
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt -y dist-upgrade 
apt-get install -y python3 python3-pip python3-venv python3.11-venv lsof unattended-upgrades sqlite3 libnss3-tools certutil

# Clone the repo
cd $HOME
git clone https://github.com/glenn-sorrentino/mastodon-scheduler.git
cd mastodon-scheduler
git switch hosted
cd ..

# Install mkcert
wget https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64
chmod +x mkcert-v1.4.4-linux-amd64
mv mkcert-v1.4.4-linux-amd64 /usr/local/bin/mkcert
mkcert -install

# Create a directory for the app
cd /var/www/html/mastodon-scheduler.app
mkdir static
mkdir templates

# Change the hostname to mastodon-scheduler.local
echo "Changing the hostname to mastodon-scheduler.local..."
hostnamectl set-hostname mastodon-scheduler.local
echo "127.0.0.1 mastodon-scheduler.local" >> /etc/hosts

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Flask and Mastodon.py
pip3 install Flask Mastodon.py pytz gunicorn flask_httpauth Werkzeug Flask-SQLAlchemy

# Generate hashed password
HASHED_PASSWORD=$(python -c "from werkzeug.security import generate_password_hash; print(generate_password_hash('$PASSWORD'))")

cp $HOME/mastodon-scheduler/app.py /var/www/html/mastodon-scheduler.app
cp $HOME/mastodon-scheduler/db_init.py /var/www/html/mastodon-scheduler.app
cp $HOME/mastodon-scheduler/templates/index.html /var/www/html/mastodon-scheduler.app/templates
cp $HOME/mastodon-scheduler/templates/login.html /var/www/html/mastodon-scheduler.app/templates
cp $HOME/mastodon-scheduler/templates/register.html /var/www/html/mastodon-scheduler.app/templates
cp $HOME/mastodon-scheduler/templates/settings.html /var/www/html/mastodon-scheduler.app/templates
cp $HOME/mastodon-scheduler/static/style.css /var/www/html/mastodon-scheduler.app/static
cp $HOME/mastodon-scheduler/static/script.js /var/www/html/mastodon-scheduler.app/static
cp $HOME/mastodon-scheduler/static/empty-state.png /var/www/html/mastodon-scheduler.app/static
cp $HOME/mastodon-scheduler/static/logo.png /var/www/html/mastodon-scheduler.app/static

# Generate a secret key
SECRET_KEY=$(openssl rand -hex 24)

# Generate local certificates using mkcert
mkcert -key-file key.pem -cert-file cert.pem mastodon-scheduler.local

# Modify app.py to directly use these variables
sed -i "s|SECRET_KEY|$SECRET_KEY|g" app.py
sed -i "s|CLIENT_KEY|$CLIENT_KEY|g" app.py
sed -i "s|CLIENT_SECRET|$CLIENT_SECRET|g" app.py
sed -i "s|ACCESS_TOKEN|$ACCESS_TOKEN|g" app.py
sed -i "s|MASTODON_URL|$MASTODON_URL|g" app.py

# Create a systemd service file for the application
cat > /etc/systemd/system/mastodon_app.service <<EOF
[Unit]
Description=Mastodon App Service
After=network.target network-online.target
Wants=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=/var/www/html/mastodon-scheduler.app
ExecStart=/var/www/html/mastodon-scheduler.app/venv/bin/gunicorn -w 1 -b 0.0.0.0:5000 app:app --certfile=/var/www/html/mastodon-scheduler.app/cert.pem --keyfile=/var/www/html/mastodon-scheduler.app/key.pem

[Install]
WantedBy=multi-user.target
EOF

# Configure Nginx
cat >/etc/nginx/sites-available/mastodon-scheduler.nginx <<EOL
server {
    listen 80;
    server_name mastodon-scheduler.app;
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
        add_header Strict-Transport-Security "max-age=63072000; includeSubdomains";
        add_header X-Frame-Options DENY;
        add_header Onion-Location http://rqmbnke3cevftmsiiicmfpvppodunwmseeokl234bnapxhi7pz2g7qid.onion\$request_uri;
        add_header X-Content-Type-Options nosniff;
        add_header Content-Security-Policy "default-src 'self'; frame-ancestors 'none'";
        add_header Permissions-Policy "geolocation=(), midi=(), notifications=(), push=(), sync-xhr=(), microphone=(), camera=(), magnetometer=(), gyroscope=(), speaker=(), vibrate=(), fullscreen=(), payment=(), interest-cohort=()";
        add_header Referrer-Policy "no-referrer";
        add_header X-XSS-Protection "1; mode=block";
}
server {
    listen 80;
    server_name rqmbnke3cevftmsiiicmfpvppodunwmseeokl234bnapxhi7pz2g7qid.onion.mastodon-scheduler.app

    location / {
        proxy_pass http://localhost:5000;
    }
}
EOL

# Configure Nginx with privacy-preserving logging
mv $HOME/mastodon-scheduler/assets/nginx/nginx.conf /etc/nginx

ln -sf /etc/nginx/sites-available/mastodon-scheduler.nginx /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

if [ -e "/etc/nginx/sites-enabled/default" ]; then
    rm /etc/nginx/sites-enabled/default
fi
ln -sf /etc/nginx/sites-available/hushline.nginx /etc/nginx/sites-enabled/
(nginx -t && systemctl restart nginx) || error_exit

# Kill any process on port 5000
kill_port_processes() {
    echo "Checking for processes on port 5000..."
    local pid=$(lsof -t -i :5000)
    if [ ! -z "$pid" ]; then
        echo "Killing processes on port 5000..."
        kill -9 $pid
    fi
}

# Reload systemd to apply new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable mastodon_app.service

# Start the Mastodon app service
kill_port_processes
echo "Starting Mastodon app service..."
systemctl start mastodon_app.service

# Configure Unattended Upgrades
mv $HOME/mastodon-scheduler/assets/50unattended-upgrades /etc/apt/apt.conf.d
mv $HOME/mastodon-scheduler/assets/20auto-upgrades /etc/apt/apt.conf.d

systemctl restart unattended-upgrades

# Initializing database
sleep 3
python3 db_init.py
sleep 3

echo "✅ Automatic updates have been installed and configured."

echo "✅ Setup complete. Rebooting in 3 seconds..."
echo "⏲️ Rebooting in 3 seconds..."
echo "👉 Access the Mastodon Scheduler at https://mastodon-scheduler.local:5000"
sleep 3
#reboot
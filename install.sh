#!/bin/bash

#Run as root
if [[ $EUID -ne 0 ]]; then
  echo "Script needs to run as root. Elevating permissions now."
  exec sudo /bin/bash "$0" "$@"
fi

# Update and install necessary packages
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt -y dist-upgrade 
apt-get install -y python3 python3-pip python3-venv python3.11-venv lsof unattended-upgrades sqlite3 libnss3-tools ufw fail2ban

# Install nginx, clone repo, request HTTPS certs
curl https://raw.githubusercontent.com/scidsg/tools/main/new-web-app.sh | bash

APP_DIR=$(whiptail --inputbox "Enter your app directory" 8 60 "/var/www/html/mastodon-scheduler.app" --title "App Directory" 3>&1 1>&2 2>&3)

# Function to display error message and exit
error_exit() {
    echo "An error occurred during installation. Please check the output above for more details."
    exit 1
}

# Trap any errors and call the error_exit function
trap error_exit ERR

# Clone the repo
cd $APP_DIR
git switch hosted
cd ..

# Create a directory for the app
cd $APP_DIR
mkdir -p static
mkdir -p templates

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Flask and Mastodon.py
pip3 install Flask Mastodon.py pytz gunicorn flask_httpauth Werkzeug Flask-SQLAlchemy

# Generate a secret key
SECRET_KEY=$(openssl rand -hex 24)

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
ExecStart=/var/www/html/mastodon-scheduler.app/venv/bin/gunicorn -w 1 -b 127.0.0.1:5000 app:app

[Install]
WantedBy=multi-user.target
EOF

# Enable the "security" and "updates" repositories
cp $APP_DIR/assets/50unattended-upgrades /etc/apt/apt.conf.d
cp $APP_DIR/assets/20auto-upgrades /etc/apt/apt.conf.d

systemctl restart unattended-upgrades

echo "Automatic updates have been installed and configured."

# Configure Fail2Ban

echo "Configuring fail2ban..."

systemctl start fail2ban
systemctl enable fail2ban
cp /etc/fail2ban/jail.{conf,local}

# Configure fail2ban
cp $APP_DIR/assets/jail.local /etc/fail2ban

systemctl restart fail2ban

# Configure UFW (Uncomplicated Firewall)

echo "Configuring UFW..."

# Default rules
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp

# Allow SSH (modify as per your requirements)
ufw allow ssh
ufw limit ssh/tcp

# Enable UFW non-interactively
echo "y" | ufw enable

echo "UFW configuration complete."

# Configure Nginx
ln -sf /etc/nginx/sites-available/mastodon-scheduler.app.nginx /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

if [ -e "/etc/nginx/sites-enabled/default" ]; then
    rm /etc/nginx/sites-enabled/default
fi
ln -sf /etc/nginx/sites-available/mastodon-scheduler.app.nginx /etc/nginx/sites-enabled/
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

# Initializing database
sleep 3
cd $APP_DIR
python3 db_init.py
sleep 3

echo "✅ Automatic updates have been installed and configured."

echo "✅ Setup complete. Rebooting in 3 seconds..."
echo "⏲️ Rebooting in 3 seconds..."
sleep 3
reboot
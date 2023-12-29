#!/bin/bash

#Run as root
if [[ $EUID -ne 0 ]]; then
  echo "Script needs to run as root. Elevating permissions now."
  exec sudo /bin/bash "$0" "$@"
fi

# Set time zone
dpkg-reconfigure tzdata

# Update and install necessary packages
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt -y dist-upgrade 
apt-get install -y python3 python3-pip python3-venv whiptail unattended-upgrades

# Use whiptail to collect Mastodon credentials and instance URL
MASTODON_URL=$(whiptail --inputbox "Enter your Mastodon instance URL" 10 60 "https://mastodon.social" --title "Mastodon Instance URL" 3>&1 1>&2 2>&3)
CLIENT_KEY=$(whiptail --inputbox "Enter your Client Key" 10 60 --title "Mastodon Client Key" 3>&1 1>&2 2>&3)
CLIENT_SECRET=$(whiptail --inputbox "Enter your Client Secret" 10 60 --title "Mastodon Client Secret" 3>&1 1>&2 2>&3)
ACCESS_TOKEN=$(whiptail --inputbox "Enter your Access Token" 10 60 --title "Mastodon Access Token" 3>&1 1>&2 2>&3)
PASSWORD=$(whiptail --inputbox "Since anyone on your local network can reach the Mastodon Scheduler app, we'll create a password so only you can access it." 10 60 --title "Create a Password" 3>&1 1>&2 2>&3)

# Clone the repo
cd $HOME
git clone https://github.com/scidsg/mastodon-scheduler.git
cd mastodon-scheduler
git switch spin
cd ..

# Install mkcert
wget https://github.com/FiloSottile/mkcert/releases/download/v1.4.3/mkcert-v1.4.3-linux-arm
chmod +x mkcert-v1.4.3-linux-arm
mv mkcert-v1.4.3-linux-arm /usr/local/bin/mkcert
mkcert -install

# Create a directory for the app
mkdir mastodon_app
cd mastodon_app
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
pip3 install Flask Mastodon.py pytz gunicorn flask_httpauth Werkzeug

# Generate hashed password
HASHED_PASSWORD=$(python -c "from werkzeug.security import generate_password_hash; print(generate_password_hash('$PASSWORD'))")

cp $HOME/mastodon-scheduler/app.py $HOME/mastodon_app
cp $HOME/mastodon-scheduler/templates/index.html $HOME/mastodon_app/templates
cp $HOME/mastodon-scheduler/templates/login.html $HOME/mastodon_app/templates
cp $HOME/mastodon-scheduler/static/style.css $HOME/mastodon_app/static
cp $HOME/mastodon-scheduler/static/button.js $HOME/mastodon_app/static
cp $HOME/mastodon-scheduler/static/nav.js $HOME/mastodon_app/static
cp $HOME/mastodon-scheduler/static/notifications.js $HOME/mastodon_app/static
cp $HOME/mastodon-scheduler/static/publisher.js $HOME/mastodon_app/static
cp $HOME/mastodon-scheduler/static/empty-state.png $HOME/mastodon_app/static
cp $HOME/mastodon-scheduler/static/logo.png $HOME/mastodon_app/static

# Generate a secret key
SECRET_KEY=$(openssl rand -hex 24)

# Generate local certificates using mkcert
mkcert -key-file key.pem -cert-file cert.pem mastodon-scheduler.local

# Read timezone from the system
SYSTEM_TIMEZONE=$(cat /etc/timezone)

# Modify app.py to directly use these variables
sed -i "s|SECRET_KEY|$SECRET_KEY|g" app.py
sed -i "s|CLIENT_KEY|$CLIENT_KEY|g" app.py
sed -i "s|CLIENT_SECRET|$CLIENT_SECRET|g" app.py
sed -i "s|ACCESS_TOKEN|$ACCESS_TOKEN|g" app.py
sed -i "s|MASTODON_URL|$MASTODON_URL|g" app.py
sed -i "s|HASHED_PASSWORD|$HASHED_PASSWORD|g" app.py
sed -i "s|SYSTEM_TIMEZONE|$SYSTEM_TIMEZONE|g" app.py

# Update e-paper python
cd $HOME/mastodon-scheduler/assets
sed -i "s|SYSTEM_TIMEZONE|$SYSTEM_TIMEZONE|g" next_up.py

# Create a systemd service file for the application
cat > /etc/systemd/system/mastodon_app.service <<EOF
[Unit]
Description=Mastodon App Service
After=network.target network-online.target
Wants=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$HOME/mastodon_app
ExecStart=$HOME/mastodon_app/venv/bin/gunicorn -w 1 -b 0.0.0.0:5000 app:app --certfile=$HOME/mastodon_app/cert.pem --keyfile=$HOME/mastodon_app/key.pem

[Install]
WantedBy=multi-user.target
EOF

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

echo "✅ Automatic updates have been installed and configured."

echo "✅ Setup complete. Rebooting in 3 seconds..."
echo "⏲️ Rebooting in 3 seconds..."
echo "👉 Access the Mastodon Scheduler at https://mastodon-scheduler.local:5000"
sleep 3
reboot

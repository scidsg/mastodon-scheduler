#!/bin/bash

# Update and install necessary packages
sudo apt-get update
sudo apt-get install -y python3 python3-pip whiptail

# Use whiptail to collect Mastodon credentials and instance URL
MASTODON_URL=$(whiptail --inputbox "Enter your Mastodon instance URL" 10 60 "https://mastodon.social" --title "Mastodon Instance URL" 3>&1 1>&2 2>&3)
CLIENT_KEY=$(whiptail --inputbox "Enter your Client Key" 10 60 --title "Mastodon Client Key" 3>&1 1>&2 2>&3)
CLIENT_SECRET=$(whiptail --inputbox "Enter your Client Secret" 10 60 --title "Mastodon Client Secret" 3>&1 1>&2 2>&3)
ACCESS_TOKEN=$(whiptail --inputbox "Enter your Access Token" 10 60 --title "Mastodon Access Token" 3>&1 1>&2 2>&3)

# Clone the repo
cd $HOME
git clone https://github.com/glenn-sorrentino/mastodon-scheduler.git
cd mastodon-scheduler
git switch refactor
cd ..

# Create a directory for the app
mkdir mastodon_app
cd mastodon_app
mkdir static
mkdir templates

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Flask and Mastodon.py
pip3 install Flask Mastodon.py pytz gunicorn

cp $HOME/mastodon-scheduler/app.py $HOME/mastodon_app
cp $HOME/mastodon-scheduler/templates/index.html $HOME/mastodon_app/templates
cp $HOME/mastodon-scheduler/static/style.css $HOME/mastodon_app/static
cp $HOME/mastodon-scheduler/static/script.js $HOME/mastodon_app/static

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
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$HOME/mastodon_app
ExecStart=$HOME/mastodon_app/venv/bin/gunicorn -w 1 -b 0.0.0.0:5000 app:app

[Install]
WantedBy=multi-user.target
EOF

# Kill any process on port 5000
kill_port_processes() {
    echo "Checking for processes on port 5000..."
    local pid=$(sudo lsof -t -i :5000)
    if [ ! -z "$pid" ]; then
        echo "Killing processes on port 5000..."
        sudo kill -9 $pid
    fi
}

# Reload systemd to apply new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable mastodon_app.service

# Start the Mastodon app service
kill_port_processes
echo "Starting Mastodon app service..."
sudo systemctl start mastodon_app.service

echo "Setup complete"
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
mkdir mastodon_app mastodon_app/templates mastodon_app/static
cd mastodon_app

# Install mkcert
wget https://github.com/FiloSottile/mkcert/releases/download/v1.4.3/mkcert-v1.4.3-linux-arm
chmod +x mkcert-v1.4.3-linux-arm
mv mkcert-v1.4.3-linux-arm /usr/local/bin/mkcert
mkcert -install

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Flask and Mastodon.py
pip3 install Flask Mastodon.py pytz gunicorn

# Generate local certificates using mkcert
mkcert -key-file key.pem -cert-file cert.pem mastodon-scheduler.local

# Copy the app files
cp $HOME/mastodon-scheduler/app.py $HOME/mastodon_app
cp $HOME/mastodon-scheduler/templates/index.html $HOME/mastodon_app/templates
cp $HOME/mastodon-scheduler/static/style.css $HOME/mastodon_app/static
cp $HOME/mastodon-scheduler/static/script.js $HOME/mastodon_app/static

# Kill any process on port 5000
kill_port_processes() {
    echo "Checking for processes on port 5000..."
    local pid=$(sudo lsof -t -i :5000)
    if [ ! -z "$pid" ]; then
        echo "Killing processes on port 5000..."
        sudo kill -9 $pid
    fi
}

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

sudo systemctl start mastodon_app.service
sudo systemctl enable mastodon_app.service
sleep 5
sudo systemctl status mastodon_app.service

# Change the hostname to mastodon-scheduler.local
echo "Changing the hostname to mastodon-scheduler.local..."
hostnamectl set-hostname mastodon-scheduler.local
echo "127.0.0.1 mastodon-scheduler.local" >> /etc/hosts

echo "Setup complete. Launching the server..."

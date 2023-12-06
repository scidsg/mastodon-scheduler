#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Welcome message and ASCII art
cat <<"EOF"
 __  __               _              _               
|  \/  |  __ _   ___ | |_   ___   __| |  ___   _ _   
| |\/| | / _` | (_-< |  _| / _ \ / _` | / _ \ | ' \  
|_|  |_| \__,_| /__/  \__| \___/ \__,_| \___/ |_||_| 
 ___        _               _          _             
/ __|  __  | |_    ___   __| |  _  _  | |  ___   _ _ 
\__ \ / _| | ' \  / -_) / _` | | || | | | / -_) | '_|
|___/ \__| |_||_| \___| \__,_|  \_,_| |_| \___| |_|  
                                                       
Schedule your social media posts.

EOF
sleep 3

# Use whiptail to collect Mastodon credentials
CLIENT_KEY=$(whiptail --inputbox "Enter your Mastodon Client Key" 8 78 --title "Mastodon Client Key" 3>&1 1>&2 2>&3)
CLIENT_SECRET=$(whiptail --inputbox "Enter your Mastodon Client Secret" 8 78 --title "Mastodon Client Secret" 3>&1 1>&2 2>&3)
ACCESS_TOKEN=$(whiptail --inputbox "Enter your Mastodon Access Token" 8 78 --title "Mastodon Access Token" 3>&1 1>&2 2>&3)
INSTANCE_URL=$(whiptail --inputbox "Enter your Mastodon Instance URL" 8 78 "https://mastodon.social" --title "Mastodon Instance URL" 3>&1 1>&2 2>&3)

# Install Python, pip, Git, and OpenSSL
apt update && apt -y dist-upgrade && apt -y autoremove
apt install -y python3 python3-pip python3-venv git libnss3-tools

# Clone repo
git clone https://github.com/glenn-sorrentino/mastodon-scheduler.git

# Install mkcert
wget https://github.com/FiloSottile/mkcert/releases/download/v1.4.3/mkcert-v1.4.3-linux-arm
chmod +x mkcert-v1.4.3-linux-arm
mv mkcert-v1.4.3-linux-arm /usr/local/bin/mkcert
mkcert -install

# Set up project directory
mkdir -p ~/mastodon_app
mkdir -p ~/mastodon_app/static/uploads
mkdir -p ~/mastodon_app/static/css
cd ~/mastodon_app

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Flask and Mastodon.py
pip install Flask Mastodon.py gunicorn APScheduler SQLAlchemy Flask-SQLAlchemy

# Set up templates directory
mkdir -p templates

# Generate a secret key
SECRET_KEY=$(openssl rand -hex 24)

# Generate local certificates using mkcert
mkcert -key-file key.pem -cert-file cert.pem tooter.local

# Copy the app
cp $HOME/mastodon-scheduler/main.py $HOME/mastodon_app

# Modify main.py to directly use these variables
sed -i "s|SECRET_KEY|$SECRET_KEY|g" main.py
sed -i "s|CLIENT_KEY|$CLIENT_KEY|g" main.py
sed -i "s|CLIENT_SECRET|$CLIENT_SECRET|g" main.py
sed -i "s|ACCESS_TOKEN|$ACCESS_TOKEN|g" main.py
sed -i "s|INSTANCE_URL|$INSTANCE_URL|g" main.py

# Copy the index file
cp $HOME/mastodon-scheduler/templates/index.html $HOME/mastodon_app/templates

# Copy the stylesheet
cp $HOME/mastodon-scheduler/static/css/style.css $HOME/mastodon_app/static/css

# Create scheduled_posts.json
cat > scheduled_posts.json <<"EOF"
[
    {
        "time": "2024-01-01 09:00:00",
        "content": "Happy New Year!",
        "image": "path/to/image1.jpg"
    },
    {
        "time": "2024-02-14 10:00:00",
        "content": "Happy Valentine's Day!",
        "image": "path/to/image2.jpg"
    }
    // ... more scheduled posts ...
]
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

# Create a systemd service file for the application
cat > /etc/systemd/system/mastodon_app.service <<EOF
[Unit]
Description=Mastodon App Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$HOME/mastodon_app
ExecStart=$HOME/mastodon_app/venv/bin/gunicorn -w 1 -b 0.0.0.0:5000 main:app --certfile=$HOME/mastodon_app/cert.pem --keyfile=$HOME/mastodon_app/key.pem

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to apply new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable mastodon_app.service

# Start the Mastodon app service
kill_port_processes
echo "Starting Mastodon app service..."
sudo systemctl start mastodon_app.service

echo "Mastodon app setup complete and service started."
echo "You can access your scheduling app at https://tooter.local:5000"

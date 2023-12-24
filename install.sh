#!/bin/bash

#Run as root
if [[ $EUID -ne 0 ]]; then
  echo "Script needs to run as root. Elevating permissions now."
  exec sudo /bin/bash "$0" "$@"
fi

# Function to display error message and exit
error_exit() {
    echo "An error occurred during installation. Please check the output above for more details."
    exit 1
}

# Trap any errors and call the error_exit function
trap error_exit ERR

# Set time zone
dpkg-reconfigure tzdata

# Update and install necessary packages
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt -y dist-upgrade 
apt-get install -y python3 python3-pip python3-venv python3.11-venv lsof unattended-upgrades sqlite3 libnss3-tools ufw fail2ban python3-certbot-nginx libssl-dev certbot nginx whiptail tor libnginx-mod-http-geoip geoip-database cron git

############################
# Server, Nginx, HTTPS setup
############################

DOMAIN=$(whiptail --inputbox "Enter your domain name:" 8 60 3>&1 1>&2 2>&3)
EMAIL=$(whiptail --inputbox "Enter your email:" 8 60 3>&1 1>&2 2>&3)
GIT=$(whiptail --inputbox "Enter your git repo:" 8 60 3>&1 1>&2 2>&3)

# Check for valid domain name format
until [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*\.[a-zA-Z]{2,}$ ]]; do
    DOMAIN=$(whiptail --inputbox "Invalid domain name format. Please enter a valid domain name:" 8 60 3>&1 1>&2 2>&3)
done
export DOMAIN
export EMAIL
export GIT

# Debug: Print the value of the DOMAIN variable
echo "Domain: $DOMAIN"

# Create Tor configuration file
sudo tee /etc/tor/torrc << EOL
RunAsDaemon 1
HiddenServiceDir /var/lib/tor/$DOMAIN/
HiddenServicePort 80 127.0.0.1:80
EOL

# Restart Tor service
sudo systemctl restart tor.service
sleep 10

# Get the Onion address
ONION_ADDRESS=$(sudo cat /var/lib/tor/$DOMAIN/hostname)
SAUTEED_ONION_ADDRESS=$(echo $ONION_ADDRESS | tr -d '.')

# Configure Nginx
cat > /etc/nginx/sites-available/$DOMAIN.nginx << EOL
server {
        root /var/www/html/$DOMAIN;
        server_name $DOMAIN www.$DOMAIN;
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
        add_header X-Content-Type-Options nosniff;
        add_header Onion-Location http://$ONION_ADDRESS\$request_uri;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self'; img-src 'self' https:; style-src 'self'; frame-ancestors 'none';";
        add_header Permissions-Policy "geolocation=(), midi=(), notifications=(), push=(), sync-xhr=(), microphone=(), camera=(), magnetometer=(), gyroscope=(), speaker=(), vibrate=(), fullscreen=(), payment=(), interest-cohort=()";
        add_header Referrer-Policy "no-referrer";
        add_header X-XSS-Protection "1; mode=block";
}
server {
        server_name $ONION_ADDRESS;
        access_log /var/log/nginx/hs-my-website.log;
        index index.html;
        root /var/www/html/$DOMAIN;
                
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self'; img-src 'self' https:; style-src 'self'; frame-ancestors 'none';";
        add_header Permissions-Policy "geolocation=(), midi=(), notifications=(), push=(), sync-xhr=(), microphone=(), camera=(), magnetometer=(), gyroscope=(), speaker=(), vibrate=(), fullscreen=(), payment=(), interest-cohort=()";
        add_header Referrer-Policy "no-referrer";
        add_header X-XSS-Protection "1; mode=block";
}
server {
        listen 80;
        server_name $DOMAIN www.$DOMAIN; # YOUR URLS
        return 301 https://$DOMAIN\$request_uri;
}
server {
    listen 80;
    server_name $SAUTEED_ONION_ADDRESS.$DOMAIN;

    location / {
        root /var/www/html/$DOMAIN;
    }
}
EOL

# Configure Nginx with privacy-preserving logging
cat > /etc/nginx/nginx.conf << EOL
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events {
        worker_connections 768;
        # multi_accept on;
}
http {
        ##
        # Basic Settings
        ##
        sendfile on;
        tcp_nopush on;
        types_hash_max_size 2048;
        # server_tokens off;
        server_names_hash_bucket_size 128;
        # server_name_in_redirect off;
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        ##
        # SSL Settings
        ##
        ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
        ssl_prefer_server_ciphers on;
        ##
        # Logging Settings
        ##
        # access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;
        ##
        # Gzip Settings
        ##
        gzip on;
        # gzip_vary on;
        # gzip_proxied any;
        # gzip_comp_level 6;
        # gzip_buffers 16 8k;
        # gzip_http_version 1.1;
        # gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
        ##
        # Virtual Host Configs
        ##
        include /etc/nginx/conf.d/*.conf;
        include /etc/nginx/sites-enabled/*;
        ##
        # Enable privacy preserving logging
        ##
        geoip_country /usr/share/GeoIP/GeoIP.dat;
        log_format privacy '0.0.0.0 - \$remote_user [\$time_local] "\$request" \$status \$body_bytes_sent "\$http_referer" "-" \$geoip_country_code';

        access_log /var/log/nginx/access.log privacy;
}
EOL

sudo ln -sf /etc/nginx/sites-available/$DOMAIN.nginx /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

if [ -e "/etc/nginx/sites-enabled/default" ]; then
    rm /etc/nginx/sites-enabled/default
fi
ln -sf /etc/nginx/sites-available/$DOMAIN.nginx /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx || error_exit

cd /var/www/html
git clone $GIT
REPO_NAME=$(basename $GIT .git)
mv $REPO_NAME $DOMAIN

SERVER_IP=$(curl -s ifconfig.me)
WIDTH=$(tput cols)
whiptail --msgbox --title "Instructions" "\nPlease ensure that your DNS records are correctly set up before proceeding:\n\nAdd an A record with the name: @ and content: $SERVER_IP\n* Add a CNAME record with the name $SAUTEED_ONION_ADDRESS.$DOMAIN and content: $DOMAIN\n* Add a CAA record with the name: @ and content: 0 issue \"letsencrypt.org\"\n" 14 $WIDTH
# Request the certificates
certbot --nginx -d $DOMAIN,$SAUTEED_ONION_ADDRESS.$DOMAIN --agree-tos --non-interactive --no-eff-email --email ${EMAIL}

# Set up cron job to renew SSL certificate
(crontab -l 2>/dev/null; echo "30 2 * * 1 /usr/bin/certbot renew --quiet") | crontab -

####################################
####################################

APP_DIR=$(whiptail --inputbox "Enter your app directory" 8 60 "$DOMAIN" --title "App Directory" 3>&1 1>&2 2>&3)

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
pip3 install Flask Mastodon.py pytz gunicorn flask_httpauth Werkzeug Flask-SQLAlchemy cryptography Flask-WTF

# Generate and save the key
mkdir -p /etc/mastodon-scheduler
python3 -c "from encryption_utils import generate_key; generate_key()"

# Modify app.py to directly use these variables
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
WorkingDirectory=/var/www/html/$DOMAIN
ExecStart=/var/www/html/$DOMAIN/venv/bin/gunicorn -w 1 -b 127.0.0.1:5000 app:app

[Install]
WantedBy=multi-user.target
EOF

# Enable the "security" and "updates" repositories
cp assets/50unattended-upgrades /etc/apt/apt.conf.d
cp assets/20auto-upgrades /etc/apt/apt.conf.d

systemctl restart unattended-upgrades

echo "Automatic updates have been installed and configured."

# Configure Fail2Ban

echo "Configuring fail2ban..."

systemctl start fail2ban
systemctl enable fail2ban
cp /etc/fail2ban/jail.{conf,local}

# Configure fail2ban
cp assets/jail.local /etc/fail2ban

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
ln -sf /etc/nginx/sites-available/$DOMAIN.nginx /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

if [ -e "/etc/nginx/sites-enabled/default" ]; then
    rm /etc/nginx/sites-enabled/default
fi
ln -sf /etc/nginx/sites-available/$DOMAIN.nginx /etc/nginx/sites-enabled/
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
echo "Initializing database..."
python3 db_init.py
sleep 3

echo "✅ Automatic updates have been installed and configured."

echo "
✅ Mastodon Scheduler installation complete! Access your site at these addresses:
                                               
https://$DOMAIN
https://$SAUTEED_ONION_ADDRESS.$DOMAIN;
http://$ONION_ADDRESS
"
echo "⏲️ Rebooting in 3 seconds..."
sleep 3
reboot

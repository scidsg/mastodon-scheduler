#!/bin/bash

# Run as root
if [[ $EUID -ne 0 ]]; then
  echo "Script needs to run as root. Elevating permissions now."
  exec sudo /bin/bash "$0" "$@"
fi

# Stop and disable the Mastodon app service
echo "Stopping Mastodon app service..."
systemctl stop mastodon_app.service
systemctl disable mastodon_app.service

# Remove the systemd service file
echo "Removing the systemd service file..."
rm -f /etc/systemd/system/mastodon_app.service

# Reload systemd to apply changes
systemctl daemon-reload

# Remove the Mastodon app directory
echo "Removing the Mastodon app directory..."
rm -rf $HOME/mastodon_app

# Remove the cloned repository
echo "Removing the cloned repository..."
rm -rf $HOME/mastodon-scheduler

# Remove mkcert and generated certificates
echo "Removing mkcert and generated certificates..."
rm -f /usr/local/bin/mkcert
rm -f $HOME/mastodon_app/cert.pem
rm -f $HOME/mastodon_app/key.pem

# Change the hostname back (Optional: Replace 'original-hostname' with your original hostname if different)
echo "Reverting the hostname..."
hostnamectl set-hostname original-hostname
sed -i '/mastodon-scheduler.local/d' /etc/hosts

# Uninstall packages (Optional: Comment out if you want to keep these packages)
echo "Uninstalling packages..."
apt-get remove -y python3 python3-pip whiptail unattended-upgrades
apt-get autoremove -y

# Remove configuration files for Unattended Upgrades (Optional)
echo "Removing Unattended Upgrades configuration files..."
rm -f /etc/apt/apt.conf.d/50unattended-upgrades
rm -f /etc/apt/apt.conf.d/20auto-upgrades

echo "✅ Uninstallation complete."

#!/bin/bash

#Run as root
if [[ $EUID -ne 0 ]]; then
  echo "Script needs to run as root. Elevating permissions now."
  exec sudo /bin/bash "$0" "$@"
fi

# Install required packages for e-ink display
apt update
apt -y dist-upgrade
apt install -y python3-pip

# Enable SPI interface
raspi-config nonint do_spi 0

# Install Waveshare e-Paper library
git clone https://github.com/waveshare/e-Paper.git
pip3 install ./e-Paper/RaspberryPi_JetsonNano/python/
pip3 install requests python-gnupg stem

# Install other Python packages
pip3 install RPi.GPIO spidev
apt -y autoremove

# Enable SPI interface
if ! grep -q "dtparam=spi=on" /boot/config.txt; then
    echo "dtparam=spi=on" | tee -a /boot/config.txt
    echo "SPI interface enabled."
else
    echo "SPI interface is already enabled."
fi

cd $HOME/mastodon_app

# Copy the display python
cp $HOME/mastodon-scheduler/assets/next_up.py $HOME/mastodon_app

sed -i "s|local_ip|$local_ip|g" $HOME/mastodon_app/next_up.py

cat > /etc/systemd/system/nextup.service << EOF
[Unit]
Description=Next Up Mastodon Post Display
After=network.target

[Service]
ExecStart=/usr/bin/python3 /root/mastodon_app/next_up.py
WorkingDirectory=$HOME/mastodon_app
StandardOutput=inherit
StandardError=inherit
Restart=always
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl enable nextup.service
systemctl start nextup.service

echo "✅ E-ink display configuration complete. Rebooting your Raspberry Pi..."
sleep 3

# reboot

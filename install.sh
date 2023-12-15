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

# Copy the app
cp $HOME/mastodon-scheduler/app.py $HOME/mastodon_app

# HTML template for the form
mkdir templates
cat <<EOF > templates/index.html
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="author" content="Glenn Sorrentino">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>🗓️ Mastodon Scheduler</title>
    <link rel="stylesheet" type="text/css" href="static/style.css">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:wght@400;700&family=IBM+Plex+Mono:wght@300;400&display=swap" rel="stylesheet">
</head>
<body>
  <div class="publisher">
      <h1>Post to Mastodon</h1>
      <form method="POST" onsubmit="return validateForm()" enctype="multipart/form-data">
         <input type="text" name="content_warning" placeholder="Content warning"><br>
         <textarea name="content" placeholder="What's happening?"></textarea><br>
         Schedule Post (optional, in your local time):<br>
         <input type="datetime-local" name="scheduled_at" placeholder="YYYY-MM-DDTHH:MM"><br>
         <input type="file" name="image" accept="image/*"><br>
         <input type="text" name="alt_text" placeholder="Enter image description (alt text)"><br>
         <input type="submit" value="Toot!">
      </form>
  </div>
  <div class="scheduled-posts">
    <h2>Scheduled Posts</h2>
    <ul>
        {% for status in scheduled_statuses %}
            <li>
                <!-- Display content -->
                Content: {{ status['params']['text'] }}<br>
                <!-- Display images with alt text as title -->
                {% for media in status.get('media_attachments', []) %}
                    <div class="image-container">
                        <img src="{{ media.url }}" title="{{ media.description }}" alt="Image attached to post" style="max-width: 100px; height: auto;">
                        {% if media.description %}
                            <span class="alt-indicator">Alt</span>
                        {% endif %}
                    </div>
                    <br>
                {% endfor %}
                <!-- Display content warning if available -->
                {% if status['params']['spoiler_text'] %}
                    <strong>Content Warning:</strong> {{ status['params']['spoiler_text'] }}<br>
                {% endif %}
                <strong>Scheduled for:</strong> {{ status['scheduled_at'] }}<br>
                <!-- Cancel button -->
                <form action="/cancel/{{ status['id'] }}" method="post">
                    <input type="submit" value="Cancel">
                </form>
            </li>
        {% endfor %}
    </ul>
  </div>
  <script src="{{ url_for('static', filename='script.js') }}"></script>
</body>
</html>
EOF

# Create CSS
mkdir static
cat <<EOF > static/style.css
body {
    display: flex;
    justify-content: center;
    margin: 0;
}

.publisher,
.scheduled-posts {
    padding: 1rem;
    box-sizing: border-box;
}

.scheduled-posts ul {
    padding-left: 0;
}

.scheduled-posts li {
    list-style: none;
    margin-bottom: 1rem;
}

.image-container {
    position: relative;
}

.image-container .alt-indicator {
    position: absolute;
    bottom: .25rem;
    left: .25rem;
    background-color: #333;
    color: white;
}

@media only screen and (max-width: 480px) {
    body {
        flex-direction: column;
    }
}
EOF

# Create JS
cat <<EOF > static/script.js
function validateForm() {
    var scheduledTimeInput = document.getElementsByName("scheduled_at")[0];
    if (scheduledTimeInput.value) {
        var scheduledTime = new Date(scheduledTimeInput.value);
        var currentTime = new Date();
        var fiveMinutesLater = new Date(currentTime.getTime() + 5 * 60000); // Add 5 minutes

        if (scheduledTime <= fiveMinutesLater) {
            alert("Scheduled time must be at least 5 minutes in the future.");
            return false;
        }
    }
    return true;
}
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

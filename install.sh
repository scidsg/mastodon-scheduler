#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Install Python, pip, Git, and OpenSSL
apt update && apt -y dist-upgrade && apt -y autoremove
apt install -y python3 python3-pip python3-venv git libnss3-tools

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

# Use whiptail to collect Mastodon credentials
CLIENT_KEY=$(whiptail --inputbox "Enter your Mastodon Client Key" 8 78 --title "Mastodon Client Key" 3>&1 1>&2 2>&3)
CLIENT_SECRET=$(whiptail --inputbox "Enter your Mastodon Client Secret" 8 78 --title "Mastodon Client Secret" 3>&1 1>&2 2>&3)
ACCESS_TOKEN=$(whiptail --inputbox "Enter your Mastodon Access Token" 8 78 --title "Mastodon Access Token" 3>&1 1>&2 2>&3)
INSTANCE_URL=$(whiptail --inputbox "Enter your Mastodon Instance URL" 8 78 "https://mastodon.social" --title "Mastodon Instance URL" 3>&1 1>&2 2>&3)

# Generate a secret key
SECRET_KEY=$(openssl rand -hex 24)

# Generate local certificates using mkcert
mkcert -key-file key.pem -cert-file cert.pem tooter.local

# Create main.py using a here-document and directly input the collected values
cat > main.py <<EOF
import os
import logging
from datetime import datetime
from flask import Flask, request, render_template, redirect, url_for, flash
from flask_sqlalchemy import SQLAlchemy
from werkzeug.utils import secure_filename
from mastodon import Mastodon
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
from sqlalchemy import inspect

# Setup logging
logging.basicConfig(level=logging.INFO)

# Flask application setup
app = Flask(__name__, static_folder='static')
app.secret_key = '$SECRET_KEY'
app.config['UPLOAD_FOLDER'] = os.path.join(app.static_folder, 'uploads')
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16 Megabyte limit
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///jobs.sqlite'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Ensure the upload directory exists
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

# SQLAlchemy setup
db = SQLAlchemy(app)

# Model for scheduled posts
class ScheduledPost(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    content = db.Column(db.Text, nullable=False)
    image_path = db.Column(db.String(255), nullable=True)  # Image path can be null
    schedule_time = db.Column(db.DateTime, nullable=False)

    def __repr__(self):
        return f'<ScheduledPost {self.id} {self.content[:20]}>'

# Check for existing tables before creating new ones
with app.app_context():
    db.create_all()

# APScheduler setup with SQLAlchemyJobStore
scheduler = BackgroundScheduler({
    'default': SQLAlchemyJobStore(url=app.config['SQLALCHEMY_DATABASE_URI'])
})
scheduler.start()

# Mastodon API setup
mastodon = Mastodon(
    client_id='CLIENT_KEY',  
    client_secret='CLIENT_SECRET',  
    access_token='ACCESS_TOKEN',  
    api_base_url='INSTANCE_URL' 
)

def allowed_file(filename):
    """Check if the uploaded file is allowed."""
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def post_to_mastodon(content, image_path=None):
    """Post to Mastodon, optionally with an image."""
    logging.info(f"Executing scheduled post: {content}")
    media_id = None
    try:
        if image_path:
            # Update this line to reflect the new path
            full_image_path = os.path.join(app.root_path, 'static', image_path)
            if os.path.exists(full_image_path):
                media_response = mastodon.media_post(full_image_path)
                logging.info(f"Media post response: {media_response}")
                media_id = media_response['id']
            else:
                logging.error(f"Image file not found: {full_image_path}")
        status_response = mastodon.status_post(content, media_ids=[media_id] if media_id else None)
        logging.info(f"Status post response: {status_response}")
    except Exception as e:
        logging.error(f"Error posting to Mastodon: {e}")

@app.route('/', methods=['GET', 'POST'])
def index():
    """Handle post and schedule requests."""
    if request.method == 'POST':
        status = request.form['status']
        file = request.files['image']
        schedule_time = request.form.get('schedule_time')

        if schedule_time:
            schedule_datetime = datetime.strptime(schedule_time, '%Y-%m-%dT%H:%M')
            image_path = None
            if file and allowed_file(file.filename):
                filename = secure_filename(file.filename)
                # Save the file in the UPLOAD_FOLDER
                file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
                file.save(file_path)
                # Save the relative path in the database
                image_path = os.path.join('uploads', filename)

            # Save scheduled post to database
            new_post = ScheduledPost(
                content=status,
                image_path=image_path,
                schedule_time=schedule_datetime
            )
            db.session.add(new_post)
            db.session.commit()

            # Schedule the post
            scheduler.add_job(
                post_to_mastodon, 
                'date', 
                run_date=schedule_datetime, 
                args=[status, image_path],
                id=str(new_post.id)
            )
            flash("👍 Successfully scheduled you post for " + schedule_time)
        else:
            media_id = None
            if file and allowed_file(file.filename):
                filename = secure_filename(file.filename)
                # Save the file in the UPLOAD_FOLDER
                file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
                file.save(file_path)
                # Post directly with the file path
                media = mastodon.media_post(file_path)
                media_id = media['id']
            mastodon.status_post(status, media_ids=[media_id] if media_id else None)
            flash("Posted Successfully!")

    # Query all scheduled posts from the database and order by schedule time descending
    scheduled_posts = ScheduledPost.query.order_by(ScheduledPost.schedule_time.desc()).all()

    # Pass the scheduled posts to the template
    return render_template('index.html', scheduled_posts=scheduled_posts)

def load_scheduled_posts():
    """Load and schedule any posts from the database."""
    posts = ScheduledPost.query.filter(ScheduledPost.schedule_time > datetime.now()).all()
    for post in posts:
        job_id = f"post_{post.id}"
        if not scheduler.get_job(job_id):
            scheduler.add_job(post_to_mastodon, 'date', id=job_id, run_date=post.schedule_time, args=[post.content, post.image_path])

@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

if __name__ == '__main__':
    load_scheduled_posts()  # Load scheduled posts
    app.run(host='tooter.local', port=5000, ssl_context=('cert.pem', 'key.pem'))
EOF

# Modify main.py to directly use these variables
sed -i "s|CLIENT_KEY|$CLIENT_KEY|g" main.py
sed -i "s|CLIENT_SECRET|$CLIENT_SECRET|g" main.py
sed -i "s|ACCESS_TOKEN|$ACCESS_TOKEN|g" main.py
sed -i "s|INSTANCE_URL|$INSTANCE_URL|g" main.py

# Modify the index.html file to correctly reference images from the static path
cat > templates/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Post to Mastodon</title>
    <link rel="stylesheet" type="text/css" href="static/css/style.css">
</head>
<body>
    <header>
        <h1>Post to Mastodon</h1>
    </header>

    <!-- Display flash messages -->
    {% with messages = get_flashed_messages() %}
        {% if messages %}
            <ul class="notification">
            {% for message in messages %}
                <li>{{ message }}</li>
            {% endfor %}
            </ul>
        {% endif %}
    {% endwith %}

    <!-- Form for posting status with file upload and scheduling -->
    <form method="post" enctype="multipart/form-data">
        <textarea name="status" placeholder="What's on your mind?"></textarea><br>
        <input type="file" name="image"><br>
        <input type="datetime-local" name="schedule_time"><br>
        <button type="submit">Post or Schedule</button>
    </form>
    <div class="scheduled-posts">
        <h2>Scheduled Posts</h2>
        <ul>
            {% for post in scheduled_posts %}
            <li>
                {{ post.content }}<br><span class="meta">{{ post.schedule_time }}</span>
                {% if post.image_path %}
                    <!-- Updated to reference images from the static folder -->
                    <img src="{{ url_for('static', filename=post.image_path) }}" alt="Scheduled image">
                {% endif %}
            </li>
            {% else %}
            <li>No scheduled posts</li>
            {% endfor %}
        </ul>
    </div>
</body>
</html>
EOF

# Create stylesheet
cat > static/css/style.css <<'EOF'
body {
  display: flex;
  flex-direction: column;
  font-family: Helvetica, Arial, sans-serif;
  margin: 0;
  height: calc(100vh - 3.875rem);
  justify-content: start;
  padding-top: 3.875rem;

}

header {
    padding: 1.25rem 1rem;
    border-bottom: 1px solid rgba(0,0,0,0.1);
    position: fixed;
    top: 0;
    background-color: white;
    width: 100%;
}

header h1 {
    margin: 0;
    font-size: 1.25rem;
}

h2 {
    margin-bottom: .325rem;
}

.meta {
    font-size: .825rem;
    font-family: monospace;
    margin: .5rem 0;
    display: inline-flex;
    color: #494949;
}

.notification {
  background-color: #c3fbc3;
  width: fit-content;
  padding: 1rem 1.25rem;
  border-radius: .125rem;
  position: fixed;
  top: 1rem;
  margin: 0;
  right: 1rem;
  outline: 1px solid #1f951f45;
  box-shadow: 0px 12px 12px -4px rgba(20, 85, 10, 0.08);
}

li {
    list-style: none;
}

form,
.scheduled-posts {
  max-width: 640px;
  width: 100%;
  display: flex;
  flex-direction: column;
  align-self: center;
  gap: .325rem;
  margin: 1rem 0;
}

form input {
  max-width: 320px;
}

form button {
  width: fit-content;
}

form textarea {
    height: 240px;
    padding: .75rem;
}

.scheduled-posts li img {
    display: block;
    width: 50%;
    margin-top: .5rem;
}

.scheduled-posts ul {
    padding: 0;
}
EOF

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
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
INSTANCE_URL=$(whiptail --inputbox "Enter your Mastodon Instance URL" 8 78 "https://fosstodon.org" --title "Mastodon Instance URL" 3>&1 1>&2 2>&3)

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
app = Flask(__name__)
app.secret_key = '$SECRET_KEY'
app.config['UPLOAD_FOLDER'] = 'uploads'
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
    image_path = db.Column(db.String(255))
    schedule_time = db.Column(db.DateTime, nullable=False)

    def __repr__(self):
        return f'<ScheduledPost {self.id} {self.content[:20]}>'

# Check for existing tables before creating new ones
with app.app_context():
    inspector = inspect(db.engine)
    if not inspector.has_table('scheduled_post'):
        db.create_all()

# APScheduler setup with SQLAlchemyJobStore
jobstores = {
    'default': SQLAlchemyJobStore(url='sqlite:///jobs.sqlite')
}
scheduler = BackgroundScheduler(jobstores=jobstores)

# Check if apscheduler_jobs table exists before starting the scheduler
with app.app_context():
    if not inspector.has_table('apscheduler_jobs'):
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
    ALLOWED_EXTENSIONS = set(['png', 'jpg', 'jpeg', 'gif'])
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def post_to_mastodon(content, image_path=None):
    """Post to Mastodon, optionally with an image."""
    logging.info(f"Executing scheduled post: {content}")
    media_id = None
    if image_path and os.path.exists(image_path):
        media = mastodon.media_post(image_path)
        media_id = media['id']
    mastodon.status_post(content, media_ids=[media_id] if media_id else None)

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
                image_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
                file.save(image_path)

            # Save scheduled post to database
            new_post = ScheduledPost(
                content=status,
                image_path=image_path,
                schedule_time=schedule_datetime
            )
            db.session.add(new_post)
            db.session.commit()
            scheduler.add_job(post_to_mastodon, 'date', run_date=schedule_datetime, args=[status, image_path])
            flash("Post scheduled for " + schedule_time)
        else:
            media_id = None
            if file and allowed_file(file.filename):
                filename = secure_filename(file.filename)
                file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
                file.save(file_path)
                media = mastodon.media_post(file_path)
                media_id = media['id']
            mastodon.status_post(status, media_ids=[media_id] if media_id else None)
            flash("Posted Successfully!")

    # Query all scheduled posts from the database and order by schedule time
    scheduled_posts = ScheduledPost.query.order_by(ScheduledPost.schedule_time).all()

    # Pass the scheduled posts to the template
    return render_template('index.html', scheduled_posts=scheduled_posts)

def load_scheduled_posts():
    """Load and schedule any posts from the database."""
    posts = ScheduledPost.query.filter(ScheduledPost.schedule_time > datetime.now()).all()
    for post in posts:
        job_id = f"post_{post.id}"
        if not scheduler.get_job(job_id):
            scheduler.add_job(post_to_mastodon, 'date', id=job_id, run_date=post.schedule_time, args=[post.content, post.image_path])

if __name__ == '__main__':
    load_scheduled_posts()  # Load scheduled posts
    app.run(host='tooter.local', port=5000, ssl_context=('cert.pem', 'key.pem'))
EOF

# Modify main.py to directly use these variables
sed -i "s|CLIENT_KEY|$CLIENT_KEY|g" main.py
sed -i "s|CLIENT_SECRET|$CLIENT_SECRET|g" main.py
sed -i "s|ACCESS_TOKEN|$ACCESS_TOKEN|g" main.py
sed -i "s|INSTANCE_URL|$INSTANCE_URL|g" main.py

# Create index.html
cat > templates/index.html <<"EOF"
<!DOCTYPE html>
<html>
<head>
    <title>Post to Mastodon</title>
</head>
<body>
    <h1>Post to Mastodon</h1>

    <!-- Display flash messages -->
    {% with messages = get_flashed_messages() %}
        {% if messages %}
            <ul>
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
    <h2>Scheduled Posts</h2>
    <ul>
    {% for post in scheduled_posts %}
        <li>{{ post.schedule_time }} - {{ post.content }}</li>
    {% else %}
        <li>No scheduled posts</li>
    {% endfor %}
    </ul>
</body>
</html>
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

# Create a systemd service file for the application
cat > /etc/systemd/system/mastodon_app.service <<EOF
[Unit]
Description=Mastodon App Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=/home/$USER/mastodon_app
Environment="PATH=/home/$USER/mastodon_app/venv/bin"
ExecStart=/home/$USER/mastodon_app/venv/bin/gunicorn -w 4 -b 0.0.0.0:5000 main:app --certfile=./cert.pem --keyfile=./key.pem

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to apply new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable mastodon_app.service

# Start the service
systemctl start mastodon_app.service

echo "Mastodon app setup complete and service started."

# Activate the virtual environment and run the Flask app
source venv/bin/activate
gunicorn -w 4 -b tooter.local:5000 main:app --certfile=./cert.pem --keyfile=./key.pem
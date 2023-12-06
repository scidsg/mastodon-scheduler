import os
import logging
from datetime import datetime
from flask import Flask, request, render_template, redirect, url_for, flash
from flask_sqlalchemy import SQLAlchemy
from werkzeug.utils import secure_filename
from mastodon import Mastodon, MastodonError
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
from sqlalchemy import inspect

# Setup logging
logging.basicConfig(level=logging.INFO)

# Flask application setup
app = Flask(__name__, static_folder='static')
app.secret_key = 'SECRET_KEY'
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

from dateutil.parser import parse

def post_to_mastodon(content, image_path=None, scheduled_time=None):
    """Post to Mastodon, optionally with an image, at a scheduled time."""
    try:
        media_id = None
        if image_path:
            # If there's an image, attempt to upload it
            full_image_path = os.path.join(app.root_path, 'static', image_path)
            if os.path.exists(full_image_path):
                media = mastodon.media_post(full_image_path)
                media_id = media['id']

        # Check if scheduled_time is provided and is a datetime object
        if scheduled_time and isinstance(scheduled_time, datetime):
            # Convert the scheduled_time to ISO 8601 format
            scheduled_time_iso = scheduled_time.astimezone().isoformat()
            # Schedule the post using Mastodon's API
            mastodon.status_post(content, media_ids=[media_id] if media_id else None, scheduled_at=scheduled_time_iso)
        elif scheduled_time:
            # If scheduled_time is not a datetime object, raise an error
            raise ValueError("scheduled_time must be a datetime object")
        else:
            # Post immediately if no scheduled_time is provided
            mastodon.status_post(content, media_ids=[media_id] if media_id else None)

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
            try:
                # Convert schedule_time from string to datetime object
                schedule_datetime = datetime.strptime(schedule_time, '%Y-%m-%dT%H:%M')
                image_path = None
                if file and allowed_file(file.filename):
                    filename = secure_filename(file.filename)
                    file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
                    file.save(file_path)
                    image_path = os.path.join('uploads', filename)

                # Call post_to_mastodon with the correct datetime object
                post_to_mastodon(status, image_path, schedule_datetime)
                flash("👍 Successfully scheduled your post for " + schedule_time)

            except ValueError:
                flash("Error: Invalid date format. Please use YYYY-MM-DDTHH:MM format.")

        else:
        image_path = None
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(file_path)
            image_path = os.path.join('uploads', filename)

        if not schedule_time:  # Check if schedule_time was not provided
            # Save scheduled post to database
            new_post = ScheduledPost(
                content=status,
                image_path=image_path,
                schedule_time=schedule_datetime if schedule_time else None
            )
            db.session.add(new_post)
            db.session.commit()

            # Call post_to_mastodon with the scheduled time if provided
            post_to_mastodon(status, image_path, schedule_datetime if schedule_time else None)
            flash("👍 Successfully scheduled your post for " + schedule_time if schedule_time else "Posted Successfully!")

    # Query all scheduled posts from the database and order by schedule time ascending
    scheduled_posts = ScheduledPost.query.order_by(ScheduledPost.schedule_time).all()

    # Determine the next up post
    now = datetime.now()
    next_up_post = None
    for post in scheduled_posts:
        if post.schedule_time and post.schedule_time > now:
            next_up_post = post
            break

    # Pass the scheduled posts and next up post to the template
    return render_template('index.html', scheduled_posts=scheduled_posts, next_up_post=next_up_post)

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
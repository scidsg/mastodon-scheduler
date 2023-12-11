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
    image_alt_text = db.Column(db.String(255), nullable=True)  # Alt text for the image
    cw_text = db.Column(db.String(255), nullable=True)  # Content Warning text
    is_posted = db.Column(db.Boolean, default=False, nullable=False)

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

def post_to_mastodon(post_id):
    with app.app_context():
        post = ScheduledPost.query.get(post_id)
        if not post:
            logging.error(f"Post with ID {post_id} not found")
            return

        logging.info(f"Executing scheduled post: {post.content}, CW: {post.cw_text}")
        media_id = None
        try:
            if post.image_path:
                full_image_path = os.path.join(app.root_path, 'static', post.image_path)
                if os.path.exists(full_image_path):
                    media_response = mastodon.media_post(full_image_path)
                    if media_response:
                        mastodon.media_update(media_response['id'], description=post.image_alt_text)
                        media_id = media_response['id']
                else:
                    logging.error(f"Image file not found: {full_image_path}")

            status_response = mastodon.status_post(post.content, media_ids=[media_id] if media_id else None, spoiler_text=post.cw_text)
            logging.info(f"Status post response: {status_response}")

            # Check if post was successful and set is_posted flag
            # Adjust this condition based on how you determine success
            if status_response:  
                post.is_posted = True

        except Exception as e:
            logging.error(f"Error posting to Mastodon: {e}")

        # Commit the change outside of the try block
        db.session.commit()

@app.route('/', methods=['GET', 'POST'])
def index():
    """Handle post and schedule requests."""
    if request.method == 'POST':
        status = request.form['status']
        file = request.files.get('image')
        schedule_time = request.form.get('schedule_time')
        image_alt = request.form.get('image_alt', '')
        cw_text = request.form.get('cw_text', '')  # Retrieve CW text

        # Generate a unique identifier for the image filename
        unique_id = datetime.utcnow().strftime('%Y%m%d%H%M%S%f')

        if schedule_time:
            schedule_datetime = datetime.strptime(schedule_time, '%Y-%m-%dT%H:%M')
            image_path = None
            if file and allowed_file(file.filename):
                filename = secure_filename(file.filename)
                unique_filename = f"{unique_id}_{filename}"
                file_path = os.path.join(app.config['UPLOAD_FOLDER'], unique_filename)
                file.save(file_path)
                image_path = os.path.join('uploads', unique_filename)

            # Save scheduled post to database
            new_post = ScheduledPost(
                content=status,
                image_path=image_path,
                schedule_time=schedule_datetime,
                image_alt_text=image_alt,
                cw_text=cw_text  # Save CW text
            )
            db.session.add(new_post)
            db.session.commit()

            # Schedule the post
            scheduler.add_job(
                post_to_mastodon, 
                'date', 
                run_date=schedule_datetime, 
                args=[new_post.id],  # Only post_id is needed
                id=f"post_{new_post.id}",
                replace_existing=True
            )
            # Format the datetime for the flash message
            human_readable_time = schedule_datetime.strftime('%b. %d, %Y at %-I:%M %p')
            flash(f"👍 Post scheduled for {human_readable_time}")
        else:
            media_id = None
            if file and allowed_file(file.filename):
                filename = secure_filename(file.filename)
                unique_filename = f"{unique_id}_{filename}"
                file_path = os.path.join(app.config['UPLOAD_FOLDER'], unique_filename)
                file.save(file_path)

                media = mastodon.media_post(file_path)
                if media:
                    mastodon.media_update(media['id'], description=image_alt)
                    media_id = media['id']

                status_response = mastodon.status_post(status, media_ids=[media_id] if media_id else None, spoiler_text=cw_text)
                flash("🛫 Posted Successfully!")
            else:
                # Handle posting without an image
                status_response = mastodon.status_post(status, spoiler_text=cw_text)
                flash("🛫 Posted Successfully!")

    # Fetch Mastodon user info and avatar
    user_info = get_mastodon_user_info()
    username = user_info.username if user_info else "Unknown"
    profile_url = user_info.url if user_info else "#"
    avatar_url = user_info.avatar if user_info else "default_avatar.png"  # Default avatar image if not found

    
    # Query all scheduled posts from the database and order by schedule time ascending
    scheduled_posts = ScheduledPost.query.order_by(ScheduledPost.schedule_time).all()

    # Determine the next up post
    now = datetime.now()
    next_up_post = None
    for post in scheduled_posts:
        if post.schedule_time > now:
            next_up_post = post
            break

    # Pass the scheduled posts, next up post, username, and profile URL to the template
    return render_template('index.html', avatar_url=avatar_url, scheduled_posts=scheduled_posts, next_up_post=next_up_post, username=username, profile_url=profile_url, now=now)

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

@app.route('/delete_post/<int:post_id>', methods=['POST'])
def delete_post(post_id):
    post_to_delete = ScheduledPost.query.get_or_404(post_id)
    
    # Remove the scheduled job
    try:
        scheduler.remove_job(f'post_{post_id}')
    except Exception as e:
        logging.error(f"Error removing job: {e}")

    # Delete the post from the database
    db.session.delete(post_to_delete)
    db.session.commit()

    flash("Scheduled post deleted successfully")
    return redirect(url_for('index'))

@app.route('/edit_post/<int:post_id>', methods=['GET', 'POST'])
def edit_post(post_id):
    post_to_edit = ScheduledPost.query.get_or_404(post_id)

    # Fetch Mastodon user info
    user_info = get_mastodon_user_info()
    username = user_info.username if user_info else "Unknown"
    profile_url = user_info.url if user_info else "#"
    avatar_url = user_info.avatar if user_info else "default_avatar.png"  # Default avatar image if not found
    
    if request.method == 'POST':
        # Update the post details
        post_to_edit.content = request.form['status']
        post_to_edit.cw_text = request.form.get('cw_text', '')
        post_to_edit.image_alt_text = request.form.get('image_alt', '')

        schedule_time = request.form.get('schedule_time')
        if schedule_time:
            new_schedule_time = datetime.strptime(schedule_time, '%Y-%m-%dT%H:%M')
            # Check if the schedule time has actually changed
            if new_schedule_time != post_to_edit.schedule_time:
                post_to_edit.schedule_time = new_schedule_time

                # Create a consistent job ID based on post ID
                job_id = f'post_{post_id}'

                # Remove existing job with the same ID (if any)
                if scheduler.get_job(job_id):
                    try:
                        scheduler.remove_job(job_id)
                    except Exception as e:
                        logging.error(f"Error removing existing job: {e}")

                # Schedule a new job
                try:
                    scheduler.add_job(
                        post_to_mastodon, 
                        'date', 
                        run_date=new_schedule_time, 
                        args=[post_to_edit.id], 
                        id=job_id
                    )
                except Exception as e:
                    logging.error(f"Error scheduling new job: {e}")

        # Handle image update if a new image was uploaded
        file = request.files.get('image')
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            unique_filename = f"{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}_{filename}"
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], unique_filename)
            file.save(file_path)
            post_to_edit.image_path = os.path.join('uploads', unique_filename)

        db.session.commit()

        flash("Scheduled post updated successfully")
        return redirect(url_for('index'))
    else:
        # Present the form for editing with the current post details
        scheduled_posts = ScheduledPost.query.order_by(ScheduledPost.schedule_time).all()
        return render_template('edit_post.html', post=post_to_edit, username=username, profile_url=profile_url, avatar_url=avatar_url)

def get_mastodon_user_info():
    try:
        user_data = mastodon.account_verify_credentials()
        return user_data  # Return the whole user_data object
    except Exception as e:
        logging.error(f"Error fetching user info: {e}")
        return None

@app.route('/api/next_post', methods=['GET'])
def get_next_post():
    next_up_post = ScheduledPost.query.filter(ScheduledPost.schedule_time > datetime.now()).order_by(ScheduledPost.schedule_time).first()
    if next_up_post:
        return {
            "content": next_up_post.content,
            "schedule_time": next_up_post.schedule_time.strftime("%Y-%m-%d %H:%M:%S"),
            "image_path": next_up_post.image_path if next_up_post.image_path else "",
            "image_alt_text": next_up_post.image_alt_text if next_up_post.image_alt_text else "",
            "cw_text": next_up_post.cw_text if next_up_post.cw_text else ""
        }
    return {"message": "No upcoming posts"}, 404

if __name__ == '__main__':
    load_scheduled_posts()  # Load scheduled posts
    app.run(host='0.0.0.0', port=5000, ssl_context=('cert.pem', 'key.pem'))
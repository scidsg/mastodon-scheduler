from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, session
from mastodon import Mastodon
from datetime import datetime, timezone
from werkzeug.utils import secure_filename
import mimetypes
import pytz
import dateutil.parser
from werkzeug.security import check_password_hash, generate_password_hash
from flask_sqlalchemy import SQLAlchemy

app = Flask(__name__)

# Set a secret key for the Flask app
app.secret_key = 'SECRET_KEY'

# Configure the SQLite database
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///mastodon-scheduler.db'
db = SQLAlchemy(app)

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(128))
    client_key = db.Column(db.String(128))
    client_secret = db.Column(db.String(128))
    access_token = db.Column(db.String(128))
    api_base_url = db.Column(db.String(128))

@app.route('/', methods=['GET', 'POST'])
def index():
    if not session.get('authenticated'):
        return redirect(url_for('login'))

    user_id = session.get('user_id')
    user = User.query.get(user_id)

    # Check if user's API credentials are set
    if user and user.client_key and user.client_secret and user.access_token and user.api_base_url:
        # Initialize Mastodon with user's credentials
        mastodon = Mastodon(
            client_id=user.client_key,
            client_secret=user.client_secret,
            access_token=user.access_token,
            api_base_url=user.api_base_url
        )

    error_message = None
    media_id = None

    else:
        # Handle case where user credentials are not set
        flash("Please set your Mastodon API credentials in settings.")
        return redirect(url_for('settings'))

    # Retrieve user information
    try:
        user_info = mastodon.account_verify_credentials()
        user_avatar = user_info['avatar']
        username = user_info['username']
        profile_url = user_info['url']
    except Exception as e:
        user_avatar = None
        username = "User"
        profile_url = "#" 
        print(f"Error fetching user information: {e}")

    if request.method == 'POST':
        content = request.form['content']
        content_warning = request.form.get('content_warning')
        scheduled_time = request.form.get('scheduled_at')
        image = request.files.get('image')
        alt_text = request.form.get('alt_text', '')

        if image and image.filename != '':
            filename = secure_filename(image.filename)
            mimetype = mimetypes.guess_type(filename)[0]

            if not mimetype:
                error_message = "Could not determine the MIME type of the uploaded file."
            else:
                try:
                    media = mastodon.media_post(image, mime_type=mimetype, description=alt_text)
                    media_id = media['id']
                except Exception as e:
                    error_message = f"Error uploading image: {e}"

        if scheduled_time and not error_message:
            try:
                local_datetime = datetime.strptime(scheduled_time, "%Y-%m-%dT%H:%M")
                utc_datetime = local_datetime.astimezone(timezone.utc)
                mastodon.status_post(status=content, spoiler_text=content_warning, media_ids=[media_id] if media_id else None, scheduled_at=utc_datetime)
                flash("👍 Toot scheduled successfully!", "success")
                return redirect(url_for('index'))
            except ValueError:
                error_message = "Invalid date format."

        elif not scheduled_time and not error_message:
            try:
                mastodon.status_post(status=content, spoiler_text=content_warning, media_ids=[media_id] if media_id else None)
                flash("👍 Toot posted successfully!", "success")
                return redirect(url_for('index'))
            except Exception as e:
                error_message = f"Error posting to Mastodon: {e}"

    try:
        scheduled_statuses = mastodon.scheduled_statuses()

        # Debug: Print original order
        print("Original Order:")
        for status in scheduled_statuses:
            print(status['scheduled_at'])

        # Sort the scheduled statuses by their scheduled time in ascending order
        for status in scheduled_statuses:
            if isinstance(status['scheduled_at'], str):
                # Convert string to datetime object
                try:
                    status['scheduled_at_parsed'] = dateutil.parser.parse(status['scheduled_at'])
                except Exception as e:
                    print(f"Error parsing date string: {e}")
                    status['scheduled_at_parsed'] = datetime.min
            elif isinstance(status['scheduled_at'], datetime):
                # If already a datetime object
                status['scheduled_at_parsed'] = status['scheduled_at']
            else:
                status['scheduled_at_parsed'] = datetime.min

        scheduled_statuses.sort(key=lambda x: x['scheduled_at_parsed'])

        # Debug: Print sorted order
        print("Sorted Order:")
        for status in scheduled_statuses:
            print(status['scheduled_at_parsed'])

        for status in scheduled_statuses:
            media_urls = [media['url'] for media in status.get('media_attachments', [])]
            status['media_urls'] = media_urls
    except Exception as e:
        scheduled_statuses = []
        error_message = f"Error fetching scheduled statuses: {e}"
        flash("⚠️ Error fetching scheduled posts.", "error")

    return render_template('index.html', scheduled_statuses=scheduled_statuses, 
                           error_message=error_message, user_avatar=user_avatar, 
                           username=username, profile_url=profile_url)

@app.route('/cancel/<status_id>', methods=['POST'])
def cancel_post(status_id):
    try:
        response = mastodon.scheduled_status_delete(status_id)
        app.logger.info(f"Response from Mastodon API: {response}")
        flash("👍 Scheduled toot canceled successfully!", "success")
    except Exception as e:
        app.logger.error(f"Error canceling scheduled post: {e}")
        flash("⚠️ Error canceling scheduled post.", "error")
    
    return redirect(url_for('index'))

@app.route('/api/next_post', methods=['GET'])
def get_next_post():
    try:
        scheduled_statuses = mastodon.scheduled_statuses()
        if scheduled_statuses:
            # Sort the posts by scheduled time
            sorted_statuses = sorted(scheduled_statuses, key=lambda x: x['scheduled_at'])
            next_post = sorted_statuses[0]  # Get the earliest scheduled post

            post_data = {
                'content': next_post['params']['text'],
                'image_path': next_post['media_attachments'][0]['url'] if next_post['media_attachments'] else None,
                'image_alt_text': next_post['media_attachments'][0]['description'] if next_post['media_attachments'] else None,
                'cw_text': next_post['params']['spoiler_text'],
                'schedule_time': next_post['scheduled_at']
            }
            return jsonify(post_data)
        else:
            return jsonify({'message': 'No scheduled posts'}), 404
    except Exception as e:
        return jsonify({'error': str(e)}), 500

def format_datetime(value, format='%b %d, %Y at %-I:%M %p'):
    """Format a date time to (Default): 'Dec. 1, 2023 at 1:30 PM'"""
    if value is None:
        return ""
    
    # Check if value is already a datetime object
    if isinstance(value, datetime):
        utc_datetime = value
    else:
        # If it's a string, parse it into a datetime object
        try:
            utc_datetime = datetime.strptime(value, "%Y-%m-%dT%H:%M:%S.%fZ")
        except ValueError as e:
            return f"Invalid datetime format: {e}"

    # Ensure the datetime is timezone-aware
    utc_datetime = utc_datetime.replace(tzinfo=pytz.UTC)

    # Convert UTC to local timezone
    local_timezone = pytz.timezone('America/Los_Angeles')  # Adjust to your timezone
    local_datetime = utc_datetime.astimezone(local_timezone)

    return local_datetime.strftime(format)

app.jinja_env.filters['datetime'] = format_datetime

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']

        user = User.query.filter_by(username=username).first()
        if user and check_password_hash(user.password_hash, password):
            session['authenticated'] = True
            session['user_id'] = user.id  # Store user ID in session
            return redirect(url_for('index'))
        else:
            flash('Invalid username or password')

    return render_template('login.html')

@app.route('/logout')
def logout():
    session.pop('authenticated', None)  # Clear the 'authenticated' session key
    return redirect(url_for('login'))   # Redirect to the login page

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        # Check if user already exists
        if User.query.filter_by(username=username).first():
            flash('Username already exists')
            return redirect(url_for('register'))
        # Create new user
        hashed_password = generate_password_hash(password)
        new_user = User(username=username, password_hash=hashed_password)
        db.session.add(new_user)
        db.session.commit()
        flash('Account created successfully')
        return redirect(url_for('login'))
    return render_template('register.html')

@app.route('/settings', methods=['GET', 'POST'])
def settings():
    if not session.get('authenticated'):
        return redirect(url_for('login'))

    user_id = session.get('user_id')
    user = User.query.get(user_id)

    if request.method == 'POST':
        user.client_key = request.form.get('client_key')
        user.client_secret = request.form.get('client_secret')
        user.access_token = request.form.get('access_token')
        user.api_base_url = request.form.get('api_base_url')

        db.session.commit()
        flash('Settings updated successfully', 'success')

    # Pass the current credentials to the template
    return render_template('settings.html', user=user)


if __name__ == '__main__':
    app.run()
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, session
from flask_wtf import FlaskForm
from wtforms import StringField, TextAreaField, PasswordField, SubmitField, FileField, SelectField, ValidationError
import re
from wtforms.validators import DataRequired, Length, Optional, EqualTo
from flask_wtf.file import FileAllowed
from mastodon import Mastodon
from datetime import datetime, timezone
from werkzeug.utils import secure_filename
import mimetypes
import pytz
import dateutil.parser
from werkzeug.security import check_password_hash, generate_password_hash
from flask_sqlalchemy import SQLAlchemy
from encryption_utils import encrypt_data, decrypt_data

app = Flask(__name__)

def load_key():
    # Load key from file or environment variable
    with open('/etc/mastodon-scheduler/encryption.key', 'rb') as key_file:
        return key_file.read()

app.config['SECRET_KEY'] = load_key()

# Configure the SQLite database
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///mastodon-scheduler.db'
db = SQLAlchemy(app)

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(128))
    _client_key_encrypted = db.Column('client_key', db.LargeBinary)
    _client_secret_encrypted = db.Column('client_secret', db.LargeBinary)
    _access_token_encrypted = db.Column('access_token', db.LargeBinary)
    _api_base_url_encrypted = db.Column('api_base_url', db.LargeBinary)
    timezone = db.Column(db.String(50), default='UTC')  # Default to UTC

    # Client key encrypted field and its getter and setter
    @property
    def client_key(self):
        if self._client_key_encrypted:
            return decrypt_data(self._client_key_encrypted, app.config['SECRET_KEY'])
        return None

    @client_key.setter
    def client_key(self, value):
        self._client_key_encrypted = encrypt_data(value, app.config['SECRET_KEY'])

    # Client secret encrypted field and its getter and setter
    @property
    def client_secret(self):
        if self._client_secret_encrypted:
            return decrypt_data(self._client_secret_encrypted, app.config['SECRET_KEY'])
        return None

    @client_secret.setter
    def client_secret(self, value):
        self._client_secret_encrypted = encrypt_data(value, app.config['SECRET_KEY'])

    # Access token encrypted field and its getter and setter
    @property
    def access_token(self):
        if self._access_token_encrypted:
            return decrypt_data(self._access_token_encrypted, app.config['SECRET_KEY'])
        return None

    @access_token.setter
    def access_token(self, value):
        self._access_token_encrypted = encrypt_data(value, app.config['SECRET_KEY'])

    # API base URL encrypted field and its getter and setter
    @property
    def api_base_url(self):
        if self._api_base_url_encrypted:
            return decrypt_data(self._api_base_url_encrypted, app.config['SECRET_KEY'])
        return None

    @api_base_url.setter
    def api_base_url(self, value):
        self._api_base_url_encrypted = encrypt_data(value, app.config['SECRET_KEY'])

def get_mastodon_client(user):
    return Mastodon(
        client_id=user.client_key,
        client_secret=user.client_secret,
        access_token=user.access_token,
        api_base_url=user.api_base_url
    )

# Define the form class
class PostForm(FlaskForm):
    content = TextAreaField('What\'s on Your Mind?', validators=[DataRequired(), Length(max=500)])
    content_warning = StringField('Content Warning', validators=[Optional(), Length(max=500)])
    image = FileField('Add an Image', validators=[Optional(), FileAllowed(['jpg', 'png', 'gif', 'jpeg'], 'Images only!')])
    alt_text = TextAreaField('Alt Text', validators=[Optional(), Length(max=1500)])
    scheduled_at = StringField('Schedule Post', validators=[Optional()])
    submit = SubmitField('Toot!')

@app.route('/', methods=['GET', 'POST'])
def index():
    if not session.get('authenticated'):
        return redirect(url_for('login'))

    form = PostForm()
    user_id = session.get('user_id')
    user = User.query.get(user_id)

    if user is None:
        flash("User not found. Please log in again.")
        return redirect(url_for('login'))

    # Initialize Mastodon with user's credentials
    if user.client_key and user.client_secret and user.access_token and user.api_base_url:
        mastodon = Mastodon(
            client_id=user.client_key,
            client_secret=user.client_secret,
            access_token=user.access_token,
            api_base_url=user.api_base_url
        )
    else:
        flash("👇 Please set your Mastodon API credentials.")
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

    if form.validate_on_submit():
        content = form.content.data
        content_warning = form.content_warning.data
        scheduled_time = form.scheduled_at.data
        image = form.image.data
        alt_text = form.alt_text.data

        if scheduled_time:
            try:
                # Convert the scheduled time from the user's timezone to UTC
                user_timezone = pytz.timezone(user.timezone) if user.timezone else pytz.utc
                local_datetime = datetime.strptime(scheduled_time, "%Y-%m-%dT%H:%M")
                local_datetime = user_timezone.localize(local_datetime)
                utc_datetime = local_datetime.astimezone(pytz.utc)
            except Exception as e:
                flash(f"Error in date conversion: {e}", 'error')
                return render_template('index.html', form=form, user_avatar=user_avatar, username=username, profile_url=profile_url)

            error_message, media_id = handle_post(mastodon, content, content_warning, utc_datetime, image, alt_text)
            if not error_message:
                return redirect(url_for('index'))
            else:
                flash(error_message, 'error')

    try:
        scheduled_statuses = mastodon.scheduled_statuses()
        # Process scheduled statuses as before
    except Exception as e:
        scheduled_statuses = []
        flash(f"Error: {e}", 'error')

    return render_template('index.html', form=form, scheduled_statuses=scheduled_statuses, 
                           user_avatar=user_avatar, username=username, profile_url=profile_url)

def handle_post(mastodon, content, content_warning, utc_datetime, image, alt_text):
    """
    Handle the posting logic. This function tries to upload an image, schedule or post a toot.
    Returns a tuple of error_message and media_id.
    """
    media_id = None
    error_message = None

    if image:
        filename = secure_filename(image.filename)
        mimetype = mimetypes.guess_type(filename)[0]
        if not mimetype:
            error_message = "Could not determine the MIME type of the uploaded file."
        else:
            try:
                media = mastodon.media_post(image.stream, mime_type=mimetype, description=alt_text)
                media_id = media['id']
            except Exception as e:
                error_message = f"Error uploading image: {e}"

    if utc_datetime and not error_message:  # Use utc_datetime directly without parsing
        try:
            mastodon.status_post(status=content, spoiler_text=content_warning, media_ids=[media_id] if media_id else None, scheduled_at=utc_datetime)
            flash("👍 Toot scheduled successfully!", "success")
        except Exception as e:
            error_message = f"Error scheduling post: {e}"
    elif not utc_datetime and not error_message:
        try:
            mastodon.status_post(status=content, spoiler_text=content_warning, media_ids=[media_id] if media_id else None)
            flash("👍 Toot posted successfully!", "success")
        except Exception as e:
            error_message = f"Error posting to Mastodon: {e}"

    return error_message, media_id

@app.route('/cancel/<status_id>', methods=['POST'])
def cancel_post(status_id):
    user_id = session.get('user_id')
    if not user_id:
        flash("⚠️ You need to be logged in to cancel a post.", "error")
        return redirect(url_for('login'))
    
    user = User.query.get(user_id)
    if not user:
        flash("⚠️ User not found.", "error")
        return redirect(url_for('index'))

    mastodon = get_mastodon_client(user)

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

def format_datetime(value, user_timezone_str='UTC', format='%b %d, %Y at %-I:%M %p'):
    """Format a datetime to the user's local timezone."""
    if value is None:
        return ""
    
    try:
        # Parse the datetime string into a datetime object
        utc_datetime = value if isinstance(value, datetime) else datetime.strptime(value, "%Y-%m-%dT%H:%M:%S.%fZ")
        utc_datetime = utc_datetime.replace(tzinfo=pytz.UTC)

        # Convert UTC to the user's local timezone
        user_timezone = pytz.timezone(user_timezone_str)
        local_datetime = utc_datetime.astimezone(user_timezone)

        return local_datetime.strftime(format)
    except (ValueError, pytz.exceptions.UnknownTimeZoneError) as e:
        return f"Error in datetime conversion: {e}"

app.jinja_env.filters['datetime'] = format_datetime

# Define the LoginForm class
class LoginForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired(), Length(min=4, max=80)])
    password = PasswordField('Password', validators=[DataRequired()])
    submit = SubmitField('Login')

@app.route('/login', methods=['GET', 'POST'])
def login():
    form = LoginForm()
    if form.validate_on_submit():
        username = form.username.data
        password = form.password.data

        user = User.query.filter_by(username=username).first()
        if user and check_password_hash(user.password_hash, password):
            session['authenticated'] = True
            session['user_id'] = user.id
            return redirect(url_for('index'))
        else:
            flash('⛔️ Invalid username or password')

    return render_template('login.html', form=form)

@app.route('/logout')
def logout():
    session.pop('authenticated', None)  # Clear the 'authenticated' session key
    return redirect(url_for('login'))   # Redirect to the login page

# Password Requirements
def password_length(min=-1, max=-1):
    def _password_length(form, field):
        if len(field.data) < min or (max != -1 and len(field.data) > max):
            raise ValidationError(f'Password must be between {min} and {max} characters long.')
    return _password_length

def password_contains_number():
    def _password_contains_number(form, field):
        if not re.search(r'\d', field.data):
            raise ValidationError('Password must contain at least one number.')
    return _password_contains_number

def password_contains_uppercase():
    def _password_contains_uppercase(form, field):
        if not re.search(r'[A-Z]', field.data):
            raise ValidationError('Password must contain at least one uppercase letter.')
    return _password_contains_uppercase

def password_contains_special():
    def _password_contains_special(form, field):
        if not re.search(r'[\W_]', field.data):  # \W matches any non-word character, _ is included as it's not covered by \W
            raise ValidationError('Password must contain at least one special character.')
    return _password_contains_special

# Define the RegistrationForm class
class RegistrationForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired(), Length(min=4, max=80)])
    password = PasswordField('Password', validators=[
        DataRequired(),
        password_length(min=16, max=128),
        password_contains_number(),
        password_contains_uppercase(),
        password_contains_special()
    ])
    confirm_password = PasswordField('Confirm Password', validators=[
        DataRequired(),
        EqualTo('password', message='Passwords must match.')
    ])
    invite_code = StringField('Invite Code', validators=[DataRequired(), Length(min=4, max=80)])
    submit = SubmitField('Register')

@app.route('/register', methods=['GET', 'POST'])
def register():
    form = RegistrationForm()

    if form.validate_on_submit():
        username = form.username.data
        password = form.password.data
        confirm_password = form.confirm_password.data
        invite_code = form.invite_code.data

        # Validate invite code
        code = InviteCode.query.filter_by(code=invite_code, used=False).first()
        if not code or code.is_expired:
            flash('⛔️ Invalid or expired invite code', 'error')
            return redirect(url_for('register'))

        # Check if user already exists
        if User.query.filter_by(username=username).first():
            flash('💔 Username already exists', 'error')
            return redirect(url_for('register'))

        # Create new user
        hashed_password = generate_password_hash(password)
        new_user = User(username=username, password_hash=hashed_password)
        db.session.add(new_user)

        # Mark invite code as used
        code.used = True
        db.session.commit()

        flash('👍 Account created successfully', 'success')
        return redirect(url_for('login'))

    return render_template('register.html', form=form)

class SettingsForm(FlaskForm):
    client_key = StringField('Client Key', validators=[DataRequired()])
    client_secret = StringField('Client Secret', validators=[DataRequired()])
    access_token = StringField('Access Token', validators=[DataRequired()])
    api_base_url = StringField('API Base URL', validators=[DataRequired()])
    timezone = SelectField('Timezone', choices=[(tz, tz) for tz in pytz.all_timezones], default='UTC')
    submit = SubmitField('Save Settings')

@app.route('/settings', methods=['GET', 'POST'])
def settings():
    if not session.get('authenticated'):
        return redirect(url_for('login'))

    user_id = session.get('user_id')
    user = User.query.get(user_id)
    if not user:
        flash("User not found.", "error")
        return redirect(url_for('index'))

    form = SettingsForm(obj=user)

    if form.validate_on_submit():
        user.client_key = form.client_key.data
        user.client_secret = form.client_secret.data
        user.access_token = form.access_token.data
        user.api_base_url = form.api_base_url.data
        user.timezone = form.timezone.data

        # Create a Mastodon instance here with the new settings
        mastodon = get_mastodon_client(user)

        try:
            # Verify the credentials with Mastodon
            user_info = mastodon.account_verify_credentials()
            user_avatar = user_info['avatar']
            username = user_info['username']
            profile_url = user_info['url']
            # If we reach this point, the credentials are good
            db.session.commit()
            flash('👍 Settings updated successfully', 'success')
            # You might want to redirect to a different page on success,
            # For example, back to the profile page or dashboard
            return redirect(url_for('settings'))
        except Exception as e:
            # If the new credentials are not valid, do not commit to the database
            flash(f"⚠️ Failed to verify Mastodon credentials: {e}", "error")

    # If not form.validate_on_submit() i.e., either GET request or form submission failure
    user_avatar = None
    username = "User"
    profile_url = "#"
    
    # Optional: if you want to display the current user info, regardless of form submission
    if user.client_key and user.client_secret and user.access_token and user.api_base_url:
        mastodon = get_mastodon_client(user)
        try:
            user_info = mastodon.account_verify_credentials()
            user_avatar = user_info['avatar']
            username = user_info['username']
            profile_url = user_info['url']
        except Exception as e:
            flash(f"⚠️ Error retrieving Mastodon profile: {e}", "error")

    return render_template('settings.html', form=form, user_avatar=user_avatar, username=username, profile_url=profile_url)

class InviteCode(db.Model):
    __tablename__ = 'invite_code'
    id = db.Column(db.Integer, primary_key=True)
    code = db.Column(db.String(16), unique=True, nullable=False)
    expiration_date = db.Column(db.DateTime, nullable=False)
    used = db.Column(db.Boolean, default=False, nullable=False)

    __table_args__ = {'extend_existing': True}

    @property
    def is_expired(self):
        return datetime.utcnow() > self.expiration_date

if __name__ == '__main__':
    app.run()
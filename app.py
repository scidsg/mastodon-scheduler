from flask import Flask, render_template, request, redirect, url_for, flash
from mastodon import Mastodon
import datetime
from werkzeug.utils import secure_filename
import mimetypes
import pytz

app = Flask(__name__)

# Set a secret key for the Flask app
app.secret_key = 'SECRET_KEY'

# Initialize Mastodon
mastodon = Mastodon(
    client_id='CLIENT_KEY',
    client_secret='CLIENT_SECRET',
    access_token='ACCESS_TOKEN',
    api_base_url='MASTODON_URL'
)

@app.route('/', methods=['GET', 'POST'])
def index():
    error_message = None
    media_id = None

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
                local_datetime = datetime.datetime.strptime(scheduled_time, "%Y-%m-%dT%H:%M")
                utc_datetime = local_datetime.astimezone(datetime.timezone.utc)
                mastodon.status_post(status=content, spoiler_text=content_warning, media_ids=[media_id] if media_id else None, scheduled_at=utc_datetime)
                flash("Toot scheduled successfully!", "success")
                return redirect(url_for('index'))
            except ValueError:
                error_message = "Invalid date format."

        elif not scheduled_time and not error_message:
            try:
                mastodon.status_post(status=content, spoiler_text=content_warning, media_ids=[media_id] if media_id else None)
                flash("Toot posted successfully!", "success")
                return redirect(url_for('index'))
            except Exception as e:
                error_message = f"Error posting to Mastodon: {e}"

    try:
        scheduled_statuses = mastodon.scheduled_statuses()
        for status in scheduled_statuses:
            media_urls = [media['url'] for media in status.get('media_attachments', [])]
            status['media_urls'] = media_urls
    except Exception as e:
        scheduled_statuses = []
        error_message = f"Error fetching scheduled statuses: {e}"
        flash("Error fetching scheduled posts.", "error")

    return render_template('index.html', scheduled_statuses=scheduled_statuses, 
                           error_message=error_message, user_avatar=user_avatar, 
                           username=username, profile_url=profile_url)

@app.route('/cancel/<status_id>', methods=['POST'])
def cancel_post(status_id):
    try:
        mastodon.scheduled_status_delete(status_id)
        flash("Scheduled toot canceled successfully!", "success")
    except Exception as e:
        app.logger.error(f"Error canceling scheduled post: {e}")
        flash("Error canceling scheduled post.", "error")
    
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, ssl_context=('cert.pem', 'key.pem'))
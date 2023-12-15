from flask import Flask, render_template, request, redirect, url_for
from mastodon import Mastodon
import datetime
from werkzeug.utils import secure_filename
import mimetypes
import pytz

app = Flask(__name__)

# Initialize Mastodon
mastodon = Mastodon(
    client_id='$CLIENT_KEY',
    client_secret='$CLIENT_SECRET',
    access_token='$ACCESS_TOKEN',
    api_base_url='$INSTANCE_URL'
)

@app.route('/', methods=['GET', 'POST'])
def index():
    error_message = None
    media_id = None

    if request.method == 'POST':
        content = request.form['content']
        content_warning = request.form.get('content_warning')
        scheduled_time = request.form.get('scheduled_at')
        image = request.files.get('image')
        alt_text = request.form.get('alt_text', '')

        # Handle image upload
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

        # Handling scheduled post
        if scheduled_time and not error_message:
            try:
                local_datetime = datetime.datetime.strptime(scheduled_time, "%Y-%m-%dT%H:%M")
                utc_datetime = local_datetime.astimezone(datetime.timezone.utc)
                mastodon.status_post(status=content, spoiler_text=content_warning, media_ids=[media_id] if media_id else None, scheduled_at=utc_datetime)
                return redirect(url_for('index'))
            except ValueError:
                error_message = "Invalid date format."

        # Handling immediate post
        elif not scheduled_time and not error_message:
            mastodon.status_post(status=content, spoiler_text=content_warning, media_ids=[media_id] if media_id else None)
            return redirect(url_for('index'))

    try:
        scheduled_statuses = mastodon.scheduled_statuses()

        # Extract media URLs from scheduled statuses
        for status in scheduled_statuses:
            media_urls = [media['url'] for media in status.get('media_attachments', [])]
            status['media_urls'] = media_urls
    except Exception as e:
        scheduled_statuses = []
        error_message = f"Error fetching scheduled statuses: {e}"

    return render_template('index.html', scheduled_statuses=scheduled_statuses, error_message=error_message)

@app.route('/cancel/<status_id>', methods=['POST'])
def cancel_post(status_id):
    try:
        mastodon.scheduled_status_delete(status_id)
    except Exception as e:
        app.logger.error(f"Error canceling scheduled post: {e}")
    
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, ssl_context=('cert.pem', 'key.pem'))
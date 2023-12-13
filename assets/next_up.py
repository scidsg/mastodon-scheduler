import requests
import time
import sys
import os
import http.client as http_client
from waveshare_epd import epd2in13_V3
from datetime import datetime
from PIL import Image, ImageDraw, ImageFont, ImageOps
import textwrap

def fetch_next_post():
    try:
        response = requests.get('https://mastodon-scheduler.local:5000/api/next_post')
        if response.status_code == 200:
            return response.json()
        else:
            return None
    except requests.RequestException as e:
        print(f"Error fetching next post: {e}")
        return None

from PIL import Image, ImageDraw, ImageFont, ImageOps
import textwrap

def display_post(epd, post_data):
    print('Displaying next scheduled post...')
    image = Image.new('1', (epd.height, epd.width), 255)
    draw = ImageDraw.Draw(image)

    # Define font sizes
    font_post = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf', 11)
    font_schedule = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf', 10)
    font_meta = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf', 11)

    # Prepare and wrap post content
    post_content = post_data.get('content', 'No content').replace("\n", " ")
    wrapped_post_content = textwrap.fill(post_content, width=30)  # Adjust width as needed

    # Truncate long posts and add ellipsis if truncated
    max_lines = 4
    wrapped_post_content_lines = wrapped_post_content.split('\n')
    if len(wrapped_post_content_lines) > max_lines:
        wrapped_post_content_lines = wrapped_post_content_lines[:max_lines]
        wrapped_post_content_lines[-1] += '…'

    # Calculate post content height
    post_content_height = sum(draw.textsize(line, font=font_post)[1] for line in wrapped_post_content_lines)

    # Check for image, alt text, and content warning
    has_image = '✔' if post_data.get('image_path') else '✖'
    has_alt_text = '✔' if post_data.get('image_alt_text') else '✖'
    has_cw = '✓' if post_data.get('cw_text') else '✖'
    metadata = f"Img: {has_image} Alt: {has_alt_text} CW: {has_cw}"
    metadata_height = draw.textsize(metadata, font=font_meta)[1]

    # Format schedule time
    schedule_time_str = post_data.get('schedule_time', '')
    if schedule_time_str:
        try:
            schedule_time_obj = datetime.strptime(schedule_time_str, '%Y-%m-%d %H:%M:%S')
            formatted_schedule_time = schedule_time_obj.strftime('%b %d, %Y at %-I:%M %p')
        except ValueError:
            formatted_schedule_time = schedule_time_str
    else:
        formatted_schedule_time = 'No schedule time'

    schedule_time = "Scheduled for " + formatted_schedule_time
    schedule_time_height = draw.textsize(schedule_time, font=font_schedule)[1]

    # Calculate total height of text block including metadata
    total_text_height = post_content_height + metadata_height + schedule_time_height + 17  # Adjust padding as needed

    # Calculate starting Y position for vertical centering
    start_y = (epd.width - total_text_height) // 2

    # Draw wrapped post content
    y = start_y
    for line in wrapped_post_content_lines:
        draw.text((5, y), line, font=font_post, fill=0)
        y += draw.textsize(line, font=font_post)[1]

    # Draw metadata
    draw.text((5, y + 7), metadata, font=font_meta, fill=0)
    y += metadata_height + 5

    # Draw schedule time
    draw.text((5, y + 10), schedule_time, font=font_schedule, fill=0)

    # Send image to e-paper display
    epd.display(epd.getbuffer(image.rotate(270, expand=True)))

def main():
    print("Starting Mastodon display script")
    epd = epd2in13_V3.EPD()
    epd.init()
    print("EPD initialized")

    try:
        while True:
            next_post = fetch_next_post()
            if next_post:
                display_post(epd, next_post)
            else:
                print("No upcoming posts. Displaying message on screen...")
                display_no_posts_message(epd)
            time.sleep(60)
    except KeyboardInterrupt:
        print('Exiting...')
        sys.exit(0)
    except Exception as e:
        print(f"Unexpected error: {e}")
        sys.exit(1)

def display_no_posts_message(epd):
    image = Image.new('1', (epd.height, epd.width), 255)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf', 11)
    message = "No scheduled posts"
    draw.text((5, 50), message, font=font, fill=0)
    epd.display(epd.getbuffer(image.rotate(270, expand=True)))

if __name__ == '__main__':
    main()
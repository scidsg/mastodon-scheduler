# 🗓️ Mastodon Scheduler

This project is a Flask-based web application that allows users to post statuses (toots) to Mastodon. It supports both immediate posting and scheduling posts for future times. It also includes image upload functionality.

## Features

- Post immediately to Mastodon.
- Schedule posts for future times.
- Upload images with your posts.
- View a list of scheduled posts.

![tooter](https://github.com/glenn-sorrentino/mastodon-scheduler/assets/28545431/6b5b04bd-b7bb-4c1b-a90a-562245504b2c)

## Prerequisites

Before you begin, ensure you have met the following requirements:
- You have a Linux machine with Python 3, pip, and Git installed.
- You have a Mastodon account and have generated your Mastodon API credentials (Client Key, Client Secret, Access Token).

## Installation

To install the Mastodon App, follow these steps:

1. Clone the repository:
```bash
git clone https://github.com/glenn-sorrentino/mastodon_scheduler.git
```
  
2. Navigate to the project directory:
```bash
cd mastodon_scheduler
```

3. Run the installation script:

```bash
./install.sh
```

This script will set up a Python virtual environment, install necessary dependencies, create a Flask app, and set up a systemd service for the app.

## Usage

After installation, the Mastodon App will be running as a service on your machine. You can access the web interface by navigating to `https://tooter.local:5000` in your web browser.

To post a status or schedule a post, simply fill in the form on the main page and submit.

## Contributing

Contributions to this project are welcome. To contribute, please follow these steps:

1. Fork this repository.
2. Create a branch: `git checkout -b <branch_name>`.
3. Make your changes and commit them: `git commit -m '<commit_message>'`.
4. Push to the original branch: `git push origin <project_name>/<location>`.
5. Create the pull request.

Alternatively, see the GitHub documentation on [creating a pull request](https://help.github.com/articles/creating-a-pull-request/).

## Contact

If you have any questions or feedback, please contact me at hello@scidsg.org.
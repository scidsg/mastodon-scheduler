# 🗓️ Mastodon Scheduler

This project is a Flask-based web application that allows users to post statuses (toots) to Mastodon. It supports both immediate posting and scheduling posts for future times. It also includes image upload functionality.

## Easy Install
```bash
curl https://raw.githubusercontent.com/glenn-sorrentino/mastodon-scheduler/hosted/install.sh | bash
```

![beta-cover](https://github.com/scidsg/mastodon-scheduler/assets/28545431/63834369-4613-48d4-bc92-158055e8bda6)

## Features

- **Post Immediately**: Send toots to Mastodon right away.
- **Schedule Posts**: Plan your posts for future dates and times.
- **Upload Images**: Attach images to your toots with ease.
- **Content Warnings**: Add content warnings to your posts for sensitive or spoiler content.
- **Image Alt Text**: Provide alternative text for images, enhancing accessibility.
- **View Scheduled Posts**: Review all your scheduled posts in one place.
- **Cancel Scheduled Posts**: Cancel scheduled posts before publication.

## Prerequisites

Before you begin the installation of Mastodon Scheduler, ensure you have:

- **Linux Environment**: A compatible Linux operating system. The installation script is tailored for Debian-based distributions (e.g., Ubuntu).
- **Root Access**: The script requires root privileges to install necessary packages and perform configurations.
- **Internet Connection**: An active internet connection to download required packages and dependencies.
- **Mastodon Account**: A Mastodon account and your generated API credentials (Client Key, Client Secret, Access Token) with the following scopes:
  -  `read:accounts`
  -  `read:statuses`
  -  `write:media`
  -  `write:statuses`
  -  `crypto`

## Installation

To install the Mastodon App, follow these steps:

1. Run the easy installer command:
```bash
curl https://raw.githubusercontent.com/glenn-sorrentino/mastodon-scheduler/main/install.sh | bash
```
or

1. Clone the repository:
```bash
git clone https://github.com/glenn-sorrentino/mastodon-scheduler.git
```
  
2. Navigate to the project directory:
```bash
cd mastodon-scheduler
```

3. Make the installer executable:

```bash
chmod +x install.sh
```

4. Run the installation script:

```bash
./install.sh
```

This script will set up a Python virtual environment, install necessary dependencies, create a Flask app, and set up a systemd service for the app.

## Contributing

Contributions to this project are welcome. To contribute, please follow these steps:

1. Fork this repository.
2. Create a branch: `git checkout -b <branch_name>`.
3. Make and commit your changes: `git commit -m '<commit_message>'`.
4. Push to the original branch: `git push origin <project_name>/<location>`.
5. Create the pull request.

Alternatively, see the GitHub documentation on [creating a pull request](https://help.github.com/articles/creating-a-pull-request/).

## Contact

If you have any questions or feedback, please get in touch with me at glenn@scidsg.org.

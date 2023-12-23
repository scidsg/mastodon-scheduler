# 🗓️ Mastodon Scheduler

This project is a Flask-based web application that allows users to post statuses (toots) to Mastodon. It supports both immediate posting and scheduling posts for future times. It also includes image upload functionality.

## Easy Install
```bash
curl https://raw.githubusercontent.com/glenn-sorrentino/mastodon-scheduler/main/install.sh | bash
```

![cover](https://github.com/glenn-sorrentino/mastodon-scheduler/assets/28545431/10908fcd-e4e1-4d2e-a719-02da704b61fd)

## Features

- **Post Immediately**: Send toots to Mastodon right away.
- **Schedule Posts**: Plan your posts for future dates and times.
- **Upload Images**: Attach images to your toots with ease.
- **Content Warnings**: Add content warnings to your posts for sensitive or spoiler content.
- **Image Alt Text**: Provide alternative text for images, enhancing accessibility.
- **View Scheduled Posts**: Review all your scheduled posts in one place.
- **Cancel Scheduled Posts**: Cancel scheduled posts before publication.

## Love E-Paper?

Waveshare's 2.13" e-paper display is supported! 

### Easy Insall

```bash
curl https://raw.githubusercontent.com/glenn-sorrentino/mastodon-scheduler/main/display.sh | bash
```

![IMG_8299](https://github.com/glenn-sorrentino/mastodon-scheduler/assets/28545431/304e3381-f573-4179-95b3-925b2138c44e)

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

## Usage

After installation, the Mastodon App will run as a service on your machine. You can access the web interface by navigating to `https://mastodon-scheduler.local:5000` in your web browser.

To post a status or schedule a post, fill in the form on the main page and submit.

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

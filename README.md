# 🗓️ Mastodon Scheduler

This project is a Flask-based web application that allows users to post statuses (toots) to Mastodon. It supports both immediate posting and scheduling posts for future times. It also includes image upload functionality.

## Easy Install
```bash
curl https://raw.githubusercontent.com/glenn-sorrentino/mastodon-scheduler/hosted/install.sh | bash
```

![beta-cover](https://github.com/glenn-sorrentino/mastodon-scheduler/assets/28545431/c684905e-f4b5-4654-b766-04ad9ad7fe09)

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

## Privacy and Security Features

Our Mastodon Scheduler app prioritizes privacy and security right from the installation process. The install.sh script, designed to be run with root privileges, ensures a secure setup by performing tasks such as:

- **Tor Integration:** We configure Tor to offer users an additional layer of anonymity. The torrc configuration includes running Tor as a daemon and setting up a hidden service for your domain, allowing access through an Onion address.
- **HTTPS Setup:** We use Certbot for SSL/TLS certificate management, ensuring all data transmitted between the server and clients is encrypted.
- **Secure Server Settings:** Nginx is configured with security headers like `Strict-Transport-Security` and `X-Content-Type-Options`, enhancing protection against common web vulnerabilities.

- **Encryption of Sensitive Data:** We encrypt sensitive user information such as API keys and tokens using `encryption_utils`. This prevents unauthorized access to user credentials.
```
sqlite> SELECT * FROM user;
1|gs|scrypt:32768:8:1$Y0MAydnXNHr3EHgL$210c702d4fcb1f8c57b53b84d7dd5928c39eec4200d1390379c67b6c46d47bf414a13d94b570d281a7c2001843886906bbac930926fac965b47c144d6d524054|gAAAAABlg-qz9i1uGHmDxFLNExq_Rv_T2ek8L9KLmflNjOHwm9JLYarNBGq_xYyCPrMV-Z7WNYeo8BoW0Vqiz05L2ZX2JKV5SqW9GD4URwzZhSZe6W406d8-lNGCLipLHOPwCGcsjCBC|gAAAAABlg-qzbLP4HYFCVwYqoPKdSwRhKYMt9lsiYDcNwcqlHobt-CIa6cLrwtAug3bUF9Wq43T9td4FV1OKPS76acw0S3aNX2ZFIoIsceCoPpZn_y2rSUUEmg00lVnww-TkInDK8Wsh|gAAAAABlg-qzNzNjShzecNO8_nuWlpuEv70chOmvT4n1cQ0Mx6rz0segY2qUcG80kgftwJ1jfq_xonx81MOV5fnhONvk0ELdjzMTNwtySO6MejLwRcrZqvPZ3GId0SnbvTudsNRdkIvk|gAAAAABlg-qzZBQLMghwOipWfBYkxiFYMIe9lJszcD3b2BMjnDqBQQ9hKMIIXHWlFqWWW3uA4zw3oDaa8PUOSA8d1a1eXUN9gNng9UClEdEPdN5onEYJjxQ=
```
 
- **Secure Authentication**: Passwords are hashed using Werkzeug's `generate_password_hash`, ensuring they are stored securely. Login verification is done using `check_password_hash`.
- **SQLAlchemy for Database Interaction:** By using SQLAlchemy, we reduce the risk of SQL injection attacks. It abstracts database queries and uses parameterized statements.
- **Flask-WTF for Forms:** This tool provides CSRF protection for our forms, safeguarding against Cross-Site Request Forgery attacks.
- **Data Validation and Sanitization:** Input validation is implemented using WTForms validators, ensuring that only properly formatted data is accepted.

### System-Level Security

Back in install.sh, system-level security measures are employed:

- **Fail2Ban and UFW:** These tools protect against brute force attacks and unauthorized access. Fail2Ban monitors log files for suspicious activity and bans IPs that show malicious signs, while UFW (Uncomplicated Firewall) manages network traffic rules.
- **Unattended Upgrades:** The system is configured to automatically apply security updates, ensuring that the server is protected against known vulnerabilities.
- **Privacy-Preserving Logging:** Nginx is configured to log requests in a way that respects user privacy. The logs are sanitized to prevent storing IP addresses.

### Data Privacy

We handle user data with the utmost respect for privacy:

- **Minimal Data Collection:** The app collects only the data necessary for functionality.
- **Transparency:** Users are informed about the data collected and its usage.
- **User Control:** Users have control over their data, with the ability to modify or delete their information.

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

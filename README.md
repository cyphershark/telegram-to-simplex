# telegram-to-simplex
telegram-to-simplex is a relay that lets you transfer news you've seen on [Telegram](https://github.com/TelegramOfficial) directly into [SimpleX Chat](https://github.com/simplex-chat/simplex-chat) groups

Languages: 
 - 🇺🇸 English
 - [⬜️🟦⬜️ Russian](README.ru.md)

## Motivation
Telegram is a great source of relatively **unmoderated news**, but it lacks strong chatting privacy protecting features like E2EE-by-default, MTProto audit, and a disclosed server source code. SimpleX Chat, on the opposite, is a great **privacy friendly messaging tool** (and an app), yet it lacks good channel support (added 30 April 2026, but still lacks huge audience for major platforms to migrate to SimpleX). 
telegram-to-simplex acknowledges that difference and aims to create **a better cross interface user experience for users of both platforms** to take the best of both: communication privacy of SimpleX Chat and free speech nature of Telegram. 

## Features
With telegram-to-simplex, you can:
- Send a Telegram **text message** to a SimpleX Chat group;
- Send a Telegram **image** to a SimpleX Chat group, the image will be visible and delivered not as a usual file;
- Send a Telegram **file** to a SimpleX Chat group;
- **Forward a Telegram message** to a SimpleX Chat group, with source name and link on top of the final message;
- **Protect Telegram bot with a password**, so that the aliens can't use your relay;

## Installation
### Flow tree
```
Prerequisites: create Telegram bot (token) + copy SimpleX group link 👤
                              │
                       🔀 Pick path
                              │
            ┌─────────────────┴─────────────────┐
            ▼                                   ▼
      QUICK INSTALL                       MANUAL INSTALL
            │                                   │
   1. Run install.sh 🤖              1. System dependencies 👤
      (deps + openssl@3,             2. SimpleX Chat CLI install 👤
       arch-aware CLI binary            (download + ad-hoc sign +
       + ad-hoc sign + openssl           openssl symlink bridge)
       symlink bridge, repo,         3. Clone repo + venv + .env
       venv, .env template)             template 👤
            │                                   │
            └─────────────────┬─────────────────┘
                              ▼
   2. Start SimpleX profile + server on :5225 👤
      simplex-chat -d ~/simplex-data/bot -p 5225
      └─ first run only: set a display name when prompted
      └─ leave it running (the wizard connects to it)
                              ▼
   3. Run the setup.py wizard 🤖  (you answer 3 prompts 👤)
      enter: Telegram token · bridge password · group link
        → auto-joins the group  (/c <link>)
        → auto-detects group id + name  (/groups)
        → writes .env (chmod 600)
                              │
                       🔀 Pick path: run it in the background?
                              │
            ┌─────────────────┴─────────────────┐
            ▼                                   ▼
   4a. Background services 🤖           4b. Run manually 👤
       macOS:  setup-launchd.sh             • keep the :5225 server
       Linux:  setup-systemd.sh               from step 2 running
       (auto-start at login/boot,           • open a 2nd terminal:
        restart on crash)                      cd repo && . .venv/bin/activate
            │                                   && python bridge.py
   ⚠ first stop the manual :5225            │
     server from step 2 — the agent/        │
     unit binds the same port (clash)       │
            └─────────────────┬─────────────────┘
                              ▼
   5. Verify 👤
      lsof -nP -iTCP:5225 -sTCP:LISTEN   (server up?)
      + service state (launchctl print / systemctl status)
      + tail logs if anything's crash-looping
                              ▼
   6. Authorize + test 👤
      Telegram: /start <password>  →  forward a post  →  check SimpleX group

Legend:  👤 you do it    🤖 a script does it    🔀 branch point    ⚠ gotcha
```
### Prerequisites
0. Creating a Telegram bot
  - Go to [@BotFather](https://t.me/BotFather)
  - Send `/newbot` and assign a name to it
  - Send its USERNAME made up in your head, but it has to end with "bot". Remember the USERNAME
  - Remember the TOKEN under the `Use this token to access the HTTP API`
### Universal quick setup
Open your terminal. Remember that it's better to install the application as a sudoer, not as a root, due to rights non-excessiveness.
1. Paste in that line (Ctrl + Shift + V) and run:
```
curl -sSL https://raw.githubusercontent.com/cyphershark/telegram-to-simplex/main/install.sh | bash
```
This script detects your OS, installs system dependencies, the SimpleX Chat CLI, clones the repo, sets up a Python virtual environment, and creates a config file template. After it finishes, you'll need to set up your SimpleX account and fill in credentials.

2. Complete the SimpleX Chat CLI: `python setup.py`

3. Configure the running agent: 
* `bash setup-systemd.sh` for Linux,
* `bash setup-launchd.sh` for MacOS.

4. Verify: `sudo systemctl status telegram-to-simplex`
## Manual installation
### 1. System dependencies

**Debian/Ubuntu:** `sudo apt update && sudo apt install git python3 python3-venv python3-pip ffmpeg`

**Arch:** `sudo pacman -S git python python-pip ffmpeg`

**Fedora:** `sudo dnf install git python3 python3-pip ffmpeg`

**macOS (Homebrew):** `brew install git python ffmpeg openssl@3`

### 2. SimpleX Chat CLI
```
curl -o- https://raw.githubusercontent.com/simplex-chat/simplex-chat/stable/install.sh | bash
```
1. Start the CLI in interactive mode: `simplex-chat -d ~/simplex-data/bot`
2. Enter name for your technical account on SimpleX
3. Create a contact address: `/ad`
4. Enable auto-accept: `/auto_accept on`
5. Grab a link to your group: open it, tap its name on top, click "🔗 Group link", copy it
6. Paste link into the CLI: `/c INVITE_LINK` - the bot will accept invitation and it will appear in the chat
7. Fetch group name: `/groups` will give you out "#YOUR_GROUP (3 members) - admin" - save the name after "#"
8. Fetch group ID: `/_get chats 1 pcc=on` will give you a JSON file - find `chatId` or `groupId` and save it
9. Quit: `/quit`

#### 3. Clone and set up
```
git clone https://github.com/cyphershark/telegram-to-simplex.git
cd telegram-to-simplex
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

#### 4. Configure credentials
0. Create a strong password and copy it: `openssl rand -hex 24`
1. Then edit the config file: `nano ~/telegram-to-simplex/.env` and put in credentials:
```
TELEGRAM_TOKEN=YOUR_TOKEN # an API token from BotFather
BRIDGE_PASSWORD=YOUR_PASSWORD
SIMPLEX_GROUP_ID=YOUR_GROUP_ID
SIMPLEX_GROUP_NAME=YOUR_GROUP_NAME
SIMPLEX_WS=ws://127.0.0.1:5225
TMP_DIR=/home/YOUR_USER/telegram-to-simplex/tmp # put in your user's name
```
2. Update permissions: `chmod 600 ~/telegram-to-simplex/.env`

#### 5. Setting up a process (Linux)
1. Create a service file for SimpleX: `sudo nano /etc/systemd/system/simplex-chat.service`
2. Paste in, replacing YOUR_USER with your username:
```
[Unit]
Description=SimpleX Chat CLI WebSocket server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=YOUR_USER
Group=YOUR_USER
WorkingDirectory=/home/YOUR_USER
ExecStart=/home/YOUR_USER/.local/bin/simplex-chat -d /home/YOUR_USER/simplex-data/bot -p 5225
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```
3. Create a service file for bridging: `sudo nano /etc/systemd/system/telegram-to-simplex.service`
4. Paste in, YOUR_USER is your username:
```
[Unit]
Description=telegram-to-simplex bridge
After=network-online.target simplex-chat.service
Wants=network-online.target
Requires=simplex-chat.service

[Service]
Type=simple
User=YOUR_USER
Group=YOUR_USER
WorkingDirectory=/home/YOUR_USER/telegram-to-simplex
EnvironmentFile=/home/YOUR_USER/telegram-to-simplex/.env
ExecStart=/home/YOUR_USER/telegram-to-simplex/.venv/bin/python /home/YOUR_USER/telegram-to-simplex/bridge.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```
5. Restart daemon:
```
sudo systemctl daemon-reload
sudo systemctl enable --now simplex-chat
sudo systemctl enable --now telegram-to-simplex
```
6. Verify, both should be in "Active: active (running)" mode:
```
sudo systemctl status simplex-chat
sudo systemctl status telegram-to-simplex
```
**Congratulations! The program is ready to run**

## Use
1. Open your bot by its @USERNAME
2. Click Start on the bottom
3. Send `/start PASSWORD` to the bot - with your password instead of PASSWORD. For instance, if it's "123456", then send `/start 123456`. You should see "✅ Authorized. Forward channel posts to me and I'll relay them to SimpleX"
4. Now, you can forward or directly send messages to the bot so that it will appear in the SimpleX Chat group
4.1. For instance, open any Telegram channel, long-press a post, and select 'Forward'. Send to your bot. The bot replies '✅ Relayed' on success. The post appears in your SimpleX group with the channel name and link prepended.

## Uninstall
In case you want to uninstall the relay, run `bash uninstall.sh` - it will delete the SimpleX CLI and associated packages and processes, except for Python.

## Potential improvements
- To add specification of more media types (e.g. audios, videos, GIFs, etc.). The advancement is hugely slowed down by SimpleX WebSocket API.
- To add ability to send to multiple groups and to SimpleX channels.
- Adding troubleshooting and debugging features to README. 

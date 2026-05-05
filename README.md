# telegram-to-simplex
telegram-to-simplex is a relay that lets you transfer news you've seen on [Telegram](https://github.com/TelegramOfficial) directly into [SimpleX Chat](https://github.com/simplex-chat/simplex-chat) groups

## Motivation
Telegram is a great source of news unmoderated as much as possible, but it lacks strong chatting privacy protecting features like E2EE-by-default, MTProto audit, and a disclosed server source code. SimpleX Chat, on the opposite, is a great privacy friendly messaging tool (and an app), yet it lacks good channel support (added 30 Aplil 2026, but still lacks huge audience for major platforms to migrate to SimpleX). 
telegram-to-simplex acknowledges that difference and aims to create a better cross interface user experience for users of both platforms to take the best of both: communication privacy of SimpleX Chat and free speech nature of Telegram. 

## Features
With telegram-to-simplex, you can:
- Send a Telegram text message to a SimpleX Chat group;
- Send a Telegram image to a SimpleX Chat group, the image will be visible and delivered not as a usual file;
- Send a Telegram file to a SimpleX Chat group;
- Forward a Telegram message to a SimpleX Chat group, with source name and link on top of the final message;
- Protect Telegram bot with a password, so that the aliens can't use your relay;

## Installation
### Prerequisits
1. Creating a Telegram bot
  - Go to [@BotFather](https://t.me/BotFather)
  - Send `/newbot` and assign a name to it
  - Send its USERNAME made up in your head, but it has to end with "bot". Remember the USERNAME
  - Remember the TOKEN under the `Use this token to access the HTTP API:`
### Universal
Open your terminal. Remember that it's better to install the application as a sudoer, not as a root, due to rights non excessiviness.
Paste in that line (Ctrl + Shift + V) and run:
```
curl -sSL https://raw.githubusercontent.com/cyphershark/telegram-to-simplex/main/install.sh | bash
```
### Linux
### MacOS
### Windows
*Currently no support*

## Use
1. Open your bot by its @USERNAME
2. Click Start on the bottom
3. Send `/start PASSWORD` to the bot - with your password instead of PASSWORD. For instance, if it's "123456", then send `\start 123456`
4. Now, you can forward or directly send messages to the bot so that it will appear in the SimpleX Chat group

## Potential improvements
- To add speficication of more media types (e.g. audios, videos, GIFs, etc.). The advancement is hugely slowed down by SimpleX WebSocket API.
- To add ability to send to multiple groups and to SimpleX channels.

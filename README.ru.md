# telegram-to-simplex
telegram-to-simplex - это реле (мост), позволяющий перебрасывать новости из Telegram в чаты SimpleX Chat.

Языки:
- [🇺🇸 Английский](README.md)
- ⬜️🟦⬜️ Русский

## Мотивировка
Телеграм - это место относительно слабо модерируемых новостей, но платформе не хватает приватности для общения (и, более того, создатель платформы отказывается внедрять E2EE шифрование, исправлять проблемы с метаданными протокола MTProto, а также раскрывать исходный код серверов). SimpleX Chat, с другой стороны, это отличный способ защищённой переписки, которому не хватает развитой сети публичных каналов (они были добавлены в обновлении 30 апреля 2026 г., но ввиду непопулярности платформы, до сих пор остаются «в тени»).
Проект telegram-to-simplex признаёт эту разницу и стремится создать кросс-платформенный интерфейс для улучшения пользовательского опыта через собирание лучших практик от обеих платформ: приватности общения SimpleX Chat'а и свободы слова в Telegram.

## Возможности программы
С telegram-to-simplex, вы можете:
1. Отправлять в SimpleX чаты:
   - Текстовые сообщения
   - Изображения в отрендеренном формате, пригодном для просмотра
   - Иные файлы
2. Пересылать всё вышеперечисленное из других каналов, при этом сверху в сообщении в SimpleX вы увидите автора и ссылку на оригинальный пост
3. Защитить Телеграм-бот паролем, чтобы незнакомцы не могли пересылать сообщения в ваш чат в SimpleX.

## Установка
   - **На данный момент установка возможна только на дистрибутивы Linux и MacOS**
### Подготовка
0. Создание ТГ-бота
  - Откройте BotFather [@BotFather](https://t.me/BotFather)
  - Отправьте `/newbot` и дайте имя боту
  - Запомните адрес бота (USERNAME) при создании
  - Запомните токен (TOKEN), который будет после `Use this token to access the HTTP API`
### Универсальная простая установка
Откройте терминал. Имейте в виду, что устанавливать лучше как sudo-пользователь, а не администратор (root).
1. Вставьте (Ctrl/Cmd + Shift + V) и запустите:
```
curl -sSL https://raw.githubusercontent.com/cyphershark/telegram-to-simplex/main/install.sh | bash
```
Этот скрипт определит вашу ОС, установит зависимые пакеты, SimpleX-Chat CLI (клиент командной строки), проклонирует репозиторий, установит виртуальное пространство Python, и создаст пример конфиг-файла. По завершении вам надо будет либо вручную, либо через пункт 2 создать аккаунт в SimpleX-Chat, добавиться в группу, и запомнить ID.

2. Если вам лень возиться с SimpleX Chat CLI, этот скрипт сделает за вас: `python setup.py`
   - Введите нужные credentials: они будут отображаться у бота, когда он будет пересылать сообщения.

3. Запустите работу агента для непрерывной работы реле: 
* `bash setup-systemd.sh` для Linux,
* `bash setup-launchd.sh` для MacOS.

4. Проверьте работу: `sudo systemctl status telegram-to-simplex`

### Самостоятельная установка
#### 1. Установка системных пакетов

**Debian/Ubuntu:** `sudo apt update && sudo apt install git python3 python3-venv python3-pip ffmpeg`

**Arch:** `sudo pacman -S git python python-pip ffmpeg`

**Fedora:** `sudo dnf install git python3 python3-pip ffmpeg`

**macOS (Homebrew):** `brew install git python ffmpeg openssl@3`

#### 2. SimpleX-Chat CLI
```
curl -o- https://raw.githubusercontent.com/simplex-chat/simplex-chat/stable/install.sh | bash
```
1. Запустите CLI в интерактивном режиме: `simplex-chat -d ~/simplex-data/bot`
2. Придумайте имя для бота в SimpleX - оно будет отображаться только в SimpleX
3. Задайте адрес аккаунта: `/ad`
4. Включите автоматический приём сообщений: `/auto_accept on`
5. Возьмите ссылку на ваш чат: откройте, нажмите сверху на название чата, "🔗 Group link", скопируйте ссылку
6. Вставьте в CLI: `/c INVITE_LINK` - бот пример приглашение и в чате вы должны увидеть соответствующее сообщение
7. Узнайте название чата: `/groups` выдаст "#YOUR_GROUP (3 members) - admin" - сохраните название после "#"
8. Узнайте ID чата: `/_get chats 1 pcc=on` выдаст JSON файл - найдите `chatId` или `groupId` и сохраните
9. Теперь можете покинуть CLI: `/quit`

#### 3. Проклонируйте и создайте venv
```
git clone https://github.com/cyphershark/telegram-to-simplex.git
cd telegram-to-simplex
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

#### 4. Задайте credentials
0. Создайте сильный пароль и сохраните его надёжно: `openssl rand -hex 24` (как вариант)
1. Отредактируйте файл конфигурации venv: `nano ~/telegram-to-simplex/.env` и вставьте credentials:
```
TELEGRAM_TOKEN=YOUR_TOKEN # API-токен от BotFather
BRIDGE_PASSWORD=YOUR_PASSWORD
SIMPLEX_GROUP_ID=YOUR_GROUP_ID
SIMPLEX_GROUP_NAME=YOUR_GROUP_NAME
SIMPLEX_WS=ws://127.0.0.1:5225
TMP_DIR=/home/YOUR_USER/telegram-to-simplex/tmp # ваш username
```
2. Обновите права: `chmod 600 ~/telegram-to-simplex/.env`

#### 5. Установка процесса (Linux)
1. Создайте файл процесса SimpleX: `sudo nano /etc/systemd/system/simplex-chat.service`
2. Вставьте, заменяя YOUR_USER своим юзернеймом:
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
3. Создайте сервисный файл для соединения: `sudo nano /etc/systemd/system/telegram-to-simplex.service`
4. Вставьте текст, где YOUR_USER - ваш юзернейм:
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
5. Перезапустите daemon:
```
sudo systemctl daemon-reload
sudo systemctl enable --now simplex-chat
sudo systemctl enable --now telegram-to-simplex
```
6. Проверьте работу, обе команды должны выдавать "Active: active (running)":
```
sudo systemctl status simplex-chat
sudo systemctl status telegram-to-simplex
```
**Поздравляем! Реле готово к работе**

## Использование
1. Запустите вашего бота в ТГ по адресу: @USERNAME
2. Отправьте `/start PASSWORD` боту - где на месте <PASSWORD> ваш пароль. Например, при пароле "123456" отправьте `/start 123456`. Вы должны увидеть "Authorized. Forward channel posts to me and I'll relay them to SimpleX"
3. Теперь вы можете отправлять или пересылать сообщения прямо в бот и они будут пересылаться в группу SimpleX-Chat. 

## Uninstall
Если вы хотите удалить реле, запустите в терминале `bash uninstall.sh` - скрипт удалит SimpleX CLI, а также ассоциированные процессы и пакеты, за исключением Python.

## Потенциальные улучшения
- Добавить поддержку большего числа медиафайлов (e.g. audios, videos, GIFs, etc.). Продвижение очень затруднено из-за WebSocket API SimpleX-Chat.
- Возможность отправлять сообщения в несколько групп/чатов и каналов в SimpleX.
- Добавить помощь по основному траблшутингу и багам в README. 
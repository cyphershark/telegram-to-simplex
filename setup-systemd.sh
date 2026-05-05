#!/usr/bin/env bash
RUN_USER=$(whoami)
HOME_DIR=$(eval echo ~$RUN_USER)
INSTALL_DIR="$HOME_DIR/telegram-to-simplex"
DATA_DIR="$HOME_DIR/simplex-data"

sudo tee /etc/systemd/system/simplex-chat.service > /dev/null <<EOF
[Unit]
Description=SimpleX Chat CLI WebSocket server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
WorkingDirectory=$HOME_DIR
ExecStart=$HOME_DIR/.local/bin/simplex-chat -d $DATA_DIR/bot -p 5225
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/telegram-to-simplex.service > /dev/null <<EOF
[Unit]
Description=telegram-to-simplex bridge
After=network-online.target simplex-chat.service
Wants=network-online.target
Requires=simplex-chat.service

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/.venv/bin/python $INSTALL_DIR/bridge.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now simplex-chat
sudo systemctl enable --now telegram-to-simplex
echo "Done. Check: sudo systemctl status telegram-to-simplex"
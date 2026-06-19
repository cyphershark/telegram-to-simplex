#!/usr/bin/env bash
# macOS launchd setup — background equivalent of setup-systemd.sh
# Creates two LaunchAgents that run at login and restart on crash:
#   chat.simplex.cli     -> simplex-chat WebSocket server on :5225
#   chat.simplex.bridge  -> telegram-to-simplex bridge (waits for the server)
set -euo pipefail

RUN_USER="$(whoami)"
HOME_DIR="$(eval echo "~$RUN_USER")"
INSTALL_DIR="$HOME_DIR/telegram-to-simplex"
DATA_DIR="$HOME_DIR/simplex-data"
SIMPLEX_BIN="$HOME_DIR/.local/bin/simplex-chat"
AGENT_DIR="$HOME_DIR/Library/LaunchAgents"
LOG_DIR="$HOME_DIR/Library/Logs/telegram-to-simplex"

CLI_LABEL="chat.simplex.cli"
BRIDGE_LABEL="chat.simplex.bridge"

mkdir -p "$AGENT_DIR" "$LOG_DIR"

# ---- 1. SimpleX CLI WebSocket server -------------------------------------
# This is the `simplex-chat -d ~/simplex-data/bot -p 5225` command, as an agent.
cat > "$AGENT_DIR/$CLI_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>$CLI_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SIMPLEX_BIN</string>
        <string>-d</string>
        <string>$DATA_DIR/bot</string>
        <string>-p</string>
        <string>5225</string>
    </array>
    <key>WorkingDirectory</key> <string>$HOME_DIR</string>
    <key>RunAtLoad</key>        <true/>
    <key>KeepAlive</key>        <true/>
    <key>StandardOutPath</key>  <string>$LOG_DIR/cli.out.log</string>
    <key>StandardErrorPath</key><string>$LOG_DIR/cli.err.log</string>
</dict>
</plist>
EOF

# ---- 2. telegram-to-simplex bridge ---------------------------------------
# launchd has no EnvironmentFile, so we source .env in a shell wrapper.
# KeepAlive makes it relaunch until the server's port 5225 is listening.
cat > "$AGENT_DIR/$BRIDGE_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>$BRIDGE_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>set -a; . "$INSTALL_DIR/.env"; set +a; exec "$INSTALL_DIR/.venv/bin/python" "$INSTALL_DIR/bridge.py"</string>
    </array>
    <key>WorkingDirectory</key> <string>$INSTALL_DIR</string>
    <key>RunAtLoad</key>        <true/>
    <key>KeepAlive</key>        <true/>
    <key>ThrottleInterval</key> <integer>10</integer>
    <key>StandardOutPath</key>  <string>$LOG_DIR/bridge.out.log</string>
    <key>StandardErrorPath</key><string>$LOG_DIR/bridge.err.log</string>
</dict>
</plist>
EOF

# ---- load them -----------------------------------------------------------
GUI="gui/$(id -u)"
# bootout first in case they're already loaded (ignore errors), then bootstrap.
launchctl bootout  "$GUI/$CLI_LABEL"    2>/dev/null || true
launchctl bootout  "$GUI/$BRIDGE_LABEL" 2>/dev/null || true
launchctl bootstrap "$GUI" "$AGENT_DIR/$CLI_LABEL.plist"
launchctl bootstrap "$GUI" "$AGENT_DIR/$BRIDGE_LABEL.plist"
launchctl enable    "$GUI/$CLI_LABEL"
launchctl enable    "$GUI/$BRIDGE_LABEL"

echo "Done."
echo "  Status : launchctl print $GUI/$BRIDGE_LABEL | grep state"
echo "  Logs   : tail -f $LOG_DIR/bridge.err.log"
echo "  Stop   : launchctl bootout $GUI/$BRIDGE_LABEL ; launchctl bootout $GUI/$CLI_LABEL"
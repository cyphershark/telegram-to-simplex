#!/usr/bin/env bash
# telegram-to-simplex installer
# Detects OS, installs dependencies, clones repo, sets up venv.

set -euo pipefail

# ---------- config ----------
REPO_URL="${REPO_URL:-https://github.com/YOUR_USERNAME/telegram-to-simplex.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/telegram-to-simplex}"
SIMPLEX_DATA_DIR="${SIMPLEX_DATA_DIR:-$HOME/simplex-data}"

# ---------- colors ----------
if [ -t 1 ]; then
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    RED=$'\033[31m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
    BOLD=""; GREEN=""; YELLOW=""; RED=""; BLUE=""; RESET=""
fi

info()  { echo "${BLUE}[INFO]${RESET}  $*"; }
ok()    { echo "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo "${YELLOW}[WARN]${RESET}  $*"; }
fail()  { echo "${RED}[FAIL]${RESET}  $*" >&2; exit 1; }
step()  { echo; echo "${BOLD}== $* ==${RESET}"; }

# ---------- OS detection ----------
detect_os() {
    case "$(uname -s)" in
        Darwin)
            OS_FAMILY="macos"
            return
            ;;
        Linux)
            ;;
        *)
            fail "Unsupported OS: $(uname -s)"
            ;;
    esac

    if [ ! -f /etc/os-release ]; then
        fail "Cannot detect Linux distribution (no /etc/os-release)"
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    local id="${ID:-}"
    local id_like="${ID_LIKE:-}"
    local check="$id $id_like"

    if [[ "$check" =~ (debian|ubuntu) ]]; then
        OS_FAMILY="debian"
    elif [[ "$check" =~ (arch|manjaro|endeavouros) ]]; then
        OS_FAMILY="arch"
    elif [[ "$check" =~ (fedora|rhel|centos) ]]; then
        OS_FAMILY="fedora"
    else
        fail "Unsupported Linux distribution: $id (ID_LIKE: $id_like)"
    fi
}

# ---------- dependency installation ----------
install_pkg() {
    case "$OS_FAMILY" in
        debian)
            sudo apt-get install -y "$@"
            ;;
        arch)
            sudo pacman -S --needed --noconfirm "$@"
            ;;
        fedora)
            sudo dnf install -y "$@"
            ;;
        macos)
            brew install "$@"
            ;;
    esac
}

update_repos() {
    case "$OS_FAMILY" in
        debian)  sudo apt-get update ;;
        arch)    sudo pacman -Sy ;;
        fedora)  sudo dnf check-update || true ;;
        macos)
            command -v brew >/dev/null 2>&1 || fail \
                "Homebrew not found. Install from https://brew.sh and re-run."
            brew update
            ;;
    esac
}

install_dependencies() {
    step "Installing system dependencies"

    update_repos

    case "$OS_FAMILY" in
        debian)
            install_pkg git curl python3 python3-venv python3-pip ffmpeg ca-certificates
            ;;
        arch)
            install_pkg git curl python python-pip ffmpeg ca-certificates
            ;;
        fedora)
            install_pkg git curl python3 python3-pip ffmpeg ca-certificates
            ;;
        macos)
            install_pkg git python ffmpeg
            ;;
    esac

    ok "System dependencies installed"
}

# ---------- simplex-chat install ----------
install_simplex_chat() {
    step "Checking simplex-chat CLI"

    if command -v simplex-chat >/dev/null 2>&1; then
        ok "simplex-chat already installed: $(simplex-chat --version 2>&1 | head -1)"
        return
    fi

    info "Installing simplex-chat CLI from official installer"
    curl -fsSL https://raw.githubusercontent.com/simplex-chat/simplex-chat/stable/install.sh | bash

    # The installer puts the binary in ~/.local/bin
    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v simplex-chat >/dev/null 2>&1; then
        fail "simplex-chat not found on PATH after install. Add ~/.local/bin to your PATH."
    fi

    ok "simplex-chat installed"
}

# ---------- repo + venv ----------
clone_repo() {
    step "Cloning telegram-to-simplex repository"

    if [ -d "$INSTALL_DIR/.git" ]; then
        info "Repository already exists at $INSTALL_DIR — pulling latest"
        git -C "$INSTALL_DIR" pull --ff-only
    else
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
    ok "Repository ready at $INSTALL_DIR"
}

setup_venv() {
    step "Setting up Python virtual environment"

    cd "$INSTALL_DIR"
    if [ ! -d ".venv" ]; then
        python3 -m venv .venv
    fi

    # shellcheck disable=SC1091
    . .venv/bin/activate

    pip install --quiet --upgrade pip
    if [ -f requirements.txt ]; then
        pip install --quiet -r requirements.txt
        ok "Python dependencies installed"
    else
        warn "No requirements.txt found in $INSTALL_DIR"
    fi

    deactivate
}

# ---------- config scaffolding ----------
scaffold_env() {
    step "Configuration scaffolding"

    local env_file="$INSTALL_DIR/.env"
    if [ -f "$env_file" ]; then
        ok ".env already exists — not overwriting"
        return
    fi

    if [ -f "$INSTALL_DIR/.env.example" ]; then
        cp "$INSTALL_DIR/.env.example" "$env_file"
    else
        cat > "$env_file" <<'EOF'
# Telegram bot token from @BotFather
TELEGRAM_TOKEN=

# Password users send with /start to authorize
BRIDGE_PASSWORD=

# SimpleX WebSocket endpoint (default for local CLI)
SIMPLEX_WS=ws://127.0.0.1:5225

# Numeric SimpleX group ID (find via /groups in CLI)
SIMPLEX_GROUP_ID=1

# SimpleX group's local display name (for /image and /f commands)
SIMPLEX_GROUP_NAME=

# Where to download Telegram media before relaying
TMP_DIR=
EOF
    fi

    chmod 600 "$env_file"
    # Fill TMP_DIR with a sensible default
    if grep -q '^TMP_DIR=$' "$env_file"; then
        sed -i.bak "s|^TMP_DIR=$|TMP_DIR=$INSTALL_DIR/tmp|" "$env_file" && rm -f "$env_file.bak"
    fi
    mkdir -p "$INSTALL_DIR/tmp"

    ok "Created $env_file (chmod 600)"
    warn "Fill in TELEGRAM_TOKEN, BRIDGE_PASSWORD, and SIMPLEX_GROUP_NAME before running"
}

# ---------- summary ----------
print_summary() {
    step "Setup complete"
    cat <<EOF

Next steps:

  1. Initialize SimpleX profile (one time, interactive):
       simplex-chat -d $SIMPLEX_DATA_DIR/bot
     – set a display name
     – run /ad to create a contact address
     – run /auto_accept on
     – join your destination group; note its ID via /groups
     – /quit

  2. Edit the bridge config:
       nano $INSTALL_DIR/.env

    3. Run as background services:
        bash $INSTALL_DIR/setup-systemd.sh

    4. Verify:
        sudo systemctl status telegram-to-simplex

    5. Authorize yourself in Telegram:
        /start <BRIDGE_PASSWORD>

EOF
}

# ---------- main ----------
main() {
    detect_os
    info "Detected OS family: $OS_FAMILY"
    install_dependencies
    install_simplex_chat
    clone_repo
    setup_venv
    scaffold_env
    print_summary
}

main "$@"
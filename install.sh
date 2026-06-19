#!/usr/bin/env bash
# telegram-to-simplex installer
# Detects OS, installs dependencies, clones repo, sets up venv.

set -euo pipefail

# ---------- config ----------
REPO_URL="${REPO_URL:-https://github.com/cyphershark/telegram-to-simplex.git}"
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
            # openssl@3 is required: the simplex-chat macOS binary dynamically
            # links against Homebrew's libcrypto.3.dylib.
            install_pkg git python ffmpeg openssl@3
            ;;
    esac

    ok "System dependencies installed"
}

# ---------- simplex-chat install (macOS helpers) ----------

# The macOS simplex-chat binary hardcodes an ABSOLUTE OpenSSL path baked in at
# build time, using the name "openssl@3.0" — which Homebrew never creates (its
# formula is "openssl@3"). The prefix also differs by arch (/opt/homebrew on
# Apple Silicon, /usr/local on Intel). Rather than guess, read the exact paths
# the binary asks for via `otool -L` and symlink each to the real brew dylib.
#
# We use a symlink (not install_name_tool) on purpose: editing the Mach-O would
# invalidate the code signature and trip "main executable failed strict
# validation". The symlink leaves the binary byte-for-byte untouched.
bridge_openssl_macos() {
    local bin="$HOME/.local/bin/simplex-chat"
    local real_lib_dir wants want base target
    real_lib_dir="$(brew --prefix openssl@3)/lib"

    wants="$(otool -L "$bin" | grep -oE '/[^ ]*openssl@[^ ]*\.dylib' | sort -u || true)"
    if [ -z "$wants" ]; then
        warn "Binary references no OpenSSL path — nothing to bridge."
        return
    fi

    while read -r want; do
        [ -n "$want" ] || continue
        base="$(basename "$want")"
        target="$real_lib_dir/$base"

        if [ ! -f "$target" ]; then
            fail "Expected OpenSSL lib not found: $target
       Try: brew install openssl@3"
        fi
        if [ -e "$want" ]; then
            ok "OpenSSL path already present: $want"
        else
            sudo mkdir -p "$(dirname "$want")"
            sudo ln -sf "$target" "$want"
            ok "Bridged $want -> $target"
        fi
    done <<< "$wants"
}

install_simplex_chat_macos() {
    local bin="$HOME/.local/bin/simplex-chat"
    local asset size

    case "$(uname -m)" in
        arm64)  asset="simplex-chat-macos-aarch64" ;;
        x86_64) asset="simplex-chat-macos-x86-64"  ;;
        *)      fail "Unknown macOS arch: $(uname -m)" ;;
    esac

    mkdir -p "$HOME/.local/bin"
    info "Downloading $asset"
    curl -fL "https://github.com/simplex-chat/simplex-chat/releases/latest/download/$asset" \
        -o "$bin"

    # Guard against a truncated download / HTML error page (real binary is ~30MB).
    size="$(stat -f%z "$bin" 2>/dev/null || stat -c%s "$bin")"
    if [ "${size:-0}" -lt 1000000 ]; then
        fail "Downloaded simplex-chat is only ${size} bytes — download failed."
    fi

    chmod +x "$bin"

    # Apple Silicon refuses to exec a binary without a valid signature, and the
    # release binary is unsigned. Clear quarantine, then ad-hoc sign.
    # IMPORTANT: this must be the LAST thing that touches the file. The OpenSSL
    # bridge below only creates symlinks, so the signature stays valid.
    if command -v codesign >/dev/null 2>&1; then
        xattr -c "$bin" 2>/dev/null || true
        codesign --force --sign - "$bin"
    else
        warn "codesign not found (install Xcode Command Line Tools: xcode-select --install)"
    fi

    bridge_openssl_macos
}

# ---------- simplex-chat install ----------
install_simplex_chat() {
    step "Checking simplex-chat CLI"

    # A broken binary still satisfies `command -v`, so verify it actually RUNS.
    # (`if` conditions are exempt from `set -e`, so a failing --version is safe.)
    if command -v simplex-chat >/dev/null 2>&1 && simplex-chat --version >/dev/null 2>&1; then
        ok "simplex-chat already installed: $(simplex-chat --version 2>&1 | head -1)"
        return
    fi
    if command -v simplex-chat >/dev/null 2>&1; then
        warn "Existing simplex-chat found but won't run — reinstalling"
    fi

    info "Installing simplex-chat CLI"

    if [ "$OS_FAMILY" = "macos" ]; then
        install_simplex_chat_macos
    else
        # Linux: the official installer ships a binary that works with the
        # distro's OpenSSL (and is signed/validated differently than macOS).
        curl -fsSL https://raw.githubusercontent.com/simplex-chat/simplex-chat/stable/install.sh | bash
    fi

    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v simplex-chat >/dev/null 2>&1; then
        fail "simplex-chat not found on PATH after install. Add ~/.local/bin to your PATH."
    fi
    if ! simplex-chat --version >/dev/null 2>&1; then
        fail "simplex-chat installed but fails to run — see the error above."
    fi

    ok "simplex-chat installed: $(simplex-chat --version 2>&1 | head -1)"
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
     - set a display name
     - run /ad to create a contact address
     - run /auto_accept on
     - join your destination group via /c <GROUP_LINK>; note its ID via /groups
     - /quit

  2. Edit the bridge config:
       nano $INSTALL_DIR/.env

EOF

    if [ "$OS_FAMILY" = "macos" ]; then
        cat <<EOF
  3. Run the bridge (macOS has no systemd; run it directly or via launchd):
        cd $INSTALL_DIR && . .venv/bin/activate && python -m bot   # adjust to the repo's entrypoint

  4. Authorize yourself in Telegram:
        /start <BRIDGE_PASSWORD>

EOF
    else
        cat <<EOF
  3. Run as background services:
        bash $INSTALL_DIR/setup-systemd.sh

  4. Verify:
        sudo systemctl status telegram-to-simplex

  5. Authorize yourself in Telegram:
        /start <BRIDGE_PASSWORD>

EOF
    fi
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
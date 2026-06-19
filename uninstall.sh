#!/usr/bin/env bash
# telegram-to-simplex UNINSTALLER  (antipode of install.sh / setup-systemd.sh)
#
# Removes:
#   - the systemd units (Linux) OR launchd agents (macOS) for the bridge & CLI
#   - the simplex-chat binary in ~/.local/bin
#   - the macOS OpenSSL "@3.0" bridge symlinks the installer created
#   - the repo / venv / .env  ($HOME/telegram-to-simplex)
#   - the SimpleX data dir incl. the CLI account/keys  ($HOME/simplex-data)  [IRREVERSIBLE]
#   - the packages the installer added: git, ffmpeg, (macOS: openssl@3)  -- NOT python
#
# Usage:  bash uninstall.sh           # interactive (asks for confirmation)
#         bash uninstall.sh -y        # non-interactive (assume yes) -- use with care

set -euo pipefail

ASSUME_YES=0
[ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ] && ASSUME_YES=1

# ---------- config (mirrors the installer) ----------
RUN_USER="$(whoami)"
HOME_DIR="$(eval echo "~$RUN_USER")"
INSTALL_DIR="${INSTALL_DIR:-$HOME_DIR/telegram-to-simplex}"
DATA_DIR="${SIMPLEX_DATA_DIR:-$HOME_DIR/simplex-data}"
SIMPLEX_BIN="$HOME_DIR/.local/bin/simplex-chat"
SERVICES=(telegram-to-simplex simplex-chat)   # bridge first, then the CLI it depends on

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
        Darwin) OS_FAMILY="macos"; return ;;
        Linux)  ;;
        *)      fail "Unsupported OS: $(uname -s)" ;;
    esac
    [ -f /etc/os-release ] || fail "Cannot detect Linux distribution"
    # shellcheck disable=SC1091
    . /etc/os-release
    local check="${ID:-} ${ID_LIKE:-}"
    if   [[ "$check" =~ (debian|ubuntu) ]];          then OS_FAMILY="debian"
    elif [[ "$check" =~ (arch|manjaro|endeavouros) ]]; then OS_FAMILY="arch"
    elif [[ "$check" =~ (fedora|rhel|centos) ]];     then OS_FAMILY="fedora"
    else fail "Unsupported Linux distribution"; fi
}

# ---------- manifest + confirmation ----------
confirm() {
    step "About to uninstall telegram-to-simplex"

    cat <<EOF

This will PERMANENTLY remove the following from this machine ($RUN_USER):

  Services/agents : ${SERVICES[*]}
  CLI binary      : $SIMPLEX_BIN
  App + venv      : $INSTALL_DIR
  SimpleX data    : $DATA_DIR
  Packages        : git, ffmpeg$( [ "$OS_FAMILY" = macos ] && echo ", openssl@3" )  (python is KEPT)

${RED}${BOLD}THIS DESTROYS YOUR SIMPLEX CLI ACCOUNT.${RESET}
The profile, contact address, group memberships and private keys live in
  $DATA_DIR
Once deleted they CANNOT be recovered, and your contacts will no longer be able
to reach this identity.

EOF

    if [ "$ASSUME_YES" -eq 1 ]; then
        warn "-y given: proceeding without prompt."
        return
    fi
    if [ ! -t 0 ]; then
        fail "No terminal to confirm on. Re-run interactively, or pass -y if you are certain."
    fi

    local reply
    read -r -p "Type ${BOLD}DELETE${RESET} (in capitals) to proceed, anything else to abort: " reply
    [ "$reply" = "DELETE" ] || fail "Aborted — nothing was changed."
}

# ---------- service / agent removal ----------
remove_services_linux() {
    step "Removing systemd units"
    local unit removed=0
    for unit in "${SERVICES[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${unit}.service"; then
            sudo systemctl disable --now "${unit}.service" 2>/dev/null || true
            sudo rm -f "/etc/systemd/system/${unit}.service"
            ok "Removed ${unit}.service"
            removed=1
        else
            info "No system unit ${unit}.service"
        fi
        # also sweep a possible --user unit
        if systemctl --user list-unit-files 2>/dev/null | grep -q "^${unit}.service"; then
            systemctl --user disable --now "${unit}.service" 2>/dev/null || true
            rm -f "$HOME_DIR/.config/systemd/user/${unit}.service"
            ok "Removed user unit ${unit}.service"
            removed=1
        fi
    done
    if [ "$removed" -eq 1 ]; then
        sudo systemctl daemon-reload || true
        sudo systemctl reset-failed 2>/dev/null || true
    fi
}

remove_services_macos() {
    step "Removing launchd agents"
    local agent_dir="$HOME_DIR/Library/LaunchAgents"
    local found=0 plist label
    if [ -d "$agent_dir" ]; then
        # match anything referencing simplex or the bridge
        for plist in "$agent_dir"/*simplex*.plist "$agent_dir"/*telegram-to-simplex*.plist; do
            [ -e "$plist" ] || continue
            label="$(basename "$plist" .plist)"
            launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || \
                launchctl unload "$plist" 2>/dev/null || true
            rm -f "$plist"
            ok "Removed launchd agent $label"
            found=1
        done
    fi
    [ "$found" -eq 1 ] || info "No matching launchd agents found."
}

# ---------- binary + macOS OpenSSL bridge ----------
remove_binary() {
    step "Removing simplex-chat binary"
    if [ -e "$SIMPLEX_BIN" ]; then
        rm -f "$SIMPLEX_BIN"
        ok "Removed $SIMPLEX_BIN"
    else
        info "No binary at $SIMPLEX_BIN"
    fi
}

remove_openssl_bridge_macos() {
    step "Removing OpenSSL bridge symlinks"
    # The installer created fake dirs named openssl@3.0 (note the .0) full of
    # symlinks. We remove ONLY the @3.0 bridge -- never brew's real openssl@3.
    local p
    for p in /opt/homebrew/opt/openssl@3.0 /usr/local/opt/openssl@3.0; do
        if [ -e "$p" ] || [ -L "$p" ]; then
            case "$p" in
                */openssl@3.0)  # extra guard: must end in @3.0
                    sudo rm -rf "$p"
                    ok "Removed bridge $p" ;;
                *) warn "Refusing to remove unexpected path $p" ;;
            esac
        fi
    done
}

# ---------- app files + account ----------
remove_app_files() {
    step "Removing application files and SimpleX account data"
    local d
    for d in "$INSTALL_DIR" "$DATA_DIR"; do
        if [ -d "$d" ]; then
            rm -rf "$d"
            ok "Removed $d"
        else
            info "Not present: $d"
        fi
    done
}

# ---------- packages (except python) ----------
remove_packages() {
    step "Removing packages (keeping python)"
    # Each removal is non-fatal: a package manager that refuses (because another
    # program still depends on it, e.g. openssl) is the SAFE outcome -- we report
    # it rather than forcing removal and breaking the system.
    case "$OS_FAMILY" in
        macos)
            local f
            for f in git ffmpeg openssl@3; do
                if brew list --versions "$f" >/dev/null 2>&1; then
                    if brew uninstall "$f" 2>/dev/null; then
                        ok "Uninstalled $f"
                    else
                        warn "Kept $f (still required by other Homebrew formulae)"
                    fi
                else
                    info "Not a managed Homebrew formula: $f"
                fi
            done
            ;;
        debian)
            sudo apt-get remove -y git ffmpeg 2>/dev/null || warn "Some packages could not be removed (in use)."
            sudo apt-get autoremove -y 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Rns --noconfirm git ffmpeg 2>/dev/null || warn "Some packages could not be removed (in use)."
            ;;
        fedora)
            sudo dnf remove -y git ffmpeg 2>/dev/null || warn "Some packages could not be removed (in use)."
            ;;
    esac
    info "python was intentionally left installed."
}

# ---------- summary ----------
print_summary() {
    step "Uninstall complete"
    cat <<EOF

Removed the bridge, the SimpleX CLI binary, its data/account, and the
installer's packages (where not still in use). python was kept.

Notes:
  - If you also want python gone, remove it manually with your package manager.
  - ~/.local/bin itself was left in place (it may hold unrelated tools); only
    the simplex-chat binary inside it was deleted.
  - Anything you added to your shell PATH by hand is untouched.

EOF
}

# ---------- main ----------
main() {
    detect_os
    info "Detected OS family: $OS_FAMILY"
    confirm

    if [ "$OS_FAMILY" = "macos" ]; then
        remove_services_macos
    else
        remove_services_linux
    fi

    remove_binary
    [ "$OS_FAMILY" = "macos" ] && remove_openssl_bridge_macos
    remove_app_files
    remove_packages
    print_summary
}

main "$@"
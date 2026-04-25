#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#   my-dots installer — Hyprland + Quickshell + Waybar rice
#   Usage: bash <(curl -fsSL https://raw.githubusercontent.com/<TOI>/my-dots/main/install.sh)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────
readonly REPO_URL="https://github.com/samyns/my-dots.git"
readonly REPO_BRANCH="${MY_DOTS_BRANCH:-main}"
readonly CLONE_DIR="${TMPDIR:-/tmp}/my-dots-install-$$"
readonly BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Folders managed by this installer (touched in $CONFIG_HOME)
readonly MANAGED_DIRS=(hypr quickshell waybar kitty dunst)

# ─── Colors & logging ───────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m';   C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'; C_BLUE=$'\033[0;34m'
    C_BOLD=$'\033[1m';     C_RESET=$'\033[0m'
else
    C_RED='';C_GREEN='';C_YELLOW='';C_BLUE='';C_BOLD='';C_RESET=''
fi
log()   { printf "%s[*]%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf "%s[✓]%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf "%s[!]%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf "%s[✗]%s %s\n" "$C_RED"    "$C_RESET" "$*" >&2; }
fatal() { err "$*"; exit 1; }

ask_yn() {
    local prompt="$1" default="${2:-n}" reply hint="[y/N]"
    [[ "$default" == "y" ]] && hint="[Y/n]"
    while true; do
        read -rp "$(printf '%s[?]%s %s %s ' "$C_YELLOW" "$C_RESET" "$prompt" "$hint")" reply
        reply="${reply:-$default}"
        case "${reply,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) warn "Please answer y or n." ;;
        esac
    done
}

cleanup() { [[ -d "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"; }
trap cleanup EXIT

# ─── Pre-flight ─────────────────────────────────────────────────────
preflight() {
    log "Running pre-flight checks…"
    [[ $EUID -ne 0 ]] || fatal "Do not run this script as root. Run as your normal user; sudo will be invoked when needed."
    command -v pacman >/dev/null || fatal "pacman not found — this script is for Arch Linux only."
    command -v sudo   >/dev/null || fatal "sudo is required."
    command -v git    >/dev/null || sudo pacman -S --needed --noconfirm git
    log "Asking for sudo password upfront…"
    sudo -v || fatal "sudo authentication failed."
    # Keep sudo alive in background
    while true; do sudo -n true; sleep 60; kill -0 $$ 2>/dev/null || exit; done 2>/dev/null &
    log "Checking internet connectivity…"
    ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 || fatal "No internet connection."
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        warn "You are running this from inside Hyprland. You will need to log out / restart your session at the end."
    fi
    ok "All checks passed."
}

# ─── User prompts ───────────────────────────────────────────────────
collect_choices() {
    echo
    log "I'll ask a few questions before starting."
    echo
    BACKUP_OLD=true;          ask_yn "Backup existing configs to $BACKUP_DIR?" y || BACKUP_OLD=false
    INSTALL_AUR=true;         ask_yn "Install AUR packages (quickshell-git, awww)? Highly recommended." y || INSTALL_AUR=false
    INSTALL_WALLPAPERS=true;  ask_yn "Install default wallpapers to ~/Pictures/Wallpapers?" y || INSTALL_WALLPAPERS=false
    ENABLE_SERVICES=true;     ask_yn "Enable system services (NetworkManager, pipewire)?" y || ENABLE_SERVICES=false
    echo
}

# ─── Base setup ─────────────────────────────────────────────────────
install_base() {
    log "Installing base-devel + git…"
    sudo pacman -S --needed --noconfirm base-devel git
}

bootstrap_aur_helper() {
    if command -v yay  >/dev/null; then ok "yay is already installed."; return; fi
    if command -v paru >/dev/null; then ok "paru is already installed."; return; fi
    log "Bootstrapping yay (AUR helper)…"
    local d; d=$(mktemp -d)
    git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$d/yay-bin"
    (cd "$d/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$d"
    ok "yay installed."
}

# ─── Clone ──────────────────────────────────────────────────────────
clone_repo() {
    log "Cloning my-dots ($REPO_BRANCH)…"
    git clone --depth=1 --branch "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR"
}

# ─── Packages ───────────────────────────────────────────────────────
read_pkg_list() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -vE '^\s*(#|$)' "$file"
}

install_packages() {
    local pacman_pkgs aur_pkgs
    mapfile -t pacman_pkgs < <(read_pkg_list "$CLONE_DIR/packages/pacman.txt")
    mapfile -t aur_pkgs    < <(read_pkg_list "$CLONE_DIR/packages/aur.txt")

    if (( ${#pacman_pkgs[@]} > 0 )); then
        log "Installing ${#pacman_pkgs[@]} pacman packages…"
        sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}"
    fi
    if $INSTALL_AUR && (( ${#aur_pkgs[@]} > 0 )); then
        log "Installing ${#aur_pkgs[@]} AUR packages…"
        local helper; helper=$(command -v yay || command -v paru)
        "$helper" -S --needed --noconfirm "${aur_pkgs[@]}"
    fi
}

# ─── Deploy configs ─────────────────────────────────────────────────
deploy_configs() {
    mkdir -p "$CONFIG_HOME"
    for name in "${MANAGED_DIRS[@]}"; do
        local src="$CLONE_DIR/config/$name"
        local dest="$CONFIG_HOME/$name"
        [[ -d "$src" ]] || { warn "Skipping $name (not in repo)."; continue; }

        if [[ -e "$dest" ]]; then
            if $BACKUP_OLD; then
                mkdir -p "$BACKUP_DIR"
                log "Backing up $dest → $BACKUP_DIR/$name"
                mv "$dest" "$BACKUP_DIR/$name"
            else
                warn "Removing existing $dest (no backup)."
                rm -rf "$dest"
            fi
        fi
        log "Installing config: $name"
        cp -r "$src" "$dest"
    done

    # Make all .sh / .py executable
    log "Setting executable bits on scripts…"
    find "$CONFIG_HOME/hypr" "$CONFIG_HOME/quickshell" "$CONFIG_HOME/waybar" \
        -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true

    # Create the user override file (NEVER overwritten on update)
    local user_conf="$CONFIG_HOME/hypr/user.conf"
    if [[ ! -f "$user_conf" ]]; then
        cat > "$user_conf" <<'EOF'
# ═══════════════════════════════════════════════════════════════════
# Personal Hyprland overrides
# This file is created empty by the installer and is NEVER overwritten
# by future updates. Put your monitor configs, custom binds, env vars,
# theme tweaks, etc. here.
#
# Examples:
#   monitor = DP-1, 2560x1440@144, 0x0, 1
#   bind    = SUPER, B, exec, firefox
#   env     = GTK_THEME, Adwaita-dark
# ═══════════════════════════════════════════════════════════════════
EOF
        ok "Created empty user.conf for your personal overrides."
    fi
}

# ─── Wallpapers & Pictures dir ─────────────────────────────────────
setup_user_dirs() {
    mkdir -p "$HOME/Pictures/Wallpapers" "$HOME/Screenshots"
    if $INSTALL_WALLPAPERS && [[ -d "$CLONE_DIR/assets/wallpapers" ]]; then
        log "Installing default wallpapers…"
        cp -n "$CLONE_DIR/assets/wallpapers/"* "$HOME/Pictures/Wallpapers/" 2>/dev/null || true
    fi
}

# ─── Services ──────────────────────────────────────────────────────
enable_services() {
    $ENABLE_SERVICES || { warn "Skipping service activation."; return; }
    log "Enabling system services…"
    sudo systemctl enable --now NetworkManager.service 2>/dev/null || warn "NetworkManager: skipped."
    log "Enabling user audio services…"
    systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || warn "pipewire: skipped (this is fine if you'll start it from the session)."
}

# ─── Final message ─────────────────────────────────────────────────
finalize() {
    echo
    ok "${C_BOLD}Installation complete!${C_RESET}"
    echo
    echo "  ${C_BOLD}Next steps:${C_RESET}"
    echo "    1. Reboot or log out, then log back into Hyprland."
    echo "    2. Customise via ~/.config/hypr/user.conf — never edit hyprland.conf directly."
    echo "    3. Wallpapers go in ~/Pictures/Wallpapers/ (use SUPER+P to pick one)."
    if [[ -d "$BACKUP_DIR" ]]; then
        echo
        echo "  ${C_BOLD}Backup of your old configs:${C_RESET}"
        echo "    $BACKUP_DIR"
    fi
    echo
    echo "  ${C_BOLD}Docs & support:${C_RESET}"
    echo "    https://github.com/<TOI>/my-dots#readme"
    echo
}

main() {
    preflight
    collect_choices
    install_base
    $INSTALL_AUR && bootstrap_aur_helper
    clone_repo
    install_packages
    deploy_configs
    setup_user_dirs
    enable_services
    finalize
}

main "$@"

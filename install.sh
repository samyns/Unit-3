#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#   Unit-3 installer — Hyprland + Quickshell + Waybar rice
#   Usage: bash <(curl -fsSL https://raw.githubusercontent.com/samyns/Unit-3/main/install.sh)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────
readonly REPO_URL="https://github.com/samyns/Unit-3.git"
readonly REPO_BRANCH="${UNIT3_BRANCH:-main}"
readonly CLONE_DIR="${TMPDIR:-/tmp}/Unit-3-install-$$"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Files that must NEVER be overwritten by re-running the installer.
# Relative to $CONFIG_HOME.
readonly PRESERVED_FILES=(
    "hypr/user.conf"
)

# Add support for flags
PINNED_MODE=false
VM_GL_TWEAKS=false          # Mesa llvmpipe + libgl software for Quickshell/Kitty (VirtualBox et al.)
BOOT_WALLPAPER_VM=false     # exec-once awww img → first wallpaper in ~/Pictures/wallpapers

[[ "${UNIT3_VM:-}" == "1" || "${UNIT3_VM:-}" == "yes" ]] && VM_GL_TWEAKS=true

for arg in "$@"; do
    case "$arg" in
        --pinned) PINNED_MODE=true ;;
        --latest) PINNED_MODE=false ;;
        --vm)     VM_GL_TWEAKS=true ;;
        --help|-h)
            cat <<EOF
Usage: install.sh [options]

  --latest   Install latest versions of all packages (default).
  --pinned   Install exact versions tested by the maintainer.
             Use this if --latest broke something on your system.
  --vm       VirtualBox / weak GPU: patch Quickshell + Kitty to use software OpenGL
             (llvmpipe), optional boot wallpaper. Or set env UNIT3_VM=1.

  Also: UNIT3_VM=1 same effect as --vm for non-interactive installs.
EOF
            exit 0
            ;;
    esac
done

# Folders managed by this installer (touched in $CONFIG_HOME)
readonly MANAGED_DIRS=(hypr quickshell waybar kitty dunst)

# Temp dir used to stash preserved user files during install
PRESERVED_STASH=""

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

cleanup() {
    [[ -d "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"
    [[ -n "$PRESERVED_STASH" && -d "$PRESERVED_STASH" ]] && rm -rf "$PRESERVED_STASH"
}
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
    INSTALL_WALLPAPERS=true;  ask_yn "Install default wallpapers to ~/Pictures/wallpapers?" y || INSTALL_WALLPAPERS=false
    INSTALL_BASHRC=true;      ask_yn "Install Unit-3 .bashrc (welcome banner + NieR prompt)?" y || INSTALL_BASHRC=false
    ENABLE_SERVICES=true;     ask_yn "Enable system services (NetworkManager, pipewire)?" y || ENABLE_SERVICES=false

    if $VM_GL_TWEAKS; then
        log "VirtualBox / software-GL mode enabled (--vm or UNIT3_VM=1)."
    elif ask_yn "VirtualBox or limited GPU? Apply software OpenGL for Quickshell + Kitty (fixes many VM crashes)" n; then
        VM_GL_TWEAKS=true
    fi
    if $VM_GL_TWEAKS && $INSTALL_WALLPAPERS; then
        BOOT_WALLPAPER_VM=false
        ask_yn "Apply the first bundled wallpaper automatically at each Hyprland login (awww)?" y && BOOT_WALLPAPER_VM=true || true
    fi
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
    log "Cloning Unit-3 ($REPO_BRANCH)…"
    git clone --depth=1 --branch "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR"
}

# ─── Packages ───────────────────────────────────────────────────────
read_pkg_list() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -vE '^\s*(#|$)' "$file"
}

install_packages() {
    local pacman_list="$CLONE_DIR/packages/pacman.txt"
    local aur_list="$CLONE_DIR/packages/aur.txt"

    if $PINNED_MODE; then
        local pinned_pacman="$CLONE_DIR/packages/pinned-pacman.txt"
        local pinned_aur="$CLONE_DIR/packages/pinned-aur.txt"
        log "Pinned mode: installing exact tested versions from Arch Archive."

        if [[ -f "$pinned_pacman" ]]; then
            log "Installing pinned pacman packages…"
            install_pinned_from_archive "$pinned_pacman"
        fi
        if $INSTALL_AUR && [[ -f "$pinned_aur" ]]; then
            warn "AUR packages cannot be reliably pinned — falling back to latest."
            mapfile -t aur_pkgs < <(grep -vE '^\s*(#|$)' "$aur_list")
            local helper; helper=$(command -v yay || command -v paru)
            "$helper" -S --needed --noconfirm "${aur_pkgs[@]}"
        fi
    else
        # Latest mode (default)
        local pacman_pkgs aur_pkgs
        mapfile -t pacman_pkgs < <(grep -vE '^\s*(#|$)' "$pacman_list")
        if (( ${#pacman_pkgs[@]} > 0 )); then
            log "Installing ${#pacman_pkgs[@]} pacman packages (latest)…"
            sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}"
        fi
        if $INSTALL_AUR && [[ -f "$aur_list" ]]; then
            mapfile -t aur_pkgs < <(grep -vE '^\s*(#|$)' "$aur_list")
            if (( ${#aur_pkgs[@]} > 0 )); then
                log "Installing ${#aur_pkgs[@]} AUR packages (latest)…"
                local helper; helper=$(command -v yay || command -v paru)
                "$helper" -S --needed --noconfirm "${aur_pkgs[@]}"
            fi
        fi
    fi
}

install_pinned_from_archive() {
    local pinned_file="$1"
    local archive_base="https://archive.archlinux.org/packages"
    local urls=()

    while IFS='=' read -r pkg version; do
        [[ "$pkg" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$pkg" || -z "$version" ]] && continue
        # Archive structure: /packages/<first-letter>/<pkg>/<pkg>-<version>-x86_64.pkg.tar.zst
        local first="${pkg:0:1}"
        local url="$archive_base/$first/$pkg/$pkg-$version-x86_64.pkg.tar.zst"
        urls+=("$url")
    done < "$pinned_file"

    if (( ${#urls[@]} > 0 )); then
        sudo pacman -U --noconfirm "${urls[@]}"
    fi
}

# ─── Preserve user files across re-installs ─────────────────────────
# Stash all files listed in PRESERVED_FILES to a temp dir BEFORE deploy_configs
# wipes the managed dirs. They will be restored AFTER the copy.
stash_preserved_files() {
    PRESERVED_STASH=$(mktemp -d)
    local count=0
    for rel in "${PRESERVED_FILES[@]}"; do
        local src="$CONFIG_HOME/$rel"
        if [[ -f "$src" ]]; then
            local stash="$PRESERVED_STASH/$rel"
            mkdir -p "$(dirname "$stash")"
            cp -a "$src" "$stash"
            count=$((count + 1))
        fi
    done
    if (( count > 0 )); then
        ok "Preserved $count user file(s) for restoration after install."
    fi
}

# Restore preserved files (overwrites whatever the repo copy put in their place).
restore_preserved_files() {
    [[ -z "$PRESERVED_STASH" || ! -d "$PRESERVED_STASH" ]] && return 0
    for rel in "${PRESERVED_FILES[@]}"; do
        local stash="$PRESERVED_STASH/$rel"
        local dest="$CONFIG_HOME/$rel"
        if [[ -f "$stash" ]]; then
            mkdir -p "$(dirname "$dest")"
            cp -a "$stash" "$dest"
            ok "Restored user file: $rel"
        fi
    done
}

# ─── Deploy configs ─────────────────────────────────────────────────
deploy_configs() {
    mkdir -p "$CONFIG_HOME"

    # 1. Stash files that must survive the install.
    stash_preserved_files

    # 2. Backup or remove existing managed dirs, then copy fresh from repo.
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

    # 3. Restore preserved user files (overwrites any template the repo provided).
    restore_preserved_files

    # 4. Make all .sh / .py executable.
    log "Setting executable bits on scripts…"
    find "$CONFIG_HOME/hypr" "$CONFIG_HOME/quickshell" "$CONFIG_HOME/waybar" \
        -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true

    # 5. Create the user override file if it still doesn't exist
    #    (first-time install, nothing to restore).
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
    else
        ok "Existing user.conf preserved."
    fi
}

# Patches after copying configs and having wallpapers if applicable (--vm): Quickshell/Kitty + awww first optional background
apply_vm_software_gl_tweaks_deployed() {
    $VM_GL_TWEAKS || return 0
    local h="$CONFIG_HOME/hypr/hyprland.conf"
    local ucs="$CONFIG_HOME/hypr/user.conf"

    if [[ -f "$h" ]] && grep -qE '^exec-once = env QT_MEDIA_BACKEND=ffmpeg qs[[:space:]]*$' "$h" 2>/dev/null; then
        cp -a "$h" "${h}.bak-vmgl-$(date +%Y%m%d%H%M%S)"
        sed -i 's|^exec-once = env QT_MEDIA_BACKEND=ffmpeg qs$|exec-once = env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe QT_MEDIA_BACKEND=ffmpeg QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION=1 /usr/bin/qs|' "$h"
        ok "Patched hyprland.conf: Quickshell exec-once uses software OpenGL (llvmpipe)."
    else
        warn "Could not find default Quickshell exec-once line in hyprland.conf — skip auto-patch (edit manually if needed)."
    fi

    local mark="# unit3-install-vm-gl"
    if [[ -f "$ucs" ]] && ! grep -qF "$mark" "$ucs" 2>/dev/null; then
        cat >>"$ucs" <<'VMGL'

# unit3-install-vm-gl — Kitty + software GL (VirtualBox / GPU limitada; Quickshell ya va en hyprland.conf)
unbind = SUPER, T
bind = SUPER, T, exec, env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe KITTY_GPU_DISABLED=1 /usr/bin/kitty
VMGL
        ok "Appended Kitty software-GL binds to user.conf."
    fi

    $BOOT_WALLPAPER_VM || return 0
    local first
    first="$(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -n1)"
    if [[ -z "$first" ]]; then
        warn "No images in ~/Pictures/wallpapers — skipping boot wallpaper exec-once."
        return 0
    fi
    local wb="# unit3-install-boot-wallpaper"
    if [[ -f "$ucs" ]] && grep -qF "$wb" "$ucs" 2>/dev/null; then
        return 0
    fi
    cat >>"$ucs" <<EOF

${wb}
exec-once = sleep 4 && awww img ${first}
EOF
    ok "Added exec-once to apply wallpaper at login: ${first}"
}

# ─── System files (PAM, etc.) ───────────────────────────────────────
deploy_system_files() {
    local pam_src="$CLONE_DIR/config/system/pam.d"
    if [[ ! -d "$pam_src" ]]; then
        warn "No system files to install."
        return
    fi
    log "Installing system PAM configurations…"
    for f in "$pam_src"/*; do
        [[ -f "$f" ]] || continue
        local name; name=$(basename "$f")
        sudo install -D -m 644 "$f" "/etc/pam.d/$name"
        ok "Installed PAM config: /etc/pam.d/$name"
    done
}

# ─── Shell config (.bashrc with welcome banner) ────────────────────
deploy_shell_config() {
    $INSTALL_BASHRC || { warn "Skipping .bashrc installation."; return; }

    local bashrc_src="$CLONE_DIR/config/bash/.bashrc"
    local bashrc_dest="$HOME/.bashrc"

    [[ -f "$bashrc_src" ]] || { warn "No bundled .bashrc found in repo."; return; }

    # Backup existing .bashrc if it's not already a Unit-3 one
    if [[ -f "$bashrc_dest" ]] && ! grep -q "Unit-3 default .bashrc" "$bashrc_dest"; then
        if $BACKUP_OLD; then
            mkdir -p "$BACKUP_DIR"
            cp "$bashrc_dest" "$BACKUP_DIR/.bashrc"
            log "Backed up existing ~/.bashrc"
        fi
    fi

    log "Installing Unit-3 .bashrc (welcome banner enabled)…"
    cp "$bashrc_src" "$bashrc_dest"

    # Create empty user override if missing
    if [[ ! -f "$HOME/.bashrc.local" ]]; then
        cat > "$HOME/.bashrc.local" <<'OVR'
# Unit-3 user overrides — never touched by updates.
# Put your personal aliases, functions, exports here.
#
# Examples:
#   alias ll='ls -la'
#   export EDITOR=nano
#   export PATH="$PATH:$HOME/.local/bin"
OVR
        ok "Created empty ~/.bashrc.local for your personal overrides."
    fi

    ok "Bashrc installed."
}

# ─── Wallpapers & Pictures dir ─────────────────────────────────────
setup_user_dirs() {
    mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Screenshots"
    if $INSTALL_WALLPAPERS && [[ -d "$CLONE_DIR/assets/wallpapers" ]]; then
        log "Installing default wallpapers…"
        cp -n "$CLONE_DIR/assets/wallpapers/"* "$HOME/Pictures/wallpapers/" 2>/dev/null || true
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


# ─── qshare CLI symlink ────────────────────────────────────────────
deploy_qshare_symlink() {
    local script="$CONFIG_HOME/quickshell/scripts/qshare.py"
    local link="$HOME/.local/bin/qshare"

    if [[ ! -f "$script" ]]; then
        warn "qshare.py not found in quickshell/scripts/, skipping symlink."
        return
    fi

    mkdir -p "$HOME/.local/bin"
    if [[ -L "$link" || -e "$link" ]]; then
        rm -f "$link"
    fi
    ln -s "$script" "$link"
    ok "Symlinked qshare CLI: $link → $script"

    # Vérifier que ~/.local/bin est dans le PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -qFx "$HOME/.local/bin"; then
        warn "~/.local/bin is not in your PATH."
        warn "Add this line to ~/.bashrc.local:"
        warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}


# ─── Final message ─────────────────────────────────────────────────
finalize() {
    echo
    ok "${C_BOLD}Installation complete!${C_RESET}"
    echo
    echo "  ${C_BOLD}Next steps:${C_RESET}"
    echo "    1. Reboot or log out, then log back into Hyprland."
    if $VM_GL_TWEAKS; then
        echo "    - VirtualBox/software-GL: from TTY login, prefer: exec start-hyprland"
        echo "      (bare Hyprland prints a warning; start-hyprland sets session properly)."
    fi
    echo "    2. Customise via ~/.config/hypr/user.conf — never edit hyprland.conf directly unless you know why."
    echo "    3. Bashrc personal overrides go in ~/.bashrc.local"
    echo "    4. Wallpapers go in ~/Pictures/wallpapers/ (use SUPER+P to pick one)."
    if [[ -d "$BACKUP_DIR" ]]; then
        echo
        echo "  ${C_BOLD}Backup of your old configs:${C_RESET}"
        echo "    $BACKUP_DIR"
    fi
    echo
    echo "  ${C_BOLD}Docs & support:${C_RESET}"
    echo "    https://github.com/samyns/Unit-3#readme"
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
    deploy_system_files
    deploy_shell_config
    setup_user_dirs
    apply_vm_software_gl_tweaks_deployed
    deploy_qshare_symlink
    enable_services
    finalize
}

main "$@"
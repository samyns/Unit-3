#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
# wave-check.sh
# Vérifie au démarrage Hyprland que les vidéos de la vague de pixels
# (reveal + hide) sont présentes. Si non, les génère en bloquant.
#
# Usage :
#   - Lancer manuellement : ./wave-check.sh
#   - Au démarrage : exec-once = ~/.config/quickshell/wave-check.sh
# ═════════════════════════════════════════════════════════════════════

set -e

# ── Paths génériques (respecte XDG) ──
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

QS_DIR="$CONFIG_HOME/quickshell"
VIDEOS_DIR="$QS_DIR/videos"
LOG_DIR="$CACHE_HOME/quickshell"
LOG_FILE="$LOG_DIR/wave-check.log"

# Fichiers attendus (noms utilisés par lockscreen.qml et WallpaperPicker.qml)
REVEAL_VIDEO="$VIDEOS_DIR/wave_reveal.mp4"
HIDE_VIDEO="$VIDEOS_DIR/wave_hide.mp4"
LAST_FRAME="$VIDEOS_DIR/wave_last_frame.png"

# Scripts générateurs
REVEAL_SCRIPT="$QS_DIR/pixel_wave.py"
HIDE_SCRIPT="$QS_DIR/pixel-wave-close-video.py"
LAST_FRAME_SCRIPT="$QS_DIR/ext_last_fr.py"

# ── Préparation ──
mkdir -p "$VIDEOS_DIR" "$LOG_DIR"

# Redirection stdout + stderr vers le log (avec timestamp)
exec > >(while IFS= read -r line; do printf '[%s] %s\n' "$(date +%H:%M:%S)" "$line"; done >> "$LOG_FILE") 2>&1

echo "═══════════════════════════════════════════════════════════"
echo "wave-check.sh — démarrage"
echo "  videos dir : $VIDEOS_DIR"
echo "═══════════════════════════════════════════════════════════"

# ── Vérification présence des scripts ──
missing_scripts=()
[[ -f "$REVEAL_SCRIPT" ]] || missing_scripts+=("$REVEAL_SCRIPT")
[[ -f "$HIDE_SCRIPT"   ]] || missing_scripts+=("$HIDE_SCRIPT")
[[ -f "$LAST_FRAME_SCRIPT" ]] || missing_scripts+=("$LAST_FRAME_SCRIPT")
if (( ${#missing_scripts[@]} > 0 )); then
    echo "❌ Script(s) générateur(s) manquant(s) :"
    printf '   - %s\n' "${missing_scripts[@]}"
    echo "Abandon."
    exit 1
fi

# ── Vérif et génération reveal ──
if [[ -f "$REVEAL_VIDEO" ]]; then
    echo "✓ wave_reveal.mp4 présent"
else
    echo "⚠ wave_reveal.mp4 manquant — génération…"
    python "$REVEAL_SCRIPT" -o "$REVEAL_VIDEO"
    if [[ -f "$REVEAL_VIDEO" ]]; then
        echo "✓ wave_reveal.mp4 généré"
    else
        echo "❌ échec génération wave_reveal.mp4"
        exit 2
    fi
fi

# ── Vérif et génération hide ──
if [[ -f "$HIDE_VIDEO" ]]; then
    echo "✓ wave_hide.mp4 présent"
else
    echo "⚠ wave_hide.mp4 manquant — génération…"
    python "$HIDE_SCRIPT" -o "$HIDE_VIDEO"
    if [[ -f "$HIDE_VIDEO" ]]; then
        echo "✓ wave_hide.mp4 généré"
    else
        echo "❌ échec génération wave_hide.mp4"
        exit 3
    fi
fi

if [[ -f "$LAST_FRAME" ]]; then
    echo "✓ wave_last_frame.png présent"
else
    echo "⚠ wave_last_frame.png manquant — génération…"
    python "$LAST_FRAME_SCRIPT" "$REVEAL_VIDEO"
    if [[ -f "$LAST_FRAME" ]]; then
        echo "✓ wave_last_frame.png généré"
    else
        echo "❌ échec génération wave_last_frame.png"
        exit 4
    fi
fi

echo "═══════════════════════════════════════════════════════════"
echo "wave-check.sh — terminé"
echo "═══════════════════════════════════════════════════════════"

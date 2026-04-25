#!/bin/bash
# lock.sh — Lance hyprlock avec fond pixel wave NieR
# Bind hyprland : bindr = SUPER, L, exec, ~/.config/hypr/lock.sh

BG="$HOME/.config/hypr/lockbg.png"
SCRIPT="$HOME/.config/hypr/gen-lockbg.py"

# Générer le fond pixel wave en arrière-plan
# (si le script existe et que python3 est dispo)
if command -v python3 &>/dev/null && [ -f "$SCRIPT" ]; then
    python3 "$SCRIPT" "$BG" &
    sleep 0.15   # laisser le temps au script de démarrer
fi

# Lancer hyprlock
# hyprlock gère le focus clavier automatiquement dès l'ouverture
exec hyprlock

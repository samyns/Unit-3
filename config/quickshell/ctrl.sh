#!/usr/bin/env bash
# ── Unit-3 ControlCenter toggle ──
# Usage:
#   ctrl.sh         → toggle the ControlCenter (open if closed, close if open)
#   ctrl.sh open    → force open
#   ctrl.sh close   → force close
#
# The ControlCenter must already be loaded by the main Quickshell instance.
# This script sends an IPC command — it does NOT spawn a new qs process.

set -e

pkill cloudflared
# Envoie la commande IPC (target=ctrl, method=$1 ou 'toggle' par défaut)
exec qs ipc call ctrl "${1:-toggle}"
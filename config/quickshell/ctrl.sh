#!/usr/bin/env bash
# ── Unit-3 ControlCenter toggle ──
# Usage:
#   ctrl.sh         → toggle the ControlCenter (open if closed, close if open)
#   ctrl.sh open    → force open
#   ctrl.sh close   → force close
#
# The ControlCenter must already be loaded by the main Quickshell instance.
# This script sends an IPC command — it does NOT spawn a new qs process.

echo "This script is deprecated. Please use 'qs ctrl [toggle|open|close]' instead."
pkill cloudflared
echo "Cloudflared stopped."
exec qs ipc call ctrl toggle
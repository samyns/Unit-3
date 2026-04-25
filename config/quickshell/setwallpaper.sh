#!/bin/bash
WP="$1"
TARGET="$2"

if [ -z "$WP" ] || [ ! -f "$WP" ]; then
    echo "Usage: setwallpaper.sh <path> <monitor_name|both>"
    exit 1
fi

if [ "$TARGET" = "both" ]; then
    awww img "$WP"
else
    awww img --outputs "$TARGET" "$WP"
fi

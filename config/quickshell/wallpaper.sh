#!/bin/bash
pgrep -f "WallpaperPicker.qml" && exit 0
QT_MEDIA_BACKEND=ffmpeg qs -p ~/.config/quickshell/widgets/WallpaperPicker.qml

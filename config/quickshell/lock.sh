#!/bin/bash
pgrep -f "lockscreen.qml" && exit 0
QT_MEDIA_BACKEND=ffmpeg qs -p ~/.config/quickshell/widgets/lockscreen.qml

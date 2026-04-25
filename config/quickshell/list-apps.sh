#!/bin/bash
for f in /usr/share/applications/*.desktop "$HOME"/.local/share/applications/*.desktop; do
    [ -f "$f" ] || continue
    name=$(grep -m1 '^Name='       "$f" | cut -d= -f2-)
    exec=$(grep -m1 '^Exec='       "$f" | cut -d= -f2- | sed 's/ %[A-Za-z]//g')
    cats=$(grep -m1 '^Categories=' "$f" | cut -d= -f2-)
    nod=$(grep  -m1 '^NoDisplay='  "$f" | cut -d= -f2-)
    hid=$(grep  -m1 '^Hidden='     "$f" | cut -d= -f2-)
    [ "$nod" = "true" ] && continue
    [ "$hid" = "true" ] && continue
    [ -z "$name" ]       && continue
    [ -z "$exec" ]       && continue
    desktop=$(basename "$f" .desktop)
    echo "$name|$desktop|$cats|$exec"
done | sort -u

#!/bin/sh
hyprctl monitors 2>/dev/null | awk '/^Monitor /{name=$2} /focused: yes/{print name; exit}'

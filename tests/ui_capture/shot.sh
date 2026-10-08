#!/bin/sh
# Usage: shot.sh <out.png> <mode>
"/c/Program Files (x86)/Godot_v4.7.1-stable_win64.exe" --path "S:/projects/Project Aether" res://tests/ui_capture/capture_ui.tscn --resolution 1920x1080 -- "$1" "$2" 2>&1 | grep -E "SCRIPT ERROR|Parse Error" -A4 | head -20

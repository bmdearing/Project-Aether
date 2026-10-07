#!/bin/sh
# Usage: grid.sh <out.png> <types> <mode> [thumb_width]
"/c/Program Files (x86)/Godot_v4.7.1-stable_win64.exe" --path "S:/projects/Project Aether" res://tests/viewmodel/capture_viewmodel.tscn --resolution 1280x720 -- "$1" "$2" "$3" "${4:-320}" 2>&1 | grep -iE "error|saved" -A1 | head -20

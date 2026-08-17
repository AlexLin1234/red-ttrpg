#!/usr/bin/env bash
# Render every screen to .shots/ using a virtual framebuffer.
set -euo pipefail
GODOT="${GODOT:-godot}"
rm -rf .shots && mkdir -p .shots
xvfb-run -a "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x980 \
  scenes/shoot.tscn 2>&1 | grep -vE "ALSA|snd_|libpulse|audio|V-Sync|OpenGL API|Condition .status" || true
cp -f "$(find "$HOME/.local/share/godot/app_userdata/Redline/shots" -name '*.png' -print -quit | xargs dirname)"/*.png .shots/ 2>/dev/null || true
ls -la .shots/

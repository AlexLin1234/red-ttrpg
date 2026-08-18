#!/usr/bin/env bash
# Render every screen to .shots/ using a virtual framebuffer.
#
# Godot cannot draw under --headless, so this needs Xvfb. The import pass first
# is not optional: a newly added class_name is invisible to the compiler until
# the global class cache is rebuilt.
set -euo pipefail

GODOT="${GODOT:-godot}"
SHOTS_DIR=".shots"
USER_DATA="$HOME/.local/share/godot/app_userdata/Redline"
USER_SHOTS="$USER_DATA/shots"

# Start from an empty save library so the demo campaign is regenerated from the
# current fixtures; a stale .red from an earlier run would render old content.
rm -rf "$SHOTS_DIR" "$USER_SHOTS" "$USER_DATA/saves"
mkdir -p "$SHOTS_DIR"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

xvfb-run -a "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x980 \
	scenes/shoot.tscn 2>&1 |
	grep -vE "ALSA|snd_|libpulse|audio|V-Sync|OpenGL API|Condition \"status|set_use_vsync" || true

if compgen -G "$USER_SHOTS/*.png" >/dev/null; then
	cp -f "$USER_SHOTS"/*.png "$SHOTS_DIR/"
fi
ls -la "$SHOTS_DIR"

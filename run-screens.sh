#!/usr/bin/env bash
# Run the screen-level suites: every screen drawn, and the two native windows.
#
# run-tests.sh proves the rules hold. This proves the screens that use them
# actually draw, and that the paths a GM clicks — rolling initiative, taking a
# shot, opening a run, starting a chase, searching the campaign — still work end
# to end. Godot cannot render under --headless, so both need a framebuffer.
set -euo pipefail

GODOT="${GODOT:-godot}"
SHOTS_DIR=".shots"
USER_DATA="$HOME/.local/share/godot/app_userdata/Redline"

# Start from an empty save library so the demo campaign is regenerated from the
# current fixtures; a stale .red from an earlier run would render old content.
rm -rf "$SHOTS_DIR" "$USER_DATA/shots" "$USER_DATA/saves"
mkdir -p "$SHOTS_DIR"

quiet() {
	grep -vE "ALSA|snd_|libpulse|audio|V-Sync|OpenGL API|Condition \"status|set_use_vsync" || true
}

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "== screens =="
xvfb-run -a "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x980 \
	scenes/shoot.tscn 2>&1 | quiet

echo "== native windows =="
xvfb-run -a "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x980 \
	scenes/gm_window_smoke.tscn 2>&1 | quiet

if compgen -G "$USER_DATA/shots/*.png" >/dev/null; then
	cp -f "$USER_DATA/shots"/*.png "$SHOTS_DIR/"
fi
echo "== $(find "$SHOTS_DIR" -name '*.png' | wc -l) screens rendered to $SHOTS_DIR =="

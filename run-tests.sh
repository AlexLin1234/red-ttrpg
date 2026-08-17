#!/usr/bin/env bash
# Run the rules test suite headlessly.
set -euo pipefail
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 |
	grep -vE "ALSA|snd_|libpulse|audio|Condition \"status"

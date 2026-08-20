#!/usr/bin/env bash
# Run the local rulebook assistant's suite and the release-content audit.
#
# The helper is Python; the rest of Redline is GDScript and runs from
# ./run-tests.sh. Both must pass before a release.
set -euo pipefail
PYTHON="${PYTHON:-python3}"
"$PYTHON" -m pytest "$@"
"$PYTHON" scripts/audit_export.py

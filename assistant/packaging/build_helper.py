"""Build the helper executable and prove the build works.

    python assistant/packaging/build_helper.py

Windows is the first target — it is where a Game Master is least likely to have
Python — but the spec is platform-generic and the same command produces a macOS
or Linux helper. The build is verified by running the frozen binary's own
self test, so a broken bundle fails here rather than on a GM's machine.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "assistant" / "packaging" / "redline-assistant.spec"
NAME = "redline-assistant.exe" if sys.platform == "win32" else "redline-assistant"


def build() -> Path:
    subprocess.run(
        [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", str(SPEC)],
        cwd=ROOT,
        check=True,
    )
    built = ROOT / "dist" / NAME
    if not built.is_file():
        raise SystemExit(f"the build did not produce {built}")
    return built


def verify(executable: Path) -> None:
    result = subprocess.run([str(executable), "--self-test"], capture_output=True, text=True, timeout=180)
    if result.returncode != 0 or not json.loads(result.stdout or "{}").get("ok"):
        raise SystemExit(f"the built helper failed its self test: {result.stdout}{result.stderr}")


def main() -> int:
    executable = build()
    verify(executable)
    print(f"built and verified {executable}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# PyInstaller build of the local rulebook assistant helper.
#
#     python -m PyInstaller assistant/packaging/redline-assistant.spec
#
# The result is one executable a Game Master never has to think about: Godot
# starts it, writes it a session token, and it exits when Redline does. Nothing
# from a Game Master's library is bundled — the helper is code only, and it
# reads books out of their private application-data directory at runtime.

import sys
from pathlib import Path

BLOCK_CIPHER = None
ROOT = Path(SPECPATH).resolve().parents[1]

# Backends are imported by name at runtime, so PyInstaller cannot see them.
HIDDEN_IMPORTS = [
    "uvicorn.logging",
    "uvicorn.loops.auto",
    "uvicorn.protocols.http.auto",
    "uvicorn.protocols.websockets.auto",
    "uvicorn.lifespan.on",
]
if sys.platform == "win32":
    HIDDEN_IMPORTS += ["keyring.backends.Windows"]
elif sys.platform == "darwin":
    HIDDEN_IMPORTS += ["keyring.backends.macOS"]
else:
    HIDDEN_IMPORTS += ["keyring.backends.SecretService", "keyring.backends.kwallet"]

analysis = Analysis(
    [str(ROOT / "assistant" / "__main__.py")],
    pathex=[str(ROOT)],
    binaries=[],
    datas=[],
    hiddenimports=HIDDEN_IMPORTS,
    hookspath=[],
    runtime_hooks=[],
    # Nothing here should drag a GUI toolkit or a test runner into the build.
    excludes=["tkinter", "pytest", "IPython", "matplotlib", "numpy.distutils"],
    cipher=BLOCK_CIPHER,
    noarchive=False,
)
archive = PYZ(analysis.pure, analysis.zipped_data, cipher=BLOCK_CIPHER)

executable = EXE(
    archive,
    analysis.scripts,
    analysis.binaries,
    analysis.datas,
    [],
    name="redline-assistant",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    # A console-less build still keeps stdin and stdout, which is the whole
    # handshake, but avoids flashing a terminal window over the game.
    console=False,
    disable_windowed_traceback=True,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

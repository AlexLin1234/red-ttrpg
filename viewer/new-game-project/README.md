# Cyberpunk RED Stream GM Viewer

Godot 4 viewer for the local `cprtool` service. Start the Python service from
the repository root, then run this project:

```powershell
.\.venv\Scripts\python.exe -m uvicorn cprtool.gm.service:app --host 127.0.0.1 --port 8000
```

Select a token, choose an action, then click a target. **Move** enables token
dragging; Shift-drag a cover prop while Move is active to rearrange the alley.
**Take Cover** also enters token movement mode. Ctrl+Z/Ctrl+Shift+Z call the
server-backed undo/redo history. Existing encounter actors are created as
tokens on startup, and cover durability is restored by stable prop ID.

The included geometry and SVG tokens are an original, dependency-free
blockout. Replace the meshes through the `MeshLibrary` or the token portrait
paths when a licensed environment kit and final character art are available.

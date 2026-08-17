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

The GM map is visible on startup when an image has been uploaded; press **M**
to toggle it. **Upload Map** accepts common raster formats and the service
normalizes the selected image to PNG. **Draw Zone** starts a polygon: left-click
vertices and right-click after at least three points to save it. **Clear Zones**
removes the current overlays. The map image and normalized zone coordinates are
persisted in the Git-ignored `data/maps/` directory.

Use the separate **Close Month** control to deduct each actor's upcoming
Lifestyle cost, mark unaffordable payments as due, and advance the game
calendar. The monthly operation and every deduction participate in server
undo/redo.

The included geometry and SVG tokens are an original, dependency-free
blockout. Replace the meshes through the `MeshLibrary` or the token portrait
paths when a licensed environment kit and final character art are available.

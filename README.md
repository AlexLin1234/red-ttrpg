# Redline

A standalone desktop GM console for Cyberpunk RED, built as a single Godot 4.7
project. Four screens cover the campaign library, City map, isometric combat
location, and character Forge.

No server, sidecar, or network connection is required. Rules run in GDScript
and campaigns are portable `.red` files stored on disk.

An optional FastAPI service and container are included for a persistent cloud
session. `POST /encounter/month-end` performs the same in-game month close as
one atomic operation and `/ws` broadcasts the resulting campaign state.

![The campaign library](docs/mockups/1a-library.png)

## Features

**Library** — lists campaign saves with real file size, format version, and
checksum-verified integrity. The active save shows party status, the latest
session log, and restore points.

**City** — provides the built-in Night City district view or any raster image
selected by the GM. Uploaded images are normalized to PNG, embedded in the
campaign save, and support persistent polygon zones. Choose **Draw zone**,
left-click vertices, and right-click to finish.

The in-world clock, date, shift, and weather are campaign state. Crossing a
month boundary automatically bills every configured character for the upcoming
month. **Close month** is available when the GM wants to advance explicitly.

**Location** — provides an isometric encounter board with tile, prop, and unit
placement, initiative, combat resolution, cover raycasts, and exact event-based
undo.

**Forge** — edits PCs, NPCs, and mook templates. Alongside stats, skills, gear,
Humanity, armor, and cover, each character can carry cash and one of the four
Lifestyle levels:

- Kibble — 100eb/month
- Generic Prepak — 300eb/month
- Good Prepak — 600eb/month
- Fresh Food — 1,500eb/month

An affordable month close deducts the cost and records the paid-through month.
An unaffordable payment never makes cash negative; it records the balance and a
seven-day grace period instead.

## Rules and owned content

No sourcebook pages or extracted images ship with Redline. The built-in combat
table is a homebrew placeholder so a fresh install can resolve a fight. A GM
who owns a map image can import it through the City screen; the image remains
inside their local campaign save.

The combat resolver handles exploding and fumbling d10s, defender-wins ties,
armor ablation, critical injuries, and cover. Each action records its exact
inverse so undo restores previous state structurally.

## Running it

Open `project.godot` in Godot 4.7, or run:

```bash
godot --path .
./run-tests.sh
./run-shots.sh
```

Both scripts accept `GODOT=/path/to/godot`. The test script performs the import
pass required to register global GDScript classes and then runs the headless
suite. Screenshot tests require a graphical renderer or Xvfb.

## Private Night City map

The sourcebook and map are deliberately ignored by Git. With a user-owned PDF
mounted read-only, extract the largest embedded image (optionally constrain the
search with `--page N`):

```bash
python scripts/extract_night_city_map.py \
  --pdf "/input/Cyberpunk Red.pdf" \
  --output "data/maps/night_city_2045.png"
```

The City screen loads that RGB-compatible PNG at runtime, preserves its aspect
ratio, and toggles it with **M** or **Map [M]**. When absent, the built-in map
remains usable. For cloud use, `docker compose up --build` provides persistent
`/data` campaign storage, a writable map mount, a read-only sourcebook mount,
and the API health check. Set `SOURCEBOOK_PDF` to the host PDF path.

## Layout

```text
project.godot        one Godot project with the Store autoload
scenes/              app and screenshot-runner scenes
scripts/
  app.gd             shell, screen routing, shortcuts
  rules/             dice, resolver, events, tables, Lifestyle billing
  campaign/          .red container, schema, store, fixtures
  encounter/         initiative, rounds, turns
  city/              built-in Night City district data
  board/             isometric board
  screens/           library, city, location, forge
  ui/theme.gd        palette, fonts, widget factories
tests/               headless runner and suites
docs/mockups/        visual design references
```

## Save format

A `.red` file is a zip containing:

```text
manifest.json          version, timestamps, SHA-256 and size per entry
campaign.json          identity, clock, map image/zones, logs and districts
roster.json            characters, cash and Lifestyle state
locations/<id>.json    board layouts
assets/map.png          optional normalized GM-uploaded map
```

The library reads only the manifest and campaign metadata when listing saves.
Opening a save verifies every entry against the recorded SHA-256 checksum.

## License

MIT, see `LICENSE`. Cyberpunk RED is a trademark of R. Talsorian Games; Redline
is an unaffiliated tool and includes none of the sourcebook's copyrighted
content.

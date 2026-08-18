# Redline

A standalone desktop GM console for Cyberpunk RED, built as a single Godot 4.7
project. Four screens cover the campaign library, City map, isometric combat
location, and character Forge.

No server, sidecar, API, or network connection is required. Rules, campaign
editing, Lifestyle month closing, and undo/redo all run in GDScript. Campaigns
are portable `.red` files stored on disk.

An optional FastAPI service and container are included for a persistent cloud
session. `POST /encounter/month-end` performs the same in-game month close as
one atomic operation and `/ws` broadcasts the resulting campaign state.

![The campaign library](docs/mockups/1a-library.png)

## Features

**Library** — lists campaign saves with real file size, format version, and
checksum-verified integrity. The active save shows party status, the latest
session log, and restore points.

**City** — Night City as hover-inspectable zone plates. Each reports who holds
it, what it is, danger, population, law response and net density. Diamond
markers flag zones carrying open job hooks.

Zones are campaign data, not a fixed list. Draw a new one corner by corner
straight onto the map and it becomes an area with the same fields as every
built-in district, ready to fill in. The Areas tab lists them all with Edit and
Delete on each; deleting a zone also removes the job hooks that pointed at it,
and says so before it does. The eight Night City districts are only the seed —
a campaign saved before zones were editable is migrated on open, keeping any
overrides it already carried.

What a zone occupies is editable too, not just what it says. **Reshape on the
map** puts handles on its corners: drag one to move it, click a cross on an edge
to add a corner there, right-click a corner to remove it, or drag inside the
shape to slide the whole plate — name included. Three corners is the floor. When
you finish, every pin is re-checked against the new boundary, so a district that
grew over a clinic now claims it.

Points of interest are pins dropped inside those zones — a clinic, a fixer's
booth, a corp tower. Each carries a name, a kind and notes, and can link to a
location: pick an existing board or build a fresh one on the spot. A linked pin
draws filled and opens its board in one click; an unlinked one draws hollow,
because it is a note on the map rather than somewhere the party can walk into.
The Places tab lists them all. Deleting a zone re-homes its pins rather than
deleting them — a place the party knows about does not stop existing because
the GM redrew a boundary.

**Upload map** puts the GM's own image behind those plates. It is normalized to
PNG, stored inside the campaign save, and drawn as a *backdrop* rather than a
separate mode — zones, pins and reshaping all keep working on top of it, so a
zone drawn over a real landmark stays on that landmark. A slider sets how
strongly it reads, and `M` hides it. A campaign carrying label-only zones from
the earlier annotation tool has them adopted into `areas` on open, so they gain
the district fields instead of being dropped.

The in-world clock, date, shift, and weather are campaign state. Crossing a
month boundary automatically bills every configured character for the upcoming
month. **Close month** is available when the GM wants to advance explicitly.

**Location** — provides an isometric encounter board with tile, prop, and unit
placement, initiative, combat resolution, cover raycasts, and exact event-based
undo.

**Forge** — edits PCs, NPCs, and mook templates. Players can choose any of the
ten Roles, configure Role Ability ranks and specialty/allocation points, and
build a sheet from the complete Skill catalog. Role Ability and Skill Checks
accept situational modifiers and use the same exploding-10/fumbling-1 d10 rules
as combat. Alongside stats, skills, gear, Humanity, armor, and cover, each
character can carry cash and one of the four Lifestyle levels:

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
godot --path .                # run the app
./run-tests.sh                # headless logic suite
./run-shots.sh                # render every screen to .shots/ (needs Xvfb)
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

Install the extraction-only dependencies with `python -m pip install -r
requirements.txt`. The City screen loads the resulting RGB-compatible PNG at
runtime, preserves its aspect ratio, and toggles it with **M** or **Map [M]**.
When absent, the built-in map remains usable.

The committed `data/.gdignore` prevents Godot from trying to import private
runtime tables as translation catalogs. If the project was previously opened
with extracted tables present, close Godot and remove the `.godot/` directory
once to clear the old failed import records; Godot will rebuild that cache.
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
  city/              zone data, the Night City seed, map images
  board/             the isometric board
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

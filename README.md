# Redline

A standalone desktop GM console for Cyberpunk RED, built as a single Godot 4.7
project. Four screens: a campaign library, a Night City map, a 3D isometric
location with combat, and a character forge.

No server, no sidecar, no network. The rules engine is GDScript; campaigns are
`.red` files on your disk.

![The campaign library](docs/mockups/1a-library.png)

## The four screens

**Library** — every campaign in `~/Documents/Redline/saves` as a `.red` file,
with its real size, format version and a checksum-verified integrity state. The
active save gets a hero panel: party HP and humanity, last session's log, and
named restore points.

**City** — Night City as hover-inspectable zone plates. Each reports who holds
it, what it is, danger, population, law response and net density. The in-world
clock, date, shift and weather are campaign state: advance an hour or a day and
the save changes with it. Diamond markers flag zones carrying open job hooks.

Zones are campaign data, not a fixed list. Draw a new one corner by corner
straight onto the map and it becomes an area with the same fields as every
built-in district, ready to fill in. The Areas tab lists them all with Edit and
Delete on each; deleting a zone also removes the job hooks that pointed at it,
and says so before it does. The eight Night City districts are only the seed —
a campaign saved before zones were editable is migrated on open, keeping any
overrides it already carried.

Points of interest are pins dropped inside those zones — a clinic, a fixer's
booth, a corp tower. Each carries a name, a kind and notes, and can link to a
location: pick an existing board or build a fresh one on the spot. A linked pin
draws filled and opens its board in one click; an unlinked one draws hollow,
because it is a note on the map rather than somewhere the party can walk into.
The Places tab lists them all. Deleting a zone re-homes its pins rather than
deleting them — a place the party knows about does not stop existing because
the GM redrew a boundary.

**Location** — an isometric board. Pick tiles, props or units from the palette
and click the grid to place them. Roll 1d10 + REF for initiative, then fire.
Every attack writes its arithmetic out longhand so you can see — and override —
what the engine did.

**Forge** — one editor for PCs, named NPCs and mook templates; they differ by a
tag, not by a screen. Ten stats with a point total, skills with computed totals,
gear and cyberware costed in Humanity, and armour SP tracked across six hit
locations. The cover builder alongside it writes props straight into the board's
palette.

## Cover is a question, not an answer

When you shoot, the board raycasts the line of fire across five points on the
target's silhouette. If something is in the way it stops and asks what that
means:

- **Cover takes the hit** — the barrier absorbs the damage at its own SP and HP.
  This is the default, and what the rules engine implements.
- **Partial cover** — a −2 penalty to the attack, damage carries through.
- **Ignore cover** — clear shot.

The geometry proposes; you dispose.

## Rules data

**No book data ships with Redline.** It boots on a homebrew placeholder table
set so a fresh install can resolve a fight immediately. If you own the book,
replace any value or import a JSON document in the same shape —
`scripts/rules/tables.gd` documents it, and `Tables.validate()` reports what is
missing before an import is accepted.

The combat resolver is pure and separately tested: exploding and fumbling d10s,
defender wins ties, armour ablates only after damage gets through, and cover
absorbs overflow rather than passing it on. Each constant carries the page it
was checked against, in `scripts/rules/resolver.gd`.

Undo is exact. Every action records the events it applied and the inverse of
each one, so stepping back restores the previous state structurally rather than
approximately. A fuzz test round-trips a thousand random attacks.

## Running it

Open `project.godot` in Godot 4.7, or:

```bash
godot --path .                # run the app
./run-tests.sh                # 230 checks, headless
./run-shots.sh                # render every screen to .shots/ (needs Xvfb)
```

Both scripts take `GODOT=/path/to/godot` if the binary is not on your `PATH`.

Godot cannot draw under `--headless`, so `run-shots.sh` uses a virtual
framebuffer. It is the visual half of verification: `run-tests.sh` proves the
rules hold, `run-shots.sh` proves the screens draw — and it drives the real
combat path, rolling initiative and answering the cover prompt, rather than only
photographing a static scene.

## Layout

```
project.godot        one project, Store autoload
scenes/              app.tscn, shoot.tscn
scripts/
  app.gd             shell: header, screen routing, shortcuts
  rules/             dice, resolver, reversible events, tables
  campaign/          .red container, schema, store, demo content
  encounter/         initiative, rounds, turns
  city/              zone data and the built-in Night City seed
  board/             the isometric board
  screens/           library, city, location, forge
  ui/theme.gd        palette, fonts, widget factories
tests/               headless runner and suites
docs/mockups/        the UI direction these screens are built against
```

Screens are assembled in GDScript rather than authored as `.tscn` trees. They
are dense, data-driven grids whose contents come from the campaign file, so the
layout has to be built in a loop either way; keeping it in code puts the
structure in one readable place.

## The save format

A `.red` file is a zip:

```
manifest.json          format, version, timestamps, SHA-256 + size per entry
campaign.json          identity, clock, weather, session log, hooks, districts
roster.json            characters
locations/<id>.json    board layouts
```

The library reads only `manifest.json` and `campaign.json` to draw a card, so
listing stays fast however large the file is. Integrity re-hashes every entry
against the manifest — "Verified" means it checked, and a test proves it fails
on a save edited behind the app's back.

## Licence

MIT, see `LICENSE`. Cyberpunk RED is a trademark of R. Talsorian Games; this is
an unaffiliated tool that ships none of their content.

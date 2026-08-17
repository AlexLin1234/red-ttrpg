# Redline

A standalone desktop GM console for Cyberpunk RED. Four screens: a campaign
library, a Night City map, a 3D isometric location with combat, and a character
forge.

Electron + React + TypeScript. Everything runs locally — no server, no account,
no network. Campaigns are files on your disk.

![The campaign library](docs/mockups/1a-library.png)

## The four screens

**Library** — every campaign in `~/Documents/Redline/saves` as a `.red` file,
with its real size, format version and a checksum-verified integrity state. The
active save gets a hero panel: party HP and humanity, last session's log, and
named restore points.

**City** — Night City as hover-inspectable districts. Each reports who holds it,
danger, population, law response and net density. The in-world clock, date,
shift and weather are campaign state: advance an hour or a day and the save
changes with it. Diamond markers flag districts carrying open job hooks.

**Location** — an isometric board. Drag tiles, props and units from the palette
onto the grid (Alt raises elevation). Roll 1d10 + REF for initiative, then fire.
Every attack writes its arithmetic out longhand so you can see — and override —
what the engine did.

**Forge** — one editor for PCs, named NPCs and mook templates; they differ by a
tag, not by a screen. Ten stats with a point total, skills with computed totals,
gear and cyberware costed in humanity, and armour SP tracked across six hit
locations. The cover builder alongside it writes props straight into the board's
palette.

## Cover is a question, not an answer

When you shoot, the board raycasts the line of fire across the target's
silhouette. If something is in the way it stops and asks you what that means:

- **Cover takes the hit** — the barrier absorbs the damage at its own SP and HP.
  This is the default and what the rules engine implements.
- **Partial cover** — a −2 penalty to the attack, damage carries through.
- **Ignore cover** — clear shot.

The geometry proposes; you dispose.

## Rules data

**No book data ships with Redline.** It boots on a homebrew placeholder table set
so a fresh install can resolve a fight immediately. If you own the book, replace
any value in the in-app table editor or import a JSON document in the same shape
(`src/core/rules/tables.ts` documents it).

The combat resolver is pure and separately tested: exploding and fumbling d10s,
defender wins ties, armour ablates only after damage gets through, and cover
absorbs overflow rather than passing it on. Constants carry the page they were
checked against, in `src/core/rules/resolver.ts`.

Undo is exact. Every action records the events it applied and the inverse of
each one, so stepping back restores the previous state structurally — not a
snapshot approximation. A fuzz test round-trips a thousand random attacks.

## Running it

```bash
npm install
npm run dev          # renderer in a browser at :5173, in-memory save library
npm run dev:electron # the real desktop app
```

`npm run dev` is useful on its own: with no Electron preload present the app
falls back to an in-memory library seeded with the demo campaign, so every
screen works in a browser.

```bash
npm test             # Vitest over the rules core
npm run test:e2e     # Playwright over the four-screen flow
npm run build        # typecheck + renderer + Electron shell
npm run package      # electron-builder → release/
```

## Layout

```
electron/           shell: window, save IPC. Thin on purpose.
src/platform/       the only seam to the OS — electron.ts and web.ts
src/core/           pure logic, no DOM
  rules/            dice, resolver, reversible events, tables
  campaign/         .red container, schema, demo content
  encounter/        initiative, rounds, turns
  city/             district data
src/screens/        library, city, location, forge
tests/              Vitest
e2e/                Playwright + screenshots
docs/mockups/       the UI direction these screens are built against
```

Every OS call goes through `src/platform/bridge.ts`. Electron implements it over
the preload bridge; the browser implements it in memory. Swapping the desktop
shell means rewriting those two files and nothing else.

## The save format

A `.red` file is a zip:

```
manifest.json          format, version, timestamps, SHA-256 + size per entry
campaign.json          identity, clock, weather, session log, hooks, districts
roster.json            characters
locations/<id>.json    board layouts
```

The library reads only `manifest.json` and `campaign.json` to draw a card, so
listing stays fast regardless of how much is in the file. Integrity re-hashes
every entry against the manifest — "Verified" means it checked.

## Licence

MIT, see `LICENSE`. Cyberpunk RED is a trademark of R. Talsorian Games; this is
an unaffiliated tool that ships none of their content.

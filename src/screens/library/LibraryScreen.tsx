import { useCallback, useEffect, useState } from 'react'

import { useStore } from '../../app/store'
import {
  packCampaign,
  readSummary,
  suggestFileName,
  unpackCampaign,
  type CampaignSummary,
} from '../../core/campaign/container'
import { newCampaign } from '../../core/campaign/fixtures'
import { seriousWoundThreshold } from '../../core/campaign/schema'
import { bridge, type SaveFileEntry } from '../../platform/bridge'
import './library.css'

interface LibraryRow {
  file: SaveFileEntry
  summary: CampaignSummary | null
  error: string | null
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function formatAge(timestamp: number): string {
  const seconds = Math.max(0, (Date.now() - timestamp) / 1000)
  const days = seconds / 86400
  if (days < 1) return 'today'
  if (days < 2) return 'yesterday'
  if (days < 14) return `${Math.round(days)} days ago`
  if (days < 60) return `${Math.round(days / 7)} weeks ago`
  if (days < 365) return `${Math.round(days / 30)} months ago`
  return 'last year'
}

function formatDate(iso: string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return '—'
  return date
    .toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
    .toUpperCase()
}

export function LibraryScreen() {
  const { dispatch, state } = useStore()
  const [rows, setRows] = useState<LibraryRow[]>([])
  const [selected, setSelected] = useState<string | null>(null)
  const [libraryPath, setLibraryPath] = useState('')
  const [busy, setBusy] = useState(true)

  const refresh = useCallback(async () => {
    setBusy(true)
    const platform = bridge()
    setLibraryPath(await platform.libraryDir())
    const files = await platform.listSaves()
    files.sort((a, b) => b.modified - a.modified)
    const next: LibraryRow[] = []
    for (const file of files) {
      try {
        next.push({ file, summary: await readSummary(await platform.readSave(file.path)), error: null })
      } catch (error) {
        next.push({ file, summary: null, error: (error as Error).message })
      }
    }
    setRows(next)
    setSelected((current) => current ?? next[0]?.file.path ?? null)
    setBusy(false)
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  const active = rows.find((row) => row.file.path === selected) ?? null

  const openSelected = useCallback(async () => {
    if (!active) return
    dispatch({ type: 'status', message: 'Opening…' })
    try {
      const bytes = await bridge().readSave(active.file.path)
      const loaded = await unpackCampaign(bytes)
      dispatch({
        type: 'opened',
        open: { path: active.file.path, sizeOnDisk: active.file.size, loaded },
      })
    } catch (error) {
      dispatch({ type: 'status', message: `Could not open: ${(error as Error).message}` })
    }
  }, [active, dispatch])

  const createCampaign = useCallback(async () => {
    const name = `New Campaign ${new Date().toISOString().slice(0, 10)}`
    const bundle = newCampaign(name)
    const path = `${libraryPath}/${suggestFileName(name)}`
    await bridge().writeSave(path, await packCampaign(bundle))
    await refresh()
    setSelected(path)
  }, [libraryPath, refresh])

  const importCampaign = useCallback(async () => {
    const picked = await bridge().pickSaveToImport()
    if (!picked) {
      dispatch({ type: 'status', message: 'Import is only available in the desktop app.' })
      return
    }
    const path = `${libraryPath}/${picked.name}`
    await bridge().writeSave(path, picked.bytes)
    await refresh()
    setSelected(path)
  }, [dispatch, libraryPath, refresh])

  return (
    <div className="library">
      <section className="library-list panel" aria-label="Saved campaigns">
        <div className="section-head">
          <span className="micro">Saved campaigns</span>
          <span className="micro">
            {busy ? 'Reading…' : `${rows.length} ${rows.length === 1 ? 'save' : 'saves'}`}
          </span>
        </div>

        <div className="library-rows scroll">
          {rows.map((row) => (
            <button
              key={row.file.path}
              type="button"
              className="library-row"
              aria-current={row.file.path === selected ? 'true' : undefined}
              onClick={() => setSelected(row.file.path)}
              onDoubleClick={() => void openSelected()}
            >
              <span className="library-cover hatched" aria-hidden="true">
                <span className="micro">Cover</span>
              </span>
              <span className="library-row-main">
                <span className="display library-row-name">
                  {row.summary?.name ?? row.file.name}
                </span>
                <span className="micro">
                  {row.error
                    ? `Unreadable — ${row.error}`
                    : `${row.summary?.city ?? '—'} · ${row.summary?.players ?? 0} players · ${
                        row.summary?.sessions
                          ? `Session ${row.summary.sessions}`
                          : row.summary?.arc ?? '—'
                      }`}
                </span>
              </span>
              <span className="library-row-meta">
                <span className="micro">{formatAge(row.file.modified)}</span>
                <span className="micro library-row-size">{formatSize(row.file.size)}</span>
              </span>
            </button>
          ))}
          {!busy && rows.length === 0 ? (
            <p className="library-empty micro">
              No campaigns in {libraryPath}. Create one to begin.
            </p>
          ) : null}
        </div>

        <div className="library-actions">
          <button type="button" className="button is-primary" onClick={() => void createCampaign()}>
            + New campaign
          </button>
          <button type="button" className="button" onClick={() => void importCampaign()}>
            Import .red
          </button>
        </div>
      </section>

      {active?.summary ? (
        <ActiveSave row={active} onOpen={() => void openSelected()} busy={state.status === 'Opening…'} />
      ) : (
        <section className="library-hero panel">
          <div className="empty-state">
            <span className="micro">Select a campaign</span>
            {active?.error ? <p className="library-error">{active.error}</p> : null}
          </div>
        </section>
      )}
    </div>
  )
}

function ActiveSave({
  row,
  onOpen,
  busy,
}: {
  row: LibraryRow
  onOpen: () => void
  busy: boolean
}) {
  const summary = row.summary!
  const [detail, setDetail] = useState<Awaited<ReturnType<typeof unpackCampaign>> | null>(null)

  // The hero panel shows party state and the session log, so it needs the full
  // campaign — but only for the one save the GM is looking at.
  useEffect(() => {
    let cancelled = false
    setDetail(null)
    void (async () => {
      try {
        const loaded = await unpackCampaign(await bridge().readSave(row.file.path))
        if (!cancelled) setDetail(loaded)
      } catch {
        if (!cancelled) setDetail(null)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [row.file.path])

  const party = detail?.roster.characters.filter((character) => character.kind === 'pc') ?? []
  const log = detail?.campaign.sessionLog ?? []
  const restorePoints = detail?.campaign.restorePoints ?? []
  const integrity = detail?.integrity

  return (
    <section className="library-hero panel" aria-label="Active save">
      <div className="library-keyart hatched">
        <span className="micro">Campaign key art — 962 × 228 drop zone</span>
      </div>

      <div className="library-hero-head">
        <div>
          <span className="micro-accent">
            Active save {row.file.modified ? `· ${formatAge(row.file.modified)}` : ''}
          </span>
          <h1 className="display library-title">{summary.name}</h1>
          <span className="micro">
            {summary.sessions ? `Session ${summary.sessions} · ` : ''}
            {summary.arc} · {summary.city}
          </span>
        </div>
        <div className="library-hero-actions">
          <button type="button" className="button is-primary" onClick={onOpen} disabled={busy}>
            ▶ Continue
          </button>
          <button type="button" className="button" disabled={restorePoints.length === 0}>
            Snapshots
          </button>
        </div>
      </div>

      <div className="library-hero-body">
        <div className="library-hero-left">
          <span className="micro">Party</span>
          <div className="library-party">
            {party.map((character) => (
              <div key={character.id} className="library-party-card">
                <span className="library-portrait hatched" aria-hidden="true" />
                <div className="library-party-main">
                  <div className="library-party-name">
                    <span className="field-value">{character.name}</span>
                    <span className="micro">{character.role}</span>
                  </div>
                  <span className="micro">
                    HP {character.hp}/{character.maxHp} · HUM {character.humanity} · SP{' '}
                    {character.armor.body.sp}
                  </span>
                  <div className="hp-bar">
                    <div
                      className={`hp-bar-fill${
                        character.hp <= seriousWoundThreshold(character.maxHp)
                          ? ' is-critical'
                          : character.hp < character.maxHp
                            ? ' is-hurt'
                            : ''
                      }`}
                      style={{ width: `${Math.max(0, (character.hp / character.maxHp) * 100)}%` }}
                    />
                  </div>
                </div>
              </div>
            ))}
            {party.length === 0 ? <p className="micro">No player characters yet.</p> : null}
          </div>

          <span className="micro">Last session log</span>
          <div className="library-log scroll">
            {log.map((entry, index) => (
              <div key={`${entry.session}-${index}`} className="library-log-row">
                <span className="micro">Sess {entry.session}</span>
                <span className="library-log-text">{entry.text}</span>
              </div>
            ))}
            {log.length === 0 ? <p className="micro">Nothing logged yet.</p> : null}
          </div>
        </div>

        <div className="library-hero-right">
          <span className="micro">Save file</span>
          <div className="library-facts">
            <Fact label="Format" value={`.RED v${summary.version}`} />
            <Fact label="Created" value={formatDate(summary.created)} />
            <Fact label="Sessions" value={String(summary.sessions)} />
            <Fact label="Locations" value={`${summary.locations} built`} />
            <Fact label="NPCs" value={String(summary.npcs)} />
            <Fact label="Hooks" value={`${summary.encounters} open`} />
            <Fact
              label="Integrity"
              value={
                integrity === undefined
                  ? 'Checking…'
                  : integrity.verified
                    ? 'Verified'
                    : `${integrity.problems.length} problems`
              }
              tone={integrity && !integrity.verified ? 'alert' : undefined}
            />
          </div>

          <span className="micro">Restore points</span>
          <div className="library-restore">
            {restorePoints.map((point) => (
              <div key={point.id} className="library-restore-row">
                <span className="field-value">{point.label}</span>
                <span className="micro">
                  Session {point.session} · {new Date(point.createdAt).toISOString().slice(11, 16)}
                </span>
              </div>
            ))}
            {restorePoints.length === 0 ? <p className="micro">None recorded.</p> : null}
          </div>

          <p className="library-path micro" title={row.file.path}>
            {row.file.path}
          </p>
        </div>
      </div>
    </section>
  )
}

function Fact({ label, value, tone }: { label: string; value: string; tone?: 'alert' }) {
  return (
    <div className="field-row">
      <span className="micro">{label}</span>
      <span className={`field-value${tone === 'alert' ? ' is-alert' : ''}`}>{value}</span>
    </div>
  )
}

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'

import { useStore } from '../../app/store'
import { Encounter, type ActorInput, type EncounterSnapshot } from '../../core/encounter/encounter'
import { STAT_KEYS, seriousWoundThreshold, type Character } from '../../core/campaign/schema'
import { DEFAULT_TABLES } from '../../core/rules/tables.default'
import { JsonTables } from '../../core/rules/tables'
import type { FireMode, Location as HitLocation } from '../../core/rules/resolver'
import { IsoBoard, type Cell, type CoverHit } from './iso'
import './location.css'

type PaletteTab = 'tiles' | 'props' | 'units'
type Tool = 'select' | 'move' | 'fire' | 'aimed' | 'autofire' | 'blast'

const TOOLS: { id: Tool; label: string; hint: string }[] = [
  { id: 'select', label: 'Select', hint: 'Click a unit to inspect it' },
  { id: 'move', label: 'Move', hint: 'Click a unit, then click a cell' },
  { id: 'fire', label: 'Fire', hint: 'Click a target' },
  { id: 'aimed', label: 'Aimed', hint: 'Called shot at −8 DV' },
  { id: 'autofire', label: 'Autofire', hint: 'Ten rounds, multiplier by margin' },
  { id: 'blast', label: 'Blast', hint: 'Click a cell to detonate' },
]

const BLAST_RADIUS_M = 6
const BLAST_DICE = 6

/** Turn a saved character into the shape the encounter engine wants. */
function toActorInput(character: Character): ActorInput {
  const weapons: Record<string, Record<string, unknown>> = {}
  for (const weapon of character.weapons) {
    weapons[weapon.name] = {
      ammo: weapon.ammo,
      magazine: weapon.magazine ?? weapon.ammo,
      weapon_type: weapon.weaponType,
      damage_dice: weapon.damageDice,
      rof: weapon.rof,
      autofire_rating: weapon.autofireRating ?? null,
      quality: weapon.quality ?? 'standard',
      jammed: weapon.jammed ?? false,
    }
  }
  const primary = character.weapons[0]
  const attackSkill = character.skills.find((skill) =>
    ['Handgun', 'Shoulder Arms', 'Melee Weapon'].includes(skill.name),
  )
  const evasion = character.skills.find((skill) => skill.name === 'Evasion')
  return {
    name: character.name,
    max_hp: character.maxHp,
    hp: character.hp,
    armor: Object.fromEntries(
      Object.entries(character.armor).map(([location, slot]) => [location, slot.sp]),
    ),
    ref: character.stats.REF,
    stats: character.stats,
    side: character.side,
    attack_base: attackSkill
      ? (character.stats[attackSkill.stat] ?? 0) + attackSkill.level
      : character.stats.REF,
    evasion_base: evasion ? (character.stats[evasion.stat] ?? 0) + evasion.level : character.stats.DEX,
    selected_weapon: primary?.name ?? '',
    skills: Object.fromEntries(
      character.skills.map((skill) => [skill.name, (character.stats[skill.stat] ?? 0) + skill.level]),
    ),
    weapons,
  }
}

interface PendingShot {
  attackerUnitId: string
  targetUnitId: string
  mode: FireMode
  location: HitLocation
  distanceM: number
  cover: CoverHit | null
  coverName: string
  coverSp: number
  coverHp: number
}

export function LocationScreen() {
  const { campaign, roster, activeLocation, dispatch } = useStore()
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const boardRef = useRef<IsoBoard | null>(null)
  const encounterRef = useRef<Encounter | null>(null)

  const [snapshot, setSnapshot] = useState<EncounterSnapshot | null>(null)
  const [tool, setTool] = useState<Tool>('select')
  const [paletteTab, setPaletteTab] = useState<PaletteTab>('units')
  const [selectedUnitId, setSelectedUnitId] = useState<string | null>(null)
  const [hoverCell, setHoverCell] = useState<Cell | null>(null)
  const [pending, setPending] = useState<PendingShot | null>(null)
  const [message, setMessage] = useState('Roll initiative to begin the round.')

  const characterById = useMemo(
    () => new Map((roster?.characters ?? []).map((character) => [character.id, character])),
    [roster],
  )

  // Board units keyed by their character, for turning initiative into tokens.
  const unitByCharacter = useMemo(() => {
    const map = new Map<string, string>()
    for (const unit of activeLocation?.units ?? []) map.set(unit.characterId, unit.id)
    return map
  }, [activeLocation])

  const characterOfUnit = useCallback(
    (unitId: string): Character | null => {
      const unit = activeLocation?.units.find((entry) => entry.id === unitId)
      return unit ? (characterById.get(unit.characterId) ?? null) : null
    },
    [activeLocation, characterById],
  )

  // -- encounter -------------------------------------------------------------

  useEffect(() => {
    if (!activeLocation || !roster) return
    const actors: Record<string, ActorInput> = {}
    for (const unit of activeLocation.units) {
      const character = characterById.get(unit.characterId)
      if (character) actors[unit.id] = toActorInput(character)
    }
    if (Object.keys(actors).length === 0) return
    const tables = new JsonTables(campaign?.tables ?? DEFAULT_TABLES)
    const encounter = new Encounter(tables, actors)
    encounterRef.current = encounter
    setSnapshot(encounter.snapshot())
    setSelectedUnitId(activeLocation.units[0]?.id ?? null)
  }, [activeLocation, roster, characterById, campaign?.tables])

  // -- board -----------------------------------------------------------------

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const board = new IsoBoard(canvas)
    boardRef.current = board
    const onResize = () => board.resize()
    window.addEventListener('resize', onResize)
    return () => {
      window.removeEventListener('resize', onResize)
      board.dispose()
      boardRef.current = null
    }
  }, [])

  useEffect(() => {
    const board = boardRef.current
    if (!board || !activeLocation || !campaign) return
    board.setLocation(activeLocation, campaign.coverPalette)
  }, [activeLocation, campaign])

  // Redraw tokens whenever the encounter changes: HP pips and downed states
  // come straight off the snapshot.
  useEffect(() => {
    const board = boardRef.current
    if (!board || !activeLocation) return
    const visuals = new Map(
      activeLocation.units.flatMap((unit) => {
        const character = characterById.get(unit.characterId)
        if (!character) return []
        const actor = snapshot?.actors.find((entry) => entry.id === unit.id)
        const hp = actor?.hp ?? character.hp
        const maxHp = actor?.maxHp ?? character.maxHp
        return [
          [
            unit.characterId,
            {
              id: unit.id,
              characterId: unit.characterId,
              name: character.name,
              side: character.side,
              hpRatio: Math.max(0, Math.min(1, hp / maxHp)),
              down: hp <= 0,
            },
          ] as const,
        ]
      }),
    )
    board.setUnits(activeLocation.units, visuals)
    board.setSelection(selectedUnitId)
  }, [activeLocation, characterById, snapshot, selectedUnitId])

  useEffect(() => {
    boardRef.current?.setSelection(selectedUnitId)
  }, [selectedUnitId])

  useEffect(() => {
    boardRef.current?.showBlastPreview(tool === 'blast' ? hoverCell : null, BLAST_RADIUS_M)
  }, [tool, hoverCell])

  // -- actions ---------------------------------------------------------------

  const commit = useCallback(() => {
    const encounter = encounterRef.current
    if (encounter) setSnapshot(encounter.snapshot())
  }, [])

  const moveUnit = useCallback(
    (unitId: string, cell: Cell) => {
      if (!activeLocation) return
      dispatch({
        type: 'location',
        id: activeLocation.id,
        update: (location) => ({
          ...location,
          units: location.units.map((unit) =>
            unit.id === unitId ? { ...unit, x: cell.x, z: cell.z, layer: cell.layer } : unit,
          ),
        }),
      })
    },
    [activeLocation, dispatch],
  )

  const beginAttack = useCallback(
    (targetUnitId: string, mode: FireMode) => {
      const board = boardRef.current
      const encounter = encounterRef.current
      if (!board || !encounter || !activeLocation || !selectedUnitId) return
      if (targetUnitId === selectedUnitId) return

      const attackerUnit = activeLocation.units.find((unit) => unit.id === selectedUnitId)
      const targetUnit = activeLocation.units.find((unit) => unit.id === targetUnitId)
      if (!attackerUnit || !targetUnit) return

      const from: Cell = { x: attackerUnit.x, z: attackerUnit.z, layer: attackerUnit.layer }
      const to: Cell = { x: targetUnit.x, z: targetUnit.z, layer: targetUnit.layer }
      const distanceM = Math.round(board.distanceM(from, to) * 10) / 10
      const cover = board.coverBetween(from, to)
      const definition = cover
        ? campaign?.coverPalette.find((entry) => entry.id === cover.coverId)
        : undefined
      const prop = cover ? activeLocation.props.find((entry) => entry.id === cover.propId) : undefined

      const shot: PendingShot = {
        attackerUnitId: selectedUnitId,
        targetUnitId,
        mode,
        location: mode === 'aimed' ? 'head' : 'body',
        distanceM,
        cover,
        coverName: definition?.name ?? 'Cover',
        coverSp: definition?.sp ?? 0,
        coverHp: prop?.hp ?? definition?.hp ?? 0,
      }

      // The GM decides whether cover applies. That is the whole point of the
      // prompt: the geometry proposes, the table disposes.
      if (cover) setPending(shot)
      else resolveShot(shot, 'none')
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [activeLocation, campaign, selectedUnitId],
  )

  const resolveShot = useCallback(
    (shot: PendingShot, coverChoice: 'absorb' | 'penalty' | 'none') => {
      const encounter = encounterRef.current
      const board = boardRef.current
      if (!encounter || !board || !activeLocation) return
      setPending(null)

      const attacker = encounter.snapshot().actors.find((entry) => entry.id === shot.attackerUnitId)
      const weaponName = attacker?.selectedWeapon
      if (!weaponName) {
        setMessage('The selected unit has no weapon configured.')
        return
      }

      try {
        encounter.attack({
          attackerId: shot.attackerUnitId,
          targetId: shot.targetUnitId,
          weapon: weaponName,
          distanceM: shot.distanceM,
          location: shot.location,
          mode: shot.mode,
          // Partial cover as a flat penalty is a GM call, not the printed rule;
          // absorbing the hit is what the resolver does by default.
          modifiers: coverChoice === 'penalty' ? -2 : 0,
          coverHp: coverChoice === 'absorb' ? shot.coverHp : undefined,
          coverId: coverChoice === 'absorb' ? shot.cover?.propId : undefined,
        })
      } catch (error) {
        setMessage((error as Error).message)
        return
      }

      const next = encounter.snapshot()
      setSnapshot(next)

      const attackerUnit = activeLocation.units.find((unit) => unit.id === shot.attackerUnitId)
      const targetUnit = activeLocation.units.find((unit) => unit.id === shot.targetUnitId)
      if (attackerUnit && targetUnit) {
        board.playShot(
          { x: attackerUnit.x, z: attackerUnit.z, layer: attackerUnit.layer },
          { x: targetUnit.x, z: targetUnit.z, layer: targetUnit.layer },
          Boolean(next.result?.hit),
        )
      }
      setMessage(next.card?.title ?? 'Resolved')
    },
    [activeLocation],
  )

  /**
   * Grenades hit everyone inside the radius for full damage with no cover save,
   * so this walks the units itself rather than going through the single-target
   * resolver.
   */
  const detonate = useCallback(
    (cell: Cell) => {
      const encounter = encounterRef.current
      const board = boardRef.current
      if (!encounter || !board || !activeLocation) return
      board.playBlast(cell, BLAST_RADIUS_M)

      const caught: string[] = []
      for (const unit of activeLocation.units) {
        const distance = board.distanceM(cell, { x: unit.x, z: unit.z, layer: unit.layer })
        if (distance > BLAST_RADIUS_M) continue
        caught.push(unit.id)
      }
      if (caught.length === 0) {
        setMessage(`Blast at ${BLAST_RADIUS_M} m caught nobody.`)
        return
      }
      setMessage(
        `Frag · ${BLAST_DICE}d6 · blast ${BLAST_RADIUS_M} m · ${caught.length} in radius · roll damage per target, no cover save`,
      )
    },
    [activeLocation],
  )

  // -- canvas events ---------------------------------------------------------

  const onCanvasMove = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {
    const board = boardRef.current
    if (!board) return
    const pick = board.pick(event.nativeEvent)
    const cell = pick?.cell ?? null
    setHoverCell(cell)
    board.setHoverCell(cell)
  }, [])

  const onCanvasClick = useCallback(
    (event: React.MouseEvent<HTMLCanvasElement>) => {
      const board = boardRef.current
      if (!board) return
      const pick = board.pick(event.nativeEvent)
      if (!pick) return

      if (tool === 'blast') {
        detonate(pick.cell)
        return
      }
      if (pick.kind === 'unit') {
        if (tool === 'fire') beginAttack(pick.id, 'single')
        else if (tool === 'aimed') beginAttack(pick.id, 'aimed')
        else if (tool === 'autofire') beginAttack(pick.id, 'autofire')
        else setSelectedUnitId(pick.id)
        return
      }
      if (tool === 'move' && selectedUnitId) {
        moveUnit(selectedUnitId, pick.cell)
        return
      }
      if (pick.kind === 'prop') setMessage(`Prop ${pick.id}`)
    },
    [beginAttack, detonate, moveUnit, selectedUnitId, tool],
  )

  const onWheel = useCallback((event: React.WheelEvent<HTMLCanvasElement>) => {
    boardRef.current?.setZoom(event.deltaY > 0 ? 2 : -2)
  }, [])

  const onDrop = useCallback(
    (event: React.DragEvent<HTMLCanvasElement>) => {
      event.preventDefault()
      const board = boardRef.current
      if (!board || !activeLocation) return
      const payload = event.dataTransfer.getData('application/redline')
      if (!payload) return
      const pick = board.pick(event.nativeEvent)
      if (!pick) return
      const parsed = JSON.parse(payload) as { kind: PaletteTab; id: string }
      // Alt raises the drop one elevation layer, matching the palette hint.
      const layer = event.altKey ? Math.min((activeLocation.layers ?? 1) - 1, 1) : 0
      const cell = { ...pick.cell, layer }

      dispatch({
        type: 'location',
        id: activeLocation.id,
        update: (location) => {
          if (parsed.kind === 'props') {
            const cover = campaign?.coverPalette.find((entry) => entry.id === parsed.id)
            return {
              ...location,
              props: [
                ...location.props,
                {
                  id: `prop-${Date.now()}`,
                  coverId: parsed.id,
                  x: cell.x,
                  z: cell.z,
                  layer: cell.layer,
                  rotation: 0,
                  hp: cover?.hp ?? 10,
                },
              ],
            }
          }
          if (parsed.kind === 'units') {
            return {
              ...location,
              units: [
                ...location.units,
                { id: `unit-${Date.now()}`, characterId: parsed.id, x: cell.x, z: cell.z, layer: cell.layer },
              ],
            }
          }
          const exists = location.tiles.some(
            (tile) => tile.x === cell.x && tile.z === cell.z && tile.layer === cell.layer,
          )
          if (exists) return location
          return {
            ...location,
            tiles: [...location.tiles, { ...cell, tileId: parsed.id, rotation: 0 }],
          }
        },
      })
    },
    [activeLocation, campaign, dispatch],
  )

  if (!campaign || !activeLocation) {
    return (
      <div className="empty-state">
        <span className="micro">No location in this campaign yet.</span>
      </div>
    )
  }

  const selectedActor = snapshot?.actors.find((actor) => actor.id === selectedUnitId) ?? null
  const selectedCharacter = selectedUnitId ? characterOfUnit(selectedUnitId) : null
  const currentTool = TOOLS.find((entry) => entry.id === tool)

  return (
    <div className="loc">
      <header className="loc-bar">
        <span className="micro">
          {campaign.city} / {activeLocation.name}
        </span>
        <span className="micro">
          Grid {activeLocation.tileMetres} m · Elev {activeLocation.layers} layers ·{' '}
          {snapshot?.round ? `Combat · Round ${snapshot.round}` : 'Setup'}
        </span>
      </header>

      <div className="loc-body">
        <aside className="loc-palette panel">
          <div className="tab-row">
            {(['tiles', 'props', 'units'] as PaletteTab[]).map((entry) => (
              <button
                key={entry}
                type="button"
                className="tab"
                aria-selected={paletteTab === entry}
                onClick={() => setPaletteTab(entry)}
              >
                {entry}
              </button>
            ))}
          </div>

          <div className="loc-palette-grid scroll">
            {paletteTab === 'tiles'
              ? ['deck', 'grate', 'rubble', 'ramp', 'water'].map((tile) => (
                  <PaletteChip key={tile} kind="tiles" id={tile} label={tile} />
                ))
              : null}
            {paletteTab === 'props'
              ? campaign.coverPalette.map((cover) => (
                  <PaletteChip
                    key={cover.id}
                    kind="props"
                    id={cover.id}
                    label={cover.name}
                    sub={`SP ${cover.sp} · ${cover.hp} HP`}
                  />
                ))
              : null}
            {paletteTab === 'units'
              ? (roster?.characters ?? []).slice(0, 24).map((character) => (
                  <PaletteChip
                    key={character.id}
                    kind="units"
                    id={character.id}
                    label={character.name}
                    sub={character.role}
                  />
                ))
              : null}
          </div>

          <p className="loc-palette-hint micro">
            Drag onto the grid. Alt raises elevation.
          </p>

          <div className="loc-grid-facts">
            <div className="field-row">
              <span className="micro">Snap</span>
              <span className="field-value">{activeLocation.tileMetres} m</span>
            </div>
            <div className="field-row">
              <span className="micro">Elevation shading</span>
              <span className="field-value">On</span>
            </div>
            <div className="field-row">
              <span className="micro">Line of sight</span>
              <span className="field-value">Dynamic</span>
            </div>
            <div className="field-row">
              <span className="micro">Cover prompt</span>
              <span className="field-value">GM decides</span>
            </div>
          </div>
        </aside>

        <section className="loc-stage">
          <canvas
            ref={canvasRef}
            className="loc-canvas"
            onClick={onCanvasClick}
            onMouseMove={onCanvasMove}
            onMouseLeave={() => {
              setHoverCell(null)
              boardRef.current?.setHoverCell(null)
            }}
            onWheel={onWheel}
            onDragOver={(event) => event.preventDefault()}
            onDrop={onDrop}
          />

          {tool === 'blast' ? (
            <div className="loc-banner">
              Frag grenade · {BLAST_DICE}d6 · blast {BLAST_RADIUS_M} m · everyone in radius takes
              full damage, no cover save
            </div>
          ) : null}

          <div className="loc-toolbar">
            {TOOLS.map((entry) => (
              <button
                key={entry.id}
                type="button"
                className="loc-tool"
                aria-pressed={tool === entry.id}
                onClick={() => setTool(entry.id)}
              >
                {entry.label}
              </button>
            ))}
            <span className="loc-tool-hint micro">{currentTool?.hint}</span>
          </div>

          {snapshot?.card ? (
            <div className={`loc-card tone-${snapshot.card.tone}`}>
              <div className="loc-card-head">
                <span className="micro">Attack resolution</span>
                <span className="display loc-card-title">{snapshot.card.title}</span>
              </div>
              <div className="loc-card-lines">
                {snapshot.card.lines.map((line, index) => (
                  <p key={index} className="loc-card-line">
                    {line}
                  </p>
                ))}
              </div>
            </div>
          ) : (
            <div className="loc-card is-idle">
              <span className="micro">{message}</span>
            </div>
          )}
        </section>

        <aside className="loc-rail panel">
          <div className="section-head">
            <span className="micro">Initiative</span>
            <span className="micro">1d10 + REF</span>
          </div>

          <div className="loc-initiative scroll">
            {(snapshot?.initiative ?? []).map((entry) => {
              const actor = snapshot?.actors.find((item) => item.id === entry.actorId)
              const isCurrent = snapshot?.currentActorId === entry.actorId
              const ratio = actor ? Math.max(0, actor.hp / actor.maxHp) : 1
              const serious = actor ? actor.hp <= seriousWoundThreshold(actor.maxHp) : false
              return (
                <button
                  key={entry.actorId}
                  type="button"
                  className="loc-init-row"
                  aria-current={isCurrent ? 'true' : undefined}
                  onClick={() => setSelectedUnitId(entry.actorId)}
                >
                  <span className="display loc-init-score">{entry.score}</span>
                  <span className="loc-init-main">
                    <span className="loc-init-name">{entry.name}</span>
                    <span className="micro">
                      {isCurrent ? 'Acting now' : ''}
                      {actor && actor.hp <= 0
                        ? 'Down'
                        : serious
                          ? ' · Seriously wounded'
                          : ''}
                    </span>
                    <span className="hp-bar">
                      <span
                        className={`hp-bar-fill${
                          ratio <= 0.25 ? ' is-critical' : ratio < 1 ? ' is-hurt' : ''
                        }`}
                        style={{ width: `${ratio * 100}%` }}
                      />
                    </span>
                  </span>
                  <span className="micro loc-init-hp">
                    {actor ? `${actor.hp}/${actor.maxHp}` : ''}
                  </span>
                </button>
              )
            })}
            {(snapshot?.initiative.length ?? 0) === 0 ? (
              <p className="micro loc-init-empty">Not rolled yet.</p>
            ) : null}
          </div>

          {selectedActor && selectedCharacter ? (
            <div className="loc-selected">
              <div className="section-head">
                <span className="micro">Selected</span>
                <span className="micro">{selectedCharacter.role}</span>
              </div>
              <div className="loc-stats">
                {STAT_KEYS.map((key) => (
                  <div key={key} className="loc-stat">
                    <span className="micro">{key}</span>
                    <span className="loc-stat-value">{selectedCharacter.stats[key]}</span>
                  </div>
                ))}
              </div>

              <div className="section-head">
                <span className="micro">Actions this turn</span>
              </div>
              <div className="loc-actions">
                {(snapshot?.actionsTaken[selectedActor.id] ?? []).map((action, index) => (
                  <div key={index} className="loc-action is-used">
                    <span>{action}</span>
                    <span className="micro">Used</span>
                  </div>
                ))}
                <div className="loc-action">
                  <span>Move · {selectedCharacter.stats.MOVE * 2} m</span>
                  <span className="micro">Action</span>
                </div>
                <div className="loc-action">
                  <span>Attack · {selectedActor.selectedWeapon || '—'}</span>
                  <span className="micro">
                    {selectedActor.weapons[0] ? `${selectedActor.weapons[0].ammo} rds` : '—'}
                  </span>
                </div>
                <div className="loc-action">
                  <span>Aimed shot · head</span>
                  <span className="micro">−8 DV</span>
                </div>
              </div>
            </div>
          ) : null}

          <div className="loc-rail-actions">
            <button
              type="button"
              className="button"
              onClick={() => {
                encounterRef.current?.rollInitiative()
                commit()
                setMessage('Initiative rolled.')
              }}
            >
              Roll initiative
            </button>
            <button
              type="button"
              className="button"
              disabled={!snapshot?.canUndo}
              onClick={() => {
                encounterRef.current?.undo()
                commit()
              }}
            >
              Undo
            </button>
            <button
              type="button"
              className="button is-primary"
              disabled={(snapshot?.initiative.length ?? 0) === 0}
              onClick={() => {
                encounterRef.current?.endTurn()
                commit()
                const next = encounterRef.current?.currentTurn()
                if (next) setSelectedUnitId(next.actorId)
              }}
            >
              End turn ▸
            </button>
          </div>
        </aside>
      </div>

      {pending ? (
        <CoverPrompt
          shot={pending}
          onChoose={(choice) => resolveShot(pending, choice)}
          onCancel={() => setPending(null)}
        />
      ) : null}
    </div>
  )
}

function PaletteChip({
  kind,
  id,
  label,
  sub,
}: {
  kind: PaletteTab
  id: string
  label: string
  sub?: string
}) {
  return (
    <div
      className="loc-chip"
      draggable
      onDragStart={(event) => {
        event.dataTransfer.setData('application/redline', JSON.stringify({ kind, id }))
        event.dataTransfer.effectAllowed = 'copy'
      }}
title={sub ? `${label} — ${sub}` : label}
    >
      <span className="loc-chip-swatch hatched" aria-hidden="true" />
      <span className="loc-chip-label">{label}</span>
      {sub ? <span className="micro">{sub}</span> : null}
    </div>
  )
}

/**
 * The geometry found cover in the line of fire; the GM decides what it means.
 * Both readings are offered because the printed rule and the mockup's HUD
 * disagree, and that disagreement is the GM's to settle.
 */
function CoverPrompt({
  shot,
  onChoose,
  onCancel,
}: {
  shot: PendingShot
  onChoose: (choice: 'absorb' | 'penalty' | 'none') => void
  onCancel: () => void
}) {
  return (
    <div className="loc-modal-scrim" role="dialog" aria-modal="true" aria-label="Cover in the line of fire">
      <div className="loc-modal panel">
        <span className="micro">Cover in the line of fire</span>
        <h2 className="display loc-modal-title">{shot.coverName}</h2>
        <p className="loc-modal-text">
          {Math.round(shot.cover!.occlusion * 100)}% of the target is behind it, {shot.cover!.distanceM} m
          from the shooter. Range to target {shot.distanceM} m.
        </p>

        <div className="loc-modal-choices">
          <button type="button" className="button is-primary" onClick={() => onChoose('absorb')}>
            Cover takes the hit
            <span className="micro">SP {shot.coverSp} · {shot.coverHp} HP absorbs the damage</span>
          </button>
          <button type="button" className="button" onClick={() => onChoose('penalty')}>
            Partial cover
            <span className="micro">−2 to the attack, damage carries to the target</span>
          </button>
          <button type="button" className="button" onClick={() => onChoose('none')}>
            Ignore cover
            <span className="micro">Clear shot</span>
          </button>
        </div>

        <button type="button" className="loc-modal-cancel micro" onClick={onCancel}>
          Cancel the shot
        </button>
      </div>
    </div>
  )
}

/**
 * Live encounter state.
 *
 * This module owns no rules arithmetic of its own. It reads actor state, hands
 * the numbers to the pure resolver, records the resulting events through the
 * reversible session log, and renders a snapshot the board can draw.
 *
 * Beyond the original port it also owns initiative, rounds and the per-turn
 * action budget, which the location screen needs and the old service never had.
 */

import { rollCheck, type RandomSource } from '../rules/dice'
import { Session, type ActorState, type GameEvent, type WorldState } from '../rules/events'
import {
  createAttackRequest,
  createTargetState,
  createWeapon,
  resolveAttack,
  type AttackResult,
  type FireMode,
  type Location,
  type Weapon,
} from '../rules/resolver'
import { JsonTables, type TablesDocument } from '../rules/tables'
import { HIT_LOCATIONS } from '../rules/resolver'

export interface ResolutionCard {
  kind: string
  title: string
  attacker?: string
  target?: string
  weapon?: string
  mode?: string
  location?: string
  hit?: boolean
  hpDamage?: number
  criticalInjury?: string | null
  lines: string[]
  tone: 'hit' | 'miss' | 'neutral' | 'undo'
}

export interface InitiativeEntry {
  actorId: string
  name: string
  score: number
  roll: number
  ref: number
}

export interface ActorInput {
  name?: string
  max_hp: number
  hp?: number
  armor?: Partial<Record<Location, number>>
  cover_hp?: number
  cover_id?: string | null
  wound_state?: string
  death_save_due?: boolean
  critical_injuries?: string[]
  attack_base?: number
  evasion_base?: number
  ref?: number
  selected_weapon?: string
  stats?: Record<string, number>
  skills?: Record<string, number>
  side?: 'party' | 'hostile' | 'neutral'
  weapons?: Record<string, { ammo?: number; jammed?: boolean; [key: string]: unknown }>
  [key: string]: unknown
}

const EMPTY_ARMOR: Partial<Record<Location, number>> = {}

function normaliseActor(actorId: string, entry: ActorInput): ActorState {
  const maxHp = Number(entry.max_hp)
  if (!Number.isFinite(maxHp) || maxHp <= 0) throw new Error(`${actorId}: max_hp must be positive`)
  const hp = entry.hp === undefined ? maxHp : Number(entry.hp)
  if (hp > maxHp) throw new Error(`${actorId}: hp cannot exceed max_hp`)

  const armor: Partial<Record<Location, number>> = { ...EMPTY_ARMOR }
  for (const location of HIT_LOCATIONS) {
    const value = entry.armor?.[location]
    if (value !== undefined) {
      if (value < 0) throw new Error(`${actorId}: SP cannot be negative`)
      armor[location] = Number(value)
    }
  }

  const coverHp = Number(entry.cover_hp ?? 0)
  if (coverHp < 0) throw new Error(`${actorId}: cover HP cannot be negative`)

  const weapons: Record<string, { ammo: number; jammed: boolean; [key: string]: unknown }> = {}
  for (const [name, weapon] of Object.entries(entry.weapons ?? {})) {
    const ammo = Number(weapon.ammo ?? 0)
    if (ammo < 0) throw new Error('ammo cannot be negative')
    weapons[name] = { ...weapon, ammo, jammed: Boolean(weapon.jammed ?? false) }
  }

  return {
    ...entry,
    name: String(entry.name ?? actorId),
    max_hp: maxHp,
    hp,
    armor,
    cover_hp: coverHp,
    wound_state: String(entry.wound_state ?? 'unhurt'),
    death_save_due: Boolean(entry.death_save_due ?? false),
    critical_injuries: (entry.critical_injuries ?? []).map(String),
    weapons,
  } as ActorState
}

export interface WeaponView {
  name: string
  ammo: number
  jammed: boolean
  weaponType: string
  damageDice: number
  rof: number
  magazine: number
  autofireRating: number | null
  quality: Weapon['quality']
}

export interface ActorView {
  id: string
  name: string
  hp: number
  maxHp: number
  armor: Partial<Record<Location, number>>
  coverHp: number
  woundState: string
  deathSaveDue: boolean
  criticalInjuries: string[]
  attackBase: number
  evasionBase: number
  side: 'party' | 'hostile' | 'neutral'
  stats: Record<string, number>
  skills: Record<string, number>
  selectedWeapon: string
  weapons: WeaponView[]
}

export interface EncounterSnapshot {
  revision: number
  round: number
  turnIndex: number
  initiative: InitiativeEntry[]
  currentActorId: string | null
  actionsTaken: Record<string, string[]>
  canUndo: boolean
  canRedo: boolean
  actors: ActorView[]
  card: ResolutionCard | null
  events: GameEvent[]
  result: AttackResult | null
  covers: Record<string, number>
}

export interface AttackCommand {
  attackerId: string
  targetId: string
  weapon: string
  distanceM: number
  location?: Location
  mode?: FireMode
  modifiers?: number
  contested?: boolean
  coverHp?: number | null
  coverId?: string | null
}

export class Encounter {
  readonly tables: JsonTables
  session: Session
  revision = 0
  card: ResolutionCard | null = null
  events: GameEvent[] = []
  result: AttackResult | null = null

  round = 0
  initiative: InitiativeEntry[] = []
  turnIndex = 0
  /** Actions already taken this turn, keyed by actor id. */
  actionsTaken: Record<string, string[]> = {}

  constructor(
    tables: TablesDocument | JsonTables,
    actors?: Record<string, ActorInput>,
    private rng: RandomSource = { randint: (low, high) => low + Math.floor(Math.random() * (high - low + 1)) },
  ) {
    this.tables = tables instanceof JsonTables ? tables : new JsonTables(tables)
    this.session = new Session({ actors: {}, covers: {} })
    if (actors) this.load(actors)
  }

  // -- state ----------------------------------------------------------------

  /** Replace the encounter. Loading clears undo history by design. */
  load(actors: Record<string, ActorInput>): void {
    if (Object.keys(actors).length === 0) throw new Error('an encounter needs at least one actor')
    const state: WorldState = { actors: {}, covers: {} }
    for (const [key, value] of Object.entries(actors)) {
      state.actors[key] = normaliseActor(key, value)
    }
    this.session = new Session(state)
    this.revision += 1
    this.card = null
    this.events = []
    this.result = null
    this.round = 0
    this.initiative = []
    this.turnIndex = 0
    this.actionsTaken = {}
  }

  actor(actorId: string): ActorState {
    const actor = this.session.state.actors[actorId]
    if (!actor) throw new Error(`unknown actor: ${actorId}`)
    return actor
  }

  actorIds(): string[] {
    return Object.keys(this.session.state.actors)
  }

  private weaponState(actorId: string, weaponName: string) {
    const weapon = this.actor(actorId).weapons[weaponName]
    if (!weapon) throw new Error(`${actorId} is not carrying ${weaponName}`)
    return weapon
  }

  /** Weapon stats come from the actor's inline override, else the tables. */
  weapon(actorId: string, weaponName: string): Weapon {
    const entry = this.weaponState(actorId, weaponName)
    const quality = (entry.quality as Weapon['quality']) ?? 'standard'
    if (entry.damage_dice !== undefined) {
      return createWeapon({
        name: weaponName,
        weaponType: String(entry.weapon_type),
        damageDice: Number(entry.damage_dice),
        rof: Number(entry.rof ?? 1),
        magazine: Number(entry.magazine ?? 1),
        autofireRating:
          entry.autofire_rating === undefined || entry.autofire_rating === null
            ? null
            : Number(entry.autofire_rating),
        quality,
      })
    }
    const profile = this.tables.weapon(weaponName)
    return createWeapon({
      name: weaponName,
      weaponType: profile.range_type,
      damageDice: profile.damage_dice,
      rof: profile.rof,
      magazine: profile.magazine ?? 1,
      autofireRating: profile.autofire_rating,
      quality,
    })
  }

  // -- initiative ------------------------------------------------------------

  /** Roll 1d10 + REF for every actor and start round 1. Ties break by REF. */
  rollInitiative(): InitiativeEntry[] {
    const entries: InitiativeEntry[] = []
    for (const [actorId, actor] of Object.entries(this.session.state.actors)) {
      const ref = Number(actor.ref ?? (actor.stats as Record<string, number> | undefined)?.REF ?? 0)
      const roll = rollCheck(this.rng)
      entries.push({ actorId, name: String(actor.name), score: ref + roll.total, roll: roll.total, ref })
    }
    entries.sort((a, b) => b.score - a.score || b.ref - a.ref || a.name.localeCompare(b.name))
    this.initiative = entries
    this.round = 1
    this.turnIndex = 0
    this.actionsTaken = {}
    return entries
  }

  currentTurn(): InitiativeEntry | null {
    return this.initiative[this.turnIndex] ?? null
  }

  endTurn(): void {
    if (this.initiative.length === 0) return
    const current = this.currentTurn()
    if (current) delete this.actionsTaken[current.actorId]
    this.turnIndex += 1
    if (this.turnIndex >= this.initiative.length) {
      this.turnIndex = 0
      this.round += 1
    }
    this.revision += 1
  }

  private noteAction(actorId: string, action: string): void {
    ;(this.actionsTaken[actorId] ??= []).push(action)
  }

  // -- actions ---------------------------------------------------------------

  attack(command: AttackCommand): void {
    const {
      attackerId,
      targetId,
      weapon: weaponName,
      distanceM,
      location = 'body',
      mode = 'single',
      modifiers = 0,
      contested = false,
    } = command
    const coverId = command.coverId ?? null
    let coverHp = command.coverHp ?? null
    if (coverId !== null && coverHp === null) throw new Error('coverId requires coverHp')

    const attacker = this.actor(attackerId)
    const weaponState = this.weaponState(attackerId, weaponName)
    if (weaponState.jammed) throw new Error(`${weaponName} is jammed and must be cleared first`)
    if (attacker.attack_base === undefined) throw new Error(`${attackerId} has no attack_base`)

    let defenderEvasionBase: number | null = null
    if (contested) {
      const target = this.actor(targetId)
      if (target.evasion_base === undefined) throw new Error(`${targetId} has no evasion_base`)
      defenderEvasionBase = Number(target.evasion_base)
    }

    const targetActor = this.actor(targetId)
    let targetState = createTargetState({
      targetId,
      hp: Number(targetActor.hp),
      maxHp: Number(targetActor.max_hp),
      armor: targetActor.armor,
      coverHp: Number(targetActor.cover_hp),
    })

    let coverEvents: GameEvent[] = []
    if (coverHp !== null) {
      if (coverHp < 0) throw new Error('cover HP cannot be negative')
      const knownCoverHp = coverId === null ? undefined : this.session.state.covers?.[coverId]
      if (coverId !== null && knownCoverHp !== undefined) coverHp = Number(knownCoverHp)
      targetState = createTargetState({
        targetId,
        hp: targetState.hp,
        maxHp: targetState.maxHp,
        armor: targetState.armor,
        coverHp,
      })
      const coverChanged =
        coverHp !== targetActor.cover_hp ||
        coverId !== (targetActor.cover_id ?? null) ||
        (coverId !== null && !(coverId in (this.session.state.covers ?? {})))
      if (coverChanged) {
        coverEvents = [{ kind: 'cover_set', target_id: targetId, hp: coverHp, cover_id: coverId }]
      }
    }

    const request = createAttackRequest({
      attackerId,
      target: targetState,
      weapon: this.weapon(attackerId, weaponName),
      attackBase: Number(attacker.attack_base),
      distanceM,
      ammo: Number(weaponState.ammo),
      location,
      mode,
      defenderEvasionBase,
      modifiers,
    })
    const result = resolveAttack(request, this.tables, this.rng)

    const resultEvents = result.events.map((event) =>
      coverId !== null && event.kind === 'cover_damaged' ? { ...event, cover_id: coverId } : event,
    )
    const appliedEvents = [...coverEvents, ...resultEvents]
    this.session.record(
      {
        kind: 'attack',
        attacker_id: attackerId,
        target_id: targetId,
        weapon: weaponName,
        distance_m: distanceM,
        location,
        mode,
        modifiers,
        contested,
        cover_hp: coverHp,
        cover_id: coverId,
      },
      appliedEvents,
    )
    this.revision += 1
    this.card = this.attackCard(attackerId, targetId, weaponName, mode, location, result)
    this.events = structuredClone(appliedEvents)
    this.result = result
    this.noteAction(attackerId, mode === 'autofire' ? 'Autofire' : mode === 'aimed' ? 'Aimed Shot' : 'Attack')
  }

  reload(actorId: string, weaponName: string, amount?: number): void {
    const state = this.weaponState(actorId, weaponName)
    const magazine = Number(state.magazine ?? 0) || this.weapon(actorId, weaponName).magazine
    const missing = magazine - Number(state.ammo)
    const refill = amount === undefined ? missing : amount
    if (refill <= 0) throw new Error(`${weaponName} does not need a reload`)
    if (refill > missing) throw new Error(`${weaponName} can accept at most ${missing} rounds`)
    const events: GameEvent[] = [
      { kind: 'ammo_restored', actor_id: actorId, weapon: weaponName, amount: refill },
    ]
    this.session.record({ kind: 'reload', actor_id: actorId, weapon: weaponName, amount: refill }, events)
    this.revision += 1
    this.card = {
      kind: 'reload',
      title: 'RELOAD',
      attacker: String(this.actor(actorId).name),
      lines: [`${weaponName}: +${refill} rounds`, `Ammo: ${this.weaponState(actorId, weaponName).ammo}`],
      tone: 'neutral',
    }
    this.events = structuredClone(events)
    this.noteAction(actorId, 'Reload')
  }

  clearJam(actorId: string, weaponName: string): void {
    const state = this.weaponState(actorId, weaponName)
    if (!state.jammed) throw new Error(`${weaponName} is not jammed`)
    const events: GameEvent[] = [{ kind: 'weapon_unjammed', actor_id: actorId, weapon: weaponName }]
    this.session.record({ kind: 'clear_jam', actor_id: actorId, weapon: weaponName }, events)
    this.revision += 1
    this.card = {
      kind: 'clear_jam',
      title: 'JAM CLEARED',
      attacker: String(this.actor(actorId).name),
      lines: [`${weaponName} is ready to fire`],
      tone: 'neutral',
    }
    this.events = structuredClone(events)
  }

  undo(): void {
    const entry = this.session.log[this.session.log.length - 1]
    if (!entry) throw new RangeError('nothing to undo')
    const inverse = structuredClone(entry.inverse) as GameEvent[]
    this.session.undo()
    this.revision += 1
    this.card = { kind: 'undo', title: 'UNDO', lines: ['Previous action reversed.'], tone: 'undo' }
    this.events = inverse
    this.result = null
  }

  redo(): void {
    const entry = this.session.redoLog[this.session.redoLog.length - 1]
    if (!entry) throw new RangeError('nothing to redo')
    const replayed = structuredClone(entry.events) as GameEvent[]
    this.session.redo()
    this.revision += 1
    this.card = { kind: 'redo', title: 'REDO', lines: ['Previous action applied again.'], tone: 'neutral' }
    this.events = replayed
  }

  canUndo(): boolean {
    return this.session.log.length > 0
  }

  canRedo(): boolean {
    return this.session.redoLog.length > 0
  }

  // -- presentation ----------------------------------------------------------

  /**
   * The render model. Everything the board, the initiative rail and the
   * inspector draw comes from here, so a component never reaches into the
   * session state directly.
   */
  snapshot(): EncounterSnapshot {
    return {
      revision: this.revision,
      round: this.round,
      turnIndex: this.turnIndex,
      initiative: structuredClone(this.initiative),
      currentActorId: this.currentTurn()?.actorId ?? null,
      actionsTaken: structuredClone(this.actionsTaken),
      canUndo: this.canUndo(),
      canRedo: this.canRedo(),
      actors: Object.entries(this.session.state.actors).map(([id, actor]) =>
        this.actorView(id, actor),
      ),
      card: this.card ? structuredClone(this.card) : null,
      events: structuredClone(this.events),
      result: this.result ? structuredClone(this.result) : null,
      covers: structuredClone(this.session.state.covers ?? {}),
    }
  }

  private actorView(actorId: string, actor: ActorState): ActorView {
    return {
      id: actorId,
      name: String(actor.name),
      hp: Number(actor.hp),
      maxHp: Number(actor.max_hp),
      armor: { ...actor.armor },
      coverHp: Number(actor.cover_hp),
      woundState: String(actor.wound_state),
      deathSaveDue: Boolean(actor.death_save_due),
      criticalInjuries: [...actor.critical_injuries],
      attackBase: Number(actor.attack_base ?? 0),
      evasionBase: Number(actor.evasion_base ?? 0),
      side: (actor.side as ActorView['side']) ?? 'neutral',
      stats: { ...((actor.stats as Record<string, number>) ?? {}) },
      skills: { ...((actor.skills as Record<string, number>) ?? {}) },
      selectedWeapon: String(actor.selected_weapon ?? Object.keys(actor.weapons)[0] ?? ''),
      weapons: Object.entries(actor.weapons).map(([name, state]) =>
        this.weaponView(actorId, name, state),
      ),
    }
  }

  /**
   * A weapon with no inline stats and no table entry still has to draw — the GM
   * may have typed a homebrew name they have not costed yet.
   */
  private weaponView(
    actorId: string,
    name: string,
    state: { ammo: number; jammed: boolean; [key: string]: unknown },
  ): WeaponView {
    try {
      const weapon = this.weapon(actorId, name)
      return {
        name,
        ammo: state.ammo,
        jammed: state.jammed,
        weaponType: weapon.weaponType,
        damageDice: weapon.damageDice,
        rof: weapon.rof,
        magazine: weapon.magazine,
        autofireRating: weapon.autofireRating,
        quality: weapon.quality,
      }
    } catch {
      return {
        name,
        ammo: state.ammo,
        jammed: state.jammed,
        weaponType: String(state.weapon_type ?? 'unknown'),
        damageDice: Number(state.damage_dice ?? 0),
        rof: Number(state.rof ?? 1),
        magazine: Number(state.magazine ?? state.ammo),
        autofireRating:
          state.autofire_rating === undefined || state.autofire_rating === null
            ? null
            : Number(state.autofire_rating),
        quality: (state.quality as Weapon['quality']) ?? 'standard',
      }
    }
  }

  private attackCard(
    attackerId: string,
    targetId: string,
    weaponName: string,
    mode: FireMode,
    location: Location,
    result: AttackResult,
  ): ResolutionCard {
    let title: string
    if (!result.hit) title = 'MISS'
    else if (result.criticalInjury) title = 'CRITICAL INJURY'
    else if (result.hpDamage) title = 'HIT'
    else title = 'STOPPED'
    return {
      kind: 'attack',
      title,
      attacker: String(this.actor(attackerId).name),
      target: String(this.actor(targetId).name),
      weapon: weaponName,
      mode,
      location,
      hit: result.hit,
      hpDamage: result.hpDamage,
      criticalInjury: result.criticalInjury,
      lines: [...result.cardLines],
      tone: result.hit ? 'hit' : 'miss',
    }
  }
}

/**
 * Reversible event application and session history.
 *
 * Every event knows how to undo itself: `apply` returns the new state together
 * with a ready-to-run inverse sequence. That is what makes the GM's undo button
 * exact rather than approximate — no snapshot diffing, no lost precision.
 */

import type { Location } from './resolver'

export interface GameEventBase {
  kind: string
  [key: string]: unknown
}

export type GameEvent = GameEventBase

export const EVENT_KINDS: ReadonlySet<string> = new Set([
  'ammo_spent',
  'weapon_jammed',
  'attack_missed',
  'cover_damaged',
  'cover_set',
  'armor_ablated',
  'damage_taken',
  'critical_injury',
  'seriously_wounded',
  'death_save_due',
])

export interface WeaponState {
  ammo: number
  jammed: boolean
  [key: string]: unknown
}

export interface ActorState {
  hp: number
  max_hp: number
  armor: Partial<Record<Location, number>>
  cover_hp: number
  cover_id?: string | null
  wound_state: string
  death_save_due: boolean
  critical_injuries: string[]
  weapons: Record<string, WeaponState>
  [key: string]: unknown
}

export interface WorldState {
  actors: Record<string, ActorState>
  covers?: Record<string, number>
  [key: string]: unknown
}

function clone<T>(value: T): T {
  return structuredClone(value)
}

function actorOf(state: WorldState, actorId: string): ActorState {
  const actor = state.actors[actorId]
  if (!actor) throw new Error(`unknown actor: ${actorId}`)
  return actor
}

function weaponOf(actor: ActorState, name: string): WeaponState {
  const weapon = actor.weapons[name]
  if (!weapon) throw new Error(`unknown weapon: ${name}`)
  return weapon
}

function applyOne(state: WorldState, event: GameEvent): GameEvent {
  const kind = String(event.kind)
  if (kind === 'noop' || kind === 'attack_missed') return { kind: 'noop' }

  if (kind === 'ammo_spent' || kind === 'ammo_restored') {
    const actor = actorOf(state, String(event.actor_id))
    const weapon = weaponOf(actor, String(event.weapon))
    const amount = Number(event.amount)
    const delta = kind === 'ammo_spent' ? -amount : amount
    if (weapon.ammo + delta < 0) throw new Error('event would make ammo negative')
    weapon.ammo += delta
    return { ...event, kind: kind === 'ammo_spent' ? 'ammo_restored' : 'ammo_spent' }
  }

  if (kind === 'weapon_jammed' || kind === 'weapon_unjammed') {
    const actor = actorOf(state, String(event.actor_id))
    const weapon = weaponOf(actor, String(event.weapon))
    const previous = Boolean(weapon.jammed)
    weapon.jammed = kind === 'weapon_jammed'
    return {
      kind: previous ? 'weapon_jammed' : 'weapon_unjammed',
      actor_id: event.actor_id,
      weapon: event.weapon,
    }
  }

  const target = actorOf(state, String(event.target_id ?? ''))

  if (kind === 'cover_set') {
    const previous = Number(target.cover_hp ?? 0)
    const targetCoverIdExisted = 'cover_id' in target
    const previousId = target.cover_id ?? null
    const coverId = (event.cover_id ?? null) as string | null
    const coversExisted = state.covers !== undefined
    const covers = (state.covers ??= {})
    const coverExisted = coverId !== null && String(coverId) in covers
    const previousCoverHp = coverExisted ? Number(covers[String(coverId)]) : null

    target.cover_hp = Number(event.hp)
    target.cover_id = coverId
    if (target.cover_hp < 0) throw new Error('cover HP cannot be negative')
    if (coverId !== null) covers[String(coverId)] = target.cover_hp

    return {
      kind: 'cover_restored',
      target_id: event.target_id,
      hp: previous,
      cover_id: previousId,
      target_cover_id_existed: targetCoverIdExisted,
      affected_cover_id: coverId,
      cover_existed: coverExisted,
      previous_cover_hp: previousCoverHp,
      covers_existed: coversExisted,
    }
  }

  if (kind === 'cover_restored') {
    target.cover_hp = Number(event.hp)
    if (event.target_cover_id_existed === true) {
      target.cover_id = (event.cover_id ?? null) as string | null
    } else {
      delete target.cover_id
    }
    const covers = (state.covers ??= {})
    const affectedCoverId = event.affected_cover_id ?? null
    if (affectedCoverId !== null) {
      const key = String(affectedCoverId)
      if (event.cover_existed === true) covers[key] = Number(event.previous_cover_hp)
      else delete covers[key]
    }
    if (event.covers_existed === false && Object.keys(covers).length === 0) {
      delete state.covers
    }
    return { kind: 'noop' }
  }

  if (kind === 'cover_damaged' || kind === 'cover_repaired') {
    const amount = Number(event.amount)
    const coverId = (event.cover_id ?? null) as string | null
    const covers = coverId !== null ? (state.covers ??= {}) : (state.covers ?? {})
    const previous =
      coverId !== null && String(coverId) in covers
        ? Number(covers[String(coverId)])
        : Number(target.cover_hp ?? 0)
    target.cover_hp = kind === 'cover_damaged' ? Math.max(0, previous - amount) : previous + amount
    if (coverId !== null) covers[String(coverId)] = target.cover_hp
    const actual = kind === 'cover_damaged' ? previous - target.cover_hp : amount
    const inverse: GameEvent = {
      kind: kind === 'cover_damaged' ? 'cover_repaired' : 'cover_damaged',
      target_id: event.target_id,
      amount: actual,
    }
    if (coverId !== null) inverse.cover_id = event.cover_id
    return inverse
  }

  if (kind === 'armor_ablated' || kind === 'armor_restored') {
    const location = String(event.location) as Location
    const amount = Number(event.amount ?? 1)
    target.armor ??= {}
    // Track whether the location was on the sheet at all, so restoring a limb
    // that had no armour entry leaves the sheet exactly as it was found.
    const existed = location in target.armor
    const previous = Number(target.armor[location] ?? 0)
    const next = kind === 'armor_ablated' ? Math.max(0, previous - amount) : previous + amount
    if (!existed && next === 0) {
      return { kind: 'noop' }
    }
    target.armor[location] = next
    const actual = kind === 'armor_ablated' ? previous - next : amount
    return {
      kind: kind === 'armor_ablated' ? 'armor_restored' : 'armor_ablated',
      target_id: event.target_id,
      location,
      amount: actual,
      location_existed: existed,
    }
  }

  if (kind === 'damage_taken' || kind === 'damage_healed') {
    const amount = Number(event.amount)
    const previous = Number(target.hp)
    target.hp =
      kind === 'damage_taken'
        ? previous - amount
        : Math.min(Number(target.max_hp), previous + amount)
    const actual = kind === 'damage_taken' ? previous - target.hp : target.hp - previous
    return {
      kind: kind === 'damage_taken' ? 'damage_healed' : 'damage_taken',
      target_id: event.target_id,
      amount: actual,
    }
  }

  if (kind === 'critical_injury' || kind === 'critical_injury_removed') {
    target.critical_injuries ??= []
    const injury = String(event.injury)
    if (kind === 'critical_injury') {
      target.critical_injuries.push(injury)
      return { kind: 'critical_injury_removed', target_id: event.target_id, injury }
    }
    const index = target.critical_injuries.indexOf(injury)
    if (index === -1) throw new Error(`target is not carrying injury: ${injury}`)
    target.critical_injuries.splice(index, 1)
    return {
      kind: 'critical_injury',
      target_id: event.target_id,
      location: event.location ?? 'body',
      injury,
      rolls: event.rolls ?? [],
    }
  }

  if (kind === 'seriously_wounded' || kind === 'wound_state_restored') {
    const previous = String(target.wound_state ?? 'unhurt')
    target.wound_state =
      kind === 'seriously_wounded' ? 'seriously_wounded' : String(event.state)
    return { kind: 'wound_state_restored', target_id: event.target_id, state: previous }
  }

  if (kind === 'death_save_due' || kind === 'death_save_cleared') {
    const previous = Boolean(target.death_save_due)
    target.death_save_due = kind === 'death_save_due'
    return {
      kind: previous ? 'death_save_due' : 'death_save_cleared',
      target_id: event.target_id,
    }
  }

  throw new Error(`unsupported event kind: ${kind}`)
}

/** Apply events atomically and return new state plus ready-to-run inverses. */
export function apply(
  state: WorldState,
  events: readonly GameEvent[],
): { state: WorldState; inverse: GameEvent[] } {
  const nextState = clone(state) as WorldState
  const inverses: GameEvent[] = []
  for (const event of events) inverses.push(applyOne(nextState, event))
  inverses.reverse()
  return { state: nextState, inverse: inverses }
}

export interface LogEntry {
  action: Record<string, unknown>
  events: readonly GameEvent[]
  inverse: readonly GameEvent[]
}

export class Session {
  state: WorldState
  log: LogEntry[] = []
  redoLog: LogEntry[] = []

  constructor(state: WorldState) {
    this.state = clone(state)
  }

  record(action: Record<string, unknown>, events: readonly GameEvent[]): WorldState {
    const eventList = clone(events) as GameEvent[]
    const applied = apply(this.state, eventList)
    this.state = applied.state
    this.log.push({ action: clone(action), events: eventList, inverse: applied.inverse })
    this.redoLog.length = 0
    return clone(this.state)
  }

  undo(): WorldState {
    const entry = this.log.pop()
    if (!entry) throw new RangeError('nothing to undo')
    this.state = apply(this.state, entry.inverse).state
    this.redoLog.push(entry)
    return clone(this.state)
  }

  redo(): WorldState {
    const entry = this.redoLog.pop()
    if (!entry) throw new RangeError('nothing to redo')
    const applied = apply(this.state, entry.events)
    this.state = applied.state
    this.log.push({ action: entry.action, events: entry.events, inverse: applied.inverse })
    return clone(this.state)
  }
}

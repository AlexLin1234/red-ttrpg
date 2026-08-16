/**
 * Ported from the original Python `tests/test_encounter.py`, with the snapshot
 * shape adapted to the TypeScript view model.
 */
import { describe, expect, it } from 'vitest'

import { Encounter, type ActorInput, type EncounterSnapshot } from '../src/core/encounter/encounter'
import type { RandomSource } from '../src/core/rules/dice'
import { JsonTables, type TablesDocument } from '../src/core/rules/tables'

class FixedRng implements RandomSource {
  private index = 0
  constructor(private readonly values: number[]) {}
  randint(low: number, high: number): number {
    const value = this.values[this.index++]
    if (value === undefined) throw new Error('FixedRng ran out of values')
    expect(value).toBeGreaterThanOrEqual(low)
    expect(value).toBeLessThanOrEqual(high)
    return value
  }
}

/** A minimal table document: one pistol profile and flat DVs. */
function tablesDoc(dv = 13): TablesDocument {
  const band = [{ min_m: 0, max_m: 1000, dv }]
  const injuries = Object.fromEntries(
    Array.from({ length: 11 }, (_, index) => [
      String(index + 2),
      { name: `Test body injury ${index + 2}`, page: 187 },
    ]),
  )
  const headInjuries = Object.fromEntries(
    Array.from({ length: 11 }, (_, index) => [
      String(index + 2),
      { name: `Test head injury ${index + 2}`, page: 187 },
    ]),
  )
  return {
    ranged_dv: { pistol: band },
    autofire_dv: { pistol: band },
    weapons: {
      'Heavy Pistol': {
        range_type: 'pistol',
        skill: 'Handgun',
        damage_dice: 3,
        magazine: 8,
        rof: 2,
        hands: 1,
        concealable: true,
        autofire_rating: null,
        page: 341,
      },
    },
    armor: {},
    aimed_shots: { head: { modifier: -8, page: 170 } },
    cover: {},
    critical_injuries: { body: injuries, head: headInjuries },
  }
}

const SOLO: ActorInput = {
  name: 'Rache',
  max_hp: 40,
  attack_base: 12,
  evasion_base: 10,
  weapons: {
    'Heavy Pistol': { ammo: 8, weapon_type: 'pistol', damage_dice: 3, magazine: 8 },
  },
}

const GOON: ActorInput = {
  name: 'Booster',
  max_hp: 40,
  hp: 30,
  armor: { body: 7, head: 7 },
  evasion_base: 8,
  weapons: {},
}

function encounter(rolls: number[] = [], dv = 13, actors?: Record<string, ActorInput>): Encounter {
  return new Encounter(
    new JsonTables(tablesDoc(dv)),
    actors ?? { solo: structuredClone(SOLO), goon: structuredClone(GOON) },
    new FixedRng(rolls),
  )
}

function strike(session: Encounter, overrides: Record<string, unknown> = {}): EncounterSnapshot {
  session.attack({
    attackerId: 'solo',
    targetId: 'goon',
    weapon: 'Heavy Pistol',
    distanceM: 5,
    ...overrides,
  })
  return session.snapshot()
}

const actor = (snapshot: EncounterSnapshot, id: string) => {
  const found = snapshot.actors.find((entry) => entry.id === id)
  if (!found) throw new Error(`no actor ${id} in snapshot`)
  return found
}

describe('loading', () => {
  it('fills defaults and reports a drawable snapshot', () => {
    const snapshot = encounter().snapshot()
    const goon = actor(snapshot, 'goon')
    expect(goon.name).toBe('Booster')
    expect(goon.woundState).toBe('unhurt')
    expect(goon.deathSaveDue).toBe(false)
    expect(goon.criticalInjuries).toEqual([])

    const solo = actor(snapshot, 'solo')
    expect(solo.hp).toBe(40) // hp defaults to maxHp
    expect(solo.attackBase).toBe(12)
    expect(solo.evasionBase).toBe(10)
    expect(solo.selectedWeapon).toBe('Heavy Pistol')
    expect(solo.skills).toEqual({})

    const weapon = solo.weapons[0]
    expect(weapon).toMatchObject({
      name: 'Heavy Pistol',
      ammo: 8,
      jammed: false,
      weaponType: 'pistol',
      damageDice: 3,
      magazine: 8,
      autofireRating: null,
      quality: 'standard',
    })
    expect(snapshot.card).toBeNull()
    expect(snapshot.canUndo).toBe(false)
  })

  it('requires at least one actor', () => {
    expect(() => encounter().load({})).toThrow(/at least one actor/)
  })

  it('rejects hp above max', () => {
    expect(() => encounter([], 13, { solo: { max_hp: 10, hp: 11 } })).toThrow(/cannot exceed/)
  })
})

describe('attacking', () => {
  it('spends ammo, applies damage and renders a card', () => {
    const session = encounter([8, 4, 4, 4])
    const snapshot = strike(session)
    expect(actor(snapshot, 'goon').hp).toBe(25)
    expect(actor(snapshot, 'solo').weapons[0]?.ammo).toBe(7)
    expect(snapshot.card).toMatchObject({
      title: 'HIT',
      attacker: 'Rache',
      target: 'Booster',
      hpDamage: 5,
    })
    expect(snapshot.card?.lines.length).toBeGreaterThan(0)
    expect(snapshot.events[0]?.kind).toBe('ammo_spent')
    expect(snapshot.result?.hit).toBe(true)
    expect(snapshot.canUndo).toBe(true)
  })

  it('titles a miss and costs only ammo', () => {
    const session = encounter([2], 20)
    const snapshot = strike(session)
    expect(snapshot.card?.title).toBe('MISS')
    expect(snapshot.card?.hit).toBe(false)
    expect(actor(snapshot, 'goon').hp).toBe(30)
    expect(actor(snapshot, 'solo').weapons[0]?.ammo).toBe(7)
  })

  it('names a critical injury on the card', () => {
    const session = encounter([8, 6, 6, 2, 3, 4])
    const snapshot = strike(session)
    expect(snapshot.card?.title).toBe('CRITICAL INJURY')
    expect(snapshot.card?.criticalInjury).toBe('Test body injury 7')
    expect(actor(snapshot, 'goon').criticalInjuries).toEqual(['Test body injury 7'])
  })

  it('reports wound state and death saves', () => {
    const session = encounter([8, 4, 4, 4], 13, {
      solo: structuredClone(SOLO),
      goon: { name: 'Booster', max_hp: 20, hp: 10, weapons: {} },
    })
    const goon = actor(strike(session), 'goon')
    expect(goon.hp).toBe(-2)
    expect(goon.woundState).toBe('seriously_wounded')
    expect(goon.deathSaveDue).toBe(true)
  })

  it('lets cover absorb the hit instead of the target', () => {
    const session = encounter([8, 4, 4, 4], 13, {
      solo: structuredClone(SOLO),
      goon: { name: 'Booster', max_hp: 40, hp: 30, cover_hp: 10, weapons: {} },
    })
    const goon = actor(strike(session), 'goon')
    expect(goon.coverHp).toBe(0)
    expect(goon.hp).toBe(30)
    expect(session.snapshot().card?.title).toBe('STOPPED')
  })

  it('falls back to the table profile when the actor has no inline stats', () => {
    const session = encounter([8, 4, 4, 4], 13, {
      solo: { max_hp: 40, attack_base: 12, weapons: { 'Heavy Pistol': { ammo: 8 } } },
      goon: { max_hp: 40, hp: 30, armor: { body: 7, head: 7 }, weapons: {} },
    })
    expect(actor(strike(session), 'goon').hp).toBe(25) // three d6 from the table profile
  })

  it('rejects unknown actors and weapons', () => {
    expect(() => strike(encounter(), { targetId: 'nobody' })).toThrow(/unknown actor/)
    expect(() => strike(encounter(), { weapon: 'Marksman Rifle' })).toThrow(/not carrying/)
  })
})

describe('cover as a board object', () => {
  it('is event sourced and reversible', () => {
    const session = encounter([8, 4, 4, 4])
    const covered = strike(session, { coverHp: 20, coverId: 'BlueBarrier' })
    expect(actor(covered, 'goon').coverHp).toBe(8)
    expect(covered.covers).toEqual({ BlueBarrier: 8 })
    expect(actor(covered, 'goon').hp).toBe(30)
    expect(covered.events.map((event) => event.kind)).toEqual([
      'cover_set',
      'ammo_spent',
      'cover_damaged',
    ])

    session.undo()
    const undone = session.snapshot()
    expect(actor(undone, 'goon').coverHp).toBe(0)
    expect(undone.covers).toEqual({})
    expect(undone.events.some((event) => event.kind === 'cover_restored')).toBe(true)

    session.redo()
    const redone = session.snapshot()
    expect(redone.covers).toEqual({ BlueBarrier: 8 })
    const coverDamage = redone.events.find((event) => event.kind === 'cover_damaged')
    expect(coverDamage?.cover_id).toBe('BlueBarrier')
  })

  it('requires a cover HP measurement alongside a cover id', () => {
    expect(() => strike(encounter(), { coverId: 'BlueBarrier' })).toThrow(
      /coverId requires coverHp/,
    )
  })
})

describe('undo and redo', () => {
  it('restores the previous state and replays it', () => {
    const session = encounter([8, 4, 4, 4])
    strike(session)
    session.undo()
    const undone = session.snapshot()
    expect(actor(undone, 'goon').hp).toBe(30)
    expect(actor(undone, 'solo').weapons[0]?.ammo).toBe(8)
    expect(undone.card?.title).toBe('UNDO')
    expect(undone.events.some((event) => event.kind === 'damage_healed')).toBe(true)
    expect(undone.canRedo).toBe(true)

    session.redo()
    const redone = session.snapshot()
    expect(actor(redone, 'goon').hp).toBe(25)
    expect(actor(redone, 'solo').weapons[0]?.ammo).toBe(7)
    expect(redone.card?.title).toBe('REDO')
  })

  it('raises when there is nothing to undo', () => {
    expect(() => encounter().undo()).toThrow(/nothing to undo/)
  })
})

describe('weapon upkeep', () => {
  it('requires a jam to be cleared before firing', () => {
    const session = encounter([1, 4])
    session.session.state.actors.solo!.weapons['Heavy Pistol']!.jammed = true
    expect(() => strike(session)).toThrow(/jammed/)

    session.clearJam('solo', 'Heavy Pistol')
    const snapshot = session.snapshot()
    expect(actor(snapshot, 'solo').weapons[0]?.jammed).toBe(false)
    expect(snapshot.card?.title).toBe('JAM CLEARED')

    session.undo()
    expect(actor(session.snapshot(), 'solo').weapons[0]?.jammed).toBe(true)
  })

  it('refills the magazine reversibly', () => {
    const session = encounter([2], 20)
    strike(session)
    session.reload('solo', 'Heavy Pistol')
    expect(actor(session.snapshot(), 'solo').weapons[0]?.ammo).toBe(8)
    session.undo()
    expect(actor(session.snapshot(), 'solo').weapons[0]?.ammo).toBe(7)
  })

  it('refuses a pointless or oversized reload', () => {
    const session = encounter([2], 20)
    strike(session)
    expect(() => session.reload('solo', 'Heavy Pistol', 0)).toThrow(/does not need/)
    expect(() => session.reload('solo', 'Heavy Pistol', 2)).toThrow(/at most 1/)
  })

  it('keeps an uncosted homebrew weapon drawable', () => {
    const session = encounter([], 13, { solo: { max_hp: 40, weapons: { Homebrew: { ammo: 3 } } } })
    const weapon = actor(session.snapshot(), 'solo').weapons[0]
    expect(weapon).toMatchObject({ name: 'Homebrew', ammo: 3, weaponType: 'unknown' })
  })
})

describe('initiative', () => {
  it('orders by 1d10 + REF and cycles turns into the next round', () => {
    const session = encounter([3, 9], 13, {
      slow: { name: 'Slow', max_hp: 20, ref: 2, weapons: {} },
      fast: { name: 'Fast', max_hp: 20, ref: 8, weapons: {} },
    })
    // Object order decides roll order: slow rolls 3 (score 5), fast rolls 9 (17).
    const order = session.rollInitiative()
    expect(order.map((entry) => entry.actorId)).toEqual(['fast', 'slow'])
    expect(session.round).toBe(1)
    expect(session.currentTurn()?.actorId).toBe('fast')

    session.endTurn()
    expect(session.currentTurn()?.actorId).toBe('slow')
    expect(session.round).toBe(1)

    session.endTurn()
    expect(session.currentTurn()?.actorId).toBe('fast')
    expect(session.round).toBe(2)
  })

  it('records the actions an actor has spent this turn', () => {
    const session = encounter([5, 5, 8, 4, 4, 4])
    session.rollInitiative()
    strike(session)
    expect(session.snapshot().actionsTaken.solo).toEqual(['Attack'])
  })
})

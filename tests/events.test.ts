/**
 * Ported from the original Python `tests/test_events.py`.
 *
 * The contract these pin down: applying an event sequence and then applying its
 * inverse must restore the previous state *exactly*, structurally identical, for
 * any attack the resolver can produce. That is what the GM's undo depends on.
 */
import { describe, expect, it } from 'vitest'

import { SeededRandom } from '../src/core/rules/dice'
import { apply, Session, type GameEvent, type WorldState } from '../src/core/rules/events'
import {
  createAttackRequest,
  createTargetState,
  createWeapon,
  resolveAttack,
  type TargetState,
  type Weapon,
} from '../src/core/rules/resolver'
import type { CriticalInjuryRef, Tables } from '../src/core/rules/tables'

class StubTables implements Tables {
  rangedDv(): number {
    return 13
  }
  autofireDv(): number {
    return 17
  }
  autofireMultiplier(margin: number, rating: number | null): number {
    return Math.min(margin, rating ?? 1)
  }
  criticalInjury(location: 'body' | 'head', roll: number): CriticalInjuryRef {
    return { name: `Injury ${location} ${roll}`, page: 187 }
  }
}

function world(target: TargetState, weapon: Weapon, ammo: number): WorldState {
  return {
    actors: {
      solo: {
        hp: 40,
        max_hp: 40,
        armor: {},
        cover_hp: 0,
        wound_state: 'unhurt',
        death_save_due: false,
        critical_injuries: [],
        weapons: { [weapon.name]: { ammo, jammed: false } },
      },
      goon: {
        hp: target.hp,
        max_hp: target.maxHp,
        armor: { body: target.armor.body ?? 0, head: target.armor.head ?? 0 },
        cover_hp: target.coverHp,
        critical_injuries: [],
        wound_state: 'lightly_wounded',
        death_save_due: false,
        weapons: {},
      },
    },
  }
}

describe('event round trips', () => {
  it('restores exact state after applying an inverse', () => {
    const target = createTargetState({ targetId: 'goon', hp: 30, maxHp: 40, armor: { body: 7 } })
    const weapon = createWeapon({
      name: 'Heavy Pistol',
      weaponType: 'pistol',
      damageDice: 3,
      magazine: 8,
    })
    const before = world(target, weapon, 8)
    const pristine = structuredClone(before)
    const result = resolveAttack(
      createAttackRequest({
        attackerId: 'solo',
        target,
        weapon,
        attackBase: 14,
        distanceM: 5,
        ammo: 8,
      }),
      new StubTables(),
      new SeededRandom(7),
    )
    const applied = apply(before, result.events)
    const restored = apply(applied.state, applied.inverse)
    expect(restored.state).toEqual(pristine)
    // apply() must not mutate the state handed to it.
    expect(before).toEqual(pristine)
  })

  it('reverses a cover assignment and its damage as one action', () => {
    const target = createTargetState({ targetId: 'goon', hp: 30, maxHp: 40 })
    const weapon = createWeapon({
      name: 'Heavy Pistol',
      weaponType: 'pistol',
      damageDice: 3,
      magazine: 8,
    })
    const before = world(target, weapon, 8)
    const pristine = structuredClone(before)
    const events: GameEvent[] = [
      { kind: 'cover_set', target_id: 'goon', hp: 20, cover_id: 'crate' },
      { kind: 'cover_damaged', target_id: 'goon', amount: 12, cover_id: 'crate' },
    ]
    const applied = apply(before, events)
    expect(applied.state.actors.goon?.cover_hp).toBe(8)
    const restored = apply(applied.state, applied.inverse)
    expect(restored.state).toEqual(pristine)
    expect(applied.inverse[0]?.cover_id).toBe('crate')
    expect(applied.inverse[1]?.affected_cover_id).toBe('crate')
  })

  it('round trips one thousand random attacks', () => {
    const generator = new SeededRandom(20260815)
    const tables = new StubTables()
    for (let iteration = 0; iteration < 1000; iteration += 1) {
      const maxHp = generator.randint(20, 60)
      const target = createTargetState({
        targetId: 'goon',
        hp: generator.randint(1, maxHp),
        maxHp,
        armor: { body: generator.randint(0, 15), head: generator.randint(0, 15) },
        coverHp: [0, 0, 0, 5, 10, 20][generator.randint(0, 5)],
      })
      const weapon = createWeapon({
        name: 'Test Gun',
        weaponType: 'pistol',
        damageDice: generator.randint(2, 6),
        magazine: 20,
      })
      const before = world(target, weapon, 20)
      const pristine = structuredClone(before)
      const result = resolveAttack(
        createAttackRequest({
          attackerId: 'solo',
          target,
          weapon,
          attackBase: generator.randint(5, 20),
          distanceM: generator.randint(0, 6),
          ammo: 20,
        }),
        tables,
        new SeededRandom(generator.randint(1, 2 ** 30)),
      )
      const applied = apply(before, result.events)
      const restored = apply(applied.state, applied.inverse)
      expect(restored.state).toEqual(pristine)
    }
  })
})

describe('session history', () => {
  it('undoes, redoes, and clears redo on a new action', () => {
    const target = createTargetState({ targetId: 'goon', hp: 30, maxHp: 40, armor: { body: 0 } })
    const weapon = createWeapon({
      name: 'Heavy Pistol',
      weaponType: 'pistol',
      damageDice: 3,
      magazine: 8,
    })
    const initial = world(target, weapon, 8)
    const result = resolveAttack(
      createAttackRequest({
        attackerId: 'solo',
        target,
        weapon,
        attackBase: 20,
        distanceM: 5,
        ammo: 8,
      }),
      new StubTables(),
      new SeededRandom(3),
    )
    const session = new Session(structuredClone(initial))
    const resolved = session.record({ kind: 'attack' }, result.events)
    expect(session.undo()).toEqual(initial)
    expect(session.redo()).toEqual(resolved)
    session.undo()
    session.record({ kind: 'miss' }, [{ kind: 'attack_missed', target_id: 'goon' }])
    expect(session.redoLog).toHaveLength(0)
  })

  it('does not cap undo depth', () => {
    const target = createTargetState({ targetId: 'goon', hp: 30, maxHp: 40 })
    const weapon = createWeapon({
      name: 'Heavy Pistol',
      weaponType: 'pistol',
      damageDice: 3,
      magazine: 200,
    })
    const initial = world(target, weapon, 200)
    const session = new Session(structuredClone(initial))
    for (let index = 0; index < 100; index += 1) {
      session.record({ index }, [
        { kind: 'ammo_spent', actor_id: 'solo', weapon: weapon.name, amount: 1 },
      ])
    }
    for (let index = 0; index < 100; index += 1) session.undo()
    expect(session.state).toEqual(initial)
  })

  it('refuses to undo an empty log', () => {
    const session = new Session({ actors: {} })
    expect(() => session.undo()).toThrow(/nothing to undo/)
    expect(() => session.redo()).toThrow(/nothing to redo/)
  })
})

/**
 * Adapted from the original Python `tests/test_tables.py`.
 *
 * That suite skipped unless the operator had promoted a book-derived
 * `tables.json`. Redline ships homebrew placeholders instead, so these run
 * always: they check the adapter's behaviour and that the shipped defaults are
 * internally consistent enough to resolve a fight.
 */
import { describe, expect, it } from 'vitest'

import { DEFAULT_TABLES } from '../src/core/rules/tables.default'
import { JsonTables, validateTablesDocument } from '../src/core/rules/tables'
import type { RandomSource } from '../src/core/rules/dice'
import {
  createAttackRequest,
  createTargetState,
  createWeapon,
  resolveAttack,
} from '../src/core/rules/resolver'

const tables = new JsonTables(DEFAULT_TABLES)

describe('range bands', () => {
  it('reads a DV out of the band containing the distance', () => {
    expect(tables.rangedDv('pistol', 5)).toBe(11)
    expect(tables.rangedDv('pistol', 20)).toBe(15)
    expect(tables.rangedDv('sniper_rifle', 75)).toBe(15)
  })

  it('rejects a distance past the last band', () => {
    expect(() => tables.rangedDv('pistol', 250)).toThrow(/no valid range band/)
  })

  it('rejects a negative distance and an unknown weapon type', () => {
    expect(() => tables.rangedDv('pistol', -1)).toThrow(/cannot be negative/)
    expect(() => tables.rangedDv('railgun', 5)).toThrow(/unknown weapon type/)
  })

  it('reads autofire bands and caps the multiplier by rating', () => {
    expect(tables.autofireDv('smg', 10)).toBe(17)
    expect(tables.autofireDv('assault_rifle', 20)).toBe(19)
    expect(tables.autofireMultiplier(7, 4)).toBe(4)
    expect(tables.autofireMultiplier(2, 4)).toBe(2)
  })

  it('refuses autofire for a weapon type with no table', () => {
    expect(() => tables.autofireDv('sniper_rifle', 20)).toThrow(/does not support autofire/)
    expect(() => tables.autofireMultiplier(0, 4)).toThrow(/margin must be positive/)
    expect(() => tables.autofireMultiplier(3, null)).toThrow(/rating must be positive/)
  })
})

describe('shipped defaults', () => {
  it('is labelled as homebrew rather than book data', () => {
    expect(DEFAULT_TABLES.source).toMatch(/homebrew/i)
  })

  it('gives every weapon positive damage and rof', () => {
    for (const name of tables.weaponNames()) {
      const weapon = tables.weapon(name)
      expect(weapon.damage_dice).toBeGreaterThan(0)
      expect(weapon.rof).toBeGreaterThan(0)
    }
  })

  it('covers every critical injury roll for both tables', () => {
    for (const location of ['body', 'head'] as const) {
      for (let roll = 2; roll <= 12; roll += 1) {
        expect(tables.criticalInjury(location, roll).name).toBeTruthy()
      }
    }
    expect(() => tables.criticalInjury('body', 13)).toThrow(/between 2 and 12/)
  })

  it('exposes the cover materials the builder offers', () => {
    expect(tables.cover('Concrete')).toMatchObject({ sp: 15, hp: 30 })
    expect(tables.cover('Vehicle Hulk')).toMatchObject({ sp: 12, hp: 50 })
    expect(tables.aimedShot('head').modifier).toBe(-8)
  })

  it('passes its own validator', () => {
    expect(validateTablesDocument(DEFAULT_TABLES)).toEqual([])
  })
})

describe('import validation', () => {
  it('rejects a non-object and reports every missing section', () => {
    expect(validateTablesDocument('nope')).toEqual(['file is not a JSON object'])
    const problems = validateTablesDocument({})
    expect(problems).toContain('missing "ranged_dv" section')
    expect(problems).toContain('missing "critical_injuries" section')
  })

  it('reports a gap in a critical injury table', () => {
    const broken = structuredClone(DEFAULT_TABLES)
    delete broken.critical_injuries.body['7']
    expect(validateTablesDocument(broken)).toContain('body critical injuries missing roll 7')
  })

  it('reports a weapon with impossible stats', () => {
    const broken = structuredClone(DEFAULT_TABLES)
    broken.weapons['Heavy Sidearm']!.damage_dice = 0
    expect(validateTablesDocument(broken)).toContain('Heavy Sidearm: damage_dice must be positive')
  })
})

describe('resolver against the shipped tables', () => {
  it('resolves an attack end to end', () => {
    class FixedRng implements RandomSource {
      private index = 0
      constructor(private readonly values: number[]) {}
      randint(): number {
        return this.values[this.index++]!
      }
    }
    const result = resolveAttack(
      createAttackRequest({
        attackerId: 'solo',
        target: createTargetState({ targetId: 'goon', hp: 30, maxHp: 40, armor: { body: 7 } }),
        weapon: createWeapon({
          name: 'Heavy Sidearm',
          weaponType: 'pistol',
          damageDice: 3,
          magazine: 8,
        }),
        attackBase: 9,
        distanceM: 5,
        ammo: 8,
      }),
      tables,
      new FixedRng([5, 4, 4, 4]),
    )
    expect(result.hit).toBe(true)
    expect(result.defense).toBe(11)
    expect(result.hpDamage).toBe(5)
  })
})

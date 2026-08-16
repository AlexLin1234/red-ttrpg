/**
 * Ported 1:1 from the original Python `tests/test_resolver.py`. Every case here
 * pins a rule the resolver must keep after the TypeScript port.
 */
import { describe, expect, it } from 'vitest'

import { rollCheck, type RandomSource } from '../src/core/rules/dice'
import {
  createAttackRequest,
  createTargetState,
  createWeapon,
  resolveAttack,
  type AttackRequest,
  type AttackResult,
} from '../src/core/rules/resolver'
import type { CriticalInjuryRef, Tables } from '../src/core/rules/tables'

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

class FakeTables implements Tables {
  constructor(private readonly dv = 13) {}
  rangedDv(weaponType: string, distanceM: number): number {
    expect(weaponType).toBe('pistol')
    expect(distanceM).toBeGreaterThanOrEqual(0)
    return this.dv
  }
  autofireDv(): number {
    return this.dv
  }
  autofireMultiplier(margin: number, rating: number | null): number {
    expect(rating).not.toBeNull()
    return Math.min(margin, rating ?? 1)
  }
  criticalInjury(location: 'body' | 'head', roll: number): CriticalInjuryRef {
    return { name: `Test ${location} injury ${roll}`, page: 187 }
  }
}

function request(overrides: Partial<Parameters<typeof createAttackRequest>[0]> = {}): AttackRequest {
  return createAttackRequest({
    attackerId: 'solo',
    target: createTargetState({
      targetId: 'goon',
      hp: 30,
      maxHp: 40,
      armor: { body: 7, head: 7 },
    }),
    weapon: createWeapon({ name: 'Heavy Pistol', weaponType: 'pistol', damageDice: 3, magazine: 8 }),
    attackBase: 12,
    distanceM: 5,
    ammo: 8,
    ...overrides,
  })
}

const kinds = (result: AttackResult) => result.events.map((event) => event.kind)

describe('check rolls', () => {
  it('returns a plain roll', () => {
    expect(rollCheck(new FixedRng([7])).total).toBe(7)
  })

  it('explodes upward once on a ten', () => {
    const roll = rollCheck(new FixedRng([10, 6]))
    expect(roll.rolls).toEqual([10, 6])
    expect(roll.total).toBe(16)
  })

  it('fumbles downward once on a one', () => {
    const roll = rollCheck(new FixedRng([1, 6]))
    expect(roll.rolls).toEqual([1, 6])
    expect(roll.total).toBe(-5)
  })
})

describe('hitting', () => {
  it('misses on a tie against a static DV', () => {
    const result = resolveAttack(request({ attackBase: 8 }), new FakeTables(13), new FixedRng([5, 2, 3, 4]))
    expect(result.hit).toBe(false)
  })

  it('hits when the DV is beaten', () => {
    const result = resolveAttack(request({ attackBase: 9 }), new FakeTables(13), new FixedRng([5, 2, 3, 4]))
    expect(result.hit).toBe(true)
  })

  it('misses on a tie in an opposed check', () => {
    const result = resolveAttack(
      request({ attackBase: 8, defenderEvasionBase: 8 }),
      new FakeTables(),
      new FixedRng([5, 5]),
    )
    expect(result.hit).toBe(false)
    expect(result.defenseKind).toBe('evasion')
  })

  it('spends ammo on a miss and emits no damage', () => {
    const result = resolveAttack(request({ attackBase: 0 }), new FakeTables(20), new FixedRng([2]))
    expect(kinds(result)).toEqual(['ammo_spent', 'attack_missed'])
    expect(result.hpDamage).toBe(0)
  })
})

describe('damage', () => {
  it('lets armor stop a hit without ablating', () => {
    const result = resolveAttack(request(), new FakeTables(), new FixedRng([8, 2, 2, 3]))
    expect(result.rawDamage).toBe(7)
    expect(result.hpDamage).toBe(0)
    expect(kinds(result)).not.toContain('armor_ablated')
  })

  it('ablates and damages on a penetrating hit', () => {
    const result = resolveAttack(request(), new FakeTables(), new FixedRng([8, 4, 4, 4]))
    expect(result.hpDamage).toBe(5)
    expect(kinds(result).slice(-2)).toEqual(['armor_ablated', 'damage_taken'])
  })

  it('applies the head multiplier after armor', () => {
    const result = resolveAttack(
      request({ location: 'head', mode: 'aimed', attackBase: 20 }),
      new FakeTables(),
      new FixedRng([8, 4, 4, 4]),
    )
    expect(result.rawDamage).toBe(12)
    expect(result.armorDamage).toBe(10)
  })

  it('adds direct damage for a critical injury', () => {
    const result = resolveAttack(request(), new FakeTables(), new FixedRng([8, 6, 6, 2, 3, 4]))
    expect(result.criticalInjury).toBe('Test body injury 7')
    expect(result.armorDamage).toBe(7)
    expect(result.hpDamage).toBe(12)
    expect(kinds(result)).toContain('critical_injury')
  })

  it('lets cover take the full hit and stop resolution', () => {
    const covered = createTargetState({
      targetId: 'goon',
      hp: 30,
      maxHp: 40,
      armor: { body: 7 },
      coverHp: 4,
    })
    const result = resolveAttack(request({ target: covered }), new FakeTables(), new FixedRng([8, 6, 6, 6]))
    expect(kinds(result)).toEqual(['ammo_spent', 'cover_damaged'])
    expect(result.hpDamage).toBe(0)
    expect(result.criticalInjury).toBeNull()
    expect(result.cardLines.at(-1)).toBe('Cover: 4 HP - 18 = 0 HP')
  })
})

describe('wound thresholds', () => {
  it('emits seriously wounded when crossing half HP', () => {
    const target = createTargetState({ targetId: 'goon', hp: 21, maxHp: 40, armor: { body: 0 } })
    const result = resolveAttack(request({ target }), new FakeTables(), new FixedRng([8, 4, 4, 4]))
    expect(kinds(result)).toContain('seriously_wounded')
  })

  it('does not emit seriously wounded when landing exactly on the threshold', () => {
    const target = createTargetState({ targetId: 'goon', hp: 21, maxHp: 40, armor: { body: 0 } })
    const weapon = createWeapon({ name: 'Needler', weaponType: 'pistol', damageDice: 1 })
    const result = resolveAttack(request({ target, weapon }), new FakeTables(), new FixedRng([8, 1]))
    expect(result.hpDamage).toBe(1)
    expect(kinds(result)).not.toContain('seriously_wounded')
  })

  it('emits a death save when HP reaches zero', () => {
    const target = createTargetState({ targetId: 'goon', hp: 5, maxHp: 40, armor: { body: 0 } })
    const result = resolveAttack(request({ target }), new FakeTables(), new FixedRng([8, 4, 4, 4]))
    expect(kinds(result)).toContain('death_save_due')
  })
})

describe('weapon handling', () => {
  it('refuses to attack with an empty weapon', () => {
    expect(() => resolveAttack(request({ ammo: 0 }), new FakeTables(), new FixedRng([]))).toThrow(
      /empty/,
    )
  })

  it('freezes its inputs', () => {
    const attack = request()
    expect(() => {
      ;(attack as { ammo: number }).ammo = 7
    }).toThrow(TypeError)
  })

  it('caps the autofire multiplier by margin and spends ten rounds', () => {
    const weapon = createWeapon({
      name: 'Assault Rifle',
      weaponType: 'assault_rifle',
      damageDice: 5,
      magazine: 25,
      autofireRating: 4,
    })
    const result = resolveAttack(
      request({ weapon, mode: 'autofire', attackBase: 17, ammo: 25 }),
      new FakeTables(17),
      new FixedRng([5, 3, 4]),
    )
    expect(result.rawDamage).toBe(28)
    expect(result.events[0]?.amount).toBe(10)
  })

  it('jams a poor weapon when the attack check rolls a one', () => {
    const weapon = createWeapon({
      name: 'Junker',
      weaponType: 'pistol',
      damageDice: 2,
      quality: 'poor',
    })
    const result = resolveAttack(request({ weapon }), new FakeTables(30), new FixedRng([1, 4]))
    expect(kinds(result)).toContain('weapon_jammed')
  })
})

describe('called shots at limbs', () => {
  it('uses the limb armor value and applies no multiplier', () => {
    const target = createTargetState({
      targetId: 'goon',
      hp: 30,
      maxHp: 40,
      armor: { body: 7, head: 7, left_arm: 2 },
    })
    const result = resolveAttack(
      request({ target, location: 'left_arm', mode: 'aimed', attackBase: 20 }),
      new FakeTables(),
      new FixedRng([8, 4, 4, 4]),
    )
    expect(result.armorSp).toBe(2)
    expect(result.armorDamage).toBe(10)
  })

  it('requires aimed mode for a called shot', () => {
    expect(() => request({ location: 'left_leg' })).toThrow(/aimed/)
  })
})

/**
 * Pure Cyberpunk RED combat resolution.
 *
 * This module performs no I/O and mutates neither the request nor the supplied
 * table provider. All state changes are described as events for a separate
 * applier (see `events.ts`).
 *
 * The constants below are working values carried over from the original Python
 * resolver, along with the page each was checked against. They are not a
 * substitute for checking a licensed copy of the book.
 */

import { damageRoll, rollCheck, type RandomSource, type Roll } from './dice'
import type { GameEvent } from './events'
import type { Tables } from './tables'

export const RULES = {
  hit_requires_meeting_dv: false, // core rulebook p. 172: defender wins a tie
  opposed_hit_requires_exceeding_dv: true, // core rulebook p. 129: defender wins a tie
  ablate_on_stopped_hit: false, // core rulebook p. 186: ablate only after damage
  crit_injury_bonus_damage: 5, // core rulebook p. 187
  critical_trigger_sixes: 2, // core rulebook p. 187
  headshot_multiplier: 2, // core rulebook p. 170: after head SP
  min_damage_through_armor: 0, // core rulebook p. 186
  aimed_shot_modifier: -8, // core rulebook p. 170
  autofire_ammo_cost: 10, // core rulebook p. 173
  autofire_damage_dice: 2, // core rulebook p. 173
  cover_blocks_overflow: true, // core rulebook p. 182
  poor_quality_jams_on_one: true, // core rulebook p. 342
  excellent_quality_attack_bonus: 1, // core rulebook p. 342
} as const

/**
 * Hit locations. The original resolver modelled only body and head; the limb
 * locations were added for the character sheet's per-location SP tracking and
 * resolve against their own armour value with no damage multiplier.
 */
export type Location = 'body' | 'head' | 'left_arm' | 'right_arm' | 'left_leg' | 'right_leg'
export type FireMode = 'single' | 'aimed' | 'autofire'
export type WeaponQuality = 'poor' | 'standard' | 'excellent'

export const HIT_LOCATIONS: readonly Location[] = [
  'head',
  'body',
  'left_arm',
  'right_arm',
  'left_leg',
  'right_leg',
]

/** Critical injury tables are printed for the body and the head only. */
export function injuryTableFor(location: Location): 'body' | 'head' {
  return location === 'head' ? 'head' : 'body'
}

export interface Weapon {
  readonly name: string
  readonly weaponType: string
  readonly damageDice: number
  readonly rof: number
  readonly magazine: number
  readonly autofireRating: number | null
  readonly quality: WeaponQuality
}

export interface TargetState {
  readonly targetId: string
  readonly hp: number
  readonly maxHp: number
  /** Armour SP per hit location. Missing locations count as SP 0. */
  readonly armor: Readonly<Partial<Record<Location, number>>>
  readonly coverHp: number
}

export interface AttackRequest {
  readonly attackerId: string
  readonly target: TargetState
  readonly weapon: Weapon
  readonly attackBase: number
  readonly distanceM: number
  readonly ammo: number
  readonly location: Location
  readonly mode: FireMode
  readonly defenderEvasionBase: number | null
  readonly modifiers: number
}

export interface AttackResult {
  readonly hit: boolean
  readonly attackRoll: Roll
  readonly attackTotal: number
  readonly defense: number
  readonly defenseKind: 'range' | 'evasion'
  readonly damageRolls: readonly number[]
  readonly rawDamage: number
  readonly armorSp: number
  readonly armorDamage: number
  readonly hpDamage: number
  readonly criticalInjury: string | null
  readonly events: readonly GameEvent[]
  readonly cardLines: readonly string[]
}

export function createWeapon(input: {
  name: string
  weaponType: string
  damageDice: number
  rof?: number
  magazine?: number
  autofireRating?: number | null
  quality?: WeaponQuality
}): Weapon {
  const weapon: Weapon = {
    name: input.name,
    weaponType: input.weaponType,
    damageDice: input.damageDice,
    rof: input.rof ?? 1,
    magazine: input.magazine ?? 1,
    autofireRating: input.autofireRating ?? null,
    quality: input.quality ?? 'standard',
  }
  if (weapon.damageDice <= 0) throw new Error('damageDice must be positive')
  if (weapon.rof <= 0) throw new Error('rof must be positive')
  if (weapon.magazine <= 0) throw new Error('magazine must be positive')
  if (weapon.autofireRating !== null && weapon.autofireRating <= 0) {
    throw new Error('autofireRating must be positive')
  }
  return Object.freeze(weapon)
}

export function createTargetState(input: {
  targetId: string
  hp: number
  maxHp: number
  armor?: Partial<Record<Location, number>>
  coverHp?: number
}): TargetState {
  const armor = { ...(input.armor ?? {}) }
  const target: TargetState = {
    targetId: input.targetId,
    hp: input.hp,
    maxHp: input.maxHp,
    armor: Object.freeze(armor),
    coverHp: input.coverHp ?? 0,
  }
  if (target.maxHp <= 0) throw new Error('maxHp must be positive')
  if (target.hp > target.maxHp) throw new Error('hp cannot exceed maxHp')
  if (target.coverHp < 0) throw new Error('SP and cover HP cannot be negative')
  for (const value of Object.values(armor)) {
    if (value < 0) throw new Error('SP and cover HP cannot be negative')
  }
  return Object.freeze(target)
}

export function createAttackRequest(input: {
  attackerId: string
  target: TargetState
  weapon: Weapon
  attackBase: number
  distanceM: number
  ammo: number
  location?: Location
  mode?: FireMode
  defenderEvasionBase?: number | null
  modifiers?: number
}): AttackRequest {
  const request: AttackRequest = {
    attackerId: input.attackerId,
    target: input.target,
    weapon: input.weapon,
    attackBase: input.attackBase,
    distanceM: input.distanceM,
    ammo: input.ammo,
    location: input.location ?? 'body',
    mode: input.mode ?? 'single',
    defenderEvasionBase: input.defenderEvasionBase ?? null,
    modifiers: input.modifiers ?? 0,
  }
  if (request.distanceM < 0) throw new Error('distanceM cannot be negative')
  if (request.ammo < 0) throw new Error('ammo cannot be negative')
  if (request.location !== 'body' && request.mode !== 'aimed') {
    throw new Error('a called shot must use aimed mode')
  }
  if (request.mode === 'autofire' && request.weapon.autofireRating === null) {
    throw new Error('weapon does not support autofire')
  }
  return Object.freeze(request)
}

function meetsDefense(total: number, defense: number, kind: 'range' | 'evasion'): boolean {
  if (kind === 'evasion') {
    return RULES.opposed_hit_requires_exceeding_dv ? total > defense : total >= defense
  }
  return RULES.hit_requires_meeting_dv ? total >= defense : total > defense
}

/** Resolve one ranged attack and return descriptive events. */
export function resolveAttack(
  request: AttackRequest,
  tables: Tables,
  rng: RandomSource,
): AttackResult {
  const ammoCost = request.mode === 'autofire' ? RULES.autofire_ammo_cost : 1
  if (request.ammo < ammoCost) throw new Error('cannot attack with an empty weapon')

  const events: GameEvent[] = [
    {
      kind: 'ammo_spent',
      actor_id: request.attackerId,
      weapon: request.weapon.name,
      amount: ammoCost,
    },
  ]

  const check = rollCheck(rng)
  const aimedModifier = request.mode === 'aimed' ? RULES.aimed_shot_modifier : 0
  const qualityModifier =
    request.weapon.quality === 'excellent' ? RULES.excellent_quality_attack_bonus : 0
  const attackTotal =
    request.attackBase + request.modifiers + aimedModifier + qualityModifier + check.total

  if (request.weapon.quality === 'poor' && check.rolls[0] === 1 && RULES.poor_quality_jams_on_one) {
    events.push({
      kind: 'weapon_jammed',
      actor_id: request.attackerId,
      weapon: request.weapon.name,
    })
  }

  let defenseKind: 'range' | 'evasion'
  let defense: number
  let defenseCard: string
  if (request.defenderEvasionBase === null) {
    defenseKind = 'range'
    defense =
      request.mode === 'autofire'
        ? tables.autofireDv(request.weapon.weaponType, request.distanceM)
        : tables.rangedDv(request.weapon.weaponType, request.distanceM)
    defenseCard = `DV ${defense} (range)`
  } else {
    defenseKind = 'evasion'
    const defenseRoll = rollCheck(rng)
    defense = request.defenderEvasionBase + defenseRoll.total
    defenseCard = `Defense ${defense} (evasion)`
  }

  const attackCard =
    `Attack: base ${request.attackBase} + d10 ${check.total}` +
    ` + modifiers ${request.modifiers + aimedModifier + qualityModifier} = ${attackTotal}`

  if (!meetsDefense(attackTotal, defense, defenseKind)) {
    events.push({
      kind: 'attack_missed',
      actor_id: request.attackerId,
      target_id: request.target.targetId,
    })
    return {
      hit: false,
      attackRoll: check,
      attackTotal,
      defense,
      defenseKind,
      damageRolls: [],
      rawDamage: 0,
      armorSp: 0,
      armorDamage: 0,
      hpDamage: 0,
      criticalInjury: null,
      events,
      cardLines: [attackCard, defenseCard, 'MISS'],
    }
  }

  const damageDice =
    request.mode === 'autofire' ? RULES.autofire_damage_dice : request.weapon.damageDice
  const damage = damageRoll(damageDice, rng)
  let multiplier = 1
  if (request.mode === 'autofire') {
    multiplier = tables.autofireMultiplier(attackTotal - defense, request.weapon.autofireRating)
  }
  const rawDamage = damage.total * multiplier
  let damageText = `Damage: ${damage.rolls.join(' + ')} = ${damage.total}`
  if (multiplier !== 1) damageText += `; x ${multiplier} = ${rawDamage}`
  const cardLines = [attackCard, defenseCard, damageText]

  // Cover is binary in RED: it takes the hit instead of the target. Damage in
  // excess of the cover's remaining HP does not pass through this attack.
  if (request.target.coverHp > 0) {
    events.push({
      kind: 'cover_damaged',
      target_id: request.target.targetId,
      amount: rawDamage,
    })
    const remainingCover = Math.max(0, request.target.coverHp - rawDamage)
    cardLines.push(`Cover: ${request.target.coverHp} HP - ${rawDamage} = ${remainingCover} HP`)
    return {
      hit: true,
      attackRoll: check,
      attackTotal,
      defense,
      defenseKind,
      damageRolls: damage.rolls,
      rawDamage,
      armorSp: 0,
      armorDamage: 0,
      hpDamage: 0,
      criticalInjury: null,
      events,
      cardLines,
    }
  }

  const armorSp = request.target.armor[request.location] ?? 0
  const penetrates = rawDamage > armorSp
  const afterArmor = penetrates
    ? Math.max(RULES.min_damage_through_armor, rawDamage - armorSp)
    : 0
  const locationMultiplier = request.location === 'head' ? RULES.headshot_multiplier : 1
  const armorDamage = afterArmor * locationMultiplier

  if (penetrates || RULES.ablate_on_stopped_hit) {
    events.push({
      kind: 'armor_ablated',
      target_id: request.target.targetId,
      location: request.location,
      amount: 1,
    })
  }

  let criticalInjury: string | null = null
  let criticalBonus = 0
  const sixes = damage.rolls.filter((value) => value === 6).length
  if (sixes >= RULES.critical_trigger_sixes) {
    const injuryRoll = damageRoll(2, rng)
    const injury = tables.criticalInjury(injuryTableFor(request.location), injuryRoll.total)
    criticalInjury = injury.name
    criticalBonus = RULES.crit_injury_bonus_damage
    events.push({
      kind: 'critical_injury',
      target_id: request.target.targetId,
      location: request.location,
      injury: criticalInjury,
      rolls: injuryRoll.rolls,
    })
  }

  const hpDamage = armorDamage + criticalBonus
  if (hpDamage) {
    events.push({
      kind: 'damage_taken',
      target_id: request.target.targetId,
      amount: hpDamage,
    })
  }

  const newHp = request.target.hp - hpDamage
  const seriousThreshold = Math.floor((request.target.maxHp - 1) / 2)
  if (request.target.hp > seriousThreshold && seriousThreshold >= newHp) {
    events.push({ kind: 'seriously_wounded', target_id: request.target.targetId })
  }
  if (newHp <= 0) {
    events.push({ kind: 'death_save_due', target_id: request.target.targetId })
  }

  cardLines.push(`Armor: ${rawDamage} - SP ${armorSp} = ${afterArmor}`)
  if (locationMultiplier !== 1) {
    cardLines.push(`Head: ${afterArmor} x ${locationMultiplier} = ${armorDamage}`)
  }
  if (criticalBonus) {
    cardLines.push(`Critical Injury (${criticalInjury}): +${criticalBonus} direct HP`)
  }
  cardLines.push(`HP damage: ${armorDamage} + ${criticalBonus} = ${hpDamage}`)

  return {
    hit: true,
    attackRoll: check,
    attackTotal,
    defense,
    defenseKind,
    damageRolls: damage.rolls,
    rawDamage,
    armorSp,
    armorDamage,
    hpDamage,
    criticalInjury,
    events,
    cardLines,
  }
}

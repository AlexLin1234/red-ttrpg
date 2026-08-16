/**
 * Interfaces and the JSON adapter for rules tables.
 *
 * No book data ships with Redline. The app boots on the homebrew placeholder set
 * in `tables.default.ts`; a GM who owns the book can replace any value in the
 * in-app editor or import a JSON file. The document shape below is unchanged
 * from the original tool, so an operator's existing `tables.json` imports as-is.
 */

export interface RangeBand {
  min_m: number
  max_m: number
  dv: number | null
}

export interface WeaponProfile {
  name: string
  range_type: string
  skill: string
  damage_dice: number
  magazine: number | null
  rof: number
  hands: number
  concealable: boolean
  autofire_rating: number | null
  page: number
}

export interface ArmorProfile {
  name: string
  sp: number
  penalty: Record<string, number>
  page: number
}

export interface CriticalInjuryRef {
  name: string
  page: number
}

export interface CoverExample {
  hp: number
  sp: number
  page: number
}

export interface TablesDocument {
  /** Freeform provenance note shown in the editor, e.g. "homebrew placeholder". */
  source?: string
  ranged_dv: Record<string, RangeBand[]>
  autofire_dv: Record<string, RangeBand[]>
  weapons: Record<string, Omit<WeaponProfile, 'name'>>
  armor: Record<string, Omit<ArmorProfile, 'name'>>
  aimed_shots: Record<string, { modifier: number; page: number }>
  cover: Record<string, CoverExample>
  critical_injuries: {
    body: Record<string, CriticalInjuryRef>
    head: Record<string, CriticalInjuryRef>
  }
}

/** The narrow surface the resolver depends on. */
export interface Tables {
  rangedDv(weaponType: string, distanceM: number): number
  autofireDv(weaponType: string, distanceM: number): number
  autofireMultiplier(margin: number, rating: number | null): number
  criticalInjury(location: 'body' | 'head', roll: number): CriticalInjuryRef
}

export class JsonTables implements Tables {
  constructor(readonly data: TablesDocument) {}

  private band(
    group: Record<string, RangeBand[]>,
    weaponType: string,
    distanceM: number,
    missingMessage: string,
    noBandMessage: string,
  ): number {
    if (distanceM < 0) throw new Error('distanceM cannot be negative')
    const bands = group[weaponType]
    if (!bands) throw new Error(`${missingMessage}: ${weaponType}`)
    for (const entry of bands) {
      if (entry.min_m <= distanceM && distanceM <= entry.max_m) {
        if (entry.dv === null) break
        return entry.dv
      }
    }
    throw new Error(`${weaponType} ${noBandMessage} at ${distanceM} m`)
  }

  rangedDv(weaponType: string, distanceM: number): number {
    return this.band(
      this.data.ranged_dv,
      weaponType,
      distanceM,
      'unknown weapon type',
      'has no valid range band',
    )
  }

  autofireDv(weaponType: string, distanceM: number): number {
    return this.band(
      this.data.autofire_dv,
      weaponType,
      distanceM,
      'weapon type does not support autofire',
      'has no autofire range band',
    )
  }

  autofireMultiplier(margin: number, rating: number | null): number {
    if (margin < 1) throw new Error('autofire margin must be positive')
    if (rating === null || rating < 1) throw new Error('autofire rating must be positive')
    return Math.min(margin, rating)
  }

  criticalInjury(location: 'body' | 'head', roll: number): CriticalInjuryRef {
    if (location !== 'body' && location !== 'head') {
      throw new Error(`invalid injury location: ${location}`)
    }
    if (roll < 2 || roll > 12) throw new Error('critical injury roll must be between 2 and 12')
    const entry = this.data.critical_injuries[location][String(roll)]
    if (!entry) throw new Error(`missing ${location} critical injury roll ${roll}`)
    return entry
  }

  weapon(name: string): WeaponProfile {
    const entry = this.data.weapons[name]
    if (!entry) throw new Error(`unknown weapon: ${name}`)
    return { name, ...entry }
  }

  weaponNames(): string[] {
    return Object.keys(this.data.weapons)
  }

  armor(name: string): ArmorProfile {
    const entry = this.data.armor[name]
    if (!entry) throw new Error(`unknown armor: ${name}`)
    return { name, ...entry }
  }

  aimedShot(location: string): { modifier: number; page: number } {
    const entry = this.data.aimed_shots[location]
    if (!entry) throw new Error(`unknown aimed-shot location: ${location}`)
    return entry
  }

  cover(example: string): CoverExample {
    const entry = this.data.cover[example]
    if (!entry) throw new Error(`unknown cover example: ${example}`)
    return entry
  }
}

/**
 * Validate an imported document before it replaces the active tables. Returns
 * the list of problems; empty means the file is usable.
 */
export function validateTablesDocument(value: unknown): string[] {
  const problems: string[] = []
  if (typeof value !== 'object' || value === null) return ['file is not a JSON object']
  const doc = value as Partial<TablesDocument>

  for (const key of ['ranged_dv', 'autofire_dv', 'weapons', 'critical_injuries'] as const) {
    if (!doc[key] || typeof doc[key] !== 'object') problems.push(`missing "${key}" section`)
  }
  if (doc.critical_injuries) {
    for (const location of ['body', 'head'] as const) {
      const table = doc.critical_injuries[location]
      if (!table) {
        problems.push(`missing "${location}" critical injury table`)
        continue
      }
      for (let roll = 2; roll <= 12; roll += 1) {
        if (!table[String(roll)]) problems.push(`${location} critical injuries missing roll ${roll}`)
      }
    }
  }
  for (const [name, profile] of Object.entries(doc.weapons ?? {})) {
    if (!profile || profile.damage_dice <= 0) problems.push(`${name}: damage_dice must be positive`)
    if (!profile || profile.rof <= 0) problems.push(`${name}: rof must be positive`)
  }
  return problems
}

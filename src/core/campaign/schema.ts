/**
 * The shape of everything inside a `.red` campaign file.
 *
 * A save is a zip; each interface below is one JSON entry in it. Keeping the
 * pieces separate means the library screen can read `manifest.json` and
 * `campaign.json` alone to draw a card, without parsing a 200 MB campaign's
 * every location.
 */

import type { Location } from '../rules/resolver'
import type { TablesDocument } from '../rules/tables'

export const SAVE_FORMAT = 'redline-campaign'
export const SAVE_VERSION = '0.4'

export interface ManifestEntry {
  /** Lowercase hex SHA-256 of the entry's bytes. */
  sha256: string
  bytes: number
}

export interface CampaignManifest {
  format: typeof SAVE_FORMAT
  version: string
  created: string
  updated: string
  sessions: number
  entries: Record<string, ManifestEntry>
}

export interface WorldClock {
  year: number
  /** 1-12. */
  month: number
  /** 1-31. */
  day: number
  /** 0-23. */
  hour: number
  /** 0-59. */
  minute: number
}

export interface Weather {
  condition: string
  temperatureC: number
  visibilityPct: number
}

export interface SessionLogEntry {
  session: number
  text: string
}

export interface JobHook {
  id: string
  districtId: string
  title: string
  detail: string
  status: 'open' | 'running' | 'closed'
}

/** GM-authored overrides on top of the built-in district data. */
export interface DistrictOverride {
  control?: string
  danger?: number
  heat?: number
  note?: string
}

export const STAT_KEYS = [
  'INT',
  'REF',
  'DEX',
  'TECH',
  'COOL',
  'WILL',
  'LUCK',
  'MOVE',
  'BODY',
  'EMP',
] as const
export type StatKey = (typeof STAT_KEYS)[number]

export interface Skill {
  name: string
  /** The stat this skill is rolled against. */
  stat: StatKey
  level: number
}

export interface GearItem {
  name: string
  kind: 'weapon' | 'cyberware' | 'armor' | 'gear'
  detail?: string
  /** Humanity cost, for cyberware. */
  humanityCost?: number
}

export interface ArmorSlot {
  sp: number
  ablated: boolean
}

export interface CharacterWeapon {
  name: string
  ammo: number
  magazine?: number
  weaponType?: string
  damageDice?: number
  rof?: number
  autofireRating?: number | null
  quality?: 'poor' | 'standard' | 'excellent'
  jammed?: boolean
}

export interface Character {
  id: string
  name: string
  role: string
  kind: 'pc' | 'npc' | 'mook'
  side: 'party' | 'hostile' | 'neutral'
  tags: string[]
  stats: Record<StatKey, number>
  skills: Skill[]
  gear: GearItem[]
  armor: Record<Location, ArmorSlot>
  hp: number
  maxHp: number
  humanity: number
  maxHumanity: number
  weapons: CharacterWeapon[]
  notes?: string
}

export interface Roster {
  characters: Character[]
}

/** A cover prop authored in the forge and placed on the board. */
export interface CoverDefinition {
  id: string
  name: string
  material: string
  /** Metres. */
  height: number
  width: number
  depth: number
  sp: number
  hp: number
  destructible: boolean
}

export interface BoardTile {
  x: number
  z: number
  layer: number
  tileId: string
  rotation: number
}

export interface BoardProp {
  id: string
  coverId: string
  x: number
  z: number
  layer: number
  rotation: number
  hp: number
}

export interface BoardUnit {
  id: string
  characterId: string
  x: number
  z: number
  layer: number
}

export interface GameLocation {
  id: string
  name: string
  districtId: string
  gridWidth: number
  gridHeight: number
  tileMetres: number
  layers: number
  tiles: BoardTile[]
  props: BoardProp[]
  units: BoardUnit[]
}

export interface RestorePoint {
  id: string
  label: string
  session: number
  createdAt: string
}

export interface Campaign {
  id: string
  name: string
  arc: string
  city: string
  gm: string
  players: number
  sessions: number
  clock: WorldClock
  weather: Weather
  sessionLog: SessionLogEntry[]
  hooks: JobHook[]
  districts: Record<string, DistrictOverride>
  coverPalette: CoverDefinition[]
  restorePoints: RestorePoint[]
  /** Table overrides layered on top of the shipped defaults. */
  tables?: TablesDocument
}

/** Everything a loaded campaign holds in memory. */
export interface CampaignBundle {
  manifest: CampaignManifest
  campaign: Campaign
  roster: Roster
  locations: GameLocation[]
}

/**
 * The HP at or below which an actor is Seriously Wounded.
 *
 * Shared by the character sheet and the resolver so the sheet can never
 * disagree with the combat math. The resolver's rule is `(maxHp - 1) / 2`
 * rounded down; change it here and both follow.
 */
export function seriousWoundThreshold(maxHp: number): number {
  return Math.floor((maxHp - 1) / 2)
}

export function emptyArmor(): Record<Location, ArmorSlot> {
  return {
    head: { sp: 0, ablated: false },
    body: { sp: 0, ablated: false },
    left_arm: { sp: 0, ablated: false },
    right_arm: { sp: 0, ablated: false },
    left_leg: { sp: 0, ablated: false },
    right_leg: { sp: 0, ablated: false },
  }
}

export function emptyStats(): Record<StatKey, number> {
  return Object.fromEntries(STAT_KEYS.map((key) => [key, 4])) as Record<StatKey, number>
}

export function pointsSpent(stats: Record<StatKey, number>): number {
  return STAT_KEYS.reduce((sum, key) => sum + (stats[key] ?? 0), 0)
}

/** Cyberware humanity cost, summed off the gear list. */
export function humanitySpent(gear: readonly GearItem[]): number {
  return gear.reduce((sum, item) => sum + (item.humanityCost ?? 0), 0)
}

export function formatClock(clock: WorldClock): string {
  const hh = String(clock.hour).padStart(2, '0')
  const mm = String(clock.minute).padStart(2, '0')
  return `${hh}:${mm}`
}

const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC']
const WEEKDAYS = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT']

export function formatDate(clock: WorldClock): string {
  const date = new Date(Date.UTC(clock.year, clock.month - 1, clock.day))
  const weekday = WEEKDAYS[date.getUTCDay()] ?? 'FRI'
  return `${weekday} ${clock.day} ${MONTHS[clock.month - 1] ?? 'JAN'} ${clock.year}`
}

/** Night City runs three shifts; the header names the one the clock is in. */
export function shiftOf(clock: WorldClock): { label: string; shift: number } {
  if (clock.hour < 8) return { label: 'NIGHT', shift: 3 }
  if (clock.hour < 16) return { label: 'DAY', shift: 1 }
  return { label: 'EVENING', shift: 2 }
}

export function advanceClock(clock: WorldClock, minutes: number): WorldClock {
  const base = Date.UTC(clock.year, clock.month - 1, clock.day, clock.hour, clock.minute)
  const moved = new Date(base + minutes * 60_000)
  return {
    year: moved.getUTCFullYear(),
    month: moved.getUTCMonth() + 1,
    day: moved.getUTCDate(),
    hour: moved.getUTCHours(),
    minute: moved.getUTCMinutes(),
  }
}

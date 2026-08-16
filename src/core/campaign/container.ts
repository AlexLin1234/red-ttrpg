/**
 * Reading and writing the `.red` campaign container.
 *
 * A save is a zip so the mockup's save-file panel can tell the truth: the file
 * has a real size on disk, a real format version, and a per-entry SHA-256 in the
 * manifest that either matches the bytes or does not. "INTEGRITY: VERIFIED" is a
 * check, not a decoration.
 */

import { unzipSync, zipSync } from 'fflate'

import {
  SAVE_FORMAT,
  SAVE_VERSION,
  type Campaign,
  type CampaignBundle,
  type CampaignManifest,
  type GameLocation,
  type ManifestEntry,
  type Roster,
} from './schema'

const MANIFEST = 'manifest.json'
const CAMPAIGN = 'campaign.json'
const ROSTER = 'roster.json'
const LOCATION_PREFIX = 'locations/'

const encoder = new TextEncoder()
const decoder = new TextDecoder()

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const buffer = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer
  const digest = await crypto.subtle.digest('SHA-256', buffer)
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

function encodeJson(value: unknown): Uint8Array {
  return encoder.encode(JSON.stringify(value, null, 2))
}

function decodeJson<T>(bytes: Uint8Array, what: string): T {
  try {
    return JSON.parse(decoder.decode(bytes)) as T
  } catch (error) {
    throw new Error(`${what} is not valid JSON: ${(error as Error).message}`)
  }
}

/** Pack a bundle into `.red` bytes, recomputing the manifest as it goes. */
export async function packCampaign(
  bundle: Omit<CampaignBundle, 'manifest'> & { manifest?: Partial<CampaignManifest> },
): Promise<Uint8Array> {
  const files: Record<string, Uint8Array> = {
    [CAMPAIGN]: encodeJson(bundle.campaign),
    [ROSTER]: encodeJson(bundle.roster),
  }
  for (const location of bundle.locations) {
    files[`${LOCATION_PREFIX}${location.id}.json`] = encodeJson(location)
  }

  const entries: Record<string, ManifestEntry> = {}
  for (const [name, bytes] of Object.entries(files)) {
    entries[name] = { sha256: await sha256Hex(bytes), bytes: bytes.byteLength }
  }

  const now = new Date().toISOString()
  const manifest: CampaignManifest = {
    format: SAVE_FORMAT,
    version: SAVE_VERSION,
    created: bundle.manifest?.created ?? now,
    updated: now,
    sessions: bundle.campaign.sessions,
    entries,
  }

  return zipSync({ [MANIFEST]: encodeJson(manifest), ...files }, { level: 6 })
}

export interface IntegrityReport {
  verified: boolean
  problems: string[]
}

export interface LoadedCampaign extends CampaignBundle {
  integrity: IntegrityReport
}

/** Unpack `.red` bytes and check every entry against the manifest. */
export async function unpackCampaign(bytes: Uint8Array): Promise<LoadedCampaign> {
  let files: Record<string, Uint8Array>
  try {
    files = unzipSync(bytes)
  } catch (error) {
    throw new Error(`not a readable .red container: ${(error as Error).message}`)
  }

  const manifestBytes = files[MANIFEST]
  if (!manifestBytes) throw new Error('container has no manifest.json')
  const manifest = decodeJson<CampaignManifest>(manifestBytes, MANIFEST)
  if (manifest.format !== SAVE_FORMAT) {
    throw new Error(`unsupported save format: ${String(manifest.format)}`)
  }

  const campaignBytes = files[CAMPAIGN]
  if (!campaignBytes) throw new Error('container has no campaign.json')
  const rosterBytes = files[ROSTER]

  const locations: GameLocation[] = []
  for (const [name, entry] of Object.entries(files)) {
    if (name.startsWith(LOCATION_PREFIX) && name.endsWith('.json')) {
      locations.push(decodeJson<GameLocation>(entry, name))
    }
  }
  locations.sort((a, b) => a.name.localeCompare(b.name))

  const problems: string[] = []
  for (const [name, expected] of Object.entries(manifest.entries)) {
    const actual = files[name]
    if (!actual) {
      problems.push(`${name} is listed in the manifest but missing from the file`)
      continue
    }
    if (actual.byteLength !== expected.bytes) {
      problems.push(`${name} is ${actual.byteLength} bytes, manifest says ${expected.bytes}`)
      continue
    }
    if ((await sha256Hex(actual)) !== expected.sha256) {
      problems.push(`${name} does not match its manifest checksum`)
    }
  }
  for (const name of Object.keys(files)) {
    if (name !== MANIFEST && !manifest.entries[name]) {
      problems.push(`${name} is in the file but not listed in the manifest`)
    }
  }

  return {
    manifest,
    campaign: decodeJson<Campaign>(campaignBytes, CAMPAIGN),
    roster: rosterBytes ? decodeJson<Roster>(rosterBytes, ROSTER) : { characters: [] },
    locations,
    integrity: { verified: problems.length === 0, problems },
  }
}

export interface CampaignSummary {
  name: string
  arc: string
  city: string
  players: number
  sessions: number
  version: string
  created: string
  updated: string
  locations: number
  npcs: number
  characters: number
  encounters: number
}

/**
 * The library list needs a card per save, not a whole campaign. This reads only
 * the two small entries it needs and skips the location payloads.
 */
export async function readSummary(bytes: Uint8Array): Promise<CampaignSummary> {
  const files = unzipSync(bytes, {
    filter: (file) => file.name === MANIFEST || file.name === CAMPAIGN || file.name === ROSTER,
  })
  const manifestBytes = files[MANIFEST]
  const campaignBytes = files[CAMPAIGN]
  if (!manifestBytes || !campaignBytes) throw new Error('container is missing its index entries')
  const manifest = decodeJson<CampaignManifest>(manifestBytes, MANIFEST)
  const campaign = decodeJson<Campaign>(campaignBytes, CAMPAIGN)
  const rosterBytes = files[ROSTER]
  const roster = rosterBytes ? decodeJson<Roster>(rosterBytes, ROSTER) : { characters: [] }

  const locations = Object.keys(manifest.entries).filter(
    (name) => name.startsWith(LOCATION_PREFIX) && name.endsWith('.json'),
  ).length

  return {
    name: campaign.name,
    arc: campaign.arc,
    city: campaign.city,
    players: campaign.players,
    sessions: campaign.sessions,
    version: manifest.version,
    created: manifest.created,
    updated: manifest.updated,
    locations,
    npcs: roster.characters.filter((character) => character.kind !== 'pc').length,
    characters: roster.characters.length,
    encounters: campaign.hooks.filter((hook) => hook.status !== 'closed').length,
  }
}

/** `blackwall_sunrise.red` from "Blackwall Sunrise". */
export function suggestFileName(campaignName: string): string {
  const slug = campaignName
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
  return `${slug || 'campaign'}.red`
}

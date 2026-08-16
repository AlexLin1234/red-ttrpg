/**
 * Demo content.
 *
 * "Blackwall Sunrise" is the campaign shown throughout the UI mockups. It seeds
 * a fresh install so every screen has something real to draw, and it is what the
 * end-to-end tests drive. The lighter saves exist to fill the library list.
 */

import {
  emptyArmor,
  type ArmorSlot,
  type Campaign,
  type CampaignBundle,
  type Character,
  type CoverDefinition,
  type GameLocation,
  type Roster,
  type SessionLogEntry,
  type Skill,
  type StatKey,
} from './schema'
import type { Location } from '../rules/resolver'

function stats(values: Partial<Record<StatKey, number>>): Record<StatKey, number> {
  return {
    INT: 5,
    REF: 5,
    DEX: 5,
    TECH: 4,
    COOL: 5,
    WILL: 5,
    LUCK: 4,
    MOVE: 5,
    BODY: 5,
    EMP: 5,
    ...values,
  }
}

function armor(sp: number, ablated: Partial<Record<Location, number>> = {}): Record<Location, ArmorSlot> {
  const slots = emptyArmor()
  for (const key of Object.keys(slots) as Location[]) {
    const override = ablated[key]
    slots[key] =
      override === undefined ? { sp, ablated: false } : { sp: override, ablated: true }
  }
  return slots
}

function skills(entries: readonly [string, StatKey, number][]): Skill[] {
  return entries.map(([name, stat, level]) => ({ name, stat, level }))
}

export function skillTotal(character: Character, skill: Skill): number {
  return (character.stats[skill.stat] ?? 0) + skill.level
}

const COVER_PALETTE: CoverDefinition[] = [
  {
    id: 'cover-jersey',
    name: 'Concrete Jersey Barrier',
    material: 'Concrete',
    height: 1.2,
    width: 2,
    depth: 1,
    sp: 15,
    hp: 30,
    destructible: true,
  },
  {
    id: 'cover-crate',
    name: 'Market Crate',
    material: 'Wood Crate',
    height: 1.1,
    width: 1.2,
    depth: 1.2,
    sp: 5,
    hp: 12,
    destructible: true,
  },
  {
    id: 'cover-hulk',
    name: 'Burned-Out Hatchback',
    material: 'Vehicle Hulk',
    height: 1.5,
    width: 4,
    depth: 1.8,
    sp: 12,
    hp: 50,
    destructible: true,
  },
  {
    id: 'cover-pillar',
    name: 'Parkade Pillar',
    material: 'Concrete',
    height: 3,
    width: 0.8,
    depth: 0.8,
    sp: 15,
    hp: 30,
    destructible: false,
  },
  {
    id: 'cover-vending',
    name: 'Vending Kiosk',
    material: 'Sheet Metal',
    height: 2,
    width: 1,
    depth: 0.8,
    sp: 7,
    hp: 15,
    destructible: true,
  },
]

function partyMembers(): Character[] {
  return [
    {
      id: 'spike',
      name: 'Spike Adebayo',
      role: 'Solo',
      kind: 'pc',
      side: 'party',
      tags: ['PC', 'RECURRING'],
      stats: stats({ INT: 6, REF: 7, DEX: 7, TECH: 4, COOL: 6, WILL: 6, LUCK: 5, MOVE: 6, BODY: 8, EMP: 4 }),
      skills: skills([
        ['Handgun', 'REF', 6],
        ['Shoulder Arms', 'REF', 4],
        ['Evasion', 'DEX', 5],
        ['Athletics', 'BODY', 4],
        ['Perception', 'INT', 4],
      ]),
      gear: [
        { name: 'Heavy Sidearm', kind: 'weapon', detail: '3d6' },
        { name: 'Light Plate', kind: 'armor', detail: 'SP11' },
        { name: 'Kerenzikov', kind: 'cyberware', detail: '+2 initiative', humanityCost: 7 },
      ],
      armor: armor(11),
      hp: 42,
      maxHp: 45,
      humanity: 32,
      maxHumanity: 40,
      weapons: [
        { name: 'Heavy Sidearm', ammo: 8, magazine: 8, weaponType: 'pistol', damageDice: 3, rof: 2 },
      ],
    },
    {
      id: 'mira',
      name: 'Mira Vega',
      role: 'Netrunner',
      kind: 'pc',
      side: 'party',
      tags: ['PC', 'JACKED IN'],
      stats: stats({ INT: 8, REF: 6, DEX: 6, TECH: 7, COOL: 5, WILL: 6, LUCK: 6, MOVE: 5, BODY: 5, EMP: 5 }),
      skills: skills([
        ['Interface', 'INT', 6],
        ['Handgun', 'REF', 3],
        ['Evasion', 'DEX', 4],
        ['Perception', 'INT', 5],
        ['Electronics', 'TECH', 5],
      ]),
      gear: [
        { name: 'Service Sidearm', kind: 'weapon', detail: '2d6' },
        { name: 'Kevlar Weave', kind: 'armor', detail: 'SP7' },
        { name: 'Neural Link', kind: 'cyberware', detail: 'interface plugs', humanityCost: 2 },
      ],
      armor: armor(7),
      hp: 28,
      maxHp: 38,
      humanity: 40,
      maxHumanity: 50,
      weapons: [
        { name: 'Service Sidearm', ammo: 12, magazine: 12, weaponType: 'pistol', damageDice: 2, rof: 2 },
      ],
    },
    {
      id: 'tallow',
      name: 'Doc Tallow',
      role: 'Medtech',
      kind: 'pc',
      side: 'party',
      tags: ['PC', 'SERIOUSLY WOUNDED'],
      stats: stats({ INT: 7, REF: 5, DEX: 6, TECH: 8, COOL: 5, WILL: 6, LUCK: 4, MOVE: 5, BODY: 6, EMP: 7 }),
      skills: skills([
        ['First Aid', 'TECH', 6],
        ['Surgery', 'TECH', 5],
        ['Handgun', 'REF', 3],
        ['Perception', 'INT', 4],
        ['Evasion', 'DEX', 3],
      ]),
      gear: [
        { name: 'Light Sidearm', kind: 'weapon', detail: '1d6' },
        { name: 'Kevlar Weave', kind: 'armor', detail: 'SP7' },
        { name: 'Medscanner', kind: 'gear' },
      ],
      armor: armor(7),
      hp: 11,
      maxHp: 40,
      humanity: 38,
      maxHumanity: 50,
      weapons: [
        { name: 'Light Sidearm', ammo: 12, magazine: 12, weaponType: 'pistol', damageDice: 1, rof: 2 },
      ],
    },
    {
      id: 'brick',
      name: 'Brick Osei',
      role: 'Solo',
      kind: 'pc',
      side: 'party',
      tags: ['PC', 'BORGWARE'],
      stats: stats({ INT: 5, REF: 7, DEX: 6, TECH: 4, COOL: 6, WILL: 7, LUCK: 4, MOVE: 6, BODY: 9, EMP: 3 }),
      skills: skills([
        ['Shoulder Arms', 'REF', 6],
        ['Melee Weapon', 'DEX', 5],
        ['Athletics', 'BODY', 5],
        ['Evasion', 'DEX', 3],
        ['Endurance', 'WILL', 4],
      ]),
      gear: [
        { name: 'Service Rifle', kind: 'weapon', detail: '5d6, autofire 4' },
        { name: 'Heavy Plate', kind: 'armor', detail: 'SP13' },
        { name: 'Subdermal Armor', kind: 'cyberware', detail: 'SP13', humanityCost: 7 },
      ],
      armor: armor(13),
      hp: 50,
      maxHp: 50,
      humanity: 28,
      maxHumanity: 40,
      weapons: [
        {
          name: 'Service Rifle',
          ammo: 25,
          magazine: 25,
          weaponType: 'assault_rifle',
          damageDice: 5,
          rof: 1,
          autofireRating: 4,
        },
      ],
    },
  ]
}

function nonPlayerCharacters(): Character[] {
  const mooks: Character[] = Array.from({ length: 12 }, (_, index) => ({
    id: `booster-${index + 1}`,
    name: `Booster ${index + 1}`,
    role: 'Mook',
    kind: 'mook' as const,
    side: 'hostile' as const,
    tags: ['MOOK', 'MAELSTROM'],
    stats: stats({ REF: 5, DEX: 5, BODY: 5, WILL: 4, COOL: 4, EMP: 3 }),
    skills: skills([
      ['Handgun', 'REF', 3],
      ['Evasion', 'DEX', 2],
    ]),
    gear: [{ name: 'Service Sidearm', kind: 'weapon' as const, detail: '2d6' }],
    armor: armor(4),
    hp: 25,
    maxHp: 25,
    humanity: 30,
    maxHumanity: 40,
    weapons: [
      { name: 'Service Sidearm', ammo: 12, magazine: 12, weaponType: 'pistol', damageDice: 2, rof: 2 },
    ],
  }))

  return [
    {
      id: 'ninevolt',
      name: 'Kestrel "Nine-Volt"',
      role: 'Solo — Maelstrom Lieutenant',
      kind: 'npc',
      side: 'hostile',
      tags: ['HOSTILE', 'RANK & SOLO', 'BORGWARE', 'RECURRING'],
      stats: stats({ INT: 5, REF: 8, DEX: 8, TECH: 4, COOL: 7, WILL: 7, LUCK: 3, MOVE: 7, BODY: 9, EMP: 2 }),
      skills: skills([
        ['Handgun', 'REF', 6],
        ['Shoulder Arms', 'REF', 5],
        ['Melee Weapon', 'REF', 6],
        ['Evasion', 'DEX', 5],
        ['Athletics', 'BODY', 4],
        ['Interrogation', 'COOL', 4],
        ['Perception', 'INT', 4],
      ]),
      gear: [
        { name: 'Hand Cannon', kind: 'weapon', detail: '4d6' },
        { name: 'Heavy SMG', kind: 'weapon', detail: '3d6, autofire 3' },
        { name: 'Monowire', kind: 'weapon', detail: '2d6 AP' },
        { name: 'Sandevistan', kind: 'cyberware', detail: '+3 initiative', humanityCost: 3 },
        { name: 'Kerenzikov', kind: 'cyberware', detail: '+2 initiative', humanityCost: 7 },
        { name: 'Subdermal Armor', kind: 'cyberware', detail: 'SP11', humanityCost: 7 },
        { name: 'Cybereye', kind: 'cyberware', detail: 'low-light', humanityCost: 2 },
      ],
      armor: armor(11, { left_arm: 7, right_leg: 9 }),
      hp: 45,
      maxHp: 45,
      humanity: 18,
      maxHumanity: 40,
      weapons: [
        { name: 'Hand Cannon', ammo: 8, magazine: 8, weaponType: 'pistol', damageDice: 4, rof: 1 },
        {
          name: 'Heavy SMG',
          ammo: 40,
          magazine: 40,
          weaponType: 'smg',
          damageDice: 3,
          rof: 1,
          autofireRating: 3,
        },
      ],
    },
    {
      id: 'ninetails',
      name: 'Ninetails',
      role: 'Fixer — Westbrook',
      kind: 'npc',
      side: 'neutral',
      tags: ['NPC', 'FIXER'],
      stats: stats({ INT: 7, REF: 5, DEX: 5, TECH: 5, COOL: 8, WILL: 6, LUCK: 7, MOVE: 5, BODY: 4, EMP: 7 }),
      skills: skills([
        ['Persuasion', 'COOL', 6],
        ['Streetwise', 'COOL', 6],
        ['Trading', 'INT', 5],
        ['Perception', 'INT', 4],
      ]),
      gear: [{ name: 'Light Sidearm', kind: 'weapon', detail: '1d6' }],
      armor: armor(4),
      hp: 30,
      maxHp: 30,
      humanity: 45,
      maxHumanity: 50,
      weapons: [
        { name: 'Light Sidearm', ammo: 12, magazine: 12, weaponType: 'pistol', damageDice: 1, rof: 2 },
      ],
    },
    {
      id: 'annika',
      name: 'Dr. Annika Ross',
      role: 'Ripperdoc — Watson',
      kind: 'npc',
      side: 'neutral',
      tags: ['NPC', 'RIPPERDOC'],
      stats: stats({ INT: 8, REF: 4, DEX: 6, TECH: 8, COOL: 5, WILL: 5, LUCK: 4, MOVE: 4, BODY: 4, EMP: 6 }),
      skills: skills([
        ['Surgery', 'TECH', 7],
        ['First Aid', 'TECH', 6],
        ['Perception', 'INT', 4],
      ]),
      gear: [{ name: 'Surgery Suite', kind: 'gear' }],
      armor: armor(0),
      hp: 28,
      maxHp: 28,
      humanity: 48,
      maxHumanity: 50,
      weapons: [],
    },
    {
      id: 'halvorsen',
      name: 'Sgt. Halvorsen',
      role: 'NCPD — City Center',
      kind: 'npc',
      side: 'neutral',
      tags: ['NPC', 'NCPD'],
      stats: stats({ INT: 6, REF: 7, DEX: 6, TECH: 4, COOL: 7, WILL: 7, LUCK: 4, MOVE: 6, BODY: 7, EMP: 5 }),
      skills: skills([
        ['Handgun', 'REF', 5],
        ['Shoulder Arms', 'REF', 4],
        ['Interrogation', 'COOL', 5],
        ['Perception', 'INT', 5],
      ]),
      gear: [
        { name: 'Service Sidearm', kind: 'weapon', detail: '2d6' },
        { name: 'Light Plate', kind: 'armor', detail: 'SP11' },
      ],
      armor: armor(11),
      hp: 40,
      maxHp: 40,
      humanity: 42,
      maxHumanity: 50,
      weapons: [
        { name: 'Service Sidearm', ammo: 12, magazine: 12, weaponType: 'pistol', damageDice: 2, rof: 2 },
      ],
    },
    {
      id: 'courier',
      name: 'The Courier',
      role: 'Plot — location unknown',
      kind: 'npc',
      side: 'neutral',
      tags: ['HOOK', 'PLOT'],
      stats: stats({ INT: 6, REF: 6, DEX: 7, TECH: 5, COOL: 6, WILL: 5, LUCK: 6, MOVE: 7, BODY: 5, EMP: 5 }),
      skills: skills([
        ['Athletics', 'BODY', 6],
        ['Stealth', 'DEX', 6],
        ['Evasion', 'DEX', 5],
      ]),
      gear: [{ name: 'Data Shard', kind: 'gear', detail: 'the Arasoma leak' }],
      armor: armor(4),
      hp: 30,
      maxHp: 30,
      humanity: 44,
      maxHumanity: 50,
      weapons: [],
    },
    ...mooks,
  ]
}

function sessionLog(): SessionLogEntry[] {
  return [
    { session: 14, text: 'Party breached the Kabuki parkade and lost the courier in the stairwell.' },
    { session: 14, text: 'Doc Tallow took 22 from an autofire burst — still at Seriously Wounded.' },
    { session: 13, text: 'Mira traced the Arasoma leak to a dead drop under the Pacifica pier.' },
    { session: 13, text: 'Maelstrom marked the party. Watson heat raised to 4.' },
    { session: 12, text: 'Fixer "Ninetails" advanced 3,000eb against the courier job.' },
  ]
}

/** The Kabuki parkade from mockup 1C: a two-level deck with pillars and wrecks. */
function kabukiParkade(): GameLocation {
  const tiles = []
  for (let x = 0; x < 20; x += 1) {
    for (let z = 0; z < 20; z += 1) {
      // A ramp bites a corner out of the deck, which the mockup shows as a gap.
      if (x > 15 && z > 15) continue
      tiles.push({ x, z, layer: 0, tileId: 'deck', rotation: 0 })
    }
  }

  const props = [
    { id: 'prop-pillar-a', coverId: 'cover-pillar', x: 6, z: 6, layer: 0, rotation: 0, hp: 30 },
    { id: 'prop-pillar-b', coverId: 'cover-pillar', x: 13, z: 6, layer: 0, rotation: 0, hp: 30 },
    { id: 'prop-pillar-c', coverId: 'cover-pillar', x: 6, z: 13, layer: 0, rotation: 0, hp: 30 },
    { id: 'prop-pillar-d', coverId: 'cover-pillar', x: 13, z: 13, layer: 0, rotation: 0, hp: 30 },
    { id: 'prop-jersey-a', coverId: 'cover-jersey', x: 9, z: 8, layer: 0, rotation: 0, hp: 30 },
    { id: 'prop-jersey-b', coverId: 'cover-jersey', x: 10, z: 12, layer: 0, rotation: 90, hp: 30 },
    { id: 'prop-hulk', coverId: 'cover-hulk', x: 15, z: 9, layer: 0, rotation: 0, hp: 50 },
    { id: 'prop-crate-a', coverId: 'cover-crate', x: 4, z: 10, layer: 0, rotation: 0, hp: 12 },
    { id: 'prop-kiosk', coverId: 'cover-vending', x: 17, z: 4, layer: 0, rotation: 0, hp: 15 },
  ]

  const units = [
    { id: 'unit-spike', characterId: 'spike', x: 4, z: 15, layer: 0 },
    { id: 'unit-mira', characterId: 'mira', x: 6, z: 17, layer: 0 },
    { id: 'unit-tallow', characterId: 'tallow', x: 3, z: 12, layer: 0 },
    { id: 'unit-ninevolt', characterId: 'ninevolt', x: 14, z: 5, layer: 0 },
    { id: 'unit-booster-1', characterId: 'booster-1', x: 12, z: 9, layer: 0 },
    { id: 'unit-booster-2', characterId: 'booster-2', x: 16, z: 11, layer: 0 },
  ]

  return {
    id: 'kabuki-parkade',
    name: 'Kabuki Parkade — Level 2',
    districtId: 'watson',
    gridWidth: 20,
    gridHeight: 20,
    tileMetres: 2,
    layers: 3,
    tiles,
    props,
    units,
  }
}

export function blackwallSunrise(): Omit<CampaignBundle, 'manifest'> {
  const roster: Roster = { characters: [...partyMembers(), ...nonPlayerCharacters()] }
  const campaign: Campaign = {
    id: 'blackwall-sunrise',
    name: 'Blackwall Sunrise',
    arc: 'Arc 2 "The Arasoma Leak"',
    city: 'Night City',
    gm: 'V. Okonkwo',
    players: 4,
    sessions: 14,
    clock: { year: 2045, month: 9, day: 14, hour: 21, minute: 47 },
    weather: { condition: 'Acid Rain', temperatureC: 18, visibilityPct: 40 },
    sessionLog: sessionLog(),
    hooks: [
      {
        id: 'hook-extraction',
        districtId: 'pacifica',
        title: 'Extraction',
        detail: 'Arasoma counter-grab goes dark tonight.',
        status: 'open',
      },
      {
        id: 'hook-pier',
        districtId: 'pacifica',
        title: 'Pier Generator',
        detail: 'Fixer wants the pier generator back online.',
        status: 'open',
      },
      {
        id: 'hook-courier',
        districtId: 'watson',
        title: 'The Courier',
        detail: 'Lost in the Kabuki parkade stairwell with the leak shard.',
        status: 'running',
      },
      {
        id: 'hook-heat',
        districtId: 'watson',
        title: 'Maelstrom Marker',
        detail: 'The party is marked. Heat 4 and climbing.',
        status: 'open',
      },
      {
        id: 'hook-audit',
        districtId: 'city-center',
        title: 'Internal Audit',
        detail: 'Arasoma is auditing its own leak. Someone inside is helping.',
        status: 'open',
      },
    ],
    districts: {
      watson: { heat: 4, note: 'Party marked by Maelstrom.' },
      pacifica: { note: 'Pier generator dark since session 12.' },
    },
    coverPalette: COVER_PALETTE,
    restorePoints: [
      {
        id: 'restore-parkade',
        label: 'Before the Parkade',
        session: 14,
        createdAt: '2045-09-14T21:12:00.000Z',
      },
      {
        id: 'restore-session-13',
        label: 'End of Session 13',
        session: 13,
        createdAt: '2045-09-07T23:48:00.000Z',
      },
      {
        id: 'restore-arc-2',
        label: 'Arc 2 Start',
        session: 11,
        createdAt: '2045-08-24T19:30:00.000Z',
      },
    ],
  }

  return { campaign, roster, locations: [kabukiParkade()] }
}

/** The lighter saves that fill out the library list in mockup 1A. */
export function libraryFillers(): Omit<CampaignBundle, 'manifest'>[] {
  const make = (
    id: string,
    name: string,
    city: string,
    players: number,
    sessions: number,
    arc: string,
  ): Omit<CampaignBundle, 'manifest'> => ({
    campaign: {
      id,
      name,
      arc,
      city,
      gm: 'V. Okonkwo',
      players,
      sessions,
      clock: { year: 2045, month: 6, day: 2, hour: 14, minute: 0 },
      weather: { condition: 'Smog', temperatureC: 24, visibilityPct: 65 },
      sessionLog: [],
      hooks: [],
      districts: {},
      coverPalette: COVER_PALETTE,
      restorePoints: [],
    },
    roster: { characters: [] },
    locations: [],
  })

  return [
    make('pistol-club', 'The Pistol Club', 'Night City', 5, 31, 'Session 31'),
    make('rust-revelation', 'Rust & Revelation', 'Badlands', 3, 7, 'Session 7'),
    make('arasoma-internal', 'Arasoma Internal', 'City Center', 4, 2, 'Session 2'),
    make('downtime-sandbox', 'Downtime Sandbox', 'Unset', 0, 0, 'Prep only'),
    make('one-shot-pacifica', 'One-Shot: Pacifica', 'Pacifica', 6, 1, 'Complete'),
  ]
}

export function newCampaign(name: string): Omit<CampaignBundle, 'manifest'> {
  const now = new Date()
  return {
    campaign: {
      id: `campaign-${now.getTime()}`,
      name,
      arc: 'Arc 1',
      city: 'Night City',
      gm: '',
      players: 0,
      sessions: 0,
      clock: { year: 2045, month: 1, day: 1, hour: 20, minute: 0 },
      weather: { condition: 'Clear', temperatureC: 20, visibilityPct: 90 },
      sessionLog: [],
      hooks: [],
      districts: {},
      coverPalette: COVER_PALETTE,
      restorePoints: [],
    },
    roster: { characters: [] },
    locations: [],
  }
}

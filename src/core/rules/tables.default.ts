/**
 * Homebrew placeholder tables.
 *
 * These are NOT book data. They exist so a fresh install can resolve a fight
 * immediately, and so every screen has something to render. The weapon names are
 * deliberately generic categories rather than the printed catalogue: a GM who
 * owns the book replaces these in the in-app table editor, or imports a JSON
 * document in this same shape.
 */

import type { RangeBand, TablesDocument } from './tables'

/** `[maxMetres, dv]` pairs, read as "out to this distance, this DV". */
function bands(pairs: readonly (readonly [number, number])[]): RangeBand[] {
  let min = 0
  return pairs.map(([max, dv]) => {
    const band: RangeBand = { min_m: min, max_m: max, dv }
    min = max
    return band
  })
}

const HOMEBREW_PAGE = 0

function injuries(names: readonly string[]): Record<string, { name: string; page: number }> {
  const table: Record<string, { name: string; page: number }> = {}
  names.forEach((name, index) => {
    table[String(index + 2)] = { name, page: HOMEBREW_PAGE }
  })
  return table
}

export const DEFAULT_TABLES: TablesDocument = {
  source: 'homebrew placeholder — not book data',

  ranged_dv: {
    pistol: bands([
      [6, 11],
      [12, 13],
      [25, 15],
      [50, 20],
      [100, 25],
    ]),
    smg: bands([
      [6, 11],
      [12, 12],
      [25, 15],
      [50, 18],
      [100, 22],
    ]),
    shotgun: bands([
      [6, 11],
      [12, 14],
      [25, 18],
      [50, 24],
    ]),
    assault_rifle: bands([
      [6, 15],
      [12, 13],
      [25, 13],
      [50, 15],
      [100, 18],
      [200, 22],
    ]),
    sniper_rifle: bands([
      [6, 20],
      [12, 17],
      [25, 15],
      [50, 15],
      [100, 15],
      [200, 17],
      [400, 21],
    ]),
    bow: bands([
      [6, 13],
      [12, 14],
      [25, 16],
      [50, 20],
      [100, 24],
    ]),
    thrown: bands([
      [6, 12],
      [12, 14],
      [25, 18],
      [50, 24],
    ]),
    melee: bands([[2, 10]]),
  },

  autofire_dv: {
    smg: bands([
      [6, 15],
      [12, 17],
      [25, 20],
      [50, 25],
    ]),
    assault_rifle: bands([
      [6, 17],
      [12, 17],
      [25, 19],
      [50, 22],
      [100, 26],
    ]),
  },

  weapons: {
    'Light Sidearm': {
      range_type: 'pistol',
      skill: 'Handgun',
      damage_dice: 1,
      magazine: 12,
      rof: 2,
      hands: 1,
      concealable: true,
      autofire_rating: null,
      page: HOMEBREW_PAGE,
    },
    'Service Sidearm': {
      range_type: 'pistol',
      skill: 'Handgun',
      damage_dice: 2,
      magazine: 12,
      rof: 2,
      hands: 1,
      concealable: true,
      autofire_rating: null,
      page: HOMEBREW_PAGE,
    },
    'Heavy Sidearm': {
      range_type: 'pistol',
      skill: 'Handgun',
      damage_dice: 3,
      magazine: 8,
      rof: 2,
      hands: 1,
      concealable: true,
      autofire_rating: null,
      page: HOMEBREW_PAGE,
    },
    'Hand Cannon': {
      range_type: 'pistol',
      skill: 'Handgun',
      damage_dice: 4,
      magazine: 8,
      rof: 1,
      hands: 2,
      concealable: false,
      autofire_rating: null,
      page: HOMEBREW_PAGE,
    },
    'Compact SMG': {
      range_type: 'smg',
      skill: 'Handgun',
      damage_dice: 2,
      magazine: 30,
      rof: 1,
      hands: 1,
      concealable: true,
      autofire_rating: 3,
      page: HOMEBREW_PAGE,
    },
    'Heavy SMG': {
      range_type: 'smg',
      skill: 'Shoulder Arms',
      damage_dice: 3,
      magazine: 40,
      rof: 1,
      hands: 2,
      concealable: false,
      autofire_rating: 3,
      page: HOMEBREW_PAGE,
    },
    'Combat Shotgun': {
      range_type: 'shotgun',
      skill: 'Shoulder Arms',
      damage_dice: 5,
      magazine: 4,
      rof: 1,
      hands: 2,
      concealable: false,
      autofire_rating: null,
      page: HOMEBREW_PAGE,
    },
    'Service Rifle': {
      range_type: 'assault_rifle',
      skill: 'Shoulder Arms',
      damage_dice: 5,
      magazine: 25,
      rof: 1,
      hands: 2,
      concealable: false,
      autofire_rating: 4,
      page: HOMEBREW_PAGE,
    },
    'Marksman Rifle': {
      range_type: 'sniper_rifle',
      skill: 'Shoulder Arms',
      damage_dice: 5,
      magazine: 4,
      rof: 1,
      hands: 2,
      concealable: false,
      autofire_rating: null,
      page: HOMEBREW_PAGE,
    },
    Monoblade: {
      range_type: 'melee',
      skill: 'Melee Weapon',
      damage_dice: 2,
      magazine: null,
      rof: 2,
      hands: 1,
      concealable: true,
      autofire_rating: null,
      page: HOMEBREW_PAGE,
    },
    'Heavy Melee': {
      range_type: 'melee',
      skill: 'Melee Weapon',
      damage_dice: 3,
      magazine: null,
      rof: 2,
      hands: 2,
      concealable: false,
      autofire_rating: null,
      page: HOMEBREW_PAGE,
    },
  },

  armor: {
    'Kevlar Weave': { sp: 7, penalty: {}, page: HOMEBREW_PAGE },
    'Light Plate': { sp: 11, penalty: {}, page: HOMEBREW_PAGE },
    'Heavy Plate': { sp: 13, penalty: { REF: -2, DEX: -2, MOVE: -2 }, page: HOMEBREW_PAGE },
    Exoshell: { sp: 18, penalty: { REF: -4, DEX: -4, MOVE: -4 }, page: HOMEBREW_PAGE },
  },

  aimed_shots: {
    head: { modifier: -8, page: HOMEBREW_PAGE },
    left_arm: { modifier: -8, page: HOMEBREW_PAGE },
    right_arm: { modifier: -8, page: HOMEBREW_PAGE },
    left_leg: { modifier: -8, page: HOMEBREW_PAGE },
    right_leg: { modifier: -8, page: HOMEBREW_PAGE },
  },

  // Materials and values come from the cover builder in the UI mockups.
  cover: {
    Concrete: { hp: 30, sp: 15, page: HOMEBREW_PAGE },
    'Steel Plate': { hp: 40, sp: 20, page: HOMEBREW_PAGE },
    Glass: { hp: 10, sp: 2, page: HOMEBREW_PAGE },
    'Sheet Metal': { hp: 15, sp: 7, page: HOMEBREW_PAGE },
    'Wood Crate': { hp: 12, sp: 5, page: HOMEBREW_PAGE },
    'Vehicle Hulk': { hp: 50, sp: 12, page: HOMEBREW_PAGE },
  },

  critical_injuries: {
    body: injuries([
      'Cracked Ribs',
      'Broken Ribs',
      'Torn Muscle',
      'Punctured Lung',
      'Foreign Object',
      'Broken Arm',
      'Dislocated Shoulder',
      'Spinal Bruise',
      'Ruptured Organ',
      'Shattered Pelvis',
      'Crushed Chest',
    ]),
    head: injuries([
      'Split Lip',
      'Broken Nose',
      'Concussion',
      'Damaged Ear',
      'Damaged Eye',
      'Cracked Skull',
      'Fractured Jaw',
      'Whiplash',
      'Lost Eye',
      'Brain Trauma',
      'Crushed Skull',
    ]),
  },
}

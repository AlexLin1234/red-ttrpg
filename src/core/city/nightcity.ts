/**
 * The built-in Night City map.
 *
 * The geometry is a stylised block diagram, not a survey — angular plates laid
 * out on a 1000 × 700 grid, the way the mockup draws it. All descriptive text is
 * original: Redline ships no book prose, the same way it ships no book tables.
 * A GM can override control, danger and notes per campaign, and later drop in
 * their own map image.
 */

export type ZoneType =
  | 'corporate'
  | 'combat'
  | 'residential'
  | 'industrial'
  | 'reclaimed'
  | 'outland'

export interface District {
  id: string
  name: string
  /** The small line under the name, e.g. "MAELSTROM · HEAT 4". */
  subtitle: string
  zoneType: ZoneType
  control: string
  /** 1 (quiet) to 5 (open firefights). */
  danger: number
  population: number
  lawResponse: string
  netDensity: string
  description: string
  /** Polygon in the 1000 × 700 map viewBox. */
  polygon: readonly (readonly [number, number])[]
  /** Where the label block sits. */
  label: readonly [number, number]
}

export const MAP_WIDTH = 1000
export const MAP_HEIGHT = 700

export const ZONE_LABELS: Record<ZoneType, string> = {
  corporate: 'Corporate Zone',
  combat: 'Combat Zone',
  residential: 'Residential',
  industrial: 'Industrial',
  reclaimed: 'Reclaimed',
  outland: 'Outland',
}

export const DISTRICTS: readonly District[] = [
  {
    id: 'watson',
    name: 'Watson',
    subtitle: 'Maelstrom · Heat 4',
    zoneType: 'combat',
    control: 'Maelstrom',
    danger: 4,
    population: 310_000,
    lawResponse: 'Slow',
    netDensity: 'High',
    description:
      'Half-finished towers the developers walked away from, now wired into somebody else. ' +
      'The markets run all night under the parkades and nobody asks where the stock came from. ' +
      'Maelstrom took the north blocks two winters ago and has not been pushed back since.',
    polygon: [
      [40, 380],
      [300, 380],
      [300, 520],
      [250, 660],
      [40, 660],
    ],
    label: [60, 620],
  },
  {
    id: 'heywood',
    name: 'Heywood',
    subtitle: 'Valentinos · Heat 2',
    zoneType: 'residential',
    control: 'Valentinos',
    danger: 3,
    population: 480_000,
    lawResponse: 'Moderate',
    netDensity: 'Medium',
    description:
      'The part of the city that still behaves like a neighbourhood. Family money, block parties, ' +
      'and a very clear understanding of which streets are spoken for. Outsiders get one polite warning.',
    polygon: [
      [300, 380],
      [560, 380],
      [560, 660],
      [250, 660],
      [300, 520],
    ],
    label: [320, 620],
  },
  {
    id: 'pacifica',
    name: 'Pacifica',
    subtitle: 'Combat Zone · Heat 5',
    zoneType: 'combat',
    control: 'Voodoo Boys',
    danger: 5,
    population: 6_000,
    lawResponse: 'Never',
    netDensity: 'High',
    description:
      'An abandoned resort megaproject. The Voodoo Boys hold the drowned levels, nobody else claims ' +
      'the surface. Rain never fully stops here — the runoff is unseeded cyberware and worse. ' +
      'Bring your own light and your own way out.',
    polygon: [
      [560, 380],
      [860, 380],
      [900, 500],
      [820, 660],
      [560, 660],
    ],
    label: [580, 620],
  },
  {
    id: 'city-center',
    name: 'City Center',
    subtitle: 'Corporate · Heat 1',
    zoneType: 'corporate',
    control: 'Arasoma & partners',
    danger: 2,
    population: 92_000,
    lawResponse: 'Immediate',
    netDensity: 'Saturated',
    description:
      'Glass, private security, and a skyline that bills by the hour. Everything is monitored and ' +
      'most of it is deniable. Violence here is a paperwork problem, which makes it more expensive, ' +
      'not less likely.',
    polygon: [
      [300, 150],
      [560, 150],
      [560, 380],
      [300, 380],
    ],
    label: [320, 340],
  },
  {
    id: 'santo-domingo',
    name: 'Santo Domingo',
    subtitle: 'Industrial · Heat 3',
    zoneType: 'industrial',
    control: 'Corporate contractors',
    danger: 3,
    population: 265_000,
    lawResponse: 'Slow',
    netDensity: 'Low',
    description:
      'Fabrication plants and the housing built to keep them staffed. The grid browns out on a ' +
      'schedule everyone has memorised. Union muscle and corporate muscle share the same parking lot ' +
      'and mostly leave each other alone.',
    polygon: [
      [560, 150],
      [820, 150],
      [860, 380],
      [560, 380],
    ],
    label: [580, 340],
  },
  {
    id: 'westbrook',
    name: 'Westbrook',
    subtitle: 'Nightlife · Heat 2',
    zoneType: 'residential',
    control: 'Tyger Claws',
    danger: 3,
    population: 198_000,
    lawResponse: 'Bought',
    netDensity: 'High',
    description:
      'Where the money goes to be seen. Clubs, clinics, and the fixers who work the gap between them. ' +
      'The Tyger Claws keep it orderly in the way a bouncer keeps a door orderly.',
    polygon: [
      [560, 40],
      [820, 40],
      [820, 150],
      [560, 150],
    ],
    label: [578, 128],
  },
  {
    id: 'north-oak',
    name: 'North Oak',
    subtitle: 'Private · Heat 1',
    zoneType: 'corporate',
    control: 'Private estates',
    danger: 1,
    population: 14_000,
    lawResponse: 'Immediate',
    netDensity: 'Private',
    description:
      'Above the smog line. Gate codes, private roads, and response times measured against a ' +
      'contract. If you are here without an invitation, that has already been noticed.',
    polygon: [
      [300, 40],
      [560, 40],
      [560, 150],
      [300, 150],
    ],
    label: [318, 128],
  },
  {
    id: 'badlands',
    name: 'Badlands',
    subtitle: 'Nomad · Heat 2',
    zoneType: 'outland',
    control: 'Nomad families',
    danger: 3,
    population: 41_000,
    lawResponse: 'None',
    netDensity: 'None',
    description:
      'Dust, solar farms, and the convoy routes that keep the city fed. The families run their own ' +
      'law out here and it is enforced faster than anything inside the ring.',
    polygon: [
      [820, 40],
      [960, 40],
      [960, 660],
      [820, 660],
      [900, 500],
      [860, 380],
      [820, 150],
    ],
    label: [838, 620],
  },
]

export function districtById(id: string): District | undefined {
  return DISTRICTS.find((district) => district.id === id)
}

/** A rough visual centre, used to place hook markers. */
export function districtCentroid(district: District): [number, number] {
  const points = district.polygon
  let x = 0
  let y = 0
  for (const [px, py] of points) {
    x += px
    y += py
  }
  return [x / points.length, y / points.length]
}

export function polygonPoints(district: District): string {
  return district.polygon.map(([x, y]) => `${x},${y}`).join(' ')
}

const WEATHER_TABLE: readonly { condition: string; temperature: number; visibility: number }[] = [
  { condition: 'Clear', temperature: 22, visibility: 95 },
  { condition: 'Smog', temperature: 26, visibility: 55 },
  { condition: 'Acid Rain', temperature: 18, visibility: 40 },
  { condition: 'Heavy Rain', temperature: 16, visibility: 35 },
  { condition: 'Dust Haze', temperature: 30, visibility: 45 },
  { condition: 'Cold Snap', temperature: 8, visibility: 80 },
]

export function rollWeather(random: () => number = Math.random) {
  const entry = WEATHER_TABLE[Math.floor(random() * WEATHER_TABLE.length)] ?? WEATHER_TABLE[0]!
  return {
    condition: entry.condition,
    temperatureC: entry.temperature,
    visibilityPct: entry.visibility,
  }
}

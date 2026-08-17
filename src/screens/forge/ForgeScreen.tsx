import { useCallback, useMemo, useState } from 'react'

import { useStore } from '../../app/store'
import {
  STAT_KEYS,
  emptyArmor,
  emptyStats,
  humanitySpent,
  pointsSpent,
  seriousWoundThreshold,
  type Character,
  type CoverDefinition,
  type StatKey,
} from '../../core/campaign/schema'
import { DEFAULT_TABLES } from '../../core/rules/tables.default'
import { HIT_LOCATIONS, type Location as HitLocation } from '../../core/rules/resolver'
import { CoverPreview } from './CoverPreview'
import './forge.css'

type ForgeTab = 'stats' | 'skills' | 'gear' | 'cover'

const TABS: { id: ForgeTab; label: string }[] = [
  { id: 'stats', label: 'Stats' },
  { id: 'skills', label: 'Skills' },
  { id: 'gear', label: 'Gear' },
  { id: 'cover', label: 'Cover' },
]

const LOCATION_LABELS: Record<HitLocation, string> = {
  head: 'Head',
  body: 'Torso',
  left_arm: 'L Arm',
  right_arm: 'R Arm',
  left_leg: 'L Leg',
  right_leg: 'R Leg',
}

const MATERIAL_COLORS: Record<string, number> = {
  Concrete: 0x3b434c,
  'Steel Plate': 0x4a5666,
  Glass: 0x2f5566,
  'Sheet Metal': 0x5a5f66,
  'Wood Crate': 0x6a4a26,
  'Vehicle Hulk': 0x63343a,
}

const MOOK_FIRST = ['Wire', 'Chrome', 'Sixer', 'Rat', 'Coil', 'Dregs', 'Static', 'Hatch']
const MOOK_LAST = ['Vasquez', 'Okoro', 'Petrov', 'Ng', 'Hale', 'Duarte', 'Sable', 'Kovac']

function randomOf<T>(values: readonly T[]): T {
  return values[Math.floor(Math.random() * values.length)]!
}

function rollMook(): Character {
  const stats = emptyStats()
  for (const key of STAT_KEYS) stats[key] = 3 + Math.floor(Math.random() * 4)
  const maxHp = 20 + Math.floor(Math.random() * 12)
  const armor = emptyArmor()
  const sp = 4 + Math.floor(Math.random() * 8)
  for (const location of HIT_LOCATIONS) armor[location] = { sp, ablated: false }
  return {
    id: `mook-${Date.now()}`,
    name: `${randomOf(MOOK_FIRST)} ${randomOf(MOOK_LAST)}`,
    role: 'Mook',
    kind: 'mook',
    side: 'hostile',
    tags: ['MOOK', 'ROLLED'],
    stats,
    skills: [
      { name: 'Handgun', stat: 'REF', level: 2 + Math.floor(Math.random() * 4) },
      { name: 'Evasion', stat: 'DEX', level: 1 + Math.floor(Math.random() * 3) },
    ],
    gear: [{ name: 'Service Sidearm', kind: 'weapon', detail: '2d6' }],
    armor,
    hp: maxHp,
    maxHp,
    humanity: 30,
    maxHumanity: 40,
    weapons: [
      { name: 'Service Sidearm', ammo: 12, magazine: 12, weaponType: 'pistol', damageDice: 2, rof: 2 },
    ],
  }
}

function blankCharacter(): Character {
  const armor = emptyArmor()
  return {
    id: `character-${Date.now()}`,
    name: 'New Character',
    role: 'Unset',
    kind: 'npc',
    side: 'neutral',
    tags: ['NPC'],
    stats: emptyStats(),
    skills: [],
    gear: [],
    armor,
    hp: 30,
    maxHp: 30,
    humanity: 40,
    maxHumanity: 50,
    weapons: [],
  }
}

export function ForgeScreen() {
  const { campaign, roster, dispatch, state, activeLocation } = useStore()
  const [tab, setTab] = useState<ForgeTab>('stats')

  const characters = roster?.characters ?? []
  const selectedId = state.activeCharacterId ?? characters[0]?.id ?? null
  const character = characters.find((entry) => entry.id === selectedId) ?? null

  const editCharacter = useCallback(
    (id: string, update: (character: Character) => Character) => {
      dispatch({
        type: 'roster',
        update: (current) => ({
          ...current,
          characters: current.characters.map((entry) => (entry.id === id ? update(entry) : entry)),
        }),
      })
    },
    [dispatch],
  )

  const addCharacter = useCallback(
    (next: Character) => {
      dispatch({
        type: 'roster',
        update: (current) => ({ ...current, characters: [next, ...current.characters] }),
      })
      dispatch({ type: 'selectCharacter', id: next.id })
    },
    [dispatch],
  )

  if (!campaign || !roster) {
    return <div className="empty-state micro">No campaign is open.</div>
  }

  return (
    <div className="forge">
      <aside className="forge-roster panel">
        <div className="section-head">
          <span className="micro">Roster</span>
          <span className="micro">{characters.length}</span>
        </div>

        <div className="forge-roster-list scroll">
          {characters.map((entry) => (
            <button
              key={entry.id}
              type="button"
              className="forge-roster-row"
              aria-current={entry.id === selectedId ? 'true' : undefined}
              onClick={() => dispatch({ type: 'selectCharacter', id: entry.id })}
            >
              <span className="forge-roster-portrait hatched" aria-hidden="true" />
              <span className="forge-roster-main">
                <span className="forge-roster-name">{entry.name}</span>
                <span className="micro">{entry.role}</span>
              </span>
              <span className={`forge-tag is-${entry.kind}`}>
                {entry.id === selectedId ? 'Editing' : entry.kind.toUpperCase()}
              </span>
            </button>
          ))}
        </div>

        <div className="forge-roster-actions">
          <button type="button" className="button is-primary" onClick={() => addCharacter(blankCharacter())}>
            + New character
          </button>
          <button type="button" className="button" onClick={() => addCharacter(rollMook())}>
            Roll random mook
          </button>
        </div>
      </aside>

      <section className="forge-sheet panel">
        {character ? (
          <>
            <header className="forge-head">
              <span className="forge-portrait hatched" aria-hidden="true">
                <span className="micro">Portrait</span>
              </span>

              <div className="forge-identity">
                <span className="micro">Role · {character.role}</span>
                <input
                  className="forge-name"
                  value={character.name}
                  aria-label="Character name"
                  onChange={(event) =>
                    editCharacter(character.id, (entry) => ({ ...entry, name: event.target.value }))
                  }
                />
                <div className="forge-tags">
                  {character.tags.map((tag) => (
                    <span
                      key={tag}
                      className={`forge-tag${tag === 'HOSTILE' ? ' is-hostile' : ''}`}
                    >
                      {tag}
                    </span>
                  ))}
                </div>
              </div>

              <div className="forge-vitals">
                <div className="forge-vital">
                  <span className="micro">HP / seriously wounded</span>
                  <span className="forge-vital-value">
                    {character.maxHp}
                    <span className="forge-vital-sub">/ {seriousWoundThreshold(character.maxHp)}</span>
                  </span>
                </div>
                <div className="forge-vital">
                  <span className="micro">Humanity</span>
                  <span
                    className={`forge-vital-value${
                      character.humanity <= character.maxHumanity * 0.5 ? ' is-alert' : ''
                    }`}
                  >
                    {character.humanity}
                    <span className="forge-vital-sub">/ {character.maxHumanity}</span>
                  </span>
                  <span className="micro">
                    {character.humanity <= character.maxHumanity * 0.5
                      ? 'Cyberpsychosis risk'
                      : 'Stable'}
                  </span>
                </div>
              </div>

              <div className="tab-row forge-tabs">
                {TABS.map((entry) => (
                  <button
                    key={entry.id}
                    type="button"
                    className="tab"
                    aria-selected={tab === entry.id}
                    onClick={() => setTab(entry.id)}
                  >
                    {entry.label}
                  </button>
                ))}
              </div>
            </header>

            <div className="forge-body scroll">
              {tab === 'stats' ? (
                <StatsTab character={character} onEdit={editCharacter} />
              ) : null}
              {tab === 'skills' ? <SkillsTab character={character} /> : null}
              {tab === 'gear' ? <GearTab character={character} /> : null}
              {tab === 'cover' ? (
                <p className="micro forge-hint">
                  The cover builder is in the right rail — it stays visible on every tab so a prop
                  can be built while reading a sheet.
                </p>
              ) : null}
            </div>
          </>
        ) : (
          <div className="empty-state">
            <span className="micro">No character selected</span>
          </div>
        )}
      </section>

      <CoverBuilder
        palette={campaign.coverPalette}
        canPlace={Boolean(activeLocation)}
        onSave={(cover) =>
          dispatch({
            type: 'campaign',
            update: (current) => ({ ...current, coverPalette: [...current.coverPalette, cover] }),
          })
        }
        onPlace={(cover) => {
          if (!activeLocation) return
          dispatch({
            type: 'campaign',
            update: (current) => ({ ...current, coverPalette: [...current.coverPalette, cover] }),
          })
          dispatch({
            type: 'location',
            id: activeLocation.id,
            update: (location) => ({
              ...location,
              props: [
                ...location.props,
                {
                  id: `prop-${Date.now()}`,
                  coverId: cover.id,
                  x: Math.floor(location.gridWidth / 2),
                  z: Math.floor(location.gridHeight / 2),
                  layer: 0,
                  rotation: 0,
                  hp: cover.hp,
                },
              ],
            }),
          })
          dispatch({ type: 'navigate', screen: 'location' })
        }}
      />
    </div>
  )
}

function StatsTab({
  character,
  onEdit,
}: {
  character: Character
  onEdit: (id: string, update: (character: Character) => Character) => void
}) {
  const spent = pointsSpent(character.stats)
  return (
    <>
      <div className="section-head">
        <span className="micro">Stats</span>
        <span className="micro">{spent} points spent</span>
      </div>
      <div className="forge-stats">
        {STAT_KEYS.map((key) => (
          <label key={key} className="forge-stat">
            <span className="micro">{key}</span>
            <input
              className="forge-stat-input"
              type="number"
              min={1}
              max={10}
              value={character.stats[key]}
              onChange={(event) =>
                onEdit(character.id, (entry) => ({
                  ...entry,
                  stats: { ...entry.stats, [key]: Number(event.target.value) } as Record<
                    StatKey,
                    number
                  >,
                }))
              }
            />
          </label>
        ))}
      </div>

      <div className="section-head">
        <span className="micro">Armor · SP by location</span>
        <span className="micro">Ablation tracked per hit</span>
      </div>
      <div className="forge-armor">
        {HIT_LOCATIONS.map((location) => {
          const slot = character.armor[location]
          return (
            <div key={location} className={`forge-armor-slot${slot.ablated ? ' is-ablated' : ''}`}>
              <span className="micro">{LOCATION_LABELS[location]}</span>
              <span className="forge-armor-value">
                {slot.sp}
                <span className="micro">{slot.ablated ? 'Ablated' : `SP${slot.sp}`}</span>
              </span>
            </div>
          )
        })}
      </div>
    </>
  )
}

function SkillsTab({ character }: { character: Character }) {
  return (
    <>
      <div className="section-head">
        <span className="micro">Skills</span>
        <span className="micro">Level + stat = total</span>
      </div>
      <div className="forge-skills">
        {character.skills.map((skill) => (
          <div key={skill.name} className="forge-skill">
            <span className="forge-skill-name">{skill.name}</span>
            <span className="micro">{skill.stat}</span>
            <span className="forge-skill-level">{skill.level}</span>
            <span className="forge-skill-total">
              +{(character.stats[skill.stat] ?? 0) + skill.level}
            </span>
          </div>
        ))}
        {character.skills.length === 0 ? <p className="micro">No skills recorded.</p> : null}
      </div>
    </>
  )
}

function GearTab({ character }: { character: Character }) {
  const humanity = humanitySpent(character.gear)
  return (
    <>
      <div className="section-head">
        <span className="micro">Gear & cyberware</span>
        <span className="micro">{humanity} humanity spent</span>
      </div>
      <div className="forge-gear">
        {character.gear.map((item) => (
          <div key={item.name} className="forge-gear-row">
            <span className="forge-gear-name">{item.name}</span>
            <span className="micro">{item.kind}</span>
            <span className="forge-gear-detail">{item.detail ?? ''}</span>
            <span className={`forge-gear-cost${item.humanityCost ? ' is-cost' : ''}`}>
              {item.humanityCost ? `${item.humanityCost} HUM` : ''}
            </span>
          </div>
        ))}
        {character.gear.length === 0 ? <p className="micro">Nothing carried.</p> : null}
      </div>
    </>
  )
}

function CoverBuilder({
  palette,
  canPlace,
  onSave,
  onPlace,
}: {
  palette: readonly CoverDefinition[]
  canPlace: boolean
  onSave: (cover: CoverDefinition) => void
  onPlace: (cover: CoverDefinition) => void
}) {
  const materials = useMemo(() => Object.entries(DEFAULT_TABLES.cover), [])
  const [material, setMaterial] = useState('Concrete')
  const [name, setName] = useState('Concrete Jersey Barrier')
  const [height, setHeight] = useState(1.2)
  const [width, setWidth] = useState(2)
  const [depth, setDepth] = useState(1)
  const [destructible, setDestructible] = useState(true)

  const profile = DEFAULT_TABLES.cover[material] ?? { sp: 10, hp: 20, page: 0 }
  // Bigger cover has more to chew through; the printed HP is for a nominal
  // 2 × 1 × 1 m block and scales with volume from there.
  const volumeFactor = (height * width * depth) / (1.2 * 2 * 1)
  const hp = Math.max(1, Math.round(profile.hp * volumeFactor))

  const build = (): CoverDefinition => ({
    id: `cover-${Date.now()}`,
    name: name.trim() || material,
    material,
    height,
    width,
    depth,
    sp: profile.sp,
    hp,
    destructible,
  })

  return (
    <aside className="forge-cover panel">
      <div className="section-head">
        <span className="micro">Cover builder</span>
        <span className="micro">{palette.length} in palette</span>
      </div>

      <div className="forge-preview">
        <CoverPreview
          width={width}
          height={height}
          depth={depth}
          color={MATERIAL_COLORS[material] ?? 0x3b434c}
        />
        <span className="micro forge-preview-dims">
          {width} × {depth} × {height} m
        </span>
      </div>

      <label className="forge-field">
        <span className="micro">Name</span>
        <input value={name} onChange={(event) => setName(event.target.value)} />
      </label>

      <Slider label="Height" value={height} min={0.3} max={4} onChange={setHeight} />
      <Slider label="Width" value={width} min={0.3} max={6} onChange={setWidth} />
      <Slider label="Depth" value={depth} min={0.3} max={4} onChange={setDepth} />

      <label className="forge-field forge-field-inline">
        <span className="micro">Destructible</span>
        <input
          type="checkbox"
          checked={destructible}
          onChange={(event) => setDestructible(event.target.checked)}
        />
      </label>

      <span className="micro">Material</span>
      <div className="forge-materials">
        {materials.map(([key, entry]) => (
          <button
            key={key}
            type="button"
            className="forge-material"
            aria-pressed={material === key}
            onClick={() => setMaterial(key)}
          >
            <span className="forge-material-name">{key}</span>
            <span className="micro">
              SP {entry.sp} · {entry.hp} HP
            </span>
          </button>
        ))}
      </div>

      <div className="forge-rules">
        <span className="micro">Rules effect</span>
        <p className="forge-rules-text">
          Blocks line of sight above {height.toFixed(1)} m. The barrier absorbs damage at SP{' '}
          {profile.sp} and has {hp} HP at this size.{' '}
          {destructible
            ? 'It ablates as it takes hits and fails when its HP reaches zero.'
            : 'It is marked indestructible and will not fail.'}
        </p>
      </div>

      <div className="forge-cover-actions">
        <button type="button" className="button is-primary" onClick={() => onSave(build())}>
          Save to palette
        </button>
        <button
          type="button"
          className="button"
          disabled={!canPlace}
          onClick={() => onPlace(build())}
        >
          Place on map
        </button>
      </div>
    </aside>
  )
}

function Slider({
  label,
  value,
  min,
  max,
  onChange,
}: {
  label: string
  value: number
  min: number
  max: number
  onChange: (value: number) => void
}) {
  return (
    <label className="forge-slider">
      <span className="micro">{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={0.1}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
      />
      <span className="forge-slider-value">{value.toFixed(1)} m</span>
    </label>
  )
}

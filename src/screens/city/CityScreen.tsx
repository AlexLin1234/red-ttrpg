import { useMemo, useState } from 'react'

import { useStore } from '../../app/store'
import {
  DISTRICTS,
  MAP_HEIGHT,
  MAP_WIDTH,
  ZONE_LABELS,
  districtCentroid,
  polygonPoints,
  rollWeather,
  type District,
} from '../../core/city/nightcity'
import {
  advanceClock,
  formatClock,
  formatDate,
  shiftOf,
  type JobHook,
} from '../../core/campaign/schema'
import './city.css'

type Tab = 'map' | 'control' | 'jobs' | 'net'

const TABS: { id: Tab; label: string }[] = [
  { id: 'map', label: 'Map' },
  { id: 'control', label: 'Control' },
  { id: 'jobs', label: 'Jobs' },
  { id: 'net', label: 'Net' },
]

export function CityScreen() {
  const { campaign, dispatch, locations } = useStore()
  const [tab, setTab] = useState<Tab>('map')
  const [hovered, setHovered] = useState<string | null>(null)
  const [pinned, setPinned] = useState<string | null>('pacifica')

  const focusId = hovered ?? pinned
  const focus = useMemo(
    () => DISTRICTS.find((district) => district.id === focusId) ?? null,
    [focusId],
  )

  if (!campaign) return <div className="empty-state micro">No campaign is open.</div>

  const shift = shiftOf(campaign.clock)
  const hooksByDistrict = new Map<string, JobHook[]>()
  for (const hook of campaign.hooks) {
    if (hook.status === 'closed') continue
    const list = hooksByDistrict.get(hook.districtId) ?? []
    list.push(hook)
    hooksByDistrict.set(hook.districtId, list)
  }

  const advance = (minutes: number) =>
    dispatch({
      type: 'campaign',
      update: (current) => ({ ...current, clock: advanceClock(current.clock, minutes) }),
    })

  const reroll = () =>
    dispatch({ type: 'campaign', update: (current) => ({ ...current, weather: rollWeather() }) })

  const focusHooks = focus ? (hooksByDistrict.get(focus.id) ?? []) : []
  const override = focus ? campaign.districts[focus.id] : undefined
  const danger = override?.danger ?? focus?.danger ?? 0
  const control = override?.control ?? focus?.control ?? '—'

  return (
    <div className="city">
      <header className="city-bar">
        <span className="micro">
          {campaign.city} · {campaign.arc} · {locations.length} locations
        </span>
        <div className="tab-row">
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
        <span className="micro">GM · {campaign.gm || 'unset'}</span>
      </header>

      <div className="city-body">
        <section className="city-map panel" aria-label="Night City districts">
          <svg
            viewBox={`0 0 ${MAP_WIDTH} ${MAP_HEIGHT}`}
            className="city-svg"
            role="group"
            aria-label="District map"
          >
            <defs>
              <pattern id="city-grid" width="20" height="20" patternUnits="userSpaceOnUse">
                <path d="M20 0H0V20" fill="none" stroke="#141c26" strokeWidth="1" />
              </pattern>
            </defs>
            <rect width={MAP_WIDTH} height={MAP_HEIGHT} fill="url(#city-grid)" />

            {DISTRICTS.map((district) => {
              const isFocus = district.id === focusId
              return (
                <g
                  key={district.id}
                  className={`city-district is-${district.zoneType}${isFocus ? ' is-focus' : ''}`}
                  onMouseEnter={() => setHovered(district.id)}
                  onMouseLeave={() => setHovered(null)}
                  onClick={() => setPinned(district.id)}
                  tabIndex={0}
                  role="button"
                  aria-label={`${district.name}, ${ZONE_LABELS[district.zoneType]}`}
                  onFocus={() => setHovered(district.id)}
                  onBlur={() => setHovered(null)}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter' || event.key === ' ') {
                      event.preventDefault()
                      setPinned(district.id)
                    }
                  }}
                >
                  <polygon points={polygonPoints(district)} />
                  <text className="city-district-name" x={district.label[0]} y={district.label[1]}>
                    {district.name.toUpperCase()}
                  </text>
                  <text
                    className="city-district-sub"
                    x={district.label[0]}
                    y={district.label[1] + 14}
                  >
                    {(override?.control ?? district.subtitle).toUpperCase()}
                  </text>
                </g>
              )
            })}

            {DISTRICTS.filter((district) => hooksByDistrict.has(district.id)).map((district) => {
              const [cx, cy] = districtCentroid(district)
              return (
                <g key={`hook-${district.id}`} className="city-hook" aria-hidden="true">
                  <rect x={cx - 6} y={cy - 6} width="12" height="12" transform={`rotate(45 ${cx} ${cy})`} />
                </g>
              )
            })}
          </svg>
        </section>

        <aside className="city-rail panel">
          <div className="city-clock">
            <span className="micro">In-world clock</span>
            <div className="display city-time">{formatClock(campaign.clock)}</div>
            <span className="micro">
              {shift.label} · Shift {shift.shift}
            </span>
            <span className="micro city-date">{formatDate(campaign.clock)}</span>
            <span className="micro">
              {campaign.weather.condition} · {campaign.weather.temperatureC}°C · Vis{' '}
              {campaign.weather.visibilityPct}%
            </span>
            <div className="city-clock-actions">
              <button type="button" className="button" onClick={() => advance(60)}>
                +1 hour
              </button>
              <button type="button" className="button" onClick={() => advance(60 * 24)}>
                +1 day
              </button>
              <button type="button" className="button" onClick={reroll}>
                Weather
              </button>
            </div>
          </div>

          <hr className="rule" />

          {tab === 'map' && focus ? (
            <DistrictPanel
              district={focus}
              control={control}
              danger={danger}
              note={override?.note}
              hooks={focusHooks}
            />
          ) : null}

          {tab === 'control' ? (
            <div className="city-list scroll">
              <span className="micro">Who holds what</span>
              {DISTRICTS.map((district) => (
                <div key={district.id} className="field-row">
                  <span className="micro">{district.name}</span>
                  <span className="field-value">
                    {campaign.districts[district.id]?.control ?? district.control}
                  </span>
                </div>
              ))}
            </div>
          ) : null}

          {tab === 'jobs' ? (
            <div className="city-list scroll">
              <span className="micro">Open hooks</span>
              {campaign.hooks.filter((hook) => hook.status !== 'closed').length === 0 ? (
                <p className="micro">Nothing running.</p>
              ) : null}
              {campaign.hooks
                .filter((hook) => hook.status !== 'closed')
                .map((hook) => (
                  <div key={hook.id} className="city-hook-row">
                    <div className="city-hook-head">
                      <span className="field-value">{hook.title}</span>
                      <span className="micro">{hook.status}</span>
                    </div>
                    <span className="micro city-hook-where">{hook.districtId}</span>
                    <p className="city-hook-detail">{hook.detail}</p>
                  </div>
                ))}
            </div>
          ) : null}

          {tab === 'net' ? (
            <div className="city-list scroll">
              <span className="micro">Net density</span>
              {DISTRICTS.map((district) => (
                <div key={district.id} className="field-row">
                  <span className="micro">{district.name}</span>
                  <span className="field-value">{district.netDensity}</span>
                </div>
              ))}
            </div>
          ) : null}

          {tab === 'map' && !focus ? (
            <p className="micro city-hint">Hover a district to inspect it.</p>
          ) : null}
        </aside>
      </div>
    </div>
  )
}

function DistrictPanel({
  district,
  control,
  danger,
  note,
  hooks,
}: {
  district: District
  control: string
  danger: number
  note?: string
  hooks: JobHook[]
}) {
  const isCombatZone = district.zoneType === 'combat'
  return (
    <div className="city-detail scroll">
      <span className="micro">Hovered district</span>
      <h2 className="display city-detail-name">{district.name}</h2>
      <span className={`micro${isCombatZone ? ' city-danger' : ''}`}>
        {ZONE_LABELS[district.zoneType]}
        {district.lawResponse === 'Never' ? ' · No NCPD presence' : ''}
      </span>

      <p className="city-detail-text">{district.description}</p>
      {note ? <p className="city-detail-note">{note}</p> : null}

      <div className="city-stats">
        <Stat label="Danger" value={`${danger}/5`} tone={danger >= 4 ? 'alert' : undefined} />
        <Stat label="Population" value={`~${district.population.toLocaleString('en-GB')}`} />
        <Stat label="Law response" value={district.lawResponse} />
        <Stat label="Net density" value={district.netDensity} />
        <Stat label="Control" value={control} wide />
      </div>

      <span className="micro">Job hooks here</span>
      {hooks.length === 0 ? <p className="micro">None flagged.</p> : null}
      {hooks.map((hook) => (
        <div key={hook.id} className="city-detail-hook">
          <span className="city-detail-hook-title">◇ {hook.title}</span>
          <p className="city-hook-detail">{hook.detail}</p>
        </div>
      ))}
    </div>
  )
}

function Stat({
  label,
  value,
  tone,
  wide,
}: {
  label: string
  value: string
  tone?: 'alert'
  wide?: boolean
}) {
  return (
    <div className={`city-stat${wide ? ' is-wide' : ''}`}>
      <span className="micro">{label}</span>
      <span className={`city-stat-value${tone === 'alert' ? ' is-alert' : ''}`}>{value}</span>
    </div>
  )
}

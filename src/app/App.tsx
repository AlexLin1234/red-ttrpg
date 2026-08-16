import { useEffect } from 'react'

import { CityScreen } from '../screens/city/CityScreen'
import { ForgeScreen } from '../screens/forge/ForgeScreen'
import { LibraryScreen } from '../screens/library/LibraryScreen'
import { LocationScreen } from '../screens/location/LocationScreen'
import { useStore, type ScreenId } from './store'
import './app.css'

const SCREENS: { id: ScreenId; label: string; hint: string }[] = [
  { id: 'library', label: 'Library', hint: '1' },
  { id: 'city', label: 'City', hint: '2' },
  { id: 'location', label: 'Location', hint: '3' },
  { id: 'forge', label: 'Forge', hint: '4' },
]

export function App() {
  const { state, dispatch, campaign, save } = useStore()

  // Number keys move between screens; Ctrl/Cmd-S saves. Both are GM reflexes.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null
      if (target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
        event.preventDefault()
        if (state.open) void save()
        return
      }
      const index = Number(event.key) - 1
      const screen = SCREENS[index]
      if (screen && !event.ctrlKey && !event.metaKey && !event.altKey) {
        if (screen.id !== 'library' && !state.open) return
        dispatch({ type: 'navigate', screen: screen.id })
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [dispatch, save, state.open])

  return (
    <div className="app">
      <header className="app-header">
        <div className="app-brand">
          <span className="app-brand-mark" aria-hidden="true" />
          <span className="display app-brand-name">Redline</span>
          <span className="micro">
            {campaign ? `${campaign.name} / ${campaign.city}` : 'GM Console · Build 0.4.2'}
          </span>
        </div>

        <nav className="app-nav" aria-label="Screens">
          {SCREENS.map((screen) => (
            <button
              key={screen.id}
              type="button"
              className="app-nav-item"
              aria-current={state.screen === screen.id ? 'page' : undefined}
              disabled={screen.id !== 'library' && !state.open}
              onClick={() => dispatch({ type: 'navigate', screen: screen.id })}
            >
              {screen.label}
              <span className="app-nav-key">{screen.hint}</span>
            </button>
          ))}
        </nav>

        <div className="app-header-right">
          {state.status ? <span className="micro app-status">{state.status}</span> : null}
          {state.open ? (
            <>
              <span className={`micro app-dirty${state.dirty ? ' is-dirty' : ''}`}>
                {state.dirty ? 'Unsaved changes' : 'Saved'}
              </span>
              <button type="button" className="app-save" onClick={() => void save()}>
                Save
              </button>
            </>
          ) : (
            <span className="micro">Local library</span>
          )}
        </div>
      </header>

      <main className="app-body">
        {state.screen === 'library' ? <LibraryScreen /> : null}
        {state.screen === 'city' ? <CityScreen /> : null}
        {state.screen === 'location' ? <LocationScreen /> : null}
        {state.screen === 'forge' ? <ForgeScreen /> : null}
      </main>
    </div>
  )
}

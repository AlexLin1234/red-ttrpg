/**
 * The one place the loaded campaign lives.
 *
 * Screens read from here and dispatch edits back; nothing else holds campaign
 * state. Saving is explicit — `dirty` drives the header indicator so the GM can
 * see at a glance whether the file on disk matches what is on screen.
 */

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useReducer,
  type Dispatch,
  type ReactNode,
} from 'react'

import { packCampaign, suggestFileName, type LoadedCampaign } from '../core/campaign/container'
import type { Campaign, Character, GameLocation, Roster } from '../core/campaign/schema'
import { bridge } from '../platform/bridge'

export type ScreenId = 'library' | 'city' | 'location' | 'forge'

export interface OpenCampaign {
  path: string
  sizeOnDisk: number
  loaded: LoadedCampaign
}

export interface AppState {
  screen: ScreenId
  open: OpenCampaign | null
  dirty: boolean
  activeLocationId: string | null
  activeCharacterId: string | null
  status: string | null
}

export type AppAction =
  | { type: 'navigate'; screen: ScreenId }
  | { type: 'opened'; open: OpenCampaign }
  | { type: 'closed' }
  | { type: 'campaign'; update: (campaign: Campaign) => Campaign }
  | { type: 'roster'; update: (roster: Roster) => Roster }
  | { type: 'location'; id: string; update: (location: GameLocation) => GameLocation }
  | { type: 'addLocation'; location: GameLocation }
  | { type: 'selectLocation'; id: string | null }
  | { type: 'selectCharacter'; id: string | null }
  | { type: 'saved'; sizeOnDisk: number }
  | { type: 'status'; message: string | null }

const initialState: AppState = {
  screen: 'library',
  open: null,
  dirty: false,
  activeLocationId: null,
  activeCharacterId: null,
  status: null,
}

function reducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'navigate':
      return { ...state, screen: action.screen }
    case 'opened':
      return {
        ...state,
        open: action.open,
        dirty: false,
        screen: 'city',
        activeLocationId: action.open.loaded.locations[0]?.id ?? null,
        activeCharacterId: action.open.loaded.roster.characters[0]?.id ?? null,
        status: null,
      }
    case 'closed':
      return { ...initialState }
    case 'campaign': {
      if (!state.open) return state
      const loaded = { ...state.open.loaded, campaign: action.update(state.open.loaded.campaign) }
      return { ...state, open: { ...state.open, loaded }, dirty: true }
    }
    case 'roster': {
      if (!state.open) return state
      const loaded = { ...state.open.loaded, roster: action.update(state.open.loaded.roster) }
      return { ...state, open: { ...state.open, loaded }, dirty: true }
    }
    case 'location': {
      if (!state.open) return state
      const locations = state.open.loaded.locations.map((location) =>
        location.id === action.id ? action.update(location) : location,
      )
      return {
        ...state,
        open: { ...state.open, loaded: { ...state.open.loaded, locations } },
        dirty: true,
      }
    }
    case 'addLocation': {
      if (!state.open) return state
      const locations = [...state.open.loaded.locations, action.location]
      return {
        ...state,
        open: { ...state.open, loaded: { ...state.open.loaded, locations } },
        activeLocationId: action.location.id,
        dirty: true,
      }
    }
    case 'selectLocation':
      return { ...state, activeLocationId: action.id }
    case 'selectCharacter':
      return { ...state, activeCharacterId: action.id }
    case 'saved':
      return {
        ...state,
        dirty: false,
        open: state.open ? { ...state.open, sizeOnDisk: action.sizeOnDisk } : null,
        status: 'Saved',
      }
    case 'status':
      return { ...state, status: action.message }
    default:
      return state
  }
}

interface StoreValue {
  state: AppState
  dispatch: Dispatch<AppAction>
  save: () => Promise<void>
  campaign: Campaign | null
  roster: Roster | null
  locations: GameLocation[]
  activeLocation: GameLocation | null
  activeCharacter: Character | null
}

const StoreContext = createContext<StoreValue | null>(null)

export function StoreProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(reducer, initialState)

  const save = useCallback(async () => {
    if (!state.open) return
    const { loaded, path } = state.open
    const bytes = await packCampaign({
      manifest: loaded.manifest,
      campaign: loaded.campaign,
      roster: loaded.roster,
      locations: loaded.locations,
    })
    const result = await bridge().writeSave(path, bytes)
    dispatch({ type: 'saved', sizeOnDisk: result.size })
  }, [state.open])

  const value = useMemo<StoreValue>(() => {
    const loaded = state.open?.loaded ?? null
    return {
      state,
      dispatch,
      save,
      campaign: loaded?.campaign ?? null,
      roster: loaded?.roster ?? null,
      locations: loaded?.locations ?? [],
      activeLocation:
        loaded?.locations.find((location) => location.id === state.activeLocationId) ?? null,
      activeCharacter:
        loaded?.roster.characters.find((character) => character.id === state.activeCharacterId) ??
        null,
    }
  }, [state, save])

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>
}

export function useStore(): StoreValue {
  const value = useContext(StoreContext)
  if (!value) throw new Error('useStore must be used inside a StoreProvider')
  return value
}

export { suggestFileName }

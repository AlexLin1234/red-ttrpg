/**
 * The browser implementation of the platform bridge.
 *
 * There is no filesystem here, so the save library lives in memory (mirrored to
 * localStorage when it is available) and is seeded with the demo campaigns. This
 * is what lets the end-to-end tests drive all four screens in a plain browser,
 * and what makes `npm run dev` useful without launching Electron.
 */

import { packCampaign } from '../core/campaign/container'
import { blackwallSunrise, libraryFillers } from '../core/campaign/fixtures'
import { suggestFileName } from '../core/campaign/container'
import type {
  ImportedSave,
  PlatformBridge,
  SaveFileEntry,
  WriteResult,
} from './bridge'

const LIBRARY_DIR = '~/Documents/Redline/saves'
const STORAGE_KEY = 'redline.library.v1'

interface StoredSave {
  bytes: Uint8Array
  modified: number
}

function toBase64(bytes: Uint8Array): string {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}

function fromBase64(value: string): Uint8Array {
  const binary = atob(value)
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index)
  return bytes
}

export class WebBridge implements PlatformBridge {
  readonly kind = 'web' as const
  private saves = new Map<string, StoredSave>()
  private ready: Promise<void>

  constructor(options: { seed?: boolean; persist?: boolean } = {}) {
    const persist = options.persist ?? true
    this.ready = this.restore(persist).then(async (restored) => {
      if (!restored && (options.seed ?? true)) await this.seed()
      if (persist) this.persist()
    })
  }

  private storage(): Storage | null {
    try {
      return typeof localStorage === 'undefined' ? null : localStorage
    } catch {
      return null
    }
  }

  private async restore(persist: boolean): Promise<boolean> {
    if (!persist) return false
    const store = this.storage()
    const raw = store?.getItem(STORAGE_KEY)
    if (!raw) return false
    try {
      const parsed = JSON.parse(raw) as Record<string, { bytes: string; modified: number }>
      for (const [path, entry] of Object.entries(parsed)) {
        this.saves.set(path, { bytes: fromBase64(entry.bytes), modified: entry.modified })
      }
      return this.saves.size > 0
    } catch {
      return false
    }
  }

  private persist(): void {
    const store = this.storage()
    if (!store) return
    const payload: Record<string, { bytes: string; modified: number }> = {}
    for (const [path, entry] of this.saves) {
      payload[path] = { bytes: toBase64(entry.bytes), modified: entry.modified }
    }
    try {
      store.setItem(STORAGE_KEY, JSON.stringify(payload))
    } catch {
      // A full quota is not worth failing a save over; the in-memory copy stands.
    }
  }

  private async seed(): Promise<void> {
    const day = 24 * 60 * 60 * 1000
    const now = Date.now()
    const bundles = [
      { bundle: blackwallSunrise(), age: 2 * day },
      ...libraryFillers().map((bundle, index) => ({ bundle, age: (21 + index * 30) * day })),
    ]
    for (const { bundle, age } of bundles) {
      const bytes = await packCampaign(bundle)
      const path = `${LIBRARY_DIR}/${suggestFileName(bundle.campaign.name)}`
      this.saves.set(path, { bytes, modified: now - age })
    }
  }

  async libraryDir(): Promise<string> {
    return LIBRARY_DIR
  }

  async listSaves(): Promise<SaveFileEntry[]> {
    await this.ready
    return [...this.saves.entries()].map(([path, entry]) => ({
      path,
      name: path.slice(path.lastIndexOf('/') + 1),
      size: entry.bytes.byteLength,
      modified: entry.modified,
    }))
  }

  async readSave(filePath: string): Promise<Uint8Array> {
    await this.ready
    const entry = this.saves.get(filePath)
    if (!entry) throw new Error(`no save at ${filePath}`)
    return entry.bytes
  }

  async writeSave(filePath: string, bytes: Uint8Array): Promise<WriteResult> {
    await this.ready
    const modified = Date.now()
    this.saves.set(filePath, { bytes, modified })
    this.persist()
    return { path: filePath, size: bytes.byteLength, modified }
  }

  async deleteSave(filePath: string): Promise<void> {
    await this.ready
    this.saves.delete(filePath)
    this.persist()
  }

  /** No OS file picker in a browser; the library list is the picker. */
  async pickSaveToImport(): Promise<ImportedSave | null> {
    return null
  }

  async pickSaveDestination(suggestedName: string): Promise<string | null> {
    return `${LIBRARY_DIR}/${suggestedName}`
  }

  async revealInFolder(): Promise<void> {
    // Nothing to reveal without a filesystem.
  }
}

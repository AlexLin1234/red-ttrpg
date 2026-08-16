/**
 * The single seam between the app and the operating system.
 *
 * Everything above this line is plain web code. `electron.ts` implements it over
 * the preload bridge; `web.ts` implements it against an in-memory library so the
 * whole app can be driven in a browser — which is how the end-to-end tests run.
 * Swapping Electron for another shell means rewriting only these two files.
 */

export interface SaveFileEntry {
  path: string
  name: string
  size: number
  modified: number
}

export interface ImportedSave {
  path: string
  name: string
  bytes: Uint8Array
}

export interface WriteResult {
  path: string
  size: number
  modified: number
}

export interface PlatformBridge {
  readonly kind: 'electron' | 'web'
  libraryDir(): Promise<string>
  listSaves(): Promise<SaveFileEntry[]>
  readSave(filePath: string): Promise<Uint8Array>
  writeSave(filePath: string, bytes: Uint8Array): Promise<WriteResult>
  deleteSave(filePath: string): Promise<void>
  pickSaveToImport(): Promise<ImportedSave | null>
  pickSaveDestination(suggestedName: string): Promise<string | null>
  revealInFolder(filePath: string): Promise<void>
}

let active: PlatformBridge | null = null

export function setBridge(bridge: PlatformBridge): void {
  active = bridge
}

export function bridge(): PlatformBridge {
  if (!active) throw new Error('platform bridge has not been installed')
  return active
}

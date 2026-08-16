import type {
  ImportedSave,
  PlatformBridge,
  SaveFileEntry,
  WriteResult,
} from './bridge'

interface RedlinePreload {
  libraryDir(): Promise<string>
  listSaves(): Promise<SaveFileEntry[]>
  readSave(filePath: string): Promise<Uint8Array>
  writeSave(filePath: string, bytes: Uint8Array): Promise<WriteResult>
  deleteSave(filePath: string): Promise<void>
  pickSaveToImport(): Promise<ImportedSave | null>
  pickSaveDestination(suggestedName: string): Promise<string | null>
  revealInFolder(filePath: string): Promise<void>
}

declare global {
  interface Window {
    redline?: RedlinePreload
  }
}

export function isElectron(): boolean {
  return typeof window !== 'undefined' && window.redline !== undefined
}

export function createElectronBridge(): PlatformBridge {
  const api = window.redline
  if (!api) throw new Error('preload bridge is missing')
  return {
    kind: 'electron',
    libraryDir: () => api.libraryDir(),
    listSaves: () => api.listSaves(),
    readSave: (filePath) => api.readSave(filePath),
    writeSave: (filePath, bytes) => api.writeSave(filePath, bytes),
    deleteSave: (filePath) => api.deleteSave(filePath),
    pickSaveToImport: () => api.pickSaveToImport(),
    pickSaveDestination: (suggestedName) => api.pickSaveDestination(suggestedName),
    revealInFolder: (filePath) => api.revealInFolder(filePath),
  }
}

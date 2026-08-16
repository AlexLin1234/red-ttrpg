import { contextBridge, ipcRenderer } from 'electron'

/**
 * The only surface the renderer gets. Every method here mirrors one entry in
 * `src/platform/bridge.ts`; nothing else from Node or Electron is exposed.
 */
const redline = {
  listSaves: () => ipcRenderer.invoke('saves:list'),
  readSave: (filePath: string) => ipcRenderer.invoke('saves:read', filePath),
  writeSave: (filePath: string, bytes: Uint8Array) =>
    ipcRenderer.invoke('saves:write', filePath, bytes),
  deleteSave: (filePath: string) => ipcRenderer.invoke('saves:delete', filePath),
  pickSaveToImport: () => ipcRenderer.invoke('saves:pick-import'),
  pickSaveDestination: (suggestedName: string) =>
    ipcRenderer.invoke('saves:pick-destination', suggestedName),
  libraryDir: () => ipcRenderer.invoke('saves:library-dir'),
  revealInFolder: (filePath: string) => ipcRenderer.invoke('saves:reveal', filePath),
}

contextBridge.exposeInMainWorld('redline', redline)

export type RedlinePreload = typeof redline

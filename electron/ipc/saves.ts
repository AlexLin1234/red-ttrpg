import { app, dialog, ipcMain, shell } from 'electron'
import { createHash } from 'node:crypto'
import fs from 'node:fs/promises'
import path from 'node:path'

const SAVE_EXTENSION = '.red'

/** `~/Documents/Redline/saves`, created on demand. */
function libraryDir(): string {
  return path.join(app.getPath('documents'), 'Redline', 'saves')
}

async function ensureLibraryDir(): Promise<string> {
  const dir = libraryDir()
  await fs.mkdir(dir, { recursive: true })
  return dir
}

/**
 * Reject any path that escapes the library directory. The renderer supplies
 * these strings, so they are treated as untrusted even though it is our own UI.
 */
function assertInsideLibrary(filePath: string): void {
  const resolved = path.resolve(filePath)
  const root = path.resolve(libraryDir())
  if (resolved !== root && !resolved.startsWith(root + path.sep)) {
    throw new Error('refusing to touch a file outside the save library')
  }
  if (path.extname(resolved).toLowerCase() !== SAVE_EXTENSION) {
    throw new Error('refusing to touch a file that is not a .red save')
  }
}

export function registerSaveIpc(): void {
  ipcMain.handle('saves:library-dir', async () => ensureLibraryDir())

  ipcMain.handle('saves:list', async () => {
    const dir = await ensureLibraryDir()
    const entries = await fs.readdir(dir, { withFileTypes: true })
    const saves = []
    for (const entry of entries) {
      if (!entry.isFile() || path.extname(entry.name).toLowerCase() !== SAVE_EXTENSION) continue
      const filePath = path.join(dir, entry.name)
      const stat = await fs.stat(filePath)
      saves.push({ path: filePath, name: entry.name, size: stat.size, modified: stat.mtimeMs })
    }
    return saves
  })

  ipcMain.handle('saves:read', async (_event, filePath: string) => {
    assertInsideLibrary(filePath)
    const bytes = await fs.readFile(filePath)
    return new Uint8Array(bytes)
  })

  ipcMain.handle('saves:write', async (_event, filePath: string, bytes: Uint8Array) => {
    assertInsideLibrary(filePath)
    await fs.mkdir(path.dirname(filePath), { recursive: true })
    // Write to a sibling temp file and rename, so a crash mid-write cannot
    // truncate an existing campaign.
    const temporary = `${filePath}.${createHash('sha1').update(String(Date.now())).digest('hex').slice(0, 8)}.tmp`
    await fs.writeFile(temporary, Buffer.from(bytes))
    await fs.rename(temporary, filePath)
    const stat = await fs.stat(filePath)
    return { path: filePath, size: stat.size, modified: stat.mtimeMs }
  })

  ipcMain.handle('saves:delete', async (_event, filePath: string) => {
    assertInsideLibrary(filePath)
    await fs.rm(filePath, { force: true })
  })

  ipcMain.handle('saves:pick-import', async () => {
    const result = await dialog.showOpenDialog({
      title: 'Import campaign',
      filters: [{ name: 'Redline campaign', extensions: ['red'] }],
      properties: ['openFile'],
    })
    const picked = result.filePaths[0]
    if (result.canceled || !picked) return null
    const bytes = await fs.readFile(picked)
    return { path: picked, name: path.basename(picked), bytes: new Uint8Array(bytes) }
  })

  ipcMain.handle('saves:pick-destination', async (_event, suggestedName: string) => {
    const dir = await ensureLibraryDir()
    const result = await dialog.showSaveDialog({
      title: 'Save campaign',
      defaultPath: path.join(dir, suggestedName),
      filters: [{ name: 'Redline campaign', extensions: ['red'] }],
    })
    return result.canceled ? null : (result.filePath ?? null)
  })

  ipcMain.handle('saves:reveal', async (_event, filePath: string) => {
    assertInsideLibrary(filePath)
    shell.showItemInFolder(filePath)
  })
}

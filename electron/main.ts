import { app, BrowserWindow, shell } from 'electron'
import path from 'node:path'
import { registerSaveIpc } from './ipc/saves'

// This file is bundled to CommonJS by scripts/build-electron.mjs, so __dirname
// is the real thing rather than an import.meta shim.
declare const __dirname: string

const dirname = __dirname
const devServerUrl = process.env.VITE_DEV_SERVER_URL

function createWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 1600,
    height: 980,
    minWidth: 1280,
    minHeight: 800,
    backgroundColor: '#0a0f15',
    show: false,
    autoHideMenuBar: true,
    title: 'Redline',
    webPreferences: {
      preload: path.join(dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  })

  window.once('ready-to-show', () => window.show())

  // Anything that is not the app itself opens in the user's browser, never in-app.
  window.webContents.setWindowOpenHandler(({ url }) => {
    void shell.openExternal(url)
    return { action: 'deny' }
  })

  if (devServerUrl) {
    void window.loadURL(devServerUrl)
  } else {
    void window.loadFile(path.join(dirname, '..', 'dist', 'index.html'))
  }

  return window
}

app.whenReady().then(() => {
  registerSaveIpc()
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

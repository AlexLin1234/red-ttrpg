import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

import { App } from './app/App'
import { StoreProvider } from './app/store'
import './design/tokens.css'
import { setBridge } from './platform/bridge'
import { createElectronBridge, isElectron } from './platform/electron'
import { WebBridge } from './platform/web'

// Electron when the preload is present, an in-memory library otherwise. The
// browser path is what `npm run dev` and the end-to-end tests use.
setBridge(isElectron() ? createElectronBridge() : new WebBridge())

const container = document.getElementById('root')
if (!container) throw new Error('#root is missing from index.html')

createRoot(container).render(
  <StrictMode>
    <StoreProvider>
      <App />
    </StoreProvider>
  </StrictMode>,
)

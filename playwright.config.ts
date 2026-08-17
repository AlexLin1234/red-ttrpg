import { defineConfig } from '@playwright/test'

/**
 * The renderer is a plain web app, so the whole four-screen flow is testable in
 * a browser with the in-memory platform bridge — no Electron, no display server.
 */
export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  reporter: process.env.CI ? 'line' : 'list',
  timeout: 60_000,
  use: {
    baseURL: 'http://127.0.0.1:4173',
    viewport: { width: 1600, height: 980 },
    launchOptions: {
      // Use the Chromium already on the machine rather than downloading one.
      executablePath:
        process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
    },
  },
  webServer: {
    command: 'npm run build:renderer && npx vite preview --port 4173 --strictPort',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
})

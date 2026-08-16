/**
 * Screenshot the built renderer.
 *
 * Usage: node scripts/shoot.mjs <out-dir> [screen ...]
 *
 * Serves `dist/` and drives it in the preinstalled Chromium with the in-memory
 * web bridge, so every screen can be looked at without Electron or a display.
 */
import { chromium } from 'playwright'
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { extname, join, normalize } from 'node:path'
import { mkdirSync } from 'node:fs'

const TYPES = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.woff2': 'font/woff2',
  '.svg': 'image/svg+xml',
  '.map': 'application/json',
}

const outDir = process.argv[2] ?? 'e2e/__screenshots__'
const screens = process.argv.slice(3)
mkdirSync(outDir, { recursive: true })

const server = createServer(async (request, response) => {
  const path = normalize(decodeURIComponent(new URL(request.url, 'http://x').pathname))
  const file = join('dist', path === '/' ? 'index.html' : path)
  try {
    const body = await readFile(file)
    response.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' })
    response.end(body)
  } catch {
    response.writeHead(404).end('not found')
  }
})
await new Promise((resolve) => server.listen(0, resolve))
const port = server.address().port

// Use the preinstalled Chromium rather than downloading one; the bundled
// revision does not have to match the Playwright package version.
const browser = await chromium.launch({
  executablePath:
    process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
})
const page = await browser.newPage({ viewport: { width: 1600, height: 980 }, deviceScaleFactor: 2 })
const errors = []
page.on('console', (message) => {
  if (message.type() === 'error') errors.push(message.text())
})
page.on('pageerror', (error) => errors.push(String(error)))

await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'networkidle' })
await page.waitForSelector('.library-row', { timeout: 15000 })
await page.waitForTimeout(500)
await page.screenshot({ path: join(outDir, '1a-library.png') })
console.log('shot 1a-library')

if (screens.length > 0) {
  await page.getByRole('button', { name: /Continue/ }).click()
  await page.waitForTimeout(700)
  for (const screen of screens) {
    await page.locator('.app-nav-item', { hasText: new RegExp(`^${screen}`, 'i') }).first().click()
    await page.waitForTimeout(900)
    await page.screenshot({ path: join(outDir, `${screen.toLowerCase()}.png`) })
    console.log(`shot ${screen.toLowerCase()}`)
  }
}

await browser.close()
server.close()
if (errors.length) {
  console.error('\nconsole errors:')
  for (const error of errors) console.error(' -', error)
  process.exitCode = 1
}

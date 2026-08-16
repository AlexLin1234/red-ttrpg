import { build } from 'esbuild'

/**
 * The Electron shell is bundled to CommonJS: the preload script must be CJS to
 * run in a sandboxed context, and keeping main.cjs alongside it avoids the
 * dual-format loader dance entirely.
 */
const shared = {
  bundle: true,
  platform: 'node',
  target: 'node20',
  format: 'cjs',
  external: ['electron'],
  sourcemap: true,
  logLevel: 'info',
}

await build({ ...shared, entryPoints: ['electron/main.ts'], outfile: 'dist-electron/main.cjs' })
await build({ ...shared, entryPoints: ['electron/preload.ts'], outfile: 'dist-electron/preload.cjs' })

/**
 * Fold the built renderer into one self-contained HTML fragment.
 *
 * Used to publish a live, clickable build of the app where a dev server is not
 * reachable — every font, stylesheet and script becomes inline, so the page
 * needs no network at all.
 *
 * Usage: node scripts/build-singlefile.mjs <out.html>
 */
import { readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

const out = process.argv[2] ?? 'dist/redline-standalone.html'
const html = await readFile('dist/index.html', 'utf8')

const cssHref = html.match(/href="\.\/(assets\/[^"]+\.css)"/)?.[1]
const jsSrc = html.match(/src="\.\/(assets\/[^"]+\.js)"/)?.[1]
if (!cssHref || !jsSrc) throw new Error('could not find the built CSS/JS in dist/index.html')

let css = await readFile(join('dist', cssHref), 'utf8')

// Fonts are the only url() references the build emits; inline each as a data URI.
const fontRefs = [...css.matchAll(/url\(\.\/([^)]+\.woff2)\)/g)]
for (const [match, file] of fontRefs) {
  const bytes = await readFile(join('dist/assets', file))
  css = css.replace(match, `url(data:font/woff2;base64,${bytes.toString('base64')})`)
}

const js = await readFile(join('dist', jsSrc), 'utf8')

const fragment = `<title>Redline GM Console</title>
<style>
${css}
/* The artifact frame does not guarantee a percentage height chain. */
html, body { height: 100%; margin: 0; }
#root { height: 100vh; min-height: 560px; }
</style>
<div id="root"></div>
<script type="module">
${js.replaceAll('</script', '<\\/script')}
</script>
`

await writeFile(out, fragment)
console.log(`${out} — ${(Buffer.byteLength(fragment) / 1024).toFixed(0)} KB`)

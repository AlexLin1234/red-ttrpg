import { fileURLToPath, URL } from 'node:url'
import react from '@vitejs/plugin-react'
// vitest/config re-exports Vite's defineConfig with the `test` block typed.
import { defineConfig } from 'vitest/config'

const resolvePath = (relative: string) => fileURLToPath(new URL(relative, import.meta.url))

export default defineConfig({
  // Electron loads the built renderer over file://, so assets must be relative.
  base: './',
  plugins: [react()],
  resolve: {
    alias: {
      '@core': resolvePath('./src/core'),
      '@app': resolvePath('./src/app'),
      '@screens': resolvePath('./src/screens'),
      '@platform': resolvePath('./src/platform'),
      '@design': resolvePath('./src/design'),
    },
  },
  server: { port: 5173, strictPort: true },
  build: { outDir: 'dist', emptyOutDir: true, sourcemap: true },
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
  },
})

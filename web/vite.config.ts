/// <reference types="vitest/config" />
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import { readFileSync } from 'node:fs'

// Same version number as the iOS and Android apps (MARKETING_VERSION in project.yml).
const appVersion = /MARKETING_VERSION:\s*"?([0-9.]+)/.exec(readFileSync(new URL('../project.yml', import.meta.url), 'utf8'))?.[1] ?? '0.1'

// Strict Content Security Policy for production builds: only our own bundled code runs,
// no network access besides our own origin, no plugins, no inline scripts.
const CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self'",
  // The public recipe list, and the espresso machine (GaggiMate) in the local network over ws://.
  "connect-src 'self' https://raw.githubusercontent.com ws:",
  "manifest-src 'self'",
  "worker-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'none'",
].join('; ')

function contentSecurityPolicy(): Plugin {
  return {
    name: 'brewlog-csp',
    apply: 'build',
    transformIndexHtml: (html) =>
      html.replace('<head>', `<head>\n    <meta http-equiv="Content-Security-Policy" content="${CSP}" />`),
  }
}

export default defineConfig({
  // Relative base: works on any host or sub-path (GitHub Pages, Netlify, Cloudflare Pages, local).
  base: './',
  plugins: [react(), contentSecurityPolicy()],
  define: { __APP_VERSION__: JSON.stringify(appVersion) },
  // Fixed ports: browsers keep BrewLog's data per address (including the port), so it must not change between runs.
  // ../Shared holds recipes.json, shared with the iOS and Android apps.
  server: { port: 5173, strictPort: true, fs: { allow: ['..'] } },
  preview: { port: 4173, strictPort: true },
  build: { target: 'es2022', sourcemap: false },
  test: { environment: 'node', include: ['tests/**/*.test.ts'] },
})

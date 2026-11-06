import { chromium } from '../web/node_modules/playwright/index.mjs'
import { createServer } from 'http'
import { readFile } from 'fs/promises'
import { existsSync, readFileSync } from 'fs'
import { resolve, extname } from 'path'

const PORT = 4180
const DIST_DIR = resolve('web/dist')
const SCREENSHOT_DIR = resolve('docs/screenshots')

const MIME = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
}

// Simple static file server for web/dist
const server = createServer(async (req, res) => {
  try {
    let urlPath = req.url.split('?')[0].split('#')[0]
    if (urlPath === '/' || urlPath === '') urlPath = '/index.html'
    let filePath = resolve(DIST_DIR, '.' + urlPath)
    if (!existsSync(filePath)) {
      filePath = resolve(DIST_DIR, 'index.html')
    }
    const data = await readFile(filePath)
    res.setHeader('Content-Type', MIME[extname(filePath)] || 'application/octet-stream')
    res.end(data)
  } catch (err) {
    res.statusCode = 500
    res.end(String(err))
  }
})

await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve))
console.log(`Server running at http://127.0.0.1:${PORT}`)

const browser = await chromium.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-gpu'],
})

const context = await browser.newContext({
  viewport: { width: 460, height: 1000 },
  colorScheme: 'dark',
  deviceScaleFactor: 2,
})

const page = await context.newPage()

// Read sample backup to seed rich data
const sampleBackup = JSON.parse(readFileSync('samples/recipes/sample-full-brewlog-backup.json', 'utf8'))

// 1. Welcome screen
console.log('Capturing welcome.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/onboarding`)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/welcome.png` })

// 2. Setup: Brewer selection (click Start setup)
console.log('Capturing setup-brewer.png...')
const startBtn = page.locator('button', { hasText: 'Start setup' })
if (await startBtn.isVisible()) {
  await startBtn.click()
  await page.waitForTimeout(500)
}
await page.screenshot({ path: `${SCREENSHOT_DIR}/setup-brewer.png` })

// 3. Quick weigh screen
console.log('Capturing quick-weigh.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/weigh`)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/quick-weigh.png` })

// 4. Seed database with rich sample data for brew setup, detail, stats, etc.
console.log('Seeding database with sample brews...')
await page.goto(`http://127.0.0.1:${PORT}/#/`)
await page.evaluate(async (data) => {
  localStorage.setItem('brewlog.settings', JSON.stringify({
    onboardingDone: true,
    setupBannerDismissed: true,
    brewMode: 'filter',
    demoScale: true,
    pressureDemo: true,
    machineKind: 'none',
  }))
  localStorage.setItem('brewlog.setup', JSON.stringify({
    recipeId: 'lance-hedrick-121-v60',
    brewerId: 'gear-sample-origami',
    grinderId: 'gear-sample-comandante',
    filterId: 'filter-sample-cafec',
    beanId: 'bean-sample-geisha',
    dose: 15.0,
    waterAmount: 250.0,
    grindValue: 24.0,
    grindText: '24 clicks',
    waterTemp: 93.0,
  }))
  localStorage.setItem('brewlog.espressoSetup', JSON.stringify({
    recipeId: 'espresso-standard-1-2',
    brewerId: 'gear-sample-robot',
    grinderId: 'gear-sample-comandante',
    beanId: 'bean-sample-geisha',
    dose: 18.0,
    waterAmount: 36.0,
    grindValue: 12.0,
    grindText: '12 clicks',
    waterTemp: 94.0,
  }))

  // Seed IndexedDB
  const DB_NAME = 'brewlog'
  const STORE = 'kv'
  const req = indexedDB.open(DB_NAME, 1)
  await new Promise((resolve, reject) => {
    req.onupgradeneeded = () => req.result.createObjectStore(STORE)
    req.onsuccess = () => {
      const db = req.result
      const tx = db.transaction(STORE, 'readwrite')
      const store = tx.objectStore(STORE)
      store.put(data, 'appdata')
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    }
    req.onerror = () => reject(req.error)
  })
}, sampleBackup)

// 5. Setup screen (main brew screen with Filter | Espresso CapsuleSwitch in TopBar)
console.log('Capturing setup.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/`)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/setup.png` })

// 6. Brew Detail & Suggestions screen
console.log('Capturing suggestions.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/brews/brew-sample-1`)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/suggestions.png` })

// 7. Pours analysis (scrolled down on brew detail)
console.log('Capturing pours.png...')
await page.evaluate(() => window.scrollBy(0, 450))
await page.waitForTimeout(400)
await page.screenshot({ path: `${SCREENSHOT_DIR}/pours.png` })

// 8. Stats screen (12-week activity, rating trend, scatter plot)
console.log('Capturing stats.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/journal`)
await page.waitForTimeout(400)
// Switch to Stats tab
const statsTab = page.locator('button', { hasText: 'Stats' })
if (await statsTab.isVisible()) {
  await statsTab.click()
  await page.waitForTimeout(600)
}
await page.screenshot({ path: `${SCREENSHOT_DIR}/stats.png` })

// 9. Extraction Calculator tool
console.log('Capturing tools-extraction.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/tools/extraction`)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/tools-extraction.png` })

// 10. Water Calculator tool
console.log('Capturing tools-water.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/tools/water`)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/tools-water.png` })

// 11. Grind Converter tool
console.log('Capturing tools-grind.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/tools/grind`)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/tools-grind.png` })

await browser.close()
server.close()
console.log('All screenshots captured successfully!')

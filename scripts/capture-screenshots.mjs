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

// 1. Welcome screen (clean onboarding state)
console.log('Capturing welcome.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/onboarding`)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/welcome.png` })

// 2. Setup: Brewer selection
console.log('Capturing setup-brewer.png...')
const startBtn = page.locator('button', { hasText: 'Start setup' })
if (await startBtn.isVisible()) {
  await startBtn.click()
  await page.waitForTimeout(500)
}
await page.screenshot({ path: `${SCREENSHOT_DIR}/setup-brewer.png` })

// 3. Setup: Grinder selection
console.log('Capturing setup-grinder.png...')
const firstBrewer = page.locator('.tile', { hasText: 'Origami' }).first()
if (await firstBrewer.isVisible()) {
  await firstBrewer.click()
  await page.waitForTimeout(400)
}
const nextBtn = page.locator('button', { hasText: 'Next' }).first()
if (await nextBtn.isVisible()) {
  await nextBtn.click()
  await page.waitForTimeout(500)
}
await page.screenshot({ path: `${SCREENSHOT_DIR}/setup-grinder.png` })

// 4. Quick weigh screen
console.log('Capturing quick-weigh.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/weigh`)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/quick-weigh.png` })

// --- Generate Rich Mock Data ---
console.log('Generating rich mock data for stats and brew detail...')
const recipesJson = JSON.parse(readFileSync('Shared/recipes.json', 'utf8'))
const lanceRecipe = recipesJson.find((r) => r.id === 'lance-hedrick-121-v60') || recipesJson[0]
const hoffmannRecipe = recipesJson.find((r) => r.id === 'hoffmann-1cup-v60') || recipesJson[1]

const now = Date.now()

const beans = [
  {
    id: 'bean-sample-geisha',
    name: 'Panama Geisha Natural',
    roaster: 'Finca Deborah',
    origin: 'Panama, Boquete',
    varietal: 'Geisha',
    process: 'natural',
    roastLevel: 'light',
    roastDate: now - 14 * 86_400_000,
    tastingNotes: 'Jasmine, bergamot, peach, wild strawberry',
    notes: 'Competition lot with vibrant floral complexity',
    bagWeight: 200.0,
    remaining: 155.0,
    isArchived: false,
    createdAt: now - 75 * 86_400_000,
  },
  {
    id: 'bean-sample-guji',
    name: 'Ethiopia Guji Hambela',
    roaster: 'Dakata Roastery',
    origin: 'Ethiopia, Guji',
    varietal: 'Heirloom',
    process: 'washed',
    roastLevel: 'light',
    roastDate: now - 21 * 86_400_000,
    tastingNotes: 'Jasmine tea, lemon candy, peach blossom',
    notes: 'Crisp and ultra-clean classic washed profile',
    bagWeight: 250.0,
    remaining: 190.0,
    isArchived: false,
    createdAt: now - 75 * 86_400_000,
  },
  {
    id: 'bean-sample-colombia',
    name: 'Colombia El Paraiso',
    roaster: 'Manhattan Coffee Roasters',
    origin: 'Colombia, Cauca',
    varietal: 'Castillo',
    process: 'anaerobic',
    roastLevel: 'light',
    roastDate: now - 10 * 86_400_000,
    tastingNotes: 'Red plum, lychee, bubblegum, raspberry',
    notes: 'Thermal shock anaerobic fermentation',
    bagWeight: 250.0,
    remaining: 160.0,
    isArchived: false,
    createdAt: now - 75 * 86_400_000,
  },
]

const equipment = [
  {
    id: 'gear-sample-origami',
    name: 'Origami Dripper M',
    type: 'brewer',
    notes: 'Matte pink ceramic',
    method: 'v60',
    createdAt: now - 75 * 86_400_000,
  },
  {
    id: 'gear-sample-robot',
    name: 'Cafelat Robot',
    type: 'brewer',
    notes: 'Retro green manual lever',
    method: 'espresso',
    createdAt: now - 75 * 86_400_000,
  },
  {
    id: 'gear-sample-comandante',
    name: 'Comandante C40 MK4',
    type: 'grinder',
    notes: 'Red Clix installed',
    grinder: {
      unit: 'clicks',
      step: 1.0,
      adjustStep: 2.0,
      finerIsLower: true,
      minClicks: 10.0,
      maxClicks: 40.0,
      rangeNote: 'pour-over 20–28 clicks',
      defaultGrind: 24.0,
      micronsPerStep: 30.0,
    },
    createdAt: now - 75 * 86_400_000,
  },
  {
    id: 'gear-sample-cafec',
    name: 'CAFEC Abaca',
    type: 'filter',
    notes: 'Fast flow refined abaca fibers',
    filterFlow: 'fast',
    idealRoast: 'light',
    createdAt: now - 75 * 86_400_000,
  },
]

// Generate realistic samples for brew-sample-1
const sample1Samples = []
for (let t = 0; t <= 178; t += 0.5) {
  let w = 0
  if (t <= 12) {
    w = (t / 12) * 50
  } else if (t < 45) {
    w = 50
  } else if (t <= 70) {
    w = 50 + ((t - 45) / 25) * 200.2
  } else {
    w = 250.2
  }
  sample1Samples.push({ t: Math.round(t * 10) / 10, w: Math.round(w * 10) / 10 })
}

const showcaseBrew = {
  id: 'brew-sample-1',
  date: now - 2 * 3600 * 1000,
  recipeId: lanceRecipe.id,
  recipeName: lanceRecipe.name,
  recipe: lanceRecipe,
  dose: 15.0,
  targetWater: 250.0,
  finalWeight: 250.2,
  totalTime: 178.0,
  waterTemp: 94.0,
  grindSetting: '24 clicks',
  grindValue: 24.0,
  suggestedGrind: 24.0,
  brewerId: 'gear-sample-origami',
  brewerName: 'Origami Dripper M',
  grinderId: 'gear-sample-comandante',
  grinderName: 'Comandante C40 MK4',
  grinderSpec: equipment[2].grinder,
  filterId: 'gear-sample-cafec',
  filterName: 'CAFEC Abaca',
  filterFlow: 'fast',
  filterIdealRoast: 'light',
  beanId: 'bean-sample-geisha',
  usedScale: true,
  rating: 5,
  feedback: ['perfect'],
  tds: 1.38,
  drinkWeight: 220.0,
  notes: 'Exceptional jasmine clarity, explosive peach sweetness and a delicate tea-like body.',
}

// Generate 18 pour-over brews spread across 12 weeks for beautiful activity & rating curves
const brews = [showcaseBrew]
const ratingsPattern = [5, 4, 5, 5, 4, 5, 4, 5, 4, 5, 4, 4, 5, 4, 5, 4, 4]

for (let w = 0; w < 12; w++) {
  const weekStart = now - w * 7 * 86_400_000
  const count = w === 0 ? 1 : (w % 3 === 0 ? 2 : 1)
  for (let c = 0; c < count; c++) {
    const brewIndex = brews.length
    const isLance = brewIndex % 2 === 0
    const rec = isLance ? lanceRecipe : hoffmannRecipe
    const bean = brewIndex % 3 === 0 ? beans[0] : brewIndex % 3 === 1 ? beans[1] : beans[2]
    const rating = ratingsPattern[brewIndex % ratingsPattern.length]
    brews.push({
      id: `brew-hist-${w}-${c}`,
      date: weekStart - c * 2 * 86_400_000 - 86_400_000,
      recipeId: rec.id,
      recipeName: rec.name,
      recipe: rec,
      dose: 15.0,
      targetWater: 250.0,
      finalWeight: 250.0 + (brewIndex % 3) * 0.4,
      totalTime: 174.0 + (brewIndex % 5) * 2,
      waterTemp: 94.0,
      grindSetting: `${23 + (brewIndex % 3)} clicks`,
      grindValue: 23.0 + (brewIndex % 3),
      suggestedGrind: 24.0,
      brewerId: 'gear-sample-origami',
      brewerName: 'Origami Dripper M',
      grinderId: 'gear-sample-comandante',
      grinderName: 'Comandante C40 MK4',
      grinderSpec: equipment[2].grinder,
      filterId: 'gear-sample-cafec',
      filterName: 'CAFEC Abaca',
      filterFlow: 'fast',
      filterIdealRoast: 'light',
      beanId: bean.id,
      usedScale: true,
      rating,
      feedback: rating === 5 ? ['perfect'] : [],
      tds: 1.34 + (brewIndex % 4) * 0.02,
      drinkWeight: 219.0 + (brewIndex % 3),
      notes: 'Clean, sweet and vibrant fruit cup.',
    })
  }
}

// Add 3 espresso shots for Cafelat Robot
for (let s = 0; s < 3; s++) {
  brews.push({
    id: `brew-espresso-${s}`,
    date: now - s * 5 * 86_400_000 - 3600_000,
    recipeId: 'espresso-standard-1-2',
    recipeName: 'Standard Espresso 1:2',
    recipe: {
      id: 'espresso-standard-1-2',
      name: 'Standard Espresso 1:2',
      method: 'espresso',
      dose: 18.0,
      water: 36.0,
      targetTime: 28.0,
      steps: [],
    },
    dose: 18.0,
    targetWater: 36.0,
    finalWeight: 36.4,
    totalTime: 28.5,
    waterTemp: 94.0,
    grindSetting: '12 clicks',
    grindValue: 12.0,
    suggestedGrind: 12.0,
    brewerId: 'gear-sample-robot',
    brewerName: 'Cafelat Robot',
    grinderId: 'gear-sample-comandante',
    grinderName: 'Comandante C40 MK4',
    grinderSpec: equipment[2].grinder,
    filterId: null,
    filterName: '',
    filterFlow: null,
    filterIdealRoast: null,
    beanId: 'bean-sample-geisha',
    usedScale: true,
    rating: 5,
    feedback: ['perfect'],
    tds: 9.6,
    drinkWeight: 36.4,
    notes: 'Syrupy body, vibrant bergamot acidity and velvety crema.',
  })
}

const mockAppData = {
  beans,
  equipment,
  brews,
  customRecipes: [],
}

const localSettings = {
  'brewlog.settings': {
    onboardingDone: true,
    setupBannerDismissed: true,
    brewMode: 'filter',
    demoScale: true,
    pressureDemo: true,
    machineKind: 'none',
    onlineRecipes: false,
  },
  'brewlog.setup': {
    recipeId: lanceRecipe.id,
    brewerId: 'gear-sample-origami',
    grinderId: 'gear-sample-comandante',
    filterId: 'gear-sample-cafec',
    beanId: 'bean-sample-geisha',
    dose: 15.0,
    waterAmount: 250.0,
    grindValue: 24.0,
    grindText: '24 clicks',
    waterTemp: 94.0,
  },
  'brewlog.espressoSetup': {
    recipeId: 'espresso-standard-1-2',
    brewerId: 'gear-sample-robot',
    grinderId: 'gear-sample-comandante',
    beanId: 'bean-sample-geisha',
    dose: 18.0,
    waterAmount: 36.0,
    grindValue: 12.0,
    grindText: '12 clicks',
    waterTemp: 94.0,
  },
}

// 5. Seed database & local storage
console.log('Seeding IndexedDB with brews and samples...')
await page.goto(`http://127.0.0.1:${PORT}/#/`)
await page.evaluate(
  async ({ appdata, samples, settings }) => {
    // Write local storage
    for (const [k, v] of Object.entries(settings)) {
      localStorage.setItem(k, JSON.stringify(v))
    }

    // Write IndexedDB
    const DB_NAME = 'brewlog'
    const STORE = 'kv'
    const req = indexedDB.open(DB_NAME, 1)
    await new Promise((resolve, reject) => {
      req.onupgradeneeded = () => req.result.createObjectStore(STORE)
      req.onsuccess = () => {
        const db = req.result
        const tx = db.transaction(STORE, 'readwrite')
        const store = tx.objectStore(STORE)
        store.put(appdata, 'appdata')
        store.put(samples, 'samples:brew-sample-1')
        tx.oncomplete = () => resolve()
        tx.onerror = () => reject(tx.error)
      }
      req.onerror = () => reject(req.error)
    })

    if (window.repository) {
      window.repository.data.set(appdata)
      window.repository.cacheSamples('brew-sample-1', samples)
    }
    if (window.scale) {
      window.scale.setDemo(true)
    }
    if (window.setup) {
      window.setup.adopt(appdata)
    }
    if (window.espressoSetup) {
      window.espressoSetup.adopt(appdata)
    }
  },
  { appdata: mockAppData, samples: sample1Samples, settings: localSettings },
)

// 6. Brew setup screen (main brew tab with loaded recipe, gear and TopBar switch)
console.log('Capturing setup.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/brew`)
await page.evaluate((data) => {
  if (window.scale) window.scale.setDemo(true)
  if (window.setup) window.setup.adopt(data)
}, mockAppData)
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/setup.png` })

// 7. Pour analysis (top of brew detail with pour curve chart & metrics)
console.log('Capturing pours.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/brews/brew-sample-1`)
await page.waitForSelector('.title')
await page.evaluate(() => window.scrollTo(0, 0))
await page.waitForTimeout(600)
await page.screenshot({ path: `${SCREENSHOT_DIR}/pours.png` })

// 8. Suggestions ("What to try next": scrolled to taste, suggestions and brew findings)
console.log('Capturing suggestions.png...')
await page.evaluate(() => window.scrollTo(0, 360))
await page.waitForTimeout(500)
await page.screenshot({ path: `${SCREENSHOT_DIR}/suggestions.png` })

// 9. Statistics screen (with 12-week activity, rating trend, and clean spacing)
console.log('Capturing stats.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/journal`)
await page.waitForTimeout(500)
const statsTab = page.locator('.topbar button', { hasText: 'Stats' })
if (await statsTab.isVisible()) {
  await statsTab.click()
  await page.waitForTimeout(600)
}
await page.waitForSelector('svg')
await page.screenshot({ path: `${SCREENSHOT_DIR}/stats.png` })

// 10. Extraction Calculator tool (with populated inputs and rendered chart)
console.log('Capturing tools-extraction.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/tools/extraction`)
await page.waitForTimeout(500)
const tdsInput = page.locator('input[placeholder="e.g. 1.35"]')
if (await tdsInput.isVisible()) {
  await tdsInput.fill('1.38')
  await page.waitForTimeout(500)
}
await page.screenshot({ path: `${SCREENSHOT_DIR}/tools-extraction.png` })

// 11. Water Calculator tool
console.log('Capturing tools-water.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/tools/water`)
await page.waitForTimeout(500)
await page.screenshot({ path: `${SCREENSHOT_DIR}/tools-water.png` })

// 12. Grind Converter tool
console.log('Capturing tools-grind.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/tools/grind`)
await page.waitForTimeout(600)
const grindSelects = page.locator('select.input')
if (await grindSelects.count() >= 2) {
  await grindSelects.nth(0).selectOption({ index: 0 })
  await grindSelects.nth(1).selectOption({ index: 1 })
}
const settingInput = page.locator('.field input[type="text"]').first()
if (await settingInput.isVisible()) {
  await settingInput.fill('24')
  await page.waitForTimeout(400)
}
await page.screenshot({ path: `${SCREENSHOT_DIR}/tools-grind.png` })

// 13. Brewing screen (live brew session)
console.log('Capturing brewing.png...')
await page.goto(`http://127.0.0.1:${PORT}/#/brew`)
await page.waitForTimeout(400)
const startBrewBtn = page.locator('button', { hasText: 'Start brew' })
if (await startBrewBtn.isVisible()) {
  await startBrewBtn.click()
  await page.waitForTimeout(800)
  await page.screenshot({ path: `${SCREENSHOT_DIR}/brewing.png` })
}

await browser.close()
server.close()
console.log('All screenshots captured successfully!')
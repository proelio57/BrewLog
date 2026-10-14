# BrewLog for the web (PWA)

The web version of BrewLog: a **Progressive Web App** with the same features and the same analysis rules as the iOS and Android apps. It runs in the browser, can be added to the home screen, works offline, and can be hosted **for free**. You don't need an Apple or Google developer account.

- BOOKOO Themis Mini over **Web Bluetooth**, or the built-in demo scale
- Guided brewing: auto-start on the first pour, a soft ping just before each target, a chime when each step starts, and a countdown ring
- One chart with weight (left axis) and flow in g/s (right axis) against the recipe curve
- Setup assistant, Quick weigh, recipes (incl. your own), beans, gear (CAFEC/Hario filters, grinder scales), journal
- Rule-based taste feedback with concrete grind suggestions ("go from 24 to 22 clicks"), filter- and roast-aware
- Backup export/import (one JSON file) to move your journal between devices

## Which browser?

Web Bluetooth (needed for the scale) isn't available in every browser. Everything else (timer, demo scale, journal, analysis) works everywhere.

| Device | Browser | BOOKOO scale |
|---|---|---|
| iPhone / iPad | **Bluefy – Web BLE Browser** (free, App Store) | ✅ |
| iPhone / iPad | Safari, Chrome, Firefox … | ❌ Apple doesn't allow Bluetooth in these. Timer and demo scale only |
| Android | Chrome | ✅ |
| Windows, macOS | Chrome or Edge | ✅ |
| Any | Firefox | ❌ |

Web Bluetooth and offline mode need **HTTPS** (or `localhost`). All the free hosts below give you HTTPS automatically.

## Run it on your computer

Needs [Node.js](https://nodejs.org) 22.12 or newer.

```bash
cd web
npm install
npm run dev        # http://localhost:5173 (demo scale works; Bluetooth too, in Chrome/Edge)
npm test           # 32 unit tests: same scenarios and numbers as the iOS and Android tests
npm run build      # type check + production build → web/dist (static files, ~125 KB gzipped)
npm run preview    # serves web/dist on http://localhost:4173
```

## Put it online for free

`npm run build` creates the folder `web/dist`. It contains only static files, so any static host works. The app uses relative paths, so it also works in a sub-folder.

**Cloudflare Pages** (free account):
1. <https://dash.cloudflare.com> → **Workers & Pages** → **Create** → **Pages** → upload your files (*Direct Upload*).
2. Name the project (e.g. `brewlog`) and drag the `web/dist` folder in.
3. Your app is live at `https://brewlog.pages.dev` (or similar).

**Netlify** (free account):
1. <https://app.netlify.com/drop> → drag the `web/dist` folder in.
2. Your app is live at `https://<random-name>.netlify.app`. You can rename it under *Site configuration*.

**GitHub Pages** works too, but on the free GitHub plan only from a **public** repository.

To publish an update, run `npm run build` again and upload the new `dist` folder the same way. The app picks up the new version the next time it's opened (if it's already open, close and reopen it).

Both Cloudflare Pages and Netlify also apply the extra security headers from `public/_headers`.

## Install it on your phone

**iPhone** (with the scale):
1. Install **Bluefy** from the App Store.
2. Open your BrewLog address in Bluefy and add it to Bluefy's favourites.

Safari's *Add to Home Screen* also works, but only for the timer and demo scale, because Safari has no Bluetooth. Safari and Bluefy keep **separate data**; use the backup to move it.

**Android**: open the address in Chrome → menu ⋮ → **Add to Home screen** / **Install app**. It opens full screen, works offline and can use Bluetooth.

**Computer**: in Chrome or Edge, click the install icon at the right of the address bar.

## Using the BOOKOO scale

Switch the scale on. Brew tab → tap the scale card → **Search for BOOKOO** → pick it in the browser's list.

- If the connection drops while the app is open (e.g. the scale went to sleep), BrewLog reconnects by itself.
- After reopening the app, tap **Search** again. Browsers don't let websites reconnect to a Bluetooth device silently.

## Sounds, vibration and screen

- **Sounds** start working after your first tap (a browser rule). On iPhone the silent switch can mute websites; BrewLog asks for "playback" audio where the browser supports it. Test the sounds in **Settings → Sound & vibration**.
- **Vibration** works on Android only. iPhone browsers don't support it.
- The **screen stays on** while brewing (Screen Wake Lock), if the browser supports it.

## Your data

- Everything is stored **in this browser on this device** (IndexedDB). There's no server, no account and no analytics.
- **Settings → Backup → Export backup** saves a JSON file with all brews (including weight curves), beans, gear and your recipes. **Import** replaces all data on the device with a backup.
- Browsers can delete website data, e.g. when you clear browsing data, and Safari after 7 days without a visit. BrewLog asks the browser to keep its storage, but **export a backup now and then**.

## Project structure

```
index.html, public/     App shell, manifest, icons, service worker (sw.js), _headers
src/domain/             Recipes (recipes.json = copy of Shared/recipes.json), models, validation, presets   (pure)
src/scale/              BOOKOO protocol + validator (pure), Web Bluetooth ScaleManager, DemoScale
src/brewing/            BrewSession: auto-start, pings, countdown, recording                              (pure)
src/analysis/           BrewAnalyzer + GrindRecommender                                                   (pure)
src/data/               IndexedDB repository + backup, settings, brew setup state
src/audio/              Synthesized cues (Web Audio), vibration, wake lock
src/ui/, src/screens/   Components, SVG chart, screens. Shell.tsx = routes + tab bar
tests/                  Unit tests (Vitest), incl. a check that recipes.json matches Shared/recipes.json
```

The pure TypeScript parts are 1:1 ports of the Swift/Kotlin code, with identical thresholds, suggestion keys and priorities. React 19 and lucide-react (icons) are the only runtime dependencies, bundled at build time; there's no state library (a small `Store` + `useSyncExternalStore`), and the chart is plain SVG.

## Security & privacy

- **Strict Content Security Policy** in production builds: only the app's own bundled scripts run, no inline scripts, no connections to other servers (`connect-src 'self'`), no plugins. No third-party scripts, fonts, CDNs or trackers.
- **Bluetooth input is untrusted**: packets are length-, header- and range-checked, and checksums are verified once the firmware is known to use them. Device names are sanitized.
- **Write allowlist**: only four fixed commands (tare, start, stop and reset the timer) can ever be written to the scale.
- **Backup files are untrusted**: max. 50 MB, every field is parsed, validated and clamped, IDs are restricted to safe characters, and text is always rendered as text.
- **User input** (recipes, beans, gear, numbers) is sanitized and clamped. Stored data is re-validated when loaded.
- `public/_headers` adds clickjacking protection and other security headers on Cloudflare Pages and Netlify.

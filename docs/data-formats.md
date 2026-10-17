# Data formats

Shared by the iOS, Android and web apps, so files can move between them. iOS and web implement everything below;
Android's gaps are listed in the checklist at the end.

## Recipe files

The same JSON as `Shared/recipes.json`. A file can hold a single recipe object, a list of recipes, or
`{ "recipes": [ ... ] }`. Only `name` and `steps` are required; everything else gets the defaults of a new
recipe. All values are validated and clamped on import (see `RecipeValidation.swift`).

```json
{
  "name": "Morning V60",
  "author": "Me",
  "method": "v60",
  "dose": 15,
  "water": 250,
  "temperature": 94,
  "targetTime": 180,
  "steps": [
    { "kind": "bloom", "time": 0, "target": 45, "note": "Swirl gently" },
    { "kind": "pour", "time": 45, "target": 150 },
    { "kind": "pour", "time": 75, "target": 250 }
  ]
}
```

| Field | Default | Notes |
|---|---|---|
| `id` | new `custom-<uuid>` | A file can't replace a built-in recipe: a built-in id becomes a copy. Same id as one of your recipes = update it |
| `method` | `universal` | `v60`, `switch`, `kalita`, `universal`, `espresso` |
| `dose`, `temperature` | 15 g, 94 °C | |
| `water` | last pour target | |
| `targetTime` | last step + 60 s | seconds |
| `flowMin`, `flowMax` | 3, 8 | g/s |
| `steps[].kind` | – | `bloom`, `pour`, `swirl`, `stir`, `closeValve`, `openValve`, `remove`, `preinfuse`, `extract` |
| `steps[].time` | – | seconds from start |
| `steps[].target` | – | cumulative grams on the scale (pours and blooms) |
| `steps[].valve` | – | `open` / `closed` (Hario Switch) |
| `pressure` | – | Espresso only: peak pressure in bar (e.g. 9, turbo shots 6) |

**Espresso recipes** use `"method": "espresso"`, `water` = yield in the cup, `targetTime` = shot time,
`flowMin`/`flowMax` = g/s in the cup, and two steps: `preinfuse` at 0 s, then `extract` with the yield as target
at the time the first drops are expected. Apps that don't know a method or step kind skip just that recipe.

Export (iOS): a recipe's **⋯ → Share as file**, or **Recipes → + → Share my recipes**.

## BrewLog backup

One JSON file with everything: **Settings → Backup & import → Export backup** (iOS, web). Importing it on any
device merges: what isn't there yet (by `id`) is added, nothing is replaced or deleted, so importing the same file
twice adds nothing. The same **Import** also reads recipe files and Beanconqueror backups (detected by content).

```json
{
  "app": "BrewLog", "format": 1, "exportedAt": "2026-10-17T08:00:00.000Z",
  "data": { "version": 1, "beans": [], "equipment": [], "brews": [], "customRecipes": [] },
  "samples": { "<brewId>": [[0, 0], [1.5, 12.3]] },
  "machine": { "<brewId>": [{ "t": 0, "p": 1.5, "c": 92.5, "f": 2.1 }] }
}
```

- Dates are milliseconds since 1970 (whole numbers). Ids are strings: lowercase UUIDs from iOS and Android; the web
  app falls back to `id-<time>-<random>` without a secure context. iOS stores UUIDs and maps other ids to a stable
  UUID, so references and de-duplication still work.
- `samples`: weight curve per brew as `[seconds, grams]` pairs (`{t, w}` objects are read too). `machine`: espresso
  pressure/temperature/flow per brew (see Espresso shots). Only stored for brews the import adds.
- **Bean:** `id, name, roaster, origin, varietal, process, roastLevel, roastDate (or null), tastingNotes, notes,
  bagWeight, remaining, isArchived, createdAt, externalId`.
- **Equipment:** `id, name, type (brewer|grinder|kettle|filter|scale|water), notes, method, filterFlow, idealRoast,
  grinder {unit, step, adjustStep, finerIsLower, rangeNote, defaultGrind}, createdAt, externalId`; iOS also writes
  `isFavorite`.
- **Brew:** `id, date, recipeId, recipeName, recipe (snapshot of the scaled recipe or null), dose, targetWater,
  finalWeight, totalTime, waterTemp, grindSetting, grindValue, suggestedGrind, brewerId, brewerName, grinderId,
  grinderName, grinderSpec, filterId, filterName, filterFlow, filterIdealRoast, beanId, usedScale, rating (0–5),
  feedback ([perfect|sour|bitter|weak|strong|astringent|flat]), notes, externalId`.
- `customRecipes`: recipe objects as in recipe files.
- Android (for now) exports the bare `data` object (no wrapper, no curves); it's read the same way.
- The file is untrusted: every field is optional with the defaults of a new item, text is sanitized and limited,
  numbers are clamped (e.g. dose ≤ 150 g, water ≤ 3000 g, time ≤ 30 min), unknown fields and enum values are
  ignored, a broken entry (e.g. a bean without a name) only drops itself. Limits: 1000 beans, 1000 gear,
  10 000 brews, 500 recipes, 18 010 samples per brew, 200 MB per file.

## Espresso shots

A brew with an espresso recipe may carry `machineSamplesData`: `[{"t": seconds, "p": bar, "c": °C, "f": ml/s}]`
recorded from the machine (about 2–5 per second). The analysis (`EspressoAnalyzer.swift`) uses shot time vs. target
(±3 s), ratio vs. target (±0.2), time to the first gram in the cup, peak pressure vs. the recipe and sudden pressure
drops of ≥ 2 bar within 2 s (channeling).

### GaggiMate

WebSocket `ws://<host>/ws` (default host `gaggimate.local`), JSON messages with a `tp` field
(spec: `docs/websocket-api.yaml` in jniebuhr/gaggimate).

- Read: `evt:status` frames are partial and merged (missing key = unchanged, `null` = cleared). Telemetry every
  500 ms: `ct`/`tt` temperature/target, `pr`/`pt` pressure/target, `fl` pump flow, `cw` weight from GaggiMate's own
  scale (`bc` = scale connected), `process` `{a: 1 active, s: "infusion" | "brew" | "grind", u: 1 utility}`. Slow
  state: `m` mode (0 standby, 1 brew, 2 steam, 3 water), `p` profile, `cp` pressure sensor, `sys.s` system state.
  A shot is running while `process.a == 1`, `s` is `infusion` or `brew` and `u != 1`.
- Control: `req:change-mode {mode}`, `req:process:activate {ignoreWarnings}`, `req:process:deactivate`,
  `req:raise-temp` / `req:lower-temp`, `req:scale:tare`. A blocked start answers with `evt:brew:confirm {warn}`.
- Profiles: `req:profiles:save {rid, profile}` → `res:profiles:save {rid, profile.id}`, then
  `req:profiles:select {rid, id}`. BrewLog's profiles are named `BrewLog · <recipe>`: a pre-infusion phase at 3 bar
  (needs a pressure sensor), then the recipe's pressure with a 2 s linear ramp, stopped by a volumetric target at the
  yield when GaggiMate has a scale, otherwise by time. The profile id per recipe is remembered to update it next time.

## Online recipe list

`Shared/recipes.json` is published by `.github/workflows/recipes.yml` to
`https://raw.githubusercontent.com/<RELEASE_REPO>/sidestore/recipes.json`. The URL is baked into the app at
build time (`RECIPE_FEED_URL`, Info.plist key `BrewLogRecipeFeedURL`; empty = feature off).

- Checked at launch and when the app comes to the foreground, at most every 6 hours. Max 1 MB, HTTPS only.
- Merge rule: built-in recipes keep their order, an online recipe with the same `id` replaces it, new ids are
  appended. Online recipes are presets (not editable, can be duplicated). User recipes are never touched.
- The last good download is cached on the device; a broken or unreachable list keeps the old one.

## Beanconqueror import

Beanconqueror's **Settings → Export** produces `Beanconqueror.zip` (older versions: `Beanconqueror.json`).
The ZIP contains `Beanconqueror.json` plus chunks `Beanconqueror_Brews_<n>.json` / `Beanconqueror_Beans_<n>.json`
for large backups (stored or deflated entries). Mapping:

| Beanconqueror | BrewLog |
|---|---|
| `BEANS[]` name, roaster, roastingDate, weight, aromatics, note, finished | Bean (finished → archived, remaining = weight − doses used) |
| `bean_information[0]` country, region, variety, processing | origin, varietal, process (text match: washed / natural / honey / anaerobic / other) |
| `roast` (`ROASTS_ENUM`) | Cinnamon/New England/Half City → light, American/Moderate-Light → medium-light, City/City+ → medium, Full City(+) → medium-dark, Vienna/French/Italian → dark |
| `MILL[]` | Grinder (known models get the preset's scale, e.g. Comandante) |
| `PREPARATION[]` (skipped if finished and unused) | Brewer; `type` V60/Origami/Kono/… → V60, HARIO_SWITCH → Switch, KALITA_WAVE/OREA/APRIL… → flat bottom |
| `BREWS[]` `config.unix_timestamp` (seconds) | date |
| `grind_weight` | dose |
| `brew_quantity` (else `brew_beverage_quantity`) | water / final weight |
| `brew_time` + `brew_time_milliseconds` / 1000 | total time |
| `brew_temperature`, `note` | water temp, notes |
| `grind_size` | grind text; numeric (`24`, `7,5`) → grind value on the grinder's scale |
| `rating` on `SETTINGS[0].brew_rating` scale (default 5) | 1–5 stars, 0 = not rated |

Imported items remember their Beanconqueror id (`externalID = "beanconqueror:<uuid>"`), so importing the same
backup again only adds what's new. Gear with the same name as existing gear is reused. Brews have no recipe and
no pour curve; choosing a recipe via **Edit** enables the analysis.

## Porting checklist (Android)

Web has everything above. Android still needs:

- [ ] BrewLog backup in the wrapped format above: export with `samples`/`machine`, import that detects
  `"app": "BrewLog"` (today Android exports and reads only the bare `data` object, without curves)
- [ ] Espresso: shot screen, espresso analysis, GaggiMate (started on branch `wip/android-espresso-parity`)

Test data: `BrewLogTests/ImportTests.swift` (`backupJSON`, ZIP fixtures) and `BrewLogTests/BackupTests.swift`
(`webBackupJSON`, a web backup with broken entries) can be reused as fixtures.

# Data formats

Shared by the iOS, Android and web apps, so files can move between them. iOS implements everything below.
Android and web read the same `recipes.json` today; import/export, the online list and the Beanconqueror import
are still to do there (see the checklist at the end).

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

## Porting checklist (Android / web)

- [ ] Lenient recipe decoding (defaults above) + recipe file import/export
- [ ] Online recipe list with the same merge rule and cache
- [ ] Beanconqueror import (ZIP reader + mapping above, `externalID` for de-duplication)
- [ ] Edit a saved brew (date, recipe, dose, water, time, temperature, brewer, grinder, filter)
- [ ] Espresso: recipes (`espresso`, `preinfuse`, `extract`, `pressure`), shot screen, espresso analysis, GaggiMate
- [ ] App icon from `web/public/icon.svg` (already used by the web app)

Test data: `BrewLogTests/ImportTests.swift` (`backupJSON`, ZIP fixtures) can be reused as fixtures.

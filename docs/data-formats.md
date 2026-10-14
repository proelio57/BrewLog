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
| `method` | `universal` | `v60`, `switch`, `kalita`, `universal` |
| `dose`, `temperature` | 15 g, 94 °C | |
| `water` | last pour target | |
| `targetTime` | last step + 60 s | seconds |
| `flowMin`, `flowMax` | 3, 8 | g/s |
| `steps[].kind` | – | `bloom`, `pour`, `swirl`, `stir`, `closeValve`, `openValve`, `remove` |
| `steps[].time` | – | seconds from start |
| `steps[].target` | – | cumulative grams on the scale (pours and blooms) |
| `steps[].valve` | – | `open` / `closed` (Hario Switch) |

Export (iOS): a recipe's **⋯ → Share as file**, or **Recipes → + → Share my recipes**.

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
- [ ] App icon from `web/public/icon.svg` (already used by the web app)

Test data: `BrewLogTests/ImportTests.swift` (`backupJSON`, ZIP fixtures) can be reused as fixtures.

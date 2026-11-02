# Brew Statistics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Stats view in the Journal tab with separate pour-over and espresso statistics: activity, rating trend, ratios and times, beans and recipes, with charts.

**Architecture:** A pure `BrewStats` module computes everything from plain `BrewStats.Entry` values; a thin adapter turns SwiftData `Brew`s into entries (using `EspressoAnalyzer.firstDrops` / `pressureSummary` and `Extraction` for espresso and TDS numbers); SwiftUI + Swift Charts views only draw.

**Tech Stack:** Swift 5 mode, SwiftUI, Swift Charts, SwiftData, iOS 17; XCTest; Linux runner `scripts/test-pure-swift.sh` (created in the espresso plan, Task 1).

**Spec:** `docs/superpowers/specs/2026-11-02-espresso-tab-and-stats-design.md` (part B)

## Global Constraints

- iOS only (Android paused, web later; parity guide rows with Android "No (paused)", Web "No").
- Placement: Journal tab, segmented control *Journal | Stats*; inside Stats: *Pour-over | Espresso* and range *30 days | 90 days | All*.
- Weeks: the last 12 calendar weeks (Monday start, `Calendar(identifier: .iso8601)` in the views; tests pass a calendar), oldest first.
- Trend verdict from the least-squares slope of the weekly average rating over the weeks that have ratings: > +0.05 ★/week "Improving", < −0.05 "Declining", else "Steady"; fewer than 3 rated weeks → no verdict.
- Channeling sign: sudden pressure drop ≥ 2 bar or first drops < 3 s (same thresholds as `EspressoAnalyzer`).
- Unrated brews (rating 0) never count toward averages.
- Copy is English, sentence case.
- Verification: pure logic with `bash scripts/test-pure-swift.sh BrewLogTests/BrewStatsTests.swift BrewLog/Analysis/BrewStats.swift`; everything with iOS CI (same commands as the espresso plan).

## Review Focus

- No brews in the range (new user, or only espresso while looking at pour-over): every section shows an empty state, no chart crashes on empty data (`testEmptyInputGivesEmptyStats`).
- Brews without a bean or with a deleted bean: grouped under "No bean", not dropped (`testBrewsWithoutBeanAreGrouped`).
- A recipe brewed once rated 5★ shouldn't outrank one brewed 10× at 4.6★: recipes and beans rank by average with at least 2 rated brews first, then by count (`testRankingNeedsTwoRatings`).
- Old imported brews without curves (Beanconqueror): espresso averages for first drops and pressure use only shots that have them, counts show how many (`testAveragesSkipMissingValues`).
- A brew dated in the future (clock or import): counted, but in the current week, not beyond the chart (`testFutureDatesClampToThisWeek`).

---

### Task 1: BrewStats (pure)

**Files:**
- Create: `BrewLog/Analysis/BrewStats.swift`
- Test: `BrewLogTests/BrewStatsTests.swift`

**Interfaces:**
- Produces:
  - `enum BrewStats`
  - `struct Entry: Equatable { var date: Date; var espresso: Bool; var rating: Int; var beanID: UUID?; var beanName: String; var recipeName: String; var dose: Double; var yield: Double; var time: Double; var targetTime: Double; var grind: String; var extractionYield: Double?; var firstDrops: Double?; var peakPressure: Double?; var suddenDrop: Double? }`
  - `struct Week: Equatable { var start: Date; var brews: Int; var averageRating: Double? }`
  - `enum Trend: Equatable { case improving, steady, declining }` with `title`
  - `struct Group: Equatable, Identifiable { var id: String; var name: String; var brews: Int; var averageRating: Double?; var bestRecipe: String?; var bestGrind: String?; var lastBrewed: Date }` (best = highest-rated brew, ties → newest)
  - `struct Summary: Equatable { var brews: Int; var weeks: [Week]; var trend: Trend?; var averageRatio: Double?; var averageTime: Double?; var averageTimeDelta: Double?; var averageExtraction: Double?; var extractionCount: Int; var averageFirstDrops: Double?; var firstDropsCount: Int; var averagePeakPressure: Double?; var pressureCount: Int; var channelingShots: Int; var beans: [Group]; var recipes: [Group]; var points: [Point] }`
  - `struct Point: Equatable { var time: Double; var ratio: Double; var rating: Int }` (espresso scatter)
  - `static func summary(_ entries: [Entry], espresso: Bool, since: Date?, now: Date, calendar: Calendar) -> Summary`
  - `static func trend(_ weeks: [Week]) -> Trend?`

- [ ] **Step 1: Write the failing tests** (UTC ISO-8601 calendar, fixed `now`):
  - `testWeeksCountAndAverage`: 3 brews this week (ratings 4, 5, 0) + 1 last week (3) → `weeks.count == 12`, last week `brews == 3`, `averageRating == 4.5`; previous `3.0`.
  - `testTrendVerdicts`: weekly averages 3.0, 3.5, 4.0, 4.5 → `.improving`; 4,4,4 → `.steady`; 5,4,3 → `.declining`; two rated weeks → `nil`.
  - `testFiltersByKindAndRange`: espresso entries don't appear in `summary(espresso: false)`; `since` excludes older entries.
  - `testEspressoAverages`: ratios 2.0 and 2.2 → `averageRatio == 2.1`; first drops 6 and nil → `averageFirstDrops == 6`, `firstDropsCount == 1`; `suddenDrop 2.5` or `firstDrops 2` → `channelingShots == 2` of 3; `points.count == 3`.
  - The five Review Focus tests named there.
- [ ] **Step 2: Run** the Linux runner → Expected: FAIL (`cannot find 'BrewStats'`).
- [ ] **Step 3: Implement** `BrewStats.swift` (Foundation only). Trend slope: ordinary least squares of average rating over week index.
- [ ] **Step 4: Run** → Expected: all pass.
- [ ] **Step 5: Commit** — `feat(ios): BrewStats computes activity, trends, beans and recipes`

### Task 2: Brew → Entry adapter

**Files:**
- Create: `BrewLog/Analysis/BrewStats+Brew.swift`
- Test: `BrewLogTests/BrewStatsAdapterTests.swift` (iOS CI; uses an in-memory `ModelContainer`)

**Interfaces:**
- Consumes: `BrewStats.Entry` (Task 1), `EspressoAnalyzer.firstDrops(_:)`, `EspressoAnalyzer.pressureSummary(_:)`, `Extraction.evaluate(...)`, `Brew.grindDisplay`.
- Produces: `extension Brew { var statsEntry: BrewStats.Entry }` — `espresso` from `recipe?.method.isEspresso`, `yield = finalWeight`, `time = totalTime`, `targetTime = recipe?.targetTime ?? 0`, `beanName = bean?.name ?? "No bean"`, `extractionYield` only when `tds` is set (beverage = `beverageWeight` or the estimate), espresso fields only for espresso brews.

- [ ] **Step 1: Write the failing test** `testEspressoBrewBecomesEntry`: an espresso brew with samples (first gram at 7 s) and machine samples (peak 9.0) → `entry.espresso`, `firstDrops == 7`, `peakPressure == 9.0`; a pour-over brew without bean → `beanName == "No bean"`, `peakPressure == nil`.
- [ ] **Step 2: Run on CI** → FAIL to compile.
- [ ] **Step 3: Implement** the extension.
- [ ] **Step 4: Run on CI** → pass.
- [ ] **Step 5: Commit** — `feat(ios): brews feed the statistics`

### Task 3: Stats view

**Files:**
- Create: `BrewLog/Views/Stats/StatsView.swift`
- Create: `BrewLog/Views/Stats/StatsCharts.swift`
- Modify: `BrewLog/Views/History/HistoryListView.swift` (segmented control; the old `statsSection` goes away)

**Interfaces:**
- Consumes: `BrewStats.summary(...)`, `Brew.statsEntry`.
- Produces: `struct StatsView: View` (`@Query` all brews; `@AppStorage("stats.kind")` pour-over/espresso, `@AppStorage("stats.range")` 30/90/0 days); `WeeklyBrewsChart(weeks:)` (BarMark), `RatingTrendChart(weeks:trend:)` (LineMark + PointMark, verdict label), `ShotScatterChart(points:)` (PointMark, colour by rating).

- [ ] **Step 1:** `StatsView` sections in order: headline tiles (brews · average ★ · trend), Activity (`WeeklyBrewsChart`), Rating (`RatingTrendChart`), Brewing (pour-over: average time vs target as "+12 s" / "−5 s", extraction average with count; espresso: shot time, ratio 1:x.x, first drops with "n of m shots", peak pressure with count, channeling "n shots", `ShotScatterChart`), Beans (rows: name, brews, ★, best recipe, best grind, last brewed), Recipes (rows: name, brews, ★). Empty state per section: "No brews in this range yet."
- [ ] **Step 2:** Journal: segmented `Picker` *Journal | Stats* at the top; Stats shows `StatsView`.
- [ ] **Step 3:** Build on CI → success, all tests pass.
- [ ] **Step 4: Commit** — `feat(ios): statistics for pour-over and espresso with charts and trends`

### Task 4: Docs

**Files:**
- Modify: `docs/ai-parity-guide.md` (row "Brew Statistics": iOS Yes, Android No (paused), Web No; file-map row)
- Modify: `README.md` (Journal bullet: Stats)

- [ ] **Step 1:** Update both.
- [ ] **Step 2:** Manual check on the phone with existing brews: both kinds, all three ranges, empty espresso state.
- [ ] **Step 3: Commit** — `docs: statistics`

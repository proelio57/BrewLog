# Release Notes Cleanup & GaggiMate Profile Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Release notes become one short bullet per user-facing change (no commit bodies, no session links), and the espresso screen lists the profiles stored on the GaggiMate so one can be selected on the machine and brewed with in BrewLog.

**Architecture:** `scripts/release-notes.sh` keeps only the subject line of `feat`/`fix`/`perf` commits. GaggiMate profile handling stays pure in `Machine/GaggiMateProfileImport.swift` (parse the `res:profiles:list` answer into summaries + recipes); `MachineManager` gets `profiles` state plus `refreshProfiles()` / `selectProfile(_:)`; a `MachineProfilesSheet` opened from the machine card's "Profile" row lists them.

**Tech Stack:** bash + python3 (release notes), Swift 5 mode, SwiftUI, iOS 17, XCTest (pure logic also via `scripts/test-pure-swift.sh`).

**Spec:** User request 2026-11-05: "Entfern aus den Patch notes die Claude Sessions und nur Stichpunkte für die Features. Import von GaggiMate-Profilen in BrewLog oder Steuern der Profile auf GaggiMate; dass ich eins von der Maschine auswählen kann." GaggiMate API: `docs/websocket-api.yaml` and `schema/profile.json` in jniebuhr/gaggimate.

## Global Constraints

- Release notes: one line per change, `• <Subject>` (type prefix removed, first letter upper-case), nothing else from the commit message. Max 2000 characters. Empty → `Bug fixes and improvements.` Used by both `ios.yml` and `android.yml` through `sidestore-publish.sh`; the output format change applies to both.
- No URL and no `Claude-Session`, `Co-Authored-By`, `Signed-off-by` text may ever appear in the notes, even if it is in the subject line.
- GaggiMate messages (verbatim from its API): `req:profiles:list {rid}` → `res:profiles:list {rid, profiles, error?}`; `req:profiles:select {rid, id}` → `res:profiles:select {rid, error?}`. `evt:status.p` is the selected profile's **label** (no id).
- Profile fields used: `id` (string), `label`, `selected` (bool), `favorite` (bool), `utility` (bool), `dose`, `temperature`, `phases`. Pump pressure/flow `-1` means "hold current" (not a value). Target types: `volumetric`, `ratio`, `pressure`, `flow`, `pumped`.
- Profiles whose label starts with `GaggiMateProfile.labelPrefix` ("BrewLog · ") are BrewLog's own; they are listed (they can be selected) but not imported again.
- Copy is English, sentence case, no exclamation marks.
- Verification: pure Swift with `scripts/test-pure-swift.sh BrewLogTests/<File>.swift <sources…>`; full app via the iOS CI on the PR (build + `xcodebuild test`, "Executed N tests, with 0 failures").

## Review Focus

- A profile with a `ratio` target and no `volumetric` one: the yield must be dose × ratio, not 1:2 (test `testRatioTargetSetsYield`, Task 2).
- Pump pressure `-1` ("hold current") in a phase: must not count as 0 bar or lower the recipe pressure (test `testHoldPressureIsIgnored`, Task 2).
- Machine disconnects while the sheet is open or a select is pending: the sheet shows the error text, no spinner forever (completion gets nil after the 8 s timeout; test via `MachineManager` is not possible, so the sheet's `onDisappear`/error path is checked in the manual run list of Task 3).
- Two profiles with the same label: selection is by `id`, the check mark comes from `selected` in the list answer, not from the label (test `testSummariesUseSelectedFlag`, Task 2).
- A commit subject that itself contains a URL or a session id: stripped (test case `subject-with-url`, Task 1).

---

### Task 1: Release notes as short bullets

**Files:**
- Modify: `scripts/release-notes.sh`
- Create: `scripts/test-release-notes.sh`
- Modify: `.github/workflows/ios.yml` (run the test before "Build unsigned IPA"), `.github/workflows/android.yml` (same, before its build step)

**Interfaces:**
- Produces: `scripts/release-notes.sh [rev]` prints lines `• Subject` separated by a single newline.

- [ ] **Step 1: Write the failing test `scripts/test-release-notes.sh`**

Creates a throw-away repo in `mktemp -d`, makes these commits on a branch and merges it with `--no-ff` into `main`, runs `release-notes.sh HEAD` there and compares with the expected text; exits 1 with a diff on mismatch.

| Commit message | Expected line |
|---|---|
| `feat(ios): import GaggiMate profiles as espresso recipes` + body paragraph + `Co-Authored-By: X <x@y>` + `Claude-Session: https://claude.ai/code/session_123` | `• Import GaggiMate profiles as espresso recipes` |
| `fix: the mode switch no longer hitches` + body | `• The mode switch no longer hitches` |
| `docs: statistics` | (none) |
| `chore(ci): bump` | (none) |
| `fix(ios): crash on start, see https://example.com/x (session_01AbC)` | `• Crash on start` |

Expected output exactly:
```
• Import GaggiMate profiles as espresso recipes
• The mode switch no longer hitches
• Crash on start
```
Second case: a repo with only `docs:` commits → `Bug fixes and improvements.`

- [ ] **Step 2: Run it, expect FAIL**

Run: `bash scripts/test-release-notes.sh`
Expected: exit 1, diff shows the body paragraphs and the session line.

- [ ] **Step 3: Change `release-notes.sh`**

In the python part: use only `lines[0]` after the type match (drop `body`); remove URLs (`https?://\S+`), `session_[A-Za-z0-9]+`, then a trailing `, see`/`(…)` remnant left empty by that (`re.sub(r"[\s,;:(]*(see)?[\s(]*\)?\s*$", "", …)` applied only if something was removed); join with `"\n"`. Update the header comment to say "subject line only".

- [ ] **Step 4: Run it, expect PASS**

Run: `bash scripts/test-release-notes.sh` → exit 0, prints `release notes OK`.

- [ ] **Step 5: Wire into CI** — add a step `Release notes test` running `bash scripts/test-release-notes.sh` to both workflows, and add `scripts/release-notes.sh`, `scripts/test-release-notes.sh` to both workflows' `paths` lists.

- [ ] **Step 6: Commit**

```bash
git add scripts/release-notes.sh scripts/test-release-notes.sh .github/workflows/ios.yml .github/workflows/android.yml
git commit -m "ci: release notes list one short line per feature or fix"
```

---

### Task 2: Parse the machine's profile list

**Files:**
- Modify: `BrewLog/Machine/GaggiMateProfileImport.swift`
- Test: `BrewLogTests/ImportTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct MachineProfileSummary: Identifiable, Equatable {
      let id: String          // GaggiMate profile id
      let label: String       // without the "BrewLog · " prefix
      let isSelected: Bool
      let isFavorite: Bool
      let isBrewLogs: Bool    // label had the BrewLog prefix
      let recipe: Recipe?     // nil for utility profiles
  }
  extension GaggiMateProfile {
      static func summaries(fromListResponse response: [String: Any]) -> [MachineProfileSummary]
  }
  ```
  Order: selected first, then favorites, then the rest, each group in the machine's order. Utility profiles are left out. Entries without a string `id` are left out (they can't be selected).

- [ ] **Step 1: Write failing tests** in `ImportTests.swift`:
  - `testSummariesUseSelectedFlag`: two profiles both labelled `"Turbo"`, ids `a`/`b`, `b` has `"selected": true` → `summaries.first?.id == "b"`, `isSelected` true only for `b`.
  - `testSummariesOrderAndSkip`: profiles [plain `x`, favorite `y`, utility `z`, no-id `w`, `"BrewLog · Classic"` id `c`] → ids `["y", "x", "c"]`; `c` has `isBrewLogs == true`, label `"Classic"`.
  - `testRatioTargetSetsYield`: dose 18, brew phase `targets: [{type: "ratio", value: 2.5}]` → `recipe.water == 45`.
  - `testHoldPressureIsIgnored`: preinfusion pump `{target: "pressure", pressure: 3}`, brew pump `{target: "pressure", pressure: -1}` then `{target: "pressure", pressure: 6}` → `recipe.pressure == 6`; tip for the hold phase contains `"hold"` and no `"-1"`.

- [ ] **Step 2: Run, expect FAIL**

Run: `scripts/test-pure-swift.sh BrewLogTests/ImportTests.swift BrewLog/Machine/GaggiMateProfileImport.swift BrewLog/Machine/MachineStatus.swift BrewLog/Recipes/Recipe.swift BrewLog/Recipes/RecipeValidation.swift BrewLog/Recipes/RecipeLibrary.swift BrewLog/Import/RecipeFile.swift BrewLog/Import/BeanconquerorBackup.swift BrewLog/Import/ZipArchive.swift`
(If a source needs UIKit/SwiftData and breaks the Linux build, run the tests in CI instead and note it.)
Expected: compile error `summaries(fromListResponse:)` not found.

- [ ] **Step 3: Implement** `summaries(fromListResponse:)`; in `Phase.init` treat pressure/flow `< 0` as "hold" (`holdsPressure = true`, value nil; summary text `hold pressure`); in `recipe(from:)` use the last `ratio` target × dose as yield when no `volumetric` target exists.

- [ ] **Step 4: Run, expect PASS** (same command; all `ImportTests` pass).

- [ ] **Step 5: Commit** `feat(ios): read GaggiMate's profile list with the selected profile`

---

### Task 3: Pick a machine profile from the espresso screen

**Files:**
- Modify: `BrewLog/Machine/MachineManager.swift`
- Create: `BrewLog/Views/Espresso/MachineProfilesSheet.swift`
- Modify: `BrewLog/Views/Brew/MachineCard.swift` (the "Profile" `StatView` becomes a button opening the sheet), `BrewLog/Views/Espresso/EspressoSetupView.swift` (its "Profile" `machineRow` opens the sheet too)
- Modify: `docs/data-formats.md` (GaggiMate section: list/select), `docs/ai-parity-guide.md` (Espresso Machine row: add the sheet)

**Interfaces:**
- Consumes: `GaggiMateProfile.summaries(fromListResponse:) -> [MachineProfileSummary]` (Task 2), `DataImporter.importRecipes(_:into:)`.
- Produces on `MachineManager`:
  ```swift
  private(set) var profiles: [MachineProfileSummary] = []
  private(set) var profilesLoading = false
  func refreshProfiles()                                   // req:profiles:list; sets profiles or notice
  func selectProfile(_ id: String, completion: @escaping (Bool) -> Void)  // req:profiles:select, then refreshProfiles()
  ```
  `fetchProfiles(completion:)` (existing, used by Settings import) is reimplemented on top of the same request.

- [ ] **Step 1: MachineManager** — add the three members above. `refreshProfiles()` is a no-op unless `kind == .gaggimate && isConnected`; on a nil/`error` answer it sets `notice = "Couldn't read the profiles from the machine."` and keeps the old list. Demo machine: `profiles` = two fixed summaries built from `RecipeLibrary` espresso presets (`id` = recipe id), `selectProfile` sets `status.profile` and `isSelected` locally.

- [ ] **Step 2: `MachineProfilesSheet`** (`NavigationStack` + `List`, title "Machine profiles", detents medium/large):
  - Calls `machine.refreshProfiles()` in `.task`; `ProgressView` while `profilesLoading` and the list is empty.
  - Row: label, star for favorites, check mark for `isSelected`; tapping a row calls `selectProfile`, shows a spinner on that row, and on success also imports `summary.recipe` (if non-nil and not `isBrewLogs`) with `DataImporter.importRecipes` and sets it as the espresso setup's recipe (`setup.recipe = recipe`, environment `BrewSetup` is the espresso one on this screen), then dismisses.
  - On failure: row spinner stops, footer shows `machine.notice`.
  - Footer: "Selecting a profile sets it on the machine and brews with it here: BrewLog takes the yield, time and pressure from it."
  - Empty state: "No profiles on the machine."

- [ ] **Step 3: Open the sheet** from `MachineCard` ("Profile" stat) and `EspressoSetupView` ("Profile" row) — only when `machine.kind == .gaggimate || machine.kind == .demo` and connected; otherwise keep the plain value.

- [ ] **Step 4: Docs** — `data-formats.md`: add `req:profiles:select {rid, id}` / list behaviour and that selecting imports the recipe; parity guide row.

- [ ] **Step 5: Push the branch and open/refresh the PR; CI must be green** (iOS build + tests).

Manual run list (demo machine, then a real GaggiMate if available): open sheet → list shows, current one checked; select another → machine card shows the new profile name, recipe card shows the imported recipe with its yield; switch Wi-Fi off and select → error text, no endless spinner.

- [ ] **Step 6: Commit** `feat(ios): choose the GaggiMate profile from the espresso screen and brew with it`

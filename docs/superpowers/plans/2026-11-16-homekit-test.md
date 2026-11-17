# HomeKit Test Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Find out whether a BrewLog build with the HomeKit entitlement installs through SideStore and can switch a plug.

**Architecture:** The entitlement goes into `project.yml` (Xcode builds) and `scripts/build-ipa.sh` (unsigned IPA, via `ldid`, app binary only). `HomeKitPlugs` lists every power-state characteristic and toggles one; it is the code the later `HomeKitPlug` builds on. A temporary Settings row opens the test screen. `HMHomeManager` is created only when that screen opens, so a build where HomeKit does not work still starts.

**Tech Stack:** SwiftUI, HomeKit, XcodeGen, ldid.

**Spec:** `docs/superpowers/specs/2026-11-16-machine-power-and-smart-plug-design.md` (Order of work, step 1)

## Global Constraints

- iOS 17, Swift 5 mode.
- The widget extension must not get the HomeKit entitlement.
- No `HMHomeManager` before the user opens the test screen.
- If SideStore cannot install the release: revert the merge the same day.

## Review Focus

- HomeKit access denied or no home set up → the screen says so instead of an empty list.
- Entitlement stripped by SideStore → the screen shows the authorization status, the app does not crash.
- Accessory unreachable → the row shows the error from HomeKit.
- A plug with several outlets → one row per outlet.
- Toggling twice quickly → the second tap waits for the first write.

None of these can run in unit tests (HomeKit needs a device); they are checked on the phone.

---

### Task 1: Entitlement and usage text

**Files:** Modify `project.yml` (entitlement property `com.apple.developer.homekit: true`, `INFOPLIST_KEY_NSHomeKitUsageDescription`), `scripts/build-ipa.sh` (second entitlements file for the app with the HomeKit key; the appex keeps the App Group only).

- [ ] Edit both files. - [ ] `bash -n scripts/build-ipa.sh`. - [ ] Commit.

### Task 2: `HomeKitPlugs` and the test screen

**Files:** Create `BrewLog/Power/HomeKitPlugs.swift`, `BrewLog/Views/Gear/HomeKitTestView.swift`; modify `BrewLog/App/Features.swift` (`static let homeKitTest = true`), `BrewLog/Views/Gear/GearViews.swift` (row in the machine section).

**Produces:**
- `final class HomeKitPlugs: NSObject, ObservableObject, HMHomeManagerDelegate` with `@Published var plugs: [Plug]`, `@Published var status: String`, `func start()`, `func toggle(_ plug: Plug) async`.
- `struct Plug: Identifiable { id: UUID (characteristic), home, room, name: String, isOn: Bool?, reachable: Bool, error: String? }`.

- [ ] Write both files. - [ ] Add the row. - [ ] Commit. - [ ] CI builds and runs the existing tests.

### Task 3: Release notes, PR, merge on green, try on the phone

- [ ] `RELEASE_NOTES.md`: iOS "HomeKit test: Settings → Machine → HomeKit test (temporary)". - [ ] PR, merge on green. - [ ] The user installs and reports.

# La Marzocco Support — Decision & Spike Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decide how (and whether) BrewLog talks to La Marzocco home machines (Linea Micra, Linea Mini, GS3), verify the current API, and write the implementation plan from the verified facts.

**Architecture:** This plan stops at a written, verified protocol description and a follow-up implementation plan. Building on an unverified API would waste the work: La Marzocco changed its app and firmware in 2025 and third-party access broke more than once.

**Tech Stack:** Research only (pylamarzocco source, Home Assistant integration); output is Markdown.

**Spec:** User request 2026-11-05 ("danach la marzocco Support"), after the Decent plan.

## Global Constraints

- BrewLog's privacy rule (`docs/ai-parity-guide.md` §1): network only for the recipe feed, update checks and the user's own machine **in the local network**; opt-in features (Git backup, Ask Claude) use the user's own account/key and do nothing until set up.
- Known state (to verify in Task 1): the local WebSocket (`ws://<ip>:8081/api/v1/streaming`, bearer "communicationKey") was reported removed in 2025 firmware; the communication key itself always came from La Marzocco's cloud with the user's account; Bluetooth also needs that key; the cloud API needs username, password and an installation key and was reported to block third-party clients at times.
- Most La Marzocco home machines have no pressure readout; what's available is on/off, boiler temperatures, brew state / shot timer, and settings.

## Review Focus

- The API changes again after implementation: the integration must fail with a clear "La Marzocco changed its connection" message, never crash or hang (requirement for the follow-up plan).
- Credentials: stored in the Keychain only, never in backups or Git sync (requirement for the follow-up plan).
- No account set up: nothing is sent anywhere (requirement for the follow-up plan).

---

### Task 1: Decision with the user (blocking)

- [ ] **Step 1:** Ask the user which route is acceptable, with these options:
  1. **Opt-in cloud** (like Git backup): the user enters their La Marzocco account once; BrewLog talks to La Marzocco's servers to read state and switch the machine. Breaks "local only" for this one opt-in feature.
  2. **Cloud only to fetch the key, then Bluetooth locally**: one-time login, afterwards local BLE only (if Task 2 confirms BLE still works with the key).
  3. **No integration**: a La Marzocco works like any machine without app connection (scale + BOOKOO pressure sensor), documented in the README.
- [ ] **Step 2:** Record the decision at the top of this file (date + option). Option 3 ends the plan after a README line.

### Task 2: Verify the current API (spike)

**Files:**
- Create: `docs/la-marzocco-protocol.md`

- [ ] **Step 1:** Read the current pylamarzocco release (GitHub zweckj/pylamarzocco, latest tag) and the Home Assistant `lamarzocco` integration: auth flow (endpoints, installation key, request signing), the status/WebSocket messages, the BLE characteristics and what they need, the commands for power on/off and brew-state.
- [ ] **Step 2:** Write `docs/la-marzocco-protocol.md` with exact endpoints, message shapes and example payloads, each with the source file and tag it came from, plus open issues from the tracker that affect it (e.g. #81, #170).
- [ ] **Step 3:** Commit `docs: La Marzocco protocol as of <tag>`.

### Task 3: Write the implementation plan

- [ ] **Step 1:** With the decision and `docs/la-marzocco-protocol.md`, write `docs/superpowers/plans/<date>-la-marzocco-implementation.md` following the Decent plan's structure: pure protocol type with tests → connection (cloud client or BLE) feeding `MachineManager` (`MachineKind.laMarzocco`, `MachineCapabilities` without `.profiles`/`.machineScale`) → Settings UI (account sheet, Keychain via the pattern in `Import/GitSync.swift`) → docs.
- [ ] **Step 2:** Get the user's review of that plan before implementing.

# Machine power: switch off after the shot, smart plug, and what follows

Date: 2026-11-16. Status: waiting for approval.

## Intent

After a shot the GaggiMate should not stay hot for hours. BrewLog asks whether to switch it off, and when the
machine is in standby it cuts the power at the smart plug. The plug is in HomeKit today; Home Assistant may follow.
Switching the machine back on must be just as easy, because a plug that is off takes the GaggiMate off the network.

## Goals

1. One question after the shot: Steam / Switch off / Later.
2. Standby (asked for in BrewLog or reached by the machine itself) switches the smart plug off, after a countdown
   that can be cancelled.
3. A button in BrewLog switches the plug on, and BrewLog says when the machine is ready.
4. Auto-off after a set idle time.
5. Siri and Shortcuts actions "machine on" and "machine off".
6. Heat-up status on the Lock Screen (Live Activity).
7. Android and web get the same through Home Assistant.

## Non-goals

- Switching while BrewLog is not running. iOS suspends the app; a machine that goes to standby on its own with the
  phone locked stays powered. The settings text says so and points to a Home Assistant automation for that case.
- Plugs for machines other than GaggiMate and the demo machine in this round. The plug layer itself is not tied to
  GaggiMate, so other machines can follow.
- Schedules (heat up at 7:00). The Shortcuts actions cover this through a Home app or Shortcuts automation.

## Anti-goals

- Cutting the power while a shot runs, while steaming, or while the user is still flushing. Hence the countdown, and
  never during an active process.
- A release that SideStore can no longer sign. HomeKit needs an entitlement; see the test below.
- A second prompt stacked on the existing "Switch to steam?" prompt.

## Constraints

- iOS is installed through SideStore with a free Apple ID. The IPA is unsigned and `scripts/build-ipa.sh` writes
  entitlements with `ldid`. Whether SideStore keeps `com.apple.developer.homekit` is unknown.
- BrewLog only sees the machine's mode while its WebSocket is open (app in the foreground, or a brew Live Activity
  keeping it alive for a short time).
- The smart plug credentials for Home Assistant (a long-lived token) belong in the Keychain / EncryptedSharedPreferences,
  not in UserDefaults or the backup export.

## Approaches for the plug

1. **HomeKit directly (iOS).** Pick the accessory in BrewLog. No setup, but the entitlement may not survive
   SideStore, and it is iOS only.
2. **Home Assistant REST.** Address + token, `switch.turn_on` / `turn_off` and the state. Works on all three
   platforms and can be paired with an automation that runs without the app. Needs a running Home Assistant.
3. **Shortcut (iOS).** BrewLog runs a named shortcut through `shortcuts://x-callback-url/run-shortcut`. No
   entitlement, certain to work with SideStore, but the Shortcuts app comes to the front for a moment.

**Chosen (by the user):** HomeKit first, behind a test; the Shortcut as the iOS fallback if the test fails; Home
Assistant after that, which also brings the feature to Android and web. All "further features" (auto-off, Siri,
Lock Screen) are wanted.

## Design

### Plug layer

`SmartPlug` protocol: `isConfigured`, `state` (on / off / unknown), `turnOn()`, `turnOff()`. Implementations:
`HomeKitPlug`, `ShortcutPlug` (two shortcut names, state unknown), `HomeAssistantPlug`. `MachinePower` owns the
chosen plug and the rules below; views and intents only talk to `MachinePower`. On Android the same split, with the
rules in `android/shared` (commonMain) and only `HomeAssistantPlug` as an implementation.

### Rules (`MachinePower`)

- **Switch off** = set the machine to standby, then start the plug countdown.
- **Standby seen** (mode changes to 0 while connected, from any cause) starts the plug countdown, when a plug is
  configured and "Switch the plug off in standby" is on.
- **Countdown:** 30 s by default (setting: 0 / 30 s / 2 min / 5 min), shown as a banner with "Cancel". It is
  cancelled when the mode leaves standby. It never starts while a process is active.
- **Switch on** = plug on, then wait for the GaggiMate to connect, set brew mode, and report "ready" when the
  temperature is within 2 °C of the target (local notification if the app is in the background, when allowed).
- **Auto-off:** setting Off / 15 / 30 / 60 min. The timer restarts on every shot, mode change and steam use. When it
  runs out: Switch off. Only while BrewLog runs; the settings text says so.

### After the shot

The existing alert becomes "Shot done" with Steam / Switch off / Later. The setting "After the shot" gets a fourth
value: Ask / Switch to steam / Switch off / Off. After "Steam", when the mode has been steam and no steam has been
drawn for 2 min, or the user goes back to brew, BrewLog asks once "Switch off?".

### Controls

- Machine card (dashboard and Gear): a power button. Plug off or machine unreachable with a plug configured → "Switch
  on". Machine on → "Switch off".
- Settings → Machine: plug type and its setup (HomeKit accessory picker / shortcut names / Home Assistant address,
  token, entity), countdown, auto-off, "After the shot".

### Siri and Shortcuts

App Intents `SwitchMachineOn` and `SwitchMachineOff`, running `MachinePower` in the background. They need no
entitlement. With a HomeKit or Home Assistant plug they work without opening the app; with the Shortcut plug they
are not offered (a shortcut calling a shortcut).

### Lock Screen

A second Live Activity "heating": current and target temperature, "ready" when reached, ends 2 min after ready or
when a brew starts. Started by Switch on. Updated only while the app is alive; it shows the last value with its time
when updates stop.

## Order of work

Each step is its own PR and release.

1. **HomeKit test.** Entitlement + `NSHomeKitUsageDescription` + a hidden screen that lists homes and accessories
   and toggles one. Release it. If SideStore cannot install it, revert the same day (the installed version stays
   usable) and take the Shortcut path for iOS.
2. **Plug layer, rules, prompt, power button, countdown, ready notice** (iOS), with HomeKit or the Shortcut plug.
3. **Auto-off.**
4. **Siri and Shortcuts actions.**
5. **Heating Live Activity.**
6. **Home Assistant plug** on iOS, then the rules in `android/shared` and the Android UI, then web.

## Tests

`MachinePower` is tested with a fake plug and a fake clock: countdown starts on standby, is cancelled on mode
change, never starts during a process, auto-off restarts on activity, switch-on reports ready. Home Assistant calls
are tested against recorded requests. HomeKit itself can only be tried on the device.

## Left to the builder

- Names and placement of the settings rows; banner styling.
- How the heating activity shares code with the brew activity.
- Whether the Home Assistant plug talks to the entity directly or through a webhook when no token is given.

## Calls made without the user

- 30 s default countdown; "ready" at 2 °C below target; one follow-up question after steaming.
- The plug rules apply to GaggiMate and the demo machine first.
- Home Assistant token in secure storage and left out of backups.

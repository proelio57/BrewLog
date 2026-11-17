# TODO: animations on the live brew screen (rinsing, grinding, pouring)

Status of the live brew screen: step changes cross-fade and the pour bar moves, but these moments are static.
Nothing here is implemented yet. Build on iOS first (SwiftUI), then port the same timing to Android
(Compose) and, later, to the shared web UI.

## What to animate

- **Rinsing** (`BrewPhase.rinsing`, the paper rinse step): a water-wave or swirl icon that loops while the rinse
  is running, so it reads as "in progress" from across the counter. Stops when the step is done.
- **Grinding** (`BrewPhase.preparing`, "Ground at …"): a short rotating or pulsing grinder/bean icon while the
  user grinds, and a gentle settle when the dose is weighed (`BeanDosing` on target).
- **Pouring** (`BrewPhase.brewing`, the active step): the pour progress bar fills with a soft ease and a
  subtle pulse at the ping point (`pingLead`), the flow number cross-fades when it changes, and the current
  step chip pulses until the step ends.
- **Pour start/stop:** when the scale first leaves zero (`zeroConfirmed` → begin), a short scale-up of the
  weight number so the start is visible without looking at the timer.

## Constraints

- Respect Reduce Motion (iOS `accessibilityReduceMotion`) and the Android system animator scale: show the
  end state with no loop.
- Animations are decoration only: they must not change timing, cues or haptics.
- Keep it cheap: no animation during the shot's chart redraws (the chart already updates ~10 Hz).

## Where it lives

- iOS: `BrewLog/Views/Brew/BrewSessionView.swift` (`stepCard`, `controls`, `PourProgressBar`),
  `BrewLog/Views/Components/Components.swift` (`PulsingDrop` is the existing pattern to reuse).
- Android: `android/app/src/main/java/com/brewlog/app/ui/screens/LiveBrewScreen.kt` (`PourProgressBar`,
  `CountdownRing`, the pulse in `rememberInfiniteTransition`).

## Done when

- Each of the three phases has a visible animation on iOS and Android.
- Reduce Motion / animator scale 0 turns every loop off.
- Parity note added to `docs/gemini-android-parity.md`.

# Espresso tab and brew statistics — design

Request (2026-11-02): "Refine espresso. Its own tab at the bottom; the scale starts by itself, measures and
calculates everything, and above all the pressure — GaggiMate and the BOOKOO Espresso Monitor. Then statistics
for pour-over and espresso separately, with graphs and trends, for beans and everything."

Platform: **iOS** (SwiftUI, iOS 17+). Android is paused; web follows later (parity guide gets "No" rows).

## A. Espresso tab

1. **Switch at the top of the Brew tab** (revised 2026-11-02): a segmented control *Filter | Espresso*, remembered.
   The tab bar stays as it is (Brew · Recipes · Journal · Beans · Gear). Filter shows the pour-over setup and only
   pour-over recipes in the picker; Espresso shows the espresso screen and only espresso recipes.
2. **Separate remembered setup** for espresso (recipe, dose, temperature, bean, machine = brewer, grinder, grind):
   picking a pour-over recipe never changes the espresso setup and vice versa. Pour-over keeps the existing
   `setup.*` keys (no migration); espresso uses `espresso.*`.
3. **Espresso mode screen** (inside the Brew tab): device strip (scale, GaggiMate, BOOKOO Espresso Monitor — each with state and, when
   live, weight / pressure / temperature), recipe card (espresso recipes), dose · yield · ratio · temperature,
   bean, grinder and grind, big **Pull shot** button.
4. **GaggiMate wins** (revised 2026-11-02): the machine's settings are always right. When it is connected the
   espresso screen shows its target temperature, target pressure and profile ("from GaggiMate") instead of the
   recipe's, Pull shot never sends a profile (only the existing explicit "Send recipe" does), and the brew is
   saved and analysed with the machine's target temperature (else the measured average, else the recipe) and
   target pressure (else the recipe).
4b. **Automatic shot**: Pull shot opens the shot screen, tares the scale and arms. With a controllable GaggiMate
   the app starts the shot itself (without changing its profile). The timer starts by itself on the first of:
   machine pump on, pressure ≥ 1 bar (monitor), or weight ≥ auto-start threshold.
5. **Stop at the target yield**: once `weight + flow × stopLag ≥ yield` the app stops a controllable machine
   (`stopShot`), otherwise plays the target cue with a "Stop now" banner. `stopLag` setting: 0.5–2.5 s,
   default 1.0 s. Setting "Stop at the target yield" (default on).
6. **Automatic end**: the shot finishes by itself 3 s after the pump stops (existing), or — without a machine —
   once the weight has settled (≥ 4 readings in 1.5 s within ±0.3 g) after reaching ≥ 90 % of the yield.
7. **Live numbers**: shot time, time to first drops, weight, live ratio (1:x), flow (g/s), current and peak
   pressure (bar), temperature (°C, GaggiMate). Pressure from the monitor wins over the machine's (existing rule).
8. Everything is saved with the brew as today (weight curve, machine curve, dose, yield, time) and analysed by
   `EspressoAnalyzer`.

## B. Statistics

1. **Where**: Journal tab gets a segmented control *Journal | Stats*; Stats has *Pour-over | Espresso* and a
   range *30 days | 90 days | All*.
2. **Both**: brews per week (bars, last 12 weeks), average rating per week (line) with a trend verdict
   (improving / steady / declining from the least-squares slope over the range: > +0.05 ★/week improving,
   < −0.05 declining), average ratio, beans table (brews, average rating, best recipe, best grind, last brewed),
   recipes ranking (brews, average rating).
3. **Pour-over**: average brew time vs target, extraction yield trend when TDS is logged.
4. **Espresso**: average shot time, average ratio, average time to first drops, average peak pressure, shots
   with signs of channeling (sudden drop ≥ 2 bar or first drops < 3 s), scatter shot time × ratio coloured by
   rating.
5. All numbers come from a pure, tested `BrewStats` module; views only draw (Swift Charts).

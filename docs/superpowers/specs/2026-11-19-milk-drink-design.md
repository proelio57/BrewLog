# Milk drink: steam and weigh the milk after the shot

Date: 2026-11-19. Status: approved (the user chose milk in the recipe).

## Intent
Before an espresso the user says whether it's a milk drink. A milk drink switches the machine to steam after the
shot without asking and adds a step to weigh the milk; an espresso without milk never asks about steam.

## Design
- `Recipe.milk` (grams, optional; nil = espresso only), edited in the recipe editor, shown in the recipe.
- Brew tab (espresso): "Milk drink" toggle and milk stepper, starting at the recipe's milk (150 g when the recipe
  has none). The amount goes into the brew's recipe snapshot.
- After the shot (`AfterShot`): milk drink → steam (GaggiMate/demo) + milk step; espresso → Settings "After an
  espresso": ask to switch off / switch off / nothing. The old "steam" setting reads as "ask".
- Milk step: weight from the phone's scale or GaggiMate's, Tare, progress to the target, steam heating status,
  Done (saves `Brew.milkWeight`) or Skip; then the rating screen.
- Journal: the brew shows the milk weighed (or the target).

## Approaches considered
Milk only as a setting (one amount for all drinks) — rejected by the user; per recipe distinguishes cappuccino
and flat white. Weighing before the shot — rejected: weighing while the boiler heats for steam saves waiting.

## Left for later
Android (same fields; recipe JSON already ignores unknown keys), milk in the backup format.

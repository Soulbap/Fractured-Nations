# FRACTURED NATIONS — UI-01B

## Field Manual — HUD & Interface Implementation

Branch: `feature/ui-01b`
Scope: presentation only.  No simulation, navigation, construction rules, world assets or gameplay-order logic was changed.

## Delivered interface work

### Shared visual system

`scripts/ui/field_manual.gd` centralises the Field Manual tokens used by the
runtime UI: dark canvas, warm ink, olive command state, blue logistics,
amber action, red invalid/danger and green valid/success.  It also supplies
the compact one-pixel-border panel and button treatments used by the touched
interfaces.

### Tactical command

* The squad list is now a compact **TASK FORCE** overview, with one readable
  callsign / effective strength / order row per squad.
* The selected-squad actions are a wrapping **COMMAND DECK** rather than a
  wide button strip.  Existing assault, regroup and ROE actions are retained.
* The vehicle and facility panel uses the same blue operational treatment,
  keeping its existing information and actions intact.
* Default HUD help is deliberately brief.  F1 still expands the detailed
  control reference and F3 keeps diagnostics separate from normal play.

### Construction

* Build families remain grouped, while buttons and the construction caption
  now use the shared visual language.
* During placement, a dedicated contextual readout shows the selected asset,
  green **VALID PLACEMENT** or red invalid reason, and the place/rotate/cancel
  affordances.  Its status refreshes with the live placement check; no build
  validation rules were changed.

### First person and strategic map

* The first-person corner readout is reduced to weapon, magazine/reserve,
  fire mode and a small health bar; the crosshair and gameplay feedback are
  preserved.
* The strategic map’s information slab adopts the Field Manual treatment and
  is only shown when there is a selected squad, vehicle, objective, operation
  or structure.  With no relevant selection the map uses the full width.

## Files changed

| Area | Files |
| --- | --- |
| Shared tokens | `scripts/ui/field_manual.gd` |
| RTS HUD | `scripts/ui/squad_panel.gd`, `scripts/ui/tactical_panel.gd`, `scripts/ui/logistics_panel.gd`, `scripts/ui/game_hud.gd` |
| Construction | `scripts/ui/construction_panel.gd` |
| Strategic map | `scripts/ui/strategic_map.gd` |

## Visual reference captures

`docs/ui_01b/` contains both the BASE-01 comparison set (`baseline_*`) and
live UI-01B captures from the Godot game:

* `live_rts.png` — normal RTS view with the compact task-force panel;
* `live_rts_command_deck.png` — selected squad and contextual command deck;
* `live_strategic_map.png` — strategic-map presentation.

## Verification and known environment limitation

* A Godot editor filesystem scan registered the new shared `FieldManual`
  class.  A separate headless Godot parse smoke check loaded every UI-01B
  script without reporting a parser error.
* `git diff --check` completed without whitespace errors.
* The generated `res://scenes/world/ref_20km.tscn` and terrain data are
  ignored by Git.  For the live capture only, the UI-01B worktree used
  temporary local links to the existing generated test world; no world asset
  or gameplay source was edited.

## Suggested final smoke path

1. Make the ignored generated `scenes/world/ref_20km.tscn` / world data
   available in the `feature/ui-01b` worktree.
2. Open the main scene and check RTS selection, build placement, TAB first
   person and M strategic map.
3. Confirm F1 expands controls, F3 exposes diagnostics, and tactical orders,
   construction validity and strategic-map selection remain functional.

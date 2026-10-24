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

## UI-01B.1 — Visual Polish & Completion

### Design pass

The second pass used the supplied Arma, Regiments, WARNO and map-interface
references as a compositional check: information is anchored to the edge,
the active order surface is temporary, and the battlefield stays central.
No reference artwork or third-party assets were copied into the game.

* **Task Force:** removed the repeated ROE column, tightened rows, replaced
  `NONE` with `IDLE`, and added a restrained state marker.  A selected row now
  reads as one item in an operational roster rather than a debug line.
* **Command Deck:** moved from a floating right-side block to a centred,
  lower contextual deck.  It uses a stable width, equal-height buttons and
  reports squad readiness/order rather than AI effectiveness counters.
* **Construction:** category headers now use the shared control treatment;
  base entries have a common 32 px rhythm; the permanent construction footer
  is reduced to one quiet exit/help line because the panel owns the detail.

### Live capture register

The following are captured from the running UI-01B Godot project, not from
mockups or baseline images:

| File | Result |
| --- | --- |
| `final/01_rts_idle.png` | Captured — RTS idle |
| `final/02_rts_squad_selected.png` | Captured — selected squad / Command Deck |
| `final/03_rts_multi_selected.png` | Captured — multi-selection |
| `final/04_rts_vehicle_selected.png` | Blocked — the supplied scenario has no player-controlled vehicle instance |
| `final/05_construction_menu.png` | Captured — catalogue and category palette |
| `final/06_construction_valid.png` | Captured — valid Command Post placement |
| `final/07_construction_invalid.png` | Captured — Barracks correctly reports that a Command Post is required |
| `final/08_construction_base.png` | Blocked — creating a base solely for a screenshot would modify live construction state |
| `final/09_fps_normal.png` | Captured — first-person HUD |
| `final/10_fps_interaction.png` | Blocked — the reference spawn has no interaction prompt in reach |
| `final/11_map_default.png` | Captured — default operational map |
| `final/12_map_squad_selected.png` | Captured — selected squad map inspector |
| `final/13_map_base_selected.png` | Captured — selected friendly objective/base context |
| `final/14_map_logistics.png` | Blocked — no player logistics/vehicle item is present in this scenario |

### Visual review

The first live RTS review showed an overly wide roster, repeated `FREE` labels,
and an isolated right-side command slab.  The changes above are the resulting
second visual revision.  The construction capture also exposed a duplicated
instruction manual across panel and footer; normal construction HUD is now
intentionally quiet.  The remaining limitation is scenario coverage, not a
UI failure: player vehicles, an established base and an interaction target are
not spawned in the supplied reference state and were not fabricated.

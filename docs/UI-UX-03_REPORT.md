# UI-UX-03 — Tactical interface, tactical map, RTS camera, runtime stability

Branch `develop`, after COMBAT-COVER-03. Check: `--scenario=dev --uiux03-test [--shots] [--shot-tag=t] [--scale=1.25]
[--only shots,dropdowns,nav,layout,map,camera,streamer,econ,small]` (results `benchmarks/raw/uiux03_test.json`, shots `docs/ui_ux03/`).
`--legacy-rts-camera` restores the old camera for comparison. Screenshots `before_*` are the pre-milestone HUD and map (same test,
same scenario), `final_*`-less names are 100 % scale at 1920×1080, `s125_*` the default 125 % scale, `11/12_*` 1280×720 at 125 %.

## 1. Problems found

| Area | What was wrong (measured / seen in `before_*`) |
|---|---|
| Squad card | ~550×200 logical px at 100 %; at the default 125 % on 1080p that is two thirds of the screen width. 19 labelled tiles (every order, four behaviour tiles, formation, fire) always visible. |
| Navigation | Development only on F2; construction only on B; no way to reach the base / recruitment except finding and clicking the building; time controls only on keys. |
| Right column | The objective tracker / Opportunities and a selected building's panel were both placed at the top right corner: they overlapped. |
| Map | A 10 m/px raster preview: blurry terrain, pixel-stepped roads, blocky territory blobs at 30–75 % opacity, no relief information, light-on-dark markers. The layer list took a 214×300 px column. |
| RTS camera | One ray focus→camera per frame; the camera was put on the first hit, unsmoothed. Legacy run beside a house: **22.5 m jump in one frame, view turned round 6 times** in 6 s. |
| Economy HUD | `economy_hud.gd:205` "Invalid polygon data, triangulation failed". |
| Vegetation streamer | `vegetation_streamer.gd:679` "Trying to assign invalid previously freed instance". |

## 2. Design decisions

* One visual language for every mode: the existing UI-01C kit (FNUI tokens, dark translucent panels, caps labels, one accent blue, amber
  for armed / selected-on-map, status colours only for state). No new framework: two new kit components (`FNDropdown`, `FNMenu`) and
  icons drawn on the same 24-px grid.
* Show the current state, hide the alternatives: a value that has 4–6 options is one dropdown that shows its value; actions that are
  rare live in one "Squad" menu. Orders that are used constantly stay one click away as icon tiles.
* Hotkeys are accelerators, never the only way in: every key-only screen got a visible entry; tooltips carry the key.
* The map is a planning surface, so it looks like a topographic sheet (Arma 3 / military topo convention): light paper, green woods,
  brown contours, blue water, roads by class; unit symbols follow APP-6 shapes (friendly rectangle with the infantry cross, hostile
  diamond) on top. Dark chrome around it keeps it in the same family as the HUD.

## 3. HUD and squad card

* **Squad card** (`scripts/ui/tactical_panel.gd`): **330×144 logical px** (was ~550×200; −57 % area). Rows: header (emblem, callsign,
  strength, status) · order line · HP / AMMO / SUPP bars with support weapons (MG / RKT / GR) · one row of 9 icon tiles (Bound, Follow,
  Hold, Regroup | Assault, Suppress, Flank, Defend, Withdraw; hotkey in the corner, name + help in the tooltip, amber when armed, green
  bar when current) · **Formation ▾  Behaviour ▾  Fire ▾  Squad ▾** · feedback line.
* **Dropdowns** (`scripts/ui/kit/fn_dropdown.gd`, `fn_menu.gd`): open on the side with room (the bottom card opens upward), clamped
  inside the screen, current choice marked (accent bar + tint), hotkey per row, help in the row tooltip; a click outside or Esc closes
  without acting; a choice calls the existing order (`SquadControl.set_formation`, `RTSController.set_behaviour`, `set_roe`, ...). A
  selection with different values reads **MIXED** (amber); a choice applies to every selected squad. V / Shift+V / X / Y / [ ] / O / R / C
  unchanged. The menu is re-parented to the HUD layer while open, so nothing draws over it.
* **Squad menu**: Garrison base (O), Rearm here (R), Equipment, Spacing wider / closer (] [), Show on screen (C).

## 4. Main navigation (`scripts/ui/nav_bar.gd`)

Two small panels on the top edge of the tactical view:
* left: **Map** (M) · **Build** (B) · **Development** (F2) · **Base** · **Armoury** (F10, Development Scenario only);
* right: **pause** · **1x 2x 4x 8x** · war clock · **game menu** (Esc).

Audit of existing screens: Map, Construction, Military Development, the base / facility panel (recruitment, stores, vehicles),
Equipment (per squad, now in the Squad menu), Armoury (dev rule), pause menu. There is no separate logistics or economy screen (the
supply strip is the economy display; logistics is the facility / vehicle panel), so none was invented. **Base** selects the player's
base building (HQ first) and frames it; repeated clicks step through the bases; disabled with "establish a Command Post" when there is
none. **Development** is hidden in a scenario without Military Development (rule `development`). An open screen shows the selected
surface; F-keys still toggle the same screens.

## 5. Panel layout

`GameHUD._layout_right`: the right column is the building / vehicle panel first, then the tracker. While a panel is up — or when the
list would reach the squad card — the tracker folds to its header with the count ("OPPORTUNITIES · 2", chevron to expand; the player
can fold it too). Check `layout`: building panel 38→219, tracker from 225, no overlap. The roster starts below the navigation row;
the supply strip and the notifications drop below the navigation row on narrow screens instead of touching it. Key-hint bar trimmed to
what has no button now (LMB, RMB, RMB drag, Tab, F1).

## 6. Tactical map overhaul

* **Base layer** (`scripts/ui/map_topo.gd`, `shaders/ui/topo_map.gdshader`), built once on first open (~230 ms) from the live world:
  Terrain3D's height maps as they are in memory (settlements, shoulders, relief applied; 256 px per 2 km region), vegetation.png and
  info.png. The shader draws paper tint by height, fields, rock, built-up areas, woods in two densities, wet ground, a north-west
  hillshade, **contours** (5 / 10 / 20 / 50 m by zoom, bold every fifth, faded where they would crowd), water, and **territory** as a
  13 % tint with a firm border line (one smoothly filtered channel per faction instead of the old cell blobs). Pan / zoom only change
  uniforms.
* **Vectors** in world coordinates (one transform per draw): roads from `RoadNetwork` by class (primary red-orange, secondary yellow,
  local / street white with casing, tracks brown; real width once wider than the symbol; streets from 0.12 px/m), bridges with their
  state (red cross when closed), river and lake shores from water.json, the 1 620 settlement houses from the WorldOverrides layers
  (fitted boxes, from 0.12 px/m).
* **Symbols** restyled for paper: friendly squads light faction fill with dark frame and cross, echelon dot, amber selection frame;
  contacts as hostile diamonds — filled = observed now, dashed hollow = reported, small = stale (still only `IntelSim` contacts);
  objectives / bases / facilities on paper with owner-colour frames; dark ink with a paper halo for every label; camera wedge dark.
* **Chrome**: one top bar — title, war clock, **10 layer toggles + legend** (Units, Contacts, Objectives, Orders, Logistics, Territory,
  Roads, Relief, Grid, Camera, Legend; icon buttons with tooltips), grid reference and height under the cursor, Close. The 214×300 px
  layer column is gone. 1 km grid with edge references, scale bar with the contour interval, legend (drawn with the same calls as the
  map).
* Interaction unchanged (wheel zoom to cursor, MMB pan / camera, LMB select / box, RMB order, buttons). Check `map`: markers at the
  squads' real centres, a right-click move order reaches the squad.

## 7. RTS camera — cause and fix

Cause: `RTSCamera._avoid_obstacles` put the camera on the first static hit of a focus→camera ray every frame, unsmoothed. COMBAT-COVER-03
made settlement houses full-volume box colliders (correctly), and the instance collider pool around the camera anchor is rebuilt every
10 m, so that ray switched between a house and nothing while panning, rotating or zooming: the camera snapped between its zoom
distance and the wall; with the focus at a wall it was put at the focus and `look_at` turned the view round. Building collision was not
changed.

Fix (`scripts/rts/rts_camera.gd`, `_step`): only **buildings and structures** (box solids in the instance pool, StructureManager bodies)
count — trees, rocks, soldiers, vehicles and terrain never move the camera; a building closer than 4 m to the focus **lifts the camera
over its roof** instead of pulling it in; the pull-in and the lift are **smoothed** (in fast / out slow, at most 35 m/s, a long frame
cannot turn the glide into a jump) and measured from the unpulled pose (no feedback). Wheel zoom is never capped. Check `camera` (6 s of
panning across a house, a full turn round it, zoom 6↔26 m): legacy (`--legacy-rts-camera`) **8 flips, worst 3 025 m/s** (a whole correction in one frame); new **0 flips, worst 38.6 m/s**
(speed of the camera distance beyond the zoom's own change).

## 8. Economy HUD error — cause and fix

Cause: world markers (supply caches, construction sites, stashes, capture labels, the tracker's target) were projected with
`is_position_behind` + `unproject_position`. A point just in front of the camera plane (a cache next to a low RTS camera) projects to
coordinates around 10⁹ px; in float32 the 9 px diamond around it loses its size and the canvas cannot triangulate it.
Fix: `FNUI.project(cam, p)` returns the screen point only when it is finite and inside the viewport plus a 200 px margin; every
screen-space marker in `economy_hud.gd` and `objective_tracker.gd` uses it (nothing is drawn that the player could not see).
Check `econ`: a point at the camera plane is not projected, a cache placed there plus one in view drawn without an error.

## 9. Vegetation streamer error — cause and fix

Cause: PERFORMANCE-01's release queue. A cell hidden by camera movement is queued for freeing and kept reusable; when the camera came
back before the drain it was shown again (still in the queue), and when it left again it was queued a **second** time. The older entry
freed it; the newer one then assigned the freed instance to a typed variable (`vegetation_streamer.gd:679`). Typical trigger: panning
back and forth or zooming in and out over woods.
Fix: the queue holds instance ids, an instance is queued at most once (`_queued`), the drain resolves ids with `instance_from_id`
(null when gone) and `_deactivate_all` clears the set. No reference to a freed node is kept. Check `streamer`: hide → show from the queue
→ hide gives one queue entry, the drain frees it; then a 40-step camera sweep with reuse; no error in the log.

## 10. Validation

Real game, Development Scenario, 1920×1080 fullscreen, plus 125 % and 1280×720 @ 125 %. Iterated four times on screenshots (fixes from
the reviews: truncated card title, unreadable meter captions, over-wide Squad button, map title text clipped, map shader painting the
whole screen, scale bar under the key strip, toasts touching the navigation on narrow screens, opportunities growing into the card).

Results of the final run (`benchmarks/raw/uiux03_test.json`): **PASS, 0 failures.**

| Check | Result |
|---|---|
| dropdowns | card 330×144; formation menu opens upward inside the screen; Column / Auto set; outside click closes, nothing changes; Stealth on two squads; X / V still work; mixed selection reads MIXED |
| nav | Map, Build, Development (click and F2), Base (selects the barracks, shows its panel), pause / resume by mouse |
| layout | building panel 38–219, opportunities from 225 folded, no overlap |
| map | topo layer built (240 ms); 5 squads in 4 markers at their real centres; RMB move order reached the squad |
| camera | 0 flips, 38.6 m/s (legacy 8 flips, 3 025 m/s) |
| streamer | one queue entry after hide → show → hide; freed; sweep without error |
| econ | camera-plane point not projected; frame drawn without error |
| small | 1280×720 @ 125 %: card, menu and navigation inside the screen, roster and navigation apart |

No "triangulation failed" and no "previously freed" line in any run's log.

Screenshots (`docs/ui_ux03/`): `01_rts_one_squad`, `02_rts_multi_squads`, `03_formation_dropdown`, `04_behaviour_dropdown`,
`05_building_selected`, `06_building_and_opportunities`, `07_navigation_research` (+ `07a` hover), `08_map_overview`, `09_map_local`,
`09b_map_close`, `10_camera_building_{38,22,9}m`, `11_720p_125_menu`, `12_720p_125_multi`; the same with `s125_` at 125 %;
`before_*` for comparison.

Regression checks chosen by impact (no full suite): `--visual02-test --only wv_streamer` (the release queue serves the variant
streamer) PASS; `--gameplay05-test --only u_orders` (its order-tooltip check was moved to the new order row and Squad menu) PASS.
`--qol01-test` z_shots now hovers the behaviour dropdown instead of the removed tile (compiles; not re-run: screenshot-only).

## 11. Known limitations

* The map's base layer is built from the terrain once per session; roads built later appear through the logistics layer (as before),
  houses built by the player through the facility layer.
* Forest and land cover come from the 10 m generator maps (vegetation.png / info.png), not from the placed trees.
* Camera: with the focus inside a house footprint the camera rises over the roof and shows the roof (it never goes inside).
* `--ui01c-test` (UI-01C phase 1) still addresses the removed ROE / formation tiles and is superseded by `--uiux03-test`.
* Development and Base entries depend on the scenario (no Military Development in the Development Scenario; Base needs a base).

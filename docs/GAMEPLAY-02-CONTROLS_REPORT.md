# GAMEPLAY-02 (controls) — Controls, UI, FPS weapon, tactical placement

Branch `feature/gameplay-02` (worktree `../fractured-nations-gameplay-02`, from `develop` @ `0fac37c`), not pushed or merged.
Named `-CONTROLS` because `docs/GAMEPLAY-02_REPORT.md` is the earlier GAMEPLAY-02 milestone (weapons, roles, explosives).

## Fixed (root causes)

| Problem | Cause | Fix |
|---|---|---|
| Invisible cursor at launch, menu keyboard-only | The world scene's exploration `Player` (FPSController, `player_controlled = true`) captured the mouse in its `_ready`, before `CoreDemo` removed it | One mouse policy: `GameController.refresh_mouse()` (captured only in first person with no menu open; `hold_mouse(reason)` for menus). FPSController and SoldierBody only ask the policy |
| Cursor freed / captured at random after mode changes | Every `SoldierBody` set the global mouse mode from its `player_controlled` setter, so a body streamed in near the player freed the first-person capture | Same policy; mode changes, menus, window focus and a click in first person all go through it |
| Esc "sometimes" did nothing | `PauseMenu` (process mode ALWAYS) stays in the tree when hidden and hidden CanvasLayers still get `_unhandled_input`: after the first use every Esc was eaten as "resume". Also the RTS controller used Esc to clear the selection first | The menu ignores input while hidden; Esc no longer clears the selection (it still cancels an armed order / a right-drag; a click on open ground deselects) |
| No weapon in first person | COMBAT-POLISH-01's prone tilt (`InfantryCharacter._apply_tilt`) reset the character transform to identity every frame - also on the first-person arms, whose transform the `Viewmodel` sets: the rifle sat 1.44 m above the camera | `InfantryCharacter.ground_tilt`, false for the viewmodel arms |
| First-person weapon shook (play test, follow-up) | The Viewmodel placed the arms in `_process` from the previous frame's animated weapon pose: one frame behind the idle, the sight moved 2.5 mm a frame (up to 13 mm, also aiming) | Placed on `skeleton_updated` (after this frame's animation and grip IK): range 21 mm -> under 2 mm, still, aiming and walking (`f_steady`) |
| Speckled, "see-through" shading on arms and weapon (follow-up) | Shadow acne: the possessed body (shadows-only) lies where the first-person arms are. With the body hidden the speckle vanished | Upper-body pieces of the possessed body go on render layer 20, which the sun's `shadow_caster_mask` leaves out (`UnitVisuals.FP_NO_SHADOW_LAYER`); legs and boots keep their shadow. The sleeves' ripstop normal map at 0.3x in first person only (its grid read as dots at 30 cm) |
| Camera 8x too fast at 8x | `RTSCamera` used the scaled frame delta | Real-time delta (also works while paused) |

## Implemented

- **Pause and speed** (tactical view and map): **Space** pause/resume, **1-4** = 1/2/4/8 x (also resume), `,` `.` kept.
  Pause is the scene-tree pause (as the Esc menu) with the presentation kept running (`CoreDemo._presentation()`: cameras,
  RTS controls, HUD, construction, overlays, terrain/vegetation streaming). WorldSim, bodies, navigation and the detail tier stop.
  Speed uses the existing `TimeCompression` (fixed 1/60 s steps). First person / driving: always 1 x and never paused; Space
  keeps jump/brake there. Keys are read by `CoreDemo.KeyRelay` (runs while paused). Keys 1-4 no longer jump to sites in the
  sandbox (the old scripted worlds keep them). A chip at the top shows PAUSED / the speed.
- **UI scale**: Settings screen (start screen and Esc menu), 75-175 % in 5 % steps, default 125 %, applied on slider release,
  saved in `user://settings.cfg` (`UISettings`), applied at start. Uses the root window's `content_scale_factor` on the
  existing canvas_items stretch, so every menu, HUD panel and tooltip scales together. Scripted tests always run at 100 %.
- **RTS hover / feedback**: brackets and a tag on the unit under the cursor (blue = yours with "click select" / "RMB board",
  red = a visible enemy with the order keys), a ground reticle where a move would go, cursor shape (hand / cross), a short
  pulse where an order was given. Dark outlines for contrast.
- **Right-drag placement**: short right click = move (now given on release); hold and drag = frontage. Preview: line, facing
  arrow (away from where the squad stands), every soldier's place (filled = cover), lines from each soldier. Release orders
  it. `SquadPositions.placement` spreads soldiers evenly (min 1.3 m; short drags make ranks), snaps places to protected cover
  near the line (`CombatBrain.cover_spots` + `_evaluate_spot` against a threat ahead of the line). `SquadControl.order_place`
  is an ordinary squad Move whose slots are those places (`SquadState.placed`, saved; cleared by any new order in
  `SquadTactics.on_order`); each place is the soldier's post; the end-of-move cover step (`_settle`) leaves placed squads
  alone. Several selected squads share the line by size; selected loose soldiers get individual moves.
- **Construction speed** (`BuildCosts.WORK`, player and AI): field works ~40 %, mid buildings ~50 %, large ~60 % of before.
  Costs unchanged. Soldier-seconds (8 soldiers = /8): sandbag position 96→40, fighting position 110→45, MG nest 140→60,
  guard tower 240→120, command post 480→240, supply depot 560→320, barracks block 640→380, vehicle depot 720→430,
  HQ 960→600; line modules halved (HESCO 16→8). Repairs follow (share of work).

## Controls

Tactical: RMB move · **RMB drag place** · **Space** pause · **1-4** speed · Esc menu. First person: unchanged (Space jump), Esc
menu. Settings: start screen or Esc → Settings.

## Verification

`--scenario=new_game --controls-test --shots --fullscreen` (`scripts/debug/controls_selftest.gd`, real input events pushed
into the viewport), one run, **PASS**, shots in `docs/gameplay02_controls/`:

| Check | Result |
|---|---|
| m_mouse | cursor visible in RTS; first person wants capture, still after a body spawns; menu shows it; resume recaptures; back to RTS visible |
| e_escape | 3x open/close with a squad selected (selection kept) and 3x in first person |
| f_steady | sight point frame to frame: median 0.5 mm, max 1.8 mm, range < 2 mm (before 2.5 / 13 / 21 mm); `f_steady_light.png`, `f_steady_against_sun.png` |
| f_weapon | weapon at camera (0.06, -0.29, -0.38) - in view (before: (0.14, +1.44, -0.45)); `f_weapon_hip.png` |
| u_scale | 125 %: canvas 922x518, 175 %: 658x370, command panel on screen in both; settings panel opens |
| s_speed | paused: sim clock +0.00 s, camera moved 52 m; 1-4 = 1/2/4/8 x; possession -> 1 x, unpaused, key 4 ignored |
| d_drag | 18 m drag: preview 8/8, placed 8, min gap 2.57 m, on the line, all arrived within 1.0 m and stayed; short click = plain move |
| b_build | sandbag fighting position: work 40, 8 soldiers, done in 6.6 simulated s |

All scripts compile (`tools/check_scripts.gd`). No regression suites run (brief: short targeted checks only).

## Limitations

- The start screen was not clicked by a test (tests skip it); the cursor is visible from the first frame by the policy.
- Placement was measured on open ground (0 cover spots); the cover snap reuses the AI's cover search, not separately measured.
- Several squads share one line by size; no multi-squad planner. Facing is "away from the squad", no manual rotation.
- At 175 % the 1152x648 HUD gets tight (fits, verified for the command panel only).
- The worktree needs the git-ignored world: `worlds/ref_20km/{source,terrain,vegetation,water}` are junctions to the main
  folder, `terrain_*.tres`, `scenes/world/ref_20km.tscn` and `.godot/` were copied (none committed).

## Files

`scripts/core/game_controller.gd`, `scripts/player/fps_controller.gd`, `scripts/game/core_demo.gd`, `scripts/ui/pause_menu.gd`,
`scripts/ui/main_menu.gd`, `scripts/ui/settings_panel.gd` (new), `scripts/ui/ui_settings.gd` (new), `scripts/ui/game_hud.gd`,
`scripts/ui/tactical_panel.gd`, `scripts/rts/rts_controller.gd`, `scripts/rts/rts_camera.gd`, `scripts/core/time_compression.gd`,
`scripts/characters/infantry_character.gd`, `scripts/combat/viewmodel.gd`, `scripts/units/unit_visuals.gd`, `scripts/core/squad_positions.gd`,
`scripts/core/squad_control.gd`, `scripts/core/squad_state.gd`, `scripts/core/squad_tactics.gd`,
`scripts/construction/build_costs.gd`, `scripts/debug/controls_selftest.gd` (new), `README.md`, this report.

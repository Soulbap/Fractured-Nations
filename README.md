# FRACTURED NATIONS

Modern military sandbox in Godot 4. One large, continuous 3D world shared by the FPS,
RTS and 2D-map views.

**Project standard (PROJECT-CONSOLIDATION-01):** one Godot project in the folder
`C:\Users\Hafnor\Desktop\Game Dev\fractured-nations`, one active development branch **`develop`** (`main` is the
stable branch, updated only with the product owner's approval), one canonical development world **`ref_20km`**
(main scene `scenes/game/world_ref_20km.tscn`, checked with `worlds/ref_20km.manifest.json`). All earlier feature
branches are contained in `develop` and stay as history. Next milestone: **NAVIGATION N1** (baseline, off-road and
obstacle navigation). See [docs/PROJECT-CONSOLIDATION-01_REPORT.md](docs/PROJECT-CONSOLIDATION-01_REPORT.md) and
[CLAUDE.md](CLAUDE.md).

Newest gameplay: **GAMEPLAY-03** (on `develop`) — defensive warfare: defending squads judge their posts against the
believed threat (protection, line of fire, **concealment** measured from the enemy's side, prepared positions, weapon
roles: the machine gunner takes the widest arc it is least seen from, the grenadier a concealed post), keep the posts that
still serve when the threat moves, and a garrison no longer gives up its base because it is outnumbered: it **falls back
line by line inside the base** (forward fire team first, the other covering) and holds its last line round the objective.
Attackers rank their fire support by danger (enemies reported at fortifications first), send a support squad that can no
longer fire in with the assault, and retry from another side. The AI grenadier visibly raises the launcher before firing;
soldiers notice a grenade after a moment and get down when they cannot get clear. The MG emplacement's roof now leaves the
rear open (the crew is visible). See [docs/GAMEPLAY-03_REPORT.md](docs/GAMEPLAY-03_REPORT.md).

Before that, **GAMEPLAY-02** (on `develop`) — infantry combat and support weapons: every squad carries a **light
machine gun** (sustained, suppressive fire; better braced, worse on the move) and a **grenadier** with hand grenades and a
light **anti-structure launcher**; all soldiers carry a frag grenade. The AI uses them on what it has seen (grenades into
positions and cover, rockets at enemy structures, never with friends in the blast), the MG gunner takes the best firing
post and the MG emplacement's gun slot, soldiers get clear of grenades they see land. Multi-squad attacks were diagnosed
with a combat recorder and recoordinated (assault positions, staggered starts, a fire support that covers when the assault
crosses, no lone re-assaults). First person: **G** throws a grenade, **X** raises the launcher; suppression darkens the
screen edges. New Blender assets: LMG, ammunition box, grenade, launcher. See [docs/GAMEPLAY-02_REPORT.md](docs/GAMEPLAY-02_REPORT.md).

Before that, **GAMEPLAY-01C–01G** (on `develop`) — base warfare: soldiers fight from fortifications (towers,
fighting positions, an MG emplacement, HESCO and sandbag walls; new and rebuilt Blender assets), squads can be ordered to
**Garrison** a base (**O**), every base is a strategic objective that the player and the AI factions attack, defend and
capture (also off-screen), AI factions expand with outpost / defensive / main base templates, depleted squads are
replenished at a barracks, structures take damage, are disabled and repaired by soldiers, and **Esc** opens an in-game
menu (resume, save, load, main menu, quit). See [docs/GAMEPLAY-01C_01G_REPORT.md](docs/GAMEPLAY-01C_01G_REPORT.md).

Before that, **GAMEPLAY-01B** (merged) — the first playable early game: a start screen with
**New Game** (eight North soldiers in the south, no base, little supply), Continue and the Development Scenario;
supply caches, paid construction and recruitment, income from captured objectives; buildings are construction sites
that idle soldiers build (squad tactic BUILD); safe, scenario-aware saves. See
[docs/GAMEPLAY-01B_REPORT.md](docs/GAMEPLAY-01B_REPORT.md).

Before that, **BASE-01** (branch `feature/base-01`) — the player establishes their own base anywhere suitable: in
construction mode (**B**, RTS) a **Command Post** opens a base with a 150 m area, and **Barracks**, **Supply Depot**,
**Vehicle Parking** and **Guard Post** are built inside it; refused spots say why (too steep, water, road or bridge, outside
the base area, overlap). The base is a real, saved `ConstructionState` base that the logistics and war systems read; see
[docs/BASE-01_REPORT.md](docs/BASE-01_REPORT.md).

Before that, **AI-WAR-LOGISTICS-01** (merged into `develop`) — AI factions have bases and income, recruit, take
vehicles, move squads in convoys over a road network that was audited and repaired (`--road-audit`, overlay **F8**), supply
and counterattack; see [docs/AI-WAR-LOGISTICS-01_REPORT.md](docs/AI-WAR-LOGISTICS-01_REPORT.md).

Previous state: **AI-COMBAT-STRAT-01** (branch `feature/ai-combat-strat-01`, built on `feature/ai-squad-01`) — AI attacks
are coordinated operations: the squads get roles (assault, fire support, maneuver, reserve, security) and the
operation moves through approach, deploy, support, assault and secure; it breaks off with cover fire when it is losing
and its survivors recover before they are used again. AI factions score attack / reinforce / join / garrison from what
they have been told (confirmed, reported, stale or assumed), keep a reserve, stick to a decision for a while and send
help to a running attack instead of starting a second one; garrisons spread over sectors facing the believed threat.
The strategic-map AI inspector (**I**) shows stages, roles, forces and every candidate action with its utility. See
[docs/AI-COMBAT-STRAT-01_REPORT.md](docs/AI-COMBAT-STRAT-01_REPORT.md).

Before that, **AI-SQUAD-01** (branch `feature/ai-squad-01`, built on `feature/ai-intel-01`) — infantry squads fight
as organised units. A squad splits into two fire teams (leaders take over when one falls), spreads out when it comes
under fire, picks firing posts with cover and a view, and carries out squad tactics: **defend**, **suppress** (fire
at a reported position, with real ammunition, until the report is old), **assault**, **flank** (a covered route chosen
only when it exposes the squad clearly less than going straight in), **bound** (one team moves while the other
covers), **reposition**, **withdraw** (leapfrogging back with covering fire) and **regroup**. Shots passing close
suppress soldiers (less accurate, slower to react, head down, pinned teams do not dash). Squads choose tactics only
when nobody commands them and only from what they saw or what their faction has been told; operations assault
objectives with the same tactics. You command them from the tactical view: select a squad and press **Z** assault,
**K** suppress, **L** flank, **J** defend, **Backspace** withdraw (at the cursor, or arm from the bottom-right bar and
click), **Shift + right click** moves by bounds, **Shift+V** cycles formations (V still toggles line / column; auto: column on roads and in woods, wedge in
the open, dispersed under fire); **F7** shows fire teams, posts, fire missions and flank routes. Four new Blender cover
props (sandbag fighting position, log barricade, boulder group, earth berm) are in the construction menu under Defences.
`--squad-demo` starts a ready-made encounter (a defended position, two attacking squads) in the real game. See
[docs/AI-SQUAD-01_REPORT.md](docs/AI-SQUAD-01_REPORT.md).

Before that, **AI-INTEL-01 / AI-OBS-01** (branch `feature/ai-intel-01`, built on `feature/integration-04`) —
factions no longer know where enemies are merely because they are near: what a faction believes comes from
reports (soldiers who saw an enemy, heard gunfire or were shot at, or hold an objective an enemy stands in),
arrives after a short delay, ages into stale beliefs with a growing uncertainty circle, is saved with the war,
and is what the strategic AI uses to reinforce, reassess and send a squad to look at an old report. The
strategic map shows your faction's contact picture (filled diamond = seen now, outlined = reported, faded =
stale, circle = how far it may have moved). Developer inspector on the map: **I** cycles through the factions'
pictures and decisions, **T** adds the true squad positions (labelled TRUTH) and lets you inspect any squad.
See [docs/AI-INTEL-01_OBS-01_REPORT.md](docs/AI-INTEL-01_OBS-01_REPORT.md).

Before that, **INTEGRATION-04** (branch `feature/integration-04`) — LOGISTICS-01 / BASE-02 and the
AI architecture research integrated on top of `feature/world-integration-03`, no gameplay change. The
consolidated AI plan (interfaces the AI uses, gaps, milestone order) is [docs/AI_ROADMAP.md](docs/AI_ROADMAP.md);
the integration findings are in [docs/INTEGRATION-04_REPORT.md](docs/INTEGRATION-04_REPORT.md).

Before that, **LOGISTICS-01 / BASE-02** (branch `feature/logistics-01-base-02`, built on
`feature/world-integration-03`) — the military operations layer: the 6x6 truck and 8x8 APC are
persistent, drivable units (AI along the real road network, bridges and player-built roads, in
the near and the abstract tier alike; direct control with a chase camera), infantry board,
ride and disembark, one inventory model carries ammunition, fuel and supplies between depots
by truck and convoy, soldiers resupply from depots, and bases are groups of working facilities
(barracks recruit squads, the vehicle depot hands out vehicles, depots store and load) with optional,
overridable automation. Controls: RMB vehicles / squads, **T** board, **U** unload, **P** take the
wheel (W/S/A/D, V bumper view, Tab back), click a building for its panel; the strategic map shows
vehicles, bases and your roads. See [docs/LOGISTICS-01_BASE-02_REPORT.md](docs/LOGISTICS-01_BASE-02_REPORT.md).

Before that, **WORLD-INTEGRATION-03** (branch `feature/world-integration-03`, the new
development baseline) — WORLD-PLAYTEST-01 and ASSET-PRODUCTION-01 brought together in one
playable sandbox: the corrected 20 km world with its road network, player-built roads and
yards; three infantry families in the war (North wears NATO kit, South Russian, East Chinese —
a configurable table in `WorldState.FACTION_LOADOUTS`, not a faction identity); the nine
military base buildings, 24 base-expansion modules and a curated set of props placeable
through the construction menu (six collapsible categories: Buildings, Training, Logistics,
Defences, Infrastructure, Roads) with the existing groundwork, clearing, collision and
navigation; the 6x6 truck and 8x8 APC validated in the world as visual prototypes. See
[docs/WORLD-INTEGRATION-03_REPORT.md](docs/WORLD-INTEGRATION-03_REPORT.md).

Before that, **WORLD-PLAYTEST-01** (branch `feature/world-playtest-01`, from the unified
sandbox) — fixes from the first manual playtest: the river runs in a natural valley instead
of a 27 m deep canal, bridges span an open river (they stood on earth dams), the 300 km road
network was audited and repaired, the player can build dirt / gravel / asphalt roads as curves
and paved yards as polygons (one shared road network with the world's roads and the AI's
routes), long move orders follow strategic routes over bridges instead of wading, the strategic
map shows the tactical camera with a view wedge (middle click moves it there), middle-drag
tilts the RTS camera, and time compression reaches the requested 2-8 x (16 x added). See
[docs/WORLD-PLAYTEST-01_REPORT.md](docs/WORLD-PLAYTEST-01_REPORT.md).

Before that, **INTEGRATION-02** — the unified sandbox on branch `feature/unified-sandbox`,
the single development baseline: the complete WORLD-SANDBOX-01B war (strategic map, RTS, FPS,
faction AI, operations, combat, construction, saves) with the CHARACTER-01 soldiers (rig,
equipment, animations, first-person carbine). See
[docs/INTEGRATION-02_REPORT.md](docs/INTEGRATION-02_REPORT.md) for what was integrated and how
to launch it; development rules are in [CLAUDE.md](CLAUDE.md).

Before that, **WORLD-SANDBOX-01B** — the war made ready for the first manual playtest: a
readable strategic map (smooth zoom towards the cursor; squads always drawn at their real
positions and grouped on screen only when they would overlap; operation details with march
progress), a short HUD that names your faction (F1 all controls, F3 technical counters), AI
factions that move reserves up to the front and no longer throw small attacks at fortified
HQs, and accelerated tests that run the same 1/60 s simulation steps as normal play. See
[docs/WORLD-SANDBOX-01B_REPORT.md](docs/WORLD-SANDBOX-01B_REPORT.md).

Before that, **WORLD-SANDBOX-01** — the first playable persistent war. Three factions
(North = you, South = aggressive AI, East = defensive AI) fight for twelve strategic objectives
(bases, towns, river bridges, villages) across the whole 20 x 20 km world. Forces march along
planned routes (roads and bridges, never through lakes, the river or cliffs), capture ground by
driving defenders out, reinforce, recover and run out of reserves. You command your faction on a
strategic map (M), in the tactical view and in first person - the same soldiers in the same
world, which keeps fighting wherever you are and is saved with F5. See
[docs/WORLD-SANDBOX-01_REPORT.md](docs/WORLD-SANDBOX-01_REPORT.md).

Before that, **COMBAT-02** — larger and smarter infantry fights: 100 v 100 and several
battles kilometres apart run at about 3.3 ms average frame time; soldiers who come under fire
work out roughly where it comes from and take nearby cover (HESCO, buildings, rocks, trees,
terrain) and fight from it, within what their squad order allows (Hold keeps its area, Move and
Follow only pause briefly, Hold Fire takes cover without firing; a player order always wins);
see [docs/COMBAT-02_REPORT.md](docs/COMBAT-02_REPORT.md).

Before that, **COMBAT-01b** — soldiers fight on their own: they see enemies (field of
view, terrain, trees, foliage, structures), pick and keep a target, aim with human error,
fire, reload and take casualties through the same rifle and combat authority as the player,
while squad orders, Hold Fire / Weapons Free, possession and save/load keep working; see
[docs/COMBAT-01B_REPORT.md](docs/COMBAT-01B_REPORT.md).

Before that, **COMBAT-01a** — the first rifle: possess a soldier, aim, fire (semi / auto),
reload and kill; hits and cover are resolved from world data, so they work at any range and
with or without the camera nearby; see [docs/COMBAT-01A_REPORT.md](docs/COMBAT-01A_REPORT.md).

Before that, **UNIT-01A** — squads with tactical orders (move in line or column, hold, follow,
regroup) on top of the soldiers, persistent through FPS possession, the abstract tier and
save/load; see [docs/UNIT-01A_REPORT.md](docs/UNIT-01A_REPORT.md).

Before that, **WORLD-INTEGRATION-01** — the construction system and the FPS/RTS game run on
the reference world `ref_20km`, which is now the main scene (see
[docs/WORLD-INTEGRATION-01_REPORT.md](docs/WORLD-INTEGRATION-01_REPORT.md) and
[docs/WORLD-TERRAIN-01_REPORT.md](docs/WORLD-TERRAIN-01_REPORT.md)), on top of
**WORLD-BASE-01** freeform military base construction (RTS construction mode,
drag-to-build HESCO / fences / barriers, Blender-made construction set, persistent and saved)
on the **WORLD-CORE-02** 20 km world simulation, the WORLD-CORE-01 FPS/RTS control, the
WORLD-TECH-02 vegetation foundation and the WORLD-TECH-01 world-technology prototype. See
[docs/WORLD-BASE-01_REPORT.md](docs/WORLD-BASE-01_REPORT.md),
[docs/WORLD-CORE-02_REPORT.md](docs/WORLD-CORE-02_REPORT.md),
[docs/WORLD-CORE-01_REPORT.md](docs/WORLD-CORE-01_REPORT.md),
[docs/WORLD-TECH-02_REPORT.md](docs/WORLD-TECH-02_REPORT.md) and
[docs/WORLD-TECH-01_REPORT.md](docs/WORLD-TECH-01_REPORT.md).

**CHARACTER-01** (branch `feature/character-01`): modular modern infantry character. One
shared rig, body and animation set dressed by data-driven loadouts (standard, heavy, recon),
generated by `tools/blender/character/build_infantry.py` and assembled by
`scripts/characters/`. Soldiers in the game use it automatically. See
[docs/CHARACTER-01_REPORT.md](docs/CHARACTER-01_REPORT.md) and the asset standard
[docs/CHARACTER_STANDARD.md](docs/CHARACTER_STANDARD.md); inspect it in
`scenes/characters/character_lab.tscn` (1–4 speed, C crouch, Q/E orbit, wheel zoom).

## Requirements

| Dependency | Version | Notes |
|---|---|---|
| Godot | **4.7.2-stable** (standard, not .NET) | Forward+ renderer, **Vulkan** (D3D12 only as automatic fallback) |
| Physics | Jolt (built into Godot 4.7) | Set in Project Settings → Physics → 3D |
| Terrain3D | 1.0.2-stable (MIT) | Bundled in `addons/terrain_3d` (Windows + Linux x86_64 binaries) |
| Godot Road Generator | 0.9.5 (MIT) | Bundled in `addons/road-generator` |
| Godot AI | 4.3.0 | Editor MCP addon used during development, optional |

All addons are committed to the repository. Nothing has to be installed separately.

## Opening the project

1. Clone the repository and check out `develop` (the active development branch; `main` is the
   stable branch). On the development machine the project lives in
   `C:\Users\Hafnor\Desktop\Game Dev\fractured-nations`, next to the Godot executables.
2. Put the canonical world data in place (it is not in git, see *Reference world* below) and open
   `project.godot` with Godot 4.7.2. The first import takes about a minute.
3. If the editor shows errors about Terrain3D on first open, restart the editor once.
   GDExtensions load at startup.

## Running the prototype

**The main scene is `scenes/game/world_ref_20km.tscn`, which needs the generated reference
world.** On a fresh checkout build it first (about 14 minutes, ~2.4 GB of git-ignored data under
`worlds/ref_20km/` and `scenes/world/ref_20km.tscn`; Blender 5.x must be installed because the
generator runs in Blender's Python):

```bash
bash tools/terrain_ref/build_ref_world.sh
```

Then press **F5**. The start screen (GAMEPLAY-01B) offers:

- **New Game** — one North squad of eight near Moen in the south, no base, 500 kg of supplies. South holds the former
  North territory in the north, East the east bank. Secure supply caches (diamond markers, 30 s), place a **Command
  Post** (B) — your idle soldiers walk there and build it — then a Supply Depot, Barracks and defences, recruit at the
  barracks and take objectives for income. The supply strip (top) and a dismissible hint guide the first steps.
- **Continue** — the saved game (F5 saves, F9 loads, or **Esc** → Save Game / Load Game; one slot in `user://saves/ref_20km/`).
  Esc → Main Menu returns here without starting anything.
- **Development Scenario** — the full three-faction war as before: you are North (blue) in the tactical view over
  your HQ with five squads, free and instant construction and the starting stockpile; South (orange, aggressive) and
  East (green, defensive) plan and launch their own operations.

`-- --scenario=new_game|dev` or `-- --continue` skip the menu; scripted tests default to the Development Scenario and
save to `user://test_saves/`, never to your save. Press **M** for the strategic map. The first start builds the
strategic route grid (about 1 s) and caches it in `user://strategic/`. The scripted tests of
earlier milestones (`--squad-test`, `--combat-test` ...) still use their own fixed two-faction
layout. The small `scenes/game/core_demo.tscn` (2 km world, no build needed) still runs on its
own with that layout.

| Key | Strategic map (M) |
|---|---|
| M / Esc | Open / close the map (from first person the game switches to the tactical view first) |
| H | Show / hide the map controls on the map |
| Wheel, middle-drag or WASD, Home | Zoom towards the cursor (whole map down to a base), pan, whole map |
| Middle click (no drag) | Move the tactical camera there (keeps its heading, tilt and height); the white dot and faint wedge show where the tactical camera is and which way it looks |
| LMB, LMB-drag, Shift | Select a squad or a group of squads, an objective or an operation (also its label on the map or its row in the list); box select; add |
| Double-click a group | Zoom in until its squads separate |
| LMB on an objective with squads selected | Makes it their target; then Attack / Defend / Reinforce |
| RMB | Order the selected squads: on an enemy or neutral objective = **attack**, on your own = **reinforce**, on open ground = **move** (all as operations with planned routes); cancels a pending button order |
| Buttons | Attack / Defend / Reinforce the target (or click one after the button), Move (then click the ground), Cancel op, View |
| G, "Go" in the operation list | Jump the tactical camera there (closes the map) |
| , and . | Time compression 1 / 2 / 4 / 8 / 16 x (first person always runs at 1 x); the HUD shows the speed reached when the machine falls short |
| F5 / F9 | Save / load the whole war |

The map shows territory (each objective's area in its owner's colour), objectives with capture
progress, CONTESTED (blinking ring) and THREATENED (red warning: enemies seen near one of yours),
your squads (NATO symbols with strength, at their real positions; squads that would overlap on
screen are drawn as one group "3 sq · 24" at their real centre, and squads standing in an
objective show as a badge on it on the whole-map view), every soldier as a dot when zoomed in
close, enemy forces your soldiers have seen (diamonds; they fade when not seen for a while), your
operations with their routes and the war log. Selecting an operation shows its squads and
strength, phase, march progress and an arrival estimate once the measured progress supports
one, and the outcome of ended operations (listed for five minutes). A direct RTS order (move,
hold, follow, regroup) takes a squad out of its operation: your command always wins.

In the tactical view (UI-01C) the **Task Force** roster top left lists your squads with their strength
and status under your faction's name; click a row to select a squad, Shift+click to add one. With
squads selected, the **command panel** at the bottom shows the selection (strength, current order,
health, ammunition, suppression, formation, rules of engagement) and every order grouped as MOVE /
COMBAT / DEFENCE / SQUAD with its key; with nothing selected a quiet key-hint bar takes its place.
F1 shows every control, F3 the technical counters and the frame-time overlay, F4 the AI debug view.
Selected squads are framed by corner brackets with their tag; each soldier is a small dot. A selected
vehicle or facility opens its panel top right (status, fuel, cargo, stock and its orders).

In first person the weapon (rounds in the magazine, reserve, fire mode) sits bottom right, health bottom
left, your squad and its order top right, and a reload prompt appears under the crosshair when the
magazine runs low. In construction (B) the build menu on the right has the base, categories and a card
with a picture per building; the panel at the bottom says whether the spot is valid, why not, and the keys.
The strategic map (M) keeps the command panel, map layers and operations on the left and an inspector on
the right for whatever is selected. All of it is built on the FRACTURED NATIONS UI kit (`scripts/ui/kit/`,
reports [UI-01C phase 1](docs/UI-01C_PHASE1_REPORT.md), [phase 2](docs/UI-01C_PHASE2_REPORT.md)); building
thumbnails come from `tools/ui/make_structure_thumbs.gd`.

| Key | First person (possessing a soldier) |
|---|---|
| Mouse | Look (click to capture, Esc to release) |
| W A S D / Shift / Space | Move / sprint / jump |
| LMB (hold in auto) / RMB | Fire / aim (narrower view) |
| R / V | Reload / semi or automatic fire |
| G | GAMEPLAY-02: throw a grenade at the point under the crosshair (up to 35 m; the HUD shows the grenades left) |
| X | GAMEPLAY-02: raise / lower the secondary weapon (the grenadier's light anti-structure launcher); LMB fires it |
| **Tab** | Switch to the tactical camera (the soldier returns to the simulation) |
| F | Debug fly / noclip |
| F3 | Performance overlay (in the war also unit / detail counters in the HUD) |
| F1 | All controls in the HUD text (war) |
| M | Strategic map (WORLD-SANDBOX-01 war) |
| F4 | AI combat debug overlay (both views): state, target, why a soldier is not firing; COMBAT-02: tactical state, threat direction (orange), chosen cover (green ring), reaction path (dashed), "AI reaction" vs "order", cover reasons |

| Key | Tactical (RTS) |
|---|---|
| W A S D (Shift faster) | Pan |
| Q / E, middle-mouse drag | Rotate; middle-drag up / down tilts the view (8–84° below the horizon) |
| Mouse wheel | Zoom (5–200 m, starts at 80 m; `RTSCamera.zoom_min` / `zoom_max` / `zoom_default`) |
| **B** | Construction mode (see below) |
| Left click / drag box, Shift+click | Select soldiers and vehicles / add to selection, Ctrl+A all soldiers |
| Ctrl+click, squad panel (left) | Select a soldier's whole squad; Shift adds more squads. Rows show order, progress, living + fallen, engaging / under fire / in cover; the list scrolls when it would reach the HUD text |
| Right click | Move: selected squads walk in formation to the point (side by side if several); a move over 150 m, or one that would cross water or a cliff, follows a strategic route (roads, bridges) in column and takes the formation again at the end; other selected soldiers get individual orders and leave their squad's order until its next one |
| H | Hold: selected squads stop and stay; other selected soldiers stop |
| F, then click a soldier | Selected squads follow that soldier, or its squad (its leader) |
| G / Shift+G | Regroup selected squads on their leader / at the cursor |
| V, [ and ] | Line or column formation, spacing −/+ 0.5 m (1.5–10 m) |
| Y, FREE / HOLD in the squad panel | Rules of engagement of the selected squads: Weapons Free (default, soldiers engage on their own) / Hold Fire (they track but do not shoot) |
| **O**, Garrison button | GAMEPLAY-01C: the selected squads garrison the base at the cursor (or clicked after the button): they man its towers, positions and walls and stay until given another order |
| Esc (nothing selected) | GAMEPLAY-01G in-game menu: Resume, Save Game, Load Game, Main Menu, Quit Game (the game is paused) |
| P, Enter or double-click | Possess the selected soldier (first person) |
| **Tab** | Return to the soldier you last controlled |

F5 / F9 also save and load units and squads (`user://saves/<world>/world.json`, next to the
construction file).

### Construction (WORLD-BASE-01, RTS)

| Key | Construction mode |
|---|---|
| B | Enter / leave; pick a type in the panel (top right) |
| Mouse, LMB | Building preview (green / red with reason), click builds |
| R, Shift+R, Ctrl+wheel | Rotate 15° |
| LMB on lines | Start, then one click per corner; click the start again to close a perimeter |
| Enter, RMB, double-click | Finish the line; Backspace removes the last corner |
| Shift / Ctrl (held) | 15° direction steps / no snapping |
| X | Delete tool: click removes a building or one line module, Shift+click a whole line |
| C | Vegetation clearing on (default) / off: trees, shrubs and debris inside new footprints are cut (saved with the base); off, trees block placement. Rocks and settlement buildings always block |
| Roads (category "Roads") | Dirt track / gravel road / asphalt road: LMB adds control points, the road curves through them; drag a point to reshape; ends snap to roads, road ends and junctions (Ctrl: no snap); clicking onto a road, Enter, RMB or double-click builds. Graded into the terrain (green / red sections in the preview), part of the AI's route network |
| Yards | Gravel / asphalt yard: click the corners, click the first one or press Enter to close; graded to one plane, paved, no route shortcut |
| Esc | Cancel line → tool → leave |
| F5 / F9 | Save / load construction (`user://saves/<world>/construction.json`) |

**Your base (BASE-01).** The panel's **BASE** section lists the five base buildings; until you have a base only the
**Command Post** can be chosen. Place it on open, level ground (not on a road, not in or next to another base, not on
ground another faction holds): it establishes "North base N" with a 150 m area, drawn as a dashed ring on the ground
while construction mode is open. Barracks (+32 soldier capacity), Supply Depot (base stores; the first one receives the
starting stockpile), Vehicle Parking (six bays) and Guard Post must stand inside that area. The HUD and the panel show
the base's buildings, beds, bays and guard posts; the strategic map (**M**) shows the area and the facilities (H, B, S,
P, G). Everything is saved with F5 and loaded with F9. Scripted check: `--base01-test [--shots] [--only
collision,infantry,vehicle,persist,far,views]` (results in `benchmarks/raw/base01_test.json`, screenshots in `docs/base_01/`).

Assets are generated in Blender by `tools/blender/structures/*.py` (sources in
`assets/structures/blender/`). Scripted checks on the reference world (from the repository
root, after the world build): `bash benchmarks/wi01/run_test.sh integration --shots`
(construction in five terrain types, clearing, navigation, persistence, performance),
`... base` (the WORLD-BASE-01 checks) and `... large` (the WORLD-CORE-02 checks). The newest
runner, `bash benchmarks/sandbox01b/run_test.sh <kind>`, also takes `sandbox` (WORLD-SANDBOX-01 /
01B war scenarios, `--only a,b`, e.g. `map_ui,hud,warp_fidelity`), `combat-tactics` (COMBAT-02
reactions and cover), `combat-scale` (COMBAT-02 16 / 50 / 100 v N, two battles), `combat-ai`
(COMBAT-01b AI firefights), `combat` (COMBAT-01a) and `squad` (UNIT-01A).

WORLD-PLAYTEST-01 checks: `Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900
res://scenes/game/world_ref_20km.tscn -- --playtest-test [--shots] [--only nav_river,nav_long,nav_base,roads,camera,timescale]`;
world geometry audits after a world build: `python tools/terrain_ref/audit_roads.py worlds/ref_20km/source`
(Blender's Python) and `Godot_console.exe --headless --path . --script res://tools/terrain_ref/audit_world.gd`.

The world exploration scene `scenes/world/test_2km.tscn` still runs on its own with the
WORLD-TECH-01 free-roaming controller.

## Editing the world

Open `scenes/world/test_2km.tscn` in the editor.

- **Terrain:** select `Terrain3D` and use the Terrain3D toolbar to sculpt and paint
  textures. Save the scene to write the region files in `worlds/test_2km/terrain/`.
- **Vegetation:** trees, bushes and rocks live in `worlds/<name>/vegetation/veg_<x>_<z>.res`
  (1024 m chunks of 128 m cells) and are streamed around the camera by the `Vegetation`
  node (`VegetationStreamer`, also in the editor viewport). Grass is camera-local GPU
  particles (`Grass` node, `GrassLayer`) masked by `worlds/<name>/vegetation/mask.res`
  (roads, base pads). You can still paint trees with Terrain3D's instancer brush; the
  `WorldBuilder` button **Bake painted instances into cells** moves them into the chunk
  files (otherwise they stay as Terrain3D MultiMeshes for the whole map).
- **Roads:** select a `RoadPoint` under `Roads/RoadManager/RoadNetwork` and move it, or
  use the Road Generator toolbar to add roads and intersections.
  `Roads/Terrain3DRoadConnector` flattens the terrain under the roads.
- **Regeneration:** the `WorldBuilder` node has inspector buttons to regenerate the
  terrain, rebuild the roads or rescatter vegetation (chunks, grass mask and the forest
  tint baked into the Terrain3D color map) from its `WorldConfig`. These overwrite hand
  edits in that layer. A copy of the terrain data is written to
  `worlds/<name>/terrain_backup/` first.

### Viewing the reference world in the editor (EDITOR-WORLD-01, phase 1)

Open `scenes/world/ref_20km.tscn` (not the main scene) to see the real game world without
running it: terrain, roads, water, bridges, trees, rocks, houses and grass. A new
**Viewpoints** menu in the 3D toolbar moves the *editor* camera (overview, every town and
village from `sites.json`, plateaus and base sites) at a safe height over Terrain3D. The
editor camera starts at y=0, below the 50-1200 m terrain, so use that menu or fly up first.
The plugin raises the editor's 3D Z-Far preference to 30 km on first enable (takes effect
after one editor restart; per open viewport: View > Settings > Z-Far). Editing terrain and
roads is phase 2 and not yet supported as a workflow; see
[docs/EDITOR-WORLD-01_REPORT.md](docs/EDITOR-WORLD-01_REPORT.md).

### Building a world from the command line

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/build_world.gd -- --config=res://worlds/test_2km/world_config.tres
```

A new size from defaults (written to `worlds/<name>/` and `scenes/world/<name>.tscn`):

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/build_world.gd -- --name=scale_4km --size=4096
```

Options: `--spacing=<m>`, `--region=<256|512|1024|2048>`, `--grass-extent=<m>`,
`--veg-extent=<m>`, `--no-roads`, `--no-vegetation`, `--no-scene`.
Scale-test worlds (`worlds/scale_*`) are git-ignored.

Rebuild only the vegetation of an existing world (chunks, mask, forest tint; adds the
`Vegetation` and `Grass` nodes if the scene lacks them):

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/rebuild_vegetation.gd -- --scene=res://scenes/world/test_2km.tscn --veg-extent=0
```

### Measurements (fast workflow, routine use)

One process per map, fixed FPS, RTS and strategic camera stations, and layer scenarios. Runs
abort automatically on render errors or memory pressure. Results go to
`benchmarks/raw/bench_<tag>.json`.

```bash
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file bench.log --script res://tools/bench_world.gd -- --scene=res://scenes/world/test_2km.tscn --tag=my_run
```

Use the GUI executable with `--log-file`. The console wrapper throttles the process when
there is heavy error output. Add `--rendering-driver d3d12` to compare backends.
`tools/measure_run.ps1` wraps a run and records peak RAM and GPU memory from Windows counters.

Synthetic stress-test maps (mirror-tiled from the 2 km world, **not** representative
terrain):

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/tile_world.gd -- --name=tile_8km --regions=8 --veg=trees
```

Optional longer regression benchmark (camera routes) and the scripted FPS controller test:

```bash
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 res://scenes/world/test_2km.tscn -- --benchmark
```

```bash
Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/world/test_2km.tscn -- --fps-test
```

Also `--screenshots` (writes `docs/screenshots/`) and `--quit-after-load`.

WORLD-CORE-01 scripted checks (spawn, orders during FPS, Tab switching, click/box selection,
right-click orders, 12 perspective switches, arrival, suspended orders, the bodiless unit tier,
frame times; about 90 s, writes `benchmarks/raw/core_test.json` and `docs/screenshots/core01_*.png`):

```bash
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file core.log res://scenes/game/core_demo.tscn -- --core-test --shots
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file wc02.log res://scenes/game/world_core_02.tscn -- --large-test --shots   # WORLD-CORE-02, real 20 km world; keys 1/2/3 sites, N next soldier
```

Targeted vegetation checks (mask, tree clearance, determinism, streamer activation,
camera jumps and FPS/RTS switching, grass altitude cutoff, colliders; about 20 s):

```bash
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file vegtest.log --script res://tools/test_vegetation.gd -- --scene=res://scenes/world/test_2km.tscn --shots
```

`benchmarks/wt02_suite/run_wt02.sh <out_dir>` runs the whole WORLD-TECH-02 validation.

## Reference world (WORLD-TERRAIN-01)

`worlds/ref_20km` is a 20 × 20 km northern-European world built from the geographic
reference map (`docs/terrain01/reference_map_03.png`) with Nordic trees, rocks, buildings
and road furniture from the project's Blender pipeline. See
[docs/WORLD-TERRAIN-01_REPORT.md](docs/WORLD-TERRAIN-01_REPORT.md).

It is the **canonical development world**: the default for development, integration and tests,
not a finished or locked map. Generated data (~2.4 GB, 540 files) is not committed; the committed
manifest `worlds/ref_20km.manifest.json` records every file's SHA-256 and role (source / generated /
analysis / preview / editor metadata / config). Check a copy with

```bash
python tools/terrain_ref/world_manifest.py verify --ignore-editor-metadata
```

and re-create the manifest (`create --note "..."`) after an intended world change. The consolidated
copy is backed up in `../fractured-nations-backups/2026-10-22_PROJECT-CONSOLIDATION-01/`; restore from
there rather than rebuilding, because a rebuild is not bit-identical to the edited data. To build a
world from scratch (about 14 minutes; `--assets` also regenerates the Blender assets, whose outputs
are committed):

```bash
bash tools/terrain_ref/build_ref_world.sh
```

`--shots` adds the top-down mosaic and the FPS/RTS screenshots. Then run
`scenes/game/world_ref_20km.tscn` (the WORLD-CORE-02 FPS/RTS game on the new world) or
open `scenes/world/ref_20km.tscn` in the editor. The geography is edited in
`tools/terrain_ref/layout_ref03.json` (river, lakes, zones, settlements, plateaus, road
waypoints, seed); `tools/terrain_ref/generate.py` turns it into heightmap, control,
colour, vegetation and road data that `ReferenceWorldBuilder` imports.

### Settlements (WORLD-SETTLEMENT-02)

The generated towns and villages (round discs, street grids, random houses) are replaced by a
**settlement layer** in `worlds/settlements/` (tracked): local roads that follow the terrain, 771
buildings in clusters and farms, ground paint and the old streets' cut/fill smoothed out. It is on by
default in the game and in `tools/terrain_ref/capture.gd`; `-- --no-settlements` shows the old world.
The canonical world files are untouched (it is applied in memory at game start, ~1.5 s). Rebuild it with

```bash
BPY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
"$BPY" tools/settlement_proto/design_settlements.py && "$BPY" tools/settlement_proto/paint_settlements.py
../Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/settlement_proto/build_overrides.gd
```

Report: [docs/WORLD-SETTLEMENT-02_REPORT.md](docs/WORLD-SETTLEMENT-02_REPORT.md).

## Asset library (ASSET-PRODUCTION-01)

Military bases, faction infantry and environment assets, all generated by Blender scripts
and validated in Godot. Details: `docs/ASSET-PRODUCTION-01_REPORT.md`, rules for new assets:
`docs/ASSET_STANDARD.md` (static) and `docs/CHARACTER_STANDARD.md` (infantry).

BLENDER-SKILLS-01 added a Blender-side QA gate (`build_assets.py -- --qa`, built on the
[blender-skills](https://github.com/EL4CTEO/blender-skills) agent skills installed in
`.claude/skills/`) that checks inward normals, z-fighting, detached parts and budgets before
the Godot validator; the library's known findings are in `benchmarks/asset01/qa_baseline.json`.
See `docs/BLENDER-SKILLS-01_REPORT.md`.

* `assets/military/` – 9 base buildings, 24 expansion modules, 51 props, 8 road assets,
  2 vehicle prototypes; 51 shared materials (`materials/`), tileable textures and the sign
  atlas (`textures/`), StructureDef data (`defs/`), `catalog.json`.
* `assets/characters/infantry/factions/` + `loadouts/{NATO,RU,CN}_rifleman.tres` – three
  faction infantry families on the shared CHARACTER-01 rig.
* Build: `blender -b --factory-startup --python tools/blender/asset_production/build_assets.py -- --export`
  (faction infantry: `.../asset_production/characters/build_factions.py`).
* Check in Godot: `benchmarks/asset01/run_lab.sh --validate | --shots | --lod | --factions | --showcase`.

## Repository layout

```
addons/          third-party editor plugins (Terrain3D, Road Generator, Godot AI)
assets/          textures, placeholder vegetation, rock models
scenes/          world and player scenes
scripts/world/   WorldConfig, terrain generator, WorldBuilder, collider streaming
scripts/vegetation/  VegetationChunk data, VegetationStreamer, GrassLayer, exclusion mask
shaders/vegetation/  GPU grass placement and blade shaders
shaders/environment/ foliage, bark, rock and grass-tuft shaders (WORLD-TERRAIN-01 assets)
shaders/world/       river and lake water
tools/terrain_ref/   reference-world generator (Python), build/capture/analysis tools
tools/blender/env/   Blender generators for the Nordic environment assets
assets/environment/  environment GLBs, .blend sources, textures, LOD scenes, vegetation library
scripts/player/  FPS controller
scripts/core/    UnitState, WorldState, WorldSim (authoritative simulation), GameController (possession)
scripts/units/   SoldierBody, VehicleBody, faction visuals
scripts/rts/     tactical camera and selection/orders
scripts/game/    CoreDemo: the playable scene wiring and spawning
scripts/ui/      HUD; scripts/ui/kit/ the UI kit (tokens, theme, icons, components)
assets/ui/fonts/ Barlow / Barlow Condensed (SIL OFL)
scripts/debug/   diagnostics overlay, benchmark, FPS self-test, WORLD-CORE-01 self-test
tools/           build, tiling, benchmark and editor-probe tools; tools/blender/ asset generators
assets/units/    soldier and vehicle glTF models (+ blender/ sources, ignored by Godot)
assets/military/ ASSET-PRODUCTION-01 library (buildings, modules, props, roads, vehicles)
tools/blender/asset_production/  static asset + faction infantry generators
tools/asset_lab/ Godot asset lab (validation, screenshots, performance) and the GLB import script
worlds/<name>/   per-world config, Terrain3D assets/material, region data, vegetation chunks
benchmarks/      committed benchmark evidence (raw/ is git-ignored)
docs/            reports and screenshots
```

## Third-party asset licenses

- Terrain3D, Godot Road Generator: MIT (see each addon's LICENSE).
- Ground and rock textures and the rock models come from the Terrain3D demo. They are
  ambientCG CC0 (`assets/terrain/textures/asset_licenses.txt`).
- Trees, bushes, the grass card and the dirt texture are procedurally generated
  placeholders (`tools/make_vegetation_assets.gd`).
- The soldier and transport vehicle models are generated in Blender by the project's own
  scripts (`tools/blender/`), no third-party content.
- The GPU grass shaders derive from Terrain3D's `extras/particle_example` (MIT).
- UI fonts Barlow and Barlow Condensed (The Barlow Project Authors): SIL Open Font License 1.1
  (`assets/ui/fonts/OFL.txt`). The UI icons are the project's own SVG (`scripts/ui/kit/fn_icons.gd`).
- WORLD-TERRAIN-01 environment assets (trees, shrubs, rocks, deadwood, bridges, buildings,
  road furniture) and their bark/foliage/ground textures are generated by the project's own
  scripts (`tools/blender/env/`, `tools/terrain_ref/make_terrain_textures.py`); photographic
  references were only viewed (`docs/terrain01/REFERENCES.md`), nothing was copied.

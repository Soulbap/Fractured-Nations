# COMBAT-TECH-01 — Combat systems research, reuse and integration assessment

Branch `feature/combat-tech-01`, based on `feature/unit-01a` (d43c954). This is research
only: no gameplay code was changed and no combat was implemented. What was added:
- a read-only probe tool (`tools/combat_probe.gd`);
- the isolated lab experiment (`docs/combat_tech01/lab/`);
- raw results (`docs/combat_tech01/raw/`);
- this report.

Third-party code was cloned into a scratch folder outside every worktree. It is **not**
committed; section 11 pins the exact commits.

Everything marked *verified* was run on Godot 4.7.2-stable (official) with Jolt Physics on
this machine: RTX 3070, Vulkan.

---

## 1. Executive summary

**Little of the existing Godot combat code fits our architecture. The patterns do, and
Godot itself already provides the hard parts.** All the FPS weapon projects I inspected
assume one player:
- they aim from the active camera or the screen centre;
- they keep ammo in a shared Resource or a global autoload;
- they find their parts by unique node names in a player scene;
- they read `Input` directly.

None of them can be driven by AI without rewriting the core. The AI frameworks are solid
but larger than COMBAT-01 needs.

**Two measured facts about our own world decide the architecture:**
1. **Bodies exist only near the observer; rifle fights happen further out.** Soldiers get
   physics bodies, and therefore hurtboxes, only within 120 m of the observer (released at
   150 m). Rifle fights happen at 100–300 m. A player firing at an enemy 250 m away is
   firing at a unit with no body. *Physics hurtboxes cannot be the authoritative way to hit
   soldiers.*
2. **Physics only knows the world near the camera.** Terrain collision exists within
   ~200 m of the camera and tree colliders within 40 m of the observer. Measured on
   `ref_20km`:
   - physics rays pass through hills beyond the collision radius (up to 4 of 32 lines at
     800 m);
   - they pass through trees beyond 40 m (2–9 of 32 lines per ring from 100 to 800 m, in
     forest and on open ground).

   *Line of sight and shot occlusion must come from world data* (heightmap, vegetation
   chunks, structure records) wherever physics is not loaded.

**The recommendation follows from these:**
- **One `CombatSim` owned by `WorldSim`.** It resolves every shot (player, AI, near or far)
  against **records**:
  - soldiers: analytic capsule + head tests from `UnitState`, using Godot's `Geometry3D`;
  - world occlusion: the physics ray where it is valid, world data elsewhere.
- **Measured agreement.** The analytic soldier test matched Jolt hurtboxes on **2,999 of
  3,000** random shots, at about 30 µs for 40 soldiers in GDScript. It needs no node, so it
  works in both simulation tiers and through every transition.
- **Same path for player and AI.** A possessed soldier calls the same
  `request_fire(unit, origin, direction)` as AI.
- **Configuration and state.** Weapons are **static Resources** (`WeaponDef`). All mutable
  combat state (magazine, reserve, cooldown, health, alive) lives in **`UnitState`**.
- **What we reuse:**
  - Godot built-ins for physics, geometry, audio, particles and decals;
  - concrete patterns from the inspected projects: Jeh3no's weapon resource fields,
    bukkbeek's fire / cooldown / reload flow, cluttered-code's hit-zone multipliers and
    damage signals, Open RTS's target polling, chafmere's spray profile.
- **What we don't adopt for COMBAT-01:** no external addon is required. Beehave (pure
  GDScript, MIT, loads on 4.7.2) is the fallback if the soldier state machine outgrows
  ~6 states. LimboAI waits for a decision because it ships a native binary.
- **COMBAT-01 is split into four milestones (section 10):**
  1. **01a** combat core plus FPS rifle;
  2. **01b** perception and autonomous engagement;
  3. **01c** the same combat running cheaply for units without bodies;
  4. **01d** the two-squad firefight with RTS feedback.

  The custom code is small adapters around `WorldState`: about 900–1,400 lines of GDScript
  in total.

---

## 2. Projects and repositories investigated

Source was cloned and read at the commits in section 11. Star, issue and release counts are
from the GitHub API on 2026-10-20.

| Project | Area | What it is | Stars / open issues / last push / release |
|---|---|---|---|
| [Jeh3no/Godot-simple-FPS-weapon-system](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system) | FPS weapons | Resource-driven weapon addon (hitscan/projectile, ammo types, reload parts, recoil, sway) plus its player character | 114 / 2 / 2026-06-22 / none |
| [bukkbeek/GodotFPS-Template](https://github.com/bukkbeek/GodotFPS-Template) | FPS template | Weapons, ammo autoload, zombie enemies with nav and bone damage, HUD, VFX | 65 / 0 / 2026-03-31 / none |
| [chafmere/Godot4-FPS-Template](https://github.com/chafmere/Godot4-FPS-Template) | FPS template | Weapon state machine, projectile class, spray profiles, pickups | 118 / 4 / 2026-02-01 / v2.0.3 |
| [lampe-games/godot-open-rts](https://github.com/lampe-games/godot-open-rts) | RTS combat | Complete small RTS: units, actions (auto-attack, attack in range), projectiles | 1127 / 24 / 2025-01-07 / 0.9.0 |
| [limbonaut/limboai](https://github.com/limbonaut/limboai) | AI | C++ behaviour trees + hierarchical state machines, editor, debugger | 3059 / 62 / 2026-10-04 / v1.8.1 |
| [bitbrain/beehave](https://github.com/bitbrain/beehave) | AI | Pure-GDScript behaviour trees with debugger | 3305 / 28 / 2026-09-20 / v2.9.3 |
| [cluttered-code/godot-health-hitbox-hurtbox](https://github.com/cluttered-code/godot-health-hitbox-hurtbox) | Damage | Health, HurtBox, HitBox, HitScan components (2D and 3D), modifiers, gdUnit4 tests | 173 / 0 / 2026-07-22 / v5.0.4 |
| [Tattomoosa/VisionCone3D](https://github.com/Tattomoosa/VisionCone3D) | Perception | `Area3D` cone with budgeted ray probes, `body_sighted` / `body_hidden` | 69 / 7 / 2025-04-17 / 0.3.0 |
| [toledosq/godot_weapon_manager](https://github.com/toledosq/godot_weapon_manager) | FPS weapons | Weapon manager with curve recoil, inventory, attachments (author: on the back burner) | 12 / 3 / 2024-02-06 / none |
| [indieAYUSH/Simple-and-Modular-weapon-system-for-godot-4.x](https://github.com/indieAYUSH/Simple-and-Modular-weapon-system-for-godot-4.x) | FPS template | Player states, weapons, inventory (153 MB with assets) | 5 / 0 / 2026-07-11 / none |
| [quiver-dev/top-down-shooter-core](https://github.com/quiver-dev/top-down-shooter-core) | Patterns (2D) | Small component split: `Magazine` resource, `DistanceWeapon`, `Behavior` input | 27 / 1 / 2023-03-09 / none |

**Searched but not inspected:**
- *Ultimate Tactical AI for Godot 4.x* (itch.io, GOAP with squads, suppression and cover):
  paid, licence not stated publicly, source not available to read.
- *godot-tactical-study* (esyfxy): cover and perception, but it includes assets from a
  commercial game.
- *Enemy Perception* (paid).
- *Generic Squad Tactics* (turn-based, AI-generated demo).
- *operation-steel-tide* (licence and AI not verified).

None of these is usable as a dependency without more licence clarity, and none was needed
for the recommendation.

**Godot built-ins, documentation-level, used in the experiments:**
- `PhysicsDirectSpaceState3D.intersect_ray` / `PhysicsRayQueryParameters3D` (masks,
  `exclude`, `hit_from_inside`, `collide_with_areas`);
- `RayCast3D`, `Area3D`;
- `Geometry3D.segment_intersects_sphere`, `segment_intersects_cylinder`;
- `NavigationAgent3D` (already used);
- `RandomNumberGenerator` (seeded);
- `AudioStreamPlayer3D`, `GPUParticles3D`, `Decal`;
- Terrain3D's `Terrain3DData.get_height` (already used).

---

## 3. Source-code findings

Each finding is labelled **Verified** (run here), **Read** (from source), **Claimed**
(README or store) or **Assumed**.

### 3.1 Jeh3no — Simple FPS Weapon System (a7bd56c)

**Files:** `addons/JehenoSimpleFPSWeaponSystem/Weapons/Scripts/`:
- `weapon_resources_script.gd` (`WeaponResource`, 115 lines);
- `shoot_managers_script.gd` (157);
- `weapon_manager_script.gd` (169);
- `reload_manager_script.gd` (108);
- `Ammunition/ammunition_manager_script.gd` (23).

**What it has (Read):**
- hitscan and projectile;
- burst count (`nb_proj_shots`) and pellets (`nb_proj_shots_at_same_time`);
- min / max spread;
- `damage_dropoff` curve and a headshot multiplier;
- part-wise reload (`nb_parts_needed`);
- recoil and sway values;
- muzzle flash scene;
- five example weapons.

**What blocks reuse:**
- **Aim (Read):** it aims from the screen centre of `%Camera` (`get_camera_fov()`), so
  there is no aim input an AI could drive.
- **Shared runtime state (Read):** `total_ammo_in_mag`, `is_shooting` and `is_reloading`
  are fields of the *Resource*. Every soldier using the same `.tres` would share one
  magazine unless each instance duplicates the resource.
- **Node dependencies (Read):** `WeaponManager` needs `%HUD`, `%Camera`,
  `%CameraRecoilHolder`, `%ViewportCam`, `%AnimationPlayer`, `%AnimationManager`,
  `%LinkComponent`, `%InputManagementComponent` and more. That is the whole player scene.
- **Ammo reserve (Read):** one per player (`ammo_dict` on a node).
- **Damage interface (Read):** by group (`"Enemies"`, `"EnemiesHead"`, `"HitableObjects"`)
  plus a duck-typed `hitscan_hit()`.
- **Raycast (Read):** no mask or `exclude`, so the ray can hit the shooter. Damage is
  truncated to int.
- **Timing (Read):** fire timing uses `await get_tree().create_timer(...)`, not
  deterministic.
- **Bug (Read):** in the `all_ammo_in_mag` branch, `weapon_manager.ammo_manager.amm_dict`
  is a typo, a runtime error on that path.
- **Assets (Claimed):** the sounds and sprites in the showcase video are proprietary and
  not included.

**Value:** the most complete *list of fields* a rifle needs. A reference for `WeaponDef`.

### 3.2 bukkbeek — GodotFPS-Template (1161979)

**Files:**
- `common/weapon/weapon.gd` (291);
- `common/autoloads/bullets.gd`, `global.gd`;
- `common/enemy/enemy.gd` (229), `enemy_bone_damage.gd`.

**What it has (Read):** the most decoupled weapon. `initialize(camera, raycast,
raycast_origin)` takes the ray from outside. `try_fire()` covers cooldown, magazine,
automatic reload, spread by rotating the ray origin, decal, muzzle VFX and
`collider.get_damage(damage, direction)`.

**Verified:** fired **from code with no player**, through a `RayCast3D` on a pivot we
own: 11 shots and 11 hits on a target at 20 m.

**What blocks reuse:**
- **Shared reserve (Verified):** the reserve came out of the global `Bullets` autoload
  (480 → 471). Every weapon in the game draws from one inventory.
- **Autoloads and nodes (Read):** it needs `Global` signals (`aim_mode_changed`,
  `camera_shake`, `bullets_changed`) and fixed child nodes (`CooldownTimer`,
  `ReloadTimer`, aim markers, `TestCamera`, `TestTarget`).
- **Enemies (Read):** melee zombies. "Vision" is distance only, with no line of sight, and
  they chase the single global player.
- **Assets (Read):** model, animation and audio licences are mixed. Sounds are from
  Pixabay and animations from Mesh2Motion; use is allowed, resale is not.

**Value:** the `try_fire → consume → fire → cooldown / reload` flow is a good template.
`PhysicalBoneSimulator3D` per-bone damage is a later option for ragdolls.

### 3.3 chafmere — Godot4-FPS-Template (7130929)

**Files:** `Player_Controller/scripts/`:
- `Weapon_State_Machine/Weapon_State_Machine.gd` (263), `weapon_resource.gd`;
- `Projectiles/Projectile.gd` (137);
- `Spawnable_Objects/SprayProfiles/spray_profile.gd`.

**What blocks reuse (Read):**
- the projectile aims from `get_viewport().get_camera_3d()`, the *active* camera, so an
  AI soldier would fire along the player's view;
- `_input` / `Input` are read inside the weapon state machine;
- damage is by `"Target"` group plus `Hit_Successful()`;
- the hard-coded collision mask is `0b11101101`.

**Value:**
- `Spray_Profile`: noise plus a `Path2D` recoil pattern, a good later recoil model.
- An explicit Jolt note: `set_hit_from_inside(false)  # In Jolt this is set to true by
  default`. **Verified on 4.7.2:** the default is `false` for both `RayCast3D` and
  `PhysicsRayQueryParameters3D`. The comment is outdated, but the setting matters (§3.6).

### 3.4 Open RTS (a628ad3)

**Files:** `source/match/units/actions/`:
- `WaitingForTargets.gd` (polls every 10 frames, picks the closest enemy in
  `sight_range`);
- `AutoAttacking.gd` (follow until in range, then attack);
- `AttackingWhileInRange.gd` (`attack_interval`, spawns a projectile).

Also `units/Unit.gd` (`hp`, `attack_damage`, `attack_range`, `attack_domains`).

**What it does (Read):**
- no line of sight (sight is a flat distance);
- projectiles are guided to the target and always hit;
- state lives on nodes;
- timers drive the cadence.

**Value:**
- the action structure, *waiting → pursuing → attacking in range*, maps directly onto our
  order layer;
- low-frequency target polling and closest-target choice;
- the "next attack availability" timestamp pattern, which matches our sim-time approach.

Code: reference only. Last push January 2025.

### 3.5 cluttered-code — Health, HitBoxes, HurtBoxes and HitScans (c9d2185, v5.0.4)

**Files:** `addons/health_hitbox_hurtbox/`:
- `health/health.gd` (`Health`, 255);
- `3d/hurt_box_3d/hurt_box_3d.gd` (`HurtBox3D extends Area3D`);
- `3d/hit_scan_3d/hit_scan_3d.gd` (`HitScan3D extends RayCast3D`);
- `resources/health_modifier.gd`, `health_action.gd`.

There are 20 gdUnit4 test files in `test/`.

**Verified on 4.7.2 / Jolt:**
- the HitScan3D → HurtBox3D → Health chain applies damage (25 → 75 HP);
- a head HurtBox with a ×2 `HealthModifier` doubles it (50);
- `died` fires exactly once at 0.

**What blocks reuse for soldiers (Read):**
- `Health` is a Node that owns `current`. Ours is `UnitState.health`, and bodies are freed
  when a soldier goes abstract, so the component would be a second, short-lived authority.
- Health is an `int`; ours is a float.
- HurtBoxes are `Area3D`s on bodies, which don't exist beyond 120–150 m (§1).

**Value:** the per-zone multiplier model and the signal set (`damaged`, `died`,
`first_hit`) are the right design. The addon can be used *as is* for non-soldier
destructibles later (props, barrels). It is MIT and actively maintained.

### 3.6 Physics and ray pitfalls (Verified, lab experiment 1)

| Case | Result |
|---|---|
| Shot mask = hurtboxes only, wall in between | **Passes through the wall** (hits `HurtBody`) |
| Mask = world + hurtboxes | Wall stops it |
| Mask includes the soldier capsule layer, hurtbox same size as capsule | **Capsule wins, no damage** |
| Shooter's own hurtbox around the muzzle, `hit_from_inside = true` | Hits itself; `false` (default) does not |
| Jolt ray cost, simple scene | 0.74 µs per line-of-sight ray (64 soldiers, 2,016 pairs in 1.5 ms); 1.7 µs per shot ray including areas |
| Jolt ray cost, real `ref_20km` terrain and forest | 2.9–7.7 µs per ray |

### 3.7 AI frameworks

- **LimboAI (df8933d, v1.8.1).** C++ behaviour trees plus hierarchical state machines,
  with an editor, debugger and GDScript tasks. `gdextension/limboai.gdextension` declares
  `compatibility_minimum = "4.2"`, and the README table says 1.8.x targets Godot 4.6+ as a
  GDExtension (4.7 as a module).
  - **Claimed.** Not run here: the repository has source only, and testing needs a
    prebuilt native DLL from a release. I did not load third-party native code without your
    approval (§12).
  - MIT, very active, 62 open issues.
- **Beehave (fe58915, 2.9.4-dev; release v2.9.3).** Pure GDScript, 45 scripts (~4,200
  lines). **Verified:** `beehave_tree.gd`, `selector.gd` and `action.gd` load and
  instantiate on 4.7.2. MIT, active.
- **Our need for COMBAT-01** is about 5 states: idle / moving (order), engage, reload,
  dead. A plain state enum in the combat brain is smaller than either framework and
  debuggable in the existing HUD. A framework pays off once suppression, cover and
  flanking arrive (COMBAT-02+).

### 3.8 Perception

- **VisionCone3D (944b83d, 0.3.0).** An `Area3D` cone plus random-point ray probes with a
  per-frame budget (`vision_test_shape_max_probe_count`). **Verified:** it loads on 4.7.2.
  - It sees only `PhysicsBody3D`s inside the cone, so it does not work for abstract units.
  - A per-soldier cone at rifle ranges (300 m) overlaps many colliders.
  - Reference: the budgeted multi-point probe idea.
- **Godot has no perception system.** Perception is distance plus field-of-view maths plus
  a line-of-sight query, and must run on records (§1).

### 3.9 Our world (Verified, `tools/combat_probe.gd`, raw results in `docs/combat_tech01/raw/`)

32 directions per ring, eye height 1.6 m, the game's physics setup.

| Range (m) | Site A (open plateau): physics blocked / heightmap blocked / trees on line / *trees missed by physics* | Forest clearing: same columns |
|---|---|---|
| 50 | 0 / 0 / 0 / 0 | 11 / 0 / 11 / 0 |
| 100 | 0 / 0 / 0 / 0 | 11 / 0 / 13 / **2** |
| 200 | 0 / 0 / 0 / 0 | 11 / 0 / 17 / **6** |
| 300 | 0 / 0 / 1 / **1** | 15 / 8 / 19 / **5** |
| 400 | 4 / 4 / 1 / **1** | 15 / 11 / 19 / **4** |
| 600 | 15 / 15 / 16 / **5** | 20 / 20 / 22 / **3** |
| 800 | 18 / 22 / 27 / **9** (+4 hills missed) | 23 / 24 / 23 / **1** (+1 hill missed) |

**Cost per line, in GDScript:**
- physics ray: 2.9–7.7 µs;
- heightmap march every 2 m: 72–79 µs;
- trunk test reading vegetation cells: 147–558 µs. This is unoptimised and re-reads the
  cells each time; a cached per-cell trunk grid makes it about 10× cheaper (§9.3).

**Conclusions:**
- Within ~200 m, the physics ray and the heightmap agree 100% for terrain.
- Beyond the collision radius, physics misses hills.
- Beyond 40 m, physics misses trees everywhere.

---

## 4. Candidate comparison matrix

| Criterion | Jeh3no weapon system | bukkbeek template | chafmere template | cluttered-code health/hurtbox | Open RTS | LimboAI | Beehave | VisionCone3D |
|---|---|---|---|---|---|---|---|---|
| Version | a7bd56c (no release) | 1161979 | 7130929 / v2.0.3 | c9d2185 / v5.0.4 | a628ad3 / 0.9.0 | df8933d / v1.8.1 | fe58915 / v2.9.3 | 944b83d / 0.3.0 |
| Godot 4.7.2 | Claimed 4.4–4.7 (AssetLib), not run | **Verified** (weapon.gd from code) | Project 4.6, not run | **Verified** | Project 4.3, not run | Claimed 4.6+, not run (native) | **Verified** (scripts load) | **Verified** (loads) |
| Features | Full rifle feature list | Weapon flow, zombies, VFX | Spray profiles, projectile | Health, zones, signals, tests | RTS target / attack loop | BT + HSM, editor, debugger | BT, debugger | Cone + budgeted probes |
| Dependencies | Its player scene (%nodes) | 2 autoloads, child nodes | Player, active camera | none (gdUnit4 only for tests) | Whole game | Native GDExtension | none | none |
| Integration effort | High (rewrite core) | Medium (strip autoloads) | High | Low for props / **high for soldiers** | High | Medium | Low–medium | Medium |
| Fit with WorldState and FPS/RTS | Poor: camera aim, state in Resource | Poor: global ammo, global player | Poor: active-camera aim | Partial: second health authority, body-only | Poor: node state, no line of sight | Neutral (AI only) | Neutral (AI only) | Poor: body-only |
| Maintenance | Active (Jun 2026) | Mar 2026 | Feb 2026 | Active (Jul 2026), 0 issues | Stale (Jan 2025) | Very active | Active | Apr 2025 |
| Licence | MIT; showcase audio proprietary (not included) | MIT; Pixabay / Mesh2Motion assets, no resale | MIT | MIT | MIT | MIT | MIT | MIT |
| Pitfalls | Shared mag in `.tres`, `amm_dict` typo, `await` timing, self-hit | Shared reserve (verified), signals coupling | Fires from the player view for AI | Wall pass-through / capsule masking (verified), int HP | Guided always-hit shots | Native binary per platform and engine | Extra tick and memory per agent | 300 m cones, no abstract tier |
| **Recommendation** | **Reference** (`WeaponDef` fields) | **Reference** (fire flow) | **Reference** (spray later) | **Reference** for soldiers; **reuse as is** later for props | **Reference** (target loop) | **Defer** (decision §12) | **Fallback** for COMBAT-02+ | **Reject** (pattern only) |

**Also rejected:**
- **toledosq/godot_weapon_manager:** stale, `EventBus` and inventory coupling.
- **indieAYUSH:** player-centric, 153 MB of assets, weapon code tied to its player.
- **Quiver top-down core:** 2D, stale. Its `Magazine` / `Behavior` split is a useful idea
  only.

---

## 5. Verified compatibility and test results

| Experiment | Result |
|---|---|
| Lab 1: HitScan3D → HurtBox3D → Health on 4.7.2 / Jolt | Works: body 25, head ×2 = 50, `died` once. Pitfalls: mask without world passes through walls; unit-capsule layer in the mask blocks hurtboxes; self-hits with `hit_from_inside` |
| Lab 2: bukkbeek `weapon.gd` fired from code | 11/11 hits at 20 m with our own ray; the global reserve drops (480 → 471) |
| Lab 3: Jolt ray cost | 0.74 µs line-of-sight ray, 1.7 µs shot ray (simple scene) |
| Lab 4: third-party scripts on 4.7.2 | Beehave (tree, selector, action), VisionCone3D and Health load and instantiate |
| **Lab 5: record-based shots vs Jolt hurtboxes** | **2,999 / 3,000** identical results (same soldier, same zone; one grazing edge); 30 µs per shot for 40 soldiers in brute-force GDScript |
| Probe: `ref_20km` site A and forest | Table §3.9: hills missed beyond ~200 m, trees missed beyond 40 m; costs as listed |

Not verified: Jeh3no and chafmere at runtime (blocked by their player dependencies, as read
in source) and LimboAI (native binary, §12).

**Reproduce:**
- Lab: `docs/combat_tech01/lab/` (project file and `tests/lab.gd`). Clone the pinned addons
  into `addons/` as listed in §11, then run
  `Godot_console --headless --path <lab> --script res://tests/lab.gd`.
- Probe: `Godot --path . --script res://tools/combat_probe.gd -- [--at=x,z]` (needs the
  built world).

---

## 6. Recommended components to reuse

**Godot built-ins (no dependency):**
- `PhysicsRayQueryParameters3D` + `intersect_ray`: world occlusion inside loaded physics,
  with an explicit `collision_mask = world`, `exclude = [shooter]` and
  `hit_from_inside = false`.
- `Geometry3D.segment_intersects_cylinder` / `segment_intersects_sphere`: soldier hit test
  on records. Mind that the cylinder runs along Z.
- `RandomNumberGenerator` with explicit seeds: spread and abstract outcomes, reproducible.
- `AudioStreamPlayer3D`, `GPUParticles3D` (muzzle flash, impacts), `Decal` (bullet
  holes), `MeshInstance3D` (tracers).
- Terrain3D `Terrain3DData.get_height` and our `VegetationStreamer.get_cell_instances` /
  `StructureManager` records: line of sight and occlusion beyond physics.
- The existing `NavigationAgent3D` and squad orders: movement while engaging.

**Patterns adapted (small code of our own):**

| Source | What we take |
|---|---|
| Jeh3no `WeaponResource` | Field set for `WeaponDef`: fire mode, interval, magazine, reserve, reload time, min / max spread, damage, damage drop-off `Curve`, headshot multiplier, range, muzzle-flash scene, sounds. **Without** runtime fields |
| bukkbeek `weapon.gd` | Control flow `try_fire()`: busy / reloading → empty → auto-reload → consume → resolve → cooldown, as sim-time timestamps instead of `Timer` nodes |
| cluttered-code | Zone multipliers (head ×2, body ×1) and the damage event set (`damaged`, `died`, first hit) as `WorldState` signals |
| Open RTS | Target polling at low frequency, closest or sticky target, "next shot available at" timestamp |
| chafmere `Spray_Profile` | Later: recoil pattern for FPS feel |

**Optional, later:**
- **Beehave:** if the soldier brain grows beyond a small state enum.
- **cluttered-code addon as is:** for destructible props.
- **LimboAI:** if approved and if behaviour trees with an editor become worth a native
  dependency.

---

## 7. Rejected alternatives and reasons

| Alternative | Reason |
|---|---|
| Adopt a complete FPS weapon framework (Jeh3no / bukkbeek / chafmere) | Player-camera aim, global or Resource-held ammo, player-scene node dependencies, direct `Input`. Making them AI-drivable means rewriting the cores, which is more code than writing the core against `WorldState` |
| Physics hurtboxes as the authoritative soldier hit test | Bodies only exist within 120–150 m; fights happen at 100–300 m. A hurtbox design would need every engaged enemy promoted to a body, or two hit systems |
| cluttered-code `Health` node as soldier health | A second authority next to `UnitState.health`, lost when the body is freed |
| Open RTS combat code | No line of sight, always-hit guided projectiles, node-held state, stale |
| VisionCone3D as soldier perception | Body-only, large cones at rifle ranges |
| LimboAI now | Native binary not testable without your approval; COMBAT-01's state count does not need it |
| Ultimate Tactical AI (itch) | Paid, licence not public, source not inspectable |
| godot-tactical-study | Contains assets from a commercial game |
| Physics-only line of sight / occlusion | Misses hills beyond ~200 m and trees beyond 40 m (§3.9) |
| Bullet projectiles (RigidBody) for rifles | Not needed at COMBAT-01 ranges; costs bodies and can't run in the abstract tier. Hitscan with drop-off covers it; ballistics later if wanted |

---

## 8. Known pitfalls and integration risks

1. **Shot mask.** The mask must contain world geometry. Our unit capsules (and any
   hurtboxes) must not block the record test. The shooter must be excluded. Use
   `hit_from_inside = false`.
2. **Physics coverage is camera-local:** terrain within ~200 m, trees within 40 m,
   structures within 260 m. Authoritative occlusion must use world data, or a hybrid with
   identical results (§9.3). Otherwise the same shot gives different results depending on
   where the camera is, which breaks determinism and fairness.
3. **Detail radius vs engagement range (120 / 150 m vs 100–300 m).** The record-based hit
   test removes the hit problem. *Visuals* of far enemies are proxies (capsules), so the
   firefight may need a larger detail radius for looks. That is a decision (§12), not a
   blocker.
4. **No runtime state in Resources.** A shared `.tres` would share magazines (Jeh3no). All
   mutable state goes on `UnitState`.
5. **No `await` / `Timer` gameplay timing.** Use sim-time timestamps (`WorldState.time`).
   These survive tier changes, possession and save/load; timers on freed bodies do not.
6. **Duplicate damage across tier transitions.** Shots are events resolved once, by
   `CombatSim`, against records. Bodies never apply damage themselves, so a promotion or
   demotion mid-burst can't double-apply.
7. **Cost of data-based line of sight in GDScript** (72–558 µs per line, unoptimised). It
   needs a cached trunk grid, adaptive heightmap steps and a per-frame budget. Measure in
   COMBAT-01a.
8. **Possession.** Player and AI must not both fire for the same unit. The brain skips
   `player_controlled` units, exactly like movement does now.
9. **Jolt version notes.** Some Godot 4 docs and repositories still claim Jolt's
   `hit_from_inside` defaults to true. On 4.7.2 it is false; set it explicitly anyway.
10. **Assets.** None of the inspected projects' audio is reusable without care
    (proprietary, or Pixabay with no-resale terms). See §12.

---

## 9. Proposed combat architecture

### 9.1 Ownership

```
WorldState (authority)
  UnitState      + alive, health (exists), weapon_id, mag, reserve,
                   next_shot_at, reload_until, shot_counter,
                   target_id, last_seen{pos,time}, fire_mode (squad rule)
  SquadState     + rules_of_engagement (weapons free / hold fire)
  WeaponDef .tres  static only (rifle stats, curves, FX scenes, sounds)

WorldSim
  SquadControl   (UNIT-01A) movement orders
  CombatSim      NEW: request_fire(), resolve_shot(), apply_damage(), death
  CombatBrain    NEW: perception + engage/reload state per unit, low rate, budgeted

Presentation (no authority)
  SoldierBody    FPS input -> CombatSim.request_fire; muzzle point, animation
  CombatFX       listens to WorldState.shot_fired / unit_damaged / unit_died:
                 muzzle flash, tracer, impact, decal, AudioStreamPlayer3D (only near camera)
  HUD / RTS      ammo, health, squad "in contact / casualties"
```

### 9.2 One shot fired by the player (possessed soldier)

1. `SoldierBody` (possessed): LMB pressed, mouse held for automatic fire.
   `CombatSim.request_fire(unit_id, origin = camera eye, dir = camera forward)`.
2. `CombatSim` checks `UnitState` and `WeaponDef`:
   - alive?
   - `time >= next_shot_at`?
   - `mag > 0`? Otherwise start a reload, unless one is running.
   - It consumes 1 round, sets `next_shot_at`, increments `shot_counter`.
3. Spread: `rng.seed = hash(unit_id, shot_counter)`; jitter `dir` inside the cone from
   min / max spread. The cone grows with movement and sustained fire.
4. `resolve_shot(origin, dir, range, shooter)`:
   - world occlusion distance **d_world**: physics ray inside the loaded radius (mask
     world, exclude shooter), plus heightmap / trunks / structures beyond (§9.3);
   - soldier hit: record test along the segment, using a spatial grid of `UnitState`
     positions. Nearest soldier hit **d_unit** with zone (head / body);
   - if `d_unit < d_world`, it's a hit: `damage = def.damage * dropoff(d / range) * zone
     multiplier`.
5. `apply_damage(target, amount, zone, shooter)`:
   - `UnitState.health -= amount`;
   - signal `unit_damaged`;
   - at ≤ 0: `alive = false`, orders cleared, signal `unit_died`. `SquadControl` drops the
     soldier from formation slots; the body plays death or is replaced by a corpse proxy.
6. `WorldState.shot_fired(shooter, origin, end, hit)`: `CombatFX` draws the muzzle flash
   at the body's muzzle (viewmodel in FPS), a tracer to the end, and an impact or decal;
   sound plays at the origin.

### 9.3 One shot fired by an AI soldier

1. `CombatBrain` tick (2–4 Hz per unit, budgeted):
   - perception: enemies within weapon range and field of view from the spatial grid, then
     a line-of-sight check (same occlusion as §9.2);
   - target memory: `last_seen` position and time; keep the current target if still
     visible.
2. Engage state:
   - aim = target position + aim error (grows with distance, the target's movement, and
     later suppression);
   - when `next_shot_at` is due, call **the same** `request_fire(unit_id, origin = eye or
     muzzle, dir = aim)`.
3. Same `CombatSim` path: steps 2–6 above.
4. Without a body (abstract): identical, run at a lower rate. Origin = record position +
   eye height. No `CombatFX` unless the camera is near.

**Occlusion rule.** For identical results everywhere:
- terrain = heightmap march with adaptive steps (physics may answer where it is loaded,
  because the two agree, §3.9);
- trees = cached trunk grid of the vegetation chunks, minus clearings;
- structures = `StructureManager` records, oriented boxes along the segment, the same
  data as `blocks_point`.

### 9.4 Detailed vs abstract

- **Shared statistics.** `WeaponDef` and the damage rules are identical. The abstract tier
  calls the same `request_fire` at the same `next_shot_at` cadence; it only skips effects
  and runs perception less often.
- **Coarse resolution, for later and very many units.** If per-shot cost is too high for
  hundreds of far units, a squad-level resolver can replace individual shots: expected hits
  per second = rounds per second × P(hit | range, exposure, cover, suppression), drawn with
  a seeded RNG. It consumes the same magazine counters and applies the same damage events.
  The interface is the same `CombatSim.apply_damage`, so detailed and abstract outcomes stay
  consistent.
- **Transitions.** Combat state lives in `UnitState` (magazine, reload end, next shot,
  target, last seen). Promotion or demotion changes only who renders the unit. Since a shot
  is a single event applied once by `CombatSim`, there are no duplicate shots or damage.
- **Reproducibility.** Seeds from (`world_seed`, `unit_id`, `shot_counter`).
  Data-based occlusion makes outcomes independent of the camera position.

### 9.5 What we write (estimates)

| Component | Lines (GDScript) | Notes |
|---|---|---|
| `WeaponDef` resource + `rifle.tres` | 60 | Fields from Jeh3no, static only |
| `UnitState` / `SquadState` combat fields + save | 60 | Extends existing to_dict / from_dict |
| `CombatSim` (fire, spread, resolve, damage, death, events) | 300–400 | Uses Geometry3D, physics ray, world data |
| Occlusion helpers (heightmap march, trunk grid, structure boxes) | 150–250 | Trunk grid reuses `StructureManager._trees_in`-style caching |
| `CombatBrain` (perception, memory, engage / reload / hold, budget) | 250–350 | State enum; Beehave only if it outgrows this |
| FPS input + viewmodel / muzzle hookup in `SoldierBody` | 80–120 | Input changes, not combat |
| `CombatFX` (flash, tracer, impact, decal, audio pooling) | 120–180 | Godot built-ins |
| HUD / RTS feedback (ammo, health, hit marker, squad contact) | 80–120 | Existing HUD and panel |
| **Total** | **~1,100–1,500** | Plus targeted tests |

---

## 10. COMBAT-01 roadmap

Each milestone is playable on its own, tested with short scripted runs like
UNIT-01A / WI-01, and documented.

### COMBAT-01a: combat core and the FPS rifle

**Scope:**
- `WeaponDef` (one rifle: semi / auto, 30-round magazine, 2.4 s reload, drop-off curve,
  head ×2);
- `UnitState` combat fields and save/load;
- `CombatSim` request / resolve / damage / death;
- possessed-soldier input (LMB fire, R reload, V fire mode in FPS only);
- `CombatFX`: muzzle flash, tracer, impact, decal, 3D sound;
- FPS HUD: ammo, health, hit marker;
- dead soldiers: alive = false, dropped from selection and formations, a corpse marker in
  both tiers, persistent.

**Reused:** Godot built-ins; patterns from Jeh3no, bukkbeek and cluttered-code (§6).

**Risks:**
- shot occlusion cost (data-based) — measure;
- viewmodel and muzzle placement on our soldier model;
- audio assets (§12).

**Acceptance tests:**
- player shots kill a target soldier at 20 / 150 / 250 m (body and head damage per
  `WeaponDef`);
- walls, HESCO, terrain beyond 200 m and trees beyond 40 m block shots;
- a soldier never hits itself;
- the magazine empties, reload takes its time, the reserve decreases;
- state survives Tab, possession change, a 12 km jump and F5/F9;
- the same shot (same seed) gives the same result with the camera near or far;
- frame time with sustained automatic fire stays within 0.5 ms of UNIT-01A.

### COMBAT-01b: perception and autonomous engagement

**Scope:**
- `CombatBrain` per soldier, 2–4 Hz, budgeted:
  - range / field-of-view / line-of-sight perception on records;
  - target memory and a sticky target;
  - engage → fire with aim error → reload when empty → lost target (search the last seen
    point briefly, then resume the order).
- Squad rule of engagement: weapons free (default) / hold fire (key in RTS, shown in the
  panel).
- Movement: orders keep driving movement. Soldiers fire while holding or when in position;
  firing while moving has lower accuracy.
- AI uses `request_fire` exactly like the player.

**Reused:** Open RTS polling and target pick; optionally Beehave if the state count grows.

**Risks:**
- line-of-sight checks per second (budget plus caching);
- aim error tuning;
- target thrashing (stickiness).

**Acceptance tests:**
- two squads 150 m apart with clear line of sight detect each other in under 2 s and
  exchange fire;
- a squad behind a hill or forest edge does not see the other;
- Hold Fire suppresses firing and Weapons Free resumes it;
- an empty magazine triggers a reload;
- a possessed soldier is never driven by the brain, and its squad keeps engaging;
- line-of-sight checks stay under the budget (for example ≤ 1.5 ms per frame) with
  16 v 16.

### COMBAT-01c: combat without bodies (abstract tier)

**Scope:**
- the same `CombatBrain` and `CombatSim` for units without bodies, at a lower rate;
- no effects;
- data-based occlusion only;
- casualties, ammunition and target memory consistent through promotion and demotion.

**Reused:** the 01a / 01b code unchanged. This is the payoff of record-based resolution.

**Risks:**
- cost when many far fights run at once (cap the rate per squad);
- the coarse squad-level resolver is kept in reserve (§9.4), not built unless measured
  necessary.

**Acceptance tests:**
- a fight continues while the camera is 10 km away, and casualties and ammunition match a
  reference run with the same seeds within tolerance;
- returning mid-fight shows the same state;
- no duplicate damage across 20 forced promotion / demotion cycles during a fight.

### COMBAT-01d: first firefight, integration and feedback

**Scope:**
- the scenario: Alpha (8) vs an opposing squad of 8 on mixed terrain near a base;
- RTS feedback in the squad panel (in contact, casualties, ammunition low), health on
  selection rings, death markers;
- the player commands in RTS, possesses one soldier, fights in FPS, returns with Tab;
- FX and sound tuning;
- performance pass.

**Reused:** UNIT-01A squads and orders, WI-01 world, everything above.

**Risks:**
- combat feel (aim error, time to kill) needs your playtesting;
- the visual detail radius for far enemies (§12).

**Acceptance tests:**
- the scripted firefight resolves (one side broken or eliminated) with plausible
  casualties;
- the player's possessed soldier contributes kills that the RTS state reflects;
- Tab mid-fight resets nothing;
- save mid-fight and load continue the fight;
- frame times documented against UNIT-01A.

**Deferred:** suppression, cover-seeking and cover indicators, ballistics and penetration,
grenades, vehicles and AT weapons, morale, medics and wounds.

**Foundations already in place for later:**
- the shot event stream (near misses for suppression: distance from the segment to each
  unit is already computed in the record test);
- `StructureManager` boxes and vegetation and terrain line-of-sight helpers (cover
  detection and indicators);
- `CombatBrain` states (for a Beehave or LimboAI move).

---

## 11. Links to exact sources and commits

Inspected trees (shallow clones, 2026-10-20). Pin these when adopting anything.

| Repository | Commit | Key files |
|---|---|---|
| [Jeh3no/Godot-simple-FPS-weapon-system](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system/tree/a7bd56c978c1abe1894e6b3822f8826f0a119cfb) | `a7bd56c978c1abe1894e6b3822f8826f0a119cfb` | [weapon_resources_script.gd](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system/blob/a7bd56c978c1abe1894e6b3822f8826f0a119cfb/addons/JehenoSimpleFPSWeaponSystem/Weapons/Scripts/weapon_resources_script.gd), [shoot_managers_script.gd](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system/blob/a7bd56c978c1abe1894e6b3822f8826f0a119cfb/addons/JehenoSimpleFPSWeaponSystem/Weapons/Scripts/shoot_managers_script.gd), [weapon_manager_script.gd](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system/blob/a7bd56c978c1abe1894e6b3822f8826f0a119cfb/addons/JehenoSimpleFPSWeaponSystem/Weapons/Scripts/weapon_manager_script.gd), [reload_manager_script.gd](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system/blob/a7bd56c978c1abe1894e6b3822f8826f0a119cfb/addons/JehenoSimpleFPSWeaponSystem/Weapons/Scripts/reload_manager_script.gd) |
| [bukkbeek/GodotFPS-Template](https://github.com/bukkbeek/GodotFPS-Template/tree/11619794d644e7933f87caa6099f3acc1f085f5d) | `11619794d644e7933f87caa6099f3acc1f085f5d` | [common/weapon/weapon.gd](https://github.com/bukkbeek/GodotFPS-Template/blob/11619794d644e7933f87caa6099f3acc1f085f5d/common/weapon/weapon.gd), [common/autoloads/bullets.gd](https://github.com/bukkbeek/GodotFPS-Template/blob/11619794d644e7933f87caa6099f3acc1f085f5d/common/autoloads/bullets.gd), [common/enemy/enemy.gd](https://github.com/bukkbeek/GodotFPS-Template/blob/11619794d644e7933f87caa6099f3acc1f085f5d/common/enemy/enemy.gd) |
| [chafmere/Godot4-FPS-Template](https://github.com/chafmere/Godot4-FPS-Template/tree/71309293911f57b124cf1b4be751df311b20b48c) | `71309293911f57b124cf1b4be751df311b20b48c` | [Projectile.gd](https://github.com/chafmere/Godot4-FPS-Template/blob/71309293911f57b124cf1b4be751df311b20b48c/Player_Controller/scripts/Projectiles/Projectile.gd), [Weapon_State_Machine.gd](https://github.com/chafmere/Godot4-FPS-Template/blob/71309293911f57b124cf1b4be751df311b20b48c/Player_Controller/scripts/Weapon_State_Machine/Weapon_State_Machine.gd), [spray_profile.gd](https://github.com/chafmere/Godot4-FPS-Template/blob/71309293911f57b124cf1b4be751df311b20b48c/Player_Controller/Spawnable_Objects/SprayProfiles/spray_profile.gd) |
| [lampe-games/godot-open-rts](https://github.com/lampe-games/godot-open-rts/tree/a628ad3bb6a9a903587a181a7ee3300dbf735e81) | `a628ad3bb6a9a903587a181a7ee3300dbf735e81` | [WaitingForTargets.gd](https://github.com/lampe-games/godot-open-rts/blob/a628ad3bb6a9a903587a181a7ee3300dbf735e81/source/match/units/actions/WaitingForTargets.gd), [AutoAttacking.gd](https://github.com/lampe-games/godot-open-rts/blob/a628ad3bb6a9a903587a181a7ee3300dbf735e81/source/match/units/actions/AutoAttacking.gd), [AttackingWhileInRange.gd](https://github.com/lampe-games/godot-open-rts/blob/a628ad3bb6a9a903587a181a7ee3300dbf735e81/source/match/units/actions/AttackingWhileInRange.gd) |
| [cluttered-code/godot-health-hitbox-hurtbox](https://github.com/cluttered-code/godot-health-hitbox-hurtbox/tree/c9d21850e6fa60a67f6a3ff0dac889bf803d06ad) | `c9d21850e6fa60a67f6a3ff0dac889bf803d06ad` (v5.0.4) | [health.gd](https://github.com/cluttered-code/godot-health-hitbox-hurtbox/blob/c9d21850e6fa60a67f6a3ff0dac889bf803d06ad/addons/health_hitbox_hurtbox/health/health.gd), [hurt_box_3d.gd](https://github.com/cluttered-code/godot-health-hitbox-hurtbox/blob/c9d21850e6fa60a67f6a3ff0dac889bf803d06ad/addons/health_hitbox_hurtbox/3d/hurt_box_3d/hurt_box_3d.gd), [hit_scan_3d.gd](https://github.com/cluttered-code/godot-health-hitbox-hurtbox/blob/c9d21850e6fa60a67f6a3ff0dac889bf803d06ad/addons/health_hitbox_hurtbox/3d/hit_scan_3d/hit_scan_3d.gd) |
| [limbonaut/limboai](https://github.com/limbonaut/limboai/tree/df8933d3e1a0e7884efb640c0e363140741c50cb) | `df8933d3e1a0e7884efb640c0e363140741c50cb` (release v1.8.1) | [limboai.gdextension](https://github.com/limbonaut/limboai/blob/df8933d3e1a0e7884efb640c0e363140741c50cb/gdextension/limboai.gdextension), [README version table](https://github.com/limbonaut/limboai/blob/df8933d3e1a0e7884efb640c0e363140741c50cb/README.md) |
| [bitbrain/beehave](https://github.com/bitbrain/beehave/tree/fe589153fa780a3f88989578ceb5f539afffb7c2) | `fe589153fa780a3f88989578ceb5f539afffb7c2` (2.9.4-dev; release v2.9.3) | `addons/beehave/nodes/beehave_tree.gd`, `composites/selector.gd`, `leaves/action.gd` |
| [Tattomoosa/VisionCone3D](https://github.com/Tattomoosa/VisionCone3D/tree/944b83d562b894a9d997ea762e16c7eefc1cf846) | `944b83d562b894a9d997ea762e16c7eefc1cf846` (0.3.0) | `addons/tattomoosa.vision_cone_3d/src/VisionCone3D.gd` |
| [toledosq/godot_weapon_manager](https://github.com/toledosq/godot_weapon_manager/tree/2a530156d973aeba25df2b38ea266aed5bf6a5aa) | `2a530156d973aeba25df2b38ea266aed5bf6a5aa` | `scripts/weapons/Weapon.gd`, `scripts/player/WeaponManager.gd` |
| [indieAYUSH/Simple-and-Modular-weapon-system-for-godot-4.x](https://github.com/indieAYUSH/Simple-and-Modular-weapon-system-for-godot-4.x/tree/1d214cbc43600289d6c86dc94cb539dff6806fc9) | `1d214cbc43600289d6c86dc94cb539dff6806fc9` | `fps-weapon-system-1/addons/weapons/Scripts/` |
| [quiver-dev/top-down-shooter-core](https://github.com/quiver-dev/top-down-shooter-core/tree/75c6dd4da43f160c503045c7f513d9dfb1e33ea5) | `75c6dd4da43f160c503045c7f513d9dfb1e33ea5` | `weapons/distance_weapon.gd`, `weapons/magazine.gd` |

### Dependency inventory (proposal for COMBAT-01)

| Dependency | Version | Licence | Status |
|---|---|---|---|
| Godot | 4.7.2-stable | MIT | existing |
| Jolt Physics (built in) | Godot 4.7.2 | MIT | existing |
| Terrain3D | 1.0.2 | MIT | existing |
| **New runtime dependencies for COMBAT-01** | **none** | — | recommended |
| Beehave (optional, COMBAT-02+) | v2.9.3 (release) / fe58915 | MIT | verified to load on 4.7.2 |
| LimboAI (optional) | v1.8.1 / df8933d | MIT | needs approval to test the native binary |
| cluttered-code health / hurtbox (optional, props) | v5.0.4 / c9d2185 | MIT | verified on 4.7.2 / Jolt |
| Weapon audio | — | — | open (§12) |

---

## 12. Open questions requiring your decisions

1. **LimboAI.** May I download and load its official v1.8.1 release binary in an isolated
   test project to verify it on 4.7.2? My recommendation: not needed for COMBAT-01; revisit
   at COMBAT-02.
2. **Weapon audio and effects.** Where should rifle sounds come from?
   - CC0 sources (for example freesound CC0 or Kenney);
   - Pixabay (free use, no resale, attribution not required);
   - recorded / synthesised in-house.

   The models come from our Blender pipeline as before.
3. **Health model.** A single HP pool with head / body multipliers (recommended for
   COMBAT-01), or wound zones (limbs, bleeding) later?
4. **Friendly fire.** On (recommended: the same rules for everyone; shots already ignore
   only the shooter), or off for COMBAT-01?
5. **Death and the possessed soldier.** When the player's soldier dies, switch to RTS
   (recommended) or auto-possess a squad mate? Do dead soldiers stay as persistent corpse
   markers (recommended), or disappear?
6. **Default rules of engagement.** Weapons free (recommended) or hold fire until ordered?
7. **Visual range of enemies.** Far enemies (> 150 m) show as proxies. Should combat raise
   the body promotion radius for *engaged* units (looks better, costs frame time), or keep
   proxies with clearer markers for COMBAT-01 (recommended)?
8. **Shot occlusion authority.** I recommend data-based occlusion everywhere (heightmap,
   trunk grid, structure records), with physics used only where the result is provably
   identical. This makes outcomes independent of the camera. The alternative is cheaper but
   camera-dependent physics occlusion. Confirm.

# ASSET-INTEGRATION-01 — weapons and vehicles in the gameplay systems

The 16 WEAPON-ASSETS-01 weapons and 6 VEHICLE-ASSETS-01 vehicles are registered in the existing systems (`WeaponDef` /
`InfantryRole` / `InfantryLoadout` / `InfantryEquipment`, `VehicleDefs` / `VehicleVisual` / `VehicleSim` /
`VehicleTransport`) and can be tested in the Development Scenario through a small armoury (F10). No asset was rebuilt; no
parallel weapon, vehicle, inventory, combat or movement system was added. New Game is unchanged (checked by the test).

During review the product owner pointed out that soldiers looked *down into* the weapon instead of along the sight. That was
true of the shared rifle pose too (VISUAL-03 clips) and is fixed for every weapon by the same hold modifier (§2.2).

## 1. What was built

| Part | Where | What it does |
|---|---|---|
| Hold data on the weapon piece | `InfantryEquipment.aim_eye / support_grip / hold_shift` | The weapon's own aiming eye (sight line x, height, eye relief behind the grip) and support-hand point; written into the 16 `weapon_<id>.tres` by `tools/asset_integration/make_weapon_data.py` (also kept by `build_weapons.write_equipment` through `weapon_holds.json`). Defaults = the shared rifle, so existing pieces are unchanged as data. |
| Hold modifier | `scripts/characters/infantry_grip_ik.gd` (`InfantryGripIK`, run after the aim / flinch modifiers) | While the weapon is raised: turns neck and head to look along the bore, moves the weapon so its aiming eye is at the right eye (measured once on the rig's `Eye` surface), solves both arms onto it (two-bone, the clip's elbow plane): firing hand on the grip, support hand on the weapon's own `GRIP_Support` (or the override). |
| First person | `Viewmodel` | Lays the held weapon's own sight line on the camera (pistols, SVD, launchers); built-in optics: clear `Lens`, faces across the sight axis cut away; magnified scopes (optic > 25 cm: HK417, AXMC, SVD) hide the weapon at full aim and draw a ring + duplex cross hairs; the arms hold a secondary launcher with the same hold; the arms keep their hold during a reload (no more sleeve filling the view). |
| Weapon definitions | `assets/combat/weapons/<id>.tres` (16), `CombatSim.WEAPON_DIR_NAMED` | Copied from the class they belong to (rifle, carbine, dmr, lmg, gpmg, launcher, recoilless) with the weapon's magazine, rate, sight zoom (`ads_fov`); pistols and the AXMC tuned from carbine / dmr. No procurement fields, in no development project. Launchers carry `WeaponDef.held_piece` (their GLB + hold). |
| Development roles | `assets/combat/roles/dev/dev_<id>.tres` (16), `InfantryRole.DEV_DIR` | One per weapon (launchers: with the family's new rifle - HK416 / AK-12 - and the launcher as secondary). A subfolder, so the equipment screen's role list never shows them. |
| Loadouts | `assets/characters/infantry/loadouts/{NATO,RU,CN}_w_<id>.tres` (36) | Each faction family's rifleman with the weapon in the hands instead of the rifle and its accessories (`InfantryRole.loadout_for` picks the soldier's family). |
| Vehicle definitions | `VehicleDefs` LMV / PATRIA / CV90 / SCANIA / LEOPARD / NH90, `pack_ids()` | Dimensions, handling, seats, door positions; `articulated`, `tracked`, `drivable`. `all_ids()` and `BaseSim.VEHICLES` (the economy) are untouched. |
| Articulation | `VehicleVisual` (articulated branch) | Parts from the GLB pivots listed in the sidecar: wheels spin and steer (radius measured on the mesh), road wheels / sprockets / idlers / rollers spin, doors / hatches / ramp open about the sidecar's axis (sign chosen so they swing out / up / down) and slide doors slide, turret / gun / RWS turn to presentation inputs, rotors spin. Doors open by themselves while the transport boards or unloads at a stop; the NH90's rotor idles while anyone is aboard or boarding. |
| No-flight guard | `VehicleSim` | A type with `drivable = false` (NH90) refuses drive orders with a reason and never moves, driven or not. |
| Development armoury | `scripts/ui/dev_armoury.gd` (`DevArmoury`), scenario rule `dev_armoury` (dev.tres only) | F10 in the tactical view: weapon buttons (to the selected soldier, or the possessed one; in first person **[ / ]** step through the list), vehicle buttons (parked at the camera focus), Doors / Turret sweep / Rotor / Drive for the selected or last spawned vehicle. `CombatSim.give_role` re-equips through `_equip_role` (the economy's path, without cost). |
| Test | `scripts/debug/asset_integration_selftest.gd` `--asset-integration-test` | §4. |

Changed shared code, briefly: `InfantryCharacter` (eye measurement, hold modifier set-up, held secondary swap /
`secondary_scene()`, reset on rebuild), `SoldierBody` (held piece of the secondary, swap when another secondary is
issued), `WeaponDef.held_piece` / `held_scene()`, `CombatSim.weapon()` fallback folder and `give_role`,
`InfantryRole.by_id()` fallback folder, `CoreDemo` (armoury, test switch).

## 2. Weapons

### 2.1 Status per weapon

Grip numbers are measured on the posed skeleton in the game (bone attachments), weapon raised, standing: firing wrist and
support wrist against their hold on the weapon (cm), the eye's distance from the weapon's aiming eye (cm), the head's look
direction against the bore (deg). FPS: the weapon's sight point off the camera axis at full aim (mm), and one shot / reload.

| Weapon | Registered (def / role / loadouts) | Third person: wrist / support / eye / look | FPS: sight off axis, zoom | Shot / reload / magazine | Gameplay class | Remaining limitations |
|---|---|---|---|---|---|---|
| HK416N | yes | 0.0 / 0.2 / 0.1 cm / 0° | 0.1 mm, 42° | fires, reloads, mag on `ATT_Magazine` | rifle | CompM4 seen through its clear tube (no lit dot) |
| HK417 | yes | 0.1 / 0.1 / 0.0 / 0° | scope view, 14° | yes (not in the FPS set) | dmr | scope reticle is a generic duplex |
| FN Minimi 7.62 | yes | 0.0 / 1.8 / 0.1 / 0° | 0.5 mm, 42° | fires, reloads; belt, nothing moves on reload | lmg | — |
| FN MAG | yes | 0.1 / 0.2 / 0.0 / 0° | 0.5 mm, 42° | fires, reloads (belt) | gpmg | support hand under the gas cylinder (asset marker is a bipod hold on the butt); stock touches the jaw |
| Glock 17 | yes | 0.1 / 0.2 / 0.0 / 0° (arm's length) | 0.5 mm, 55° | fires, reloads, mag on bone | rifle-class rules, semi only | reload clip is the rifle's (the hands do not meet at the grip); prone: eye 6.8 cm off (arm reach) |
| AI AXMC | yes | 0.0 / 0.1 / 0.0 / 0° | scope view, 8° | fires (bolt rate 45/min), reloads | dmr (`aim_mult` 0.3, 900 m) | no bolt animation |
| Carl-Gustaf M4 | yes (secondary) | 0.1 / 0.1 / 0.1 / 0° on the shoulder | 0.2 mm, 42° | X to switch, fires a rocket (`CombatSim.fire_secondary`) | recoilless (anti-structure blast) | not carried on the back; no anti-vehicle effect (§5) |
| M72 EC | yes (secondary, 1 tube) | 0.1 / 4.5 / 0.0 / 0° | 1.0 mm, 42° | fires once, then empty | launcher | tube not shown collapsed / discarded |
| AK-12 | yes | 0.0 / 0.1 / 0.0 / 0° | (not in the FPS set) | yes | rifle | iron sights only (no optic on the asset) |
| AK-74M | yes | 0.1 / 0.1 / 0.0 / 0° | 0.1 mm, 48° | fires, reloads, mag on bone | rifle | — |
| RPK-74M | yes | 0.1 / 0.1 / 0.0 / 0° | (not in the FPS set) | yes | lmg (45-rd magazine) | — |
| SVD | yes | 0.1 / 5.1 / 0.1 / 0° | scope view, 10° | fires, reloads | dmr | support hand 5 cm short of the asset's handguard point (arm reach with the long eye relief) |
| PKP Pecheneg | yes | 0.1 / 0.1 / 0.0 / 0° | 0.5 mm, 42° | fires, reloads | gpmg | support hand under the shroud (marker is the carry handle); stock touches the jaw |
| MP-443 | yes | 0.0 / 0.2 / 0.0 / 0° | (pistol checked with the Glock) | yes | rifle-class, semi | as Glock |
| RPG-7V2 | yes (secondary, 3 rockets) | 0.1 / 0.1 / 0.0 / 0° | 0.3 mm, 42° (PGO-7 centred) | fires | launcher | rocket stays drawn in the tube after firing |
| RPG-26 | yes (secondary, 1 tube) | 0.1 / 0.1 / 0.0 / 0° | (not in the FPS set) | yes | launcher | as M72 |

Development access for every weapon: armoury button (RTS) and **[ / ]** (FPS); all 16 shown in third person
(`docs/asset_integration01/sheet_weapons_third_person.jpg`, `sheet_weapons_side.jpg`).

### 2.2 The hold, and the look along the sight

The VISUAL-03 clips put the eye near the rifle's sight line but tip the head forward over the receiver; from outside the
soldier looks into the weapon. `InfantryGripIK` now straightens the head onto the bore and brings the weapon's sight line
to the right eye for every weapon (the shipped faction rifles included): measured eye error ≤ 1 mm and look error 0° for
all 16 and for the faction rifle. The same modifier makes pistols reach out to arm's length, puts launchers on the
shoulder with their offset sights at the eye, and moves the support hand to each weapon's own grip, without a new clip.
Postures (`p_posture`): crouch is exact for MG, pistol and launcher; prone keeps the eye on the sight for the MG and the
RPG-7, the support hand stays where the `Prone_Aim` clip holds it (10-17 cm from the standing support point, it is a
different hold), and the pistol prone misses the eye by 6.8 cm (arm reach) — `docs/asset_integration01/sheet_postures.jpg`.

### 2.3 What the weapon gameplay is

The existing rules serve all: hitscan, magazines and reserves on the record, reload, recoil, spread, AI handling numbers per
class; launchers are secondary weapons fired through `CombatSim.fire_secondary` (rocket flight, `detonate` blast on soldiers
and structures). No new ammunition, inventory or ballistics. Numbers are the class's with sensible per-weapon magazine, rate
and zoom; no balance pass.

## 3. Vehicles

| Vehicle | 1. Registered | 2. Visual / articulation | 3. Existing gameplay connected | 4. Not implemented |
|---|---|---|---|---|
| Iveco LMV | `VehicleDefs.LMV`, 4 passengers | GLB, LODs, 3 collision boxes; 4 wheels spin, front steer; 5 doors; RWS yaw / pitch; steering wheel | drives (`VehicleSim`, 49.6 m in the test), player Drive, AI routing, transport (4), logistics cargo 300 kg, save / load | RWS fire; passengers not drawn in seats |
| Patria 6x6 | `PATRIA`, 10 passengers | 6 wheels (axles 1-2 steer), 6 doors / hatches, RWS | drives, transport: a squad of four boarded with the rear door opening (1.0) and got out | as LMV |
| CV9030N | `CV90` (tracked), 8 passengers | 22 track wheels spin, turret, 30 mm gun, RWS, 5 hatches / doors | drives 49.7 m (kinematic turning circle - no pivot turn), transport | turret weapon, track link animation |
| Scania XT 6x6 | `SCANIA`, 12 passengers, 10 t cargo | 6 wheels, front steer, doors, steering wheel | drives 49.6 m, transport, logistics cargo | cargo body not openable |
| Leopard 2A8 NOR | `LEOPARD` (tracked), crew only | 26 track wheels, turret, 120 mm gun, RWS, hatches | drives 49.8 m | main gun / armour / penetration (no vehicle combat exists) |
| NH90 TTH | `NH90`, 10 passengers, not drivable | 2 cockpit doors, 2 slide doors, ramp, main + tail rotor | spawn, inspect, boarding / unloading on the ground (rotor idles at 4 rad/s while loaded) | flight (no flight model): drive orders refused with a reason |

All six: spawnable from the armoury, front to −Z (front markers checked), scale next to a soldier
(`docs/asset_integration01/v_scale_lmv.jpg`, `v_lineup.jpg`), seats exposed as `VehicleVisual.seats` (5 / 12 / 11 / 2 /
4 / 12 markers), the shared presentation inputs turn every moving part (`v_vehicles` checks each moved from rest:
`sheet_vehicles.jpg`). Damage to the new types was not exercised in this milestone; blasts do not reach vehicles (§5).

## 4. Verification

New test `--asset-integration-test [--shots] [--only ...]` (real game, Development Scenario, 1920x1080, ~7 min for all):
`r_registry`, `w_weapons`, `f_fps`, `p_posture`, `v_switch`, `v_vehicles`, `v_drive`, `v_transport`, `s_persist` — **all
pass** (`benchmarks/raw/asset_integration_test.json`). `r_registry` also checks the New Game guards: `VehicleDefs.all_ids()`
and the economy's vehicle table unchanged, no development role in the equipment screen's folder, no armoury rule in
`new_game.tres`, none of the weapons in a development project. `s_persist` round-trips a soldier's role / weapon / look /
secondary and every vehicle type through `UnitState.to_dict` → `var_to_str` → `from_dict` (the save's form). `v_switch`:
FPS → RTS → FPS keeps the HK417 on the record, the character and the first-person arms.

Change-impact runs on the shared code (no full suite):

| Run | Why | Result |
|---|---|---|
| `--combat01-test --only f_gunplay,p_posture` | `Viewmodel`, hold modifier on the shipped rifle / DMR, postures | pass |
| `--paces --visual03-test --only e_trans` | aim / fire / reload transitions and the magazine with the modifier | pass |
| `--scenario=new_game --gameplay05-test --only q_perf` | every aiming soldier now runs the modifier | pass; opening fight 4.6 ms avg, p95 7.7, p99 10.2 ms |
| `--integration03-test --only vehicles` | old truck / APC | fails only on two pre-existing points unrelated to this work: the North HQ open-site precondition and the raw-GLB "lowest point" of the old truck / APC (their hulls start 0.42 / 0.55 m up by asset - no `VehicleVisual` or `VehicleSim` involved) |
| `--logistics-test --only veh_drive,transport` | old vehicles | stops on the same North HQ site precondition before any vehicle code runs (pre-existing) |

Iterations that came from looking at the screenshots: the head looking into the weapon (above); launchers missing from two
shots (a held secondary was not swapped when another one was issued with the same loadout - fixed in `InfantryCharacter` /
`SoldierBody`); black scope views (tube end faces across the sight axis - cut, and the scope view for magnified optics);
the FPS reload filling the view with the sleeve (arms kept in their hold); the launcher cool-down carried over when
re-equipped (reset in `give_role`).

Screenshots (`docs/asset_integration01/`): `sheet_weapons_third_person.jpg`, `sheet_weapons_side.jpg`, `sheet_fps_hip_ads.jpg`,
`sheet_fps_launchers_reload.jpg`, `sheet_postures.jpg`, `sheet_vehicles.jpg`, and full frames `f_*_ads.jpg`,
`w_*_side.jpg`, `p_fn_mag_prone.jpg`, `v_*.jpg`.

## 5. Remaining limitations and future work

* **Anti-vehicle effect.** `CombatSim.detonate` damages soldiers and structures only; launchers do nothing to vehicles.
  Needs a vehicle damage model (armour classes, a hit against the vehicle's footprint) — a combat subsystem, not done here.
* **Vehicle weapons and crew.** Turret / gun / RWS move only by the presentation inputs (armoury sweep); no vehicle fires,
  no crew sits in a seat, passengers stay hidden aboard (the seats are exposed for that work). Tank combat, penetration:
  not started.
* **Helicopter flight.** The NH90 is a landed transport; a flight model in `VehicleSim` would be its own milestone.
* **Tracks.** Wheels spin, the link loops do not move (they are prepared for UV / link animation); tracked vehicles turn
  on the kinematic circle, no pivot turn.
* **Animation.** Reload is the rifle clip for every weapon: pistols (the hands do not meet), belt-fed MGs (nothing moves)
  and the FPS reload view (the weapon dips to the lower corner, a pistol's shoulder shows) want first-person / per-class
  reload clips in the Blender character pipeline; bolts, slides, charging handles and feed covers do not animate.
* **Carrying.** Launchers are not carried on the back (they appear in the hands only); the M72 / RPG-26 are not shown
  collapsed or discarded; the RPG-7's rocket stays in the tube after the shot.
* **Stocks.** MAG / PKP stocks touch the jaw at the cheek weld (head straightened onto the bore); a small hold shift per
  weapon (`InfantryEquipment.hold_shift`) can tune it.
* **Scope picture.** A generic duplex reticle; the real reticles (PM II, PSO-1, PGO-7) and the CompM4's lit dot are not
  modelled.
* **Navigation footprint.** `VehicleBody.FOOTPRINT` (3.3 x 8.7 m) carves the navmesh for every type; the Leopard with its
  gun and the NH90 are larger.
* **Seen during review, not part of this milestone:** the NATO helmet's top is flat rather than round (character asset,
  Blender character pipeline).

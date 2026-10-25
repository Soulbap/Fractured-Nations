# WEAPON-ASSETS-01 - report

Sixteen recognisable infantry weapons (eight NATO / Norwegian, eight Russian), built by script in Blender 5.2,
exported as GLB with authored LODs and separate moving parts, and validated and photographed in Godot 4.7.2.
They fit the existing character weapon contract (`docs/CHARACTER_STANDARD.md` §3), so an `InfantryLoadout`
can carry any of them through the shipped `InfantryEquipment` resources without new code. No gameplay system
was changed.

## 1. What was delivered

| Weapon | Id | Tris LOD0 / LOD1 / LOD2 | Separate parts | Length (m) |
|---|---|---|---|---|
| HK416N | `weapon_hk416` | 34128 / 5126 / 826 | ChargingHandle, Trigger, Stock, Mag, Optic (CompM4-class), Foregrip | 1.004 |
| HK417 | `weapon_hk417` | 37176 / 5576 / 968 | ChargingHandle, Trigger, Stock, Mag, Optic (PM II-class), Bipod | 1.052 |
| FN Minimi 7.62 Mk3 | `weapon_fn_minimi` | 17636 / 3278 / 704 | FeedCover, Trigger, Stock, ChargingHandle, Bipod, AmmoPouch, Belt | 1.010 |
| FN MAG | `weapon_fn_mag` | 9716 / 3074 / 708 | FeedCover, Trigger, Stock, ChargingHandle, Bipod, Belt | 1.265 |
| Glock 17 (P80) | `weapon_glock_17` | 4750 / 1672 / 244 | Slide, Trigger, Mag | 0.198 |
| AI AXMC | `weapon_axmc` | 30786 / 3824 / 912 | Trigger, Bolt, Stock (folding), Mag, Optic, Bipod | 1.265 |
| Carl-Gustaf M4 | `weapon_carl_gustaf_m4` | 8060 / 2720 / 824 | Foregrip, Optic, Bipod | 0.985 |
| M72 EC Mk1 | `weapon_m72_law` | 2588 / 1172 / 292 | RearSight, FrontTube (telescoping), FrontSight | 0.984 |
| AK-12 (6P70) | `weapon_ak12` | 18624 / 2952 / 700 | Bolt, Trigger, Stock (telescopic, folding), Mag | 0.954 |
| AK-74M | `weapon_ak74m` | 11610 / 3378 / 708 | Bolt, Trigger, Stock (folding), Mag | 0.945 |
| RPK-74M | `weapon_rpk74m` | 11876 / 3568 / 788 | Bolt, Trigger, Stock, Mag (45 rds), Bipod | 1.060 |
| SVD | `weapon_svd` | 10722 / 3632 / 712 | Bolt, Trigger, Mag, Optic (PSO-1) | 1.235 |
| PKP Pecheneg | `weapon_pkp_pecheneg` | 9676 / 3474 / 748 | FeedCover, Trigger, Stock, ChargingHandle, Bipod, Belt, Mag (100-rd box) | 1.212 |
| MP-443 Grach | `weapon_mp443` | 4952 / 2116 / 244 | Slide, Hammer, Trigger, Mag | 0.209 |
| RPG-7V2 | `weapon_rpg7` | 6928 / 3280 / 1014 | Trigger, Foregrip, Optic (PGO-7), Grenade (PG-7V) | 0.95 launcher, 1.364 loaded |
| RPG-26 | `weapon_rpg26` | 2706 / 1248 / 372 | RearSight, FrontSight | 0.770 |

Per weapon, in `assets/weapons/{nato,russian}/<id>/`: `weapon_<id>.glb`, the sidecar `weapon_<id>.json`
(parts with pivots in Godot axes and their axis of movement, markers, triangles per LOD and part, materials,
bounds, published dimensions, variant), `weapon_<id>.tres` (`InfantryEquipment`, mode rigid, attach `ATT_Weapon`,
slot `weapon`) and the editable `source/weapon_<id>.blend`.

References: `assets/weapons/_references/<id>/` - downloaded, freely licensed photographs with `manifest.json`
(licence, author, source page) and `notes.md` (variant, dimensions marked *published* or *estimated*,
features, sources including the manufacturer and encyclopaedic pages, uncertainties). The photographs were
used for proportions only; no third-party model or texture is part of the assets.

## 2. How the assets are built

* `tools/blender/weapons/build_weapons.py` - entry point (`--only`, `--export`, `--save-blend`, `--previews DIR`,
  `--list`); modules `wpn_nato_rifles`, `wpn_nato_mg`, `wpn_nato_other`, `wpn_nato_launchers`, `wpn_ru_rifles`,
  `wpn_ru_other`, `wpn_ru_launchers`, each with a `BUILDERS` table.
* `tools/blender/weapons/wpn_lib.py` - the part library on bmesh: side-outline prisms with bevels, lathes
  (barrels, optics, tubes), lofts, Picatinny rails with recoil slots, tubes along paths, boolean cuts with
  retries, weighted normals, box UVs. `Weapon.part(name, pivot, axis)` makes a `PIV_<Part>` pivot empty; the
  magazine part hangs on `ATT_Magazine` so `InfantryCharacter._hang_magazine` finds it. Every primitive is
  tagged with the LODs it appears in, so LOD1 / LOD2 are authored, never decimated.
* Materials are names resolved in Godot by `InfantryMaterials` (the infantry material table, box-projected
  UVs). New: `Weapon_Anodized`, `Weapon_Phosphate`, `Weapon_PaintBlack`, `Polymer_Green`, `Wood_Laminate`
  (procedural wood texture written by the builder to `assets/characters/infantry/textures/`), `Launcher_OD`,
  `Launcher_Green`, `Composite_Dark`. The rows were added to `InfantryMaterials.TABLE` (they reached `develop`
  inside COMBAT-01 commit `fb1ffc1`, made by the parallel session from the shared working tree).
* Weapon space: origin at the pistol grip, +Y muzzle (Godot -Z), bore z = 0.074 for rifles; pistols, launchers
  record their own bore / tube height in the sidecar (`bore_z`).
* Reference download: `tools/vehicle_assets/fetch_references.py --pack weapons` (the vehicle tool, extended -
  no second downloader).

Blender previews (Eevee studio + clay + LOD strips + FPS views) of every weapon: `docs/weapon_assets01/wip/`.

## 3. Validation in Godot

`tools/weapon_assets/run_weapon_lab.sh --validate` (scene `tools/weapon_assets/weapon_lab.tscn`) loads every GLB and
checks: each sidecar part's pivot node at its position (2 mm), the LOD meshes of every part, every surface
material known to `InfantryMaterials.TABLE`, triangles falling LOD0 > LOD1 > LOD2, the LOD0 bounds against the
sidecar (1 cm; this also proves the orientation - muzzle to -Z, up +Y), the overall length against the published
figure (4 % / 15 mm), every marker at its position, the muzzle ahead of the grip, `GRIP_Main` at the origin, and
the `InfantryEquipment` resource. Results: `benchmarks/weapon_assets01/validate.json`.

**All 16 weapons pass (0 failures).** Measured lengths in Godot against the published figure:

| Weapon | Godot (m) | Published (m) | Weapon | Godot (m) | Published (m) |
|---|---|---|---|---|---|
| HK416N | 1.003 | - (estimated 0.98) | AK-12 | 0.954 | 0.88-0.94 |
| HK417 | 1.051 | 1.03 | AK-74M | 0.945 | 0.943 |
| Minimi 7.62 Mk3 | 1.010 | 1.000 | RPK-74M | 1.060 | 1.060 |
| FN MAG | 1.265 | 1.263 | SVD | 1.235 | 1.225 |
| Glock 17 | 0.198 | 0.202 | PKP | 1.212 | 1.200 |
| AXMC | 1.265 | 1.28 | MP-443 | 0.209 | 0.198 (hammer adds 4 mm) |
| Carl-Gustaf M4 | 0.985 | < 1.0 | RPG-7V2 (launcher) | 0.950 | 0.950 |
| M72 EC (extended) | 0.984 | 0.98 | RPG-26 | 0.770 | 0.770 |

The HK416N sidecar carries no published overall length (the Norwegian 14.5" configuration's figure was not
confirmed), so only its bounds were checked; its notes give the photo-traced estimate. The AK-12 measures to the
extended stock with the muzzle device (published range 880-940 mm, 0.954 is 1.5 % over the top of the range).

## 4. Visual inspection and iterations

Every weapon was rendered from left, right, front 3/4, rear 3/4 and two first-person cameras (hip and aiming) and
looked at; problems fixed on the way:

* Camera roll (weapons rendered upright) - camera tracking axis fixed.
* Optic floating over the HK rail - rail top put on the contract height (B + 0.040).
* Pistol grips with a gap under the receiver (HK416, AK family) - grip tops buried in the receiver; floating
  grip ribs on the AK grip replaced by side panels.
* AK handguards: the upper handguard / gas tube sat above the receiver line with a gap to the lower handguard -
  both lowered and joined; finger grooves added.
* AK-74M stock read as a slab - comb drop, concave belly and recessed side panels.
* SVD: PSO-1 lowered (sight line 0.152 m) and the thumbhole stock reshaped (straight lower strut, larger hole).
* RPK-74M came out 1.14 m against the published 1.06 m - barrel end, front sight, bipod and stock pull corrected.
* RPG-7 trigger housing did not reach the grip - housing deepened.
* Launcher first-person cameras sat inside the tubes - per-weapon FPS cameras.
* Previews too bright (black polymer read grey) - studio lights reduced, `Launcher_OD` darkened.

Godot screenshots (1920x1080 frames): `docs/weapon_assets01/godot/` - `weapon_<id>_views.jpg` (left, right,
front 3/4, rear 3/4), `weapon_<id>_fps_lods.jpg` (the game's `Viewmodel` holding the weapon at HIP and ADS, then
LOD1 at 14 m and LOD2 at 30 m), `showcase_{all,nato,russian}.jpg`.

The Godot shots were looked at: materials resolve through `InfantryMaterials` (no grey fallbacks), every weapon
faces -Z with its parts in place, the first-person frames show the HIP placement low right and the ADS line through
the sight (the CompM4 window centred on the HK416), and LOD1 / LOD2 keep the silhouette at their switch distances.
Two lab fixes came from looking: the key light first lit the side facing away from the camera (weapons read black),
and the first showcase laid the weapons flat (bipods and grips stood up) - it is now an upright wall rack.

## 5. Limitations and open points

* Not integrated into gameplay: no loadout or `WeaponDef` uses the new weapons yet (out of scope); the shipped
  infantry rifles are unchanged.
* First-person view: the `Viewmodel` ADS placement assumes the rifle sight line (0.172 m); pistols, the SVD
  (0.152 m) and the launchers (their own sight heights, recorded in the sidecar `fps` cameras of the build)
  need per-weapon ADS offsets when they are wired in.
* Hands: `GRIP_Main` / `GRIP_Support` markers are given per weapon, but the two-hand IK poses of the shared rig
  were not re-fitted for the long launchers and the pistols.
* Detail level: mid-poly hard surface without baked normal maps; surface wear and markings come only from the
  shared tiling textures. The AK receivers, FN MAG / Minimi receivers and the PKP shroud are simplified; the
  CompM4 / PM II / Carl-Gustaf sights are generic forms, not branded replicas.
* Dimensions marked *estimated* in the notes (grip-to-muzzle splits, scope heights, box sizes) were measured
  on photographs and can be off by a few millimetres to centimetres.

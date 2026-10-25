# VEHICLE-ASSETS-01 — Norwegian / NATO military vehicle asset pack

Six vehicle assets built in Blender 5.2 by script, exported as GLB with moving parts, imported and validated in Godot 4.7.2.
Brief: [VEHICLE-ASSETS-01_PLAN.md](VEHICLE-ASSETS-01_PLAN.md).

## 1. Status

| ID | Vehicle | Variant modelled | Status |
|---|---|---|---|
| VEH-01 | Iveco LMV | Norwegian Army LMV ("LAV") with Protector RS4 | **Completed and visually validated** (Blender + Godot) |
| VEH-02 | Patria 6x6 | CAVS hull, Protector RS4 of the Norwegian command variant | **Completed and visually validated** |
| VEH-03 | CV9030N | Mk IIIb, Soucy rubber tracks, Protector RWS | **Completed and visually validated** |
| VEH-04 | Scania military truck | Scania XT 6x6 G-cab cargo (Danish / Dutch configuration; see §2) | **Completed and visually validated** |
| VEH-05 | Leopard 2A8 NOR | 2A8 NOR, EuroTrophy, lightweight Norwegian skirts | **Completed and visually validated**; RWS type is an estimate |
| VEH-06 | NH90 TTH | NATO TTH (German / Finnish / French army configuration) | **Completed and visually validated**; at the lower end of the quality target (§7) |

"Completed and visually validated" means: references researched, dimensions documented, model built, materials applied, moving parts
separated, Blender renders and Godot screenshots looked at, the major problems found in them corrected, GLB exported, imported into
Godot and passing the Godot structural validator. It does **not** mean Arma 3 parity everywhere — see §7 for the honest gaps.

## 2. Variants and decisions

* **Iveco LMV** — Forsvaret's LMV (170 vehicles 2007–2018, designated LAV); four doors, rear door, snorkel, roof light bar and a
  Protector RS4 as on the Norwegian winter photographs.
* **Patria 6x6** — the CAVS hull (Finland / Latvia / Sweden / Germany …). Norway's own Patria 6x6 is the command variant with the
  Protector RS4, so that station is fitted. NATO three-colour camouflage.
* **CV9030N** — the Mk IIIb (2012 programme): add-on armour modules, rubber tracks (Norway introduced Soucy tracks in Afghanistan),
  Protector RWS on the turret, 30 mm Bushmaster II.
* **Scania** — Norway currently has **no** Scania military trucks in production use: the 1986–1997 Scania fleet (3-series 93 / 113 /
  143, 6x6 hook-lift) is being replaced by Rheinmetall MAN HX / TGS. The modern documented Nordic military Scania is the **Scania XT**
  (Danish Army framework ~1,000 trucks, Dutch Army, Finnish Defence Forces). The asset is a Scania XT 6x6 G-cab with a dropside cargo
  body and canvas — named plainly "Scania XT 6x6 military truck", no invented designation.
* **Leopard 2A8 NOR** — 2A8 hull / turret per the KNDS and Norwegian delivery reporting (8.05 m hull, 11.17 m with gun, 3.8 m wide,
  2.72 m turret roof); lightweight skirts with grouser containers (Norwegian change). The Norwegian RWS type is not confirmed in any
  source found; a Protector-type station stands in on the loader's side and is marked as an estimate.
* **NH90 TTH** — NATO reference helicopter; tail rotor on the left of the fin (checked against the German / Finnish photographs).

Full reference notes per vehicle (sources, dimensions verified / estimated, recognition features, uncertainties):
`assets/military/vehicles/_references/<vehicle>/notes.md`; 45 freely licensed photographs with source page, licence and author in
each `manifest.json` (`tools/vehicle_assets/fetch_references.py`). Non-Commons sources (manufacturer, KNDS press release, defence
press, Forsvaret-related forums) are cited by URL in the notes; nothing from them is copied into an asset.

## 3. Dimensions used

| Vehicle | Length | Width | Height | Running gear | Source quality |
|---|---|---|---|---|---|
| Iveco LMV | 4.87 m | 2.00 m body / 2.05 m flares | 2.05 m roof | WB 3.20 m, track 1.72 m (est.), 335/80 R20 Ø 1.04 m | published + photo estimates |
| Patria 6x6 | 7.50 m | 2.84 m hull | 2.30 m hull / 2.46 m cab | axles 1.55 + 1.55 m (est.), Ø 1.24 m | published + photo estimates |
| CV9030N | 6.55 m hull | 3.24 m over armour | 2.62 m turret roof | 7 road wheels Ø 0.62 m, track 0.533 m, front sprocket | compiled Mk III data + estimates |
| Scania XT 6x6 | 8.90 m | 2.55 m | 3.25 m cab | WB 4.50 m to tandem, tandem 1.40 m, Ø 1.20 m | estimates |
| Leopard 2A8 NOR | 8.05 m hull, 11.17 m gun fwd | 3.80 m | 2.72 m roof, 3.13 m periscope | 7 road wheels Ø 0.70 m, track 0.635 m, rear sprocket | published |
| NH90 TTH | 16.13 m fuselage, 19.56 m rotors | 16.30 m rotor | 5.23 m tail rotor top | mast y 2.05 / z 4.12, tail rotor Ø 3.2 m (est.) | published + estimates |

Godot-measured LOD0 bounds (incl. antennas, mirrors, rotor blades parked at 45°): LMV 2.46 × 3.88 × 5.44 m, Patria 3.53 × 4.08 × 7.72,
CV90 3.29 × 4.64 × 7.69, Scania 2.99 × 4.67 × 9.12, Leopard 4.42 × 4.96 × 11.34, NH90 12.20 × 5.00 × 17.05 (x · y · z, Godot).

## 4. Numbers (measured)

| Vehicle | Triangles LOD0 / 1 / 2 | Draw objects LOD0 / 1 / 2 | Surfaces LOD0 | Materials | Moving parts | GLB |
|---|---|---|---|---|---|---|
| Iveco LMV | 32,780 / 7,008 / 1,140 | 13 / 12 / 6 | 37 | 6 | 12 | 1.5 MB |
| Patria 6x6 | 40,720 / 8,010 / 1,160 | 15 / 15 / 8 | 44 | 7 | 14 | 1.3 MB |
| CV9030N | 54,086 / 15,678 / 1,506 | 34 / 34 / 6 | 66 | 6 | 33 | 2.8 MB |
| Scania XT 6x6 | 37,210 / 8,750 / 1,204 | 12 / 11 / 9 | 36 | 6 | 11 | 1.0 MB |
| Leopard 2A8 NOR | 67,514 / 15,908 / 1,730 | 36 / 36 / 6 | 63 | 5 | 35 | 4.2 MB |
| NH90 TTH | 14,282 / 4,912 / 3,500 | 12 / 12 / 7 | 23 | 4 | 11 | 1.1 MB |

Triangles are Godot's own counts (`benchmarks/vehicle_assets01/validate.json`). Materials are all from the shared library
(`assets/military/materials/`); three were added: `Camo_NATO3` (NATO three-colour camouflage texture, tile 7 m), `Tyre`
(rubber with the rubber normal map, not folded into the palette) and `Glass_Vehicle` (see-through armoured glass, LOD0 only).
These counts are far above the static-library guidance of 4–5 k for vehicles (ASSET_STANDARD §5): that budget was set for distant
props; these are player-facing vehicles at FPS range. LOD1 (45–180 m) is 4–9× lighter and LOD2 (180–2000 m) is 1.1–3.5 k triangles
with **6–9 draw objects** (doors, hatches, road wheels, rollers, sprockets and the RWS gun have no far LOD; a running-gear block fills
the track band). No frame-time measurement with many vehicles was made in this task (none is claimed).

## 5. Structure for Godot

```
<vehicle>.glb
  Body_LOD0/1/2                     hull (shell with the cabin cavity and openings on LOD0, see §6)
  Turret (Node3D at the ring centre, yaw)   -> Turret_LOD*, Gun (trunnions, pitch) -> Gun_LOD*, Hatch_*
  RWS (yaw) -> RWS_Gun (pitch)
  Wheel_L1 / R1 ... (Node3D at the wheel centre: spin about X, steer about Y on steering axles; one mesh per LOD shared by all wheels)
  RoadWheel_L1..7, Sprocket_L, Idler_L, Roller_L* (spin), Track_L / Track_R (separate loops)
  Door_* (hinge pivots), Door_Slide_* (slide aft), Ramp, Hatch_*, SteeringWheel, CargoBody
  MainRotor (hub, spin) -> Blade_1..4 (pitch), TailRotor (spin about X)
  COL_<n>-convcolonly               simplified collision boxes (3–5 per vehicle, never the render mesh)
  WHEEL_* / SEAT_* / DOOR_* / TOW_* / CARGO_* / ROTOR_* / WEAPON_*   markers
```

Blender +Y = Godot −Z (front), origin on the ground at the footprint centre, metres. The JSON sidecar next to each GLB lists every
part with parent, Godot-space pivot, rotation axis hint and triangles per LOD, plus tracks (link count, pitch, loop length), markers,
collision boxes, dimensions and the QA result. Tracks are prepared for animation: separate loop objects whose links are placed by
`veh_kit.Belt` (113 links × 0.125 m on the CV90, 87 × 0.185 m on the Leopard), with every wheel on its own spin pivot.

The vehicles are **not** wired into gameplay (brief: asset production only). `VehicleVisual` / `VehicleDefs` still drive the
LOGISTICS-01 truck / APC; adopting these assets there needs per-part articulation code (turret, doors, rotors) and is listed in §8.

## 6. Pipeline

* `tools/blender/vehicles/build_vehicles.py` — entry point (`--only`, `--export`, `--save-blend`, `--previews DIR`, `--details`,
  `--lods`, `--qa`). Background Blender, reproducible; reuses the ASSET-PRODUCTION-01 library: `ap_lib.Asset` primitives and authored
  LODs, `ap_materials` (shared materials, Kit_Palette folding, Godot .tres), box UVs, baked dirt vertex colours, the same glTF export
  settings and the library post-import script (`tools/asset_lab/ap_post_import.gd`). No second exporter, material system or import
  path.
* `ap_vehicle.py` — `VehicleAsset` of `Part`s (each an `ap_lib.Asset` with a pivot and parent), shared-mesh instances (wheels),
  selective edge bevels, weighted normals, hull / plan / pod lofts, lathe, and **shells with boolean cuts**: the outer hull is a
  separate part that gets an interior cavity and window / door / hatch openings (exact boolean, verified per cut with automatic retry,
  then joined into the body). Through the see-through glass and open doors the LOD0 cabins show seats, dashboards, racks; LOD1/2 keep
  closed hulls with opaque glass.
* `veh_kit.py` — military tyres with real tread blocks, beadlock rims with CTIS, dual road wheels, sprockets, belt / track-link
  placement (steel double-pin and rubber band links), Protector RWS + M2, smoke dischargers, lamps, mirrors, windows, openings.
* `veh_<vehicle>.py` — one builder per vehicle.
* `tools/vehicle_assets/vehicle_lab.gd` (+ `run_vehicle_lab.sh`) — Godot lab: `--validate` (parts and pivots against the sidecar,
  LOD meshes and visibility ranges, library materials, bounds = scale + orientation, collision shapes, markers) and `--shots`
  (1920 × 1080 sheets, articulation, close-up, LOD strip, line-up with a 1.8 m figure).

Outputs: `assets/military/vehicles/<id>/<id>.glb|.json`, editable sources `assets/military/blender/vehicles/<id>.blend`,
Blender previews `docs/vehicle_assets01/blender/` (front 3/4, rear 3/4, side, elevated 3/4 + clay sheet, close-ups, LOD strip),
Godot screenshots `docs/vehicle_assets01/godot/`.

Library changes: `ap_lib.Asset.build` appended a second `None` for an empty LOD, shifting the object list (never triggered in the
static library, which always has all three LODs); fixed. `ap_materials` gained the three materials and per-material alpha;
`ap_textures` the camouflage generator.

## 7. Visual inspection — what was found and fixed, and what remains

Every vehicle was rendered in Blender (Eevee + Workbench clay) and photographed in Godot, compared with the reference photographs,
and corrected over several rounds. Main findings fixed:

* windows sat inside the bodies (invisible) → glass and frames proud of the skin; then see-through glass with real cabins;
* tread blocks read as gear teeth → lower, finer blocks, lighter rubber;
* lathe parts (rims, road-wheel discs) had faces pointing inwards → closed-section lathe with poles, outward normals;
* boolean cuts collapsed the LMV / NH90 shells → self-intersection mode, per-cut verification and retry;
* `ap_lib` empty-LOD bug (above) dropped the Patria body details;
* floating parts found by the QA gate (steps, tanks, brackets, mudguards, stabiliser, tail gearbox, nav lights) → attached;
* coplanar track pins / road-wheel bands (z-fighting) → separated;
* NH90 cockpit glazing too small and flat → curved glass following the skin, bigger windscreen, lower tail rotor (centre 3.63 m);
* Patria snow chains read as letters → sagging chain bundles; Leopard Trophy radar panels → dark radar windows in painted frames;
* far LOD of tracked vehicles had 34–36 draw objects → 6.

Remaining limitations (honest):

* **Quality level.** The LMV, Patria, CV90 and Leopard are recognisable at FPS and RTS range and carry the variant features, but
  they are scripted hard-surface models without baked normal maps, panel-line decals, weathering masks or unique texture sets —
  below Arma 3 in micro-detail and material variation. The NH90 is the weakest: the fuselage is a smooth loft without panel lines,
  rivet rows, intake grilles or a detailed rotor head; it reads as an NH90 in silhouette but not up close.
* The Scania cab front is generic NTG (no SCANIA lettering, simplified grille shapes).
* QA gate: no floating parts remain; the gate still reports small items — coplanar back-to-back faces of parts sitting on surfaces
  (box bottoms on roofs, the CV90 turret floor on the hull), a few door-frame / hinge coplanar pairs, two degenerate faces on bevelled
  5 cm hatch plates, and edges with inconsistent winding left by the boolean operations inside the shells (no visible holes in the
  Blender or Godot renders). Per-part results are in each sidecar's `"qa"` block.
* Tracks are geometry loops, not yet animated (no UV-scroll or link driver); wheels spin about their pivots.
* No player/AI integration, no damage states, no interior beyond seats / dashboards / racks, no crew figures.
* Several dimensions are photo estimates (see the notes); the Leopard RWS type and the Scania configuration are documented
  substitutions.

## 8. Remaining work (suggested)

1. Integrate into `VehicleDefs` / `VehicleVisual` (part-based articulation: turret / gun aim, doors, rotors, track link scrolling).
2. Detail pass: baked normal maps for panel lines, bolts and grilles from high-poly variants; decals (markings, number plates).
3. NH90: panel lines, intake grilles, rotor head detail, cockpit interior.
4. Performance check with 20–50 vehicles (frame time, draw calls) in the ref_20km world.

## 9. Tests run

* Blender builds of all six with `--qa` (gate results in the sidecars).
* `tools/vehicle_assets/run_vehicle_lab.sh --validate` → **6 / 6 OK** (parts and pivots exact, bounds error ≤ 1 mm, every surface a
  library material, LODs with visibility ranges, collision and markers present).
* `tools/vehicle_assets/run_vehicle_lab.sh --shots` → screenshots inspected (`docs/vehicle_assets01/godot/`).
* No game test suites were run: no game code was changed (assets, tools and the asset-library build scripts only).

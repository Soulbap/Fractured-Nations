# VEHICLE-ASSETS-01 — Norwegian / NATO military vehicle asset production (brief)

Status: **done** (started and completed 2026-10-25) — see [VEHICLE-ASSETS-01_REPORT.md](VEHICLE-ASSETS-01_REPORT.md). The product owner's brief, kept verbatim
in substance. Before starting: read CLAUDE.md, the `fn-blender-pipeline` skill, `docs/ASSET_STANDARD.md`,
and check the existing vehicle systems (`VehicleSim`, `VehicleBody`, LOGISTICS-01) and asset conventions
(`assets/military/`, `tools/blender/`, `build_assets.py --qa`).

- Engine: Godot 4 (project: 4.7.2) · Modeling: Blender · Target: Arma 3-level realistic exteriors
- Asset count: 6 · Execution: Research → Model → Render → Inspect → Improve → Export → Validate

## 1. Objective

First production-ready military vehicle asset pack. Vehicles must look convincing at close range (FPS) and at
a distance (RTS, strategic map). Arma 3-level exterior fidelity, simplified interiors, efficient geometry for
many simultaneous vehicles and soldiers. Six recognizable, realistic models of real Norwegian / NATO equipment —
no generic placeholders. Recognizable silhouettes, proportions, structural features and equipment. All modeling
in Blender. Research references, build geometry, materials, render, visually evaluate, improve, prepare for
Godot. This is asset production, not research only.

## 2. Vehicles

| ID | Vehicle | Reference | Category |
|---|---|---|---|
| VEH-01 | Iveco LMV | Norwegian military configuration | Light tactical vehicle |
| VEH-02 | Patria 6×6 | Finnish/NATO configuration | Armored personnel carrier |
| VEH-03 | CV9030N | Norwegian configuration | Infantry fighting vehicle |
| VEH-04 | Scania military truck | Norwegian military configuration | Logistics vehicle |
| VEH-05 | Leopard 2A8 NOR | Norwegian configuration | Main battle tank |
| VEH-06 | NH90 TTH | NATO transport configuration | Military helicopter |

Prefer Norwegian variants; Patria and NH90 use documented NATO configurations. Verify variants and visual
characteristics; do not mix variant features without documenting it. NH90 is a NATO reference vehicle, not a
representation of Norway's current helicopter fleet.

## 3. Reference research (mandatory, before any geometry)

Find per vehicle: front / rear / side / three-quarter photos; high-resolution detail photos; technical
drawings and dimensions; manufacturer specs; real dimensions and proportions; wheel / track / suspension
layout; turret and weapon-mount geometry; exterior equipment; paint schemes and materials; extra photos of
hard components. Prefer manufacturer docs, military publications, manuals, photos of real vehicles. Private
project: references need not be royalty-free, but study them — never redistribute or reuse third-party 3D
models, textures or protected assets as original work.

Organization: `assets/vehicles/_references/<vehicle>/` with downloaded material where permitted plus a
reference manifest (source URLs, descriptions, observations). If an image cannot be downloaded, keep the URL
and describe it.

Establish before modeling: (1) approximate real dimensions, (2) silhouette and proportions, (3) major
recognizable components, (4) variant-specific differences, (5) exterior materials and colours, (6) components
to separate for animation. Never invent specs; mark visual estimates clearly.

## 4. Visual quality target

Want: realistic proportions, convincing silhouettes, properly shaped bodies, recognizable cabins / armour,
detailed wheels / tracks / suspension, realistic turrets and weapon mounts, convincing windows / lights /
grilles, armour plates and panel separation, functional-looking hinges / handles / hatches, believable
military materials, subtle wear.

Avoid: primitive boxes, wrong proportions, oversimplified wheels, cylinders standing in for mechanical
assemblies, floating parts, over-rounded / cartoon shapes, random decorative geometry, unrealistic metal
reflections, flat surfaces where the reference shows structure.

A successful script is not a successful model — the render decides. Efficient hard-surface modeling:
silhouette and major structure first; bevels, weighted normals, sensible smoothing and topology; important
geometry explicit, small detail in textures / normal maps; no bolt-level CAD.

## 5. Vehicle-specific requirements

**VEH-01 Iveco LMV** — armoured cabin; correct bonnet / windshield proportions; four realistic off-road
wheels; arches and suspension clearance; side doors and handles; armoured windows; mirrors; head / rear
lights; front grille; bumpers and protection; roof equipment per reference. Wheels and steering separate;
doors separate where practical; simplified interior (seats, wheel, dashboard).

**VEH-02 Patria 6×6** — correct six-wheel layout; distinctive armoured hull; sloped front armour; driver
vision equipment; wheel arches; visible suspension; side equipment; rear troop access; roof hatches; weapon
station / mount per documented configuration. Wheels, hatches and weapon station separate; simplified
interior.

**VEH-03 CV9030N** — tracked hull silhouette; recognizable turret; main cannon; turret optics; road wheels,
drive sprockets, idlers; track geometry (never one featureless slab); side armour and equipment; engine
grilles; rear troop access; hatches, storage. Separate turret and cannon; tracks prepared for animation.

**VEH-04 Scania military truck** — research and document the exact Norwegian-relevant variant (no invented
designation). Cabin proportions; chassis; axle configuration; military off-road tyres; suspension and
clearance; fuel tanks; steps, mirrors, headlights, grille; cargo bed or logistics body; military equipment.
Wheels separate; cargo body a distinct component where practical.

**VEH-05 Leopard 2A8 NOR** — verify references carefully; do not assume older Leopard 2 details carry over.
Hull proportions; turret geometry; main gun; turret armour; road wheels, tracks, sprockets, idlers; engine
deck, grilles; hatches; optics; storage; Norwegian details. Separate turret and gun. Where Norwegian details
cannot be verified, use documented 2A8 characteristics and note the uncertainty.

**VEH-06 NH90 TTH** — fuselage proportions; nose and cockpit; cockpit windows; main rotor with individual
blades; tail boom; tail rotor; engine housings; intakes and exhausts; landing gear; side doors; antennas and
exterior equipment; simplified cabin. Main and tail rotor separate objects with correct pivots; doors separate
where practical; simplified cockpit and troop compartment, no invisible interior detail.

## 6. Blender pipeline

Python scripting where it speeds things up, but not only primitive generation.

- **A Blockout** — verified dimensions: length / width / height, wheelbase or track layout, body proportions,
  turret placement, cabin, rotor dimensions. Render, check against references, fix big problems first.
- **B Detail** — recognizable structure, mechanical credibility, separate animated parts.
- **C Materials** — PBR: painted military metal, rubber, armoured glass, dark optical glass, bare steel,
  plastic, fabric, military camouflage. Realistic roughness, restrained variation and weathering.
- **D Render** — at least front ¾, rear ¾, side profile, elevated ¾; consistent lighting, neutral background;
  one render lit for inspecting geometry and materials.
- **E Inspect** — look at the actual renders against the references (silhouette, proportions, structure,
  missing parts, materials, wheels / tracks, turret / rotor placement, odd geometry, consistency); fix, render
  again, repeat. Never claim visual validation without inspecting; report if inspection tools are missing.

## 7. Batching

All six may be researched together and built in batches with shared scripts / materials / utilities, but each
vehicle gets its own Blender project, its own export and its own validation. Do not trade quality for finishing
all six; usable assets before six blockouts. If limits stop the run, finish as many as possible, document the
rest, keep reproducible sources. Never silently reduce scope.

## 8. Godot preparation

Real-world scale, metres, consistent forward axis (project: +Y forward in Blender), correct origins, sensible
hierarchy, predictable names, clean transforms, proper material assignments. Export GLB / glTF 2.0. Moving parts
organized for animation, e.g. `VehicleRoot` → Body, Wheels, Turret, Weapon, Doors, Hatches, CollisionReferences
(adapt per vehicle, nothing irrelevant). Helicopters: rotor pivots. Tracked: turret and cannon pivots. Wheeled:
separate wheels.

- **Collision** — simplified collision geometry / references, never the render mesh.
- **LOD** — prepare for LOD; any LOD keeps silhouette and major features and is inspected, not blind decimation.
- **Performance** — efficient geometry; measure and report actual triangle counts, never invented numbers.

## 9. Project integration

Before writing files: inspect structure, existing asset conventions, Godot version and import settings,
existing vehicle systems; no duplicate asset directories or competing pipelines; work in this project only.

Suggested layout: `assets/vehicles/{_references, iveco_lmv, patria_6x6, cv9030n, scania_military,
leopard_2a8_nor, nh90_tth}/`, each with source, export, materials, previews per project conventions. Keep the
`.blend` sources.

Scope: asset production. Do not rewrite vehicle AI, pathfinding, logistics, combat, world generation or other
gameplay. Minimal preview scenes where useful; an existing compatible vehicle controller may be used for
validation without changing behaviour. No new gameplay architecture just for demos.

## 10. Testing and validation (targeted)

Blender sources open; exports succeed; Godot imports the GLBs; materials correct; scale correct; orientation
correct; pivots correct; models display in a Godot preview scene; collision references fit future integration.
Where practical, several vehicles in one test scene for consistency and relative scale; inspect imported assets
visually in Godot. No full game suite unless broader integration risk; no long stress tests.

## 11. Deliverables

Six Blender sources; six GLB exports; reference collections (URLs, images where available, verified dimensions);
at least four preview renders per completed vehicle; report `docs/VEHICLE-ASSETS-01_REPORT.md` with: vehicles
completed, reference variants, sources, dimensions used, triangle counts, material counts, separate movable
parts, Blender export status, Godot import status, visual inspection results, known limitations, remaining work.
Separate clearly: completed and visually validated / exported but not visually validated / work in progress /
not started. Never mark incomplete models production-ready.

## 12. Acceptance (per vehicle)

1. Reference researched. 2. Dimensions and proportions documented. 3. Blender model complete. 4. Exterior
recognizable and convincingly detailed. 5. Materials applied. 6. Moving parts separated. 7. Preview renders made.
8. Visual inspection done. 9. Major visual problems fixed. 10. GLB export exists. 11. Imported into Godot.
12. Sources and documentation preserved. Visual quality, recognizability and correct Godot integration are the
success criteria, not script execution.

## 13. Execution order

Inspect project and Blender tooling → research all six → collect and organize references → verify dimensions and
configurations → set a consistent quality standard → build in Blender → render and inspect → improve failures →
export GLB → validate in Godot → report. Work autonomously on minor modeling decisions; document uncertainty and
continue with labelled approximations; preserve all existing functionality. The goal is real, visually convincing
vehicle assets inside FRACTURED NATIONS — not scripts, placeholders or a plan.

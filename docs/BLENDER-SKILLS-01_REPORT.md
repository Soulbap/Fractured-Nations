# BLENDER-SKILLS-01 — blender-skills in the Blender → Godot pipeline

Branch `feature/blender-skills-01` (worktree `../fractured-nations-blenderskills01`, from
`feature/world-integration-03` @ 21e846a). Not merged into `main`.

Status tags: **[VERIFIED]** checked by a script run (Blender 5.2.2 LTS / Godot 4.7.2);
**[INSPECTED]** looked at in renders / screenshots.

## 1. What was integrated

[EL4CTEO/blender-skills](https://github.com/EL4CTEO/blender-skills) (MIT, upstream 71d031d,
2026-10-16) is a set of 22 *Agent Skills* for Blender 5.2+: `SKILL.md` instructions per
topic plus tested `bpy` scripts with one contract (`run(**kw) -> dict`, CLI prints one JSON
line). It is not a library the pipeline links against; it is knowledge and tooling for the
agent that writes and runs the pipeline. The integration therefore has three parts:

1. **Installed project-scoped** — `.claude/skills/blender-*` (22 skills, 737 KB,
   `LICENSE-blender-skills.txt`), the layout the upstream installer uses for Claude Code with
   `-Scope project`. The runner finds our Blender (`run_in_blender.py --which` →
   `C:/Program Files/Blender Foundation/Blender 5.2/blender.exe` with `BLENDER_EXE`) and
   `env_report.py` runs clean on 5.2.2 (EEVEE/Cycles/Workbench, RTX 3070, glTF/FBX add-ons)
   [VERIFIED].
2. **Project skill `fn-blender-pipeline`** (`.claude/skills/fn-blender-pipeline/SKILL.md`):
   the routing layer that says which generic skills apply to this repo and where our
   conventions differ (+Y front, authored LODs `<id>_LOD0/1/2`, `COL_*-convcolonly` boxes,
   shared material library bound by name on import, box-projection UVs and palette point UVs,
   markers, one shared infantry skeleton, "done = Godot validator + Godot screenshot"). It
   points at our build entry points instead of the skills' modelling scripts.
3. **The QA gate wired into the build** — `build_assets.py -- --qa` runs
   `blender-asset-qa/qa_check.py` and `blender-game-optimization/mesh_stats.py` on LOD0 of
   every built asset through `tools/blender/asset_production/ap_qa.py` (the only module that
   imports the skills), optionally `review_shots.py` contact sheets (`--qa-sheets`). Results go
   into the asset's JSON sidecar (`"qa"`, with `--export`) and a run report; `--qa-strict`
   with `--qa-baseline benchmarks/asset01/qa_baseline.json` fails only on findings that are
   **new** against the recorded library state, so the gate is a regression gate from day one
   while the known backlog stays visible.

Library tolerances (`ap_qa.CHECK`): profile `game`, z-fight distance 2 mm, contact tolerance
3 cm (mounted parts sit on brackets), UV check off (box projection and palette UVs are by
design), budget table `pc`. Accepted by design: n-gons on flat kit faces (triangulated on
export) and back-to-back faces (no bakes). A builder can override per asset (`asset.qa`).

## 2. What the gate found, and what was fixed [VERIFIED]

First run over the five trial assets: HQ 149 closed parts with inward normals, T-wall 2,
chain-link fence 4; z-fighting and "floating" parts everywhere. A signed-volume test per
connected island (own script, outside the skills) confirmed the inward parts were real — the
Godot validator checks LODs, materials, bounds, collision and markers, not winding, and the
ASSET-PRODUCTION-01 screenshots did not show it at inspection distance (an inside-out box
still looks like a box; its lighting is wrong).

Root causes in the shared primitives, fixed at the source:

| Cause | Where | Fix |
|---|---|---|
| `ap_kit.Frame.m` is a reflection (`r = up × n` gives a left-handed frame), so every kit box placed on a wall frame (doors, windows, AC units, steps, lamps) was inside out | `tools/blender/character/char_lib.py: bm_box` | if the transform's linear part has a negative determinant, reverse the box's faces after transforming (vertices stay where the author put them; only the winding changes) |
| `tube_along` builds rings in a left-handed frame; vertical tubes (fallback side axis) and some path directions came out inside out (lifting loops, fence outriggers, downpipes) | `char_lib.py: tube_along` | `bmesh.ops.recalc_face_normals` on the tube's faces |
| Roofs, prisms and lofts with inherited winding (range firing-point roof −7.2 m³, APC glacis −3.1 m³) | `ap_lib.Asset.build` | new `_orient_closed_islands`: every watertight connected part of every LOD is oriented outward; open parts (signs, decals, sheets) keep their authored facing |

Result over the whole library (96 assets, rebuilt and exported in 15 s):

| | Before | After |
|---|---|---|
| Assets with inward-facing closed parts | 54 (HQ alone 149 parts) | **0** |
| Assets passing the gate | 36 | 45 |
| Remaining findings (recorded baseline) | — | z-fighting in 46 assets (coplanar overlapping faces of kit boxes: barracks 416 pairs, container yard 400, tyre run 282, HESCO 5-cell 173, HQ 133); 105 "floating" sub-parts in 18 assets (sandbag rings / stacks, wheel stops, mounted boxes more than 3 cm off their mount); one open wedge with inconsistent winding (`vehicle_ramp`); 6 assets over the 6-materials-per-asset PC budget (7–8) |

The baseline is `benchmarks/asset01/qa_baseline.json`; `--qa-strict --qa-baseline` is green
on it [VERIFIED]. The regenerated library passes the Godot validator, 96 / 96, 0 failures
[VERIFIED, `benchmarks/asset01/validate.json`], and the three StructureDefs edited by hand in
WORLD-INTEGRATION-03 (`walkable`, parking-pad sink) are now emitted by the def writer from
the builders' structure hints, so a rebuild no longer loses them [VERIFIED].

Godot screenshots after the rebuild (`docs/asset01/godot/hq_building.jpg`,
`range_firing_point.jpg`, `apc_8x8.jpg`, `chainlink_fence.jpg`, `t_wall.jpg`) [INSPECTED]:
compared with the committed ASSET-PRODUCTION-01 sheets, the HQ's window frames, door and
AC units now show their outer, lit faces where the old sheet showed the darker inner faces of
the inside-out boxes; the firing-point roof and the APC glacis are lit as outer surfaces;
nothing else moved (same bounds, same validator numbers). The difference is small at sheet
distance — which is why the inspection in ASSET-PRODUCTION-01 missed it and a numeric gate
was needed.

Blender review sheets from the gate: `docs/blenderskills01/qa/*_qa.png` (random colour per
part, four views).

## 3. Files

| File | Change |
|---|---|
| `.claude/skills/blender-*` (22), `LICENSE-blender-skills.txt` | upstream skills, project-scoped |
| `.claude/skills/fn-blender-pipeline/SKILL.md` | project routing skill |
| `tools/blender/asset_production/ap_qa.py` | gate adapter (new) |
| `tools/blender/asset_production/build_assets.py` | `--qa`, `--qa-strict`, `--qa-baseline`, `--qa-sheets`, `--qa-report`; sidecar `"qa"` |
| `tools/blender/character/char_lib.py` | `bm_box` reflection fix, `tube_along` orientation |
| `tools/blender/asset_production/ap_lib.py` | `_orient_closed_islands`; `write_structure_def` emits `walkable` |
| `tools/blender/asset_production/fam_modules.py` | `walkable` / `sink` hints on the three walkable modules |
| `assets/military/**` (96 GLB + sidecars with `"qa"`, 33 defs, catalog, materials) | regenerated with correct normals |
| `benchmarks/asset01/qa_baseline.json`, `validate.json` | recorded gate state, Godot validation |
| `docs/ASSET_STANDARD.md` §6, `CLAUDE.md`, `README.md` | the gate and the skills in the workflow |

Nothing in gameplay code, scenes, the world or the infantry assets changed. The character
builders share `bm_box` / `tube_along`; they were not re-exported (their boxes use pure
rotations, and CHARACTER-01's own checks are the gate for them), so the fixes apply to them
on their next rebuild.

## 4. Backlog from the baseline (not done here)

* Coplanar overlaps: kit boxes whose faces lie in the same plane and face the same way
  (stacked / abutting boxes). Harmless where one face is inside the other part, flicker where
  both are visible. Fix per builder (offset 2–5 mm or merge), then re-record the baseline.
* "Floating" sub-parts: decorative stacks (sandbags, tyres) and mounted boxes that hover a few
  cm; snap them to contact or raise `tol` per asset via `asset.qa`.
* `vehicle_ramp` wedge winding; 7–8 materials on the largest buildings (merge the smallest
  into the palette on LOD0 as already done on LOD1/2).
* The gate runs on LOD0 only; LOD1/2 are derived from the same primitives and share the fixes.

## 5. Running

```bash
# QA only (no files written except the report)
blender -b --factory-startup --python tools/blender/asset_production/build_assets.py -- --qa --qa-report benchmarks/asset01/qa_run.json
# regression gate for a change to one asset
blender -b --factory-startup --python tools/blender/asset_production/build_assets.py -- --only hq_building --qa-strict --qa-baseline benchmarks/asset01/qa_baseline.json --qa-sheets docs/blenderskills01/qa
# full rebuild + export + re-record the baseline, then Godot
blender -b --factory-startup --python tools/blender/asset_production/build_assets.py -- --export --qa --qa-report benchmarks/asset01/qa_baseline.json
benchmarks/asset01/run_lab.sh --validate
# any skill script directly
BLENDER_EXE="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" python .claude/skills/blender-core/scripts/run_in_blender.py .claude/skills/blender-core/scripts/env_report.py
```

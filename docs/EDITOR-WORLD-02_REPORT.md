# EDITOR-WORLD-02 (B + C) — visual world editing, persistence and runtime integration

**Status: B and C accepted** (19 of 19 acceptance items, see section 6) with the limitations in section 10.
Done on branch `develop`; the earlier commits `64ce3e6` (connector fix) and `df83ef2` (plugin + override layer) are
on `develop`, the work of this report is in the commits listed at the end. Canonical world data untouched
(`world_manifest.py verify` OK: 535 files, 0 changed; `scenes/world/ref_20km.tscn` byte-identical to the isolated copy).

## 1. What exists now

- **`world_edit` editor plugin** (`addons/world_edit/plugin.gd`): select, move/rotate/scale, add, remove, restore,
  undo/redo, save; edits static world instances (trees, rocks, houses, barns ...) of the `VegetationStreamer`.
- **Override layer** (`scripts/vegetation/world_overrides.gd`): versioned JSON next to the world
  (`worlds/<world>.overrides.json`, or `FRACTURED_WORLD_OVERRIDES`). Chunk files are never written.
- **Streamer integration** (`vegetation_streamer.gd`): effective cell view for rendering and all queries
  (colliders, line of fire, navmesh obstructions, construction), chunk unload/reload hooks, `reload_chunk`.
- **Runtime wiring fix**: `DetailManager` never connected to `clearings_changed` (it was connected in `_ready`, before
  `core_demo` assigned `navigation.vegetation`/`detail.navigation`), so a moved house did not rebake the navmesh in the
  game. Now `DetailManager.connect_vegetation()` is called from `core_demo` after the wiring.
- **Bug fixed in the layer**: `Dictionary.duplicate()` is shallow and packed arrays are shared by reference, so
  appending a moved instance would have modified the loaded chunk in memory. Buffers are copied before appending
  (found by `tools/test_world_overrides_ref.gd`).

## 2. User guide (`world_edit`)

Open `res://scenes/world/ref_20km.tscn`, 3D view; the **World objects** toolbar is at the top of the viewport.
1. Switch **World objects** on (it selects the vegetation node; the plugin is active while that node or the selection proxy is selected).
2. **Click an object** to select it (ray against mesh bounding boxes, then the nearest candidates against the mesh triangles;
   the nearest visible surface wins). The status line shows type, id, position, rotation (deg) and scale.
   A translucent copy marks the selection and Godot's own gizmo appears on it: **drag to move/rotate/scale**; the edit is applied
   when the mouse is released (exact values can also be typed in the Inspector for the proxy node `WorldObjectSelection`).
   Clicks within ~110 px of the gizmo go to the gizmo; **Ctrl+click** forces a new pick.
3. **Add**: choose the object in the list and press *Add* (placed on the terrain in front of the camera), or switch on **Place**
   and click on the terrain. **Remove** (or Delete) hides the object; **Removed** lists everything removed and restores the
   chosen entry; **Reset** returns a moved generated object to its baseline position.
4. **Undo / Redo** (buttons, Ctrl+Z, Ctrl+Shift+Z / Ctrl+Y while the 3D view has focus) use the plugin's own history
   (scene history is not used, so road/terrain undo is never involved).
5. **Save** writes the override file only. The file is also saved when the editor saves or closes (`_save_external_data`) and a
   close prompt warns about unsaved world edits (`_get_unsaved_status`). Removed manual objects are deleted for good on save.
6. The scene itself is never changed by this tool; do not save `ref_20km.tscn` for world object edits.
The in-game result needs nothing else: the streamer loads the same override file at start.

## 3. Data and identity model

- Record: `{kind: generated|added, mesh, transform (12 floats), removed, [cell, index, chunk_hash]}`; id `g:<cx>:<cz>:<mesh>:<index>`
  for generated instances and `a:<random 128 bit>` for additions. All 16 floats of the source record other than the transform
  (colour) are kept for generated instances.
- A generated record is bound to the **SHA-256 of its source chunk file** (baseline). If the file no longer has that hash the
  record is *unresolved*: it is reported, never applied and never moved to another object. Additions need no baseline.
- Static editor objects are not `WorldState.construction`; player-built structures are untouched.
- Collision proxies are the library's: tree = vertical capsule, rock/house = sphere (`collider` in the library; the radius scales with the
  instance scale, rotation does not matter for these shapes).

## 4. Hash cache and revision strategy (C1)

Before: every cell lookup cleared the hash cache and re-read/hashed the 1-2 MB chunk file (about 4-13 ms per lookup, 100 hashes per 100 lookups).
Now (`world_overrides.gd` header documents it):
- **Revision per chunk file** = `{sha256, mtime, size, checked_at}`. The hash is computed when first needed and *always when the streamer
  (re)loads the chunk*, so the in-memory chunk is bound to the hash taken at load. Lookups reuse it and never read the file.
- **Trust boundary:** chunk files are immutable base-world data while a session runs. A controlled writer (generator, editor file reload)
  calls `invalidate_chunk()/invalidate_all()`. Anything else is *detected*: `poll()` (driven by the streamer, at most one `stat`
  per chunk per second) and `chunk_hash()` compare mtime and size with the revision; a difference drops the revision, makes the streamer
  re-read the chunk (resource cache bypassed) and hashes again, after which records of the old baseline are unresolved.
  mtime/size only ever *trigger* a rehash, they are never accepted as proof of identity.
- Unknown revision (file missing/unreadable): generated records are not used; additions still load.
- **Per-cell effective cache** and per-cell indexes (`_src`, `_dst`): cells without overrides cost nothing, other cells are built once
  until a record or revision changes.
- No generator-written manifest was added: a manifest hash is not proof that a file is unchanged either, and the chunk format and the
  generator stay unchanged. The existing `worlds/ref_20km.manifest.json` still checks the whole world offline.
- Not covered: bytes replaced between two polls with identical size *and* mtime (the next chunk load rehashes anyway).

## 5. Performance (`tools/bench_world_overrides.gd`, real ref_20km chunks, at most 10 overrides per cell, headless, one machine)

Before = pre-revision layer (`docs/ew02/bench_before.json`), after = `docs/ew02/bench_after.json`. avg / max ms per cell lookup; hashes = SHA-256 computations.

| overrides (cells) | phase | before avg / max, hashes | after avg / max, hashes |
|---|---|---|---|
| 100 (10) | cold 100 lookups | 7.7 / 43.3, 100 | 0.60 / 43.6, 1 (the chunk load itself) |
| | warm 100 lookups | 7.5 / 42.8, 100 | 0.15 / 0.27, 0 |
| | after chunk unload + reload | 11.6 / 48.4, 100 | 0.21 / 4.6, 1 |
| | edit one override | 5.8 ms, 102 hashes | 0.74 ms, 0 hashes |
| 500 (51) | cold / warm / reload (avg) | 7.5 / 11.7 / 11.6, 100 hashes each | 0.61 / 0.13 / 0.21, 1 / 0 / 1 |
| | edit one override | 7.9 ms, 102 | 3.5 ms, 0 |
| 1000 (102) | cold / warm / reload (avg) | 10.5 / 11.6 / 13.4, 100 hashes each | 1.04 / 0.13 / 0.84, 2 / 0 / 2 |
| | edit one override | 151 ms, 104 | 7.0 ms, 0 |

One-time cost (validation) = one hash per override-bearing chunk per load; normal operation = 0 hashes. The 43 ms maxima are the
first synchronous chunk read from disk. In the real game (`--ew02-test c1`): 500 warm lookups 8.6 ms, 0 hashes, unload + reload exactly 1 hash.
(The old-layer benchmark was run with only the first 100 of its warm lookups at 500/1000 overrides.)

## 6. Acceptance results

Legend: GUI = real Godot 4.7.2 editor, isolated project copy + isolated world copy + scratch override file, probe plugin
`tools/ew02_acceptance/gui_probe` (results `docs/ew02/gui_phase1.json`, `gui_phase2.json`); RT = real `ref_20km` game scene,
`--ew02-test` (`docs/ew02/runtime_results.json`).

| ID | Result | Evidence |
|---|---|---|
| EW02B-01 select tree | PASS | GUI, real mouse events (`Input.parse_input_event`) on an isolated tree: exact tree (0.0 m) |
| EW02B-02 select house | PASS | GUI, real mouse events, house at Haugen |
| EW02B-03 move/rotate/scale | PASS | proxy transform (tree: +7/+3 m, 30 deg, x1.4; house +20 m, 30 deg) auto-applied, colour preserved byte for byte |
| EW02B-04 undo/redo | PASS | toolbar buttons and Ctrl+Z / Ctrl+Shift+Z key events, also for removal and reset |
| EW02B-05 add | PASS | tree, stone, house via *Add*, tree via *Place* click on terrain (real mouse) |
| EW02B-06 remove/restore | PASS | generated + manual remove, *Removed* menu restore, reset to baseline, again after restart |
| EW02B-07 save + reopen | PASS | save button, editor quit, fresh editor: 7 records, 0 unresolved, objects displayed once at their new places |
| EW02B-08 editor/runtime parity | PASS | game started with the same file: effective-data SHA, displayed MultiMesh SHA, LOD of the edited meshes and override-file SHA identical; collision at all 6 placed objects |
| EW02B-09 unload/reload | PASS | RT b6: unload + reload, no duplicate, no loss, 0 unresolved |
| EW02B-10 between cells/chunks | PASS | RT b6: other cell, other chunk, empty cell (manual), remove + restore |
| EW02C-01 revision/hash cache | PASS | RT c1 + synthetic live-change test (poll detects a rewritten chunk: record unresolved, new content loaded) |
| EW02C-02 100/500/1000 | PASS | section 5 |
| EW02C-03 collision | PASS | RT c2/c2t, `PhysicsDirectSpaceState3D.intersect_ray` against the instance colliders: moved house hits at the new place and not at the old, removed none, added hits, scale 2 hits 6 m off centre while scale 1 does not, trunk capsule moves/rotates/scales (radius 0.16 vs 0.32 m) |
| EW02C-04 navmesh | PASS | RT c3: one batched async rebake per move (not a full re-centre); nearest walkable point to the footprint centre: 4.8 m before (blocked), 0.0 after the house moved away, 5.0 at the new place, 0.0 after removal |
| EW02C-05 line of fire | PASS | RT c4: `LineOfFire.trace` blocker `tree` at the new place only, `range` at the old; removed none; added blocks; the cell cache is dropped on change |
| EW02C-06 scatter protection | PASS | `tools/test_world_overrides.gd`: a blocked scatter leaves every file in the directory byte-identical, the consent flag is not left on, overrides intact |
| EW02C-07 no world data changed | PASS | manifest OK before and after all runs; `ref_20km.tscn` identical; no `WorldObjectSelection` in the scene |
| EW02C-08 no automatic flatten | PASS | GUI: the road connector history shows no `Flatten terrain under roads`; scene tab not dirty after opening and after all operations |
| EW02C-09 runtime without plugin | PASS | RT c1/c2/c4 in a project copy with `world_edit` disabled (the game never loads editor plugins anyway) |

Regression: `--integration03-test --only catalog,views` PASS (twice). `catalog,base,base_nav,views` failed once on `views`
("damaging_shots 1, damage_events 0", combat shot randomness; `base`/`base_nav` were fine) and passed on the identical rerun. I take it as flaky
but did not prove it was flaky before this work. Synthetic suite and `test_world_overrides_ref.gd` PASS.

## 7. Parity details

Same code path for editor and game (`VegetationStreamer` + the override file). Compared after the GUI session wrote its file:
`effective_sha b890bb12...` (7x7 cells around the edits), `displayed_sha 13cfa339...`, LOD map of the edited meshes, override file `d773ea7c...`: all equal.
Per-object id/transform/mesh/colour equality follows from the identical effective-data digest (it contains the 16 floats of every instance).

## 8. Screenshots (real editor, `docs/ew02/`)

`p1_02_tree_selected.png`, `p1_05_house_moved.png`, `p1_06_added_objects.png`, `p2_02_house_after_restart.png` (after the editor restart).

## 9. Reproduce

Runtime: `FRACTURED_WORLD_OVERRIDES=<scratch.json> Godot --headless --path . res://scenes/game/world_ref_20km.tscn -- --ew02-test [--only c1,c2,c2t,c3,c4,b6,parity] [--ew02-digest=<gui_digest.json>]`.
GUI: copy the project and `worlds/ref_20km` to a scratch folder, enable `res://tools/ew02_acceptance/gui_probe/plugin.cfg` there only, run the editor with
`FRACTURED_WORLD_OVERRIDES`, `EW02_OUT`, `EW02_PHASE=1`, then `=2` (fresh editor). Benchmark: `tools/bench_world_overrides.gd -- new|old` (the `old` layer copy is not in the repository).

## 10. Known limitations

- **The real gizmo drag was not driven**: synthetic OS-level mouse events did not move Godot's gizmo handles (`gizmo_real_mouse_drag moved_m = 0`).
  Moves were made by setting the proxy transform, which goes through the same auto-apply path. The step that takes Godot's own scene-history
  gizmo entry back (so the scene does not look modified) was tested with an action of the same kind (`Translate`), not with the real gizmo; its
  action-name list (`GIZMO_ACTIONS`) is an assumption about Godot's labels. The scene-dirty indicator was read from the scene tab title, and it
  did not turn dirty even right after the simulated action, so that check is weak evidence.
- Selection is by nearest visible surface: in dense forest a click on a trunk behind foliage selects the foliage tree in front.
  Test trees were chosen isolated for that reason. Only library instances (trees, rocks, houses ...), not grass or Terrain3D painting.
- Collision, line of fire and navmesh use the library's simple shapes (house = sphere r 4 m x scale, 8.4 m square navmesh obstruction), not the building mesh.
- The override file is one file per world, with no merge tooling. A generator re-run changes chunk hashes and makes generated records unresolved
  (reported, not migrated); there is no migration workflow.
- Revision detection granularity is 1 s and relies on mtime/size to *notice* an external change (section 4).
- The toolbar is wide and clips in a small editor window.
- `--ew02-test` in a debug run reported leaked RIDs at engine shutdown and once a segmentation fault at exit (results are written before).

## 11. Outstanding

- Drive the real gizmo (or replace it with plugin-owned handles) and verify the dirty-scene behaviour with it.
- Optional: a soldier-level (SoldierBody) walk around a moved house; the navmesh itself is verified.
- Optional: migration of overrides after a re-scatter; generator-emitted persistent instance ids.
- Optional: picking that sees through foliage cards; multi-selection and duplicate.

## Commits

`efca115` (revision cache, runtime test, plugin workflow, wiring fixes) and the acceptance/documentation commit after it (see `git log`).

---

# Appendix: EDITOR-WORLD-02 investigation log (phases A and prototype, kept as history)

## Status and architectural decision

**Partially complete.** The existing chunks do not contain persistent instance identities or
provenance. Some instances may also have been baked from Terrain3D painting, while a
full scatter replaces the chunk set. Consequently, neither an array index nor a hash of
the original record can guarantee that an override still refers to the same object after
the generator changes or a re-scatter. A missing match must never silently edit a
different object. This is an identity and migration conflict that must be resolved before
implementing the requested regeneration-safe editing workflow. The product owner has now
approved a baseline-bound identity strategy with unresolved records after a mismatch.

The worktree was clean on `develop` at `14b6b86`; NAV-PERF-01A is committed. No world
data was changed or regenerated. Manifest verification with the bundled Python passed:
535 files checked, none missing, changed or extra (editor metadata excluded).

## Implemented safeguard

Scatter now refuses to replace existing vegetation chunks unless the builder's
`allow_replace_existing_vegetation` is explicitly enabled; the consent is consumed on
scatter. This protects potentially painted instances by default, but does not migrate
them or make a permitted scatter non-destructive. Back up and review chunks before
enabling it. Godot's `--check-only` accepted `world_builder.gd`; no functional scatter
test has been run. A headless editor launch encountered sandbox restrictions on Godot's
settings directories and a Terrain3D editor error, so it was not a successful editor test.

## Existing data flow

- `WorldBuilder` scatters by 128 m cell and writes 1024 m `VegetationChunk` resources.
  Each cell maps a library mesh ID to packed 16-float transform and color records. There
  is no per-instance ID. `bake_painted_instances` can append painted instances to the
  same format, without recording their origin.
- `ReferenceWorldBuilder._plan_props` derives houses, barns, sheds and roadside props
  from `sites.json`, roads and terrain, and appends them to those same vegetation cells.
  They are static world instances, not gameplay construction records. Placement uses a
  seeded sequential RNG; changed inputs or generation logic can change later records.
- `VegetationLibrary` maps mesh IDs to definitions, meshes, LOD ranges and collider
  specifications. `VegetationStreamer` loads chunks near observers, displays one
  MultiMesh per cell and mesh, and changes meshes for LOD. Editor and runtime share it.
- `get_cell_instances` supplies effective instances to `InstanceColliderStreamer`,
  `StructureManager`, navigation and line-of-fire. Construction clearings filter both
  rendering and queries; change signals invalidate dependent caches. Any override must
  update all these consumers, including both source and destination cells on a move.
- Player-built structures belong to `WorldState.construction` and `StructureManager`;
  they have gameplay state and must remain separate from static editor placements.
- `sites.json` describes settlement locations and generator inputs, not individual house
  identities. The world manifest records checksums for the canonical source and generated
  files; it is not an instance identity registry.

## Recommended direction

Use a separate versioned override layer with unique IDs for manual additions and a
spatial index of effective records by destination cell. For existing records, capture a
baseline locator (chunk, cell, mesh, record fingerprint and occurrence) and a baseline
world fingerprint. Resolve it only when the fingerprint matches; report missing or
ambiguous matches and never apply them to a guessed replacement. Persist sufficient
original data to support an explicit migration or recovery workflow. Generator changes
need durable IDs emitted by the generator or a reviewed reconciliation step; the present
data cannot establish identity across arbitrary changes by itself. Define the intended
behaviour for previously painted instances before allowing a destructive re-scatter.

Apply the effective cell view once in the streamer for rendering and queries, including
cells with additions but no original chunk. Invalidate source and destination cells in
collider, navigation and line-of-fire caches. A temporary editor selection proxy and
Godot's undo/redo can manipulate the same override records; do not persist proxy nodes.
These are design recommendations, not implemented or tested functionality.

## Roads and terrain

`roads.json` feeds both `RoadNetwork` at runtime and generated RoadPoints, while the
scene contains the Road Generator representation. Editing only RoadPoints therefore
does not update the runtime road source. The Terrain3D road connector can modify terrain,
including automatically when auto-refresh is enabled. A future road workflow needs an
explicit authoritative-source and synchronization decision, a backup and manifest
verification, and controlled terrain updates; no roads or terrain were edited here.

## Vertical prototype (in progress)

`world_overrides.gd` now contains an experimental versioned JSON layer with generated
locators bound to SHA-256 hashes of their source chunks, and random IDs for additions.
`VegetationStreamer` uses an effective-cell view for its query and render buffers and
invalidates affected cells. These changes are incomplete and must not be considered
ready for editing or deployment.

The original color failure was in `effective`: it constructed the moved record using
`Color.WHITE`, replacing the source record's color. The correction loads the source
record at its baseline-bound locator and copies every packed attribute after the 12
transform floats into the replacement. Suppression no longer uses alpha as a marker.
`get_cell_instances` returns mesh IDs and transforms; the MultiMesh path receives the
full effective buffer, while LOD switches only the mesh.

The isolated headless test `tools/test_world_overrides.gd` uses synthetic resources in
`.godot/ew02_test`. It passes full-record comparison for a moved tree, MultiMesh buffer
and LOD switches, save/reload, a streamer unload/reload, tree and house cell queries,
addition, removal and restoration. It exercises collider-streamer rebuilding, trunk
queries, line-of-fire cache invalidation and hits, navigation obstruction generation,
and scheduling a navmesh rebake. It also verifies that a changed synthetic source is
unresolved and a manual addition remains, and that scatter refuses to overwrite a
synthetic existing chunk. The scatter refusal emits expected error messages. The test
does not establish full rendered-world or editor/runtime parity, physics contact, an
actual navmesh rebake, or performance with many overrides.

`--integration03-test --only catalog,views` on the actual `ref_20km` runtime reported
`WI03 PASS`; it ran with no override file, so it is a regression only, not an override
parity test. Headless exit reported resource leaks. No visual editor test was performed.

## Verification and remaining work

No editor tool or full acceptance tests have been completed.
The milestone must not be reported as passed. The prototype repeatedly hashes source
chunks to detect changes; its performance needs measurement and improvement before use
at scale. Finish validating the vertical prototype before proceeding to editor work.

## Follow-up: hash cost and real-world data

On the local machine, `tools/bench_world_overrides.gd` measured 100 cell queries with
100 generated overrides in the 995,246-byte `veg_-1_-1.res` chunk at approximately
405 ms before this follow-up and 429 ms with the current correctness-first code (single
runs, not a statistical benchmark). Validating only records relevant to the requested
cell did not produce a demonstrated improvement in this workload. A trial cache based
only on Godot's modification time and file size was removed: unchanged metadata cannot
prove that the contents are unchanged, so it could silently apply overrides to changed
source data. SHA-256 is currently cached only within a single operation, and is still
recomputed on subsequent relevant cell reads. The requested persistent safe cache and
performance target remain unfinished.

`tools/test_world_overrides_ref.gd` uses the real `ref_20km` chunk near Haugen with an
isolated file in `.godot/ew02_ref_overrides.json`. It passed programmatic move, remove,
restore, add, save/reload, MultiMesh-buffer lookup and solid-instance lookup for a real
tree (mesh 1) and house (mesh 16). This is not a GUI test, a physical collision test, or
an editor/runtime parity test. It did not modify generated chunks. The synthetic suite
also passed after the change. No editor tool or visual acceptance operation is implemented.

## Editor tool prototype (2026-10-23)

An experimental editor plugin is present in `addons/world_edit` but is deliberately
not enabled in `project.godot`: its interactive behavior has not been verified. It
contains object picking, a temporary transform proxy, a library selector and record
operations using editor undo history. Its GDScript passes `--check-only`; this does
not establish that selection, transform gizmos, undo/redo, persistence, or runtime
parity work. In particular it still needs an isolated override-file workflow and real
interactive testing before it is safe to expose as a finished editor tool.

The connected editor had both `ref_20km` and `world_ref_20km` open with unsaved
scene changes. The existing session did not discover the new plugin during this
attempt, and restarting it would have put those unsaved changes at risk. A separate
headless editor attempt could not load Terrain3D (dynamic-library copy failed) and
could not access Godot's editor data directories; it was stopped before scene loading
completed. Neither attempt verifies the plugin or editor/runtime parity. No scene was
saved or closed, and no test overrides were written to the normal world override file.

The synthetic suite and `test_world_overrides_ref.gd` both passed again. The former
emitted its expected scatter-refusal errors; both reported environment log/certificate
access errors. The reference test remains a programmatic data/buffer test, not an
interactive or physical collision test. The manifest verification actually ran using
the bundled Python and reported `VERIFY ref_20km OK: 540 files checked, 0 missing,
0 changed, 0 extra`. Persistent safe hash caching, its after-measurement, full GUI
operations, actual collision/navigation/line-of-fire verification, and editor/runtime
parity remain open. No commit or push was made.

## Fresh editor attempt (2026-10-23)

A normal Godot editor was launched with `world_edit` enabled and
`FRACTURED_WORLD_OVERRIDES` pointing to the isolated
`.godot/ew02_gui_overrides.json` path, inherited by a game launched from that
editor. The World objects toolbar appeared. The earlier Terrain3D temporary DLL
copy prevented startup; its bytes matched the source DLL and the temporary copy
was preserved in `.godot/ew02_editor_profile/terrain-library-backup.dll` before
starting the fresh editor with a separate editor profile.

The editor automatically reopened `ref_20km.tscn`. Its tab became marked as
unsaved during startup, before any test manipulation or scene save. The session
was left open and testing stopped at the user's instruction to stop on unsaved
changes or data-loss risk. The origin and content of this scene modification are
not yet established; it must not be saved or discarded without investigating it.
No visual object manipulation, override-file save, editor restart, runtime parity,
physical collision, navigation, line-of-fire, or new hash-cache benchmark was
verified in this attempt. The editor plugin is enabled for the test session and its
project configuration change remains uncommitted. No world chunks were modified.

## Editor restart blocked (2026-10-23)

The connected Godot session still has `ref_20km.tscn` open with an unsaved
indicator. A request to quit the editor was rejected by the automatic approval
review because unsaved scene state could be lost and the instruction requires
stopping before discarding it. The editor was not closed and the scene was not
saved or reloaded. No editor/runtime acceptance test was executed in this attempt.

## Fresh editor terrain warning (2026-10-23)

After the user confirmed the prior scene changes were discarded, a new normal
editor was launched with `FRACTURED_WORLD_OVERRIDES` set to the isolated test
file. `ref_20km` reopened automatically, became marked unsaved, and the Output
displayed `Flatten terrain under roads` before any object test. In
`terrain3d_road_connector.gd`, this is the name of an undo action created when
height maps differ after terrain processing. This is evidence of a possible
in-memory terrain modification during editor startup, not proof that it was
written to disk. The editor remains open and the scene has not been saved,
closed, or manipulated further. The requested stop condition for data-loss or
terrain-change risk applies. No object GUI or runtime acceptance test was run.
The manifest verification ran after startup and reported `VERIFY ref_20km OK:
540 files checked, 0 missing, 0 changed, 0 extra`; this verifies disk files,
not the in-memory terrain state.

## Startup terrain flattening: cause and fix (2026-10-23)

**Cause.** `RoadTerrain3DConnector.auto_refresh` defaulted to `true` and `ref_20km.tscn` does not
store it, so the connector listened to `RoadManager.on_road_updated` in the editor. After a scene
opens, the ~hundreds of `RoadContainer`s rebuild their segments and each emits that signal. The
connector's `_skip_scene_load` flag only swallowed the *first* one; every later one queued
`refresh_roads()`, which ran in `_physics_process`, flattened the height maps through
`set_height_if_active_region`, and `_add_terrain_undo` then created the
`Flatten terrain under roads` action.

**The four things the brief asks us to separate**
1. *Undo action created*: yes, but `_add_terrain_undo` only creates it when the height data differs
   before/after flattening.
2. *Height map changed in memory*: yes, by implication. The action cannot exist otherwise, and on an
   isolated copy a manual flatten changed 66 of 100 regions. The size of the startup change in the
   user's session was not measured; that session's state could not be inspected safely (the
   godot-ai MCP connection was closed), so it was left untouched.
3. *Scene dirty*: yes, the undo entry marks the scene unsaved.
4. *Written to disk*: no. Terrain3D writes regions on scene save. The manifest of the canonical
   `ref_20km` verifies OK (540 files, 0 changed; 535 with `--ignore-editor-metadata`).
   Consequence: **a live editor session that opened the world with the old code must never save the
   scene**; the in-memory terrain there is flattened (bridge channels refilled).

**Fix** (`addons/road-generator/connectors/terrain3d_road_connector.gd`, only file changed):
- `auto_refresh` now defaults to `false`.
- New `_auto_refresh_armed`: the road-update/transform signals are connected only if
  `auto_refresh and _auto_refresh_armed`. Armed only when `auto_refresh` is switched on *after* the node
  is ready, so a value stored in a scene is ignored during load.
- Unchanged: the `Refresh` inspector button and `do_full_refresh()` (used by `WorldBuilder.flatten_roads`),
  roads rendering, runtime. Nothing in `ref_20km` or other world data was edited.

**Manual flattening still works.** Press `Refresh` on `Roads/Terrain3DRoadConnector`, or enable
`auto_refresh` in the inspector for live flattening while editing roads. Do this only in an isolated
scene with copied terrain data, never in canonical `ref_20km`.

**Tests** (isolated copy in the session scratchpad: full project copy + a copy of `worlds/ref_20km`; probe
EditorPlugin opens the scene in a real editor, waits, reads the undo history and hashes region heights):
| Run | auto_refresh | signal connected | action after load | manual Refresh |
|---|---|---|---|---|
| old code, `ref_20km` copy | true | yes | `Flatten terrain under roads` (history v2) | n/a (stopped) |
| old code, `test_2km` | true | yes | none (too few containers to hit it) | action + 4/4 regions changed |
| fixed code, `ref_20km` copy | false | no | none (history v1, same as any scene open) | action + 66/100 regions changed |
Canonical world manifest: OK before and after. Not re-run: a game runtime test (the change does not touch
runtime code paths; the connector returns early outside the editor).

**Remaining risks / open.** The user's already-open editor still holds the old in-memory state: close it
and discard (do not save), then reopen. The `world_edit` features (selection, move/rotate, undo, save/reopen,
editor/runtime parity, collision/streaming, hash caching) were not advanced in this step; the earlier
notes above still stand. Other scenes saved with `auto_refresh = true` would now be ignored on load
until toggled (intended).

## world_edit acceptance in an isolated editor (2026-10-23)

Run in a full project copy with a copy of `ref_20km` (scratchpad; canonical project and world untouched),
real Godot 4.7.2 editor, `world_edit` enabled, probe in `tools/ew02_acceptance/`:
- Editor camera moved over a real house near Haugen (`g:-14:-36:16:0`); the **real input path**
  (`_forward_3d_gui_input` with a left click at the house's screen position) selected the house (distance 0 m).
- Moved 20 m and rotated 30° through the proxy + `Apply transform`: record present at the destination, gone
  at the source, MultiMesh buffer of the destination cell contains the moved transform.
- Editor undo restored the original, redo re-applied; no terrain action appeared (`Flatten terrain under roads`
  absent) and the world overrides save wrote `worlds/ref_20km.overrides.json` (isolated copy).
- Runtime parity: a fresh `VegetationStreamer` (runtime code) reading the saved file reports the moved house,
  no source house, 0 unresolved records, and `InstanceColliderStreamer` places its collision shapes at the
  new position (2 near the new place; 0 near the old place with the override, 1 without it; a horizontal ray
  through the new house hits).
- All vegetation chunk files byte-identical before and after (combined SHA-256 unchanged); canonical manifest OK.
- Interpretation of "picking": by ray against the mesh AABB of loaded chunks, not by a physical click on
  mesh triangles.

**Not verified / open:** tree selection and Add/Remove/Restore through the GUI were not driven (only the house
move path; the synthetic and ref tests cover tree data paths); a navmesh rebake and line-of-fire were verified only
in the synthetic suite, not on `ref_20km`; the persistent safe chunk-hash cache (item 7) is **not implemented**
(a cache keyed on mtime/size was rejected as unsafe; a content-safe design needs generator-emitted chunk
versions); the scene reopen path was checked by reading the saved file in a fresh runtime streamer, not by
closing/reopening the scene in the editor.

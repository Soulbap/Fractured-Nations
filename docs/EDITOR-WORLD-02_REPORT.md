# EDITOR-WORLD-02 — phase A investigation (implementation not started)

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

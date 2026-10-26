## Camera-local activation of stored vegetation (trees, bushes, rocks).
##
## Vegetation is stored as VegetationChunk files (1024 m chunks of 128 m cells, see
## worlds/<name>/vegetation/). Nothing exists in the scene for the whole map. Each frame
## the streamer looks at the active camera (and optional extra observers), loads the
## chunks around them on a background thread, and keeps one MultiMeshInstance3D per
## (cell, mesh type) within that mesh type's range. Cells beyond the range are freed.
## LODs: the full mesh inside near_range, the cheapest mesh of the asset beyond it (trees:
## a mid mesh up to mid_range between them), switched by swapping the MultiMesh mesh (no
## re-upload; WORLD-VISUALS-01 variants rebuild their per-variant MultiMeshes). Activations are spread over
## frames (activations_per_frame, nearest first) so camera jumps do not stall.
##
## Not a general streaming framework: it only knows vegetation chunks and observers.
## Runs in the editor too, following the editor camera.
@tool
class_name VegetationStreamer
extends Node3D

const WorldOverrides = preload("res://scripts/vegetation/world_overrides.gd")

## Emitted when construction clearings changed the instances of these cells (colliders
## and other caches of get_cell_instances must re-read them).
signal clearings_changed(cells: Array)

@export var enabled := true:
	set(v):
		enabled = v
		if not v:
			_deactivate_all()
		_dirty = true
## Directory with veg_<x>_<z>.res chunk files.
@export var data_directory := "res://worlds/test_2km/vegetation"
@export var library: VegetationLibrary
## Must match the chunk data (WorldBuilder writes the same values).
@export var chunk_size_m := 1024.0
@export var cell_size_m := 128.0
## Observers besides the current camera (e.g. a selected unit).
@export var extra_observers: Array[Node3D] = []
## Re-evaluate cells after an observer moved this far.
@export var observer_move_threshold_m := 8.0
## (cell, mesh) activations per frame; the rest waits in a nearest-first queue.
@export var activations_per_frame := 24
## Loaded chunks are kept this far beyond the activation range before unloading.
@export var chunk_keep_margin_m := 600.0
## Relative hysteresis for the near/far LOD switch.
@export var lod_hysteresis := 0.15
## PERFORMANCE-01: cells leaving the range are hidden at once and freed at most this many per frame (more when the queue is long:
## it always empties within release_frames frames). A cell wanted again before it is freed is shown again instead of rebuilt.
@export var releases_per_frame := 8
@export var release_frames := 30
## PERFORMANCE-01: chunks the loader finished are taken into use at most this many per frame (storing one places its instances on
## the eased terrain and hashes it for the overrides: ~2-4 ms), and far chunks are unloaded at most this many per frame. After a
## camera jump 11-13 chunks finished in the same frame and 12-15 were unloaded in it: frames of 54-86 ms.
@export var stores_per_frame := 2
@export var unloads_per_frame := 2

## Vector3i(cell.x, cell.y, mesh_id) -> MultiMeshInstance3D
var active := {}
var active_lod := {}
## Cleared areas (WORLD-INTEGRATION-01, construction footprints): Vector2i cell ->
## Array of [center: Vector2, axis_x: Vector2, axis_z: Vector2, half: Vector2, ids: Dictionary].
## Instances of those mesh ids inside a rectangle are skipped by activation and by
## get_cell_instances. The chunk files are never changed; the rectangles are game state.
var clearings := {}
## Vector2i chunk location -> VegetationChunk
var chunks := {}
var overrides: RefCounted

var _missing := {}
var _loading := {}
## Chunks that must be read from disk again (their file changed): bypass the resource cache.
var _fresh := {}
var _queue: Array = []
var _queue_pos := 0
var _last_obs: Array[Vector3] = []
var _dirty := true
## Worst CPU time spent activating cells in one frame since the last get_stats().
var _worst_drain_ms := 0.0
## PERFORMANCE-01: lifecycle counters (cumulative; tests and the profiler read them).
var counters := {"chunk_loads": 0, "chunk_unloads": 0, "cells_activated": 0, "cells_freed": 0, "free_us": 0, "free_us_max_frame": 0,
	"unload_us": 0, "cells_reused": 0, "release_queue_max": 0, "store_us": 0, "store_us_max": 0, "unloads_cancelled": 0}
## Chunks waiting to be unloaded (Vector2i -> true), at most unloads_per_frame a frame; cancelled when wanted again.
var _unload_pending := {}
## PERFORMANCE-01: hidden cells waiting to be freed: [key, MultiMeshInstance3D] in order, and key -> instance for the ones that may
## be shown again (left the range by camera movement; data unchanged). Freed by _drain_release.
var _release: Array = []
var _release_pos := 0
var _reusable := {}
## --veg-immediate-free: the old behaviour (every leaving cell freed in the same frame), for comparisons only.
var _immediate_free := false
## --veg-no-variants: every instance draws variant 0 (WORLD-VISUALS-01 comparisons only).
var _no_variants := false


func _ready() -> void:
	top_level = true
	_immediate_free = "--veg-immediate-free" in OS.get_cmdline_user_args()
	_no_variants = "--veg-no-variants" in OS.get_cmdline_user_args()
	_init_overrides()
	# Instantiate the mesh assets now, not during the first activation.
	if library:
		for d in library.meshes:
			d.lod_count()


func _process(_delta: float) -> void:
	if not enabled or library == null:
		return
	_poll_loading()
	if overrides:
		overrides.poll()
	var obs := _observer_positions()
	if obs.is_empty():
		return
	if _dirty or _moved(obs):
		_last_obs = obs
		_dirty = false
		_update_sets(obs)
	_drain_queue()
	_drain_release()
	_drain_unloads()


## Forces a full re-evaluation on the next frame (e.g. after data changed).
func refresh() -> void:
	_dirty = true


func _init_overrides() -> void:
	if overrides == null:
		var world_dir := data_directory.get_base_dir()
		var override_path := OS.get_environment("FRACTURED_WORLD_OVERRIDES")
		if override_path.is_empty():
			override_path = world_dir.get_base_dir().path_join(world_dir.get_file() + ".overrides.json")
		overrides = WorldOverrides.new(self, override_path)
		# WORLD-SETTLEMENT-02: the settlements' removals and buildings, a layer under the user's overrides.
		overrides.layer_path = SettlementLayer.overrides_path(world_dir.get_file())
		# WORLD-COVER-01: the natural cover layer (boulders, logs, root plates, stone walls, timber), generated by CoverLayer.
		if CoverLayer.enabled():
			overrides.extra_layers.append(CoverLayer.path(world_dir.get_file()))
		overrides.load_file()


## Unloads one chunk (and its active cells). It is read again, and its override baseline
## rehashed, the next time it is needed.
func unload_chunk(loc: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	if chunks.has(loc):
		counters.chunk_unloads += 1
	for key in active.keys():
		if VegetationChunk.chunk_of(Vector3(key.x * cell_size_m, 0, key.y * cell_size_m), chunk_size_m) == loc:
			_deactivate(key)
	if chunks.erase(loc) and overrides:
		overrides.on_chunk_unloaded(loc)
	counters.unload_us += Time.get_ticks_usec() - t0


## The chunk file changed on disk: drop the loaded copy and bypass the resource cache on the next read.
func reload_chunk(loc: Vector2i) -> void:
	_fresh[loc] = true
	if _loading.has(loc):
		ResourceLoader.load_threaded_get(_loading[loc])
		_loading.erase(loc)
	unload_chunk(loc)
	_dirty = true


func overrides_changed(cells: Array) -> void:
	for key in active.keys():
		if cells.has(Vector2i(key.x, key.y)):
			_deactivate(key)
	_dirty = true
	clearings_changed.emit(cells)


func _effective_cell(cell: Vector2i) -> Dictionary:
	_init_overrides()
	var loc := VegetationChunk.chunk_of(Vector3(cell.x * cell_size_m, 0, cell.y * cell_size_m), chunk_size_m)
	var ch := get_chunk_sync(loc)
	var original: Dictionary = ch.cells.get(cell, {}) if ch else {}
	return overrides.effective(cell, original)


func get_stats() -> Dictionary:
	var inst := 0
	var cells := {}
	for key in active:
		var mmi: MultiMeshInstance3D = active[key]
		inst += mmi.multimesh.instance_count
		for c in mmi.get_children(true):
			inst += (c as MultiMeshInstance3D).multimesh.instance_count
		cells[Vector2i(key.x, key.y)] = true
	var out := {"active_mmis": active.size(), "active_cells": cells.size(), "active_instances": inst,
		"loaded_chunks": chunks.size(), "loading_chunks": _loading.size(),
		"queued": maxi(_queue.size() - _queue_pos, 0), "worst_activation_ms": snappedf(_worst_drain_ms, 0.01),
		"release_queued": maxi(_release.size() - _release_pos, 0), "reusable": _reusable.size(), "unload_pending": _unload_pending.size(),
		"loaded_waiting": _loading.size()}
	_worst_drain_ms = 0.0
	return out


func is_settled() -> bool:
	return _loading.is_empty() and _queue_pos >= _queue.size()


## Replaces all clearings (list of [center, axis_x, axis_z, half, ids]); re-activates the
## affected cells with the filtered instances.
func set_clearings(list: Array) -> void:
	var by_cell := {}
	var cs := cell_size_m
	for r in list:
		var c: Vector2 = r[0]
		var reach: float = (r[3] as Vector2).length()
		var c0 := VegetationChunk.cell_of(Vector3(c.x - reach, 0, c.y - reach), cs)
		var c1 := VegetationChunk.cell_of(Vector3(c.x + reach, 0, c.y + reach), cs)
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var cell := Vector2i(cx, cz)
				if not by_cell.has(cell):
					by_cell[cell] = []
				by_cell[cell].append(r)
	var changed := []
	for cell in by_cell:
		if not clearings.has(cell) or clearings[cell] != by_cell[cell]:
			changed.append(cell)
	for cell in clearings:
		if not by_cell.has(cell):
			changed.append(cell)
	clearings = by_cell
	if changed.is_empty():
		return
	var lookup := {}
	for cell in changed:
		lookup[cell] = true
	for key in active.keys():
		if lookup.has(Vector2i(key.x, key.y)):
			_deactivate(key)
	_dirty = true
	clearings_changed.emit(changed)


## Instance buffer of one (cell, mesh) without the cleared instances (the stored buffer
## itself when nothing there is cleared).
func _filtered(cell: Vector2i, mesh_id: int, buf: PackedFloat32Array) -> PackedFloat32Array:
	var rects: Array = clearings.get(cell, [])
	if rects.is_empty():
		return buf
	var fpi := VegetationChunk.FLOATS_PER_INSTANCE
	var out := PackedFloat32Array()
	for i in buf.size() / fpi:
		var o := VegetationChunk.instance_transform(buf, i).origin
		var p := Vector2(o.x, o.z)
		var cleared := false
		for r in rects:
			if not r[4].has(mesh_id):
				continue
			var d: Vector2 = p - r[0]
			if absf(d.dot(r[1])) <= r[3].x and absf(d.dot(r[2])) <= r[3].y:
				cleared = true
				break
		if not cleared:
			out.append_array(buf.slice(i * fpi, (i + 1) * fpi))
	return out


## Instances of one cell as [mesh_id, Transform3D] pairs; loads the chunk synchronously.
## Used by InstanceColliderStreamer, which needs data immediately around the player.
func get_cell_instances(cell: Vector2i, mesh_ids: Array) -> Array:
	var out := []
	var by_mesh := _effective_cell(cell)
	for mesh_id in mesh_ids:
		if not by_mesh.has(mesh_id):
			continue
		var buf := _filtered(cell, mesh_id, by_mesh[mesh_id])
		for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
			out.append([mesh_id, VegetationChunk.instance_transform(buf, i)])
	return out


func get_chunk_sync(loc: Vector2i) -> VegetationChunk:
	if chunks.has(loc):
		return chunks[loc]
	if _missing.has(loc):
		return null
	var path := _chunk_path(loc)
	if _loading.has(loc):
		_loading.erase(loc)
		_store_chunk(loc, ResourceLoader.load_threaded_get(path))
		return chunks.get(loc)
	if not ResourceLoader.exists(path):
		_missing[loc] = true
		return null
	var mode := ResourceLoader.CACHE_MODE_REPLACE if _fresh.erase(loc) else ResourceLoader.CACHE_MODE_REUSE
	_store_chunk(loc, ResourceLoader.load(path, "", mode))
	return chunks.get(loc)


# ------------------------------------------------------------------------------

func _observer_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cam: Camera3D = null
	if Engine.is_editor_hint():
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			var vp: SubViewport = ei.get_editor_viewport_3d(0)
			if vp:
				cam = vp.get_camera_3d()
	elif is_inside_tree():
		cam = get_viewport().get_camera_3d()
	if cam:
		out.append(cam.global_position)
	for o in extra_observers:
		if o and o.is_inside_tree():
			out.append(o.global_position)
	return out


func _moved(obs: Array[Vector3]) -> bool:
	if obs.size() != _last_obs.size():
		return true
	var t2 := observer_move_threshold_m * observer_move_threshold_m
	for i in obs.size():
		if obs[i].distance_squared_to(_last_obs[i]) > t2:
			return true
	return false


func _chunk_path(loc: Vector2i) -> String:
	return data_directory.path_join(VegetationChunk.file_name(loc))


func _store_chunk(loc: Vector2i, res: Resource) -> void:
	var ch := res as VegetationChunk
	if ch == null:
		_missing[loc] = true
		return
	if not is_equal_approx(ch.cell_size_m, cell_size_m) or not is_equal_approx(ch.chunk_size_m, chunk_size_m):
		push_warning("VegetationStreamer: chunk %s has cell %.0f m / chunk %.0f m, streamer expects %.0f / %.0f" % [
			loc, ch.cell_size_m, ch.chunk_size_m, cell_size_m, chunk_size_m])
		cell_size_m = ch.cell_size_m
		chunk_size_m = ch.chunk_size_m
	RoadShoulders.fix_chunk(ch)  # GAMEPLAY-04A: instances on the eased road shoulders back on the ground
	chunks[loc] = ch
	counters.chunk_loads += 1
	if overrides:
		overrides.on_chunk_loaded(loc)
	_dirty = true


func _request_chunk(loc: Vector2i) -> void:
	if chunks.has(loc) or _missing.has(loc) or _loading.has(loc):
		return
	var path := _chunk_path(loc)
	if not ResourceLoader.exists(path):
		_missing[loc] = true
		return
	var mode := ResourceLoader.CACHE_MODE_REPLACE if _fresh.erase(loc) else ResourceLoader.CACHE_MODE_REUSE
	if ResourceLoader.load_threaded_request(path, "", false, mode) != OK:
		_missing[loc] = true
		return
	_loading[loc] = path


func _poll_loading() -> void:
	var stored := 0
	for loc in _loading.keys():
		var path: String = _loading[loc]
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				if stored >= stores_per_frame and not _immediate_free:
					continue  # PERFORMANCE-01: the rest next frame (it stays loaded in the loader)
				stored += 1
				_loading.erase(loc)
				var t0 := Time.get_ticks_usec()
				_store_chunk(loc, ResourceLoader.load_threaded_get(path))
				var us := Time.get_ticks_usec() - t0
				counters.store_us += us
				counters.store_us_max = maxi(counters.store_us_max, us)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_loading.erase(loc)
				_missing[loc] = true
				push_warning("VegetationStreamer: failed to load " + path)


func _update_sets(obs: Array[Vector3]) -> void:
	var r := library.max_range()
	var cs := cell_size_m
	# Chunks around the observers; unload the ones that drifted far away.
	var wanted := {}
	for o in obs:
		var c0 := VegetationChunk.chunk_of(o - Vector3(r, 0, r), chunk_size_m)
		var c1 := VegetationChunk.chunk_of(o + Vector3(r, 0, r), chunk_size_m)
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				wanted[Vector2i(cx, cz)] = true
	for loc in wanted:
		_request_chunk(loc)
		if _unload_pending.erase(loc):
			counters.unloads_cancelled += 1
	for loc in chunks.keys():
		if not wanted.has(loc) and _square_distance(obs, Vector2(loc) * chunk_size_m, chunk_size_m) > r + chunk_keep_margin_m:
			if _immediate_free:
				unload_chunk(loc)
			else:
				_unload_pending[loc] = true

	# Desired (cell, mesh) set with distances.
	var desired := {}
	for loc in chunks:
		var ch: VegetationChunk = chunks[loc]
		for cell: Vector2i in ch.cells:
			var by_mesh: Dictionary = ch.cells[cell]
			var d := _cell_distance(obs, cell, by_mesh)
			if d > r:
				continue
			for mesh_id in by_mesh:
				var def := library.get_def(mesh_id)
				if def == null or d > def.max_range + def.fade_m:
					continue
				desired[Vector3i(cell.x, cell.y, mesh_id)] = d
	# Override destinations can be in cells or chunks with no generated records.
	_init_overrides()
	for cell in overrides.affected_cells():
		if _square_distance(obs, Vector2(cell) * cs, cs) > r:
			continue
		var by_mesh := _effective_cell(cell)
		for mesh_id in by_mesh:
			if by_mesh[mesh_id].is_empty():
				continue
			var def := library.get_def(mesh_id)
			var d := _cell_distance(obs, cell, by_mesh)
			if def and d <= def.max_range + def.fade_m:
				desired[Vector3i(cell.x, cell.y, mesh_id)] = d

	for key in active.keys():
		if not desired.has(key):
			_deactivate(key, true)
	_queue.clear()
	_queue_pos = 0
	for key in desired:
		if active.has(key):
			_update_lod(key, desired[key])
		else:
			_queue.append([desired[key], key])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


## Distance from the nearest observer to a cell: horizontal distance to the cell square
## plus the height difference to the cell's first instance.
func _cell_distance(obs: Array[Vector3], cell: Vector2i, by_mesh: Dictionary) -> float:
	var cs := cell_size_m
	var y := 0.0
	for mesh_id in by_mesh:
		# Overrides can empty a buffer (every instance of that mesh removed).
		if by_mesh[mesh_id].size() > 7:
			y = by_mesh[mesh_id][7]
			break
	var best := INF
	for o in obs:
		var dx := maxf(absf(o.x - (cell.x + 0.5) * cs) - cs * 0.5, 0.0)
		var dz := maxf(absf(o.z - (cell.y + 0.5) * cs) - cs * 0.5, 0.0)
		var dy := o.y - y
		best = minf(best, sqrt(dx * dx + dz * dz + dy * dy))
	return best


func _square_distance(obs: Array[Vector3], min_corner: Vector2, size: float) -> float:
	var best := INF
	for o in obs:
		var dx := maxf(absf(o.x - (min_corner.x + size * 0.5)) - size * 0.5, 0.0)
		var dz := maxf(absf(o.z - (min_corner.y + size * 0.5)) - size * 0.5, 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


func _drain_queue() -> void:
	var n := 0
	var t0 := Time.get_ticks_usec()
	while _queue_pos < _queue.size() and n < activations_per_frame:
		var item: Array = _queue[_queue_pos]
		_queue_pos += 1
		if not active.has(item[1]):
			_activate(item[1], item[0])
		n += 1
	if _queue_pos >= _queue.size():
		_queue.clear()
		_queue_pos = 0
	if n > 0:
		_worst_drain_ms = maxf(_worst_drain_ms, (Time.get_ticks_usec() - t0) / 1000.0)


func _activate(key: Vector3i, dist: float) -> void:
	# PERFORMANCE-01: still hidden in the release queue (the camera came back): show it again.
	var back: MultiMeshInstance3D = _reusable.get(key)
	if back:
		_reusable.erase(key)
		if is_instance_valid(back):
			var d := library.get_def(key.z)
			var l := d.lod_at(dist)
			if l != int(back.get_meta("lod", l)):
				if back.has_meta("vparts"):
					_set_variant_lod(back, d, l)
				else:
					back.multimesh.mesh = d.get_mesh(l)
				_apply_lod(back, d, l)
			back.visible = true
			active[key] = back
			active_lod[key] = l
			counters.cells_reused += 1
			return
	var cell := Vector2i(key.x, key.y)
	var by_mesh := _effective_cell(cell)
	if not by_mesh.has(key.z):
		return
	var def := library.get_def(key.z)
	var buf := _filtered(cell, key.z, by_mesh[key.z])
	if buf.is_empty():
		return
	var lod := def.lod_at(dist)
	var mmi := MultiMeshInstance3D.new()
	mmi.visibility_range_end = def.max_range
	mmi.visibility_range_end_margin = def.fade_m
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if def.variant_count() > 1 and not _no_variants:
		var split := _split_variants(def, buf)
		mmi.set_meta("vparts", split[0])
		mmi.set_meta("vfull", split[1])
		_set_variant_lod(mmi, def, lod)
	else:
		mmi.multimesh = _multimesh(def.get_mesh(lod), buf)
	_apply_lod(mmi, def, lod)
	add_child(mmi, false, Node.INTERNAL_MODE_BACK)
	active[key] = mmi
	counters.cells_activated += 1
	active_lod[key] = lod


func _update_lod(key: Vector3i, dist: float) -> void:
	var def := library.get_def(key.z)
	var cur: int = active_lod[key]
	var want := def.lod_at(dist, cur, lod_hysteresis)
	if want == cur:
		return
	var mmi: MultiMeshInstance3D = active[key]
	if mmi.has_meta("vparts"):
		_set_variant_lod(mmi, def, want)
	else:
		mmi.multimesh.mesh = def.get_mesh(want)
	_apply_lod(mmi, def, want)
	active_lod[key] = want


func _apply_lod(mmi: MultiMeshInstance3D, def: VegetationMeshDef, lod: int) -> void:
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod != VegetationMeshDef.FAR and def.cast_shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = def.get_material_override(lod)
	for c in mmi.get_children(true):
		(c as GeometryInstance3D).cast_shadow = mmi.cast_shadow


func _multimesh(mesh: Mesh, buf: PackedFloat32Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = buf.size() / VegetationChunk.FLOATS_PER_INSTANCE
	mm.buffer = buf
	return mm


## WORLD-VISUALS-01: the instances of one (cell, mesh) by variant: [[buffer per variant], whole buffer with the variant in the
## colour alpha ((v + 0.5) / 8, read by shaders/environment/impostor_v3.gdshader; empty unless the far LOD is shared)].
func _split_variants(def: VegetationMeshDef, buf: PackedFloat32Array) -> Array:
	var n := def.variant_count()
	var fpi := VegetationChunk.FLOATS_PER_INSTANCE
	# Instance indices per variant first (packed arrays inside an Array are copied on access: append to locals only).
	var idx := []
	for v in n:
		idx.append([])
	var full := buf.duplicate() if def.shared_far else PackedFloat32Array()
	for i in buf.size() / fpi:
		var k := i * fpi
		var v := VegetationMeshDef.variant_of(buf[k + 3], buf[k + 11], n)
		(idx[v] as Array).append(k)
		if def.shared_far:
			full[k + 15] = (v + 0.5) / 8.0
	var parts := []
	for v in n:
		var part := PackedFloat32Array()
		for k: int in idx[v]:
			part.append_array(buf.slice(k, k + fpi))
		parts.append(part)
	return [parts, full]


## Near: one MultiMesh per variant (variant 0 on the cell's own instance, the others as internal children). Far with a shared
## far mesh: every instance in one MultiMesh again.
func _set_variant_lod(mmi: MultiMeshInstance3D, def: VegetationMeshDef, lod: int) -> void:
	for c in mmi.get_children(true):
		c.free()
	var parts: Array = mmi.get_meta("vparts")
	if lod == VegetationMeshDef.FAR and def.shared_far:
		mmi.multimesh = _multimesh(def.get_mesh(lod), mmi.get_meta("vfull"))
		return
	mmi.multimesh = _multimesh(def.get_variant_mesh(lod, 0), parts[0])
	for v in range(1, parts.size()):
		var part: PackedFloat32Array = parts[v]
		if part.is_empty():
			continue
		var child := MultiMeshInstance3D.new()
		child.multimesh = _multimesh(def.get_variant_mesh(lod, v), part)
		child.material_override = def.get_variant_override(lod, v)
		child.visibility_range_end = mmi.visibility_range_end
		child.visibility_range_end_margin = mmi.visibility_range_end_margin
		child.visibility_range_fade_mode = mmi.visibility_range_fade_mode
		mmi.add_child(child, false, Node.INTERNAL_MODE_BACK)


## A cell leaves: hidden now, freed later by _drain_release (PERFORMANCE-01: freeing every leaving cell in the frame the camera
## crossed a threshold, or a chunk unloaded, gave 40-48 ms frames). reusable: it left by camera movement and its data is unchanged,
## so it may be shown again if wanted before it is freed (clearings and override changes rebuild instead).
func _deactivate(key: Vector3i, reusable := false) -> void:
	var mmi: MultiMeshInstance3D = active[key]
	var lod: int = active_lod.get(key, 0)
	active.erase(key)
	active_lod.erase(key)
	if not is_instance_valid(mmi):
		return
	if _immediate_free:
		_free_cell(mmi)
		return
	mmi.visible = false
	mmi.set_meta("lod", lod)
	_release.append([key, mmi])
	if reusable:
		_reusable[key] = mmi
	else:
		_reusable.erase(key)
	counters.release_queue_max = maxi(counters.release_queue_max, _release.size() - _release_pos)


func _free_cell(mmi: MultiMeshInstance3D) -> void:
	var t0 := Time.get_ticks_usec()
	mmi.free()
	counters.free_us += Time.get_ticks_usec() - t0
	counters.cells_freed += 1


## PERFORMANCE-01: unloads at most unloads_per_frame of the chunks that drifted far away (a chunk wanted again meanwhile was taken
## off the list in _update_sets). The cells of a pending chunk that are beyond the range were already released with the others.
func _drain_unloads() -> void:
	var n := 0
	for loc in _unload_pending.keys():
		if n >= unloads_per_frame:
			break
		_unload_pending.erase(loc)
		if chunks.has(loc):
			unload_chunk(loc)
			n += 1


## Frees hidden cells: releases_per_frame, or more when the queue would not empty within release_frames frames. Entries shown again
## (reused) or replaced are skipped; the queue cannot grow without bound.
func _drain_release() -> void:
	var left := _release.size() - _release_pos
	if left <= 0:
		return
	var n := maxi(releases_per_frame, ceili(float(left) / maxf(release_frames, 1)))
	var t0 := Time.get_ticks_usec()
	while _release_pos < _release.size() and n > 0:
		var e: Array = _release[_release_pos]
		_release_pos += 1
		var key: Vector3i = e[0]
		var mmi: MultiMeshInstance3D = e[1]
		if not is_instance_valid(mmi) or active.get(key) == mmi:
			continue  # shown again (reused)
		if _reusable.get(key) == mmi:
			_reusable.erase(key)
		_free_cell(mmi)
		n -= 1
	if _release_pos >= _release.size():
		_release.clear()
		_release_pos = 0
	counters.free_us_max_frame = maxi(counters.free_us_max_frame, Time.get_ticks_usec() - t0)


func _deactivate_all() -> void:
	for key in active.keys():
		_deactivate(key)
	_queue.clear()
	# Switched off: everything goes now (nothing should linger hidden).
	for i in range(_release_pos, _release.size()):
		var mmi: MultiMeshInstance3D = _release[i][1]
		if is_instance_valid(mmi) and active.get(_release[i][0]) != mmi:
			_free_cell(mmi)
	_release.clear()
	_release_pos = 0
	_reusable.clear()
	_queue_pos = 0

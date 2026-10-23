## EDITOR-WORLD-02B/C runtime acceptance on the real ref_20km game scene.
##
##   Godot.exe --path . --resolution 1600x900 --log-file ew02.log \
##     res://scenes/game/world_ref_20km.tscn -- --ew02-test [--only c1,c2,c3,c4,b6,d2,parity] [--shots]
##
## Isolation: run with FRACTURED_WORLD_OVERRIDES pointing to a scratch file. Every case builds its overrides
## through the override layer (exactly as the editor plugin does), resets them afterwards and never writes the
## chunk files, the terrain or the scene. Optional inputs for the editor round trip:
##   --ew02-digest=<json>   digest written by the GUI acceptance (checked by case "parity")
## Output: user://ew02/ew02_test.json
class_name EW02SelfTest
extends RefCounted

const Digest = preload("res://tools/ew02_acceptance/world_digest.gd")
const IDS: Array[String] = ["c1", "c2", "c2t", "c3", "c4", "b6", "parity"]
const SOLID := [1, 2, 3, 4, 5, 6, 9, 10, 12, 16, 17, 18]

var demo: Node
var tree: SceneTree
var veg: VegetationStreamer
var layer: RefCounted
var lof: LineOfFire
var results := {}
var failures: Array[String] = []
var only: Array = []
var digest_file := ""
var shots := false
var _rebakes := 0
var _done := false
var _site := {}
var _neighbours := []
const NEIGHBOUR_RADIUS := 80.0


func _init(p_demo: Node) -> void:
	demo = p_demo
	tree = demo.get_tree()


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = Array(args[oi + 1].split(","))
	for a in args:
		if a.begins_with("--ew02-digest="):
			digest_file = a.trim_prefix("--ew02-digest=")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	tree.create_timer(1500.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: ew02 test did not finish")
		_finish())
	veg = demo.vegetation
	layer = veg.overrides
	lof = demo.sim.combat.line
	demo.sim.brain.enabled = false
	demo.sim.war.enabled = false
	demo.detail.zone_rebaked.connect(func(_i: Dictionary) -> void: _rebakes += 1)
	await _physics(60)
	if not _find_site():
		failures.append("no isolated house found near Haugen")
		_finish()
		return
	print("EW02 site ", JSON.stringify(_site))
	for id in IDS:
		if only.is_empty() or only.has(id):
			if id == "c2t" or id == "parity":
				_reset()
			else:
				_prepare()
			var data: Dictionary = await call("_case_" + id)
			_reset()
			results[id] = data
			if data.get("status", "") != "PASS" and data.get("status", "") != "SKIPPED":
				failures.append("%s: %s" % [id, data.get("reason", data.get("status", "?"))])
			print("EW02 %s %s" % [id, JSON.stringify(data)])
	_finish()


# --- plumbing ---------------------------------------------------------------------------

func _physics(n: int) -> void:
	for i in n:
		await tree.physics_frame
	await tree.process_frame


func _seconds(s: float) -> void:
	await tree.create_timer(s, true, true).timeout


func _finish() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	var dir := "user://ew02"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(ProjectSettings.globalize_path(dir + "/ew02_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("EW02 %s %s" % ["COMPLETE" if failures.is_empty() else "FAILED", JSON.stringify(failures)])
	demo.shutdown_cleanup()
	tree.quit()


func _reset() -> void:
	for id in layer.records.keys():
		layer.erase_record(id)
	layer.unresolved.clear()


func _ground(p: Vector3) -> float:
	var h: float = demo.terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _cell(p: Vector3) -> Vector2i:
	return VegetationChunk.cell_of(p, veg.cell_size_m)


## Finds a house on gentle ground with the fewest solid neighbours; those neighbours are removed (through the
## override layer itself) by _prepare() so every case measures the house and nothing else.
func _find_site() -> bool:
	var solids := []
	for loc in [Vector2i(-2, -5), Vector2i(-2, -4), Vector2i(-1, -5), Vector2i(-1, -4), Vector2i(-1, -2), Vector2i(-2, -2)]:
		var ch := veg.get_chunk_sync(loc)
		if ch == null:
			continue
		for cell in ch.cells:
			for mesh_id in ch.cells[cell]:
				if SOLID.has(int(mesh_id)):
					var buf: PackedFloat32Array = ch.cells[cell][mesh_id]
					for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
						solids.append([cell, int(mesh_id), i, VegetationChunk.instance_transform(buf, i)])
	var best_count := 1 << 30
	for s in solids:
		if s[1] != 16:
			continue
		var xf: Transform3D = s[3]
		var h0 := _ground(xf.origin)
		var flat := true
		for dx in [-35.0, -20.0, 20.0, 35.0]:
			for dz in [-45.0, -20.0, 0.0, 20.0, 45.0]:
				if absf(_ground(xf.origin + Vector3(dx, 0, dz)) - h0) > 4.0:
					flat = false
		if not flat:
			continue
		var count := 0
		for o in solids:
			if o != s and Vector2(o[3].origin.x - xf.origin.x, o[3].origin.z - xf.origin.z).length() < NEIGHBOUR_RADIUS:
				count += 1
		if count < best_count:
			best_count = count
			_site = {"cell": s[0], "mesh": 16, "index": s[2], "xf": xf}
	if _site.is_empty():
		return false
	var xf0: Transform3D = _site.xf
	_site.text = {"cell": [_site.cell.x, _site.cell.y], "index": _site.index, "origin": [xf0.origin.x, xf0.origin.y, xf0.origin.z], "neighbours_removed": best_count}
	_neighbours = []
	for o in solids:
		if not (o[0] == _site.cell and o[1] == 16 and o[2] == _site.index) 				and Vector2(o[3].origin.x - xf0.origin.x, o[3].origin.z - xf0.origin.z).length() < NEIGHBOUR_RADIUS:
			_neighbours.append(o)
	return true


## Resets all overrides, then removes the neighbours of the site (a bulk edit through the layer).
func _prepare() -> void:
	_reset()
	var recs := {}
	for o in _neighbours:
		var cell: Vector2i = o[0]
		var loc := VegetationChunk.chunk_of(Vector3(cell.x * veg.cell_size_m, 0, cell.y * veg.cell_size_m), veg.chunk_size_m)
		recs[layer.generated_id(cell, o[1], o[2])] = {"kind": "generated", "cell": [cell.x, cell.y], "mesh": o[1], "index": o[2],
			"chunk_hash": layer.chunk_hash(loc), "transform": layer._encode(o[3]), "removed": true}
	layer.put_many(recs)


func _site_xf() -> Transform3D:
	return _site.xf


## Moves the near tier (navmesh, colliders, ground) to p and waits for it.
func _go(p: Vector3) -> void:
	demo.rts_camera.frame(p, 0.0, 120.0)
	demo.detail.activate_at(p)
	veg.extra_observers = [_observer(p)]
	veg.refresh()
	await _physics(30)
	await _settle_streamer()
	for i in 900:
		if not demo.navigation.has_pending_bake() and not demo.detail._recenter_to.is_finite():
			break
		await tree.process_frame


var _obs_node: Node3D


func _observer(p: Vector3) -> Node3D:
	if _obs_node == null:
		_obs_node = Node3D.new()
		demo.add_child(_obs_node)
	_obs_node.global_position = Vector3(p.x, _ground(p) + 2.0, p.z)
	return _obs_node


func _settle_streamer() -> void:
	for i in 200:
		if veg.is_settled():
			break
		await tree.process_frame
	await tree.process_frame


func _has_at(p: Vector3, mesh_id: int, tol := 0.02) -> bool:
	for v in veg.get_cell_instances(_cell(p), [mesh_id]):
		if v[1].origin.distance_to(p) < tol:
			return true
	return false


## How many displayed MultiMesh instances of mesh_id stand within tol of p, across all active cells.
func _displayed_at(p: Vector3, mesh_id: int, tol := 0.02) -> int:
	var n := 0
	for key: Vector3i in veg.active:
		if key.z != mesh_id:
			continue
		var buf: PackedFloat32Array = veg.active[key].multimesh.buffer
		for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
			if VegetationChunk.instance_transform(buf, i).origin.distance_to(p) < tol:
				n += 1
	return n


## Instance colliders (physics bodies) hit by a segment, via real physics queries.
func _collider_hits(from: Vector3, to: Vector3) -> int:
	var space: PhysicsDirectSpaceState3D = demo.get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	var n := 0
	for k in 6:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = excluded
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		excluded.append(hit.rid)
		var body: Node = hit.collider
		if body is StaticBody3D and body.get_parent() is InstanceColliderStreamer:
			n += 1
	return n


## A horizontal segment through p at the collider's mid height, from the west and from the north.
func _through(p: Vector3, lateral := 0.0) -> int:
	var y := _ground(p) + 1.1
	var a := _collider_hits(Vector3(p.x - 10.0, y, p.z + lateral), Vector3(p.x + 10.0, y, p.z + lateral))
	var b := _collider_hits(Vector3(p.x + lateral, y, p.z - 10.0), Vector3(p.x + lateral, y, p.z + 10.0))
	return a + b


func _sight_blocked(p: Vector3, half := 20.0) -> bool:
	var y := _ground(p) + 1.5
	return not lof.clear_line(Vector3(p.x - half, y, p.z), Vector3(p.x + half, y, p.z))


func _move_site(offset: Vector3, basis := Basis.IDENTITY, removed := false) -> Transform3D:
	var base := _site_xf()
	var xf := Transform3D(base.basis * basis, base.origin + offset)
	xf.origin.y = _ground(xf.origin) + (base.origin.y - _ground(base.origin))
	layer.set_generated(_site.cell, _site.mesh, _site.index, xf, removed)
	return xf


func _status(ok: bool, data: Dictionary) -> Dictionary:
	data["status"] = "PASS" if ok else "FAIL"
	return data


# --- cases ------------------------------------------------------------------------------

## C1: revision model on the real chunks. Warm lookups never hash; reload rehashes once.
func _case_c1() -> Dictionary:
	var data := {}
	await _go(_site_xf().origin)
	var xf := _move_site(Vector3(20, 0, 0))
	var cells := Digest.cells_around(_site.cell, 3)
	for c in cells:
		veg.get_cell_instances(c, SOLID)
	var h0: int = layer.stats.hashes
	var t0 := Time.get_ticks_usec()
	for i in 500:
		veg.get_cell_instances(cells[i % cells.size()], SOLID)
	data.warm_500_lookups_ms = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	data.warm_hashes = layer.stats.hashes - h0
	var loc := VegetationChunk.chunk_of(_site_xf().origin, veg.chunk_size_m)
	h0 = layer.stats.hashes
	veg.unload_chunk(loc)
	veg.get_cell_instances(_cell(xf.origin), SOLID)
	data.reload_hashes = layer.stats.hashes - h0
	data.unresolved = layer.unresolved.size()
	h0 = layer.stats.hashes
	for i in 100:
		veg.get_cell_instances(cells[i % cells.size()], SOLID)
	data.after_reload_hashes = layer.stats.hashes - h0
	return _status(data.warm_hashes == 0 and data.reload_hashes == 1 and data.after_reload_hashes == 0 and data.unresolved == 0 \
		and _has_at(xf.origin, 16), data)


## C2: physics collision of moved / removed / added / scaled / rotated objects.
func _case_c2() -> Dictionary:
	var data := {}
	var origin := _site_xf().origin
	await _go(origin)
	data.original_hits = _through(origin)
	var cstream: InstanceColliderStreamer = demo.detail.collider_streamer
	data.dbg = {"streamer": cstream != null, "target": str(cstream.target) if cstream else "", "active": cstream.active_count if cstream else -1,
		"indexed": cstream.indexed_regions if cstream else -1, "target_pos": str(cstream.target.global_position) if cstream and cstream.target else "", "origin": str(origin), "last": str(cstream._last_center), "buckets": cstream._buckets.size(), "ids": str(cstream._solid_ids()), "vegref": cstream.vegetation == veg, "any_hit": str(demo.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin + Vector3(-10, 1.2, 0), origin + Vector3(10, 1.2, 0))))}
	var moved := _move_site(Vector3(20, 0, 0), Basis(Vector3.UP, deg_to_rad(30.0)))
	await _go(origin)
	data.old_place_hits = _through(origin)
	data.new_place_hits = _through(moved.origin)
	data.new_place_hits_rotated_probe = _collider_hits(moved.origin + Vector3(0, 1.1, 0) + Vector3(-8.0, 0, 0), moved.origin + Vector3(0, 1.1, 0) + Vector3(-3.0, 0, 0))
	# Remove: no collision at the new place either.
	_move_site(Vector3(20, 0, 0), Basis.IDENTITY, true)
	await _go(origin)
	data.removed_hits = _through(moved.origin) + _through(origin)
	_prepare()
	# Added object (house) in the open next to the site.
	var spot := origin + Vector3(0, 0, 38.0)
	spot.y = _ground(spot)
	layer.add_instance(16, Transform3D(Basis.IDENTITY, spot))
	await _go(origin)
	data.added_hits = _through(spot)
	_prepare()
	# Scale: a house at scale 2 has a sphere of 8 m, so a segment 6 m off its centre still hits it.
	var big := Transform3D(Basis.IDENTITY.scaled(Vector3(2, 2, 2)), spot)
	layer.add_instance(16, big)
	await _go(origin)
	data.scaled_hit_6m_off = _collider_hits(Vector3(spot.x - 12, spot.y + 2.4, spot.z + 6.0), Vector3(spot.x + 12, spot.y + 2.4, spot.z + 6.0))
	_prepare()
	layer.add_instance(16, Transform3D(Basis.IDENTITY, spot))
	await _go(origin)
	data.unscaled_hit_6m_off = _collider_hits(Vector3(spot.x - 12, spot.y + 1.2, spot.z + 6.0), Vector3(spot.x + 12, spot.y + 1.2, spot.z + 6.0))
	var ok: bool = data.original_hits > 0 and data.old_place_hits == 0 and data.new_place_hits > 0 and data.new_place_hits_rotated_probe > 0 \
		and data.removed_hits == 0 and data.added_hits > 0 and data.scaled_hit_6m_off > 0 and data.unscaled_hit_6m_off == 0
	return _status(ok, data)


## C3: navmesh follows moved / removed houses (real rebake, real path queries).
func _case_c3() -> Dictionary:
	var data := {}
	var origin := _site_xf().origin
	await _go(origin)
	var map: RID = demo.navigation.get_navigation_map()
	var a := Vector3(origin.x - 30.0, 0, origin.z)
	var b := Vector3(origin.x + 30.0, 0, origin.z)
	var before := _path(map, a, b, origin)
	data.before = before
	data.snap_before = _snap(map, origin)
	# Move the house 40 m north: the old footprint opens, the new one blocks a path through it.
	var b0 := _rebakes
	var moved := _move_site(Vector3(0, 0, -40.0))
	data.dbg = {"nav_center": str(demo.detail.nav_center), "rebake_in": demo.detail._rebake_in, "recenter_to": str(demo.detail._recenter_to), "connected": veg.clearings_changed.is_connected(demo.detail._on_vegetation_changed), "bake_count": demo.detail.bake_count, "area": demo.detail.nav_area_size}
	await _wait_rebake(b0)
	data.rebakes_for_one_move = _rebakes - b0
	data.bake_after_move = demo.navigation.last_bake.duplicate()
	data.snap_old_place_after_move = _snap(map, origin)
	data.snap_new_place_after_move = _snap(map, moved.origin)
	data.straight_probe = _path(map, Vector3(origin.x - 30, 0, origin.z + 25), Vector3(origin.x + 30, 0, origin.z + 25), origin)
	var old_path := _path(map, a, b, origin)
	var na := Vector3(moved.origin.x - 30.0, 0, moved.origin.z)
	var nb := Vector3(moved.origin.x + 30.0, 0, moved.origin.z)
	var new_path := _path(map, na, nb, moved.origin)
	data.old_place_after = old_path
	data.new_place_after = new_path
	# Remove the house: the new place opens as well.
	b0 = _rebakes
	_move_site(Vector3(0, 0, -40.0), Basis.IDENTITY, true)
	await _wait_rebake(b0)
	var removed_path := _path(map, na, nb, moved.origin)
	data.removed_after = removed_path
	data.snap_new_place_after_remove = _snap(map, moved.origin)
	var straight := 60.0
	# The navmesh itself: the nearest walkable point to a footprint centre. Inside an obstruction it lies at
	# least half a footprint away (the house square is 8.4 m wide); on open ground it is the centre itself.
	var ok: bool = data.snap_before >= 3.5 and data.snap_old_place_after_move <= 1.0 and data.snap_new_place_after_move >= 3.5 		and data.snap_new_place_after_remove <= 1.0 and data.rebakes_for_one_move >= 1 and data.rebakes_for_one_move <= 2
	return _status(ok, data)


func _case_c4() -> Dictionary:
	var data := {}
	var origin := _site_xf().origin
	await _go(origin)
	data.original_blocked = _sight_blocked(origin)
	var moved := _move_site(Vector3(0, 0, -40.0))
	data.cell_dropped_from_cache = not lof._loaded_cells.has(_site.cell)
	data.old_place_blocked = _sight_blocked(origin)
	data.new_place_blocked = _sight_blocked(moved.origin)
	var shot_old := lof.trace(Vector3(origin.x - 20, _ground(origin) + 1.5, origin.z), Vector3(origin.x + 20, _ground(origin) + 1.5, origin.z), -1, false)
	var shot_new := lof.trace(Vector3(moved.origin.x - 20, moved.origin.y + 1.5, moved.origin.z), Vector3(moved.origin.x + 20, moved.origin.y + 1.5, moved.origin.z), -1, false)
	data.shot_old_blocker = shot_old.blocker
	data.shot_new_blocker = shot_new.blocker
	data.shot_new_distance = snappedf(shot_new.distance, 0.1)
	_move_site(Vector3(0, 0, -40.0), Basis.IDENTITY, true)
	data.removed_blocked = _sight_blocked(moved.origin)
	_prepare()
	var spot := origin + Vector3(0, 0, 38.0)
	spot.y = _ground(spot)
	layer.add_instance(16, Transform3D(Basis.IDENTITY, spot))
	data.added_blocked = _sight_blocked(spot)
	var ok: bool = data.original_blocked and not data.old_place_blocked and data.new_place_blocked and data.shot_old_blocker == "range" \
		and data.shot_new_blocker == "tree" and not data.removed_blocked and data.added_blocked and data.cell_dropped_from_cache
	return _status(ok, data)


## B6: chunk unload/reload, moves between cells and chunks, manual object in an empty cell, remove + restore.
func _case_b6() -> Dictionary:
	var data := {}
	var origin := _site_xf().origin
	await _go(origin)
	# (1) move within the chunk, unload, reload.
	var moved := _move_site(Vector3(150, 0, 0)) # different cell
	data.moved_cell_differs = _cell(moved.origin) != _site.cell
	await _go(origin)
	data.displayed_new_1 = _displayed_at(moved.origin, 16)
	data.displayed_old_1 = _displayed_at(origin, 16)
	var loc := VegetationChunk.chunk_of(origin, veg.chunk_size_m)
	veg.unload_chunk(loc)
	veg.refresh()
	await _go(origin)
	data.displayed_new_after_reload = _displayed_at(moved.origin, 16)
	data.displayed_old_after_reload = _displayed_at(origin, 16)
	data.unresolved_after_reload = layer.unresolved.size()
	# (2) move into another chunk (+1 chunk east of the site chunk).
	var to_next := Vector3((float(loc.x + 1) * veg.chunk_size_m) + 40.0 - origin.x, 0, 0)
	var far_xf := _move_site(to_next)
	data.crossed_chunk = VegetationChunk.chunk_of(far_xf.origin, veg.chunk_size_m) != loc
	await _go(far_xf.origin)
	data.displayed_far = _displayed_at(far_xf.origin, 16)
	data.displayed_old_2 = _displayed_at(origin, 16)
	await _go(origin)
	veg.unload_chunk(VegetationChunk.chunk_of(far_xf.origin, veg.chunk_size_m))
	await _go(far_xf.origin)
	data.displayed_far_after_reload = _displayed_at(far_xf.origin, 16)
	# (3) manual object in a cell without any generated data.
	var empty_cell := Vector2i.ZERO
	var found := false
	for loc2 in veg.chunks:
		var ch: VegetationChunk = veg.chunks[loc2]
		for cx in range(loc2.x * 8, loc2.x * 8 + 8):
			for cz in range(loc2.y * 8, loc2.y * 8 + 8):
				if not ch.cells.has(Vector2i(cx, cz)) and not found:
					empty_cell = Vector2i(cx, cz)
					found = true
	data.empty_cell = [empty_cell.x, empty_cell.y]
	if found:
		var p := Vector3((empty_cell.x + 0.5) * veg.cell_size_m, 0, (empty_cell.y + 0.5) * veg.cell_size_m)
		p.y = _ground(p)
		var id: String = layer.add_instance(16, Transform3D(Basis.IDENTITY, p))
		await _go(p)
		data.displayed_manual = _displayed_at(p, 16)
		# (4) remove and restore.
		var rec: Dictionary = layer.records[id].duplicate(true)
		rec.removed = true
		layer.put(id, rec)
		await _go(p)
		data.displayed_manual_removed = _displayed_at(p, 16)
		rec.removed = false
		layer.put(id, rec)
		await _go(p)
		data.displayed_manual_restored = _displayed_at(p, 16)
	_reset()
	await _go(origin)
	data.displayed_original_restored = _displayed_at(origin, 16)
	data.duplicates = _displayed_at(origin, 16) + _displayed_at(moved.origin, 16) + _displayed_at(far_xf.origin, 16)
	var ok: bool = data.moved_cell_differs and data.displayed_new_1 == 1 and data.displayed_old_1 == 0 and data.displayed_new_after_reload == 1 \
		and data.displayed_old_after_reload == 0 and data.unresolved_after_reload == 0 and data.crossed_chunk and data.displayed_far == 1 \
		and data.displayed_old_2 == 0 and data.displayed_far_after_reload == 1 and found and data.get("displayed_manual", 0) == 1 \
		and data.get("displayed_manual_removed", 1) == 0 and data.get("displayed_manual_restored", 0) == 1 \
		and data.displayed_original_restored == 1 and data.duplicates == 1
	return _status(ok, data)


## C5 / EW02B-08 runtime half: the digest of the effective world around the site, to be compared with the
## digest the editor wrote for the same override file.
func _case_parity() -> Dictionary:
	var data := {}
	if digest_file.is_empty() or not FileAccess.file_exists(digest_file):
		return {"status": "SKIPPED", "reason": "no --ew02-digest given (editor round trip not part of this run)"}
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(digest_file))
	layer.load_file()
	var centre := Vector2i(int(ref.centre[0]), int(ref.centre[1]))
	var cells := Digest.cells_around(centre, int(ref.radius))
	var origin := Vector3((centre.x + 0.5) * veg.cell_size_m, 0, (centre.y + 0.5) * veg.cell_size_m)
	await _go(origin)
	data.effective_sha = Digest.sha(Digest.lines(veg, cells))
	data.editor_effective_sha = ref.effective_sha
	data.records = layer.records.size()
	data.unresolved = layer.unresolved.size()
	var focus: Array = []
	for c in ref.focus_cells:
		focus.append(Vector2i(int(c[0]), int(c[1])))
	var meshes: Array = []
	for m in ref.focus_meshes:
		meshes.append(int(m))
	# Place the observer at the same spot as the editor camera did so the displayed set is comparable.
	await _go(Vector3((centre.x + 0.5) * veg.cell_size_m, 0, (centre.y + 0.5) * veg.cell_size_m))
	data.displayed_sha = Digest.sha(Digest.displayed_lines(veg, focus, meshes))
	data.editor_displayed_sha = ref.displayed_sha
	var lods := {}
	for key: Vector3i in veg.active_lod:
		if focus.has(Vector2i(key.x, key.y)) and meshes.has(key.z):
			lods["%d,%d,%d" % [key.x, key.y, key.z]] = veg.active_lod[key]
	var editor_lods := {}
	for k in ref.lod:
		if meshes.has(int(str(k).split(",")[2])):
			editor_lods[k] = int(ref.lod[k])
	data.lod = lods
	data.editor_lod = editor_lods
	data.lod_same = JSON.stringify(lods) == JSON.stringify(editor_lods)
	data.override_file_sha = FileAccess.get_sha256(layer.path)
	data.editor_override_sha = ref.override_sha
	data.houses_checked = []
	var ok: bool = data.effective_sha == data.editor_effective_sha and data.unresolved == 0 and data.records > 0 \
		and data.override_file_sha == data.editor_override_sha and data.displayed_sha == data.editor_displayed_sha and data.lod_same
	# Collision at every placed house/tree of the file.
	var hits_ok := true
	for id in layer.records:
		var rec: Dictionary = layer.records[id]
		if rec.get("removed", false) or not SOLID.has(int(rec.mesh)):
			continue
		var p: Vector3 = layer._decode(rec.transform).origin
		await _go(p)
		var h := _through(p, 0.0)
		data.houses_checked.append({"id": id, "mesh": rec.mesh, "pos": [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)], "collider_hits": h})
		if h == 0:
			hits_ok = false
	data.collision_at_all_placed = hits_ok
	return _status(ok and hits_ok, data)


## C2 for trees: trunk capsule at the new place only; scale changes its radius; rotation does not move it.
func _case_c2t() -> Dictionary:
	var data := {}
	var ch := veg.get_chunk_sync(Vector2i(-2, -5))
	var pick := {}
	for cell in ch.cells:
		for mesh_id in [3, 4, 5]:
			if pick.is_empty() and ch.cells[cell].has(mesh_id):
				var buf: PackedFloat32Array = ch.cells[cell][mesh_id]
				for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
					var xf := VegetationChunk.instance_transform(buf, i)
					if absf(xf.basis.get_scale().x - 1.0) < 0.15:
						pick = {"cell": cell, "mesh": mesh_id, "index": i, "xf": xf}
						break
	if pick.is_empty():
		return {"status": "FAIL", "reason": "no unscaled tree found"}
	var base: Transform3D = pick.xf
	var origin := base.origin
	await _go(origin)
	var seg := func(p: Vector3, lateral: float) -> int:
		var y := _ground(p) + 1.1
		return _collider_hits(Vector3(p.x - 1.2, y, p.z + lateral), Vector3(p.x + 1.2, y, p.z + lateral))
	data.original_hits = seg.call(origin, 0.0)
	var moved := Transform3D(base.basis, base.origin + Vector3(15, 0, 0))
	moved.origin.y = _ground(moved.origin)
	layer.set_generated(pick.cell, pick.mesh, pick.index, moved)
	await _go(origin)
	data.old_place_hits = seg.call(origin, 0.0)
	data.new_place_hits = seg.call(moved.origin, 0.0)
	var rotated := Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)) * moved.basis, moved.origin)
	layer.set_generated(pick.cell, pick.mesh, pick.index, rotated)
	await _go(origin)
	data.rotated_new_place_hits = seg.call(moved.origin, 0.0)
	var r_one: float = veg.library.get_def(pick.mesh).collider.y * base.basis.get_scale().x
	data.unscaled_radius = snappedf(r_one, 0.01)
	var lateral := r_one * 1.6
	data.unscaled_lateral_hits = seg.call(moved.origin, lateral)
	var scaled := Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)) * moved.basis.scaled(Vector3(2, 2, 2)), moved.origin)
	layer.set_generated(pick.cell, pick.mesh, pick.index, scaled)
	await _go(origin)
	data.scaled_lateral_hits = seg.call(moved.origin, lateral)
	layer.set_generated(pick.cell, pick.mesh, pick.index, scaled, true)
	await _go(origin)
	data.removed_hits = seg.call(moved.origin, 0.0) + seg.call(origin, 0.0)
	_prepare()
	var spot := origin + Vector3(0, 0, 25.0)
	spot.y = _ground(spot)
	layer.add_instance(pick.mesh, Transform3D(Basis.IDENTITY, spot))
	await _go(origin)
	data.added_hits = seg.call(spot, 0.0)
	var ok: bool = data.original_hits > 0 and data.old_place_hits == 0 and data.new_place_hits > 0 and data.rotated_new_place_hits > 0 		and data.unscaled_lateral_hits == 0 and data.scaled_lateral_hits > 0 and data.removed_hits == 0 and data.added_hits > 0
	return _status(ok, data)


func _path(map: RID, a: Vector3, b: Vector3, centre: Vector3) -> Dictionary:
	NavigationServer3D.map_force_update(map)
	var pa := NavigationServer3D.map_get_closest_point(map, Vector3(a.x, _ground(a), a.z))
	var pb := NavigationServer3D.map_get_closest_point(map, Vector3(b.x, _ground(b), b.z))
	var path := NavigationServer3D.map_get_path(map, pa, pb, true)
	var length := 0.0
	var min_cheb := INF
	var max_dev := 0.0
	var chord := Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
	for i in path.size():
		var rel := Vector2(path[i].x - pa.x, path[i].z - pa.z)
		max_dev = maxf(max_dev, absf(rel.x * chord.y - rel.y * chord.x))
		if i > 0:
			length += path[i].distance_to(path[i - 1])
			# Sample along the segment: a straight leg through the footprint has no vertex inside it.
			var n := maxi(1, ceili(path[i].distance_to(path[i - 1]) / 0.5))
			for k in n + 1:
				var q := path[i - 1].lerp(path[i], float(k) / n)
				min_cheb = minf(min_cheb, maxf(absf(q.x - centre.x), absf(q.z - centre.z)))
	return {"points": path.size(), "length": snappedf(length, 0.1), "min_cheb": snappedf(min_cheb, 0.1), "max_dev": snappedf(max_dev, 0.1), "straight": snappedf(pa.distance_to(pb), 0.1)}


## Waits for the (single, batched) navmesh rebake an override change schedules, and for its async bake.
func _wait_rebake(rebakes_before: int) -> void:
	for i in 1500:
		await tree.process_frame
		if _rebakes > rebakes_before and not demo.navigation.has_pending_bake() and demo.detail._rebake_in < 0.0:
			break
	await _seconds(0.3)


## Distance from a footprint centre to the nearest walkable navmesh point (after the map is up to date).
func _snap(map: RID, centre: Vector3) -> float:
	NavigationServer3D.map_force_update(map)
	var p := NavigationServer3D.map_get_closest_point(map, Vector3(centre.x, _ground(centre), centre.z))
	return snappedf(Vector2(p.x - centre.x, p.z - centre.z).length(), 0.1)

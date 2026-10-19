## Short, targeted checks of the WORLD-TECH-02 vegetation system on a world scene.
## Prints "VEGTEST <name> <json>" lines and a final PASS/FAIL summary, writes
## res://benchmarks/raw/vegtest_<tag>.json. Takes ~20 s on the 2 km world.
##
##   Godot.exe --path . --resolution 1600x900 --log-file t.log --script res://tools/test_vegetation.gd -- \
##       --scene=res://scenes/world/test_2km.tscn [--tag=test_2km] [--shots]
##
## Checks: grass mask on roads / off roads / base pads, tree clearance from roads and
## base pads, deterministic per-cell scatter, streamer activation bounds, camera jump
## and FPS<->RTS switch settle time and worst frame, grass altitude cutoff, collider
## streaming from chunk data.
extends SceneTree

var opts := {}
var world: Node3D
var terrain: Terrain3D
var builder: WorldBuilder
var veg: VegetationStreamer
var grass: GrassLayer
var cam: Camera3D
var results := {}
var failures: Array[String] = []
var _last_usec := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else true
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var ps: PackedScene = load(opts.get("scene", "res://scenes/world/test_2km.tscn"))
	world = ps.instantiate()
	root.add_child(world)
	terrain = world.get_node("Terrain3D")
	builder = world.get_node("WorldBuilder")
	veg = world.get_node("Vegetation")
	grass = world.get_node("Grass")
	for n in ["Player", "WorldDiagnostics", "InstanceColliderStreamer"]:
		var node := world.get_node_or_null(n)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var pcam: Camera3D = world.get_node_or_null("Player/Head/Camera3D")
	if pcam:
		pcam.current = false
	world.get_node("WorldDiagnostics").visible = false
	cam = Camera3D.new()
	cam.far = 30000.0
	cam.fov = 70.0
	world.add_child(cam)
	cam.make_current()
	terrain.set_camera(cam)
	await _frames(5)
	builder._collect_road_polylines()

	_check_mask()
	_check_tree_clearance()
	_check_determinism()
	await _check_streamer()
	await _check_grass_altitude()
	await _check_colliders()

	results.failures = failures
	results.pass = failures.is_empty()
	var tag: String = opts.get("tag", "vegtest")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/vegtest_%s.json" % tag), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("VEGTEST %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _log(name: String, data: Dictionary) -> void:
	results[name] = data
	print("VEGTEST %s %s" % [name, JSON.stringify(data)])


# ------------------------------------------------------------------------------

func _check_mask() -> void:
	var mask: VegetationMask = grass.mask
	_expect(mask != null and mask.image != null, "grass layer has no mask")
	if mask == null or mask.image == null:
		return
	var road_index := WorldBuilder._RoadIndex.new(builder.road_polylines, 32.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# Along every road polyline center: must be excluded.
	var on_road := 0
	var on_road_ok := 0
	for li in builder.road_polylines.size():
		var line: PackedVector3Array = builder.road_polylines[li]
		for i in line.size() - 1:
			for t in [0.1, 0.5, 0.9]:
				var p: Vector3 = line[i].lerp(line[i + 1], t)
				on_road += 1
				if mask.is_excluded(p.x, p.z):
					on_road_ok += 1
	# Random open ground at least 15 m from any road and outside base pads: must not be excluded.
	var hs := builder.config.half_size() - 50.0
	var gen := builder._generator()
	var open := 0
	var open_ok := 0
	while open < 400:
		var p := Vector3(rng.randf_range(-hs, hs), 0, rng.randf_range(-hs, hs))
		if road_index.distance(p) < 15.0 or builder._in_base(gen, p):
			continue
		open += 1
		if not mask.is_excluded(p.x, p.z):
			open_ok += 1
	# Base pad centers: excluded.
	var pads := 0
	var pads_ok := 0
	for site in builder.config.base_sites:
		var c := Vector2(site.x, site.y) * builder.config.half_size()
		for d in [Vector2.ZERO, Vector2(site.z * 0.7, 0), Vector2(0, -site.z * 0.7)]:
			pads += 1
			if mask.is_excluded(c.x + d.x, c.y + d.y):
				pads_ok += 1
	var excluded_area := 0.0
	var img := mask.image
	var n := img.get_width()
	var step := maxi(n / 512, 1)
	var cnt := 0
	for z in range(0, n, step):
		for x in range(0, n, step):
			cnt += 1
			if img.get_pixel(x, z).r >= 0.5:
				excluded_area += 1.0
	_log("mask", {"texel_m": mask.texel_m, "size_px": n, "road_samples": on_road, "road_excluded": on_road_ok,
		"open_samples": open, "open_clear": open_ok, "pad_samples": pads, "pad_excluded": pads_ok,
		"excluded_fraction": excluded_area / cnt})
	_expect(on_road_ok == on_road, "mask: %d/%d road samples not excluded" % [on_road - on_road_ok, on_road])
	_expect(open_ok == open, "mask: %d/%d open-ground samples excluded" % [open - open_ok, open])
	_expect(pads_ok == pads, "mask: %d/%d base pad samples not excluded" % [pads - pads_ok, pads])


func _check_tree_clearance() -> void:
	var road_index := WorldBuilder._RoadIndex.new(builder.road_polylines, 32.0)
	var gen := builder._generator()
	var chunks := builder._load_chunks()
	var trees := 0
	var near_road := 0
	var in_base := 0
	var min_d := INF
	var on_mask := 0
	var mask: VegetationMask = grass.mask
	var per_mesh := {}
	var cells := 0
	var max_cell_instances := 0
	# Large worlds: check a bounded sample of trees (chunks in load order).
	var max_trees := int(opts.get("max-trees", 300000))
	for loc in chunks:
		var ch: VegetationChunk = chunks[loc]
		if trees >= max_trees:
			break
		for cell in ch.cells:
			cells += 1
			var in_cell := 0
			for mesh_id in ch.cells[cell]:
				var buf: PackedFloat32Array = ch.cells[cell][mesh_id]
				var cnt := buf.size() / VegetationChunk.FLOATS_PER_INSTANCE
				in_cell += cnt
				per_mesh[mesh_id] = per_mesh.get(mesh_id, 0) + cnt
				if mesh_id != 1 and mesh_id != 2:
					continue
				for i in cnt:
					var o := VegetationChunk.instance_transform(buf, i).origin
					trees += 1
					var d := road_index.distance(o)
					min_d = minf(min_d, d)
					if d < builder.config.road_clearance_m - 0.01:
						near_road += 1
					if builder._in_base(gen, o):
						in_base += 1
					if mask and mask.is_excluded(o.x, o.z):
						on_mask += 1
			max_cell_instances = maxi(max_cell_instances, in_cell)
	_log("trees", {"chunks": chunks.size(), "cells_checked": cells, "trees_checked": trees, "within_road_clearance": near_road,
		"in_base_pads": in_base, "on_grass_mask": on_mask, "min_road_distance_m": min_d,
		"per_mesh": per_mesh, "max_instances_per_cell": max_cell_instances})
	_expect(near_road == 0, "%d trees inside road clearance" % near_road)
	_expect(in_base == 0, "%d trees on base pads" % in_base)
	_expect(trees > 0, "no trees stored")


func _check_determinism() -> void:
	# Scatter one cell twice with the production code path; buffers must be identical.
	builder._sc_road = WorldBuilder._RoadIndex.new(builder.road_polylines, 32.0)
	builder._sc_mask = grass.mask
	builder._sc_max_slope = cos(deg_to_rad(builder.config.max_tree_slope_deg))
	builder._sc_hs = builder.config.half_size() - 4.0
	if builder.config.vegetation_extent_m > 0.0:
		builder._sc_hs = minf(builder._sc_hs, builder.config.vegetation_extent_m * 0.5)
	builder._sc_cfg = {"seed": builder.config.world_seed, "tree_s": builder.config.tree_spacing_m,
		"bush_s": builder.config.bush_spacing_m, "rock_s": builder.config.rock_spacing_m,
		"thr": builder.config.forest_threshold, "clear": builder.config.road_clearance_m,
		"base_h": builder.config.base_height, "sites": builder.config.base_sites.size()}
	builder._generator()
	var chunks := builder._load_chunks()
	var cell := Vector2i(-3, -4)
	var stored := {}
	for loc in chunks:
		if chunks[loc].cells.has(cell):
			stored = chunks[loc].cells[cell]
	builder._sc_cells = [cell, cell]
	builder._sc_results = [null, null]
	builder._scatter_cell_task(0)
	builder._scatter_cell_task(1)
	var a: Dictionary = builder._sc_results[0]
	var b: Dictionary = builder._sc_results[1]
	var same_ab := a.size() == b.size()
	var same_stored := a.size() == stored.size()
	for k in a:
		same_ab = same_ab and b.has(k) and a[k] == b[k]
		same_stored = same_stored and stored.has(k) and a[k] == stored[k]
	var n := 0
	for k in a:
		n += a[k].size() / VegetationChunk.FLOATS_PER_INSTANCE
	_log("determinism", {"cell": [cell.x, cell.y], "instances": n, "repeat_identical": same_ab,
		"matches_stored_file": same_stored})
	_expect(same_ab, "scatter of the same cell twice differs")
	_expect(same_stored, "scatter differs from the stored chunk file")


func _check_streamer() -> void:
	var c := _road_center()
	var ground := c + Vector3(0, 1.8 + _ground_y(c), 0)
	_place(ground, ground + Vector3(60, -1, 8))
	var cold := await _settle(300)
	var cold_stats := veg.get_stats()
	# Cold start includes first mesh uploads and shader pipeline compilation. Measure the
	# station again after leaving it, which is the steady-state cost.
	_place(ground + Vector3(3000, 0, 3000), ground + Vector3(3060, 0, 3000))
	await _settle(300)
	_place(ground, ground + Vector3(60, -1, 8))
	var settle := await _settle(300)
	var st := veg.get_stats()
	var r := veg.library.max_range()
	var cs := veg.cell_size_m
	var bound := int(pow(ceil(r * 2.0 / cs) + 2, 2)) * veg.library.meshes.size()
	# Every active cell within range of the camera.
	var far_cells := 0
	for key in veg.active:
		var center := Vector3((key.x + 0.5) * cs, cam.global_position.y, (key.y + 0.5) * cs)
		if Vector2(center.x - cam.global_position.x, center.z - cam.global_position.z).length() > r + cs:
			far_cells += 1
	_log("streamer_fps", {"cold_start": {"settle_frames": cold.frames, "settle_ms": cold.ms, "worst_frame_ms": cold.worst,
		"worst_activation_ms": cold_stats.worst_activation_ms},
		"settle_frames": settle.frames, "settle_ms": settle.ms, "worst_frame_ms": settle.worst,
		"stats": st, "mmi_upper_bound": bound, "active_out_of_range": far_cells})
	_expect(st.active_mmis > 0, "no vegetation activated at the FPS station")
	_expect(st.active_mmis <= bound, "too many MultiMeshes active")
	_expect(far_cells == 0, "active cells beyond range")
	_expect(settle.worst < 50.0, "warm FPS station worst frame %.1f ms" % settle.worst)

	# Jump to the far corner: cells out of range must go, new ones come, no stall.
	var hs := _map_size() * 0.45
	var far := Vector3(hs, 0, hs)
	far.y = _ground_y(far) + 1.8
	var before := veg.active.keys()
	_place(far, far + Vector3(-60, -1, -10))
	var j := await _settle(300)
	var leftovers := 0
	for key in before:
		if not veg.active.has(key):
			continue
		var center := Vector3((key.x + 0.5) * cs, far.y, (key.y + 0.5) * cs)
		if Vector2(center.x - far.x, center.z - far.z).length() > r + cs:
			leftovers += 1
	var st2 := veg.get_stats()
	_log("streamer_jump", {"settle_frames": j.frames, "settle_ms": j.ms, "worst_frame_ms": j.worst,
		"first_frame_ms": j.first, "stats": st2, "old_cells_out_of_range_still_active": leftovers})
	_expect(j.worst < 50.0, "camera jump worst frame %.1f ms" % j.worst)
	_expect(leftovers == 0, "%d out-of-range cells still active after the jump" % leftovers)

	# Rapid FPS <-> RTS switching, 6 round trips.
	var rts := c + Vector3(0, 600 + _ground_y(c), 420)
	var worst := 0.0
	var worst_settle := 0
	for i in 12:
		_place(ground if i % 2 == 0 else rts, c + Vector3(0, _ground_y(c), 0))
		var s := await _settle(120)
		worst = maxf(worst, s.worst)
		worst_settle = maxi(worst_settle, s.frames)
	await _physics(3)
	var st3 := veg.get_stats()
	_log("streamer_switch", {"round_trips": 6, "worst_frame_ms": worst, "worst_settle_frames": worst_settle,
		"stats_at_rts600": st3, "grass_active_at_rts600": grass.active})
	_expect(worst < 50.0, "FPS/RTS switch worst frame %.1f ms" % worst)
	_expect(not grass.active, "grass still active at 600 m altitude")

	# Rapid movement: 60 m/s at ground level for 180 frames.
	_place(ground, ground + Vector3(60, -1, 8))
	await _settle(300)
	var worst_move := 0.0
	var p := ground
	for i in 180:
		p.x += 1.0
		p.y = _ground_y(p) + 1.8
		cam.global_position = p
		_last_usec = Time.get_ticks_usec()
		await process_frame
		worst_move = maxf(worst_move, (Time.get_ticks_usec() - _last_usec) / 1000.0)
	_log("streamer_move", {"speed_m_per_frame": 1.0, "frames": 180, "worst_frame_ms": worst_move,
		"stats": veg.get_stats(), "grass_active": grass.active})
	_expect(worst_move < 50.0, "fast movement worst frame %.1f ms" % worst_move)
	if opts.has("shots"):
		_shot("move_end")


func _check_grass_altitude() -> void:
	var c := _road_center()
	var g := _ground_y(c)
	var seq := [[1.8, true], [60.0, true], [120.0, false], [600.0, false], [70.0, true], [1.8, true]]
	var seen := []
	var ok := true
	for s in seq:
		cam.global_position = c + Vector3(0, g + s[0], 0)
		cam.look_at(c + Vector3(1, g, 0))
		await _physics(3)
		seen.append([s[0], grass.active, snappedf(grass.camera_height, 0.1)])
		ok = ok and grass.active == s[1]
	_log("grass_altitude", {"cutoff_m": grass.max_camera_height, "sequence_height_active_measured": seen,
		"particles": grass.particle_count()})
	_expect(ok, "grass altitude cutoff sequence wrong: %s" % JSON.stringify(seen))


func _check_colliders() -> void:
	var streamer: InstanceColliderStreamer = world.get_node("InstanceColliderStreamer")
	var player: Node3D = world.get_node("Player")
	# Put the player in a forest cell with trees.
	var tree_pos := Vector3.INF
	var chunks := builder._load_chunks()
	for loc in chunks:
		for cell in chunks[loc].cells:
			var by_mesh: Dictionary = chunks[loc].cells[cell]
			if by_mesh.has(1) and by_mesh[1].size() > 20 * VegetationChunk.FLOATS_PER_INSTANCE:
				tree_pos = VegetationChunk.instance_transform(by_mesh[1], 0).origin
				break
		if tree_pos != Vector3.INF:
			break
	if tree_pos == Vector3.INF:
		_log("colliders", {"skipped": "no forest cell"})
		return
	player.global_position = tree_pos + Vector3(3, 1, 0)
	streamer.process_mode = Node.PROCESS_MODE_INHERIT
	streamer._last_center = Vector3.INF
	var t0 := Time.get_ticks_usec()
	await physics_frame
	await physics_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var shapes := 0
	for cs in streamer._pool:
		if not cs.disabled:
			shapes += 1
	_log("colliders", {"active_colliders": streamer.active_count, "enabled_shapes": shapes,
		"cells_indexed": streamer.indexed_regions, "first_index_ms": ms})
	_expect(streamer.active_count > 0, "no instance colliders built from chunk data")
	streamer.process_mode = Node.PROCESS_MODE_DISABLED


# ------------------------------------------------------------------------------

func _settle(max_frames: int) -> Dictionary:
	var worst := 0.0
	var first := 0.0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	for i in max_frames:
		_last_usec = Time.get_ticks_usec()
		await process_frame
		var ms := (Time.get_ticks_usec() - _last_usec) / 1000.0
		if i == 0:
			first = ms
		worst = maxf(worst, ms)
		frames += 1
		if veg.is_settled() and i >= 2:
			break
	return {"frames": frames, "ms": (Time.get_ticks_usec() - t0) / 1000.0, "worst": worst, "first": first}


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame


func _map_size() -> float:
	return terrain.region_size * terrain.vertex_spacing * sqrt(float(terrain.data.get_region_count()))


func _road_center() -> Vector3:
	var cfg := builder.config
	if cfg and cfg.main_road.size() > 4:
		var w := cfg.main_road[4] * cfg.half_size()
		return Vector3(w.x, 0, w.y)
	return Vector3.ZERO


func _ground_y(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _place(pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	var up := Vector3.UP if absf((look - pos).normalized().y) < 0.99 else Vector3.FORWARD
	cam.look_at(look, up)


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://docs/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png("%s/vegtest_%s_%s.png" % [dir, opts.get("tag", "vegtest"), name])

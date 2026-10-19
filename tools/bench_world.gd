## Fast world benchmark: one process per map, fixed camera stations, several layer
## scenarios in sequence, automatic abort of failing scenarios.
##
##   Godot.exe --path . --resolution 1600x900 --script res://tools/bench_world.gd -- \
##       --scene=res://scenes/world/tile_8km.tscn --tag=tile_8km \
##       [--scenarios=full,trees,particles,roads,terrain] [--shots]
##       [--particle-radius=60] [--particle-spacing=0.5] [--max-vram-mb=7400]
##
## Scenarios run heaviest first, because layers can only be removed in-process:
##   full       everything the map contains (terrain, roads, all instanced vegetation)
##   trees      stored grass removed (trees, bushes, rocks remain)
##   particles  trees + Terrain3D camera-following GPU particle grass
##   roads      all vegetation removed (terrain + roads)
##   terrain    roads removed (terrain only)
## Each scenario visits the stations with a short warm-up and measurement window and
## finishes with a camera-jump test. Output: res://benchmarks/raw/bench_<tag>.json
##
## The longer camera-route benchmark (WorldDiagnostics --benchmark) is kept as an
## optional regression test.
extends SceneTree

const PARTICLES_SCENE := "res://addons/terrain_3d/extras/particle_example/Terrain3DParticles.tscn"
const WARMUP := 60
const MEASURE := 180
## Abort a scenario after this many rendering-resource errors.
const MAX_RENDER_ERRORS := 200

var opts := {}
var world: Node3D
var terrain: Terrain3D
var cfg: WorldConfig
var cam: Camera3D
var report := {}
var particles: Node3D
var errors: ErrorCounter
var _last_usec := 0
var _scenario := ""
## Per-scenario abort state, checked after every frame.
var _abort := ""
var _sc_start_usec := 0
var _sc_err0 := 0
var _budget_s := 45.0
var _max_vram := 7400.0
var _slow_frames := 0


class ErrorCounter extends Logger:
	var lock := Mutex.new()
	var render_errors := 0
	var other_errors := 0
	var samples: Dictionary = {}

	func _log_error(function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _backtrace: Array[ScriptBacktrace]) -> void:
		var msg := rationale if rationale != "" else code
		lock.lock()
		if "descriptor" in msg or "uniform set" in msg.to_lower() or "Uniforms were never supplied" in msg \
				or "device" in msg.to_lower() and ("lost" in msg or "removed" in msg):
			render_errors += 1
		else:
			other_errors += 1
		if samples.size() < 12 and not samples.has(msg):
			samples[msg] = function
		lock.unlock()

	func take() -> Dictionary:
		lock.lock()
		var d := {"render_errors": render_errors, "other_errors": other_errors}
		lock.unlock()
		return d


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else true
	errors = ErrorCounter.new()
	OS.add_logger(errors)
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var t0 := Time.get_ticks_msec()
	var ps: PackedScene = load(opts.get("scene", "res://scenes/world/test_2km.tscn"))
	var t_loaded := Time.get_ticks_msec()
	world = ps.instantiate()
	terrain = world.get_node("Terrain3D")
	if opts.has("max-lod"):
		# Experiment: fewer LODs per mesh -> fewer MultiMeshes (cells x LODs). Applied
		# before the terrain enters the tree so no MultiMesh is built twice.
		var max_lod := int(opts["max-lod"])
		for id in terrain.assets.get_mesh_count():
			var ma: Terrain3DMeshAsset = terrain.assets.get_mesh_asset(id)
			if ma and ma.last_lod > max_lod:
				var far_range := ma.get_lod_range(ma.last_lod)
				ma.last_lod = max_lod
				ma.set_lod_range(max_lod, far_range)
				ma.last_shadow_lod = mini(ma.last_shadow_lod, max_lod)
	root.add_child(world)
	cfg = world.get_node("WorldBuilder").config
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

	report.tag = opts.get("tag", "bench")
	report.scene = opts.get("scene")
	report.synthetic_tiled = String(report.scene).contains("tile_")
	report.map = {"size_m": _map_size(), "regions": terrain.data.get_region_count(),
		"region_size": terrain.region_size, "vertex_spacing": terrain.vertex_spacing}
	report.machine = {"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"window": DisplayServer.window_get_size(), "godot": Engine.get_version_info().string,
		"max_lod_option": opts.get("max-lod", "asset default"),
		"d3d12_max_resource_descriptors": ProjectSettings.get_setting("rendering/rendering_device/d3d12/max_resource_descriptors")}
	report.load = {"scene_load_ms": t_loaded - t0, "instantiate_5_frames_ms": Time.get_ticks_msec() - t_loaded,
		"errors": errors.take()}
	report.instances = _instance_census()
	report.terrain_map_arrays = _map_arrays()
	report.scenarios = {}

	_max_vram = float(opts.get("max-vram-mb", 7400.0))
	_budget_s = float(opts.get("scenario-budget", 45.0))
	var list: PackedStringArray = String(opts.get("scenarios", "full,trees,particles,roads,terrain")).split(",")
	print("BENCH stage loaded %d ms" % (Time.get_ticks_msec() - t0))
	for sc in list:
		_scenario = sc
		print("BENCH stage scenario ", sc)
		var e0: Dictionary = errors.take()
		_sc_err0 = e0.render_errors
		_sc_start_usec = Time.get_ticks_usec()
		_abort = ""
		_slow_frames = 0
		_apply(sc)
		var t_apply := (Time.get_ticks_usec() - _sc_start_usec) / 1000.0
		await _frames(30)
		var r := {"resources": _resources(), "stations": {}, "apply_ms": t_apply}
		for st in _stations():
			if _abort != "":
				break
			var res := await _station(st)
			if _abort == "":
				r.stations[st.name] = res
			else:
				r.stations[st.name] = {"aborted_during": true, "partial": res}
		if _abort == "":
			r.jumps = await _jumps()
		r.aborted = _abort
		r.elapsed_s = (Time.get_ticks_usec() - _sc_start_usec) / 1e6
		var e_end: Dictionary = errors.take()
		r.render_errors = e_end.render_errors - e0.render_errors
		r.resources_end = _resources()
		report.scenarios[sc] = r
		print("BENCH %s/%s %s" % [report.tag, sc, JSON.stringify(_brief(r))])
	if opts.has("region-churn"):
		report.region_churn = await _region_churn()
		print("BENCH region-churn ", JSON.stringify(report.region_churn))
	report.error_samples = errors.samples
	var out := "res://benchmarks/raw/bench_%s.json" % report.tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path(out), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("BENCH done ", out)
	quit()


func _map_size() -> float:
	return terrain.region_size * terrain.vertex_spacing * sqrt(float(terrain.data.get_region_count()))


# ------------------------------------------------------------------------------
# Scenarios
# ------------------------------------------------------------------------------

func _apply(sc: String) -> void:
	match sc:
		"full":
			pass
		"trees":
			_strip([0])
		"particles":
			_strip([0])
			if particles == null:
				particles = load(PARTICLES_SCENE).instantiate()
				terrain.add_child(particles)
				var radius := float(opts.get("particle-radius", 60.0))
				particles.grid_width = 5
				particles.cell_width = clampf(radius * 2.0 / 5.0, 8.0, 256.0)
				particles.instance_spacing = float(opts.get("particle-spacing", 0.5))
		"roads":
			_strip([0, 1, 2, 3, 4, 5, 6])
			if particles:
				particles.free()
				particles = null
		"terrain":
			_strip([0, 1, 2, 3, 4, 5, 6])
			if particles:
				particles.free()
				particles = null
			var roads := world.get_node_or_null("Roads")
			if roads:
				roads.free()


func _strip(ids: Array) -> void:
	# clear_by_mesh() frees that mesh's MultiMeshes. A full update_mmis(true) rebuild
	# afterwards re-creates every remaining MultiMesh and was seen to double VRAM.
	for id in ids:
		terrain.instancer.clear_by_mesh(id)


# ------------------------------------------------------------------------------
# Stations
# ------------------------------------------------------------------------------

func _stations() -> Array:
	var hs := _map_size() * 0.5
	var c := _road_center()
	var far := Vector3(hs * 0.92, 0, hs * 0.92)
	var fov_half := deg_to_rad(cam.fov * 0.5)
	var strategic_alt := minf(hs / tan(fov_half) * 1.05, 25000.0)
	return [
		{"name": "fps_center", "pos": c + Vector3(0, 1.8, 0), "look": c + Vector3(60, 0.5, 8), "ground": true},
		{"name": "fps_far_corner", "pos": far + Vector3(0, 1.8, 0), "look": far + Vector3(-60, 0.5, -10), "ground": true},
		{"name": "rts_150m", "pos": c + Vector3(0, 150, 105), "look": c, "ground": false},
		{"name": "rts_600m", "pos": c + Vector3(0, 600, 420), "look": c, "ground": false},
		{"name": "strategic", "pos": Vector3(0, strategic_alt, 1.0), "look": Vector3.ZERO, "ground": false},
	]


func _road_center() -> Vector3:
	var p := Vector3.ZERO
	if cfg and cfg.main_road.size() > 4:
		var w := cfg.main_road[4] * cfg.half_size()
		p = Vector3(w.x, 0, w.y)
	return p


func _ground_y(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _place(st: Dictionary) -> void:
	var pos: Vector3 = st.pos
	var look: Vector3 = st.look
	if st.ground:
		pos.y += _ground_y(pos)
		look.y += _ground_y(look)
	else:
		look.y = _ground_y(look)
		pos.y += look.y
	cam.global_position = pos
	var up := Vector3.UP if absf((look - pos).normalized().y) < 0.99 else Vector3.FORWARD
	cam.look_at(look, up)


func _station(st: Dictionary) -> Dictionary:
	_place(st)
	await _frames(WARMUP)
	var ms := PackedFloat32Array()
	var gpu := PackedFloat32Array()
	var cpu := PackedFloat32Array()
	var vp := root.get_viewport_rid()
	for i in MEASURE:
		if _abort != "":
			break
		_last_usec = Time.get_ticks_usec()
		await process_frame
		ms.append((Time.get_ticks_usec() - _last_usec) / 1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		_check()
	if ms.is_empty():
		return {"frames": 0}
	if opts.has("shots"):
		_shot(st.name)
	var r := _pct(ms)
	r.frames = ms.size()
	r.gpu_ms = _pct(gpu)
	r.cpu_render_ms = _pct(cpu)
	r.draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	r.objects_in_frame = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	r.primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	r.video_mem_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	return r


## Unit switching: teleport between 8 spots across the whole map and record the worst
## frame in the first 10 frames after each jump.
func _jumps() -> Dictionary:
	var hs := _map_size() * 0.45
	var spots := [Vector3(-hs, 0, -hs), Vector3(hs, 0, hs), Vector3(-hs, 0, hs), Vector3(hs, 0, -hs),
		Vector3.ZERO, Vector3(-hs, 0, 0), Vector3(hs, 0, 0), Vector3(0, 0, -hs)]
	var worst := PackedFloat32Array()
	for s in spots:
		_place({"pos": s + Vector3(0, 1.8, 0), "look": s + Vector3(40, 0.5, 10), "ground": true})
		var w := 0.0
		for i in 10:
			_last_usec = Time.get_ticks_usec()
			await process_frame
			w = maxf(w, (Time.get_ticks_usec() - _last_usec) / 1000.0)
			if _check():
				break
		worst.append(w)
	var mx := 0.0
	for v in worst:
		mx = maxf(mx, v)
	return {"worst_ms_per_jump": worst, "max_ms": mx}


# ------------------------------------------------------------------------------
# Counting
# ------------------------------------------------------------------------------

## Cost of the Terrain3D 1.0 API operations a region-window streamer would use:
## unload a region and load it back from disk (Terrain3DData.remove_regionl /
## load_region with update=true, which rebuilds the map texture arrays).
## Measures wall time of the call and the next frame. Not a streaming system.
func _region_churn() -> Dictionary:
	var dir := terrain.data_directory
	var hs := _map_size() * 0.5
	var loc: Vector2i = terrain.data.get_region_location(Vector3(hs - 100.0, 0, hs - 100.0))
	var runs := []
	for i in 3:
		var t0 := Time.get_ticks_usec()
		terrain.data.remove_regionl(loc, true)
		var t_rm := Time.get_ticks_usec()
		_last_usec = t_rm
		await process_frame
		var t_f1 := Time.get_ticks_usec()
		terrain.data.load_region(loc, dir, true)
		var t_ld := Time.get_ticks_usec()
		_last_usec = t_ld
		await process_frame
		var t_f2 := Time.get_ticks_usec()
		runs.append({"remove_call_ms": (t_rm - t0) / 1000.0, "frame_after_remove_ms": (t_f1 - t_rm) / 1000.0,
			"load_call_ms": (t_ld - t_f1) / 1000.0, "frame_after_load_ms": (t_f2 - t_ld) / 1000.0,
			"regions_now": terrain.data.get_region_count()})
		await _frames(10)
	return {"region": loc, "regions_total": terrain.data.get_region_count(), "runs": runs}


## Expected MultiMesh count from the stored data: Terrain3D groups instances in 32 m
## cells per region and keeps one MultiMesh per (cell, mesh, LOD).
func _instance_census() -> Dictionary:
	var per_mesh := {}
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		var inst: Dictionary = region.get_instances()
		for mesh_id in inst:
			var cells: Dictionary = inst[mesh_id]
			var d: Dictionary = per_mesh.get(mesh_id, {"instances": 0, "cells": 0})
			d.cells += cells.size()
			for cell in cells:
				d.instances += cells[cell][0].size()
			per_mesh[mesh_id] = d
	var expected_mm := 0
	for mesh_id in per_mesh:
		var ma: Terrain3DMeshAsset = terrain.assets.get_mesh_asset(mesh_id)
		var lods := ma.get_lod_count() if ma else 1
		per_mesh[mesh_id].lods = lods
		per_mesh[mesh_id].name = ma.name if ma else "?"
		expected_mm += per_mesh[mesh_id].cells * lods
	return {"per_mesh": per_mesh, "expected_multimeshes_cells_x_lods": expected_mm}


## Layer and mip counts of Terrain3D's region map texture arrays (D3D12 counts
## layers x mips as subresources; Godot 4.7.2 aborts above 4096 per resource).
func _map_arrays() -> Dictionary:
	var out := {}
	var rids := {"height": terrain.data.get_height_maps_rid(), "control": terrain.data.get_control_maps_rid(),
		"color": terrain.data.get_color_maps_rid()}
	for k in rids:
		var rid: RID = rids[k]
		if not rid.is_valid():
			continue
		var layer0: Image = RenderingServer.texture_2d_layer_get(rid, 0)
		var layers := terrain.data.get_region_count()
		var mips := layer0.get_mipmap_count() + 1 if layer0 else -1
		out[k] = {"layers": layers, "mip_levels": mips, "format": layer0.get_format() if layer0 else -1,
			"size": layer0.get_size() if layer0 else Vector2i.ZERO, "subresources": layers * mips,
			"approx_mb": _array_mb(layer0, layers)}
	return out


func _array_mb(img: Image, layers: int) -> float:
	if img == null:
		return 0.0
	return img.get_data_size() * layers / 1048576.0


func _resources() -> Dictionary:
	var mmi := 0
	var inst_total := 0
	for n in _all(terrain):
		if n is MultiMeshInstance3D:
			mmi += 1
			var mm: MultiMesh = n.multimesh
			if mm:
				inst_total += mm.instance_count
	var gp := 0
	if particles:
		for n in particles.find_children("*", "GPUParticles3D", true, false):
			gp += (n as GPUParticles3D).amount
	return {
		"multimesh_instance_nodes": mmi, "multimesh_instances_total": inst_total,
		"gpu_particles": gp,
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buffer_mem_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}


func _all(n: Node) -> Array:
	var out := []
	for ch in n.get_children(true):
		out.append(ch)
		out.append_array(_all(ch))
	return out


func _pct(a: PackedFloat32Array) -> Dictionary:
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	var sum := 0.0
	for v in a:
		sum += v
	return {"avg": sum / n, "p50": s[n / 2], "p95": s[int(n * 0.95)], "p99": s[int(n * 0.99)], "max": s[n - 1]}


func _brief(r: Dictionary) -> Dictionary:
	var b := {"aborted": r.aborted, "render_errors": r.render_errors,
		"vram": snappedf(r.resources.video_mem_mb, 1), "mmi": r.resources.multimesh_instance_nodes}
	for st in r.stations:
		var s: Dictionary = r.stations[st]
		if s.has("avg"):
			b[st] = "%.1fms p99 %.1f gpu %.1f" % [s.avg, s.p99, s.gpu_ms.avg]
		else:
			b[st] = "aborted"
	if r.has("jumps"):
		b.jump_max_ms = snappedf(r.jumps.max_ms, 0.1)
	return b


func _shot(station: String) -> void:
	var dir := ProjectSettings.globalize_path("res://docs/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png("%s/bench_%s_%s_%s.png" % [dir, report.tag, _scenario, station])


func _frames(n: int) -> void:
	for i in n:
		_last_usec = Time.get_ticks_usec()
		await process_frame
		if _check():
			return


## Returns true (and sets _abort) when the current scenario must stop: repeated
## rendering-resource errors, VRAM pressure, sustained multi-second frames or the
## scenario time budget.
func _check() -> bool:
	if _abort != "" or _sc_start_usec == 0:
		return _abort != ""
	var frame_ms := (Time.get_ticks_usec() - _last_usec) / 1000.0
	_slow_frames = _slow_frames + 1 if frame_ms > 1000.0 else 0
	var e: Dictionary = errors.take()
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	if e.render_errors - _sc_err0 > MAX_RENDER_ERRORS:
		_abort = "render errors: %d" % (e.render_errors - _sc_err0)
	elif vram > _max_vram:
		_abort = "video memory %.0f MB above %.0f MB" % [vram, _max_vram]
	elif _slow_frames >= 3:
		_abort = "3 consecutive frames over 1 s"
	elif (Time.get_ticks_usec() - _sc_start_usec) / 1e6 > _budget_s:
		_abort = "scenario time budget %.0f s exceeded" % _budget_s
	return _abort != ""

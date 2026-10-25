## VISUAL-02 world survey: fixed camera positions across the whole 20 km reference world (not only the New Game valley), the
## same conditions in every run, for before / after screenshots and frame rates per view.
##
##   Godot.exe --path . --fullscreen --log-file v2.log res://scenes/game/world_ref_20km.tscn -- --scenario=new_game --visual02-test [--shots] --only survey [--shot-dir=res://docs/visual02/baseline] [--shot-tag=before]
##
## survey: the 15 world views with a free camera (HUD hidden), then the tactical camera over a base, first person and the
## strategic map. Prints "V2 <check> <json>", writes res://benchmarks/raw/visual02_test.json and (with --shots) PNGs.
class_name Visual02SelfTest
extends Gameplay04SelfTest

const CHECKS_V2: Array[String] = ["survey", "veg_stats"]

## name, eye (x, height above ground, z), target (x, height above ground, z), field of view. World coordinates (+X east,
## +Z south); the places were chosen from the generator's maps (see docs/VISUAL-02_REPORT.md, section 2).
const VIEWS := [
	["01_meadow", Vector3(7600, 8, -3000), Vector3(7850, 0, -3250), 60.0],
	["02_dense_forest", Vector3(-5850, 1.7, -1914), Vector3(-5810, 2.5, -1880), 70.0],
	["03_sparse_forest", Vector3(6436, 1.8, 2520), Vector3(6496, 2.0, 2560), 70.0],
	["04_forest_edge", Vector3(7275, 2.0, -1700), Vector3(7275, 4.0, -1540), 65.0],
	["05_farmland", Vector3(4000, 25, -1150), Vector3(4250, 0, -800), 60.0],
	["06_settlement", Vector3(-4150, 45, 50), Vector3(-4000, 0, -100), 60.0],
	["06b_village_street", Vector3(-4075, 1.8, -40), Vector3(-3995, 3.0, -115), 65.0],
	["07_road_forest", Vector3(4633, 2.2, -3503), Vector3(4815, 2.0, -3571), 65.0],
	["08_road_open", Vector3(3826, 2.2, 82), Vector3(3783, 2.0, 275), 65.0],
	["09_river", Vector3(160, 8, -700), Vector3(100, 0, -1100), 65.0],
	["10_foothills", Vector3(2900, 30, -7600), Vector3(6500, 150, -7000), 60.0],
	["11_valley", Vector3(-600, 80, -3200), Vector3(300, 0, 1500), 60.0],
	["13_rts_high", Vector3(1000, 900, 3000), Vector3(1000, 0, 2300), 55.0],
	["15_long_distance", Vector3(5900, 70, -5900), Vector3(-2000, 0, 2000), 55.0],
]

## Suffix of the screenshots (before / after a visual change).
var shot_tag := ""
var _cam: Camera3D
## --views=05,13: only the survey views whose names start with these prefixes (iteration); empty = all.
var _views: PackedStringArray = []


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/visual02/baseline"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
		elif a.begins_with("--shot-tag="):
			shot_tag = a.trim_prefix("--shot-tag=")
		elif a.begins_with("--views="):
			_views = a.trim_prefix("--views=").split(",")
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	SoldierBody.require_mouse_capture = false
	tree.create_timer(1200.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	for n in CHECKS_V2:
		if only.has(n):
			_log(n, await call("_" + n))
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("V2 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/visual02_test%s.json" % (("_" + shot_tag) if shot_tag != "" else "")), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("V2 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


func _ground(x: float, z: float) -> float:
	var h := demo.terrain.data.get_height(Vector3(x, 0, z))
	return h if is_finite(h) else 0.0


func _set_hud(on: bool) -> void:
	for c in demo.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = on
	demo.hud.visible = on


## The free survey camera at an eye point looking at a target (heights above the ground there).
func _look(eye: Vector3, target: Vector3, fov: float) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "Visual02Camera"
		_cam.far = 16000.0
		_cam.near = 0.1
		demo.add_child(_cam)
	# In RTS mode DetailManager keeps the terrain camera on its anchor, which follows the tactical camera's focus: move the
	# focus to the eye so the terrain clipmap, collision and streaming are centred on the view.
	demo.rts_camera.frame(Vector3(eye.x, 0, eye.z), 0.0, 40.0)
	await _physics(2)
	var e := Vector3(eye.x, _ground(eye.x, eye.z) + eye.y, eye.z)
	var t := Vector3(target.x, _ground(target.x, target.z) + target.y, target.z)
	_cam.fov = fov
	_cam.global_position = e
	_cam.look_at(t, Vector3.UP)
	_cam.current = true


func _survey() -> Dictionary:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo.sim.brain.enabled = false
	var tag := ("_" + shot_tag) if shot_tag != "" else ""
	var out := {}
	_set_hud(false)
	for v: Array in VIEWS:
		if not _views.is_empty() and not Array(_views).any(func(p: String) -> bool: return String(v[0]).begins_with(p)):
			continue
		await _look(v[1], v[2], v[3])
		# Streaming (terrain LOD, vegetation chunks on a thread, grass) settles in a few seconds after a jump.
		await _seconds(5.0)
		var fps := await _measure_fps()
		out[v[0]] = {"fps": fps, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
		_png(String(v[0]) + tag)
	if _cam:
		_cam.current = false
	_set_hud(true)
	if not _views.is_empty() and not Array(_views).any(func(p: String) -> bool: return p.begins_with("1") and int(p) >= 12):
		demo.sim.brain.enabled = true
		return out
	demo.game.enter_rts()
	# 12: the tactical camera over a small base east of the start (the same structures as the GAMEPLAY-05 tour).
	var pf := _war().player_faction
	var sq: SquadState = _player_squads()[0]
	var start := demo.sim.war.squad_center(sq)
	var base := start + Vector3(70, 0, 10)
	for e: Array in [[&"command_post", Vector3(0, 0, 0)], [&"supply_depot", Vector3(-22, 0, 10)], [&"guard_tower", Vector3(18, 0, -18)],
			[&"sandbag_fighting_position", Vector3(10, 0, -26)], [&"fighting_position", Vector3(-14, 0, -24)], [&"mg_emplacement", Vector3(26, 0, 4)]]:
		var p := _spot(e[0], base + (e[1] as Vector3), [0.0, 6.0, 12.0], 8)
		if p.is_finite():
			_add_built(e[0], p, Vector3(0, 0, -1), pf)
	var rig := demo.rts_camera
	await _frame(base, 55.0, 0.6)
	rig.pitch_offset = deg_to_rad(30.0) - rig._base_pitch()
	rig._update_transform()
	await _seconds(3.0)
	out["12_base_rts"] = {"fps": await _measure_fps()}
	_png("12_base_rts" + tag)
	rig.pitch_offset = 0.0
	# The tactical camera at its normal height over the start valley.
	await _frame(start, 160.0, 0.0)
	await _seconds(3.0)
	out["13b_rts_valley"] = {"fps": await _measure_fps()}
	_png("13b_rts_valley" + tag)
	# 14: first person, the squad leader.
	demo.game.possess(sq.leader_id)
	await _seconds(3.0)
	out["14_fps"] = {"fps": await _measure_fps()}
	_png("14_fps" + tag)
	demo.game.enter_rts()
	demo.toggle_map()
	await _seconds(1.5)
	_png("16_map" + tag)
	demo.toggle_map()
	demo.sim.brain.enabled = true
	return out


## Statistics of the trees the game actually planted (every chunk file): instances per mesh type, and for the trees of a
## sample of cells the nearest-neighbour spacing (its coefficient of variation: ~0.5 is natural clumping, low values a grid).
func _veg_stats() -> Dictionary:
	var dir := demo.vegetation.data_directory
	var counts := {}
	var files := 0
	var nn := PackedFloat32Array()
	var trees := [1, 2, 3, 4, 5, 6]
	for fn in DirAccess.get_files_at(dir):
		if not fn.begins_with("veg_") or not fn.ends_with(".res"):
			continue
		var ch := ResourceLoader.load(dir.path_join(fn), "", ResourceLoader.CACHE_MODE_IGNORE) as VegetationChunk
		if ch == null:
			continue
		files += 1
		var c := ch.counts_by_mesh()
		for mid in c:
			counts[mid] = int(counts.get(mid, 0)) + int(c[mid])
		# Nearest-neighbour distances in the first cell of every 4th chunk with at least 50 trees.
		if files % 4 != 0:
			continue
		for cell in ch.cells:
			var pts := PackedVector2Array()
			for mid in trees:
				var buf: PackedFloat32Array = ch.cells[cell].get(mid, PackedFloat32Array())
				for k in range(0, buf.size(), VegetationChunk.FLOATS_PER_INSTANCE):
					pts.append(Vector2(buf[k + 3], buf[k + 11]))
			if pts.size() < 50:
				continue
			for i in mini(pts.size(), 200):
				var best := INF
				for j in pts.size():
					if i != j:
						best = minf(best, pts[i].distance_squared_to(pts[j]))
				nn.append(sqrt(best))
			break
	var mean := 0.0
	for d in nn:
		mean += d
	mean /= maxf(nn.size(), 1)
	var var_s := 0.0
	for d in nn:
		var_s += (d - mean) * (d - mean)
	var sd := sqrt(var_s / maxf(nn.size(), 1))
	return {"files": files, "per_mesh": counts, "nn_mean_m": snappedf(mean, 0.01), "nn_cv": snappedf(sd / maxf(mean, 0.001), 0.001), "nn_samples": nn.size()}


## Frames per second over two real seconds.
func _measure_fps() -> float:
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await tree.create_timer(2.0, true, false, true).timeout
	return snappedf((Engine.get_frames_drawn() - f0) * 1000.0 / maxf(Time.get_ticks_msec() - t0, 1.0), 0.1)

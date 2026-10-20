## COMBAT-02 scaling measurements on the reference world (fast, about 6 minutes).
##
##   Godot.exe --path . --resolution 1600x900 res://scenes/game/world_ref_20km.tscn -- --combat-scale-test [--shots]
##
## Spawns N v N infantry (squads of 10 in line, squads side by side, 120 m apart) on the
## COMBAT-01b meadow and on a second spot about 3 km away, and measures frames, brain time,
## sight checks, shots and memory with the camera at the fight, far away, and jumping
## between two simultaneous battles. Health is raised so nobody dies during a measurement
## window (weapons and accuracy unchanged). Prints "SCALE <case> <json>" and writes
## res://benchmarks/raw/combat_scale_test.json.
class_name CombatScaleSelfTest
extends CombatAISelfTest

var area2 := Vector3.INF


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/combat02"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	lof = combat.line
	brain = demo.sim.brain
	brain.enabled = true
	def = combat.weapon(&"rifle")
	tree.create_timer(1200.0).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish in 1200 s")
		_finish())
	demo.sim.state.shot_fired.connect(_on_shot_rec)
	await _physics(60)
	_load_world_data()
	for u in demo.sim.state.soldiers():
		default_soldiers.append(u.position)
	_press(KEY_TAB)
	await _physics(3)
	area = _find_spot("meadow", demo.sites[0].position)
	area2 = _find_battlefield(area + Vector3(3000, 0, 0))
	brain.tactics_enabled = not "--no-tactics" in args
	_log("startup", {"area": _v(area), "area2": _v(area2) if area2.is_finite() else "none", "dist_km": snappedf(_flat(area, area2) / 1000.0, 0.01) if area2.is_finite() else -1})
	demo.rts_camera.frame(area, 0.0, 130.0)
	await _seconds(2.0)
	_log("baseline", await _measure_fight(5.0))
	var only := args.find("--scale-only")
	var cases: Array = [16, 50, 100]
	if only >= 0 and only + 1 < args.size():
		cases = [int(args[only + 1])]
	for n: int in cases:
		_log("battle_%dv%d_at_fight" % [n, n], await _battle([area], n, "at"))
		_log("battle_%dv%d_far" % [n, n], await _battle([area], n, "far"))
	if area2.is_finite() and only < 0:
		_log("two_battles_50v50", await _battle([area, area2], 50, "jump"))
	_finish()


## A second battlefield: open enough (few trunks or houses within 50 m), dry, not too
## steep, at least 1 km from the default soldiers, searched outward from center.
func _find_battlefield(center: Vector3) -> Vector3:
	for r: float in [0.0, 300.0, 600.0, 900.0, 1300.0, 1800.0, 2400.0]:
		var n := 1 if r == 0.0 else clampi(int(r / 50.0), 12, 64)
		for k in n:
			var a := k * TAU / n
			var p := demo.on_ground(center.x + cos(a) * r, center.z + sin(a) * r, 0.0)
			if absf(p.x) > 9000.0 or absf(p.z) > 9000.0 or not _far_from_soldiers(p, 1000.0):
				continue
			var s := _solids(p, 50.0)
			if s.trees + s.houses + s.rocks <= 6 and _dry(p, 70.0) and _height_range(p, 60.0) < 8.0:
				return p
	return Vector3.INF


## Squads of up to 10 per side; returns the squads.
func _spawn_battle(c: Vector3, n: int, tag: String) -> Array:
	var out := []
	var per := 10
	var count := ceili(float(n) / per)
	# At most 5 squads side by side (a 180 m front); more stand in a second rank 15 m behind.
	var per_rank := mini(count, 5)
	for k in count:
		var size := mini(per, n - k * per)
		var rank := k / per_rank
		var off := Vector3((k % per_rank - (per_rank - 1) * 0.5) * (per * 3.0 + 6.0), 0, rank * 15.0)
		out.append(_squad("%sN%d" % [tag, k], 0, size, c + Vector3(0, 0, 60) + off, 0.0))
		out.append(_squad("%sS%d" % [tag, k], 1, size, c + Vector3(0, 0, -60) - off, PI))
	for sq: SquadState in out:
		_tough(sq, 1.0e6)
	return out


## mode: "at" camera at the (first) battle, "far" camera 12 km away, "jump" camera jumps
## between the battles every 3 s.
func _battle(centers: Array, n: int, mode: String) -> Dictionary:
	var squads := []
	for i in centers.size():
		squads.append_array(_spawn_battle(centers[i], n, "B%d" % i))
	var mem0 := OS.get_static_memory_usage()
	match mode:
		"at":
			demo.rts_camera.frame(centers[0], 0.0, 150.0)
		_:
			demo.rts_camera.frame(demo.sites[2].position, 0.0, 130.0)
	# Cold start: the first seconds (vegetation buckets, first sightings).
	brain.reset_stats()
	var t0 := Time.get_ticks_msec()
	var cold_max_frame := 0.0
	while Time.get_ticks_msec() - t0 < 3000:
		var t := Time.get_ticks_usec()
		await tree.process_frame
		cold_max_frame = maxf(cold_max_frame, (Time.get_ticks_usec() - t) / 1000.0)
	var cold := {"brain_us_max": brain.update_usec_max, "frame_ms_max": snappedf(cold_max_frame, 0.01)}
	var m: Dictionary
	if mode == "jump":
		var parts := []
		for k in 4:
			demo.rts_camera.frame(centers[k % centers.size()], 0.0, 150.0)
			parts.append(await _measure_fight(3.0))
		m = parts[0].duplicate()
		for key in ["frame_ms_avg", "brain_update_us_avg", "sight_checks_per_frame"]:
			var s := 0.0
			for p: Dictionary in parts:
				s += p[key]
			m[key] = snappedf(s / parts.size(), 0.01)
		for key in ["frame_ms_p99", "frame_ms_max", "brain_update_us_max", "frames_over_33ms", "bodies"]:
			var mx := 0.0
			for p: Dictionary in parts:
				mx = maxf(mx, p[key])
			m[key] = mx
		m["shots"] = parts.reduce(func(a: int, p: Dictionary) -> int: return a + p.shots, 0)
		m["parts"] = parts.map(func(p: Dictionary) -> Array: return [p.frame_ms_avg, p.frame_ms_p99, p.frame_ms_max, p.bodies, p.shots])
	else:
		m = await _measure_fight(8.0)
	if shots and mode == "at":
		_frame_action(centers[0], PI * 0.5, 200.0)
		await _snap_firing("05_scale_%dv%d_rts" % [n, n])
	m["soldiers"] = n * 2 * centers.size()
	m["camera"] = mode
	m["cold_start_3s"] = cold
	m["static_memory_mb"] = snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1)
	m["memory_added_mb"] = snappedf((OS.get_static_memory_usage() - mem0) / 1048576.0, 0.1)
	m["engaging"] = m.states.get("engaging", 0)
	await _clear()
	demo.rts_camera.frame(area, 0.0, 130.0)
	await _seconds(1.5)
	return m


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("SCALE %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/combat_scale_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("SCALE %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/c02_%s.jpg" % [_shot_dir, shot_name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("SCALE shot: ", path)

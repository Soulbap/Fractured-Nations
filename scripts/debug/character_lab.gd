## CHARACTER-01 lab: in-engine inspection and short validation of the infantry character.
##
##   Godot.exe --path . --resolution 1600x900 res://scenes/characters/character_lab.tscn -- [mode]
##
## Modes (after "--"):
##   --shots      screenshots of every loadout: neutral, walking, running, sprint, crouch,
##                close FPS distance, RTS distance, LOD bands -> docs/character01/godot/
##   --checks     attachment / alignment / LOD / sharing checks, prints "CHAR <check> <json>"
##   --perf N     N soldiers (mixed loadouts) walking in a grid; frame time, draw calls,
##                memory and animation cost -> benchmarks/raw/character_perf.json
## Without a mode it is an interactive viewer: 1-4 speed (idle/walk/run/sprint), C crouch,
## Q/E orbit, wheel zoom, L cycles loadout highlight.
extends Node3D

const SHOT_DIR := "res://docs/character01/godot"
const LOADOUTS := ["A_standard", "B_heavy", "C_recon"]

var chars: Array[InfantryCharacter] = []
var cam: Camera3D
var sun: DirectionalLight3D
var _orbit := 0.6
var _dist := 4.5
var _height := 1.2
var _target := Vector3(0, 1.0, 0)
var _speed := 0.0
var _results := {}
var _failures: Array[String] = []


func _ready() -> void:
	_build_env()
	var args := OS.get_cmdline_user_args()
	if "--perf" in args:
		var i := args.find("--perf")
		var n := int(args[i + 1]) if i + 1 < args.size() else 60
		_run_perf.call_deferred(n, "--old" in args)
		return
	for i in LOADOUTS.size():
		var c := _spawn(LOADOUTS[i], 0, Vector3((i - 1) * 1.6, 0, 0), 0.0)
		chars.append(c)
	# Same loadout A for the South faction: camouflage and patch come from the material library.
	var south := _spawn("A_standard", 1, Vector3(3.2, 0, 0), 0.0)
	south.name = "A_standard_South"
	chars.append(south)
	# Far-view proxies (abstract tier) of the same loadouts, 4 m behind the line-up.
	for i in LOADOUTS.size():
		var pm := MeshInstance3D.new()
		pm.mesh = InfantryProxyMesh.get_mesh(LOADOUTS[i], 0)
		pm.name = "Proxy_" + LOADOUTS[i]
		add_child(pm)
		pm.position = Vector3((i - 1) * 1.6, 0, 4.0)
	if "--clips" in args:
		_run_clips.call_deferred()
	elif "--shots" in args:
		_run_shots.call_deferred()
	elif "--checks" in args:
		_run_checks.call_deferred()


func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.35, 0.47, 0.62)
	mat.sky_horizon_color = Color(0.68, 0.72, 0.74)
	mat.ground_horizon_color = Color(0.45, 0.43, 0.38)
	mat.ground_bottom_color = Color(0.25, 0.24, 0.2)
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.34, 0.28)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 2000.0
	add_child(cam)
	cam.current = true
	_update_cam()


func _spawn(loadout_id: String, faction: int, pos: Vector3, yaw: float) -> InfantryCharacter:
	var c := InfantryCharacter.new()
	c.name = loadout_id
	add_child(c)
	c.position = pos
	c.rotation.y = yaw
	c.setup(InfantryLoadout.by_id(loadout_id), faction)
	return c


func _update_cam() -> void:
	var off := Vector3(sin(_orbit), 0, -cos(_orbit)) * _dist
	cam.global_position = _target + off + Vector3(0, _height - _target.y + 0.5, 0)
	cam.look_at(_target)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _speed = 0.0
			KEY_2: _speed = 1.4
			KEY_3: _speed = 4.5
			KEY_4: _speed = 7.5
			KEY_C:
				for c in chars:
					c.crouched = not c.crouched
		for c in chars:
			c.debug_velocity = -c.global_basis.z * _speed
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(0.6, _dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(300.0, _dist * 1.1)
		_update_cam()


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_Q):
		_orbit -= delta
		_update_cam()
	elif Input.is_key_pressed(KEY_E):
		_orbit += delta
		_update_cam()


# ------------------------------------------------------------------------------ shots


func _set_speed(v: float, crouch := false) -> void:
	for c in chars:
		c.crouched = crouch
		c.debug_velocity = -c.global_basis.z * v


func _shot(name: String, frames := 3) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(ProjectSettings.globalize_path("%s/%s.jpg" % [SHOT_DIR, name]), 0.9)
	print("CHAR shot ", name)


func _frame(target: Vector3, dist: float, orbit: float, height: float, fov := 50.0) -> void:
	_target = target
	_dist = dist
	_orbit = orbit
	_height = height
	cam.fov = fov
	_update_cam()


func _run_shots() -> void:
	await _wait(0.5)
	# Line-up: all loadouts, neutral idle, three-quarter front and back.
	_set_speed(0.0)
	_frame(Vector3(0, 0.95, 0), 5.2, 0.45, 1.25)
	await _wait(1.0)
	await _shot("lineup_idle_front")
	_frame(Vector3(0, 0.95, 0), 5.2, PI + 0.5, 1.35)
	await _shot("lineup_idle_back")
	for state in [["walk", 1.4, false], ["run", 4.5, false], ["sprint", 7.5, false], ["crouch", 0.0, true], ["crouchwalk", 1.2, true]]:
		_set_speed(state[1], state[2])
		_frame(Vector3(0, 0.9, 0), 5.0, 1.1, 1.2)
		await _wait(0.8 + 0.37 * randf())
		for c in chars:
			print("CHAR state ", state[0], " ", c.name, " ", c.anim_state(), " crouch_param=", c.anim_tree.get("parameters/crouch/blend_amount"),
				" move_param=", c.anim_tree.get("parameters/move/blend_amount"), " pos=", c.anim_tree.get("parameters/loco/blend_position"))
		await _shot("lineup_" + state[0] + "_side")
	_set_speed(0.0)
	await _wait(0.8)
	# Close FPS inspection of each loadout (another soldier seen from 1.5 m at eye height).
	for i in LOADOUTS.size():
		var p := chars[i].global_position
		_frame(p + Vector3(0, 1.35, 0), 1.45, 0.35, 1.62, 55.0)
		await _shot("fps_close_%s" % LOADOUTS[i])
		_frame(p + Vector3(0, 1.10, 0), 2.6, PI + 0.6, 1.6, 55.0)
		await _shot("fps_close_back_%s" % LOADOUTS[i])
	var ps := chars[3].global_position
	_frame(ps + Vector3(0, 1.2, 0), 2.0, 0.5, 1.5, 55.0)
	await _shot("fps_close_A_standard_south")
	# Weapon and hands close-up while walking (alignment).
	_set_speed(1.4)
	await _wait(0.5)
	_frame(chars[0].global_position + Vector3(0.05, 1.18, -0.3), 0.9, 0.9, 1.35, 45.0)
	await _shot("closeup_weapon_hands_walk")
	_set_speed(0.0)
	await _wait(0.4)
	_frame(chars[0].global_position + Vector3(0.0, 1.15, -0.35), 0.75, -0.5, 1.30, 45.0)
	await _shot("closeup_weapon_hands_idle_left")
	_set_speed(0.0)
	# RTS distances (LOD bands): 25 m, 60 m, 120 m elevated views.
	for d in [[25.0, 14.0], [60.0, 32.0], [120.0, 65.0]]:
		_frame(Vector3(0, 0.9, 2.0), d[0], 0.6, d[1], 40.0)
		await _wait(0.3)
		await _shot("rts_%dm" % int(d[0]))
	print("CHAR shots done")
	get_tree().quit()


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		t += await _frame_delta()


func _frame_delta() -> float:
	await get_tree().process_frame
	return get_process_delta_time()


## Plays every clip directly on the AnimationPlayer (tree off) and photographs it, to
## check the exported clips independently of the blend tree.
func _run_clips() -> void:
	await _wait(0.3)
	var c := chars[0]
	c.anim_tree.active = false
	for other in chars:
		if other != c:
			other.visible = false
	_frame(c.global_position + Vector3(0, 0.9, 0), 3.2, 1.2, 1.2, 50.0)
	for clip in c.anim_player.get_animation_list():
		c.anim_player.play(clip)
		c.anim_player.seek(0.0, true)
		c.anim_player.pause()
		await _shot("clip_" + clip, 2)
	get_tree().quit()


# ------------------------------------------------------------------------------ checks


func _log(check: String, data: Dictionary) -> void:
	_results[check] = data
	print("CHAR ", check, " ", JSON.stringify(data))


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)
		push_error("CHAR FAIL: " + msg)


func _run_checks() -> void:
	await _wait(0.3)
	# 1. One skeleton and one animation set for all loadouts.
	var bone_counts := []
	var clip_sets := []
	for c in chars:
		bone_counts.append(c.skeleton.get_bone_count())
		clip_sets.append(c.anim_player.get_animation_list())
	_log("shared_rig", {"bones": bone_counts, "clips": clip_sets[0], "same_clips": clip_sets[0] == clip_sets[1] and clip_sets[1] == clip_sets[2],
		"humanoid_bones_present": _humanoid_coverage(chars[0].skeleton)})
	_expect(bone_counts[0] == bone_counts[1] and bone_counts[1] == bone_counts[2], "loadouts have different skeletons")
	_expect(clip_sets[0] == clip_sets[1], "loadouts have different clip sets")
	# 2. Equipment swap without rebuilding: change one character's loadout at runtime.
	var c0 := chars[0]
	var t0 := Time.get_ticks_usec()
	c0.setup(InfantryLoadout.by_id("B_heavy"), 0)
	var swap_ms := (Time.get_ticks_usec() - t0) / 1000.0
	await get_tree().process_frame
	var swapped := c0.pieces.has("pack_ruck") and not c0.pieces.has("pack_assault")
	c0.setup(InfantryLoadout.by_id("A_standard"), 0)
	await get_tree().process_frame
	_log("swap", {"ms": swap_ms, "swapped": swapped, "back": c0.pieces.has("pack_assault")})
	_expect(swapped, "runtime loadout swap failed")
	# 3/4. Animation + attachment alignment: support hand stays on the handguard and the
	# weapon follows the firing hand in every state; helmet stays on the head.
	var align := {}
	for state in [["idle", 0.0, false], ["walk", 1.4, false], ["run", 4.5, false], ["sprint", 7.5, false], ["crouch", 0.0, true], ["crouchwalk", 1.2, true]]:
		_set_speed(state[1], state[2])
		await _wait(0.6)
		var worst := {"support_mm": 0.0, "weapon_mm": 0.0, "helmet_mm": 0.0}
		for k in 20:
			await get_tree().process_frame
			for c in chars:
				var m := _alignment(c)
				for key in worst:
					worst[key] = maxf(worst[key], m[key])
		align[state[0]] = worst
		_expect(worst.support_mm < 15.0, "%s: support hand %.1f mm off the handguard" % [state[0], worst.support_mm])
		_expect(worst.weapon_mm < 2.0, "%s: weapon %.1f mm off the grip" % [state[0], worst.weapon_mm])
	_log("alignment", align)
	# Feet: stance foot speed vs ground (no sliding when the body moves at the clip speed).
	_set_speed(0.0)
	var slide := {}
	for state in [["v1.0", 1.0], ["v1.4", 1.4], ["v2.2", 2.2], ["v3.0", 3.0], ["v3.7", 3.7], ["v4.5", 4.5], ["v6.0", 6.0]]:
		slide[state[0]] = await _foot_slide(chars[0], state[1])
	_log("foot_slide", slide)
	# LOD ranges and material sharing.
	var mats := {}
	var lods := {0: 0, 1: 0, 2: 0}
	for c in chars:
		for mi in c.lod_meshes:
			if not is_instance_valid(mi):
				continue
			for s in mi.get_surface_override_material_count():
				var m := mi.get_surface_override_material(s)
				if m:
					mats[m.get_instance_id()] = m.resource_name
	for l in 3:
		lods[l] = chars[1].triangle_count(l)
	_log("lod_and_materials", {"unique_materials_all_loadouts": mats.size(), "material_names": mats.values(),
		"B_tris": lods, "A_tris": [chars[0].triangle_count(0), chars[0].triangle_count(1), chars[0].triangle_count(2)]})
	_expect(mats.size() <= 24, "too many unique materials (%d)" % mats.size())
	# Proxy mesh (abstract tier): one surface, built once per loadout/faction.
	var tp := Time.get_ticks_usec()
	var pm := InfantryProxyMesh.get_mesh("B_heavy", 1)
	var proxy_ms := (Time.get_ticks_usec() - tp) / 1000.0
	_log("proxy", {"surfaces": pm.get_surface_count(), "triangles": pm.get_meta("triangles", 0), "build_ms_faction1": proxy_ms,
		"aabb": str(pm.get_aabb())})
	_expect(pm.get_surface_count() == 1, "proxy mesh is not a single surface")
	_expect(pm.get_aabb().size.y > 1.6 and pm.get_aabb().size.y < 2.3, "proxy mesh height wrong: %s" % pm.get_aabb())
	_log("summary", {"failures": _failures, "pass": _failures.is_empty()})
	print("CHAR RESULT ", "PASS" if _failures.is_empty() else "FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _humanoid_coverage(sk: Skeleton3D) -> String:
	var prof := SkeletonProfileHumanoid.new()
	var found := 0
	for i in prof.bone_size:
		if sk.find_bone(prof.get_bone_name(i)) >= 0:
			found += 1
	return "%d/%d" % [found, prof.bone_size]


## Distances (mm) between where things should be and where they are this frame.
func _alignment(c: InfantryCharacter) -> Dictionary:
	var sk := c.skeleton
	var weapon: Node3D = c.pieces.get("carbine", [null])[0]
	var out := {"support_mm": 0.0, "weapon_mm": 0.0, "helmet_mm": 0.0}
	if weapon == null:
		return out
	var grip: Node3D = c.mounts.get("weapon:GRIP_Support")
	var lh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftHand"))
	# Support grip point in the hand (GRIP_IN_HAND: 0.050 along the hand axis, 0.038 along palm).
	var axis := lh.basis.y.normalized()
	var palm := -lh.basis.z.normalized()
	var hand_grip := lh.origin + axis * 0.050 + palm * 0.038
	if grip:
		out.support_mm = hand_grip.distance_to(grip.global_position) * 1000.0
	var att := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ATT_Weapon"))
	out.weapon_mm = att.origin.distance_to(weapon.global_position) * 1000.0
	var helmet: Node3D = c.pieces.get("helmet_covered", c.pieces.get("helmet_bare", [null]))[0]
	if helmet:
		var hd := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ATT_Head"))
		out.helmet_mm = hd.origin.distance_to(helmet.global_position) * 1000.0
	return out


## Moves the character at speed v for 2 s and records the horizontal world speed of the
## lower foot every frame. A planted foot is still, so the 25th percentile of those speeds
## (the planted part of each step) is the slide; 0 is ideal. Robust to swing frames.
func _foot_slide(c: InfantryCharacter, v: float) -> Dictionary:
	var sk := c.skeleton
	var start := c.global_position
	c.debug_velocity = -c.global_basis.z * v
	await _wait(0.8)
	var speeds: Array[float] = []
	var prev := {}
	var t := 0.0
	while t < 2.0:
		var dt := await _frame_delta()
		c.global_position += c.debug_velocity * dt
		t += dt
		var pts := {}
		for b in ["LeftFoot", "RightFoot"]:
			pts[b] = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin
		var low: String = "LeftFoot" if pts.LeftFoot.y < pts.RightFoot.y else "RightFoot"
		if prev.has(low) and dt > 0:
			speeds.append(Vector2(pts[low].x - prev[low].x, pts[low].z - prev[low].z).length() / dt)
		prev = pts
	c.debug_velocity = Vector3.ZERO
	c.global_position = start
	speeds.sort()
	var p25 := speeds[int(speeds.size() * 0.25)] if speeds.size() > 0 else 0.0
	return {"body_speed": v, "planted_p25_ms": snappedf(p25, 0.01), "ratio": snappedf(p25 / v, 0.01), "samples": speeds.size()}


# ------------------------------------------------------------------------------ perf


func _run_perf(n: int, old_model: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var per_row := int(ceil(sqrt(n)))
	var root := Node3D.new()
	add_child(root)
	var old_scene: PackedScene = load("res://assets/units/soldier.glb")
	var t0 := Time.get_ticks_usec()
	var nodes := []
	for i in n:
		var pos := Vector3((i % per_row) * 2.2 - per_row * 1.1, 0, (i / per_row) * 2.2 - per_row * 1.1)
		if old_model:
			var m: Node3D = old_scene.instantiate()
			root.add_child(m)
			m.position = pos
			nodes.append(m)
		else:
			var c := InfantryCharacter.new()
			root.add_child(c)
			c.position = pos
			c.setup(InfantryLoadout.by_id(LOADOUTS[i % 2]), i % 2)
			c.debug_velocity = -c.global_basis.z * (1.4 if i % 3 else 4.5)
			nodes.append(c)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var report := {"soldiers": n, "old_placeholder": old_model, "build_ms": build_ms}
	for station in [["close", 6.0, 3.0], ["mid", 30.0, 16.0], ["rts", 90.0, 55.0]]:
		_frame(Vector3(0, 0.9, 0), station[1], 0.7, station[2], 55.0)
		await _wait(1.0)
		var frames := 0
		var t := 0.0
		var worst := 0.0
		var proc := 0.0
		InfantryCharacter.anim_usec = 0
		while t < 3.0:
			var dt := await _frame_delta()
			t += dt
			frames += 1
			worst = maxf(worst, dt)
			proc += Performance.get_monitor(Performance.TIME_PROCESS)
		var anim_ms := InfantryCharacter.anim_usec / 1000.0 / frames
		report[station[0]] = {
			"avg_ms": snappedf(t / frames * 1000.0, 0.01), "worst_ms": snappedf(worst * 1000.0, 0.01),
			"process_ms": snappedf(proc / frames * 1000.0, 0.01), "anim_ms": snappedf(anim_ms, 0.001),
			"gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), 0.01),
			"cpu_render_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()), 0.01),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		}
		await _shot("perf_%s_%d_%s" % ["old" if old_model else "new", n, station[0]], 1)
	report["static_mem_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	report["video_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	report["texture_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1)
	report["buffer_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1)
	print("CHAR perf ", JSON.stringify(report))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open("res://benchmarks/raw/character_perf_%s_%d.json" % ["old" if old_model else "new", n], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	get_tree().quit()

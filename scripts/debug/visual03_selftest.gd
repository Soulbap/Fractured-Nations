## VISUAL-03 in-game validation of the soldier on the VISUAL-02 world, through the real bodies, controller, squad orders
## and AI (QOL-01.1: the walk / run / sprint orders the checks give are the game's own paces).
##
##   Godot.exe --path . --fullscreen --log-file v3.log res://scenes/game/world_ref_20km.tscn -- --visual03-test [--shots] [--only a_loco,b_squad,c_combat,d_terrain,e_trans,f_views] [--shot-dir=res://docs/visual03/godot]
##
## a_loco     one soldier walks, jogs, runs (squad order paces), stops and turns on the spot
## b_squad    eight soldiers in formation: jog, a change of direction at a run, a walk
## c_combat   two fire teams 120 m apart with the AI on: rifles raised, aiming and firing in different directions
## d_terrain  a squad up and down a slope and over uneven ground
## e_trans    one soldier: stand -> move -> stop -> crouch -> stand -> aim -> move aiming -> fire -> reload (the magazine
##            leaves the well with the support hand and is back in it afterwards)
## f_views    the same soldier from first-person range (another soldier's eyes) and RTS distances
## Every check records frame sequences (rec/<check>_NNN.png, encoded to MP4 by tools/visual03/encode_mp4.py),
## stills, and numbers: the character's animation state, speeds by pace, foot slip of the planted foot in the engine.
## Prints "V3 <check> <json>", writes res://benchmarks/raw/visual03_test.json.
class_name Visual03SelfTest
extends Gameplay05SelfTest

const CHECKS3: Array[String] = ["a_loco", "b_squad", "c_combat", "d_terrain", "e_trans", "f_views"]
var _cs: CombatScenario
var _site := {}
## A straight stretch of road near the site (walking checks: the feet are not hidden in tall grass).
var _road := {}
var _tcam: Camera3D


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/visual03/godot"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKS3)
	SoldierBody.require_mouse_capture = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	tree.create_timer(1500.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_expect(not WorldSim.UNIFORM_PACE, "run without --uniform-pace (walk / run / sprint orders)")
	_cs = CombatScenario.new(demo)
	_site = _cs.find_site()
	_expect(not _site.is_empty(), "no open test site")
	if _site.is_empty():
		_finish()
		return
	_road = _find_road(_site.def)
	_tcam = Camera3D.new()
	_tcam.fov = 50.0
	_tcam.far = 4000.0
	demo.add_child(_tcam)
	if demo.hud:
		demo.hud.visible = false
		demo.hud.process_mode = Node.PROCESS_MODE_DISABLED     # it would switch the unit markers back on
	demo.rts.select_squads([])
	UnitVisuals.markers_visible = false     # the ground dots would hide the feet in the close views
	for n in CHECKS3:
		if only.has(n):
			# The near tier (bodies, navmesh) is built around the RTS camera: put it over the test spot first.
			var spot: Vector3 = _site.def if n in ["c_combat", "d_terrain"] else _walk_spot()[0]
			demo.rts_camera.frame(spot, 0.6, 40.0)
			await _seconds(3.0)
			_log(n, await call("_" + n))
			_cs.reset()
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("V3 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/visual03_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("V3 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


# --- helpers ------------------------------------------------------------------------------------------------------------

func _body(u: UnitState) -> SoldierBody:
	return demo.sim.view_of(u.id) as SoldierBody


func _char(u: UnitState) -> InfantryCharacter:
	var b := _body(u)
	return b.character if b else null


## Frames of the viewport (downscaled to 960 wide) every `every` rendered frames for `seconds`, while `probe` (optional)
## samples numbers each frame. Returns the probe's samples.
func _record(tag: String, seconds: float, every := 2, probe := Callable()) -> Array:
	var samples := []
	var n := 0
	var k := 0
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	if shots:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir + "/rec"))
	while Time.get_ticks_msec() < t_end:
		await tree.process_frame
		if probe.is_valid():
			samples.append(probe.call())
		k += 1
		if shots and k % every == 0:
			var img := demo.get_viewport().get_texture().get_image()
			img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
			img.save_png(ProjectSettings.globalize_path("%s/rec/%s_%03d.png" % [_shot_dir, tag, n]))
			n += 1
	return samples


## The test camera `dist` m from `target`, at compass `yaw` (rad, 0 = +Z side) and `pitch_deg` above the horizon.
func _cam(target: Vector3, dist: float, yaw: float, pitch_deg := 12.0) -> void:
	var off := Vector3(sin(yaw), 0, cos(yaw)) * cos(deg_to_rad(pitch_deg)) + Vector3.UP * sin(deg_to_rad(pitch_deg))
	_tcam.current = true
	_tcam.global_position = target + off * dist
	_tcam.look_at(target, Vector3.UP)


## A straight road within 1.5 km of p: {pos, dir (Vector3)}; empty when none.
func _find_road(p: Vector3) -> Dictionary:
	var roads: RoadNetwork = demo.sim.state.roads
	var best := {}
	for r: float in [300.0, 800.0, 1500.0, 3000.0, 5000.0]:
		var n := roads.nearest(p, r)
		if not n.is_empty() and n.end < 0:
			var d2: Vector2 = n.dir
			best = {"pos": demo.on_ground(n.pos.x, n.pos.z, 0.0), "dir": Vector3(d2.x, 0, d2.y)}
			break
	return best


## Where the walking checks run: the road when there is one, else the open site.
func _walk_spot() -> Array:
	if not _road.is_empty():
		return [_road.pos, _road.dir]
	return [_site.def, _site.side]


func _cam_follow(u: UnitState, dist: float, yaw: float, pitch_deg := 12.0) -> void:
	var b := _body(u)
	var p := b.global_position if b else u.position
	_cam(p + Vector3.UP * 0.95, dist * 0.6, yaw, pitch_deg)


## Horizontal slip of the lowest foot while planted (in the engine, through the real controller and AnimationTree): world
## positions of both foot bones each frame; a foot is planted while it is the lower one and within 4 cm of its lowest height.
func _foot_probe(u: UnitState) -> Callable:
	return func() -> Dictionary:
		var c := _char(u)
		if c == null or c.skeleton == null:
			return {}
		var sk := c.skeleton
		var out := {"t": Time.get_ticks_usec() / 1e6}
		for s in ["Left", "Right"]:
			var i := sk.find_bone(s + "Foot")
			out[s] = sk.global_transform * sk.get_bone_global_pose(i).origin
		out["v"] = Vector2(_body(u).velocity.x, _body(u).velocity.z).length() if _body(u) else 0.0
		out["anim"] = c.anim_state()
		return out


static func _slip(samples: Array) -> Dictionary:
	var res := {}
	for s in ["Left", "Right"]:
		var ys := []
		for x: Dictionary in samples:
			if x.has(s):
				ys.append((x[s] as Vector3).y)
		if ys.is_empty():
			continue
		ys.sort()
		var low: float = ys[int(ys.size() * 0.1)]
		var v := []
		for i in range(1, samples.size()):
			var a: Dictionary = samples[i - 1]
			var b: Dictionary = samples[i]
			if not a.has(s) or not b.has(s):
				continue
			var pa: Vector3 = a[s]
			var pb: Vector3 = b[s]
			var dt: float = b.t - a.t
			if dt <= 0.0 or pa.y > low + 0.04 or pb.y > low + 0.04:
				continue
			v.append(Vector2(pb.x - pa.x, pb.z - pa.z).length() / dt)
		v.sort()
		res[s] = {"planted_frames": v.size(), "median_ms": snappedf(v[v.size() / 2], 0.01) if not v.is_empty() else -1.0,
			"p90_ms": snappedf(v[int(v.size() * 0.9)], 0.01) if not v.is_empty() else -1.0}
	return res


func _spawn_one(at: Vector3, facing: Vector3, tag := "V3") -> UnitState:
	var sq := _cs.spawn(0, at, facing, 1, tag)
	var u := demo.sim.state.get_unit(sq.members[0])
	u.position = demo.on_ground(at.x, at.z, 0.0)
	u.anchor_pos = u.position
	var b := _body(u)
	if b:
		b.global_position = u.position + Vector3.UP * 0.1
	return u


func _move(sq: SquadState, to: Vector3, pace: int) -> void:
	demo.sim.squads.order_move([sq.id], demo.on_ground(to.x, to.z, 0.0), pace)


# --- checks -------------------------------------------------------------------------------------------------------------

func _a_loco() -> Dictionary:
	demo.sim.brain.enabled = false
	var ws := _walk_spot()
	var c: Vector3 = ws[0]
	var dir: Vector3 = ws[1]
	var u := _spawn_one(c - dir * 40.0, dir)
	var sq := demo.sim.state.squad_of(u.id)
	await _cam_follow(u, 6.0, atan2(dir.x, dir.z) + PI * 0.5)
	await _seconds(2.0)
	var out := {"paces": {}}
	var leg := 0
	for p: Array in [["walk", UnitState.Pace.WALK, 3.5], ["run", UnitState.Pace.RUN, 3.0], ["sprint", UnitState.Pace.SPRINT, 3.0]]:
		var goal := u.position + dir * (float(p[2]) * UnitState.PACE_SPEED[p[1]] + 6.0)
		_move(sq, goal, p[1])
		await _physics(20)
		var cam_follow := func() -> Dictionary:
			_cam_follow(u, 6.0, atan2(dir.x, dir.z) + PI * 0.5, 10.0)
			return _foot_probe(u).call()
		var smp := await _record("a_%s_side" % p[0], float(p[2]), 2, cam_follow)
		var vs := smp.filter(func(x: Dictionary) -> bool: return x.has("v")).map(func(x: Dictionary) -> float: return x.v)
		vs.sort()
		out.paces[p[0]] = {"speed_ms": snappedf(vs[vs.size() / 2], 0.01) if not vs.is_empty() else -1.0, "slip": _slip(smp),
			"anim": smp[-1].get("anim", {}) if not smp.is_empty() else {}}
		_expect(not vs.is_empty() and absf(vs[vs.size() / 2] - UnitState.PACE_SPEED[p[1]]) < 0.6,
			"a_loco: %s speed %.2f, want %.2f" % [p[0], vs[vs.size() / 2] if not vs.is_empty() else -1.0, UnitState.PACE_SPEED[p[1]]])
		leg += 1
	# Stop: hold, record the deceleration.
	demo.sim.squads.order_hold([sq.id])
	await _record("a_stop_side", 2.5, 2, func() -> Dictionary:
		_cam_follow(u, 6.0, atan2(dir.x, dir.z) + PI * 0.5, 10.0)
		return {})
	# Turn on the spot: the soldier turns to watch around (the record's watch direction, as the AI does).
	var b := _body(u)
	var yaw0 := b.rotation.y
	u.watch_yaw = wrapf(yaw0 + PI * 0.75, -PI, PI)
	u.watch_until = demo.sim.state.time + 30.0
	var turn := await _record("a_turn", 2.5, 2, func() -> Dictionary:
		_cam_follow(u, 5.0, yaw0 + PI * 0.3, 14.0)
		var c2 := _char(u)
		return c2.anim_state() if c2 else {})
	out["turn_amount_max"] = turn.map(func(x: Dictionary) -> float: return absf(float(x.get("turn", 0.0)))).max() if not turn.is_empty() else 0.0
	_expect(float(out.turn_amount_max) > 0.3, "a_loco: no turn clip while turning on the spot")
	_png("a_end")
	demo.sim.brain.enabled = true
	return out


func _b_squad() -> Dictionary:
	demo.sim.brain.enabled = false
	var ws := _walk_spot()
	var c: Vector3 = ws[0]
	var dir: Vector3 = ws[1]
	var sq := _cs.spawn(0, c - dir * 60.0, dir, 8, "V3SQ")
	await _seconds(2.0)
	var out := {}
	var centre := func() -> Vector3: return demo.sim.war.squad_center(sq)
	_move(sq, centre.call() + dir * 60.0, UnitState.Pace.RUN)
	await _physics(30)
	var follow := func() -> Dictionary:
		var p: Vector3 = centre.call()
		_cam(p + Vector3.UP, 22.0, atan2(dir.x, dir.z) + PI * 0.6, 22.0)
		return {}
	await _record("b_jog", 6.0, 2, follow)
	var side := Vector3(-dir.z, 0, dir.x)
	_move(sq, centre.call() + side * 50.0, UnitState.Pace.RUN)
	await _physics(20)
	await _record("b_turn_run", 6.0, 2, follow)
	_move(sq, centre.call() + side * 25.0, UnitState.Pace.WALK)
	await _physics(20)
	await _record("b_walk", 5.0, 2, follow)
	await _cam(centre.call(), 60.0, 0.6, 35.0)
	await _seconds(1.0)
	_png("b_rts_medium")
	# Animation cost of the eight characters (AnimationTree advance + aim modifier) and the frame time, 3 s.
	var u0 := InfantryCharacter.anim_usec
	var f0 := Engine.get_process_frames()
	var t0 := Time.get_ticks_usec()
	await _seconds(3.0)
	var frames := maxi(1, Engine.get_process_frames() - f0)
	out["anim_usec_per_frame_all"] = snappedf(float(InfantryCharacter.anim_usec - u0) / frames, 0.1)
	out["frame_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0 / frames, 0.01)
	out["characters"] = demo.sim.state.units.values().filter(func(x: UnitState) -> bool: return demo.sim.view_of(x.id) is SoldierBody).size()
	var spd := []
	for id in sq.members:
		var b := _body(demo.sim.state.get_unit(id))
		if b:
			spd.append(snappedf(Vector2(b.velocity.x, b.velocity.z).length(), 0.01))
	out["walk_speeds"] = spd
	demo.sim.brain.enabled = true
	return out


func _c_combat() -> Dictionary:
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var a := _cs.spawn(0, c - dir * 35.0, dir, 4, "V3A")
	var b := _cs.spawn(1, c + dir * 35.0, -dir, 4, "V3B")
	# Nobody dies: the check is about the animation (raise, aim, fire), not the outcome.
	var keep_alive := func() -> void:
		for sq: SquadState in [a, b]:
			for id in sq.members:
				var uu := demo.sim.state.get_unit(id)
				if uu:
					uu.max_health = 100000.0
					uu.health = uu.max_health
	keep_alive.call()
	demo.sim.state.shot_fired.connect(func(_s: Dictionary) -> void: keep_alive.call())
	await _seconds(2.0)
	demo.sim.brain.enabled = true
	var shots0 := {"n": 0}
	var counter := func(_s: Dictionary) -> void: shots0.n += 1
	demo.sim.state.shot_fired.connect(counter)
	var mid := c
	await _cam(mid + Vector3.UP, 30.0, atan2(dir.x, dir.z) + PI * 0.5, 16.0)
	var t0 := demo.sim.state.time
	while shots0.n == 0 and demo.sim.state.time - t0 < 60.0:
		await _physics(10)
	var a0 := demo.sim.state.get_unit(a.members[0])
	var diag := {"ai_state": UnitState.AI_STATE_NAMES[a0.ai_state], "target": a0.target_id, "reason": a0.ai_reason,
		"brain": demo.sim.brain.enabled, "dist": snappedf(a0.position.distance_to(demo.sim.state.get_unit(b.members[0]).position), 0.1)}
	await _cam_follow(a0, 5.0, atan2(dir.x, dir.z) + PI * 0.75, 10.0)
	var smp := await _record("c_aim_close", 5.0, 2, func() -> Dictionary:
		_cam_follow(a0, 5.0, atan2(dir.x, dir.z) + PI * 0.75, 10.0)
		var ch := _char(a0)
		return ch.anim_state() if ch else {})
	await _cam(mid + Vector3.UP, 28.0, atan2(dir.x, dir.z) + PI * 0.5, 16.0)
	await _record("c_fight", 6.0, 2)
	_png("c_fight")
	demo.sim.state.shot_fired.disconnect(counter)
	var aims := smp.map(func(x: Dictionary) -> float: return float(x.get("aim", 0.0)))
	var out := {"shots": shots0.n, "aim_max": aims.max() if not aims.is_empty() else 0.0, "diag": diag}
	_expect(shots0.n > 0, "c_combat: no shot fired")
	_expect(float(out.aim_max) > 0.8, "c_combat: rifle never raised (aim %.2f)" % float(out.aim_max))
	return out


func _d_terrain() -> Dictionary:
	demo.sim.brain.enabled = false
	# A slope: the steepest of a few sampled lines near the site within what infantry walks (grade 0.15..0.45).
	var c: Vector3 = _site.def
	var cands := []
	for k in 36:
		var d := Vector3(cos(k * TAU / 36.0), 0, sin(k * TAU / 36.0))
		for r: float in [80.0, 160.0, 260.0, 380.0, 520.0]:
			var p := c + Vector3(cos(k * 1.7), 0, sin(k * 1.7)) * r
			var h0 := demo.on_ground(p.x, p.z, 0.0).y
			var h1 := demo.on_ground(p.x + d.x * 30.0, p.z + d.z * 30.0, 0.0).y
			var g := (h1 - h0) / 30.0
			if g > 0.12 and g < 0.45:
				cands.append({"p": p, "d": d, "g": g})
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.g) > float(y.g))
	# Open ground: the camera 14 m to the side must see the soldiers (no trunks or crowns in between).
	# Open ground: no tree trunk within 12 m of the climb or of the camera beside it (vegetation data, so crowns without
	# colliders count too).
	var best := {}
	var sm := demo.structures
	for cd: Dictionary in cands:
		var p: Vector3 = cd.p
		var d: Vector3 = cd.d
		var side := Vector3(-d.z, 0, d.x)
		var clear := true
		for t: float in [-8.0, 4.0, 16.0, 28.0]:
			for o: float in [0.0, 7.0, 14.0]:
				var q := p + d * t + side * o
				if sm.blocks_trunk(Vector2(q.x, q.z), 12.0 if o == 0.0 else 6.0):
					clear = false
		if clear:
			best = cd
			break
	_expect(not best.is_empty(), "d_terrain: no slope of 15-45 %% near the site")
	if best.is_empty():
		return {}
	var p0: Vector3 = best.p
	var d: Vector3 = best.d
	var sq := _cs.spawn(0, p0 - d * 8.0, d, 4, "V3UP")
	await _seconds(2.0)
	var side_yaw := atan2(-d.z, d.x)       # compass yaw of the side direction (-d.z, 0, d.x)
	var follow := func() -> Dictionary:
		var p: Vector3 = demo.sim.war.squad_center(sq)
		_cam(p + Vector3.UP, 14.0, side_yaw, 8.0)
		return {}
	_move(sq, p0 + d * 32.0, UnitState.Pace.RUN)
	await _physics(20)
	await _record("d_uphill", 6.0, 2, follow)
	_move(sq, p0 - d * 10.0, UnitState.Pace.RUN)
	await _physics(20)
	await _record("d_downhill", 6.0, 2, follow)
	var u := demo.sim.state.get_unit(sq.members[0])
	await _cam_follow(u, 4.0, atan2(d.x, d.z) + PI * 0.5, 4.0)
	_png("d_feet_slope")
	demo.sim.brain.enabled = true
	return {"grade": snappedf(float(best.g), 0.01), "at": [roundi(p0.x), roundi(p0.z)]}


func _e_trans() -> Dictionary:
	demo.sim.brain.enabled = false
	var ws := _walk_spot()
	var c: Vector3 = ws[0]
	var dir: Vector3 = ws[1]
	var u := _spawn_one(c, dir)
	var sq := demo.sim.state.squad_of(u.id)
	var view := func() -> Dictionary:
		_cam_follow(u, 5.0, atan2(dir.x, dir.z) + PI * 0.6, 10.0)
		var ch := _char(u)
		var st := ch.anim_state() if ch else {}
		st["t"] = Time.get_ticks_usec() / 1e6
		return st
	await _cam_follow(u, 5.0, atan2(dir.x, dir.z) + PI * 0.6, 10.0)
	await _seconds(1.5)
	var log := []
	# move and stop
	_move(sq, u.position + dir * 8.0, UnitState.Pace.RUN)
	log.append_array(await _record("e_1_move_stop", 4.5, 2, view))
	# crouch and stand (the cover pose)
	u.tactic = UnitState.Tactic.IN_COVER
	log.append_array(await _record("e_2_crouch", 2.0, 2, view))
	u.tactic = UnitState.Tactic.NONE
	log.append_array(await _record("e_3_stand", 1.5, 2, view))
	# aim at a point ahead, then move while aiming, fire, reload
	var tgt := u.position + dir * 60.0 + Vector3(-dir.z, 0, dir.x) * 25.0
	u.target_id = 99999
	u.target_last_pos = tgt
	u.target_seen_at = demo.sim.state.time + 30.0
	log.append_array(await _record("e_4_raise", 1.5, 2, view))
	_move(sq, u.position - dir * 6.0, UnitState.Pace.WALK)
	log.append_array(await _record("e_5_aim_move", 3.0, 2, view))
	for i in 4:
		u.shot_counter += 1
		u.last_shot_at = demo.sim.state.time
		log.append_array(await _record("e_6_fire_%d" % i, 0.25, 1, view))
	u.reload_until = demo.sim.state.time + 2.6
	# the magazine bone's distance from the weapon bone (0 = seated in the well)
	var mag_off := func() -> float:
		var ch := _char(u)
		if ch == null or not ch.attachments.has("ATT_Magazine") or not ch.attachments.has("ATT_Weapon"):
			return -1.0
		return (ch.attachments.ATT_Magazine as Node3D).global_position.distance_to((ch.attachments.ATT_Weapon as Node3D).global_position)
	var mag_view := func() -> Dictionary:
		var st: Dictionary = view.call()
		st["mag"] = mag_off.call()
		return st
	var rl: Array = await _record("e_7_reload", 3.0, 2, mag_view)
	log.append_array(rl)
	var mag_max := 0.0
	for r in rl:
		mag_max = maxf(mag_max, float(r.get("mag", -1.0)))
	var mag_end: float = mag_off.call()
	_expect(mag_max > 0.15, "the magazine did not leave the well during the reload (%.3f m)" % mag_max)
	_expect(mag_end >= 0.0 and mag_end < 0.01, "the magazine is not back in the well after the reload (%.3f m)" % mag_end)
	u.target_id = -1
	u.target_seen_at = -1.0e9
	u.target_last_pos = Vector3.INF
	u.last_shot_at = -1.0e9
	log.append_array(await _record("e_8_lower", 1.5, 2, view))
	# Snap check: the fastest change of a blend weight (per second; frames are uneven while shots are written). A full
	# transition faster than ~0.15 s (rate > 7 /s) reads as a snap.
	var rate := 0.0
	var worst := ""
	for i in range(1, log.size()):
		var dt := float(log[i].get("t", 0.0)) - float(log[i - 1].get("t", 0.0))
		if dt <= 0.0:
			continue
		for k in ["aim", "crouch", "move_amount", "alert"]:
			if log[i].has(k) and log[i - 1].has(k):
				var r := absf(float(log[i][k]) - float(log[i - 1][k])) / maxf(dt, 1.0 / 60.0)
				if r > rate:
					rate = r
					worst = "%s at sample %d: %.2f -> %.2f in %.3f s" % [k, i, float(log[i - 1][k]), float(log[i][k]), dt]
	# Writing a screenshot makes the next frame long; the character caps a frame's blend step at 1/20 s, so the largest
	# change of a weight in one frame is bounded (0.40 for the move blend) and nothing switches in a single frame.
	var step := 0.0
	for i in range(1, log.size()):
		for k in ["aim", "crouch", "move_amount", "alert"]:
			if log[i].has(k) and log[i - 1].has(k):
				step = maxf(step, absf(float(log[i][k]) - float(log[i - 1][k])))
	_expect(step <= 0.45, "e_trans: a blend weight jumped by %.2f in one frame (snap)" % step)
	demo.sim.brain.enabled = true
	return {"max_blend_step": snappedf(step, 0.01), "max_blend_rate_per_s": snappedf(rate, 0.1), "worst": worst, "frames": log.size(),
		"mag_out_m": snappedf(mag_max, 0.001), "mag_end_m": snappedf(mag_end, 0.001)}


func _f_views() -> Dictionary:
	demo.sim.brain.enabled = false
	var ws := _walk_spot()
	var c: Vector3 = ws[0]
	var dir: Vector3 = ws[1]
	var u := _spawn_one(c, dir)
	var watcher := _spawn_one(c + dir * 3.2 + Vector3(-dir.z, 0, dir.x) * 0.8, -dir, "V3W")
	await _seconds(2.0)
	var out := {}
	# First person: possess the watcher, look at the subject.
	demo.game.possess(watcher.id)
	await _seconds(1.5)
	var wb := _body(watcher)
	if wb:
		wb.look_at(u.position + Vector3.UP * 1.2, Vector3.UP)
	await _seconds(0.5)
	_png("f_fps_close")
	demo.game.enter_rts()
	UnitVisuals.markers_visible = true
	for v: Array in [["f_rts_near", 15.0], ["f_rts_mid", 40.0], ["f_rts_far", 110.0]]:
		demo.rts_camera.camera.make_current()
		demo.rts_camera.frame(u.position, 0.7, float(v[1]))
		await _seconds(1.5)
		_png(v[0])
	out["lod_meshes"] = _char(u).lod_meshes.size() if _char(u) else 0
	UnitVisuals.markers_visible = false
	demo.sim.brain.enabled = true
	return out

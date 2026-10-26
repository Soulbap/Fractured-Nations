## COMBAT-POLISH-01 checks in the real game on ref_20km (a few, short):
##
##   Godot.exe --path . --fullscreen --log-file cp.log res://scenes/game/world_ref_20km.tscn -- --scenario=dev --combat-polish01-test [--shots] [--only ...]
##
## p_prone   soldiers prone on a slope facing up it, down it and across it, aiming at an enemy: side / RTS shots, and the
##           height of the head, hips and feet bones over the ground under each (nothing floating, nothing buried)
## t_ground  a ditch and a fold of the microrelief from eye height and the RTS camera (the ground paint)
## a_ai_cover an AI faction's squad is sent the way an operation sends it (one-point route, line formation) to an open place with
##           relief, an enemy reported 230 m beyond it: protected soldiers at the end, distance from the point, time
##           (`--no-ai-end-cover` gives the before numbers)
## Prints "WC <check> <json>", writes res://benchmarks/raw/world_cover_test.json (WorldCoverSelfTest._finish).
class_name CombatPolish01SelfTest
extends WorldCover11SelfTest

const CHECKSCP: Array[String] = ["p_prone", "t_ground", "a_ai_cover"]


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/combat_polish01"
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKSCP)
	SoldierBody.require_mouse_capture = false
	tree.create_timer(900.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_feats = TerrainRelief.read_features(demo.config.world_name)
	_cs = CombatScenario.new(demo)
	_site = _cs.find_site()
	_tcam = Camera3D.new()
	_tcam.fov = 50.0
	_tcam.far = 4000.0
	demo.add_child(_tcam)
	if demo.hud:
		demo.hud.visible = false
	_quiet_area(_site.def, 2500.0)
	for n in CHECKSCP:
		if only.has(n):
			_log(n, await call("_" + n))
			await _physics(10)
	_finish()


## Open ground near the test area whose fall line is between 0.18 and 0.36 (the slopes soldiers lie on at the relief): {p, up}.
func _slope_spot(min_g := 0.18, max_g := 0.36) -> Dictionary:
	var data: Terrain3DData = demo.sim.terrain.data
	var routes: StrategicRoutes = demo.sim.war.routes
	var c: Vector3 = _site.def
	var best := {}
	var best_s := INF
	for r in range(20, 400, 12):
		for k in 24:
			var a := k * TAU / 24.0 + r * 0.37
			var p := c + Vector3(cos(a), 0, sin(a)) * r
			var hx := data.get_height(p + Vector3(1.5, 0, 0)) - data.get_height(p - Vector3(1.5, 0, 0))
			var hz := data.get_height(p + Vector3(0, 0, 1.5)) - data.get_height(p - Vector3(0, 0, 1.5))
			var g := Vector2(hx, hz).length() / 3.0
			if is_nan(g) or g < min_g or g > max_g or routes.cover_at(p) > 0.3 or _trunks_near(p, 10.0) > 0:
				continue
			# an even slope: the same grade 3 m to either side across it
			var s := absf(g - (min_g + max_g) * 0.5)
			if s < best_s:
				best_s = s
				best = {"p": demo.on_ground(p.x, p.z, 0.0), "up": Vector3(hx, 0, hz).normalized(), "grade": snappedf(g, 0.01)}
		if not best.is_empty() and r > 120:
			break
	return best


func _bone_y(c: InfantryCharacter, bone: String) -> Vector3:
	var i := c.skeleton.find_bone(bone)
	return (c.skeleton.global_transform * c.skeleton.get_bone_global_pose(i)).origin if i >= 0 else Vector3.INF


## Height of the head, hips, both feet and the muzzle above the ground under them (m), and where the rifle points (degrees up).
func _prone_numbers(u: UnitState, aim_at: Vector3) -> Dictionary:
	var c := _char(u)
	if c == null or c.skeleton == null:
		return {}
	var data: Terrain3DData = demo.sim.terrain.data
	var out := {}
	for b in ["Head", "Hips", "LeftFoot", "RightFoot", "LeftHand"]:
		var p := _bone_y(c, b)
		out[b] = snappedf(p.y - data.get_height(p), 0.01) if p.is_finite() else "?"
	var m := c.muzzle()
	if m:
		var fwd := -m.global_basis.z.normalized()
		var want := (aim_at - m.global_position).normalized()
		out["muzzle_up_deg"] = snappedf(rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0))), 0.1)
		out["want_up_deg"] = snappedf(rad_to_deg(asin(clampf(want.y, -1.0, 1.0))), 0.1)
		out["muzzle_off_deg"] = snappedf(rad_to_deg(fwd.angle_to(want)), 0.1)
	return out


func _p_prone() -> Dictionary:
	var out := {}
	var s := _slope_spot(0.24, 0.40)
	_expect(not s.is_empty(), "p_prone: no open slope near the test area")
	if s.is_empty():
		return out
	out["slope"] = {"at": _v(s.p), "grade": s.grade}
	var p: Vector3 = s.p
	var up: Vector3 = s.up
	var side := up.cross(Vector3.UP).normalized()
	demo.rts_camera.camera.make_current()
	demo.rts_camera.frame(p, atan2(-side.x, -side.z), 20.0)
	await _seconds(2.0)
	# Three pairs 12 m apart along the slope's contour: facing up it, down it and across it, each aiming at its own enemy 60 m off.
	var cases := [["uphill", up], ["downhill", -up], ["across", side]]
	var sq := _cs.spawn(0, p, up, 6, "PP")
	var foes: Array = []
	for c: Array in cases:
		var en := _cs.spawn(1, p + (c[1] as Vector3) * 60.0, -(c[1] as Vector3), 1, "PE")
		en.roe = SquadState.Roe.HOLD_FIRE
		foes.append(en)
	_tough([sq] + foes)
	sq.roe = SquadState.Roe.HOLD_FIRE
	demo.sim.squads.order_hold([sq.id])
	var rows := {}
	var t_end := demo.sim.state.time + 5.0
	while true:
		var k := 0
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			var ci := k / 2
			var dir: Vector3 = cases[ci][1]
			var enemy := demo.sim.state.get_unit(foes[ci].members[0])
			var q := p + side * ((ci - 1) * 12.0 + (k % 2) * 2.4 - 1.2)
			var b := _body(u)
			if not rows.has(id):
				q = demo.on_ground(q.x, q.z, 0.0)
				u.position = q
				if b:
					b.teleport(q, atan2(-dir.x, -dir.z))
				rows[id] = true
			Posture.set_now(u, Posture.PRONE)
			u.yaw = atan2(-dir.x, -dir.z)
			if b:
				b.rotation.y = u.yaw
			u.target_id = enemy.id
			u.target_seen_at = demo.sim.state.time
			u.target_last_pos = enemy.position
			u.target_aim_y = 1.1
			u.last_shot_at = demo.sim.state.time
			k += 1
		if demo.sim.state.time >= t_end:
			break
		await _physics(1)
	var k2 := 0
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		var ci := k2 / 2
		var enemy := demo.sim.state.get_unit(foes[ci].members[0])
		var row := _prone_numbers(u, Posture.aim_point(enemy, false))
		row["slope_deg"] = snappedf(rad_to_deg(InfantryCharacter.slope_at(demo.sim.terrain.data, u.position, u.yaw).x), 0.1)
		if not out.has(cases[ci][0]):
			out[cases[ci][0]] = []
		out[cases[ci][0]].append(row)
		_expect(not row.is_empty(), "p_prone %s: %s has no body" % [cases[ci][0], u.unit_name])
		for b in ["Head", "Hips", "LeftFoot", "RightFoot"]:
			if row.has(b) and row[b] is float:
				_expect(float(row[b]) > -0.12 and float(row[b]) < 0.45, "p_prone %s: %s %.2f m from the ground" % [cases[ci][0], b, float(row[b])])
		if row.has("muzzle_off_deg"):
			_expect(float(row.muzzle_off_deg) < 12.0, "p_prone %s: rifle %.0f deg off the enemy" % [cases[ci][0], float(row.muzzle_off_deg)])
		k2 += 1
	for ci in 3:
		var mid := demo.on_ground(p.x + side.x * (ci - 1) * 12.0, p.z + side.z * (ci - 1) * 12.0, 0.0)
		var view: Vector3 = up if ci == 2 else (side if ci == 0 else -side)
		_cam(mid + Vector3.UP * 0.3, 4.5, atan2(view.x, view.z), 10.0)
		await _seconds(0.4)
		_png("prone_%s_side" % cases[ci][0])
	_tcam.current = false
	demo.rts_camera.camera.make_current()
	demo.rts_camera.frame(p, atan2(-side.x, -side.z), 16.0)
	await _seconds(1.2)
	_png("prone_rts")
	# First person: the soldier lying downhill possessed (the same place and posture), looking along the line at the others.
	var me := demo.sim.state.get_unit(sq.members[2])
	if demo.game.possess(me.id):
		Posture.set_now(me, Posture.PRONE)
		await _seconds(1.5)
		var body := _body(me)
		_aim_body(body, demo.sim.state.get_unit(sq.members[0]).position + Vector3.UP * 0.3)
		await _seconds(1.0)
		out["fps"] = {"posture": Posture.NAMES[me.posture], "eye_minus_ground_m": snappedf(body.camera.global_position.y - demo.sim.terrain.data.get_height(body.camera.global_position), 0.01)}
		_png("prone_fps")
		demo.game.enter_rts()
		await _seconds(0.5)
	await _clear_squads([sq] + foes)
	return out


func _t_ground() -> Dictionary:
	var out := {}
	for kind in ["ditch", "fold", "hollow"]:
		var fs := _relief(kind, _site.def, 6, 0.4)
		if fs.is_empty():
			continue
		var f: Dictionary = fs[0].f
		var p := _extreme(f)
		out[kind] = _v(p)
		demo.rts_camera.camera.make_current()
		_tcam.current = false
		demo.rts_camera.frame(p, 0.8, 30.0)
		await _seconds(3.0)
		_png("ground_%s_rts" % kind)
		var yaw := _open_side(p, 0.8)
		_cam(p + Vector3.UP * 0.5, 14.0, yaw, 7.0)
		await _seconds(1.5)
		_png("ground_%s_eye" % kind)
	return out


func _a_ai_cover() -> Dictionary:
	var c := _relief_place()
	_expect(c.is_finite(), "a_ai_cover: no open place with relief")
	if not c.is_finite():
		return {}
	# The AI squad is faction 1, the enemy faction 0 (the player's side), reported only.
	var enemy := _cs.spawn(0, c + Vector3(0, 0, -230), Vector3.BACK, 4, "AE")
	var sq := _cs.spawn(1, c + Vector3(-70, 0, 30), Vector3.RIGHT, 6, "AS")
	_tough([sq])
	sq.recover_until = demo.sim.state.time + 9999.0  # WarSim leaves it alone
	demo.sim.war.intel.report_seen(demo.sim.state.get_unit(sq.members[0]), demo.sim.state.get_unit(enemy.members[0]), 4)
	await _until(func() -> bool: return demo.sim.tactics.threat_pos(sq).is_finite(), 10.0, 1.0)
	var threat := demo.sim.tactics.threat_pos(sq)
	for id in enemy.members:
		demo.sim.state.remove_unit(id)
	demo.rts_camera.camera.make_current()
	demo.rts_camera.frame(c, 0.0, 60.0)
	demo.sim.squads.follow_route(sq, PackedVector3Array([demo.on_ground(c.x, c.z, 0.0)]), SquadState.Formation.LINE)
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(2.0)
	while demo.sim.state.time - t0 < 120.0:
		await _physics(15)
		if demo.sim.state.time - t0 > 8.0 and sq.status != SquadState.Status.MOVING and not demo.sim.squads.marching(sq) 				and not demo.sim.squads.route_waiting(sq) and (not demo.sim.tactics.settle_ai or String(demo.sim.tactics._meta(sq, "settled_key", "")) != ""):
			break
	# Until every soldier is at the post he was given (or 25 s).
	var t1 := demo.sim.state.time
	while demo.sim.state.time - t1 < 25.0:
		var away := 0
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			if u.post_pos.is_finite() and _flat3(u.position, u.post_pos) > 1.5:
				away += 1
		if away == 0:
			break
		await _physics(15)
	CoreDemo.apply_time_scale(1.0)
	await _seconds(4.0)
	var prot := 0
	var far := 0.0
	var postures := {}
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if _held_protected(u, threat):
			prot += 1
		far = maxf(far, _flat3(u.position, c))
		postures[Posture.NAMES[u.posture]] = int(postures.get(Posture.NAMES[u.posture], 0)) + 1
	var out := {"ai_end_cover": demo.sim.tactics.settle_ai, "at": _v(c), "time_s": snappedf(demo.sim.state.time - t0, 0.1), "protected_at_end": prot,
		"of": sq.members.size(), "farthest_from_goal_m": snappedf(far, 0.1), "postures": postures, "settled": demo.sim.tactics._meta(sq, "settled", {}),
		"tactic": sq.tactic_name(), "order": demo.sim.squads.describe_order(sq).text}
	var td := (threat - c).normalized()
	demo.rts_camera.frame(c, atan2(-td.x, -td.z), 30.0)
	await _seconds(2.0)
	_png("ai_cover_end_rts" if demo.sim.tactics.settle_ai else "ai_cover_end_rts_before")
	_expect(far < 40.0, "a_ai_cover: soldiers ended %.0f m from the point" % far)
	_expect(not demo.sim.tactics.settle_ai or prot >= 3, "a_ai_cover: only %d of %d protected at the end" % [prot, sq.members.size()])
	await _clear_squads([sq])
	return out

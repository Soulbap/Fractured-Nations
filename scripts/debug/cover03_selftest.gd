## COMBAT-COVER-03 checks in the real game on ref_20km, at a real settlement house with the WORLD-DETAIL-02 objects round it:
##
##   Godot.exe --path . --fullscreen --log-file cc3.log res://scenes/game/world_ref_20km.tscn -- --scenario=dev --cover03-test [--shots] [--only ...]
##
## a_building  a shooter and a target on opposite sides of the house: LineOfFire stops the line at the wall (and the box covers the
##             whole house: a fan of lines across its footprint, against the old sphere collider), the physics ray of the near tier
##             too; the AI shooter does not hit him for 10 s; the possessed shooter's shot (the real muzzle path) hits the wall,
##             also pressed against the wall
## b_terrain   two soldiers on either side of a terrain crest, a fire mission at the hidden one: no rounds into the hillside
## c_corner    a soldier behind the house's back wall with a fire mission at a target out front: blocked, he moves to a firing
##             position (a corner, a step aside) and fires from there
## d_click     an 8-man player squad, a single right click beside the house wall (preview under the cursor first): the places, their
##             cover, spacing, nothing inside the house; the squad walks there and stands at its places
## e_direction the cover judgement of a spot behind a garden wall and behind the house against a threat in front, at the side, behind
## f_drag      a right-drag roughly along the settlement (house + walls + yard objects) with a believed enemy: several objects used,
##             no stacking, no long detours, preview = order
## g_fight     the squad placed at the house by a click meets an enemy squad across the open ground: 60 s, rounds into own cover,
##             blocked lines, firing moves, places kept
## q_perf      the cost of a single-click plan (hover), a drag plan and one CoverEval judgement
## Prints "CC3 <check> <json>", writes res://benchmarks/raw/cover03_test.json, shots (with --shots) into docs/combat_cover03/.
class_name Cover03SelfTest
extends AiCombat02SelfTest

const CHECKS_CC3: Array[String] = ["a_building", "b_terrain", "c_corner", "d_click", "e_direction", "f_drag", "g_fight", "q_perf"]

## The chosen house: {c (base centre), yaw, basis, hx, hz, h, front (unit: local +z), side (local +x)}
var _house := {}
var _details: Dictionary = {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/combat_cover03"
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKS_CC3)
	SoldierBody.require_mouse_capture = false
	tree.create_timer(1500.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_layer = {}
	var dj: Variant = JSON.parse_string(FileAccess.get_file_as_string(DetailLayer.path(demo.config.world_name)))
	_details = dj.records if dj is Dictionary else {}
	_cs = CombatScenario.new(demo)
	_site = _cs.find_site()
	_house = await _pick_house()
	_expect(not _house.is_empty(), "no settlement house with open ground in front and behind (precondition)")
	if _house.is_empty():
		_finish()
		return
	results["house"] = {"at": _v(_house.c), "yaw_deg": snappedf(rad_to_deg(float(_house.yaw)), 1.0), "details_40m": _house.n}
	_quiet_area(_house.c, 2500.0)
	for n in CHECKS_CC3:
		if only.has(n):
			_quiet_area(_house.c, 2500.0)
			if demo.game.mode != GameController.Mode.RTS:
				demo.game.enter_rts()
			_log(n, await call("_" + n))
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("CC3 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	CoreDemo.apply_time_scale(1.0)
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/cover03_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("CC3 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


# --- Site -------------------------------------------------------------------------------------------------------------------

## A settlement house (library id 16) with the most WORLD-DETAIL-02 objects within 40 m whose front and back have 30 m of open,
## dry, gentle ground (a line from 30 m in front to 30 m behind meets only the house).
func _pick_house() -> Dictionary:
	var sj: Variant = JSON.parse_string(FileAccess.get_file_as_string(SettlementLayer.overrides_path(demo.config.world_name)))
	if not sj is Dictionary:
		return {}
	var houses: Array = []
	for rec: Dictionary in (sj.records as Dictionary).values():
		if rec.get("kind") == "added" and int(rec.get("mesh", -1)) == 16 and not bool(rec.get("removed", false)):
			var t: Array = rec.transform
			var p := Vector3(t[9], t[10], t[11])
			if absf(p.x) > 9000.0 or absf(p.z) > 9000.0:
				continue
			var n := 0
			for d: Dictionary in _details.values():
				var dt: Array = d.transform
				if Vector2(float(dt[9]) - p.x, float(dt[11]) - p.z).length() < 40.0:
					n += 1
			houses.append([n, p])
	houses.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var line := demo.sim.combat.line
	var tried := 0
	for e: Array in houses:
		tried += 1
		if tried > 80:
			break
		var p: Vector3 = e[1]
		for cell: Vector2i in line.cells_along(p - Vector3(40, 0, 40), p + Vector3(40, 0, 40)):
			line.warm(cell)
		var box := _box_at(p, 4.0, 5.75)
		if box.is_empty():
			continue
		var front: Vector3 = box.basis.z
		var side: Vector3 = box.basis.x
		var ok := true
		for s: float in [-1.0, 1.0]:
			for k: float in [10.0, 20.0, 30.0]:
				var q := demo.on_ground(p.x + front.x * s * (5.75 + k), p.z + front.z * s * (5.75 + k), 0.0)
				if _cs._slope(q, 3.0) > 10.0 or not _cs._dry(q, 3.0) or demo.sim.structures.blocks_trunk(Vector2(q.x, q.z), 1.0):
					ok = false
		if not ok:
			continue
		var a := demo.on_ground(p.x + front.x * 35.75, p.z + front.z * 35.75, 0.0) + Vector3.UP * 1.6
		var b := demo.on_ground(p.x - front.x * 35.75, p.z - front.z * 35.75, 0.0) + Vector3.UP * 1.1
		var r := line.trace(a, b, -1, false)
		if r.blocker != "tree" or absf(float(r.distance) - 30.0) > 2.5:
			continue
		# both halves of that line are clear apart from the house
		if not line.clear_line(a, a.lerp(b, 0.38)) or not line.clear_line(b + Vector3.UP * 0.5, b.lerp(a, 0.38)):
			continue
		await _physics(1)
		return {"c": box.c, "yaw": box.yaw, "basis": box.basis, "hx": 4.0, "hz": 5.75, "h": box.h, "front": front, "side": side, "n": e[0]}
	return {}


## The box solid (LineOfFire bucket record) with half sizes hx, hz nearest p: {c, yaw, basis, h}.
func _box_at(p: Vector3, hx: float, hz: float) -> Dictionary:
	var line := demo.sim.combat.line
	var best := {}
	var bd := 3.0
	for bx in range(floori((p.x - 20.0) / LineOfFire.BUCKET), floori((p.x + 20.0) / LineOfFire.BUCKET) + 1):
		for bz in range(floori((p.z - 20.0) / LineOfFire.BUCKET), floori((p.z + 20.0) / LineOfFire.BUCKET) + 1):
			var data: PackedFloat32Array = line._buckets.get(Vector2i(bx, bz), PackedFloat32Array())
			for i in range(0, data.size(), LineOfFire.STRIDE):
				if data[i + 5] < 1.5 or absf(data[i + 7] - hx) > 0.05 or absf(data[i + 8] - hz) > 0.05:
					continue
				var d := Vector2(data[i] - p.x, data[i + 1] - p.z).length()
				if d < bd:
					bd = d
					best = {"c": Vector3(data[i], data[i + 2], data[i + 1]), "yaw": data[i + 6], "basis": Basis(Vector3.UP, data[i + 6]), "h": data[i + 4]}
	return best


## A point at local (x, z) of the house (metres from its centre along side / front), on the ground.
func _hp(x: float, z: float) -> Vector3:
	var c: Vector3 = _house.c
	var q := c + (_house.side as Vector3) * x + (_house.front as Vector3) * z
	return demo.on_ground(q.x, q.z, 0.0)


func _shooter(faction: int, at: Vector3, facing: Vector3, tag: String) -> UnitState:
	var u := _one(faction, at, facing, tag)
	demo.sim.state.squad_of(u.id).roe = SquadState.Roe.WEAPONS_FREE
	return u


## Puts a soldier exactly at p (spawn_recruits lays a squad out round its point; a held target runs for cover when shot at).
func _put(u: UnitState, p: Vector3) -> void:
	u.clear_reaction()
	u.position = p
	u.anchor_pos = p
	var b := _body(u)
	if b:
		b.teleport(p, u.yaw)
	demo.sim.state.halt(u.id)


var _shot_log: Array = []


func _rec_shot(shot: Dictionary) -> void:
	_shot_log.append(shot)


func _rec_shots(on: bool) -> void:
	if on:
		_shot_log.clear()
		if not demo.sim.state.shot_fired.is_connected(_rec_shot):
			demo.sim.state.shot_fired.connect(_rec_shot)
	elif demo.sim.state.shot_fired.is_connected(_rec_shot):
		demo.sim.state.shot_fired.disconnect(_rec_shot)


func _mouse_button(button: MouseButton, at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.global_position = at
	ev.pressed = down
	ev.button_mask = MOUSE_BUTTON_MASK_RIGHT if down and button == MOUSE_BUTTON_RIGHT else 0
	Input.warp_mouse(at * demo.get_viewport().get_screen_transform().get_scale())
	demo.get_viewport().push_input(ev, true)


func _mouse_move(at: Vector2, mask: int) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.button_mask = mask
	Input.warp_mouse(at * demo.get_viewport().get_screen_transform().get_scale())
	demo.get_viewport().push_input(ev, true)


## A believed enemy of faction f at p (an IntelSim report, applied at the next sweep).
func _contact(f: int, p: Vector3) -> void:
	var ef := 1 if f == 0 else 0
	demo.sim.war.intel._queue(f, ef, ContactState.Kind.INFANTRY, ContactState.Source.SEEN, p, -1, 8.0, 6, "test", demo.sim.state.time, 0.0)
	await _seconds(1.3)
	_expect(not demo.sim.war.intel.contacts_near(f, p, 30.0).is_empty(), "contact at %s not applied" % str(_v(p)))


func _player_squad8(at: Vector3, facing: Vector3, tag: String) -> SquadState:
	var pf := demo.sim.state.war.player_faction
	var sq := _cs.spawn(pf, at, facing, 8, tag)
	_tough([sq])
	demo.sim.squads.order_hold([sq.id])
	return sq


# --- Checks -----------------------------------------------------------------------------------------------------------------

func _a_building() -> Dictionary:
	var out := {}
	var line := demo.sim.combat.line
	var hz: float = _house.hz
	# The box against the old sphere: lines at chest height across the footprint (between random points 14-22 m out) that
	# must meet the house.
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var crossing := 0
	var blocked := 0
	var old_blocked := 0
	var c: Vector3 = _house.c
	var basis: Basis = _house.basis
	for k in 400:
		var a1 := rng.randf() * TAU
		var a2 := a1 + PI + rng.randf_range(-0.6, 0.6)
		var pa := demo.on_ground(c.x + cos(a1) * rng.randf_range(14.0, 22.0), c.z + sin(a1) * rng.randf_range(14.0, 22.0), 0.0) + Vector3.UP * 1.2
		var pb := demo.on_ground(c.x + cos(a2) * rng.randf_range(14.0, 22.0), c.z + sin(a2) * rng.randf_range(14.0, 22.0), 0.0) + Vector3.UP * 1.2
		# does the line cross the footprint below the eaves (geometry of the mesh: 8 x 11.5 m, walls to 5.4 m over the origin)?
		var la := basis.inverse() * (pa - c)
		var lb := basis.inverse() * (pb - c)
		var hit: Variant = AABB(Vector3(-4.0, 0.1, -5.75), Vector3(8.0, 5.0, 11.5)).intersects_segment(la, lb)
		if hit == null:
			continue
		crossing += 1
		var r := line.trace(pa, pb, -1, false)
		if r.blocker != "range":
			blocked += 1
		# the old collider: a sphere of radius 4 at 1.2 m over the origin
		if not Geometry3D.segment_intersects_sphere(pa, pb, c + Vector3.UP * (0.55 + 1.2), 4.0).is_empty():
			old_blocked += 1
	out["lines_crossing_house"] = crossing
	out["blocked_now"] = blocked
	out["blocked_old_sphere"] = old_blocked
	_expect(crossing >= 100 and blocked == crossing, "a_building: %d of %d lines through the house pass" % [crossing - blocked, crossing])
	# Shooter 25 m in front, target 25 m behind.
	var ps := _hp(0.0, hz + 25.0)
	var pt := _hp(0.0, -hz - 25.0)
	var s := _shooter(1, ps, -(_house.front as Vector3), "SA")
	var t := _one(0, pt, _house.front, "TA")
	await _frame(c, 70.0, (_house.yaw as float) + 0.9)
	_put(s, ps)
	_put(t, pt)
	await _seconds(1.0)
	var eye := CombatSim.eye_of(s)
	var r0 := line.trace(eye, Posture.aim_point(t, false), s.id)
	out["los_blocker"] = r0.blocker
	out["los_stop_m"] = snappedf(r0.distance, 0.1)
	_expect(r0.blocker == "tree" and absf(float(r0.distance) - 25.0) < 1.5, "a_building: line stopped by %s at %.1f m (wall at ~25 m)" % [r0.blocker, r0.distance])
	# The near tier's physics (InstanceColliderStreamer boxes) stops the same line at the same wall.
	var space := demo.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, Posture.aim_point(t, false))
	var bodies: Array[RID] = []
	for u: UnitState in [s, t]:
		var b := _body(u)
		if b:
			bodies.append(b.get_rid())
	q.exclude = bodies
	var ph := space.intersect_ray(q)
	out["physics_stop_m"] = snappedf(eye.distance_to(ph.position), 0.1) if not ph.is_empty() else -1.0
	_expect(not ph.is_empty() and absf(eye.distance_to(ph.position) - float(r0.distance)) < 0.6, "a_building: physics ray %s vs LineOfFire %.1f m" % [str(out.physics_stop_m), r0.distance])
	# AI: 10 s weapons free at a target he knows is there.
	s.target_id = t.id
	s.target_last_pos = t.position
	_rec_shots(true)
	var h0 := t.health
	for k in 20:
		_put(t, pt)
		_put(s, ps)  # he stays where the house is between them (moving round it is c_corner)
		await _seconds(0.5)
	_rec_shots(false)
	var hits := 0
	for sh: Dictionary in _shot_log:
		if int(sh.shooter) == s.id and int(sh.hit_unit) == t.id:
			hits += 1
	out["ai_shots"] = _shot_log.filter(func(sh: Dictionary) -> bool: return int(sh.shooter) == s.id).size()
	out["ai_hits_through"] = hits
	out["target_health_lost"] = snappedf(h0 - t.health, 0.1)
	_expect(hits == 0 and t.health >= h0, "a_building: the AI hit the target through the house")
	# FPS: the possessed shooter (player side) aims through the wall: standing 25 m off, then pressed against it.
	demo.sim.state.remove_unit(s.id)
	var me := _shooter(demo.sim.state.war.player_faction, ps, -(_house.front as Vector3), "PA")
	var en := _one(1 - demo.sim.state.war.player_faction, pt, _house.front, "EA")
	await _seconds(1.0)
	_put(en, pt)
	var fps := {}
	for case_name: String in ["standing_25m", "pressed_to_wall"]:
		var at := ps if case_name == "standing_25m" else _hp(1.0, hz + 0.45)
		_put(me, at)
		_put(en, pt)
		await _physics(4)
		demo.rts.select([me.id])
		if demo.game.mode == GameController.Mode.RTS:
			demo.game.toggle()
		await _seconds(1.2)
		var body := _body(me)
		if body == null or not me.player_controlled:
			_expect(false, "a_building: could not possess the shooter")
			break
		var dir := (Posture.aim_point(en, false) - body.camera.global_position).normalized()
		body.global_rotation.y = atan2(-dir.x, -dir.z)
		body.head.rotation.x = asin(clampf(dir.y, -1.0, 1.0))
		await _physics(3)
		var cam := body.camera
		var ms := demo.sim.combat.muzzle_shot(me.id, cam.global_position, -cam.global_basis.z, body.muzzle_position())
		me.next_shot_at = 0.0
		var shot := demo.sim.combat.request_fire(me.id, ms.origin, ms.dir, CombatSim.Source.PLAYER)
		fps[case_name] = {"fired": shot.get("fired", false), "blocker": shot.get("blocker", ""), "stop_m": snappedf(float(shot.get("distance", -1.0)), 0.01),
			"hit_unit": int(shot.get("hit_unit", -1)), "origin_from_eye_m": snappedf((ms.origin as Vector3).distance_to(cam.global_position), 0.01)}
		_expect(bool(shot.get("fired", false)) and int(shot.get("hit_unit", -1)) != en.id and String(shot.get("blocker", "")) == "tree",
			"a_building: FPS shot %s: %s" % [case_name, str(fps[case_name])])
		if case_name == "pressed_to_wall":
			_png("a_fps_against_wall")
		demo.game.enter_rts()
		await _seconds(0.5)
	out["fps"] = fps
	return out


func _b_terrain() -> Dictionary:
	var out := {}
	var line := demo.sim.combat.line
	var c: Vector3 = _site.def if not _site.is_empty() else _house.c
	var pick := {}
	for r: float in [200.0, 400.0, 700.0, 1100.0]:
		for k in 24:
			var a := k * TAU / 24.0
			var mid := demo.on_ground(c.x + cos(a) * r, c.z + sin(a) * r, 0.0)
			for j in 8:
				var d := Vector3(cos(j * TAU / 8.0), 0.0, sin(j * TAU / 8.0))
				var p := demo.on_ground(mid.x - d.x * 60.0, mid.z - d.z * 60.0, 0.0)
				var q := demo.on_ground(mid.x + d.x * 60.0, mid.z + d.z * 60.0, 0.0)
				if not _cs._dry(p, 3.0) or not _cs._dry(q, 3.0) or _cs._slope(p, 3.0) > 12.0 or _cs._slope(q, 3.0) > 12.0:
					continue
				var s1 := line.trace(p + Vector3.UP * 1.6, q + Vector3.UP * 1.1, -1, false)
				if s1.blocker != "terrain" or float(s1.distance) < 35.0 or float(s1.distance) > 85.0:
					continue
				if line.trace(q + Vector3.UP * 1.6, p + Vector3.UP * 1.1, -1, false).blocker != "terrain":
					continue
				pick = {"p": p, "q": q, "crest_m": s1.distance}
				break
			if not pick.is_empty():
				break
		if not pick.is_empty():
			break
	_expect(not pick.is_empty(), "b_terrain: no crest between two dry, gentle places (precondition)")
	if pick.is_empty():
		return out
	out["crest_m"] = snappedf(pick.crest_m, 0.1)
	_quiet_area(pick.p, 600.0)
	var s := _shooter(1, pick.p, (pick.q - pick.p).normalized(), "SB")
	var t := _one(0, pick.q, (pick.p - pick.q).normalized(), "TB")
	await _frame(pick.p.lerp(pick.q, 0.5), 90.0)
	_put(s, pick.p)
	_put(t, pick.q)
	await _seconds(1.0)
	var holds0: int = demo.sim.brain.lof_holds
	_rec_shots(true)
	for k in 12:
		_put(t, pick.q)
		s.fire_at = t.position
		s.fire_until = demo.sim.state.time + 3.0
		await _seconds(1.0)
	_rec_shots(false)
	var mine := _shot_log.filter(func(sh: Dictionary) -> bool: return int(sh.shooter) == s.id)
	var into_hill := 0
	for sh: Dictionary in mine:
		if String(sh.blocker) == "terrain" and float(sh.distance) < 120.0 - 10.0:
			into_hill += 1
	out["shots"] = mine.size()
	out["into_hillside"] = into_hill
	out["lof_holds"] = demo.sim.brain.lof_holds - holds0
	out["reason"] = s.ai_reason
	out["target_hit"] = t.health < t.max_health
	_expect(into_hill == 0, "b_terrain: %d rounds into the hillside" % into_hill)
	_expect(int(out.lof_holds) > 0, "b_terrain: the mission never met the blocked line (precondition)")
	return out


func _c_corner() -> Dictionary:
	var out := {}
	var hz: float = _house.hz
	var at := _hp(0.0, -hz - 1.0)
	var t_at := _hp(14.0, hz + 60.0)
	# The shooter is the player's (no squad tactics of the AI's own command move him about); the target holds fire.
	var pf := demo.sim.state.war.player_faction
	var s := _shooter(pf, at, _house.front, "SC")
	var t := _one(1 - pf, t_at, -(_house.front as Vector3), "TC")
	await _frame(_house.c, 60.0, (_house.yaw as float) + PI)
	_put(s, at)
	_put(t, t_at)
	await _seconds(1.0)
	var ev0: Dictionary = demo.sim.brain.cover_eval.judge(s.position, t.position)
	out["start"] = {"level": CoverEval.LEVEL_NAMES[int(ev0.level)], "can_fire": ev0.can_fire}
	var moves0: int = demo.sim.brain.lof_moves
	_rec_shots(true)
	var first_shot := INF
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(2.0)
	var trail: Array = []
	var last_note := ""
	while demo.sim.state.time - t0 < 40.0:
		if s.cover_note != last_note:
			last_note = s.cover_note
			trail.append([snappedf(demo.sim.state.time - t0, 0.1), _local_of(s.position), last_note])
		if t.position.distance_to(t_at) > 0.5:
			_put(t, t_at)
		s.fire_at = t.position
		s.fire_until = demo.sim.state.time + 3.0
		await _physics(10)
		if first_shot == INF and _shot_log.any(func(sh: Dictionary) -> bool: return int(sh.shooter) == s.id and String(sh.blocker) != "tree"):
			first_shot = demo.sim.state.time - t0
	CoreDemo.apply_time_scale(1.0)
	_rec_shots(false)
	var mine := _shot_log.filter(func(sh: Dictionary) -> bool: return int(sh.shooter) == s.id)
	var into_house := mine.filter(func(sh: Dictionary) -> bool: return String(sh.blocker) == "tree" and float(sh.distance) < 15.0).size()
	out["trail"] = trail
	out["moves_for_line"] = demo.sim.brain.lof_moves - moves0
	out["moved_m"] = snappedf(SquadControl._flat(at, s.position), 0.1)
	out["shots"] = mine.size()
	out["into_house"] = into_house
	out["first_clear_shot_s"] = snappedf(first_shot, 0.1) if first_shot < INF else -1.0
	var ev1: Dictionary = demo.sim.brain.cover_eval.judge(s.position, t.position)
	out["end"] = {"level": CoverEval.LEVEL_NAMES[int(ev1.level)], "can_fire": ev1.can_fire, "note": s.cover_note}
	_png("c_corner")
	_expect(int(out.moves_for_line) >= 1 and first_shot < INF, "c_corner: no move to a firing position / no shot past the house (%s)" % s.cover_note)
	_expect(into_house <= 1, "c_corner: %d rounds into the house" % into_house)
	_expect(not demo.sim.structures.blocks_trunk(Vector2(s.position.x, s.position.z), 0.2), "c_corner: ended inside a solid")
	return out


## p in the house's frame (x along its side axis, z along its front axis; the walls at |x| 4, |z| 5.75).
func _local_of(p: Vector3) -> Array:
	var l := (_house.basis as Basis).inverse() * (p - (_house.c as Vector3))
	return [snappedf(l.x, 0.1), snappedf(l.z, 0.1)]


## Where the squad's soldiers ended against their places; spacing; inside solids.
func _places_facts(sq: SquadState, plan: Dictionary) -> Dictionary:
	var pts: Array = plan.values()
	var min_gap := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			min_gap = minf(min_gap, SquadControl._flat(pts[i], pts[j]))
	var inside := 0
	for p: Vector3 in pts:
		if demo.sim.structures.blocks_trunk(Vector2(p.x, p.z), 0.3):
			inside += 1
	return {"n": pts.size(), "min_gap_m": snappedf(min_gap, 0.01), "inside_solid": inside, "placed": sq.placed.size()}


func _arrival(sq: SquadState, limit: float) -> Dictionary:
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(3.0)
	while demo.sim.state.time - t0 < limit and sq.status == SquadState.Status.MOVING:
		await _physics(10)
	CoreDemo.apply_time_scale(1.0)
	await _seconds(2.0)
	var off: Array = []
	var stuck := 0
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if u == null or not sq.placed.has(id):
			continue
		off.append(snappedf(SquadControl._flat(u.position, sq.placed[id]), 0.1))
		if u.move_state == UnitState.MoveState.BLOCKED:
			stuck += 1
	off.sort()
	return {"took_s": snappedf(demo.sim.state.time - t0, 0.1), "off_place_m": off, "blocked": stuck}


func _levels(info: Dictionary) -> Dictionary:
	var n := {"heavy": 0, "light": 0, "exposed": 0, "unknown": 0, "fire": 0}
	for id in info:
		var r: Dictionary = info[id]
		match int(r.get("level", -1)):
			CoverEval.Level.HEAVY:
				n.heavy += 1
			CoverEval.Level.LIGHT:
				n.light += 1
			CoverEval.Level.NONE:
				n.exposed += 1
			_:
				n.unknown += 1
		if int(r.get("fire", -1)) == CoverEval.Fire.CLEAR:
			n.fire += 1
	return n


func _d_click() -> Dictionary:
	var out := {}
	var hz: float = _house.hz
	var sq := _player_squad8(_hp(-3.0, -hz - 30.0), _house.front, "PC")
	# A believed enemy 120 m out in front of the house: the back wall is the cover.
	await _contact(sq.faction, _hp(5.0, hz + 120.0))
	var yaw: float = float(_house.yaw) + PI
	await _frame(_hp(0.0, -hz - 8.0), 55.0, yaw)
	demo.rts.select_squads([sq.id])
	await _seconds(1.0)
	var cam := demo.rts_camera.camera
	var click3 := _hp(1.5, -hz - 1.6)
	var at := cam.unproject_position(click3)
	_mouse_move(at, 0)
	await _seconds(0.5)
	_mouse_move(at + Vector2(1, 0), 0)
	await _seconds(0.5)
	out["hover_plan"] = demo.rts.hover_plan.size()
	out["hover_levels"] = _levels(demo.rts.hover_info)
	_png("d_click_preview")
	_expect(demo.rts.hover_plan.size() == 8, "d_click: the preview under the cursor shows %d of 8 places" % demo.rts.hover_plan.size())
	var preview: Dictionary = demo.rts.hover_plan.duplicate()
	_mouse_button(MOUSE_BUTTON_RIGHT, at + Vector2(1, 0), true)
	await _physics(2)
	_mouse_button(MOUSE_BUTTON_RIGHT, at + Vector2(1, 0), false)
	await _physics(3)
	out["feedback"] = demo.rts.tactic_feedback
	out["places"] = _places_facts(sq, sq.placed)
	var same := 0
	for id in sq.placed:
		if preview.has(id) and (preview[id] as Vector3).distance_to(sq.placed[id]) < 0.05:
			same += 1
	out["same_as_preview"] = same
	_expect(sq.placed.size() == 8, "d_click: %d of 8 placed" % sq.placed.size())
	_expect(same == 8, "d_click: the order differs from the preview (%d same)" % same)
	_expect(float(out.places.min_gap_m) >= 1.1 and int(out.places.inside_solid) == 0, "d_click: places %s" % str(out.places))
	_expect(int(out.hover_levels.heavy) >= 5, "d_click: only %d heavy places behind the house" % int(out.hover_levels.heavy))
	out["arrival"] = await _arrival(sq, 60.0)
	var off: Array = out.arrival.off_place_m
	_expect(not off.is_empty() and float(off[off.size() - 1]) <= 2.2, "d_click: soldiers short of their places %s" % str(off))
	_png("d_click_arrived")
	# where the soldiers stand now, judged against the contact
	var prot := 0
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if u and int(demo.sim.brain.cover_eval.judge(u.position, _hp(5.0, hz + 120.0)).level) >= CoverEval.Level.LIGHT:
			prot += 1
	out["standing_protected"] = prot
	return out


func _e_direction() -> Dictionary:
	var out := {}
	var ce: CoverEval = demo.sim.brain.cover_eval
	var hz: float = _house.hz
	# Behind the house.
	var p := _hp(0.0, -hz - 1.0)
	var rows := {}
	for k: String in ["front", "side", "rear"]:
		var th: Vector3
		match k:
			"front":
				th = _hp(0.0, 60.0)
			"side":
				th = _hp(60.0, -hz - 1.0)
			"rear":
				th = _hp(0.0, -hz - 60.0)
		var r := ce.judge(p, th)
		rows[k] = {"level": CoverEval.LEVEL_NAMES[int(r.level)], "fire": "clear" if int(r.fire) == CoverEval.Fire.CLEAR else "blocked"}
	out["house"] = rows
	_expect(rows.front.level == "heavy cover" and rows.front.fire == "blocked", "e_direction: house front %s" % str(rows.front))
	_expect(rows.side.level != "heavy cover" and rows.rear.level == "exposed", "e_direction: house side / rear %s %s" % [str(rows.side), str(rows.rear)])
	# Behind the nearest garden wall / sandbag wall / concrete block row of the detail layer.
	var best := {}
	for id in [33, 42, 35, 40]:
		var w := _nearest_detail(id, _house.c, 150.0)
		if not w.is_empty():
			best = w
			break
	if best.is_empty():
		out["wall"] = "none within 150 m"
		return out
	var wb: Basis = best.basis
	var wc: Vector3 = best.c
	var hzw: float = best.hz
	var wp := demo.on_ground(wc.x - wb.z.x * (hzw + 1.0), wc.z - wb.z.z * (hzw + 1.0), 0.0)
	var wrows := {}
	for k: String in ["front", "side", "rear"]:
		var th: Vector3
		match k:
			"front":
				th = wc + wb.z * 60.0
			"side":
				th = wp + wb.x * 60.0
			"rear":
				th = wc - wb.z * 60.0
		th = demo.on_ground(th.x, th.z, 0.0)
		var r := ce.judge(wp, th)
		wrows[k] = {"level": CoverEval.LEVEL_NAMES[int(r.level)], "fire": "clear" if int(r.fire) == CoverEval.Fire.CLEAR else "blocked", "stand": r.stand}
	out["wall"] = {"id": best.id, "height": snappedf(best.h, 0.01), "at": _v(wc), "judged": wrows}
	_expect(wrows.front.level != "exposed", "e_direction: wall front %s" % str(wrows.front))
	_expect(wrows.rear.level != "heavy cover", "e_direction: wall rear %s" % str(wrows.rear))
	return out


func _nearest_detail(mesh_id: int, near: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for rec: Dictionary in _details.values():
		if int(rec.get("mesh", -1)) != mesh_id:
			continue
		var t: Array = rec.transform
		var p := Vector3(t[9], t[10], t[11])
		var d := Vector2(p.x - near.x, p.z - near.z).length()
		if d < bd:
			bd = d
			best = {"p": p}
	if best.is_empty():
		return {}
	var line := demo.sim.combat.line
	for cell: Vector2i in line.cells_along(best.p, best.p):
		line.warm(cell)
	var data_best := {}
	var dd := 4.0
	var p: Vector3 = best.p
	for bx in range(floori((p.x - 8.0) / LineOfFire.BUCKET), floori((p.x + 8.0) / LineOfFire.BUCKET) + 1):
		for bz in range(floori((p.z - 8.0) / LineOfFire.BUCKET), floori((p.z + 8.0) / LineOfFire.BUCKET) + 1):
			var data: PackedFloat32Array = line._buckets.get(Vector2i(bx, bz), PackedFloat32Array())
			for i in range(0, data.size(), LineOfFire.STRIDE):
				if data[i + 5] < 1.5:
					continue
				var d := Vector2(data[i] - p.x, data[i + 1] - p.z).length()
				if d < dd:
					dd = d
					data_best = {"id": mesh_id, "c": Vector3(data[i], data[i + 2], data[i + 1]), "basis": Basis(Vector3.UP, data[i + 6]),
						"hx": data[i + 7], "hz": data[i + 8], "h": data[i + 4]}
	return data_best


func _f_drag() -> Dictionary:
	var out := {}
	var hz: float = _house.hz
	var sq := _player_squad8(_hp(0.0, -hz - 35.0), _house.front, "PD")
	await _contact(sq.faction, _hp(0.0, hz + 140.0))
	var yaw: float = float(_house.yaw) + PI
	await _frame(_hp(0.0, -hz - 5.0), 75.0, yaw)
	demo.rts.select_squads([sq.id])
	await _seconds(1.0)
	var cam := demo.rts_camera.camera
	# A drag roughly along the back of the house and on past it (2.5-4 m off the wall, longer than the wall).
	var a3 := _hp(-14.0, -hz - 3.5)
	var b3 := _hp(12.0, -hz - 2.5)
	var a := cam.unproject_position(a3)
	var b := cam.unproject_position(b3)
	_mouse_move(a, 0)
	await _physics(2)
	_mouse_button(MOUSE_BUTTON_RIGHT, a, true)
	await _physics(2)
	for i in range(1, 11):
		_mouse_move(a.lerp(b, i / 10.0), MOUSE_BUTTON_MASK_RIGHT)
		await _physics(3)
	await _seconds(0.4)
	_mouse_move(b, MOUSE_BUTTON_MASK_RIGHT)
	await _seconds(0.3)
	out["preview"] = demo.rts.rdrag_plan.size()
	out["preview_levels"] = _levels(demo.rts.rdrag_info)
	var kinds := {}
	for id in demo.rts.rdrag_info:
		var k := String((demo.rts.rdrag_info[id] as Dictionary).get("kind", "?"))
		kinds[k] = int(kinds.get(k, 0)) + 1
	out["preview_kinds"] = kinds
	_png("f_drag_preview")
	_mouse_button(MOUSE_BUTTON_RIGHT, b, false)
	await _physics(3)
	out["feedback"] = demo.rts.tactic_feedback
	out["places"] = _places_facts(sq, sq.placed)
	var far := 0.0
	for p: Vector3 in sq.placed.values():
		far = maxf(far, SquadPositions._seg_dist(p, a3, b3))
	out["max_off_line_m"] = snappedf(far, 0.1)
	_expect(sq.placed.size() == 8, "f_drag: %d of 8 placed" % sq.placed.size())
	_expect(float(out.places.min_gap_m) >= 1.1 and int(out.places.inside_solid) == 0, "f_drag: places %s" % str(out.places))
	_expect(far <= 10.0, "f_drag: a place %.1f m off the dragged line" % far)
	_expect(int(out.preview_levels.heavy) + int(out.preview_levels.light) >= 6, "f_drag: only %s in cover" % str(out.preview_levels))
	out["arrival"] = await _arrival(sq, 60.0)
	_png("f_drag_arrived")
	return out


func _g_fight() -> Dictionary:
	var out := {}
	var hz: float = _house.hz
	var sq := _player_squad8(_hp(-2.0, -hz - 25.0), _house.front, "PG")
	var en_at := _hp(-6.0, hz + 105.0)
	await _contact(sq.faction, en_at)
	demo.rts.select_squads([sq.id])
	var cp := demo.rts.cover_plan_at(_hp(0.0, -hz - 1.5), [sq.id])
	_expect(not cp.is_empty(), "g_fight: no cover plan at the house")
	if cp.is_empty():
		return out
	demo.rts._order_cover([sq.id], cp, _hp(0.0, -hz - 1.5))
	await _arrival(sq, 50.0)
	var en := _cs.spawn(1, en_at, -(_house.front as Vector3), 8, "EG")
	_tough([en])
	demo.sim.squads.order_hold([en.id])
	await _frame(_hp(0.0, 10.0), 110.0, float(_house.yaw) + PI * 0.75)
	var b0 := {"lof_holds": demo.sim.brain.lof_holds, "lof_moves": demo.sim.brain.lof_moves, "lof_stands": demo.sim.brain.lof_stands,
		"own_cover_holds": demo.sim.brain.own_cover_holds, "friendly_holds": demo.sim.brain.friendly_holds,
		"ground_saves": demo.sim.brain.ground_saves}
	_rec_shots(true)
	var t0 := demo.sim.state.time
	var near_place := 0
	var samples := 0
	CoreDemo.apply_time_scale(2.0)
	var shot_mid := false
	var trails := {}
	while demo.sim.state.time - t0 < 60.0:
		await _physics(15)
		for id in sq.members.slice(0, 3):
			var u := demo.sim.state.get_unit(id)
			if u == null or not sq.placed.has(id):
				continue
			var tr: Array = trails.get(id, [])
			var line := "%s|%s|%s|%.1f" % [demo.sim.brain.order_mode(u), u.cover_note, u.ai_reason, SquadControl._flat(u.position, sq.placed[id])]
			if tr.is_empty() or String(tr[tr.size() - 1][1]) != line:
				tr.append([snappedf(demo.sim.state.time - t0, 0.1), line])
			trails[id] = tr
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			if u == null or not u.alive or not sq.placed.has(id):
				continue
			samples += 1
			if SquadControl._flat(u.position, sq.placed[id]) <= 3.6:
				near_place += 1
		if not shot_mid and demo.sim.state.time - t0 > 25.0:
			shot_mid = true
			CoreDemo.apply_time_scale(1.0)
			await _seconds(0.5)
			_png("g_fight")
			CoreDemo.apply_time_scale(2.0)
	CoreDemo.apply_time_scale(1.0)
	_rec_shots(false)
	var per := {}
	for side: String in ["player", "enemy"]:
		per[side] = {"shots": 0, "hits": 0, "into_own_cover": 0, "into_terrain_short": 0}
	for sh: Dictionary in _shot_log:
		var u := demo.sim.state.get_unit(int(sh.shooter))
		if u == null:
			continue
		var side := "player" if u.faction == sq.faction else "enemy"
		per[side].shots += 1
		if int(sh.hit_unit) > 0:
			per[side].hits += 1
		elif String(sh.blocker) in ["tree", "structure"] and float(sh.distance) < 6.0:
			per[side].into_own_cover += 1
		elif String(sh.blocker) == "terrain" and float(sh.distance) < 30.0:
			per[side].into_terrain_short += 1
	out["shots"] = per
	out["brain"] = {"lof_holds": demo.sim.brain.lof_holds - int(b0.lof_holds), "lof_moves": demo.sim.brain.lof_moves - int(b0.lof_moves),
		"lof_stands": demo.sim.brain.lof_stands - int(b0.lof_stands), "own_cover_holds": demo.sim.brain.own_cover_holds - int(b0.own_cover_holds),
		"friendly_holds": demo.sim.brain.friendly_holds - int(b0.friendly_holds), "ground_saves": demo.sim.brain.ground_saves - int(b0.ground_saves)}
	out["placed_kept_share"] = snappedf(float(near_place) / maxi(samples, 1), 0.01)
	out["trails"] = trails
	out["squad"] = {"order": sq.order, "tactic": sq.tactic, "owner": sq.tactic_owner, "why": sq.tactic_why if "tactic_why" in sq else ""}
	var alive := [0, 0]
	for id in sq.members:
		alive[0] += 1 if demo.sim.state.get_unit(id) and demo.sim.state.get_unit(id).alive else 0
	for id in en.members:
		alive[1] += 1 if demo.sim.state.get_unit(id) and demo.sim.state.get_unit(id).alive else 0
	out["alive"] = {"player": alive[0], "enemy": alive[1]}
	_expect(int(per.player.shots) > 0 and int(per.enemy.shots) > 0, "g_fight: no fight (shots %s)" % str(per))
	_expect(float(out.placed_kept_share) >= 0.85, "g_fight: soldiers left their places (%.2f near them)" % out.placed_kept_share)
	var wasted := int(per.player.into_own_cover) + int(per.enemy.into_own_cover)
	_expect(wasted * 10 <= int(per.player.shots) + int(per.enemy.shots), "g_fight: %d of the rounds into own cover" % wasted)
	return out


func _q_perf() -> Dictionary:
	var out := {}
	var hz: float = _house.hz
	var sq := _player_squad8(_hp(0.0, -hz - 30.0), _house.front, "PQ")
	await _contact(sq.faction, _hp(0.0, hz + 120.0))
	await _seconds(0.5)
	var t0 := Time.get_ticks_usec()
	for k in 10:
		demo.rts.cover_plan_at(_hp(-2.0 + k * 0.4, -hz - 1.5), [sq.id])
	out["click_plan_ms"] = snappedf((Time.get_ticks_usec() - t0) / 10000.0, 0.01)
	var info := {}
	var threats: Array = demo.rts.order_threats([sq.id], [], _house.c)
	t0 = Time.get_ticks_usec()
	for k in 10:
		demo.sim.squads.place_plan([sq.id], _hp(-12.0, -hz - 3.0 - k * 0.2), _hp(10.0, -hz - 2.5), _house.front, true, {}, {"threats": threats, "snap": 3.0, "overflow": 8.0}, info)
	out["drag_plan_ms"] = snappedf((Time.get_ticks_usec() - t0) / 10000.0, 0.01)
	var ce: CoverEval = demo.sim.brain.cover_eval
	t0 = Time.get_ticks_usec()
	for k in 100:
		ce.judge(_hp(-4.0 + k * 0.08, -hz - 1.0), _hp(0.0, hz + 120.0))
	out["judge_us"] = snappedf((Time.get_ticks_usec() - t0) / 100.0, 0.1)
	_expect(float(out.click_plan_ms) < 25.0, "q_perf: a click plan takes %.1f ms" % out.click_plan_ms)
	return out


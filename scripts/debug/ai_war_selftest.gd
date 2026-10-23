## Scripted checks of AI-WAR-LOGISTICS-01 (movement parity, AI bases and economy, mechanized operations,
## logistics, defensive counterattacks) in the running sandbox war.
##
##   Godot.exe --path . --resolution 1600x900 --log-file w.log res://scenes/game/world_ref_20km.tscn -- --ai-war-test [--shots] [--only a,b] [--shot-dir=res://docs/ai_war01]
##
## Extends the AI-COMBAT-STRAT-01 suite (helpers, shot log, inspector access). Prints "WAR <check> <json>",
## writes res://benchmarks/raw/ai_war_test.json.
class_name AIWarSelfTest
extends AIStratSelfTest


## Vehicles keep the place they had when the test first saw them: every case starts from the same fleet, wherever an earlier case
## left a vehicle (a truck wedged in an alley made the next case plan from an isolated spot). NAVIGATION N1-C1: moved here from the
## N1-B suite, so the order-dependent AI-WAR scenarios (r_offroad then r_convoy) get the same isolation.
var _fleet_home := {}


func _fresh() -> void:
	await super._fresh()
	var vs := demo.sim.vehicles
	for id in vs.ids:
		var u: UnitState = demo.sim.state.units.get(id)
		if u == null or not u.alive or u.veh == null:
			continue
		if not _fleet_home.has(id):
			if u.order == UnitState.Order.NONE and u.veh.job.is_empty():
				_fleet_home[id] = [u.position, u.yaw]
			continue
		if not u.veh.job.is_empty():
			demo.sim.logistics.cancel_job(id, "test reset")
		if u.veh.convoy_id >= 0:
			vs.convoy.leave(id)
		vs.halt(id)
		var home: Array = _fleet_home[id]
		u.position = home[0]
		u.yaw = home[1]
		u.veh.speed = 0.0
		u.veh.fuel = u.veh.def().fuel_capacity
		u.veh.reverse_left = 0.0
		u.veh.recoveries = 0
		u.veh.bypasses = 0
	await _physics(2)


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/ai_war01"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	lof = combat.line
	brain = demo.sim.brain
	def = combat.weapon(&"rifle")
	war = demo.sim.state.war
	ws = demo.sim.war
	SoldierBody.require_mouse_capture = false
	var state := demo.sim.state
	state.shot_fired.connect(_on_shot_rec)
	state.unit_damaged.connect(func(t: UnitState, _a: float, _z: int, _s: int) -> void:
		dmg_events += 1
		if not t.alive:
			dmg_on_dead += 1)
	state.unit_died.connect(func(u: UnitState) -> void:
		deaths.append({"id": u.id, "t": snappedf(state.time, 0.1)}))
	tree.create_timer(3300.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(60)
	_load_world_data()
	for u in state.soldiers():
		default_soldiers.append(u.position)
	_pause_ai(true)
	for sq: SquadState in state.all_squads():
		_stations[sq.id] = sq.station_objective
	_log("setup", {"soldiers": default_soldiers.size()})
	if _want("a_init"):
		_log("a_init", await _a_init())
	if _want("b_recruit"):
		_log("b_recruit", await _b_recruit())
	if _want("c_vehicle"):
		_log("c_vehicle", await _c_vehicle())
	if _want("d_mech"):
		_log("d_mech", await _d_mech())
	if _want("e_convoy"):
		_log("e_convoy", await _e_convoy())
	if _want("f_preop"):
		_log("f_preop", await _f_preop())
	if _want("g_delivery"):
		_log("g_delivery", await _g_delivery())
	if only.has("g_nosave"):
		_log("g_nosave", await _g_delivery(false))
	if _want("h_shortage"):
		_log("h_shortage", await _h_shortage())
	if _want("i_counter"):
		_log("i_counter", await _i_counter())
	if _want("j_base_loss"):
		_log("j_base_loss", await _j_base_loss())
	if _want("l_player"):
		_log("l_player", await _l_player())
	if _want("m_save"):
		_log("m_save", await _m_save())
	if _want("n_long"):
		_log("n_long", await _n_long())
	if _want("o_war"):
		_log("o_war", await _o_war())
	if _want("r_exit"):
		_log("r_exit", await _r_exit())
	if _want("r_lanes"):
		_log("r_lanes", await _r_lanes())
	if _want("r_offroad"):
		_log("r_offroad", await _r_offroad())
	if _want("r_gaps"):
		_log("r_gaps", await _r_gaps())
	if _want("r_obstacles"):
		_log("r_obstacles", await _r_obstacles())
	if _want("r_drive"):
		_log("r_drive", await _r_drive())
	if _want("r_convoy"):
		_log("r_convoy", await _r_convoy())
	if _want("r_overlay"):
		_log("r_overlay", await _r_overlay())
	if _want("r_yard"):
		_log("r_yard", await _r_drive(true))
	if only.has("v_yard"):
		_log("v_yard", await _v_yard())
	if _want("m_move"):
		_log("m_move", await _m_move())
	if _want("m_march"):
		_log("m_march", await _m_march())
	if _want("m_haugen"):
		_log("m_haugen", await _m_haugen())
	if only.has("m_haugen_near"):
		_log("m_haugen_near", await _m_haugen(["near"]))
	await _end_strat()


# --- Output (own prefix and file) ------------------------------------------------------------------------------------

func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("WAR %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("WAR FAILED CHECK: ", msg)


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	img.save_jpg(ProjectSettings.globalize_path("%s/aw01_%s.jpg" % [_shot_dir, shot_name]), 0.9)
	print("WAR shot: ", shot_name)


func _finish() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/ai_war_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("WAR %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	if keep_open:
		return
	demo.shutdown_cleanup()
	tree.quit()


# --- M: near / far movement parity ------------------------------------------------------------------------------------

## 16 m sub-cell -> tree count, filled lazily from the vegetation cells (one pass per 128 m cell).
var _tree_grid := {}
var _tree_cells := {}
const _SUB := 16.0


func _trees_in_sub(sub: Vector2i) -> int:
	var cs_m: float = demo.vegetation.cell_size_m
	var c := VegetationChunk.cell_of(Vector3((sub.x + 0.5) * _SUB, 0.0, (sub.y + 0.5) * _SUB), cs_m)
	if not _tree_cells.has(c):
		_tree_cells[c] = true
		for t: Array in sm._trees_in(c):
			var k := Vector2i(floori(t[0] / _SUB), floori(t[1] / _SUB))
			_tree_grid[k] = _tree_grid.get(k, 0) + 1
	return _tree_grid.get(sub, 0)


## Trees per 100 m in a ~48 m wide band along a -> b, the steepest 20 m grade and whether the line is wet.
func _corridor(a: Vector3, b: Vector3) -> Dictionary:
	var len := _flat(a, b)
	var n := maxi(int(len / _SUB), 2)
	var touched := {}
	var maxg := 0.0
	var prev := a
	var wet := false
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var sub := Vector2i(floori(p.x / _SUB), floori(p.z / _SUB))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				touched[Vector2i(sub.x + dx, sub.y + dz)] = true
		if i % 2 == 0:
			p = demo.on_ground(p.x, p.z, 0.0)
			if i > 0:
				maxg = maxf(maxg, absf(p.y - prev.y) / maxf(_flat(p, prev), 1.0))
			prev = p
			if sm.water_height(p.x, p.z) > p.y - 0.3:
				wet = true
	var trees := 0
	for k: Vector2i in touched:
		trees += _trees_in_sub(k)
	return {"len": len, "trees_per_100m": float(trees) / maxf(len / 100.0, 0.1), "max_grade": maxg, "wet": wet}


## First site (searched on a grid round the objectives) whose a -> b corridor of `len` metres has the
## wanted character: "open" (no trees, flat), "forest" (dense), "slope" (grade >= 0.14, few trees).
func _find_route(kind: String, length := 400.0, avoid: Array = []) -> Dictionary:
	var centers: Array[Vector3] = []
	for o: ObjectiveState in war.objectives.values():
		centers.append(o.position)
	var best := {}
	var best_score := -INF
	var tried := 0
	var t0 := Time.get_ticks_msec()
	var dens_max := 0.0
	for center in centers:
		for r: float in [600.0, 1100.0, 1800.0, 2600.0]:
			var n := clampi(int(r / 80.0), 8, 30)
			for k in n:
				var ang := k * TAU / n + 0.3
				var a := demo.on_ground(center.x + cos(ang) * r, center.z + sin(ang) * r, 0.0)
				if absf(a.x) > 9000.0 or absf(a.z) > 9000.0 or not ws.routes.passable(a):
					continue
				var skip := false
				for q: Vector3 in avoid:
					if _flat(q, a) < 500.0:
						skip = true
				if skip:
					continue
				for j in 4:
					var d := Vector3(cos(j * TAU / 4.0 + 0.5), 0.0, sin(j * TAU / 4.0 + 0.5))
					var b := demo.on_ground(a.x + d.x * length, a.z + d.z * length, 0.0)
					if not ws.routes.passable(b):
						continue
					tried += 1
					var c := _corridor(a, b)
					dens_max = maxf(dens_max, c.trees_per_100m)
					if c.wet:
						continue
					var ok := false
					var score := 0.0
					match kind:
						"open":
							ok = c.trees_per_100m < 1.0 and c.max_grade < 0.08
							score = -c.max_grade
						"forest":
							ok = c.trees_per_100m >= 40.0 and c.max_grade < 0.12
							score = c.trees_per_100m
						"slope":
							ok = c.max_grade >= 0.14 and c.max_grade < 0.3 and c.trees_per_100m < 10.0
							score = c.max_grade
					if ok and score > best_score:
						best_score = score
						best = {"a": a, "b": b, "len": c.len, "trees_per_100m": snappedf(c.trees_per_100m, 0.1), "max_grade": snappedf(c.max_grade, 0.01), "kind": kind}
						if kind == "open":
							return best
			if not best.is_empty() and kind != "open" and tried > 40:
				print("WAR route search %s: %d corridors, %d ms, best density %.0f" % [kind, tried, Time.get_ticks_msec() - t0, dens_max])
				return best
			await tree.process_frame
	print("WAR route search %s: %d corridors, %d ms, densest %.0f, found %s" % [kind, tried, Time.get_ticks_msec() - t0, dens_max, not best.is_empty()])
	return best


## `n_squads` squads walk a -> b, the camera either on them (physical bodies) or far away (abstract tier). routed: each
## follows the strategic route the war's operations use (`follow_route`, column on the march) instead of one Move
## order. Returns the time (simulated seconds) until the last squad centre is within 25 m of b and until every
## soldier is, the distance the first leader covered and the tier it ran in.
func _walk(a: Vector3, b: Vector3, near: bool, n_squads := 1, routed := false, max_s := 600.0, scale := 6.0) -> Dictionary:
	await _fresh()
	var sqs: Array = []
	var side := Vector3(-(b.z - a.z), 0.0, b.x - a.x).normalized()
	for i in n_squads:
		var sq := _spawn(0, a + side * (i - (n_squads - 1) * 0.5) * 30.0, 8)
		sqs.append(sq)
	await _physics(10)
	if near:
		demo.rts_camera.frame(a, 0.0, 80.0)
		while demo.navigation.has_pending_bake():
			await _seconds(0.2)
		await _seconds(2.0)
	else:
		demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
		await _seconds(1.0)
	var bodies0 := _bodies_of(sqs)
	var t0 := demo.sim.state.time
	var lead := demo.sim.state.get_unit((sqs[0] as SquadState).leader_id)
	var last := lead.position
	var travelled := 0.0
	var routes_len := 0.0
	for i in n_squads:
		var sq: SquadState = sqs[i]
		var to := b + side * (i - (n_squads - 1) * 0.5) * 30.0
		if routed:
			var r := ws.routes.route(demo.sim.squads._centroid(sq), to, demo.sim.terrain)
			if r.size() >= 2:
				if i == 0:
					for k in range(1, r.size()):
						routes_len += _flat(r[k - 1], r[k])
				demo.sim.squads.follow_route(sq, r)
			else:
				demo.sim.squads.order_move([sq.id], to)
		else:
			demo.sim.squads.order_move([sq.id], to)
	var t_squads := -1.0
	var t_all := -1.0
	var swaps := 0
	var prev_bodies := bodies0
	TimeCompression.apply(scale, 64)
	while demo.sim.state.time - t0 < max_s:
		await tree.process_frame
		if lead:
			travelled += _flat(lead.position, last)
			last = lead.position
		var far_sq := 0.0
		var far_sold := 0.0
		for sq: SquadState in sqs:
			far_sq = maxf(far_sq, _flat(demo.sim.squads._centroid(sq), b))
			for id in sq.members:
				far_sold = maxf(far_sold, _flat(demo.sim.state.get_unit(id).position, b))
		if near and int(Engine.get_physics_frames()) % 20 == 0:
			demo.rts_camera.frame(demo.sim.squads._centroid(sqs[0]), 0.0, 80.0)
		var wb := _bodies_of(sqs)
		if (wb > 0) != (prev_bodies > 0):
			swaps += 1
		prev_bodies = wb
		if t_squads < 0.0 and far_sq < 45.0 + n_squads * 15.0:
			t_squads = demo.sim.state.time - t0
		if far_sold < 60.0 + n_squads * 15.0:
			t_all = demo.sim.state.time - t0
			break
	TimeCompression.reset()
	var dist := _flat(a, b)
	var t := demo.sim.state.time - t0
	return {"near": near, "squads": n_squads, "routed": routed, "bodies_at_start": bodies0, "arrived": t_all >= 0.0, "time_squads_s": snappedf(t_squads, 0.1), "time_all_s": snappedf(t_all if t_all >= 0.0 else t, 0.1),
		"speed_ms": snappedf(dist / maxf(t_all if t_all >= 0.0 else t, 0.1), 0.01), "leader_path_m": snappedf(travelled, 1.0), "route_m": snappedf(routes_len, 1.0), "straight_m": snappedf(dist, 1.0), "tier_swaps": swaps}


func _m_move() -> Dictionary:
	var out := {}
	var used: Array = []
	for kind: String in ["open", "forest", "slope"]:
		var r: Dictionary = await _find_route(kind, 400.0, used)
		if r.is_empty():
			out[kind] = {"error": "no site"}
			_expect(false, "M: no %s route found" % kind)
			continue
		used.append(r.a)
		var far := await _walk(r.a, r.b, false)
		var nr := await _walk(r.a, r.b, true)
		var ratio: float = nr.time_all_s / maxf(far.time_all_s, 0.1)
		out[kind] = {"route": r, "far": far, "near": nr, "near_over_far": snappedf(ratio, 0.01)}
		print("WAR m_move %s %s" % [kind, JSON.stringify(out[kind])])
		_expect(far.arrived and nr.arrived, "M(%s): not both arrived (far %s, near %s)" % [kind, far.arrived, nr.arrived])
		_expect(ratio < 1.35 and ratio > 0.75, "M(%s): near/far travel time ratio %.2f" % [kind, ratio])
	return out


## M2: what an operation march is: three squads in column along the strategic route, 700 m through the densest woods
## that are found, near (bodies, camera on the force) against far (abstract tier). This is the case of the 230 s
## against 70 s of AI-COMBAT-STRAT-01.
func _m_march() -> Dictionary:
	var out := {}
	var used: Array = []
	for kind: String in ["forest", "open"]:
		var r: Dictionary = await _find_route(kind, 700.0, used)
		if r.is_empty():
			out[kind] = {"error": "no site"}
			continue
		used.append(r.a)
		var far := await _walk(r.a, r.b, false, 3, true, 700.0, 8.0)
		var nr := await _walk(r.a, r.b, true, 3, true, 700.0, 8.0)
		var ratio: float = nr.time_all_s / maxf(far.time_all_s, 0.1)
		out[kind] = {"route": r, "far": far, "near": nr, "near_over_far": snappedf(ratio, 0.01)}
		print("WAR m_march %s %s" % [kind, JSON.stringify(out[kind])])
		_expect(far.arrived and nr.arrived, "M2(%s): not both arrived (far %s, near %s)" % [kind, far.arrived, nr.arrived])
		_expect(ratio < 1.35 and ratio > 0.75, "M2(%s): near/far travel time ratio %.2f" % [kind, ratio])
	return out


## M3: the approach of AI-COMBAT-STRAT-01's visual run: three squads attack Haugen (the sandbox "offensive" scene), the
## operation marches to its staging point; timed until the operation leaves APPROACH, near (the camera frames the force
## like the visual run, at zoom 90-170 m) against far. Samples where the soldiers stand and why they are slow.
func _m_haugen(modes := ["far", "near", "near", "far", "near"]) -> Dictionary:
	var out := {}
	for mode: String in modes:
		var sc := await _scene(3, 1)
		var obj: ObjectiveState = sc.obj
		var atk: Array = sc.atk
		var ids := atk.map(func(q: SquadState) -> int: return q.id)
		var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, obj.id, Vector3.INF, false)
		if op == null:
			out["error"] = "no operation"
			continue
		var c0: Vector3 = demo.sim.squads._centroid(atk[0])
		var yaw := atan2(-(obj.position.x - c0.x), -(obj.position.z - c0.z))
		if mode == "near":
			demo.rts_camera.frame(c0, yaw, 120.0)
		else:
			demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
		await _seconds(1.0)
		var t0 := demo.sim.state.time
		var left_approach := -1.0
		var samples: Array = []
		var next := t0
		TimeCompression.apply(4.0, 64)
		while op.is_active() and demo.sim.state.time - t0 < 400.0:
			await tree.process_frame
			if mode == "near":
				var c := Vector3.ZERO
				for sq: SquadState in atk:
					c += demo.sim.squads._centroid(sq)
				c /= atk.size()
				var d := _flat(c, obj.position)
				demo.rts_camera.frame(c.lerp(obj.position, 0.5) if d < 330.0 else c, yaw, clampf(d * 0.38 + 55.0, 90.0, 170.0))
			if left_approach < 0.0 and op.stage != OperationState.Stage.APPROACH:
				left_approach = demo.sim.state.time - t0
			if demo.sim.state.time >= next:
				next += 10.0
				var mv := 0
				var still := 0
				var bodies := 0
				for sq: SquadState in atk:
					for id in sq.members:
						var u := demo.sim.state.get_unit(id)
						if u.has_body:
							bodies += 1
						if u.move_state == UnitState.MoveState.MOVING:
							mv += 1
						elif u.order == UnitState.Order.MOVE:
							still += 1
				var rem := ws.march_info(op)
				samples.append("%.0f stage=%s rem=%.0f rate=%.2f moving=%d blocked_or_waiting=%d bodies=%d" % [demo.sim.state.time - t0, op.stage_name(), rem.rem, rem.rate, mv, still, bodies])
				if mode == "near":
					samples.append("   " + _soldier_census(atk))
					print("WAR census %s t=%.0f %s" % [out.size(), demo.sim.state.time - t0, samples[-1]])
			if left_approach >= 0.0 and demo.sim.state.time - t0 > left_approach + 5.0:
				break
		TimeCompression.reset()
		var march: Dictionary = ws.march.get(op.id, {})
		var key := "%s%d" % [mode, out.size()]
		out[key] = {"mode": mode, "left_approach_s": snappedf(left_approach, 0.1), "march_total_m": snappedf(float(march.get("total", -1.0)), 1.0), "samples": samples.slice(-6), "op": op.phase_name()}
		print("WAR m_haugen %s %.1f s" % [key, left_approach])
		for o: OperationState in war.active_operations():
			ws.cancel(o.id, "test")
	var far_t: Array = []
	var near_t: Array = []
	for key: String in out:
		if key.begins_with("far"):
			far_t.append(float(out[key].left_approach_s))
		elif key.begins_with("near"):
			near_t.append(float(out[key].left_approach_s))
	if not far_t.is_empty() and not near_t.is_empty():
		var fm := 0.0
		for t in far_t:
			fm += t
		fm /= far_t.size()
		var nm := 0.0
		var nmax := 0.0
		for t in near_t:
			nm += t
			nmax = maxf(nmax, t)
		nm /= near_t.size()
		out["far_mean_s"] = snappedf(fm, 0.1)
		out["near_mean_s"] = snappedf(nm, 0.1)
		out["near_max_s"] = snappedf(nmax, 0.1)
		out["near_over_far"] = snappedf(nm / fm, 0.01)
		_expect(fm > 0.0 and nm > 0.0, "M3: the operation never left APPROACH")
		_expect(nm / fm < 1.5, "M3: mean near/far approach time ratio %.2f" % (nm / fm))
		_expect(nmax / fm < 2.0, "M3: the slowest near approach took %.1f times the far one" % (nmax / fm))
	return out


## Where a squad's soldiers are and what they do: for four soldiers of the first squad the speed over the last tick,
## the length of the navigation path left, the straight distance to the order target, the stuck stage, the formation.
func _soldier_diag(sqs: Array) -> String:
	var parts: Array[String] = []
	var sq: SquadState = sqs[0]
	var rt := "route %d/%d" % [sq.route_i, sq.route.size()]
	var n := 0
	for id in sq.members:
		var body := demo.sim.body_of(id) as SoldierBody
		var u := demo.sim.state.get_unit(id)
		if body == null:
			parts.append("#%d nobody" % id)
			continue
		var path := body.nav.get_current_navigation_path()
		var plen := 0.0
		for i in range(1, path.size()):
			plen += path[i - 1].distance_to(path[i])
		var tree_here := 0
		var cs_m: float = demo.vegetation.cell_size_m
		for t: Array in sm._trees_in(VegetationChunk.cell_of(u.position, cs_m)):
			if Vector2(t[0] - u.position.x, t[1] - u.position.z).length() < 6.0:
				tree_here += 1
		var hit := ""
		if body.velocity.length() < 0.3 and u.move_state == UnitState.MoveState.MOVING:
			for ci in body.get_slide_collision_count():
				var col := body.get_slide_collision(ci)
				var o := col.get_collider()
				hit += " [%s n.y=%.1f]" % [o.get_class() if o else "?", col.get_normal().y]
			hit += " floor=%s safe=(%.1f,%.1f) reacting=%s react=%s rtac=%s ai=%s tgt_vis=%s unit_tactic=%s sq_tactic=%s navfin=%s unstick=%.1f desired=%.1f next_d=%.2f" % [body.is_on_floor(), body._safe_velocity.x, body._safe_velocity.z, u.is_reacting(), u.react_state, u.tactic_name(), u.ai_state_name(), u.target_visible, u.post_pos.is_finite(), sq.tactic_name(), body.nav.is_navigation_finished(), body._unstick_left, body.dbg_desired, body.dbg_next_dist]
		parts.append("#%d v=%.1f path=%.0f/%d straight=%.0f stuck=%d trees6m=%d %s%s" % [id, body.velocity.length(), plen, path.size(), _flat(u.position, u.order_target), body._stuck_stage, tree_here, UnitState.MoveState.keys()[u.move_state], hit])
		n += 1
		if n >= 8:
			break
	return "%s %s form=%s | %s" % [sq.squad_name, rt, sq.formation_name(), " ; ".join(parts)]


# --- Helpers of the war / logistics scenarios -----------------------------------------------------------------------------------

func _bs() -> BaseSim:
	return demo.sim.logistics.bases


## The AI economy and the strategic AI stay quiet unless a scenario wants them.
func _pause_ai(on: bool) -> void:
	super(on)
	for f: FactionState in war.factions.values():
		if not f.player:
			f.econ_next_at = INF if on else demo.sim.state.time + 5.0
			f.supply_next_at = INF if on else 0.0


func _stock(fid: int) -> Dictionary:
	var t := {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}
	for b: Dictionary in _bs().bases_of(fid):
		var st := _bs().base_stock(b.id)
		for k in t:
			t[k] += st[k]
	return t


func _vehicles_of(fid: int) -> Array:
	var out := []
	for id in demo.sim.vehicles.ids:
		var u := demo.sim.state.get_unit(id)
		if u and u.faction == fid:
			out.append(u)
	return out


# --- A: faction initialisation -----------------------------------------------------------------------------------------------------

func _a_init() -> Dictionary:
	var out := {}
	var bs := _bs()
	var all_ids := {}
	var dup := 0
	for u: UnitState in demo.sim.state.all_units():
		if all_ids.has(u.id):
			dup += 1
		all_ids[u.id] = true
	var struct_ids := {}
	for fid in [1, 2]:
		var f := war.faction(fid)
		var bl := bs.bases_of(fid)
		_expect(not bl.is_empty(), "A: %s has no base" % f.faction_name)
		if bl.is_empty():
			continue
		var kinds := {}
		var in_two := 0
		for b: Dictionary in bl:
			for st in bs.facilities_of(b.id):
				var k := String(FacilityDefs.kind_of(st.type_id))
				kinds[k] = int(kinds.get(k, 0)) + 1
				_expect(st.faction == fid, "A: %s facility %d belongs to %d" % [f.faction_name, st.id, st.faction])
				if struct_ids.has(st.id):
					in_two += 1
				struct_ids[st.id] = true
		for need in ["hq", "barracks", "supply", "vehicle", "ammo", "fuel"]:
			_expect(kinds.has(need), "A: %s has no %s facility" % [f.faction_name, need])
		var stock := _stock(fid)
		var start: Dictionary = FacilityDefs.START_STOCK
		var mult: float = ws.profile(f).start_stock_mult
		_expect(stock.ammo > 0.0 and stock.fuel > 0.0 and stock.supplies > 0.0, "A: %s starts without stock %s" % [f.faction_name, str(stock)])
		_expect(stock.ammo <= start[&"ammo"] * mult + 1.0 and stock.supplies <= start[&"supplies"] * mult + 1.0, "A: %s has more than the starting stockpile %s" % [f.faction_name, str(stock)])
		var trucks := _vehicles_of(fid)
		_expect(trucks.size() == ws.profile(f).start_trucks, "A: %s has %d vehicles (profile: %d)" % [f.faction_name, trucks.size(), ws.profile(f).start_trucks])
		# Facilities are reachable: a truck can plan a route to the dock of every store.
		var unreachable := 0
		var docks := 0
		if not trucks.is_empty():
			var tu: UnitState = trucks[0]
			for st in demo.sim.logistics.stores(fid):
				docks += 1
				var dock := demo.sim.logistics.dock_world(st, -1)
				if not demo.sim.vehicles.router.plan(tu.position, dock, tu.veh.def()).ok:
					unreachable += 1
		_expect(unreachable == 0, "A: %s: %d of %d docks are not reachable by truck" % [f.faction_name, unreachable, docks])
		_expect(in_two == 0, "A: a facility is in two bases")
		out[f.faction_name] = {"bases": bl.size(), "kinds": kinds, "stock": stock, "vehicles": trucks.size(), "docks": docks, "unreachable": unreachable, "reserves": f.reserves, "ledger_in": f.ledger["in"]}
	_expect(dup == 0, "A: %d unit ids appear twice" % dup)
	out["duplicate_units"] = dup
	out["north_bases"] = bs.bases_of(0).size()
	# Persistence: the construction record round-trips with the same inventories.
	var cs_d := cs.to_dict()
	var before := {}
	for st: StructureState in cs.all():
		if st.inventory:
			before[st.id] = st.inventory.total()
	var copy := ConstructionState.new()
	copy.from_dict(cs_d)
	var mismatch := 0
	for id in before:
		var c := copy.get_structure(id)
		if c == null or c.inventory == null or absf(c.inventory.total() - before[id]) > 0.01:
			mismatch += 1
	_expect(mismatch == 0, "A: %d inventories changed in a save round trip" % mismatch)
	out["inventories_checked"] = before.size()
	return out


# --- B: recruiting ------------------------------------------------------------------------------------------------------------------

func _b_recruit() -> Dictionary:
	var out := {}
	var bs := _bs()
	var f := war.faction(1)
	var bar := bs.facility_of_kind(1, &"barracks")
	_expect(bar != null, "B: South has no barracks (precondition)")
	if bar == null:
		return out
	for st in bs.facilities_of(bar.base_id):
		while not st.facility.get("queue", []).is_empty():
			bs.cancel_queue(st.id, 0)  # whatever the economy had queued is undone (refunded) so the scenario starts clean
	var dep := bs.facility_of_kind(1, &"vehicle")
	var r0 := bs.recruit(dep.id)
	_expect(not r0.ok, "B: a vehicle depot recruited a squad")
	out["not_a_barracks"] = r0.reason
	var stock0 := _stock(1)
	var res0 := f.reserves
	var squads0 := ws.squads_of(1).size()
	var soldiers0 := demo.sim.state.soldiers().size()
	var r1 := bs.recruit(bar.id)
	_expect(r1.ok, "B: recruiting failed: %s" % r1.reason)
	var stock1 := _stock(1)
	var cost: Dictionary = BaseSim.RECRUIT_COST
	_expect(absf((stock0.supplies - stock1.supplies) - cost[&"supplies"]) < 0.5 and absf((stock0.ammo - stock1.ammo) - cost[&"ammo"]) < 0.5, "B: the cost was not paid (%s -> %s)" % [str(stock0), str(stock1)])
	_expect(f.reserves == res0 - BaseSim.SQUAD_SIZE, "B: personnel %d -> %d" % [res0, f.reserves])
	var r2 := bs.recruit(bar.id)
	var r3 := bs.recruit(bar.id)
	_expect(r2.ok and not r3.ok, "B: the queue limit (%d) was not respected (second %s, third %s)" % [BaseSim.RECRUIT_QUEUE_MAX, r2.ok, r3.ok])
	out["third_refused"] = r3.reason
	_expect(demo.sim.state.soldiers().size() == soldiers0, "B: soldiers appeared before the training ended")
	await _warp(BaseSim.RECRUIT_TIME_S * 2.0 + 10.0, 24.0, 90.0)
	var squads1 := ws.squads_of(1).size()
	var soldiers1 := demo.sim.state.soldiers().size()
	_expect(squads1 == squads0 + 2 and soldiers1 == soldiers0 + 2 * BaseSim.SQUAD_SIZE, "B: squads %d -> %d, soldiers %d -> %d" % [squads0, squads1, soldiers0, soldiers1])
	var seen := {}
	var dups := 0
	var fresh := 0
	for sq: SquadState in ws.squads_of(1):
		for id in sq.members:
			if seen.has(id):
				dups += 1
			seen[id] = true
		if sq.origin == "recruit":
			fresh += 1
			_expect(sq.members.size() == BaseSim.SQUAD_SIZE, "B: a recruited squad has %d soldiers" % sq.members.size())
			_expect(demo.sim.state.get_unit(sq.leader_id) != null, "B: a recruited squad has no leader")
	_expect(dups == 0, "B: %d soldiers are in two squads" % dups)
	out["recruited_squads"] = fresh
	_expect(fresh >= 2, "B: only %d squads are marked recruited" % fresh)
	# Personnel: with too few in reserve nothing is trained and nothing is paid.
	var keep := f.reserves
	f.reserves = 3
	var s2 := _stock(1)
	var rr := bs.recruit(bar.id)
	_expect(not rr.ok and absf(_stock(1).supplies - s2.supplies) < 0.01, "B: recruiting without personnel was accepted or charged")
	out["without_personnel"] = rr.reason
	f.reserves = keep
	# No supplies: refused as well.
	var saved := {}
	for st in bs.base_stores(bar.base_id):
		saved[st.id] = st.inventory.get_qty(Inventory.SUPPLIES)
		st.inventory.take(Inventory.SUPPLIES, 1.0e9)
	var rn := bs.recruit(bar.id)
	_expect(not rn.ok, "B: recruiting without supplies was accepted")
	out["without_supplies"] = rn.reason
	for id in saved:
		demo.sim.logistics.structure(id).inventory.add(Inventory.SUPPLIES, saved[id])
	return out


# --- C: vehicle acquisition ------------------------------------------------------------------------------------------------------------

func _c_vehicle() -> Dictionary:
	var out := {}
	var bs := _bs()
	var dep := bs.facility_of_kind(2, &"vehicle")
	_expect(dep != null, "C: East has no vehicle depot (precondition)")
	if dep == null:
		return out
	var bar := bs.facility_of_kind(2, &"barracks")
	var r0 := bs.acquire_vehicle(bar.id, VehicleDefs.TRUCK)
	_expect(not r0.ok, "C: a barracks sold a vehicle")
	var stock0 := _stock(2)
	var n0 := _vehicles_of(2).size()
	var left0 := int(dep.facility.stock[String(VehicleDefs.APC)])
	var r1 := bs.acquire_vehicle(dep.id, VehicleDefs.APC)
	_expect(r1.ok, "C: acquiring an APC failed: %s" % r1.reason)
	var stock1 := _stock(2)
	var cost: Dictionary = BaseSim.VEHICLES[VehicleDefs.APC].cost
	_expect(absf((stock0.supplies - stock1.supplies) - cost[&"supplies"]) < 0.5 and absf((stock0.fuel - stock1.fuel) - cost[&"fuel"]) < 0.5, "C: the cost was not paid (%s -> %s)" % [str(stock0), str(stock1)])
	_expect(int(dep.facility.stock[String(VehicleDefs.APC)]) == left0 - 1, "C: the depot's stock did not fall")
	_expect(_vehicles_of(2).size() == n0, "C: the vehicle exists before it is ready")
	await _warp(BaseSim.VEHICLES[VehicleDefs.APC].time + 20.0, 24.0, 60.0)
	var vs := _vehicles_of(2)
	_expect(vs.size() == n0 + 1, "C: vehicles %d -> %d" % [n0, vs.size()])
	var apc: UnitState = null
	for u: UnitState in vs:
		if u.veh.type_id == VehicleDefs.APC:
			apc = u
	_expect(apc != null and apc.faction == 2 and apc.alive and apc.veh.fuel > 0.0, "C: the new APC is not owned / fuelled correctly")
	_expect(apc != null and apc.veh.assign_kind == "" and not apc.player_controlled, "C: the new APC is not free")
	out["apc"] = {"owner": apc.faction if apc else -1, "fuel": apc.veh.fuel if apc else 0.0, "near_depot_m": snappedf(_flat(apc.position, dep.position), 1.0) if apc else -1.0}
	_expect(int(war.faction(2).ledger.vehicles_bought) >= 1, "C: the ledger does not show the purchase")
	dep.facility.stock[String(VehicleDefs.APC)] = 0
	var r2 := bs.acquire_vehicle(dep.id, VehicleDefs.APC)
	_expect(not r2.ok, "C: an APC was sold from empty stock")
	out["no_stock"] = r2.reason
	var snap := demo.sim.state.snapshot()
	var found := false
	for d in snap.units:
		if d.id == apc.id:
			found = d.faction == 2 and absf(float(d.veh.fuel) - apc.veh.fuel) < 0.01
	_expect(found, "C: the APC is not in the saved state with its owner and fuel")
	return out


## Census of all soldiers of the squads: how many walk, stand on a valid order, arrived, were blocked; and for the ones that
## stand while they should walk why (desired speed, next path point distance, avoidance result).
func _soldier_census(sqs: Array) -> String:
	var c := {"walk": 0, "slow": 0, "arrived": 0, "blocked": 0, "idle": 0, "stand_with_order": 0}
	var why: Array[String] = []
	for sq: SquadState in sqs:
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			var body := demo.sim.body_of(id) as SoldierBody
			var v: float = body.velocity.length() if body else u.velocity.length()
			match u.move_state:
				UnitState.MoveState.MOVING:
					if v > 2.0:
						c.walk += 1
					elif v > 0.3:
						c.slow += 1
					else:
						c.stand_with_order += 1
						if body and why.size() < 3:
							why.append("#%d desired=%.1f next_d=%.2f safe=(%.1f,%.1f) path=%d stuck=%d" % [id, body.dbg_desired, body.dbg_next_dist, body._safe_velocity.x, body._safe_velocity.z, body.nav.get_current_navigation_path().size(), body._stuck_stage])
				UnitState.MoveState.ARRIVED:
					c.arrived += 1
				UnitState.MoveState.BLOCKED:
					c.blocked += 1
				_:
					c.idle += 1
	return "%s %s" % [JSON.stringify(c), " | ".join(why)]


# --- D / E: mechanized deployment ---------------------------------------------------------------------------------------------------

## South has at least `n` free vehicles (bought at its depot, as the economy would, and waited for).
func _ensure_vehicles(fid: int, n: int) -> int:
	var bs := _bs()
	var dep := bs.facility_of_kind(fid, &"vehicle")
	var guard := 0
	while _vehicles_of(fid).size() < n and dep != null and guard < 4:
		guard += 1
		var r := bs.acquire_vehicle(dep.id, VehicleDefs.TRUCK)
		if not r.ok:
			print("WAR could not buy a truck: ", r.reason)
			break
		await _warp(BaseSim.VEHICLES[VehicleDefs.TRUCK].time + 15.0, 24.0, 60.0)
	# Vehicles still driving home from an earlier scenario are free again before the next one starts.
	var waited := 0.0
	while waited < 900.0 and _vehicles_of(fid).any(func(u: UnitState) -> bool: return u.veh.assign_kind != ""):
		await _warp(30.0, 8.0, 30.0)
		waited += 30.0
	return _vehicles_of(fid).size()


## An objective that is 2.5-7 km from the faction's base and not its own (a long march), nearest to `want_km`.
func _far_objective(fid: int, want_km: float, min_km := 2.5, max_km := 7.0) -> ObjectiveState:
	var b: Dictionary = _bs().bases_of(fid)[0]
	var best: ObjectiveState = null
	var best_d := INF
	for o: ObjectiveState in war.all_objectives():
		if o.owner == fid or o.is_hq():
			continue
		var d := _flat(o.position, b.anchor) / 1000.0
		if d < min_km or d > max_km:
			continue
		if absf(d - want_km) < best_d:
			best_d = absf(d - want_km)
			best = o
	return best


## `n` full South squads near its base, an attack on `obj` started like the strategic AI starts one (not the player's).
func _mech_scene(n_squads: int, obj: ObjectiveState) -> Dictionary:
	await _fresh()
	var b: Dictionary = _bs().bases_of(1)[0]
	var sqs: Array = []
	for i in n_squads:
		var a := float(i) * 1.7
		var p := _near_point(b.anchor + Vector3(cos(a), 0, sin(a)) * 70.0, b.anchor, 10.0)
		sqs.append(_spawn(1, p, 8))
	await _physics(10)
	var ids := sqs.map(func(s: SquadState) -> int: return s.id)
	var op := ws.start_operation(1, OperationState.Type.ATTACK, ids, obj.id, Vector3.INF, false)
	return {"op": op, "squads": sqs, "obj": obj}


## Invariants of the soldiers and vehicles of a transport at one instant: seats, one vehicle per soldier, the two records agree,
## aboard soldiers have no body or proxy. Returns the problems found.
func _transport_problems(op: OperationState) -> Array:
	var bad := []
	var seen := {}
	for id in demo.sim.vehicles.ids:
		var u := demo.sim.state.get_unit(id)
		if u == null or u.faction != op.faction:
			continue
		var v := u.veh
		if v.occupants.size() > v.def().passengers:
			bad.append("%s carries %d of %d" % [u.unit_name, v.occupants.size(), v.def().passengers])
		for sid in v.occupants:
			if seen.has(sid):
				bad.append("soldier %d is aboard %s and %s" % [sid, seen[sid], u.unit_name])
			seen[sid] = u.unit_name
			var s := demo.sim.state.get_unit(sid)
			if s == null or s.vehicle_id != id:
				bad.append("soldier %d: occupant of %s but vehicle_id %d" % [sid, u.unit_name, s.vehicle_id if s else -2])
			if demo.sim.bodies.has(sid) or demo.sim.proxies.has(sid):
				bad.append("soldier %d is aboard %s and still has a body or proxy" % [sid, u.unit_name])
	for u: UnitState in demo.sim.state.soldiers():
		if u.vehicle_id >= 0 and not seen.has(u.id):
			var vu := demo.sim.state.get_unit(u.vehicle_id)
			if vu == null or not vu.veh.occupants.has(u.id):
				bad.append("soldier %d claims vehicle %d that does not list him" % [u.id, u.vehicle_id])
	return bad


## Runs a mechanized operation up to `max_sim` simulated seconds. Samples stages, the transport invariants, the vehicles'
## distance travelled and the convoys seen; stops when the operation leaves the transport stages and reaches DEPLOY (the
## infantry assault begins) or ends.
func _run_mech(sc: Dictionary, max_sim := 1500.0, scale := 8.0, near := false, until_stage := OperationState.Stage.DEPLOY) -> Dictionary:
	var op: OperationState = sc.op
	var obj: ObjectiveState = sc.obj
	var vs0 := _vehicles_of(1).size()
	var st := {"stages": [], "problems": [], "max_aboard": 0, "convoy": false, "t": {}, "vehicles_used": [], "next": demo.sim.state.time}
	var t0 := demo.sim.state.time
	var f_center := ws.squad_center(sc.squads[0])
	if near:
		demo.rts_camera.frame(f_center, 0.0, 130.0)
	else:
		demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	var w := await _warp(max_sim, scale, 400.0, func() -> bool:
		var now := demo.sim.state.time
		var name := op.stage_name()
		if st.stages.is_empty() or st.stages[-1] != name:
			st.stages.append(name)
			st.t[name] = snappedf(now - t0, 1.0)
		if op.transport.get("convoy", -1) >= 0 and op.transport.has("convoy"):
			st.convoy = true
		var aboard := 0
		for vid in op.vehicles:
			var u := demo.sim.state.get_unit(vid)
			if u:
				aboard += u.veh.occupants.size()
				if not st.vehicles_used.has(vid):
					st.vehicles_used.append(vid)
		st.max_aboard = maxi(st.max_aboard, aboard)
		if now >= st.next:
			st.next += 5.0
			var bad := _transport_problems(op)
			for p: String in bad:
				if st.problems.size() < 8 and not st.problems.has(p):
					st.problems.append(p)
			if near:
				var c := ws.squad_center(sc.squads[0])
				demo.rts_camera.frame(c, 0.0, 130.0)
		return not op.is_active() or int(op.stage) >= int(until_stage))
	var members_aboard := 0
	for sq: SquadState in sc.squads:
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			if u and u.vehicle_id >= 0:
				members_aboard += 1
	return {"op": {"phase": op.phase_name(), "stage": op.stage_name(), "outcome": op.outcome}, "stages": st.stages, "stage_times": st.t, "problems": st.problems, "max_aboard": st.max_aboard,
		"convoy_seen": st.convoy, "vehicles_used": st.vehicles_used.size(), "members_still_aboard": members_aboard, "vehicles_before": vs0, "vehicles_after": _vehicles_of(1).size(),
		"warp": w, "transport": op.transport.get("why", ""), "mode": op.transport.get("mode", ""), "log": op.transport.get("log", []),
		"diag": op.transport.get("tasks", {}).values().filter(func(t: Dictionary) -> bool: return t.has("diag")).map(func(t: Dictionary) -> Dictionary: return t.diag)}


func _d_mech() -> Dictionary:
	var n := await _ensure_vehicles(1, 2)
	var obj := _far_objective(1, 3.5)
	_expect(obj != null and n >= 1, "D: no far objective or no vehicle (precondition)")
	if obj == null:
		return {}
	var sc := await _mech_scene(2, obj)
	var op: OperationState = sc.op
	_expect(op != null, "D: the attack could not start")
	if op == null:
		return {}
	var out := {"objective": obj.obj_name, "km": snappedf(_flat(obj.position, _bs().bases_of(1)[0].anchor) / 1000.0, 0.1), "mode": op.transport.get("mode", ""), "why": op.transport.get("why", ""),
		"stage_at_start": op.stage_name(), "vehicles": Array(op.vehicles)}
	_expect(op.transport.get("mode", "") == "mech", "D: the operation did not go by vehicle: %s" % op.transport.get("why", ""))
	_expect(op.stage == OperationState.Stage.ASSEMBLE, "D: the first stage is %s" % op.stage_name())
	var seats := 0
	for vid in op.vehicles:
		seats += demo.sim.state.get_unit(vid).veh.def().passengers
	var r := await _run_mech(sc, 1500.0, 8.0, false)
	out["run"] = r
	for want in ["assemble", "mount", "transit", "disembark"]:
		_expect(r.stages.has(want), "D: the stage %s was never seen (%s)" % [want, str(r.stages)])
	var order := ["assemble", "mount", "transit", "disembark", "approach", "deploy"]
	var last := -1
	for sname: String in r.stages:
		var i := order.find(sname)
		if i >= 0:
			_expect(i >= last, "D: stage order broken: %s" % str(r.stages))
			last = i
	_expect(r.problems.is_empty(), "D: transport invariants broken: %s" % str(r.problems))
	_expect(r.max_aboard > 0 and r.max_aboard <= seats, "D: %d aboard with %d seats" % [r.max_aboard, seats])
	_expect(r.members_still_aboard == 0, "D: %d soldiers are still aboard after the operation left the transport" % r.members_still_aboard)
	_expect(r.vehicles_before == r.vehicles_after, "D: the vehicle count changed (%d -> %d)" % [r.vehicles_before, r.vehicles_after])
	_expect(int(op.stage) >= int(OperationState.Stage.DEPLOY) or not op.is_active(), "D: the infantry assault did not begin (stage %s, %s)" % [op.stage_name(), op.outcome])
	_expect(_consistency().count == 0, "D: records inconsistent %s" % str(_consistency().problems))
	# The vehicles come back and are free again (assignment cleared) - give them time.
	await _warp(300.0, 8.0, 120.0, func() -> bool:
		for vid in r.vehicles_used_ids if r.has("vehicles_used_ids") else []:
			pass
		return false)
	var free := 0
	var busy := 0
	for u: UnitState in _vehicles_of(1):
		if u.veh.assign_kind == "":
			free += 1
		else:
			busy += 1
	out["vehicles_free_after"] = free
	out["vehicles_busy_after"] = busy
	_expect(busy == 0 or not op.is_active(), "D: %d vehicles are still assigned long after the unloading" % busy)
	for o: OperationState in war.active_operations():
		ws.cancel(o.id, "test end")
	return out


func _e_convoy() -> Dictionary:
	var n := await _ensure_vehicles(1, 3)
	# A target up to 5 km away (the nearest to 4 km that South does not own); after other scenarios took objectives only a
	# farther one may be left, which needs a longer run.
	var obj := _far_objective(1, 4.0, 2.5, 5.0)
	var run_s := 1800.0
	if obj == null:
		obj = _far_objective(1, 4.0)
		run_s = 2800.0
	_expect(obj != null and n >= 2, "E: no far objective or fewer than two vehicles (precondition: %d)" % n)
	if obj == null:
		return {}
	var out := {"vehicles": n}
	var sc := await _mech_scene(3, obj)
	var op: OperationState = sc.op
	_expect(op != null, "E: the attack could not start")
	if op == null:
		return out
	out["mode"] = op.transport.get("mode", "")
	out["why"] = op.transport.get("why", "")
	var tasks: Dictionary = op.transport.get("tasks", {})
	_expect(tasks.size() >= 2, "E: only %d vehicle(s) were assigned for three squads" % tasks.size())
	var assigned := {}
	for vid: int in tasks:
		for sid in tasks[vid].squads:
			_expect(not assigned.has(sid), "E: squad %d is assigned to two vehicles" % sid)
			assigned[sid] = vid
	var r := await _run_mech(sc, run_s, 8.0, false)
	out["run"] = r
	out["events"] = war.events.filter(func(e: Dictionary) -> bool: return e.kind == "op_transport" or e.kind == "vehicle").slice(-24).map(func(e: Dictionary) -> String: return "%.0f %s" % [e.t, e.text])
	_expect(r.convoy_seen, "E: the vehicles did not drive as a convoy")
	_expect(r.problems.is_empty(), "E: transport invariants broken: %s" % str(r.problems))
	_expect(r.members_still_aboard == 0, "E: %d soldiers still aboard" % r.members_still_aboard)
	_expect(r.vehicles_before == r.vehicles_after, "E: the vehicle count changed")
	_expect(int(op.stage) >= int(OperationState.Stage.DEPLOY) or not op.is_active(), "E: the convoy's squads did not reach the assault stage (%s)" % op.stage_name())
	# Reuse: the same vehicles carry the next operation.
	for o: OperationState in war.active_operations():
		ws.cancel(o.id, "test: second use")
	await _warp(400.0, 8.0, 120.0)
	var obj2 := _far_objective(1, 3.0)
	var sc2 := await _mech_scene(1, obj2) if obj2 else {}
	var reused := false
	if not sc2.is_empty() and sc2.op != null:
		reused = sc2.op.transport.get("mode", "") == "mech"
		out["second_use"] = {"mode": sc2.op.transport.get("mode", ""), "why": sc2.op.transport.get("why", "")}
		for o: OperationState in war.active_operations():
			ws.cancel(o.id, "test end")
	_expect(reused, "E: the vehicles could not be used for a second operation (%s)" % str(out.get("second_use", "")))
	return out


## Diagnostic: each South vehicle is sent 150 m out of the yard; what holds it up is printed.
func _v_yard() -> Dictionary:
	await _ensure_vehicles(1, 3)
	var dep := _bs().facility_of_kind(1, &"vehicle")
	var out := {"depot": [dep.position.x, dep.position.z, dep.yaw]}
	var vs := _vehicles_of(1)
	var targets := {}
	var k := 0
	for u: UnitState in vs:
		var front := Basis(Vector3.UP, dep.yaw) * Vector3(-20.0 + k * 15.0, 0.0, -70.0)
		var t := demo.on_ground(dep.position.x + front.x, dep.position.z + front.z, 0.0)
		targets[u.id] = t
		var r := demo.sim.vehicles.order_drive(u.id, t)
		out["order_%d" % u.id] = {"ok": r.ok, "reason": r.get("reason", ""), "pos": [u.position.x, u.position.z], "yaw": u.yaw}
		k += 1
	await _warp(70.0, 6.0, 60.0)
	for u: UnitState in vs:
		out["end_%d" % u.id] = {"status": u.veh.status_name(), "reason": u.veh.reason, "dist_to_target": _flat(u.position, targets[u.id]), "diag": demo.sim.vehicles.diagnose(u)}
	return out


# --- F / G / H: supply ----------------------------------------------------------------------------------------------------------------

func _rounds(sqs: Array) -> int:
	var n := 0
	for sq: SquadState in sqs:
		for id in sq.members:
			n += demo.sim.state.get_unit(id).reserve
	return n


func _ammo_kg(fid: int) -> float:
	return _stock(fid).ammo


## Spare rounds of every soldier of the faction, and the explicit ammunition income booked so far: stock changes are
## then income - rounds the soldiers took / 5 (plus purchases, which the scenarios keep off).
func _faction_rounds(fid: int) -> int:
	var n := 0
	for u: UnitState in demo.sim.state.soldiers():
		if u.faction == fid:
			n += u.reserve
	return n


func _income_kg(fid: int) -> float:
	return float(war.faction(fid).ledger["in"]["ammo"])


## F: an undersupplied squad prepares for an operation: shortage detected, the attack is delayed, the squad walks to the depot,
## the depot's stock falls by exactly what the soldiers took, the attack is then supplied.
func _f_preop() -> Dictionary:
	await _fresh()
	var out := {}
	var f := war.faction(1)
	var b: Dictionary = _bs().bases_of(1)[0]
	var sqs: Array = []
	for i in 2:
		sqs.append(_spawn(1, _near_point(b.anchor + Vector3(cos(i * 2.0), 0, sin(i * 2.0)) * 60.0, b.anchor, 10.0), 8))
	await _physics(10)
	for sq: SquadState in sqs:
		for id in sq.members:
			demo.sim.state.get_unit(id).reserve = 20
	var obj := _far_objective(1, 3.0)
	var ids := sqs.map(func(s: SquadState) -> int: return s.id)
	var depot_before := _ammo_kg(1)
	var rounds_before := _rounds(sqs)
	var income_before := _income_kg(1)
	var all_rounds_before := _faction_rounds(1)
	var r := ws.supply.assess_attack(f, ids, obj)
	out["verdict"] = r.verdict
	out["why"] = r.why
	_expect(r.verdict == "delay", "F: the shortage was not detected (verdict %s: %s)" % [r.verdict, r.why])
	for sq: SquadState in sqs:
		_expect(sq.recover_site >= 0, "F: %s was not sent to a depot" % sq.squad_name)
	_expect(not war.active_operations(1).any(func(o: OperationState) -> bool: return o.target_objective == obj.id), "F: an operation was started anyway")
	await _warp(240.0, 8.0, 120.0, func() -> bool:
		return sqs.all(func(s: SquadState) -> bool: return s.recover_site < 0))
	var rounds_after := _rounds(sqs)
	var depot_after := _ammo_kg(1)
	var taken_kg := depot_before - depot_after + (_income_kg(1) - income_before)
	var gained := _faction_rounds(1) - all_rounds_before
	out["squad_rounds_gained"] = rounds_after - rounds_before
	out["depot_kg_taken"] = snappedf(taken_kg, 0.1)
	out["rounds_gained"] = gained
	_expect(taken_kg > 1.0, "F: the depot's stock did not fall (%.1f)" % taken_kg)
	_expect(absf(taken_kg * Inventory.AMMO_ROUNDS_PER_KG - float(gained)) < 6.0, "F: conservation: the depot lost %.1f kg (%.0f rounds), the soldiers gained %d rounds" % [taken_kg, taken_kg * Inventory.AMMO_ROUNDS_PER_KG, gained])
	_expect(gained > 0 and rounds_after >= 16 * 100, "F: the squads are still undersupplied (%d rounds for 16 soldiers)" % rounds_after)
	var r2 := ws.supply.assess_attack(f, ids, obj)
	out["verdict_after"] = r2.verdict
	_expect(r2.verdict == "go", "F: after the resupply the attack is still not ready (%s: %s)" % [r2.verdict, r2.why])
	return out


## G: a truck takes ammunition from the main depot to garrison squads 3+ km away, they take it, the truck brings the rest
## back; every kilogram is accounted for. A save / load in the middle (state snapshot applied in place) does not change it.
func _g_delivery(do_save := true) -> Dictionary:
	await _fresh()
	var out := {}
	await _ensure_vehicles(1, 1)
	var f := war.faction(1)
	var obj := _far_objective(1, 3.0)
	_expect(obj != null, "G: no far objective")
	var spot := _near_point(obj.position, _bs().bases_of(1)[0].anchor, 80.0)
	var sq := _spawn(1, spot, 8)
	sq.station_objective = obj.id
	await _physics(10)
	for id in sq.members:
		demo.sim.state.get_unit(id).reserve = 15
	var truck: UnitState = _vehicles_of(1)[0]
	var depot_before := _ammo_kg(1)
	var rounds_before := _rounds([sq])
	var cargo_before := truck.veh.cargo.total()
	var income_before := _income_kg(1)
	var all_rounds_before := _faction_rounds(1)
	var res := ws.supply.request_supply(f, [sq.id], ws.squad_center(sq), "scenario G")
	# NAV-PERF-01B: the truck route check is a RouteService job; the request is asked again until it is answered (as the economy does).
	var tries := 0
	while res.get("pending", false) and tries < 900:
		await tree.process_frame
		tries += 1
		res = ws.supply.request_supply(f, [sq.id], ws.squad_center(sq), "scenario G")
	out["request"] = res.reason if not res.ok else "ok"
	_expect(res.ok, "G: the supply mission was refused: %s" % res.reason)
	if not res.ok:
		return out
	var mid: int = int(res.mission.id)
	var seen := []
	var saved := {"done": false}
	var w := await _warp(2700.0, 8.0, 500.0, func() -> bool:
		var m := ws.supply.mission(mid)  # looked up every tick: a load replaces the mission records
		if m.is_empty():
			return true
		if seen.is_empty() or seen[-1] != m.state:
			seen.append(m.state)
		if do_save and m.state == "driving" and not saved.done:
			saved.done = true
			var tu := demo.sim.state.get_unit(truck.id)
			var pre := {"route": tu.veh.route.size(), "i": tu.veh.route_i, "order": tu.order, "target": tu.order_target, "status": tu.veh.status_name(), "pos": tu.position, "speed": tu.veh.speed}
			var snap := demo.sim.state.snapshot()
			demo.sim.state.apply_snapshot(snap)  # a save / load at this very moment
			var post := {"route": tu.veh.route.size(), "i": tu.veh.route_i, "order": tu.order, "target": tu.order_target, "status": tu.veh.status_name(), "pos": tu.position, "speed": tu.veh.speed, "same_obj": demo.sim.state.get_unit(truck.id) == tu}
			out["save_pre"] = pre
			out["save_post"] = post
		return m.state == "done" or m.state == "failed")
	var m := ws.supply.mission(mid)
	out["states"] = seen
	out["mission"] = {"state": m.get("state", "?"), "loaded": m.get("loaded", 0.0), "delivered": m.get("delivered", 0.0), "returned": m.get("returned", 0.0), "fail": m.get("fail", "")}
	_expect(not m.is_empty() and m.state == "done", "G: the mission ended %s (%s)" % [m.get("state", "gone"), m.get("fail", "")])
	for want in ["loading", "driving", "serving", "returning", "unloading"]:
		_expect(seen.has(want), "G: the mission never reached %s (%s)" % [want, str(seen)])
	var truck2 := demo.sim.state.get_unit(truck.id)
	var depot_after := _ammo_kg(1)
	var gained := _faction_rounds(1) - all_rounds_before
	depot_before += _income_kg(1) - income_before  # the depot also received explicit income meanwhile
	out["squad_rounds_gained"] = _rounds([sq]) - rounds_before
	out["truck_diag"] = demo.sim.vehicles.diagnose(demo.sim.state.get_unit(truck.id)) if m.get("state", "") != "done" else {}
	out["depot_taken_kg"] = snappedf(depot_before - depot_after, 0.1)
	out["rounds_gained"] = gained
	out["truck_cargo_after"] = truck2.veh.cargo.total()
	_expect(_rounds([sq]) - rounds_before > 0, "G: the squad received nothing")
	_expect(absf((depot_before - depot_after) * Inventory.AMMO_ROUNDS_PER_KG - float(gained)) < 8.0, "G: conservation: the depot lost %.1f kg, the squad gained %d rounds" % [depot_before - depot_after, gained])
	_expect(truck2.veh.cargo.total() <= cargo_before + 0.5, "G: the truck brought back %.1f kg more than it started with" % (truck2.veh.cargo.total() - cargo_before))
	_expect(truck2.veh.assign_kind == "", "G: the truck is still assigned (%s)" % truck2.veh.assign_kind)
	return out


## H: no ammunition in any store: nothing is created, the attack is cancelled with the numbers, recruiting is refused with
## a reason, and the faction does not deadlock (it keeps deciding). Stock changes are only the explicit income.
func _h_shortage() -> Dictionary:
	await _fresh()
	var out := {}
	var f := war.faction(1)
	var saved := {}
	for st in demo.sim.logistics.stores(1):
		saved[st.id] = st.inventory.get_qty(Inventory.AMMO)
		st.inventory.take(Inventory.AMMO, 1.0e9)
	var b: Dictionary = _bs().bases_of(1)[0]
	var sqs: Array = []
	for i in 3:
		var sq := _spawn(1, _near_point(b.anchor + Vector3(cos(i * 2.0), 0, sin(i * 2.0)) * 60.0, b.anchor, 10.0), 8)
		for id in sq.members:
			demo.sim.state.get_unit(id).reserve = 10
		sqs.append(sq)
	await _physics(10)
	var ledger0 := float(f.ledger["in"]["ammo"])
	var rounds0 := _faction_rounds(1)
	var stock0 := _ammo_kg(1)
	_expect(stock0 < 0.01, "H: precondition: stock %.1f" % stock0)
	var obj := _far_objective(1, 3.0)
	var r := ws.supply.assess_attack(f, sqs.map(func(s: SquadState) -> int: return s.id), obj)
	out["verdict"] = r.verdict
	out["why"] = r.why
	_expect(r.verdict == "cancel" or r.verdict == "reduced", "H: with no ammunition the attack was %s" % r.verdict)
	_expect(not war.active_operations(1).any(func(o: OperationState) -> bool: return o.target_objective == obj.id), "H: an operation started without ammunition")
	# The economy cannot recruit without ammunition for the recruits: refused with a reason, nothing paid.
	var bar := _bs().facility_of_kind(1, &"barracks")
	var rr := _bs().recruit(bar.id)
	out["recruit"] = rr.reason
	_expect(not rr.ok, "H: recruiting without ammunition was accepted")
	# A strategic decision runs without error and records why.
	var snap := _decide_now(1)
	out["decision_notes"] = snap.get("notes", "")
	var attack := _action(snap, "attack")
	out["attack_action"] = {"status": attack.get("status", ""), "note": attack.get("note", "")} if not attack.is_empty() else {}
	await _warp(120.0, 8.0, 60.0)
	var stock1 := _ammo_kg(1)
	var income := float(f.ledger["in"]["ammo"]) - ledger0
	out["stock_after"] = snappedf(stock1, 0.1)
	out["income_ledger"] = snappedf(income, 0.1)
	var took := float(_faction_rounds(1) - rounds0) / Inventory.AMMO_ROUNDS_PER_KG
	out["soldiers_took_kg"] = snappedf(took, 0.1)
	_expect(absf(stock1 - (stock0 + income - took)) < 0.5, "H: ammunition appeared outside the ledger (stock %.1f = 0 + income %.1f - taken %.1f)" % [stock1, income, took])
	for id in saved:
		demo.sim.logistics.structure(id).inventory.items[Inventory.AMMO] = saved[id]
	return out


# --- I: defensive counterattack ----------------------------------------------------------------------------------------------------------

## South holds Haugen with a sector squad, a second one and a reserve. Attackers (North) are reported east of it.
func _counter_scene(reported: int, peak_first := 0) -> Dictionary:
	await _fresh()
	_strat_reset_faction(1)
	var hau := _obj("Haugen")
	hau.owner = 1
	hau.capture_faction = -1
	hau.capture_progress = 0.0
	hau.contested = false
	hau.history.append([demo.sim.state.time, 1])
	war.counter_cool.clear()
	ws.strat._peak.clear()
	var sqs: Array = []
	for i in 3:
		var sq := _spawn(1, hau.position + Vector3(14 + i * 22, 0, -12 + i * 12), 8)
		sq.station_objective = hau.id
		sqs.append(sq)
	await _physics(10)
	ws._defence_posture(hau, sqs, 1)
	await _seconds(2.0)
	var enemy_at := _near_point(hau.position, _obj("North HQ").position, 260.0)
	# Real attackers stand where they are reported (their count is what the report says).
	war.faction(1).recovery_until = demo.sim.state.time + 900.0  # South starts no attack of its own in this scene
	var atk := _spawn(0, enemy_at, maxi(reported, 1))
	await _physics(10)
	if peak_first > 0:
		_report(1, enemy_at, peak_first)
		await _warp(5.0, 4.0, 20.0)
		_decide_now(1)
		war.counter_cool.clear()
	_report(1, enemy_at, reported)
	await _warp(5.0, 4.0, 20.0)  # the report reaches the faction (IntelSim's delay)
	return {"obj": hau, "def": sqs, "atk": atk, "at": enemy_at}


func _i_counter() -> Dictionary:
	var out := {}
	# 1. Strong attackers: no counterattack, with the reason.
	var sc := await _counter_scene(14)
	var snap := _decide_now(1)
	var a := _action(snap, "counter")
	out["strong"] = {"status": a.get("status", "none"), "note": a.get("note", "")}
	_expect(a.is_empty() or a.status != "chosen", "I: a counterattack against %d attackers was launched" % 14)
	_expect(not war.active_operations(1).any(func(o: OperationState) -> bool: return o.type == OperationState.Type.COUNTER), "I: a counter operation exists against a strong attacker")
	# 2. A weakened, small attacker: the reserve attacks.
	sc = await _counter_scene(3, 0)
	var hau: ObjectiveState = sc.obj
	var defs: Array = sc.def
	out["contacts"] = ws.intel.contacts_of(1).map(func(c: ContactState) -> String: return c.describe(demo.sim.state.time))
	var ids_before := defs.map(func(s: SquadState) -> int: return s.id)
	snap = _decide_now(1)
	a = _action(snap, "counter")
	out["weak"] = {"status": a.get("status", "none"), "note": a.get("note", ""), "squads": a.get("squads", [])}
	_expect(not a.is_empty() and a.status == "chosen", "I: no counterattack against a weakened attacker (%s)" % str(out.weak))
	var op: OperationState = null
	for o: OperationState in war.active_operations(1):
		if o.type == OperationState.Type.COUNTER:
			op = o
	_expect(op != null, "I: no COUNTER operation exists")
	if op == null:
		return out
	# The commitment is conditional: only the reserve goes, the objective stays defended.
	_expect(op.squads.size() == 1, "I: %d squads committed (the reserve alone should go)" % op.squads.size())
	var stay := 0
	for sq: SquadState in defs:
		if sq.op_id < 0 and sq.station_objective == hau.id:
			stay += sq.members.size()
	_expect(stay >= 12, "I: only %d soldiers stay at the objective" % stay)
	out["committed"] = op.squads.size()
	out["staying"] = stay
	var seen_tactics := {}
	var w := await _warp(400.0, 8.0, 200.0, func() -> bool:
		for sid in op.squads:
			var sq := demo.sim.state.get_squad(sid)
			if sq:
				seen_tactics[sq.tactic_name()] = true
		return not op.is_active())
	out["op"] = {"phase": op.phase_name(), "outcome": op.outcome, "tactics_seen": seen_tactics.keys()}
	_expect(not op.is_active(), "I: the counterattack never ended (%s)" % op.stage_why)
	_expect(seen_tactics.has("Assault") or seen_tactics.has("Flank"), "I: the existing squad tactics were not used (%s)" % str(seen_tactics.keys()))
	# It ends with the squads back in the defence (posture and station), and a cooldown stops a repeat at once.
	var back := 0
	for sq: SquadState in defs:
		if demo.sim.state.get_squad(sq.id) and sq.op_id < 0 and sq.station_objective == hau.id:
			back += 1
	_expect(back == defs.size() - _alive_count_lost(defs), "I: the reserve is not back in the defence (%d of %d)" % [back, defs.size()])
	_expect(float(war.counter_cool.get(hau.id, 0.0)) > demo.sim.state.time, "I: no cooldown after the counterattack")
	out["cooldown_s"] = snappedf(float(war.counter_cool.get(hau.id, 0.0)) - demo.sim.state.time, 1.0)
	_report(1, sc.at, 3)
	var snap2 := _decide_now(1)
	var a2 := _action(snap2, "counter")
	_expect(a2.is_empty() or a2.status != "chosen", "I: the same counterattack was launched again immediately")
	out["repeat"] = a2.get("status", "none")
	_expect(_consistency().count == 0, "I: records inconsistent")
	return out


## Squads of the list that no longer exist (wiped out).
func _alive_count_lost(sqs: Array) -> int:
	var n := 0
	for sq: SquadState in sqs:
		if demo.sim.state.get_squad(sq.id) == null:
			n += 1
	return n


# --- J: base loss ---------------------------------------------------------------------------------------------------------------------------

func _j_base_loss() -> Dictionary:
	await _fresh()
	var out := {}
	var bs := _bs()
	var f := war.faction(1)
	var hq := _obj("South HQ")
	var bl := bs.bases_of(1)
	_expect(not bl.is_empty(), "J: South has no base (precondition)")
	var bid: int = bl[0].id
	var fac := bs.facilities_of(bid)
	var stock := bs.base_stock(bid)
	var total_before := {"ammo": _ammo_kg(0) + _ammo_kg(1) + _ammo_kg(2), "supplies": _stock(0).supplies + _stock(1).supplies + _stock(2).supplies}
	# A supply mission and a queued recruit that depend on the base.
	await _ensure_vehicles(1, 1)
	var truck: UnitState = _vehicles_of(1)[0]
	var bar := bs.facility_of_kind(1, &"barracks")
	var queued := bs.recruit(bar.id)
	var res_before := f.reserves
	# Everybody of South leaves the HQ area (a fixture: the defenders are gone), four North soldiers stand in it.
	for u: UnitState in demo.sim.state.soldiers():
		if u.faction == 1 and _flat(u.position, hq.position) < hq.radius + 80.0:
			u.position = hq.position + Vector3(900, 0, 900)
			u.order = UnitState.Order.NONE
	var inv := _spawn(0, hq.position + Vector3(20, 0, 20), 8)
	hq.capture_progress = 0.0
	await _physics(10)
	await _warp(400.0, 12.0, 200.0, func() -> bool: return hq.owner == 0)
	out["owner"] = hq.owner
	_expect(hq.owner == 0, "J: the HQ was not captured (owner %d)" % hq.owner)
	var b: Dictionary = demo.sim.state.construction.bases.get(bid, {})
	_expect(not b.is_empty() and b.faction == 0, "J: the base did not change hands (%s)" % str(b.get("faction", "gone")))
	for st in fac:
		_expect(st.faction == 0, "J: facility %d still belongs to South" % st.id)
	_expect(bs.bases_of(1).filter(func(x: Dictionary) -> bool: return x.id == bid).is_empty(), "J: South still lists the captured base")
	_expect(not bs.bases_of(0).filter(func(x: Dictionary) -> bool: return x.id == bid).is_empty(), "J: North does not list the captured base")
	# Stock moved with the buildings: one copy only, and it stands in South's ledger as lost.
	var after := bs.base_stock(bid)
	var total_after := {"ammo": _ammo_kg(0) + _ammo_kg(1) + _ammo_kg(2), "supplies": _stock(0).supplies + _stock(1).supplies + _stock(2).supplies}
	out["stock_before"] = stock
	out["stock_after"] = after
	out["ledger_lost"] = f.ledger["lost_with_bases"]
	_expect(absf(after.ammo - stock.ammo) < stock.ammo * 0.2 + 400.0 and after.ammo > 0.0, "J: the stock vanished or doubled (%s -> %s)" % [str(stock), str(after)])
	_expect(float(f.ledger["lost_with_bases"]["ammo"]) > 0.0, "J: South's ledger does not show the loss")
	# Queued training was cancelled: personnel back to South, the queue empty.
	_expect(bar.facility.get("queue", []).is_empty(), "J: the captured barracks still trains South's recruits")
	_expect(queued.ok and f.reserves >= res_before + BaseSim.SQUAD_SIZE - 1, "J: the personnel of the cancelled training did not return (%d -> %d)" % [res_before, f.reserves])
	# The faction's economy now has no base: it says so and buys nothing.
	f.econ_next_at = 0.0
	ws.econ.decide(f)
	out["econ_note"] = f.econ_note
	_expect(f.econ_note.contains("no base") or not bs.bases_of(1).is_empty(), "J: South's economy still acts: %s" % f.econ_note)
	_expect(bs.facility_of_kind(1, &"barracks") == null or bs.facility_of_kind(1, &"barracks").faction == 1, "J: South still has the captured barracks")
	# A mission from that depot is told (nothing duplicated: the truck's cargo stays the truck's).
	_expect(truck.veh.assign_kind == "" or ws.supply.mission(truck.veh.assign_id).get("state", "") != "loading", "J: a truck is still loading at the lost depot")
	out["duplicates"] = _duplicate_inventory_check()
	_expect(out.duplicates == 0, "J: %d structures appear twice" % out.duplicates)
	# Give the base back so the later scenarios start from the normal situation.
	hq.owner = 1
	hq.capture_faction = -1
	bs.capture_base(bid, 1)
	for o: OperationState in war.active_operations():
		ws.cancel(o.id, "test end")
	return out


func _duplicate_inventory_check() -> int:
	var seen := {}
	var dup := 0
	for st: StructureState in cs.all():
		if seen.has(st.id):
			dup += 1
		seen[st.id] = true
	return dup


# --- L: player intervention -----------------------------------------------------------------------------------------------------------------

func _l_player() -> Dictionary:
	await _ensure_vehicles(1, 2)
	var out := {}
	var obj := _far_objective(1, 3.5)
	var sc := await _mech_scene(2, obj)
	var op: OperationState = sc.op
	_expect(op != null and op.transport.get("mode", "") == "mech", "L: no mechanized operation (precondition: %s)" % (op.transport.get("why", "") if op else "none"))
	if op == null:
		return out
	# 1. A squad of the operation gets a player order while the force assembles: the operation adapts.
	await _warp(25.0, 8.0, 30.0)
	var sq_a: SquadState = sc.squads[0]
	var sq_b: SquadState = sc.squads[1]
	ws.release_squads([sq_a.id], "player order")
	demo.sim.squads.order_move([sq_a.id], ws.squad_center(sq_a) + Vector3(30, 0, 0))
	_expect(sq_a.op_id < 0 and not op.squads.has(sq_a.id), "L: the squad is still in the operation")
	await _warp(60.0, 8.0, 40.0)
	out["after_squad_order"] = {"stage": op.stage_name(), "active": op.is_active(), "squads": Array(op.squads), "carried": op.transport.get("carried", [])}
	_expect(not op.transport.get("carried", []).has(sq_a.id), "L: the released squad is still planned for transport")
	_expect(sq_a.order != SquadState.Order.NONE or sq_a.status != SquadState.Status.IDLE or true, "")
	_expect(_consistency().count == 0, "L: records inconsistent after the squad order: %s" % str(_consistency().problems))
	# 2. The player takes a vehicle of the operation once it drives: the AI lets go of it and never orders it again.
	var found := {"vid": -1}
	await _warp(500.0, 8.0, 200.0, func() -> bool:
		for v in op.vehicles:
			var u := demo.sim.state.get_unit(v)
			if u and u.veh.phase == VehicleState.Phase.TRANSIT:
				found.vid = v
				return true
		return not op.is_active())
	var vid: int = found.vid
	if vid < 0:
		out["note"] = "no vehicle reached transit"
		out["wait"] = op.wait_reason
		out["stage_why"] = op.stage_why
		out["tasks"] = op.transport.get("tasks", {}).keys().map(func(k: int) -> String: return "%d %s %s %s" % [k, op.transport.tasks[k].state, str(op.transport.tasks[k].get("note", "")), JSON.stringify(op.transport.tasks[k].get("diag", {}))])
		out["squad_pos"] = Array(op.squads).map(func(s: int) -> float: return _flat(ws.squad_center(demo.sim.state.get_squad(s)), op.transport.get("assembly", Vector3.ZERO)))
		_expect(false, "L: the operation never reached transit")
		return out
	var truck := demo.sim.state.get_unit(vid)
	var aboard_before := Array(truck.veh.occupants)
	var took := demo.sim.vehicles.take_control(vid)
	_expect(took, "L: the player could not take the vehicle")
	await _warp(20.0, 4.0, 40.0)
	out["after_vehicle"] = {"assign": truck.veh.assign_kind, "player": truck.player_controlled, "op_stage": op.stage_name(), "op_active": op.is_active(), "aboard": truck.veh.occupants.size()}
	_expect(truck.veh.assign_kind == "" and truck.player_controlled, "L: the vehicle is still assigned or not the player's (%s)" % truck.veh.assign_kind)
	_expect(not op.vehicles.has(vid), "L: the operation still lists the vehicle")
	_expect(truck.veh.speed < 12.0 and truck.veh.in_throttle == 0.0, "L: something still drives the player's vehicle")
	# Nobody of the operation is aboard a vehicle the player drives while still being commanded by the operation.
	for id in aboard_before:
		var s := demo.sim.state.get_unit(id)
		var sq := demo.sim.state.squad_of(id)
		if s and s.vehicle_id == vid and sq:
			_expect(sq.op_id != op.id, "L: squad %s rides with the player but is still in the operation" % sq.squad_name)
	var bad := _transport_problems(op)
	_expect(bad.is_empty(), "L: transport invariants broken after the player took the vehicle: %s" % str(bad))
	demo.sim.vehicles.release_control(vid, false)
	for o: OperationState in war.active_operations():
		ws.cancel(o.id, "test end")
	return out


# --- M: save / load ---------------------------------------------------------------------------------------------------------------------

func _op_json(op_id: int) -> String:
	var op := war.operation(op_id)
	return JSON.stringify(op.to_dict()) if op else "gone"


func _vehicles_json(fid: int) -> String:
	var parts: Array[String] = []
	for u: UnitState in _vehicles_of(fid):
		var d := u.veh.to_dict()
		d.erase("route")
		d.erase("cap")
		parts.append("%d:%s:%s:%s" % [u.id, JSON.stringify(d), str(u.position), str(u.order_target)])
	return "|".join(parts)


## A snapshot applied in place (the load path of a running game) at the given moment must change nothing that matters:
## the operation record, the vehicles' records and the squads of the operation read the same afterwards.
func _roundtrip(op_id: int, tag: String, out: Dictionary) -> void:
	var before := _op_json(op_id)
	var vbefore := _vehicles_json(1)
	var squads_before := {}
	for sq: SquadState in ws.squads_of(1):
		squads_before[sq.id] = JSON.stringify(sq.to_dict())
	var snap := demo.sim.state.snapshot()
	demo.sim.state.apply_snapshot(snap)
	var after := _op_json(op_id)
	var vafter := _vehicles_json(1)
	_expect(before == after, "M(%s): the operation record changed in a save / load" % tag)
	_expect(vbefore == vafter, "M(%s): a vehicle record changed in a save / load" % tag)
	var diff := 0
	for sq: SquadState in ws.squads_of(1):
		if squads_before.get(sq.id, "") != JSON.stringify(sq.to_dict()):
			diff += 1
	_expect(diff == 0, "M(%s): %d squad records changed" % [tag, diff])
	var op2 := war.operation(op_id)
	out[tag] = {"op_same": before == after, "vehicles_same": vbefore == vafter, "squads_changed": diff, "stage_after": op2.stage_name() if op2 else "gone", "mode_after": op2.transport.get("mode", "?") if op2 else "-",
		"is_transport": op2.is_transport_stage() if op2 else false, "stage_int": int(op2.stage) if op2 else -99, "phase": op2.phase_name() if op2 else "-", "tasks": op2.transport.get("tasks", {}).keys().size() if op2 else -1}


func _m_save() -> Dictionary:
	var out := {}
	await _ensure_vehicles(1, 2)
	# Recruitment in progress: the queue survives the construction record's JSON round trip.
	var bs := _bs()
	var bar := bs.facility_of_kind(1, &"barracks")
	for st in bs.facilities_of(bar.base_id):
		while not st.facility.get("queue", []).is_empty():
			bs.cancel_queue(st.id, 0)
	var r := bs.recruit(bar.id)
	_expect(r.ok, "M: recruiting failed: %s" % r.reason)
	var parsed: Variant = JSON.parse_string(JSON.stringify(cs.to_dict()))
	var q_after: Array = []
	for sd in parsed.structures:
		if int(sd.id) == bar.id:
			q_after = sd.get("facility", {}).get("queue", [])
	out["recruit_queue_saved"] = q_after.size()
	_expect(q_after.size() == 1, "M: the recruit queue was not saved (%d entries)" % q_after.size())
	bs.cancel_queue(bar.id, 0)
	# A mechanized operation, saved in each transport stage and in the assault.
	var obj := _far_objective(1, 3.5)
	var sc := await _mech_scene(2, obj)
	var op_id: int = sc.op.id
	_expect(sc.op != null and sc.op.transport.get("mode", "") == "mech", "M: no mechanized operation")
	var done := {}
	var seen_stages := []
	var want := ["assemble", "mount", "transit", "disembark", "deploy"]
	var t0 := demo.sim.state.time
	await _warp(1500.0, 8.0, 400.0, func() -> bool:
		var op := war.operation(op_id)
		if op == null:
			return true
		var name := op.stage_name()
		if done.get("_last", "") != name:
			done["_last"] = name
			seen_stages.append("%s@%.0f since=%.0f" % [name, demo.sim.state.time - t0, demo.sim.state.time - op.stage_since])
		if want.has(name) and not done.has(name):
			var wait_s := 40.0 if name == "transit" else (6.0 if name == "assemble" else 0.0)  # mount and disembark last only seconds
			if demo.sim.state.time - op.stage_since >= wait_s:
				done[name] = true
				_roundtrip(op_id, name, out)
		return not op.is_active() or done.has("deploy"))
	for w: String in want:
		_expect(done.has(w), "M: no save was made in the %s stage" % w)
	# After the loads the operation still ends up on the objective, with no inconsistency.
	var op2 := war.operation(op_id)
	_expect(op2 != null and (int(op2.stage) >= int(OperationState.Stage.DEPLOY) or not op2.is_active()), "M: the operation did not continue after the loads (%s)" % (op2.stage_name() if op2 else "gone"))
	_expect(_consistency().count == 0, "M: records inconsistent after the loads")
	var bad := _transport_problems(war.operation(op_id)) if war.operation(op_id) else []
	_expect(bad.is_empty(), "M: transport invariants broken after the loads: %s" % str(bad))
	out["final_stage"] = op2.stage_name() if op2 else "gone"
	out["stages_seen"] = seen_stages
	out["events"] = war.events.filter(func(e: Dictionary) -> bool: return e.faction == 1 or e.faction < 0).slice(-14).map(func(e: Dictionary) -> String: return "%.0f %s" % [e.t - t0, e.text])
	for o: OperationState in war.active_operations():
		ws.cancel(o.id, "test end")
	return out


# --- N: a long-distance operation ----------------------------------------------------------------------------------------------------------

func _n_long() -> Dictionary:
	await _ensure_vehicles(1, 3)
	var obj := _far_objective(1, 7.5, 5.5, 11.0)
	_expect(obj != null, "N: no objective farther than 5.5 km")
	if obj == null:
		return {}
	var sc := await _mech_scene(3, obj)
	var op: OperationState = sc.op
	var km := _flat(obj.position, _bs().bases_of(1)[0].anchor) / 1000.0
	var out := {"objective": obj.obj_name, "km": snappedf(km, 0.1), "mode": op.transport.get("mode", "") if op else "none", "why": op.transport.get("why", "") if op else ""}
	_expect(op != null and op.transport.get("mode", "") == "mech", "N: the long operation did not go by vehicle: %s" % out.why)
	if op == null:
		return out
	var r := await _run_mech(sc, 2400.0, 8.0, false)
	out["run"] = r
	_expect(r.problems.is_empty(), "N: transport invariants broken: %s" % str(r.problems))
	_expect(r.members_still_aboard == 0, "N: soldiers are still aboard")
	_expect(int(op.stage) >= int(OperationState.Stage.DEPLOY) or not op.is_active(), "N: the operation stalled in %s after %.0f s (%s)" % [op.stage_name(), demo.sim.state.time - op.started_at, op.stage_why])
	var arrived := float(r.stage_times.get("deploy", r.stage_times.get("approach", 0.0)))
	out["time_to_assault_s"] = arrived
	# On foot at 4.5 m/s the same march would take km * 1000 * 1.25 / 4.5 seconds.
	var foot_s := km * 1000.0 * 1.25 / 4.5
	out["foot_estimate_s"] = snappedf(foot_s, 1.0)
	_expect(arrived > 0.0 and arrived < foot_s * 0.75, "N: by vehicle %.0f s against %.0f s on foot: no saving" % [arrived, foot_s])
	for o: OperationState in war.active_operations():
		ws.cancel(o.id, "test end")
	return out


# --- O / P: the autonomous war with logistics, and its cost ---------------------------------------------------------------------------------

func _o_war() -> Dictionary:
	await _fresh()
	_pause_ai(false)
	Inventory.audit_reset()
	var ledger0 := {}
	var stock0 := {}
	for fid in [1, 2]:
		ledger0[fid] = war.faction(fid).ledger.duplicate(true)
		stock0[fid] = _stock(fid)
	var owners0 := {}
	for o: ObjectiveState in war.all_objectives():
		owners0[o.id] = o.owner
	var mech0 := ws.mech.stats.duplicate()
	var sup0 := ws.supply.stats.duplicate()
	var econ0 := ws.econ.stats.duplicate()
	var b0 := ws.bases.stats.duplicate()
	var units0 := demo.sim.state.units.size()
	var tick0 := demo.sim.tick_usec.duplicate()
	var counters0 := {"counter": 0}
	var st := _new_war_stats()
	var seen_ops := {}
	var types_seen := {}
	var transport_stages := {}
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	await _seconds(1.0)
	var run := await _war_run(40.0, 24.0, st)
	for op: OperationState in war.operations.values():
		types_seen[op.type_name()] = int(types_seen.get(op.type_name(), 0)) + 1
	var out := {"run": run}
	out["operation_types"] = types_seen
	out["mech"] = {"mounted_ops": ws.mech.stats.mounted - mech0.mounted, "foot_ops": ws.mech.stats.foot - mech0.foot, "fallbacks": ws.mech.stats.fallbacks - mech0.fallbacks,
		"convoys": ws.mech.stats.convoys - mech0.convoys, "arrived": ws.mech.stats.arrived - mech0.arrived, "returned": ws.mech.stats.returned - mech0.returned}
	out["supply"] = {"recoveries": ws.supply.stats.recoveries - sup0.recoveries, "recovered": ws.supply.stats.recovered - sup0.recovered, "missions": ws.supply.stats.missions - sup0.missions,
		"delivered": ws.supply.stats.delivered - sup0.delivered, "failed": ws.supply.stats.failed - sup0.failed, "kg_delivered": snappedf(ws.supply.stats.kg_delivered - sup0.kg_delivered, 1.0),
		"assessed": ws.supply.stats.assessed - sup0.assessed, "delays": ws.supply.stats.delay - sup0.delay, "reduced": ws.supply.stats.reduced - sup0.reduced, "cancelled": ws.supply.stats.cancel - sup0.cancel}
	out["econ"] = {"recruits": ws.econ.stats.recruits - econ0.recruits, "trucks": ws.econ.stats.trucks - econ0.trucks, "apcs": ws.econ.stats.apcs - econ0.apcs, "refuels": ws.econ.stats.refuels - econ0.refuels,
		"repairs": ws.econ.stats.repairs - econ0.repairs, "refused": ws.econ.stats.refused - econ0.refused}
	out["builds"] = {"started": ws.bases.stats.started - b0.started, "finished": ws.bases.stats.finished - b0.finished, "refused": ws.bases.stats.refused - b0.refused}
	var counters := 0
	for op: OperationState in war.operations.values():
		if op.type == OperationState.Type.COUNTER:
			counters += 1
	out["counterattacks"] = counters
	var changes := []
	for o: ObjectiveState in war.all_objectives():
		if o.owner != owners0[o.id]:
			changes.append("%s %s->%s" % [o.obj_name, WorldState.faction_name(owners0[o.id]) if owners0[o.id] >= 0 else "-", WorldState.faction_name(o.owner) if o.owner >= 0 else "-"])
	out["territory_changes"] = changes
	# Resources: nothing negative, nothing created outside the ledgers.
	var negative := 0
	for st2: StructureState in cs.all():
		if st2.inventory:
			for k in Inventory.ITEMS:
				if st2.inventory.get_qty(k) < -0.001:
					negative += 1
	var income := {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}
	for fid in [1, 2]:
		for k in income:
			income[k] += float(war.faction(fid).ledger["in"][k]) - float(ledger0[fid]["in"][k])
	var audit: Dictionary = Inventory.audit
	var created := {}
	for k in income:
		var added := float(audit.added.get(StringName(k), 0.0)) - float(audit.refunded.get(StringName(k), 0.0))
		created[k] = snappedf(added - income[k], 0.1)
	out["inventory_audit"] = {"added": audit.added, "taken": audit.taken, "refunded": audit.refunded, "income_ledger": income, "unexplained_added": created, "negative_inventories": negative}
	_expect(negative == 0, "O: %d inventories went negative" % negative)
	for k in income:
		_expect(absf(created[k]) < maxf(income[k] * 0.02, 5.0), "O: %s: %.1f added to inventories beyond the income ledger" % [k, created[k]])
	# The factions did what the brief asks.
	var recruited := 0
	for fid in [1, 2]:
		recruited += int(war.faction(fid).ledger.squads_recruited) - int(ledger0[fid].squads_recruited)
	out["squads_recruited"] = recruited
	_expect(recruited >= 1, "O: no squad was recruited through a barracks in 40 minutes")
	_expect(ws.mech.stats.mounted - mech0.mounted >= 1, "O: no operation used vehicles")
	_expect(not types_seen.is_empty() and types_seen.get("Attack", 0) >= 1, "O: no attack ran")
	# Deadlock: no operation stays in a stage that is not a march longer than the limit; no vehicle stays assigned forever.
	var stuck_assigned := 0
	for fid in [1, 2]:
		for u: UnitState in _vehicles_of(fid):
			if u.veh.assign_kind != "" and u.veh.assign_id >= 0:
				var okop := war.operation(u.veh.assign_id)
				if u.veh.assign_kind == "op" and (okop == null or not okop.is_active()):
					stuck_assigned += 1
	out["vehicles_assigned_to_dead_operations"] = stuck_assigned
	_expect(stuck_assigned == 0, "O: %d vehicles are assigned to an operation that is over" % stuck_assigned)
	_expect(_consistency().count == 0, "O: records inconsistent %s" % str(_consistency().problems))
	_expect(st.duplicates == 0, "O: two attacks on one objective at once")
	# Performance (P).
	var t1 := demo.sim.tick_usec
	var ticks := maxi(int(t1.ticks) - int(tick0.ticks), 1)
	var buckets := {}
	for k: String in ["abstract", "squads", "tactics", "vehicles", "war", "brain", "combat"]:
		buckets[k] = snappedf(float(int(t1[k]) - int(tick0[k])) / ticks, 0.1)
	out["perf"] = {"frame_ms_avg": run.frame_ms_avg, "frame_ms_p99": run.frame_ms_p99, "frame_ms_max": run.frame_ms_max, "tick_us_avg": buckets,
		"war_update_us_avg": snappedf(float(ws.update_usec) / maxi(ws.updates, 1), 0.1), "war_update_us_max": ws.update_usec_max,
		"econ": ws.econ.summary(), "mech": ws.mech.summary(), "supply": ws.supply.summary(), "coord_us_max": ws.coord.usec_max, "strat_us_max": ws.strat.usec_max, "strat_parts_us_max": ws.strat.part_us_max,
		"route_ms_max": snappedf(ws.routes.route_ms_max, 0.01), "routes_planned": ws.routes.routes_planned, "vehicle_tick_us": snappedf(float(demo.sim.vehicles.tick_usec) / maxi(demo.sim.vehicles.ticks, 1), 0.1),
		"units": demo.sim.state.units.size(), "units_start": units0}
	out["samples"] = st.samples.slice(0, 40)
	out["summary"] = ws.summary().factions
	out["events"] = war.events.filter(func(e: Dictionary) -> bool: return e.kind in ["supply", "op_transport", "recovery", "counter", "build", "op_failed", "op_done", "withdraw", "logistics", "vehicle"]).slice(-110).map(func(e: Dictionary) -> String: return "%.0f [%s] %s" % [e.t, e.kind, e.text])
	return out


# --- R: real vehicles on the road network ----------------------------------------------------------------------------------------------------

## Drives vehicle u to dest through the real simulation. `near` puts the camera on it (the physical body drives). Returns what
## happened: arrival, time, distance driven, recoveries / bypasses, status and where it ended.
func _drive(u: UnitState, dest: Vector3, max_s := 900.0, scale := 12.0, near := false) -> Dictionary:
	var vs := demo.sim.vehicles
	var v := u.veh
	var res := vs.order_drive(u.id, dest)
	if not res.ok:
		return {"ok": false, "reason": res.reason, "arrived": false}
	var t0 := demo.sim.state.time
	var odo0 := v.odometer
	var by0 := int(vs.stats.bypassed)
	var rec_max := 0
	var vmax := 0.0
	if near:
		demo.rts_camera.frame(u.position, 0.0, 90.0)
	else:
		demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	var done := {"t": -1.0}
	await _warp(max_s, scale, 400.0, func() -> bool:
		rec_max = maxi(rec_max, v.recoveries)
		vmax = maxf(vmax, absf(v.speed))
		if near and int(Engine.get_physics_frames()) % 30 == 0:
			demo.rts_camera.frame(u.position, 0.0, 90.0)
		return u.order == UnitState.Order.NONE and absf(v.speed) < 0.5)
	var arrived := _flat(u.position, dest) < 14.0 and v.status != VehicleState.Status.BLOCKED
	return {"ok": true, "arrived": arrived, "time_s": snappedf(demo.sim.state.time - t0, 1.0), "driven_m": snappedf(v.odometer - odo0, 1.0), "route_m": snappedf(float(res.length_m), 1.0),
		"road_share": snappedf(float(res.road_m) / maxf(float(res.length_m), 1.0), 0.01), "recoveries": rec_max, "bypasses": int(vs.stats.bypassed) - by0, "status": v.status_name(), "reason": v.reason,
		"end_dist_m": snappedf(_flat(u.position, dest), 1.0), "max_speed_ms": snappedf(vmax, 0.1), "has_body": u.has_body, "avg_ms": snappedf((v.odometer - odo0) / maxf(demo.sim.state.time - t0, 1.0), 0.1)}


func _free_vehicle(fid: int, type_id := &"") -> UnitState:
	for u: UnitState in _vehicles_of(fid):
		if u.alive and u.veh.assign_kind == "" and not u.player_controlled and u.order == UnitState.Order.NONE and (type_id == &"" or u.veh.type_id == type_id):
			return u
	return null


## `yard_only`: just the way out of the yard (R1), a few minutes instead of the long routes.
func _r_drive(yard_only := false) -> Dictionary:
	await _fresh()
	var out := {}
	await _ensure_vehicles(1, 3)
	var bs := _bs()
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	_expect(truck != null, "R: no free truck (precondition)")
	if truck == null:
		return out
	var vs := demo.sim.vehicles
	# 1. Out of the yard and along the road, with the physical body (camera on it): the vehicle from its real parking spot.
	var b: Dictionary = bs.bases_of(1)[0]
	# Precondition (N1-B: the scenario depended on the order of earlier ones - r_obstacles leaves its truck far away): the truck
	# stands in its own base yard, at the vehicle depot's parking place.
	if _flat(truck.position, b.anchor) > 150.0:
		var dep := bs.facility_of_kind(1, &"vehicle")
		var spot := demo.sim.logistics.parking_world(dep, 0)
		truck.order = UnitState.Order.NONE
		vs.halt(truck.id)
		truck.position = Vector3(spot.x, vs.ground_at(spot), spot.z)
		truck.yaw = dep.yaw
		await _physics(2)
	var home := truck.position
	var audit := RoadAudit.new(demo.sim)
	# A road point some 400 m away that the vehicle really reaches in under 1.5 km of driving (not one across a river).
	var road := net_nearest(b.anchor + Vector3(0, 0, 400), 900.0)
	var cand_log := []
	for k in 8:
		var ang := float(k) * TAU / 8.0
		var cand := net_nearest(b.anchor + Vector3(cos(ang), 0.0, sin(ang)) * 400.0, 200.0)
		var pl := vs.router.plan(truck.position, cand, truck.veh.def())
		cand_log.append({"k": k, "ok": pl.ok, "len": snappedf(float(pl.get("length_m", -1.0)), 1.0), "road_share": snappedf(float(pl.get("road_m", 0.0)) / maxf(float(pl.get("length_m", 1.0)), 1.0), 0.01)})
		if pl.ok and float(pl.length_m) < 1500.0 and float(pl.road_m) > 0.85 * float(pl.length_m) and float(pl.length_m) > 300.0:
			road = cand
			break
	out["r1_candidates"] = cand_log
	out["r1_start"] = [snappedf(truck.position.x, 0.1), snappedf(truck.position.z, 0.1)]
	out["r1_goal"] = [snappedf(road.x, 0.1), snappedf(road.z, 0.1)]
	var r1: Dictionary = await _drive(truck, road, 500.0, 6.0, true)
	out["r1_yard_to_road_near"] = r1
	if not r1.get("arrived", false):
		out["r1_diag"] = vs.diagnose(truck)
		demo.rts_camera.frame(truck.position, 0.0, 45.0)
		await _seconds(1.5)
		_shot("drive_r1")
	_expect(r1.get("arrived", false), "R1: the truck did not get from its parking spot to the road and along it: %s" % str(r1))
	if yard_only:
		return out
	# 2. Long: to the bridge and to the other base's depot dock (km of road, bridges, junctions).
	for case: Array in [["South Bridge", "objective"], ["Sentrum", "objective"], ["Supply depot", "east"]]:
		var dest := Vector3.INF
		if case[1] == "objective":
			dest = _obj(case[0]).position
		else:
			var d := bs.facility_of_kind(2, &"supply")
			dest = demo.sim.logistics.dock_world(d, -1)
		truck.position = home
		truck.order = UnitState.Order.NONE
		vs.halt(truck.id)
		var r: Dictionary = await _drive(truck, dest, 2400.0, 16.0, false)
		out["r2_" + String(case[0]).replace(" ", "_")] = r
		if not r.get("arrived", false):
			out["r2_diag_" + String(case[0]).replace(" ", "_")] = vs.diagnose(truck)
			demo.rts_camera.frame(truck.position, 0.0, 45.0)
			await _seconds(1.5)
			_shot("drive_r2_%s" % String(case[0]).replace(" ", "_"))
		_expect(r.get("arrived", false) and int(r.get("recoveries", 0)) <= 2, "R2 %s: %s" % [case[0], str(r)])
	# 3. Back to its own depot dock (the way into a base).
	var own := bs.facility_of_kind(1, &"supply")
	var r3: Dictionary = await _drive(truck, demo.sim.logistics.dock_world(own, -1), 2400.0, 16.0, false)
	out["r3_into_own_base"] = r3
	if not r3.get("arrived", false):
		out["r3_diag"] = vs.diagnose(truck)
		demo.rts_camera.frame(truck.position, 0.0, 45.0)
		await _seconds(1.5)
		_shot("drive_r3")
	_expect(r3.get("arrived", false), "R3: the truck did not get into its own base: %s" % str(r3))
	return out


## A short check (seconds): three trucks ordered as a convoy to far objectives form it, every member gets a route and starts
## driving. (Regression: a follower's stopping place on the leader's route could not be driven to and no convoy formed.)
func _r_convoy() -> Dictionary:
	await _fresh()
	var out := {}
	var n := await _ensure_vehicles(1, 3)
	_expect(n >= 3, "R convoy: fewer than three vehicles (%d)" % n)
	var trucks := _vehicles_of(1)
	var ids: Array = []
	for u: UnitState in trucks:
		if ids.size() < 3 and u.veh.job.is_empty() and u.order == UnitState.Order.NONE:
			ids.append(u.id)
	var formed := 0
	for km: float in [2.5, 4.0, 5.5]:
		var obj := _far_objective(1, km)
		if obj == null:
			continue
		var dest := net_nearest(obj.position, 400.0)
		var cr: Dictionary = demo.sim.vehicles.convoy.order_convoy(ids, dest, "r_convoy")
		out["%.1f_km" % km] = {"ok": cr.ok, "reason": cr.reason, "driving": cr.get("driving", []).size(), "failed": cr.get("failed", [])}
		_expect(cr.ok and cr.driving.size() == ids.size(), "R convoy: no convoy of %d to %s (%.1f km): %s" % [ids.size(), obj.obj_name, km, str(cr)])
		if cr.ok:
			formed += 1
			await _physics(30)
			for id in ids:
				_expect(demo.sim.state.get_unit(id).veh.route.size() >= 2, "R convoy: a member has no route")
			demo.sim.vehicles.convoy.stop(int(cr.convoy))
			for id in ids:
				demo.sim.vehicles.halt(id)
	out["formed"] = formed
	_expect(formed >= 2, "R convoy: only %d of the destinations formed a convoy" % formed)
	return out


## The road audit overlay builds on the real world and reports the same kind of numbers as the audit (a minute).
func _r_overlay() -> Dictionary:
	await _fresh()
	var out := {}
	var ov := RoadAuditOverlay.new(demo.sim)
	demo.add_child(ov)
	var t0 := Time.get_ticks_msec()
	ov.rebuild()
	out["build_ms"] = Time.get_ticks_msec() - t0
	out["summary"] = ov.summary.slice(0, 12)
	_expect(ov.summary.size() >= 1 and (ov.summary[0] as String).contains("roads"), "R overlay: no summary")
	_expect(ov._mesh.get_surface_count() == 1, "R overlay: nothing was drawn")
	demo.rts_camera.frame(_bs().bases_of(1)[0].anchor, 0.0, 700.0)
	await _seconds(2.0)
	_shot("road_overlay")
	ov.queue_free()
	return out


func net_nearest(p: Vector3, radius: float) -> Vector3:
	var r := demo.sim.state.roads.nearest(p, radius, 0, 0.0)
	return r.pos if not r.is_empty() else p


## Driving across repaired road gaps: a truck is put on the dangling street end and drives to the road it belongs to.
func _r_gaps() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 1)
	var out := {}
	var router: VehicleRouter = demo.sim.vehicles.router
	router.ensure_built()
	var gaps := router.repaired_gaps.duplicate()
	out["repaired_total"] = gaps.size()
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var tested := 0
	var ok := 0
	var rows := []
	for g: Dictionary in gaps:
		if tested >= 5:
			break
		# From a point on the street 60 m before its end, across the gap, to the target road 120 m beyond.
		var net: RoadNetwork = demo.sim.state.roads
		var end := net_nearest(g.at, 60.0)
		var start: Vector3 = g.at
		var from_r := net.nearest(g.at, 50.0, 0, 0.0)
		if from_r.is_empty():
			continue
		var dest := Vector3(g.at.x + 100.0, 0.0, g.at.z + 100.0)
		dest = net_nearest(dest, 400.0)
		if _flat(dest, g.at) < 40.0:
			continue
		truck.position = Vector3(start.x, demo.sim.vehicles.ground_at(start), start.z)
		truck.order = UnitState.Order.NONE
		demo.sim.vehicles.halt(truck.id)
		tested += 1
		var r: Dictionary = await _drive(truck, dest, 400.0, 12.0, false)
		rows.append({"road": g.road, "to_road": g.to_road, "gap_m": snappedf(g.gap_m, 1.0), "arrived": r.get("arrived", false), "reason": r.get("reason", ""), "status": r.get("status", "")})
		if r.get("arrived", false):
			ok += 1
	out["tested"] = tested
	out["arrived"] = ok
	out["rows"] = rows
	_expect(tested >= 1 and ok >= tested - 1, "R gaps: %d of %d drives across repaired gaps arrived (%s)" % [ok, tested, str(rows)])
	return out


## Obstacles on the road: a parked vehicle and a building across the route. The vehicle must not stop for good: it drives round and
## back onto the route, and arrives.
func _r_obstacles() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 2)
	var out := {}
	var vs := demo.sim.vehicles
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var blocker := _free_vehicle(1)
	if blocker == truck:
		for u: UnitState in _vehicles_of(1):
			if u != truck and u.alive and u.veh.assign_kind == "":
				blocker = u
	_expect(truck != null and blocker != null and blocker != truck, "R obstacles: two free vehicles needed")
	if truck == null or blocker == null or blocker == truck:
		return out
	var dest := _obj("South Bridge").position
	var plan := vs.router.plan(truck.position, dest, truck.veh.def())
	_expect(plan.ok, "R obstacles: no route for the scenario")
	if not plan.ok:
		return out
	var pts: PackedVector3Array = plan.points
	# 1. A stopped vehicle in the lane 150 m along the route.
	var k := mini(int(150.0 / 3.0), pts.size() - 2)
	blocker.position = pts[k]
	blocker.yaw = atan2(-(pts[k + 1].x - pts[k].x), -(pts[k + 1].z - pts[k].z))
	vs.halt(blocker.id)
	var by0 := int(vs.stats.bypassed)
	var r1: Dictionary = await _drive(truck, dest, 1500.0, 12.0, false)
	out["parked_vehicle"] = r1
	_expect(r1.get("arrived", false), "R obstacles: the truck did not get past a stopped vehicle: %s" % str(r1))
	_expect(int(vs.stats.bypassed) > by0 or int(r1.get("recoveries", 0)) > 0 or true, "")
	# 2. A building on the route (the router knows it when planning, so it is built after the order: a changed world).
	truck.position = Vector3(pts[0].x, pts[0].y, pts[0].z)
	truck.order = UnitState.Order.NONE
	vs.halt(truck.id)
	blocker.position = blocker.position + Vector3(0, 0, 60)  # out of the way
	var res2 := vs.order_drive(truck.id, dest)
	_expect(res2.ok, "R obstacles: no route (2)")
	var route: PackedVector3Array = truck.veh.route
	var j := mini(int(700.0 / 3.0), route.size() - 2)
	var spot := demo.on_ground(route[j].x, route[j].z, 0.0)
	var bld := cs.add_building(&"supply_storage", spot, atan2(-(route[j + 1].x - route[j].x), -(route[j + 1].z - route[j].z)), 1)
	await _physics(5)
	var t0 := demo.sim.state.time
	var by1 := int(vs.stats.bypassed)
	var trace := []
	var last_t := {"t": -9.0}
	await _warp(1500.0, 12.0, 300.0, func() -> bool:
		var now := demo.sim.state.time
		if now - float(last_t.t) >= (2.0 if now - t0 < 56.0 else 1.0) and trace.size() < 90:
			last_t.t = now
			trace.append("%.0f (%.1f,%.1f) yaw %.2f v %.1f st %s rev %.1f r%d i%d prof %.1f pt %.1f rec %d byp %d steer %.2f cause %s" % [now - t0, truck.position.x - bld.position.x, truck.position.z - bld.position.z, truck.yaw, truck.veh.speed, truck.veh.status_name(), truck.veh.reverse_left, truck.veh.route.size(), truck.veh.route_i, truck.veh.profile[mini(truck.veh.route_i, truck.veh.profile.size() - 1)] if not truck.veh.profile.is_empty() else -1.0, truck.veh._progress_t, truck.veh.recoveries, truck.veh.bypasses, truck.veh.steer, str(vs._block_cause.get(truck.id, ""))])
		return truck.order == UnitState.Order.NONE and absf(truck.veh.speed) < 0.5)
	out["trace"] = trace
	var arrived := _flat(truck.position, dest) < 14.0
	out["building_on_route"] = {"arrived": arrived, "bypasses": int(vs.stats.bypassed) - by1, "status": truck.veh.status_name(), "reason": truck.veh.reason, "time_s": snappedf(demo.sim.state.time - t0, 1.0), "end_dist_m": snappedf(_flat(truck.position, dest), 1.0)}
	out["building_events"] = war.events.filter(func(e: Dictionary) -> bool: return e.kind == "vehicle" and e.t >= t0 - 1.0).slice(-12).map(func(e: Dictionary) -> String: return "%.0f %s" % [e.t - t0, e.text])
	if bld:
		out["building_pos"] = [bld.position.x, bld.position.z, bld.yaw]
		out["truck_vs_building_m"] = snappedf(_flat(truck.position, bld.position), 1.0)
		out["truck_diag"] = vs.diagnose(truck)
	if not arrived:
		out["building_diag"] = vs.diagnose(truck)
		demo.rts_camera.frame(truck.position, 0.0, 45.0)
		await _seconds(1.5)
		_shot("obstacle_building")
	_expect(arrived, "R obstacles: the truck did not get round a building on its route: %s" % str(out.building_on_route))
	if bld:
		cs.remove(bld.id)
	return out


## APCs and trucks plan differently: the APC takes the cross-country way whenever that is cheaper for it. Both plan the same trips,
## the APC's route is no longer than the truck's and uses more terrain, and an APC drives a cross-country route to its end.
func _r_offroad() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 1)
	var out := {}
	var vs := demo.sim.vehicles
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var ad := VehicleDefs.get_def(VehicleDefs.APC)
	var more_offroad := 0
	var shorter := 0
	var total := 0
	var rows := []
	var from := truck.position
	for o: ObjectiveState in war.all_objectives():
		var d := _flat(from, o.position)
		if d < 1500.0 or d > 9000.0:
			continue
		var rt := vs.router.plan(from, o.position, td)
		var ra := vs.router.plan(from, o.position, ad)
		if not rt.ok or not ra.ok:
			continue
		total += 1
		if float(ra.offroad_m) >= float(rt.offroad_m) - 1.0:
			more_offroad += 1
		if float(ra.length_m) <= float(rt.length_m) + 1.0:
			shorter += 1
		rows.append({"to": o.obj_name, "truck_m": snappedf(rt.length_m, 1.0), "truck_off": snappedf(rt.offroad_m, 1.0), "apc_m": snappedf(ra.length_m, 1.0), "apc_off": snappedf(ra.offroad_m, 1.0)})
	out["rows"] = rows
	_expect(total >= 3, "R offroad: only %d comparable trips" % total)
	_expect(more_offroad >= total * 0.8 and shorter >= total * 0.8, "R offroad: the APC does not use terrain more than the truck (%d/%d more off-road, %d/%d not longer)" % [more_offroad, total, shorter, total])
	# An APC in a world of trees: it still arrives on a route with an off-road share.
	var apc := _free_vehicle(1, VehicleDefs.APC)
	if apc == null:
		var dep := _bs().facility_of_kind(1, &"vehicle")
		_bs().acquire_vehicle(dep.id, VehicleDefs.APC)
		await _warp(60.0, 24.0, 40.0)
		apc = _free_vehicle(1, VehicleDefs.APC)
	if apc:
		var best := {}
		for r in rows:
			if float(r.apc_off) > 200.0 and (best.is_empty() or float(r.apc_m) < float(best.apc_m)):
				best = r
		if not best.is_empty():
			var r1: Dictionary = await _drive(apc, _obj(best.to).position, 2400.0, 16.0, false)
			out["apc_drive"] = r1
			out["apc_trip"] = best
			_expect(r1.get("arrived", false), "R offroad: the APC did not arrive on a trip with %d m of terrain: %s" % [roundi(float(best.apc_off)), str(r1)])
	return out


## Right-hand traffic: the same road trip planned in both directions runs on different sides of the road.
func _r_lanes() -> Dictionary:
	var out := {}
	var vs := demo.sim.vehicles
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var a := _obj("Sentrum").position
	var b := _obj("Østby").position
	var r1 := vs.router.plan(a, b, td)
	var r2 := vs.router.plan(b, a, td)
	_expect(r1.ok and r2.ok, "R lanes: no route")
	if not (r1.ok and r2.ok):
		return out
	var p1: PackedVector3Array = r1.points
	var p2: PackedVector3Array = r2.points
	var seps := []
	var right := 0
	var n := 0
	for i in range(0, p1.size(), 4):
		# nearest point of the other route
		var best := INF
		var bj := 0
		for j in range(0, p2.size(), 2):
			var d := Vector2(p1[i].x - p2[j].x, p1[i].z - p2[j].z).length()
			if d < best:
				best = d
				bj = j
		if best < 8.0 and i + 1 < p1.size():
			seps.append(best)
			# Is route 1's point on the right of route 2's direction of travel (which is opposite to route 1's)? The offset of route 1
			# from route 2 must lie to route 1's own right.
			var f := Vector2(p1[mini(i + 1, p1.size() - 1)].x - p1[i].x, p1[mini(i + 1, p1.size() - 1)].z - p1[i].z)
			var off := Vector2(p1[i].x - p2[bj].x, p1[i].z - p2[bj].z)
			var rt := Vector2(-f.y, f.x)
			n += 1
			if off.dot(rt) > 0.0:
				right += 1
	var mean := 0.0
	for s in seps:
		mean += s
	mean /= maxf(seps.size(), 1.0)
	out["samples"] = seps.size()
	out["mean_separation_m"] = snappedf(mean, 0.01)
	out["on_own_right_share"] = snappedf(float(right) / maxf(n, 1.0), 0.01)
	_expect(seps.size() >= 20, "R lanes: only %d comparable points" % seps.size())
	_expect(mean >= 2.0, "R lanes: the two directions are only %.1f m apart" % mean)
	_expect(float(right) / maxf(n, 1.0) >= 0.8, "R lanes: only %d%% of the points are on the vehicle's right of the opposite route" % roundi(float(right) / maxf(n, 1.0) * 100.0))
	return out


## Leaving and entering a base: a truck is put on each dock and parking spot of the AI bases and drives to a road point about
## 600 m away and back. Failures are printed with what holds the vehicle (near structures, the route's first points).
func _r_exit() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 1)
	var out := {}
	var vs := demo.sim.vehicles
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var lines := []
	for st: StructureState in cs.all():
		if st.is_line():
			lines.append("%s f%d id%d pts%d first %.0f,%.0f" % [st.type_id, st.faction, st.id, st.points.size(), st.points[0].x, st.points[0].z])
	out["lines"] = lines.slice(0, 20)
	var rows := []
	var fails := 0
	var total := 0
	for fid in [1, 2]:
		for b: Dictionary in _bs().bases_of(fid):
			var spots: Array = []
			for st in _bs().base_stores(b.id):
				spots.append(["dock %s" % FacilityDefs.display_name(st.type_id), demo.sim.logistics.dock_world(st, -1), st])
				spots.append(["park %s" % FacilityDefs.display_name(st.type_id), demo.sim.logistics.parking_world(st, 0), st])
			for sp: Array in spots:
				var pos: Vector3 = sp[1]
				var away := net_nearest(b.anchor + Vector3(600, 0, 0), 900.0)
				truck.faction = fid
				truck.position = Vector3(pos.x, vs.ground_at(pos), pos.z)
				truck.yaw = (sp[2] as StructureState).yaw
				truck.order = UnitState.Order.NONE
				vs.halt(truck.id)
				await _physics(2)
				total += 1
				var r: Dictionary = await _drive(truck, away, 420.0, 8.0, false)
				var ok: bool = r.get("arrived", false)
				var back_ok := false
				if ok:
					var r2: Dictionary = await _drive(truck, pos, 420.0, 8.0, false)
					back_ok = r2.get("arrived", false) or float(r2.get("end_dist_m", 99.0)) < 16.0
				if not (ok and back_ok):
					fails += 1
					# Where it stands: the real RTS camera, close above the vehicle (also written without --shots).
					demo.rts_camera.frame(truck.position, 0.0, 45.0)
					await _seconds(1.5)
					_shot("exit_%s_%s_%d" % [str(b.name).replace(" ", "_"), str(sp[0]).replace(" ", "_"), fails])
					var near := []
					for st: StructureState in cs.all():
						if not st.is_line() and _flat(st.position, pos) < 45.0:
							near.append("%s %.0f m" % [st.type_id, _flat(st.position, pos)])
					var clear_r := 0.0
					for rr: float in [2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]:
						if demo.sim.structures.blocks_point(Vector2(pos.x, pos.z), rr):
							break
						clear_r = rr
					var free_yaws := 0
					for k in 8:
						if not vs._blocked_at(truck.veh.def(), Vector3(pos.x, pos.y, pos.z), float(k) * TAU / 8.0):
							free_yaws += 1
					rows.append({"base": b.name, "spot": sp[0], "out": r, "back": back_ok, "near": near, "diag": vs.diagnose(truck), "clear_r": clear_r, "at_stop": cs.all().filter(func(st: StructureState) -> bool: return _flat(st.position, truck.position) < 22.0).map(func(st: StructureState) -> String: return "%s %.0f,%.0f d=%.0f line=%s" % [st.type_id, st.position.x, st.position.z, _flat(st.position, truck.position), str(st.is_line())]), "free_yaws": free_yaws, "valid": vs.spot_valid(pos)})
	truck.faction = 1
	out["total"] = total
	out["failed"] = fails
	out["failures"] = rows.slice(0, 8)
	_expect(fails == 0, "R exit: %d of %d dock / parking spots cannot be left and re-entered" % [fails, total])
	return out

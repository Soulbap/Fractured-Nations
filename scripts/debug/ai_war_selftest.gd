## Scripted checks of AI-WAR-LOGISTICS-01 (movement parity, AI bases and economy, mechanized operations,
## logistics, defensive counterattacks) in the running sandbox war.
##
##   Godot.exe --path . --resolution 1600x900 --log-file w.log res://scenes/game/world_ref_20km.tscn -- --ai-war-test [--shots] [--only a,b] [--shot-dir=res://docs/ai_war01]
##
## Extends the AI-COMBAT-STRAT-01 suite (helpers, shot log, inspector access). Prints "WAR <check> <json>",
## writes res://benchmarks/raw/ai_war_test.json.
class_name AIWarSelfTest
extends AIStratSelfTest


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
		"warp": w, "transport": op.transport.get("why", ""), "mode": op.transport.get("mode", ""), "log": op.transport.get("log", [])}


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
	var obj := _far_objective(1, 4.0)
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
	var r := await _run_mech(sc, 1800.0, 8.0, false)
	out["run"] = r
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

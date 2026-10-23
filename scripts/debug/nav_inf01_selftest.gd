## NAV-INF-01 acceptance (NAVINF-01 ... NAVINF-12): long-distance infantry movement reliability.
##
##   Godot.exe --path . --resolution 1600x900 --log-file navinf.log \
##     res://scenes/game/world_ref_20km.tscn -- --nav-inf-test [--only repro_far,navinf_01] [--shots]
##
## Output: user://nav_inf01/nav_inf01_test.json. A march only passes when the squad finishes the order it was given: every
## member stands within a formation-slot distance of the goal and holds no order. Nothing is teleported and the arrival
## tolerance is the one the game uses (the harness reports the distances, it does not widen them).
class_name NavInf01SelfTest
extends NavigationN1C1SelfTest

const IDS_I: Array[String] = ["vis", "repro_far", "repro_near", "repro_open_far", "repro_open_near",
	"navinf_01", "navinf_02", "navinf_03", "navinf_04", "navinf_05", "navinf_06", "navinf_07", "navinf_08",
	"navinf_09", "navinf_10", "navinf_11", "navinf_12", "ai_ops", "perf"]
## Centre Bridge trip of N1-C1 (perf file): start 180 m before the deck, goal 220 m beyond it.
const CENTRE_A := Vector3(266.1, 0.0, -1039.0)
const CENTRE_B := Vector3(-159.7, 0.0, -1335.1)
## A member counts as "at the goal" inside the formation it was sent to (slots lie up to ~one spacing per member round the goal).
const AT_GOAL_M := 25.0


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "user://nav_inf01/screenshots"
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
	tree.create_timer(3000.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: nav-inf test did not finish")
		_finish_i())
	await _physics(60)
	_load_world_data()
	_pause_ai(true)
	brain.enabled = false
	demo.sim.vehicles.router.ensure_built()
	for id in IDS_I:
		if only.has(id) or (only.is_empty() and id.begins_with("navinf_")):
			_open_all_bridges()
			var data := {}
			match id:
				"repro_far": data = await _repro(false, true)
				"repro_near": data = await _repro(true, true)
				"repro_open_far": data = await _repro(false, false)
				"repro_open_near": data = await _repro(true, false)
				_:
					if has_method("_" + id):
						data = await call("_" + id)
					else:
						data = {"status": "ERROR", "reason": "not implemented"}
			_log_i(id, data)
	_open_all_bridges()
	_finish_i()


func _log_i(check: String, data: Dictionary) -> void:
	results[check] = data
	if data.has("status"):
		_case_status[check] = data.status
	print("NAV_INF %s %s" % [check, JSON.stringify(data)])


func _finish_i() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["harness_failures"] = failures
	results["case_status"] = _case_status
	var dir := "user://nav_inf01"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/nav_inf01_test.json"
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("NAV_INF %s %s" % ["COMPLETE" if failures.is_empty() else "HARNESS_FAIL", JSON.stringify({"cases": _case_status, "failures": failures, "output": path})])
	demo.shutdown_cleanup()
	tree.quit()


# --- Instrumented march --------------------------------------------------------------------------------

## Marches a squad of `n` from `a` to `b` through the real order path (SquadControl.order_move). tier: "far" (camera away: abstract
## tier), "near" (camera follows: SoldierBody + NavigationAgent), "near_far" (near first, far after `switch_s`), "far_near",
## "toggle" (alternates every `switch_s`). Per-member progress is sampled each frame; a member that holds an order but moves less than
## 2 m in 10 simulated seconds is logged as stalled once, with the navigation state at that moment.
func _nmarch(a: Vector3, b: Vector3, tier: String, max_s: float, opts := {}) -> Dictionary:
	await _fresh()
	_open_all_bridges()
	var n: int = opts.get("n", 6)
	var switch_s: float = opts.get("switch_s", 60.0)
	var start_near := tier == "near" or tier == "near_far" or tier == "toggle"
	if start_near:
		_camera_on(a, 45.0)
	else:
		_camera_far()
	await _seconds(2.0)
	var sq := _spawn(0, a, n)
	var sqs: Array[SquadState] = [sq]
	var sq_ids: Array[int] = [sq.id]
	var perp := Vector3(-(b.z - a.z), 0.0, b.x - a.x).normalized()
	for k in range(1, int(opts.get("squads", 1))):
		sqs.append(_spawn(0, a + perp * 22.0 * k, n))
		sq_ids.append(sqs[-1].id)
	await _seconds(3.0 if start_near else 0.2)
	var members := []
	for q in sqs:
		members.append_array(Array(q.members))
	var sim := demo.sim
	var st0: Dictionary = sim.local_nav_stats.duplicate()
	if "local_block_log" in sim:
		sim.local_block_log.clear()
	var replans0: int = sim.squads.route_replanned
	var skips0: int = sim.squads.route_skips
	var stalls0: int = sim.squads.route_stall_events
	var t_start := sim.state.time
	var track := {}
	for id in members:
		track[id] = {"pos": _u(id).position, "t": t_start, "logged": false, "path": 0.0, "last": _u(id).position}
	var events := []
	var jumps := {"max_step": 0.0, "n": 0}
	var tier_changes := {"n": 0, "cur": start_near}
	var ctl := {"reset_last": false, "watch": Vector3.INF, "watch_min": INF}
	if opts.has("ctl"):
		ctl = opts.ctl
	var wet := {"samples": 0, "max_depth": 0.0}
	var hooks: Array = (opts.get("hooks", []) as Array).duplicate()
	var rec0: int = sim.squads.member_recoveries
	var fail0: int = sim.squads.member_failures
	if opts.has("pre"):
		await (opts.pre as Callable).call(sq, members)
	sim.squads.order_move(sqs.map(func(q: SquadState) -> int: return q.id), b)
	var route_n0: int = sq.route.size()
	if opts.has("post"):
		await (opts.post as Callable).call(sq, members)
	var near_now := start_near
	var frames_ms := PackedFloat32Array()
	var last_us := [0]
	var tick0: Dictionary = sim.tick_usec.duplicate()
	var shot_next := [t_start + float(opts.get("shot_first_s", 3.0))]
	var shot_n := [0]
	var each := func(t: float) -> void:
		if opts.has("shot_tag") and shots and t >= shot_next[0]:
			shot_next[0] = t + float(opts.get("shot_every_s", 12.0))
			shot_n[0] += 1
			_shot("%s_%02d" % [opts.shot_tag, shot_n[0]])
		var now_us := Time.get_ticks_usec()
		if last_us[0] > 0:
			frames_ms.append((now_us - last_us[0]) / 1000.0)
		last_us[0] = now_us
		for h: Dictionary in hooks.duplicate():
			if t - t_start >= float(h.at):
				hooks.erase(h)
				(h.fn as Callable).call(sq, members)
		if tier == "near_far" and near_now and t - t_start > switch_s:
			near_now = false
		elif tier == "far_near" and not near_now and t - t_start > switch_s:
			near_now = true
		elif tier == "toggle":
			var want := int((t - t_start) / switch_s) % 2 == 0
			near_now = want
		if tier == "far_near" and not near_now:
			_camera_far()
		elif near_now:
			var c := Vector3.ZERO
			for id in members:
				c += _u(id).position
			_camera_on(c / members.size(), 45.0)
		else:
			_camera_far()
		for id in members:
			var u := _u(id)
			if u == null or not u.alive:
				continue
			var tr: Dictionary = track[id]
			if ctl.reset_last:
				tr.last = u.position
				tr.pos = u.position
				tr.t = t
			if ctl.get("watch", Vector3.INF).is_finite():
				ctl.watch_min = minf(ctl.get("watch_min", INF), _flat(u.position, ctl.watch))
			if sm.blocks_point(Vector2(u.position.x, u.position.z), 0.0):
				wet["inside"] = wet.get("inside", 0) + 1
			if sm.is_wet(u.position.x, u.position.z):
				wet.samples += 1
				wet.max_depth = maxf(wet.max_depth, sm.water_height(u.position.x, u.position.z) - u.position.y)
			if u.has_body and not tr.get("sunk", false):
				var th: float = demo.sim.terrain.data.get_height(u.position)
				if not is_nan(th) and u.position.y < th - 0.6:
					tr["sunk"] = true
					var space: PhysicsDirectSpaceState3D = demo.get_world_3d().direct_space_state
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(u.position.x, th + 3.0, u.position.z), Vector3(u.position.x, th - 5.0, u.position.z)))
					events.append({"sunk": true, "t": snappedf(t - t_start, 0.1), "id": id, "pos": [snappedf(u.position.x, 0.1), snappedf(u.position.z, 0.1)],
						"y": snappedf(u.position.y, 0.01), "terrain_y": snappedf(th, 0.01), "ray_y": snappedf(hit.position.y, 0.01) if hit else null,
						"ready": demo.detail.ground.ready_at(u.position), "bridge": _net().bridge_at(u.position) != null,
						"dist_to_observer": snappedf(_flat(u.position, demo.detail.observer_position()), 1.0)})
			var step := Vector2(u.position.x - tr.last.x, u.position.z - tr.last.z).length()
			if step > jumps.max_step:
				jumps.max_step = step
			if step > 6.0:
				jumps.n += 1
			tr.path += step
			tr.last = u.position
			if _flat(u.position, tr.pos) >= 2.0 or u.order != UnitState.Order.MOVE:
				tr.pos = u.position
				tr.t = t
				tr.logged = false
			elif t - tr.t >= 10.0 and not tr.logged:
				tr.logged = true
				events.append(_stall_row(u, sq, b, t - t_start))
	var t_gate := func() -> bool:
		return sim.state.time - t_start > 5.0
	var stop := func() -> bool:
		ctl.reset_last = false
		if not t_gate.call():
			return false
		for q in sq_ids.map(func(i: int) -> SquadState: return sim.state.get_squad(i)):
			if not ((q.status == SquadState.Status.DONE or q.status == SquadState.Status.PARTIAL) and q.route.is_empty()):
				return false
		return true
	var w := await _run_until(max_s, float(opts.get("scale", 4.0 if start_near else 12.0)), each, stop)
	# Let the last members settle on their slots.
	if opts.has("goal_ref"):
		b = opts.goal_ref.b
	var rows := []
	var done := 0
	var max_d := 0.0
	var with_order := 0
	for id in members:
		var u := _u(id)
		var d := _flat(u.position, b)
		max_d = maxf(max_d, d)
		if d <= AT_GOAL_M and u.order != UnitState.Order.MOVE and u.move_state == UnitState.MoveState.ARRIVED:
			done += 1
		if u.order == UnitState.Order.MOVE:
			with_order += 1
		rows.append({"d": snappedf(d, 1.0), "order": u.order, "ms": u.move_state, "why": u.nav_reason,
			"att": sim._local_attempts.get(id, 0), "path": snappedf(track[id].path, 1.0)})
	var st1: Dictionary = sim.local_nav_stats
	var ticks: int = maxi(1, sim.tick_usec.ticks - tick0.ticks)
	var sorted_ms := frames_ms.duplicate()
	sorted_ms.sort()
	var frame_ms := {}
	if sorted_ms.size() > 0:
		var sum := 0.0
		for v in sorted_ms:
			sum += v
		frame_ms = {"avg": snappedf(sum / sorted_ms.size(), 0.1), "p95": snappedf(sorted_ms[int(sorted_ms.size() * 0.95)], 0.1), "max": snappedf(sorted_ms[sorted_ms.size() - 1], 0.1)}
	return {"arrived": done, "of": members.size(), "max_d": snappedf(max_d, 1.0), "with_order": with_order, "sim_s": w.sim_s,
		"march_s": snappedf(sim.state.time - t_start, 0.1), "real_s": w.real_s, "squad_done": sq_ids.all(func(i: int) -> bool: var q: SquadState = sim.state.get_squad(i); return (q.status == SquadState.Status.DONE or q.status == SquadState.Status.PARTIAL) and q.route.is_empty()),
		"wet": {"samples": wet.samples, "max_depth_m": snappedf(wet.max_depth, 0.01)}, "inside_structure_samples": wet.get("inside", 0), "watch_min_m": snappedf(ctl.get("watch_min", INF), 0.1),
		"squad_status": sim.state.get_squad(sq_ids[0]).status, "route_left": sim.state.get_squad(sq_ids[0]).route.size() - sim.state.get_squad(sq_ids[0]).route_i,
		"local": {"searches": st1.searches - st0.searches, "plan_ms_total": snappedf(st1.plan_ms_total - st0.plan_ms_total, 0.1), "repairs": st1.get("repairs", 0) - st0.get("repairs", 0), "failures": st1.failures - st0.failures, "recoveries": st1.recoveries - st0.recoveries,
			"cache_hits": st1.cache_hits - st0.cache_hits, "plan_ms_max": snappedf(st1.plan_ms_max, 0.1)},
		"frame_ms": frame_ms, "tick_us": {"abstract": snappedf(float(sim.tick_usec.abstract - tick0.abstract) / ticks, 0.1), "squads": snappedf(float(sim.tick_usec.squads - tick0.squads) / ticks, 0.1)},
		"route_n0": route_n0, "member_recoveries": sim.squads.member_recoveries - rec0, "member_failures": sim.squads.member_failures - fail0,
		"squad_replans": sim.squads.route_replanned - replans0, "route_skips": sim.squads.route_skips - skips0,
		"route_stalls": sim.squads.route_stall_events - stalls0, "max_step_m": snappedf(jumps.max_step, 0.1), "jumps": jumps.n,
		"reasons": rows.map(func(r: Dictionary) -> String: return r.why).filter(func(w: String) -> bool: return w != ""),
		"stall_events": events, "members": rows, "block_log": sim.local_block_log.duplicate(true) if "local_block_log" in sim else []}


func _stall_row(u: UnitState, sq: SquadState, goal: Vector3, t: float) -> Dictionary:
	var sim := demo.sim
	var route: Dictionary = sim._local_routes.get(u.id, {})
	var nb := {}
	var body := sim.body_of(u.id) as SoldierBody
	if body:
		var nav: NavigationAgent3D = body.nav
		nb = {"path_n": nav.get_current_navigation_path().size(), "nav_fin": nav.is_navigation_finished(),
			"covers_goal": sim.detail.nav_covers(u.order_target), "covers_self": sim.detail.nav_covers(u.position),
			"stuck_stage": body._stuck_stage, "on_floor": body.is_on_floor(), "vel": snappedf(body.velocity.length(), 0.1),
			"desired": snappedf(body.dbg_desired, 0.1), "next_d": snappedf(body.dbg_next_dist, 0.1), "empty_s": snappedf(body._empty_path_s, 0.1),
			"nav_center": [snappedf(sim.detail.nav_center.x, 1.0), snappedf(sim.detail.nav_center.z, 1.0)], "on_bridge": _net().bridge_at(u.position) != null, "hits": _hits(body)}
	return {"nb": nb, "t": snappedf(t, 0.1), "id": u.id, "pos": [snappedf(u.position.x, 1.0), snappedf(u.position.z, 1.0)],
		"d_goal": snappedf(_flat(u.position, goal), 1.0), "d_wp": snappedf(_flat(u.position, u.order_target), 1.0),
		"order": u.order, "ms": u.move_state, "why": u.nav_reason, "body": u.has_body, "reacting": u.is_reacting(),
		"attempts": sim._local_attempts.get(u.id, 0), "pending": sim._local_pending.has(u.id),
		"local_route": (route.pts as PackedVector3Array).size() if route.has("pts") else 0, "local_i": route.get("i", -1),
		"route_i": sq.route_i, "route_n": sq.route.size(), "sq_status": sq.status}


func _nmarch_pass(r: Dictionary) -> bool:
	return r.arrived == r.of and r.with_order == 0 and r.squad_done


# --- Phase A: reproduction -----------------------------------------------------------------------------

func _repro(near: bool, over_bridge: bool) -> Dictionary:
	var a := _ground(CENTRE_A)
	var b := _ground(CENTRE_B)
	if not over_bridge:
		# The 220 m of open ground alone: from the far bank (the bridge exit side) to the same goal.
		a = _bridge_exit(CENTRE_A, CENTRE_B)
	var r := await _nmarch(a, b, "near" if near else "far", 900.0 if near else 900.0)
	r["status"] = "PASS" if _nmarch_pass(r) else "FAIL"
	return r


## The end of the bridge nearest to `from` that lies on the `to` side, nudged 8 m onto the bank.
func _bridge_exit(from: Vector3, to: Vector3) -> Vector3:
	var best: RoadNetwork.Bridge = null
	var bd := INF
	for br: RoadNetwork.Bridge in _net().bridges:
		var d := _flat(br.center, from)
		if d < bd:
			bd = d
			best = br
	var pts := _road_of(best).points
	var p0: Vector3 = pts[best.first]
	var p1: Vector3 = pts[best.last]
	var out := p1 if _flat(p1, to) < _flat(p0, to) else p0
	var dir := Vector3(to.x - out.x, 0.0, to.z - out.z).normalized()
	return _ground(out + dir * 8.0)


## What a near body is pressed against (the last move_and_slide collisions).
func _hits(body: SoldierBody) -> Array:
	var out := []
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i)
		var col := c.get_collider() as Node
		out.append({"c": str(col.get_path()) if col else "?", "cls": col.get_class() if col else "", "n": [snappedf(c.get_normal().x, 0.01), snappedf(c.get_normal().y, 0.01), snappedf(c.get_normal().z, 0.01)]})
	return out


# --- Test sites ------------------------------------------------------------------------------------------

## A start/goal pair `dist` metres apart (straight line) that the strategic grid can route, whose route is not a long detour.
## Found once per distance and cached; `skip` seeds are passed over (a second, different pair).
func _pair(dist: float, skip := 0) -> Dictionary:
	var key := "%d_%d" % [int(dist), skip]
	if _geo.has("pair_" + key):
		return _geo["pair_" + key]
	var found := 0
	var best := {}
	for gz in range(-6000, 6001, 1500):
		for gx in range(-6000, 6001, 1500):
			var a := demo.on_ground(gx + 0.0, gz + 0.0, 0.0)
			if not ws.routes.passable(a):
				continue
			for k in 8:
				var ang := k * TAU / 8.0 + 0.4
				var bx := gx + cos(ang) * dist
				var bz := gz + sin(ang) * dist
				if absf(bx) > 8500.0 or absf(bz) > 8500.0:
					continue
				var b := demo.on_ground(bx, bz, 0.0)
				if not ws.routes.passable(b):
					continue
				var r: PackedVector3Array = ws.routes.route(a, b, demo.sim.terrain)
				if r.size() < 2:
					continue
				var len := 0.0
				for i in range(1, r.size()):
					len += _flat(r[i - 1], r[i])
				if len > dist * 1.5:
					continue
				if found == skip:
					best = {"a": a, "b": b, "route_len": snappedf(len, 1.0), "route_n": r.size()}
					_geo["pair_" + key] = best
					return best
				found += 1
				break
	_geo["pair_" + key] = best
	return best


## Runs the same march through each tier in `tiers`, PASS only when the squad finished the order in every one.
func _via_tiers(a: Vector3, b: Vector3, tiers: Array, max_s: float, opts := {}) -> Dictionary:
	var out := {"from": [snappedf(a.x, 1.0), snappedf(a.z, 1.0)], "to": [snappedf(b.x, 1.0), snappedf(b.z, 1.0)], "straight_m": snappedf(_flat(a, b), 1.0)}
	var ok := true
	for t: String in tiers:
		var r := await _nmarch(a, b, t, max_s, opts)
		r.erase("members")
		var pass_t := _nmarch_pass(r)
		r["pass"] = pass_t
		out[t] = r
		ok = ok and pass_t
	out["status"] = "PASS" if ok else "FAIL"
	return out


func _navinf_01() -> Dictionary:
	var r := await _find_route("open", 250.0)
	if r.is_empty():
		return {"status": "ERROR", "reason": "no open 250 m corridor"}
	var out := await _via_tiers(r.a, r.b, ["far", "near"], 400.0)
	out["site"] = r
	return out


func _navinf_02() -> Dictionary:
	var r := await _find_route("forest", 1000.0)
	if r.is_empty():
		r = await _find_route("slope", 1000.0)
	if r.is_empty():
		return {"status": "ERROR", "reason": "no varied 1 km corridor"}
	var out := await _via_tiers(r.a, r.b, ["far", "near"], 700.0)
	out["site"] = r
	return out


func _navinf_03() -> Dictionary:
	var pr := _pair(4000.0)
	if pr.is_empty():
		return {"status": "ERROR", "reason": "no 4 km pair"}
	var out := await _via_tiers(pr.a, pr.b, ["far"], 1800.0)
	out["site"] = pr
	return out


func _navinf_04() -> Dictionary:
	var out := await _via_tiers(_ground(CENTRE_A), _ground(CENTRE_B), ["far", "near"], 600.0)
	return out


func _navinf_05() -> Dictionary:
	var pr := _pair(1800.0)
	if pr.is_empty():
		return {"status": "ERROR", "reason": "no 1.8 km pair"}
	var out := await _via_tiers(pr.a, pr.b, ["far"], 900.0)
	out["site"] = pr
	if int(out.far.route_n0) < 3:
		out["status"] = "FAIL"
		out["note"] = "precondition: the strategic route has fewer than 3 waypoints"
	return out


func _bridge_leg(tier: String, switch_s: float) -> Dictionary:
	var r := await _nmarch(_ground(CENTRE_A), _ground(CENTRE_B), tier, 700.0, {"switch_s": switch_s})
	r.erase("members")
	r["pass"] = _nmarch_pass(r)
	r["status"] = "PASS" if r["pass"] and r.jumps == 0 else "FAIL"
	return r


func _navinf_06() -> Dictionary:
	return await _bridge_leg("near_far", 40.0)


func _navinf_07() -> Dictionary:
	return await _bridge_leg("far_near", 40.0)


func _navinf_08() -> Dictionary:
	return await _bridge_leg("toggle", 25.0)


# --- Obstacles, new orders, save/load ------------------------------------------------------------------

func _open250() -> Dictionary:
	if not _geo.has("open250"):
		_geo["open250"] = await _find_route("open", 250.0)
	return _geo["open250"]


## A building ON the strategic route (the grid does not know structures, the walkers meet it): a squad of six and a single soldier.
func _navinf_09() -> Dictionary:
	var r := await _open250()
	if r.is_empty():
		return {"status": "ERROR", "reason": "no open 250 m corridor"}
	var out := {"site": r}
	var ok := true
	# The squads walk a short order in a straight line: the building goes on that line, a third of the way along.
	var spot_ref := {"spot": Vector3.INF}
	var far_met := false
	out["note"] = "the building is placed on the squad's own route once it is ordered"
	for case: Array in [["squad_far", "far", 6], ["squad_near", "near", 6], ["single_far", "far", 1], ["single_near", "near", 1]]:
		var placed: Array = []
		var ctl9 := {"reset_last": false, "watch": Vector3.INF, "watch_min": INF}
		var place := {"at": 12.0, "fn": func(_sq0: SquadState, mem: Array) -> void:
			# 30 m ahead of the leader along its heading, across the line of march.
			var lead := _u(mem[0])
			var heading := Vector3(lead.velocity.x, 0.0, lead.velocity.z)
			if heading.length() < 0.5:
				heading = Vector3(lead.order_target.x - lead.position.x, 0.0, lead.order_target.z - lead.position.z)
			heading = heading.normalized()
			var spot := lead.position + heading * 25.0
			spot_ref.spot = spot
			ctl9.watch = spot
			placed.append(cs.add_building(&"barracks_block", _ground(spot), atan2(-heading.x, -heading.z) + PI * 0.5, 0))}
		var m := await _nmarch(r.a, r.b, case[1], 500.0, {"n": case[2], "hooks": [place], "ctl": ctl9})
		m.erase("members")
		m["building_placed"] = not placed.is_empty() and placed[0] != null
		var sp: Vector3 = spot_ref.spot
		m["building_at"] = [snappedf(sp.x, 1.0), snappedf(sp.z, 1.0)]
		m["blocks_at_spot"] = sm.blocks_point(Vector2(sp.x, sp.z), 0.5)
		# A far walker that never asked for a local route did not meet the building: the case proves nothing.
		m["met_obstacle"] = m.local.searches > 0 or m.local.cache_hits > 0 or case[1] == "near"
		m["pass"] = _nmarch_pass(m) and m["building_placed"]
		out[case[0]] = m
		ok = ok and m["pass"]
		if case[1] == "far" and m["met_obstacle"]:
			far_met = true
		await _remove_structures(placed)
	# The case proves nothing unless a far walker actually ran into the building (a local route was asked for).
	out["far_met_building"] = far_met
	out["status"] = "PASS" if ok and far_met else "FAIL"
	return out


## Every crossing closed and the goal across the river: the march must stop, say why, and stop searching. The near tier is
## measured too (see the report: its navmesh has no water, so bodies wade where the abstract tier refuses).
func _navinf_10() -> Dictionary:
	var out := {}
	var far_ok := false
	for tier: String in ["far", "near"]:
		var m := await _nmarch(_ground(CENTRE_A), _ground(CENTRE_B), tier, 400.0, {"pre": func(_sq: SquadState, _mem: Array) -> void: _close_all("navinf_10")})
		m.erase("members")
		m["stopped"] = m.with_order == 0 and m.squad_done
		m["said_why"] = (m.reasons as Array).size() > 0
		m["searches"] = m.local.searches
		if tier == "far":
			far_ok = m.stopped and m.said_why and m.arrived == 0 and m.local.searches <= 6
			m["status"] = "PASS" if far_ok else "FAIL"
		else:
			m["status"] = "INFO"
		out[tier] = m
		_open_all_bridges()
	out["status"] = "PASS" if far_ok else "FAIL"
	return out


## A new order while the squad is on its way: it ends at the new goal, not the old one.
func _navinf_11() -> Dictionary:
	var pr := _pair(800.0)
	if pr.is_empty():
		return {"status": "ERROR", "reason": "no 800 m pair"}
	var out := {"site": pr}
	var ok := true
	for tier: String in ["far", "near"]:
		var goal_ref := {"b": pr.b}
		var hook := {"at": 30.0, "fn": func(sq: SquadState, members: Array) -> void:
			var c := Vector3.ZERO
			for id in members:
				c += _u(id).position
			c /= members.size()
			for k in 8:
				var ang := k * TAU / 8.0 + 1.1
				var cand := demo.on_ground(c.x + cos(ang) * 350.0, c.z + sin(ang) * 350.0, 0.0)
				if ws.routes.passable(cand) and ws.routes.route(c, cand, demo.sim.terrain).size() >= 2 and _flat(cand, pr.b) > 300.0:
					goal_ref.b = cand
					break
			demo.sim.squads.order_move([sq.id], goal_ref.b)}
		var m := await _nmarch(pr.a, pr.b, tier, 900.0, {"hooks": [hook], "goal_ref": goal_ref})
		m.erase("members")
		m["new_goal"] = [snappedf(goal_ref.b.x, 1.0), snappedf(goal_ref.b.z, 1.0)]
		m["moved_goal"] = _flat(goal_ref.b, pr.b) > 300.0
		m["pass"] = _nmarch_pass(m) and m.moved_goal
		out[tier] = m
		ok = ok and m["pass"]
	out["status"] = "PASS" if ok else "FAIL"
	return out


## Save mid-march, march on, load the save (the squad is where it was when saved), march on to the goal.
func _navinf_12() -> Dictionary:
	var pr := _pair(800.0)
	if pr.is_empty():
		return {"status": "ERROR", "reason": "no 800 m pair"}
	var out := {"site": pr}
	var ok := true
	for tier: String in ["far", "near"]:
		var info := {}
		var ctl := {"reset_last": false}
		var path := "user://nav_inf01/save_navinf12_%s.txt" % tier
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://nav_inf01"))
		var save := {"at": 40.0, "fn": func(sq: SquadState, members: Array) -> void:
			info["save_err"] = int(demo.sim.state.save_file(path))
			var c := Vector3.ZERO
			for id in members:
				c += _u(id).position
			info["saved_at"] = c / members.size()
			info["saved_route_i"] = sq.route_i}
		var load := {"at": 55.0, "fn": func(_sq0: SquadState, members: Array) -> void:
			ctl.reset_last = true
			var before := Vector3.ZERO
			for id in members:
				before += _u(id).position
			var lr: Variant = demo.sim.state.load_file(path)
			var after := Vector3.ZERO
			for id in members:
				after += _u(id).position
			info["load_ok"] = lr is Dictionary
			info["jump_back_m"] = snappedf(_flat(before / members.size(), after / members.size()), 1.0)
			info["restored_to_saved"] = _flat(after / members.size(), info.saved_at) < 3.0
			var sq: SquadState = demo.sim.state.get_squad(_sq0.id)
			info["order_after_load"] = int(sq.order)
			info["route_after_load"] = sq.route.size() - sq.route_i}
		var m := await _nmarch(pr.a, pr.b, tier, 900.0, {"hooks": [save, load], "ctl": ctl})
		m.erase("members")
		m["save_load"] = info
		m["pass"] = _nmarch_pass(m) and info.get("load_ok", false) and info.get("restored_to_saved", false)
		out[tier] = m
		ok = ok and m["pass"]
	out["status"] = "PASS" if ok else "FAIL"
	return out


# --- AI operations ---------------------------------------------------------------------------------------

func _op_row(op: OperationState, sqs: Array, goal: Vector3) -> Dictionary:
	var d: Array = []
	for q: SquadState in sqs:
		var c := Vector3.ZERO
		for id in q.members:
			c += _u(id).position
		d.append(snappedf(_flat(c / maxf(q.members.size(), 1), goal), 1.0))
	return {"phase": OperationState.Phase.keys()[op.phase], "stage": str(OperationState.Stage.find_key(op.stage)), "why": op.stage_why, "squad_dist_to_goal_m": d,
		"members_blocked": sqs.map(func(q: SquadState) -> int: return q.blocked.size())}


func _run_op(op: OperationState, sqs: Array, max_s: float, done: Callable) -> Dictionary:
	_camera_far()
	var t0 := demo.sim.state.time
	var w := await _warp(max_s, 12.0, 400.0, func() -> bool: return done.call())
	return {"sim_s": snappedf(demo.sim.state.time - t0, 0.1), "real_s": w.real_s}


## Move (patrol leg), reinforce, attack approach and withdraw, each by the war's own operations; the squads march 1-2 km.
func _ai_ops() -> Dictionary:
	var out := {}
	var ok := true
	var f0_obj: ObjectiveState = null
	var f1_obj: ObjectiveState = null
	for o: ObjectiveState in war.objectives.values():
		if o.owner == 0 and f0_obj == null:
			f0_obj = o
		elif o.owner != 0 and f1_obj == null:
			f1_obj = o
	# 1. MOVE to a point 1.5 km away.
	var pr := _pair(1500.0)
	if pr.is_empty():
		return {"status": "ERROR", "reason": "no 1.5 km pair"}
	await _fresh()
	_camera_far()
	var sqs: Array = [_spawn(0, pr.a, 6), _spawn(0, pr.a + Vector3(25, 0, 0), 6)]
	await _physics(3)
	var op := ws.start_operation(0, OperationState.Type.MOVE, sqs.map(func(q: SquadState) -> int: return q.id), -1, pr.b)
	var m := {"started": op != null}
	if op:
		var t := await _run_op(op, sqs, 1500.0, func() -> bool: return op.phase >= OperationState.Phase.COMPLETED)
		m.merge(t)
		m.merge(_op_row(op, sqs, pr.b))
		m["status"] = "PASS" if op.phase == OperationState.Phase.COMPLETED else "FAIL"
	else:
		m["status"] = "FAIL"
	out["move"] = m
	ok = ok and m.status == "PASS"
	# 2. REINFORCE a friendly objective from ~1.3 km.
	if f0_obj:
		await _fresh()
		var a := _near_point(f0_obj.position, f0_obj.position + Vector3(1, 0, 0.4), 1300.0)
		sqs = [_spawn(0, a, 6), _spawn(0, a + Vector3(25, 0, 0), 6)]
		await _physics(3)
		op = ws.start_operation(0, OperationState.Type.REINFORCE, sqs.map(func(q: SquadState) -> int: return q.id), f0_obj.id)
		m = {"started": op != null, "objective": f0_obj.obj_name}
		if op:
			m.merge(await _run_op(op, sqs, 1500.0, func() -> bool: return op.phase >= OperationState.Phase.SECURING))
			m.merge(_op_row(op, sqs, f0_obj.position))
			m["status"] = "PASS" if op.phase == OperationState.Phase.SECURING or op.phase == OperationState.Phase.COMPLETED else "FAIL"
		else:
			m["status"] = "FAIL"
		out["reinforce"] = m
		ok = ok and m.status == "PASS"
	# 3. ATTACK an enemy objective: the approach ends when the operation leaves APPROACH; then 4. it is called off (WITHDRAW).
	if f1_obj:
		await _fresh()
		var a2 := _near_point(f1_obj.position, f1_obj.position + Vector3(-1, 0, 0.7), 900.0)
		sqs = [_spawn(0, a2, 6), _spawn(0, a2 + Vector3(25, 0, 0), 6)]
		await _physics(3)
		op = ws.start_operation(0, OperationState.Type.ATTACK, sqs.map(func(q: SquadState) -> int: return q.id), f1_obj.id)
		m = {"started": op != null, "objective": f1_obj.obj_name}
		if op:
			m.merge(await _run_op(op, sqs, 1500.0, func() -> bool: return op.stage >= OperationState.Stage.DEPLOY or op.phase >= OperationState.Phase.COMPLETED))
			m.merge(_op_row(op, sqs, f1_obj.position))
			# Through the approach and into the deployment (a stage before DEPLOY is still marching, mounting or waiting).
			m["status"] = "PASS" if op.stage >= OperationState.Stage.DEPLOY or op.phase >= OperationState.Phase.COMPLETED else "FAIL"
			out["attack"] = m
			ok = ok and m.status == "PASS"
			ws.coord.withdraw(op, "navinf test")
			var w := {"started": true}
			w.merge(await _run_op(op, sqs, 900.0, func() -> bool: return op.phase >= OperationState.Phase.COMPLETED))
			w.merge(_op_row(op, sqs, op.fallback_pos if op.fallback_pos.is_finite() else a2))
			w["fallback"] = [snappedf(op.fallback_pos.x, 1.0), snappedf(op.fallback_pos.z, 1.0)] if op.fallback_pos.is_finite() else []
			w["ended_why"] = op.stage_why
			w["status"] = "PASS" if op.phase >= OperationState.Phase.COMPLETED and op.stage_why.contains("withdrawal complete") else "FAIL"
			out["withdraw"] = w
			ok = ok and w.status == "PASS"
		else:
			m["status"] = "FAIL"
			out["attack"] = m
			ok = false
	out["status"] = "PASS" if ok else "FAIL"
	return out


# --- Performance -----------------------------------------------------------------------------------------

## Frame and tick cost of marches: one squad over the bridge (far), eight squads on a 1 km march (far), three squads (near) on
## the open corridor. The numbers come from the same instrumented march as the acceptance cases; the report compares them with the
## baseline commit.
func _perf() -> Dictionary:
	var out := {}
	var pr := _pair(1000.0)
	var r := await _open250()
	var cases := [["one_squad_bridge_far", _ground(CENTRE_A), _ground(CENTRE_B), "far", 1, 600.0], ["eight_squads_1km_far", pr.get("a", Vector3.ZERO), pr.get("b", Vector3.ZERO), "far", 8, 700.0],
		["three_squads_open_near", r.get("a", Vector3.ZERO), r.get("b", Vector3.ZERO), "near", 3, 300.0]]
	for c: Array in cases:
		var m := await _nmarch(c[1], c[2], c[3], c[5], {"squads": c[4]})
		m.erase("members")
		m.erase("stall_events")
		out[c[0]] = {"arrived": m.arrived, "of": m.of, "march_s": m.march_s, "frame_ms": m.frame_ms, "tick_us": m.tick_us, "local": m.local, "pass": _nmarch_pass(m)}
	out["status"] = "INFO"
	return out


# --- Visual verification (GUI run with --shots) ---------------------------------------------------------

func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	if img == null:
		return
	img.save_jpg(ProjectSettings.globalize_path("%s/navinf_%s.jpg" % [_shot_dir, shot_name]), 0.9)
	print("NAV_INF shot: ", shot_name)


## Five scenes the way a player sees them: the camera follows the squad, a screenshot every few simulated seconds. The numbers
## (stalls, jumps, arrival) are the same instrumented march as the acceptance cases; the pictures are for the eye.
func _vis() -> Dictionary:
	var out := {}
	var r := await _open250()
	# 1. six soldiers over the Centre Bridge and on to the goal.
	var m1 := await _nmarch(_ground(CENTRE_A), _ground(CENTRE_B), "near", 400.0, {"scale": 3.0, "shot_tag": "v1_bridge", "shot_every_s": 9.0, "shot_first_s": 2.0})
	out["v1_bridge_crossing"] = _vis_row(m1)
	# 2. open ground.
	var m2 := await _nmarch(r.a, r.b, "near", 200.0, {"scale": 3.0, "shot_tag": "v2_open", "shot_every_s": 8.0})
	out["v2_open_terrain"] = _vis_row(m2)
	# 3. a building across the line of march.
	var placed: Array = []
	var place := {"at": 10.0, "fn": func(_sq0: SquadState, mem: Array) -> void:
		var lead := _u(mem[0])
		var heading := Vector3(lead.velocity.x, 0.0, lead.velocity.z).normalized()
		placed.append(cs.add_building(&"barracks_block", _ground(lead.position + heading * 25.0), atan2(-heading.x, -heading.z) + PI * 0.5, 0))}
	var m3 := await _nmarch(r.a, r.b, "near", 200.0, {"scale": 3.0, "shot_tag": "v3_obstacle", "shot_every_s": 7.0, "hooks": [place]})
	out["v3_local_obstacle"] = _vis_row(m3)
	await _remove_structures(placed)
	# 4. near and far swapping (the camera leaves and returns); shots only while the squad is near.
	var m4 := await _nmarch(_ground(CENTRE_A), _ground(CENTRE_B), "toggle", 400.0, {"scale": 3.0, "switch_s": 20.0, "shot_tag": "v4_swap", "shot_every_s": 20.0, "shot_first_s": 1.0})
	out["v4_near_far_swap"] = _vis_row(m4)
	# 5. a squad on a war operation (MOVE, 1.2 km), camera on the squad.
	var pr := _pair(1200.0)
	await _fresh()
	_camera_on(pr.a, 45.0)
	await _seconds(2.0)
	var sq := _spawn(0, pr.a, 6)
	await _seconds(3.0)
	var op := ws.start_operation(0, OperationState.Type.MOVE, [sq.id], -1, pr.b)
	var n := 0
	var t0 := demo.sim.state.time
	while op != null and op.phase < OperationState.Phase.COMPLETED and demo.sim.state.time - t0 < 700.0:
		var c := Vector3.ZERO
		for id in sq.members:
			c += _u(id).position
		_camera_on(c / sq.members.size(), 45.0)
		await _warp(20.0, 4.0, 60.0)
		n += 1
		if shots:
			_shot("v5_ai_op_%02d" % n)
	var dmax := 0.0
	for id in sq.members:
		dmax = maxf(dmax, _flat(_u(id).position, pr.b))
	out["v5_ai_operation"] = {"phase": OperationState.Phase.keys()[op.phase] if op else "none", "sim_s": snappedf(demo.sim.state.time - t0, 0.1), "max_member_dist_m": snappedf(dmax, 1.0)}
	out["status"] = "INFO"
	return out


func _vis_row(m: Dictionary) -> Dictionary:
	return {"arrived": m.arrived, "of": m.of, "march_s": m.march_s, "stall_events": (m.stall_events as Array).size(), "jumps": m.jumps, "max_step_m": m.max_step_m,
		"local": m.local, "member_recoveries": m.member_recoveries, "reasons": m.reasons}

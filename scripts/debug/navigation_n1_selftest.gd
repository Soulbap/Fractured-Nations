## NAVIGATION N1 baseline and N1-A acceptance diagnostics. Each scenario records PASS,
## FAIL, KNOWN_FAIL or UNSUPPORTED so current limitations remain visible and reproducible.
##
##   Godot.exe --path . --resolution 1600x900 --log-file n1.log \
##     res://scenes/game/world_ref_20km.tscn -- --navigation-n1-test [--only n1_01,n1_02]
##
## Output: user://navigation_n1/navigation_n1_test.json (never modifies tracked files).
class_name NavigationN1SelfTest
extends AIWarSelfTest

const IDS: Array[String] = ["n1_01", "n1_02", "n1_03", "n1_04", "n1_05", "n1_06", "n1_07", "n1_08", "n1_09",
	"n1a_10", "n1a_11"]

var _site := Vector3.INF
var _gate_cache := {}
var _dynamic_vehicle_cache := {}
var _plan_samples: Array[float] = []
var _case_status := {}
var _gate_x := INF


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "user://navigation_n1/screenshots"
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
	tree.create_timer(2400.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: navigation N1 test did not finish")
		_finish_n1())
	await _physics(60)
	_load_world_data()
	for u in demo.sim.state.soldiers():
		default_soldiers.append(u.position)
	for sq: SquadState in demo.sim.state.all_squads():
		_stations[sq.id] = sq.station_objective
	_pause_ai(true)
	brain.enabled = false
	demo.sim.vehicles.router.ensure_built()
	var before := _metrics_snapshot()
	_log_n1("setup", {
		"world": demo.config.world_name,
		"scene": "res://scenes/game/world_ref_20km.tscn",
		"godot": Engine.get_version_info().get("string", "unknown"),
		"road_nodes": demo.sim.vehicles.router.node_count(),
		"strategic_grid": [ws.routes.size.x, ws.routes.size.y],
		"requested": Array(only) if not only.is_empty() else IDS,
	})
	for id in IDS:
		if _want(id):
			await _run_case(id)
	var cpu := await _cpu_sample(4.0)
	results["baseline"] = _metrics_delta(before, _metrics_snapshot())
	results["baseline"]["cpu"] = cpu
	results["baseline"]["vehicle_plan_percentiles_ms"] = _percentiles(_plan_samples)
	results["case_status"] = _case_status
	await _cleanup_test_structures()
	await _fresh()
	brain.enabled = true
	TimeCompression.reset()
	while demo.navigation.has_pending_bake() or demo.detail._rebake_in >= 0.0:
		await _seconds(0.2)
	await _seconds(0.5)
	_finish_n1()


func _want(id: String) -> bool:
	return only.is_empty() or only.has(id)


func _run_case(id: String) -> void:
	var data := {}
	match id:
		"n1_01": data = await _n1_01()
		"n1_02": data = await _n1_02()
		"n1_03": data = await _n1_03()
		"n1_04": data = await _n1_04()
		"n1_05": data = await _n1_05()
		"n1_06": data = _n1_06()
		"n1_07": data = await _n1_07()
		"n1_08": data = await _n1_08()
		"n1_09": data = await _n1_09()
		"n1a_10": data = await _n1a_10()
		"n1a_11": data = await _n1a_11()
	_log_n1(id, data)


func _classify(id: String, status: String, data: Dictionary, note := "") -> Dictionary:
	data["status"] = status
	data["note"] = note
	_case_status[id] = status
	return data


func _log_n1(check: String, data: Dictionary) -> void:
	results[check] = data
	print("NAV_N1 %s %s" % [check, JSON.stringify(data)])


func _finish_n1() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["harness_failures"] = failures
	results["harness_pass"] = failures.is_empty()
	var dir := "user://navigation_n1"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/navigation_n1_test.json"
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("NAV_N1 %s %s" % ["COMPLETE" if failures.is_empty() else "HARNESS_FAIL", JSON.stringify({"cases": _case_status, "failures": failures, "output": path})])
	demo.shutdown_cleanup()
	tree.quit()


# --- Shared infantry setup -----------------------------------------------------------------

func _find_site() -> Vector3:
	if _site.is_finite():
		return _site
	var origin := _obj("North HQ").position
	var probe := StructureCatalog.get_def(&"barracks_block")
	for r: float in [350.0, 500.0, 650.0, 800.0, 950.0, 1150.0]:
		for k in 24:
			var a := TAU * float(k) / 24.0
			var c := demo.on_ground(origin.x + cos(a) * r, origin.z + sin(a) * r, 0.0)
			if not sm._ids_in(Rect2(Vector2(c.x, c.z), Vector2.ZERO).grow(130.0)).is_empty():
				continue
			var ok := true
			for off in [Vector3.ZERO, Vector3(75, 0, 65), Vector3(-75, 0, 65), Vector3(75, 0, -65), Vector3(-75, 0, -65)]:
				var p: Vector3 = c + off
				if not ws.routes.passable(p) or sm.water_height(p.x, p.z) > demo.ground_height(p) + 0.2:
					ok = false
					break
			if not ok:
				continue
			var chk := sm.check_building(probe, c, 0.0, -1, true)
			if chk.ok:
				_site = chk.xform.origin
				return _site
	_expect(false, "N1: no open diagnostic site found")
	return Vector3.INF


func _ground(p: Vector3) -> Vector3:
	return demo.on_ground(p.x, p.z, 0.0)


func _line(type_id: StringName, pts: Array) -> StructureState:
	var grounded := PackedVector3Array()
	for p: Vector3 in pts:
		grounded.append(_ground(p))
	var s := cs.add_line(type_id, grounded, PackedInt32Array(), 0)
	await _physics(3)
	return s


func _building(type_id: StringName, pos: Vector3, yaw := 0.0, validate := true) -> StructureState:
	var p := _ground(pos)
	if validate:
		var chk := sm.check_building(StructureCatalog.get_def(type_id), p, yaw, -1, true)
		if not chk.ok:
			return null
		p = chk.xform.origin
	var s := cs.add_building(type_id, p, yaw, 0)
	await _physics(3)
	return s


func _remove_structures(list: Array) -> void:
	for s: StructureState in list:
		if s:
			cs.remove(s.id)
	await _wait_navigation()


func _cleanup_test_structures() -> void:
	var c := _find_site()
	if not c.is_finite():
		return
	var remove := []
	for s: StructureState in cs.all():
		var p := s.position
		if s.is_line() and not s.points.is_empty():
			p = s.points[0]
		if _flat(p, c) < 180.0:
			remove.append(s)
	await _remove_structures(remove)


func _wait_navigation() -> void:
	await _seconds(1.2)
	var t0 := Time.get_ticks_msec()
	while (demo.navigation.has_pending_bake() or demo.detail._rebake_in >= 0.0) and Time.get_ticks_msec() - t0 < 20000:
		await _seconds(0.2)


func _watch_squad(sq: SquadState, goal: Vector3, sim_s: float, scale: float, wall_z := INF, shot_name := "") -> Dictionary:
	var track := {"last": {}, "last_t": {}, "stall_max_s": 0.0, "inside_blocking_samples": 0, "samples": 0,
		"crossed_wall": false, "shot": false}
	var t0 := demo.sim.state.time
	var rep0 := demo.sim.squads.route_replanned
	var skip0 := demo.sim.squads.route_skips
	var stall0 := demo.sim.squads.route_stall_events
	var react0 := demo.sim.squads.route_stall_while_reacting
	var member0 := demo.sim.squads.member_recoveries
	var member_fail0 := demo.sim.squads.member_failures
	var local0: Dictionary = demo.sim.local_nav_stats.duplicate(true)
	var w := await _warp(sim_s, scale, 180.0, func() -> bool:
		if shots and shot_name != "" and not track.shot and demo.sim.state.time - t0 >= 5.0:
			_shot(shot_name)
			track.shot = true
		var terminal := true
		for id in sq.members:
			var u := _u(id)
			if u == null or not u.alive:
				continue
			track.samples += 1
			if sm.blocks_point(Vector2(u.position.x, u.position.z), 0.2):
				track.inside_blocking_samples += 1
			if wall_z != INF and _gate_x != INF and absf(u.position.z - wall_z) < 4.0 and absf(u.position.x - _gate_x) < 12.0:
				track.crossed_wall = true
			var prev: Vector3 = track.last.get(id, Vector3.INF)
			if not prev.is_finite() or _flat(prev, u.position) > 1.0:
				track.last[id] = u.position
				track.last_t[id] = demo.sim.state.time
			elif u.has_order():
				track.stall_max_s = maxf(float(track.stall_max_s), demo.sim.state.time - float(track.last_t.get(id, demo.sim.state.time)))
			if u.order == UnitState.Order.MOVE or (u.move_state != UnitState.MoveState.ARRIVED and u.move_state != UnitState.MoveState.BLOCKED):
				terminal = false
		return terminal)
	var arrived := 0
	var blocked := 0
	var bodies := 0
	var dists := []
	var target_dists := []
	var members := []
	for id in sq.members:
		var u := _u(id)
		if u == null:
			continue
		var d := _flat(u.position, goal)
		var td := _flat(u.position, u.order_target)
		dists.append(snappedf(d, 0.1))
		target_dists.append(snappedf(td, 0.1))
		var reached := u.order == UnitState.Order.NONE and u.move_state == UnitState.MoveState.ARRIVED \
			and td <= 3.1 and d <= 20.0
		arrived += 1 if reached else 0
		blocked += 1 if u.move_state == UnitState.MoveState.BLOCKED else 0
		bodies += 1 if u.has_body else 0
		members.append({"id": id, "pos": [snappedf(u.position.x, 0.1), snappedf(u.position.z, 0.1)],
			"target": [snappedf(u.order_target.x, 0.1), snappedf(u.order_target.z, 0.1)],
			"centre_m": snappedf(d, 0.1), "target_m": snappedf(td, 0.1),
			"order": u.order, "move_state": u.move_state, "reason": u.nav_reason})
	return {
		"arrived": arrived, "of": sq.members.size(), "blocked": blocked, "bodies_at_end": bodies,
		"time_s": snappedf(demo.sim.state.time - t0, 1.0), "real_s": w.real_s,
		"dist_m": dists, "target_dist_m": target_dists, "members": members,
		"stall_max_s": snappedf(track.stall_max_s, 0.1),
		"inside_blocking_samples": track.inside_blocking_samples, "samples": track.samples,
		"crossed_wall": track.crossed_wall,
		"route_replans": demo.sim.squads.route_replanned - rep0,
		"route_skips": demo.sim.squads.route_skips - skip0,
		"route_stalls": demo.sim.squads.route_stall_events - stall0,
		"stalls_while_reacting": demo.sim.squads.route_stall_while_reacting - react0,
		"member_recoveries": demo.sim.squads.member_recoveries - member0,
		"member_failures": demo.sim.squads.member_failures - member_fail0,
		"local_searches": int(demo.sim.local_nav_stats.searches) - int(local0.searches),
		"local_successes": int(demo.sim.local_nav_stats.successes) - int(local0.successes),
		"local_failures": int(demo.sim.local_nav_stats.failures) - int(local0.failures),
		"local_cache_hits": int(demo.sim.local_nav_stats.cache_hits) - int(local0.cache_hits),
		"local_plan_ms_mean": snappedf((float(demo.sim.local_nav_stats.plan_ms_total) - float(local0.plan_ms_total)) \
			/ maxf(float(int(demo.sim.local_nav_stats.searches) - int(local0.searches)), 1.0), 0.01),
		"local_plan_ms_max": snappedf(float(demo.sim.local_nav_stats.plan_ms_max), 0.01),
	}


func _march(sq: SquadState, goal: Vector3, near: bool, sim_s := 240.0, wall_z := INF, shot_name := "") -> Dictionary:
	if near:
		demo.rts_camera.frame(goal.lerp(ws.squad_center(sq), 0.5), 0.0, 80.0 if shots else 105.0)
	else:
		demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	await _seconds(2.0)
	var bodies0 := 0
	for id in sq.members:
		bodies0 += 1 if _u(id).has_body else 0
	demo.sim.squads.order_move([sq.id], goal)
	var out := await _watch_squad(sq, goal, sim_s, 10.0 if near else 16.0, wall_z, shot_name)
	out["tier_requested"] = "near" if near else "far"
	out["bodies_at_start"] = bodies0
	return out


# --- N1-01 / N1-02 / N1-08 / N1-09: infantry -----------------------------------------------

func _n1_01() -> Dictionary:
	await _fresh()
	await _cleanup_test_structures()
	var c := _find_site()
	var b := await _building(&"barracks_block", c)
	if b == null:
		_expect(false, "N1-01: building precondition failed")
		return _classify("n1_01", "ERROR", {"reason": "building could not be placed"})
	await _wait_navigation()
	var sq := _spawn(0, c + Vector3(0, 0, 55), 8)
	var move: Dictionary = await _march(sq, c + Vector3(0, 0, -55), true, 180.0, INF, "n1a_building_detour")
	await _remove_structures([b])
	var passed: bool = move.arrived >= 6 and move.inside_blocking_samples == 0 and move.stall_max_s < 90.0
	return _classify("n1_01", "PASS" if passed else "FAIL", {"movement": move, "obstacle": "barracks_block"},
		"Near-tier NavigationAgent3D must route the squad around a blocking building.")


func _gate_results() -> Dictionary:
	if not _gate_cache.is_empty():
		return _gate_cache
	await _fresh()
	await _cleanup_test_structures()
	var c := _find_site()
	var hx := 75.0
	var hz := 65.0
	_gate_x = c.x + 6.0
	var walls := []
	walls.append(await _line(&"hesco", [c + Vector3(-hx, 0, hz), c + Vector3(-hx, 0, -hz), c + Vector3(hx, 0, -hz), c + Vector3(hx, 0, hz)]))
	walls.append(await _line(&"fence", [c + Vector3(-hx, 0, hz), c + Vector3(-2.1, 0, hz)]))
	walls.append(await _line(&"fence", [c + Vector3(14.0, 0, hz), c + Vector3(hx, 0, hz)]))
	var hq := await _building(&"hq_building", c + Vector3(0, 0, -30), 0.0, false)
	var blocker := await _line(&"fence", [c + Vector3(-2.1, 0, hz), c + Vector3(14.0, 0, hz)])
	await _wait_navigation()
	var closed_near_sq := _spawn(0, c + Vector3(6, 0, 112), 8)
	var closed_near := await _march(closed_near_sq, c + Vector3(0, 0, 20), true, 90.0, c.z + hz)
	await _fresh()
	var closed_far_sq := _spawn(0, c + Vector3(0, 0, -115), 8)
	var closed_far := await _march(closed_far_sq, c + Vector3(0, 0, 20), false, 120.0, c.z + hz)
	await _fresh()
	cs.remove(blocker.id)
	await _wait_navigation()
	var near_sq := _spawn(0, c + Vector3(6, 0, 112), 8)
	var near := await _march(near_sq, c + Vector3(0, 0, 20), true, 240.0, c.z + hz, "n1a_open_gate")
	await _fresh()
	var far_sq := _spawn(0, c + Vector3(0, 0, -115), 8)
	var far := await _march(far_sq, c + Vector3(0, 0, 20), false, 600.0, c.z + hz)
	await _remove_structures(walls + [hq])
	_gate_cache = {"closed_near": closed_near, "closed_far": closed_far, "open_near": near, "open_far": far,
		"gate": [snappedf(c.x + 6.0, 0.1), snappedf(c.z + hz, 0.1)], "opening_m": 16.1}
	return _gate_cache


func _n1_02() -> Dictionary:
	var g: Dictionary = await _gate_results()
	var closed_ok: bool = g.closed_near.arrived == 0 and g.closed_far.arrived == 0 and g.closed_near.inside_blocking_samples == 0 and g.closed_far.inside_blocking_samples == 0
	var open_ok: bool = g.open_near.arrived == 8 and g.open_far.arrived == 8 \
		and g.open_near.stall_max_s < 25.0 and g.open_far.stall_max_s < 25.0 \
		and g.open_near.inside_blocking_samples == 0 and g.open_far.inside_blocking_samples == 0
	return _classify("n1_02", "PASS" if closed_ok and open_ok else "FAIL", g.duplicate(true),
		"Closed perimeter must remain impassable; the opening must work in both tiers.")


func _n1_08() -> Dictionary:
	var g: Dictionary = await _gate_results()
	var reproduced: bool = g.open_far.arrived < 8 or g.open_far.stall_max_s >= 25.0
	return _classify("n1_08", "FAIL" if reproduced else "PASS", {"far_defence_line": g.open_far, "reproduced": reproduced},
		"Far-tier infantry must refine its route through the valid opening without crossing the defence line.")


func _n1_09() -> Dictionary:
	var g: Dictionary = await _gate_results()
	var n: Dictionary = g.open_near
	var f: Dictionary = g.open_far
	var near_reliable: bool = n.arrived == 8 and n.stall_max_s < 25.0
	var far_reliable: bool = f.arrived == 8 and f.stall_max_s < 25.0
	var reachable: bool = near_reliable and far_reliable
	return _classify("n1_09", "PASS" if reachable else "FAIL", {
		"near": n, "far": f, "reachability_equal": near_reliable == far_reliable,
		"near_reliable": near_reliable, "far_reliable": far_reliable,
		"time_ratio_far_over_near": snappedf(float(f.time_s) / maxf(float(n.time_s), 0.1), 0.01),
		"same_passage": n.crossed_wall and f.crossed_wall,
	}, "Movement time may differ; valid-goal reachability must not depend on simulation tier.")


## N1-A transition acceptance: the same order crosses both tier boundaries and survives
## an in-place save/load. Per-frame displacement is recorded to reject teleport fixes.
func _n1a_10() -> Dictionary:
	await _fresh()
	await _cleanup_test_structures()
	var c := _find_site()
	var near_far_sq := _spawn(0, c + Vector3(120, 0, 60), 8)
	var near_far := await _transition_march(near_far_sq, c + Vector3(120, 0, -60), true, false)
	await _fresh()
	var far_near_sq := _spawn(0, c + Vector3(120, 0, 60), 8)
	var far_near := await _transition_march(far_near_sq, c + Vector3(120, 0, -60), false, true, true)
	var passed: bool = near_far.arrived == 8 and far_near.arrived == 8 \
		and near_far.switched and far_near.switched and far_near.saved \
		and near_far.max_step_m < 5.0 and far_near.max_step_m < 5.0 \
		and near_far.orders_lost == 0 and far_near.orders_lost == 0
	return _classify("n1a_10", "PASS" if passed else "FAIL", {"near_to_far": near_far, "far_to_near_save": far_near},
		"Tier changes and save/load must retain targets and orders without teleporting.")


func _transition_march(sq: SquadState, goal: Vector3, start_near: bool, end_near: bool, do_save := false) -> Dictionary:
	var ids := Array(sq.members)
	var start := ws.squad_center(sq)
	demo.rts_camera.frame(start if start_near else Vector3(9000, 0, -9000), 0.0, 105.0)
	await _seconds(2.0)
	var bodies_start := 0
	for id in ids:
		bodies_start += 1 if _u(id).has_body else 0
	demo.sim.squads.order_move([sq.id], goal)
	var t0 := demo.sim.state.time
	var track := {"switched": false, "saved": false, "lost_ids": {}, "max_step": 0.0, "last": {}}
	await _warp(300.0, 10.0, 180.0, func() -> bool:
		var elapsed := demo.sim.state.time - t0
		if not track.switched and elapsed >= 8.0:
			demo.rts_camera.frame(goal if end_near else Vector3(9000, 0, -9000), 0.0, 105.0)
			track.switched = true
		if do_save and track.switched and not track.saved and elapsed >= 16.0:
			var snap := demo.sim.state.snapshot()
			demo.sim.state.apply_snapshot(snap)
			track.saved = true
		var terminal := true
		for id in ids:
			var u := _u(id)
			if u == null:
				continue
			var prev: Vector3 = track.last.get(id, u.position)
			track.max_step = maxf(float(track.max_step), _flat(prev, u.position))
			track.last[id] = u.position
			if u.order == UnitState.Order.NONE and u.move_state != UnitState.MoveState.ARRIVED and u.move_state != UnitState.MoveState.BLOCKED:
				track.lost_ids[id] = true
			if u.order == UnitState.Order.MOVE:
				terminal = false
		return terminal and track.switched and (track.saved or not do_save))
	if shots and end_near:
		demo.rts_camera.frame(ws.squad_center(sq), 0.0, 55.0)
		await _seconds(2.0)
		_shot("n1a_far_promoted_near")
	var arrived := 0
	var bodies_end := 0
	var inside := 0
	var members := []
	for id in ids:
		var u := _u(id)
		if u == null:
			continue
		arrived += 1 if u.move_state == UnitState.MoveState.ARRIVED and _flat(u.position, u.order_target) <= 3.1 else 0
		bodies_end += 1 if u.has_body else 0
		inside += 1 if sm.blocks_point(Vector2(u.position.x, u.position.z), 0.2) else 0
		members.append({"id": id, "state": u.move_state, "order": u.order,
			"target_m": snappedf(_flat(u.position, u.order_target), 0.1), "reason": u.nav_reason})
	return {"arrived": arrived, "of": ids.size(), "bodies_start": bodies_start, "bodies_end": bodies_end,
		"switched": track.switched, "saved": track.saved if do_save else true, "orders_lost": track.lost_ids.size(),
		"max_step_m": snappedf(track.max_step, 0.01), "inside_obstacle_end": inside, "members": members}


## A member legitimately holding a tactical reaction must not spend the navigation
## recovery budget or lose its underlying squad order.
func _n1a_11() -> Dictionary:
	await _fresh()
	await _cleanup_test_structures()
	var c := _find_site() + Vector3(180, 0, 0)
	var sq := _spawn(0, c + Vector3(0, 0, 35), 8)
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	await _seconds(2.0)
	demo.sim.squads.order_move([sq.id], c + Vector3(0, 0, -35))
	var held := _u(sq.members[3])
	held.react_target = held.position
	held.react_state = UnitState.ReactState.ARRIVED
	held.tactic = UnitState.Tactic.IN_COVER
	held.react_until = INF
	var recover0 := demo.sim.squads.member_recoveries
	await _warp(35.0, 16.0, 30.0)
	var preserved := held.order == UnitState.Order.MOVE and held.is_reacting()
	var recovery_during := demo.sim.squads.member_recoveries - recover0
	if shots:
		demo.rts_camera.frame(c, 0.0, 55.0)
		await _seconds(2.0)
		_shot("n1a_member_temporarily_behind")
	held.clear_reaction()
	var move := await _watch_squad(sq, c + Vector3(0, 0, -35), 120.0, 16.0)
	var passed: bool = preserved and recovery_during == 0 and move.arrived == 8
	return _classify("n1a_11", "PASS" if passed else "FAIL", {"order_preserved": preserved,
		"recoveries_during_reaction": recovery_during, "after_reaction": move},
		"A tactical reaction pauses member-stall accounting and the original order resumes afterwards.")


# --- Vehicle helpers and N1-03 / N1-04 / N1-05 / N1-07 -----------------------------------

func _candidate_trip(u: UnitState, min_m := 500.0, max_m := 3500.0, need_bridge := false) -> Dictionary:
	var best := {}
	for o: ObjectiveState in war.all_objectives():
		var res := demo.sim.vehicles.router.plan(u.position, o.position, u.veh.def())
		if res.has("ms"):
			_plan_samples.append(float(res.ms))
		if not res.ok or res.length_m < min_m or res.length_m > max_m or (need_bridge and int(res.bridges) < 1):
			continue
		if best.is_empty() or float(res.length_m) < float(best.plan.length_m):
			best = {"objective": o, "plan": res}
	return best


func _dynamic_vehicle() -> Dictionary:
	if not _dynamic_vehicle_cache.is_empty():
		return _dynamic_vehicle_cache
	await _fresh()
	await _ensure_vehicles(1, 1)
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	if truck == null:
		return {"error": "no free truck"}
	# Keep scenarios independent: N1-03 drives a persistent world vehicle, but N1-04/05
	# must measure the same initial fleet regardless of case order.
	var truck_before := {"position": truck.position, "yaw": truck.yaw, "order": truck.order,
		"order_target": truck.order_target, "move_state": truck.move_state, "veh": truck.veh.to_dict()}
	var trip := _candidate_trip(truck, 600.0, 12000.0)
	if trip.is_empty():
		return {"error": "no suitable trip"}
	var vs := demo.sim.vehicles
	var ordered := vs.order_drive(truck.id, trip.objective.position)
	if not ordered.ok:
		return {"error": ordered.reason}
	var route: PackedVector3Array = truck.veh.route
	var k := clampi(int(route.size() * 0.18), 12, maxi(route.size() - 3, 12))
	var block_pos := route[k]
	var building := await _building(&"barracks_block", block_pos, truck.yaw, false)
	await _physics(5)
	var stats0 := vs.stats.duplicate(true)
	var t0 := demo.sim.state.time
	var max_stall := 0.0
	var stall_since := -1.0
	await _warp(900.0, 16.0, 180.0, func() -> bool:
		if truck.order == UnitState.Order.MOVE and absf(truck.veh.speed) < 0.4:
			if stall_since < 0.0:
				stall_since = demo.sim.state.time
			max_stall = maxf(max_stall, demo.sim.state.time - stall_since)
		else:
			stall_since = -1.0
		return truck.order == UnitState.Order.NONE and absf(truck.veh.speed) < 0.5)
	var arrived := _flat(truck.position, trip.objective.position) < 16.0 and truck.veh.status != VehicleState.Status.BLOCKED
	_dynamic_vehicle_cache = {
		"arrived": arrived, "destination": trip.objective.obj_name,
		"time_s": snappedf(demo.sim.state.time - t0, 1.0), "end_dist_m": snappedf(_flat(truck.position, trip.objective.position), 1.0),
		"block_at": [snappedf(block_pos.x, 0.1), snappedf(block_pos.z, 0.1)], "status": truck.veh.status_name(), "reason": truck.veh.reason,
		"replans": int(vs.stats.replanned) - int(stats0.replanned),
		"bypass_attempts": int(vs.stats.bypass_attempted) - int(stats0.bypass_attempted),
		"bypass_successes": int(vs.stats.bypassed) - int(stats0.bypassed),
		"recoveries": int(vs.stats.recovered) - int(stats0.recovered), "stall_max_s": snappedf(max_stall, 0.1),
		"initial_route": {"length_m": trip.plan.length_m, "road_m": trip.plan.road_m, "offroad_m": trip.plan.offroad_m, "bridges": trip.plan.bridges},
	}
	if building:
		cs.remove(building.id)
	await _wait_navigation()
	truck.position = truck_before.position
	truck.yaw = truck_before.yaw
	truck.order = truck_before.order
	truck.order_target = truck_before.order_target
	truck.move_state = truck_before.move_state
	truck.veh.copy_from(truck_before.veh)
	return _dynamic_vehicle_cache


func _n1_03() -> Dictionary:
	var d := await _dynamic_vehicle()
	return _classify("n1_03", "PASS" if d.get("arrived", false) else "FAIL", {"blocked_road": d},
		"A route blocked after planning should use a valid local bypass or replan when terrain permits.")


func _n1_04() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 1)
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	if truck == null:
		return _classify("n1_04", "ERROR", {"reason": "no truck"})
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var ad := VehicleDefs.get_def(VehicleDefs.APC)
	var rows := []
	var different := 0
	for o: ObjectiveState in war.all_objectives():
		var dist := _flat(truck.position, o.position)
		if dist < 1500.0 or dist > 9000.0:
			continue
		var rt := demo.sim.vehicles.router.plan(truck.position, o.position, td)
		var ra := demo.sim.vehicles.router.plan(truck.position, o.position, ad)
		if rt.has("ms"): _plan_samples.append(float(rt.ms))
		if ra.has("ms"): _plan_samples.append(float(ra.ms))
		if not rt.ok or not ra.ok:
			rows.append({"to": o.obj_name, "truck_ok": rt.ok, "apc_ok": ra.ok, "truck_reason": rt.get("reason", ""), "apc_reason": ra.get("reason", "")})
			continue
		if absf(float(rt.offroad_m) - float(ra.offroad_m)) > 25.0 or absf(float(rt.length_m) - float(ra.length_m)) > 25.0:
			different += 1
		rows.append({"to": o.obj_name, "truck_m": snappedf(rt.length_m, 1.0), "truck_offroad_m": snappedf(rt.offroad_m, 1.0),
			"apc_m": snappedf(ra.length_m, 1.0), "apc_offroad_m": snappedf(ra.offroad_m, 1.0), "truck_ms": rt.ms, "apc_ms": ra.ms})
		if rows.size() >= 8:
			break
	var profiles := {
		"truck": {"width_m": td.width, "turn_radius_m": td.wheelbase / tan(td.max_steer), "max_grade": td.max_grade, "offroad_factor": td.offroad_factor, "offroad_speed_ms": td.offroad_speed},
		"wheeled_apc": {"width_m": ad.width, "turn_radius_m": ad.wheelbase / tan(ad.max_steer), "max_grade": ad.max_grade, "offroad_factor": ad.offroad_factor, "offroad_speed_ms": ad.offroad_speed},
		"tracked_future": {"implemented": false, "needed": ["lower offroad cost", "vehicle-specific slope", "width/length", "minimum turn or pivot capability", "bridge width/load"]},
	}
	var passed := rows.size() >= 3 and different > 0
	return _classify("n1_04", "PASS" if passed else "FAIL", {"profiles": profiles, "routes": rows, "different_choices": different},
		"Truck and wheeled APC use the same world data with distinct movement profiles.")


func _n1_05() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 3)
	var ids := []
	for u: UnitState in _vehicles_of(1):
		if ids.size() < 3 and u.alive and u.veh.assign_kind == "" and u.order == UnitState.Order.NONE:
			ids.append(u.id)
	if ids.size() < 3:
		return _classify("n1_05", "ERROR", {"reason": "fewer than three free vehicles"})
	var lead := _u(ids[0])
	var trip := _candidate_trip(lead, 800.0, 12000.0, true)
	if trip.is_empty():
		return _classify("n1_05", "ERROR", {"reason": "no bridge route found"})
	var cr := demo.sim.vehicles.convoy.order_convoy(ids, trip.objective.position, "N1 bridge convoy")
	if not cr.ok:
		return _classify("n1_05", "FAIL", {"formed": false, "reason": cr.reason, "failed": cr.get("failed", [])})
	var on_bridge := {}
	var stopped_since := {}
	var stall_max := 0.0
	var t0 := demo.sim.state.time
	await _warp(1800.0, 20.0, 240.0, func() -> bool:
		var active := 0
		for id in ids:
			var u := _u(id)
			if u == null:
				continue
			if not is_nan(demo.sim.state.roads.deck_height(u.position)):
				on_bridge[id] = true
			if u.order == UnitState.Order.MOVE:
				active += 1
				if absf(u.veh.speed) < 0.4:
					if not stopped_since.has(id): stopped_since[id] = demo.sim.state.time
					stall_max = maxf(stall_max, demo.sim.state.time - float(stopped_since[id]))
				else:
					stopped_since.erase(id)
		return active == 0)
	var arrived := 0
	var rows := []
	for id in ids:
		var u := _u(id)
		var d := _flat(u.position, trip.objective.position)
		arrived += 1 if d < 45.0 and u.veh.status != VehicleState.Status.BLOCKED else 0
		rows.append({"id": id, "distance_m": snappedf(d, 1.0), "status": u.veh.status_name(), "reason": u.veh.reason, "crossed_bridge": on_bridge.has(id)})
	var cid := int(cr.convoy)
	demo.sim.vehicles.convoy.stop(cid)
	var passed := arrived == ids.size() and on_bridge.size() == ids.size()
	return _classify("n1_05", "PASS" if passed else "FAIL", {"formed": true, "destination": trip.objective.obj_name,
		"planned_bridges": trip.plan.bridges, "arrived": arrived, "of": ids.size(), "vehicles": rows,
		"stall_max_s": snappedf(stall_max, 1.0), "time_s": snappedf(demo.sim.state.time - t0, 1.0),
		"capacity_logic_present": false}, "Current convoy spacing is tested; bridge width/capacity is not represented.")


func _n1_06() -> Dictionary:
	return _classify("n1_06", "UNSUPPORTED", {
		"expected_unsupported": true,
		"observed": "Bridges are inferred from road/deck geometry and have no persistent enabled/disabled route entity.",
		"diagnostic": "No supported API can invalidate one bridge without changing road or structure data.",
	}, "Do not implement bridge destruction in N1.")


func _n1_07() -> Dictionary:
	await _fresh()
	await _cleanup_test_structures()
	var c := _find_site()
	var sq := _spawn(0, c + Vector3(0, 0, 70), 8)
	demo.rts_camera.frame(c, 0.0, 110.0)
	await _seconds(2.0)
	demo.sim.squads.order_move([sq.id], c + Vector3(0, 0, -70))
	await _warp(3.0, 1.0, 10.0)
	var b := await _building(&"barracks_block", c, 0.0, false)
	await _wait_navigation()
	var infantry: Dictionary = await _watch_squad(sq, c + Vector3(0, 0, -70), 240.0, 10.0)
	if b: cs.remove(b.id)
	await _wait_navigation()
	var vehicle: Dictionary = await _dynamic_vehicle()
	var passed: bool = infantry.arrived >= 6 and vehicle.get("arrived", false)
	return _classify("n1_07", "PASS" if passed else "FAIL", {"infantry": infantry, "vehicle": vehicle,
		"invalidation": {"strategic_grid_updates_for_structure": false, "vehicle_fail_cache_cleared": true, "near_navmesh_rebaked": true}},
		"A newly placed structure must invalidate or locally refine every affected route.")


# --- Metrics ---------------------------------------------------------------------------------

func _metrics_snapshot() -> Dictionary:
	var r: StrategicRoutes = ws.routes
	var vr: VehicleRouter = demo.sim.vehicles.router
	return {
		"time": demo.sim.state.time,
		"strategic": {"plans": r.routes_planned, "failed": r.routes_failed, "ms_total": r.route_ms_total, "ms_max": r.route_ms_max,
			"failure_reasons": r.failure_reasons.duplicate(true), "last_failure": r.last_failure.duplicate(true)},
		"vehicle": {"plans": vr.plans, "failed": vr.failed_plans, "ms_total": vr.plan_ms_total, "ms_max": vr.plan_ms_max,
			"failure_reasons": vr.failure_reasons.duplicate(true), "last_failure": vr.last_failure.duplicate(true),
			"graph_builds": vr.graph_builds, "graph_rebuilds": vr.graph_rebuilds, "graph_ms_total": vr.graph_ms_total,
			"graph_ms_max": vr.graph_ms_max, "last_rebuild_reason": vr.last_rebuild_reason, "sim_stats": demo.sim.vehicles.stats.duplicate(true)},
		"squads": {"routed_orders": demo.sim.squads.routed_orders, "replanned": demo.sim.squads.route_replanned,
			"skips": demo.sim.squads.route_skips, "stall_events": demo.sim.squads.route_stall_events,
			"stall_while_reacting": demo.sim.squads.route_stall_while_reacting},
		"ticks": demo.sim.tick_usec.duplicate(true),
	}


func _metrics_delta(a: Dictionary, b: Dictionary) -> Dictionary:
	var sp := int(b.strategic.plans) - int(a.strategic.plans)
	var vp := int(b.vehicle.plans) - int(a.vehicle.plans)
	var ticks := maxi(int(b.ticks.ticks) - int(a.ticks.ticks), 1)
	var tick_avg := {}
	for k in ["abstract", "squads", "tactics", "vehicles", "war", "brain", "combat"]:
		tick_avg[k] = snappedf(float(int(b.ticks.get(k, 0)) - int(a.ticks.get(k, 0))) / ticks, 0.1)
	var sim_delta := {}
	for k in b.vehicle.sim_stats:
		sim_delta[k] = int(b.vehicle.sim_stats[k]) - int(a.vehicle.sim_stats.get(k, 0))
	return {
		"simulated_s": snappedf(float(b.time) - float(a.time), 1.0),
		"strategic": {"plans": sp, "failed": int(b.strategic.failed) - int(a.strategic.failed),
			"ms_avg": snappedf((float(b.strategic.ms_total) - float(a.strategic.ms_total)) / maxi(sp, 1), 0.01), "ms_max_ever": b.strategic.ms_max,
			"failure_reasons": b.strategic.failure_reasons, "last_failure": b.strategic.last_failure},
		"vehicle": {"plans": vp, "failed": int(b.vehicle.failed) - int(a.vehicle.failed),
			"ms_avg": snappedf((float(b.vehicle.ms_total) - float(a.vehicle.ms_total)) / maxi(vp, 1), 0.01), "ms_max_ever": b.vehicle.ms_max,
			"failure_reasons": b.vehicle.failure_reasons, "last_failure": b.vehicle.last_failure,
			"graph_builds": int(b.vehicle.graph_builds) - int(a.vehicle.graph_builds), "graph_rebuilds": int(b.vehicle.graph_rebuilds) - int(a.vehicle.graph_rebuilds),
			"graph_ms_total": snappedf(float(b.vehicle.graph_ms_total) - float(a.vehicle.graph_ms_total), 0.01), "graph_ms_max_ever": b.vehicle.graph_ms_max,
			"last_rebuild_reason": b.vehicle.last_rebuild_reason, "movement": sim_delta},
		"squads": {"routed_orders": int(b.squads.routed_orders) - int(a.squads.routed_orders), "replanned": int(b.squads.replanned) - int(a.squads.replanned),
			"skips": int(b.squads.skips) - int(a.squads.skips), "stall_events": int(b.squads.stall_events) - int(a.squads.stall_events),
			"stall_while_reacting": int(b.squads.stall_while_reacting) - int(a.squads.stall_while_reacting)},
		"tick_us_avg": tick_avg, "ticks": ticks,
		"war_update_us_avg_ever": snappedf(float(ws.update_usec) / maxi(ws.updates, 1), 0.1), "war_update_us_max_ever": ws.update_usec_max,
	}


func _cpu_sample(seconds: float) -> Dictionary:
	var ms := PackedFloat32Array()
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		var t0 := Time.get_ticks_usec()
		await tree.process_frame
		ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	return _percentiles(Array(ms))


func _percentiles(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "avg": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var v := values.duplicate()
	v.sort()
	var sum := 0.0
	for x in v: sum += float(x)
	return {"n": v.size(), "avg": snappedf(sum / v.size(), 0.01),
		"p95": snappedf(float(v[mini(int(v.size() * 0.95), v.size() - 1)]), 0.01),
		"p99": snappedf(float(v[mini(int(v.size() * 0.99), v.size() - 1)]), 0.01),
		"max": snappedf(float(v[-1]), 0.01)}

## NAV-PERF-01B+C: incremental route planning, road connectivity and AI movement integration.
##
##   Godot.exe --path . --resolution 1600x900 --log-file navperf.log \
##     res://scenes/game/world_ref_20km.tscn -- --nav-perf-bc-test [--only b_strat,b_local,b_burst] [--shots] [--tag=name]
##
## Output: user://nav_perf_bc/nav_perf_bc_<tag>.json. The "b_*" cases are the cost measurements (run on the baseline and on the new
## code through the same public calls); the other cases are the milestone's acceptance checks.
class_name NavPerfBCSelfTest
extends NavInf01SelfTest

const IDS_P: Array[String] = ["b_strat", "b_local", "b_burst", "b_op", "b_vehicle", "b_vburst", "b_roads", "a_service", "c_pending", "c_vehicle", "c_ops", "c_loop",
	"c_bridge", "e_persist", "d_load", "d_load50", "d_long", "d_haugen", "z_visual", "b_settlement"]
var _tag := "run"
## Named places of ref_20km (sites.json settlements and plateaus), filled by _load_places.
var places := {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "user://nav_perf_bc/screenshots"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
		if a.begins_with("--tag="):
			_tag = a.trim_prefix("--tag=")
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
	tree.create_timer(3600.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: nav-perf-bc test did not finish")
		_finish_p())
	await _physics(60)
	_load_world_data()
	_load_places()
	_pause_ai(true)
	brain.enabled = false
	demo.sim.vehicles.router.ensure_built()
	for id in IDS_P:
		if only.has(id) or (only.is_empty() and not id.begins_with("b_") and id != "z_visual"):
			_open_all_bridges()
			var data := {}
			if has_method("_" + id):
				data = await call("_" + id)
			else:
				data = {"status": "ERROR", "reason": "not implemented"}
			_log_p(id, data)
	_open_all_bridges()
	_finish_p()


func _log_p(check: String, data: Dictionary) -> void:
	results[check] = data
	if data.has("status"):
		_case_status[check] = data.status
	print("NAV_PERF_BC %s %s" % [check, JSON.stringify(data)])


func _finish_p() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["tag"] = _tag
	results["harness_failures"] = failures
	results["case_status"] = _case_status
	var dir := "user://nav_perf_bc"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/nav_perf_bc_%s.json" % _tag
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("NAV_PERF_BC %s %s" % ["COMPLETE" if failures.is_empty() else "HARNESS_FAIL", JSON.stringify({"cases": _case_status, "failures": failures, "output": path})])
	demo.shutdown_cleanup()
	tree.quit()


func _load_places() -> void:
	var src := "res://worlds/%s/source/" % demo.config.world_name
	var sites: Variant = JSON.parse_string(FileAccess.get_file_as_string(src + "sites.json"))
	if not sites is Dictionary:
		return
	for key in ["settlements", "plateaus"]:
		for s: Dictionary in sites.get(key, []):
			var p: Array = s.get("pos", s.get("center", []))
			if p.size() >= 3:
				places[String(s.name)] = demo.on_ground(float(p[0]), float(p[2]), 0.0)


## A passable ground point at a named place (the place itself, or the nearest passable strategic cell).
func _spot(n: String) -> Vector3:
	var p: Vector3 = places.get(n, Vector3.INF)
	if not p.is_finite():
		var o := _obj(n)
		p = o.position if o else Vector3.INF
	if p.is_finite() and not ws.routes.passable(p):
		var c := ws.routes.nearest_passable(p)
		if c.x >= 0:
			var q := ws.routes.cell_center(c)
			p = demo.on_ground(q.x, q.z, 0.0)
	return p


## Long trips between geographically different areas: [from, to].
const TRIPS := [["Haugen", "Sentrum"], ["Haugen", "Flyslette øst"], ["Sentrum", "Flyslette øst"], ["Nordvik", "Grensen"],
	["Strand", "Fjellmoen"], ["Vestli", "Sletta"], ["Kvernes", "Østre"], ["Verket", "Nordre"], ["Elvetun", "Moen"],
	["Haugen", "Verket"], ["Sentrum", "Østby"], ["Midtmoen", "Bakken"], ["Sørmoen", "Fjellfoten"], ["Vestvatn", "Lia"]]


## Physical check of an infantry route: every leg crosses only passable strategic cells, heights are finite, and no 10 m step of
## a leg off the roads is steeper than the walker allows (sampled on the terrain; deck waypoints and road cells are exempt).
func _route_feasible(r: PackedVector3Array) -> Dictionary:
	var bad_legs := 0
	var nan_h := 0
	var steep := 0
	var worst := 0.0
	var rt := ws.routes
	for i in range(1, r.size()):
		var a := r[i - 1]
		var b := r[i]
		if not rt._leg_clear(a, b):
			bad_legs += 1
		var n := maxi(1, ceili(_flat(a, b) / 10.0))
		var prev := a
		var hp: float = demo.sim._infantry_height(a.x, a.z)
		for k in range(1, n + 1):
			var q := a.lerp(b, float(k) / n)
			var h: float = demo.sim._infantry_height(q.x, q.z)
			if is_nan(h):
				nan_h += 1
				continue
			if not is_nan(hp) and not rt.road[_cell_i(q)] and not rt.road[_cell_i(prev)] and _net().bridge_at(q, 3.0) == null:
				var g := absf(h - hp) / maxf(_flat(prev, q), 0.01)
				worst = maxf(worst, g)
				if g > WorldSim.INFANTRY_MAX_GRADE * 1.25:
					steep += 1
			prev = q
			hp = h
	return {"bad_legs": bad_legs, "nan_heights": nan_h, "steep_10m_steps": steep, "worst_grade": snappedf(worst, 0.01)}


func _cell_i(p: Vector3) -> int:
	var c := ws.routes.world_to_cell(p)
	return clampi(c.y, 0, ws.routes.size.y - 1) * ws.routes.size.x + clampi(c.x, 0, ws.routes.size.x - 1)


# --- Baseline measurements -------------------------------------------------------------------------------

## Strategic infantry routes between named places: total synchronous cost, the native A* call alone, length, waypoints, physical check.
func _b_strat() -> Dictionary:
	var rows := []
	var total: Array = []
	var native: Array = []
	var rt := ws.routes
	for t: Array in TRIPS:
		var a := _spot(t[0])
		var b := _spot(t[1])
		if not a.is_finite() or not b.is_finite():
			rows.append({"trip": t, "error": "unknown place"})
			continue
		var t0 := Time.get_ticks_usec()
		var r := rt.route(a, b, demo.sim.terrain)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var t1 := Time.get_ticks_usec()
		rt.astar.get_id_path(rt.nearest_passable(a), rt.nearest_passable(b))
		var nms := (Time.get_ticks_usec() - t1) / 1000.0
		total.append(ms)
		native.append(nms)
		var row := {"trip": "%s -> %s" % [t[0], t[1]], "straight_km": snappedf(_flat(a, b) / 1000.0, 0.01), "ms": snappedf(ms, 0.01), "native_ms": snappedf(nms, 0.01),
			"waypoints": r.size(), "route_km": snappedf(rt.route_length(r) / 1000.0, 0.01)}
		if r.size() >= 2:
			row.merge(_route_feasible(r))
		rows.append(row)
	return {"status": "INFO", "trips": rows, "total_ms": _percentiles(total), "native_ms": _percentiles(native)}


## Abstract-infantry local plans (the WorldSim refinement) for 30 pairs 120-480 m apart round the map, with the walker's own callbacks.
func _b_local() -> Dictionary:
	var sim := demo.sim
	var ms: Array = []
	var cells: Array = []
	var ok := 0
	var fast_ms: Array = []
	var fast_slices: Array = []
	var fast_slice_max: Array = []
	var mismatch := 0
	var end_mismatch := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n := 0
	var tries := 0
	while n < 30 and tries < 400:
		tries += 1
		var a := Vector3(rng.randf_range(-7000.0, 7000.0), 0.0, rng.randf_range(-7000.0, 7000.0))
		var ang := rng.randf() * TAU
		var d := rng.randf_range(120.0, 480.0)
		var b := a + Vector3(cos(ang), 0.0, sin(ang)) * d
		if not ws.routes.passable(a) or not ws.routes.passable(b):
			continue
		a = demo.on_ground(a.x, a.z, 0.0)
		b = demo.on_ground(b.x, b.z, 0.0)
		var res := LocalRoutePlanner.plan(a, b, WorldSim.INFANTRY_LOCAL_CELL, WorldSim.INFANTRY_LOCAL_MAX_CELLS, WorldSim.INFANTRY_MAX_GRADE,
			func(x: float, z: float) -> float: return sim._infantry_height(x, z),
			func(x: float, z: float) -> bool: return sim._infantry_blocked(x, z), 75.0, 0.55, true, false,
			Callable(sim, "_step_blocked"), 1.0)
		ms.append(float(res.ms))
		cells.append(int(res.cells))
		ok += 1 if res.ok else 0
		n += 1
		# NAV-PERF-01B: the same search with the area-aware tests the game uses now; must give the same route.
		if sim.has_method("_infantry_area"):
			var ctx: Dictionary = sim._infantry_area(LocalRoutePlanner.Search.area_for(a, b, WorldSim.INFANTRY_LOCAL_CELL, 75.0, 0.55))
			var s2 := LocalRoutePlanner.Search.new(a, b, WorldSim.INFANTRY_LOCAL_CELL, WorldSim.INFANTRY_LOCAL_MAX_CELLS, WorldSim.INFANTRY_MAX_GRADE,
				func(x: float, z: float) -> float: return sim._infantry_height_in(x, z, ctx),
				func(x: float, z: float) -> bool: return sim._infantry_blocked_in(x, z, ctx), 75.0, 0.55, true, false,
				Callable(sim, "_step_blocked"), 1.0)
			var slices := 0
			var t0 := Time.get_ticks_usec()
			var worst := 0.0
			while true:
				var s0 := Time.get_ticks_usec()
				var fin := s2.step(s0 + 2000)
				worst = maxf(worst, (Time.get_ticks_usec() - s0) / 1000.0)
				slices += 1
				if fin:
					break
			fast_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
			fast_slices.append(slices)
			fast_slice_max.append(worst)
			if s2.result.ok != res.ok or (res.ok and s2.result.pts != res.pts):
				mismatch += 1
			# The resumable end-cell search against the original on the same grid, stopped every few checks.
			for outward in [true, false]:
				var endp := a if outward else b
				var want := LocalRoutePlanner._end_cell(s2._blocked, s2._nx, s2._nz, s2._lo, s2.cell, endp, Callable(sim, "_step_blocked"), outward)
				var ec := LocalRoutePlanner.EndCell.new(s2._blocked, s2._nx, s2._nz, s2._lo, s2.cell, endp, Callable(sim, "_step_blocked"), outward)
				while not ec.step(Time.get_ticks_usec() + 50):
					pass
				if ec.result != want:
					end_mismatch += 1
	var out := {"status": "INFO", "plans": n, "ok": ok, "ms": _percentiles(ms), "cells": _percentiles(cells)}
	if not fast_ms.is_empty():
		out["area_aware_ms"] = _percentiles(fast_ms)
		out["slices_at_2ms"] = _percentiles(fast_slices)
		out["slice_ms_max"] = _percentiles(fast_slice_max)
		out["route_mismatches"] = mismatch
		out["end_cell_mismatches"] = end_mismatch
	return out


## n squads ordered at once (one call) to places 2-6 km away: the cost of the order call itself, then the frames of the next 40
## simulated seconds (route following, local refinements).
func _burst(n_squads: int) -> Dictionary:
	await _fresh()
	_camera_far()
	var starts := ["Haugen", "Sentrum", "Elvetun", "Skogli", "Midtmoen"]
	var goals := ["Flyslette øst", "Verket", "Østby", "Bakken", "Sørmoen", "Lia"]
	var sqs: Array[SquadState] = []
	for i in n_squads:
		var a := _spot(starts[i % starts.size()]) + Vector3((i / starts.size()) * 30.0, 0.0, 0.0)
		sqs.append(_spawn(0, a, 6))
	await _physics(3)
	var has_routing := "routing" in demo.sim
	if has_routing:
		demo.sim.routing.reset_stats()
	var t0 := Time.get_ticks_usec()
	for i in n_squads:
		demo.sim.squads.order_move([sqs[i].id], _spot(goals[i % goals.size()]))
	var order_ms := (Time.get_ticks_usec() - t0) / 1000.0
	# The first 8 simulated seconds at 1x (what the player sees when the orders go out), then 32 s at 4x.
	var rec1 := _frame_recorder()
	var routed_at := {}
	var t_start := demo.sim.state.time
	var each := func() -> bool:
		for sq in sqs:
			if not sq.route.is_empty() and not routed_at.has(sq.id):
				routed_at[sq.id] = demo.sim.state.time - t_start
		return false
	await _warp(8.0, 1.0, 60.0, func() -> bool:
		_frame_tick(rec1)
		return each.call())
	var routing_1x: Dictionary = demo.sim.routing.report() if has_routing else {}
	if has_routing:
		demo.sim.routing.reset_stats()
	var rec4 := _frame_recorder()
	var w := await _warp(32.0, 4.0, 120.0, func() -> bool:
		_frame_tick(rec4)
		return each.call())
	var lat: Array = routed_at.values()
	var out := {"squads": n_squads, "order_call_ms": snappedf(order_ms, 0.1), "routed": routed_at.size(), "route_latency_sim_s": _percentiles(lat),
		"frames_1x": _percentiles(rec1.ms), "frames_4x": _percentiles(rec4.ms), "sim_s": w.sim_s,
		"local": {"searches": demo.sim.local_nav_stats.searches, "plan_ms_max": snappedf(demo.sim.local_nav_stats.plan_ms_max, 0.1),
			"native_astar_max_ms": snappedf(LocalRoutePlanner.native_astar_max_ms, 0.01)}}
	if has_routing:
		out["routing_1x"] = routing_1x
		out["routing_4x"] = demo.sim.routing.report()
	return out


func _d_load50() -> Dictionary:
	var r := await _burst(50)
	r["status"] = "INFO"
	return r


func _b_burst() -> Dictionary:
	var out := {"status": "INFO"}
	for n in [10, 25, 50]:
		out["n%d" % n] = await _burst(n)
	return out


func _vr_warm() -> void:
	var vr := demo.sim.vehicles.router
	vr._plan_cache.clear()
	vr._leg_cache.clear()
	vr._fail_cache.clear()


## Vehicle plans: synchronous (plan()) and, on the new code, resumable (PlanRunner with a 2 ms deadline per step) on the same
## trips with the same warm caches: wall time, steps, the longest step, and whether both give the same route.
func _b_vehicle() -> Dictionary:
	await _fresh()
	var vr := demo.sim.vehicles.router
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var ad := VehicleDefs.get_def(VehicleDefs.APC)
	var trips: Array = []
	var va := _obj("Verket").position
	var vb := _obj("South Bridge").position
	va.y = demo.sim.vehicles.ground_at(va)
	vb.y = demo.sim.vehicles.ground_at(vb)
	trips.append(["Verket -> South Bridge", va, vb, td])
	var dense: Dictionary = await _find_route("forest", 300.0)
	if not dense.is_empty():
		trips.append(["dense woods APC", dense.a, dense.b, ad])
	var names := ["North HQ", "Sentrum", "Haugen", "Centre Bridge", "Elvetun", "South HQ", "Verket", "Østby", "East HQ", "Ødegård"]
	for i in names.size():
		var o1 := _obj(names[i])
		var o2 := _obj(names[(i + 3) % names.size()])
		if o1 and o2:
			var p1 := o1.position
			var p2 := o2.position
			p1.y = demo.sim.vehicles.ground_at(p1)
			p2.y = demo.sim.vehicles.ground_at(p2)
			trips.append(["%s -> %s" % [names[i], names[(i + 3) % names.size()]], p1, p2, td])
	var rows := []
	var sync_ms: Array = []
	var res_ms: Array = []
	var step_max: Array = []
	var mismatch := 0
	var resumable := vr.has_method("_stop")
	for t: Array in trips:
		_vr_warm()
		var t0 := Time.get_ticks_usec()
		var r1 := vr.plan(t[1], t[2], t[3])
		var ms1 := (Time.get_ticks_usec() - t0) / 1000.0
		sync_ms.append(ms1)
		var row := {"trip": t[0], "ok": r1.ok, "sync_ms": snappedf(ms1, 0.1), "km": snappedf(float(r1.get("length_m", 0.0)) / 1000.0, 0.01)}
		if resumable:
			_vr_warm()
			var runner = load("res://scripts/vehicles/vehicle_router.gd").PlanRunner.new(vr, t[1], t[2], t[3], [])
			var steps := 0
			var worst := 0.0
			var t1 := Time.get_ticks_usec()
			while true:
				var s0 := Time.get_ticks_usec()
				var fin: bool = runner.step(s0 + 2000)
				worst = maxf(worst, (Time.get_ticks_usec() - s0) / 1000.0)
				steps += 1
				if fin or steps > 5000:
					break
			var ms2 := (Time.get_ticks_usec() - t1) / 1000.0
			var r2: Dictionary = runner.result
			var same: bool = r2.get("ok", false) == r1.ok and (not r1.ok or r2.points == r1.points)
			if not same:
				mismatch += 1
			res_ms.append(ms2)
			step_max.append(worst)
			row.merge({"resumable_ms": snappedf(ms2, 0.1), "steps": steps, "step_max_ms": snappedf(worst, 0.1), "same_route": same,
				"max_piece": "%s %.1f ms" % [runner.max_piece, runner.max_piece_ms]})
		rows.append(row)
	var out := {"status": "INFO", "trips": rows, "sync_ms": _percentiles(sync_ms),
		"native_max_ms": {"road": snappedf(vr.native_road_astar_max_ms, 0.01), "local": snappedf(vr.native_local_astar_max_ms, 0.01)}}
	if resumable:
		out.merge({"resumable_ms": _percentiles(res_ms), "step_max_ms": _percentiles(step_max), "route_mismatches": mismatch})
	return out


## Six trucks of the player's faction: three ordered as a group (the RTS path) to Verket, three one by one in the same frame to
## Sentrum (on the baseline the production call was order_drive; now it is request_drive). Order calls, frames of the next 10 s
## at 1x, when each truck has its route.
func _b_vburst() -> Dictionary:
	await _fresh()
	_camera_far()
	var trucks: Array = await _trucks(4)
	var ids: Array = trucks.map(func(u: UnitState) -> int: return u.id)
	if ids.size() < 4:
		return {"status": "ERROR", "reason": "%d trucks" % ids.size()}
	_vr_warm()
	demo.sim.routing.reset_stats()
	var rec := _frame_recorder()
	var t0 := Time.get_ticks_usec()
	demo.sim.vehicles.order_group(ids.slice(0, 2), _obj("Verket").position)
	var group_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for i in range(2, 4):
		demo.sim.vehicles.request_drive(ids[i], _obj("Sentrum").position + Vector3(i * 15.0, 0, 0))
	var three_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var routed := {}
	var t_start := demo.sim.state.time
	await _warp(10.0, 1.0, 60.0, func() -> bool:
		_frame_tick(rec)
		for u: UnitState in trucks:
			if u.veh.route.size() >= 2 and not routed.has(u.id):
				routed[u.id] = demo.sim.state.time - t_start
		return false)
	return {"status": "INFO", "group_order_call_ms": snappedf(group_ms, 0.1), "three_orders_call_ms": snappedf(three_ms, 0.1), "routed": routed.size(),
		"route_latency_sim_s": _percentiles(routed.values()), "frames_1x": _percentiles(rec.ms), "routing": demo.sim.routing.report()}


## An AI attack on Haugen with eight squads from ~3 km: the cost of start_operation (it plans every squad's route at once).
func _b_op() -> Dictionary:
	await _fresh()
	_camera_far()
	var hau := _obj("Haugen")
	var a := _near_point(hau.position, _spot("Sentrum"), 3000.0)
	var sqs := []
	for i in 8:
		sqs.append(_spawn(1, a + Vector3((i % 4) * 30.0, 0.0, (i / 4) * 30.0), 6))
	await _physics(3)
	var t0 := Time.get_ticks_usec()
	var op := ws.start_operation(1, OperationState.Type.ATTACK, sqs.map(func(q: SquadState) -> int: return q.id), hau.id)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var out := {"status": "INFO", "start_operation_ms": snappedf(ms, 0.1), "started": op != null}
	if op:
		ws.cancel(op.id, "measured")
	return out


# --- A: RouteService on its own ------------------------------------------------------------------------------------------------

## A test runner: `steps_needed` checkpoints of `spin_us` busy work each; stops at the deadline between checkpoints.
class DummyRunner:
	var steps_needed := 3
	var spin_us := 300
	var done_steps := 0
	var ok := true
	var resets := 0
	var result := {}

	func _init(p_steps := 3, p_spin_us := 300, p_ok := true) -> void:
		steps_needed = p_steps
		spin_us = p_spin_us
		ok = p_ok

	func step(deadline_us: int) -> bool:
		while true:
			var t0 := Time.get_ticks_usec()
			while Time.get_ticks_usec() - t0 < spin_us:
				pass
			done_steps += 1
			if done_steps >= steps_needed:
				result = {"ok": ok, "reason": "" if ok else "dummy: no way", "route": PackedVector3Array([Vector3.ZERO, Vector3.ONE])}
				return true
			if deadline_us > 0 and Time.get_ticks_usec() >= deadline_us:
				return false
		return true

	func reset() -> void:
		done_steps = 0
		resets += 1
		result = {}


func _svc_run(svc: RouteService, frames: int, budget := 2.0) -> Dictionary:
	svc.frame_budget_ms = budget
	var worst := 0.0
	for i in frames:
		var t0 := Time.get_ticks_usec()
		svc.step(1)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		if svc.queue_length() == 0:
			break
	return {"frame_ms_max": snappedf(worst, 0.01)}


## States, callbacks, superseding, reuse of the same request, shared searches, priority, aging, invalidation, the result cache,
## cancelling everything, and the frame budget under a queue of 60 jobs.
func _a_service() -> Dictionary:
	var out := {}
	var ok := true
	var calls := []
	var cb := func(j: RouteService.Job) -> void: calls.append([j.id, j.state, j.owner])
	# 1. States and the callback.
	var svc := RouteService.new()
	var j1 := svc.submit(&"test", "o1", RouteService.Priority.PLAYER, "", DummyRunner.new(20, 300), cb)
	var s0 := j1.state
	svc.frame_budget_ms = 2.0
	var t0 := Time.get_ticks_usec()
	svc.step(1)
	var first_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var s1 := j1.state
	var r := _svc_run(svc, 200)
	var c1 := {"pending_first": s0 == RouteService.State.PENDING, "running_after_one_frame": s1 == RouteService.State.RUNNING,
		"first_frame_ms": snappedf(first_ms, 0.01), "completed": j1.state == RouteService.State.COMPLETED, "slices": j1.slices,
		"callbacks": calls.size(), "frame_ms_max": r.frame_ms_max}
	c1["pass"] = c1.pending_first and c1.running_after_one_frame and c1.completed and c1.callbacks == 1 and j1.slices > 1 and first_ms < 2.0 + 0.6
	out["states"] = c1
	# 2. A search that finds nothing: FAILED, callback with the reason.
	calls.clear()
	var j2 := svc.submit(&"test", "o2", RouteService.Priority.PLAYER, "", DummyRunner.new(2, 100, false), cb)
	_svc_run(svc, 20)
	out["failed"] = {"state": j2.state_name(), "reason": j2.reason, "callbacks": calls.size(),
		"pass": j2.state == RouteService.State.FAILED and calls.size() == 1 and j2.reason != ""}
	# 3. A newer request of the same owner replaces the old one; the old callback never fires.
	calls.clear()
	var j3a := svc.submit(&"test", "sq", RouteService.Priority.PLAYER, "a", DummyRunner.new(40, 300), cb)
	svc.step(1)
	var j3b := svc.submit(&"test", "sq", RouteService.Priority.PLAYER, "b", DummyRunner.new(3, 100), cb)
	_svc_run(svc, 100)
	out["superseded"] = {"old": j3a.state_name(), "new": j3b.state_name(), "callbacks": calls.map(func(c: Array) -> int: return c[0]),
		"pass": j3a.state == RouteService.State.CANCELLED and j3b.state == RouteService.State.COMPLETED and calls.size() == 1 and calls[0][0] == j3b.id}
	# 4. The same request again keeps the search under way (no cancel-and-restart).
	var j4a := svc.submit(&"test", "same", RouteService.Priority.PLAYER, "k", DummyRunner.new(10, 300), cb)
	svc.step(1)
	var j4b := svc.submit(&"test", "same", RouteService.Priority.PLAYER, "k", DummyRunner.new(10, 300), cb)
	_svc_run(svc, 100)
	out["same_again"] = {"same_job": j4a == j4b, "reused": svc.stats.reused_same, "pass": j4a == j4b and j4a.state == RouteService.State.COMPLETED}
	# 5. Two owners, one search: both get the result.
	calls.clear()
	var j5a := svc.submit(&"test", "p", RouteService.Priority.OPERATION, "d", DummyRunner.new(6, 200), cb)
	var j5b := svc.submit(&"test", "q", RouteService.Priority.OPERATION, "d", DummyRunner.new(6, 200), cb)
	_svc_run(svc, 100)
	out["shared"] = {"a": j5a.state_name(), "b": j5b.state_name(), "callbacks": calls.size(), "b_has_result": j5b.result.get("ok", false),
		"pass": j5a.state == RouteService.State.COMPLETED and j5b.state == RouteService.State.COMPLETED and calls.size() == 2 and j5b.leader == j5a}
	# 6. The first of two sharing owners cancels: the other still gets its result.
	calls.clear()
	var j6a := svc.submit(&"test", "p6", RouteService.Priority.OPERATION, "e", DummyRunner.new(12, 300), cb)
	var j6b := svc.submit(&"test", "q6", RouteService.Priority.OPERATION, "e", DummyRunner.new(12, 300), cb)
	svc.step(1)
	svc.cancel(j6a, "test")
	_svc_run(svc, 100)
	out["heir"] = {"a": j6a.state_name(), "b": j6b.state_name(), "callbacks": calls.size(),
		"pass": j6a.state == RouteService.State.CANCELLED and j6b.state == RouteService.State.COMPLETED and calls.size() == 1}
	# 7. Priority: a player request queued after a strategic one runs first.
	var order := []
	var rec := func(j: RouteService.Job) -> void: order.append(j.owner)
	svc.submit(&"test", "strategic", RouteService.Priority.STRATEGIC, "", DummyRunner.new(1, 50), rec)
	svc.submit(&"test", "player", RouteService.Priority.PLAYER, "", DummyRunner.new(1, 50), rec)
	_svc_run(svc, 10)
	out["priority"] = {"order": order.duplicate(), "pass": order == ["player", "strategic"]}
	# 8. Aging: a strategic request that waited long enough goes before a new player request.
	order.clear()
	svc.aging_s = 0.05
	svc.submit(&"test", "old_strategic", RouteService.Priority.STRATEGIC, "", DummyRunner.new(1, 50), rec)
	var tw := Time.get_ticks_usec()
	while Time.get_ticks_usec() - tw < 300000:
		pass
	svc.submit(&"test", "new_player", RouteService.Priority.PLAYER, "", DummyRunner.new(1, 50), rec)
	_svc_run(svc, 10)
	svc.aging_s = 1.5
	out["aging"] = {"order": order.duplicate(), "pass": order == ["old_strategic", "new_player"]}
	# 9. The world changes under a running search: INVALIDATED, it starts again and finishes; a change elsewhere does not touch it.
	var dr9 := DummyRunner.new(20, 300)
	var j9 := svc.submit(&"test", "inv", RouteService.Priority.PLAYER, "", dr9, cb, Vector3.ZERO, Vector3.ZERO, Rect2(0, 0, 100, 100))
	svc.step(1)
	var inv0: int = svc.stats.invalidated
	svc.invalidate("far away", Rect2(5000, 5000, 10, 10))
	var untouched := dr9.resets == 0
	svc.invalidate("test change", Rect2(50, 50, 10, 10))
	_svc_run(svc, 100)
	out["invalidated"] = {"restarts": j9.restarts, "runner_resets": dr9.resets, "untouched_by_far_change": untouched, "counted": svc.stats.invalidated - inv0,
		"state": j9.state_name(), "pass": untouched and j9.restarts == 1 and dr9.resets == 1 and j9.state == RouteService.State.COMPLETED}
	# 10. A finished infantry route is reused until the world changes.
	var j10 := svc.submit(&"infantry", "c1", RouteService.Priority.PLAYER, "inf:cache", DummyRunner.new(2, 50), cb)
	_svc_run(svc, 10)
	var hits0: int = svc.stats.cache_hits
	var j10b := svc.submit(&"infantry", "c2", RouteService.Priority.PLAYER, "inf:cache", DummyRunner.new(2, 50), cb)
	var hit: bool = j10b.is_done() and svc.stats.cache_hits == hits0 + 1
	svc.invalidate("roads changed")
	var j10c := svc.submit(&"infantry", "c3", RouteService.Priority.PLAYER, "inf:cache", DummyRunner.new(2, 50), cb)
	out["cache"] = {"hit": hit, "after_change_pending": not j10c.is_done(), "pass": j10.ok() and hit and not j10c.is_done()}
	_svc_run(svc, 10)
	# 11. Everything cancelled (a load).
	for k in 5:
		svc.submit(&"test", "x%d" % k, RouteService.Priority.STRATEGIC, "", DummyRunner.new(5, 100), cb)
	svc.cancel_all("test")
	out["cancel_all"] = {"queue": svc.queue_length(), "pass": svc.queue_length() == 0}
	# 12. 60 jobs, 2 ms per frame: no frame much over budget, the queue drains, every job finishes.
	var svc2 := RouteService.new()
	var done := [0]
	for k in 60:
		svc2.submit(&"test", "load%d" % k, k % 5, "", DummyRunner.new(10, 300), func(_j: RouteService.Job) -> void: done[0] += 1)
	var r12 := _svc_run(svc2, 2000)
	out["budget_60_jobs"] = {"frame_ms_max": r12.frame_ms_max, "done": done[0], "frames": svc2.stats.frames_with_work, "queue_max": svc2.queue_max,
		"wait_ms": RouteService.percentiles(svc2.wait_samples), "pass": done[0] == 60 and r12.frame_ms_max <= 2.0 + 0.3 + 0.5}
	for k in out:
		ok = ok and bool(out[k].get("pass", false))
	out["status"] = "PASS" if ok else "FAIL"
	return out


# --- C: integration ------------------------------------------------------------------------------------------------------------

func _frames_until(cond: Callable, max_frames: int) -> int:
	for i in max_frames:
		if cond.call():
			return i
		await tree.process_frame
	return -1


func _route_end(sq: SquadState) -> Vector3:
	return sq.route[sq.route.size() - 1] if not sq.route.is_empty() else Vector3.INF


## Infantry: an order's route is pending (the squad waits, MOVING, no failure), arrives, a newer order replaces a pending one and
## its result is never applied, a Hold while pending drops it, and an operation does not end while its routes are being planned.
func _c_pending() -> Dictionary:
	await _fresh()
	_camera_far()
	var squads := demo.sim.squads
	var a := _spot("Haugen")
	var sq := _spawn(0, a, 6)
	await _physics(3)
	var out := {}
	var b := _spot("Sentrum")
	squads.order_move([sq.id], b)
	var p := {"route_empty_at_order": sq.route.is_empty(), "waiting": squads.route_waiting(sq), "status_moving": sq.status == SquadState.Status.MOVING}
	var fr: int = await _frames_until(func() -> bool: return not sq.route.is_empty(), 600)
	p["frames_to_route"] = fr
	p["route_end_to_goal_m"] = snappedf(_flat(_route_end(sq), b), 0.1)
	p["pass"] = p.route_empty_at_order and p.waiting and p.status_moving and fr >= 0 and p.route_end_to_goal_m < 1.0
	out["pending_then_route"] = p
	# A newer order while the first is pending.
	await _fresh()
	sq = _spawn(0, a, 6)
	await _physics(3)
	var sup0: int = demo.sim.routing.stats.superseded
	var g1 := _spot("Verket")
	var g2 := _spot("Elvetun")
	squads.order_move([sq.id], g1)
	squads.order_move([sq.id], g2)
	fr = await _frames_until(func() -> bool: return not sq.route.is_empty(), 600)
	await _physics(30)
	var n := {"frames_to_route": fr, "end_to_new_goal_m": snappedf(_flat(_route_end(sq), g2), 0.1), "end_to_old_goal_m": snappedf(_flat(_route_end(sq), g1), 0.1),
		"superseded": demo.sim.routing.stats.superseded - sup0}
	n["pass"] = fr >= 0 and n.end_to_new_goal_m < 1.0
	out["newer_order_wins"] = n
	# Hold while pending.
	await _fresh()
	sq = _spawn(0, a, 6)
	await _physics(3)
	squads.order_move([sq.id], g1)
	squads.order_hold([sq.id])
	await _physics(60)
	var h := {"route_empty": sq.route.is_empty(), "waiting": squads.route_waiting(sq), "order": sq.order_name()}
	h["pass"] = h.route_empty and not h.waiting and sq.order == SquadState.Order.HOLD
	out["hold_drops_pending"] = h
	# An operation waits for its routes, it does not end.
	await _fresh()
	var sqs := [_spawn(0, a, 6), _spawn(0, a + Vector3(30, 0, 0), 6)]
	await _physics(3)
	var op := ws.start_operation(0, OperationState.Type.MOVE, sqs.map(func(q: SquadState) -> int: return q.id), -1, _spot("Skogli"))
	var o := {"started": op != null, "starting": op.starting if op else false, "phase_at_start": OperationState.Phase.keys()[op.phase] if op else "none"}
	fr = await _frames_until(func() -> bool: return sqs.all(func(q: SquadState) -> bool: return not q.route.is_empty()), 600)
	await _physics(70)  # past the operation's one-second update
	o["frames_to_routes"] = fr
	o["phase_after"] = OperationState.Phase.keys()[op.phase] if op else "none"
	o["pass"] = op != null and o.starting and fr >= 0 and op.phase == OperationState.Phase.MOVING and not op.starting
	if op:
		ws.cancel(op.id, "test")
	out["operation_waits"] = o
	var ok := true
	for k in out:
		ok = ok and bool(out[k].pass)
	out["status"] = "PASS" if ok else "FAIL"
	return out


## Vehicles: a requested route is pending (order taken, the vehicle stands, WAITING), arrives and is driven; a newer order wins; a
## halt while pending drops the answer; a convoy forms from the leader's route.
func _c_vehicle() -> Dictionary:
	await _fresh()
	_camera_far()
	var vs := demo.sim.vehicles
	var trucks: Array = await _trucks(3)
	if trucks.size() < 3:
		return {"status": "ERROR", "reason": "fewer than 3 trucks"}
	var t: UnitState = trucks[0]
	var d1 := _obj("Verket").position
	var d2 := _obj("Sentrum").position
	var out := {}
	var res := vs.request_drive(t.id, d1)
	var p := {"ok": res.ok, "pending": res.get("pending", false), "order_move": t.order == UnitState.Order.MOVE, "route_empty": t.veh.route.is_empty(),
		"status": t.veh.status_name(), "reason": t.veh.reason}
	var fr: int = await _frames_until(func() -> bool: return t.veh.route.size() >= 2 or t.order != UnitState.Order.MOVE, 900)
	await _physics(120)
	p["frames_to_route"] = fr
	p["route_km"] = snappedf(t.veh.route_remaining_m() / 1000.0, 0.01)
	p["moving"] = absf(t.veh.speed) > 0.5
	p["pass"] = res.ok and p.pending and p.order_move and p.route_empty and fr >= 0 and t.veh.route.size() >= 2 and p.moving
	out["pending_then_drive"] = p
	# A newer order while the first is being planned.
	vs.halt(t.id)
	await _physics(30)
	vs.request_drive(t.id, d1)
	vs.request_drive(t.id, d2)
	fr = await _frames_until(func() -> bool: return t.veh.route.size() >= 2, 900)
	var n := {"frames": fr, "end_to_new_m": snappedf(_flat(t.veh.route[t.veh.route.size() - 1], d2), 0.1) if t.veh.route.size() >= 2 else -1.0}
	n["pass"] = fr >= 0 and float(n.end_to_new_m) >= 0.0 and float(n.end_to_new_m) < 5.0
	out["newer_order_wins"] = n
	# Halt while planning.
	vs.halt(t.id)
	await _physics(5)
	vs.request_drive(t.id, d1)
	vs.halt(t.id)
	await _physics(120)
	out["halt_drops_pending"] = {"route_empty": t.veh.route.is_empty(), "order": t.order, "pass": t.veh.route.is_empty() and t.order == UnitState.Order.NONE}
	# A convoy: the leader's route first, then the others to their places in column.
	await _fresh()
	trucks = await _trucks(3)
	var ids: Array = trucks.map(func(u: UnitState) -> int: return u.id)
	var cr := vs.convoy.order_convoy(ids, d1)
	var forming: bool = demo.sim.state.logistics.convoys.get(cr.get("convoy", -1), {}).get("forming", false)
	fr = await _frames_until(func() -> bool: return trucks.all(func(u: UnitState) -> bool: return u.veh.route.size() >= 2), 1500)
	var c := {"ok": cr.ok, "pending": cr.get("pending", false), "forming_at_order": forming, "frames_all_routed": fr,
		"same_convoy": trucks.all(func(u: UnitState) -> bool: return u.veh.convoy_id == int(cr.get("convoy", -2)))}
	c["pass"] = cr.ok and forming and fr >= 0 and c.same_convoy
	out["convoy_forms"] = c
	vs.convoy.stop(int(cr.get("convoy", -1)))
	var ok := true
	for k in out:
		ok = ok and bool(out[k].pass)
	out["status"] = "PASS" if ok else "FAIL"
	return out


## AI operations: three factions start operations in the same frame (all get their routes, none fails or ends for waiting); an
## operation cancelled while its routes are pending gets nothing applied; a changed target (new operation, same squads) ends at
## the new target; reinforcements join a running operation.
func _c_ops() -> Dictionary:
	await _fresh()
	_camera_far()
	var out := {}
	var hau := _obj("Haugen")
	var s_sqs := []
	var e_sqs := []
	var n_sqs := []
	var sa := _near_point(hau.position, _spot("Sentrum"), 2200.0)
	for i in 3:
		s_sqs.append(_spawn(1, sa + Vector3(i * 30.0, 0, 0), 6))
	var ea := _near_point(_obj("Ødegård").position, _obj("Østby").position, 1500.0)
	for i in 3:
		e_sqs.append(_spawn(2, ea + Vector3(i * 30.0, 0, 0), 6))
	var na := _near_point(_obj("Elvetun").position, hau.position, 600.0)
	for i in 2:
		n_sqs.append(_spawn(0, na + Vector3(i * 30.0, 0, 0), 6))
	await _physics(3)
	var ids := func(a: Array) -> Array: return a.map(func(q: SquadState) -> int: return q.id)
	var op1 := ws.start_operation(1, OperationState.Type.ATTACK, ids.call(s_sqs), hau.id)
	var op2 := ws.start_operation(2, OperationState.Type.ATTACK, ids.call(e_sqs), _obj("Sentrum").id)
	var op3 := ws.start_operation(0, OperationState.Type.MOVE, ids.call(n_sqs), -1, _spot("Skogli"))
	var all_sqs: Array = s_sqs + e_sqs + n_sqs
	var fr: int = await _frames_until(func() -> bool: return all_sqs.all(func(q: SquadState) -> bool: return not q.route.is_empty() or q.op_id < 0 or ws.war.operation(q.op_id).transport.get("mode", "foot") == "mech"), 900)
	await _warp(5.0, 1.0, 30.0)
	var m := {"started": [op1 != null, op2 != null, op3 != null], "frames_to_routes": fr,
		"phases": [op1, op2, op3].map(func(o: OperationState) -> String: return OperationState.Phase.keys()[o.phase] if o else "none"),
		"transport": [op1, op2, op3].map(func(o: OperationState) -> String: return String(o.transport.get("mode", "?")) if o else ""),
		"squads_marching": all_sqs.filter(func(q: SquadState) -> bool: return demo.sim.squads.marching(q)).size(), "of": all_sqs.size()}
	m["pass"] = op1 != null and op2 != null and op3 != null and fr >= 0 and [op1, op2, op3].all(func(o: OperationState) -> bool: return o.is_active())
	out["three_factions_at_once"] = m
	for o: OperationState in [op1, op2, op3]:
		if o and o.is_active():
			ws.cancel(o.id, "test")
	# Cancelled while pending.
	await _fresh()
	var c_sqs := [_spawn(1, sa, 6), _spawn(1, sa + Vector3(30, 0, 0), 6)]
	await _physics(3)
	var opc := ws.start_operation(1, OperationState.Type.ATTACK, ids.call(c_sqs), hau.id)
	ws.cancel(opc.id, "test: cancelled while planning")
	await _physics(120)
	out["cancelled_while_pending"] = {"routes": c_sqs.map(func(q: SquadState) -> int: return q.route.size()), "waiting": c_sqs.map(func(q: SquadState) -> bool: return demo.sim.squads.route_waiting(q)),
		"pass": c_sqs.all(func(q: SquadState) -> bool: return q.route.is_empty() and not demo.sim.squads.route_waiting(q) and q.op_id < 0)}
	# Target changed: the same squads get a new operation before the first one's routes came.
	var opx := ws.start_operation(1, OperationState.Type.MOVE, ids.call(c_sqs), -1, _spot("Verket"))
	var new_goal := _spot("Midtmoen")
	var opy := ws.start_operation(1, OperationState.Type.MOVE, ids.call(c_sqs), -1, new_goal)
	fr = await _frames_until(func() -> bool: return c_sqs.all(func(q: SquadState) -> bool: return not q.route.is_empty()), 900)
	var ends: Array = c_sqs.map(func(q: SquadState) -> float: return snappedf(_flat(_route_end(q), new_goal), 1.0))
	out["changed_target"] = {"first": OperationState.Phase.keys()[opx.phase] if opx else "none", "frames": fr, "end_to_new_goal_m": ends,
		"pass": opx != null and opy != null and not opx.is_active() and fr >= 0 and ends.all(func(e: float) -> bool: return e < 60.0)}
	if opy:
		ws.cancel(opy.id, "test")
	# Reinforcements.
	await _fresh()
	var r_sqs := [_spawn(1, sa, 6)]
	var add := [_spawn(1, sa + Vector3(-400, 0, 200), 6)]
	await _physics(3)
	var opr := ws.start_operation(1, OperationState.Type.ATTACK, ids.call(r_sqs), hau.id)
	await _physics(30)
	var joined := ws.join_operation(opr, ids.call(add), "test")
	fr = await _frames_until(func() -> bool: return not add[0].route.is_empty(), 900)
	out["reinforcement"] = {"joined": joined, "frames": fr, "role": SquadState.OpRole.keys()[add[0].op_role], "pass": joined and fr >= 0 and add[0].op_id == opr.id}
	if opr:
		ws.cancel(opr.id, "test")
	var ok := true
	for k in out:
		ok = ok and bool(out[k].pass)
	out["status"] = "PASS" if ok else "FAIL"
	return out


## C4: no request-cancel-request loop. A squad ordered across the river with every crossing closed, and an operation with a goal
## there: the number of route requests over two simulated minutes stays small, the operation waits ("route blocked") and does not
## fail before its timeout, and nobody is passive when a route exists (the control squad on the same bank gets one at once).
func _c_loop() -> Dictionary:
	await _fresh()
	_camera_far()
	_close_all("nav-perf-bc loop test")
	await _physics(5)
	var a := _spot("Haugen")
	var b := _spot("Østby")
	var sq := _spawn(0, a, 6)
	var sq2 := _spawn(1, a + Vector3(200, 0, 0), 6)
	var ctrl := _spawn(0, a + Vector3(0, 0, 200), 6)
	await _physics(3)
	var req0: int = demo.sim.squads.route_requests
	var sub0: int = demo.sim.routing.stats.submitted
	demo.sim.squads.order_move([sq.id], b)
	demo.sim.squads.order_move([ctrl.id], _spot("Sentrum"))
	var op := ws.start_operation(1, OperationState.Type.MOVE, [sq2.id], -1, b)
	var w := await _warp(120.0, 8.0, 120.0)
	var out := {"sim_s": w.sim_s, "route_requests": demo.sim.squads.route_requests - req0, "service_jobs": demo.sim.routing.stats.submitted - sub0,
		"squad_status": SquadState.Status.keys()[sq.status], "op_phase": OperationState.Phase.keys()[op.phase] if op else "none", "op_wait": op.wait_reason if op else "",
		"op_outcome": op.outcome if op else "", "control_route": ctrl.route.size(), "local": demo.sim.local_nav_stats.searches}
	# Requests: one per order, the operation's retries (every 20 s) and the control squad.
	out["pass"] = op != null and int(out.route_requests) <= 12 and ctrl.route.size() >= 2
	_open_all_bridges()
	if op and op.is_active():
		ws.cancel(op.id, "test")
	out["status"] = "PASS" if out.pass else "FAIL"
	return out


# --- B: bridges and the road network ---------------------------------------------------------------------------------------------

## B3: a squad on its approach to the Centre Bridge and a squad marching elsewhere; the bridge closes: the first gets a route round
## it from the service (or stops with the reason), the other gets no new request; nobody steps on the closed deck; reopening leaves
## the marches alone and a new order uses the bridge again. A truck whose route crosses the bridge holds short of it and gets its
## new route as a service job.
func _c_bridge() -> Dictionary:
	await _fresh()
	_camera_far()
	_open_all_bridges()
	var out := {}
	var b := _net().bridge_at(_ground(CENTRE_A).lerp(_ground(CENTRE_B), 0.45), 60.0)
	if b == null:
		for br: RoadNetwork.Bridge in _net().bridges:
			if b == null or _flat(br.center, CENTRE_A) < _flat(b.center, CENTRE_A):
				b = br
	var a := _ground(CENTRE_A)
	var g := _ground(CENTRE_B)
	var sq1 := _spawn(0, a, 6)
	var sq2 := _spawn(0, _spot("Haugen"), 6)
	await _physics(3)
	demo.sim.squads.order_move([sq1.id], g)
	demo.sim.squads.order_move([sq2.id], _spot("Skogli"))
	await _frames_until(func() -> bool: return not sq1.route.is_empty() and not sq2.route.is_empty(), 300)
	var crosses_before := _crosses(sq1.route, b)
	var r2_before := sq2.route.duplicate()
	var job2_before := sq2.route_job
	var req0: int = demo.sim.squads.route_requests
	var reroutes0: int = demo.sim.squads.bridge_reroutes
	var blocked0: int = demo.sim.squads.bridge_blocked
	_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "nav-perf-bc test")
	await _frames_until(func() -> bool: return not demo.sim.squads.route_waiting(sq1), 300)
	await _physics(5)
	var inf := {"bridge": b.id, "crossed_before": crosses_before, "requests": demo.sim.squads.route_requests - req0,
		"rerouted": demo.sim.squads.bridge_reroutes - reroutes0, "stopped": demo.sim.squads.bridge_blocked - blocked0,
		"route_crosses_after": _crosses(sq1.route, b, sq1.route_i), "reason": String(demo.sim.squads.route_block_reason.get(sq1.id, "")),
		"other_squad_untouched": sq2.route == r2_before and sq2.route_job == job2_before}
	# March on for two simulated minutes: nobody on the closed deck.
	var on_deck := [0]
	await _warp(120.0, 8.0, 120.0, func() -> bool:
		for id in sq1.members:
			var u := _u(id)
			if u and b.strip_contains(Vector2(u.position.x, u.position.z)) and not b.is_open():
				on_deck[0] += 1
		return false)
	inf["samples_on_closed_deck"] = on_deck[0]
	# Reopen: the march in progress keeps its route; a new order uses the bridge.
	var r1_before := sq1.route.duplicate()
	_net().set_bridge_state(b.id, RoadNetwork.BridgeState.OPEN)
	await _physics(10)
	inf["route_kept_on_reopen"] = sq1.route == r1_before
	var sq3 := _spawn(0, a + Vector3(20, 0, 0), 6)
	await _physics(3)
	demo.sim.squads.order_move([sq3.id], g)
	await _frames_until(func() -> bool: return not sq3.route.is_empty(), 300)
	inf["new_order_uses_bridge"] = _crosses(sq3.route, b)
	inf["pass"] = crosses_before and inf.requests <= 1 and (inf.rerouted == 1 or inf.stopped == 1) and not inf.route_crosses_after \
		and inf.other_squad_untouched and on_deck[0] == 0 and inf.route_kept_on_reopen and inf.new_order_uses_bridge
	out["infantry"] = inf
	# A truck over the same bridge.
	await _fresh()
	var trip := _bridge_trip(b, 600.0, 500.0)
	var trucks: Array = await _trucks(1)
	var t: UnitState = trucks[0]
	_stand_truck(t, trip.start, trip.yaw)
	await _physics(3)
	var vs := demo.sim.vehicles
	vs.request_drive(t.id, trip.dest)
	await _frames_until(func() -> bool: return t.veh.route.size() >= 2, 900)
	var v_crosses := _crosses(t.veh.route, b)
	var tr := Trace.new(t, _net())
	await _warp(60.0, 4.0, 60.0, func() -> bool:
		tr.step(demo.sim.state.time)
		return _flat(t.position, trip.entry) < 260.0)
	var replans0: int = vs.stats.bridge_replans
	var vjobs0: int = int(demo.sim.routing.by_kind.get(&"vehicle", 0))
	_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "nav-perf-bc test")
	await _warp(240.0, 4.0, 120.0, func() -> bool:
		tr.step(demo.sim.state.time)
		return false)
	var veh := {"crossed_before": v_crosses, "service_jobs": int(demo.sim.routing.by_kind.get(&"vehicle", 0)) - vjobs0, "bridge_replans": vs.stats.bridge_replans - replans0,
		"status": t.veh.status_name(), "reason": t.veh.reason, "route_crosses_after": _crosses(t.veh.route, b, t.veh.route_i) if t.veh.route.size() >= 2 else false}
	veh.merge(tr.summary())
	veh["pass"] = v_crosses and veh.service_jobs >= 1 and not veh.entered_closed and not veh.route_crosses_after and (veh.bridge_replans == 1 or t.veh.status == VehicleState.Status.BLOCKED)
	out["truck"] = veh
	_open_all_bridges()
	out["status"] = "PASS" if inf.pass and veh.pass else "FAIL"
	return out


## B1/B2 in the running game: RoadAudit.connectivity (router graph after its repairs, bridges, strategic grid) and routes between
## different areas of ref_20km for trucks and infantry, each checked point by point. Data problems are reported, never fixed here.
func _b_roads() -> Dictionary:
	await _fresh()
	var audit := RoadAudit.new(demo.sim)
	var pl := {}
	for n in ["Haugen", "Sentrum", "Flyslette øst", "Verket", "Østby", "Nordvik", "Grensen", "Elvetun", "Ødegård", "Strand", "Fjellmoen", "Midtmoen", "Vestli", "Sletta"]:
		var p := _spot(n)
		if p.is_finite():
			pl[n] = p
	for o: ObjectiveState in war.objectives.values():
		pl[o.obj_name] = o.position
	var conn := audit.connectivity(pl)
	var pairs := [["Haugen", "Sentrum"], ["Haugen", "Flyslette øst"], ["Sentrum", "Flyslette øst"], ["Haugen", "Verket"], ["North HQ", "East HQ"],
		["South HQ", "Haugen"], ["Flyslette øst", "South HQ"], ["Nordvik", "Grensen"], ["Østby", "Elvetun"]]
	var rows := []
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var veh_ok := 0
	var inf_ok := 0
	for pr: Array in pairs:
		var a: Vector3 = pl.get(pr[0], Vector3.INF)
		var b: Vector3 = pl.get(pr[1], Vector3.INF)
		if not a.is_finite() or not b.is_finite():
			continue
		a.y = demo.sim.vehicles.ground_at(a)
		b.y = demo.sim.vehicles.ground_at(b)
		var vr := demo.sim.vehicles.router.plan(a, b, td)
		var row := {"trip": "%s -> %s" % pr, "straight_km": snappedf(_flat(a, b) / 1000.0, 0.1)}
		if vr.ok:
			var chk := audit.vehicle_route_check(vr.points, td)
			row["truck"] = {"km": snappedf(float(vr.length_m) / 1000.0, 0.1), "road_km": snappedf(float(vr.road_m) / 1000.0, 0.1), "bridges": vr.bridge_ids, "check": chk}
			veh_ok += 1 if chk.ok else 0
		else:
			row["truck"] = {"fail": vr.reason}
		var ir := ws.routes.route(a, b, demo.sim.terrain)
		if ir.size() >= 2:
			var f := _route_feasible(ir)
			row["infantry"] = {"km": snappedf(ws.routes.route_length(ir) / 1000.0, 0.1), "check": f}
			inf_ok += 1 if f.bad_legs == 0 and f.nan_heights == 0 else 0
		else:
			row["infantry"] = {"fail": String(ws.routes.last_failure.get("reason", "no route"))}
		rows.append(row)
	var bridges_ok: bool = (conn.bridges as Array).all(func(r: Dictionary) -> bool: return r.traversable)
	# A truck trip that fails is a map finding when one end lies far from the road network (no access road), a code or data fault
	# otherwise.
	var off: Array = (conn.places_far_from_main_network as Array).map(func(d: Dictionary) -> String: return String(d.place))
	var unexplained := 0
	var no_access := 0
	for row: Dictionary in rows:
		if row.truck.has("fail"):
			var ends: Array = String(row.trip).split(" -> ")
			if off.has(ends[0]) or off.has(ends[1]):
				row.truck["finding"] = "map data: an end has no road within 400 m (%s)" % ", ".join(ends.filter(func(e: String) -> bool: return off.has(e)))
				no_access += 1
			else:
				unexplained += 1
	# A truck route is physically wrong when it crosses water, a structure or a closed deck. Short terrain steps under the road
	# (grade over the vehicle limit across ~6 m) are listed as map findings: the route itself is the road.
	var wrong := 0
	var steps := []
	for row: Dictionary in rows:
		var chk: Dictionary = row.truck.get("check", {})
		if chk.is_empty():
			continue
		if int(chk.wet) > 0 or int(chk.in_structure) > 0 or int(chk.closed_deck) > 0:
			wrong += 1
		for w: Array in chk.where:
			if w[0] == "steep" and not steps.any(func(q: Array) -> bool: return Vector2(q[0], q[1]).distance_to(Vector2(w[1][0], w[1][1])) < 30.0):
				steps.append([w[1][0], w[1][1], w[2]])
	return {"status": "PASS" if bridges_ok and wrong == 0 and unexplained == 0 and inf_ok == rows.size() else "FAIL", "connectivity": conn,
		"routes": rows, "trucks_clean": veh_ok, "trucks_physically_wrong": wrong, "trucks_no_road_access": no_access, "trucks_unexplained_failures": unexplained,
		"terrain_steps_on_truck_routes": steps, "infantry_ok": inf_ok, "of": rows.size()}


## WORLD-SETTLEMENT-01 (run with --settlement-proto=haugen --only b_settlement): the prototype's local roads are in the road
## network, a truck plans in and out of the village from yards that only the new roads reach, and infantry crosses the village.
func _b_settlement() -> Dictionary:
	if SettlementProto.active() != "haugen":
		return {"status": "FAIL", "reason": "needs --settlement-proto=haugen"}
	await _fresh()
	var net := demo.sim.state.roads
	var names := {}
	for r: RoadNetwork.Road in net.world:
		names[r.name] = true
	var gone: bool = not names.has("Haugen gate 1") and not names.has("Haugen gate 2")
	var added := ["Haugvegen", "Bakkeli", "Nordre Haugen gardsveg", "Austre Haugen gardsveg", "Vestre Haugen gardsveg", "Sagvegen"].filter(
		func(n: String) -> bool: return names.has(n))
	var audit := RoadAudit.new(demo.sim)
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var g := func(x: float, z: float) -> Vector3: return Vector3(x, demo.sim.vehicles.ground_at(Vector3(x, 0, z)), z)
	# Ends of the new roads (upper Haugvegen, Nordre Haugen, Haugen ovre, Vestre Haugen) and places outside the village.
	var trips := [["upper Haugvegen", g.call(-1682.0, -4578.0), "Fv south-east", g.call(-1193.0, -4012.0)],
		["Fv south-east", g.call(-1193.0, -4012.0), "Nordre Haugen", g.call(-1732.0, -4796.0)],
		["Haugen ovre", g.call(-1352.0, -4552.0), "Sentrum", _spot("Sentrum")],
		["Vestre Haugen", g.call(-1736.0, -4404.0), "Lv haugen south", g.call(-1675.0, -4151.0)]]
	var rows := []
	var ok := gone and added.size() == 6
	for t: Array in trips:
		var a: Vector3 = t[1]
		var b: Vector3 = t[3]
		# The start must be off every canonical road, so only the new roads can serve it.
		var near: Dictionary = net.nearest(a, 30.0)
		var vr := demo.sim.vehicles.router.plan(a, b, td)
		var row := {"trip": "%s -> %s" % [t[0], t[2]], "start_road": String(near.get("road").name) if near.get("road") else "none"}
		if vr.ok:
			var chk := audit.vehicle_route_check(vr.points, td)
			row["truck"] = {"km": snappedf(float(vr.length_m) / 1000.0, 0.01), "road_km": snappedf(float(vr.road_m) / 1000.0, 0.01), "check": chk}
			ok = ok and int(chk.wet) == 0 and int(chk.in_structure) == 0
		else:
			row["truck"] = {"fail": vr.reason}
			ok = false
		var ir := ws.routes.route(a, b, demo.sim.terrain)
		if ir.size() >= 2:
			var f := _route_feasible(ir)
			row["infantry"] = {"km": snappedf(ws.routes.route_length(ir) / 1000.0, 0.01), "check": f}
			ok = ok and f.bad_legs == 0 and f.nan_heights == 0
		else:
			row["infantry"] = {"fail": String(ws.routes.last_failure.get("reason", "no route"))}
			ok = false
		rows.append(row)
	return {"status": "PASS" if ok else "FAIL", "old_streets_removed": gone, "new_roads": added, "trips": rows}


# --- D: movement in the world ---------------------------------------------------------------------------------------------------

## D1: a squad of six marches Haugen -> Sentrum (3.2 km route) in the abstract tier, and 1.2 km with the camera on it (bodies,
## navmesh); the instrumented march of NAV-INF-01 (stalls, jumps, water, replans, arrival within the game's own tolerance).
func _d_long() -> Dictionary:
	var out := {}
	var far := await _nmarch(_spot("Haugen"), _spot("Sentrum"), "far", 3600.0, {"n": 6, "scale": 12.0})
	far.erase("members")
	far["pass"] = _nmarch_pass(far)
	out["far_haugen_sentrum"] = far
	var pr := _pair(1200.0)
	if not pr.is_empty():
		var near := await _nmarch(pr.a, pr.b, "near", 1500.0, {"n": 6, "scale": 4.0})
		near.erase("members")
		near["pass"] = _nmarch_pass(near)
		out["near_1200m"] = near
	var ok := true
	for k in out:
		ok = ok and bool(out[k].pass)
	out["status"] = "PASS" if ok else "FAIL"
	return out


## D2: 10, 25 and 50 squads ordered at once to places 2-6 km away: the order call, the first 8 s at 1x (frames, route work per
## frame, queue, latency), 32 s at 4x; every squad must get its route and none may wait more than a few seconds for it.
func _d_load() -> Dictionary:
	var out := {}
	var ok := true
	for n in [10, 25, 50]:
		var r := await _burst(n)
		var lat: Dictionary = r.route_latency_sim_s
		# Route work per frame: the budget (2 ms at 1x, 4 x 2 ms at 4x) plus at most one piece of work over it.
		r["pass"] = int(r.routed) == n and float(lat.get("max", 99.0)) < 5.0 and float((r.routing_1x as Dictionary).frame_ms_max) < 2.0 + 2.5 			and float((r.routing_4x as Dictionary).frame_ms_max) < 8.0 + 2.5
		ok = ok and r.pass
		out["n%d" % n] = r
	out["status"] = "PASS" if ok else "FAIL"
	return out


## D3: four South squads attack Haugen, held by two North squads, from ~2 km (an AI ATTACK operation, combat on). Navigation is
## judged, not the fight: every squad gets its route at once, none loses its operation while marching, the operation reaches its
## deployment (or ends for a tactical reason, reported as such), no squad waits for a route long.
func _d_haugen() -> Dictionary:
	await _fresh()
	_camera_far()
	var hau := _obj("Haugen")
	var defenders := [_spawn(0, hau.position + Vector3(-30, 0, 0), 6), _spawn(0, hau.position + Vector3(30, 0, 20), 6)]
	var a := _near_point(hau.position, _spot("Sentrum"), 2000.0)
	var att := []
	for i in 4:
		att.append(_spawn(1, a + Vector3((i % 2) * 35.0, 0, (i / 2) * 35.0), 6))
	brain.enabled = true
	await _physics(3)
	var req0: int = demo.sim.squads.route_requests
	var t0 := demo.sim.state.time
	var op := ws.start_operation(1, OperationState.Type.ATTACK, att.map(func(q: SquadState) -> int: return q.id), hau.id)
	if op == null:
		brain.enabled = false
		return {"status": "FAIL", "reason": "the operation did not start"}
	var routed_at := {}
	var lost_op := {}
	var stages := []
	var last_stage := [-1]
	var fail0: int = demo.sim.squads.route_failures
	await _warp(900.0, 8.0, 240.0, func() -> bool:
		for q: SquadState in att:
			if not q.route.is_empty() and not routed_at.has(q.id):
				routed_at[q.id] = snappedf(demo.sim.state.time - t0, 0.01)
			if q.op_id != op.id and not q.members.is_empty() and op.is_active():
				lost_op[q.id] = snappedf(demo.sim.state.time - t0, 0.1)
		if int(op.stage) != last_stage[0]:
			last_stage[0] = int(op.stage)
			stages.append([snappedf(demo.sim.state.time - t0, 0.1), str(OperationState.Stage.find_key(op.stage)), op.stage_why])
		return not op.is_active() or int(op.stage) >= int(OperationState.Stage.ASSAULT))
	brain.enabled = false
	var dists: Array = att.map(func(q: SquadState) -> float: return snappedf(_flat(ws.squad_center(q), hau.position), 1.0))
	var out := {"routed_after_s": routed_at.values(), "routed": routed_at.size(), "of": att.size(), "lost_op": lost_op, "stages": stages,
		"phase": OperationState.Phase.keys()[op.phase], "outcome": op.outcome, "wait_reason": op.wait_reason, "transport": op.transport.get("mode", "foot"),
		"route_requests": demo.sim.squads.route_requests - req0, "dist_to_haugen_m": dists, "losses": op.losses,
		"route_failures": demo.sim.squads.route_failures - fail0}
	var nav_ok: bool = routed_at.size() == att.size() and routed_at.values().all(func(t: float) -> bool: return t < 3.0) and lost_op.is_empty() \
		and (int(op.stage) >= int(OperationState.Stage.DEPLOY) or (not op.is_active() and not String(op.outcome).contains("route")))
	out["navigation_pass"] = nav_ok
	out["tactical_note"] = "" if op.is_active() or op.phase == OperationState.Phase.COMPLETED else "operation ended: %s (tactical, not navigation)" % op.outcome
	if op.is_active():
		ws.cancel(op.id, "test")
	out["status"] = "PASS" if nav_ok else "FAIL"
	return out


# --- E: save and load while routes are being planned ------------------------------------------------------------------------------

func _e_persist() -> Dictionary:
	await _fresh()
	_camera_far()
	var path := "user://nav_perf_bc/save_pending.txt"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://nav_perf_bc"))
	var sq := _spawn(0, _spot("Haugen"), 6)
	var trucks: Array = await _trucks(1)
	var t: UnitState = trucks[0]
	var sqs := [_spawn(1, _spot("Sentrum"), 6)]
	await _physics(3)
	demo.sim.squads.order_move([sq.id], _spot("Elvetun"))
	demo.sim.vehicles.request_drive(t.id, _obj("Verket").position)
	var op := ws.start_operation(1, OperationState.Type.MOVE, sqs.map(func(q: SquadState) -> int: return q.id), -1, _spot("Skogli"))
	# Saved in the same frame: every route is still pending.
	var pend := {"squad": demo.sim.squads.route_waiting(sq), "vehicle": demo.sim.vehicles.route_pending(t.id), "op_starting": op.starting if op else false}
	var err := demo.sim.state.save_file(path)
	await _frames_until(func() -> bool: return not sq.route.is_empty() and t.veh.route.size() >= 2, 900)
	var lr: Variant = demo.sim.state.load_file(path)
	var sq_l := demo.sim.state.get_squad(sq.id)
	var t_l := demo.sim.state.get_unit(t.id)
	var op_l := ws.war.operation(op.id) if op else null
	var after_load := {"squad_waiting": demo.sim.squads.route_waiting(sq_l), "squad_route": sq_l.route.size(), "vehicle_order": t_l.order, "vehicle_route": t_l.veh.route.size(),
		"op_starting": op_l.starting if op_l else false}
	var fr: int = await _frames_until(func() -> bool:
		var q := demo.sim.state.get_squad(sq.id)
		var u := demo.sim.state.get_unit(t.id)
		var o := ws.war.operation(op.id)
		return not q.route.is_empty() and u.veh.route.size() >= 2 and o != null and not o.starting, 900)
	var out := {"pending_at_save": pend, "save_err": err, "load_ok": lr is Dictionary, "after_load": after_load, "frames_to_routes_after_load": fr}
	out["pass"] = pend.squad and pend.vehicle and pend.op_starting and err == OK and lr is Dictionary and after_load.squad_waiting and after_load.vehicle_order == UnitState.Order.MOVE \
		and after_load.vehicle_route == 0 and after_load.op_starting and fr >= 0
	var o2 := ws.war.operation(op.id)
	if o2 and o2.is_active():
		ws.cancel(o2.id, "test")
	out["status"] = "PASS" if out.pass else "FAIL"
	return out


# --- Z: visual run ------------------------------------------------------------------------------------------------------------------

func _shot_p(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	if img == null:
		return
	img.save_jpg(ProjectSettings.globalize_path("%s/navperf_%s.jpg" % [_shot_dir, shot_name]), 0.88)
	print("NAV_PERF_BC shot: ", shot_name)


## What a player sees (GUI run with --shots): the route overlay (F6) on; 25 squads ordered at once; a squad marching near the
## camera over open ground and into Sentrum; the Haugen attack approaching; a truck holding short of a closed bridge and turning.
func _z_visual() -> Dictionary:
	var out := {}
	if not (demo._route_overlay != null and is_instance_valid(demo._route_overlay)):
		demo.toggle_route_overlay()
	# 1. 25 squads at once, camera over Haugen.
	await _fresh()
	var starts := ["Haugen", "Sentrum", "Elvetun", "Skogli", "Midtmoen"]
	var sqs := []
	for i in 25:
		sqs.append(_spawn(0, _spot(starts[i % 5]) + Vector3((i / 5) * 30.0, 0, 0), 6))
	_camera_on(_spot("Haugen"), 220.0)
	await _seconds(3.0)
	demo.sim.routing.reset_stats()
	for i in 25:
		demo.sim.squads.order_move([sqs[i].id], _spot(["Flyslette øst", "Verket", "Østby", "Bakken", "Sørmoen"][i % 5]))
	for k in 4:
		await _seconds(1.0)
		if shots:
			_shot_p("z1_burst_%d" % k)
	out["burst"] = demo.sim.routing.report()
	# 2. One squad near the camera, Haugen towards Sentrum (bodies), screenshots on the way.
	var m := await _nmarch(_spot("Haugen"), _spot("Haugen").lerp(_spot("Sentrum"), 0.35), "near", 900.0,
		{"n": 6, "scale": 3.0, "shot_tag": "z2_march", "shot_every_s": 40.0, "shot_first_s": 3.0})
	out["near_march"] = _vis_row(m)
	# 3. The Haugen attack approaching (camera follows the attackers).
	await _fresh()
	var hau := _obj("Haugen")
	var a := _near_point(hau.position, _spot("Sentrum"), 1500.0)
	var att := []
	for i in 3:
		att.append(_spawn(1, a + Vector3(i * 35.0, 0, 0), 6))
	_spawn(0, hau.position, 6)
	brain.enabled = true
	await _physics(3)
	var op := ws.start_operation(1, OperationState.Type.ATTACK, att.map(func(q: SquadState) -> int: return q.id), hau.id)
	for k in 6:
		var c := Vector3.ZERO
		for q: SquadState in att:
			c += ws.squad_center(q)
		_camera_on(c / att.size(), 70.0)
		await _warp(25.0, 4.0, 60.0)
		if shots:
			_shot_p("z3_haugen_%d" % k)
	brain.enabled = false
	out["haugen"] = {"stage": str(OperationState.Stage.find_key(op.stage)) if op else "none", "why": op.stage_why if op else ""}
	if op and op.is_active():
		ws.cancel(op.id, "visual done")
	out["status"] = "INFO"
	return out

## NAVIGATION N1-C1 planning-cost measurements: identical workloads, run on the N1-B baseline and on the N1-C1 code.
##
##   Godot.exe --headless --path . res://scenes/game/world_ref_20km.tscn -- --navigation-n1c1-perf [--tag=name]
##
## Uses only the planner entry points that exist in both versions (VehicleRouter.plan, StructureManager placement and its
## caches), so the same file measures both. Output: user://navigation_n1c1/perf_<tag>.json.
##
## Cold    = every cache dropped: router plans, legs, failures, the vegetation collider caches.
## Warm    = vegetation caches warm, router plan and leg caches dropped (what a new order costs in a running game).
## Cached  = the plan cache answers.
class_name NavigationN1C1PerfTest
extends NavigationN1BSelfTest

var _tag := "run"


func run(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--tag="):
			_tag = a.trim_prefix("--tag=")
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
	tree.create_timer(1800.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog")
		_finish_perf())
	await _physics(60)
	_load_world_data()
	_pause_ai(true)
	brain.enabled = false
	demo.sim.vehicles.router.ensure_built()
	results["tag"] = _tag
	results["verket"] = await _verket_perf()
	results["woods"] = await _woods_perf()
	results["workload"] = await _workload_perf()
	results["after_structure"] = await _structure_perf()
	results["infantry_over_bridge"] = await _infantry_over_bridge()
	results["native_astar_max_ms"] = {"road": _vr().native_road_astar_max_ms, "vehicle_local": _vr().native_local_astar_max_ms,
		"strategic": demo.routes.native_astar_max_ms, "infantry_local": LocalRoutePlanner.native_astar_max_ms}
	_finish_perf()


func _finish_perf() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["failures"] = failures
	var dir := "user://navigation_n1c1"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/perf_%s.json" % _tag
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("NAV_N1C1_PERF ", JSON.stringify(results))
	demo.shutdown_cleanup()
	tree.quit()


func _vr() -> VehicleRouter:
	return demo.sim.vehicles.router


func _cold() -> void:
	var vr := _vr()
	vr._plan_cache.clear()
	vr._leg_cache.clear()
	vr._fail_cache.clear()
	sm._tree_cache.clear()
	sm._trunk_sub.clear()


func _warm() -> void:
	var vr := _vr()
	vr._plan_cache.clear()
	vr._leg_cache.clear()
	vr._fail_cache.clear()


func _prof() -> Dictionary:
	return _vr().prof.duplicate()


func _prof_delta(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in b:
		var d: float = float(b[k]) - float(a.get(k, 0.0))
		if absf(d) > 0.0:
			out[k] = snappedf(d, 0.1)
	return out


func _timed_plan(from: Vector3, to: Vector3, d: VehicleDefs.Def) -> Dictionary:
	var p0 := _prof()
	var t0 := Time.get_ticks_usec()
	var res := _vr().plan(from, to, d)
	var wall := (Time.get_ticks_usec() - t0) / 1000.0
	return {"ok": res.ok, "wall_ms": wall, "len": snappedf(float(res.get("length_m", -1.0)), 1.0), "prof": _prof_delta(p0, _prof())}


## Verket -> South Bridge (the documented 290-430 ms plan), truck.
func _verket_perf() -> Dictionary:
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var a := _obj("Verket").position
	var b := _obj("South Bridge").position
	a.y = demo.sim.vehicles.ground_at(a)
	b.y = demo.sim.vehicles.ground_at(b)
	var out := {}
	_cold()
	out["cold"] = _timed_plan(a, b, td)
	var warm: Array = []
	for i in 5:
		_warm()
		warm.append(_timed_plan(a, b, td))
	out["warm_runs_ms"] = warm.map(func(r: Dictionary) -> float: return snappedf(r.wall_ms, 0.1))
	out["warm_prof_last"] = warm[-1].prof
	out["warm"] = _percentiles(warm.map(func(r: Dictionary) -> float: return r.wall_ms))
	out["cached"] = _timed_plan(a, b, td)
	return out


## First plan through dense woods, APC (the N1B-04 corridor).
func _woods_perf() -> Dictionary:
	var ad := VehicleDefs.get_def(VehicleDefs.APC)
	var dense: Dictionary = await _find_route("forest", 300.0)
	if dense.is_empty():
		return {"error": "no dense woods found"}
	var out := {"corridor": dense}
	_cold()
	out["cold"] = _timed_plan(dense.a, dense.b, ad)
	var warm: Array = []
	for i in 5:
		_warm()
		warm.append(_timed_plan(dense.a, dense.b, ad))
	out["warm"] = _percentiles(warm.map(func(r: Dictionary) -> float: return r.wall_ms))
	out["warm_prof_last"] = warm[-1].prof
	out["trunk_index_comparison"] = _trunk_index_comparison(dense.a, dense.b)
	return out


## Compare the previous rectangular bucket traversal with the current index on the same warmed data.
func _trunk_index_comparison(a: Vector3, b: Vector3) -> Dictionary:
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2.ONE * 105.0
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2.ONE * 105.0
	var rect := Rect2(lo, hi - lo)
	var old_times: Array = []
	var new_times: Array = []
	var equal := true
	for repetition in 5:
		var old := PackedFloat32Array()
		var current := PackedFloat32Array()
		var t := Time.get_ticks_usec()
		_old_trunks_in_rect(rect, old)
		old_times.append((Time.get_ticks_usec() - t) / 1000.0)
		t = Time.get_ticks_usec()
		sm.trunks_in_rect(rect, current)
		new_times.append((Time.get_ticks_usec() - t) / 1000.0)
		var old_rows: Array = []
		var new_rows: Array = []
		for i in range(0, old.size(), 3):
			old_rows.append(Vector3(old[i], old[i + 1], old[i + 2]))
		for i in range(0, current.size(), 3):
			new_rows.append(Vector3(current[i], current[i + 1], current[i + 2]))
		# The arrays need not be in the same order, but every collider must be present.
		old_rows.sort_custom(func(x: Vector3, y: Vector3) -> bool: return x.x < y.x if x.x != y.x else (x.y < y.y if x.y != y.y else x.z < y.z))
		new_rows.sort_custom(func(x: Vector3, y: Vector3) -> bool: return x.x < y.x if x.x != y.x else (x.y < y.y if x.y != y.y else x.z < y.z))
		equal = equal and old_rows == new_rows
	return {"equal": equal, "old_ms": _percentiles(old_times), "new_ms": _percentiles(new_times)}


func _old_trunks_in_rect(rect: Rect2, out: PackedFloat32Array) -> void:
	var cs: float = sm.vegetation.cell_size_m
	var c0 := VegetationChunk.cell_of(Vector3(rect.position.x - sm._trunk_max_r, 0, rect.position.y - sm._trunk_max_r), cs)
	var c1 := VegetationChunk.cell_of(Vector3(rect.end.x + sm._trunk_max_r, 0, rect.end.y + sm._trunk_max_r), cs)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell := Vector2i(cx, cz)
			var sub: Dictionary = sm._trunk_sub.get(cell, {})
			if sub.is_empty() and not sm._trunk_sub.has(cell):
				sub = sm._build_trunk_sub(cell)
			if sub.is_empty():
				continue
			for gx in range(floori((rect.position.x - sm._trunk_max_r) / sm.TRUNK_SUB), floori((rect.end.x + sm._trunk_max_r) / sm.TRUNK_SUB) + 1):
				for gz in range(floori((rect.position.y - sm._trunk_max_r) / sm.TRUNK_SUB), floori((rect.end.y + sm._trunk_max_r) / sm.TRUNK_SUB) + 1):
					for trunk: Array in sub.get(Vector2i(gx, gz), []):
						if trunk[0] >= rect.position.x - 6.0 and trunk[0] <= rect.end.x + 6.0 and trunk[1] >= rect.position.y - 6.0 and trunk[1] <= rect.end.y + 6.0:
							out.append_array(PackedFloat32Array([trunk[0], trunk[1], trunk[2]]))


## Fixed workload: truck plans between objective pairs 2-8 km apart (24 pairs, the same on every run), cold router caches.
func _workload_perf() -> Dictionary:
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var objs: Array = war.all_objectives()
	var pairs := []
	for i in objs.size():
		for j in objs.size():
			if i == j:
				continue
			var d := _flat(objs[i].position, objs[j].position)
			if d > 2000.0 and d < 8000.0:
				pairs.append([objs[i].position, objs[j].position])
	pairs = pairs.slice(0, 24)
	var out := {"pairs": pairs.size()}
	_cold()
	var cold_ms: Array = []
	var warm_ms: Array = []
	var p0 := _prof()
	for p: Array in pairs:
		_warm()
		warm_ms.append(_timed_plan(p[0], p[1], td).wall_ms)
	out["warm"] = _percentiles(warm_ms)
	out["warm_prof"] = _prof_delta(p0, _prof())
	_cold()
	for p: Array in pairs:
		_vr()._plan_cache.clear()
		_vr()._leg_cache.clear()
		cold_ms.append(_timed_plan(p[0], p[1], td).wall_ms)
	out["first_pass_ms"] = _percentiles(cold_ms)
	# A burst: three vehicles ordered in one frame, six rounds, as N1B-09 does.
	await _ensure_vehicles(1, 3)
	var fleet := _vehicles_of(1).filter(func(u: UnitState) -> bool: return u.alive and u.order == UnitState.Order.NONE)
	var vs := demo.sim.vehicles
	var frame_ms: Array = []
	var plan_ms: Array = []
	for round_i in 6:
		_vr()._fail_cache.clear()
		var t0 := Time.get_ticks_usec()
		for i in fleet.size():
			var pr: Array = pairs[(i + round_i * 3) % pairs.size()]
			var u: UnitState = fleet[i]
			var res := vs.order_drive(u.id, pr[1])
			if res.has("ms"):
				plan_ms.append(float(res.ms))
		frame_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		for u: UnitState in fleet:
			vs.halt(u.id)
		await tree.process_frame
	out["burst_frame_ms"] = _percentiles(frame_ms)
	out["burst_plan_ms"] = _percentiles(plan_ms)
	return out


## The first plans after a structure is placed: the vegetation collider caches are dropped (whole world before N1-C1, only the
## changed cells after); plans across the site, plans far away, and the cache sizes before and after.
func _structure_perf() -> Dictionary:
	await _fresh()
	await _cleanup_test_structures()
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var c := _find_site()
	var out := {"site": [snappedf(c.x, 1.0), snappedf(c.z, 1.0)]}
	if not c.is_finite():
		return out
	# Trips that cross the site, and trips in woods elsewhere that fill the vegetation cache.
	var cross := []
	for k in 6:
		var ang := float(k) * PI / 6.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		cross.append([_ground(c - dir * 140.0), _ground(c + dir * 140.0)])
	var far_a := _obj("Verket").position
	var far_b := _obj("South Bridge").position
	far_a.y = demo.sim.vehicles.ground_at(far_a)
	far_b.y = demo.sim.vehicles.ground_at(far_b)
	_cold()
	for p: Array in cross:
		_vr().plan(p[0], p[1], td)
	_vr().plan(far_a, far_b, td)
	out["cache_before"] = {"tree_cells": sm._tree_cache.size(), "trunk_cells": sm._trunk_sub.size(), "plan_cache": _vr()._plan_cache.size(), "leg_cache": _vr()._leg_cache.size()}
	var b := await _building(&"barracks_block", c, 0.0, false)
	await _physics(5)
	out["placed"] = b != null
	out["cache_after"] = {"tree_cells": sm._tree_cache.size(), "trunk_cells": sm._trunk_sub.size(), "plan_cache": _vr()._plan_cache.size(), "leg_cache": _vr()._leg_cache.size()}
	var first: Array = []
	var cache_hits0: int = _vr().cache_hits
	for p: Array in cross:
		first.append(_timed_plan(p[0], p[1], td).wall_ms)
	out["cross_site_first_ms"] = first.map(func(v: float) -> float: return snappedf(v, 0.1))
	var far_after := _timed_plan(far_a, far_b, td)
	out["far_plan_after"] = far_after
	out["far_plan_cache_hit"] = _vr().cache_hits > cache_hits0
	_warm()
	var warm: Array = []
	for p: Array in cross:
		warm.append(_timed_plan(p[0], p[1], td).wall_ms)
	out["cross_site_warm_ms"] = warm.map(func(v: float) -> float: return snappedf(v, 0.1))
	if b:
		cs.remove(b.id)
	await _wait_navigation()
	return out


## A squad of six marches over the Centre Bridge (open): where do they end after 6 simulated minutes? Same start and goal on
## every version, far tier. Reported as found; the scenario exists to separate old behaviour from changes.
func _infantry_over_bridge() -> Dictionary:
	await _fresh()
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	var a := _ground(Vector3(266.1, 0.0, -1039.0))
	var b := _ground(Vector3(-159.7, 0.0, -1335.1))
	var sq := _spawn(0, a, 6)
	await _physics(3)
	demo.sim.squads.order_move([sq.id], b)
	await _warp(360.0, 12.0, 120.0)
	var rows := []
	var near := 0
	for id in sq.members:
		var u := _u(id)
		rows.append([snappedf(u.position.x, 1.0), snappedf(u.position.z, 1.0), snappedf(u.position.y, 1.0), u.nav_reason])
		if _flat(u.position, b) < 40.0:
			near += 1
	return {"arrived": near, "of": sq.members.size(), "members": rows, "route_left": sq.route.size()}

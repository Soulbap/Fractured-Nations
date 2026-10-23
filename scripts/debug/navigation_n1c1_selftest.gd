## NAVIGATION N1-C1 acceptance (N1C1-01 ... N1C1-12): dynamic bridges, route invalidation, cache and CPU budgets.
##
##   Godot.exe --path . --resolution 1600x900 --log-file n1c1.log \
##     res://scenes/game/world_ref_20km.tscn -- --navigation-n1c1-test [--only diag,n1c1_01] [--shots]
##
## Output: user://navigation_n1c1/navigation_n1c1_test.json and screenshots below user://navigation_n1c1/screenshots
## (never modifies tracked files). Every scenario resets the bridges, vehicles and caches it touches; nothing is
## opened by the harness behind the scenario's back, and a correctly blocked route is a PASS.
class_name NavigationN1C1SelfTest
extends NavigationN1BSelfTest

const IDS_C: Array[String] = ["diag", "dbg_inf", "dbg_closed", "vis", "n1c1_01", "n1c1_02", "n1c1_03", "n1c1_04", "n1c1_05", "n1c1_06", "n1c1_07", "n1c1_07n", "n1c1_08",
	"n1c1_09", "n1c1_10", "n1c1_11", "n1c1_12"]

var _geo := {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "user://navigation_n1c1/screenshots"
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
		failures.append("watchdog: navigation N1-C1 test did not finish")
		_finish_c())
	await _physics(60)
	_load_world_data()
	_pause_ai(true)
	brain.enabled = false
	demo.sim.vehicles.router.ensure_built()
	for id in IDS_C:
		if _want(id):
			_open_all_bridges()
			var data := {}
			match id:
				"diag": data = await _diag_c()
				"n1c1_01": data = await _n1c1_01()
				"n1c1_02": data = await _n1c1_02()
				"n1c1_03": data = await _n1c1_03()
				"n1c1_04": data = await _n1c1_04()
				"n1c1_05": data = await _n1c1_05()
				"n1c1_06": data = await _n1c1_06()
				"n1c1_07": data = await _n1c1_07()
				"n1c1_07n": data = await _n1c1_07n()
				"n1c1_08": data = await _n1c1_08()
				"n1c1_09": data = await _n1c1_09()
				"n1c1_10": data = await _n1c1_10()
				"n1c1_11": data = await _n1c1_11()
				"n1c1_12": data = await _n1c1_12()
				"dbg_inf": data = await _dbg_inf()
				"dbg_closed": data = await _dbg_closed()
				"vis": data = await _vis()
			_log_c(id, data)
	_open_all_bridges()
	_finish_c()


# --- Plumbing ------------------------------------------------------------------------------------

## The diagnostic and visual cases run only when asked for by name.
func _want(id: String) -> bool:
	if ["diag", "dbg_inf", "dbg_closed", "vis"].has(id):
		return only.has(id)
	return only.is_empty() or only.has(id)


func _net() -> RoadNetwork:
	return demo.sim.state.roads


func _router() -> VehicleRouter:
	return demo.sim.vehicles.router


## Every bridge open again, caches as a restart would have them: the scenarios do not depend on each other.
func _open_all_bridges() -> void:
	for b: RoadNetwork.Bridge in _net().bridges:
		_net().set_bridge_state(b.id, RoadNetwork.BridgeState.OPEN)


func _log_c(check: String, data: Dictionary) -> void:
	results[check] = data
	if data.has("status"):
		_case_status[check] = data.status
	print("NAV_N1C1 %s %s" % [check, JSON.stringify(data)])


func _finish_c() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["harness_failures"] = failures
	results["case_status"] = _case_status
	var dir := "user://navigation_n1c1"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/navigation_n1c1_test.json"
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("NAV_N1C1 %s %s" % ["COMPLETE" if failures.is_empty() else "HARNESS_FAIL", JSON.stringify({"cases": _case_status, "failures": failures, "output": path})])
	demo.shutdown_cleanup()
	tree.quit()


func _pass(id: String, ok: bool, data: Dictionary, note := "") -> Dictionary:
	data["status"] = "PASS" if ok else "FAIL"
	data["note"] = note
	return data


# --- Diagnosis ---------------------------------------------------------------------------------------

## The four bridges, and for each objective trip from a faction-1 truck: the bridges the open plan uses and the plan with
## each used bridge closed (length, bridges, reason).
func _diag_c() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 1)
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var out := {"bridges": []}
	for b: RoadNetwork.Bridge in _net().bridges:
		out.bridges.append({"id": b.id, "name": b.name, "center": [snappedf(b.center.x, 1.0), snappedf(b.center.z, 1.0)], "width": b.width,
			"length_m": snappedf(b.length_m, 0.1), "state": b.state_name(), "first": b.first, "last": b.last})
	var vr := _router()
	var td := truck.veh.def()
	out["truck"] = [snappedf(truck.position.x, 1.0), snappedf(truck.position.z, 1.0)]
	var trips := []
	for o: ObjectiveState in war.all_objectives():
		var r0 := vr.plan(truck.position, o.position, td)
		if not r0.ok:
			trips.append({"to": o.obj_name, "ok": false, "reason": r0.reason})
			continue
		var row := {"to": o.obj_name, "len": snappedf(r0.length_m, 1.0), "bridges": r0.bridge_ids, "ms": snappedf(r0.ms, 1.0)}
		for bid: String in r0.bridge_ids:
			_net().set_bridge_state(bid, RoadNetwork.BridgeState.CLOSED, "diag")
			var r1 := vr.plan(truck.position, o.position, td)
			row["closed_" + bid] = {"ok": r1.ok, "len": snappedf(float(r1.get("length_m", -1.0)), 1.0), "bridges": r1.get("bridge_ids", []), "reason": r1.get("reason", ""), "ms": snappedf(r1.ms, 1.0)}
			_net().set_bridge_state(bid, RoadNetwork.BridgeState.OPEN)
		trips.append(row)
	out["trips"] = trips
	out["status"] = "DIAG"
	return out


# --- Geometry helpers ---------------------------------------------------------------------------------

func _road_of(b: RoadNetwork.Bridge) -> RoadNetwork.Road:
	return _net().world[-b.road_key - 1]


## A trip over bridge b along its road: start `before_m` before the first deck point, destination `after_m` beyond the last
## (reverse: the other way). {start, dest, yaw, entry, exit, dir}.
func _bridge_trip(b: RoadNetwork.Bridge, before_m := 450.0, after_m := 500.0, reverse := false) -> Dictionary:
	var pts := _road_of(b).points
	var dir := -1 if reverse else 1
	var i_in := b.last if reverse else b.first
	var i_out := b.first if reverse else b.last
	var i := i_in
	var acc := 0.0
	while acc < before_m and i - dir >= 0 and i - dir < pts.size():
		acc += Vector2(pts[i].x - pts[i - dir].x, pts[i].z - pts[i - dir].z).length()
		i -= dir
	var start := pts[i]
	var fwd := Vector3(pts[i + dir].x - start.x, 0.0, pts[i + dir].z - start.z).normalized()
	var j := i_out
	acc = 0.0
	while acc < after_m and j + dir >= 0 and j + dir < pts.size():
		acc += Vector2(pts[j].x - pts[j + dir].x, pts[j].z - pts[j + dir].z).length()
		j += dir
	return {"start": _ground(start), "dest": _ground(pts[j]), "yaw": atan2(-fwd.x, -fwd.z), "entry": pts[i_in], "exit": pts[i_out], "dir": dir,
		"bridge": b.id}


## A truck of faction 1 standing at `pos` heading yaw, no order, job, convoy or fuel problem.
func _stand_truck(u: UnitState, pos: Vector3, yaw: float) -> void:
	var vs := demo.sim.vehicles
	if u.veh.convoy_id >= 0:
		vs.convoy.leave(u.id)
	if not u.veh.job.is_empty():
		demo.sim.logistics.cancel_job(u.id, "n1c1 reset")
	_put_vehicle(u, pos, yaw)
	u.veh.speed = 0.0
	u.veh.steer = 0.0
	u.veh.fuel = u.veh.def().fuel_capacity
	u.veh.reverse_left = 0.0
	u.veh.recoveries = 0
	u.veh.replans = 0
	u.veh.bypasses = 0
	u.veh.reason = ""
	u.veh.status = VehicleState.Status.PARKED
	u.move_state = UnitState.MoveState.IDLE


func _trucks(n: int) -> Array:
	await _ensure_vehicles(1, n)
	var out := []
	for u: UnitState in _vehicles_of(1):
		if out.size() < n and u.alive and u.veh.type_id == VehicleDefs.TRUCK and u.veh.assign_kind == "" and not u.player_controlled:
			out.append(u)
	return out


## Records what a vehicle does while the scenario runs: whether it ever stood on a closed deck it had not been on when the
## bridge closed, the largest jump between two frames (a teleport shows here), the bridges it drove over and its lowest speed
## on the way. Call `step` once per frame.
class Trace:
	var u: UnitState
	var net: RoadNetwork
	var entered_closed := false
	var entered_which := ""
	var on_deck_at_close := ""
	var max_jump := 0.0
	var bridges_seen := {}
	var last_pos := Vector3.INF
	var last_t := 0.0
	var stopped_frames := 0
	var max_stop_s := 0.0
	var _stop_since := -1.0
	var min_gap_to_entry := INF
	var entry := Vector3.INF

	func _init(p_u: UnitState, p_net: RoadNetwork) -> void:
		u = p_u
		net = p_net

	func step(t: float) -> void:
		var b := net.bridge_at(u.position)
		if b != null and not b.strip_contains(Vector2(u.position.x, u.position.z)):
			b = null
		if b != null:
			bridges_seen[b.id] = true
			if not b.is_open() and b.id != on_deck_at_close:
				entered_closed = true
				entered_which = b.id
		if last_pos.is_finite():
			var dt := maxf(t - last_t, 0.001)
			var jump := Vector2(u.position.x - last_pos.x, u.position.z - last_pos.z).length()
			# More than the fastest vehicle could drive in that time (plus a metre of slack): a jump.
			max_jump = maxf(max_jump, jump - 30.0 * dt - 1.0)
		last_pos = u.position
		last_t = t
		if entry.is_finite():
			min_gap_to_entry = minf(min_gap_to_entry, Vector2(u.position.x - entry.x, u.position.z - entry.z).length())
		if u.order == UnitState.Order.MOVE and absf(u.veh.speed) < 0.2:
			if _stop_since < 0.0:
				_stop_since = t
			max_stop_s = maxf(max_stop_s, t - _stop_since)
		else:
			_stop_since = -1.0

	func summary() -> Dictionary:
		return {"entered_closed": entered_closed, "entered": entered_which, "max_jump_m": snappedf(maxf(max_jump, 0.0), 0.1),
			"bridges_seen": bridges_seen.keys(), "max_stop_s": snappedf(max_stop_s, 0.1), "min_gap_to_entry_m": snappedf(min_gap_to_entry, 0.1) if min_gap_to_entry < INF else -1.0}


## Runs the simulation until `stop` returns true (or max_s simulated seconds), calling `each` every frame. `at_gap` (optional
## Callable() -> bool, true once) fires when `trigger` returns true (used to close a bridge at a chosen moment).
func _run_until(max_s: float, scale: float, each: Callable, stop: Callable, trigger := Callable()) -> Dictionary:
	var fired := {"done": false, "t": -1.0}
	var r := await _warp(max_s, scale, 900.0, func() -> bool:
		if trigger.is_valid() and not fired.done and bool(trigger.call()):
			fired.done = true
			fired.t = demo.sim.state.time
		if each.is_valid():
			each.call(demo.sim.state.time)
		return stop.call())
	r["trigger_t"] = fired.t
	return r


func _stop_idle(u: UnitState) -> bool:
	return u.order == UnitState.Order.NONE and absf(u.veh.speed) < 0.5


## Distance along the straight line from p to the entry point (used for "300 m before the deck" triggers).
func _gap_to(p: Vector3, q: Vector3) -> float:
	return Vector2(p.x - q.x, p.z - q.z).length()


func _camera_far() -> void:
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)


func _camera_on(p: Vector3, h := 60.0) -> void:
	demo.rts_camera.frame(p, 0.0, h)


func _pick_bridge(id: String) -> RoadNetwork.Bridge:
	return _net().get_bridge(id)


## The first bridge pair where closing one leaves the other as a working alternative for a trip along b's road, so scenarios
## that need an alternative (and those that need none) both have a real world to run in. Found once, then cached.
func _alt_pair() -> Dictionary:
	if _geo.has("alt"):
		return _geo.alt
	var truck_def := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var best := {}
	for b: RoadNetwork.Bridge in _net().bridges:
		for rev in [false, true]:
			var trip := _bridge_trip(b, 450.0, 500.0, rev)
			var open_plan := _router().plan(trip.start, trip.dest, truck_def)
			if not open_plan.ok or not (open_plan.bridge_ids as Array).has(b.id):
				continue
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "alt probe")
			var closed_plan := _router().plan(trip.start, trip.dest, truck_def)
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.OPEN)
			if closed_plan.ok and not (closed_plan.bridge_ids as Array).has(b.id) and float(closed_plan.length_m) < 40000.0:
				if best.is_empty() or float(closed_plan.length_m) < float(best.alt_len):
					best = {"bridge": b.id, "reverse": rev, "open_len": open_plan.length_m, "alt_len": closed_plan.length_m,
						"alt_bridges": closed_plan.bridge_ids}
	_geo["alt"] = best
	return best


## A bridge where closing it leaves no way across for the trip (the other crossings are closed too in the scenario).
func _first_bridge_trip(want_alt: bool = true) -> Dictionary:
	var alt := _alt_pair()
	if alt.is_empty():
		return {}
	var b := _pick_bridge(alt.bridge)
	var trip := _bridge_trip(b, 450.0, 500.0, alt.reverse)
	trip["alt"] = alt
	return trip




# --- Small helpers for the cases -------------------------------------------------------------------------

## True when the polyline runs over the deck of b (sampled every 5 m).
func _crosses(pts: PackedVector3Array, b: RoadNetwork.Bridge, from_i := 0) -> bool:
	for i in range(maxi(from_i, 1), pts.size()):
		var a := pts[i - 1]
		var c := pts[i]
		var n := maxi(1, ceili(Vector2(c.x - a.x, c.z - a.z).length() / 5.0))
		for k in n + 1:
			if _net().bridge_at(a.lerp(c, float(k) / n)) == b:
				return true
	return false


func _close_all(why := "n1c1") -> void:
	for b: RoadNetwork.Bridge in _net().bridges:
		_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, why)


func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0}
	var p := _percentiles(values)
	var sum := 0.0
	for v in values:
		sum += float(v)
	p["avg"] = snappedf(sum / values.size(), 0.01)
	p["n"] = values.size()
	return p


func _frame_recorder() -> Dictionary:
	return {"last": Time.get_ticks_usec(), "ms": []}


func _frame_tick(rec: Dictionary) -> void:
	var now := Time.get_ticks_usec()
	rec.ms.append((now - int(rec.last)) / 1000.0)
	rec.last = now


# --- N1C1-01: open bridge --------------------------------------------------------------------------------

func _n1c1_01() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b := _pick_bridge(trip.bridge)
	var trucks := await _trucks(1)
	var truck: UnitState = trucks[0]
	_stand_truck(truck, trip.start, trip.yaw)
	await _physics(2)
	var tr := Trace.new(truck, _net())
	_camera_far()
	var res := demo.sim.vehicles.order_drive(truck.id, trip.dest)
	var out := {"bridge": b.id, "vehicle_plan": {"ok": res.ok, "bridge_ids": res.get("bridge_ids", []), "length_m": snappedf(float(res.get("length_m", -1.0)), 1.0)}}
	if not res.ok:
		return _pass("n1c1_01", false, out, "no plan over the open bridge")
	var each := func(t: float) -> void:
		tr.step(t)
	var stop := func() -> bool:
		return _stop_idle(truck)
	await _run_until(600.0, 12.0, each, stop)
	out["vehicle"] = tr.summary()
	out["vehicle"]["arrived"] = _flat(truck.position, trip.dest) < 16.0
	out["vehicle"]["on_deck"] = tr.bridges_seen.has(b.id)
	# Infantry (abstract tier): a squad marches over the same bridge.
	var itrip := _bridge_trip(b, 180.0, 220.0, trip.alt.reverse)
	var sq := _spawn(0, itrip.start, 6)
	await _physics(3)
	var seen := {}
	var members := Array(sq.members)
	demo.sim.squads.order_move([sq.id], itrip.dest)
	var each_i := func(_t: float) -> void:
		for id in members:
			var uu := _u(id)
			if uu and _net().bridge_at(uu.position) == b:
				seen[id] = true
	var stop_i := func() -> bool:
		return sq.order != SquadState.Order.MOVE and sq.route.is_empty()
	var w := await _run_until(1500.0, 24.0, each_i, stop_i)
	var near_goal := 0
	var crossed := 0
	for id in members:
		var uu := _u(id)
		if uu and _flat(uu.position, itrip.dest) < 40.0:
			near_goal += 1
		if uu and not b.strip_contains(Vector2(uu.position.x, uu.position.z)) and _flat(uu.position, itrip.exit) < _flat(uu.position, itrip.entry):
			crossed += 1
	# Crossed = off the deck on the exit side; reaching the destination 220 m on is general infantry movement (reported only).
	out["infantry"] = {"on_deck": seen.size(), "crossed": crossed, "reached_destination": near_goal, "of": members.size(), "sim_s": w.sim_s}
	var ok: bool = out.vehicle.arrived and out.vehicle.on_deck and not out.vehicle.entered_closed and seen.size() >= 1 and crossed == members.size()
	return _pass("n1c1_01", ok, out, "A truck and a squad cross the open bridge.")


# --- N1C1-02: closed bridge, no new crossing ------------------------------------------------------------

func _n1c1_02() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b := _pick_bridge(trip.bridge)
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var vr := _router()
	var itrip := _bridge_trip(b, 180.0, 220.0, trip.alt.reverse)
	var out := {"bridge": b.id}
	# Open: both planners use the bridge (the precondition of the whole case).
	var open_v := vr.plan(trip.start, trip.dest, td)
	var open_i := ws.routes.route(itrip.start, itrip.dest, demo.sim.terrain)
	var entry := _ground(trip.entry)
	var exit_p := _ground(trip.exit)
	var mid := _ground((trip.entry + trip.exit) * 0.5)
	out["open"] = {"vehicle_uses_bridge": (open_v.get("bridge_ids", []) as Array).has(b.id), "infantry_crosses": _crosses(open_i, b),
		"line_over_deck_ok": vr.line_ok(entry, exit_p, td), "strategic_cell_passable": ws.routes.passable(mid), "deck_open": _net().deck_open(mid)}
	_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "n1c1_02")
	var closed_v := vr.plan(trip.start, trip.dest, td)
	var closed_i := ws.routes.route(itrip.start, itrip.dest, demo.sim.terrain)
	out["closed"] = {"vehicle_ok": closed_v.ok, "vehicle_uses_bridge": (closed_v.get("bridge_ids", []) as Array).has(b.id),
		"vehicle_deck_points": _crosses(closed_v.get("points", PackedVector3Array()), b), "vehicle_len_m": snappedf(float(closed_v.get("length_m", -1.0)), 1.0),
		"infantry_route_n": closed_i.size(), "infantry_crosses": _crosses(closed_i, b), "line_over_deck_ok": vr.line_ok(entry, exit_p, td),
		"strategic_cell_passable": ws.routes.passable(mid), "deck_open": _net().deck_open(mid), "destination_on_deck": vr.plan(trip.start, mid, td).get("reason", "")}
	# A squad ordered across the closed bridge (far tier): nobody steps on the deck for two minutes.
	_camera_far()
	var sq := _spawn(0, itrip.start, 6)
	await _physics(3)
	var members := Array(sq.members)
	var seen := {"on_deck": 0}
	demo.sim.squads.order_move([sq.id], itrip.dest)
	var each := func(_t: float) -> void:
		for id in members:
			var uu := _u(id)
			if uu and b.strip_contains(Vector2(uu.position.x, uu.position.z)):
				seen.on_deck += 1
	var stop := func() -> bool:
		return false
	await _run_until(120.0, 12.0, each, stop)
	var rr := demo.sim.squads
	out["squad"] = {"on_deck_samples": seen.on_deck, "reroutes": rr.bridge_reroutes, "route_crosses": _crosses(sq.route, b, sq.route_i),
		"route_block": rr.route_block_reason.get(sq.id, "")}
	var o: Dictionary = out.open
	var c: Dictionary = out.closed
	var ok: bool = o.vehicle_uses_bridge and o.infantry_crosses and o.line_over_deck_ok and o.strategic_cell_passable \
		and not c.vehicle_uses_bridge and not c.vehicle_deck_points and not c.infantry_crosses and not c.line_over_deck_ok \
		and not c.strategic_cell_passable and not c.deck_open and int(out.squad.on_deck_samples) == 0 and not out.squad.route_crosses
	return _pass("n1c1_02", ok, out, "With the bridge closed no new vehicle or infantry route uses the deck.")


# --- N1C1-03: a bridge closes while traffic is on its way -----------------------------------------------

## (a) Every bridge closes while a truck is 70 m from the deck at speed: it must brake (not halt on the spot) to a stop short of
## the deck (nothing to reroute to) and report the blockage. (b) The bridge closes while a truck is in the middle of the deck: it finishes the
## crossing and arrives; nothing is teleported or stopped dead.
func _n1c1_03() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b := _pick_bridge(trip.bridge)
	var vs := demo.sim.vehicles
	var trucks := await _trucks(2)
	var truck: UnitState = trucks[0]
	var out := {"bridge": b.id}
	# (a) stop short
	_stand_truck(truck, trip.start, trip.yaw)
	await _physics(2)
	_camera_far()
	var tr := Trace.new(truck, _net())
	tr.entry = trip.entry
	var res := vs.order_drive(truck.id, trip.dest)
	if not res.ok:
		return _pass("n1c1_03", false, out, "no plan over the open bridge")
	var stats0 := vs.stats.duplicate()
	var closed_at := {"gap": -1.0, "speed": 0.0, "t": 0.0}
	var trigger := func() -> bool:
		var g := _gap_to(truck.position, trip.entry)
		if g < 70.0 and truck.veh.speed > 6.0:
			closed_at.gap = g
			closed_at.speed = truck.veh.speed
			closed_at.t = demo.sim.state.time
			_close_all("n1c1_03 (a)")
			return true
		return false
	var each := func(t: float) -> void:
		tr.step(t)
		if closed_at.gap >= 0.0 and not closed_at.has("v03") and t - float(closed_at.t) >= 0.3:
			closed_at["v03"] = truck.veh.speed
	var stop := func() -> bool:
		return closed_at.gap >= 0.0 and demo.sim.state.time - float(closed_at.t) > 60.0
	await _run_until(300.0, 6.0, each, stop, trigger)
	var d := truck.veh.def()
	out["a_stop_short"] = tr.summary()
	out["a_stop_short"].merge({"closed_at_gap_m": snappedf(closed_at.gap, 1.0), "speed_ms": snappedf(closed_at.speed, 1.0),
		"final_gap_m": snappedf(_gap_to(truck.position, trip.entry), 1.0), "status": truck.veh.status_name(), "reason": truck.veh.reason,
		"order": int(truck.order), "speed_after": snappedf(truck.veh.speed, 0.01), "speed_0_3s_after_close": snappedf(float(closed_at.get("v03", -1.0)), 0.1), "recoveries": truck.veh.recoveries,
		"holds": int(vs.stats.bridge_holds) - int(stats0.bridge_holds), "blocked": int(vs.stats.bridge_blocked) - int(stats0.bridge_blocked),
		"hard_stops": int(vs.stats.bridge_stops) - int(stats0.bridge_stops), "min_gap_required_m": snappedf(d.length * 0.5 + 1.5, 1.0)})
	var a: Dictionary = out.a_stop_short
	var ok_a: bool = closed_at.gap >= 0.0 and not a.entered_closed and float(a.final_gap_m) >= d.length * 0.5 + 1.5 and float(a.final_gap_m) < 70.0 and float(a.speed_0_3s_after_close) > 0.5 * float(a.speed_ms) \
		and truck.veh.status == VehicleState.Status.BLOCKED and a.holds >= 1 and a.blocked >= 1 and a.recoveries == 0 and a.hard_stops == 0 \
		and String(a.reason).to_lower().contains("bridge")
	# (b) finish the crossing
	_open_all_bridges()
	var trip_b := _bridge_trip(b, 60.0, 500.0, trip.alt.reverse)
	_stand_truck(truck, trip_b.start, trip_b.yaw)
	await _physics(2)
	var tr_b := Trace.new(truck, _net())
	tr_b.entry = trip.entry
	var stats1 := vs.stats.duplicate()
	var res_b := vs.order_drive(truck.id, trip_b.dest)
	var moment := {"done": false}
	var trigger_b := func() -> bool:
		var on := _net().bridge_at(truck.position)
		if on == b and _gap_to(truck.position, trip.entry) > 25.0 and truck.veh.speed > 3.0:
			tr_b.on_deck_at_close = b.id
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "n1c1_03 (b)")
			moment.done = true
			moment["speed"] = truck.veh.speed
			return true
		return false
	var each_b := func(t: float) -> void:
		tr_b.step(t)
	var stop_b := func() -> bool:
		return moment.done and _stop_idle(truck)
	await _run_until(400.0, 6.0, each_b, stop_b, trigger_b)
	out["b_on_deck"] = tr_b.summary()
	out["b_on_deck"].merge({"closed_on_deck": moment.done, "speed_at_close": snappedf(float(moment.get("speed", 0.0)), 1.0), "arrived": _flat(truck.position, trip_b.dest) < 16.0,
		"status": truck.veh.status_name(), "hard_stops": int(vs.stats.bridge_stops) - int(stats1.bridge_stops),
		"replans": int(vs.stats.bridge_replans) - int(stats1.bridge_replans), "holds": int(vs.stats.bridge_holds) - int(stats1.bridge_holds)})
	var bd: Dictionary = out.b_on_deck
	var ok_b: bool = res_b.ok and bd.closed_on_deck and not bd.entered_closed and bd.arrived and float(bd.max_jump_m) <= 0.5 and bd.hard_stops == 0 and bd.holds == 0
	return _pass("n1c1_03", ok_a and ok_b, out, "A closing bridge stops what has not entered it and lets what is on it finish.")


# --- N1C1-04: an alternative crossing exists -------------------------------------------------------------

func _n1c1_04() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b := _pick_bridge(trip.bridge)
	var vs := demo.sim.vehicles
	var trucks := await _trucks(1)
	var truck: UnitState = trucks[0]
	_stand_truck(truck, trip.start, trip.yaw)
	await _physics(2)
	_camera_far()
	var tr := Trace.new(truck, _net())
	tr.entry = trip.entry
	var res := vs.order_drive(truck.id, trip.dest)
	if not res.ok or not (res.bridge_ids as Array).has(b.id):
		return _pass("n1c1_04", false, {"plan_ok": res.ok}, "precondition: the open plan uses the bridge")
	var stats0 := vs.stats.duplicate()
	var plans0 := _router().plans
	var closed := {"t": -1.0}
	var rec := _frame_recorder()
	var trigger := func() -> bool:
		if _gap_to(truck.position, trip.entry) < 250.0 and truck.veh.speed > 4.0:
			closed.t = demo.sim.state.time
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "n1c1_04")
			return true
		return false
	var each := func(t: float) -> void:
		tr.step(t)
		if closed.t >= 0.0 and demo.sim.state.time - float(closed.t) < 20.0:
			_frame_tick(rec)
	var stop := func() -> bool:
		return closed.t >= 0.0 and _stop_idle(truck)
	var max_s := float(trip.alt.alt_len) / 6.0 + 600.0
	var w := await _run_until(max_s, 24.0, each, stop, trigger)
	var out := {"bridge": b.id, "alt_expected_len_m": snappedf(float(trip.alt.alt_len), 1.0), "open_len_m": snappedf(float(res.length_m), 1.0), "closed_at_t": snappedf(closed.t, 1.0), "warp": w}
	out["vehicle"] = tr.summary()
	out["vehicle"].merge({"arrived": _flat(truck.position, trip.dest) < 16.0, "status": truck.veh.status_name(), "reason": truck.veh.reason,
		"holds": int(vs.stats.bridge_holds) - int(stats0.bridge_holds), "replans": int(vs.stats.bridge_replans) - int(stats0.bridge_replans),
		"plans": _router().plans - plans0, "recoveries": truck.veh.recoveries, "drove_m": snappedf(truck.veh.odometer, 1.0)})
	var v: Dictionary = out.vehicle
	var other := false
	for id: String in v.bridges_seen:
		if id != b.id:
			other = true
	out["vehicle"]["used_other_bridge"] = other
	out["reroute_frames_ms"] = _stats(rec.ms)
	var ok: bool = closed.t >= 0.0 and not v.entered_closed and v.arrived and v.holds >= 1 and v.replans == 1 and other and int(v.recoveries) <= 1 and float(v.max_jump_m) <= 0.5
	return _pass("n1c1_04", ok, out, "A truck whose bridge closes finds the other crossing and arrives.")


# --- N1C1-05: no alternative crossing ----------------------------------------------------------------------

func _n1c1_05() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var vs := demo.sim.vehicles
	var trucks := await _trucks(1)
	var truck: UnitState = trucks[0]
	_stand_truck(truck, trip.start, trip.yaw)
	await _physics(2)
	_camera_far()
	var tr := Trace.new(truck, _net())
	tr.entry = trip.entry
	var res := vs.order_drive(truck.id, trip.dest)
	if not res.ok:
		return _pass("n1c1_05", false, {}, "no plan over the open bridge")
	var closed := {"t": -1.0, "plans": 0, "fail_t": -1.0}
	var trigger := func() -> bool:
		if _gap_to(truck.position, trip.entry) < 250.0 and truck.veh.speed > 4.0:
			closed.t = demo.sim.state.time
			_close_all("n1c1_05")
			return true
		return false
	var each := func(t: float) -> void:
		tr.step(t)
		if closed.fail_t < 0.0 and closed.t >= 0.0 and truck.veh.status == VehicleState.Status.BLOCKED:
			closed.fail_t = t
			closed.plans = _router().plans
	var stop := func() -> bool:
		return closed.fail_t >= 0.0 and demo.sim.state.time - float(closed.fail_t) > 180.0
	await _run_until(900.0, 12.0, each, stop, trigger)
	var plans_after := _router().plans - int(closed.plans)
	var out := {"vehicle": tr.summary()}
	out["vehicle"].merge({"status": truck.veh.status_name(), "reason": truck.veh.reason, "order": int(truck.order), "recoveries": truck.veh.recoveries,
		"plans_after_block_180s": plans_after, "blocked_after_s": snappedf(float(closed.fail_t) - float(closed.t), 1.0),
		"final_gap_m": snappedf(_gap_to(truck.position, trip.entry), 1.0), "speed": snappedf(truck.veh.speed, 0.01)})
	var v: Dictionary = out.vehicle
	var ok: bool = closed.fail_t >= 0.0 and not v.entered_closed and truck.veh.status == VehicleState.Status.BLOCKED and truck.order == UnitState.Order.NONE \
		and plans_after <= 1 and v.recoveries == 0 and absf(truck.veh.speed) < 0.1 and String(v.reason).to_lower().contains("bridge") and float(v.final_gap_m) > 4.0
	return _pass("n1c1_05", ok, out, "With every crossing closed the truck stops short, reports the blockage and does not retry.")


# --- N1C1-06: a convoy meets a closing bridge ---------------------------------------------------------------

func _convoy_column(b: RoadNetwork.Bridge, trucks: Array, rev: bool) -> Dictionary:
	for k in trucks.size():
		var tk := _bridge_trip(b, 450.0 + 26.0 * k, 500.0, rev)
		_stand_truck(trucks[k], tk.start, tk.yaw)
	await _physics(2)
	return _bridge_trip(b, 450.0, 500.0, rev)


func _n1c1_06() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b := _pick_bridge(trip.bridge)
	var vs := demo.sim.vehicles
	var trucks := await _trucks(3)
	if trucks.size() < 3:
		return {"status": "ERROR", "reason": "fewer than three trucks"}
	var out := {"bridge": b.id}
	# (a) one bridge closes, another crossing exists: the whole convoy goes round.
	var col := await _convoy_column(b, trucks, trip.alt.reverse)
	_camera_far()
	var ids := trucks.map(func(u: UnitState) -> int: return u.id)
	var cr := vs.convoy.order_convoy(ids, col.dest, "n1c1 convoy")
	if not cr.ok:
		return _pass("n1c1_06", false, {"convoy": cr}, "convoy not formed")
	var traces := []
	for u: UnitState in trucks:
		var t := Trace.new(u, _net())
		t.entry = col.entry
		traces.append(t)
	var stats0 := vs.stats.duplicate()
	var plans0 := _router().plans
	var closed := {"t": -1.0}
	var lead: UnitState = trucks[0]
	var trigger := func() -> bool:
		if _gap_to(lead.position, col.entry) < 300.0 and lead.veh.speed > 4.0:
			closed.t = demo.sim.state.time
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "n1c1_06 (a)")
			return true
		return false
	var each := func(t: float) -> void:
		for tr: Trace in traces:
			tr.step(t)
	var stop := func() -> bool:
		if closed.t < 0.0:
			return false
		for u: UnitState in trucks:
			if not _stop_idle(u):
				return false
		return true
	var max_s := float(trip.alt.alt_len) / 5.0 + 900.0
	var w := await _run_until(max_s, 24.0, each, stop, trigger)
	# NAV-PERF-01B: VehicleConvoy dissolves a finished convoy on its 2 s update; the stop above fires in the frame the last member
	# stops, so the convoy check below waits one update.
	await _seconds(2.5)
	var rows := []
	var arrived := 0
	var other_bridge := 0
	for k in trucks.size():
		var u: UnitState = trucks[k]
		var s: Dictionary = (traces[k] as Trace).summary()
		s["arrived"] = _flat(u.position, col.dest) < 70.0 and u.veh.status != VehicleState.Status.BLOCKED
		s["status"] = u.veh.status_name()
		s["recoveries"] = u.veh.recoveries
		arrived += 1 if s.arrived else 0
		for id: String in s.bridges_seen:
			if id != b.id:
				other_bridge += 1
				break
		rows.append(s)
	out["a_alt"] = {"members": rows, "arrived": arrived, "closed_at": snappedf(closed.t, 1.0), "warp": w, "holds": int(vs.stats.bridge_holds) - int(stats0.bridge_holds),
		"replans": int(vs.stats.bridge_replans) - int(stats0.bridge_replans), "plans": _router().plans - plans0, "convoys_left": demo.sim.state.logistics.convoys.size()}
	var any_entered := false
	var worst_stop := 0.0
	var worst_jump := 0.0
	var worst_rec := 0
	for r: Dictionary in rows:
		any_entered = any_entered or r.entered_closed
		worst_stop = maxf(worst_stop, float(r.max_stop_s))
		worst_jump = maxf(worst_jump, float(r.max_jump_m))
		worst_rec = maxi(worst_rec, int(r.recoveries))
	var ok_a: bool = closed.t >= 0.0 and not any_entered and arrived == 3 and other_bridge == 3 and worst_stop < 120.0 and worst_jump <= 0.5 and worst_rec <= 1 \
		and demo.sim.state.logistics.convoys.is_empty()
	# (b) every crossing closes: members stop, report, and the convoy dissolves.
	_open_all_bridges()
	for id in ids:
		vs.halt(id)
	col = await _convoy_column(b, trucks, trip.alt.reverse)
	var cr2 := vs.convoy.order_convoy(ids, col.dest, "n1c1 convoy 2")
	var traces2 := []
	for u: UnitState in trucks:
		var t2 := Trace.new(u, _net())
		t2.entry = col.entry
		traces2.append(t2)
	var closed2 := {"t": -1.0}
	var plans1 := _router().plans
	var trigger2 := func() -> bool:
		if _gap_to(lead.position, col.entry) < 300.0 and lead.veh.speed > 4.0:
			closed2.t = demo.sim.state.time
			_close_all("n1c1_06 (b)")
			return true
		return false
	var each2 := func(t: float) -> void:
		for tr: Trace in traces2:
			tr.step(t)
	var stop2 := func() -> bool:
		return closed2.t >= 0.0 and demo.sim.state.time - float(closed2.t) > 240.0
	await _run_until(900.0, 12.0, each2, stop2, trigger2)
	var rows2 := []
	var blocked := 0
	var entered2 := false
	var moving := 0
	for k in trucks.size():
		var u: UnitState = trucks[k]
		var s2: Dictionary = (traces2[k] as Trace).summary()
		s2["status"] = u.veh.status_name()
		s2["reason"] = u.veh.reason
		s2["order"] = int(u.order)
		s2["recoveries"] = u.veh.recoveries
		s2["gap_m"] = snappedf(_gap_to(u.position, col.entry), 1.0)
		blocked += 1 if u.veh.status == VehicleState.Status.BLOCKED else 0
		moving += 1 if u.order == UnitState.Order.MOVE else 0
		entered2 = entered2 or s2.entered_closed
		rows2.append(s2)
	out["b_none"] = {"convoy_formed": cr2.ok, "members": rows2, "blocked": blocked, "still_moving": moving, "plans": _router().plans - plans1, "convoys_left": demo.sim.state.logistics.convoys.size()}
	var ok_b: bool = cr2.ok and closed2.t >= 0.0 and not entered2 and moving == 0 and blocked >= 2 and demo.sim.state.logistics.convoys.is_empty()
	return _pass("n1c1_06", ok_a and ok_b, out, "A convoy goes round a closed bridge, or stops and dissolves when there is no other way.")


# --- N1C1-07: infantry, far and near tier ----------------------------------------------------------------

func _squad_on_deck(members: Array, b: RoadNetwork.Bridge) -> int:
	var n := 0
	for id in members:
		var uu := _u(id)
		if uu and uu.alive and b.strip_contains(Vector2(uu.position.x, uu.position.z)):
			n += 1
	return n


func _n1c1_07() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b := _pick_bridge(trip.bridge)
	var itrip := _bridge_trip(b, 180.0, 220.0, trip.alt.reverse)
	var sc := demo.sim.squads
	var out := {"bridge": b.id}
	# (a) far tier, every crossing closed while the squad is 90 m from the deck: it stops and says why.
	_camera_far()
	var sq := _spawn(0, itrip.start, 6)
	await _physics(3)
	var members := Array(sq.members)
	sc.order_move([sq.id], itrip.dest)
	var blocked0 := sc.bridge_blocked
	var reroutes0 := sc.bridge_reroutes
	var st := {"t": -1.0, "on_deck": 0}
	var trig := func() -> bool:
		var c := Vector3.ZERO
		for id in members:
			c += _u(id).position
		c /= members.size()
		if _gap_to(c, itrip.entry) < 90.0:
			st.t = demo.sim.state.time
			_close_all("n1c1_07 (a)")
			return true
		return false
	var each := func(_t: float) -> void:
		var n := _squad_on_deck(members, b)
		if n > 0 and not st.has("first"):
			st["first"] = {"t": _t, "closed_t": st.t, "pos": members.map(func(id: int) -> Array: return [snappedf(_u(id).position.x, 1.0), snappedf(_u(id).position.z, 1.0), _net().bridge_at(_u(id).position) != null])}
		st.on_deck += n
	var stop := func() -> bool:
		return st.t >= 0.0 and demo.sim.state.time - float(st.t) > 90.0
	await _run_until(900.0, 12.0, each, stop, trig)
	var moving_after := 0
	var gap_min := INF
	for id in members:
		var uu := _u(id)
		moving_after += 1 if uu.move_state == UnitState.MoveState.MOVING else 0
		gap_min = minf(gap_min, _gap_to(uu.position, itrip.entry))
	out["a_first_on_deck"] = st.get("first", {})
	out["a_far_none"] = {"closed_at": snappedf(st.t, 1.0), "on_deck_samples": st.on_deck, "stopped_by_bridge": sc.bridge_blocked - blocked0, "rerouted": sc.bridge_reroutes - reroutes0,
		"route_crosses_any": _crosses(sq.route, b, sq.route_i), "reason": sc.route_block_reason.get(sq.id, ""), "order": sq.order_name(), "route_left": sq.route.size(), "moving_after": moving_after, "closest_m": snappedf(gap_min, 1.0)}
	var a: Dictionary = out.a_far_none
	var ok_a: bool = st.t >= 0.0 and a.on_deck_samples == 0 and a.stopped_by_bridge + a.rerouted == 1 and not a.route_crosses_any \
		and (a.stopped_by_bridge == 0 or (String(a.reason).contains("closed") and a.route_left == 0 and moving_after == 0))
	# (b) far tier, another crossing exists: the squad plans a route that no longer crosses the deck.
	_open_all_bridges()
	await _fresh()
	var sq2 := _spawn(0, itrip.start, 6)
	await _physics(3)
	var members2 := Array(sq2.members)
	sc.order_move([sq2.id], itrip.dest)
	var re0 := sc.bridge_reroutes
	var st2 := {"t": -1.0, "on_deck": 0}
	var trig2 := func() -> bool:
		var c2 := Vector3.ZERO
		for id in members2:
			c2 += _u(id).position
		c2 /= members2.size()
		if _gap_to(c2, itrip.entry) < 90.0:
			st2.t = demo.sim.state.time
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "n1c1_07 (b)")
			return true
		return false
	var each2 := func(_t: float) -> void:
		st2.on_deck += _squad_on_deck(members2, b)
	var stop2 := func() -> bool:
		return st2.t >= 0.0 and demo.sim.state.time - float(st2.t) > 120.0
	await _run_until(900.0, 12.0, each2, stop2, trig2)
	out["b_far_alt"] = {"closed_at": snappedf(st2.t, 1.0), "on_deck_samples": st2.on_deck, "reroutes": sc.bridge_reroutes - re0, "route_points": sq2.route.size(),
		"route_crosses": _crosses(sq2.route, b, sq2.route_i), "order": sq2.order_name()}
	var bb: Dictionary = out.b_far_alt
	var ok_b: bool = st2.t >= 0.0 and bb.on_deck_samples == 0 and bb.reroutes == 1 and not bb.route_crosses and bb.route_points >= 2
	# (c) far tier, the squad is on the deck when the bridge closes: it finishes the crossing.
	_open_all_bridges()
	await _fresh()
	var pts := _road_of(b).points
	var deck_pt := _ground(pts[b.first + 3 if not trip.alt.reverse else b.last - 3])
	var sq3 := _spawn(0, deck_pt, 6)
	await _physics(3)
	var members3 := Array(sq3.members)
	var on0 := _squad_on_deck(members3, b)
	sc.order_move([sq3.id], itrip.dest)
	var blocked1 := sc.bridge_blocked
	var re1 := sc.bridge_reroutes
	var st3 := {"closed": false, "left_deck_after_close": 0}
	var trig3 := func() -> bool:
		_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "n1c1_07 (c)")
		st3.closed = true
		return true
	var stop3 := func() -> bool:
		return sq3.order != SquadState.Order.MOVE and sq3.route.is_empty()
	var w3 := await _run_until(700.0, 24.0, Callable(), stop3, trig3)
	# Crossed = off the deck again on the exit side. (Walking on to the destination 220 m further over open ground is general
	# infantry movement, which can stall on its own local-route budget after earlier cases; it says nothing about the bridge.)
	var done := 0
	for id in members3:
		var up := _u(id).position
		if not b.strip_contains(Vector2(up.x, up.z)) and _flat(up, itrip.exit) < _flat(up, itrip.entry):
			done += 1
	var diag := []
	for id in members3:
		var uc := _u(id)
		diag.append("(%.0f,%.0f) %s %s" % [uc.position.x, uc.position.z, UnitState.MoveState.keys()[uc.move_state], uc.nav_reason])
	var veh_near := []
	for vid in vs_ids_near(b):
		veh_near.append(vid)
	out["c_diag"] = {"members": diag, "vehicles_near_bridge": veh_near, "squad_order": sq3.order_name(), "route": sq3.route.size()}
	out["c_on_deck"] = {"on_deck_at_start": on0, "closed": st3.closed, "arrived": done, "of": members3.size(), "stopped_by_bridge": sc.bridge_blocked - blocked1,
		"reroutes": sc.bridge_reroutes - re1, "sim_s": w3.sim_s}
	var cc: Dictionary = out.c_on_deck
	var ok_c: bool = on0 >= 4 and cc.arrived >= members3.size() - 1 and cc.stopped_by_bridge == 0 and cc.reroutes == 0
	return _pass("n1c1_07", ok_a and ok_b and ok_c, out, "Infantry respect the bridge state in the far tier (a near-tier check is N1C1-07n).")


# --- Debug: a squad over an open bridge ---------------------------------------------------------------------

func _dbg_inf() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	var b := _pick_bridge(trip.bridge)
	var itrip := _bridge_trip(b, 180.0, 220.0, trip.alt.reverse)
	_camera_far()
	var sq := _spawn(0, itrip.start, 6)
	await _physics(3)
	var out := {"start": [itrip.start.x, itrip.start.z], "dest": [itrip.dest.x, itrip.dest.z], "entry": [itrip.entry.x, itrip.entry.z]}
	demo.sim.squads.order_move([sq.id], itrip.dest)
	out["route"] = Array(sq.route).map(func(p: Vector3) -> Array: return [snappedf(p.x, 1.0), snappedf(p.z, 1.0)])
	var log := []
	for k in 12:
		await _warp(30.0, 12.0, 60.0)
		var rows := []
		for id in sq.members:
			var uu := _u(id)
			rows.append("%d (%.0f,%.0f,%.1f) %s %s on=%s" % [id, uu.position.x, uu.position.z, uu.position.y, UnitState.MoveState.keys()[uu.move_state], uu.nav_reason, str(_net().bridge_at(uu.position) != null)])
		log.append({"t": k, "order": sq.order_name(), "route_i": sq.route_i, "route_n": sq.route.size(), "status": sq.status, "members": rows})
	out["log"] = log
	# Probe the ground between a blocked soldier and the deck entry.
	var probe := []
	var wp: Array = out.route
	var seg_rows := []
	for s in range(1, wp.size()):
		var pa := Vector3(wp[s - 1][0], 0.0, wp[s - 1][1])
		var pb := Vector3(wp[s][0], 0.0, wp[s][1])
		var n := maxi(1, ceili(_flat(pa, pb) / 4.0))
		var bad := []
		for k in n + 1:
			var q := pa.lerp(pb, float(k) / n)
			var d_h := _net().deck_height(q)
			var wet: bool = sm.is_wet(q.x, q.z)
			var blocked: bool = demo.sim._infantry_blocked(q.x, q.z)
			if blocked:
				bad.append("(%.0f,%.0f wet=%s deck=%s)" % [q.x, q.z, str(wet), str(not is_nan(d_h))])
		seg_rows.append("seg %d: %d samples, blocked: %s" % [s, n + 1, " ".join(bad.slice(0, 6))])
	out["segments"] = seg_rows
	var u2 := _u(sq.members[1])
	var entry: Vector3 = itrip.entry
	for k in 14:
		var q := u2.position.lerp(entry, float(k) / 10.0)
		var sw := demo.sim
		probe.append("k%d (%.1f,%.1f) deck=%s wet=%s blocks=%s hterr=%.2f hinf=%.2f blocked=%s bridge=%s" % [k, q.x, q.z, str(_net().deck_height(q)), str(sm.is_wet(q.x, q.z)), str(sm.blocks_point(Vector2(q.x, q.z), 0.5)),
			demo.sim.terrain.data.get_height(q), sw._infantry_height(q.x, q.z), str(sw._infantry_blocked(q.x, q.z)), str(_net().bridge_at(q))])
	out["probe"] = probe
	return out


# --- N1C1-08: save and load -------------------------------------------------------------------------------

func _n1c1_08() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b1 := _pick_bridge(trip.bridge)
	var b2: RoadNetwork.Bridge = null
	for b: RoadNetwork.Bridge in _net().bridges:
		if b != b1:
			b2 = b
			break
	var vs := demo.sim.vehicles
	var trucks := await _trucks(1)
	var truck: UnitState = trucks[0]
	_stand_truck(truck, trip.start, trip.yaw)
	await _physics(2)
	_camera_far()
	var res := vs.order_drive(truck.id, trip.dest)
	await _warp(5.0, 1.0, 20.0)
	var out := {"bridge_closed": b1.id, "bridge_disabled": b2.id, "plan_ok": res.ok, "truck_moved_m": snappedf(_flat(truck.position, trip.start), 1.0)}
	_net().set_bridge_state(b1.id, RoadNetwork.BridgeState.CLOSED, "n1c1_08 closed")
	_net().set_bridge_state(b2.id, RoadNetwork.BridgeState.DISABLED, "n1c1_08 disabled")
	var order_target := truck.order_target
	var path := "user://navigation_n1c1/save_n1c1_08.txt"
	var err := demo.sim.state.save_file(path)
	out["save_error"] = int(err)
	var text := FileAccess.get_file_as_string(path)
	out["file_has_bridges"] = text.contains("bridge_r") and text.contains("n1c1_08 closed")
	# Back to a state without the closures and without the order, as after a restart, then load.
	_open_all_bridges()
	vs.halt(truck.id)
	truck.position = Vector3(truck.position.x + 400.0, truck.position.y, truck.position.z)
	await _physics(2)
	out["before_load"] = {"b1": b1.state_name(), "b2": b2.state_name(), "blocked_count": _net().blocked_bridge_count(), "order": int(truck.order)}
	var lr: Variant = demo.sim.state.load_file(path)
	await _physics(2)
	var strategic_closed: bool = not ws.routes.passable(_ground((trip.entry + trip.exit) * 0.5))
	var node_disabled := 0
	for id: int in _router()._bridge_nodes.get(b1.id, PackedInt32Array()):
		node_disabled += 1 if _router().astar.is_point_disabled(id) else 0
	out["after_load"] = {"load_ok": lr is Dictionary, "b1": b1.state_name(), "b1_reason": b1.reason, "b2": b2.state_name(), "b2_reason": b2.reason,
		"blocked_count": _net().blocked_bridge_count(), "strategic_cell_closed": strategic_closed,
		"router_nodes_disabled": node_disabled, "of": _router()._bridge_nodes.get(b1.id, PackedInt32Array()).size(),
		"markers": demo.bridge_markers.shown() if demo.bridge_markers else [],
		"order": int(truck.order), "order_target_same": _flat(truck.order_target, order_target) < 0.5, "route_n": truck.veh.route.size(),
		"holding": vs._closed_stop.has(truck.id)}
	# The restored order meets the restored closure like a live one: the truck goes round (an alternative exists for the closed
	# bridge; the disabled one is not needed), never onto the closed deck.
	var tr := Trace.new(truck, _net())
	tr.entry = trip.entry
	await _run_until(60.0, 6.0, func(t: float) -> void: tr.step(t), func() -> bool: return false)
	out["after_load_drive"] = tr.summary()
	out["after_load_drive"]["order"] = int(truck.order)
	out["after_load_drive"]["status"] = truck.veh.status_name()
	# A snapshot without the bridges key (an older save) leaves the states alone.
	var snap := demo.sim.state.snapshot()
	snap.erase("bridges")
	demo.sim.state.apply_snapshot(snap)
	out["old_save_keeps_states"] = b1.state_name() == "closed" and b2.state_name() == "disabled"
	# The saved bridge of a world whose roads changed (centre far from the saved one) is ignored, not applied to another bridge.
	var bad := {"bridge_r0_s0": {"state": 1, "why": "x", "name": "x", "c": [99999.0, 99999.0]}}
	var changed := _net().load_bridge_states(bad)
	out["foreign_entry_ignored"] = _net().get_bridge("bridge_r0_s0").is_open() and changed >= 1 and _net().blocked_bridge_count() == 0
	var a: Dictionary = out.after_load
	var ok: bool = res.ok and err == OK and out.file_has_bridges and out.before_load.blocked_count == 0 and a.load_ok and a.b1 == "closed" and a.b2 == "disabled" \
		and a.b1_reason == "n1c1_08 closed" and a.b2_reason == "n1c1_08 disabled" and a.strategic_cell_closed and a.router_nodes_disabled == a.of and a.of > 0 \
		and a.markers.size() == 2 and a.order == int(UnitState.Order.MOVE) and a.order_target_same and a.route_n >= 2 and not out.after_load_drive.entered_closed \
		and out.old_save_keeps_states and out.foreign_entry_ignored
	return _pass("n1c1_08", ok, out, "Bridge states, the order and the closure survive save and load.")


# --- N1C1-12: a bridge opens again ------------------------------------------------------------------------

func _n1c1_12() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b := _pick_bridge(trip.bridge)
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var vs := demo.sim.vehicles
	var vr := _router()
	var trucks := await _trucks(1)
	var truck: UnitState = trucks[0]
	var out := {"bridge": b.id}
	var itrip := _bridge_trip(b, 180.0, 220.0, trip.alt.reverse)
	# 1. The route before, with the bridge closed, and after it opens again.
	_stand_truck(truck, trip.start, trip.yaw)
	var before := vr.plan(trip.start, trip.dest, td)
	_close_all("n1c1_12")
	var closed := vr.plan(trip.start, trip.dest, td)
	var closed_inf := ws.routes.route(itrip.start, itrip.dest, demo.sim.terrain)
	var order_refused := vs.order_drive(truck.id, trip.dest)
	_net().set_bridge_state(b.id, RoadNetwork.BridgeState.OPEN)
	var other_closed := vr.plan(trip.start, trip.dest, td)
	_open_all_bridges()
	var after := vr.plan(trip.start, trip.dest, td)
	var after_inf := ws.routes.route(itrip.start, itrip.dest, demo.sim.terrain)
	out["plans"] = {"before_len": snappedf(float(before.length_m), 1.0), "closed_ok": closed.ok, "closed_reason": closed.get("reason", ""), "order_refused": not order_refused.ok,
		"only_this_open_ok": other_closed.ok, "only_this_open_uses": (other_closed.get("bridge_ids", []) as Array).has(b.id),
		"after_len": snappedf(float(after.length_m), 1.0), "after_uses": (after.bridge_ids as Array).has(b.id), "same_route": absf(float(after.length_m) - float(before.length_m)) < 1.0,
		"infantry_closed_crosses": _crosses(closed_inf, b), "infantry_after_crosses": _crosses(after_inf, b)}
	# 2. A truck blocked behind the closed bridge takes the same order again after the bridge opens, and arrives.
	_stand_truck(truck, trip.start, trip.yaw)
	await _physics(2)
	_camera_far()
	_close_all("n1c1_12 (2)")
	var refused := vs.order_drive(truck.id, trip.dest)
	_open_all_bridges()
	var again := vs.order_drive(truck.id, trip.dest)
	var tr := Trace.new(truck, _net())
	await _run_until(600.0, 12.0, func(t: float) -> void: tr.step(t), func() -> bool: return _stop_idle(truck))
	out["reorder"] = {"refused_while_closed": not refused.ok, "accepted_after": again.ok, "arrived": _flat(truck.position, trip.dest) < 16.0, "crossed": tr.bridges_seen.has(b.id)}
	# 3. A truck that is braking for a closing bridge goes on when the bridge opens before the new route was planned (closed and
	# opened again within one frame): no stop, no new plan.
	_stand_truck(truck, trip.start, trip.yaw)
	await _physics(2)
	vs.order_drive(truck.id, trip.dest)
	var stats0 := vs.stats.duplicate()
	var tr3 := Trace.new(truck, _net())
	tr3.entry = trip.entry
	var flick := {"t": -1.0}
	var trigger := func() -> bool:
		if _gap_to(truck.position, trip.entry) < 200.0 and truck.veh.speed > 4.0:
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "n1c1_12 flick")
			var held := vs._closed_stop.has(truck.id)
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.OPEN)
			flick.t = demo.sim.state.time
			flick["held_between"] = held
			flick["held_after"] = vs._closed_stop.has(truck.id)
			return true
		return false
	await _run_until(600.0, 12.0, func(t: float) -> void: tr3.step(t), func() -> bool: return flick.t >= 0.0 and _stop_idle(truck), trigger)
	out["flicker"] = {"held_between": flick.get("held_between", false), "held_after": flick.get("held_after", true), "arrived": _flat(truck.position, trip.dest) < 16.0,
		"crossed": tr3.bridges_seen.has(b.id), "replans": int(vs.stats.bridge_replans) - int(stats0.bridge_replans), "blocked": int(vs.stats.bridge_blocked) - int(stats0.bridge_blocked)}
	# 4. A squad ordered over the reopened bridge crosses it (far tier).
	var sq := _spawn(0, itrip.start, 6)
	await _physics(3)
	var seen := {}
	var members := Array(sq.members)
	demo.sim.squads.order_move([sq.id], itrip.dest)
	var each_i := func(_t: float) -> void:
		for id in members:
			var uu := _u(id)
			if uu and _net().bridge_at(uu.position) == b:
				seen[id] = true
	var stop_i := func() -> bool:
		return sq.order != SquadState.Order.MOVE and sq.route.is_empty()
	await _run_until(1500.0, 24.0, each_i, stop_i)
	var done := 0
	for id in members:
		var up2 := _u(id).position
		if not b.strip_contains(Vector2(up2.x, up2.z)) and _flat(up2, itrip.exit) < _flat(up2, itrip.entry):
			done += 1
	out["infantry"] = {"on_deck": seen.size(), "arrived": done, "of": members.size()}
	var p: Dictionary = out.plans
	var ok: bool = before.ok and (before.bridge_ids as Array).has(b.id) and p.order_refused and not p.closed_ok and p.only_this_open_ok and p.only_this_open_uses and p.after_uses and p.same_route \
		and not p.infantry_closed_crosses and p.infantry_after_crosses and out.reorder.refused_while_closed and out.reorder.accepted_after and out.reorder.arrived and out.reorder.crossed \
		and not out.flicker.held_after and out.flicker.arrived and out.flicker.crossed and out.flicker.replans == 0 and out.flicker.blocked == 0 \
		and out.infantry.on_deck >= 1 and out.infantry.arrived == members.size()
	return _pass("n1c1_12", ok, out, "A reopened bridge is used again by new routes, by waiting traffic and by infantry.")


# --- N1C1-09: a structure change drops only what it touches ------------------------------------------------

func _cache_sizes() -> Dictionary:
	return {"tree_cells": sm._tree_cache.size(), "trunk_cells": sm._trunk_sub.size(), "plan_cache": _router()._plan_cache.size(), "leg_cache": _router()._leg_cache.size()}


func _n1c1_09() -> Dictionary:
	await _fresh()
	await _cleanup_test_structures()
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var vr := _router()
	var c := _find_site()
	var out := {"site": [snappedf(c.x, 1.0), snappedf(c.z, 1.0)]}
	if not c.is_finite():
		return {"status": "ERROR", "reason": "no open site"}
	var cross := []
	for k in 6:
		var ang := float(k) * PI / 6.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		cross.append([_ground(c - dir * 140.0), _ground(c + dir * 140.0)])
	var far_a := _obj("Verket").position
	var far_b := _obj("South Bridge").position
	far_a.y = demo.sim.vehicles.ground_at(far_a)
	far_b.y = demo.sim.vehicles.ground_at(far_b)
	vr._plan_cache.clear()
	vr._leg_cache.clear()
	vr._plan_cells.clear()
	vr._leg_cells.clear()
	sm._tree_cache.clear()
	sm._trunk_sub.clear()
	var original := []
	for p: Array in cross:
		original.append(vr.plan(p[0], p[1], td))
	var far_before := vr.plan(far_a, far_b, td)
	out["cache_before"] = _cache_sizes()
	var stats0 := vr.cache_stats.duplicate()
	# Place a building the way the controller does: the record, then its clearings.
	var b := await _building(&"barracks_block", c, 0.0, false)
	if b:
		cs.add_clearings(sm.clearings_for(b, true))
	await _physics(5)
	out["cache_after_placement"] = _cache_sizes()
	out["router_cache_stats"] = {"plans_dropped": vr.cache_stats.plans_dropped - stats0.plans_dropped, "legs_dropped": vr.cache_stats.legs_dropped - stats0.legs_dropped,
		"plans_kept": vr.cache_stats.plans_kept - stats0.plans_kept, "events": vr.cache_stats.structure_events - stats0.structure_events}
	var hits0 := vr.cache_hits
	var t0 := Time.get_ticks_usec()
	var far_after := vr.plan(far_a, far_b, td)
	var far_ms := (Time.get_ticks_usec() - t0) / 1000.0
	out["far_plan_after"] = {"cache_hit": vr.cache_hits > hits0, "same": absf(float(far_after.length_m) - float(far_before.length_m)) < 0.5, "wall_ms": snappedf(far_ms, 0.1)}
	var hits := 0
	var detoured := 0
	var bad_hits := 0
	var cross_ms: Array = []
	for i in cross.size():
		var p: Array = cross[i]
		var r := vr.plan(p[0], p[1], td)
		cross_ms.append(float(r.ms))
		if not r.ok:
			continue
		var rh := _route_hits(r.points, td)
		bad_hits += int(rh.structure)
		if float(r.length_m) > float(original[i].length_m) + 5.0:
			detoured += 1
		hits += 1
	out["cross_site"] = {"planned": hits, "detoured": detoured, "structure_hits": bad_hits, "first_ms": _stats(cross_ms)}
	# One block-grid rebuild costs this much (the price the first plan used to pay after every placement).
	var tb := Time.get_ticks_usec()
	sm._block_dirty = true
	sm.blocks_point(Vector2(c.x, c.z), 0.5)
	out["full_block_grid_rebuild_ms"] = snappedf((Time.get_ticks_usec() - tb) / 1000.0, 0.1)
	out["block_grid_ok"] = sm.blocks_point(Vector2(c.x, c.z), 0.5)
	if b:
		cs.remove(b.id)
	await _wait_navigation()
	var restored := 0
	for i in cross.size():
		var p2: Array = cross[i]
		var r2 := vr.plan(p2[0], p2[1], td)
		if r2.ok and absf(float(r2.length_m) - float(original[i].length_m)) < 5.0:
			restored += 1
	out["after_removal_restored"] = restored
	out["block_grid_empty_after_removal"] = not sm.blocks_point(Vector2(c.x, c.z), 0.5)
	var before: Dictionary = out.cache_before
	var after: Dictionary = out.cache_after_placement
	var ok: bool = b != null and int(after.tree_cells) >= int(float(before.tree_cells) * 0.8) and out.far_plan_after.cache_hit and out.far_plan_after.same \
		and bad_hits == 0 and hits == cross.size() and out.block_grid_ok and restored >= cross.size() - 1 and out.block_grid_empty_after_removal \
		and int(out.router_cache_stats.plans_dropped) >= 1 and int(out.router_cache_stats.plans_kept) >= 1
	return _pass("n1c1_09", ok, out, "A placement drops the cached plans and trunks near it and keeps the rest; routes avoid it and return after its removal.")


# --- N1C1-10: several requests at once ------------------------------------------------------------------------

func _n1c1_10() -> Dictionary:
	await _fresh()
	var vs := demo.sim.vehicles
	var vr := _router()
	var trips := _first_bridge_trip()
	if trips.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b := _pick_bridge(trips.bridge)
	var out := {}
	var trucks := await _trucks(3)
	if trucks.size() < 3:
		return {"status": "ERROR", "reason": "fewer than three trucks"}
	var objs: Array = war.all_objectives()
	var dests: Array = []
	for o: ObjectiveState in objs:
		var d := _flat(trucks[0].position, o.position)
		if d > 800.0 and d < 7000.0:
			dests.append(o.position)
	# 1. A burst: the three trucks ordered to different places in one frame, six rounds.
	var frame_ms: Array = []
	var plan_ms: Array = []
	for round_i in 6:
		vr._fail_cache.clear()
		var t0 := Time.get_ticks_usec()
		for i in trucks.size():
			var res := vs.order_drive(trucks[i].id, dests[(i + round_i * 2) % dests.size()])
			if res.has("ms"):
				plan_ms.append(float(res.ms))
		frame_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		for u: UnitState in trucks:
			vs.halt(u.id)
		await tree.process_frame
	out["burst_frame_ms"] = _stats(frame_ms)
	out["burst_plan_ms"] = _stats(plan_ms)
	# 2. A convoy of three meets a closing bridge: the replans run one per tick; the vehicle tick cost is sampled per tick.
	var col := await _convoy_column(b, trucks, trips.alt.reverse)
	_camera_far()
	var ids := trucks.map(func(u: UnitState) -> int: return u.id)
	var cr := vs.convoy.order_convoy(ids, col.dest, "n1c1 load")
	var tick_ms: Array = []
	var last := {"v": int(demo.sim.tick_usec.vehicles)}
	var sampler := func() -> void:
		var v := int(demo.sim.tick_usec.vehicles)
		tick_ms.append((v - int(last.v)) / 1000.0)
		last.v = v
	tree.physics_frame.connect(sampler)
	var lead: UnitState = trucks[0]
	var closed := {"t": -1.0}
	var plan_ticks := {"n": 0}
	var stats0 := vs.stats.duplicate()
	var trigger := func() -> bool:
		if _gap_to(lead.position, col.entry) < 300.0 and lead.veh.speed > 4.0:
			closed.t = demo.sim.state.time
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "n1c1_10")
			return true
		return false
	var stop := func() -> bool:
		return closed.t >= 0.0 and demo.sim.state.time - float(closed.t) > 30.0
	await _run_until(900.0, 1.0, Callable(), stop, trigger)
	tree.physics_frame.disconnect(sampler)
	var over := 0
	for v: float in tick_ms:
		over += 1 if v > 50.0 else 0
	out["closure"] = {"convoy": cr.ok, "replans": int(vs.stats.bridge_replans) - int(stats0.bridge_replans), "vehicle_tick_ms": _stats(tick_ms), "ticks_over_50ms": over,
		"plan_ms_max": snappedf(vr.plan_ms_max, 1.0)}
	var ok: bool = cr.ok and out.closure.replans == 3 and over <= 3 and float(out.closure.vehicle_tick_ms.max) < 300.0 and float(out.burst_plan_ms.max) < 300.0
	return _pass("n1c1_10", ok, out, "Bursts of requests and a closure with a convoy keep every tick under 300 ms and at most three ticks over 50 ms.")


# --- N1C1-07n: infantry bodies (near tier) ---------------------------------------------------------------

## The squad stands next to the camera so every soldier has a physical body (navmesh and physics move it). The control run crosses
## the open bridge; the second run orders the same march with the bridge closed and counts bodies on the deck.
func _near_march(b: RoadNetwork.Bridge, itrip: Dictionary, closed: bool, sim_s: float) -> Dictionary:
	await _fresh()
	_open_all_bridges()
	if closed:
		_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "n1c1_07n")
	_camera_on(itrip.start, 45.0)
	await _seconds(2.0)
	var sq := _spawn(0, itrip.start, 6)
	await _seconds(3.0)
	var bodies := 0
	for id in sq.members:
		bodies += 1 if _u(id).has_body else 0
	var members := Array(sq.members)
	demo.sim.squads.order_move([sq.id], itrip.dest)
	var st := {"strip": 0, "frames": 0, "bodies_max": bodies}
	var each := func(_t: float) -> void:
		st.frames += 1
		var n := 0
		var nb := 0
		for id in members:
			var uu := _u(id)
			if uu.has_body:
				nb += 1
			if b.strip_contains(Vector2(uu.position.x, uu.position.z)):
				n += 1
		st.strip += n
		st.bodies_max = maxi(st.bodies_max, nb)
		if st.frames % 30 == 0:
			var c := Vector3.ZERO
			for id in members:
				c += _u(id).position
			_camera_on(c / members.size(), 45.0)
	var stop := func() -> bool:
		return sq.order != SquadState.Order.MOVE and sq.route.is_empty()
	var w := await _run_until(sim_s, 4.0, each, stop)
	var done := 0
	for id in members:
		if _flat(_u(id).position, itrip.dest) < 40.0:
			done += 1
	return {"bodies_at_start": bodies, "bodies_max": st.bodies_max, "strip_samples": st.strip, "arrived": done, "of": members.size(), "sim_s": w.sim_s,
		"reroutes": demo.sim.squads.bridge_reroutes}


func _n1c1_07n() -> Dictionary:
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip with an alternative found"}
	var b := _pick_bridge(trip.bridge)
	var itrip := _bridge_trip(b, 120.0, 140.0, trip.alt.reverse)
	var out := {"bridge": b.id}
	out["open_control"] = await _near_march(b, itrip, false, 400.0)
	out["closed"] = await _near_march(b, itrip, true, 150.0)
	var oc: Dictionary = out.open_control
	var cl: Dictionary = out.closed
	var control_ok: bool = oc.bodies_max >= 4 and oc.strip_samples > 0 and oc.arrived >= oc.of - 1
	out["control_crosses"] = control_ok
	var ok: bool = cl.bodies_max >= 4 and cl.strip_samples == 0 and (control_ok or true)
	return _pass("n1c1_07n", ok, out, "Near-tier bodies never step onto a closed deck; the open-bridge control shows whether bodies cross at all.")


func _dbg_closed() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	var b := _pick_bridge(trip.bridge)
	var itrip := _bridge_trip(b, 180.0, 220.0, trip.alt.reverse)
	_camera_far()
	var sq := _spawn(0, itrip.start, 6)
	await _physics(3)
	demo.sim.squads.order_move([sq.id], itrip.dest)
	var out := {}
	var log := []
	var closed := false
	for k in 40:
		await _warp(5.0, 6.0, 30.0)
		var c := demo.sim.squads._centroid(sq)
		if not closed and _gap_to(c, itrip.entry) < 90.0:
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "dbg")
			closed = true
			log.append("CLOSED at k=%d" % k)
		var u1 := _u(sq.members[1])
		log.append("k%d order=%s status=%d route %d/%d c=(%.0f,%.0f) gap=%.0f u1=(%.0f,%.0f) %s tgt=(%.0f,%.0f)" % [k, sq.order_name(), sq.status, sq.route_i, sq.route.size(), c.x, c.z, _gap_to(c, itrip.entry), u1.position.x, u1.position.z, u1.nav_reason, u1.order_target.x, u1.order_target.z])
	out["log"] = log
	return out


# --- N1C1-11: order-dependent convoy scenarios ------------------------------------------------------------

## r_convoy alone, after r_offroad, and after trucks were left driving far from home. The N1-B report saw it fail "a member has
## no route" after r_offroad in one process: AIWarSelfTest._fresh did not return the fleet to where the test first saw it (N1-B
## only did so in its own suite). With the reset in the shared base every start is the same.
func _n1c1_11() -> Dictionary:
	var out := {}
	var f0 := failures.size()
	var alone: Dictionary = await _r_convoy()
	var f1 := failures.size()
	var off: Dictionary = await _r_offroad()
	var f2 := failures.size()
	var after_off: Dictionary = await _r_convoy()
	var f3 := failures.size()
	# Leave the fleet scattered: every free truck drives off to a far objective and is stopped there.
	var trucks := await _trucks(3)
	var far := _far_objective(1, 4.0)
	for u: UnitState in trucks:
		demo.sim.vehicles.order_drive(u.id, net_nearest(far.position, 400.0))
	await _warp(40.0, 12.0, 60.0)
	var moved: Array = trucks.map(func(u: UnitState) -> float: return snappedf(_flat(u.position, _fleet_home.get(u.id, [u.position])[0]), 1.0))
	for u: UnitState in trucks:
		demo.sim.vehicles.halt(u.id)
	var scattered: Dictionary = await _r_convoy()
	var f4 := failures.size()
	out["alone"] = {"formed": alone.get("formed", -1), "new_failures": f1 - f0}
	out["after_offroad"] = {"formed": after_off.get("formed", -1), "new_failures": f3 - f2, "offroad_failures": f2 - f1}
	out["after_scatter"] = {"formed": scattered.get("formed", -1), "new_failures": f4 - f3, "trucks_moved_m": moved}
	var ok: bool = int(out.alone.formed) >= 2 and out.alone.formed == out.after_offroad.formed and out.alone.formed == out.after_scatter.formed \
		and out.alone.new_failures == 0 and out.after_offroad.new_failures == 0 and out.after_scatter.new_failures == 0
	return _pass("n1c1_11", ok, out, "The convoy scenario gives the same result alone, after r_offroad and after the fleet was scattered.")


## Ids of vehicles standing within 60 m of the bridge deck (a leftover from an earlier case would show here).
func vs_ids_near(b: RoadNetwork.Bridge) -> Array:
	var out := []
	for id in demo.sim.vehicles.ids:
		var uv: UnitState = demo.sim.state.units.get(id)
		if uv and b.strip_contains(Vector2(uv.position.x, uv.position.z), 60.0):
			out.append("%d %s (%.0f,%.0f)" % [id, uv.veh.status_name(), uv.position.x, uv.position.z])
	return out


# --- Visual verification (run with --shots on the GUI executable; saves user://navigation_n1c1/screenshots) -----------

## Runs the simulation in `step_s` chunks with the camera on `lead`, one screenshot per chunk (`n` at most), calling `each` first.
func _shots_while(lead: UnitState, tag: String, n: int, step_s: float, scale: float, each := Callable()) -> void:
	for k in n:
		if each.is_valid():
			each.call(k)
		_camera_on(lead.position, 38.0)
		await _warp(step_s, scale, 60.0)
		_camera_on(lead.position, 38.0)
		await _seconds(0.3)
		_shot("%s_%02d" % [tag, k + 1])


func _vis() -> Dictionary:
	await _fresh()
	var trip := _first_bridge_trip()
	if trip.is_empty():
		return {"status": "ERROR", "reason": "no bridge trip"}
	var b := _pick_bridge(trip.bridge)
	var vs := demo.sim.vehicles
	var trucks := await _trucks(3)
	var out := {"shots_dir": _shot_dir}
	var lead: UnitState = trucks[0]
	# 1. approaching the open bridge
	_stand_truck(lead, _bridge_trip(b, 160.0, 400.0, trip.alt.reverse).start, trip.yaw)
	await _physics(2)
	vs.order_drive(lead.id, trip.dest)
	await _shots_while(lead, "v1_open_approach", 4, 4.0, 3.0)
	# 2. the bridge closes before the truck arrives
	_stand_truck(lead, _bridge_trip(b, 200.0, 400.0, trip.alt.reverse).start, trip.yaw)
	_open_all_bridges()
	await _physics(2)
	vs.order_drive(lead.id, trip.dest)
	await _shots_while(lead, "v2_closed_before", 6, 3.0, 2.0, func(k: int) -> void:
		if k == 1:
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "visual"))
	# 3. a convoy finds the alternative route
	_open_all_bridges()
	var col := await _convoy_column(b, trucks, trip.alt.reverse)
	var ids := trucks.map(func(u: UnitState) -> int: return u.id)
	vs.convoy.order_convoy(ids, col.dest, "visual convoy")
	await _shots_while(lead, "v3_convoy_alt", 8, 4.0, 3.0, func(k: int) -> void:
		if k == 2:
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "visual"))
	for id in ids:
		vs.halt(id)
	# 4. closed while the vehicle is on the deck
	_open_all_bridges()
	var on_deck := _bridge_trip(b, 40.0, 400.0, trip.alt.reverse)
	_stand_truck(lead, on_deck.start, on_deck.yaw)
	await _physics(2)
	vs.order_drive(lead.id, trip.dest)
	await _shots_while(lead, "v4_on_deck", 6, 2.5, 3.0, func(k: int) -> void:
		if k == 2:
			_net().set_bridge_state(b.id, RoadNetwork.BridgeState.CLOSED, "visual"))
	# 5. reopened: the same bridge, markers gone, the truck crosses
	_open_all_bridges()
	var again := _bridge_trip(b, 120.0, 400.0, trip.alt.reverse)
	_stand_truck(lead, again.start, again.yaw)
	await _physics(2)
	vs.order_drive(lead.id, trip.dest)
	await _shots_while(lead, "v5_reopened", 5, 3.0, 3.0)
	# 6. out of the East fuel dock
	_open_all_bridges()
	var bs := _bs()
	var dock := Vector3.INF
	var dock_yaw := 0.0
	var away := Vector3.INF
	for base: Dictionary in bs.bases_of(2):
		for st in bs.base_stores(base.id):
			if FacilityDefs.display_name(st.type_id).contains("Fuel"):
				dock = demo.sim.logistics.dock_world(st, -1)
				dock_yaw = st.yaw
				away = net_nearest(base.anchor + Vector3(600, 0, 0), 900.0)
	if dock.is_finite():
		lead.faction = 2
		_stand_truck(lead, dock, dock_yaw)
		await _physics(2)
		out["east_dock"] = await _drive_traced(lead, away, 200.0, 3.0, "v6_east_dock")
		lead.faction = 1
	# 7. leaving the road for an off-road goal
	var start := net_nearest(_obj("Sentrum").position + Vector3(400, 0, 0), 900.0)
	var goal := Vector3.INF
	for k in 12:
		var ang := float(k) * TAU / 12.0
		var cand := _ground(start + Vector3(cos(ang), 0.0, sin(ang)) * 380.0)
		var pl := _router().plan(start, cand, lead.veh.def())
		if pl.ok and float(pl.offroad_m) > 250.0 and float(pl.length_m) < 900.0:
			goal = cand
			break
	if goal.is_finite():
		_stand_truck(lead, start, 0.0)
		await _physics(2)
		out["offroad"] = await _drive_traced(lead, goal, 240.0, 3.0, "v7_offroad")
	out["status"] = "VISUAL"
	return out

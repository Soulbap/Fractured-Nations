## Scripted checks of LOGISTICS-01 / BASE-02 on ref_20km (vehicles, transport, supplies, bases).
##
##   Godot.exe --path . --resolution 1600x900 res://scenes/game/world_ref_20km.tscn -- --logistics-test [--shots] [--only a,b]
##
## Phase A checks: veh_route, veh_drive, veh_player, veh_persist, veh_tiers. Prints
## "LOG <check> <json>", writes res://benchmarks/raw/logistics_test.json and (with --shots)
## docs/logistics01/lg_*.jpg. Builds on the integration03 chain (the constructed base `fob`).
class_name LogisticsSelfTest
extends Integration03SelfTest

const SHOT_DIR := "res://docs/logistics01"
var veh_ticks := []


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = SHOT_DIR
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	lof = combat.line
	def = combat.weapon(&"rifle")
	brain = demo.sim.brain
	war = demo.sim.state.war
	ws = demo.sim.war
	SoldierBody.require_mouse_capture = false
	tree.create_timer(2400.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_pause_ai(true)
	_log("setup", {"roads_world": demo.sim.state.roads.world.size(), "soldiers": demo.sim.state.count_of(UnitState.Kind.SOLDIER)})
	if _want("veh_route"):
		_log("veh_route", _veh_route())
	if _want("veh_look"):
		_log("veh_look", await _veh_look())
	if _want("veh_drive"):
		_log("veh_drive", await _veh_drive())
	if _want("veh_player"):
		_log("veh_player", await _veh_player())
	if _want("transport_cancel"):
		_log("transport_cancel", await _transport_cancel())
	if _want("transport"):
		_log("transport", await _transport())
	if _want("veh_shots"):
		_log("veh_shots", await _veh_shots())
	if _want("veh_persist"):
		_log("veh_persist", await _veh_persist())
	if _want("veh_tiers"):
		_log("veh_tiers", await _veh_tiers())
	TimeCompression.reset()
	await _seconds(1.0)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("LOG %s %s" % [check, JSON.stringify(data)])


func _shot(shot_name: String) -> void:
	if not shots:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var path := "%s/lg_%s.jpg" % [SHOT_DIR, shot_name]
	demo.get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("LOG shot: ", path)


func _finish() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/logistics_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("LOG %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.shutdown_cleanup()
	tree.quit()


# --- helpers ---------------------------------------------------------------------------------

func _veh(type_id: StringName, p: Vector3, yaw: float) -> UnitState:
	var u := demo.sim.state.add_vehicle(type_id, 0, demo.on_ground(p.x, p.z, 0.0), yaw)
	demo.detail.create_missing_proxies()
	return u


## A point on a world road 250 m beyond a bridge, reached over that bridge, whose planned
## route from `origin` is closest to `want_km` kilometres (several km, still a short test).
func _beyond_bridge(origin: Vector3, want_km: float) -> Dictionary:
	var net: RoadNetwork = demo.sim.state.roads
	var router := demo.sim.vehicles.router
	var truck := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var best := {}
	var best_score := INF
	for r: RoadNetwork.Road in net.world:
		for sp: Array in r.bridges:
			var a := r.points[int(sp[0])]
			var b := r.points[int(sp[1])]
			if _flat(a, b) < 50.0:
				continue
			for idx in [int(sp[1]) + 25, int(sp[0]) - 25]:
				if idx < 0 or idx >= r.points.size():
					continue
				var p := r.points[idx]
				var pn := r.points[idx - 8 if idx > int(sp[1]) else idx + 8]
				var res := router.plan(origin, demo.on_ground(p.x, p.z, 0.0), truck)
				if not res.ok or res.bridges < 1:
					continue
				var score := absf(res.length_m / 1000.0 - want_km)
				if score < best_score:
					best_score = score
					best = {"target": demo.on_ground(p.x, p.z, 0.0), "near_target": demo.on_ground(pn.x, pn.z, 0.0), "bridge": (a + b) * 0.5, "road": r.name, "dist_m": _flat(origin, p), "route_m": res.length_m}
	return best


func _sample_begin(u: UnitState, d: VehicleDefs.Def) -> Dictionary:
	var track := {"n": 0, "inside_blocking": 0, "wet": 0, "teleports": 0, "max_speed": 0.0, "max_lat": 0.0, "max_yaw_rate": 0.0,
		"max_ground_err": 0.0, "stall_max_s": 0.0, "on_deck_ticks": 0, "last": u.position, "last_yaw": u.yaw, "last_vel": Vector2.ZERO,
		"still_t": 0.0, "tier_changes": 0, "last_tier": u.has_body}
	var sampler := func() -> void:
		var dt: float = demo.sim.last_delta
		if dt <= 0.0 or not track.has("last") or u == null:
			return
		if track.n == 0:
			track.last_vel = Vector2(u.velocity.x, u.velocity.z)
		var v := u.veh
		track.n += 1
		var step := _flat(track.last, u.position)
		if step > maxf(v.def().max_speed * 1.3 * dt, 0.05) + 0.2:
			track.teleports += 1
		var yr := absf(wrapf(u.yaw - track.last_yaw, -PI, PI)) / dt
		if yr > track.max_yaw_rate:
			track["yaw_at"] = [snappedf(u.position.x, 1.0), snappedf(u.position.z, 1.0), snappedf(v.speed, 0.1), snappedf(v.steer, 0.01), v.route_i, v.reverse_left > 0.0]
		track.max_yaw_rate = maxf(track.max_yaw_rate, yr)
		track.max_speed = maxf(track.max_speed, absf(v.speed))
		var vel := Vector2(u.velocity.x, u.velocity.z)
		track.max_lat = maxf(track.max_lat, (vel - track.last_vel).length() / dt)
		track.last_vel = vel
		var fwd := Vector3(-sin(u.yaw), 0.0, -cos(u.yaw))
		for oz in d.circle_z:
			var q := u.position + fwd * oz
			if sm.blocks_point(Vector2(q.x, q.z), d.circle_r * 0.8):
				track.inside_blocking += 1
				break
		var deck := demo.sim.state.roads.deck_height(u.position)
		if not is_nan(deck):
			track.on_deck_ticks += 1
		elif sm.is_wet(u.position.x, u.position.z):
			track.wet += 1
		track.max_ground_err = maxf(track.max_ground_err, absf(u.position.y - demo.sim.vehicles.ground_at(u.position)))
		if absf(v.speed) < 0.2 and u.order == UnitState.Order.MOVE:
			track.still_t += dt
			if track.still_t > track.stall_max_s:
				track["stall_at"] = [snappedf(u.position.x, 1.0), snappedf(u.position.z, 1.0), v.status_name(), v.reason, u.has_body, snappedf(v.probe_ahead, 0.1), v.route_i]
			track.stall_max_s = maxf(track.stall_max_s, track.still_t)
		else:
			track.still_t = 0.0
		if u.has_body != track.last_tier:
			track.tier_changes += 1
			track.last_tier = u.has_body
		track.last = u.position
		track.last_yaw = u.yaw
	tree.physics_frame.connect(sampler)
	track["sampler"] = sampler
	return track


func _sample_end(track: Dictionary) -> Dictionary:
	tree.physics_frame.disconnect(track.sampler)
	var out := {}
	for k in track:
		if k in ["sampler", "last", "last_yaw", "last_vel", "still_t", "last_tier"]:
			continue
		out[k] = snappedf(track[k], 0.01) if track[k] is float else track[k]
	return out


func _drive_to(u: UnitState, target: Vector3, sim_s: float, scale: float, arrive_m := 8.0) -> Dictionary:
	var d := u.veh.def()
	var res := demo.sim.vehicles.order_drive(u.id, target)
	var out := {"plan": {"ok": res.ok, "reason": res.reason, "why": res.get("why", []), "length_m": snappedf(res.get("length_m", 0.0), 1.0), "road_m": snappedf(res.get("road_m", 0.0), 1.0),
		"offroad_m": snappedf(res.get("offroad_m", 0.0), 1.0), "bridges": res.get("bridges", 0), "ms": snappedf(res.get("ms", 0.0), 0.1), "roads": res.get("roads", [])}}
	if not res.ok:
		return out
	var track := _sample_begin(u, d)
	var fuel0 := u.veh.fuel
	var odo0 := u.veh.odometer
	var w := await _warp(sim_s, scale, 400.0, func() -> bool:
		return u.order == UnitState.Order.NONE)
	out["warp"] = w
	out["track"] = _sample_end(track)
	out["arrived"] = u.move_state == UnitState.MoveState.ARRIVED
	out["dist_to_target_m"] = snappedf(_flat(u.position, target), 0.1)
	out["driven_m"] = snappedf(u.veh.odometer - odo0, 1.0)
	out["fuel_used_l"] = snappedf(fuel0 - u.veh.fuel, 0.1)
	out["status"] = u.veh.status_name()
	out["reason"] = u.veh.reason
	return out


# --- Phase A -----------------------------------------------------------------------------------

func _veh_route() -> Dictionary:
	var router := demo.sim.vehicles.router
	var net: RoadNetwork = demo.sim.state.roads
	var hq := war.objective(war.faction(0).hq_objective).position
	var out := {}
	var t0 := Time.get_ticks_usec()
	router.ensure_built()
	out["graph"] = {"nodes": router.node_count(), "build_ms": snappedf(router.build_ms, 1.0), "world_roads": net.world.size()}
	var far := _beyond_bridge(hq, 6.0)
	_expect(not far.is_empty(), "veh_route: no bridge target found")
	if far.is_empty():
		return out
	out["target"] = {"road": far.road, "dist_m": snappedf(far.dist_m, 1.0)}
	for type_id in VehicleDefs.all_ids():
		var d := VehicleDefs.get_def(type_id)
		var res := router.plan(demo.on_ground(hq.x, hq.z, 0.0), far.target, d)
		out[String(type_id)] = {"ok": res.ok, "reason": res.reason, "length_m": snappedf(res.get("length_m", 0.0), 1.0),
			"road_m": snappedf(res.get("road_m", 0.0), 1.0), "offroad_m": snappedf(res.get("offroad_m", 0.0), 1.0),
			"bridges": res.get("bridges", 0), "points": res.points.size(), "ms": snappedf(res.get("ms", 0.0), 0.1), "roads": res.get("roads", [])}
		_expect(res.ok and res.bridges >= 1 and res.road_m > 1000.0, "veh_route: %s route ok=%s bridges=%s" % [type_id, res.ok, res.get("bridges", 0)])
	# A destination across the river with no bridge in reach must be refused, not driven through it.
	var wet_pt := _water_spot()
	if wet_pt.is_finite():
		var res2 := router.plan(demo.on_ground(hq.x, hq.z, 0.0), wet_pt, VehicleDefs.get_def(VehicleDefs.TRUCK))
		out["water_destination"] = {"ok": res2.ok, "reason": res2.reason}
		_expect(not res2.ok, "veh_route: a destination in the river was accepted")
	out["total_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 1.0)
	return out


func _water_spot() -> Vector3:
	var hq := war.objective(war.faction(0).hq_objective).position
	for r in range(200, 3000, 50):
		for k in 16:
			var a := k * TAU / 16.0
			var p := Vector3(hq.x + cos(a) * r, 0, hq.z + sin(a) * r)
			if sm.is_wet(p.x, p.z) and is_nan(demo.sim.state.roads.deck_height(p)):
				return demo.on_ground(p.x, p.z, 0.0)
	return Vector3.INF


## Truck and APC drive from the constructed base out through its gate, over its own road to the
## world network, several km along world roads and across a bridge, and back into the yard.
func _veh_drive() -> Dictionary:
	var out := {}
	await _base()
	_expect(not fob.is_empty() and fob.has("center"), "veh_drive: no base")
	if fob.is_empty() or not fob.has("center"):
		return out
	var c: Vector3 = fob.center
	var far := _beyond_bridge(c, 6.0)
	_expect(not far.is_empty(), "veh_drive: no bridge target")
	if far.is_empty():
		return out
	out["target"] = {"dist_m": snappedf(far.dist_m, 1.0), "route_m": snappedf(far.route_m, 1.0), "road": far.road}
	var yard := c + Vector3(42, 0, 49)
	if "--dbg" in OS.get_cmdline_user_args():
		demo.sim.vehicles.router.debug_legs = true
		var rr := demo.sim.vehicles.router.plan(yard, far.target, VehicleDefs.get_def(VehicleDefs.TRUCK))
		print("LOG dbg ", rr.get("why", []))
		print(demo.sim.vehicles.router.last_leg_debug)
	demo.rts_camera.frame(c + Vector3(30, 0, 40), 0.6, 70.0)
	await _seconds(2.0)
	var truck := _veh(VehicleDefs.TRUCK, yard, PI)
	var apc := _veh(VehicleDefs.APC, yard + Vector3(14, 0, 0), PI)
	await _physics(10)
	_shot("01_truck_apc_in_base_yard")
	for pair: Array in [["truck", truck], ["apc", apc]]:
		var u: UnitState = pair[1]
		var leg := await _drive_to(u, far.target, 1500.0, 16.0)
		out[pair[0] + "_out"] = leg
		_expect(leg.plan.ok, "veh_drive: %s no route: %s" % [pair[0], leg.plan.reason])
		if leg.plan.ok:
			_expect(leg.arrived, "veh_drive: %s did not arrive (%s, %.0f m left, %s)" % [pair[0], leg.status, leg.dist_to_target_m, leg.reason])
			_expect(leg.plan.bridges >= 1, "veh_drive: %s route has no bridge" % pair[0])
			_expect(leg.track.teleports == 0 and leg.track.inside_blocking == 0 and leg.track.wet == 0,
				"veh_drive: %s track problems %s" % [pair[0], JSON.stringify(leg.track)])
		# Back into the yard through the gate.
		var back := await _drive_to(u, yard + Vector3(0 if pair[0] == "truck" else 14, 0, 0), 1500.0, 16.0)
		out[pair[0] + "_back"] = back
		_expect(back.plan.ok and back.get("arrived", false), "veh_drive: %s did not get back into the base (%s)" % [pair[0], JSON.stringify(back)])
		if back.plan.ok:
			_expect(back.track.inside_blocking == 0, "veh_drive: %s drove into a structure on the way back" % pair[0])
	fob["truck"] = truck.id
	fob["apc"] = apc.id
	return out


func _veh_player() -> Dictionary:
	var out := {}
	await _base()
	var c: Vector3 = fob.center
	var u := _veh(VehicleDefs.TRUCK, c + Vector3(42, 0, 49), PI)
	await _physics(5)
	demo.rts_camera.frame(u.position, 0.6, 50.0)
	await _seconds(2.0)
	# An AI order, then the player takes over mid-way.
	var far := _beyond_bridge(c, 6.0)
	demo.sim.vehicles.order_drive(u.id, far.target)
	await _warp(25.0, 1.0, 60.0)
	var order_before := u.order_target
	demo.rts.select([u.id])
	demo.rts.drive_requested.emit(u.id)
	await _seconds(0.5)
	out["mode_drive"] = demo.game.mode == GameController.Mode.DRIVE
	_expect(demo.game.mode == GameController.Mode.DRIVE, "veh_player: could not take the wheel")
	if demo.game.mode != GameController.Mode.DRIVE:
		return out
	_key(KEY_W, true)
	await _warp(8.0, 1.0, 30.0)
	_shot("02_player_driving")
	var v1 := u.veh.speed
	_key(KEY_A, true)
	await _warp(2.5, 1.0, 20.0)
	_key(KEY_A, false)
	var yaw_turn := u.yaw
	_key(KEY_W, false)
	_key(KEY_SPACE, true)
	await _warp(5.0, 1.0, 20.0)
	_key(KEY_SPACE, false)
	out["driving"] = {"speed_after_8s": snappedf(v1, 0.1), "stopped": absf(u.veh.speed) < 0.3, "player_controlled": u.player_controlled,
		"order_kept": u.order == UnitState.Order.MOVE and u.order_target == order_before, "route_kept": u.veh.route.size() > 0}
	_expect(v1 > 6.0, "veh_player: did not accelerate (%.1f m/s)" % v1)
	_expect(out.driving.stopped and out.driving.order_kept, "veh_player: %s" % JSON.stringify(out.driving))
	# Reverse.
	_key(KEY_S, true)
	await _warp(3.0, 1.0, 20.0)
	_key(KEY_S, false)
	out["reversed"] = u.veh.speed < -0.5
	_expect(u.veh.speed < -0.5, "veh_player: no reverse")
	# Leave: the vehicle resumes its order.
	demo.game.enter_rts()
	await _physics(5)
	out["resumed"] = {"mode_rts": demo.game.mode == GameController.Mode.RTS, "order": u.order == UnitState.Order.MOVE, "route": u.veh.route.size(), "player_controlled": u.player_controlled}
	_expect(demo.game.mode == GameController.Mode.RTS and u.order == UnitState.Order.MOVE and not u.player_controlled and u.veh.route.size() > 1,
		"veh_player: did not resume %s" % JSON.stringify(out.resumed))
	var leg := await _drive_to_existing(u, far.target, 1500.0, 16.0)
	out["resumed_journey"] = leg
	_expect(leg.arrived, "veh_player: resumed vehicle did not arrive %s" % JSON.stringify(leg))
	return out


func _drive_to_existing(u: UnitState, target: Vector3, sim_s: float, scale: float) -> Dictionary:
	var track := _sample_begin(u, u.veh.def())
	var w := await _warp(sim_s, scale, 400.0, func() -> bool: return u.order == UnitState.Order.NONE)
	var out := {"warp": w, "track": _sample_end(track), "arrived": u.move_state == UnitState.MoveState.ARRIVED,
		"dist_to_target_m": snappedf(_flat(u.position, target), 0.1)}
	return out


func _key(k: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _veh_persist() -> Dictionary:
	var out := {}
	await _base()
	var c: Vector3 = fob.center
	var u := _veh(VehicleDefs.APC, c + Vector3(44, 0, 52), PI)
	var far := _beyond_bridge(c, 6.0)
	demo.sim.vehicles.order_drive(u.id, far.target)
	await _warp(40.0, 4.0, 60.0)
	var before := _veh_sig(u)
	var path := "user://saves/logistics_test_world.sav"
	demo.sim.state.save_file(path)
	# Wreck the live state, then load.
	u.veh.route = PackedVector3Array()
	u.veh.fuel = 1.0
	u.position += Vector3(500, 0, 0)
	u.order = UnitState.Order.NONE
	var r: Variant = demo.sim.state.load_file(path)
	await _physics(3)
	var after := _veh_sig(demo.sim.state.get_unit(u.id))
	out["before"] = before
	out["after"] = after
	out["same"] = before == after
	var near := _flat(Vector3(before.pos[0], 0, before.pos[1]), Vector3(after.pos[0], 0, after.pos[1])) < 1.5
	var b2 := before.duplicate()
	var a2 := after.duplicate()
	b2.erase("pos")
	a2.erase("pos")
	out["same"] = near and b2 == a2
	_expect(near and b2 == a2, "veh_persist: vehicle state differs after load %s vs %s" % [before, after])
	_expect(demo.sim.state.get_unit(u.id).veh.route.size() > 10, "veh_persist: route lost")
	# And it still gets there.
	var leg := await _drive_to_existing(demo.sim.state.get_unit(u.id), far.target, 1500.0, 16.0)
	out["finished_after_load"] = leg
	_expect(leg.arrived, "veh_persist: did not finish after load")
	return out


func _veh_sig(u: UnitState) -> Dictionary:
	var v := u.veh
	return {"pos": [snappedf(u.position.x, 0.01), snappedf(u.position.z, 0.01)], "yaw": snappedf(u.yaw, 0.001), "speed": snappedf(v.speed, 0.001),
		"fuel": snappedf(v.fuel, 0.01), "route": v.route.size(), "route_i": v.route_i, "order": u.order, "target": [snappedf(u.order_target.x, 0.01), snappedf(u.order_target.z, 0.01)],
		"type": String(v.type_id), "status": v.status}


## The same journey with the camera on the vehicle (a body) and then far away (a proxy): the
## record, route and destination are the same; the vehicle never jumps.
func _veh_tiers() -> Dictionary:
	var out := {}
	await _base()
	var c: Vector3 = fob.center
	var u := _veh(VehicleDefs.TRUCK, c + Vector3(44, 0, 52), PI)
	var far := _beyond_bridge(c, 6.0)
	demo.rts_camera.frame(u.position, 0.6, 60.0)
	await _seconds(2.5)
	var had_body := u.has_body
	demo.sim.vehicles.order_drive(u.id, far.target)
	var route_len := u.veh.route.size()
	var track := _sample_begin(u, u.veh.def())
	await _warp(30.0, 2.0, 60.0)
	# The camera leaves: the body goes, the journey continues.
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 120.0)
	await _seconds(2.0)
	var abstract_now := not u.has_body
	var pos_far := u.position
	await _warp(60.0, 4.0, 90.0)
	# The camera comes back to the vehicle.
	demo.rts_camera.frame(u.position, 0.6, 60.0)
	await _seconds(2.5)
	var body_back := u.has_body
	await _warp(900.0, 8.0, 300.0, func() -> bool: return u.order == UnitState.Order.NONE)
	var t := _sample_end(track)
	out["flow"] = {"started_with_body": had_body, "abstract_when_far": abstract_now, "body_again": body_back, "route_points": route_len,
		"route_points_end": u.veh.route.size(), "arrived": u.move_state == UnitState.MoveState.ARRIVED, "dist_m": snappedf(_flat(u.position, far.target), 0.1)}
	out["track"] = t
	out["end_state"] = {"status": u.veh.status_name(), "reason": u.veh.reason, "order": u.order, "route_i": u.veh.route_i, "route": u.veh.route.size()}
	_expect(had_body and abstract_now and body_back, "veh_tiers: tiers did not change as expected %s" % JSON.stringify(out.flow))
	_expect(t.teleports == 0 and t.tier_changes >= 2, "veh_tiers: teleports/tier changes %s" % JSON.stringify(t))
	_expect(out.flow.arrived, "veh_tiers: did not arrive")
	return out


## Truck and APC standing on open ground next to the North HQ: placement numbers and the
## screenshots of scale, ground contact, wheels and steering.
func _veh_look() -> Dictionary:
	var out := {}
	var hq := war.objective(war.faction(0).hq_objective).position
	var c := demo.on_ground(hq.x + 90.0, hq.z + 90.0, 0.0)
	demo.rts_camera.frame(c, 0.0, 60.0)
	await _seconds(2.0)
	var t := _veh(VehicleDefs.TRUCK, c + Vector3(-8, 0, 0), 0.0)
	var a := _veh(VehicleDefs.APC, c + Vector3(8, 0, 0), 0.0)
	var px: Node = demo.sim.proxies.get(t.id)
	if px:
		var hull: VehicleVisual = px._vehicle_visual
		var aabb := AABB()
		var first := true
		for mi: MeshInstance3D in UnitVisuals.mesh_instances(hull):
			var bb := mi.global_transform * mi.get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
		out["proxy_hull"] = {"unit": [snappedf(t.position.x, 0.1), snappedf(t.position.y, 0.1), snappedf(t.position.z, 0.1)],
			"aabb_centre": [snappedf(aabb.get_center().x, 0.1), snappedf(aabb.get_center().y, 0.1), snappedf(aabb.get_center().z, 0.1)], "aabb_size": [snappedf(aabb.size.x, 0.1), snappedf(aabb.size.y, 0.1), snappedf(aabb.size.z, 0.1)]}
	await _seconds(1.5)
	for u: UnitState in [t, a]:
		var b := demo.sim.body_of(u.id) as VehicleBody
		var vis := b.visual
		var wy := []
		for w in vis.wheels:
			wy.append(snappedf((w.steer as Node3D).global_position.y - u.position.y, 0.01))
		out[String(u.veh.type_id)] = {"has_body": b != null, "unit_y": snappedf(u.position.y, 0.01), "ground_y": snappedf(demo.ground_height(u.position), 0.01),
			"body_global_y": snappedf(b.global_position.y, 0.01), "hull_local_y": snappedf(vis.body.position.y, 0.02), "wheel_centres_above_ground": wy,
			"shapes": vis.collision_shapes.size(), "wheels": vis.wheels.size(), "lods": vis.lod_count}
	for shot in [["03_look_rts_high", 0.0, 55.0, false], ["03b_look_front", 0.0, 22.0, false]]:
		demo.rts_camera.frame(c, shot[1], shot[2])
		await _seconds(1.2)
		_shot(shot[0])
	# Steering and moving: a slow drive in a circle for the wheel pose.
	demo.sim.vehicles.take_control(t.id)
	t.veh.in_throttle = 1.0
	t.veh.in_steer = 0.6
	await _warp(3.5, 1.0, 20.0)
	demo.rts_camera.frame(t.position, 0.6, 26.0)
	await _seconds(0.3)
	_shot("04_look_turning")
	var tb := demo.sim.body_of(t.id) as VehicleBody
	var bb := AABB()
	var first2 := true
	for mi: MeshInstance3D in UnitVisuals.mesh_instances(tb.visual.body):
		var q := mi.global_transform * mi.get_aabb()
		bb = q if first2 else bb.merge(q)
		first2 = false
	out["turning"] = {"steer_rad": snappedf(t.veh.steer, 0.01), "speed": snappedf(t.veh.speed, 0.1), "unit": [snappedf(t.position.x, 0.1), snappedf(t.position.y, 0.1), snappedf(t.position.z, 0.1)],
		"body_node": [snappedf(tb.global_position.x, 0.1), snappedf(tb.global_position.y, 0.1), snappedf(tb.global_position.z, 0.1)],
		"hull_centre": [snappedf(bb.get_center().x, 0.1), snappedf(bb.get_center().y, 0.1), snappedf(bb.get_center().z, 0.1)], "ring_y": snappedf(tb.ring.global_position.y, 0.1)}
	demo.sim.vehicles.release_control(t.id, false)
	for u: UnitState in [t, a]:
		demo.sim.state.remove_unit(u.id)
	return out


## Screenshots of the Phase A situations: on a road, on a bridge, in a curve, at the base gate,
## and from the driver's seat.
func _veh_shots() -> Dictionary:
	var out := {}
	var net: RoadNetwork = demo.sim.state.roads
	# Bridge: a truck and an APC approach and cross the longest bridge.
	var best: Array = []
	for r: RoadNetwork.Road in net.world:
		for sp: Array in r.bridges:
			if best.is_empty() or _flat(r.points[int(sp[0])], r.points[int(sp[1])]) > _flat(best[0].points[int(best[1][0])], best[0].points[int(best[1][1])]):
				best = [r, sp]
	var r: RoadNetwork.Road = best[0]
	var sp: Array = best[1]
	var i0 := int(sp[0])
	var i1 := int(sp[1])
	var t := _veh(VehicleDefs.TRUCK, r.points[i0 - 30], 0.0)
	var a := _veh(VehicleDefs.APC, r.points[i0 - 45], 0.0)
	for u: UnitState in [t, a]:
		u.yaw = atan2(-(r.points[i0].x - r.points[i0 - 30].x), -(r.points[i0].z - r.points[i0 - 30].z))
	demo.rts_camera.frame(r.points[i0], 0.0, 70.0)
	await _seconds(2.0)
	var dest := demo.on_ground(r.points[i1 + 40].x, r.points[i1 + 40].z, 0.0)
	demo.sim.vehicles.order_drive(t.id, dest)
	demo.sim.vehicles.order_drive(a.id, dest)
	var on_bridge := false
	var guard := 0
	while not on_bridge and guard < 4000:
		await tree.physics_frame
		guard += 1
		on_bridge = not is_nan(net.deck_height(t.position)) and t.has_body
	out["on_bridge"] = on_bridge
	demo.rts_camera.frame(t.position, 0.9, 40.0)
	await _seconds(0.4)
	_shot("05_truck_on_bridge")
	demo.rts_camera.frame(t.position, 2.2, 22.0)
	await _seconds(0.3)
	_shot("05b_truck_on_bridge_close")
	# From the driver's seat on the bridge, then bumper view.
	demo.game.drive(t.id)
	await _seconds(0.8)
	_shot("06_drive_camera_bridge")
	demo.game.drive_camera.bumper_view = true
	await _seconds(0.5)
	_shot("06b_drive_bumper_view")
	demo.game.drive_camera.bumper_view = false
	demo.game.enter_rts()
	await _warp(60.0, 4.0, 60.0)
	# Curve: the tightest bend of a road the vehicles can use, a truck entering it.
	var tight := INF
	var where: Array = []
	for rd: RoadNetwork.Road in net.world:
		if rd.cls == &"track":
			continue
		for k in range(10, rd.points.size() - 10, 3):
			var rad := RoadNetwork.min_radius(rd.points.slice(k - 5, k + 6), 12.0)
			if rad < tight and rad > 8.0:
				tight = rad
				where = [rd, k]
	if not where.is_empty():
		var rd: RoadNetwork.Road = where[0]
		var k: int = where[1]
		var c := _veh(VehicleDefs.TRUCK, rd.points[k - 25], 0.0)
		c.yaw = atan2(-(rd.points[k - 24].x - rd.points[k - 25].x), -(rd.points[k - 24].z - rd.points[k - 25].z))
		demo.rts_camera.frame(rd.points[k], 0.0, 80.0)
		await _seconds(2.0)
		demo.sim.vehicles.order_drive(c.id, demo.on_ground(rd.points[k + 25].x, rd.points[k + 25].z, 0.0))
		var g2 := 0
		while _flat(c.position, rd.points[k]) > 14.0 and g2 < 3000:
			await tree.physics_frame
			g2 += 1
		demo.rts_camera.frame(c.position, 0.5, 45.0)
		await _seconds(0.3)
		_shot("07_truck_in_curve")
		out["curve"] = {"radius_m": snappedf(tight, 0.1), "road": rd.name, "speed": snappedf(c.veh.speed, 0.1), "steer": snappedf(c.veh.steer, 0.01)}
	# Base: a truck arrives through the entrance.
	await _base()
	if fob.has("center"):
		var bc: Vector3 = fob.center
		var v := _veh(VehicleDefs.TRUCK, bc + Vector3(0, 0, 120), 0.0)
		v.yaw = PI
		demo.rts_camera.frame(bc + Vector3(8, 0, 66), 0.2, 60.0)
		await _seconds(2.0)
		demo.sim.vehicles.order_drive(v.id, bc + Vector3(42, 0, 49))
		var g3 := 0
		while _flat(v.position, bc + Vector3(8, 0, 66)) > 12.0 and g3 < 4000:
			await tree.physics_frame
			g3 += 1
		demo.rts_camera.frame(v.position, 0.3, 36.0)
		await _seconds(0.3)
		_shot("08_truck_entering_base")
		out["base_entry_ok"] = g3 < 4000
	return out


# --- Phase B: infantry transport ---------------------------------------------------------------

## Soldiers of both squads: aboard / hidden / positions, for the invariants checked all the way.
func _aboard_state(sqs: Array, vehicles: Array) -> Dictionary:
	var out := {"aboard": 0, "with_view": 0, "far_from_vehicle": 0, "dup_occupant": 0, "link_mismatch": 0, "walking_while_aboard": 0, "ai_active_aboard": 0}
	var seen := {}
	for vu: UnitState in vehicles:
		for id in vu.veh.occupants:
			if seen.has(id):
				out.dup_occupant += 1
			seen[id] = vu.id
	for sq: SquadState in sqs:
		for id in sq.members:
			var s := _u(id)
			if s == null or s.vehicle_id < 0:
				continue
			out.aboard += 1
			if demo.sim.view_of(id) != null:
				out.with_view += 1
			var vu := _u(s.vehicle_id)
			if vu == null or not vu.veh.occupants.has(id):
				out.link_mismatch += 1
			elif _flat(s.position, vu.position) > 3.0:
				out.far_from_vehicle += 1
			if s.order != UnitState.Order.NONE:
				out.walking_while_aboard += 1
			if s.target_id >= 0 or s.ai_state == UnitState.AiState.ENGAGING:
				out.ai_active_aboard += 1
	return out


func _soldier_sig(sqs: Array) -> Dictionary:
	var sig := {}
	for sq: SquadState in sqs:
		for id in sq.members:
			var s := _u(id)
			sig[id] = [s.faction, snappedf(s.health, 0.1), String(s.weapon_id), s.mag, s.reserve, s.loadout, sq.id]
	return sig


func _soldier_target(from: Vector3, off: Vector3) -> Vector3:
	var p := from + off
	return demo.on_ground(p.x, p.z, 0.0)


func _transport() -> Dictionary:
	var out := {}
	var net: RoadNetwork = demo.sim.state.roads
	await _base()
	_expect(fob.has("center"), "transport: no base")
	if not fob.has("center"):
		return out
	var c: Vector3 = fob.center
	# The vehicle yard of the base: trucks facing west, squads waiting east of them.
	var far := _beyond_bridge(c, 6.0)
	_expect(not far.is_empty(), "transport: no bridge target")
	if far.is_empty():
		return out
	out["target"] = {"route_m": snappedf(far.route_m, 1.0)}
	var along := Vector3(-1, 0, 0)
	var side := Vector3(0, 0, 1)
	var rp := c + Vector3(34, 0, 48)
	var truck := _veh(VehicleDefs.TRUCK, c + Vector3(32, 0, 52), PI * 0.5)
	var apc := _veh(VehicleDefs.APC, c + Vector3(32, 0, 44), PI * 0.5)
	var sa := _spawn(0, c + Vector3(50, 0, 50), 8)
	var sb := _spawn(0, c + Vector3(50, 0, 44), 8)
	await _physics(10)
	demo.rts_camera.frame(rp + side * 6.0, 0.0, 45.0)
	await _seconds(2.0)
	var before := _soldier_sig([sa, sb])
	# Capacity: the truck takes 12 of 16 soldiers.
	var r1 := demo.sim.vehicles.transport.order_transport(truck.id, sa.id)
	var r2 := demo.sim.vehicles.transport.order_transport(truck.id, sb.id)
	out["capacity"] = {"first": r1.get("boarding", 0), "second": r2.get("boarding", 0), "second_ok": r2.ok, "left_behind": r2.get("left_behind", 0)}
	_expect(r1.ok and r1.boarding == 8 and r2.ok and r2.boarding == 4 and r2.left_behind == 4, "transport: truck capacity %s" % JSON.stringify(out.capacity))
	await _seconds(0.5)
	_shot("09_boarding_start")
	var w := await _warp(60.0, 4.0, 60.0, func() -> bool: return truck.veh.occupants.size() >= 12 and truck.veh.phase == VehicleState.Phase.NONE)
	out["boarded"] = {"truck_occupants": truck.veh.occupants.size(), "phase": VehicleState.PHASE_NAMES[truck.veh.phase], "sim_s": w.sim_s}
	if truck.veh.occupants.size() < 12:
		var dbg := []
		var door := demo.sim.vehicles.transport.door_point(truck)
		for id in truck.veh.pending:
			var ps := _u(id)
			dbg.append({"id": id, "pos": [snappedf(ps.position.x, 0.1), snappedf(ps.position.z, 0.1)], "to_door": snappedf(_flat(ps.position, door), 0.1), "order": ps.order, "target": [snappedf(ps.order_target.x, 0.1), snappedf(ps.order_target.z, 0.1)],
				"move_state": ps.move_state, "has_body": ps.has_body, "react": ps.is_reacting(), "tactic": ps.tactic})
		out["pending_debug"] = dbg
		out["truck_at"] = [snappedf(truck.position.x, 0.1), snappedf(truck.position.z, 0.1), snappedf(truck.yaw, 0.01)]
		_shot("09b_boarding_stuck")
	_expect(truck.veh.occupants.size() == 12, "transport: truck has %d aboard" % truck.veh.occupants.size())
	_shot("10_boarded_truck")
	var inv := _aboard_state([sa, sb], [truck, apc])
	out["boarded_invariants"] = inv
	_expect(inv.with_view == 0 and inv.dup_occupant == 0 and inv.link_mismatch == 0 and inv.walking_while_aboard == 0, "transport: aboard invariants %s" % JSON.stringify(inv))
	var left_ids := []
	for id in sb.members:
		if _u(id).vehicle_id < 0:
			left_ids.append(id)
	out["left_on_foot"] = left_ids.size()
	_expect(left_ids.size() == 4, "transport: %d left on foot (expected 4)" % left_ids.size())
	# Combined RTS order: the rest of squad B boards the APC and is driven to the target.
	demo.rts.select_squads([sb.id])
	demo.rts.select(Array(demo.rts.selected) + [apc.id])
	var n := demo.rts.order_move(far.near_target)
	out["combined_order"] = {"soldiers": n, "message": demo.rts.current_message()}
	# The truck goes with its 12: a plain Move order for the vehicle.
	demo.rts.select([truck.id])
	demo.rts.order_move(far.target)
	out["truck_order_message"] = demo.rts.current_message()
	_expect(truck.veh.phase == VehicleState.Phase.NONE and truck.order == UnitState.Order.MOVE, "transport: truck did not start")
	var tr_t := _sample_begin(truck, truck.veh.def())
	var tr_a := _sample_begin(apc, apc.veh.def())
	await _warp(70.0, 4.0, 60.0)
	out["boarded_apc"] = {"apc_occupants": apc.veh.occupants.size(), "apc_phase": VehicleState.PHASE_NAMES[apc.veh.phase], "apc_order": apc.order}
	_expect(apc.veh.occupants.size() >= 4, "transport: apc occupants %d" % apc.veh.occupants.size())
	# Redirect while transporting: another destination, the passengers stay aboard.
	var redir := demo.sim.vehicles.order_drive(apc.id, far.near_target)
	out["redirect"] = {"ok": redir.ok, "apc_aboard": apc.veh.occupants.size(), "phase": VehicleState.PHASE_NAMES[apc.veh.phase]}
	_expect(redir.ok and apc.veh.occupants.size() >= 4, "transport: redirect")
	# Camera away (the bodies go), then save / load with soldiers aboard.
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 120.0)
	await _seconds(2.0)
	await _warp(60.0, 4.0, 60.0)
	var path := "user://saves/logistics_transport_test.sav"
	demo.sim.state.save_file(path)
	var sig_before := _soldier_sig([sa, sb])
	var occ_before := [Array(truck.veh.occupants), Array(apc.veh.occupants)]
	for sq: SquadState in [sa, sb]:
		for id in sq.members:
			_u(id).vehicle_id = -1
	truck.veh.occupants = PackedInt32Array()
	apc.veh.occupants = PackedInt32Array()
	demo.sim.state.load_file(path)
	await _physics(3)
	var occ_after := [Array(truck.veh.occupants), Array(apc.veh.occupants)]
	var inv_after := _aboard_state([sa, sb], [truck, apc])
	out["save_load"] = {"same_occupants": occ_before == occ_after, "invariants": inv_after, "same_records": sig_before == _soldier_sig([sa, sb])}
	_expect(occ_before == occ_after and inv_after.with_view == 0 and inv_after.link_mismatch == 0, "transport: save/load aboard %s" % JSON.stringify(out.save_load))
	_expect(sig_before == _soldier_sig([sa, sb]), "transport: soldier records changed through save/load")
	await _warp(1200.0, 16.0, 400.0, func() -> bool: return truck.order == UnitState.Order.NONE and apc.order == UnitState.Order.NONE)
	var t_end := _sample_end(tr_t)
	var a_end := _sample_end(tr_a)
	out["journey"] = {"truck": t_end, "apc": a_end, "truck_arrived": truck.move_state == UnitState.MoveState.ARRIVED, "apc_arrived": apc.move_state == UnitState.MoveState.ARRIVED}
	out["diagnose"] = {"truck": demo.sim.vehicles.diagnose(truck), "apc": demo.sim.vehicles.diagnose(apc)}
	_expect(truck.move_state == UnitState.MoveState.ARRIVED and apc.move_state == UnitState.MoveState.ARRIVED, "transport: vehicles did not arrive")
	_expect(t_end.teleports == 0 and a_end.teleports == 0 and t_end.inside_blocking == 0 and a_end.inside_blocking == 0, "transport: journey track problems")
	out["arrival_state"] = _aboard_state([sa, sb], [truck, apc])
	# Disembark both with the U command through the RTS, camera on the vehicles.
	demo.rts_camera.frame(truck.position, 0.5, 45.0)
	await _seconds(2.5)
	demo.rts.select([truck.id, apc.id])
	demo.rts.order_unload()
	await _warp(12.0, 1.0, 30.0)
	_shot("11_disembarked")
	var spots := []
	var bad_spot := 0
	var min_pair := INF
	for sq: SquadState in [sa, sb]:
		for id in sq.members:
			var s := _u(id)
			if s.vehicle_id >= 0:
				bad_spot += 1
				continue
			if sm.blocks_point(Vector2(s.position.x, s.position.z), 0.3) or (sm.is_wet(s.position.x, s.position.z) and is_nan(net.deck_height(s.position))):
				bad_spot += 1
			for o in spots:
				min_pair = minf(min_pair, _flat(o, s.position))
			spots.append(s.position)
	out["disembark"] = {"on_foot": spots.size(), "bad_spots": bad_spot, "min_pair_m": snappedf(min_pair, 0.1), "truck_left": truck.veh.occupants.size(), "apc_left": apc.veh.occupants.size()}
	_expect(spots.size() == 16 and bad_spot == 0 and min_pair > 0.5, "transport: disembark %s" % JSON.stringify(out.disembark))
	# The squads can act at once: a Move order 60 m away is carried out.
	demo.rts.select_squads([sa.id, sb.id])
	var dest2 := demo.on_ground(lerpf(truck.position.x, far.near_target.x, 0.5), lerpf(truck.position.z, far.near_target.z, 0.5), 0.0)
	demo.rts.order_move(dest2)
	await _warp(60.0, 4.0, 60.0)
	var arrived := 0
	for sq: SquadState in [sa, sb]:
		for id in sq.members:
			arrived += 1 if _flat(_u(id).position, dest2) < 22.0 else 0
	var same := _soldier_sig([sa, sb]) == before
	out["after_orders"] = {"soldiers_near_target": arrived, "of": 16, "records_unchanged": same}
	_expect(arrived >= 14, "transport: only %d of 16 followed their order after disembarking" % arrived)
	_expect(same, "transport: soldier identity / equipment changed during transport")
	return out


## Cancelling and re-assigning a boarding, and a full squad into the APC (its 8 seats).
func _transport_cancel() -> Dictionary:
	var out := {}
	await _base()
	var c: Vector3 = fob.center
	var truck := _veh(VehicleDefs.TRUCK, c + Vector3(32, 0, 52), PI * 0.5)
	var apc := _veh(VehicleDefs.APC, c + Vector3(32, 0, 44), PI * 0.5)
	var sq := _spawn(0, c + Vector3(54, 0, 48), 8)
	var extra := _spawn(0, c + Vector3(54, 0, 56), 1)
	await _physics(10)
	demo.rts_camera.frame(c + Vector3(40, 0, 48), 0.0, 40.0)
	await _seconds(1.5)
	var t := demo.sim.vehicles.transport
	var r := t.order_transport(truck.id, sq.id)
	await _warp(1.0, 1.0, 10.0)
	t.unload(truck.id)                         # U while boarding = cancel
	await _warp(1.0, 1.0, 10.0)
	var after_cancel := _aboard_state([sq], [truck, apc])
	var halted := 0
	for id in sq.members:
		halted += 1 if _u(id).order == UnitState.Order.NONE else 0
	out["cancel"] = {"ordered": r.ok, "aboard": after_cancel.aboard, "halted": halted, "phase": VehicleState.PHASE_NAMES[truck.veh.phase], "pending": truck.veh.pending.size()}
	_expect(r.ok and after_cancel.aboard == 0 and halted == 8 and truck.veh.pending.is_empty() and truck.veh.phase == VehicleState.Phase.NONE, "cancel: %s" % JSON.stringify(out.cancel))
	# Assign another vehicle: the same squad boards the APC (exactly eight seats).
	var r2 := t.order_transport(apc.id, sq.id)
	await _warp(30.0, 2.0, 30.0, func() -> bool: return apc.veh.occupants.size() >= 8)
	out["apc"] = {"ordered": r2.ok, "aboard": apc.veh.occupants.size(), "capacity": apc.veh.def().passengers}
	_expect(r2.ok and apc.veh.occupants.size() == 8, "apc: %s" % JSON.stringify(out.apc))
	# A ninth soldier is refused, the vehicle is full.
	var r3 := t.order_transport(apc.id, extra.id)
	out["full"] = {"ok": r3.ok, "reason": r3.reason}
	_expect(not r3.ok, "apc: a ninth soldier was accepted")
	# Cancel while transporting: the vehicle stops and everybody gets off.
	var near := c + Vector3(0, 0, 120)
	demo.sim.vehicles.order_drive(apc.id, near)
	await _warp(8.0, 1.0, 20.0)
	t.unload(apc.id)
	await _warp(8.0, 1.0, 20.0)
	var inv := _aboard_state([sq], [apc])
	out["unload_in_transit"] = {"aboard": inv.aboard, "apc_speed": snappedf(apc.veh.speed, 0.1), "occupants": apc.veh.occupants.size()}
	_expect(inv.aboard == 0 and apc.veh.occupants.is_empty(), "unload in transit: %s" % JSON.stringify(out.unload_in_transit))
	return out

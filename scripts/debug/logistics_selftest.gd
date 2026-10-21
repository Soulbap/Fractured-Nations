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
	if _want("logistics"):
		_log("logistics", await _logistics())
	if _want("bases"):
		_log("bases", await _bases())
	if _want("convoy"):
		_log("convoy", await _convoy())
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


# --- Phase C: supplies, depots, convoys ---------------------------------------------------------

## Supplies in the whole world (depots + vehicle cargo + tanks + the given soldiers' spare rounds
## as ammunition kg).
func _supply_totals(soldiers: Array = []) -> Dictionary:
	var t := {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}
	for s in cs.all():
		if s.inventory:
			for k in t:
				t[k] += s.inventory.get_qty(StringName(k))
	for id in demo.sim.vehicles.ids:
		var u := _u(id)
		for k in t:
			t[k] += u.veh.cargo.get_qty(StringName(k))
		t["fuel"] += u.veh.fuel
	for id in soldiers:
		t["ammo"] += float(_u(id).reserve) / Inventory.AMMO_ROUNDS_PER_KG
	return t


func _fuel_burned(start_odo: Dictionary) -> float:
	var burned := 0.0
	for id in start_odo:
		var u := _u(id)
		burned += (u.veh.odometer - start_odo[id]) * u.veh.def().fuel_per_km / 1000.0
	return burned


func _odo_snapshot() -> Dictionary:
	var o := {}
	for id in demo.sim.vehicles.ids:
		o[id] = _u(id).veh.odometer
	return o


## A free building spot near `around` for a depot whose dock a truck can drive to from `from`.
func _depot_site(around: Vector3, from: Vector3) -> Dictionary:
	var def := StructureCatalog.get_def(&"supply_depot")
	var truck := VehicleDefs.get_def(VehicleDefs.TRUCK)
	for r in [70.0, 110.0, 150.0, 200.0, 260.0]:
		for k in 16:
			var a := k * TAU / 16.0
			var p := demo.on_ground(around.x + cos(a) * r, around.z + sin(a) * r, 0.0)
			for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
				var chk := sm.check_building(def, p, yaw)
				if not chk.ok:
					continue
				var fake := StructureState.new()
				fake.type_id = &"supply_depot"
				fake.position = p
				fake.yaw = yaw
				var dock := FacilityDefs.dock_point(fake, 0)
				dock.y = demo.ground_height(dock)
				if sm.blocks_point(Vector2(dock.x, dock.z), 2.0) or sm.is_wet(dock.x, dock.z):
					continue
				var res := demo.sim.vehicles.router.plan(from, dock, truck)
				if res.ok:
					return {"pos": p, "yaw": yaw, "dock": dock, "route_m": res.length_m}
	return {}


func store_info(s: StructureState) -> Dictionary:
	return {"id": s.id, "type": String(s.type_id), "inventory": s.inventory.summary() if s.inventory else "-", "capacity": s.inventory.capacity if s.inventory else 0.0}


func _all_resupplied(sq: SquadState) -> bool:
	for id in sq.members:
		if _u(id).resupply_src != "":
			return false
	return true


func _logistics() -> Dictionary:
	var out := {}
	await _base()
	var c: Vector3 = fob.center
	_expect(fob.has("placed") and fob.placed.supply != null, "logistics: no supply depot in the base")
	var src: StructureState = fob.placed.supply
	var far := _beyond_bridge(c, 6.0)
	var site := _depot_site(far.target, c + Vector3(42, 0, 52))
	_expect(not site.is_empty(), "logistics: no site for the forward depot")
	if site.is_empty():
		return out
	var dst := cs.add_building(&"supply_depot", site.pos, site.yaw, 0)
	await _physics(5)
	out["depots"] = {"source": store_info(src), "forward": store_info(dst), "route_m": snappedf(site.route_m, 1.0)}
	_expect(src.inventory != null and src.inventory.get_qty(Inventory.AMMO) >= 4000.0, "logistics: the first depot has no starting stock")
	_expect(dst.inventory != null and dst.inventory.is_empty(), "logistics: the second depot is not empty")
	var lg := demo.sim.logistics
	var truck := _veh(VehicleDefs.TRUCK, FacilityDefs.dock_point(src, 0), PI)
	var truck2 := _veh(VehicleDefs.TRUCK, FacilityDefs.dock_point(src, 1), PI)
	await _physics(5)
	var soldiers := []
	var t0 := _supply_totals()
	var odo0 := _odo_snapshot()
	var inv_track := {"max_ammo_err": 0.0, "max_supplies_err": 0.0, "max_fuel_err": 0.0, "negative": 0, "over_capacity": 0, "n": 0}
	var sampler := func() -> void:
		inv_track.n += 1
		var t := _supply_totals(soldiers)
		inv_track.max_ammo_err = maxf(inv_track.max_ammo_err, absf(t.ammo - t0.ammo))
		inv_track.max_supplies_err = maxf(inv_track.max_supplies_err, absf(t.supplies - t0.supplies))
		inv_track.max_fuel_err = maxf(inv_track.max_fuel_err, absf(t.fuel + _fuel_burned(odo0) - t0.fuel))
		for s in cs.all():
			if s.inventory:
				for k in Inventory.ITEMS:
					if s.inventory.get_qty(k) < -0.001:
						inv_track.negative += 1
				if s.inventory.total() > s.inventory.capacity + 0.01:
					inv_track.over_capacity += 1
		for id in demo.sim.vehicles.ids:
			var vu := _u(id)
			if vu.veh.cargo.total() > vu.veh.cargo.capacity + 0.01 or vu.veh.fuel < -0.001 or vu.veh.cargo.get_qty(Inventory.AMMO) < -0.001:
				inv_track.over_capacity += 1
	tree.physics_frame.connect(sampler)
	demo.rts_camera.frame(FacilityDefs.dock_point(src, 0), 0.5, 40.0)
	await _seconds(1.5)
	# --- refusals ---------------------------------------------------------------------------
	var r_dry := lg.order_delivery(truck.id, dst.id, src.id, Inventory.AMMO, 100.0)
	out["dry_source"] = r_dry.reason
	_expect(not r_dry.ok and r_dry.reason.contains("no ammunition"), "logistics: dry depot order not refused: %s" % r_dry.reason)
	# --- short stock and full cargo: truck 2 at the source dock ------------------------------
	var sup_before := src.inventory.get_qty(Inventory.SUPPLIES)
	var j1 := lg.order_load(truck2.id, src.id, Inventory.SUPPLIES, 50000.0)
	await _warp(120.0, 4.0, 60.0, func() -> bool: return truck2.veh.job.is_empty())
	var got_sup := truck2.veh.cargo.get_qty(Inventory.SUPPLIES)
	var r_full := lg.order_load(truck2.id, src.id, Inventory.AMMO, 4000.0)
	await _warp(60.0, 4.0, 60.0, func() -> bool: return truck2.veh.job.is_empty())
	var cargo_total := truck2.veh.cargo.total()
	var r_full2 := lg.order_load(truck2.id, src.id, Inventory.FUEL, 500.0)
	out["short_and_full"] = {"asked_supplies": 50000.0, "stock_before": snappedf(sup_before, 0.1), "loaded": snappedf(got_sup, 0.1), "capacity": truck2.veh.cargo.capacity,
		"then_ammo_loaded": snappedf(truck2.veh.cargo.get_qty(Inventory.AMMO), 0.1), "cargo_total": snappedf(cargo_total, 0.1), "when_full": r_full2.reason}
	_expect(j1.ok and absf(got_sup - minf(sup_before, truck2.veh.cargo.capacity)) < 0.5, "logistics: short stock %s" % JSON.stringify(out.short_and_full))
	_expect(cargo_total <= truck2.veh.cargo.capacity + 0.01 and not r_full2.ok and r_full2.reason.contains("Cargo full"), "logistics: cargo limit %s" % JSON.stringify(out.short_and_full))
	# Put it back through the real unload job at the same depot (cargo returns, totals intact).
	lg.order_unload(truck2.id, src.id)
	await _warp(120.0, 4.0, 60.0, func() -> bool: return truck2.veh.job.is_empty())
	out["unload_back"] = {"truck2_cargo": snappedf(truck2.veh.cargo.total(), 0.1), "depot_supplies": snappedf(src.inventory.get_qty(Inventory.SUPPLIES), 0.1)}
	_expect(truck2.veh.cargo.is_empty() and absf(src.inventory.get_qty(Inventory.SUPPLIES) - sup_before) < 0.5, "logistics: unload back %s" % JSON.stringify(out.unload_back))
	# --- the delivery: fuel and ammunition with truck 1 -------------------------------------
	var ammo_before := src.inventory.get_qty(Inventory.AMMO)
	var fuel_before := src.inventory.get_qty(Inventory.FUEL)
	lg.order_load(truck.id, src.id, Inventory.FUEL, 2500.0)
	await _warp(120.0, 4.0, 60.0, func() -> bool: return truck.veh.job.is_empty())
	var r1 := lg.order_delivery(truck.id, src.id, dst.id, Inventory.AMMO, 3000.0)
	_expect(r1.ok, "logistics: delivery refused: %s" % r1.reason)
	await _warp(90.0, 4.0, 60.0, func() -> bool: return truck.veh.job.get("stage", "") == "to_dst")
	var loaded := {"truck_ammo": snappedf(truck.veh.cargo.get_qty(Inventory.AMMO), 0.1), "truck_fuel": snappedf(truck.veh.cargo.get_qty(Inventory.FUEL), 0.1),
		"depot_ammo_drop": snappedf(ammo_before - src.inventory.get_qty(Inventory.AMMO), 0.1), "depot_fuel_drop": snappedf(fuel_before - src.inventory.get_qty(Inventory.FUEL), 0.1),
		"stage": truck.veh.job.get("stage", "")}
	out["loaded"] = loaded
	_expect(absf(loaded.truck_ammo - 3000.0) < 0.5 and absf(loaded.truck_fuel - 2500.0) < 0.5 and absf(loaded.depot_ammo_drop - 3000.0) < 0.5 and absf(loaded.depot_fuel_drop - 2500.0) < 0.5,
		"logistics: loading %s" % JSON.stringify(loaded))
	_shot("12_truck_loaded_at_depot")
	# Cancel on the road: cargo stays aboard, nothing duplicated or lost; then redirect to unload.
	await _warp(40.0, 4.0, 60.0)
	var mid := _supply_totals(soldiers)
	lg.cancel_job(truck.id, "cancelled")
	out["cancel"] = {"truck_ammo": snappedf(truck.veh.cargo.get_qty(Inventory.AMMO), 0.1), "truck_fuel": snappedf(truck.veh.cargo.get_qty(Inventory.FUEL), 0.1), "job_cleared": truck.veh.job.is_empty(),
		"ammo_error": snappedf(mid.ammo - t0.ammo, 0.01), "stopped": truck.order == UnitState.Order.NONE}
	_expect(absf(truck.veh.cargo.get_qty(Inventory.AMMO) - 3000.0) < 0.5 and truck.veh.job.is_empty() and truck.order == UnitState.Order.NONE, "logistics: cancel %s" % JSON.stringify(out.cancel))
	var r_un := lg.order_unload(truck.id, dst.id)
	_expect(r_un.ok, "logistics: unload order refused: %s" % r_un.reason)
	var tank_before := truck.veh.fuel
	var tr := _sample_begin(truck, truck.veh.def())
	await _warp(1500.0, 16.0, 400.0, func() -> bool: return truck.veh.job.is_empty() and truck.order == UnitState.Order.NONE)
	out["journey"] = _sample_end(tr)
	out["arrival"] = {"status": truck.veh.status_name(), "dst": dst.inventory.summary(), "truck_cargo": truck.veh.cargo.summary(), "tank_used_l": snappedf(tank_before - truck.veh.fuel, 0.1),
		"at_dock_m": snappedf(_flat(truck.position, site.dock), 0.1)}
	_expect(absf(dst.inventory.get_qty(Inventory.AMMO) - 3000.0) < 0.5 and absf(dst.inventory.get_qty(Inventory.FUEL) - 2500.0) < 0.5 and truck.veh.cargo.is_empty(),
		"logistics: delivery result %s" % JSON.stringify(out.arrival))
	_shot("13_truck_unloaded_forward_depot")
	# --- refuel at the forward depot -------------------------------------------------------
	var depot_fuel := dst.inventory.get_qty(Inventory.FUEL)
	var tank := truck.veh.fuel
	var rf := lg.order_refuel(truck.id, dst.id)
	await _warp(120.0, 4.0, 60.0, func() -> bool: return truck.veh.job.is_empty())
	out["refuel"] = {"ok": rf.ok, "tank_before": snappedf(tank, 0.1), "tank_after": snappedf(truck.veh.fuel, 0.1), "depot_used": snappedf(depot_fuel - dst.inventory.get_qty(Inventory.FUEL), 0.1)}
	_expect(rf.ok and absf(truck.veh.fuel - truck.veh.def().fuel_capacity) < 0.5 and absf(out.refuel.depot_used - (truck.veh.def().fuel_capacity - tank)) < 0.5, "logistics: refuel %s" % JSON.stringify(out.refuel))
	# Out of fuel: the order is refused with the numbers.
	var keep := truck.veh.fuel
	truck.veh.fuel = 3.0
	var r_fuel := demo.sim.vehicles.order_drive(truck.id, c + Vector3(40, 0, 50))
	truck.veh.fuel = keep
	out["insufficient_fuel"] = r_fuel.reason
	_expect(not r_fuel.ok and r_fuel.reason.contains("Insufficient fuel"), "logistics: low fuel order accepted: %s" % r_fuel.reason)
	# --- resupply: soldiers with depleted reserves take ammunition from the forward depot ----
	var sq := _spawn(0, site.dock + Vector3(30, 0, 30), 8)
	await _physics(5)
	for id in sq.members:
		_u(id).reserve = 20
		soldiers.append(id)
	var rebased := _supply_totals(soldiers)
	for k in rebased:
		t0[k] = rebased[k]
	for id in odo0:
		odo0[id] = _u(id).veh.odometer
	var dst_before := dst.inventory.get_qty(Inventory.AMMO)
	var rr := lg.order_resupply([sq.id], "s%d" % dst.id)
	await _warp(60.0, 4.0, 60.0, func() -> bool: return _all_resupplied(sq))
	var got := 0
	for id in sq.members:
		got += _u(id).reserve - 20
	out["resupply"] = {"ok": rr.ok, "soldiers": rr.get("soldiers", 0), "rounds_received": got, "depot_used_kg": snappedf(dst_before - dst.inventory.get_qty(Inventory.AMMO), 0.1)}
	_expect(rr.ok and got == 8 * 100 and absf(out.resupply.depot_used_kg - got / Inventory.AMMO_ROUNDS_PER_KG) < 0.5, "logistics: resupply %s" % JSON.stringify(out.resupply))
	# --- unreachable destination: a depot in the river --------------------------------------
	var wet := _water_spot()
	if wet.is_finite():
		var wet_depot := cs.add_building(&"supply_depot", wet, 0.0, 0)
		truck.veh.cargo.add(Inventory.SUPPLIES, 500.0)
		t0["supplies"] += 500.0
		var cargo_before := truck.veh.cargo.total()
		var r_wet := lg.order_unload(truck.id, wet_depot.id)
		out["unreachable"] = {"ok": r_wet.ok, "reason": r_wet.reason, "cargo_unchanged": absf(truck.veh.cargo.total() - cargo_before) < 0.01}
		_expect(not r_wet.ok and absf(truck.veh.cargo.total() - cargo_before) < 0.01, "logistics: unreachable depot accepted %s" % JSON.stringify(out.unreachable))
		truck.veh.cargo.take(Inventory.SUPPLIES, 500.0)
		t0["supplies"] -= 500.0
		cs.remove(wet_depot.id)
	tree.physics_frame.disconnect(sampler)
	inv_track["max_ammo_err"] = snappedf(inv_track.max_ammo_err, 0.01)
	inv_track["max_supplies_err"] = snappedf(inv_track.max_supplies_err, 0.01)
	inv_track["max_fuel_err"] = snappedf(inv_track.max_fuel_err, 0.01)
	out["invariants"] = inv_track
	_expect(inv_track.max_ammo_err < 0.5 and inv_track.max_supplies_err < 0.5 and inv_track.max_fuel_err < 0.5 and inv_track.negative == 0 and inv_track.over_capacity == 0,
		"logistics: conservation %s" % JSON.stringify(inv_track))
	fob["fwd_depot"] = dst.id
	fob["fwd_site"] = site
	fob["src_depot"] = src.id
	return out


## The forward depot (built once per run, 6 km+ away over a bridge) and the source depot.
func _forward_depot() -> Dictionary:
	if fob.has("fwd_depot") and cs.get_structure(fob.fwd_depot) != null:
		return {"src": cs.get_structure(fob.src_depot), "dst": cs.get_structure(fob.fwd_depot), "site": fob.fwd_site}
	await _base()
	var c: Vector3 = fob.center
	var far := _beyond_bridge(c, 6.0)
	var site := _depot_site(far.target, c + Vector3(42, 0, 52))
	_expect(not site.is_empty(), "no site for the forward depot")
	var dst := cs.add_building(&"supply_depot", site.pos, site.yaw, 0)
	await _physics(5)
	fob["fwd_depot"] = dst.id
	fob["fwd_site"] = site
	fob["src_depot"] = fob.placed.supply.id
	return {"src": fob.placed.supply, "dst": dst, "site": site}


## Overlap area (m2) of the footprints of two vehicles.
func _overlap_area(a: UnitState, b: UnitState) -> float:
	var pa := _footprint(a)
	var pb := _footprint(b)
	var total := 0.0
	for poly in Geometry2D.intersect_polygons(pa, pb):
		var area := 0.0
		for i in poly.size():
			var p: Vector2 = poly[i]
			var q: Vector2 = poly[(i + 1) % poly.size()]
			area += p.x * q.y - q.x * p.y
		total += absf(area) * 0.5
	return total


func _footprint(u: UnitState) -> PackedVector2Array:
	var d := u.veh.def()
	var out := PackedVector2Array()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var local := Vector3(c.x * d.width * 0.5, 0.0, c.y * d.length * 0.5)
		var w := u.position + Basis(Vector3.UP, u.yaw) * local
		out.append(Vector2(w.x, w.z))
	return out


## Two loaded trucks and an APC escort drive to the forward depot as a convoy: spacing, speed
## matching, a vehicle that falls behind (the column waits), the player taking over one truck,
## and unloading at the end.
func _convoy() -> Dictionary:
	var out := {}
	var fd := await _forward_depot()
	var src: StructureState = fd.src
	var dst: StructureState = fd.dst
	var site: Dictionary = fd.site
	var c: Vector3 = fob.center
	var lg := demo.sim.logistics
	var vs := demo.sim.vehicles
	var t1 := _veh(VehicleDefs.TRUCK, FacilityDefs.dock_point(src, 0), PI)
	var t2 := _veh(VehicleDefs.TRUCK, FacilityDefs.dock_point(src, 1), PI)
	var esc := _veh(VehicleDefs.APC, FacilityDefs.dock_point(src, 2), PI)
	await _physics(5)
	demo.rts_camera.frame(FacilityDefs.dock_point(src, 1), 0.4, 50.0)
	await _seconds(1.5)
	var base_tot := _supply_totals()
	var ammo0 := src.inventory.get_qty(Inventory.AMMO)
	var fuel0 := src.inventory.get_qty(Inventory.FUEL)
	var ammo_each := minf(1500.0, src.inventory.get_qty(Inventory.AMMO))
	lg.order_load(t1.id, src.id, Inventory.AMMO, ammo_each)
	lg.order_load(t2.id, src.id, Inventory.FUEL, 1500.0)
	await _warp(120.0, 4.0, 60.0, func() -> bool: return t1.veh.job.is_empty() and t2.veh.job.is_empty())
	out["loaded"] = {"t1": t1.veh.cargo.summary(), "t2": t2.veh.cargo.summary()}
	_expect(absf(t1.veh.cargo.get_qty(Inventory.AMMO) - ammo_each) < 0.5 and absf(t2.veh.cargo.get_qty(Inventory.FUEL) - 1500.0) < 0.5, "convoy: loading %s" % JSON.stringify(out.loaded))
	_shot("14_convoy_forming")
	var members := [t1.id, t2.id, esc.id]
	var res := vs.convoy.order_convoy(members, site.dock, "Supply convoy")
	out["order"] = {"ok": res.ok, "reason": res.reason, "driving": res.get("driving", []).size(), "convoy": res.get("convoy", -1)}
	_expect(res.ok and res.driving.size() == 3, "convoy: not formed %s" % JSON.stringify(out.order))
	if not res.ok:
		return out
	var cid: int = res.convoy
	# Per-tick observation of the column.
	var obs := {"n": 0, "overlaps": 0, "max_spread_m": 0.0, "min_gap_m": INF, "leader_waits_s": 0.0, "max_speed": 0.0, "teleports": 0}
	var last := {}
	var sampler := func() -> void:
		var dt: float = demo.sim.last_delta
		if dt <= 0.0:
			return
		obs.n += 1
		var us: Array[UnitState] = [t1, t2, esc]
		for i in us.size():
			var u := us[i]
			if last.has(u.id) and _flat(last[u.id], u.position) > 25.0 * 1.3 * dt + 0.3:
				obs.teleports += 1
			last[u.id] = u.position
			obs.max_speed = maxf(obs.max_speed, absf(u.veh.speed))
			for j in range(i + 1, us.size()):
				var o := us[j]
				var area := _overlap_area(u, o)
				obs["max_overlap_m2"] = maxf(obs.get("max_overlap_m2", 0.0), area)
				# Corner clips up to 3 m2 (the collision circles are tighter than the hulls) are tolerated.
				if area > 3.0:
					obs.overlaps += 1
					if not obs.has("first_overlap") or area > obs.get("worst_area", 0.0):
						obs["first_overlap"] = {"t": snappedf(demo.sim.state.time, 0.1), "pair": [u.id, o.id], "area": snappedf(area, 0.1), "a": [snappedf(u.position.x, 0.1), snappedf(u.position.z, 0.1), snappedf(u.yaw, 0.01), snappedf(u.veh.speed, 0.1), u.veh.status_name()],
							"b": [snappedf(o.position.x, 0.1), snappedf(o.position.z, 0.1), snappedf(o.yaw, 0.01), snappedf(o.veh.speed, 0.1), o.veh.status_name()]}
						obs["worst_area"] = area
		var spread := maxf(_flat(esc.position, t1.position), maxf(_flat(esc.position, t2.position), _flat(t1.position, t2.position)))
		obs.max_spread_m = maxf(obs.max_spread_m, spread)
		if t1.order == UnitState.Order.MOVE and absf(t1.veh.speed) < 0.3:
			obs.leader_waits_s += dt
	tree.physics_frame.connect(sampler)
	if "--dbg" in OS.get_cmdline_user_args():
		for k in 30:
			await _warp(2.0, 1.0, 20.0)
			var line := "t=%.0f " % demo.sim.state.time
			for u: UnitState in [t1, t2, esc]:
				line += "| %d (%.1f,%.1f) y%.2f v%.1f %s ri%d " % [u.id, u.position.x - c.x, u.position.z - c.z, u.yaw, u.veh.speed, u.veh.status_name(), u.veh.route_i]
			print("DBG ", line)
		_shot("14b_yard_jam")
	await _warp(45.0, 4.0, 60.0)
	var apc_speed := esc.veh.speed
	demo.rts_camera.frame(t1.position, 0.5, 70.0)
	await _seconds(0.5)
	_shot("15_convoy_on_road")
	out["early"] = {"leader_kmh": snappedf(t1.veh.speed * 3.6, 0.1), "t1_kmh": snappedf(t1.veh.speed * 3.6, 0.1), "t2_kmh": snappedf(t2.veh.speed * 3.6, 0.1), "spread_m": snappedf(obs.max_spread_m, 0.1),
		"in_convoy": [esc.veh.convoy_id == cid, t1.veh.convoy_id == cid, t2.veh.convoy_id == cid], "describe": vs.convoy.describe(cid)}
	# The rear escort runs dry: the column falls apart, the leader waits for it, then it goes on.
	var tank := esc.veh.fuel
	esc.veh.fuel = 0.0
	await _warp(60.0, 4.0, 90.0)
	var lead_gap := _flat(t1.position, esc.position)
	out["fell_behind"] = {"rear_status": esc.veh.status_name(), "rear_reason": esc.veh.reason, "leader_kmh": snappedf(t1.veh.speed * 3.6, 0.1), "gap_leader_to_t2_m": snappedf(lead_gap, 1.0), "leader_waited_s": snappedf(obs.leader_waits_s, 1.0)}
	esc.veh.fuel = tank
	# Player takes over truck 2 for a while; the others carry on coherently.
	demo.rts.select([t2.id])
	demo.game.drive(t2.id)
	await _seconds(0.5)
	_key(KEY_W, true)
	await _warp(12.0, 1.0, 30.0)
	_key(KEY_W, false)
	_key(KEY_SPACE, true)
	await _warp(4.0, 1.0, 20.0)
	_key(KEY_SPACE, false)
	var drove := t2.player_controlled
	demo.game.enter_rts()
	await _physics(5)
	out["player_took_over"] = {"was_driving": drove, "resumed_order": t2.order == UnitState.Order.MOVE, "still_in_convoy": t2.veh.convoy_id == cid, "others_moving": esc.order == UnitState.Order.MOVE and t1.order == UnitState.Order.MOVE}
	_expect(drove and t1.order == UnitState.Order.MOVE and esc.order == UnitState.Order.MOVE and t2.order == UnitState.Order.MOVE and t2.veh.convoy_id == cid, "convoy: takeover %s" % JSON.stringify(out.player_took_over))
	await _warp(1500.0, 16.0, 400.0, func() -> bool: return esc.order == UnitState.Order.NONE and t1.order == UnitState.Order.NONE and t2.order == UnitState.Order.NONE)
	tree.physics_frame.disconnect(sampler)
	await _seconds(2.5)
	var ends := [t1, t2, esc]
	var col := []
	for u: UnitState in ends:
		col.append({"id": u.id, "type": String(u.veh.type_id), "arrived": u.move_state == UnitState.MoveState.ARRIVED, "dist_to_dock_m": snappedf(_flat(u.position, site.dock), 1.0), "status": u.veh.status_name()})
	var spacing := [snappedf(_flat(t1.position, t2.position), 1.0), snappedf(_flat(t2.position, esc.position), 1.0)]
	obs["max_overlap_m2"] = snappedf(obs.get("max_overlap_m2", 0.0), 0.01)
	obs.erase("min_gap_m")
	obs["max_spread_m"] = snappedf(obs.max_spread_m, 1.0)
	obs["leader_waits_s"] = snappedf(obs.leader_waits_s, 1.0)
	out["arrival"] = {"column": col, "spacing_m": spacing, "observation": obs}
	for u: UnitState in ends:
		_expect(u.move_state == UnitState.MoveState.ARRIVED, "convoy: %s did not arrive (%s %s)" % [u.unit_name, u.veh.status_name(), u.veh.reason])
	_expect(obs.overlaps == 0 and obs.teleports == 0, "convoy: overlaps %d teleports %d" % [obs.overlaps, obs.teleports])
	_expect(vs.convoy.describe(cid) == "", "convoy: not dissolved after arrival")
	# Unload both trucks at the forward depot.
	var before := dst.inventory.summary()
	lg.order_unload(t1.id, dst.id)
	lg.order_unload(t2.id, dst.id)
	await _warp(200.0, 4.0, 90.0, func() -> bool: return t1.veh.job.is_empty() and t2.veh.job.is_empty())
	out["t2_job"] = {"job": t2.veh.job, "status": t2.veh.status_name(), "reason": t2.veh.reason, "order": t2.order, "diag": vs.diagnose(t2)}
	out["unloaded"] = {"before": before, "after": dst.inventory.summary(), "t1": t1.veh.cargo.summary(), "t2": t2.veh.cargo.summary()}
	var tot := _supply_totals()
	_expect(t1.veh.cargo.is_empty() and t2.veh.cargo.is_empty(), "convoy: cargo left aboard %s" % JSON.stringify(out.unloaded))
	_expect(absf(tot.ammo - base_tot.ammo) < 0.5 and absf(tot.supplies - base_tot.supplies) < 0.5, "convoy: supplies not conserved %s vs %s" % [tot, base_tot])
	_shot("16_convoy_at_forward_depot")
	return out


# --- Phase D: bases, recruiting, vehicles, automation ------------------------------------------------

func _bases() -> Dictionary:
	var out := {}
	var fd := await _forward_depot()
	var src: StructureState = fd.src
	var dst: StructureState = fd.dst
	var lg := demo.sim.logistics
	var bs := lg.bases
	var pf := war.player_faction
	# --- ownership and grouping ---------------------------------------------------------------
	var mine := bs.bases_of(pf)
	var main_id: int = src.base_id
	var main := bs.summary(main_id)
	out["bases"] = {"count": mine.size(), "main": {"name": main.name, "kind": main.kind, "facilities": main.facilities}, "forward": {"id": dst.base_id, "kind": bs.base_kind(dst.base_id), "name": bs.summary(dst.base_id).name}}
	_expect(mine.size() >= 2 and dst.base_id != main_id and bs.base_kind(main_id) == "Main base", "bases: grouping %s" % JSON.stringify(out.bases))
	var owners_ok := true
	for s in cs.all():
		if FacilityDefs.has(s.type_id) and (s.faction != pf or s.base_id < 0):
			owners_ok = false
	_expect(owners_ok, "bases: a facility has no owner or base")
	# --- recruiting ------------------------------------------------------------------------------
	var barracks: StructureState = fob.placed.barracks_1
	var f := war.faction(pf)
	var reserves0 := f.reserves
	var stock0 := bs.base_stock(main_id)
	var squads0 := demo.sim.state.squads.size()
	var rr := bs.recruit(barracks.id)
	out["recruit"] = {"ok": rr.ok, "reason": rr.reason, "reserves_before": reserves0, "reserves_after": f.reserves, "queue": barracks.facility.get("queue", []).size()}
	_expect(rr.ok and f.reserves == reserves0 - 8, "bases: recruit %s" % JSON.stringify(out.recruit))
	var stock1 := bs.base_stock(main_id)
	out["recruit"]["paid"] = {"supplies": snappedf(stock0.supplies - stock1.supplies, 0.1), "ammo": snappedf(stock0.ammo - stock1.ammo, 0.1)}
	_expect(absf(stock0.supplies - stock1.supplies - 320.0) < 0.5 and absf(stock0.ammo - stock1.ammo - 192.0) < 0.5, "bases: recruit cost %s" % JSON.stringify(out.recruit.paid))
	# Cancel one (refund) and queue again, then let it finish.
	var cancelled := bs.cancel_queue(barracks.id, 0)
	var stock2 := bs.base_stock(main_id)
	_expect(cancelled and absf(stock2.supplies - stock0.supplies) < 0.5 and f.reserves == reserves0, "bases: refund on cancel")
	bs.recruit(barracks.id)
	await _warp(75.0, 4.0, 60.0, func() -> bool: return demo.sim.state.squads.size() > squads0)
	var new_sq: SquadState = null
	for sq in demo.sim.state.all_squads():
		if sq.id > 5 and sq.faction == pf and sq.members.size() == 8 and sq.squad_name != "":
			new_sq = sq
	var equipped := 0
	var faction_ok := 0
	var near_barracks := 0
	if demo.sim.state.squads.size() > squads0:
		new_sq = demo.sim.state.all_squads()[-1]
		for id in new_sq.members:
			var s := _u(id)
			equipped += 1 if s.weapon_id == &"rifle" and s.reserve == 120 else 0
			faction_ok += 1 if s.faction == pf else 0
			near_barracks += 1 if _flat(s.position, barracks.position) < 40.0 else 0
	out["recruited"] = {"squads_now": demo.sim.state.squads.size(), "squads_before": squads0, "equipped": equipped, "faction_ok": faction_ok, "near_barracks": near_barracks}
	_expect(demo.sim.state.squads.size() == squads0 + 1 and equipped == 8 and faction_ok == 8 and near_barracks == 8, "bases: recruited squad %s" % JSON.stringify(out.recruited))
	# Not enough supplies: drain the base and ask again.
	var drained := {}
	for s in bs.base_stores(main_id):
		drained[s.id] = s.inventory.get_qty(Inventory.SUPPLIES)
		s.inventory.take(Inventory.SUPPLIES, 1.0e9)
	var r_poor := bs.recruit(barracks.id)
	out["recruit_without_supplies"] = r_poor.reason
	_expect(not r_poor.ok and r_poor.reason.contains("Not enough"), "bases: recruiting without supplies was allowed")
	for id in drained:
		cs.get_structure(id).inventory.add(Inventory.SUPPLIES, drained[id])
	# --- vehicles ------------------------------------------------------------------------------
	var vdepot: StructureState = fob.placed.vehicle_depot
	var veh0 := demo.sim.vehicles.ids.size()
	var a1 := bs.acquire_vehicle(vdepot.id, VehicleDefs.TRUCK)
	var a2 := bs.acquire_vehicle(vdepot.id, VehicleDefs.APC)
	var a3 := bs.acquire_vehicle(vdepot.id, VehicleDefs.TRUCK)
	out["acquire"] = {"truck": a1.ok, "apc": a2.ok, "third_while_busy": a3.reason, "stock": vdepot.facility.get("stock", {})}
	_expect(a1.ok and a2.ok and not a3.ok, "bases: acquire %s" % JSON.stringify(out.acquire))
	await _warp(60.0, 4.0, 60.0, func() -> bool: return demo.sim.vehicles.ids.size() >= veh0 + 2)
	var new_vehicles := []
	for id in demo.sim.vehicles.ids:
		var vu := _u(id)
		if id > 0 and vu.faction == pf and _flat(vu.position, vdepot.position) < 80.0 and vu.veh.odometer < 1.0:
			new_vehicles.append(String(vu.veh.type_id))
	out["acquired_vehicles"] = {"count": demo.sim.vehicles.ids.size() - veh0, "types": new_vehicles}
	_expect(demo.sim.vehicles.ids.size() == veh0 + 2, "bases: vehicles not delivered %s" % JSON.stringify(out.acquired_vehicles))
	# Stock limit: the depot hands out three trucks only.
	var ok_count := 0
	for k in 4:
		var rt := bs.acquire_vehicle(vdepot.id, VehicleDefs.TRUCK)
		if rt.ok:
			ok_count += 1
			await _warp(35.0, 4.0, 40.0)
	var r_limit := bs.acquire_vehicle(vdepot.id, VehicleDefs.TRUCK)
	out["stock_limit"] = {"trucks_granted_after_first": ok_count, "then": r_limit.reason}
	_expect(not r_limit.ok and r_limit.reason.contains("left"), "bases: stock limit %s" % JSON.stringify(out.stock_limit))
	# --- base inventory / summary -------------------------------------------------------------
	var sm := bs.summary(main_id)
	out["summary"] = {"stock": sm.stock, "vehicles": sm.vehicles.size(), "soldiers": sm.soldiers, "activities": sm.activities}
	_expect(sm.vehicles.size() >= 3 and sm.soldiers >= 8, "bases: summary %s" % JSON.stringify(out.summary))
	# --- repair --------------------------------------------------------------------------------
	var truck: UnitState = null
	for id in demo.sim.vehicles.ids:
		if _u(id).veh.type_id == VehicleDefs.TRUCK and _flat(_u(id).position, vdepot.position) < 120.0:
			truck = _u(id)
	if truck:
		demo.sim.vehicles.apply_damage(truck.id, 150.0)
		var hp0 := truck.health
		var sup0: float = bs.base_stock(main_id).supplies
		var rp := lg.order_repair(truck.id, vdepot.id)
		await _warp(180.0, 4.0, 90.0, func() -> bool: return truck.veh.job.is_empty())
		out["repair"] = {"ok": rp.ok, "reason": rp.reason, "hp_before": snappedf(hp0, 0.1), "hp_after": snappedf(truck.health, 0.1), "supplies_used": snappedf(sup0 - bs.base_stock(main_id).supplies, 0.1)}
		_expect(rp.ok and truck.health > hp0 + 100.0 and absf(out.repair.supplies_used - (truck.health - hp0) * 0.5) < 0.6, "bases: repair %s" % JSON.stringify(out.repair))
	# --- destroyed vehicle: passengers out, orders dropped, no further movement -----------------
	var apc: UnitState = null
	for id in demo.sim.vehicles.ids:
		if _u(id).veh.type_id == VehicleDefs.APC and _flat(_u(id).position, vdepot.position) < 120.0:
			apc = _u(id)
	if apc:
		var sq2 := _spawn(0, apc.position + Vector3(10, 0, 10), 6)
		await _physics(3)
		demo.sim.vehicles.transport.order_transport(apc.id, sq2.id)
		await _warp(30.0, 4.0, 40.0, func() -> bool: return apc.veh.occupants.size() >= 6)
		apc.veh.cargo.add(Inventory.SUPPLIES, 200.0)
		demo.sim.vehicles.order_drive(apc.id, apc.position + Vector3(0, 0, 120))
		await _warp(3.0, 1.0, 10.0)
		demo.sim.vehicles.apply_damage(apc.id, 5000.0)
		await _warp(8.0, 1.0, 20.0)
		var aboard := 0
		for id in sq2.members:
			aboard += 1 if _u(id).vehicle_id >= 0 else 0
		out["destroyed"] = {"alive": apc.alive, "status": apc.veh.status_name(), "order": apc.order, "speed": snappedf(apc.veh.speed, 0.1), "aboard_after": aboard, "cargo_kept": apc.veh.cargo.get_qty(Inventory.SUPPLIES)}
		_expect(not apc.alive and apc.order == UnitState.Order.NONE and absf(apc.veh.speed) < 0.2 and aboard == 0, "bases: destroyed vehicle %s" % JSON.stringify(out.destroyed))
	# --- automation: keep the forward depot stocked ---------------------------------------------
	var tr2 := _veh(VehicleDefs.TRUCK, FacilityDefs.dock_point(src, 1), PI)
	await _physics(3)
	var rule := bs.add_rule_restock(dst.id, src.id, Inventory.SUPPLIES, 500.0, 1200.0, tr2.id)
	await _warp(20.0, 4.0, 30.0)
	out["rule"] = {"text": bs.describe_rule(rule), "job": lg.describe_job(tr2), "runs": rule.runs}
	_expect(rule.runs >= 1 and not tr2.veh.job.is_empty(), "bases: the rule did not send the truck %s" % JSON.stringify(out.rule))
	# The player overrides: a plain move order cancels the job and pauses the rule.
	demo.sim.vehicles.order_drive(tr2.id, tr2.position + Vector3(0, 0, 60))
	await _warp(5.0, 1.0, 20.0)
	out["override"] = {"job_cleared": tr2.veh.job.is_empty(), "rule_paused": float(rule.pause_until) > demo.sim.state.time, "last": rule.last}
	_expect(tr2.veh.job.is_empty() and float(rule.pause_until) > demo.sim.state.time, "bases: override %s" % JSON.stringify(out.override))
	bs.set_rule_enabled(rule.id, false)
	out["rule_disabled"] = bs.describe_rule(rule)
	return out

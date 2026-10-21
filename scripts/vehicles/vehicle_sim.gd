## Vehicle driving for every vehicle record (LOGISTICS-01), owned by WorldSim.
##
## One kinematic simulation, no matter who is watching: every physics tick each vehicle's
## UnitState/VehicleState is advanced here — pure-pursuit steering along the planned route,
## a speed profile from curvature and braking distance, a bicycle model for heading and
## position, the ground height (terrain or bridge deck), footprint tests against structures,
## other vehicles and (near the camera) the physics probe of the body, stuck recovery and fuel
## use. VehicleBody and UnitProxy only display the record, so promotion/demotion cannot change
## a journey and a vehicle far from the camera drives exactly as one in front of it.
##
## The player's input (VehicleState.in_*) replaces the route follower while the unit is
## player-controlled; the Move order and the route stay and can be resumed
## (release_control) or replaced (order_drive).
class_name VehicleSim
extends RefCounted

const MAP_LIMIT := 9990.0
const SCAN_TICKS := 6
## No progress for this long (s) while it should be moving: recovery starts.
const STUCK_S := 5.0
const MAX_RECOVERIES := 4

var sim: WorldSim
var router := VehicleRouter.new()
## Infantry boarding, riding and disembarking (phase B).
var transport: VehicleTransport
## Vehicles travelling together (LOGISTICS-01 phase C).
var convoy: VehicleConvoy
## Vehicle unit ids (kept in step with WorldState by its signals).
var ids: Array[int] = []
var ticks := 0
var tick_usec := 0
## Orders given / failed / arrived (statistics for tests and the report).
var stats := {"ordered": 0, "arrived": 0, "failed": 0, "recovered": 0, "replanned": 0}
## Last obstacle-scan result per vehicle id: free distance ahead along the route (m).
var _gap := {}
var _on_road := {}


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
	transport = VehicleTransport.new(self)
	convoy = VehicleConvoy.new(self)
	sim.state.unit_added.connect(_on_added)
	sim.state.unit_removed.connect(_on_removed)
	sim.state.restored.connect(refresh)


func setup(routes: StrategicRoutes) -> void:
	router.setup(sim.state.roads, routes, sim.terrain, sim.structures)


func refresh() -> void:
	ids.clear()
	for u: UnitState in sim.state.units.values():
		if u.kind == UnitState.Kind.VEHICLE and u.veh:
			ids.append(u.id)
	ids.sort()
	for u: UnitState in sim.state.units.values():
		if u.kind == UnitState.Kind.VEHICLE and u.veh:
			prepare_route(u.veh)


func _on_added(u: UnitState) -> void:
	if u.kind == UnitState.Kind.VEHICLE and not ids.has(u.id):
		ids.append(u.id)
		ids.sort()


func _on_removed(id: int) -> void:
	ids.erase(id)
	_gap.erase(id)


# --- Orders ---------------------------------------------------------------------------------

## The player's group order: the vehicles drive to the point, a line abreast when several go
## to one place. Returns {n, texts}.
func order_group(vids: Array, dest: Vector3) -> Dictionary:
	var n := 0
	var texts: Array[String] = []
	var half := vids.size() - 1
	var i := 0
	for id in vids:
		var u := sim.state.get_unit(id)
		var at := dest
		if vids.size() > 1:
			var fwd := Vector3(dest.x - u.position.x, 0.0, dest.z - u.position.z).normalized()
			at = dest + Vector3(fwd.z, 0.0, -fwd.x) * ((i - half * 0.5) * 12.0)
		i += 1
		var res := order_drive(id, at)
		if res.ok:
			n += 1
			texts.append("%s: %.1f km (%.1f km by road)" % [u.unit_name, res.length_m / 1000.0, res.road_m / 1000.0])
		else:
			texts.append("%s: %s" % [u.unit_name, res.reason])
	return {"n": n, "texts": texts}


## A vehicle takes damage (the hook the combat code uses); at zero it is disabled: it stops,
## drops its orders and jobs, and its passengers get out. Cargo stays in the wreck.
func apply_damage(id: int, amount: float, source_id := -1) -> void:
	var u := sim.state.get_unit(id)
	if u == null or u.veh == null or not u.alive:
		return
	u.health = maxf(u.health - amount, 0.0)
	sim.state.unit_damaged.emit(u, amount, 0, source_id)
	if u.health <= 0.0:
		u.alive = false
		u.veh.status = VehicleState.Status.DISABLED
		u.veh.job = {}
		leave_convoy_of(u)
		_clear_order(u, VehicleState.Status.DISABLED)
		u.move_state = UnitState.MoveState.IDLE
		_event(u, "was destroyed")
		sim.state.unit_died.emit(u)


func leave_convoy_of(u: UnitState) -> void:
	if u.veh.convoy_id >= 0:
		convoy.leave(u.id)


## Parked vehicles other than `u` as obstacle circles for the router's cross-country legs.
func _collect_parked(u: UnitState) -> void:
	var out: Array = []
	for oid in ids:
		if oid == u.id:
			continue
		var o: UnitState = sim.state.units.get(oid)
		if o == null or not o.alive or absf(o.veh.speed) > 0.3 or o.order != UnitState.Order.NONE or o.veh.convoy_id >= 0:
			continue
		if Vector2(o.position.x - u.position.x, o.position.z - u.position.z).length() > 700.0:
			continue
		var od := o.veh.def()
		var ofwd := Vector3(-sin(o.yaw), 0.0, -cos(o.yaw))
		for z in od.circle_z:
			var c := o.position + ofwd * z
			out.append([c.x, c.z, od.collide_r])
	router.parked_circles = out


## Plans a route to `target` for a vehicle and starts driving it. Returns the planner result
## ({ok, reason, length_m, road_m, ...}); on failure the vehicle keeps its previous order.
func order_drive(id: int, target: Vector3, from_transport := false) -> Dictionary:
	var u := sim.state.get_unit(id)
	if u == null or u.veh == null or not u.alive:
		return {"ok": false, "reason": "No such vehicle"}
	var v := u.veh
	if v.status == VehicleState.Status.DISABLED:
		return {"ok": false, "reason": "The vehicle is disabled"}
	if not from_transport:
		sim.logistics.bases.on_manual_order(id)
	if not from_transport and v.convoy_id >= 0:
		convoy.leave(id)
	if not from_transport and not v.job.is_empty():
		sim.logistics.cancel_job(id, "replaced by a move order")
	if not from_transport:
		match v.phase:
			VehicleState.Phase.APPROACH:
				transport.cancel(id)
			VehicleState.Phase.BOARDING:
				# A Move order while boarding: leave now with whoever is aboard.
				transport.depart(u, v, target)
			VehicleState.Phase.TRANSIT:
				v.transport_dest = target
	var t := Vector3(target.x, ground_at(target), target.z)
	_collect_parked(u)
	var res := router.plan(u.position, t, v.def())
	if not res.ok:
		v.reason = res.reason
		_event(u, "cannot go there: %s" % res.reason)
		stats.failed += 1
		return res
	var need: float = res.length_m / 1000.0 * v.def().fuel_per_km * 1.05
	if v.fuel < need:
		res = {"ok": false, "reason": "Insufficient fuel: the route needs %d l, the tank has %d l" % [ceili(need), roundi(v.fuel)]}
		v.reason = res.reason
		_event(u, "cannot go there: %s" % res.reason)
		stats.failed += 1
		return res
	_apply_route(u, res)
	u.order = UnitState.Order.MOVE
	u.order_target = t
	u.move_state = UnitState.MoveState.MOVING
	v.recoveries = 0
	v.replans = 0
	v.stuck_s = 0.0
	v.reverse_left = 0.0
	v.reason = ""
	stats.ordered += 1
	sim.state.order_changed.emit(u)
	return res


func _apply_route(u: UnitState, res: Dictionary) -> void:
	var v := u.veh
	v.route = res.points
	v.route_cap = res.caps
	v.route_i = 0
	v.route_info = {"length_m": snappedf(res.length_m, 1.0), "road_m": snappedf(res.road_m, 1.0),
		"offroad_m": snappedf(res.offroad_m, 1.0), "bridges": res.bridges, "roads": res.roads}
	prepare_route(v)
	v._progress_ref = u.position
	v._progress_t = 0.0


## Stops the vehicle and forgets its order and route.
func halt(id: int) -> void:
	var u := sim.state.get_unit(id)
	if u == null or u.veh == null:
		return
	if u.veh.phase == VehicleState.Phase.TRANSIT or u.veh.phase == VehicleState.Phase.APPROACH:
		u.veh.phase = VehicleState.Phase.NONE
	_clear_order(u, VehicleState.Status.PARKED)
	u.move_state = UnitState.MoveState.IDLE
	sim.state.order_changed.emit(u)


## Stops driving without touching the transport phase (the transport code uses it).
func halt_in_place(u: UnitState) -> void:
	_clear_order(u, VehicleState.Status.PARKED)
	u.move_state = UnitState.MoveState.IDLE


func status_note(u: UnitState, text: String) -> void:
	_event(u, text)


## Ground height plus a soldier's standing offset (terrain or bridge deck).
func ground_with_clearance(p: Vector3) -> Vector3:
	return Vector3(p.x, ground_at(p) + 0.25, p.z)


## A spot where a soldier may stand: not in a structure, not in water, not inside a vehicle.
func spot_valid(p: Vector3) -> bool:
	if sim.structures:
		if sim.structures.blocks_point(Vector2(p.x, p.z), 0.6):
			return false
		if is_nan(sim.state.roads.deck_height(p)) and sim.structures.is_wet(p.x, p.z):
			return false
	for oid in ids:
		var o: UnitState = sim.state.units.get(oid)
		if o == null:
			continue
		var d := o.veh.def()
		var off := p - o.position
		var lz := off.x * -sin(o.yaw) + off.z * -cos(o.yaw)
		var lx := off.x * cos(o.yaw) - off.z * sin(o.yaw)
		if absf(lx) < d.width * 0.5 + 0.6 and absf(lz) < d.length * 0.5 + 0.6:
			return false
	return true


func _clear_order(u: UnitState, status: int) -> void:
	var v := u.veh
	u.order = UnitState.Order.NONE
	u.order_target = Vector3.ZERO
	v.route = PackedVector3Array()
	v.route_cap = PackedFloat32Array()
	v.profile = PackedFloat32Array()
	v.route_s = PackedFloat32Array()
	v.route_i = 0
	v.status = status


## The player takes the wheel: the order and route are suspended, not lost.
func take_control(id: int) -> bool:
	var u := sim.state.get_unit(id)
	if u == null or u.veh == null or not u.alive or u.veh.status == VehicleState.Status.DISABLED:
		return false
	u.player_controlled = true
	u.veh.status = VehicleState.Status.PLAYER
	u.veh.in_throttle = 0.0
	u.veh.in_steer = 0.0
	u.veh.in_brake = 0.0
	u.veh.reverse_left = 0.0
	return true


## Back to the simulation. A vehicle that still has an order and is near its route goes on;
## one that drifted away plans the route again. `resume` false drops the order.
func release_control(id: int, resume := true) -> void:
	var u := sim.state.get_unit(id)
	if u == null or u.veh == null:
		return
	var v := u.veh
	u.player_controlled = false
	v.in_throttle = 0.0
	v.in_steer = 0.0
	v.in_brake = 1.0
	v.status = VehicleState.Status.PARKED
	if resume and u.order == UnitState.Order.MOVE and u.order_target.is_finite():
		# Internal: the vehicle keeps its convoy, job and transport state; only the route is planned again.
		order_drive(id, u.order_target, true)
	elif not resume:
		_clear_order(u, VehicleState.Status.PARKED)


# --- Route preparation ------------------------------------------------------------------------

## Cumulative length and the speed profile of the route: ceilings per point, the speed a
## corner allows (lateral acceleration), and a backward pass so the vehicle can brake in time
## for every slower point and for the end of the route.
func prepare_route(v: VehicleState) -> void:
	var n := v.route.size()
	v.profile = PackedFloat32Array()
	v.route_s = PackedFloat32Array()
	if n < 2:
		return
	var d := v.def()
	v.route_s.resize(n)
	v.profile.resize(n)
	var s := 0.0
	for i in n:
		if i > 0:
			s += Vector2(v.route[i].x - v.route[i - 1].x, v.route[i].z - v.route[i - 1].z).length()
		v.route_s[i] = s
	for i in n:
		var cap: float = v.route_cap[i] if i < v.route_cap.size() else d.offroad_speed
		var sp := minf(cap, d.max_speed)
		var r := _radius(v.route, maxi(i - 2, 0), i, mini(i + 2, n - 1))
		if is_finite(r):
			sp = minf(sp, maxf(sqrt(d.lat_accel * r), 2.0))
		v.profile[i] = sp
	v.profile[n - 1] = 0.0
	for i in range(n - 2, -1, -1):
		var ds := v.route_s[i + 1] - v.route_s[i]
		v.profile[i] = minf(v.profile[i], sqrt(v.profile[i + 1] * v.profile[i + 1] + 2.0 * d.plan_decel * ds))


static func _radius(r: PackedVector3Array, ia: int, ib: int, ic: int) -> float:
	var a := Vector2(r[ia].x, r[ia].z)
	var b := Vector2(r[ib].x, r[ib].z)
	var c := Vector2(r[ic].x, r[ic].z)
	var cross := absf((b - a).cross(c - a))
	if cross < 1e-4:
		return INF
	return a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * cross)


# --- The tick ---------------------------------------------------------------------------------

func update(dt: float) -> void:
	if ids.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	ticks += 1
	convoy.update(dt)
	for id in ids:
		var u: UnitState = sim.state.units.get(id)
		if u and u.veh:
			_step(u, dt)
	tick_usec += Time.get_ticks_usec() - t0


func _step(u: UnitState, dt: float) -> void:
	var v := u.veh
	var d := v.def()
	var target_speed := 0.0
	var steer_target := 0.0
	var rate := d.brake
	var following := false
	# The physics probe belongs to a body: without one (far from the camera) nothing is reported.
	if not u.has_body:
		v.probe_ahead = INF
	if not u.alive or v.status == VehicleState.Status.DISABLED:
		v.status = VehicleState.Status.DISABLED
		if u.order != UnitState.Order.NONE:
			_clear_order(u, VehicleState.Status.DISABLED)
	elif u.player_controlled:
		v.status = VehicleState.Status.PLAYER
		var cap := d.max_speed if _road_state(u) else maxf(d.offroad_speed * 2.0, 12.0)
		var thr := v.in_throttle
		if v.in_brake > 0.1:
			target_speed = 0.0
			rate = d.brake
		elif thr > 0.05:
			if v.speed < -0.5:
				target_speed = 0.0
				rate = d.brake
			else:
				target_speed = thr * cap
				rate = d.accel
		elif thr < -0.05:
			if v.speed > 0.5:
				target_speed = 0.0
				rate = d.brake
			else:
				target_speed = thr * d.max_reverse
				rate = d.accel
		else:
			target_speed = 0.0
			rate = 1.2
		steer_target = -v.in_steer * d.max_steer / (1.0 + pow(absf(v.speed) / 12.0, 2.0))
	elif v.reverse_left > 0.0:
		v.reverse_left -= dt
		target_speed = -2.5
		rate = d.accel
		# Back out on opposite lock, so the nose swings away from what it hit.
		steer_target = -signf(v.steer if absf(v.steer) > 0.05 else 1.0) * d.max_steer
	elif u.order == UnitState.Order.MOVE and v.route.size() >= 2:
		following = true
		var res := _follow(u, v, d, dt)
		target_speed = res.speed
		steer_target = res.steer
	else:
		if v.status != VehicleState.Status.NO_FUEL and v.status != VehicleState.Status.BLOCKED:
			v.status = VehicleState.Status.PARKED
		v.stuck_s = 0.0
	# Fuel.
	if v.fuel <= 0.0 and (target_speed != 0.0):
		target_speed = 0.0
		v.status = VehicleState.Status.NO_FUEL
		v.reason = "Out of fuel"
	# Speed and steering.
	if target_speed > v.speed:
		v.speed = minf(v.speed + rate * dt, target_speed)
	else:
		v.speed = maxf(v.speed - maxf(rate, d.brake if target_speed == 0.0 else rate) * dt, target_speed)
	v.steer = move_toward(v.steer, clampf(steer_target, -d.max_steer, d.max_steer), d.steer_rate * dt)
	if absf(v.speed) < 0.001 and absf(target_speed) < 0.001:
		v.speed = 0.0
		u.velocity = Vector3.ZERO
	else:
		_integrate(u, v, d, dt)
	if following and u.order == UnitState.Order.MOVE:
		_check_stuck(u, v, d, target_speed, dt)
	if v.phase != VehicleState.Phase.NONE or not v.occupants.is_empty():
		transport.update(u, v, dt)
	if not v.job.is_empty():
		sim.logistics.update_vehicle(u, v)


## Pure pursuit along the route: {speed, steer}. Also handles arrival.
func _follow(u: UnitState, v: VehicleState, d: VehicleDefs.Def, dt: float) -> Dictionary:
	if v.profile.size() != v.route.size():
		prepare_route(v)
	var n := v.route.size()
	var i := _nearest(v, u.position)
	v.route_i = i
	var remaining: float = v.route_s[n - 1] - v.route_s[i]
	if remaining < 2.0 or (i >= n - 1):
		_arrive(u, v)
		return {"speed": 0.0, "steer": 0.0}
	# Look-ahead point.
	var ld := clampf(absf(v.speed) * 0.9 + 5.0, 6.0, 22.0)
	var tgt := _point_at(v, i, ld)
	var fwd := Vector3(-sin(u.yaw), 0.0, -cos(u.yaw))
	var right := Vector3(cos(u.yaw), 0.0, -sin(u.yaw))
	var off := tgt - u.position
	var lx := off.dot(right)
	var lz := off.dot(fwd)
	var alpha := atan2(lx, lz)
	var dist := maxf(Vector2(off.x, off.z).length(), 1.0)
	var steer := -atan2(2.0 * d.wheelbase * sin(alpha), dist)
	var speed: float = v.profile[i]
	# Far off the path (or facing away): slow down so the turn can be made.
	var cross := _cross_track(v, i, u.position)
	if cross > 2.5:
		speed = minf(speed, maxf(6.0 - cross * 0.6, 2.5))
	if lz < 0.0:
		speed = minf(speed, 3.0)
		steer = -signf(lx if absf(lx) > 0.01 else 1.0) * d.max_steer
	# Obstacles ahead along the route and the lead vehicle.
	var gap := _gap_ahead(u, v, d, i)
	if v.convoy_id >= 0:
		speed = minf(speed, convoy.speed_limit(u, v))
	if gap < INF:
		var allowed := sqrt(2.0 * d.brake * 0.7 * maxf(gap - 2.5, 0.0))
		if allowed < speed:
			speed = allowed
	if v.probe_ahead < INF:
		var pa := sqrt(2.0 * d.brake * 0.7 * maxf(v.probe_ahead - 3.0, 0.0))
		speed = minf(speed, pa)
	if speed < 0.3 and (gap < 12.0 or v.probe_ahead < 12.0):
		v.status = VehicleState.Status.WAITING
		v.reason = "Waiting: obstacle ahead"
	else:
		v.status = VehicleState.Status.DRIVING
		v.reason = ""
	u.move_state = UnitState.MoveState.MOVING
	return {"speed": speed, "steer": steer}


func _arrive(u: UnitState, v: VehicleState) -> void:
	_clear_order(u, VehicleState.Status.PARKED)
	u.move_state = UnitState.MoveState.ARRIVED
	v.reason = ""
	stats.arrived += 1
	sim.state.order_changed.emit(u)
	_event(u, "arrived")


## Nearest route point at or after the progress index (a window ahead, so a route that
## passes itself does not jump).
func _nearest(v: VehicleState, p: Vector3) -> int:
	var n := v.route.size()
	var lo := maxi(v.route_i - 3, 0)
	var hi := mini(v.route_i + 40, n - 1)
	var best := lo
	var best_d := INF
	for k in range(lo, hi + 1):
		var dd := Vector2(v.route[k].x - p.x, v.route[k].z - p.z).length_squared()
		if dd < best_d:
			best_d = dd
			best = k
	return best


func _cross_track(v: VehicleState, i: int, p: Vector3) -> float:
	var j := mini(i + 1, v.route.size() - 1)
	var a := Vector2(v.route[i].x, v.route[i].z)
	var b := Vector2(v.route[j].x, v.route[j].z)
	var q := Vector2(p.x, p.z)
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-6 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
	return q.distance_to(a + ab * t)


## The route point `dist` metres beyond index i.
func _point_at(v: VehicleState, i: int, dist: float) -> Vector3:
	var n := v.route.size()
	var target_s: float = v.route_s[i] + dist
	var k := i
	while k < n - 1 and v.route_s[k] < target_s:
		k += 1
	return v.route[k]


# --- Movement ----------------------------------------------------------------------------------

func _integrate(u: UnitState, v: VehicleState, d: VehicleDefs.Def, dt: float) -> void:
	var yaw_rate := v.speed / d.wheelbase * tan(v.steer)
	var new_yaw := u.yaw + yaw_rate * dt
	var fwd := Vector3(-sin(new_yaw), 0.0, -cos(new_yaw))
	var step := fwd * (v.speed * dt)
	var np := u.position + step
	# Never into a structure, the water or off the map: stop in place instead.
	var moving_fwd := v.speed > 0.0
	var blocked := false
	if sim.structures and absf(v.speed) > 0.01:
		var was_in := _blocked_at(d, u.position, u.yaw)
		if not was_in and _blocked_at(d, np, new_yaw):
			blocked = true
	if not blocked and (absf(np.x) > MAP_LIMIT or absf(np.z) > MAP_LIMIT):
		blocked = true
	# The player's vehicle never drives through another vehicle: a footprint that is clear now
	# must stay clear. AI vehicles keep their distance with the gap logic instead (a hard stop
	# between two AI vehicles in a crowded yard would only deadlock them).
	if not blocked and (u.player_controlled or v.speed < 0.0) and absf(v.speed) > 0.01 and ids.size() > 1:
		if not _hits_vehicle(u, d, u.position, u.yaw) and _hits_vehicle(u, d, np, new_yaw):
			blocked = true
	if not blocked and sim.structures:
		var front := np + fwd * (d.length * 0.5 * (1.0 if moving_fwd else -1.0))
		if is_nan(sim.state.roads.deck_height(front)) and sim.structures.is_wet(front.x, front.z):
			blocked = true
	if blocked:
		v.speed = 0.0
		u.velocity = Vector3.ZERO
		if u.player_controlled:
			v.reason = "Blocked"
		return
	var moved := step.length()
	u.yaw = wrapf(new_yaw, -PI, PI)
	u.position.x = np.x
	u.position.z = np.z
	u.position.y = ground_at(u.position)
	u.velocity = fwd * v.speed
	v.odometer += absf(v.speed) * dt
	v.fuel = maxf(v.fuel - moved * d.fuel_per_km / 1000.0, 0.0)


## True when the vehicle's collision circles at (p, yaw) touch those of another vehicle.
func _hits_vehicle(u: UnitState, d: VehicleDefs.Def, p: Vector3, yaw: float) -> bool:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	for oid in ids:
		if oid == u.id:
			continue
		var o: UnitState = sim.state.units.get(oid)
		if o == null or not o.alive:
			continue
		var reach := (d.length + o.veh.def().length) * 0.5 + 1.0
		if Vector2(o.position.x - p.x, o.position.z - p.z).length() > reach:
			continue
		var od := o.veh.def()
		var ofwd := Vector3(-sin(o.yaw), 0.0, -cos(o.yaw))
		for z1 in d.circle_z:
			var a := p + fwd * z1
			for z2 in od.circle_z:
				var b := o.position + ofwd * z2
				if Vector2(a.x - b.x, a.z - b.z).length() < d.collide_r + od.collide_r:
					return true
	return false


func _blocked_at(d: VehicleDefs.Def, p: Vector3, yaw: float) -> bool:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	for oz in d.circle_z:
		var q := p + fwd * oz
		if sim.structures.blocks_point(Vector2(q.x, q.z), d.collide_r):
			return true
	return false


func ground_at(p: Vector3) -> float:
	var h: float = sim.terrain.data.get_height(p) if sim.terrain else p.y
	var deck := sim.state.roads.deck_height(p)
	if not is_nan(deck):
		h = deck if is_nan(h) else maxf(h, deck)
	return p.y if is_nan(h) else h


func _road_state(u: UnitState) -> bool:
	# Road or not, refreshed a few times per second (RoadNetwork.on_road scans nearby roads).
	var key := u.id
	var entry: Array = _on_road.get(key, [-1, false])
	if ticks - int(entry[0]) >= 15:
		entry = [ticks, sim.state.roads.on_road(u.position, 2.0)]
		_on_road[key] = entry
	return entry[1]


## Free distance ahead along the planned route: structures within the footprint circle and
## the vehicle ahead. Re-scanned every few ticks.
func _gap_ahead(u: UnitState, v: VehicleState, d: VehicleDefs.Def, i: int) -> float:
	var entry: Array = _gap.get(u.id, [-100, INF])
	if (ticks + u.id) % SCAN_TICKS != 0 and ticks - int(entry[0]) < SCAN_TICKS * 2:
		return entry[1] - 0.0
	var look := clampf(v.speed * v.speed / (2.0 * d.brake * 0.7) + 10.0, 14.0, 45.0)
	var gap := INF
	if sim.structures:
		var n := v.route.size()
		var k := i
		var base_s: float = v.route_s[i]
		while k < n and v.route_s[k] - base_s <= look:
			var p := v.route[k]
			if sim.structures.blocks_point(Vector2(p.x, p.z), d.collide_r):
				gap = v.route_s[k] - base_s - d.length * 0.5
				break
			k += 2
	# The nearest vehicle ahead (within the lane).
	var fwd := Vector3(-sin(u.yaw), 0.0, -cos(u.yaw))
	var right := Vector3(cos(u.yaw), 0.0, -sin(u.yaw))
	for oid in ids:
		if oid == u.id:
			continue
		var o: UnitState = sim.state.units.get(oid)
		if o == null or not o.alive:
			continue
		var off := o.position - u.position
		# Close range, any angle (turning in a yard): points ahead of the bumper against the
		# other vehicle's collision circles.
		if off.length() < 24.0:
			var od := o.veh.def()
			var ofwd := Vector3(-sin(o.yaw), 0.0, -cos(o.yaw))
			for s in [2.0, 4.5, 8.0, 12.0]:
				var q: Vector3 = u.position + fwd * (d.length * 0.5 + float(s))
				var hit := false
				for oz in od.circle_z:
					var oc := o.position + ofwd * oz
					if Vector2(q.x - oc.x, q.z - oc.z).length() < d.collide_r + od.collide_r + 0.4:
						hit = true
						break
				if hit:
					gap = minf(gap, float(s))
					break
		var ahead := off.dot(fwd)
		if ahead <= 0.0 or ahead > look + d.length:
			continue
		if absf(off.dot(right)) > (d.width + o.veh.def().width) * 0.5 + 0.3:
			continue
		var g := ahead - d.length * 0.5 - o.veh.def().length * 0.5
		gap = minf(gap, maxf(g, 0.0))
	_gap[u.id] = [ticks, gap]
	return gap


func _check_stuck(u: UnitState, v: VehicleState, d: VehicleDefs.Def, target_speed: float, dt: float) -> void:
	# Only counts while the vehicle is supposed to be moving and nothing legitimate holds it
	# (a vehicle waiting behind another is not stuck; a long wait still ends in a report).
	if target_speed < 0.8 and v.status != VehicleState.Status.WAITING:
		v._progress_t = 0.0
		v._progress_ref = u.position
		return
	v._progress_t += dt
	if Vector2(u.position.x - v._progress_ref.x, u.position.z - v._progress_ref.z).length() > 1.5:
		v._progress_ref = u.position
		v._progress_t = 0.0
		if v.recoveries > 0 and v.odometer - v.stuck_s > 40.0:
			v.recoveries = 0
		return
	var limit := STUCK_S if v.status != VehicleState.Status.WAITING else STUCK_S * 6.0
	if v._progress_t < limit:
		return
	v._progress_t = 0.0
	v._progress_ref = u.position
	# Held up so close to the goal by a vehicle that has already stopped there (a column that
	# lost its order): count it as arrived instead of reporting a failure.
	if v.route_remaining_m() < 45.0 and v.recoveries >= 1:
		_arrive(u, v)
		_event(u, "stopped behind another vehicle near the destination")
		return
	v.recoveries += 1
	v.stuck_s = v.odometer
	if v.recoveries <= 2:
		v.reverse_left = 3.5
		v.reason = "Stuck: reversing"
		stats.recovered += 1
		_event(u, "stuck, reversing")
	elif v.recoveries <= MAX_RECOVERIES and v.replans < 2:
		v.replans += 1
		stats.replanned += 1
		var target := u.order_target
		var res := router.plan(u.position, target, d)
		if res.ok:
			_apply_route(u, res)
			v.reason = "Stuck: route planned again"
			_event(u, "stuck, new route")
		else:
			_fail(u, "Path blocked: " + res.reason)
	else:
		_fail(u, "Path blocked: could not get free")


func _fail(u: UnitState, reason: String) -> void:
	var v := u.veh
	_clear_order(u, VehicleState.Status.BLOCKED)
	u.move_state = UnitState.MoveState.BLOCKED
	v.reason = reason
	v.speed = 0.0
	stats.failed += 1
	_event(u, reason)
	sim.state.order_changed.emit(u)


func _event(u: UnitState, text: String) -> void:
	if sim.war:
		sim.war.log_event(u.faction, "vehicle", "%s: %s" % [u.unit_name, text])


## What holds a vehicle up right now (tests and debugging): the first route point ahead that
## lies in a structure and the vehicles within the lane ahead.
func diagnose(u: UnitState) -> Dictionary:
	var v := u.veh
	var d := v.def()
	var out := {"pos": [snappedf(u.position.x, 0.1), snappedf(u.position.z, 0.1)], "route_i": v.route_i, "route": v.route.size(),
		"status": v.status_name(), "reason": v.reason, "speed": snappedf(v.speed, 0.01), "probe": snappedf(v.probe_ahead, 0.1),
		"recoveries": v.recoveries, "replans": v.replans, "reverse_left": snappedf(v.reverse_left, 0.1)}
	if sim.structures:
		for k in range(v.route_i, mini(v.route_i + 30, v.route.size())):
			var p := v.route[k]
			if sim.structures.blocks_point(Vector2(p.x, p.z), d.collide_r):
				out["blocked_route_point"] = [k, snappedf(p.x, 0.1), snappedf(p.z, 0.1), snappedf(Vector2(p.x - u.position.x, p.z - u.position.z).length(), 0.1)]
				break
		out["in_structure_now"] = _blocked_at(d, u.position, u.yaw)
	var near := []
	for oid in ids:
		if oid != u.id:
			var o: UnitState = sim.state.units.get(oid)
			if o and Vector2(o.position.x - u.position.x, o.position.z - u.position.z).length() < 40.0:
				near.append([oid, snappedf(o.position.x, 0.1), snappedf(o.position.z, 0.1), o.veh.status_name()])
	out["vehicles_near"] = near
	return out


## One-line status for the HUD and the map.
func describe(u: UnitState) -> String:
	var v := u.veh
	if v == null:
		return ""
	var d := v.def()
	var s := "%s  %s" % [d.display_name, v.status_name()]
	if not v.occupants.is_empty() or v.phase != VehicleState.Phase.NONE:
		s += "  [" + transport.describe(u) + "]"
	if not v.cargo.is_empty():
		s += "  cargo: %s (%d/%d)" % [v.cargo.summary(), roundi(v.cargo.total()), roundi(v.cargo.capacity)]
	if not v.job.is_empty():
		s += "  · " + sim.logistics.describe_job(u)
	if v.status == VehicleState.Status.DRIVING or v.status == VehicleState.Status.PLAYER:
		s += "  %d km/h" % roundi(absf(v.speed) * 3.6)
	if u.order == UnitState.Order.MOVE and not v.route.is_empty():
		s += "  %.1f km to go" % (v.route_remaining_m() / 1000.0)
	s += "  fuel %d/%d l" % [roundi(v.fuel), roundi(d.fuel_capacity)]
	if v.reason != "":
		s += "  - " + v.reason
	return s

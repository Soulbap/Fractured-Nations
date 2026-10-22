## Mechanized deployment of AI operations (AI-WAR-LOGISTICS-01), owned by WarSim.
##
## Not a second movement system: this only *orders* what already exists - VehicleSim.order_drive / VehicleConvoy for
## driving (VehicleRouter plans the routes), VehicleTransport for boarding and unloading (seats, capacity, the
## soldiers' own records), SquadControl for the walk before and after - and watches the result. The operation
## (OperationState) stays the owner: it holds the vehicles (`op.vehicles`, `op.transport`) and the squads stay in it
## while aboard (the G7 definition of the roadmap); a vehicle's `assign_kind` / `assign_id` says the same from the
## vehicle's side so no vehicle serves two operations. After the unloading the existing infantry tactics take over
## (OpCoordination APPROACH -> DEPLOY -> ...): there is no mechanized infantry combat controller.
##
## Stages (OperationState.Stage, before APPROACH), each with entry, completion, failure and a fallback:
##   ASSEMBLE   vehicles drive to the assembly point, the squads walk there.   done: every vehicle there and its squads
##              near (or ASSEMBLE_TIMEOUT_S: the ones that are there go, the rest walk).   failure: a vehicle destroyed /
##              immobilised / out of fuel / taken by the player / no route -> its squads walk the whole way.
##   MOUNT      VehicleTransport.order_transport per vehicle and squad.   done: boarding finished (BOARD_TIMEOUT_S is
##              the transport code's own).   failure: nobody boarded / no room -> those squads walk.
##   TRANSIT    one convoy (two or more vehicles, more than 600 m) or single drive to the unloading point.   done:
##              VehicleTransport unloads on arrival.   failure: blocked, no fuel, destroyed, overdue -> unload where it
##              stands and the squads walk the rest.
##   DISEMBARK  everybody is off.   -> the squads get their ordinary march route (WarSim._send) and the stage becomes
##              APPROACH; the vehicles drive back to a base (assign "return") and are free again on arrival.
## The unloading point is the staging point short of the objective (or the objective's edge for a reinforcement),
## moved back along the way in while enemies are believed there, and onto a road when one is near - unarmed
## transport does not drive into a defended objective.
class_name OpTransport
extends RefCounted

const ASSEMBLE_TIMEOUT_S := 240.0
const MOUNT_TIMEOUT_S := 150.0
const DISEMBARK_TIMEOUT_S := 45.0
## Assembly: a vehicle this close to its slot, and squads this close to the assembly point, count as there.
const SLOT_REACH_M := 30.0
## Seconds between the departures of the vehicles of one operation from their yard.
const DEPART_GAP_S := 9.0
const SQUADS_NEAR_M := 110.0
## Straight-line distance x this is the planning estimate of a drive (fuel, expected time).
const DETOUR := 1.4
## Distance from where vehicles are to the assembly point beyond which a vehicle is not considered.
const MAX_FETCH_M := 3500.0

## vehicle id -> time before which it is not offered for transport again (it got stuck on the way).
var _bad := {}
var ws: WarSim
var sim: WorldSim
var vsim: VehicleSim
var vt: VehicleTransport
var stats := {"planned": 0, "mounted": 0, "foot": 0, "fallbacks": 0, "released": 0, "vehicles_used": 0, "convoys": 0, "arrived": 0, "returned": 0}
var usec := 0
var usec_max := 0
var updates := 0


func _init(p_ws: WarSim) -> void:
	ws = p_ws
	sim = p_ws.sim
	vsim = sim.vehicles
	vt = vsim.transport


# --- Planning -----------------------------------------------------------------------------------------------------

## Called by WarSim.start_operation once the operation has its squads and its staging point: decides whether the
## march is made by vehicle and, if so, starts ASSEMBLE. Returns the squad ids that go by vehicle (the others walk,
## see WarSim.start_operation). `op.transport` always says what was decided and why.
func plan(op: OperationState) -> Array:
	stats.planned += 1
	op.transport = {"mode": "foot", "why": "", "assembly": Vector3.INF, "unload": Vector3.INF, "tasks": {}, "carried": [], "since": sim.state.time, "expected_s": 0.0, "log": []}
	var why := _ineligible(op)
	if why != "":
		return _foot(op, why)
	var sqs: Array = []
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq and not sq.members.is_empty() and sq.tactic_owner != SquadState.Owner.PLAYER:
			sqs.append(sq)
	var from := _centroid(sqs)
	var goal := op.staging_pos if op.type == OperationState.Type.ATTACK and op.staging_pos.is_finite() else op.target_pos
	var p := ws.profile(ws.war.faction(op.faction))
	var dist := WarSim._flat(from, goal)
	if dist < p.mech_min_m:
		return _foot(op, "the march is %d m, transport is used from %d m" % [roundi(dist), roundi(p.mech_min_m)])
	var tq := Time.get_ticks_usec()
	var assembly := _assembly_point(sqs, from, goal, op.faction)
	ws.strat._note_us("mech_assembly", tq)
	tq = Time.get_ticks_usec()
	var unload := _unload_point(op, assembly, goal)
	ws.strat._note_us("mech_unload", tq)
	tq = Time.get_ticks_usec()
	var cands := candidates(op.faction, assembly, unload)
	ws.strat._note_us("mech_candidates", tq)
	if cands.is_empty():
		return _foot(op, "no free transport vehicle (%s)" % _why_none(op.faction))
	# First fit: squads (largest first) into the nearest vehicles with seats; squads that do not fit walk.
	var order: Array = sqs.duplicate()
	order.sort_custom(func(a: SquadState, b: SquadState) -> bool: return a.members.size() > b.members.size())
	var tasks := {}
	var free := {}
	for c: Dictionary in cands:
		free[c.id] = c.seats
	var carried: Array = []
	var left_out: Array[String] = []
	for sq: SquadState in order:
		var n := sq.members.size()
		var placed := false
		for c: Dictionary in cands:
			if int(free[c.id]) >= n:
				if not tasks.has(c.id):
					tasks[c.id] = {"squads": [], "home": c.home, "state": "to_assembly", "note": "", "slot": Vector3.INF}
				tasks[c.id].squads.append(sq.id)
				free[c.id] = int(free[c.id]) - n
				carried.append(sq.id)
				placed = true
				break
		if not placed:
			left_out.append(sq.squad_name)
	if tasks.is_empty():
		return _foot(op, "no vehicle has %d free seats" % order[0].members.size())
	# The way from the assembly point to the unloading point must exist (one plan; every vehicle plans its own way to its
	# slot when it is ordered there, and a vehicle that cannot is dropped then, with the squads walking).
	var pu := sim.state.get_unit(tasks.keys()[0])
	# The vehicle route assembly -> unloading point is checked one second into ASSEMBLE (one route plan per tick, never
	# several inside the strategic decision that starts the operation); the planning estimate is the straight line.
	var r1 := {"length_m": WarSim._flat(pu.position, assembly) * DETOUR}
	var r2 := {"length_m": WarSim._flat(assembly, unload) * DETOUR}
	op.transport.mode = "mech"
	op.transport.assembly = assembly
	op.transport.unload = unload
	op.transport.tasks = tasks
	op.transport.carried = carried
	op.transport.expected_s = (float(r1.length_m) + float(r2.length_m)) / 7.0
	# The vehicle farthest from the assembly point needs about its distance at 5 m/s, plus the staggered departures.
	var far_m := 0.0
	for vid: int in tasks:
		far_m = maxf(far_m, WarSim._flat(sim.state.get_unit(vid).position, assembly))
	op.transport["assemble_limit"] = clampf(far_m * DETOUR / 5.0 + 120.0 + DEPART_GAP_S * tasks.size(), 150.0, 600.0)
	op.transport.why = "%d of %d squads by %d vehicle(s): march %d m, vehicle route %.1f km" % [carried.size(), sqs.size(), tasks.size(), roundi(dist), (float(r1.length_m) + float(r2.length_m)) / 1000.0]
	if not left_out.is_empty():
		op.transport.why += "; no seats for " + ", ".join(left_out) + " (they walk)"
	var vids := PackedInt32Array()
	var k := 0
	tq = Time.get_ticks_usec()
	for vid: int in tasks:
		var u := sim.state.get_unit(vid)
		u.veh.assign_kind = "op"
		u.veh.assign_id = op.id
		vids.append(vid)
		# Each vehicle waits in its own slot beside the assembly point.
		var slot := _slot(assembly, from, k, tasks.size())
		tasks[vid]["slot"] = slot
		if k == 0:
			var res := vsim.order_drive(vid, slot, true)
			if not res.ok:
				tasks[vid]["state"] = "lost"
				tasks[vid]["note"] = "cannot drive to the assembly point: %s" % res.reason
		else:
			# Vehicles leave a crowded yard one after the other (the second would otherwise block the first in the depot).
			tasks[vid]["state"] = "queued"
			tasks[vid]["depart_at"] = sim.state.time + DEPART_GAP_S * k
		k += 1
	op.vehicles = vids
	ws.strat._note_us("mech_orders", tq)
	tq = Time.get_ticks_usec()
	for sid in carried:
		var sq := sim.state.get_squad(sid)
		ws.sim.squads.order_move([sid], assembly)
		sq.op_role = SquadState.OpRole.NONE
	ws.strat._note_us("mech_squad_orders", tq)
	stats.mounted += 1
	stats.vehicles_used += tasks.size()
	_set_stage(op, OperationState.Stage.ASSEMBLE, "assembling at (%.0f, %.0f): %s" % [assembly.x, assembly.z, op.transport.why])
	ws.log_event(op.faction, "op_transport", "%s #%d: %s" % [op.type_name(), op.id, op.transport.why], assembly)
	return carried


func _foot(op: OperationState, why: String) -> Array:
	op.transport["mode"] = "foot"
	op.transport["why"] = why
	stats.foot += 1
	return []


func _ineligible(op: OperationState) -> String:
	if op.player_ordered:
		return "the player's operation (the AI does not move his squads by vehicle)"
	var f := ws.war.faction(op.faction)
	if f == null or f.player:
		return "the player's faction"
	if op.type == OperationState.Type.MOVE:
		return "a move order"
	if not sim.logistics.vsim.router or not ws.routes or not ws.routes.ready:
		return "no route network"
	return ""


## Why no vehicle qualified (for the inspector): counts of the reasons over the faction's vehicles.
func _why_none(faction: int) -> String:
	var counts := {}
	for id in vsim.ids:
		var u: UnitState = sim.state.units.get(id)
		if u == null or u.faction != faction:
			continue
		var why := _refuse(u, Vector3.INF, Vector3.INF)
		if why != "":
			counts[why] = int(counts.get(why, 0)) + 1
	if counts.is_empty():
		return "the faction owns no vehicle"
	var parts: Array[String] = []
	for k in counts:
		parts.append("%d %s" % [counts[k], k])
	return ", ".join(parts)


## Vehicles of the faction that may carry squads now: not assigned, not driven by the player, not disabled, in
## order, with fuel for the trip and back. Sorted by distance to `assembly`. [{id, seats, home, fuel_ok}]
func candidates(faction: int, assembly: Vector3, unload: Vector3) -> Array:
	var out: Array = []
	for id in vsim.ids:
		var u: UnitState = sim.state.units.get(id)
		if u == null or u.faction != faction:
			continue
		if _refuse(u, assembly, unload) != "":
			continue
		var d := WarSim._flat(u.position, assembly)
		if d > MAX_FETCH_M:
			continue
		out.append({"id": id, "seats": u.veh.def().passengers, "home": _home_of(u), "d": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return out


## "" when the vehicle may be used, else the reason it may not.
func _refuse(u: UnitState, assembly: Vector3, unload: Vector3) -> String:
	var v := u.veh
	if not u.alive or v.status == VehicleState.Status.DISABLED:
		return "destroyed"
	if float(_bad.get(u.id, 0.0)) > sim.state.time:
		return "got stuck recently"
	if u.player_controlled or v.status == VehicleState.Status.PLAYER:
		return "driven by the player"
	# A vehicle driving home from an earlier task may be given a new one on the way (its drive home is replaced).
	var returning := v.assign_kind == "return"
	if v.assign_kind != "" and not returning:
		return "already assigned (%s)" % v.assign_kind
	if v.status == VehicleState.Status.NO_FUEL:
		return "immobilised (%s)" % v.status_name()
	if not v.job.is_empty() or v.convoy_id >= 0 or v.phase != VehicleState.Phase.NONE or (u.order != UnitState.Order.NONE and not returning):
		return "busy"
	if not v.occupants.is_empty() or not v.pending.is_empty():
		return "carrying passengers"
	if u.health < u.max_health * 0.4:
		return "badly damaged"
	if assembly.is_finite() and unload.is_finite():
		var d := v.def()
		var trip := (WarSim._flat(u.position, assembly) + WarSim._flat(assembly, unload) * 2.0) * DETOUR / 1000.0
		if v.fuel < trip * d.fuel_per_km * 1.15:
			return "short of fuel (%d l for a %.1f km trip)" % [roundi(v.fuel), trip]
	return ""


## Where a vehicle goes back to: the parking spot of the nearest vehicle depot of its faction, else its own position.
func _home_of(u: UnitState) -> Vector3:
	var s := sim.logistics.nearest_store(u.position, u.faction, &"", &"vehicle")
	if s == null:
		return u.position
	# One parking spot per vehicle (by its id), so the vehicles of a convoy do not all drive to the same place.
	return sim.logistics.parking_world(s, u.id % 6)


## Where the squads and the vehicles meet: the centre of the squads, moved onto a road within 150 m when there is one
## (the trucks park on it, in line, instead of in the trees), else the biggest squad's own spot when the centre is impassable.
func _assembly_point(sqs: Array, from: Vector3, goal: Vector3, faction: int) -> Vector3:
	var p := from
	# Squads standing inside a base (fresh recruits, a garrison of the HQ) do not assemble among its buildings: the vehicles
	# would have to turn round in the yard. The point is moved out of the compound, towards the objective.
	for b: Dictionary in sim.logistics.bases.bases_of(faction):
		if WarSim._flat(b.anchor, from) < 130.0:
			var dir := Vector3(goal.x - b.anchor.x, 0.0, goal.z - b.anchor.z).normalized()
			# Prefer a spot on a road (vehicles drive well on roads; the cross-country planner knows no trees).
			var found := false
			for dist: float in [150.0, 190.0, 120.0, 230.0, 300.0]:
				for ang: float in [0.0, 0.5, -0.5, 1.0, -1.0]:
					var q := ws._ground(b.anchor + dir.rotated(Vector3.UP, ang) * dist)
					var rd := sim.state.roads.nearest(q, 120.0, 0, 0.0)
					if not rd.is_empty() and (ws.routes == null or not ws.routes.ready or ws.routes.passable(rd.pos)):
						p = ws._ground(rd.pos)
						found = true
						break
				if found:
					break
			break
	if ws.routes and ws.routes.ready and not ws.routes.passable(p):
		sqs.sort_custom(func(a: SquadState, b: SquadState) -> bool: return a.members.size() > b.members.size())
		p = ws.squad_center(sqs[0])
	var road := sim.state.roads.nearest(p, 150.0, 0, 0.0)
	_road_dir = Vector3.INF
	if not road.is_empty():
		var rp: Vector3 = road.pos
		if ws.routes == null or not ws.routes.ready or ws.routes.passable(rp):
			p = rp
			_road_dir = Vector3(road.dir.x, 0.0, road.dir.y)
	return ws._ground(p)


var _road_dir := Vector3.INF


## Slot k of n for a waiting vehicle: along the road (or spread sideways) 22 m apart, on ground a vehicle may stand on.
func _slot(assembly: Vector3, from: Vector3, k: int, n: int) -> Vector3:
	var dir := _road_dir if _road_dir.is_finite() else Vector3(1.0, 0.0, 0.0)
	var off := 22.0 * (float(k) - float(n - 1) * 0.5)
	var side := Vector3(-dir.z, 0.0, dir.x)
	for attempt in 6:
		var shift := side * (attempt / 2 + 1) * 8.0 * (1.0 if attempt % 2 == 0 else -1.0) if attempt > 0 else Vector3.ZERO
		var p := ws._ground(assembly + dir * off + shift)
		if vsim.spot_valid(p) and (ws.routes == null or not ws.routes.ready or ws.routes.passable(p)):
			return p
	return ws._ground(assembly + dir * off)


## The point the vehicles unload at: the staging point (an attack) or the objective's edge (a reinforcement), moved
## back towards where the force starts while enemies are believed within 280 m of it, and onto a road within 120 m
## when one is there (and the point stays at least 250 m from an enemy objective).
func _unload_point(op: OperationState, from: Vector3, goal: Vector3) -> Vector3:
	var p := goal
	var obj := ws.war.objective(op.target_objective)
	if op.type != OperationState.Type.ATTACK and obj:
		var back := Vector3(from.x - obj.position.x, 0.0, from.z - obj.position.z).normalized()
		p = obj.position + back * obj.radius * 0.7
	var dir := Vector3(from.x - p.x, 0.0, from.z - p.z)
	var len := dir.length()
	dir = dir / maxf(len, 0.001)
	for i in 4:
		if ws.threat_near(op.faction, p, 280.0) <= 0:
			break
		if len < 200.0:
			break
		p += dir * minf(120.0, len * 0.4)
		len = WarSim._flat(from, p)
	var road := sim.state.roads.nearest(p, 120.0, 0, 0.0)
	if not road.is_empty():
		var rp: Vector3 = road.pos
		if obj == null or op.type != OperationState.Type.ATTACK or WarSim._flat(rp, obj.position) >= 250.0:
			p = rp
	return ws._ground(p)


# --- The per-second update ----------------------------------------------------------------------------------------------

## Called by WarSim for every active operation each second, and for the vehicles returning from one.
func update(op: OperationState) -> void:
	var t0 := Time.get_ticks_usec()
	updates += 1
	var tr := op.transport
	if tr.is_empty() or tr.get("mode", "foot") != "mech":
		return
	_watch_vehicles(op)
	if op.is_transport_stage():
		match op.stage:
			OperationState.Stage.ASSEMBLE:
				_update_assemble(op)
			OperationState.Stage.MOUNT:
				_update_mount(op)
			OperationState.Stage.TRANSIT:
				_update_transit(op)
			OperationState.Stage.DISEMBARK:
				_update_disembark(op)
	var d := Time.get_ticks_usec() - t0
	usec += d
	usec_max = maxi(usec_max, d)


## Vehicles that were destroyed, taken by the player or reassigned are dropped from the plan at once.
func _watch_vehicles(op: OperationState) -> void:
	var tasks: Dictionary = op.transport.tasks
	for vid: int in tasks.keys():
		var t: Dictionary = tasks[vid]
		if t.state == "lost" or t.state == "done" or t.state == "returning":
			continue
		var u := sim.state.get_unit(vid)
		if u == null or u.veh == null:
			_lose(op, vid, "the vehicle no longer exists")
		elif not u.alive or u.veh.status == VehicleState.Status.DISABLED:
			_lose(op, vid, "%s was destroyed" % u.unit_name)
		elif u.player_controlled or u.veh.status == VehicleState.Status.PLAYER:
			_lose(op, vid, "the player took %s" % u.unit_name)
		elif u.veh.assign_kind != "op" or u.veh.assign_id != op.id:
			_lose(op, vid, "%s was reassigned" % u.unit_name)


## A vehicle leaves the plan. Its squads walk (those not aboard) or are released (aboard a vehicle the player drives).
func _lose(op: OperationState, vid: int, why: String) -> void:
	var tasks: Dictionary = op.transport.tasks
	var t: Dictionary = tasks.get(vid, {})
	if t.is_empty() or t.state == "lost":
		return
	var was: String = t.state
	if why.contains("Path blocked") or why.contains("stopped on the way") or why.contains("did not arrive"):
		_bad[vid] = sim.state.time + 900.0
	t["state"] = "lost"
	t["note"] = why
	stats.fallbacks += 1
	op.transport.log.append("%.0f %s" % [sim.state.time, why])
	var u := sim.state.get_unit(vid)
	if u and u.veh and u.alive:
		t["diag"] = vsim.diagnose(u)  # what held it up, for the inspector and the tests
		var near_s := []
		for st: StructureState in sim.state.construction.all():
			if not st.is_line() and Vector2(st.position.x - u.position.x, st.position.z - u.position.z).length() < 40.0:
				near_s.append("%s %.0f m yaw %.2f" % [st.type_id, Vector2(st.position.x - u.position.x, st.position.z - u.position.z).length(), st.yaw])
		t["diag"]["structures_near"] = near_s
	var player_took := u != null and u.player_controlled
	if u and u.veh and u.veh.assign_kind == "op" and u.veh.assign_id == op.id:
		u.veh.assign_kind = ""
		u.veh.assign_id = -1
	var i := op.vehicles.find(vid)
	if i >= 0:
		op.vehicles.remove_at(i)
	if u and u.veh and not player_took:
		if u.alive and not u.veh.occupants.is_empty():
			vt.unload(vid)  # passengers get off where the vehicle stands
		elif u.veh.phase != VehicleState.Phase.NONE:
			vt.cancel(vid)
		if u.alive and u.veh.convoy_id >= 0:
			vsim.convoy.leave(vid)
	for sid in t.get("squads", []):
		var sq := sim.state.get_squad(sid)
		if sq == null or sq.op_id != op.id:
			continue
		if player_took and _aboard(sq, vid) > 0:
			# The squad rides in a vehicle the player drives: it is the player's now.
			ws.release_squads([sid], "the player took the vehicle")
			continue
		_to_foot(op, sq, why, was)
	ws.log_event(op.faction, "op_transport", "%s #%d: %s - %s" % [op.type_name(), op.id, why, "its squads walk"], u.position if u else op.target_pos)


## A squad left the operation (a player order, a reassignment): it is no longer planned for transport; a vehicle that has
## no squad left to carry is let go (it goes home) unless it already carries somebody.
func squad_released(op: OperationState, sq: SquadState) -> void:
	var tr := op.transport
	if tr.get("mode", "foot") != "mech":
		return
	var carried: Array = tr.carried
	var i := carried.find(sq.id)
	if i >= 0:
		carried.remove_at(i)
	var late: Array = tr.get("late_foot", [])
	if late.has(sq.id):
		late.erase(sq.id)
	for vid: int in tr.tasks.keys():
		var t: Dictionary = tr.tasks[vid]
		var sl: Array = t.get("squads", [])
		if not sl.has(sq.id):
			continue
		sl.erase(sq.id)
		var u := sim.state.get_unit(vid)
		if sl.is_empty() and t.state != "lost" and t.state != "returning" and u and u.veh and u.veh.occupants.is_empty():
			if u.veh.phase != VehicleState.Phase.NONE:
				vt.cancel(vid)
			_lose(op, vid, "%s has no squad to carry any more (%s left the operation)" % [u.unit_name, sq.squad_name])


func _aboard(sq: SquadState, vid: int) -> int:
	var n := 0
	for id in sq.members:
		var s := sim.state.get_unit(id)
		if s and s.vehicle_id == vid:
			n += 1
	return n


## The squad continues on foot from where it is: its soldiers still aboard a (stopped) vehicle are set down first.
func _to_foot(op: OperationState, sq: SquadState, why: String, _was := "") -> void:
	var carried: Array = op.transport.carried
	var i := carried.find(sq.id)
	if i >= 0:
		carried.remove_at(i)
	var any_aboard := false
	for id in sq.members:
		var s := sim.state.get_unit(id)
		if s and s.vehicle_id >= 0:
			any_aboard = true
			var v := sim.state.get_unit(s.vehicle_id)
			if v and v.veh and v.veh.occupants.has(id) and v.veh.phase != VehicleState.Phase.UNLOADING:
				vt.unload(v.id)
	sq.op_role = SquadState.OpRole.NONE
	if any_aboard:
		# Walk when everybody is off (the stage monitors pick this up: squads without a route are sent).
		op.transport["late_foot"] = op.transport.get("late_foot", [])
		if not op.transport.late_foot.has(sq.id):
			op.transport.late_foot.append(sq.id)
		return
	ws._send(op, sq)


# --- ASSEMBLE -----------------------------------------------------------------------------------------------------------

func _update_assemble(op: OperationState) -> void:
	var tr := op.transport
	var now := sim.state.time
	var tasks: Dictionary = tr.tasks
	if not tr.get("route_checked", false) and now - op.stage_since >= 1.0:
		tr["route_checked"] = true
		var first := sim.state.get_unit(tasks.keys()[0])
		var chk := vsim.router.plan(tr.assembly, tr.unload, first.veh.def())
		if not chk.ok:
			_all_foot(op, "no vehicle route to the unloading point: %s" % chk.reason)
			return
		tr["expected_s"] = float(chk.length_m) / 7.0 * 2.0
	var waiting: Array[String] = []
	var live := 0
	for vid: int in tasks:
		var t: Dictionary = tasks[vid]
		if t.state == "lost":
			continue
		live += 1
		var u := sim.state.get_unit(vid)
		if t.state == "queued":
			if now >= float(t.depart_at):
				var res := vsim.order_drive(vid, t.slot, true)
				if res.ok:
					t["state"] = "to_assembly"
				else:
					_lose(op, vid, "%s cannot drive to the assembly point: %s" % [u.unit_name, res.reason])
					continue
		if t.state == "to_assembly":
			var at := WarSim._flat(u.position, t.slot) <= SLOT_REACH_M
			var halted := u.order == UnitState.Order.NONE and absf(u.veh.speed) < 0.6
			if at or (halted and WarSim._flat(u.position, tr.assembly) <= 80.0):
				t["state"] = "ready"
			elif halted and (u.veh.status == VehicleState.Status.BLOCKED or u.veh.status == VehicleState.Status.NO_FUEL):
				_lose(op, vid, "%s could not reach the assembly point (%s)" % [u.unit_name, u.veh.reason if u.veh.reason != "" else u.veh.status_name()])
				continue
			elif halted:
				# Stopped short of the slot (blocked by another vehicle): try the slot again, then the assembly point.
				var res := vsim.order_drive(vid, t.slot, true)
				if not res.ok:
					_lose(op, vid, "%s cannot reach the assembly point: %s" % [u.unit_name, res.reason])
					continue
		if t.state != "ready":
			waiting.append("%s %d m away%s" % [u.unit_name, roundi(WarSim._flat(u.position, t.slot)), " (waiting its turn)" if t.state == "queued" else ""])
	var sq_far: Array[String] = []
	for sid in tr.carried:
		var sq := sim.state.get_squad(sid)
		if sq and WarSim._flat(ws.squad_center(sq), tr.assembly) > SQUADS_NEAR_M:
			sq_far.append("%s %d m" % [sq.squad_name, roundi(WarSim._flat(ws.squad_center(sq), tr.assembly))])
			# A squad that stopped short (blocked, a reaction ended its move) is sent again.
			if sq.order != SquadState.Order.MOVE and sq.route.is_empty():
				ws.sim.squads.order_move([sid], tr.assembly)
	if live == 0:
		_all_foot(op, "no vehicle left to carry the squads")
		return
	op.wait_reason = "" if waiting.is_empty() and sq_far.is_empty() else "assembling: %s%s" % [", ".join(waiting), ("; squads " + ", ".join(sq_far)) if not sq_far.is_empty() else ""]
	var limit: float = float(tr.get("assemble_limit", ASSEMBLE_TIMEOUT_S))
	var timed_out := now - op.stage_since > limit
	if (waiting.is_empty() and sq_far.is_empty()) or timed_out:
		if timed_out:
			ws.coord.timeouts += 1
			for vid: int in tasks.keys():
				if tasks[vid].state == "to_assembly" or tasks[vid].state == "queued":
					_lose(op, vid, "%s did not arrive in %d s" % [sim.state.get_unit(vid).unit_name, int(limit)])
		_start_mount(op, "timeout: the vehicles that are there leave" if timed_out else "")


# --- MOUNT ------------------------------------------------------------------------------------------------------------------

func _start_mount(op: OperationState, note: String) -> void:
	var tr := op.transport
	var tasks: Dictionary = tr.tasks
	var boarding := 0
	for vid: int in tasks.keys():
		var t: Dictionary = tasks[vid]
		if t.state != "ready":
			continue
		var ok_squads: Array = []
		var expect := 0
		for sid in t.squads.duplicate():
			var sq := sim.state.get_squad(sid)
			if sq == null or sq.op_id != op.id or not tr.carried.has(sid):
				continue
			var res := vt.order_transport(vid, sid, Vector3.INF)
			if res.ok:
				expect += int(res.boarding)
				ok_squads.append(sid)
			else:
				_to_foot(op, sq, "%s: %s" % [sim.state.get_unit(vid).unit_name, res.reason])
		t["squads"] = ok_squads
		t["expect"] = expect
		t["state"] = "boarding" if not ok_squads.is_empty() else "done"
		boarding += expect
	if boarding == 0:
		_all_foot(op, "nobody could board")
		return
	_set_stage(op, OperationState.Stage.MOUNT, "boarding: %d soldiers into %d vehicle(s)%s" % [boarding, _live(op), (" (" + note + ")") if note != "" else ""])


func _update_mount(op: OperationState) -> void:
	var tr := op.transport
	var tasks: Dictionary = tr.tasks
	var waiting := 0
	for vid: int in tasks.keys():
		var t: Dictionary = tasks[vid]
		if t.state != "boarding":
			continue
		var u := sim.state.get_unit(vid)
		var v := u.veh
		# Boarding is over when the transport code has no phase and nobody is still walking to the door.
		if v.phase == VehicleState.Phase.NONE and v.pending.is_empty():
			if v.occupants.is_empty():
				_lose(op, vid, "%s: nobody boarded" % u.unit_name)
			else:
				t["state"] = "loaded"
				t["aboard"] = v.occupants.size()
		elif v.phase == VehicleState.Phase.APPROACH or v.phase == VehicleState.Phase.BOARDING:
			waiting += 1
	op.wait_reason = "" if waiting == 0 else "%d vehicle(s) still boarding (%d s)" % [waiting, int(sim.state.time - op.stage_since)]
	var timed_out := sim.state.time - op.stage_since > MOUNT_TIMEOUT_S
	if waiting == 0 or timed_out:
		if timed_out:
			ws.coord.timeouts += 1
			for vid: int in tasks.keys():
				if tasks[vid].state == "boarding":
					var u := sim.state.get_unit(vid)
					if u.veh.occupants.is_empty():
						_lose(op, vid, "%s: boarding took more than %d s" % [u.unit_name, int(MOUNT_TIMEOUT_S)])
					else:
						vt.depart(u, u.veh, Vector3.INF)
						tasks[vid]["state"] = "loaded"
		_start_transit(op)


# --- TRANSIT ----------------------------------------------------------------------------------------------------------------

func _start_transit(op: OperationState) -> void:
	var tr := op.transport
	var tasks: Dictionary = tr.tasks
	var ids: Array = []
	for vid: int in tasks.keys():
		if tasks[vid].state == "loaded":
			ids.append(vid)
	if ids.is_empty():
		_all_foot(op, "no vehicle was loaded")
		return
	var unload: Vector3 = tr.unload
	# Re-check the unloading point against what the faction believes now (it may have moved since the planning).
	var from: Vector3 = ws.squad_center(sim.state.get_squad(tr.carried[0])) if not tr.carried.is_empty() else tr.assembly
	unload = _unload_point(op, from, op.staging_pos if op.type == OperationState.Type.ATTACK and op.staging_pos.is_finite() else op.target_pos)
	tr["unload"] = unload
	var driving: Array = []
	var convoy_ok := false
	if ids.size() >= 2 and WarSim._flat(sim.state.get_unit(ids[0]).position, unload) > VehicleSim.CONVOY_MIN_M:
		var cr := vsim.convoy.order_convoy(ids, unload, "Op #%d convoy" % op.id)
		if cr.ok:
			convoy_ok = true
			driving = cr.driving.duplicate()
			stats.convoys += 1
			tr["convoy"] = cr.convoy
			for f: Dictionary in cr.failed:
				_lose(op, int(f.id), "%s: %s" % [sim.state.get_unit(int(f.id)).unit_name, f.reason])
	if not convoy_ok:
		for vid in ids:
			var res := vsim.order_drive(vid, unload, true)
			if res.ok:
				driving.append(vid)
			else:
				_lose(op, vid, "%s cannot drive to the unloading point: %s" % [sim.state.get_unit(vid).unit_name, res.reason])
	if driving.is_empty():
		_all_foot(op, "no vehicle could drive to the unloading point")
		return
	for vid in driving:
		var u := sim.state.get_unit(vid)
		u.veh.phase = VehicleState.Phase.TRANSIT
		u.veh.phase_since = sim.state.time
		u.veh.transport_dest = unload
		tasks[vid]["state"] = "driving"
		tasks[vid]["t0"] = sim.state.time
		tasks[vid]["odo0"] = u.veh.odometer
	tr["transit_since"] = sim.state.time
	var len_m := sim.state.get_unit(driving[0]).veh.route_remaining_m()
	tr["expected_s"] = len_m / 7.0
	_set_stage(op, OperationState.Stage.TRANSIT, "%d vehicle(s)%s to (%.0f, %.0f), %.1f km, about %d min" % [driving.size(), " in a convoy" if convoy_ok else "", unload.x, unload.z, len_m / 1000.0, ceili(len_m / 7.0 / 60.0)])


func _update_transit(op: OperationState) -> void:
	var tr := op.transport
	var tasks: Dictionary = tr.tasks
	var active := 0
	var overdue: bool = sim.state.time - float(tr.get("transit_since", sim.state.time)) > float(tr.expected_s) * 2.2 + 150.0
	for vid: int in tasks.keys():
		var t: Dictionary = tasks[vid]
		if t.state != "driving" and t.state != "unloading":
			continue
		var u := sim.state.get_unit(vid)
		var v := u.veh
		if v.occupants.is_empty() and v.phase == VehicleState.Phase.NONE:
			t["state"] = "unloaded"
			stats.arrived += 1
			continue
		if v.phase == VehicleState.Phase.UNLOADING:
			t["state"] = "unloading"
			active += 1
			continue
		if v.phase == VehicleState.Phase.NONE and not v.occupants.is_empty():
			# The transport code gave up the journey (blocked, out of fuel): passengers get off here and walk.
			_lose(op, vid, "%s stopped on the way (%s)" % [u.unit_name, v.reason if v.reason != "" else v.status_name()])
			continue
		if overdue:
			_lose(op, vid, "%s is overdue (%d s of %d expected)" % [u.unit_name, int(sim.state.time - float(tr.transit_since)), int(tr.expected_s)])
			continue
		active += 1
	var dist_left := 0.0
	for vid: int in tasks:
		if tasks[vid].state == "driving":
			dist_left = maxf(dist_left, sim.state.get_unit(vid).veh.route_remaining_m())
	op.wait_reason = "" if active == 0 else "in transit, %.1f km to the unloading point" % (dist_left / 1000.0)
	if active == 0:
		_set_stage(op, OperationState.Stage.DISEMBARK, "the vehicles have reached the unloading point")


# --- DISEMBARK ---------------------------------------------------------------------------------------------------------------

func _update_disembark(op: OperationState) -> void:
	var tr := op.transport
	var tasks: Dictionary = tr.tasks
	var aboard := 0
	for vid: int in tasks:
		var u := sim.state.get_unit(vid)
		if u and u.veh and u.alive and not u.veh.occupants.is_empty():
			aboard += 1
			if u.veh.phase == VehicleState.Phase.NONE:
				vt.unload(vid)
	op.wait_reason = "" if aboard == 0 else "%d vehicle(s) still unloading" % aboard
	if aboard == 0 or sim.state.time - op.stage_since > DISEMBARK_TIMEOUT_S:
		_finish(op)


## Everyone is off: the squads march on (OpCoordination's APPROACH takes over from the staging point), the vehicles go home.
func _finish(op: OperationState) -> void:
	var tr := op.transport
	var n := 0
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq == null or sq.op_id != op.id:
			continue
		if sq.route.is_empty() and (tr.carried.has(sid) or tr.get("late_foot", []).has(sid)):
			ws._send(op, sq)
			n += 1
	tr["late_foot"] = []
	_return_vehicles(op)
	_set_stage(op, OperationState.Stage.APPROACH, "unloaded %d squad(s) at (%.0f, %.0f): the march to the staging point" % [n, tr.unload.x, tr.unload.z])
	op.wait_reason = ""
	ws.log_event(op.faction, "op_transport", "%s #%d: troops are on the ground at (%.0f, %.0f)" % [op.type_name(), op.id, tr.unload.x, tr.unload.z], tr.unload)


# --- Fallbacks and the end of an operation -------------------------------------------------------------------------------------

## No vehicle can do the job: every squad of the transport walks the whole way (the operation goes on as a foot march).
func _all_foot(op: OperationState, why: String) -> void:
	var tr := op.transport
	stats.fallbacks += 1
	tr.log.append("%.0f all on foot: %s" % [sim.state.time, why])
	for vid: int in tr.tasks.keys():
		if tr.tasks[vid].state != "lost":
			_lose(op, vid, why)
	for sid in tr.carried.duplicate():
		var sq := sim.state.get_squad(sid)
		if sq and sq.op_id == op.id:
			_to_foot(op, sq, why)
	tr["mode"] = "foot"
	tr["why"] = "foot after: " + why
	_set_stage(op, OperationState.Stage.APPROACH, "on foot (%s)" % why)
	op.wait_reason = ""
	ws.log_event(op.faction, "op_transport", "%s #%d: %s - the squads walk" % [op.type_name(), op.id, why], op.target_pos)


## The vehicles that finished are sent back to a base and become free there (see update_returns).
func _return_vehicles(op: OperationState) -> void:
	for vid: int in op.transport.tasks.keys():
		var t: Dictionary = op.transport.tasks[vid]
		if t.state == "lost" or t.state == "returning":
			continue
		var u := sim.state.get_unit(vid)
		if u == null or u.veh == null or not u.alive or u.player_controlled:
			continue
		u.veh.assign_kind = "return"
		u.veh.assign_id = op.id
		t["state"] = "returning"
		var home: Vector3 = t.get("home", u.position)
		var res := vsim.order_drive(vid, home, true)
		if not res.ok:
			# No way home: stay here and be free (the economy refuels / the next task sends it).
			u.veh.assign_kind = ""
			u.veh.assign_id = -1
			t["state"] = "done"
			t["note"] = "could not go home: %s" % res.reason
	op.vehicles = PackedInt32Array()


## Operation over: vehicles are released (those with passengers set them down where they stand) and returning ones go home.
func release_op(op: OperationState, why: String) -> void:
	var tr := op.transport
	if tr.is_empty() or tr.get("mode", "foot") != "mech":
		return
	stats.released += 1
	for vid: int in tr.tasks.keys():
		var t: Dictionary = tr.tasks[vid]
		var u := sim.state.get_unit(vid)
		if u == null or u.veh == null:
			continue
		if t.state == "returning":
			continue  # already on its way home, free on arrival
		if u.veh.assign_kind == "op" and u.veh.assign_id == op.id:
			if u.alive and not u.player_controlled:
				if not u.veh.occupants.is_empty():
					vt.unload(vid)
				elif u.veh.phase != VehicleState.Phase.NONE:
					vt.cancel(vid)
				vsim.convoy.leave(vid)
				u.veh.assign_kind = "return"
				u.veh.assign_id = op.id
				var home: Vector3 = t.get("home", u.position)
				if not vsim.order_drive(vid, home, true).ok:
					u.veh.assign_kind = ""
					u.veh.assign_id = -1
			else:
				u.veh.assign_kind = ""
				u.veh.assign_id = -1
		t["state"] = "released"
	op.vehicles = PackedInt32Array()
	op.transport.log.append("%.0f released: %s" % [sim.state.time, why])


## Vehicles going home are free again when they arrive (or when something made them unable to).
func update_returns() -> void:
	for id in vsim.ids:
		var u: UnitState = sim.state.units.get(id)
		if u == null or u.veh == null or u.veh.assign_kind != "return":
			continue
		var done := not u.alive or u.player_controlled
		if not done and u.order == UnitState.Order.NONE and absf(u.veh.speed) < 0.6:
			done = true  # arrived, or stopped for good (blocked): free either way
		if done:
			u.veh.assign_kind = ""
			u.veh.assign_id = -1
			if u.alive and u.veh.status == VehicleState.Status.BLOCKED:
				u.veh.status = VehicleState.Status.PARKED  # stopped short of home: it stands there, it is not broken
				u.veh.reason = ""
			stats.returned += 1


func _live(op: OperationState) -> int:
	var n := 0
	for vid: int in op.transport.tasks:
		if op.transport.tasks[vid].state != "lost":
			n += 1
	return n


func _set_stage(op: OperationState, stage: int, why: String) -> void:
	if int(op.stage) != stage:
		ws.coord.stage_changes += 1
		op.stage = stage
		op.stage_since = sim.state.time
	op.stage_why = why
	ws.log_event(op.faction, "op_stage", "%s #%d: %s - %s" % [op.type_name(), op.id, op.stage_name(), why], op.target_pos)


func _centroid(sqs: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for sq: SquadState in sqs:
		c += ws.squad_center(sq)
		n += 1
	return c / maxi(n, 1)


# --- Inspection ------------------------------------------------------------------------------------------------------------------------

## Lines for the operation inspector: the decision, the stage, each vehicle's task and state.
func explain(op: OperationState) -> Array[String]:
	var out: Array[String] = []
	var tr := op.transport
	if tr.is_empty():
		return out
	out.append("Transport: %s - %s" % [tr.get("mode", "foot"), tr.get("why", "")])
	if tr.get("mode", "foot") != "mech":
		return out
	out.append("  assembly (%.0f, %.0f), unloading point (%.0f, %.0f)" % [tr.assembly.x, tr.assembly.z, tr.unload.x, tr.unload.z])
	for vid: int in tr.tasks:
		var t: Dictionary = tr.tasks[vid]
		var u := sim.state.get_unit(vid)
		var names: Array[String] = []
		for sid in t.get("squads", []):
			var sq := sim.state.get_squad(sid)
			names.append(sq.squad_name if sq else "#%d" % sid)
		out.append("  %s [%s] %s%s%s" % [u.unit_name if u else "#%d" % vid, t.state, ", ".join(names), (" - " + t.note) if t.get("note", "") != "" else "",
			(" - " + vt.describe(u)) if u and u.veh and u.alive else ""])
	for l: String in tr.log.slice(-3):
		out.append("  log: " + l)
	return out


func summary() -> Dictionary:
	return {"stats": stats.duplicate(), "us_avg": snappedf(float(usec) / maxi(updates, 1), 0.1), "us_max": usec_max}

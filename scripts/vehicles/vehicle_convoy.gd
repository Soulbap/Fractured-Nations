## Convoys (LOGISTICS-01): vehicles that travel together to one destination.
##
## No convoy command hierarchy: every member has its ordinary Move order and route (planned by
## the same router, so all follow the same roads), and the convoy only adds three things -
## the members stop in a column at the destination (each one a fixed spacing behind the one in
## front), a follower never outruns the vehicle ahead of it (speed matched inside a headway),
## and the lead vehicle slows down and finally waits when the rear of the column falls behind.
## Taking over one truck, redirecting or stopping any member leaves the others coherent: a
## member whose order is replaced simply leaves the convoy.
class_name VehicleConvoy
extends RefCounted

## Spacing of the stopped column at the destination (m, a multiple of the route's 3 m step).
const SPACING_M := 18.0
## Inside this gap (m) to the vehicle ahead, a follower matches that vehicle's speed.
const HEADWAY_M := 55.0
## The leader slows when a member is this far behind it, and stops at twice that.
const FALL_BEHIND_M := 150.0
## It waits at most this long (sim seconds) for a straggler, which then leaves the convoy.
const WAIT_LIMIT_S := 60.0
## A follower leaves its parking place only once the vehicle ahead has driven this far (m),
## so a column forming in a crowded yard does not cross itself; never longer than START_WAIT_S.
const DEPART_GAP_M := 16.0
const START_WAIT_S := 30.0

var sim: WorldSim
var vsim: VehicleSim
var _timer := 0.0


func _init(p_vsim: VehicleSim) -> void:
	vsim = p_vsim
	sim = p_vsim.sim


func _state() -> LogisticsState:
	return sim.state.logistics


## Orders the vehicles (column order as given: the first leads) to `dest`. Returns
## {ok, reason, convoy, driving, failed: [{id, reason}]}.
func order_convoy(ids: Array, dest: Vector3, name := "") -> Dictionary:
	var members: Array = []
	for id in ids:
		var u := sim.state.get_unit(id)
		if u and u.veh and u.alive:
			members.append(id)
	if members.size() < 2:
		return {"ok": false, "reason": "A convoy needs at least two vehicles"}
	for id in members:
		leave(id)
		var u := sim.state.get_unit(id)
		if not u.veh.job.is_empty():
			sim.logistics.cancel_job(id, "replaced by a convoy order")
	var lg := _state()
	var cid := lg.next_convoy_id
	lg.next_convoy_id += 1
	var cname := name if name != "" else "Convoy %d" % cid
	# NAV-PERF-01B: the leader's route is asked for first (RouteService); the others are sent when it comes, to their stopping
	# places in column behind its end (_on_leader_route). Until then the convoy is "forming": its vehicles hold.
	lg.convoys[cid] = {"members": members.duplicate(), "dest": dest, "leader": members[0], "name": cname, "odo0": {}, "start": sim.state.time, "forming": true}
	for id in members:
		sim.state.get_unit(id).veh.convoy_id = cid
	if not _send_leader(cid):
		return {"ok": false, "reason": "Convoy not formed: no vehicle can be ordered", "failed": []}
	return {"ok": true, "pending": true, "reason": "", "convoy": cid, "driving": members.duplicate(), "failed": []}


## Orders the convoy's first vehicle to the destination; false (and the convoy dissolved) when no member can be ordered.
func _send_leader(cid: int) -> bool:
	var c: Dictionary = _state().convoys.get(cid, {})
	while c.members.size() >= 2:
		var lead: int = c.members[0]
		c.leader = lead
		var res := vsim.request_drive(lead, c.dest, true, RouteService.Priority.CONVOY, _on_leader_route.bind(cid))
		if res.ok:
			return true
		_drop_member(cid, lead)
	# One vehicle left: no convoy, it drives alone.
	if c.members.size() == 1:
		var last: int = c.members[0]
		_dissolve(cid)
		vsim.request_drive(last, c.dest, true, RouteService.Priority.CONVOY)
		return false
	_dissolve(cid)
	return false


## The leader's answer. No route: it leaves (reported blocked) and the next vehicle leads. A route: the others are sent to their
## stopping places in column behind its end; a stopping place that cannot be reached (a point of the leader's lane in a structure
## or on a bank) is replaced by the destination itself, the vehicle keeps its place by the convoy's speed limit.
func _on_leader_route(u: UnitState, res: Dictionary, cid: int) -> bool:
	var c: Dictionary = _state().convoys.get(cid, {})
	if c.is_empty() or not c.get("forming", false) or c.leader != u.id:
		return false
	if not res.ok:
		_drop_member(cid, u.id)
		if sim.war:
			sim.war.log_event(u.faction, "logistics", "%s: %s cannot lead (%s)" % [c.name, u.unit_name, res.reason])
		if not _send_leader(cid):
			_state().convoys.erase(cid)
		return false
	c.erase("forming")
	var lead_route := u.veh.route
	var odo := {u.id: u.veh.odometer}
	for k in range(1, c.members.size()):
		var m := sim.state.get_unit(c.members[k])
		var goal: Vector3 = c.dest
		if lead_route.size() > 2:
			var back := mini(roundi(float(k) * SPACING_M / 3.0), lead_route.size() - 2)
			goal = lead_route[lead_route.size() - 1 - back]
		odo[m.id] = m.veh.odometer
		vsim.request_drive(m.id, goal, true, RouteService.Priority.CONVOY, _on_member_route.bind(cid, goal))
	c["odo0"] = odo
	c["start"] = sim.state.time
	if sim.war:
		sim.war.log_event(u.faction, "logistics", "%s: %d vehicles, %.1f km" % [c.name, c.members.size(), u.veh.route_remaining_m() / 1000.0])
	return false


func _on_member_route(u: UnitState, res: Dictionary, cid: int, goal: Vector3) -> bool:
	var c: Dictionary = _state().convoys.get(cid, {})
	if res.ok or c.is_empty() or goal == c.dest:
		return false
	# The stopping place cannot be driven to: the destination itself (handled: not reported blocked).
	vsim.request_drive(u.id, c.dest, true, RouteService.Priority.CONVOY)
	return true


func _drop_member(cid: int, id: int) -> void:
	var c: Dictionary = _state().convoys.get(cid, {})
	c.members.erase(id)
	var u := sim.state.get_unit(id)
	if u and u.veh:
		u.veh.convoy_id = -1


func _dissolve(cid: int) -> void:
	var c: Dictionary = _state().convoys.get(cid, {})
	for id in c.get("members", []):
		var u := sim.state.get_unit(id)
		if u and u.veh:
			u.veh.convoy_id = -1
	_state().convoys.erase(cid)


## A member's order was replaced or it was lost: it leaves; a convoy of one dissolves.
func leave(id: int) -> void:
	var u := sim.state.get_unit(id)
	if u == null or u.veh == null or u.veh.convoy_id < 0:
		return
	var cid := u.veh.convoy_id
	u.veh.convoy_id = -1
	var c: Dictionary = _state().convoys.get(cid, {})
	if c.is_empty():
		return
	c.members.erase(id)
	if c.members.size() < 2:
		for m in c.members:
			var mu := sim.state.get_unit(m)
			if mu and mu.veh:
				mu.veh.convoy_id = -1
		_state().convoys.erase(cid)
	elif c.leader == id:
		c.leader = c.members[0]


## Stops every member and dissolves the convoy.
func stop(cid: int) -> void:
	var c: Dictionary = _state().convoys.get(cid, {})
	for id in c.get("members", []).duplicate():
		vsim.halt(id)
		leave(id)
	_state().convoys.erase(cid)


## All members drive to a new destination (as a new convoy of the same vehicles).
func redirect(cid: int, dest: Vector3) -> Dictionary:
	var c: Dictionary = _state().convoys.get(cid, {})
	if c.is_empty():
		return {"ok": false, "reason": "No such convoy"}
	return order_convoy(c.members.duplicate(), dest, c.name)


## Speed ceiling (m/s) the convoy puts on a member right now (INF = none).
func speed_limit(u: UnitState, v: VehicleState) -> float:
	var c: Dictionary = _state().convoys.get(v.convoy_id, {})
	if c.is_empty():
		return INF
	var members: Array = c.members
	var i := members.find(u.id)
	if i < 0:
		return INF
	var limit := INF
	# Behind the vehicle in front: match it inside the headway.
	for j in range(i - 1, -1, -1):
		var p := sim.state.get_unit(members[j])
		if p and p.alive and p.veh:
			# Departure: wait until the vehicle ahead has pulled out of the way.
			var odo0: Dictionary = c.get("odo0", {})
			if sim.state.time - float(c.get("start", 0.0)) < START_WAIT_S and odo0.has(p.id) and p.veh.odometer - float(odo0[p.id]) < DEPART_GAP_M and v.odometer - float(odo0.get(u.id, v.odometer)) < 1.0:
				return 0.0
			var gap := _flat(p.position, u.position) - (v.def().length + p.veh.def().length) * 0.5
			if gap < HEADWAY_M and p.veh.speed > 0.0:
				limit = minf(limit, maxf(p.veh.speed + 2.5, 2.0))
			break
	# The vehicle in front of the column waits for the rear.
	if i == 0:
		var worst := 0.0
		var worst_id := -1
		for j in range(1, members.size()):
			var m := sim.state.get_unit(members[j])
			if m and m.alive:
				var d := _flat(m.position, u.position)
				if d > worst:
					worst = d
					worst_id = m.id
		if worst > FALL_BEHIND_M * 2.0:
			var now := sim.state.time
			if float(c.get("hold_since", -1.0)) < 0.0:
				c["hold_since"] = now
			if now - float(c.hold_since) > WAIT_LIMIT_S:
				# The straggler is given up: it drives on alone when it can.
				c["hold_since"] = -1.0
				var lost := sim.state.get_unit(worst_id)
				if sim.war and lost:
					sim.war.log_event(lost.faction, "logistics", "%s: %s fell behind and left the convoy" % [c.name, lost.unit_name])
				call_deferred("leave", worst_id)
			else:
				limit = 0.0
		else:
			c["hold_since"] = -1.0
			if worst > FALL_BEHIND_M:
				limit = minf(limit, 3.0)
	return limit


## Dissolves convoys whose members have all finished (called every couple of seconds).
func update(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 2.0
	var lg := _state()
	for cid in lg.convoys.keys():
		var c: Dictionary = lg.convoys[cid]
		var active := 0
		for id in c.members.duplicate():
			var u := sim.state.get_unit(id)
			if u == null or u.veh == null or not u.alive or u.veh.convoy_id != cid:
				c.members.erase(id)
			elif u.order == UnitState.Order.MOVE:
				active += 1
		if active == 0 or c.members.size() < 2:
			for id in c.members:
				var u := sim.state.get_unit(id)
				if u and u.veh:
					u.veh.convoy_id = -1
			lg.convoys.erase(cid)


## One line for the HUD.
func describe(cid: int) -> String:
	var c: Dictionary = _state().convoys.get(cid, {})
	if c.is_empty():
		return ""
	var lead := sim.state.get_unit(c.leader)
	var togo := (", %.1f km to go" % (lead.veh.route_remaining_m() / 1000.0)) if lead and lead.veh else ""
	return "%s: %d vehicles%s" % [c.name, c.members.size(), togo]


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

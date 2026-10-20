## Infantry transport (LOGISTICS-01 phase B), a part of VehicleSim.
##
## The relation vehicle <-> passengers lives in two records that only this class changes
## together: `VehicleState.occupants` (seat order) and `UnitState.vehicle_id`. An aboard
## soldier keeps its record (faction, health, weapon, loadout, squad membership) but has no
## body or proxy (WorldSim.hide_view), is not in the combat brain's grid and follows the
## vehicle, so it is neither walking nor shootable and cannot be duplicated or left behind by
## a tier change. Orders go through the existing systems: soldiers walk to the boarding point
## with ordinary Move orders, the vehicle drives with VehicleSim.order_drive, and after
## disembarking the squad regroups with SquadControl.
##
## Phases of a transport order (VehicleState.Phase): APPROACH (the vehicle drives to a far
## squad) -> BOARDING (soldiers walk to the rear door and board while the vehicle waits) ->
## TRANSIT (the vehicle drives to the destination) -> UNLOADING (stopped: the soldiers get
## off at safe spots behind it and the squad reforms).
class_name VehicleTransport
extends RefCounted

## A soldier boards within this distance (m) of the rear door.
const BOARD_RADIUS := 5.0
## A squad farther than this from the vehicle makes the vehicle drive to it first.
const APPROACH_M := 350.0
## Boarding gives up on soldiers that have not arrived after this long (sim seconds).
const BOARD_TIMEOUT_S := 90.0
const UNLOAD_DELAY_S := 1.2

var sim: WorldSim
var vsim: VehicleSim


func _init(p_vsim: VehicleSim) -> void:
	vsim = p_vsim
	sim = p_vsim.sim


# --- Orders -----------------------------------------------------------------------------------

## Assigns a squad to a vehicle: it boards, and (dest finite) is driven there and set down.
## Returns {ok, reason, boarding, left_behind}.
func order_transport(vid: int, squad_id: int, dest := Vector3.INF) -> Dictionary:
	var u := sim.state.get_unit(vid)
	var sq := sim.state.get_squad(squad_id)
	if u == null or u.veh == null or not u.alive or sq == null:
		return {"ok": false, "reason": "No such vehicle or squad"}
	var v := u.veh
	if v.status == VehicleState.Status.DISABLED:
		return {"ok": false, "reason": "The vehicle is disabled"}
	var def := v.def()
	var free := def.passengers - v.occupants.size() - v.pending.size()
	var ids: Array[int] = []
	for id in sq.members:
		var s := sim.state.get_unit(id)
		if s and s.alive and s.vehicle_id < 0 and not _is_pending(id) and ids.size() < free:
			ids.append(id)
	if ids.is_empty():
		return {"ok": false, "reason": "No room (%d/%d aboard)" % [v.occupants.size() + v.pending.size(), def.passengers] if free <= 0 else "Nobody to board"}
	var left := sq.members.size() - ids.size() - _aboard_of(sq, vid)
	v.squad_id = squad_id
	v.transport_dest = dest
	for id in ids:
		sim.state.detach(id)
		v.pending.append(id)
	if v.phase != VehicleState.Phase.BOARDING:
		v.phase_since = sim.state.time
	var far := _flat(_centroid(ids), u.position) > APPROACH_M
	if far and v.phase != VehicleState.Phase.BOARDING:
		v.phase = VehicleState.Phase.APPROACH
		var res := vsim.order_drive(vid, _approach_point(u, _centroid(ids)), true)
		if not res.ok:
			v.phase = VehicleState.Phase.NONE
			v.squad_id = -1
			v.pending = PackedInt32Array()
			return {"ok": false, "reason": "The vehicle cannot reach the squad: " + res.reason}
	else:
		_begin_boarding(u, v)
	vsim.status_note(u, "transport ordered: %s" % sq.squad_name)
	return {"ok": true, "reason": "", "boarding": ids.size(), "left_behind": maxi(left, 0), "far": far}


## True when the soldier is already walking to some vehicle.
func _is_pending(id: int) -> bool:
	for vid in vsim.ids:
		var o: UnitState = sim.state.units.get(vid)
		if o and o.veh.pending.has(id):
			return true
	return false


## Soldiers that are already aboard this vehicle count as boarded.
func _aboard_of(sq: SquadState, vid: int) -> int:
	var n := 0
	for id in sq.members:
		var s := sim.state.get_unit(id)
		if s and s.vehicle_id == vid:
			n += 1
	return n


func _begin_boarding(u: UnitState, v: VehicleState) -> void:
	v.phase = VehicleState.Phase.BOARDING
	vsim.halt_in_place(u)
	var door := door_point(u)
	var yaw := u.yaw
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var k := 0
	for id in v.pending:
		var spot := door + right * ((k % 4) - 1.5) * 1.0 + back * float(k / 4) * 1.0
		spot = vsim.ground_with_clearance(spot)
		sim.state.issue_move(id, spot)
		k += 1


## The point behind the vehicle where infantry board and get off.
func door_point(u: UnitState) -> Vector3:
	var d := u.veh.def()
	var back := Vector3(sin(u.yaw), 0.0, cos(u.yaw))
	var p := u.position + back * (d.door_z + 1.0)
	p.y = vsim.ground_at(p)
	return p


func _approach_point(u: UnitState, squad_centre: Vector3) -> Vector3:
	var to := Vector3(u.position.x - squad_centre.x, 0.0, u.position.z - squad_centre.z).normalized()
	var p := squad_centre + to * 14.0
	p.y = vsim.ground_at(p)
	return p


## Cancels the transport: soldiers still walking stop, those aboard get off where they are.
func cancel(vid: int) -> void:
	var u := sim.state.get_unit(vid)
	if u == null or u.veh == null:
		return
	var v := u.veh
	var was := v.phase
	_release_pending(v)
	v.phase = VehicleState.Phase.NONE
	v.transport_dest = Vector3.INF
	if was == VehicleState.Phase.APPROACH or was == VehicleState.Phase.TRANSIT:
		vsim.halt(vid)
	vsim.status_note(u, "transport cancelled")
	if not v.occupants.is_empty():
		_start_unloading(u, v)


## A Move order while boarding: go now, with whoever is aboard; the others stop.
func depart(u: UnitState, v: VehicleState, dest: Vector3) -> void:
	_release_pending(v)
	v.transport_dest = dest
	v.phase = VehicleState.Phase.TRANSIT if not v.occupants.is_empty() else VehicleState.Phase.NONE
	v.phase_since = sim.state.time


## Soldiers still walking to the vehicle stop where they are.
func _release_pending(v: VehicleState) -> void:
	for id in v.pending:
		var s := sim.state.get_unit(id)
		if s and s.alive and s.vehicle_id < 0:
			sim.state.halt(id)
	v.pending = PackedInt32Array()


## Stops the vehicle and sets everybody down (the U command).
func unload(vid: int) -> void:
	var u := sim.state.get_unit(vid)
	if u == null or u.veh == null:
		return
	if u.veh.occupants.is_empty():
		# Nobody aboard yet: U cancels a boarding that is still going on.
		if u.veh.phase != VehicleState.Phase.NONE or not u.veh.pending.is_empty():
			cancel(vid)
		return
	_release_pending(u.veh)
	vsim.halt(vid)
	u.veh.transport_dest = Vector3.INF
	_start_unloading(u, u.veh)


func _start_unloading(u: UnitState, v: VehicleState) -> void:
	v.phase = VehicleState.Phase.UNLOADING
	v.phase_since = sim.state.time


# --- Per tick ---------------------------------------------------------------------------------

func update(u: UnitState, v: VehicleState, _dt: float) -> void:
	# Aboard soldiers follow the vehicle; records of soldiers that vanished are dropped.
	if not v.occupants.is_empty():
		var keep := PackedInt32Array()
		for id in v.occupants:
			var s := sim.state.get_unit(id)
			if s == null or s.vehicle_id != u.id:
				continue
			keep.append(id)
			s.position = u.position + Vector3.UP * 1.2
			s.yaw = u.yaw
			s.velocity = Vector3.ZERO
		if keep.size() != v.occupants.size():
			v.occupants = keep
	if not u.alive or v.status == VehicleState.Status.DISABLED:
		if not v.occupants.is_empty():
			disembark_all(u, v)
		v.phase = VehicleState.Phase.NONE
		return
	var now := sim.state.time
	match v.phase:
		VehicleState.Phase.APPROACH:
			if u.order == UnitState.Order.NONE and u.move_state == UnitState.MoveState.ARRIVED and absf(v.speed) < 0.5:
				_begin_boarding(u, v)
			elif u.order == UnitState.Order.NONE and v.status == VehicleState.Status.BLOCKED:
				v.phase = VehicleState.Phase.NONE
		VehicleState.Phase.BOARDING:
			_update_boarding(u, v, now)
		VehicleState.Phase.TRANSIT:
			if u.order == UnitState.Order.NONE:
				if u.move_state == UnitState.MoveState.ARRIVED and absf(v.speed) < 0.6:
					_start_unloading(u, v)
				elif v.status == VehicleState.Status.BLOCKED or v.status == VehicleState.Status.NO_FUEL:
					# The journey failed (reported to the player): keep the passengers aboard.
					v.phase = VehicleState.Phase.NONE
		VehicleState.Phase.UNLOADING:
			if now - v.phase_since >= UNLOAD_DELAY_S and absf(v.speed) < 0.6:
				disembark_all(u, v)
				v.phase = VehicleState.Phase.NONE
				v.transport_dest = Vector3.INF


func _update_boarding(u: UnitState, v: VehicleState, now: float) -> void:
	var door := door_point(u)
	var def := v.def()
	var waiting := PackedInt32Array()
	var remaining := PackedInt32Array()
	for id in v.pending:
		var s := sim.state.get_unit(id)
		if s == null or not s.alive or s.vehicle_id >= 0:
			continue
		if v.occupants.size() >= def.passengers:
			sim.state.halt(id)
			continue
		var at_door := _flat(s.position, door)
		if at_door <= BOARD_RADIUS or _flat(s.position, u.position) <= def.length * 0.5 + 1.5 				or (s.order == UnitState.Order.NONE and at_door < 9.0):
			board(s, u)
		else:
			waiting.append(id)
			remaining.append(id)
	v.pending = remaining
	var timed_out := now - v.phase_since > BOARD_TIMEOUT_S
	if waiting.is_empty() or timed_out:
		if timed_out and not waiting.is_empty():
			vsim.status_note(u, "%d soldiers did not reach the vehicle" % waiting.size())
			_release_pending(v)
		if v.occupants.is_empty():
			v.phase = VehicleState.Phase.NONE
			v.reason = "Nobody boarded"
			return
		if v.transport_dest.is_finite():
			v.phase = VehicleState.Phase.TRANSIT
			v.phase_since = now
			var res := vsim.order_drive(u.id, v.transport_dest, true)
			if not res.ok:
				v.phase = VehicleState.Phase.NONE
		else:
			v.phase = VehicleState.Phase.NONE
			v.reason = ""


## The soldier gets on: record link, no more views, no orders.
func board(s: UnitState, vehicle: UnitState) -> bool:
	var v := vehicle.veh
	if v.occupants.size() >= v.def().passengers or s.vehicle_id >= 0:
		return false
	sim.state.halt(s.id)
	s.clear_reaction()
	s.target_id = -1
	s.ai_state = UnitState.AiState.IDLE
	s.vehicle_id = vehicle.id
	v.occupants.append(s.id)
	s.position = vehicle.position + Vector3.UP * 1.2
	sim.hide_view(s.id)
	sim.state.order_changed.emit(s)
	return true


## Everybody gets off at safe spots behind the vehicle (not inside walls, other vehicles,
## water or on top of each other), and the squad reforms there.
func disembark_all(u: UnitState, v: VehicleState) -> void:
	if v.occupants.is_empty():
		return
	var ids := Array(v.occupants)
	var spots := _free_spots(u, v, ids.size())
	var k := 0
	var squads := {}
	for id in ids:
		var s := sim.state.get_unit(id)
		if s == null:
			continue
		s.vehicle_id = -1
		s.position = spots[k]
		s.yaw = u.yaw
		s.velocity = Vector3.ZERO
		s.move_state = UnitState.MoveState.IDLE
		s.anchor_pos = s.position
		var sq := sim.state.squad_of(id)
		if sq:
			squads[sq.id] = sq
			sq.detached = _without(sq.detached, id)
		k += 1
	v.occupants = PackedInt32Array()
	v.squad_id = -1
	if sim.detail:
		sim.detail.create_missing_proxies()
	# Reform in the squad's formation behind the vehicle, ready for the next order.
	var back := Vector3(sin(u.yaw), 0.0, cos(u.yaw))
	for sid in squads:
		var at := vsim.ground_with_clearance(u.position + back * (v.def().door_z + 9.0))
		sim.squads.order_regroup([sid], at)
	vsim.status_note(u, "%d soldiers disembarked" % ids.size())


static func _without(a: PackedInt32Array, id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for x in a:
		if x != id:
			out.append(x)
	return out


## n positions around the vehicle's rear door, valid for a soldier, spread out.
func _free_spots(u: UnitState, v: VehicleState, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var d := v.def()
	var back := Vector3(sin(u.yaw), 0.0, cos(u.yaw))
	var right := Vector3(cos(u.yaw), 0.0, -sin(u.yaw))
	var candidates: Array[Vector3] = []
	for row in 8:
		for col in 7:
			var side := ((col + 1) / 2) * (1 if col % 2 == 1 else -1)
			candidates.append(u.position + back * (d.door_z + 1.5 + row * 1.7) + right * side * 1.6)
	# Along the sides, for a vehicle whose rear is blocked (backed against a wall).
	for k in 12:
		var sd := 1.0 if k % 2 == 0 else -1.0
		candidates.append(u.position + right * sd * (d.width * 0.5 + 2.0 + (k / 2) * 0.1) + back * (-2.0 + (k / 2) * 1.7))
	for p in candidates:
		if out.size() >= n:
			break
		var q := vsim.ground_with_clearance(p)
		if not vsim.spot_valid(q):
			continue
		var close := false
		for o in out:
			if _flat(o, q) < 1.2:
				close = true
				break
		if not close:
			out.append(q)
	# Not enough valid spots: stack the rest at the door (never inside the vehicle).
	while out.size() < n:
		out.append(vsim.ground_with_clearance(u.position + back * (d.door_z + 2.0)))
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _centroid(ids: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for id in ids:
		var s := sim.state.get_unit(id)
		if s:
			c += s.position
			n += 1
	return c / maxi(n, 1)


## One line for the HUD: who is aboard and what the transport is doing.
func describe(u: UnitState) -> String:
	var v := u.veh
	var def := v.def()
	var sq := sim.state.get_squad(v.squad_id)
	var s := "%d/%d aboard" % [v.occupants.size(), def.passengers]
	if sq and not v.occupants.is_empty():
		s += " (%s)" % sq.squad_name
	if v.phase != VehicleState.Phase.NONE:
		s += " · " + VehicleState.PHASE_NAMES[v.phase]
		if v.phase == VehicleState.Phase.BOARDING and sq:
			s += " %d/%d" % [v.occupants.size(), v.occupants.size() + v.pending.size()]
	if v.transport_dest.is_finite():
		s += " · to (%.0f, %.0f)" % [v.transport_dest.x, v.transport_dest.z]
	return s


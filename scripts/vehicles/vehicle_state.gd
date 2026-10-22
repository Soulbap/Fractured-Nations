## Persistent state of one vehicle (LOGISTICS-01): the vehicle half of a UnitState record
## (`UnitState.veh`, null for soldiers). Plain data like everything in WorldState; the
## simulation (VehicleSim) updates it every tick whether or not a body shows the vehicle,
## the body (near) and the proxy (far) only read it.
##
## Identity, faction, position, yaw, health and the Move order stay in UnitState; this
## record adds what only vehicles have: type, speed, steering, fuel, the route being driven
## and (later phases) occupants, cargo and convoy membership.
class_name VehicleState
extends RefCounted

enum Phase { NONE, APPROACH, BOARDING, TRANSIT, UNLOADING }
const PHASE_NAMES: Array[String] = ["", "driving to the squad", "boarding", "transporting", "disembarking"]
enum Status { PARKED, DRIVING, WAITING, BLOCKED, NO_FUEL, DISABLED, PLAYER }
const STATUS_NAMES: Array[String] = ["parked", "driving", "waiting", "blocked", "no fuel", "disabled", "driven by player"]

var type_id: StringName = VehicleDefs.TRUCK
## Signed speed along the heading (m/s); steering angle of the front wheels (rad, + = left).
var speed := 0.0
var steer := 0.0
## Litres in the tank.
var fuel := 0.0
## Distance driven (m); wheels spin from it, so the animation survives tier changes.
var odometer := 0.0
var status := Status.PARKED
## Why the vehicle waits or stopped (shown to the player); empty when all is well.
var reason := ""

## The route being followed (dense polyline, ~3 m apart, y = ground) with its speed ceiling
## per point, the index of the point nearest to the vehicle and the planner's summary.
var route := PackedVector3Array()
var route_cap := PackedFloat32Array()
var route_i := 0
var route_info := {}

## Infantry transport (Phase B): soldier ids aboard (seat order), the squad assigned to the
## vehicle, the phase of the transport order and its destination.
var occupants := PackedInt32Array()
## Soldiers told to board that have not got on yet (their seats are taken).
var pending := PackedInt32Array()
var squad_id := -1
## Supplies carried (an Inventory like a depot's), the convoy the vehicle drives in (-1 = none)
## and its current logistics job (see LogisticsSim): {} when idle.
var cargo: Inventory
var convoy_id := -1
var job := {}
## AI-WAR-LOGISTICS-01: what an AI faction has committed the vehicle to: "" (free), "op" (assign_id = the operation
## it carries squads for), "supply" (assign_id = the supply mission) or "return" (driving back to a base after a
## task). Only WarSim code writes it, and only for vehicles that are not player-controlled; the player taking a
## vehicle clears it (OpTransport / WarLogistics notice and adapt).
var assign_kind := ""
var assign_id := -1

var phase := Phase.NONE
var phase_since := 0.0
var transport_dest := Vector3.INF

## Stuck handling: odometer at the last recovery (stuck_s), reversing time left, attempts made.
var stuck_s := 0.0
var reverse_left := 0.0
var recoveries := 0
var replans := 0

# --- Runtime only (never saved) ---------------------------------------------------------
## Player driving input: throttle -1..1 (+ forward), steering -1..1 (+ right), brake 0..1.
var in_throttle := 0.0
var in_steer := 0.0
var in_brake := 0.0
## Speed profile derived from route + route_cap (VehicleSim.prepare_route).
var profile := PackedFloat32Array()
## Length along the route at every point.
var route_s := PackedFloat32Array()
var _progress_ref := Vector3.INF
var _progress_t := 0.0
## Detours taken round obstacles on the current order (VehicleSim._try_bypass), capped per order.
var bypasses := 0
## Runtime only: where the vehicle wants to point after backing out (INF: no goal, back out on opposite lock).
var reverse_goal := Vector3.INF
## Obstacle report of the physics probe of a body (near tier): free distance ahead.
var probe_ahead := INF


func _init() -> void:
	cargo = Inventory.make(VehicleDefs.get_def(type_id).cargo_capacity)


func def() -> VehicleDefs.Def:
	return VehicleDefs.get_def(type_id)


func status_name() -> String:
	return STATUS_NAMES[status]


func route_remaining_m() -> float:
	if route_s.is_empty():
		return 0.0
	return route_s[route_s.size() - 1] - route_s[mini(route_i, route_s.size() - 1)]


func to_dict() -> Dictionary:
	var rt := []
	for p in route:
		rt.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	return {"type": String(type_id), "speed": speed, "steer": steer, "fuel": fuel, "odo": odometer,
		"status": status, "reason": reason, "route": rt, "cap": Array(route_cap), "route_i": route_i,
		"cargo": cargo.to_dict() if cargo else null, "convoy": convoy_id, "job": job, "assign": [assign_kind, assign_id],
		"occ": Array(occupants), "pending": Array(pending), "squad": squad_id, "phase": phase, "phase_since": phase_since, "dest": transport_dest,
		"info": route_info, "stuck": stuck_s, "reverse": reverse_left, "recoveries": recoveries, "replans": replans}


static func from_dict(d: Dictionary) -> VehicleState:
	var v := VehicleState.new()
	v.copy_from(d)
	return v


## Loads a saved dictionary into this record (in place, so bodies holding it stay valid).
func copy_from(d: Dictionary) -> void:
	type_id = StringName(d.get("type", String(VehicleDefs.TRUCK)))
	speed = d.get("speed", 0.0)
	steer = d.get("steer", 0.0)
	fuel = d.get("fuel", def().fuel_capacity)
	odometer = d.get("odo", 0.0)
	status = d.get("status", Status.PARKED)
	reason = d.get("reason", "")
	route = PackedVector3Array()
	for p: Array in d.get("route", []):
		route.append(Vector3(p[0], p[1], p[2]))
	route_cap = PackedFloat32Array(d.get("cap", []))
	route_i = d.get("route_i", 0)
	route_info = d.get("info", {})
	occupants = PackedInt32Array(d.get("occ", []))
	cargo = Inventory.from_dict(d.cargo) if d.get("cargo") is Dictionary else Inventory.make(def().cargo_capacity)
	convoy_id = d.get("convoy", -1)
	job = d.get("job", {})
	var asg: Array = d.get("assign", ["", -1])
	assign_kind = String(asg[0])
	assign_id = int(asg[1])
	pending = PackedInt32Array(d.get("pending", []))
	squad_id = d.get("squad", -1)
	phase = d.get("phase", Phase.NONE)
	phase_since = d.get("phase_since", 0.0)
	transport_dest = d.get("dest", Vector3.INF)
	stuck_s = d.get("stuck", 0.0)
	reverse_left = d.get("reverse", 0.0)
	recoveries = d.get("recoveries", 0)
	replans = d.get("replans", 0)
	in_throttle = 0.0
	in_steer = 0.0
	in_brake = 0.0
	profile = PackedFloat32Array()
	route_s = PackedFloat32Array()
	_progress_ref = Vector3.INF
	_progress_t = 0.0
	probe_ahead = INF

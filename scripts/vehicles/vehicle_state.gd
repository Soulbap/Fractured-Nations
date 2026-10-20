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
## Obstacle report of the physics probe of a body (near tier): free distance ahead.
var probe_ahead := INF


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

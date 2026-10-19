## Advances the WorldState in time and connects it to physical bodies.
##
## Two tiers share one record per unit:
##   - detailed: a body (SoldierBody / VehicleBody) is registered for the unit; Godot
##     physics and navigation move it and the body writes position, heading, velocity and
##     move state back into the UnitState every physics tick;
##   - abstract: no body; the unit's order is executed here as straight-line travel at
##     its speed with the height read from the terrain. This is the tier distant units
##     will use later; today it exists so that the state provably does not depend on
##     scene nodes (the self-test exercises it).
## Possession is not a tier change: a possessed soldier keeps its body and its record.
class_name WorldSim
extends Node

@export var terrain: Terrain3D
## Distance at which an abstract unit counts as arrived.
@export var abstract_arrive_m := 1.0

var state := WorldState.new()
## id -> Node3D body
var bodies := {}


func register_body(id: int, body: Node3D) -> void:
	bodies[id] = body
	var u := state.get_unit(id)
	if u:
		u.has_body = true


func unregister_body(id: int) -> void:
	bodies.erase(id)
	var u := state.get_unit(id)
	if u:
		u.has_body = false


func body_of(id: int) -> Node3D:
	return bodies.get(id)


func _physics_process(delta: float) -> void:
	state.time += delta
	for u in state.units.values():
		if not u.has_body:
			_abstract_step(u, delta)


func _abstract_step(u: UnitState, delta: float) -> void:
	if u.order != UnitState.Order.MOVE:
		u.velocity = Vector3.ZERO
		return
	var to := u.order_target - u.position
	to.y = 0.0
	var dist := to.length()
	if dist <= abstract_arrive_m:
		u.position.x = u.order_target.x
		u.position.z = u.order_target.z
		u.velocity = Vector3.ZERO
		u.order = UnitState.Order.NONE
		u.move_state = UnitState.MoveState.ARRIVED
		return
	var step := minf(u.speed * delta, dist)
	var dir := to / dist
	u.position += dir * step
	u.velocity = dir * u.speed
	u.yaw = atan2(-dir.x, -dir.z)
	u.move_state = UnitState.MoveState.MOVING
	if terrain:
		var h: float = terrain.data.get_height(u.position)
		if not is_nan(h):
			u.position.y = h


## Counts for the HUD and tests: how many units have a body, how many are moving.
func stats() -> Dictionary:
	var moving := 0
	var with_body := 0
	for u in state.units.values():
		if u.move_state == UnitState.MoveState.MOVING:
			moving += 1
		if u.has_body:
			with_body += 1
	return {"units": state.units.size(), "bodies": bodies.size(), "with_body": with_body, "moving": moving, "time": state.time}

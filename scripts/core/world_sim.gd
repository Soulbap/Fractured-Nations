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
## WORLD-CORE-02: DetailManager decides per unit which tier applies (distance to the
## active camera) and swaps bodies for lightweight proxies; this class only keeps the
## registries and runs the abstract step for every unit without a body.
class_name WorldSim
extends Node

## Emitted when a body or proxy starts representing a unit (selection state, HUD).
signal view_added(id: int, view: Node3D)

@export var terrain: Terrain3D
## Distance at which an abstract unit counts as arrived.
@export var abstract_arrive_m := 1.0

var state := WorldState.new()
## UNIT-01A: turns squad orders (state.squads) into per-unit move orders.
var squads := SquadControl.new(self)
## COMBAT-01a: firing, reloading, damage and death (the one combat authority).
var combat := CombatSim.new(self)
## COMBAT-01b: soldiers' own perception, target choice and firing (through `combat`).
var brain := CombatBrain.new(self)
## Parent of bodies and proxies (corpse markers are created here).
var units_root: Node3D
## id -> Node3D body (detailed tier)
var bodies := {}
## id -> UnitProxy (abstract tier visual; a unit has a body or a proxy, never both)
var proxies := {}
## Set in the large world: tells bodies whether a point is covered by the navmesh.
var detail: DetailManager
## Set when construction exists: abstract units do not pass through structures.
var structures: StructureManager


func register_body(id: int, body: Node3D) -> void:
	bodies[id] = body
	var u := state.get_unit(id)
	if u:
		u.has_body = true
	view_added.emit(id, body)


func register_proxy(id: int, proxy: Node3D) -> void:
	proxies[id] = proxy
	view_added.emit(id, proxy)


func unregister_proxy(id: int) -> void:
	proxies.erase(id)


func unregister_body(id: int) -> void:
	bodies.erase(id)
	var u := state.get_unit(id)
	if u:
		u.has_body = false


func body_of(id: int) -> Node3D:
	return bodies.get(id)


## The node currently showing a unit: its body in the detailed tier, else its proxy.
func view_of(id: int) -> Node3D:
	return bodies.get(id) if bodies.has(id) else proxies.get(id)


func _ready() -> void:
	state.restored.connect(_on_restored)
	state.unit_removed.connect(_on_unit_removed)
	state.unit_died.connect(_on_unit_died)
	brain.connect_signals()
	# COMBAT-02: shots find nearby soldiers through the brain's grid.
	combat.line.unit_index = brain


## A soldier died: its body (if any) goes, a corpse marker (UnitProxy) stays in the world.
func _on_unit_died(u: UnitState) -> void:
	var b: Node3D = bodies.get(u.id)
	var parent: Node = units_root
	if b:
		parent = b.get_parent()
		unregister_body(u.id)
		b.get_parent().remove_child(b)
		b.queue_free()
	var old: Node3D = proxies.get(u.id)
	if old:
		unregister_proxy(u.id)
		old.queue_free()
	if parent:
		var corpse := UnitProxy.new()
		parent.add_child(corpse)
		corpse.bind(u, self)


## A record went away (load without that unit): its body or proxy goes too.
func _on_unit_removed(id: int) -> void:
	for reg: Dictionary in [bodies, proxies]:
		var n: Node3D = reg.get(id)
		if n:
			reg.erase(id)
			n.queue_free()


func _physics_process(delta: float) -> void:
	state.time += delta
	for u in state.units.values():
		if not u.has_body and u.alive:
			_abstract_step(u, delta)
	squads.update(delta)
	brain.update(delta)
	combat.update(delta)


## A save was loaded into the existing records: bodies would write their old position
## back on the next tick, so they jump to the loaded one first.
func _on_restored() -> void:
	for id in bodies:
		var b: Node3D = bodies[id]
		var u := state.get_unit(id)
		if u == null:
			continue
		if b is SoldierBody:
			(b as SoldierBody).teleport(u.position, u.yaw)
			(b as SoldierBody).reset_order_tracking()
		else:
			b.global_position = u.position
			b.rotation.y = u.yaw


func _abstract_step(u: UnitState, delta: float) -> void:
	# COMBAT-02: a tactical reaction pauses the order (see SoldierBody._ai_step).
	var reacting := u.is_reacting()
	if (reacting and u.react_state != UnitState.ReactState.MOVING) or (not reacting and u.order != UnitState.Order.MOVE):
		u.velocity = Vector3.ZERO
		# COMBAT-01b: a standing soldier turns to what it watches (its target).
		if not is_nan(u.watch_yaw) and not u.player_controlled:
			u.yaw = lerp_angle(u.yaw, u.watch_yaw, clampf(8.0 * delta, 0.0, 1.0))
		return
	var goal := u.react_target if reacting else u.order_target
	var to := goal - u.position
	to.y = 0.0
	var dist := to.length()
	if dist <= (0.5 if reacting else abstract_arrive_m):
		u.position.x = goal.x
		u.position.z = goal.z
		u.velocity = Vector3.ZERO
		if reacting:
			u.react_state = UnitState.ReactState.ARRIVED
		else:
			u.order = UnitState.Order.NONE
			u.move_state = UnitState.MoveState.ARRIVED
			u.anchor_pos = u.position
		return
	var step := minf(u.speed * delta, dist)
	var dir := to / dist
	if structures:
		dir = _free_direction(u, dir, step)
		if dir == Vector3.ZERO:
			u.velocity = Vector3.ZERO
			if reacting:
				u.react_state = UnitState.ReactState.FAILED
			else:
				u.order = UnitState.Order.NONE
				u.move_state = UnitState.MoveState.BLOCKED
			return
	u.position += dir * step
	u.velocity = dir * u.speed
	u.yaw = atan2(-dir.x, -dir.z)
	u.move_state = UnitState.MoveState.MOVING
	if terrain:
		var h: float = terrain.data.get_height(u.position)
		if not is_nan(h):
			u.position.y = h


## Abstract units have no physics; without this they walk straight through walls, HESCO
## and fences. The next step is tested against the structures' blocking footprints
## (StructureManager.blocks_point, a cell lookup): straight on if free, else sliding
## 45° / 90° to one side (along a wall), else ZERO (the unit stops, BLOCKED). No path
## search: an abstract unit does not find a gate on its own; it gets its navmesh path
## again when it becomes detailed near the camera.
func _free_direction(u: UnitState, dir: Vector3, step: float) -> Vector3:
	var p := Vector2(u.position.x, u.position.z)
	var look := maxf(step, 0.5)
	if structures.blocks_point(p):
		return dir  # already inside a footprint (built around it): let it walk out
	for deg: float in [0.0, 45.0, -45.0, 90.0, -90.0]:
		var d := dir.rotated(Vector3.UP, deg_to_rad(deg))
		if not structures.blocks_point(p + Vector2(d.x, d.z) * look):
			return d
	return Vector3.ZERO


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

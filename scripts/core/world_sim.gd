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
## AI-WAR-LOGISTICS-01 (near/far parity): bodies lose a few percent of their walking speed to turning, crowd avoidance
## and navmesh detours that the straight-line abstract step does not have. Measured on the same routes (open ground,
## dense woods, slopes, a three-squad column march) the bodies take 4-8 % longer; the abstract step takes that
## friction into account so the same march takes about the same time in both tiers. Not a terrain effect: the terrain
## itself affects both tiers through the same route and the same ground (no tier is faster over woods or slopes).
@export var abstract_friction := 0.93

var state := WorldState.new()
## UNIT-01A: turns squad orders (state.squads) into per-unit move orders.
var squads := SquadControl.new(self)
## AI-SQUAD-01: fire teams and squad tactics (defend, suppress, assault, flank, bound, withdraw).
var tactics := SquadTactics.new(self)
## LOGISTICS-01: driving of every vehicle record (both tiers), routes and the player's wheel.
var vehicles := VehicleSim.new(self)
## LOGISTICS-01: depots, vehicle jobs, resupply, automation.
var logistics := LogisticsSim.new(self, vehicles)
## COMBAT-01a: firing, reloading, damage and death (the one combat authority).
var combat := CombatSim.new(self)
## COMBAT-01b: soldiers' own perception, target choice and firing (through `combat`).
var brain := CombatBrain.new(self)
## WORLD-SANDBOX-01: the strategic simulation (capture, operations, faction AI, reserves,
## intelligence); idle unless the world has an active war (state.war.active).
var war := WarSim.new(self)
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
## Abstract units sliding along an obstacle: unit id -> side (+1 / -1).
var _slide := {}
## Length of the last simulation step (s).
var last_delta := 0.0
## Accumulated cost of the simulation parts (microseconds) and ticks counted.
var tick_usec := {"abstract": 0, "squads": 0, "tactics": 0, "war": 0, "brain": 0, "combat": 0, "vehicles": 0, "ticks": 0}


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


## A soldier boarded a vehicle: its body and proxy go (the record stays, DetailManager gives
## it neither while it is aboard).
func hide_view(id: int) -> void:
	var b: Node3D = bodies.get(id)
	if b:
		unregister_body(id)
		b.get_parent().remove_child(b)
		b.queue_free()
	var p: Node3D = proxies.get(id)
	if p:
		unregister_proxy(id)
		p.get_parent().remove_child(p)
		p.queue_free()


func body_of(id: int) -> Node3D:
	return bodies.get(id)


## The node currently showing a unit: its body in the detailed tier, else its proxy.
func view_of(id: int) -> Node3D:
	return bodies.get(id) if bodies.has(id) else proxies.get(id)


func _ready() -> void:
	logistics.bind()
	state.restored.connect(_on_restored)
	state.unit_removed.connect(_on_unit_removed)
	state.unit_died.connect(_on_unit_died)
	brain.connect_signals()
	tactics.connect_signals()
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
	last_delta = delta
	state.time += delta
	var t0 := Time.get_ticks_usec()
	for u in state.units.values():
		if not u.has_body and u.alive and u.kind == UnitState.Kind.SOLDIER and u.vehicle_id < 0:
			_abstract_step(u, delta)
	var t1 := Time.get_ticks_usec()
	squads.update(delta)
	var t1t := Time.get_ticks_usec()
	tactics.update(delta)
	var t2 := Time.get_ticks_usec()
	vehicles.update(delta)
	logistics.update(delta)
	var t2v := Time.get_ticks_usec()
	war.update(delta)
	var t3 := Time.get_ticks_usec()
	brain.update(delta)
	var t4 := Time.get_ticks_usec()
	combat.update(delta)
	var t5 := Time.get_ticks_usec()
	# WORLD-PLAYTEST-01: where a simulation tick goes (time compression measurements).
	tick_usec.abstract += t1 - t0
	tick_usec.squads += t1t - t1
	tick_usec.tactics += t2 - t1t
	tick_usec.vehicles += t2v - t2
	tick_usec.war += t3 - t2v
	tick_usec.brain += t4 - t3
	tick_usec.combat += t5 - t4
	tick_usec.ticks += 1


## A save was loaded into the existing records: bodies would write their old position
## back on the next tick, so they jump to the loaded one first.
func _on_restored() -> void:
	# LOGISTICS-01: soldiers aboard a vehicle show nothing; the others show something again.
	for u: UnitState in state.units.values():
		if u.vehicle_id >= 0:
			hide_view(u.id)
	if detail:
		detail.create_missing_proxies()
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
		_settle_height(u)
		u.velocity = Vector3.ZERO
		if reacting:
			u.react_state = UnitState.ReactState.ARRIVED
		else:
			u.order = UnitState.Order.NONE
			u.move_state = UnitState.MoveState.ARRIVED
			u.anchor_pos = u.position
		return
	var step := minf(u.speed * abstract_friction * delta, dist)
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
	u.velocity = dir * u.speed * abstract_friction
	u.yaw = atan2(-dir.x, -dir.z)
	u.move_state = UnitState.MoveState.MOVING
	_settle_height(u)


## Height of an abstract unit: the terrain, or the bridge deck it stands on; a unit beside
## a bridge above the river (a formation's outer file) moves onto the deck.
func _settle_height(u: UnitState) -> void:
	if terrain:
		var h: float = terrain.data.get_height(u.position)
		# WORLD-PLAYTEST-01: on a bridge the unit walks on the deck, not in the river below.
		var deck := state.roads.deck_height(u.position)
		if not is_nan(deck):
			h = deck if is_nan(h) else maxf(h, deck)
		elif structures and not is_nan(h) and structures.water_height(u.position.x, u.position.z) > h + 0.2:
			# Beside a bridge over the river (a formation's outer file): onto the deck.
			var on := state.roads.onto_deck(u.position)
			if on.is_finite():
				u.position.x = on.x
				u.position.z = on.z
				h = on.y
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
	var look := maxf(step, 1.0)
	# WORLD-INTEGRATION-03: the next step itself is tested too, not only the point 1 m
	# ahead. Sliding at 45° along a wall, the look-ahead point cleared the footprint while
	# the unit crept into it a few centimetres per tick, and "already inside: walk out"
	# then let it walk straight through the wall.
	var near := maxf(step * 2.0, 0.3)
	if structures.blocks_point(p):
		# Inside a footprint (built around it, or pushed in): out the way it came, else
		# any free side; through it only when nothing else is free.
		for deg: float in [180.0, 135.0, -135.0, 90.0, -90.0]:
			var d := dir.rotated(Vector3.UP, deg_to_rad(deg))
			if not structures.blocks_point(p + Vector2(d.x, d.z) * look):
				return d
		return dir
	if not structures.blocks_point(p + Vector2(dir.x, dir.z) * look) and not structures.blocks_point(p + Vector2(dir.x, dir.z) * near):
		_slide.erase(u.id)
		return dir
	# WORLD-SANDBOX-01: follow the obstacle on one side until the way to the target is
	# free again (a gate in a HESCO perimeter, the end of a wall). Choosing a side anew
	# every step made units slide back and forth in front of a wall forever.
	var side: int = _slide.get(u.id, 0)
	for attempt in 2:
		if side == 0:
			side = 1 if not structures.blocks_point(p + Vector2(dir.rotated(Vector3.UP, deg_to_rad(45.0)).x, dir.rotated(Vector3.UP, deg_to_rad(45.0)).z) * look) else -1
		for deg: float in [45.0, 90.0, 135.0]:
			var d := dir.rotated(Vector3.UP, deg_to_rad(deg * side))
			var q := Vector2(d.x, d.z)
			if not structures.blocks_point(p + q * look) and not structures.blocks_point(p + q * near):
				_slide[u.id] = side
				return d
		side = -side
	_slide.erase(u.id)
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

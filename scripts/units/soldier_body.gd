## Physical soldier: the detailed-tier body of a UnitState.
##
## Reuses the WORLD-TECH-01 first-person controller unchanged: when possessed, the
## FPSController reads the keyboard and mouse; when nobody controls it, this script
## executes the unit's move order through a NavigationAgent3D (navmesh path + RVO
## avoidance against the other soldiers) and feeds the same CharacterBody3D. Either
## way the result is written back into the UnitState every physics tick, so the record
## in WorldState is always what the world shows. A possessed soldier suspends its order
## and resumes it when the player leaves; it never loses it.
class_name SoldierBody
extends FPSController

## Flat distance at which an order counts as reached.
@export var arrive_distance := 1.3
## Reached the end of the navigation path but still farther than this from the target:
## the target was not reachable (outside the navmesh), reported as BLOCKED.
@export var blocked_distance := 3.0
@export var turn_speed := 8.0
## Repath attempts before an order with no navigation path is reported as BLOCKED.
@export var max_empty_path_s := 4.0

var unit: UnitState
var sim: WorldSim
var selected := false:
	set(v):
		selected = v
		if is_node_ready():
			UnitVisuals.style_ring(ring, unit.faction if unit else 0, selected)

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var visual: Node3D = $Visual
@onready var ring: MeshInstance3D = $Ring
## CHARACTER-01 infantry character (null when the placeholder model is used).
var character: InfantryCharacter

var _safe_velocity := Vector3.ZERO
var _applied_target := Vector3.INF
var _empty_path_s := 0.0


func _ready() -> void:
	player_controlled = false
	super()
	nav.velocity_computed.connect(_on_velocity_computed)
	possession_changed.connect(_on_possession_changed)
	nav.max_speed = walk_speed


## Attaches this body to a unit record and registers it with the simulation.
func bind(p_unit: UnitState, p_sim: WorldSim) -> void:
	unit = p_unit
	sim = p_sim
	name = "Soldier_%d" % unit.id
	global_position = unit.position
	rotation.y = unit.yaw
	velocity = Vector3.ZERO
	_spawn = global_transform
	if InfantryCharacter.enabled():
		_use_infantry_character()
	else:
		UnitVisuals.apply_faction(visual, unit.faction)
	UnitVisuals.style_ring(ring, unit.faction, selected)
	sim.register_body(unit.id, self)
	_sync_state()


## Replaces the placeholder model with the modular infantry character for the unit's
## loadout. Built once per body; a re-promoted unit gets the same loadout (UnitState).
func _use_infantry_character() -> void:
	if unit.loadout == "":
		unit.loadout = InfantryLoadout.default_for(unit.id)
	var lo := InfantryLoadout.by_id(unit.loadout)
	if lo == null:
		UnitVisuals.apply_faction(visual, unit.faction)
		return
	if character and character.loadout == lo and character.faction == unit.faction:
		return
	for c in visual.get_children():
		visual.remove_child(c)
		c.queue_free()
	character = InfantryCharacter.new()
	character.name = "Infantry"
	character.body = self
	visual.add_child(character)
	character.setup(lo, unit.faction)
	if player_controlled:
		UnitVisuals.set_shadows_only(visual, true)


func _exit_tree() -> void:
	if sim and unit and sim.bodies.get(unit.id) == self:
		sim.unregister_body(unit.id)


func _process(_delta: float) -> void:
	if ring.visible:
		UnitVisuals.scale_ring_for_camera(ring, selected)


func _physics_process(delta: float) -> void:
	if unit == null:
		return
	if player_controlled:
		super(delta)
		# Let the avoidance simulation know where the player is heading.
		if nav.avoidance_enabled:
			nav.velocity = Vector3(velocity.x, 0.0, velocity.z)
	else:
		_ai_step(delta)
	_sync_state()


func _ai_step(delta: float) -> void:
	var desired := Vector3.ZERO
	if unit.order == UnitState.Order.MOVE:
		if _applied_target != unit.order_target:
			_applied_target = unit.order_target
			nav.target_position = unit.order_target
			unit.move_state = UnitState.MoveState.MOVING
			_empty_path_s = 0.0
		var flat := unit.order_target - global_position
		flat.y = 0.0
		var remaining := flat.length()
		# get_next_path_position() is what makes the agent (re)query its path.
		var next := nav.get_next_path_position()
		var path_len := nav.get_current_navigation_path().size()
		if remaining <= arrive_distance:
			_finish_order(remaining)
		elif path_len == 0 and sim.detail and not sim.detail.nav_covers(unit.order_target):
			desired = flat.normalized() * walk_speed
			_face(flat.normalized(), delta)
		elif path_len == 0:
			# No path yet (navigation map not synced, or target off the navmesh): retry.
			_empty_path_s += delta
			if _empty_path_s > max_empty_path_s:
				_finish_order(remaining)
			elif Engine.get_physics_frames() % 10 == 0:
				nav.target_position = unit.order_target
		elif nav.is_navigation_finished():
			if remaining > blocked_distance and sim.detail and not sim.detail.nav_covers(unit.order_target):
				# The target lies beyond the navmesh area around the active camera: keep
				# heading for it. Leaving the camera's detail radius hands the unit to
				# the abstract tier, which finishes the walk (the order is never dropped).
				var far_dir := flat.normalized()
				desired = far_dir * walk_speed
				_face(far_dir, delta)
			else:
				_finish_order(remaining)
		else:
			var dir := next - global_position
			dir.y = 0.0
			if dir.length_squared() > 1e-4:
				dir = dir.normalized()
				desired = dir * walk_speed
				_face(dir, delta)
	else:
		_applied_target = Vector3.INF
	if nav.avoidance_enabled:
		nav.velocity = desired
		_apply_velocity(_safe_velocity if desired != Vector3.ZERO else Vector3.ZERO, delta)
	else:
		_apply_velocity(desired, delta)


func _finish_order(remaining: float) -> void:
	unit.order = UnitState.Order.NONE
	unit.move_state = UnitState.MoveState.ARRIVED if remaining <= blocked_distance else UnitState.MoveState.BLOCKED
	_applied_target = Vector3.INF
	sim.state.order_changed.emit(unit)


func _apply_velocity(v: Vector3, delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	velocity.x = v.x
	velocity.z = v.z
	move_and_slide()


func _face(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _sync_state() -> void:
	unit.position = global_position
	unit.yaw = rotation.y
	unit.velocity = velocity
	unit.player_controlled = player_controlled


func _on_velocity_computed(safe: Vector3) -> void:
	_safe_velocity = safe


func _on_possession_changed(controlled: bool) -> void:
	# Re-apply the suspended order when control returns to the simulation.
	_applied_target = Vector3.INF
	_safe_velocity = Vector3.ZERO
	if is_node_ready():
		UnitVisuals.set_shadows_only(visual, controlled)
		ring.visible = not controlled
	if unit:
		unit.player_controlled = controlled

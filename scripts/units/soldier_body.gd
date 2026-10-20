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
## COMBAT-02: a cover position must be reached more closely than an order slot.
@export var react_arrive_distance := 0.7
## Reached the end of the navigation path but still farther than this from the target:
## the target was not reachable (outside the navmesh), reported as BLOCKED.
@export var blocked_distance := 3.0
@export var turn_speed := 8.0
## Repath attempts before an order with no navigation path is reported as BLOCKED.
@export var max_empty_path_s := 4.0
## UNIT-01A stuck handling: a soldier that walks but gains less than stuck_progress_m in
## stuck_s first re-queries its path and ignores crowd avoidance for unstick_s (two
## agents can hold each other in a narrow gap); still stuck after another stuck_s, the
## order ends as BLOCKED instead of walking in place forever.
@export var stuck_s := 3.0
@export var stuck_progress_m := 0.8
@export var unstick_s := 1.5

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
## Scripted tests run in a window that may not hold OS mouse capture; they clear this so
## the trigger works without it. Always true in play.
static var require_mouse_capture := true
## COMBAT-01a first-person weapon: the viewmodel exists while possessed.
var viewmodel: Viewmodel
## The trigger only works after it was released once with the mouse captured (the click
## that captures the mouse must not fire).
var _trigger_armed := false
var _fov_hip := 75.0
var _progress_ref := Vector3.INF
var _progress_t := 0.0
var _stuck_stage := 0
var _unstick_left := 0.0


func _ready() -> void:
	ensure_combat_actions()
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
		unit.loadout = InfantryLoadout.default_for(unit.id, unit.faction)
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
		_player_weapon(delta)
	else:
		_ai_step(delta)
	_sync_state()
	if character:
		# Soldiers holding cover crouch behind it (COMBAT-02 tactic -> CHARACTER-01 pose).
		character.crouched = not player_controlled and unit.tactic == UnitState.Tactic.IN_COVER


func _ai_step(delta: float) -> void:
	var desired := Vector3.ZERO
	# COMBAT-02: a tactical reaction (react_target) pauses the order: walk to the
	# reaction's goal, then wait there until the AI ends the reaction.
	var reacting := unit.is_reacting()
	var goal := unit.react_target if reacting else unit.order_target
	if reacting and unit.react_state != UnitState.ReactState.MOVING:
		_applied_target = Vector3.INF
		if not is_nan(unit.watch_yaw):
			rotation.y = lerp_angle(rotation.y, unit.watch_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	elif reacting or unit.order == UnitState.Order.MOVE:
		if _applied_target != goal:
			_applied_target = goal
			nav.target_position = goal
			if not reacting:
				unit.move_state = UnitState.MoveState.MOVING
			_empty_path_s = 0.0
			_reset_stuck()
		var flat := goal - global_position
		flat.y = 0.0
		var remaining := flat.length()
		# get_next_path_position() is what makes the agent (re)query its path.
		var next := nav.get_next_path_position()
		var path_len := nav.get_current_navigation_path().size()
		if remaining <= (react_arrive_distance if reacting else arrive_distance):
			_finish(remaining, reacting)
		elif path_len == 0 and sim.detail and not sim.detail.nav_covers(goal):
			desired = flat.normalized() * walk_speed
			_face(flat.normalized(), delta)
		elif path_len == 0:
			# No path yet (navigation map not synced, or target off the navmesh): retry.
			_empty_path_s += delta
			if _empty_path_s > max_empty_path_s:
				_finish(remaining, reacting)
			elif Engine.get_physics_frames() % 10 == 0:
				nav.target_position = goal
		elif nav.is_navigation_finished():
			if remaining > blocked_distance and sim.detail and not sim.detail.nav_covers(goal):
				# The target lies beyond the navmesh area around the active camera: keep
				# heading for it. Leaving the camera's detail radius hands the unit to
				# the abstract tier, which finishes the walk (the order is never dropped).
				var far_dir := flat.normalized()
				desired = far_dir * walk_speed
				_face(far_dir, delta)
			else:
				_finish(remaining, reacting)
		else:
			var dir := next - global_position
			dir.y = 0.0
			if dir.length_squared() > 1e-4:
				dir = dir.normalized()
				desired = dir * walk_speed
				_face(dir, delta)
		if desired != Vector3.ZERO:
			_check_stuck(delta, remaining, reacting)
	else:
		_applied_target = Vector3.INF
		# COMBAT-01b: standing, the soldier turns to what its AI watches (its target).
		if not is_nan(unit.watch_yaw):
			rotation.y = lerp_angle(rotation.y, unit.watch_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	if _unstick_left > 0.0:
		_unstick_left -= delta
		_apply_velocity(desired, delta)
		return
	if nav.avoidance_enabled:
		nav.velocity = desired
		_apply_velocity(_safe_velocity if desired != Vector3.ZERO else Vector3.ZERO, delta)
	else:
		_apply_velocity(desired, delta)


## The record's order was replaced from outside (load): apply it afresh.
func reset_order_tracking() -> void:
	_applied_target = Vector3.INF
	_safe_velocity = Vector3.ZERO
	_empty_path_s = 0.0
	_reset_stuck()


func _reset_stuck() -> void:
	_progress_ref = global_position
	_progress_t = 0.0
	_stuck_stage = 0
	_unstick_left = 0.0


func _check_stuck(delta: float, remaining: float, reacting := false) -> void:
	if not _progress_ref.is_finite() or global_position.distance_to(_progress_ref) > stuck_progress_m:
		_progress_ref = global_position
		_progress_t = 0.0
		return
	_progress_t += delta
	if _progress_t < stuck_s:
		return
	_progress_t = 0.0
	if _stuck_stage == 0:
		_stuck_stage = 1
		nav.target_position = unit.react_target if reacting else unit.order_target
		_unstick_left = unstick_s
	else:
		_finish(remaining, reacting)


func _finish(remaining: float, reacting: bool) -> void:
	if reacting:
		# The order is untouched; the AI decides what the arrival (or failure) means.
		unit.react_state = UnitState.ReactState.ARRIVED if remaining <= react_arrive_distance + 0.8 else UnitState.ReactState.FAILED
		_applied_target = Vector3.INF
		return
	_finish_order(remaining)


func _finish_order(remaining: float) -> void:
	unit.order = UnitState.Order.NONE
	unit.move_state = UnitState.MoveState.ARRIVED if remaining <= blocked_distance else UnitState.MoveState.BLOCKED
	unit.anchor_pos = global_position
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
		_set_viewmodel(controlled)
	if unit:
		unit.player_controlled = controlled


# --- First-person weapon (COMBAT-01a) ------------------------------------------------

## LMB fire (held = automatic when the rifle is in auto), R reload, V fire mode, RMB aim.
## The shot leaves from the eye along the view; CombatSim resolves it like any other.
func _player_weapon(delta: float) -> void:
	if unit == null or not unit.alive or sim == null:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not require_mouse_capture
	var held := Input.is_action_pressed("fire")
	if not captured:
		_trigger_armed = false
	elif not held:
		_trigger_armed = true
	var aiming := captured and Input.is_action_pressed("aim")
	if viewmodel:
		viewmodel.aiming = aiming
	camera.fov = lerpf(camera.fov, 42.0 if aiming else _fov_hip, clampf(delta * 12.0, 0.0, 1.0))
	if not captured:
		return
	if Input.is_action_just_pressed("reload"):
		sim.combat.request_reload(unit.id)
	if Input.is_action_just_pressed("fire_mode"):
		sim.combat.set_fire_mode(unit.id, not unit.fire_auto)
	if not _trigger_armed or not held:
		return
	if not unit.fire_auto and not Input.is_action_just_pressed("fire"):
		return
	var shot := sim.combat.request_fire(unit.id, camera.global_position, -camera.global_basis.z, CombatSim.Source.PLAYER)
	if shot.get("fired", false):
		_recoil()


func _recoil() -> void:
	var def := sim.combat.weapon(unit.weapon_id)
	if def == null:
		return
	head.rotation.x = clampf(head.rotation.x + deg_to_rad(def.recoil_pitch_deg), -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))
	rotate_y(deg_to_rad(randf_range(-def.recoil_yaw_deg, def.recoil_yaw_deg)))
	if viewmodel:
		viewmodel.kick()


func _set_viewmodel(on: bool) -> void:
	if on and viewmodel == null and unit and unit.weapon_id != &"":
		viewmodel = Viewmodel.new()
		viewmodel.loadout = InfantryLoadout.by_id(unit.loadout if unit.loadout != "" else InfantryLoadout.default_for(unit.id, unit.faction))
		viewmodel.faction = unit.faction
		camera.add_child(viewmodel)
		camera.near = 0.03
		_fov_hip = camera.fov
	elif not on and viewmodel:
		viewmodel.queue_free()
		viewmodel = null
		camera.fov = _fov_hip


## Where shots visibly leave this soldier: the first-person muzzle while possessed, else
## the muzzle of the carbine held by the character (the placeholder model's carbine
## when the character is disabled).
func muzzle_position() -> Vector3:
	if viewmodel and player_controlled:
		return viewmodel.muzzle.global_position
	var tip := character.muzzle() if character else null
	if tip:
		return tip.global_position
	return global_transform * Vector3(0.03, 1.22, -0.80)


static func ensure_combat_actions() -> void:
	var keys := {"reload": KEY_R, "fire_mode": KEY_V}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)
	var buttons := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for action in buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var mb := InputEventMouseButton.new()
			mb.button_index = buttons[action]
			InputMap.action_add_event(action, mb)

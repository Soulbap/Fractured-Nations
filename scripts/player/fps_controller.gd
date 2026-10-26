## First-person body for WORLD-TECH-01 exploration.
##
## Movement is driven by a "move intent" (wish direction, sprint, jump) that is read
## from the keyboard only while player_controlled is true. Later, the soldier-control
## system can set the intent from AI or RTS orders and switch which body the player
## possesses without changing the physics code here.
class_name FPSController
extends CharacterBody3D

signal possession_changed(controlled: bool)

@export var player_controlled := true:
	set(value):
		player_controlled = value
		if is_inside_tree():
			_update_mouse_mode()
		possession_changed.emit(value)

@export_group("Movement")
@export var walk_speed := 4.5
@export var sprint_speed := 7.5
@export var acceleration := 10.0
@export var air_control := 0.25
@export var jump_velocity := 4.8
## Steepest walkable slope; Terrain3D steeper than this makes the player slide.
@export_range(0.0, 89.0) var max_slope_deg := 46.0

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var max_pitch_deg := 88.0

@export_group("Debug fly")
## Noclip flight for inspecting large maps. Toggle with F.
@export var fly_speed := 30.0
@export var fly_boost := 6.0

@export_group("Safety")
## Respawn if the body falls below this height (e.g. off the map edge).
@export var kill_height := -200.0

## Desired movement in local XZ (x = strafe, y = forward), -1..1.
var move_intent := Vector2.ZERO
## COMBAT-01: share of the walk / sprint speed the body may use (crouched, prone, getting down) and whether it may sprint
## or jump (set by the owner every tick; 1 / true for a plain explorer).
var speed_scale := 1.0
var may_sprint := true
var sprint_intent := false
var jump_intent := false
var flying := false

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _spawn: Transform3D


func _ready() -> void:
	ensure_input_actions()
	floor_max_angle = deg_to_rad(max_slope_deg)
	floor_snap_length = 0.6
	floor_constant_speed = true
	floor_block_on_wall = true
	_spawn = global_transform
	_update_mouse_mode()


func _unhandled_input(event: InputEvent) -> void:
	if not player_controlled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * mouse_sensitivity,
				-deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))
	elif GameController.current == null and event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif GameController.current == null and event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("toggle_fly"):
		set_flying(not flying)


func _physics_process(delta: float) -> void:
	if player_controlled:
		_read_player_intent()
	if flying:
		_fly(delta)
	else:
		_walk(delta)
	jump_intent = false
	if global_position.y < kill_height:
		respawn()


func set_flying(enabled: bool) -> void:
	flying = enabled
	$CollisionShape3D.disabled = enabled
	velocity = Vector3.ZERO


func respawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO


func teleport(pos: Vector3, yaw := NAN) -> void:
	global_position = pos
	if not is_nan(yaw):
		rotation.y = yaw
	velocity = Vector3.ZERO


func _read_player_intent() -> void:
	move_intent = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	sprint_intent = Input.is_action_pressed("sprint")
	if Input.is_action_just_pressed("jump"):
		jump_intent = true


func _walk(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif jump_intent and may_sprint:
		velocity.y = jump_velocity
	var wish := (transform.basis * Vector3(move_intent.x, 0, -move_intent.y))
	wish.y = 0
	wish = wish.normalized() * (sprint_speed if sprint_intent and may_sprint else walk_speed) * speed_scale * minf(move_intent.length(), 1.0)
	var control := 1.0 if is_on_floor() else air_control
	var horiz := Vector3(velocity.x, 0, velocity.z).lerp(wish, clampf(acceleration * control * delta, 0.0, 1.0))
	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()


func _fly(delta: float) -> void:
	var dir := camera.global_basis * Vector3(move_intent.x, 0, -move_intent.y)
	if Input.is_action_pressed("jump") and player_controlled:
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL) and player_controlled:
		dir += Vector3.DOWN
	var speed := fly_speed * (fly_boost if sprint_intent else 1.0)
	global_position += dir.normalized() * speed * delta if dir.length() > 0.01 else Vector3.ZERO


func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# GAMEPLAY-02 (controls): in the game the mouse mode is GameController's policy; a body only asks it to look again
	# (a soldier body streamed in used to free the captured mouse, the world's exploration body captured it at launch).
	if GameController.current != null:
		GameController.current.refresh_mouse()
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if player_controlled else Input.MOUSE_MODE_VISIBLE


## Registers default bindings when the project has none, so the controller works in
## any scene without editing project settings by hand.
static func ensure_input_actions() -> void:
	var binds := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "toggle_fly": [KEY_F],
	}
	for action in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

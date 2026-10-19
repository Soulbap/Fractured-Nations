## Tactical (RTS) camera rig: a focus point on the ground, a yaw and a zoom distance.
##
## Pan with the movement keys (speed scales with zoom), rotate with Q/E or middle-mouse
## drag, zoom with the wheel. Pitch steepens as the camera rises so close views look
## along the ground and far views look down. The rig never touches the world state; it
## is one of two cameras looking at the same scene.
class_name RTSCamera
extends Node3D

@export var terrain: Terrain3D
@export var zoom_min := 12.0
@export var zoom_max := 700.0
@export var zoom_factor := 1.15
## Pan speed as a fraction of the zoom distance per second.
@export var pan_speed := 0.9
@export var rotate_speed := 1.8
@export var drag_sensitivity := 0.005
@export var pitch_near_deg := 28.0
@export var pitch_far_deg := 65.0
@export var ground_clearance := 3.0
## Focus is clamped to this half extent (map half size) when > 0.
@export var map_half_size := 0.0

var focus := Vector3.ZERO
var yaw := 0.0
var zoom := 70.0
var active := false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	FPSController.ensure_input_actions()
	GameController.ensure_input_actions()
	set_process(false)
	set_process_unhandled_input(false)


func set_active(on: bool) -> void:
	active = on
	set_process(on)
	set_process_unhandled_input(on)
	if on:
		camera.make_current()
		_update_transform()


## Centers the view on a position; keeps the current zoom unless one is given.
func frame(pos: Vector3, p_yaw: float, p_zoom := -1.0) -> void:
	focus = pos
	yaw = p_yaw
	if p_zoom > 0.0:
		zoom = clampf(p_zoom, zoom_min, zoom_max)
	_update_transform()


func _process(delta: float) -> void:
	var pan := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if pan != Vector2.ZERO:
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var boost := 2.5 if Input.is_action_pressed("sprint") else 1.0
		focus += (fwd * pan.y + right * pan.x) * pan_speed * zoom * boost * delta
	var rot := Input.get_axis("rts_rotate_right", "rts_rotate_left")
	if rot != 0.0:
		yaw += rot * rotate_speed * delta
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(zoom / zoom_factor, zoom_min)
			_update_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(zoom * zoom_factor, zoom_max)
			_update_transform()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		yaw -= event.relative.x * drag_sensitivity
		_update_transform()


func _ground_height(p: Vector3) -> float:
	if terrain == null:
		return NAN
	return terrain.data.get_height(p)


func _update_transform() -> void:
	if map_half_size > 0.0:
		var lim := map_half_size - 10.0
		focus.x = clampf(focus.x, -lim, lim)
		focus.z = clampf(focus.z, -lim, lim)
	var h := _ground_height(focus)
	if not is_nan(h):
		focus.y = h
	var t := log(zoom / zoom_min) / log(zoom_max / zoom_min)
	var pitch := deg_to_rad(lerpf(pitch_near_deg, pitch_far_deg, clampf(t, 0.0, 1.0)))
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var pos := focus + back * cos(pitch) * zoom + Vector3.UP * sin(pitch) * zoom
	var gh := _ground_height(pos)
	if not is_nan(gh) and pos.y < gh + ground_clearance:
		pos.y = gh + ground_clearance
	camera.global_position = pos
	camera.look_at(focus, Vector3.UP)

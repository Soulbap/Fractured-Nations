## Chase camera for driving a vehicle directly (LOGISTICS-01).
##
## Third person behind the vehicle (heading smoothed so it does not snap in a turn, right
## mouse drag to look around, wheel to zoom) or a bumper view (V). No interior: an external
## camera is all a military truck needs. Reads the vehicle record; owns no vehicle state.
class_name DriveCamera
extends Node3D

var camera: Camera3D
var body: VehicleBody
var distance := 16.0
var orbit_yaw := 0.0
var pitch := 0.30
var bumper_view := false
var _follow_yaw := 0.0
var _orbiting := false
var _active := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "DriveCamera"
	camera.far = 6000.0
	camera.fov = 70.0
	add_child(camera)
	set_process(false)
	set_process_unhandled_input(false)


func attach(b: VehicleBody) -> void:
	body = b
	_follow_yaw = b.unit.yaw
	orbit_yaw = 0.0
	_active = true
	set_process(true)
	set_process_unhandled_input(true)
	camera.make_current()
	_update(1.0)


func detach() -> void:
	_active = false
	body = null
	_orbiting = false
	set_process(false)
	set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance * 0.9, 7.0, 50.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance * 1.1, 7.0, 50.0)
	elif event is InputEventMouseMotion and _orbiting:
		orbit_yaw -= event.relative.x * 0.005
		pitch = clampf(pitch + event.relative.y * 0.004, 0.05, 1.2)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V:
		bumper_view = not bumper_view
		orbit_yaw = 0.0


func _process(delta: float) -> void:
	if _active and body and is_instance_valid(body):
		_update(delta)


func _update(delta: float) -> void:
	var u := body.unit
	var def := u.veh.def()
	# The camera heading trails the vehicle's, and recentres slowly when the player stops looking around.
	_follow_yaw = lerp_angle(_follow_yaw, u.yaw, clampf(delta * 3.0, 0.0, 1.0))
	if not _orbiting:
		orbit_yaw = lerpf(orbit_yaw, 0.0, clampf(delta * 0.8, 0.0, 1.0))
	var yaw := _follow_yaw + orbit_yaw
	if bumper_view:
		var fwd := Vector3(-sin(u.yaw), 0.0, -cos(u.yaw))
		var eye := u.position + fwd * (def.length * 0.5 - 1.8) + Vector3.UP * 3.3
		var look := Vector3(-sin(u.yaw + orbit_yaw), -0.06, -cos(u.yaw + orbit_yaw))
		camera.global_position = eye
		camera.look_at(eye + look * 20.0, Vector3.UP)
		return
	var centre := u.position + Vector3.UP * 2.3
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var pos := centre + back * distance * cos(pitch) + Vector3.UP * distance * sin(pitch)
	var g := body.ground_height(pos)
	pos.y = maxf(pos.y, g + 1.2)
	camera.global_position = pos
	camera.look_at(centre, Vector3.UP)

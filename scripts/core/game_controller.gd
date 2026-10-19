## Switches between first-person control of one soldier and the tactical camera.
##
## Possession is an override layer on top of the simulation: the possessed soldier's
## body reads the player's input instead of its navigation agent, everything else
## continues. Switching cameras changes nothing in WorldState except the unit's
## player_controlled flag; positions, orders and ids are untouched. The terrain LOD,
## vegetation streaming and grass follow whichever camera is current.
class_name GameController
extends Node

signal mode_changed(mode: int)
signal possessed_changed(unit_id: int)

enum Mode { FPS, RTS }

@export var sim: WorldSim
@export var rts_camera: RTSCamera
@export var rts: RTSController
@export var terrain: Terrain3D
## Tree/rock colliders are streamed around this body (the possessed soldier).
@export var collider_streamer: InstanceColliderStreamer
@export var diagnostics: WorldDiagnostics

var mode := Mode.RTS
## Unit the player controls in FPS and returns to from RTS (-1 = none yet).
var possessed_id := -1


func _ready() -> void:
	ensure_input_actions()
	if rts:
		rts.possess_requested.connect(possess)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_perspective"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if mode == Mode.FPS:
		enter_rts()
	else:
		var id := rts.first_selected_soldier() if rts else -1
		if id < 0:
			id = possessed_id
		if id > 0:
			possess(id)


## Takes direct control of a soldier and switches to its first-person camera.
func possess(id: int) -> bool:
	var body := sim.body_of(id) as SoldierBody
	if body == null:
		return false
	if possessed_id != id and possessed_id > 0:
		var old := sim.body_of(possessed_id) as SoldierBody
		if old:
			old.player_controlled = false
	possessed_id = id
	if rts:
		rts.set_active(false)
	rts_camera.set_active(false)
	body.player_controlled = true
	body.camera.make_current()
	_set_active_camera(body.camera)
	if collider_streamer:
		collider_streamer.target = body
	if diagnostics:
		diagnostics.player = body
	mode = Mode.FPS
	mode_changed.emit(mode)
	possessed_changed.emit(id)
	return true


## Releases the possessed soldier to the simulation and switches to the tactical camera
## framed on it. The soldier keeps its id, position and (suspended) order.
func enter_rts() -> void:
	var body := possessed_body()
	if body:
		body.player_controlled = false
		rts_camera.frame(body.global_position, body.rotation.y)
	rts_camera.set_active(true)
	_set_active_camera(rts_camera.camera)
	if rts:
		rts.set_active(true)
	mode = Mode.RTS
	mode_changed.emit(mode)


func possessed_body() -> SoldierBody:
	return sim.body_of(possessed_id) as SoldierBody if possessed_id > 0 else null


func _set_active_camera(cam: Camera3D) -> void:
	if terrain:
		terrain.set_camera(cam)


static func ensure_input_actions() -> void:
	var binds := {
		"toggle_perspective": [KEY_TAB], "possess": [KEY_P, KEY_ENTER], "halt": [KEY_H],
		"rts_rotate_left": [KEY_Q], "rts_rotate_right": [KEY_E],
	}
	for action in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("select_all"):
		InputMap.add_action("select_all")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_A
		ev.ctrl_pressed = true
		InputMap.action_add_event("select_all", ev)

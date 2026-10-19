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
@export var rts: RTSController:
	set(v):
		rts = v
		if v and not v.possess_requested.is_connected(possess):
			v.possess_requested.connect(possess)
@export var terrain: Terrain3D
## Tree/rock colliders are streamed around this body (the possessed soldier).
@export var collider_streamer: InstanceColliderStreamer
@export var diagnostics: WorldDiagnostics
## Large world only: keeps detail (bodies, navmesh, collision) around the active camera.
@export var detail: DetailManager

## Large world only: named places the player can jump to, [{name, position}].
var sites: Array[Dictionary] = []

var mode := Mode.RTS
## Unit the player controls in FPS and returns to from RTS (-1 = none yet).
var possessed_id := -1


func _ready() -> void:
	ensure_input_actions()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_perspective"):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("possess_next") and not sites.is_empty():
		possess_next()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and not sites.is_empty():
		var i: int = event.physical_keycode - KEY_1
		if i >= 0 and i < sites.size():
			jump_to_site(i)
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
	var unit := sim.state.get_unit(id)
	if unit == null or unit.kind != UnitState.Kind.SOLDIER:
		return false
	var body := sim.body_of(id) as SoldierBody
	if body == null and detail:
		# The unit is in the abstract tier: build the detailed world around it first.
		detail.activate_at(unit.position)
		body = sim.body_of(id) as SoldierBody
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
	mode = Mode.FPS
	body.camera.make_current()
	_set_active_camera(body.camera)
	if collider_streamer and not detail:
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
	mode = Mode.RTS
	_set_active_camera(rts_camera.camera)
	if rts:
		rts.set_active(true)
	mode_changed.emit(mode)


## Possesses the soldier after the current one in id order, wherever it is in the world.
func possess_next(step := 1) -> bool:
	var ids: Array = []
	for u in sim.state.soldiers():
		ids.append(u.id)
	if ids.is_empty():
		return false
	var i := ids.find(possessed_id)
	return possess(ids[posmod(i + step, ids.size())])


## First person: possess the soldier nearest to the site. Tactical: move the camera there.
func jump_to_site(index: int) -> bool:
	if index < 0 or index >= sites.size():
		return false
	var pos: Vector3 = sites[index].position
	if mode == Mode.RTS:
		rts_camera.frame(pos, rts_camera.yaw)
		return true
	var best := -1
	var best_d := INF
	for u in sim.state.soldiers():
		var d := Vector2(u.position.x - pos.x, u.position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = u.id
	return best > 0 and possess(best)


func possessed_body() -> SoldierBody:
	return sim.body_of(possessed_id) as SoldierBody if possessed_id > 0 else null


func _set_active_camera(cam: Camera3D) -> void:
	if terrain:
		# Terrain3D builds dynamic collision around this camera. In the tactical view
		# the camera hovers up to hundreds of meters from the ground it is looking at, so
		# the large world points it at an invisible anchor on the focus point instead.
		terrain.set_camera(detail.anchor_cam if detail and mode == Mode.RTS else cam)


static func ensure_input_actions() -> void:
	var binds := {
		"toggle_perspective": [KEY_TAB], "possess": [KEY_P, KEY_ENTER], "halt": [KEY_H],
		"rts_rotate_left": [KEY_Q], "rts_rotate_right": [KEY_E], "possess_next": [KEY_N],
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

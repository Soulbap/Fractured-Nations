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
signal possessed_died(unit_id: int)
## LOGISTICS-01: the player took the wheel of a vehicle (id) or left it (-1).
signal driving_changed(unit_id: int)

enum Mode { FPS, RTS, DRIVE }

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
## LOGISTICS-01: vehicle the player drives in Mode.DRIVE (-1 = none).
var driving_id := -1
var drive_camera: DriveCamera


func _ready() -> void:
	ensure_input_actions()
	drive_camera = DriveCamera.new()
	drive_camera.name = "DriveCamera"
	add_child(drive_camera)


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
	if mode == Mode.FPS or mode == Mode.DRIVE:
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
	if unit and unit.kind == UnitState.Kind.VEHICLE:
		return drive(id)
	if unit == null or unit.kind != UnitState.Kind.SOLDIER or not unit.alive:
		return false
	# WORLD-SANDBOX-01: in the war the player commands (and possesses) only the player's
	# own faction.
	if not _commandable(unit):
		return false
	var body := sim.body_of(id) as SoldierBody
	if body == null and detail:
		# The unit is in the abstract tier: build the detailed world around it first.
		detail.activate_at(unit.position, id)
		body = sim.body_of(id) as SoldierBody
	if body == null:
		return false
	_leave_driving()
	if possessed_id != id and possessed_id > 0:
		var old := sim.body_of(possessed_id) as SoldierBody
		if old:
			old.player_controlled = false
	possessed_id = id
	# COMBAT-02: the player takes over at once - no AI reaction continues for this soldier.
	unit.clear_reaction()
	sim.brain._searches.erase(id)
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
	if mode == Mode.DRIVE:
		var vu := sim.state.get_unit(driving_id)
		_leave_driving()
		if vu:
			rts_camera.frame(vu.position, vu.yaw)
		rts_camera.set_active(true)
		mode = Mode.RTS
		_set_active_camera(rts_camera.camera)
		if rts:
			rts.set_active(true)
		mode_changed.emit(mode)
		return
	var body := possessed_body()
	if body:
		body.player_controlled = false
		rts_camera.frame(body.global_position, body.rotation.y)
	elif sim.state.get_unit(possessed_id):
		var u := sim.state.get_unit(possessed_id)
		rts_camera.frame(u.position, u.yaw)
	rts_camera.set_active(true)
	mode = Mode.RTS
	_set_active_camera(rts_camera.camera)
	if rts:
		rts.set_active(true)
	mode_changed.emit(mode)


## LOGISTICS-01: takes the wheel of a vehicle. Its order and route are suspended, not lost;
## leaving (Tab) hands the vehicle back to the simulation, which resumes its order.
func drive(id: int) -> bool:
	var unit := sim.state.get_unit(id)
	if unit == null or unit.kind != UnitState.Kind.VEHICLE or not unit.alive or not _commandable(unit):
		return false
	if mode == Mode.DRIVE and driving_id == id:
		return true
	var body := sim.body_of(id) as VehicleBody
	if body == null and detail:
		detail.activate_at(unit.position, id)
		body = sim.body_of(id) as VehicleBody
	if body == null or not sim.vehicles.take_control(id):
		return false
	if mode == Mode.FPS:
		var old := possessed_body()
		if old:
			old.player_controlled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_leave_driving()
	if rts:
		rts.set_active(false)
	rts_camera.set_active(false)
	driving_id = id
	mode = Mode.DRIVE
	drive_camera.attach(body)
	_set_active_camera(drive_camera.camera)
	if collider_streamer and not detail:
		collider_streamer.target = body
	mode_changed.emit(mode)
	driving_changed.emit(id)
	return true


func _leave_driving() -> void:
	if driving_id < 0:
		return
	sim.vehicles.release_control(driving_id)
	drive_camera.detach()
	driving_id = -1
	driving_changed.emit(-1)


func driven_body() -> VehicleBody:
	return sim.body_of(driving_id) as VehicleBody if driving_id > 0 else null


func _physics_process(_delta: float) -> void:
	if mode != Mode.DRIVE or driving_id < 0:
		return
	var u := sim.state.get_unit(driving_id)
	if u == null or u.veh == null:
		return
	var v := u.veh
	v.in_throttle = _axis(KEY_W, KEY_UP) - _axis(KEY_S, KEY_DOWN)
	v.in_steer = _axis(KEY_D, KEY_RIGHT) - _axis(KEY_A, KEY_LEFT)
	v.in_brake = 1.0 if Input.is_key_pressed(KEY_SPACE) else 0.0


static func _axis(k1: Key, k2: Key) -> float:
	return 1.0 if Input.is_key_pressed(k1) or Input.is_key_pressed(k2) else 0.0


## Possesses the soldier after the current one in id order, wherever it is in the world.
func possess_next(step := 1) -> bool:
	var ids: Array = []
	for u in sim.state.soldiers():
		if (u.alive and _commandable(u)) or u.id == possessed_id:
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
		if not u.alive or not _commandable(u):
			continue
		var d := Vector2(u.position.x - pos.x, u.position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = u.id
	return best > 0 and possess(best)


## COMBAT-01a: the possessed soldier died - back to the tactical view, where the player
## can pick another living soldier. Its record stays (a casualty marker in the world).
func on_unit_died(u: UnitState) -> void:
	if u.id == driving_id and mode == Mode.DRIVE:
		enter_rts()
		return
	if u.id != possessed_id:
		return
	if mode == Mode.FPS:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		enter_rts()
	possessed_died.emit(u.id)


func _commandable(u: UnitState) -> bool:
	var war := sim.state.war
	return not war.active or u.faction == war.player_faction


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

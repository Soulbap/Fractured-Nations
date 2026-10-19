## WORLD-CORE-01 playable prototype: one persistent world, FPS and RTS control.
##
## Wraps the WORLD-TECH-02 world scene (terrain, roads, streamed vegetation, grass)
## and adds the simulation layer on top: WorldSim/WorldState, soldier and vehicle
## bodies, a runtime-baked navigation mesh for the playable area, the tactical camera
## and controls, possession and a HUD. The world scene itself is untouched so the
## WORLD-TECH tools keep working on it.
##
## Command line (after "--"): --core-test [--shots]  scripted checks, see CoreSelfTest.
class_name CoreDemo
extends Node3D

const SOLDIER_SCENE := preload("res://scenes/units/soldier.tscn")
const VEHICLE_SCENE := preload("res://scenes/units/vehicle.tscn")

@export var soldiers_per_faction := 8
## Side of the square area around the base site that gets a navigation mesh.
@export var area_size := 420.0
## Index into WorldConfig.base_sites used as the playable area center.
@export var base_site_index := 0
@export var start_in_first_person := true
## Give a few units orders at start so there is movement to observe immediately.
@export var initial_orders := true

@onready var world: Node3D = $World
@onready var sim: WorldSim = $WorldSim
@onready var navigation: AreaNavigation = $Navigation
@onready var units_root: Node3D = $Units
@onready var rts_camera: RTSCamera = $RTSCamera
@onready var rts: RTSController = $RTSController
@onready var game: GameController = $GameController
@onready var hud: GameHUD = $HUD

var terrain: Terrain3D
var config: WorldConfig
var vegetation: VegetationStreamer
var area_center := Vector3.ZERO
var nav_info := {}
var spawn_info := {}
## Keeps the scripted test alive while its coroutine runs (a Callable holds no reference).
var _selftest: CoreSelfTest


func _ready() -> void:
	terrain = world.get_node("Terrain3D")
	config = world.get_node("WorldBuilder").config
	vegetation = world.get_node_or_null("Vegetation")
	var collider_streamer: InstanceColliderStreamer = world.get_node_or_null("InstanceColliderStreamer")
	var diagnostics: WorldDiagnostics = world.get_node_or_null("WorldDiagnostics")
	# The world's free exploration body is replaced by possessable soldiers.
	var old_player := world.get_node_or_null("Player")
	if old_player:
		if diagnostics:
			diagnostics.player = null
		if collider_streamer:
			collider_streamer.target = null
		world.remove_child(old_player)
		old_player.queue_free()
	# Every unit needs ground under it, not only the surroundings of the camera.
	terrain.collision_mode = Terrain3DCollision.FULL_GAME

	sim.terrain = terrain
	navigation.terrain = terrain
	navigation.vegetation = vegetation
	rts_camera.terrain = terrain
	rts_camera.map_half_size = config.half_size()
	rts.rig = rts_camera
	rts.sim = sim
	rts.terrain = terrain
	rts.marker_parent = self
	game.sim = sim
	game.rts_camera = rts_camera
	game.rts = rts
	game.terrain = terrain
	game.collider_streamer = collider_streamer
	game.diagnostics = diagnostics
	hud.game = game
	hud.rts = rts
	hud.sim = sim

	area_center = _base_center()
	_spawn_units()
	var obstacles := []
	for b in sim.bodies.values():
		if b is VehicleBody:
			obstacles.append(b.nav_obstacle())
	nav_info = navigation.bake_area(area_center, area_size, obstacles)
	print("CORE nav: ", JSON.stringify(nav_info))
	print("CORE spawn: ", JSON.stringify(spawn_info))

	if initial_orders:
		_issue_initial_orders()
	var first := _first_soldier_of(0)
	if start_in_first_person and first:
		game.possess(first.id)
	else:
		game.possessed_id = first.id if first else -1
		game.enter_rts()

	var args := OS.get_cmdline_user_args()
	if "--core-test" in args:
		_selftest = CoreSelfTest.new(self)
		_selftest.run.call_deferred(args)


func ground_height(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func on_ground(x: float, z: float, lift := 0.25) -> Vector3:
	return Vector3(x, ground_height(Vector3(x, 0, z)) + lift, z)


func _base_center() -> Vector3:
	var sites: PackedVector3Array = config.base_sites
	var n := sites[clampi(base_site_index, 0, sites.size() - 1)] if sites.size() > 0 else Vector3.ZERO
	var w := config.to_world(Vector2(n.x, n.y))
	return on_ground(w.x, w.y, 0.0)


func _spawn_units() -> void:
	var c := area_center
	# North on the base pad facing the road (north = -Z); South 150 m east, facing west.
	_spawn_faction(0, c + Vector3(0, 0, 10), Vector3(1, 0, 0), 0.0, c + Vector3(-28, 0, 14), 0.0)
	_spawn_faction(1, c + Vector3(150, 0, -40), Vector3(0, 0, 1), PI * 0.5, c + Vector3(175, 0, -22), PI * 0.5)
	spawn_info = {"soldiers": sim.state.count_of(UnitState.Kind.SOLDIER), "vehicles": sim.state.count_of(UnitState.Kind.VEHICLE),
		"bodies": sim.bodies.size(), "area_center": [c.x, c.y, c.z]}


func _spawn_faction(faction: int, origin: Vector3, row_dir: Vector3, yaw: float, vehicle_pos: Vector3, vehicle_yaw: float) -> void:
	var per_row := 4
	var spacing := 3.0
	var back := Vector3(sin(yaw), 0, cos(yaw))
	for i in soldiers_per_faction:
		var col := i % per_row
		var row := i / per_row
		var p := origin + row_dir * ((col - (per_row - 1) * 0.5) * spacing) + back * (row * spacing)
		var state := sim.state.add_unit(UnitState.Kind.SOLDIER, faction, on_ground(p.x, p.z), yaw)
		var body: SoldierBody = SOLDIER_SCENE.instantiate()
		units_root.add_child(body)
		body.bind(state, sim)
	var vstate := sim.state.add_unit(UnitState.Kind.VEHICLE, faction, on_ground(vehicle_pos.x, vehicle_pos.z, 0.0), vehicle_yaw,
		"%s-V%d" % [WorldState.faction_name(faction).left(1), faction + 1])
	var vbody: VehicleBody = VEHICLE_SCENE.instantiate()
	units_root.add_child(vbody)
	vbody.bind(vstate, sim)


func _issue_initial_orders() -> void:
	# A South patrol walks toward the base; two North soldiers walk to the road end.
	var south := sim.state.units_where(func(u: UnitState) -> bool: return u.faction == 1 and u.kind == UnitState.Kind.SOLDIER)
	var ids := []
	for i in mini(4, south.size()):
		ids.append(south[i].id)
	sim.state.issue_group_move(ids, on_ground(area_center.x + 60.0, area_center.z - 55.0), 3.0)
	var north := sim.state.units_where(func(u: UnitState) -> bool: return u.faction == 0 and u.kind == UnitState.Kind.SOLDIER)
	if north.size() >= 3:
		sim.state.issue_group_move([north[1].id, north[2].id], on_ground(area_center.x + 15.0, area_center.z - 75.0), 3.0)


func _first_soldier_of(faction: int) -> UnitState:
	for u in sim.state.all_units():
		if u.faction == faction and u.kind == UnitState.Kind.SOLDIER:
			return u
	return null

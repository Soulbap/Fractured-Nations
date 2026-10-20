## WORLD-CORE-01 playable prototype: one persistent world, FPS and RTS control.
##
## Wraps the WORLD-TECH-02 world scene (terrain, roads, streamed vegetation, grass)
## and adds the simulation layer on top: WorldSim/WorldState, soldier and vehicle
## bodies, a runtime-baked navigation mesh for the playable area, the tactical camera
## and controls, possession and a HUD. The world scene itself is untouched so the
## WORLD-TECH tools keep working on it.
##
## WORLD-CORE-02: when the scene has a DetailManager child (scenes/game/world_core_02.tscn)
## the same game runs on the 20 x 20 km world. Soldiers stand at the three base sites,
## only units near the active camera get bodies, the rest run in the abstract tier, and
## the navmesh and terrain collision follow the camera instead of covering the map.
##
## Command line (after "--"): --core-test [--shots]  scripted checks, see CoreSelfTest;
## --large-test [--shots]  the 20 km checks, see LargeWorldSelfTest; --base-test, see BaseSelfTest;
## --integration-test [--shots]  construction on the reference world, see IntegrationSelfTest;
## --squad-test [--shots]  UNIT-01A squads and orders, see SquadSelfTest.
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
@onready var detail: DetailManager = get_node_or_null("DetailManager")
@onready var structures: StructureManager = get_node_or_null("Structures")
@onready var construction: ConstructionController = get_node_or_null("Construction")

var terrain: Terrain3D
var config: WorldConfig
var vegetation: VegetationStreamer
var area_center := Vector3.ZERO
var nav_info := {}
var spawn_info := {}
## Large world: [{name, position, radius}] from WorldConfig.base_sites.
var sites: Array[Dictionary] = []
## Keeps the scripted test alive while its coroutine runs (a Callable holds no reference).
var _selftest: CoreSelfTest
var _large_selftest: LargeWorldSelfTest
var _base_selftest: BaseSelfTest
var _integration_selftest: IntegrationSelfTest
var _squad_selftest: SquadSelfTest


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
	# Small world: every unit needs ground under it, so collide everywhere. Large world:
	# dynamic collision around the terrain camera (the active observer).
	terrain.collision_mode = Terrain3DCollision.DYNAMIC_GAME if detail else Terrain3DCollision.FULL_GAME

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
	hud.detail = detail
	if structures:
		_setup_construction()
	if detail:
		_start_large_world(collider_streamer)
		return

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
	if structures:
		structures.area_changed.connect(func(_r: Rect2) -> void: _rebake_small_area.call_deferred())
	if "--core-test" in args and not detail:
		_selftest = CoreSelfTest.new(self)
		_selftest.run.call_deferred(args)


## WORLD-BASE-01: placed structures live in sim.state.construction; the manager shows
## and collides them around the camera, the controller is the RTS construction mode.
func _setup_construction() -> void:
	structures.terrain = terrain
	structures.vegetation = vegetation
	structures.sim = sim
	structures.map_half_size = config.half_size()
	structures.grass = world.get_node_or_null("Grass") as GrassLayer
	structures.set_water(world.get_node_or_null("Water"))
	if navigation:
		structures.terrain_edited.connect(navigation.terrain_changed)
	structures.bind_state(sim.state.construction)
	sim.structures = structures
	if construction:
		construction.structures = structures
		construction.rig = rts_camera
		construction.rts = rts
		construction.game = game
		construction.terrain = terrain
		construction.save_path = "user://saves/%s/construction.json" % config.world_name
		construction.world_state = sim.state
		game.mode_changed.connect(func(m: int) -> void:
			if m != GameController.Mode.RTS and construction.active:
				construction.set_active(false))
	hud.construction = construction


## Small world: one fixed navmesh area, rebaked with the structures inside it.
func _rebake_small_area() -> void:
	var obstacles := []
	for b in sim.bodies.values():
		if b is VehicleBody:
			obstacles.append(b.nav_obstacle())
	obstacles.append_array(structures.nav_obstacles(area_center, area_size * 0.5))
	nav_info = navigation.bake_area(area_center, area_size, obstacles)


## 20 km layout: 26 soldiers and 3 vehicles at the three base sites, bodies only near
## the first possessed soldier, everyone else abstract until the camera comes near.
func _start_large_world(collider_streamer: InstanceColliderStreamer) -> void:
	detail.sim = sim
	navigation.cell_size = 0.75
	sim.detail = detail
	detail.navigation = navigation
	detail.terrain = terrain
	detail.game = game
	detail.rts_camera = rts_camera
	detail.collider_streamer = collider_streamer
	detail.units_root = units_root
	game.detail = detail
	hud.detail = detail
	detail.structures = structures
	if structures:
		structures.observer_fn = detail.observer_position
	for i in config.base_sites.size():
		var n := config.base_sites[i]
		var w := config.to_world(Vector2(n.x, n.y))
		var c := on_ground(w.x, w.y, 0.0)
		sites.append({"name": "Site %s" % "ABC"[i], "position": c, "radius": n.z})
	game.sites = sites
	_spawn_large_world()
	detail.create_missing_proxies()
	if initial_orders:
		_issue_large_orders()
	area_center = sites[0].position
	var first := _first_soldier_of(0)
	detail.activate_at(first.position)
	nav_info = detail.last_bake
	print("CORE nav: ", JSON.stringify(nav_info))
	print("CORE spawn: ", JSON.stringify(spawn_info))
	if start_in_first_person and first:
		game.possess(first.id)
	else:
		game.possessed_id = first.id if first else -1
		game.enter_rts()
	var args := OS.get_cmdline_user_args()
	if structures:
		structures.area_changed.connect(detail.structures_changed)
		if "--load-construction" in args and construction:
			construction.load_saved()
	if "--large-test" in args:
		_large_selftest = LargeWorldSelfTest.new(self)
		_large_selftest.run.call_deferred(args)
	elif "--squad-test" in args:
		_squad_selftest = SquadSelfTest.new(self)
		_squad_selftest.run.call_deferred(args)
	elif "--integration-test" in args:
		_integration_selftest = IntegrationSelfTest.new(self)
		_integration_selftest.run.call_deferred(args)
	elif "--base-test" in args:
		_base_selftest = BaseSelfTest.new(self)
		_base_selftest.run.call_deferred(args)


func _spawn_large_world() -> void:
	# Site A: 12 North (squads Alpha 8 + Bravo 4). Site B: 8 South (4 in squad Sierra). Site C:
	# 4 North facing 4 South, unorganized. One vehicle each.
	_spawn_group(sites[0].position + Vector3(0, 0, 8), 0, 12, 6, 0.0)
	_spawn_vehicle(sites[0].position + Vector3(-26, 0, 14), 0, 0.0, 0)
	_spawn_group(sites[1].position + Vector3(0, 0, 8), 1, 8, 4, 0.0)
	_spawn_vehicle(sites[1].position + Vector3(24, 0, 12), 1, PI * 0.5, 1)
	_spawn_group(sites[2].position + Vector3(-12, 0, 0), 0, 4, 4, PI * 0.5)
	_spawn_group(sites[2].position + Vector3(12, 0, 0), 1, 4, 4, -PI * 0.5)
	_spawn_vehicle(sites[2].position + Vector3(0, 0, 22), 0, 0.3, 2)
	_make_squads()
	spawn_info = {"soldiers": sim.state.count_of(UnitState.Kind.SOLDIER), "vehicles": sim.state.count_of(UnitState.Kind.VEHICLE),
		"squads": sim.state.squads.size(),
		"sites": sites.map(func(s: Dictionary) -> Array: return [s.position.x, s.position.z])}


## UNIT-01A test squads from the soldiers standing at sites A and B.
func _make_squads() -> void:
	var a: Array = _soldiers_near(sites[0].position)
	sim.state.add_squad("Alpha", 0, a.slice(0, 8).map(func(u: UnitState) -> int: return u.id))
	sim.state.add_squad("Bravo", 0, a.slice(8, 12).map(func(u: UnitState) -> int: return u.id))
	var b: Array = _soldiers_near(sites[1].position)
	# The other four South soldiers at B keep their individual start order (WORLD-CORE-02 test).
	sim.state.add_squad("Sierra", 1, b.slice(4, 8).map(func(u: UnitState) -> int: return u.id))


func _soldiers_near(p: Vector3) -> Array:
	return sim.state.units_where(func(u: UnitState) -> bool:
		return u.kind == UnitState.Kind.SOLDIER and Vector2(u.position.x - p.x, u.position.z - p.z).length() < 60.0)


## Rows of soldiers around origin; yaw 0 faces -Z, rows extend along the facing's right.
func _spawn_group(origin: Vector3, faction: int, count: int, per_row: int, yaw: float) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var back := Vector3(sin(yaw), 0, cos(yaw))
	for i in count:
		var col := i % per_row
		var row := i / per_row
		var p := origin + right * ((col - (per_row - 1) * 0.5) * 3.0) + back * (row * 3.0)
		sim.state.add_unit(UnitState.Kind.SOLDIER, faction, on_ground(p.x, p.z), yaw)


func _spawn_vehicle(pos: Vector3, faction: int, yaw: float, site: int) -> void:
	sim.state.add_unit(UnitState.Kind.VEHICLE, faction, on_ground(pos.x, pos.z, 0.0), yaw,
		"%s-V%d" % ["ABC"[site], site + 1])


## Orders that run from the start: squad Bravo at site A walks 60 m, 4 South soldiers at
## site B walk 300 m (abstract tier, nobody is watching), 3 at site C walk 250 m.
func _issue_large_orders() -> void:
	var by_site := func(i: int) -> Array: return _soldiers_near(sites[i].position)
	for sq: SquadState in sim.state.all_squads():
		if sq.squad_name == "Bravo":
			sim.squads.order_move([sq.id], on_ground(sites[0].position.x + 55.0, sites[0].position.z - 40.0))
	var b: Array = by_site.call(1)
	sim.state.issue_group_move([b[0].id, b[1].id, b[2].id, b[3].id], on_ground(sites[1].position.x - 220.0, sites[1].position.z - 200.0), 3.0)
	var c: Array = by_site.call(2)
	sim.state.issue_group_move([c[0].id, c[1].id, c[4].id], on_ground(sites[2].position.x + 20.0, sites[2].position.z - 250.0), 3.0)


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

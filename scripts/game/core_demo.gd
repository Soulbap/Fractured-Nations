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
## --squad-test [--shots]  UNIT-01A squads and orders, see SquadSelfTest;
## --combat-test [--shots]  COMBAT-01a, see CombatSelfTest; --combat-ai-test [--shots]  COMBAT-01b
## AI firefights, see CombatAISelfTest.
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
var _base01_selftest: Base01SelfTest
var _integration_selftest: IntegrationSelfTest
var _squad_selftest: SquadSelfTest
var _combat_selftest: CombatSelfTest
var _combat_ai_selftest: CombatAISelfTest
var _combat_scale_selftest: CombatScaleSelfTest
var _combat_tactics_selftest: CombatTacticsSelfTest
var _sandbox_selftest: SandboxSelfTest
var _ui01c_selftest: UI01CSelfTest
var _ai_intel_selftest: AIIntelSelfTest
var _ai_squad_selftest: AISquadSelfTest
var _ai_strat_selftest: AIStratSelfTest
var _ai_war_selftest: AIWarSelfTest
var _navigation_n1_selftest: NavigationN1SelfTest
var _navigation_n1b_selftest: NavigationN1BSelfTest
var _navigation_n1c1_perf: NavigationN1C1PerfTest
var _navigation_n1c1_selftest: NavigationN1C1SelfTest
var _ew02_selftest: EW02SelfTest
var _nav_inf01_selftest: NavInf01SelfTest
var _road_quality_selftest: RoadQualitySelfTest
var _nav_perf_bc_selftest: NavPerfBCSelfTest
## NAVIGATION N1-C1: red barrier bars and a label on bridges that are closed or disabled (debug indicator only).
var bridge_markers: BridgeMarkers
var _road_audit: RoadAuditRunner
var _playtest_selftest: PlaytestSelfTest
var _integration03_selftest: Integration03SelfTest
var _logistics_selftest: LogisticsSelfTest
## WORLD-COVER-01: the natural cover layer builder (--build-cover-layer), kept alive while it runs.
var _cover_builder: CoverLayer
var _relief_builder: TerrainRelief
var _gameplay_selftest: GameplaySelfTest
var _campaign_selftest: CampaignSelfTest
## WORLD-SANDBOX-01: true when the game runs the three-faction war (the default).
var sandbox := false
var routes: StrategicRoutes
var strategic_map: StrategicMap
## Scripted tests of earlier milestones keep their fixed layout (no war).
const LEGACY_TESTS: Array[String] = ["--core-test", "--large-test", "--combat-test", "--combat-ai-test", "--combat-scale-test",
	"--combat-tactics-test", "--squad-test", "--integration-test", "--base-test"]
## COMBAT-01a shot effects (muzzle flash, tracer, impact, sound).
var combat_fx: CombatFX
## AI-SQUAD-01: tactical order markers; F7 shows the developer view (fire teams, posts, missions).
var tactics_overlay: TacticsOverlay
## ASSET-INTEGRATION-01: the development armoury (null outside the Development Scenario).
var armoury: DevArmoury
var contact_markers: ContactMarkers
## GAMEPLAY-01B: the scenario the war was started from (New Game, Development Scenario) and the start screen.
var scenario: ScenarioDef
var menu: MainMenu
## The result of Continue ({ok, reason}); empty when the game did not start from a save.
var continue_result := {}
## GAMEPLAY-01G: the in-game menu (Esc) and the request to show the start screen after the scene is reloaded (Main Menu).
var pause_menu: PauseMenu
static var return_to_menu := false
var _pause_mouse := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	terrain = world.get_node("Terrain3D")
	config = world.get_node("WorldBuilder").config
	vegetation = world.get_node_or_null("Vegetation")
	WorldLook.apply(world)
	GroundLook.apply(world)
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
	rts.structures = structures
	rts.drive_requested.connect(game.drive)
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
	_setup_combat()
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
		construction.save_path = save_dir().path_join("construction.json")
		construction.world_state = sim.state
		game.mode_changed.connect(func(m: int) -> void:
			if m != GameController.Mode.RTS and construction.active:
				construction.set_active(false))
	hud.construction = construction


## COMBAT-01a: the combat authority reads world data (terrain, vegetation, structures);
## effects and HUD listen to its events; deaths reach the game and the RTS selection.
func _setup_combat() -> void:
	sim.units_root = units_root
	sim.combat.line.setup(sim.state, terrain, vegetation, structures)
	sim.brain.concealment.setup(world.get_node_or_null("Grass") as GrassLayer, terrain)
	combat_fx = CombatFX.new()
	combat_fx.name = "CombatFX"
	add_child(combat_fx)
	combat_fx.setup(sim, game)
	# Developer switches (AI-SQUAD-01): --legacy-ops makes attack operations walk in as before (diagnostic comparison),
	# --no-squad-ai stops squads choosing tactics on their own.
	var launch_args := OS.get_cmdline_user_args()
	if "--legacy-ops" in launch_args:
		sim.tactics.ops_assault = false
	if "--no-squad-ai" in launch_args:
		sim.tactics.autonomous = false
	# GAMEPLAY-04C: --legacy-aim measures the accuracy arena with the GAMEPLAY-03 aim model (comparison only).
	if "--legacy-aim" in launch_args:
		sim.brain.aim_model = false
	tactics_overlay = TacticsOverlay.new()
	tactics_overlay.name = "TacticsOverlay"
	tactics_overlay.sim = sim
	tactics_overlay.rts = rts
	tactics_overlay.terrain = terrain
	add_child(tactics_overlay)
	# COMBAT-01: what the selected squad knows of the enemy (its soldiers' own perception), in the tactical view.
	contact_markers = ContactMarkers.new()
	contact_markers.name = "ContactMarkers"
	contact_markers.sim = sim
	contact_markers.rts = rts
	contact_markers.game = game
	add_child(contact_markers)
	sim.state.shot_fired.connect(hud.on_shot)
	sim.state.unit_damaged.connect(hud.on_damaged)
	sim.state.unit_died.connect(game.on_unit_died)
	sim.state.unit_died.connect(rts.on_unit_died)
	game.possessed_died.connect(hud.on_possessed_died)


## WORLD-SANDBOX-01: release the streamed ground shapes before the world is torn down
## (freeing them after Terrain3D crashed the engine on exit).
func shutdown_cleanup() -> void:
	# WORLD-COVER-01.1: no navmesh bake may still run on a worker thread when the engine shuts down (it crashed the process
	# after quit, typically after a structure change had started a re-bake).
	if is_instance_valid(navigation):
		navigation.drain()
	if detail and detail.ground:
		var g := detail.ground
		detail.ground = null
		for c in g.get_children():
			c.free()
		g.free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		shutdown_cleanup()


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
	detail.connect_vegetation()
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
	var args := OS.get_cmdline_user_args()
	# WORLD-SANDBOX-01: the game is the three-faction war unless an earlier milestone's
	# scripted test asks for its own fixed layout.
	sandbox = not Array(args).any(func(a: String) -> bool: return LEGACY_TESTS.has(a))
	var resume := false
	if sandbox:
		# GAMEPLAY-01B: the scenario comes from --scenario=<id> / --continue, else (a normal launch) the start screen;
		# scripted tests default to the Development Scenario and never see the menu.
		var choice := _scenario_arg(args)
		if choice == "":
			choice = await _run_menu()
		resume = choice == "continue"
		if resume:
			choice = String(peek_save().get("scenario", "dev"))
		scenario = ScenarioDef.load_id(choice)
		if scenario == null:
			push_error("Unknown scenario '%s': starting the Development Scenario" % choice)
			scenario = ScenarioDef.load_id("dev")
		_start_sandbox()
	else:
		_spawn_large_world()
	detail.create_missing_proxies()
	if initial_orders and not sandbox:
		_issue_large_orders()
	area_center = sites[0].position
	var first := _first_soldier_of(sim.state.war.player_faction if sandbox else 0)
	var start_at := start_focus() if sandbox else first.position
	detail.activate_at(start_at)
	nav_info = detail.last_bake
	print("CORE nav: ", JSON.stringify(nav_info))
	print("CORE spawn: ", JSON.stringify(spawn_info))
	if start_in_first_person and first and not sandbox:
		game.possess(first.id)
	else:
		game.possessed_id = first.id if first else -1
		game.enter_rts()
		if sandbox:
			rts_camera.frame(start_at, 0.0, 120.0)
	if structures:
		structures.area_changed.connect(detail.structures_changed)
		if (resume or "--load-construction" in args) and construction:
			continue_result = construction.load_game()
			if continue_result.ok:
				var at := start_focus()
				detail.activate_at(at)
				rts_camera.frame(at, 0.0, 120.0)
				var back := _first_soldier_of(sim.state.war.player_faction)
				game.possessed_id = back.id if back else -1
			else:
				push_error("Continue failed: %s" % continue_result.reason)
			print("CORE continue: ", JSON.stringify(continue_result))
	if "--large-test" in args:
		_large_selftest = LargeWorldSelfTest.new(self)
		_large_selftest.run.call_deferred(args)
	elif "--combat-tactics-test" in args:
		_combat_tactics_selftest = CombatTacticsSelfTest.new(self)
		_combat_tactics_selftest.run.call_deferred(args)
	elif "--combat-scale-test" in args:
		_combat_scale_selftest = CombatScaleSelfTest.new(self)
		_combat_scale_selftest.run.call_deferred(args)
	elif "--combat-ai-test" in args:
		_combat_ai_selftest = CombatAISelfTest.new(self)
		_combat_ai_selftest.run.call_deferred(args)
	elif "--combat-test" in args:
		_combat_selftest = CombatSelfTest.new(self)
		_combat_selftest.run.call_deferred(args)
	elif "--squad-test" in args:
		_squad_selftest = SquadSelfTest.new(self)
		_squad_selftest.run.call_deferred(args)
	elif "--integration-test" in args:
		_integration_selftest = IntegrationSelfTest.new(self)
		_integration_selftest.run.call_deferred(args)
	elif "--base01-test" in args:
		_base01_selftest = Base01SelfTest.new(self)
		_base01_selftest.run.call_deferred(args)
	elif "--base-test" in args:
		_base_selftest = BaseSelfTest.new(self)
		_base_selftest.run.call_deferred(args)
	elif "--logistics-test" in args:
		_logistics_selftest = LogisticsSelfTest.new(self)
		_logistics_selftest.run.call_deferred(args)
	elif "--integration03-test" in args:
		_integration03_selftest = Integration03SelfTest.new(self)
		_integration03_selftest.run.call_deferred(args)
	elif "--playtest-test" in args:
		_playtest_selftest = PlaytestSelfTest.new(self)
		_playtest_selftest.run.call_deferred(args)
	elif "--ai-intel-test" in args:
		_ai_intel_selftest = AIIntelSelfTest.new(self)
		_ai_intel_selftest.run.call_deferred(args)
	elif "--road-audit" in args:
		_road_audit = RoadAuditRunner.new(self)
		_road_audit.run.call_deferred(args)
	elif "--road-overlay" in args:
		toggle_road_overlay.call_deferred()
	elif "--route-overlay" in args:
		toggle_route_overlay.call_deferred()
	elif "--ai-war-test" in args:
		_ai_war_selftest = AIWarSelfTest.new(self)
		_ai_war_selftest.run.call_deferred(args)
	elif "--nav-perf-bc-test" in args:
		_nav_perf_bc_selftest = NavPerfBCSelfTest.new(self)
		_nav_perf_bc_selftest.run.call_deferred(args)
	elif "--nav-inf-test" in args:
		_nav_inf01_selftest = NavInf01SelfTest.new(self)
		_nav_inf01_selftest.run.call_deferred(args)
	elif "--road-quality-test" in args:
		_road_quality_selftest = RoadQualitySelfTest.new(self)
		_road_quality_selftest.run.call_deferred(args)
	elif "--ew02-test" in args:
		_ew02_selftest = EW02SelfTest.new(self)
		_ew02_selftest.run.call_deferred(args)
	elif "--navigation-n1c1-test" in args:
		_navigation_n1c1_selftest = NavigationN1C1SelfTest.new(self)
		_navigation_n1c1_selftest.run.call_deferred(args)
	elif "--navigation-n1c1-perf" in args:
		_navigation_n1c1_perf = NavigationN1C1PerfTest.new(self)
		_navigation_n1c1_perf.run.call_deferred(args)
	elif "--navigation-n1b-test" in args:
		_navigation_n1b_selftest = NavigationN1BSelfTest.new(self)
		_navigation_n1b_selftest.run.call_deferred(args)
	elif "--navigation-n1-test" in args:
		_navigation_n1_selftest = NavigationN1SelfTest.new(self)
		_navigation_n1_selftest.run.call_deferred(args)
	elif "--combat03-test" in args:
		_ai_strat_selftest = Combat03SelfTest.new(self)
		_ai_strat_selftest.run.call_deferred(args)
	elif "--combat02-test" in args:
		_ai_strat_selftest = Combat02SelfTest.new(self)
		_ai_strat_selftest.run.call_deferred(args)
	elif "--ai-strat-test" in args:
		_ai_strat_selftest = AIStratSelfTest.new(self)
		_ai_strat_selftest.run.call_deferred(args)
	elif "--ai-squad-test" in args or "--squad-demo" in args:
		_ai_squad_selftest = AISquadSelfTest.new(self)
		_ai_squad_selftest.run.call_deferred(args)
	elif "--sandbox-test" in args:
		_sandbox_selftest = SandboxSelfTest.new(self)
		_sandbox_selftest.run.call_deferred(args)
	elif "--campaign-test" in args:
		_campaign_selftest = CampaignSelfTest.new(self)
		_campaign_selftest.run.call_deferred(args)
	elif "--asset-integration-test" in args:
		_gameplay_selftest = AssetIntegrationSelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--combat-polish01-test" in args:
		_gameplay_selftest = CombatPolish01SelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--world-cover11-test" in args:
		_gameplay_selftest = WorldCover11SelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--world-cover-test" in args:
		_gameplay_selftest = WorldCoverSelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--build-terrain-relief" in args:
		_relief_builder = TerrainRelief.new(self)
		_relief_builder.run.call_deferred(args)
	elif "--build-cover-layer" in args:
		_cover_builder = CoverLayer.new(self)
		_cover_builder.run.call_deferred(args)
	elif "--qol011-test" in args:
		_gameplay_selftest = Qol011SelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--qol01-test" in args:
		_gameplay_selftest = Qol01SelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--combat01-test" in args:
		_gameplay_selftest = Combat01SelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--visual03-test" in args:
		_gameplay_selftest = Visual03SelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--visual02-test" in args:
		_gameplay_selftest = Visual02SelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--gameplay05-test" in args:
		_gameplay_selftest = Gameplay05SelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--gameplay04-test" in args:
		_gameplay_selftest = Gameplay04SelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--gameplay01b-test" in args:
		_gameplay_selftest = GameplaySelfTest.new(self)
		_gameplay_selftest.run.call_deferred(args)
	elif "--ui01c2-test" in args:
		_ui01c_selftest = UI01C2SelfTest.new(self)
		_ui01c_selftest.run.call_deferred(args)
	elif "--ui01c-test" in args:
		_ui01c_selftest = UI01CSelfTest.new(self)
		_ui01c_selftest.run.call_deferred(args)


## WORLD-SANDBOX-01: the strategic route grid (cached in user://), the war state and the
## starting forces.
func _start_sandbox() -> void:
	routes = StrategicRoutes.new()
	var src := "res://worlds/%s/source/" % config.world_name
	# WORLD-PLAYTEST-01: one road network for the world roads and the built ones; the route
	# grid follows it.
	sim.state.roads.load_world(src)
	# WORLD-SETTLEMENT-02: the settlement layer's heights and ground paint, before the route grid reads the
	# terrain (its cache has its own name, so switching the layer off never reuses it).
	SettlementLayer.apply_terrain(terrain, config.world_name)
	var layer := "_settlements" if SettlementLayer.enabled(config.world_name) else ""
	# GAMEPLAY-04A: road shoulders eased into the road surface (memory only); the route grid reads the eased terrain.
	if not "--no-road-shoulders" in OS.get_cmdline_user_args():
		# ROAD-QUALITY-01: fitted to the road colliders below Roads; the route grid is cached per shoulder signature (it reads the
		# eased terrain, so a change of the easing must not reuse a grid built on the old one).
		var sh := RoadShoulders.apply(terrain, sim.state.roads, config.world_name, config.vertex_spacing, world.get_node_or_null("Roads"))
		RoadShoulders.refix_loaded(vegetation)
		RoadShoulders.mask_grass(world.get_node_or_null("Grass") as GrassLayer)
		layer += "_shoulders_%s" % sh.get("signature", "")
	# WORLD-COVER-01.1: terrain microrelief (hollows, folds, ditches, banks) added after the shoulders, memory only; the route grid,
	# collision, navmesh and LineOfFire read it, the vegetation on it moves with it.
	if not TerrainRelief.apply(terrain, config.world_name).is_empty():
		TerrainRelief.refix_loaded(vegetation)
		layer += "_relief_%s" % TerrainRelief.signature
	routes.setup(terrain, config.half_size(), src, "user://strategic/%s_grid%s.bin" % [config.world_name, layer], sim.state.roads)
	routes.prebuild_profiles()
	sim.war.setup(routes)
	sim.vehicles.setup(routes)
	bridge_markers = BridgeMarkers.new()
	bridge_markers.name = "BridgeMarkers"
	add_child(bridge_markers)
	bridge_markers.bind(sim.state.roads)
	# WORLD-SANDBOX-01B: normal play starts without the frame-time overlay (F3).
	if game.diagnostics:
		game.diagnostics.set_overlay_visible(false)
	spawn_info = SandboxSetup.create(self, routes, scenario)
	spawn_info["route_grid"] = {"ms": snappedf(routes.build_ms, 0.1), "cached": routes.loaded_from_cache, "size": [routes.size.x, routes.size.y]}
	sim.war.enabled = true
	# The player commands the player's faction only (the AI factions' soldiers can be
	# watched, not ordered or possessed).
	rts.command_any_faction = false
	rts.player_faction = sim.state.war.player_faction
	# Terrain collision streamed in pieces, navmesh source on a worker: no stall when the
	# map jumps the camera or the player possesses a soldier far away.
	var cargs := OS.get_cmdline_user_args()
	if not "--no-ground-stream" in cargs:
		terrain.collision_mode = Terrain3DCollision.DISABLED
		var gs := TerrainCollisionStreamer.new()
		gs.name = "GroundCollision"
		add_child(gs)
		gs.setup(terrain)
		gs.radius = detail.collision_radius
		detail.ground = gs
	navigation.threaded_source = not "--no-thread-nav" in cargs
	# Distant battles are fought at full perception rate: the war's outcome must not depend
	# on where the camera happens to be (COMBAT-02's distance LOD saved ~20 % at 100 v 100).
	sim.brain.distance_lod = false
	_setup_map()
	# ASSET-INTEGRATION-01: the development armoury (F10), in a scenario that asks for it only (the Development Scenario).
	if armoury:
		armoury.queue_free()
		armoury = null
	if DevArmoury.enabled_for(self):
		armoury = DevArmoury.new()
		armoury.name = "DevArmoury"
		armoury.demo = self
		hud.add_child(armoury)


## GAMEPLAY-01B: a scripted test or benchmark is running (a "--...-test" / "-perf" flag, the road audit, the squad demo).
## Its saves go to user://test_saves/, so no test can overwrite the player's game.
static func automated_run() -> bool:
	for a: String in OS.get_cmdline_user_args():
		if a.ends_with("-test") or a.ends_with("-perf") or a in ["--road-audit", "--squad-demo"]:
			return true
	return false


## The one save slot of this world: user://saves/<world> for play, user://test_saves/<world> for tests.
func save_dir() -> String:
	return "user://%s/%s" % ["test_saves" if automated_run() else "saves", config.world_name]


## --scenario=<id> or --continue on the command line; tests and benchmarks default to the Development Scenario;
## "" = ask the player (start screen).
func _scenario_arg(args: PackedStringArray) -> String:
	if return_to_menu:
		# GAMEPLAY-01G: Main Menu from the in-game menu - the start screen again, whatever the command line said.
		return_to_menu = false
		return ""
	if "--menu-shot" in args:
		return ""
	for a in args:
		if a.begins_with("--scenario="):
			return a.substr(11)
		if a == "--continue":
			return "continue"
	if automated_run() or "--load-construction" in args:
		return "dev"
	return ""


## Shows the start screen until the player picks a scenario (or a valid save to continue). Quit ends the program.
func _run_menu() -> String:
	menu = MainMenu.new()
	menu.save_info = peek_save()
	add_child(menu)
	hud.visible = false
	if game.diagnostics:
		game.diagnostics.set_overlay_visible(false)
	# The backdrop: the tactical camera above New Game's start area (before a scenario no camera stands above ground).
	var view: Vector3 = sites[0].position
	var ng := ScenarioDef.load_id("new_game")
	if ng and not ng.start_squads.is_empty():
		view = on_ground(float(ng.start_squads[0].x), float(ng.start_squads[0].z), 0.0)
	rts_camera.set_active(true)
	rts_camera.frame(view + Vector3(250.0, 0.0, -150.0), 0.9, 420.0)
	rts_camera.set_process(false)
	rts_camera.set_process_unhandled_input(false)
	if "--menu-shot" in OS.get_cmdline_user_args():
		_menu_autoplay.call_deferred()
	if PauseMenu.test_quit_on_menu:
		_menu_return_check.call_deferred()
	var action: String = await menu.chosen
	if action == "quit":
		get_tree().quit()
		await get_tree().process_frame
	menu.queue_free()
	menu = null
	hud.visible = true
	rts_camera.set_process(true)
	rts_camera.set_process_unhandled_input(true)
	return action


## --menu-shot (tests): a screenshot of the start screen at the window size, then New Game is pressed through the menu.
func _menu_autoplay() -> void:
	await get_tree().create_timer(3.0).timeout
	if menu == null:
		return
	var size := get_viewport().get_visible_rect().size
	var path := "res://docs/gameplay01b/menu_%dx%d.png" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/gameplay01b"))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("CORE menu shot: %s (canvas %s)" % [path, size])
	menu._choose("new_game")


## GAMEPLAY-01G test: the start screen came back after Main Menu - a screenshot, a line for the test, then quit.
func _menu_return_check() -> void:
	await get_tree().create_timer(4.0).timeout
	if menu == null:
		return
	var path := "res://docs/gameplay01c/g_main_menu_returned.png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("CP menu_return %s" % JSON.stringify({"menu": menu != null, "save_ok": bool(menu.save_info.get("ok", false)), "squads": sim.state.squads.size()}))
	get_tree().quit()


## What the save slot holds, without loading it: {ok, scenario, title, time} or {ok false, missing, reason}. A save that
## exists but cannot be read is reported with its reason (Continue refuses it) instead of being silently replaced.
func peek_save() -> Dictionary:
	var wpath := save_dir().path_join("world.json")
	var cpath := save_dir().path_join("construction.json")
	var has_w := FileAccess.file_exists(wpath)
	var has_c := FileAccess.file_exists(cpath)
	if not has_w and not has_c:
		return {"ok": false, "missing": true, "reason": ""}
	if not has_w or not has_c:
		return {"ok": false, "missing": false, "reason": "the save is incomplete (%s is missing)" % ("world.json" if not has_w else "construction.json")}
	var snap: Variant = str_to_var(FileAccess.get_file_as_string(wpath))
	if not snap is Dictionary or not (snap as Dictionary).has("units") or not (snap as Dictionary).has("war"):
		return {"ok": false, "missing": false, "reason": "world.json is damaged or from an incompatible version"}
	var cons: Variant = JSON.parse_string(FileAccess.get_file_as_string(cpath))
	if not cons is Dictionary or not (cons as Dictionary).has("structures"):
		return {"ok": false, "missing": false, "reason": "construction.json is damaged"}
	var sid := String((snap.war as Dictionary).get("scenario", "dev"))
	var def := ScenarioDef.load_id(sid)
	if def == null:
		return {"ok": false, "missing": false, "reason": "the save is from an unknown scenario '%s'" % sid}
	return {"ok": true, "scenario": sid, "title": def.title, "time": float(snap.get("time", 0.0))}


## Where the camera starts: the player's HQ objective when the scenario says so and he holds it, else the centre of his
## first squad (New Game: no HQ), else the first base site.
func start_focus() -> Vector3:
	var war := sim.state.war
	var f := war.faction(war.player_faction)
	if f and (scenario == null or scenario.camera == "hq"):
		var hq := war.objective(f.hq_objective)
		if hq and hq.owner == f.id:
			return hq.position
	for sq: SquadState in sim.state.all_squads():
		if sq.faction == war.player_faction and not sq.members.is_empty():
			return sim.war.squad_center(sq)
	var u := _first_soldier_of(war.player_faction)
	return u.position if u else sites[0].position


# --- In-game menu (GAMEPLAY-01G) -----------------------------------------------------------------------------------------

## Esc: pauses the game (the tree, so the simulation stops) and shows the in-game menu; Esc / Resume closes it and gives the
## view back its mouse mode.
func toggle_pause() -> void:
	if pause_menu != null and pause_menu.visible:
		_close_pause()
		return
	if menu != null or not sandbox:
		return
	if pause_menu == null:
		pause_menu = PauseMenu.new()
		pause_menu.name = "PauseMenu"
		add_child(pause_menu)
		pause_menu.chosen.connect(_on_pause_chosen)
	pause_menu.save_info = peek_save()
	pause_menu.refresh()
	pause_menu.say("Game time %s  ·  %s" % [MainMenu._clock(sim.state.time), scenario.title if scenario else ""])
	_pause_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.visible = true
	get_tree().paused = true


func _close_pause() -> void:
	if pause_menu:
		pause_menu.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if game.mode == GameController.Mode.FPS else _pause_mouse


func _on_pause_chosen(action: String) -> void:
	if not is_inside_tree():
		return
	match action:
		"resume":
			_close_pause()
		"save":
			var ok := construction != null and construction.save()
			pause_menu.save_info = peek_save()
			pause_menu.refresh()
			pause_menu.say(construction.message if construction else "Nothing to save", ok)
		"load":
			# The same safe path as Continue / F9: both files are checked before anything is replaced.
			if game.mode != GameController.Mode.RTS:
				game.enter_rts()
			var r := construction.load_game() if construction else {"ok": false, "reason": "no construction system"}
			if r.ok:
				_close_pause()
				var at := start_focus()
				detail.activate_at(at)
				rts_camera.frame(at, 0.0, 120.0)
				var back := _first_soldier_of(sim.state.war.player_faction)
				game.possessed_id = back.id if back else -1
			else:
				pause_menu.say("Cannot load: %s" % r.reason, false)
		"main_menu":
			return_to_menu = true
			get_tree().paused = false
			apply_time_scale(1.0)
			get_tree().reload_current_scene()
		"quit":
			get_tree().quit()


## The strategic map on its own canvas layer above the HUD.
func _setup_map() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.name = "StrategicMapLayer"
	add_child(layer)
	strategic_map = StrategicMap.new()
	strategic_map.visible = false
	layer.add_child(strategic_map)
	strategic_map.setup(self)
	strategic_map.closed.connect(_on_map_closed)
	hud.war_sim = sim.war


## M: the strategic map. From first person the game goes to the tactical view first (the
## map commands the faction; the soldier returns to the simulation like on Tab).
func toggle_map() -> void:
	if strategic_map == null:
		return
	if strategic_map.visible:
		strategic_map.close()
		return
	if game.mode != GameController.Mode.RTS:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		game.enter_rts()
	if construction and construction.active:
		construction.set_active(false)
	rts.set_active(false)
	rts_camera.set_process(false)
	rts_camera.set_process_unhandled_input(false)
	# QOL-01: the map opens with the tactical view's squads selected, and hands its selection back when it closes.
	strategic_map.select_squads_from(rts.selected_squads())
	strategic_map.visible = true
	if sim.state.war.active:
		sim.state.war.guide["map"] = true  # GAMEPLAY-04A: the introduction notes that the map was used
	strategic_map.grab_focus()


func _on_map_closed() -> void:
	var sel := strategic_map.selected_squads.duplicate()
	if not sel.is_empty() and sel != rts.selected_squads():
		rts.select_squads(sel)
	if game.mode == GameController.Mode.RTS:
		rts_camera.set_active(true)
		rts.set_active(true)


## Time compression for the long marches of the war: 1, 2, 4, 8 x (first person: 1 x).
## Godot's time_scale alone stretches every physics step (8 x = 0.13 s steps: coarser
## movement, fewer shots); here the tick rate rises with it, so each step stays 1/60 s and
## the simulation is the same as at 1 x, only more of it per second (if the CPU cannot keep
## up, the war simply runs a little slower than the nominal factor).
func set_time_speed(step: int) -> void:
	var levels := [1.0, 2.0, 4.0, 8.0, 16.0]
	var i := levels.find(Engine.time_scale)
	i = clampi((i if i >= 0 else 0) + step, 0, levels.size() - 1)
	if game.mode == GameController.Mode.FPS:
		i = 0
	apply_time_scale(levels[i])


static func apply_time_scale(k: float) -> void:
	TimeCompression.apply(k)


## F8: the road audit overlay (disconnected networks, repaired gaps, near misses, unreachable places); a second press hides
## it, the next one rebuilds it from the current roads.
var _road_overlay: RoadAuditOverlay
## NAV-PERF-01B: route planning overlay (F6, or `--route-overlay`).
var _route_overlay: RouteServiceOverlay


func toggle_route_overlay() -> void:
	if _route_overlay != null and is_instance_valid(_route_overlay):
		_route_overlay.queue_free()
		_route_overlay = null
		return
	_route_overlay = RouteServiceOverlay.new(sim)
	add_child(_route_overlay)


func toggle_road_overlay() -> void:
	if _road_overlay != null and is_instance_valid(_road_overlay):
		_road_overlay.queue_free()
		_road_overlay = null
		return
	_road_overlay = RoadAuditOverlay.new(sim)
	add_child(_road_overlay)
	_road_overlay.rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F6:
		toggle_route_overlay()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		toggle_road_overlay()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7 and tactics_overlay:
		tactics_overlay.debug = not tactics_overlay.debug
		get_viewport().set_input_as_handled()
		return
	if not sandbox or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_M:
			toggle_map()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if strategic_map and strategic_map.visible:
				strategic_map.close()
				get_viewport().set_input_as_handled()
			elif menu == null:
				toggle_pause()
				get_viewport().set_input_as_handled()
		KEY_COMMA:
			set_time_speed(-1)
			get_viewport().set_input_as_handled()
		KEY_PERIOD:
			set_time_speed(1)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	TimeCompression.sample(sim.state.time)
	# First person always runs in real time.
	if sandbox and game.mode != GameController.Mode.RTS and Engine.time_scale != 1.0:
		apply_time_scale(1.0)


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
	sim.combat.equip_all(&"rifle")
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
	sim.combat.equip_all(&"rifle")
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

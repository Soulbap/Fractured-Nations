## Headless world build: terrain relief -> roads + terrain flattening -> vegetation
## (chunk files, grass mask, forest tint), then saves terrain data and writes the world scene.
##
## Usage (after "--"):
##   --config=res://worlds/test_2km/world_config.tres   build from an existing config
##   --name=scale_8km --size=8192 [--spacing=1.0] [--region=1024]
##        [--grass-extent=2048] [--veg-extent=8192]
##                                                      create a config from defaults
##   --no-roads  --no-vegetation                        skip stages
##   --no-scene                                         only rebuild terrain data
##
##   Godot_console.exe --headless --path . --script res://tools/build_world.gd -- --config=...
extends SceneTree

const PLAYER_SCENE := "res://scenes/player/fps_player.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var t_start := Time.get_ticks_msec()
	var opts := _parse_args()
	var cfg := _load_or_create_config(opts)
	print("BUILD world=%s size=%.0fm spacing=%.2fm region=%d" % [
		cfg.world_name, cfg.snapped_size(), cfg.vertex_spacing, cfg.region_size])
	_ensure_player_scene()

	var root := Node3D.new()
	root.name = "World_" + cfg.world_name
	get_root().add_child(root)
	_add_environment(root)

	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	root.add_child(terrain)
	terrain.owner = root
	var roads := Node3D.new()
	roads.name = "Roads"
	root.add_child(roads)
	roads.owner = root

	var builder := WorldBuilder.new()
	builder.name = "WorldBuilder"
	builder.config = cfg
	builder.terrain = terrain
	builder.road_parent = roads
	root.add_child(builder)
	builder.owner = root

	builder.setup_terrain()
	builder.generate_terrain()

	if not opts.has("no-roads") and cfg.main_road.size() > 1:
		var t := Time.get_ticks_msec()
		await builder.build_roads(root)
		for i in 10:
			await physics_frame
		builder.flatten_roads()
		for i in 5:
			await physics_frame
		print("BUILD roads + flatten: %d ms" % (Time.get_ticks_msec() - t))
	if not opts.has("no-vegetation"):
		builder.scatter_vegetation()

	var dir := cfg.data_directory()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var t_save := Time.get_ticks_msec()
	terrain.data.save_directory(dir)
	print("BUILD saved terrain data to %s in %d ms" % [dir, Time.get_ticks_msec() - t_save])
	var world_dir := dir.get_base_dir()
	# Save as standalone resources and make the scene reference them instead of
	# embedding copies, so they can be edited (and shared) independently.
	for pair in [[terrain.assets, "terrain_assets.tres"], [terrain.material, "terrain_material.tres"]]:
		var path: String = world_dir + "/" + pair[1]
		ResourceSaver.save(pair[0], path)
		pair[0].take_over_path(path)

	if not opts.has("no-scene"):
		_add_gameplay_nodes(root, cfg, terrain)
		var scene_path := "res://scenes/world/%s.tscn" % cfg.world_name
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scene_path.get_base_dir()))
		_strip_generated_owners(root)
		var ps := PackedScene.new()
		var err := ps.pack(root)
		if err == OK:
			err = ResourceSaver.save(ps, scene_path)
		print("BUILD scene %s err=%d" % [scene_path, err])
	print("BUILD done in %d ms" % (Time.get_ticks_msec() - t_start))
	quit()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _load_or_create_config(opts: Dictionary) -> WorldConfig:
	if opts.has("config"):
		return load(opts.config)
	var cfg := WorldConfig.new()
	cfg.world_name = opts.get("name", "test_2km")
	cfg.world_size_m = float(opts.get("size", 2048))
	cfg.vertex_spacing = float(opts.get("spacing", 1.0))
	cfg.grass_extent_m = float(opts.get("grass-extent", 0.0))
	cfg.vegetation_extent_m = float(opts.get("veg-extent", 0.0))
	cfg.region_size = int(opts.get("region", 1024))
	var path := "res://worlds/%s/world_config.tres" % cfg.world_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	ResourceSaver.save(cfg, path, ResourceSaver.FLAG_CHANGE_PATH)
	return cfg


func _add_environment(root: Node3D) -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.47, 0.70)
	sky_mat.sky_horizon_color = Color(0.68, 0.74, 0.80)
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.70)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.76, 0.84)
	env.fog_density = 0.00035
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.25
	env.ssao_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.3
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)
	we.owner = root
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 350.0
	sun.directional_shadow_blend_splits = true
	root.add_child(sun)
	sun.owner = root


func _add_gameplay_nodes(root: Node3D, cfg: WorldConfig, terrain: Terrain3D) -> void:
	var player: FPSController = load(PLAYER_SCENE).instantiate()
	player.name = "Player"
	root.add_child(player)
	player.owner = root
	# Spawn on the main road near the first base site.
	var spawn2 := cfg.main_road[1] * cfg.half_size() if cfg.main_road.size() > 1 else Vector2.ZERO
	var h: float = terrain.data.get_height(Vector3(spawn2.x, 0, spawn2.y))
	player.position = Vector3(spawn2.x, (0.0 if is_nan(h) else h) + 1.5, spawn2.y)
	player.rotation.y = PI * 0.5 # face east along the road

	var streamer := InstanceColliderStreamer.new()
	streamer.name = "InstanceColliderStreamer"
	root.add_child(streamer)
	streamer.owner = root
	streamer.terrain = terrain
	streamer.target = player
	# Vegetation streamer and camera-local grass (WORLD-TECH-02).
	var builder: WorldBuilder = root.get_node("WorldBuilder")
	builder.ensure_vegetation_nodes(root)

	var diag := WorldDiagnostics.new()
	diag.name = "WorldDiagnostics"
	root.add_child(diag)
	diag.owner = root
	diag.terrain = terrain
	diag.player = player
	diag.collider_streamer = streamer
	diag.config = cfg


## Road meshes are regenerated from RoadPoints on load; don't serialize them.
func _strip_generated_owners(root: Node) -> void:
	for n in root.find_children("*", "", true, false):
		if n.owner == root and n.get_parent() and n.get_parent().has_method("is_road_container") \
				and not (n.has_method("is_road_point") or n.has_method("is_road_intersection")):
			n.owner = null


func _ensure_player_scene() -> void:
	if ResourceLoader.exists(PLAYER_SCENE):
		return
	var body := FPSController.new()
	body.name = "FPSPlayer"
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	body.add_child(col)
	col.owner = body
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.62
	body.add_child(head)
	head.owner = body
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 6000.0
	head.add_child(cam)
	cam.owner = head.owner
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLAYER_SCENE.get_base_dir()))
	var ps := PackedScene.new()
	ps.pack(body)
	ResourceSaver.save(ps, PLAYER_SCENE)
	body.free()

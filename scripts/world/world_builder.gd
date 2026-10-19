## Builds the WORLD-TECH-01 prototype world from a WorldConfig.
##
## Lives in the world scene as an editor tool. Its buttons regenerate the parts of the
## world that are generated (terrain relief, road layout, vegetation scatter); everything
## can then be hand-edited with the Terrain3D and Road Generator editor tools.
## The same code runs headless from res://tools/build_world.gd.
##
## Regeneration is destructive to hand edits in the regenerated layer, so the terrain
## data directory is copied to <data_dir>_backup before any terrain-changing step.
@tool
class_name WorldBuilder
extends Node

const RoadPointScript := preload("res://addons/road-generator/nodes/road_point.gd")
const RoadIntersectionScript := preload("res://addons/road-generator/nodes/road_intersection.gd")
const RoadContainerScript := preload("res://addons/road-generator/nodes/road_container.gd")
const RoadManagerScript := preload("res://addons/road-generator/nodes/road_manager.gd")
const ConnectorScript := preload("res://addons/road-generator/connectors/terrain3d_road_connector.gd")

## Terrain3D mesh asset slots used by the scatter.
const MESH_GRASS := 0
const MESH_CONIFER := 1
const MESH_BROADLEAF := 2
const MESH_BUSH := 3
const MESH_ROCKS: Array[int] = [4, 5, 6]
## Mesh ids whose instances need physics colliders (see InstanceColliderStreamer).
const SOLID_MESHES: Array[int] = [1, 2, 4, 5, 6]

## Distance from an intersection center to its edge RoadPoints, in meters.
const JUNCTION_ARM_M := 16.0

@export var config: WorldConfig
@export var terrain: Terrain3D
@export var road_parent: Node3D

@warning_ignore_start("unused_private_class_variable")
@export_tool_button("Regenerate terrain (destructive)", "Warning") var _btn_terrain = regenerate_terrain
@export_tool_button("Rebuild roads + flatten", "Path3D") var _btn_roads = rebuild_roads
@export_tool_button("Rescatter vegetation", "MultiMeshInstance3D") var _btn_veg = rescatter_vegetation
@export_tool_button("Save terrain data", "Save") var _btn_save = save_terrain
@warning_ignore_restore("unused_private_class_variable")

var _gen: WorldTerrainGenerator
## Road centerlines as arrays of Vector3 (world space), filled by build_roads.
var road_polylines: Array = []


func _generator() -> WorldTerrainGenerator:
	if _gen == null or _gen.cfg != config:
		_gen = WorldTerrainGenerator.new(config)
	return _gen


# ------------------------------------------------------------------------------
# Editor buttons
# ------------------------------------------------------------------------------

func regenerate_terrain() -> void:
	backup_terrain_data()
	generate_terrain()
	save_terrain()


func rebuild_roads() -> void:
	backup_terrain_data()
	await build_roads(get_tree().edited_scene_root if Engine.is_editor_hint() else owner)
	await get_tree().process_frame
	await get_tree().process_frame
	flatten_roads()
	save_terrain()


func rescatter_vegetation() -> void:
	_collect_road_polylines()
	scatter_vegetation()
	save_terrain()


func save_terrain() -> void:
	if terrain and terrain.data:
		terrain.data.save_directory(terrain.data_directory)


func backup_terrain_data() -> void:
	var src := ProjectSettings.globalize_path(terrain.data_directory if terrain else config.data_directory())
	if not DirAccess.dir_exists_absolute(src):
		return
	var dst := src + "_backup"
	DirAccess.make_dir_recursive_absolute(dst)
	for f in DirAccess.get_files_at(src):
		DirAccess.copy_absolute(src.path_join(f), dst.path_join(f))
	print("WorldBuilder: backed up terrain data to ", dst)


# ------------------------------------------------------------------------------
# Terrain
# ------------------------------------------------------------------------------

## Applies config dimensions, texture/mesh assets and material settings to the terrain.
func setup_terrain() -> void:
	terrain.region_size = config.region_size as Terrain3D.RegionSize
	terrain.vertex_spacing = config.vertex_spacing
	# Assets first, so instance data loaded from the directory finds its meshes.
	terrain.assets = make_assets()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(config.data_directory()))
	terrain.data_directory = config.data_directory()
	var mat := terrain.material
	mat.world_background = Terrain3DMaterial.NONE
	mat.auto_shader = true
	# Terrain3D 1.0 autoshader: the overlay is blended in on flat ground and the base
	# shows on slopes (blend = 1 when the normal points straight up).
	mat.set_shader_param("auto_base_texture", WorldTerrainGenerator.TEX_ROCK)
	mat.set_shader_param("auto_overlay_texture", WorldTerrainGenerator.TEX_GRASS)
	mat.set_shader_param("auto_height_reduction", 0.05)
	mat.set_shader_param("auto_slope", 1.2)
	mat.set_shader_param("blend_sharpness", 0.75)
	terrain.collision_mode = Terrain3DCollision.DYNAMIC_GAME
	terrain.collision_radius = 96
	terrain.mesh_lods = 7
	terrain.mesh_size = 48


func generate_terrain() -> void:
	var t0 := Time.get_ticks_msec()
	var imgs := _generator().generate_images()
	var t1 := Time.get_ticks_msec()
	# Remove existing regions so the import fully replaces the old relief.
	for region in terrain.data.get_regions_active():
		terrain.data.remove_region(region, false)
	var hs := config.half_size()
	terrain.data.import_images([imgs[0], imgs[1], null], Vector3(-hs, 0, -hs), 0.0, 1.0)
	terrain.data.calc_height_range(true)
	print("WorldBuilder: generated %dx%d heightmap in %d ms, imported in %d ms (%d regions)" % [
		imgs[0].get_width(), imgs[0].get_height(), t1 - t0, Time.get_ticks_msec() - t1,
		terrain.data.get_region_count()])


func make_assets() -> Terrain3DAssets:
	var a := Terrain3DAssets.new()
	var tex_dir := "res://assets/terrain/textures/"
	a.set_texture(WorldTerrainGenerator.TEX_GRASS, _tex(WorldTerrainGenerator.TEX_GRASS, "Grass", tex_dir + "ground037", Color(0.72, 0.9, 0.55), 0.12))
	a.set_texture(WorldTerrainGenerator.TEX_ROCK, _tex(WorldTerrainGenerator.TEX_ROCK, "Rock", tex_dir + "rock023", Color.WHITE, 0.08))
	a.set_texture(WorldTerrainGenerator.TEX_DIRT, _tex(WorldTerrainGenerator.TEX_DIRT, "Dirt", tex_dir + "dirt_proc", Color.WHITE, 0.15))
	a.set_texture(WorldTerrainGenerator.TEX_DRY_GRASS, _tex(WorldTerrainGenerator.TEX_DRY_GRASS, "Dry grass", tex_dir + "ground037", Color(1.15, 1.0, 0.62), 0.1))

	var veg := "res://assets/vegetation/"
	var grass := Terrain3DMeshAsset.new()
	grass.name = "Grass card"
	grass.id = MESH_GRASS
	grass.generated_type = Terrain3DMeshAsset.TYPE_TEXTURE_CARD
	grass.generated_faces = 2
	grass.generated_size = Vector2(1.1, 0.7)
	grass.height_offset = 0.24
	grass.cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm: StandardMaterial3D = grass.material_override
	gm.albedo_texture = load(veg + "grass_blades.png")
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	gm.alpha_scissor_threshold = 0.4
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.vertex_color_use_as_albedo = true
	gm.roughness = 1.0
	gm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	gm.distance_fade_min_distance = 70.0
	gm.distance_fade_max_distance = 55.0
	grass.lod0_range = 70.0
	a.set_mesh_asset(MESH_GRASS, grass)

	a.set_mesh_asset(MESH_CONIFER, _mesh_asset(MESH_CONIFER, "Conifer", veg + "conifer.tscn", [60.0, 260.0, 1500.0], 1))
	a.set_mesh_asset(MESH_BROADLEAF, _mesh_asset(MESH_BROADLEAF, "Broadleaf", veg + "broadleaf.tscn", [60.0, 260.0, 1500.0], 1))
	a.set_mesh_asset(MESH_BUSH, _mesh_asset(MESH_BUSH, "Bush", veg + "bush.tscn", [45.0, 250.0], 0))
	var rock_names := ["rocka", "rockb", "rockc"]
	for i in 3:
		a.set_mesh_asset(MESH_ROCKS[i], _mesh_asset(MESH_ROCKS[i], "Rock " + "ABC"[i], veg + rock_names[i] + ".tscn", [600.0], 0))
	return a


func _tex(id: int, tex_name: String, base: String, tint: Color, uv_scale: float) -> Terrain3DTextureAsset:
	var t := Terrain3DTextureAsset.new()
	# Terrain3D orders assets by their own id, so it must match the slot.
	t.id = id
	t.name = tex_name
	t.albedo_texture = load(base + "_alb_ht.png")
	t.normal_texture = load(base + "_nrm_rgh.png")
	t.albedo_color = tint
	t.uv_scale = uv_scale
	t.detiling_rotation = 0.15
	return t


func _mesh_asset(id: int, asset_name: String, scene: String, ranges: Array, last_shadow_lod: int) -> Terrain3DMeshAsset:
	var m := Terrain3DMeshAsset.new()
	m.id = id
	m.name = asset_name
	m.scene_file = load(scene)
	for i in ranges.size():
		m.set_lod_range(i, ranges[i])
	m.last_lod = ranges.size() - 1
	m.last_shadow_lod = last_shadow_lod
	m.fade_margin = 8.0
	return m


# ------------------------------------------------------------------------------
# Roads
# ------------------------------------------------------------------------------

## Creates RoadManager > RoadContainer with RoadPoints and RoadIntersections following
## the config's main and branch polylines, plus the Terrain3D connector.
func build_roads(scene_owner: Node) -> void:
	for c in road_parent.get_children():
		road_parent.remove_child(c)
		c.free()
	var manager: Node3D = RoadManagerScript.new()
	manager.name = "RoadManager"
	road_parent.add_child(manager)
	manager.owner = scene_owner
	var container: Node3D = RoadContainerScript.new()
	container.name = "RoadNetwork"
	manager.add_child(container)
	container.owner = scene_owner

	var hs := config.half_size()
	var main_2d: Array[Vector2] = []
	for p in config.main_road:
		main_2d.append(p * hs)
	var junctions := {} # main road point index -> Array of branch paths (world 2D)
	for b in config.branch_roads:
		var idx := int(b[0].x)
		var path: Array[Vector2] = [main_2d[idx]]
		for i in range(1, b.size()):
			path.append(b[i] * hs)
		if not junctions.has(idx):
			junctions[idx] = []
		junctions[idx].append(path)

	# Main road: densify between control points, placing an intersection at junctions
	# with short arms on either side so the intersection polygon stays compact.
	var main_nodes: Array = [] # RoadPoint or RoadIntersection, in order
	var main_line: Array = []
	var inters := {} # idx -> RoadIntersection
	for i in main_2d.size():
		var p := main_2d[i]
		if junctions.has(i):
			var dir_in := (p - main_2d[i - 1]).normalized()
			var dir_out := (main_2d[i + 1] - p).normalized()
			_densify_into(main_nodes, main_line, container, scene_owner, main_line.back() if main_line.size() else main_2d[0], p - dir_in * JUNCTION_ARM_M, false)
			var rp_in := _add_rp(container, scene_owner, p - dir_in * JUNCTION_ARM_M, dir_in, 3.75)
			main_nodes.append(rp_in)
			var inter: Node3D = RoadIntersectionScript.new()
			inter.name = "Junction_%d" % i
			container.add_child(inter)
			inter.owner = scene_owner
			inter.position = _ground(p) + Vector3.UP * 0.25
			inters[i] = inter
			main_nodes.append(inter)
			var rp_out := _add_rp(container, scene_owner, p + dir_out * JUNCTION_ARM_M, dir_out, 3.75)
			main_nodes.append(rp_out)
			main_line.append(p - dir_in * JUNCTION_ARM_M)
			main_line.append(p)
			main_line.append(p + dir_out * JUNCTION_ARM_M)
		else:
			if main_line.size():
				_densify_into(main_nodes, main_line, container, scene_owner, main_line.back(), p, false)
			var dir := (main_2d[mini(i + 1, main_2d.size() - 1)] - main_2d[maxi(i - 1, 0)]).normalized()
			main_nodes.append(_add_rp(container, scene_owner, p, dir, 3.75))
			main_line.append(p)

	# Wait for RoadContainer.setup_road_container (deferred) before connecting.
	await get_tree().process_frame
	_connect_chain(main_nodes)
	road_polylines = [_line3(main_line)]

	for idx in junctions:
		for path: Array[Vector2] in junctions[idx]:
			var j := path[0]
			var first_dir := (path[1] - j).normalized()
			var nodes: Array = []
			var line: Array = [j]
			var start := j + first_dir * JUNCTION_ARM_M
			nodes.append(_add_rp(container, scene_owner, start, first_dir, 3.25, 1.0))
			line.append(start)
			var prev := start
			for k in range(1, path.size()):
				_densify_into(nodes, line, container, scene_owner, prev, path[k], false, 3.25, 1.0)
				var nd := (path[k] - path[k - 1]).normalized()
				nodes.append(_add_rp(container, scene_owner, path[k], nd, 3.25, 1.0))
				line.append(path[k])
				prev = path[k]
			await get_tree().process_frame
			_connect_chain(nodes)
			inters[idx].add_branch(nodes[0])
			road_polylines.append(_line3(line))

	var connector: Node = ConnectorScript.new()
	connector.name = "Terrain3DRoadConnector"
	road_parent.add_child(connector)
	connector.owner = scene_owner
	connector.road_manager = manager
	connector.terrain = terrain
	connector.edge_margin = 1.5
	connector.edge_falloff = 6.0
	print("WorldBuilder: built road network with %d nodes, %d intersections" % [
		container.get_child_count(), inters.size()])


## Runs the Terrain3D connector over every road segment and intersection.
func flatten_roads() -> void:
	var connector := road_parent.get_node_or_null("Terrain3DRoadConnector")
	if connector:
		connector.do_full_refresh()


func _connect_chain(nodes: Array) -> void:
	for i in nodes.size() - 1:
		var a: Node3D = nodes[i]
		var b: Node3D = nodes[i + 1]
		if b.has_method("is_road_intersection"):
			b.add_branch(a)
		elif a.has_method("is_road_intersection"):
			a.add_branch(b)
		else:
			a.connect_roadpoint(RoadPoint.PointInit.NEXT, b, RoadPoint.PointInit.PRIOR)


func _densify_into(nodes: Array, line: Array, container: Node, scene_owner: Node, from: Vector2, to: Vector2,
		include_end: bool, lane_w := 3.75, shoulder := 2.0) -> void:
	var dist := from.distance_to(to)
	var steps := int(floor(dist / config.road_point_spacing_m))
	var dir := (to - from).normalized()
	for s in range(1, steps + (1 if include_end else 0)):
		var p := from + dir * (dist * s / float(steps if steps > 0 else 1))
		if p.distance_to(to) < config.road_point_spacing_m * 0.4 and not include_end:
			continue
		nodes.append(_add_rp(container, scene_owner, p, dir, lane_w, shoulder))
		line.append(p)


func _add_rp(container: Node, scene_owner: Node, p: Vector2, dir: Vector2, lane_w: float, shoulder := 2.0) -> Node3D:
	var rp: Node3D = RoadPointScript.new()
	rp.name = "RP_%03d" % container.get_child_count()
	var dirs: Array[RoadPoint.LaneDir] = [RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD]
	var lane_types: Array[RoadPoint.LaneType] = [RoadPoint.LaneType.TWO_WAY, RoadPoint.LaneType.TWO_WAY]
	rp.traffic_dir = dirs
	rp.lanes = lane_types
	rp.lane_width = lane_w
	rp.shoulder_width_l = shoulder
	rp.shoulder_width_r = shoulder
	rp.prior_mag = config.road_point_spacing_m * 0.3
	rp.next_mag = config.road_point_spacing_m * 0.3
	container.add_child(rp)
	rp.owner = scene_owner
	var pos := _ground(p) + Vector3.UP * 0.25
	# RoadPoints face +Z toward their "next" point.
	var ahead := _ground(p + dir * 6.0) + Vector3.UP * 0.25
	var fwd := (ahead - pos).normalized()
	rp.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), pos)
	return rp


func _ground(p: Vector2) -> Vector3:
	var h: float = terrain.data.get_height(Vector3(p.x, 0, p.y)) if terrain.data.has_regionp(Vector3(p.x, 0, p.y)) else 0.0
	if is_nan(h):
		h = _generator().height_at(p.x, p.y)
	return Vector3(p.x, h, p.y)


func _line3(line: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Vector2 in line:
		out.append(Vector3(p.x, 0, p.y))
	return out


## Rebuilds road_polylines from the RoadPoints in the scene (used when roads were
## hand-edited and vegetation is rescattered).
func _collect_road_polylines() -> void:
	road_polylines.clear()
	if not road_parent:
		return
	for container in road_parent.find_children("*", "Node3D", true, false):
		if not container.has_method("is_road_container"):
			continue
		# Each connected pair of road nodes becomes a two-point polyline.
		for rp in container.get_roadpoints():
			for nxt in [rp.get_next_road_node(), rp.get_prior_road_node()]:
				if nxt:
					road_polylines.append(PackedVector3Array([rp.global_position, nxt.global_position]))


# ------------------------------------------------------------------------------
# Vegetation (Terrain3D instancer)
# ------------------------------------------------------------------------------

func scatter_vegetation() -> void:
	var t0 := Time.get_ticks_msec()
	var inst := terrain.instancer
	for id in [MESH_GRASS, MESH_CONIFER, MESH_BROADLEAF, MESH_BUSH] + MESH_ROCKS:
		inst.clear_by_mesh(id)
	var road_index := _RoadIndex.new(road_polylines, 32.0)
	var gen := _generator()
	var rng := RandomNumberGenerator.new()
	rng.seed = config.world_seed + 100
	var hs := config.half_size() - 4.0
	if config.vegetation_extent_m > 0.0:
		hs = minf(hs, config.vegetation_extent_m * 0.5)
	var data := terrain.data
	var counts := {}
	var max_slope := cos(deg_to_rad(config.max_tree_slope_deg))

	# Trees and forest-edge bushes.
	var trees: Array[Transform3D] = []
	var tree_col := PackedColorArray()
	var broad: Array[Transform3D] = []
	var broad_col := PackedColorArray()
	var bushes: Array[Transform3D] = []
	var bush_col := PackedColorArray()
	var s := config.tree_spacing_m
	var z := -hs
	while z < hs:
		var x := -hs
		while x < hs:
			var p := Vector3(x + rng.randf_range(-0.45, 0.45) * s, 0, z + rng.randf_range(-0.45, 0.45) * s)
			x += s
			var f := gen.forest_value(p.x, p.z)
			if f < config.forest_threshold - 0.15:
				continue
			if _in_base(gen, p) or road_index.distance(p) < config.road_clearance_m:
				continue
			var n := data.get_normal(p)
			if not n.is_finite() or n.y < max_slope:
				continue
			p.y = data.get_height(p)
			var density := clampf((f - config.forest_threshold) * 4.0 + 0.5, 0.0, 1.0)
			if rng.randf() > density:
				# Sparse forest edge: occasional bush.
				if rng.randf() < 0.25:
					bushes.append(_xf(rng, p, 0.7, 1.4, Vector3.UP))
					bush_col.append(_tint(rng, 0.08))
				continue
			# Conifers dominate higher ground, broadleaf the lowlands.
			var conifer_bias := clampf((p.y - config.base_height) / 60.0 + 0.45, 0.1, 0.9)
			if rng.randf() < conifer_bias:
				trees.append(_xf(rng, p, 0.75, 1.35, Vector3.UP))
				tree_col.append(_tint(rng, 0.12))
			else:
				broad.append(_xf(rng, p, 0.8, 1.3, Vector3.UP))
				broad_col.append(_tint(rng, 0.12))
		z += s

	# Roadside vegetation and scattered bushes.
	s = config.bush_spacing_m
	z = -hs
	while z < hs:
		var x := -hs
		while x < hs:
			var p := Vector3(x + rng.randf_range(-0.5, 0.5) * s, 0, z + rng.randf_range(-0.5, 0.5) * s)
			x += s
			if _in_base(gen, p):
				continue
			var d := road_index.distance(p)
			var chance := 0.06
			if d > config.road_clearance_m - 2.0 and d < config.road_clearance_m + 10.0:
				chance = 0.55
			elif d < config.road_clearance_m - 2.0:
				continue
			if rng.randf() > chance:
				continue
			var n := data.get_normal(p)
			if not n.is_finite() or n.y < max_slope:
				continue
			p.y = data.get_height(p)
			bushes.append(_xf(rng, p, 0.6, 1.5, Vector3.UP))
			bush_col.append(_tint(rng, 0.1))
		z += s

	# Rocks on slopes and in the mountains.
	var rocks: Array = [[], [], []]
	var rock_cols: Array = [PackedColorArray(), PackedColorArray(), PackedColorArray()]
	s = config.rock_spacing_m
	z = -hs
	while z < hs:
		var x := -hs
		while x < hs:
			var p := Vector3(x + rng.randf_range(-0.5, 0.5) * s, 0, z + rng.randf_range(-0.5, 0.5) * s)
			x += s
			var n := data.get_normal(p)
			if not n.is_finite():
				continue
			var steep := 1.0 - n.y
			var chance := 0.03 + steep * 2.5 + gen.mountain_mask(p.x, p.z) * 0.2
			if rng.randf() > chance or road_index.distance(p) < 7.0 or _in_base(gen, p):
				continue
			p.y = data.get_height(p) - 0.3
			var k := rng.randi_range(0, 2)
			rocks[k].append(_xf(rng, p, 0.25, 1.6, n))
			rock_cols[k].append(_tint(rng, 0.06))
		z += s

	# Grass cards in patches, kept off steep rock, roads and base pads.
	var grass: Array[Transform3D] = []
	var grass_col := PackedColorArray()
	var patch := FastNoiseLite.new()
	patch.seed = config.world_seed + 7
	patch.frequency = 0.02
	s = config.grass_spacing_m
	var ghs := hs if config.grass_extent_m <= 0.0 else minf(hs, config.grass_extent_m * 0.5)
	z = -ghs
	while z < ghs:
		var x := -ghs
		while x < ghs:
			var p := Vector3(x + rng.randf_range(-0.5, 0.5) * s, 0, z + rng.randf_range(-0.5, 0.5) * s)
			x += s
			if patch.get_noise_2d(p.x, p.z) < -0.15:
				continue
			var n := data.get_normal(p)
			if not n.is_finite() or n.y < 0.9:
				continue
			if road_index.distance(p) < 5.5 or _in_base(gen, p):
				continue
			p.y = data.get_height(p)
			grass.append(_xf(rng, p, 0.7, 1.3, n))
			var dry := gen.field_mask(p.x, p.z)
			grass_col.append(Color(0.95, 1.0, 0.8).lerp(Color(1.25, 1.05, 0.55), dry) * rng.randf_range(0.85, 1.1))
		z += s

	inst.add_transforms(MESH_CONIFER, trees, tree_col, false)
	inst.add_transforms(MESH_BROADLEAF, broad, broad_col, false)
	inst.add_transforms(MESH_BUSH, bushes, bush_col, false)
	for k in 3:
		var arr: Array[Transform3D] = []
		arr.assign(rocks[k])
		inst.add_transforms(MESH_ROCKS[k], arr, rock_cols[k], false)
	inst.add_transforms(MESH_GRASS, grass, grass_col, false)
	inst.update_mmis(true)
	counts = {"conifer": trees.size(), "broadleaf": broad.size(), "bush": bushes.size(),
		"rocks": rocks[0].size() + rocks[1].size() + rocks[2].size(), "grass": grass.size()}
	print("WorldBuilder: scattered vegetation in %d ms: %s" % [Time.get_ticks_msec() - t0, counts])


func _in_base(gen: WorldTerrainGenerator, p: Vector3) -> bool:
	for i in config.base_sites.size():
		if gen.base_mask(i, p.x, p.z) > 0.3:
			return true
	return false


func _xf(rng: RandomNumberGenerator, p: Vector3, smin: float, smax: float, up: Vector3) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	if up != Vector3.UP:
		var axis := Vector3.UP.cross(up)
		if axis.length() > 0.001:
			b = Basis(axis.normalized(), Vector3.UP.angle_to(up)) * b
	return Transform3D(b.scaled(Vector3.ONE * rng.randf_range(smin, smax)), p)


func _tint(rng: RandomNumberGenerator, amount: float) -> Color:
	var v := rng.randf_range(1.0 - amount, 1.0 + amount)
	return Color(v * rng.randf_range(0.95, 1.05), v, v * rng.randf_range(0.9, 1.05))


## Grid-bucketed road segments for fast "distance to nearest road" queries.
class _RoadIndex:
	var cell: float
	var buckets := {}

	func _init(polylines: Array, cell_size: float) -> void:
		cell = cell_size
		for line: PackedVector3Array in polylines:
			for i in line.size() - 1:
				var a := Vector2(line[i].x, line[i].z)
				var b := Vector2(line[i + 1].x, line[i + 1].z)
				var steps := int(ceil(a.distance_to(b) / (cell * 0.5))) + 1
				for s in steps + 1:
					var p := a.lerp(b, float(s) / steps)
					var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
					if not buckets.has(key):
						buckets[key] = []
					buckets[key].append([a, b])

	func distance(p3: Vector3) -> float:
		var p := Vector2(p3.x, p3.z)
		var k := Vector2i(floori(p.x / cell), floori(p.y / cell))
		var best := INF
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var b = buckets.get(k + Vector2i(dx, dy))
				if b == null:
					continue
				for seg in b:
					var q := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
					best = minf(best, p.distance_to(q))
		return best

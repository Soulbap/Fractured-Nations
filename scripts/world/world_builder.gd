## Builds the prototype world from a WorldConfig.
##
## Lives in the world scene as an editor tool. Its buttons regenerate the parts of the
## world that are generated (terrain relief, road layout, vegetation scatter); everything
## can then be hand-edited with the Terrain3D and Road Generator editor tools.
## The same code runs headless from res://tools/build_world.gd.
##
## Regeneration is destructive to hand edits in the regenerated layer, so the terrain
## data directory is copied to <data_dir>_backup before any terrain-changing step.
##
## Vegetation (WORLD-TECH-02): trees, bushes and rocks are scattered deterministically
## per 128 m cell into VegetationChunk files (worlds/<name>/vegetation/), a grass
## exclusion mask is built from roads and base pads, and forest density is baked into
## the Terrain3D color map so forests read at RTS distances without geometry. Grass
## itself is camera-local GPU particles (GrassLayer) and is not stored.
@tool
class_name WorldBuilder
extends Node

const RoadPointScript := preload("res://addons/road-generator/nodes/road_point.gd")
const RoadIntersectionScript := preload("res://addons/road-generator/nodes/road_intersection.gd")
const RoadContainerScript := preload("res://addons/road-generator/nodes/road_container.gd")
const RoadManagerScript := preload("res://addons/road-generator/nodes/road_manager.gd")
const ConnectorScript := preload("res://addons/road-generator/connectors/terrain3d_road_connector.gd")

const GRASS_LAYER_SCENE := "res://scenes/vegetation/grass_layer.tscn"
const LIBRARY_PATH := "res://assets/vegetation/vegetation_library.tres"

## Terrain3D mesh asset slots (kept for hand painting in the editor) and the ids used
## in the vegetation chunks. Grass (0) is no longer stored.
const MESH_GRASS := 0
const MESH_CONIFER := 1
const MESH_BROADLEAF := 2
const MESH_BUSH := 3
const MESH_ROCKS: Array[int] = [4, 5, 6]
## Mesh ids whose instances need physics colliders (see InstanceColliderStreamer).
const SOLID_MESHES: Array[int] = [1, 2, 4, 5, 6]

## Vegetation storage layout. VegetationStreamer must use the same values.
const CHUNK_M := 1024.0
const CELL_M := 128.0
## Grass mask: extra width beyond the road edge, and the soft edge beyond that.
const MASK_ROAD_MARGIN_M := 1.0
const MASK_EDGE_M := 2.5
## Albedo multipliers baked into the Terrain3D color map.
const FOREST_TINT := Color(0.50, 0.55, 0.38)
const DRY_TINT := Color(1.08, 1.0, 0.70)

## Distance from an intersection center to its edge RoadPoints, in meters.
const JUNCTION_ARM_M := 16.0

@export var config: WorldConfig
@export var terrain: Terrain3D
@export var road_parent: Node3D
@export var vegetation: VegetationStreamer
@export var grass: GrassLayer
## Scatter cells on the WorkerThreadPool (reads terrain data concurrently).
@export var threaded_scatter := true
## Explicit one-shot consent to replace existing chunks, which can contain painted instances.
@export var allow_replace_existing_vegetation := false

@warning_ignore_start("unused_private_class_variable")
@export_tool_button("Regenerate terrain (destructive)", "Warning") var _btn_terrain = regenerate_terrain
@export_tool_button("Rebuild roads + flatten", "Path3D") var _btn_roads = rebuild_roads
@export_tool_button("Rescatter vegetation + bake tint", "MultiMeshInstance3D") var _btn_veg = rescatter_vegetation
@export_tool_button("Bake painted instances into cells", "MeshInstance3D") var _btn_bake = bake_painted_instances
@export_tool_button("Save terrain data", "Save") var _btn_save = save_terrain
@warning_ignore_restore("unused_private_class_variable")

var _gen: WorldTerrainGenerator
## Road centerlines as arrays of Vector3 (world space), filled by build_roads.
var road_polylines: Array = []
## Full road width in meters per polyline (same indices as road_polylines).
var road_widths := PackedFloat32Array()

# Scatter job state shared with worker threads (read-only there).
var _sc_cells: Array[Vector2i] = []
var _sc_results: Array = []
var _sc_lock := Mutex.new()
var _sc_road: _RoadIndex
var _sc_mask: VegetationMask
var _sc_max_slope := 0.0
var _sc_hs := 0.0
var _sc_cfg := {}


func _generator() -> WorldTerrainGenerator:
	if _gen == null or _gen.cfg != config:
		_gen = WorldTerrainGenerator.new(config)
	return _gen


func vegetation_directory() -> String:
	return "res://worlds/%s/vegetation" % config.world_name


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
	if not _vegetation_replacement_allowed():
		return
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
	var grass_card := Terrain3DMeshAsset.new()
	grass_card.name = "Grass card"
	grass_card.id = MESH_GRASS
	grass_card.generated_type = Terrain3DMeshAsset.TYPE_TEXTURE_CARD
	grass_card.generated_faces = 2
	grass_card.generated_size = Vector2(1.1, 0.7)
	grass_card.height_offset = 0.24
	grass_card.cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm: StandardMaterial3D = grass_card.material_override
	gm.albedo_texture = load(veg + "grass_blades.png")
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	gm.alpha_scissor_threshold = 0.4
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.vertex_color_use_as_albedo = true
	gm.roughness = 1.0
	gm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	gm.distance_fade_min_distance = 70.0
	gm.distance_fade_max_distance = 55.0
	grass_card.lod0_range = 70.0
	a.set_mesh_asset(MESH_GRASS, grass_card)

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
	road_widths = PackedFloat32Array([3.75 * 2.0 + 2.0 * 2.0])

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
			road_widths.append(3.25 * 2.0 + 1.0 * 2.0)

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


## Rebuilds road_polylines (and widths) from the road nodes in the scene, so hand-edited
## roads are respected when vegetation is rescattered.
func _collect_road_polylines() -> void:
	road_polylines.clear()
	road_widths.clear()
	if not road_parent:
		return
	for container in road_parent.find_children("*", "Node3D", true, false):
		if not container.has_method("is_road_container"):
			continue
		# Each connected pair of road nodes becomes a two-point polyline.
		for rp in container.get_roadpoints():
			var w: float = rp.lane_width * rp.lanes.size() + rp.shoulder_width_l + rp.shoulder_width_r
			for nxt in [rp.get_next_road_node(), rp.get_prior_road_node()]:
				if nxt:
					road_polylines.append(PackedVector3Array([rp.global_position, nxt.global_position]))
					road_widths.append(w)


# ------------------------------------------------------------------------------
# Vegetation (chunk files + exclusion mask + forest tint)
# ------------------------------------------------------------------------------

## Scatters trees, bushes and rocks into VegetationChunk files, builds the grass
## exclusion mask, removes stored Terrain3D instances (the old storage) and bakes the
## forest tint into the color map. Deterministic per cell: the RNG of a cell is seeded
## from the world seed and the cell coordinates, so any cell can be regenerated alone.
func _vegetation_replacement_allowed() -> bool:
	var dir := ProjectSettings.globalize_path(vegetation_directory())
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("veg_") and file.ends_with(".res"):
			if not allow_replace_existing_vegetation:
				push_error("Vegetation scatter cancelled: existing chunks may contain painted instances. Back them up and explicitly enable allow_replace_existing_vegetation before replacing them.")
				return false
			break
	return true


func scatter_vegetation() -> void:
	if not _vegetation_replacement_allowed():
		return
	# Consent is consumed even if a later step fails.
	allow_replace_existing_vegetation = false
	var t0 := Time.get_ticks_msec()
	if road_polylines.is_empty():
		_collect_road_polylines()
	var dir := vegetation_directory()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var mask := build_mask()
	ResourceSaver.save(mask, dir + "/mask.res")
	# Scenes must reference the mask file, not embed a copy of the image.
	mask.take_over_path(dir + "/mask.res")
	var t1 := Time.get_ticks_msec()

	var hs := config.half_size() - 4.0
	if config.vegetation_extent_m > 0.0:
		hs = minf(hs, config.vegetation_extent_m * 0.5)
	_sc_cells.clear()
	var c0 := floori(-hs / CELL_M)
	var c1 := floori((hs - 0.001) / CELL_M)
	for cz in range(c0, c1 + 1):
		for cx in range(c0, c1 + 1):
			_sc_cells.append(Vector2i(cx, cz))
	_sc_results.clear()
	_sc_results.resize(_sc_cells.size())
	_sc_road = _RoadIndex.new(road_polylines, 32.0)
	_sc_mask = mask
	_sc_max_slope = cos(deg_to_rad(config.max_tree_slope_deg))
	_sc_hs = hs
	# Plain copies: reading Resource properties from worker threads is slow and contends.
	_sc_cfg = {"seed": config.world_seed, "tree_s": config.tree_spacing_m, "bush_s": config.bush_spacing_m,
		"rock_s": config.rock_spacing_m, "thr": config.forest_threshold, "clear": config.road_clearance_m,
		"base_h": config.base_height, "sites": config.base_sites.size()}
	_generator()
	if threaded_scatter:
		var task := WorkerThreadPool.add_group_task(_scatter_cell_task, _sc_cells.size(), -1, true, "vegetation cells")
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for i in _sc_cells.size():
			_scatter_cell_task(i)
	var t2 := Time.get_ticks_msec()

	var chunks := {}
	var counts := {}
	for i in _sc_cells.size():
		var by_mesh: Dictionary = _sc_results[i]
		if by_mesh == null or by_mesh.is_empty():
			continue
		var cell := _sc_cells[i]
		var loc := Vector2i(floori(cell.x * CELL_M / CHUNK_M), floori(cell.y * CELL_M / CHUNK_M))
		var ch: VegetationChunk = chunks.get(loc)
		if ch == null:
			ch = VegetationChunk.new()
			ch.location = loc
			ch.chunk_size_m = CHUNK_M
			ch.cell_size_m = CELL_M
			chunks[loc] = ch
		ch.cells[cell] = by_mesh
		for mesh_id in by_mesh:
			counts[mesh_id] = counts.get(mesh_id, 0) + by_mesh[mesh_id].size() / VegetationChunk.FLOATS_PER_INSTANCE
	_sc_results.clear()
	_save_chunks(chunks, true)

	# Stored Terrain3D instances are the old storage; remove them so no MultiMeshes are
	# built for the whole map on load.
	if terrain and terrain.instancer:
		for id in [MESH_GRASS, MESH_CONIFER, MESH_BROADLEAF, MESH_BUSH] + MESH_ROCKS:
			terrain.instancer.clear_by_mesh(id)
	var t3 := Time.get_ticks_msec()
	bake_forest_tint(mask)
	_apply_to_nodes(mask)
	print("WorldBuilder: vegetation in %d ms (mask %d, scatter %d cells %d, chunks+save %d, tint %d): %d chunks, %s" % [
		Time.get_ticks_msec() - t0, t1 - t0, _sc_cells.size(), t2 - t1, t3 - t2, Time.get_ticks_msec() - t3,
		chunks.size(), counts])


## Grass exclusion mask from roads (with their widths) and base pads.
func build_mask() -> VegetationMask:
	var hs := config.half_size()
	# Keep the mask at or below 4096 texels per side (16 MB at 20 km, 5 m texels).
	var texel := maxf(2.0, ceilf(hs * 2.0 / 4096.0))
	var discs := []
	for site in config.base_sites:
		discs.append([Vector2(site.x, site.y) * hs, site.z + config.base_blend_m * 0.6])
	return VegetationMask.build(hs, texel, road_polylines, road_widths, discs, MASK_ROAD_MARGIN_M, MASK_EDGE_M)


## One cell of scatter. Runs on worker threads: only reads shared data.
func _scatter_cell_task(i: int) -> void:
	var cell := _sc_cells[i]
	var gen := _gen
	var data := terrain.data
	var cfg := _sc_cfg
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cfg.seed, cell.x, cell.y])
	var by_mesh := {}
	var x0 := cell.x * CELL_M
	var z0 := cell.y * CELL_M
	var x1 := x0 + CELL_M
	var z1 := z0 + CELL_M
	var lim := _sc_hs

	# Trees and forest-edge bushes.
	var s: float = cfg.tree_s
	var z := ceilf(z0 / s) * s
	while z < z1:
		var x := ceilf(x0 / s) * s
		while x < x1:
			var p := Vector3(x + rng.randf_range(-0.45, 0.45) * s, 0, z + rng.randf_range(-0.45, 0.45) * s)
			x += s
			if absf(p.x) > lim or absf(p.z) > lim:
				continue
			var f := gen.forest_value(p.x, p.z)
			if f < cfg.thr - 0.15:
				continue
			if _in_base_n(gen, p, cfg.sites) or _sc_road.distance(p) < cfg.clear:
				continue
			var n := data.get_normal(p)
			if not n.is_finite() or n.y < _sc_max_slope:
				continue
			p.y = data.get_height(p)
			var density := clampf((f - cfg.thr) * 4.0 + 0.5, 0.0, 1.0)
			if rng.randf() > density:
				# Sparse forest edge: occasional bush.
				if rng.randf() < 0.25:
					VegetationChunk.append_to(by_mesh, MESH_BUSH, _xf(rng, p, 0.7, 1.4, Vector3.UP), _tint(rng, 0.08))
				continue
			# Conifers dominate higher ground, broadleaf the lowlands.
			var conifer_bias := clampf((p.y - cfg.base_h) / 60.0 + 0.45, 0.1, 0.9)
			if rng.randf() < conifer_bias:
				VegetationChunk.append_to(by_mesh, MESH_CONIFER, _xf(rng, p, 0.75, 1.35, Vector3.UP), _tint(rng, 0.12))
			else:
				VegetationChunk.append_to(by_mesh, MESH_BROADLEAF, _xf(rng, p, 0.8, 1.3, Vector3.UP), _tint(rng, 0.12))
		z += s

	# Roadside vegetation and scattered bushes.
	s = cfg.bush_s
	z = ceilf(z0 / s) * s
	while z < z1:
		var x := ceilf(x0 / s) * s
		while x < x1:
			var p := Vector3(x + rng.randf_range(-0.5, 0.5) * s, 0, z + rng.randf_range(-0.5, 0.5) * s)
			x += s
			if absf(p.x) > lim or absf(p.z) > lim or _in_base_n(gen, p, cfg.sites):
				continue
			var d := _sc_road.distance(p)
			var chance := 0.06
			if d > cfg.clear - 2.0 and d < cfg.clear + 10.0:
				chance = 0.55
			elif d < cfg.clear - 2.0:
				continue
			if rng.randf() > chance:
				continue
			var n := data.get_normal(p)
			if not n.is_finite() or n.y < _sc_max_slope:
				continue
			p.y = data.get_height(p)
			VegetationChunk.append_to(by_mesh, MESH_BUSH, _xf(rng, p, 0.6, 1.5, Vector3.UP), _tint(rng, 0.1))
		z += s

	# Rocks on slopes and in the mountains.
	s = cfg.rock_s
	z = ceilf(z0 / s) * s
	while z < z1:
		var x := ceilf(x0 / s) * s
		while x < x1:
			var p := Vector3(x + rng.randf_range(-0.5, 0.5) * s, 0, z + rng.randf_range(-0.5, 0.5) * s)
			x += s
			if absf(p.x) > lim or absf(p.z) > lim:
				continue
			var n := data.get_normal(p)
			if not n.is_finite():
				continue
			var steep := 1.0 - n.y
			var chance := 0.03 + steep * 2.5 + gen.mountain_mask(p.x, p.z) * 0.2
			if rng.randf() > chance or _sc_road.distance(p) < 7.0 or _in_base_n(gen, p, cfg.sites):
				continue
			p.y = data.get_height(p) - 0.3
			var k := rng.randi_range(0, 2)
			VegetationChunk.append_to(by_mesh, MESH_ROCKS[k], _xf(rng, p, 0.25, 1.6, n), _tint(rng, 0.06))
		z += s

	_sc_lock.lock()
	_sc_results[i] = by_mesh
	_sc_lock.unlock()


func _save_chunks(chunks: Dictionary, remove_others: bool) -> void:
	var dir := vegetation_directory()
	var gdir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(gdir)
	if remove_others:
		for f in DirAccess.get_files_at(gdir):
			if f.begins_with("veg_") and f.ends_with(".res"):
				DirAccess.remove_absolute(gdir.path_join(f))
	for loc in chunks:
		var err := ResourceSaver.save(chunks[loc], dir + "/" + VegetationChunk.file_name(loc))
		if err != OK:
			push_error("WorldBuilder: failed to save chunk %s (%d)" % [loc, err])


func _load_chunks() -> Dictionary:
	var out := {}
	var dir := vegetation_directory()
	var gdir := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(gdir):
		return out
	for f in DirAccess.get_files_at(gdir):
		if f.begins_with("veg_") and f.ends_with(".res"):
			var ch: VegetationChunk = ResourceLoader.load(dir + "/" + f, "", ResourceLoader.CACHE_MODE_IGNORE)
			if ch:
				out[ch.location] = ch
	return out


## Moves instances painted with Terrain3D's instancer brush (all mesh ids except the
## grass card) into the vegetation chunks and clears them from the terrain regions.
func bake_painted_instances() -> void:
	var chunks := _load_chunks()
	var moved := 0
	var region_m := terrain.region_size * terrain.vertex_spacing
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		var offset := Vector3(region.location.x * region_m, 0, region.location.y * region_m)
		var inst: Dictionary = region.get_instances()
		for mesh_id in inst:
			if mesh_id == MESH_GRASS:
				continue
			for cell in inst[mesh_id]:
				var xforms: Array = inst[mesh_id][cell][0]
				var colors: PackedColorArray = inst[mesh_id][cell][1]
				for k in xforms.size():
					var xf: Transform3D = xforms[k]
					var g := Transform3D(xf.basis, xf.origin + offset)
					var loc := VegetationChunk.chunk_of(g.origin, CHUNK_M)
					var ch: VegetationChunk = chunks.get(loc)
					if ch == null:
						ch = VegetationChunk.new()
						ch.location = loc
						ch.chunk_size_m = CHUNK_M
						ch.cell_size_m = CELL_M
						chunks[loc] = ch
					ch.add_instance(mesh_id, g, colors[k] if k < colors.size() else Color.WHITE)
					moved += 1
	_save_chunks(chunks, false)
	for id in [MESH_GRASS, MESH_CONIFER, MESH_BROADLEAF, MESH_BUSH] + MESH_ROCKS:
		terrain.instancer.clear_by_mesh(id)
	if vegetation:
		vegetation.chunks.clear()
		vegetation.refresh()
	print("WorldBuilder: baked %d painted instances into %d chunks" % [moved, chunks.size()])


## Bakes forest density (where trees are scattered), slope and the dry fields into the
## Terrain3D color map at 1/8 vertex resolution, so forests remain recognizable from
## RTS distances without rendering trees. Hand-painted color is overwritten.
func bake_forest_tint(mask: VegetationMask = null) -> void:
	var t0 := Time.get_ticks_msec()
	if mask == null:
		mask = load(vegetation_directory() + "/mask.res") if ResourceLoader.exists(vegetation_directory() + "/mask.res") else null
	var gen := _generator()
	var rs := terrain.region_size
	var step := 8
	var n := rs / step
	var spacing := terrain.vertex_spacing
	var region_m := rs * spacing
	var max_slope := cos(deg_to_rad(config.max_tree_slope_deg))
	var inv_run := 1.0 / (2.0 * step * spacing)
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		var ox := region.location.x * region_m
		var oz := region.location.y * region_m
		var hm: Image = region.get_height_map()
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
		for pz in n:
			var vz := pz * step
			for px in n:
				var vx := px * step
				var x := ox + (vx + step * 0.5) * spacing
				var z := oz + (vz + step * 0.5) * spacing
				var f := gen.forest_value(x, z)
				var d := clampf((f - config.forest_threshold) * 4.0 + 0.5, 0.0, 1.0)
				if d > 0.0:
					var gx := (hm.get_pixel(mini(vx + step, rs - 1), vz).r - hm.get_pixel(maxi(vx - step, 0), vz).r) * inv_run
					var gz := (hm.get_pixel(vx, mini(vz + step, rs - 1)).r - hm.get_pixel(vx, maxi(vz - step, 0)).r) * inv_run
					var ny := 1.0 / sqrt(1.0 + gx * gx + gz * gz)
					d *= smoothstep(max_slope - 0.08, max_slope + 0.02, ny)
					if mask:
						d *= 1.0 - mask.value(x, z)
				var dry := gen.field_mask(x, z) * (1.0 - d)
				var c := Color.WHITE.lerp(FOREST_TINT, d).lerp(DRY_TINT, dry * 0.6)
				c.a = 0.5
				img.set_pixel(px, pz, c)
		img.resize(rs, rs, Image.INTERPOLATE_CUBIC)
		img.generate_mipmaps()
		region.set_color_map(img)
		region.set_modified(true)
	terrain.data.update_maps(Terrain3DRegion.TYPE_COLOR, true, true)
	print("WorldBuilder: baked forest tint into %d regions in %d ms" % [
		terrain.data.get_region_count(), Time.get_ticks_msec() - t0])


## Creates the VegetationStreamer and GrassLayer nodes in the world scene if they are
## missing and wires them to this builder and the collider streamer.
func ensure_vegetation_nodes(scene_owner: Node) -> void:
	var root := scene_owner
	if vegetation == null:
		vegetation = root.get_node_or_null("Vegetation")
	if vegetation == null:
		vegetation = VegetationStreamer.new()
		vegetation.name = "Vegetation"
		root.add_child(vegetation)
		vegetation.owner = scene_owner
	vegetation.library = load(LIBRARY_PATH)
	vegetation.data_directory = vegetation_directory()
	vegetation.chunk_size_m = CHUNK_M
	vegetation.cell_size_m = CELL_M
	if grass == null:
		grass = root.get_node_or_null("Grass")
	if grass == null:
		grass = load(GRASS_LAYER_SCENE).instantiate()
		grass.name = "Grass"
		root.add_child(grass)
		grass.owner = scene_owner
	grass.terrain = terrain
	var mask_path := vegetation_directory() + "/mask.res"
	if ResourceLoader.exists(mask_path):
		grass.mask = load(mask_path)
	var streamer: InstanceColliderStreamer = root.get_node_or_null("InstanceColliderStreamer")
	if streamer:
		streamer.vegetation = vegetation


func _apply_to_nodes(mask: VegetationMask) -> void:
	if vegetation:
		vegetation.data_directory = vegetation_directory()
		vegetation.chunks.clear()
		vegetation.refresh()
	if grass:
		grass.mask = mask
		grass.apply_mask()


func _in_base(gen: WorldTerrainGenerator, p: Vector3) -> bool:
	return _in_base_n(gen, p, config.base_sites.size())


func _in_base_n(gen: WorldTerrainGenerator, p: Vector3, sites: int) -> bool:
	for i in sites:
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

## Camera-local GPU particle grass on Terrain3D.
##
## A grid of GPUParticles3D follows the active camera; the particle shader reads the
## terrain height, control and color maps directly, so no grass is stored anywhere and
## the cost does not depend on map size. Derived from Terrain3D's
## extras/particle_example (MIT) with three additions:
##   - exclusion mask (VegetationMask): no grass on roads, base pads and other excluded
##     surfaces, plus thinning under the baked forest tint and on painted dirt,
##   - altitude cutoff: the layer switches off above max_camera_height over the terrain
##     (RTS views), with hysteresis,
##   - Terrain3D map parameters are pushed once and when the data changes, not per frame.
@tool
class_name GrassLayer
extends Node3D

@export var terrain: Terrain3D
@export var mask: VegetationMask
@export var enabled := true:
	set(v):
		enabled = v
		_set_active(false)
		_last_pos = Vector3(INF, INF, INF)
@export_range(0.125, 2.0, 0.015625) var instance_spacing := 0.5
## Width of one GPUParticles3D cell in meters; grid_width cells per side.
@export_range(8.0, 256.0, 1.0) var cell_width := 24.0
@export_range(1, 15, 2) var grid_width := 5
@export_range(1, 256, 1) var process_fixed_fps := 30
@export var process_material: ShaderMaterial
@export var mesh: Mesh
@export var mesh_material_override: Material
@export var shadow_mode: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
## Grass is drawn while the camera is lower than this above the terrain.
@export var max_camera_height := 90.0
@export var height_hysteresis := 12.0

## Rows of particles per cell and particles per cell (derived).
var rows := 1
var amount := 1
var draw_distance := 60.0
## True while the grass is drawn (camera below the altitude cutoff).
var active := false
var camera_height := 0.0
var particle_nodes: Array[GPUParticles3D] = []

var _offsets: Array[Vector3] = []
var _mat: ShaderMaterial
var _last_pos := Vector3(INF, INF, INF)
var _data_connected: Terrain3DData


func _ready() -> void:
	top_level = true
	if not terrain and get_parent() is Terrain3D:
		terrain = get_parent()
	_create_grid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_destroy_grid()


func particle_count() -> int:
	return amount * particle_nodes.size()


func _physics_process(_delta: float) -> void:
	if not enabled or not terrain or not terrain.data or _mat == null:
		return
	_connect_data()
	var cam := _camera()
	if cam == null:
		return
	var cpos := cam.global_position
	var h: float = terrain.data.get_height(cpos)
	camera_height = INF if is_nan(h) else cpos.y - h
	if active and camera_height > max_camera_height + height_hysteresis * 0.5:
		_set_active(false)
	elif not active and camera_height < max_camera_height - height_hysteresis * 0.5:
		_set_active(true)
	if not active:
		return
	if _last_pos.distance_squared_to(cpos) > 1.0:
		var pos := cpos.snapped(Vector3.ONE)
		_position_grid(pos)
		_mat.set_shader_parameter("camera_position", pos)
		_last_pos = cpos


func _camera() -> Camera3D:
	if Engine.is_editor_hint():
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			var vp: SubViewport = ei.get_editor_viewport_3d(0)
			if vp:
				return vp.get_camera_3d()
		return null
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _set_active(v: bool) -> void:
	if v == active:
		return
	active = v
	for p in particle_nodes:
		p.visible = v
		p.emitting = v
	if v:
		_last_pos = Vector3(INF, INF, INF)


func _create_grid() -> void:
	_destroy_grid()
	if process_material == null or mesh == null:
		return
	_mat = process_material.duplicate()
	rows = maxi(int(cell_width / instance_spacing), 1)
	amount = rows * rows
	draw_distance = cell_width * grid_width * 0.5
	var half := grid_width / 2
	_offsets.clear()
	var aabb := AABB(Vector3(-cell_width * 0.5, -2000.0, -cell_width * 0.5), Vector3(cell_width, 6000.0, cell_width))
	var seed0 := 0
	for x in range(-half, half + 1):
		for z in range(-half, half + 1):
			_offsets.append(Vector3(float(x * rows) * instance_spacing, 0.0, float(z * rows) * instance_spacing))
			var p := GPUParticles3D.new()
			p.lifetime = 600.0
			p.amount = amount
			p.explosiveness = 1.0
			p.process_material = _mat
			p.draw_pass_1 = mesh
			p.custom_aabb = aabb
			p.cast_shadow = shadow_mode
			p.fixed_fps = process_fixed_fps
			p.preprocess = 1.0 / float(process_fixed_fps)
			p.material_override = mesh_material_override
			p.use_fixed_seed = true
			if particle_nodes.is_empty():
				seed0 = p.seed
			else:
				p.seed = seed0
			p.visible = false
			p.emitting = false
			add_child(p, false, Node.INTERNAL_MODE_BACK)
			particle_nodes.append(p)
	_mat.set_shader_parameter("instance_spacing", instance_spacing)
	_mat.set_shader_parameter("instance_rows", rows)
	_mat.set_shader_parameter("max_dist", draw_distance)
	_apply_mask()
	active = false
	_last_pos = Vector3(INF, INF, INF)
	if terrain and terrain.data:
		_connect_data()


func _destroy_grid() -> void:
	for p in particle_nodes:
		if is_instance_valid(p):
			p.free()
	particle_nodes.clear()
	if is_instance_valid(_data_connected):
		_data_connected.maps_changed.disconnect(_update_map_parameters)
	_data_connected = null


func _connect_data() -> void:
	if _data_connected == terrain.data:
		return
	if is_instance_valid(_data_connected):
		_data_connected.maps_changed.disconnect(_update_map_parameters)
	_data_connected = terrain.data
	_data_connected.maps_changed.connect(_update_map_parameters)
	_update_map_parameters()


## Pushes the current mask to the particle shader (call after changing `mask`).
func apply_mask() -> void:
	_apply_mask()
	_last_pos = Vector3(INF, INF, INF)


func _apply_mask() -> void:
	if _mat == null:
		return
	if mask and mask.image:
		_mat.set_shader_parameter("exclusion_mask", mask.make_texture())
		_mat.set_shader_parameter("mask_origin", mask.origin)
		_mat.set_shader_parameter("mask_size_m", mask.size_m())
		_mat.set_shader_parameter("mask_enabled", true)
	else:
		_mat.set_shader_parameter("mask_enabled", false)


func _position_grid(pos: Vector3) -> void:
	for i in particle_nodes.size():
		var node := particle_nodes[i]
		var snap := Vector3(pos.x, 0, pos.z).snapped(Vector3.ONE) + _offsets[i]
		node.global_position = (snap / instance_spacing).round() * instance_spacing
		node.reset_physics_interpolation()
		node.restart(true)


## Terrain3D map texture arrays and region layout for the particle shader.
func _update_map_parameters() -> void:
	if _mat == null or not terrain or not terrain.data:
		return
	var data := terrain.data
	var locs := PackedVector2Array()
	for l in data.get_region_locations():
		locs.append(Vector2(l))
	_mat.set_shader_parameter("_background_mode", terrain.material.world_background if terrain.material else 0)
	_mat.set_shader_parameter("_vertex_spacing", terrain.vertex_spacing)
	_mat.set_shader_parameter("_vertex_density", 1.0 / terrain.vertex_spacing)
	_mat.set_shader_parameter("_region_size", float(terrain.region_size))
	_mat.set_shader_parameter("_region_texel_size", 1.0 / float(terrain.region_size))
	_mat.set_shader_parameter("_region_map_size", Terrain3DData.REGION_MAP_SIZE)
	_mat.set_shader_parameter("_region_map", data.get_region_map())
	_mat.set_shader_parameter("_region_locations", locs)
	RenderingServer.material_set_param(_mat.get_rid(), "_height_maps", data.get_height_maps_rid())
	RenderingServer.material_set_param(_mat.get_rid(), "_control_maps", data.get_control_maps_rid())
	RenderingServer.material_set_param(_mat.get_rid(), "_color_maps", data.get_color_maps_rid())

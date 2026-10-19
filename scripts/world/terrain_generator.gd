## Procedural relief for prototype worlds, imported into Terrain3D.
##
## This is not a terrain engine: it only produces height and control images once.
## Terrain3D owns storage, LOD, editing, collision and saving; after import the terrain
## is edited with Terrain3D's own sculpt/paint tools like any hand-made map.
##
## Config values are copied into plain members on construction: reading Resource
## properties per pixel is slow and contends between worker threads.
class_name WorldTerrainGenerator
extends RefCounted

## Terrain3D texture slots used by the generated control map.
const TEX_GRASS := 0
const TEX_ROCK := 1
const TEX_DIRT := 2
const TEX_DRY_GRASS := 3

var cfg: WorldConfig
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _forest := FastNoiseLite.new()

var _hs := 1.0
var _spacing := 1.0
var _base_height := 0.0
var _hills_amp := 0.0
var _detail_amp := 0.0
var _mountain_amp := 0.0
var _mountain_c := Vector2.ZERO # meters
var _mountain_r := 0.0 # meters
var _field_c := Vector2.ZERO # meters
var _field_r := 0.0 # meters
var _field_flatness := 0.0
var _valley_offset := 0.0
var _valley_amp := 0.0
var _valley_freq := 0.0
var _valley_w := 0.0
var _valley_depth := 0.0
var _site_c := PackedVector2Array() # meters
var _site_r := PackedFloat32Array()
var _site_blend := 0.0
var _site_h := PackedFloat32Array()
var _forest_c := Vector2.ZERO

var _rows: Array = []
var _ctrl_rows: Array = []
var _rows_lock := Mutex.new()
var _width := 0


func _init(config: WorldConfig) -> void:
	cfg = config
	_hs = cfg.half_size()
	_spacing = cfg.vertex_spacing
	_base_height = cfg.base_height
	_hills_amp = cfg.hills_amplitude
	_detail_amp = cfg.detail_amplitude
	_mountain_amp = cfg.mountain_amplitude
	_mountain_c = cfg.mountain_center * _hs
	_mountain_r = cfg.mountain_radius * _hs
	_field_c = cfg.field_center * _hs
	_field_r = cfg.field_radius * _hs
	_field_flatness = cfg.field_flatness
	_valley_offset = cfg.valley_offset * _hs
	_valley_amp = cfg.valley_amplitude * _hs
	_valley_freq = PI * cfg.valley_frequency / _hs
	_valley_w = cfg.valley_width_m
	_valley_depth = cfg.valley_depth
	_site_blend = cfg.base_blend_m
	_forest_c = Vector2(-0.5, -0.55) * _hs
	for site in cfg.base_sites:
		_site_c.append(Vector2(site.x, site.y) * _hs)
		_site_r.append(site.z)

	_hills.seed = cfg.world_seed
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = cfg.hills_frequency
	_hills.fractal_octaves = 4
	_detail.seed = cfg.world_seed + 1
	_detail.frequency = cfg.detail_frequency
	_detail.fractal_octaves = 3
	_ridge.seed = cfg.world_seed + 2
	_ridge.frequency = cfg.mountain_frequency
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_forest.seed = cfg.world_seed + 3
	_forest.frequency = cfg.forest_frequency
	_forest.fractal_octaves = 3
	# Base sites are flattened to the height the unflattened terrain has at their center.
	for c in _site_c:
		_site_h.append(_relief(c.x, c.y))


## Height in meters at world position (x, z), including base-site flattening.
func height_at(x: float, z: float) -> float:
	var h := _relief(x, z)
	for i in _site_c.size():
		var m := base_mask(i, x, z)
		if m > 0.0:
			h = lerpf(h, _site_h[i], m)
	return h


## 0..1 weight of base site i at (x, z): 1 inside the radius, easing to 0 over the blend.
func base_mask(i: int, x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(_site_c[i])
	return 1.0 - smoothstep(_site_r[i], _site_r[i] + _site_blend, d)


func field_mask(x: float, z: float) -> float:
	return 1.0 - smoothstep(_field_r * 0.6, _field_r, Vector2(x, z).distance_to(_field_c))


func mountain_mask(x: float, z: float) -> float:
	return 1.0 - smoothstep(_mountain_r * 0.35, _mountain_r, Vector2(x, z).distance_to(_mountain_c))


## 0..1, 1 on the valley floor.
func valley_mask(x: float, z: float) -> float:
	var vz := _valley_offset + _valley_amp * sin(_valley_freq * x)
	return 1.0 - smoothstep(_valley_w * 0.3, _valley_w, absf(z - vz))


## -1..1 forest density noise, biased toward the north-west and the mountain foothills.
func forest_value(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var bias := 0.35 * (1.0 - smoothstep(0.2 * _hs, 0.8 * _hs, p.distance_to(_forest_c)))
	var mm := mountain_mask(x, z)
	bias += 0.25 * mm * (1.0 - mm)
	bias -= 0.6 * field_mask(x, z)
	return _forest.get_noise_2d(x, z) + bias


func _relief(x: float, z: float) -> float:
	var flat := 1.0 - field_mask(x, z) * (1.0 - _field_flatness)
	var h := _base_height
	h += _hills.get_noise_2d(x, z) * _hills_amp * flat
	h += _detail.get_noise_2d(x, z) * _detail_amp * flat
	var mm := mountain_mask(x, z)
	if mm > 0.0:
		var r := _ridge.get_noise_2d(x, z) * 0.5 + 0.5
		h += pow(r, 1.6) * _mountain_amp * mm
	var vm := valley_mask(x, z)
	if vm > 0.0:
		var floor_h := minf(h, _base_height) - _valley_depth
		h = lerpf(h, floor_h, vm * 0.85)
	return h


## Builds [height_image (FORMAT_RF), control_image (FORMAT_RF)] covering the whole map.
## Rows are generated in parallel on the WorkerThreadPool.
func generate_images() -> Array[Image]:
	_width = int(cfg.snapped_size() / _spacing)
	_rows.resize(_width)
	_ctrl_rows.resize(_width)
	var task := WorkerThreadPool.add_group_task(_generate_row, _width, -1, true, "terrain rows")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var heights := PackedFloat32Array()
	var control := PackedFloat32Array()
	for r in _width:
		heights.append_array(_rows[r])
		control.append_array(_ctrl_rows[r])
	_rows.clear()
	_ctrl_rows.clear()
	var h_img := Image.create_from_data(_width, _width, false, Image.FORMAT_RF, heights.to_byte_array())
	var c_img := Image.create_from_data(_width, _width, false, Image.FORMAT_RF, control.to_byte_array())
	return [h_img, c_img]


func _generate_row(row: int) -> void:
	var z := -_hs + row * _spacing
	var heights := PackedFloat32Array()
	var control := PackedFloat32Array()
	heights.resize(_width)
	control.resize(_width)
	var auto_px := Terrain3DUtil.as_float(Terrain3DUtil.enc_auto(true))
	var dirt_px := Terrain3DUtil.as_float(Terrain3DUtil.enc_base(TEX_DIRT))
	var dry_px := Terrain3DUtil.as_float(Terrain3DUtil.enc_base(TEX_DRY_GRASS))
	# Which base sites can influence this row at all.
	var sites: Array[int] = []
	for i in _site_c.size():
		if absf(z - _site_c[i].y) < _site_r[i] + _site_blend:
			sites.append(i)
	var field_row := absf(z - _field_c.y) < _field_r
	for col in _width:
		var x := -_hs + col * _spacing
		var h := _relief(x, z)
		var base := 0.0
		for i in sites:
			var m := base_mask(i, x, z)
			if m > 0.0:
				h = lerpf(h, _site_h[i], m)
				base = maxf(base, m)
		heights[col] = h
		# Default: autoshader (grass on flats, rock on slopes). Base sites get dirt,
		# open fields get dry grass; both remain repaintable with Terrain3D's brushes.
		# Detail noise breaks up the otherwise circular texture borders.
		var edge := _detail.get_noise_2d(x * 3.0, z * 3.0) * 0.3
		if base > 0.55 + edge:
			control[col] = dirt_px
		elif field_row and field_mask(x, z) > 0.5 + edge:
			control[col] = dry_px
		else:
			control[col] = auto_px
	_rows_lock.lock()
	_rows[row] = heights
	_ctrl_rows[row] = control
	_rows_lock.unlock()

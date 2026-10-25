## Terrain "generator" for reference-based worlds: loads the maps written by
## tools/terrain_ref/generate.py instead of computing relief, and answers the per-point
## queries (height, forest density, species shares, rockiness) from them.
class_name ReferenceTerrainGenerator
extends WorldTerrainGenerator

var _src := ""
var _res := 10240
## RGBA8 2048^2: forest density, pine share, birch share, wetness.
var _veg: Image
## RGBA8 2048^2: rockiness, field, settlement, water proximity.
var _info: Image
## VISUAL-02 (cover_v2 worlds only), RGBA8 2048^2: stand age (0 clear-cut .. 1 mature), forest edge band, dryness,
## clear-cut flag. Null in worlds generated without it (the scatter then plants the old way).
var _stand: Image
var _map_px := 2048
var _map_scale := 1.0 # map pixels per metre


func _init(config: WorldConfig) -> void:
	super(config)
	var rc := config as ReferenceWorldConfig
	_src = rc.source_directory
	_res = rc.source_resolution
	_veg = Image.load_from_file(_src.path_join("vegetation.png"))
	_info = Image.load_from_file(_src.path_join("info.png"))
	if FileAccess.file_exists(_src.path_join("stand.png")):
		_stand = Image.load_from_file(_src.path_join("stand.png"))
	if _veg:
		_map_px = _veg.get_width()
	_map_scale = _map_px / cfg.snapped_size()


## Height, control and colour images of the whole map (FORMAT_RF, FORMAT_RF, FORMAT_RGBA8).
func generate_images() -> Array[Image]:
	var out: Array[Image] = []
	for f in [["height.r32", Image.FORMAT_RF], ["control.r32", Image.FORMAT_RF], ["color.rgba8", Image.FORMAT_RGBA8]]:
		var bytes := FileAccess.get_file_as_bytes(_src.path_join(f[0]))
		if bytes.is_empty():
			push_error("ReferenceTerrainGenerator: missing %s in %s (run tools/terrain_ref/generate.py)" % [f[0], _src])
			return []
		out.append(Image.create_from_data(_res, _res, false, f[1], bytes))
	return out


## Bilinear sample of a map image at world (x, z).
func _sample(img: Image, x: float, z: float) -> Color:
	if img == null:
		return Color(0, 0, 0, 0)
	var u := (x + _hs) * _map_scale
	var v := (z + _hs) * _map_scale
	var x0 := clampi(floori(u), 0, _map_px - 2)
	var y0 := clampi(floori(v), 0, _map_px - 2)
	var tx := clampf(u - x0, 0.0, 1.0)
	var ty := clampf(v - y0, 0.0, 1.0)
	var a := img.get_pixel(x0, y0).lerp(img.get_pixel(x0 + 1, y0), tx)
	var b := img.get_pixel(x0, y0 + 1).lerp(img.get_pixel(x0 + 1, y0 + 1), tx)
	return a.lerp(b, ty)


## r = forest density 0..1, g = pine share, b = birch share (rest spruce), a = wetness.
func vegetation_at(x: float, z: float) -> Color:
	return _sample(_veg, x, z)


## r = rockiness, g = field, b = settlement, a = water proximity.
func info_at(x: float, z: float) -> Color:
	return _sample(_info, x, z)


func has_stand() -> bool:
	return _stand != null


## r = stand age (0 clear-cut, ~0.25 regrowth, 1 mature), g = forest edge band, b = dryness, a = clear-cut.
func stand_at(x: float, z: float) -> Color:
	return _sample(_stand, x, z)


## -1..1 like the procedural generator (0.12 + density keeps the old thresholds usable).
func forest_value(x: float, z: float) -> float:
	return vegetation_at(x, z).r * 1.2 - 0.3


func mountain_mask(x: float, z: float) -> float:
	return info_at(x, z).r


func field_mask(x: float, z: float) -> float:
	return info_at(x, z).g


## No generated base pads in reference worlds.
func base_mask(_i: int, _x: float, _z: float) -> float:
	return 0.0


func height_at(x: float, z: float) -> float:
	return _base_height

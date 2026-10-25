## COMBAT-01 grass concealment: how tall the meadow grass stands at a point, read from the same data the grass particles
## are placed with (GrassLayer / grass_particles.gdshader: the noise patches and clods, the forest tint of the colour map,
## the exclusion mask, the painted no-grass texture, the slope) - so what conceals a soldier is what the player sees there,
## everywhere on the map, without a ray or a node. CombatBrain asks it at the staggered perception cadence only, for a
## candidate it can see; the answer is cached per 2 m cell.
##
## It only slows noticing (CombatBrain.acquire_delay): grass never blocks a line of sight or a bullet.
class_name Concealment
extends RefCounted

const CELL := 2.0
const MAX_CACHE := 40000

var terrain: Terrain3D
## The grass layer (its exclusion mask is read at query time: roads and settlements paint it after start-up).
var grass: GrassLayer
var _noise: Image
var _noise_tex: Texture2D
var _p := {"noise_scale": 0.01, "min_y": 0.32, "max_y": 0.6, "clod_boost": 0.35, "clod_min": 0.2, "clod_max": 0.5,
	"patch_min": 0.025, "patch_max": 0.2, "forest_thinning": 0.55, "excluded_id": 2, "slope_min": 0.87}
## Tuft card top above its placement point at scale 1 (the reference world's tuft: -0.45 .. +0.55 m).
var card_top := 0.55
var _cache := {}
var queries := 0


func setup(p_grass: GrassLayer, p_terrain: Terrain3D) -> void:
	terrain = p_terrain
	_cache.clear()
	grass = p_grass
	if grass == null:
		return
	var pm := grass.process_material as ShaderMaterial
	if pm:
		_noise_tex = pm.get_shader_parameter("main_noise") as Texture2D
		var param := func(k: String, fallback: Variant) -> Variant:
			var v: Variant = pm.get_shader_parameter(k)
			return fallback if v == null else v
		_p.noise_scale = float(param.call("main_noise_scale", _p.noise_scale))
		_p.min_y = float((param.call("min_scale", Vector3(0, _p.min_y, 0)) as Vector3).y)
		_p.max_y = float((param.call("max_scale", Vector3(0, _p.max_y, 0)) as Vector3).y)
		_p.clod_boost = float(param.call("clod_scale_boost", _p.clod_boost))
		_p.clod_min = float(param.call("clod_min_threshold", _p.clod_min))
		_p.clod_max = float(param.call("clod_max_threshold", _p.clod_max))
		_p.patch_min = float(param.call("patch_min_threshold", _p.patch_min))
		_p.patch_max = float(param.call("patch_max_threshold", _p.patch_max))
		_p.forest_thinning = float(param.call("forest_thinning", _p.forest_thinning))
		_p.excluded_id = int(param.call("excluded_texture_id", _p.excluded_id))
		_p.slope_min = float(param.call("surface_slope_min", _p.slope_min))
	if grass.mesh:
		card_top = maxf(grass.mesh.get_aabb().end.y, 0.1)


## Mean height (m) of the grass standing at p, times how densely it grows there (0 = bare ground).
func grass_height(p: Vector3) -> float:
	var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if _cache.has(key):
		return _cache[key]
	queries += 1
	var h := _measure(Vector3((key.x + 0.5) * CELL, p.y, (key.y + 0.5) * CELL))
	if _cache.size() >= MAX_CACHE:
		_cache.clear()
	_cache[key] = h
	return h


func _measure(p: Vector3) -> float:
	if terrain == null or terrain.data == null:
		return 0.0
	var data := terrain.data
	var mask: VegetationMask = grass.mask if grass else null
	if mask and mask.image and mask.value(p.x, p.z) > 0.5:
		return 0.0
	var n: Vector3 = data.get_normal(p)
	if not n.is_finite() or n.y < float(_p.slope_min):
		return 0.0
	if not data.get_control_auto(p):
		var base: int = data.get_control_base_id(p)
		var over: int = data.get_control_overlay_id(p)
		var blend: float = data.get_control_blend(p)
		var ex: int = _p.excluded_id
		if ex >= 0 and ((base == ex and blend < 0.7) or (over == ex and blend >= 0.3)):
			return 0.0
	var c: Color = data.get_color(p)
	var lum := c.r * 0.3 + c.g * 0.5 + c.b * 0.2
	var keep := 1.0 - float(_p.forest_thinning) * clampf((1.0 - lum) * 2.2, 0.0, 1.0)
	var noise := _noise_at(p)
	var clods := smoothstep(float(_p.clod_min), float(_p.clod_max), noise) * float(_p.clod_boost)
	var patch := smoothstep(float(_p.patch_min), float(_p.patch_max), noise)
	var scale_y := (float(_p.min_y) + float(_p.max_y)) * 0.5 + clods
	return card_top * scale_y * patch * keep


func _noise_at(p: Vector3) -> float:
	if _noise == null and _noise_tex:
		_noise = _noise_tex.get_image()
		if _noise and _noise.is_compressed():
			_noise = null
	if _noise == null:
		return 0.5
	var w := _noise.get_width()
	var h := _noise.get_height()
	var u := fposmod(p.x * float(_p.noise_scale), 1.0) * w
	var v := fposmod(p.z * float(_p.noise_scale), 1.0) * h
	return _noise.get_pixel(clampi(int(u), 0, w - 1), clampi(int(v), 0, h - 1)).r

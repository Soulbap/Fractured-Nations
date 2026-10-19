## Editor-configurable description of a generated world.
##
## Every dimension of the prototype world lives here instead of being hard-coded, so a
## new map size is a new .tres file, not a code change. Feature positions (mountains,
## valley, fields, base sites, roads) are stored in normalized map coordinates
## (-1..1 on each axis) so the same layout scales with world_size_m. Radii and widths
## are in meters because their physical size should not grow with the map.
##
## World space convention (shared by FPS, RTS and the future 2D map): +X east,
## +Z south, +Y up, 1 unit = 1 meter, map centered on the origin.
@tool
class_name WorldConfig
extends Resource

@export_group("Dimensions")
## Name used for the data directory and scene file.
@export var world_name: String = "test_2km"
## Edge length of the square world in meters. Snapped up to whole Terrain3D regions.
@export_range(256.0, 65536.0, 1.0, "suffix:m") var world_size_m: float = 2048.0
## Meters between terrain vertices. 1.0 = full detail; 2.0 quarters memory for large maps.
@export_range(0.25, 4.0, 0.25, "suffix:m") var vertex_spacing: float = 1.0
## Terrain3D region size in vertices (power of two, 64..2048).
@export_enum("256:256", "512:512", "1024:1024", "2048:2048") var region_size: int = 1024
@export var seed: int = 20261019

@export_group("Relief")
@export var base_height: float = 40.0
@export var hills_amplitude: float = 32.0
## Wavelength of the rolling hills is roughly 1 / frequency meters.
@export var hills_frequency: float = 0.0016
@export var detail_amplitude: float = 2.5
@export var detail_frequency: float = 0.012

@export_group("Mountains")
## Normalized center of the steep ridge area.
@export var mountain_center := Vector2(0.55, -0.5)
## Normalized radius of the ridge area.
@export var mountain_radius: float = 0.55
@export var mountain_amplitude: float = 120.0
@export var mountain_frequency: float = 0.0035

@export_group("Valley")
## Valley centerline: v = offset + amplitude * sin(PI * frequency * u) in normalized coords.
@export var valley_offset: float = 0.05
@export var valley_amplitude: float = 0.22
@export var valley_frequency: float = 1.1
@export var valley_width_m: float = 170.0
@export var valley_depth: float = 18.0

@export_group("Open fields")
@export var field_center := Vector2(-0.45, 0.45)
@export var field_radius: float = 0.42
## Relief multiplier inside fields (0 = flat, 1 = unchanged).
@export_range(0.0, 1.0) var field_flatness: float = 0.18

@export_group("Base sites")
## Flat areas for future military bases: x, y = normalized position, z = radius in meters.
@export var base_sites: PackedVector3Array = PackedVector3Array([
	Vector3(-0.52, 0.58, 110.0), Vector3(0.22, 0.48, 85.0), Vector3(-0.32, -0.48, 75.0)])
@export var base_blend_m: float = 55.0

@export_group("Roads")
## Main road polyline in normalized coordinates (west to east).
@export var main_road: PackedVector2Array = PackedVector2Array([
	Vector2(-0.96, 0.02), Vector2(-0.70, 0.14), Vector2(-0.42, 0.22), Vector2(-0.18, 0.20),
	Vector2(0.05, 0.10), Vector2(0.30, 0.02), Vector2(0.55, 0.08), Vector2(0.78, 0.22),
	Vector2(0.96, 0.30)])
## Branch roads. The first point of each branch is the index (as x) of the main road
## point that becomes an intersection; remaining points are the normalized path.
@export var branch_roads: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(2, 0), Vector2(-0.44, 0.38), Vector2(-0.50, 0.50)]),
	PackedVector2Array([Vector2(4, 0), Vector2(0.10, -0.15), Vector2(-0.10, -0.32), Vector2(-0.30, -0.42)]),
	PackedVector2Array([Vector2(6, 0), Vector2(0.45, 0.30), Vector2(0.27, 0.44)]),
]
## Interval between generated RoadPoints along each polyline.
@export var road_point_spacing_m: float = 70.0

@export_group("Vegetation")
@export var forest_frequency: float = 0.0025
## Higher = less forest. Noise is -1..1.
@export_range(-1.0, 1.0) var forest_threshold: float = 0.12
@export var tree_spacing_m: float = 7.0
@export var bush_spacing_m: float = 9.0
@export var grass_spacing_m: float = 2.4
@export var rock_spacing_m: float = 22.0
## Trees and bushes are kept this far from road centerlines.
@export var road_clearance_m: float = 9.0
@export var max_tree_slope_deg: float = 32.0


func half_size() -> float:
	return snapped_size() * 0.5


## World size rounded up to a whole number of regions.
func snapped_size() -> float:
	var region_m := region_size * vertex_spacing
	return ceilf(world_size_m / region_m) * region_m


func to_world(n: Vector2) -> Vector2:
	return n * half_size()


func data_directory() -> String:
	return "res://worlds/%s/terrain" % world_name

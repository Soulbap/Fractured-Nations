## Navigation mesh for one playable area, baked at runtime from world data.
##
## Terrain faces come straight from Terrain3D (generate_nav_mesh_source_geometry), tree
## trunks from the WORLD-TECH-02 vegetation chunks (same data the colliders use) as
## unwalkable obstructions, parked vehicles as carved rectangles. Nothing is stored in
## the scene; a bigger world bakes more areas the same way (one region per area around
## active units is the intended scaling path, not one navmesh for 20 km).
class_name AreaNavigation
extends NavigationRegion3D

@export var terrain: Terrain3D
@export var vegetation: VegetationStreamer
@export var agent_radius := 0.5
@export var cell_size := 0.5
## Extra clearance around tree trunks beyond the collider radius.
@export var tree_margin := 0.2

var area_center := Vector3.ZERO
var area_size := 0.0
var last_bake := {}


## obstacles: [{position: Vector3, yaw: float, size: Vector2}] (vehicles).
func bake_area(center: Vector3, size: float, obstacles: Array = []) -> Dictionary:
	area_center = center
	area_size = size
	var t0 := Time.get_ticks_usec()
	var half := size * 0.5
	var aabb := AABB(Vector3(center.x - half, -2000.0, center.z - half), Vector3(size, 6000.0, size))
	var faces: PackedVector3Array = terrain.generate_nav_mesh_source_geometry(aabb, false)
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(faces, Transform3D.IDENTITY)
	var trees := _add_tree_obstructions(src, center, half)
	for ob in obstacles:
		src.add_projected_obstruction(_rect(ob.position, ob.yaw, ob.size), ob.position.y - 2.0, 6.0, false)
	var nm := NavigationMesh.new()
	nm.cell_size = cell_size
	nm.cell_height = 0.25
	nm.agent_radius = agent_radius
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.6
	nm.agent_max_slope = 45.0
	nm.region_min_size = 4.0
	nm.edge_max_length = 12.0
	nm.detail_sample_distance = 6.0
	nm.detail_sample_max_error = 1.0
	nm.filter_walkable_low_height_spans = true
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	navigation_mesh = nm
	last_bake = {"faces": faces.size() / 3, "tree_obstructions": trees, "vehicle_obstructions": obstacles.size(),
		"polygons": nm.get_polygon_count(), "bake_ms": (Time.get_ticks_usec() - t0) / 1000.0,
		"area_m": size, "center": [center.x, center.z]}
	return last_bake


func _add_tree_obstructions(src: NavigationMeshSourceGeometryData3D, center: Vector3, half: float) -> int:
	if vegetation == null or vegetation.library == null:
		return 0
	var radii := {}
	for d in vegetation.library.meshes:
		if d.collider.x >= 0.0:
			radii[d.id] = maxf(d.collider.y, 0.25)
	if radii.is_empty():
		return 0
	var cs: float = vegetation.cell_size_m
	var c0 := VegetationChunk.cell_of(Vector3(center.x - half, 0, center.z - half), cs)
	var c1 := VegetationChunk.cell_of(Vector3(center.x + half, 0, center.z + half), cs)
	var count := 0
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for inst in vegetation.get_cell_instances(Vector2i(cx, cz), radii.keys()):
				var xf: Transform3D = inst[1]
				var o := xf.origin
				if absf(o.x - center.x) > half or absf(o.z - center.z) > half:
					continue
				var r: float = radii[inst[0]] * xf.basis.get_scale().x + tree_margin
				src.add_projected_obstruction(_rect(o, 0.0, Vector2(r * 2.0, r * 2.0)), o.y - 2.0, 6.0, false)
				count += 1
	return count


static func _rect(pos: Vector3, yaw: float, size: Vector2) -> PackedVector3Array:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var b := Basis(Vector3.UP, yaw)
	var out := PackedVector3Array()
	for corner in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
		var p: Vector3 = pos + b * corner
		out.append(Vector3(p.x, 0.0, p.z))
	return out

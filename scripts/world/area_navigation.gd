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
@export var tree_margin := 0.45

var area_center := Vector3.ZERO
var area_size := 0.0
var last_bake := {}
## Async bakes still running.
var _pending := 0
## Bumped per bake: an async result older than the newest bake is dropped (a sync bake
## for a possession jump must not be replaced by a re-centre that finishes later).
var _serial := 0
var _faces := PackedVector3Array()
var _faces_key := []
## WORLD-SANDBOX-01: build the source geometry of async bakes on a worker thread.
var threaded_source := false


func has_pending_bake() -> bool:
	return _pending > 0


## The terrain changed inside rect (construction groundwork): update the cached terrain
## faces there. Terrain3D emits one quad (two triangles, six vertices) per grid cell, row by
## row over the grid points inside the area, so the affected vertices are found by index;
## regenerating all faces would cost ~115 ms on the main thread at every placement. If the
## face count does not match that layout (holes), the cache is dropped instead.
func terrain_changed(rect: Rect2) -> void:
	var half := area_size * 0.5
	var area := Rect2(area_center.x - half, area_center.z - half, area_size, area_size)
	if _faces_key.is_empty() or not area.intersects(rect):
		return
	var sp: float = terrain.vertex_spacing
	var gx0 := ceili(area.position.x / sp)
	var gz0 := ceili(area.position.y / sp)
	var ncols := floori(area.end.x / sp) - gx0 + 1
	var nrows := floori(area.end.y / sp) - gz0 + 1
	if _faces.size() != ncols * nrows * 6:
		_faces_key = []
		return
	var cx0 := maxi(floori(rect.position.x / sp) - 1 - gx0, 0)
	var cz0 := maxi(floori(rect.position.y / sp) - 1 - gz0, 0)
	var cx1 := mini(ceili(rect.end.x / sp) + 1 - gx0, ncols - 1)
	var cz1 := mini(ceili(rect.end.y / sp) + 1 - gz0, nrows - 1)
	var corner := [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var base := (cz * ncols + cx) * 6
			for k in 6:
				var v := _faces[base + k]
				var o: Vector2i = corner[k]
				var h: float = terrain.data.get_height(Vector3((gx0 + cx + o.x) * sp, 0.0, (gz0 + cz + o.y) * sp))
				if not is_nan(h):
					v.y = h
					_faces[base + k] = v


## obstacles: [{position: Vector3, yaw: float, size: Vector2}] (vehicles, structures).
## async: bake on a worker thread and swap the navmesh in when done (the previous one
## stays active meanwhile); used for structure changes, which must not stall a frame.
func bake_area(center: Vector3, size: float, obstacles: Array = [], async := false) -> Dictionary:
	area_center = center
	area_size = size
	var t0 := Time.get_ticks_usec()
	var half := size * 0.5
	var aabb := AABB(Vector3(center.x - half, -2000.0, center.z - half), Vector3(size, 6000.0, size))
	# Terrain does not change at runtime: reuse the faces when only obstacles changed.
	var key := [center.x, center.z, size]
	if async and threaded_source and key != _faces_key:
		# WORLD-SANDBOX-01: terrain faces and tree obstructions (~115 ms) on a worker too;
		# the bake continues there. The previous navmesh stays active meanwhile.
		_serial += 1
		var tserial := _serial
		_pending += 1
		var task_holder := [-1]
		task_holder[0] = WorkerThreadPool.add_task(func() -> void:
			var faces2 := terrain.generate_nav_mesh_source_geometry(aabb, false)
			var src2 := NavigationMeshSourceGeometryData3D.new()
			src2.add_faces(faces2, Transform3D.IDENTITY)
			var trees2 := _add_tree_obstructions(src2, center, half)
			for ob in obstacles:
				src2.add_projected_obstruction(_rect(ob.position, ob.yaw, ob.size), ob.position.y - 2.0, 6.0, false)
			var nm2 := _new_navmesh()
			NavigationServer3D.bake_from_source_geometry_data(nm2, src2)
			(func() -> void:
				# Collect the finished task (an uncollected WorkerThreadPool task crashed
				# the engine on exit).
				if task_holder[0] >= 0:
					WorkerThreadPool.wait_for_task_completion(task_holder[0])
				if tserial == _serial:
					navigation_mesh = nm2
					_faces = faces2
					_faces_key = key
				_pending -= 1
				last_bake["async_done_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
				last_bake["tree_obstructions"] = trees2
				last_bake["polygons"] = nm2.get_polygon_count()).call_deferred())
		last_bake = {"bake_ms": (Time.get_ticks_usec() - t0) / 1000.0, "source_ms": 0.0, "async": true, "threaded_source": true,
			"area_m": size, "center": [center.x, center.z], "vehicle_obstructions": obstacles.size()}
		return last_bake
	if key != _faces_key:
		_faces = terrain.generate_nav_mesh_source_geometry(aabb, false)
		_faces_key = key
	var faces := _faces
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(faces, Transform3D.IDENTITY)
	var trees := _add_tree_obstructions(src, center, half)
	for ob in obstacles:
		src.add_projected_obstruction(_rect(ob.position, ob.yaw, ob.size), ob.position.y - 2.0, 6.0, false)
	var nm := _new_navmesh()
	var t_src := Time.get_ticks_usec()
	_serial += 1
	var serial := _serial
	if async:
		_pending += 1
		# The callback may come from the worker thread: apply on the main thread.
		NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func() -> void:
			(func() -> void:
				if serial == _serial:
					navigation_mesh = nm
				_pending -= 1
				last_bake["async_done_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
				last_bake["polygons"] = nm.get_polygon_count()).call_deferred())
	else:
		NavigationServer3D.bake_from_source_geometry_data(nm, src)
		navigation_mesh = nm
	last_bake = {"faces": faces.size() / 3, "tree_obstructions": trees, "vehicle_obstructions": obstacles.size(),
		"polygons": nm.get_polygon_count(), "bake_ms": (Time.get_ticks_usec() - t0) / 1000.0,
		"source_ms": (t_src - t0) / 1000.0, "async": async,
		"area_m": size, "center": [center.x, center.z]}
	return last_bake


func _new_navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = cell_size
	nm.cell_height = 0.25
	nm.agent_radius = agent_radius
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.6
	nm.agent_max_slope = rad_to_deg(atan(WorldSim.INFANTRY_MAX_GRADE))  # NAV-INF-01: one slope limit for both tiers
	nm.region_min_size = 4.0
	nm.edge_max_length = 12.0
	nm.detail_sample_distance = 6.0
	nm.detail_sample_max_error = 1.0
	nm.filter_walkable_low_height_spans = true
	return nm


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

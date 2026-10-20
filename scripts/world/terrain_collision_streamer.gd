## Terrain collision around the observer, built a few pieces per frame (WORLD-SANDBOX-01).
##
## Terrain3D's dynamic collision rebuilds every shape in one call when the camera jumps
## far (about 390 ms on ref_20km at a 200 m radius), which stalled every map jump and
## every possession of a distant soldier. This streamer covers the same area with
## HeightMapShape3D chunks of 32 x 32 terrain cells (62.5 m), filled from Terrain3DData
## heights (groundwork edits included). After a jump the chunks nearest the observer are
## built first, within budget_ms per frame; DetailManager gives a unit a body only once
## the chunk under it is ready, so no soldier ever stands on missing ground. Chunks out of
## range are recycled. Same collision layer / mask as Terrain3D's own collision.
class_name TerrainCollisionStreamer
extends StaticBody3D

const CELLS := 32
var terrain: Terrain3D
## Chunks are kept within this distance of the observer (m).
var radius := 200.0
## Work per frame (ms) for chunks beyond the ones built at once.
var budget_ms := 3.0
var spacing := 2.0
var chunk_m := 64.0
## Vector2i -> CollisionShape3D (built)
var _chunks := {}
var _queue: Array[Vector2i] = []
var _center := Vector3.INF
var _pool: Array[CollisionShape3D] = []
## Measurements.
var built := 0
var build_usec := 0
var frame_usec_max := 0


func setup(p_terrain: Terrain3D) -> void:
	terrain = p_terrain
	spacing = terrain.vertex_spacing
	chunk_m = CELLS * spacing
	collision_layer = terrain.collision.layer if terrain.collision else 1
	collision_mask = 0


func _chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / chunk_m), floori(p.z / chunk_m))


## The observer moved: queue the chunks now in range (nearest first), drop the far ones.
func set_center(p: Vector3) -> void:
	_center = p
	var c := _chunk_of(p)
	var r := ceili(radius / chunk_m)
	var want := {}
	_queue.clear()
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := c + Vector2i(dx, dz)
			var cc := Vector3((k.x + 0.5) * chunk_m, 0, (k.y + 0.5) * chunk_m)
			if Vector2(cc.x - p.x, cc.z - p.z).length() > radius + chunk_m * 0.71:
				continue
			want[k] = true
			if not _chunks.has(k):
				_queue.append(k)
	for k: Vector2i in _chunks.keys():
		if not want.has(k):
			var cs: CollisionShape3D = _chunks[k]
			cs.disabled = true
			_pool.append(cs)
			_chunks.erase(k)
	var pc := p
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _dist(a, pc) < _dist(b, pc))


func _dist(k: Vector2i, p: Vector3) -> float:
	return Vector2((k.x + 0.5) * chunk_m - p.x, (k.y + 0.5) * chunk_m - p.z).length()


## Builds queued chunks for at most budget_ms (at least one per call).
func step() -> void:
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty():
		_build(_queue.pop_front())
		if Time.get_ticks_usec() - t0 > budget_ms * 1000.0:
			break
	frame_usec_max = maxi(frame_usec_max, Time.get_ticks_usec() - t0)


## Builds every queued chunk within r of p now (possession: ground under the soldier).
func ensure_now(p: Vector3, r: float) -> void:
	var keep: Array[Vector2i] = []
	for k in _queue:
		if _dist(k, p) <= r + chunk_m * 0.71:
			_build(k)
		else:
			keep.append(k)
	_queue = keep


func ready_at(p: Vector3) -> bool:
	return _chunks.has(_chunk_of(p))


func pending() -> int:
	return _queue.size()


func _build(k: Vector2i) -> void:
	if _chunks.has(k):
		return
	var t0 := Time.get_ticks_usec()
	var n := CELLS + 1
	var data := PackedFloat32Array()
	data.resize(n * n)
	var x0 := k.x * chunk_m
	var z0 := k.y * chunk_m
	var lo := INF
	for j in n:
		for i in n:
			var h: float = terrain.data.get_height(Vector3(x0 + i * spacing, 0.0, z0 + j * spacing))
			if is_nan(h):
				h = -1000.0
			data[j * n + i] = h
			lo = minf(lo, h)
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = data
	var cs: CollisionShape3D = _pool.pop_back() if not _pool.is_empty() else null
	if cs == null:
		cs = CollisionShape3D.new()
		add_child(cs)
	cs.shape = shape
	cs.disabled = false
	# A height map shape is centred on its middle sample; scaled to the vertex spacing.
	cs.transform = Transform3D(Basis.from_scale(Vector3(spacing, 1.0, spacing)), Vector3(x0 + (n - 1) * 0.5 * spacing, 0.0, z0 + (n - 1) * 0.5 * spacing))
	_chunks[k] = cs
	built += 1
	build_usec += Time.get_ticks_usec() - t0

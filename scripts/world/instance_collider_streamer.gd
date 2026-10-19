## Streams physics colliders for stored vegetation around a target.
##
## Trees and rocks are GPU MultiMeshes with no collision. They must block the player
## (and later vehicles and bullets), so this node keeps a small pool of simple shapes
## (trunk capsules, rock spheres) around the target, built from the instance data in
## the VegetationChunk cells (via VegetationStreamer.get_cell_instances). Cells are
## indexed lazily the first time the target comes near them, so cost scales with the
## area visited, not with map size.
class_name InstanceColliderStreamer
extends Node3D

## Unused since WORLD-TECH-02 (instances no longer live in Terrain3D regions); kept so
## existing scenes load without warnings.
@export var terrain: Terrain3D
@export var vegetation: VegetationStreamer
@export var target: Node3D
@export var radius := 40.0
## Rebuild after the target moves this far.
@export var rebuild_distance := 10.0
## Fallback shapes when the vegetation library has no collider for a mesh id:
## mesh_id -> Vector3(shape_type 0=capsule 1=sphere, radius, height) at instance scale 1.
@export var shapes := {
	1: Vector3(0, 0.35, 8.0), 2: Vector3(0, 0.45, 6.0),
	4: Vector3(1, 2.2, 0.0), 5: Vector3(1, 2.2, 0.0), 6: Vector3(1, 2.2, 0.0),
}
@export var bucket_size := 32.0

var active_count := 0
## Number of vegetation cells indexed so far.
var indexed_regions := 0

var _body: StaticBody3D
var _pool: Array[CollisionShape3D] = []
var _last_center := Vector3(INF, INF, INF)
var _indexed := {} # cell -> true
var _buckets := {} # Vector2i -> Array of [mesh_id, Transform3D]


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "InstanceColliders"
	add_child(_body)


func _physics_process(_delta: float) -> void:
	if not vegetation or not target:
		return
	var c := target.global_position
	if c.distance_to(_last_center) < rebuild_distance:
		return
	_last_center = c
	_index_near(c)
	_rebuild(c)


func _solid_ids() -> Array:
	var ids := []
	if vegetation.library:
		for d in vegetation.library.meshes:
			if d.collider.x >= 0.0:
				ids.append(d.id)
	else:
		ids = shapes.keys()
	return ids


func _shape_spec(mesh_id: int) -> Vector3:
	if vegetation.library:
		var d := vegetation.library.get_def(mesh_id)
		if d and d.collider.x >= 0.0:
			return d.collider
	return shapes.get(mesh_id, Vector3(-1, 0, 0))


func _index_near(c: Vector3) -> void:
	var cs := vegetation.cell_size_m
	var ids := _solid_ids()
	var c0 := VegetationChunk.cell_of(c - Vector3(radius, 0, radius), cs)
	var c1 := VegetationChunk.cell_of(c + Vector3(radius, 0, radius), cs)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell := Vector2i(cx, cz)
			if _indexed.has(cell):
				continue
			_indexed[cell] = true
			indexed_regions += 1
			for entry in vegetation.get_cell_instances(cell, ids):
				var g: Transform3D = entry[1]
				var key := Vector2i(floori(g.origin.x / bucket_size), floori(g.origin.z / bucket_size))
				if not _buckets.has(key):
					_buckets[key] = []
				_buckets[key].append(entry)


func _rebuild(c: Vector3) -> void:
	var used := 0
	var r := int(ceil(radius / bucket_size))
	var k := Vector2i(floori(c.x / bucket_size), floori(c.z / bucket_size))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var b = _buckets.get(k + Vector2i(dx, dz))
			if b == null:
				continue
			for entry in b:
				var g: Transform3D = entry[1]
				if Vector2(g.origin.x - c.x, g.origin.z - c.z).length() > radius:
					continue
				_place(used, entry[0], g)
				used += 1
	for i in range(used, _pool.size()):
		_pool[i].disabled = true
	active_count = used


func _place(i: int, mesh_id: int, g: Transform3D) -> void:
	if i >= _pool.size():
		var new_shape := CollisionShape3D.new()
		_body.add_child(new_shape)
		_pool.append(new_shape)
	var cs := _pool[i]
	var spec := _shape_spec(mesh_id)
	var s := g.basis.get_scale().y
	if spec.x == 0:
		var cap := cs.shape as CapsuleShape3D
		if cap == null:
			cap = CapsuleShape3D.new()
			cs.shape = cap
		cap.radius = spec.y * s
		cap.height = maxf(spec.z * s, cap.radius * 2.0 + 0.01)
		cs.global_transform = Transform3D(Basis(), g.origin + Vector3.UP * cap.height * 0.5)
	else:
		var sph := cs.shape as SphereShape3D
		if sph == null:
			sph = SphereShape3D.new()
			cs.shape = sph
		sph.radius = spec.y * s
		cs.global_transform = Transform3D(Basis(), g.origin + Vector3.UP * sph.radius * 0.3)
	cs.disabled = false

## Streams physics colliders for Terrain3D instancer meshes around a target.
##
## Terrain3D 1.0 instances are GPU MultiMeshes with no collision. Trees and rocks
## must block the player (and later vehicles and bullets), so this node keeps a small
## pool of simple shapes (trunk capsules, rock spheres) around the target, built from
## the instance transforms stored in the terrain regions. Region data is indexed lazily
## the first time the target comes near a region, so cost scales with the area visited,
## not with map size. Instances painted by hand with Terrain3D's brushes are included.
class_name InstanceColliderStreamer
extends Node3D

@export var terrain: Terrain3D
@export var target: Node3D
@export var radius := 40.0
## Rebuild after the target moves this far.
@export var rebuild_distance := 10.0
## mesh_id -> Vector3(shape_type 0=capsule 1=sphere, radius, height) at instance scale 1.
@export var shapes := {
	1: Vector3(0, 0.35, 8.0), 2: Vector3(0, 0.45, 6.0),
	4: Vector3(1, 2.2, 0.0), 5: Vector3(1, 2.2, 0.0), 6: Vector3(1, 2.2, 0.0),
}
@export var bucket_size := 32.0

var active_count := 0
var indexed_regions := 0

var _body: StaticBody3D
var _pool: Array[CollisionShape3D] = []
var _last_center := Vector3(INF, INF, INF)
var _indexed := {} # region location -> true
var _buckets := {} # Vector2i -> Array of [mesh_id, Transform3D]


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "InstanceColliders"
	add_child(_body)


func _physics_process(_delta: float) -> void:
	if not terrain or not target or not terrain.data:
		return
	var c := target.global_position
	if c.distance_to(_last_center) < rebuild_distance:
		return
	_last_center = c
	_index_near(c)
	_rebuild(c)


func _index_near(c: Vector3) -> void:
	var region_m := terrain.region_size * terrain.vertex_spacing
	for dx in [-radius, 0.0, radius]:
		for dz in [-radius, 0.0, radius]:
			var p := c + Vector3(dx, 0, dz)
			var loc: Vector2i = terrain.data.get_region_location(p)
			if _indexed.has(loc) or not terrain.data.has_region(loc):
				continue
			_indexed[loc] = true
			indexed_regions += 1
			var region: Terrain3DRegion = terrain.data.get_region(loc)
			var offset := Vector3(loc.x * region_m, 0, loc.y * region_m)
			var inst: Dictionary = region.get_instances()
			for mesh_id in inst:
				if not shapes.has(mesh_id):
					continue
				for cell in inst[mesh_id]:
					var xforms: Array = inst[mesh_id][cell][0]
					for xf: Transform3D in xforms:
						# Instance transforms are stored relative to the region origin.
						var g := Transform3D(xf.basis, xf.origin + offset)
						var key := Vector2i(floori(g.origin.x / bucket_size), floori(g.origin.z / bucket_size))
						if not _buckets.has(key):
							_buckets[key] = []
						_buckets[key].append([mesh_id, g])


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
		var cs := CollisionShape3D.new()
		_body.add_child(cs)
		_pool.append(cs)
	var cs := _pool[i]
	var spec: Vector3 = shapes[mesh_id]
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

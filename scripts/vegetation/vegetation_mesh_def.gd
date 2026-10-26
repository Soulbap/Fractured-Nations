## One vegetation mesh type (conifer, bush, rock ...) as used by VegetationStreamer.
##
## The scene is a Node3D with MeshInstance3D children named <name>_LOD0..n (the same
## convention as the Terrain3D mesh assets). The streamer uses the first child near the camera,
## the last child beyond near_range and - WORLD-VISUALS-01, trees - the second child between
## near_range and mid_range when the scene has three LODs.
@tool
class_name VegetationMeshDef
extends Resource

## LOD levels as the streamer uses them.
const NEAR := 0
const MID := 1
const FAR := 2

@export var id := 1
@export var name := "Conifer"
@export var scene: PackedScene
## Full-detail mesh (LOD0) up to this distance; the cheapest LOD beyond it.
@export var near_range := 150.0
## WORLD-VISUALS-01: the mid LOD (second child) up to this distance; 0 or a scene with fewer than three LODs = none.
@export var mid_range := 0.0
## Cells farther than this from every observer are not instantiated at all.
@export var max_range := 800.0
## Fade-out width at max_range (visibility range margin).
@export var fade_m := 60.0
## Only the near (and mid) LOD casts shadows.
@export var cast_shadows := true
## Physics shape for InstanceColliderStreamer at instance scale 1:
## x = type (-1 none, 0 capsule, 1 sphere, 2 box), y = radius, z = height. WORLD-COVER-01: a box (logs, walls, timber stacks,
## root plates, rock groups) takes its size from `box`; y is then its bounding radius (set by box_radius()).
@export var collider := Vector3(-1, 0, 0)
## WORLD-COVER-01, collider type 2: half length along the instance's local x, full height, half depth along local z (m, scale 1),
## standing on the instance origin and turned with it. Every variant of the id lies inside it.
@export var box := Vector3.ZERO
## WORLD-VISUALS-01: more scenes of the same kind of plant or rock (variant 1..n; `scene` is variant 0), same size class and
## trunk / footprint, so the collider above fits all of them. Each stored instance draws one variant, chosen from its position
## (variant_of): the chunk data stays as it is.
@export var variants: Array[PackedScene] = []
## The far LOD is one mesh for every variant (trees: impostor cards whose shader picks the variant's tile in an atlas from the
## instance colour's alpha); otherwise every variant draws its own far mesh.
@export var shared_far := false

var _meshes: Array[Mesh] = []
var _overrides: Array[Material] = []
## Per variant 1..n: [meshes, overrides] in LOD order.
var _vmeshes: Array = []


func lod_count() -> int:
	_load()
	return _meshes.size()


func has_mid() -> bool:
	_load()
	return mid_range > near_range and _meshes.size() >= 3


## LOD for a distance; with the current LOD and a relative hysteresis the switch distances move away from it.
func lod_at(dist: float, current := -1, hysteresis := 0.0) -> int:
	var near := near_range
	if current == NEAR:
		near *= 1.0 + hysteresis
	elif current > NEAR:
		near *= 1.0 - hysteresis
	if dist < near:
		return NEAR
	if has_mid():
		var mid := mid_range
		if current == MID:
			mid *= 1.0 + hysteresis
		elif current == FAR:
			mid *= 1.0 - hysteresis
		if dist < mid:
			return MID
	return FAR


func _index(lod: int, count: int) -> int:
	if lod <= NEAR:
		return 0
	if lod == MID and has_mid():
		return 1
	return count - 1


## lod: NEAR, MID or FAR.
func get_mesh(lod: int) -> Mesh:
	_load()
	if _meshes.is_empty():
		return null
	return _meshes[_index(lod, _meshes.size())]


func get_material_override(lod: int) -> Material:
	_load()
	if _overrides.is_empty():
		return null
	return _overrides[_index(lod, _overrides.size())]


func variant_count() -> int:
	return 1 + variants.size()


## Mesh of one variant (0 = `scene`); lod 0 = near, 1 = far.
func get_variant_mesh(lod: int, variant: int) -> Mesh:
	if variant <= 0 or variants.is_empty():
		return get_mesh(lod)
	_load()
	var e: Array = _vmeshes[mini(variant, _vmeshes.size()) - 1][0]
	return e[0] if lod <= NEAR else (e[mini(1, e.size() - 1)] if lod == MID else e[e.size() - 1])


func get_variant_override(lod: int, variant: int) -> Material:
	if variant <= 0 or variants.is_empty():
		return get_material_override(lod)
	_load()
	var e: Array = _vmeshes[mini(variant, _vmeshes.size()) - 1][1]
	return e[0] if lod <= NEAR else (e[mini(1, e.size() - 1)] if lod == MID else e[e.size() - 1])


## Variant of an instance at world x, z: a fixed integer hash of the position (10 cm grid), the same on every run and machine.
static func variant_of(x: float, z: float, count: int) -> int:
	if count <= 1:
		return 0
	var xi := roundi(x * 10.0)
	var zi := roundi(z * 10.0)
	var h := ((xi * 73856093) ^ (zi * 19349663) ^ ((xi ^ zi) * 83492791)) & 0x7fffffff
	return (h >> 7) % count


func _load() -> void:
	if not _meshes.is_empty() or scene == null:
		return
	var lods := _scene_lods(scene)
	_meshes.assign(lods[0])
	_overrides.assign(lods[1])
	_vmeshes.clear()
	for vs in variants:
		_vmeshes.append(_scene_lods(vs) if vs else lods)


## [meshes, overrides] of the scene's MeshInstance3D children in LOD name order.
static func _scene_lods(ps: PackedScene) -> Array:
	var root := ps.instantiate()
	var found: Array[MeshInstance3D] = []
	for c in root.find_children("*", "MeshInstance3D", true, false):
		found.append(c)
	found.sort_custom(func(a: Node, b: Node) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	var meshes: Array[Mesh] = []
	var overrides: Array[Material] = []
	for mi in found:
		meshes.append(mi.mesh)
		overrides.append(mi.material_override)
	root.free()
	return [meshes, overrides]


## WORLD-COVER-01: the radius of the circle round a box collider (bucket culling, vehicle and soldier clearance).
func box_radius() -> float:
	return Vector2(box.x, box.z).length()


## The physics / ballistic spec of the id as [type, radius, height, half length, half depth] (type -1: none).
func solid_spec() -> PackedFloat32Array:
	if collider.x >= 1.5:
		return PackedFloat32Array([2.0, box_radius(), box.y, box.x, box.z])
	return PackedFloat32Array([collider.x, collider.y, collider.z, 0.0, 0.0])


## Yaw of an instance transform (rotation about +Y; 0 = local x along world +X).
static func yaw_of(xf: Transform3D) -> float:
	var bx := xf.basis.x
	return atan2(-bx.z, bx.x)

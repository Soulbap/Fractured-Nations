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
## WORLD-COVER-01.1: the box solids of each variant (index = variant, 0 = `scene`) where one box fits badly (the gaps of a rock
## group, a root plate's lying trunk, a shorter log): 6 floats per box - [2, centre x, centre z, half length, height, half depth] in
## the instance's local frame at scale 1, turned with it. Measured from the meshes by tools/world_cover/measure_cover_colliders.gd.
## Empty (or no list for a variant): the id's one `box`. Every reader of box solids goes through boxes_of().
@export var parts: Array[PackedFloat32Array] = []
## COMBAT-COVER-03: height of the bottom of every box above the instance origin (m, scale 1; negative = below). A settlement
## building's foundation reaches 0.55 m under its origin so it meets sloping ground; its solids must too, or shots and sight lines
## pass under the downhill wall. Box heights (`box.y`, part heights) are measured from this base.
@export var box_base := 0.0
## COMBAT-COVER-03: how a soldier behind this solid is judged (CoverEval): 0 by its shape (a box, a rock and a building are heavy
## cover, a trunk light), 1 always light (round bales, pallets, yard goods: they stop a bullet in this game, but a player should not
## read them as a concrete wall). Ballistics are the same either way.
@export var cover_class := 0
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


## WORLD-COVER-01.1: the box solids of an instance (collider type 2) in world space, scaled and turned with it:
## [centre on the base (Vector3), yaw, half length, height, half depth] per box - its variant's parts, else the one box.
func boxes_of(xf: Transform3D) -> Array:
	var s := xf.basis.get_scale().x
	var yaw := yaw_of(xf)
	var o := xf.origin + Vector3.UP * box_base * s
	var v := variant_of(xf.origin.x, xf.origin.z, variant_count()) if parts.size() > 1 else 0
	if use_parts and v < parts.size() and parts[v].size() >= 6:
		var p: PackedFloat32Array = parts[v]
		var b := Basis(Vector3.UP, yaw)
		var out: Array = []
		for i in range(0, p.size() - 5, 6):
			out.append([o + b * Vector3(p[i + 1], 0.0, p[i + 2]) * s, yaw, p[i + 3] * s, p[i + 4] * s, p[i + 5] * s])
		return out
	return [[o, yaw, box.x * s, box.y * s, box.z * s]]


## `--single-box-colliders`: every box id uses its one box again (comparison runs).
static var use_parts := not "--single-box-colliders" in OS.get_cmdline_user_args()


## Yaw of an instance transform (rotation about +Y; 0 = local x along world +X).
static func yaw_of(xf: Transform3D) -> float:
	var bx := xf.basis.x
	return atan2(-bx.z, bx.x)

## One vegetation mesh type (conifer, bush, rock ...) as used by VegetationStreamer.
##
## The scene is a Node3D with MeshInstance3D children named <name>_LOD0..n (the same
## convention as the Terrain3D mesh assets). The streamer uses two LODs: the first
## child near the camera and the last child beyond near_range.
class_name VegetationMeshDef
extends Resource

@export var id := 1
@export var name := "Conifer"
@export var scene: PackedScene
## Full-detail mesh (LOD0) up to this distance; the cheapest LOD beyond it.
@export var near_range := 150.0
## Cells farther than this from every observer are not instantiated at all.
@export var max_range := 800.0
## Fade-out width at max_range (visibility range margin).
@export var fade_m := 60.0
## Only the near LOD casts shadows.
@export var cast_shadows := true
## Physics shape for InstanceColliderStreamer at instance scale 1:
## x = type (-1 none, 0 capsule, 1 sphere), y = radius, z = height.
@export var collider := Vector3(-1, 0, 0)

var _meshes: Array[Mesh] = []
var _overrides: Array[Material] = []


func lod_count() -> int:
	_load()
	return _meshes.size()


## lod 0 = near, 1 = far.
func get_mesh(lod: int) -> Mesh:
	_load()
	if _meshes.is_empty():
		return null
	return _meshes[0] if lod == 0 else _meshes[_meshes.size() - 1]


func get_material_override(lod: int) -> Material:
	_load()
	if _overrides.is_empty():
		return null
	return _overrides[0] if lod == 0 else _overrides[_overrides.size() - 1]


func _load() -> void:
	if not _meshes.is_empty() or scene == null:
		return
	var root := scene.instantiate()
	var found: Array[MeshInstance3D] = []
	for c in root.find_children("*", "MeshInstance3D", true, false):
		found.append(c)
	found.sort_custom(func(a: Node, b: Node) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	for mi in found:
		_meshes.append(mi.mesh)
		_overrides.append(mi.material_override)
	root.free()

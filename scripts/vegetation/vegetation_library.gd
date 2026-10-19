## The set of vegetation mesh types a world can store, indexed by mesh id.
class_name VegetationLibrary
extends Resource

@export var meshes: Array[VegetationMeshDef] = []

var _by_id := {}


func get_def(id: int) -> VegetationMeshDef:
	if _by_id.size() != meshes.size():
		_by_id.clear()
		for d in meshes:
			_by_id[d.id] = d
	return _by_id.get(id)


func ids() -> Array:
	var out := []
	for d in meshes:
		out.append(d.id)
	return out


func max_range() -> float:
	var r := 0.0
	for d in meshes:
		r = maxf(r, d.max_range + d.fade_m)
	return r

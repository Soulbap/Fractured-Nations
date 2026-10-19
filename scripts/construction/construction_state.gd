## Every placed structure in the world, by id. Part of WorldState (world.construction).
##
## No nodes, no rendering, no terrain access: adding, removing, saving and loading only
## touch these records. StructureManager listens to the signals and updates whatever is
## visible near the camera. Saved as plain JSON (user://saves/<world>/construction.json
## by default) so a base can be inspected or edited by hand.
class_name ConstructionState
extends RefCounted

signal structure_added(s: StructureState)
signal structure_removed(s: StructureState)
## A line lost a module (s.removed changed).
signal structure_changed(s: StructureState)
signal cleared

const FORMAT_VERSION := 1

## id -> StructureState
var structures := {}
var _next_id := 1


func add_building(type_id: StringName, position: Vector3, yaw: float, faction := 0) -> StructureState:
	var s := StructureState.new()
	s.type_id = type_id
	s.position = position
	s.yaw = wrapf(yaw, -PI, PI)
	s.faction = faction
	return _insert(s)


## points: corners in order; removed: modules that are not built (blocked sections).
func add_line(type_id: StringName, points: PackedVector3Array, removed := PackedInt32Array(), faction := 0) -> StructureState:
	if points.size() < 2:
		return null
	var s := StructureState.new()
	s.type_id = type_id
	s.points = points
	s.removed = removed
	s.faction = faction
	return _insert(s)


func get_structure(id: int) -> StructureState:
	return structures.get(id)


func remove(id: int) -> bool:
	var s: StructureState = structures.get(id)
	if s == null:
		return false
	structures.erase(id)
	structure_removed.emit(s)
	return true


## Deletes one module of a line; the line disappears with its last module.
func remove_module(id: int, index: int) -> bool:
	var s: StructureState = structures.get(id)
	if s == null or not s.is_line() or s.removed.has(index) or index < 0:
		return false
	s.removed.append(index)
	if not s.instances.is_empty() and s.removed.size() >= s.instances.size():
		return remove(id)
	structure_changed.emit(s)
	return true


func count() -> int:
	return structures.size()


func all() -> Array:
	var out := structures.values()
	out.sort_custom(func(a: StructureState, b: StructureState) -> bool: return a.id < b.id)
	return out


func clear() -> void:
	structures.clear()
	_next_id = 1
	cleared.emit()


func to_dict() -> Dictionary:
	var list := []
	for s in all():
		list.append(s.to_dict())
	return {"format": FORMAT_VERSION, "next_id": _next_id, "structures": list}


func from_dict(d: Dictionary) -> void:
	clear()
	for sd in d.get("structures", []):
		var s := StructureState.from_dict(sd)
		if s.id <= 0 or s.type_id == &"":
			continue
		structures[s.id] = s
		_next_id = maxi(_next_id, s.id + 1)
		structure_added.emit(s)
	_next_id = maxi(_next_id, int(d.get("next_id", 1)))


func save_json(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), " "))
	f.close()
	return OK


func load_json(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return ERR_PARSE_ERROR
	from_dict(parsed)
	return OK


func _insert(s: StructureState) -> StructureState:
	s.id = _next_id
	_next_id += 1
	structures[s.id] = s
	structure_added.emit(s)
	return s

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
## Vegetation clearings were added or replaced.
signal clearings_changed
## GAMEPLAY-01B: a construction site was finished (it is now an ordinary structure; facilities start working), or its
## progress passed another tenth (its look changes).
signal structure_completed(s: StructureState)
signal site_progressed(s: StructureState)

## 2: adds "clearings" (version 1 files load with none).
const FORMAT_VERSION := 3

## id -> StructureState
var structures := {}
## LOGISTICS-01 bases: id -> {id, name, faction, anchor (Vector3), radius, founder}. A base is only a
## named group of facilities (StructureState.base_id); it owns nothing and no structure needs one.
## GAMEPLAY-01D: `objective` - the strategic objective of the base (WarSim.sync_bases): an objective it stands on that its
## faction holds (a headquarters), else its own objective of kind "base". The objective's owner is the ownership; `faction`
## here follows it (BaseSim.capture_base is the only writer after founding).
## BASE-01: a base established by a command post has a fixed area (anchor = the command post, `radius`
## m) and `founder` = that structure's id; radius 0 is a LOGISTICS-01 proximity group whose anchor
## follows its facilities. founder -1: none (or the command post was removed).
var bases := {}
var _next_base_id := 1
## Areas where construction removed trees and undergrowth, independent of the structures
## (removing a building does not regrow the forest): [{"c": [x, z], "yaw": r, "h": [hx, hz]}].
var clearings: Array = []
var _next_id := 1


## Records cleared rectangles (XZ center, yaw, half extents) in one change.
func add_clearings(list: Array) -> void:
	if list.is_empty():
		return
	clearings.append_array(list)
	clearings_changed.emit()


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


## WORLD-PLAYTEST-01: a road (control points + graded centre line) or a paved area
## (polygon + plane). See StructureDef.Surface.
func add_surface(type_id: StringName, points: PackedVector3Array, profile: PackedVector3Array, faction := 0) -> StructureState:
	if points.size() < 2 or profile.is_empty():
		return null
	var s := StructureState.new()
	s.type_id = type_id
	s.points = points
	s.profile = profile
	s.faction = faction
	return _insert(s)


## GAMEPLAY-01B: a construction site of a building - the structure exists (footprint, groundwork, collision) but works
## only when `need` soldier-seconds of work are done (add_work). paid: the payment record (refunded on cancel); crew: work
## per second done without soldiers (AI factions).
func add_site(type_id: StringName, position: Vector3, yaw: float, faction: int, need: float, paid: Dictionary, crew := 0.0) -> StructureState:
	var s := StructureState.new()
	s.type_id = type_id
	s.position = position
	s.yaw = wrapf(yaw, -PI, PI)
	s.faction = faction
	s.site = _site_record(need, paid, crew)
	return _insert(s)


## The same for a line (HESCO, walls): `need` covers all its built modules.
func add_line_site(type_id: StringName, points: PackedVector3Array, removed: PackedInt32Array, faction: int, need: float, paid: Dictionary) -> StructureState:
	if points.size() < 2:
		return null
	var s := StructureState.new()
	s.type_id = type_id
	s.points = points
	s.removed = removed
	s.faction = faction
	s.site = _site_record(need, paid, 0.0)
	return _insert(s)


func _site_record(need: float, paid: Dictionary, crew: float) -> Dictionary:
	return {"work": 0.0, "need": maxf(need, 1.0), "paid": paid, "crew": crew, "workers": 0, "why": "", "step": 0}


## Adds soldier-seconds of work to a site. Returns true when this call finished it: the site record goes, the structure
## is complete and structure_completed is emitted - exactly once (a finished structure takes no more work).
func add_work(s: StructureState, amount: float) -> bool:
	if s == null or not s.is_site() or not structures.has(s.id) or amount <= 0.0:
		return false
	s.site["work"] = float(s.site.work) + amount
	if float(s.site.work) >= float(s.site.need):
		s.site = {}
		structure_completed.emit(s)
		structure_changed.emit(s)
		return true
	var step := int(s.site_progress() * 10.0)
	if step != int(s.site.get("step", 0)):
		s.site["step"] = step
		site_progressed.emit(s)
	return false


## Removes a site that is not finished; returns its payment record (the caller refunds it), {} when it was no site.
func cancel_site(id: int) -> Dictionary:
	var s: StructureState = structures.get(id)
	if s == null or not s.is_site():
		return {}
	var paid: Dictionary = s.site.get("paid", {})
	remove(id)
	return {"paid": paid, "type": s.type_id, "faction": s.faction, "progress": s.site_progress()}


## A new base (LogisticsSim decides when); returns its record.
func add_base(base_name: String, faction: int, anchor: Vector3, radius := 0.0, founder := -1) -> Dictionary:
	var b := {"id": _next_base_id, "name": base_name, "faction": faction, "anchor": anchor, "radius": radius, "founder": founder}
	bases[_next_base_id] = b
	_next_base_id += 1
	return b


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
	bases = {}
	_next_base_id = 1
	clearings = []
	_next_id = 1
	cleared.emit()
	clearings_changed.emit()


func to_dict() -> Dictionary:
	var list := []
	for s in all():
		list.append(s.to_dict())
	var bl := []
	for id in bases:
		var b: Dictionary = bases[id]
		bl.append({"id": id, "name": b.name, "faction": b.faction, "anchor": [snappedf(b.anchor.x, 0.1), snappedf(b.anchor.y, 0.1), snappedf(b.anchor.z, 0.1)],
			"radius": b.get("radius", 0.0), "founder": b.get("founder", -1), "objective": b.get("objective", -1)})
	return {"format": FORMAT_VERSION, "next_id": _next_id, "structures": list, "clearings": clearings.duplicate(true), "bases": bl, "next_base": _next_base_id}


func from_dict(d: Dictionary) -> void:
	clear()
	var cl: Array = d.get("clearings", [])
	if not cl.is_empty():
		clearings = cl.duplicate(true)
		clearings_changed.emit()
	for bd: Dictionary in d.get("bases", []):
		var a: Array = bd.anchor
		bases[int(bd.id)] = {"id": int(bd.id), "name": String(bd.name), "faction": int(bd.faction), "anchor": Vector3(a[0], a[1], a[2]),
			"radius": float(bd.get("radius", 0.0)), "founder": int(bd.get("founder", -1)), "objective": int(bd.get("objective", -1))}
	_next_base_id = int(d.get("next_base", 1))
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

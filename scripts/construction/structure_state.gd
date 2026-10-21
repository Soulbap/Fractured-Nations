## One placed structure: a building (position + yaw) or a modular line (points).
##
## Plain data like UnitState. It exists whether or not anything renders it; the
## StructureManager derives instance transforms, collision and navigation obstacles from
## it near the camera. A line stores its corner points and the indices of modules that
## were deleted or could not be built, so the perimeter stays one object and single
## sections can be removed.
class_name StructureState
extends RefCounted

var id := 0
var type_id: StringName
var faction := 0
## Buildings: ground position and heading (yaw around +Y, 0 = front facing -Z).
var position := Vector3.ZERO
var yaw := 0.0
## Lines: corner points (at least two). Empty for buildings.
var points := PackedVector3Array()
## Lines: module indices that are not built.
var removed := PackedInt32Array()
## WORLD-PLAYTEST-01 surfaces. Roads: the graded centre line (dense, ~2 m, y = road
## surface), computed once at placement from the control points in `points` and saved, so
## the road never changes on load. Areas: [centroid with its height, plane gradient (x, z)].
var profile := PackedVector3Array()

## LOGISTICS-01 facilities (see FacilityDefs): supplies stored here (null: no storage), the
## base this structure belongs to (-1 = none; ConstructionState.bases), a name shown to the
## player and kind-specific state (recruitment queue, vehicle stock, ...). Saved with the
## structure, so inventories persist with the base.
var inventory: Inventory
var base_id := -1
var label := ""
var facility := {}

## Runtime cache, rebuilt from the data above (not saved): one transform per instance
## (index = module index for lines; -1 entries never appear, removed modules are skipped
## by is_removed()).
var instances: Array[Transform3D] = []


func is_line() -> bool:
	return points.size() >= 2


func is_removed(index: int) -> bool:
	return removed.has(index)


func built_count() -> int:
	return instances.size() - removed.size() if is_line() else 1


func to_dict() -> Dictionary:
	var d := {"id": id, "type": String(type_id), "faction": faction}
	if is_line():
		var pts := []
		for p in points:
			pts.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
		d["points"] = pts
		if not removed.is_empty():
			d["removed"] = Array(removed)
		if not profile.is_empty():
			var flat := []
			for p in profile:
				flat.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
			d["profile"] = flat
	else:
		d["position"] = [snappedf(position.x, 0.001), snappedf(position.y, 0.001), snappedf(position.z, 0.001)]
		d["yaw"] = snappedf(yaw, 0.0001)
	if inventory:
		d["inv"] = inventory.to_dict()
	if base_id >= 0:
		d["base"] = base_id
	if label != "":
		d["label"] = label
	if not facility.is_empty():
		d["facility"] = facility
	return d


static func from_dict(d: Dictionary) -> StructureState:
	var s := StructureState.new()
	s.id = int(d.get("id", 0))
	s.type_id = StringName(d.get("type", ""))
	s.faction = int(d.get("faction", 0))
	if d.has("points"):
		for p in d.points:
			s.points.append(Vector3(p[0], p[1], p[2]))
		for i in d.get("removed", []):
			s.removed.append(int(i))
		var flat: Array = d.get("profile", [])
		for i in range(0, flat.size() - 2, 3):
			s.profile.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
	else:
		var p: Array = d.get("position", [0, 0, 0])
		s.position = Vector3(p[0], p[1], p[2])
		s.yaw = float(d.get("yaw", 0.0))
	if d.get("inv") is Dictionary:
		s.inventory = Inventory.from_dict(d.inv)
	s.base_id = int(d.get("base", -1))
	s.label = String(d.get("label", ""))
	s.facility = d.get("facility", {})
	return s

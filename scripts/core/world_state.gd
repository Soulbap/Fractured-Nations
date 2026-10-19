## Authoritative world state: every unit the simulation knows about, by id.
##
## No scene nodes and no rendering here. FPS, RTS and the future 2D map all read this
## and send commands to it (issue_move, halt); WorldSim advances it in time. It can run
## headless, which is what keeps "which camera is active" separate from "what the world
## is doing". Faction data is a fixed table for now (two placeholder factions).
class_name WorldState
extends RefCounted

signal unit_added(unit: UnitState)
signal unit_removed(id: int)
signal order_changed(unit: UnitState)

const FACTION_NAMES: Array[String] = ["North", "South"]
const FACTION_COLORS: Array[Color] = [Color(0.3, 0.55, 1.0), Color(1.0, 0.4, 0.2)]

## id -> UnitState
var units := {}
## Simulated time in seconds.
var time := 0.0
var _next_id := 1


func add_unit(kind: UnitState.Kind, faction: int, position: Vector3, yaw := 0.0, unit_name := "") -> UnitState:
	var u := UnitState.new()
	u.id = _next_id
	_next_id += 1
	u.kind = kind
	u.faction = faction
	u.position = position
	u.yaw = yaw
	u.speed = 4.5 if kind == UnitState.Kind.SOLDIER else 0.0
	u.unit_name = unit_name if unit_name != "" else "%s-%d" % [faction_name(faction).left(1), u.id]
	units[u.id] = u
	unit_added.emit(u)
	return u


func remove_unit(id: int) -> void:
	if units.erase(id):
		unit_removed.emit(id)


func get_unit(id: int) -> UnitState:
	return units.get(id)


func all_units() -> Array:
	var out := units.values()
	out.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.id < b.id)
	return out


func units_where(pred: Callable) -> Array:
	var out := []
	for u in all_units():
		if pred.call(u):
			out.append(u)
	return out


func soldiers() -> Array:
	return units_where(func(u: UnitState) -> bool: return u.kind == UnitState.Kind.SOLDIER)


func count_of(kind: UnitState.Kind) -> int:
	var n := 0
	for u in units.values():
		if u.kind == kind:
			n += 1
	return n


## Orders a unit to walk to a world position. Vehicles cannot drive yet and refuse.
## The order survives possession: a possessed soldier suspends it and resumes it when
## the player leaves.
func issue_move(id: int, target: Vector3) -> bool:
	var u := get_unit(id)
	if u == null or u.kind != UnitState.Kind.SOLDIER:
		return false
	u.order = UnitState.Order.MOVE
	u.order_target = target
	u.move_state = UnitState.MoveState.MOVING
	order_changed.emit(u)
	return true


## Group move with a simple grid formation around the target (spacing in meters), so
## several soldiers sent to one point do not fight for the same square meter.
func issue_group_move(ids: Array, target: Vector3, spacing := 2.5) -> int:
	var movers := []
	for id in ids:
		var u := get_unit(id)
		if u and u.kind == UnitState.Kind.SOLDIER:
			movers.append(u)
	if movers.is_empty():
		return 0
	var cols := ceili(sqrt(float(movers.size())))
	var rows := ceili(float(movers.size()) / cols)
	var i := 0
	for u in movers:
		var col := i % cols
		var row := i / cols
		var offset := Vector3((col - (cols - 1) * 0.5) * spacing, 0.0, (row - (rows - 1) * 0.5) * spacing)
		issue_move(u.id, target + offset)
		i += 1
	return movers.size()


func halt(id: int) -> void:
	var u := get_unit(id)
	if u == null:
		return
	u.order = UnitState.Order.NONE
	u.order_target = Vector3.ZERO
	u.move_state = UnitState.MoveState.IDLE
	order_changed.emit(u)


static func faction_name(faction: int) -> String:
	return FACTION_NAMES[faction] if faction >= 0 and faction < FACTION_NAMES.size() else "Faction %d" % faction


static func faction_color(faction: int) -> Color:
	return FACTION_COLORS[faction] if faction >= 0 and faction < FACTION_COLORS.size() else Color.WHITE


## Deep copy of everything, for save/load and for consistency checks in tests.
func snapshot() -> Dictionary:
	var list := []
	for u in all_units():
		list.append(u.to_dict())
	return {"time": time, "next_id": _next_id, "units": list}


func restore(snap: Dictionary) -> void:
	units.clear()
	time = snap.get("time", 0.0)
	_next_id = snap.get("next_id", 1)
	for d in snap.get("units", []):
		var u := UnitState.from_dict(d)
		units[u.id] = u
		unit_added.emit(u)

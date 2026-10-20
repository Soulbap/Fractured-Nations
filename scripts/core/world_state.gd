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
## UNIT-01A: a squad was created, removed, or its order / formation / membership changed.
signal squad_changed(squad: SquadState)
## apply_snapshot() replaced the state of existing records in place (load).
signal restored
## COMBAT-01a events, emitted by CombatSim (presentation listens; no authority there).
## shot: {shooter, origin, end, dir, hit_unit, zone, blocker, distance, damage, killed, counter}
signal shot_fired(shot: Dictionary)
signal unit_damaged(unit: UnitState, amount: float, zone: int, source_id: int)
signal unit_died(unit: UnitState)
signal reload_started(unit: UnitState)
signal reload_finished(unit: UnitState)
## Seed for combat randomness (spread), so shots are reproducible.
var world_seed := 1

const FACTION_NAMES: Array[String] = ["North", "South"]
const FACTION_COLORS: Array[Color] = [Color(0.3, 0.55, 1.0), Color(1.0, 0.4, 0.2)]

## id -> UnitState
var units := {}
## Simulated time in seconds.
var time := 0.0
## Placed structures (WORLD-BASE-01): buildings and defensive lines, same no-node rule.
var construction := ConstructionState.new()
## UNIT-01A: squad id -> SquadState. Soldiers stay in `units`; a squad lists member ids.
var squads := {}
var _next_id := 1
var _next_squad_id := 1
## COMBAT-02: unit id -> SquadState, rebuilt when membership changes (squad_of was a
## linear search over all squads, called per soldier per frame by the AI).
var _squad_index := {}
var _squad_index_dirty := true


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
		for sq: SquadState in squads.values():
			if sq.has_member(id):
				_drop_member(sq, id)
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
## the player leaves. COMBAT-02: a new order ends a tactical reaction (the player's
## command comes first) unless cancel_reaction is false (Follow keeping its slots up to
## date while a follower briefly takes cover).
func issue_move(id: int, target: Vector3, cancel_reaction := true) -> bool:
	var u := get_unit(id)
	if u == null or u.kind != UnitState.Kind.SOLDIER or not u.alive:
		return false
	u.order = UnitState.Order.MOVE
	u.order_target = target
	u.move_state = UnitState.MoveState.MOVING
	u.anchor_pos = Vector3.INF
	if cancel_reaction:
		_cancel_reaction(u)
	order_changed.emit(u)
	return true


## A player / squad order overrides the soldier's own reaction; it may react again
## after a short pause.
func _cancel_reaction(u: UnitState) -> void:
	if u.tactic != UnitState.Tactic.NONE or u.is_reacting():
		u.clear_reaction()
	u.tactic_cooldown_until = maxf(u.tactic_cooldown_until, time + 3.0)


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


## Individual orders for soldiers that may belong to squads: they leave their squad's
## order (detached) until the squad gets its next order.
func issue_individual_moves(ids: Array, target: Vector3, spacing := 2.5) -> int:
	for id in ids:
		detach(id)
	return issue_group_move(ids, target, spacing)


func detach(unit_id: int) -> void:
	var sq := squad_of(unit_id)
	if sq and not sq.detached.has(unit_id):
		sq.detached.append(unit_id)
		squad_changed.emit(sq)


# --- Squads (UNIT-01A) ------------------------------------------------------------

## Creates a squad from soldiers that are not in another squad yet. The leader defaults
## to the first member.
func add_squad(squad_name: String, faction: int, member_ids: Array, leader := -1) -> SquadState:
	var sq := SquadState.new()
	sq.id = _next_squad_id
	_next_squad_id += 1
	sq.squad_name = squad_name
	sq.faction = faction
	for id in member_ids:
		var u := get_unit(id)
		if u and u.kind == UnitState.Kind.SOLDIER and squad_of(id) == null:
			sq.members.append(id)
	if sq.members.is_empty():
		return null
	sq.leader_id = leader if sq.members.has(leader) else sq.members[0]
	squads[sq.id] = sq
	_squad_index_dirty = true
	squad_changed.emit(sq)
	return sq


func get_squad(id: int) -> SquadState:
	return squads.get(id)


## The squad a unit belongs to, or null.
func squad_of(unit_id: int) -> SquadState:
	if _squad_index_dirty:
		_squad_index.clear()
		for sq: SquadState in squads.values():
			for id in sq.members:
				_squad_index[id] = sq
		_squad_index_dirty = false
	return _squad_index.get(unit_id)


func all_squads() -> Array:
	var out := squads.values()
	out.sort_custom(func(a: SquadState, b: SquadState) -> bool: return a.id < b.id)
	return out


func set_leader(squad_id: int, unit_id: int) -> bool:
	var sq := get_squad(squad_id)
	if sq == null or not sq.has_member(unit_id):
		return false
	sq.leader_id = unit_id
	squad_changed.emit(sq)
	return true


## COMBAT-01a: a killed soldier leaves its squad's members (formation slots, orders) and
## is listed among the squad's fallen.
func mark_fallen(unit_id: int) -> void:
	var sq := squad_of(unit_id)
	if sq == null:
		return
	if not sq.fallen.has(unit_id):
		sq.fallen.append(unit_id)
	_drop_member(sq, unit_id)


func _drop_member(sq: SquadState, unit_id: int) -> void:
	_squad_index_dirty = true
	var i := sq.members.find(unit_id)
	if i >= 0:
		sq.members.remove_at(i)
	i = sq.detached.find(unit_id)
	if i >= 0:
		sq.detached.remove_at(i)
	if sq.members.is_empty():
		squads.erase(sq.id)
	elif sq.leader_id == unit_id:
		sq.leader_id = sq.members[0]
	squad_changed.emit(sq)


func halt(id: int) -> void:
	var u := get_unit(id)
	if u == null:
		return
	u.order = UnitState.Order.NONE
	u.order_target = Vector3.ZERO
	u.move_state = UnitState.MoveState.IDLE
	# COMBAT-02: stopping is a command too; the soldier holds where it stands.
	_cancel_reaction(u)
	u.anchor_pos = u.position
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
	var sq_list := []
	for sq in all_squads():
		sq_list.append(sq.to_dict())
	return {"time": time, "next_id": _next_id, "units": list, "construction": construction.to_dict(),
		"squads": sq_list, "next_squad_id": _next_squad_id}


func restore(snap: Dictionary) -> void:
	units.clear()
	time = snap.get("time", 0.0)
	_next_id = snap.get("next_id", 1)
	for d in snap.get("units", []):
		var u := UnitState.from_dict(d)
		units[u.id] = u
		unit_added.emit(u)
	if snap.has("construction"):
		construction.from_dict(snap.construction)
	_restore_squads(snap)


## Loads a snapshot without replacing the record objects of units that exist in both:
## their fields are overwritten in place, so bodies and proxies that hold them stay
## valid. Units only in the snapshot are added, units missing from it removed. Squads are
## replaced. Construction is saved separately (ConstructionState JSON) and not touched.
## Returns {updated, added, removed}.
func apply_snapshot(snap: Dictionary) -> Dictionary:
	var seen := {}
	var added := 0
	var updated := 0
	for d in snap.get("units", []):
		var fresh := UnitState.from_dict(d)
		seen[fresh.id] = true
		var u := get_unit(fresh.id)
		if u == null:
			units[fresh.id] = fresh
			added += 1
			unit_added.emit(fresh)
			continue
		u.unit_name = fresh.unit_name
		u.kind = fresh.kind
		u.faction = fresh.faction
		u.position = fresh.position
		u.yaw = fresh.yaw
		u.velocity = Vector3.ZERO
		u.health = fresh.health
		u.max_health = fresh.max_health
		u.speed = fresh.speed
		u.order = fresh.order
		u.order_target = fresh.order_target
		u.move_state = fresh.move_state
		u.copy_combat_from(fresh.to_dict())
		updated += 1
	var removed := 0
	for id in units.keys():
		if not seen.has(id):
			remove_unit(id)
			removed += 1
	time = snap.get("time", time)
	_next_id = maxi(_next_id, snap.get("next_id", 1))
	_restore_squads(snap)
	restored.emit()
	return {"updated": updated, "added": added, "removed": removed}


func _restore_squads(snap: Dictionary) -> void:
	squads.clear()
	_squad_index_dirty = true
	for d in snap.get("squads", []):
		var sq := SquadState.from_dict(d)
		squads[sq.id] = sq
	_next_squad_id = snap.get("next_squad_id", squads.size() + 1)
	for sq: SquadState in squads.values():
		squad_changed.emit(sq)


## Text save of units and squads (var_to_str keeps Vector3 and packed arrays exact).
func save_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var snap := snapshot()
	snap.erase("construction")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(var_to_str(snap))
	f.close()
	return OK


func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var snap: Variant = str_to_var(FileAccess.get_file_as_string(path))
	if not snap is Dictionary:
		return ERR_PARSE_ERROR
	return apply_snapshot(snap)

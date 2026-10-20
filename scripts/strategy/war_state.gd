## The strategic layer of WorldState (WORLD-SANDBOX-01): factions, strategic objectives,
## operations and the war log. Plain data, saved and loaded with the units and squads, so
## the war resumes exactly where it was. WarSim is the only code that changes it.
class_name WarState
extends RefCounted

## False in the old test layouts (no war); true in the sandbox.
var active := false
var player_faction := 0
## id -> FactionState / ObjectiveState / OperationState
var factions := {}
var objectives := {}
var operations := {}
var next_op_id := 1
## War log: {t, faction (-1 = everyone), kind, text}. Most recent last, at most MAX_LOG.
var events: Array = []
const MAX_LOG := 200


func faction(id: int) -> FactionState:
	return factions.get(id)


func objective(id: int) -> ObjectiveState:
	return objectives.get(id)


func operation(id: int) -> OperationState:
	return operations.get(id)


func all_objectives() -> Array:
	var out := objectives.values()
	out.sort_custom(func(a: ObjectiveState, b: ObjectiveState) -> bool: return a.id < b.id)
	return out


func active_operations(faction_id := -1) -> Array:
	var out := []
	for o: OperationState in operations.values():
		if o.is_active() and (faction_id < 0 or o.faction == faction_id):
			out.append(o)
	out.sort_custom(func(a: OperationState, b: OperationState) -> bool: return a.id < b.id)
	return out


func owned_by(faction_id: int) -> Array:
	return all_objectives().filter(func(o: ObjectiveState) -> bool: return o.owner == faction_id)


func to_dict() -> Dictionary:
	var f := []
	for x: FactionState in factions.values():
		f.append(x.to_dict())
	var o := []
	for x: ObjectiveState in all_objectives():
		o.append(x.to_dict())
	var p := []
	for x: OperationState in operations.values():
		p.append(x.to_dict())
	return {"active": active, "player_faction": player_faction, "factions": f, "objectives": o, "operations": p,
		"next_op_id": next_op_id, "log": events.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	active = d.get("active", false)
	player_faction = d.get("player_faction", 0)
	factions.clear()
	objectives.clear()
	operations.clear()
	for x in d.get("factions", []):
		var fs := FactionState.from_dict(x)
		factions[fs.id] = fs
	for x in d.get("objectives", []):
		var os := ObjectiveState.from_dict(x)
		objectives[os.id] = os
	for x in d.get("operations", []):
		var op := OperationState.from_dict(x)
		operations[op.id] = op
	next_op_id = d.get("next_op_id", 1)
	events = d.get("log", []).duplicate(true)

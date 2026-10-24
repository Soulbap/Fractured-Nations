## GAMEPLAY-02B: the roles of a squad by position in it (assets/combat/squads/<id>.tres) - data, not code. A fresh squad of n
## soldiers gets slots[0..n-1]; replacements fill the roles the squad lacks first (CombatSim.apply_composition). The
## scenario chooses the table (WarState.rules "squad_composition", default "standard").
class_name SquadComposition
extends Resource

const DIR := "res://assets/combat/squads/"

@export var id := "standard"
@export var display_name := ""
## Role ids in formation order; the first half of a squad is fire team 1 (support), the second half fire team 2.
@export var slots: Array[StringName] = []

static var _cache := {}


static func by_id(comp_id: String) -> SquadComposition:
	if not _cache.has(comp_id):
		var path := DIR + comp_id + ".tres"
		_cache[comp_id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[comp_id]

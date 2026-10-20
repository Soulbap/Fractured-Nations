## A complete equipment configuration for the shared infantry character.
##
## Pure data: the same rig, body and animation set are used for every loadout. A new
## configuration is a new .tres in assets/characters/infantry/loadouts/ listing existing
## (or new) InfantryEquipment pieces; no code changes are needed.
class_name InfantryLoadout
extends Resource

const DIR := "res://assets/characters/infantry/loadouts/"

@export var id := ""
@export var display_name := ""
@export var items: Array[InfantryEquipment] = []

static var _cache := {}


static func by_id(loadout_id: String) -> InfantryLoadout:
	if not _cache.has(loadout_id):
		var path := DIR + loadout_id + ".tres"
		_cache[loadout_id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[loadout_id]


## Deterministic default for units that have no loadout yet: every third soldier carries
## the heavy loadout. The result is stored in the UnitState so it persists.
static func default_for(unit_id: int) -> String:
	return "B_heavy" if unit_id % 3 == 2 else "A_standard"


func item_in_slot(slot: String) -> InfantryEquipment:
	for it in items:
		if it.slot == slot:
			return it
	return null

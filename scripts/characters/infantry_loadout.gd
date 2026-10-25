## A complete equipment configuration for the shared infantry character.
##
## Pure data: the same rig, body and animation set are used for every loadout. A new
## configuration is a new .tres in assets/characters/infantry/loadouts/ listing existing
## (or new) InfantryEquipment pieces; no code changes are needed.
class_name InfantryLoadout
extends Resource

## VISUAL-03: the loadouts of the active asset root (InfantryCharacter.asset_root(): the staged new soldier with
## --soldier-v03, else the shipped one).
static func dir() -> String:
	return InfantryCharacter.asset_root() + "loadouts/"

@export var id := ""
@export var display_name := ""
@export var items: Array[InfantryEquipment] = []

static var _cache := {}


static func by_id(loadout_id: String) -> InfantryLoadout:
	if not _cache.has(loadout_id):
		var path := dir() + loadout_id + ".tres"
		_cache[loadout_id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[loadout_id]


## Deterministic default for units that have no loadout yet. WORLD-INTEGRATION-03: the
## faction's configured family (WorldState.FACTION_LOADOUTS) when it has one and the
## resource exists; otherwise every third soldier carries the heavy loadout. The result is
## stored in the UnitState so it persists (save/load, promotion, possession).
static func default_for(unit_id: int, faction := -1) -> String:
	var fam := WorldState.faction_loadout(faction)
	if fam != "" and by_id(fam) != null:
		return fam
	return "B_heavy" if unit_id % 3 == 2 else "A_standard"


func item_in_slot(slot: String) -> InfantryEquipment:
	for it in items:
		if it.slot == slot:
			return it
	return null

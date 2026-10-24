## GAMEPLAY-02B: what a soldier of a squad carries and does - pure data (assets/combat/roles/<id>.tres). The weapon is a
## WeaponDef id (the same rules for AI and player); the look comes from the faction's loadout family with this role's
## suffix (NATO_rifleman -> NATO_mg) when that loadout exists, else the faction's rifleman. Assigned once to a fresh
## soldier (CombatSim.apply_composition) and kept on the record (UnitState.role), so saves, possession and promotion agree.
class_name InfantryRole
extends Resource

const DIR := "res://assets/combat/roles/"

@export var id: StringName = &"rifleman"
@export var display_name := "Rifleman"
## Short label for the RTS roster / HUD ("MG", "GR").
@export var short := ""
@export var weapon_id: StringName = &"rifle"
## Loadout family suffix ("" = the faction's rifleman loadout).
@export var loadout_suffix := ""
## GAMEPLAY-02C: hand grenades carried, and a secondary weapon (WeaponDef id, e.g. the light anti-structure launcher) with
## its rounds; none = &"".
@export var grenades := 1
@export var secondary_id: StringName = &""
@export var secondary_rounds := 0

static var _cache := {}


static func by_id(role_id: StringName) -> InfantryRole:
	if not _cache.has(role_id):
		var path := DIR + String(role_id) + ".tres"
		_cache[role_id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[role_id]


## The loadout a soldier of faction f in this role wears.
func loadout_for(faction: int) -> String:
	var fam := WorldState.faction_loadout(faction)
	if fam != "" and loadout_suffix != "":
		var lo := fam.replace("rifleman", loadout_suffix)
		if InfantryLoadout.by_id(lo) != null:
			return lo
	return fam

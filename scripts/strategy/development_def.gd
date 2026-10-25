## GAMEPLAY-04B: one Military Development project - pure data (assets/development/<id>.tres). What it costs and needs, and
## what it makes possible: structures the faction may build, weapons it may procure (WeaponDef ids), infantry roles its
## squads may be equipped with (InfantryRole ids) and a few real effects of existing systems. MilitaryDevelopment
## (WarSim.dev) is the only code that reads these and the faction's state (FactionState.dev).
##
## Unlocked is not free: a building is still paid and built, a weapon still procured (WeaponDef.procure_*), a soldier still
## recruited. Knowledge is permanent; `requires_facility` is the facility (FacilityDefs kind) that must be operational while
## the project runs (it pauses without one), never a condition for keeping the result.
class_name DevelopmentDef
extends Resource

const DIR := "res://assets/development/"
## Branch ids in menu order and their titles.
const BRANCHES: Array[StringName] = [&"base", &"infantry", &"operations"]
const BRANCH_NAMES := {&"base": "Base & Logistics", &"infantry": "Infantry & Weapons", &"operations": "Operations & Intelligence"}

@export var id: StringName = &""
@export var branch: StringName = &"base"
## Column in its branch (0 = what a faction starts with).
@export var tier := 0
@export var display_name := ""
## One line on the card.
@export var summary := ""
## What the player gets, in words (the details panel; the unlock lists below are shown too).
@export_multiline var description := ""
## Developments that must be complete first.
@export var requires: Array[StringName] = []
## FacilityDefs kind that must be operational at one of the faction's bases to start and to progress (&"" = none).
@export var requires_facility: StringName = &""
## An operational milestone (MilitaryDevelopment.milestone): &"" none, &"objectives" objectives held, &"captured"
## objectives ever captured, &"caches" supply caches secured, &"kills" enemy soldiers killed; at least milestone_count.
@export var milestone: StringName = &""
@export var milestone_count := 1
## GAMEPLAY-04D: weapon types (WeaponDef ids) the faction must have found and delivered to a base first (discovery drives
## development: research alone does not open every weapon).
@export var requires_discovery: Array[StringName] = []
## Resources paid when the project starts ({"supplies": kg, "ammo": kg}); refunded in full when it is cancelled.
@export var cost := {}
## Simulated seconds of development while its requirements hold.
@export var time_s := 120.0
@export var structures: Array[StringName] = []
@export var weapons: Array[StringName] = []
@export var roles: Array[StringName] = []
## Effects on existing systems while complete: "intel_delay_mult" (reports reach the faction faster), "dev_slots" (more
## projects at once). Numbers ending in _mult multiply, the others add.
@export var effects := {}
## Known from the start by every faction that uses Military Development.
@export var initial := false
## False: a future capability the game does not have yet - shown, never startable.
@export var available := true

static var _all: Array[DevelopmentDef] = []
static var _by_id := {}


static func all() -> Array[DevelopmentDef]:
	if _all.is_empty():
		var dir := DirAccess.open(DIR)
		if dir:
			for f in dir.get_files():
				f = f.trim_suffix(".remap")
				if f.ends_with(".tres"):
					var d := load(DIR + f) as DevelopmentDef
					if d and d.id != &"":
						_all.append(d)
						_by_id[d.id] = d
		_all.sort_custom(func(a: DevelopmentDef, b: DevelopmentDef) -> bool:
			var ba := BRANCHES.find(a.branch)
			var bb := BRANCHES.find(b.branch)
			return ba < bb if ba != bb else (a.tier < b.tier if a.tier != b.tier else String(a.id) < String(b.id)))
	return _all


static func by_id(dev_id: StringName) -> DevelopmentDef:
	if _all.is_empty():
		all()
	return _by_id.get(dev_id)


static func in_branch(b: StringName) -> Array[DevelopmentDef]:
	var out: Array[DevelopmentDef] = []
	for d in all():
		if d.branch == b:
			out.append(d)
	return out

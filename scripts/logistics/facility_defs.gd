## What the buildings of the construction catalog do (LOGISTICS-01 / BASE-02): a table keyed by
## StructureDef id, so the placeable structures themselves stay pure construction data and a
## facility's gameplay is data too. A StructureState of one of these types carries the state
## (inventory, queues) and the table says what it is for.
##
## Functions with a real effect (nothing here is a "+5 %" bonus):
##   hq          designates a base, holds a small inventory, the faction's command point
##   barracks    recruits infantry squads (costs supplies and time), stages troops
##   supply      stores all three supply types, receives deliveries, loads vehicles, resupplies
##   vehicle     provides vehicles for supplies (limited stock), docks and refuels them
##   ammo        ammunition-only store
##   fuel        fuel-only store; refuels vehicles
##   storage     general stores
##   repair      restores vehicle condition (supplies)
##   training    (placeable; no mechanic yet)
class_name FacilityDefs
extends RefCounted

const TABLE := {
	&"hq_building": {"kind": &"hq", "name": "Headquarters", "storage": 6000.0},
	&"barracks_block": {"kind": &"barracks", "name": "Barracks", "storage": 1500.0},
	&"barracks": {"kind": &"barracks", "name": "Barracks module", "storage": 600.0},
	&"supply_depot": {"kind": &"supply", "name": "Supply depot", "storage": 60000.0},
	&"supply_storage": {"kind": &"supply", "name": "Supply storage", "storage": 12000.0},
	&"vehicle_depot": {"kind": &"vehicle", "name": "Vehicle depot", "storage": 8000.0},
	&"ammo_magazine": {"kind": &"ammo", "name": "Ammunition magazine", "storage": 30000.0, "allowed": [&"ammo"]},
	&"fuel_point": {"kind": &"fuel", "name": "Fuel point", "storage": 20000.0, "allowed": [&"fuel"]},
	&"fuel_bladder_berm": {"kind": &"fuel", "name": "Fuel bladder", "storage": 40000.0, "allowed": [&"fuel"]},
	&"container_yard": {"kind": &"storage", "name": "Container yard", "storage": 20000.0},
	&"repair_bay": {"kind": &"repair", "name": "Repair bay"},
	&"training_facility": {"kind": &"training", "name": "Training facility"},
}

## Stock the first supply depot of the player's faction starts with: the scenario's initial
## stockpile. Every further depot starts empty and has to be filled by trucks.
const START_STOCK := {&"ammo": 4000.0, &"fuel": 6000.0, &"supplies": 9000.0}
## Metres from a facility's dock point within which a vehicle counts as docked.
const DOCK_REACH_M := 9.0


static func has(type_id: StringName) -> bool:
	return TABLE.has(type_id)


static func kind_of(type_id: StringName) -> StringName:
	return TABLE[type_id].kind if TABLE.has(type_id) else &""


static func display_name(type_id: StringName) -> String:
	return TABLE[type_id].name if TABLE.has(type_id) else String(type_id)


static func storage_of(type_id: StringName) -> float:
	return TABLE[type_id].get("storage", 0.0) if TABLE.has(type_id) else 0.0


static func is_store(type_id: StringName) -> bool:
	return storage_of(type_id) > 0.0


## An empty inventory configured for the type, or null for types without storage.
static func make_inventory(type_id: StringName) -> Inventory:
	if not is_store(type_id):
		return null
	var allowed: Array[StringName] = []
	for a in TABLE[type_id].get("allowed", []):
		allowed.append(a)
	return Inventory.make(storage_of(type_id), allowed)


## Where a vehicle stops to be loaded, unloaded or refuelled: in front of the building (its
## local -Z), `slot` spreads several vehicles sideways. World position, y = ground height
## is left to the caller.
static func dock_point(s: StructureState, slot := 0) -> Vector3:
	var def := StructureCatalog.get_def(s.type_id)
	var front := -4.0
	if def != null:
		front = def.bounds().position.z
	var lateral := ((slot + 1) / 2) * 5.5 * (1.0 if slot % 2 == 1 else -1.0)
	var local := Vector3(lateral, 0.0, front - 6.5)
	var b := Basis(Vector3.UP, s.yaw)
	return s.position + b * local

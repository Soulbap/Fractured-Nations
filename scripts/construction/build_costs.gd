## What a structure costs to build (GAMEPLAY-01B): one table for the player and the AI factions (AiBases.BUILD_COST is
## this table). Two numbers per type:
##   cost  supplies (kg), paid once when the order is given (the player: BaseSim.faction_pay; the AI: BaseSim.pay);
##   work  soldier-seconds of construction (a site of 240 is built by eight soldiers in 30 s, by four in 60 s).
## GAMEPLAY-02 (controls): the work was cut after play testing (waiting dominated the opening): field works to about 40 % of
## the GAMEPLAY-01B numbers, mid-size buildings to about 50 %, the large and strategic ones to about 60 % - small things go up
## in seconds, a headquarters still takes a squad over a minute. Costs (supplies) are unchanged.
## Types not listed are priced from their footprint (small props cheap, large buildings dear); lines (HESCO, fences,
## sandbag walls) per module. Roads and paved areas are not priced in this milestone (they stay instant and free).
class_name BuildCosts
extends RefCounted

const COST := {
	&"command_post": 400.0, &"hq_building": 900.0, &"barracks_block": 550.0, &"barracks": 250.0,
	&"supply_depot": 450.0, &"supply_storage": 200.0, &"vehicle_depot": 750.0, &"ammo_magazine": 320.0,
	&"fuel_point": 160.0, &"fuel_bladder_berm": 200.0, &"container_yard": 250.0, &"repair_bay": 260.0,
	&"training_facility": 300.0, &"vehicle_parking_pad": 120.0, &"guard_tower_steel": 150.0, &"guard_tower": 120.0,
	&"sandbag_fighting_position": 45.0, &"dfp_sandbag_ring": 60.0, &"mg_nest": 80.0, &"bunker_fighting": 220.0,
	&"medical_station": 200.0, &"comms_station": 180.0, &"checkpoint_station": 120.0,
	&"fighting_position": 50.0, &"mg_emplacement": 90.0,
}
const WORK := {
	&"command_post": 240.0, &"hq_building": 600.0, &"barracks_block": 380.0, &"barracks": 170.0,
	&"supply_depot": 320.0, &"supply_storage": 140.0, &"vehicle_depot": 430.0, &"ammo_magazine": 230.0,
	&"fuel_point": 120.0, &"fuel_bladder_berm": 140.0, &"container_yard": 140.0, &"repair_bay": 180.0,
	&"training_facility": 230.0, &"vehicle_parking_pad": 90.0, &"guard_tower_steel": 140.0, &"guard_tower": 120.0,
	&"sandbag_fighting_position": 40.0, &"dfp_sandbag_ring": 50.0, &"mg_nest": 60.0, &"bunker_fighting": 200.0,
	&"medical_station": 170.0, &"comms_station": 150.0, &"checkpoint_station": 100.0,
	&"fighting_position": 45.0, &"mg_emplacement": 70.0,
}
## Lines: per module.
const MODULE_COST := {&"hesco": 12.0, &"hesco_tall": 18.0, &"sandbag_wall_2m": 6.0, &"sandbag_wall_low_2m": 4.0, &"t_wall": 20.0}
const MODULE_WORK := {&"hesco": 8.0, &"hesco_tall": 12.0, &"sandbag_wall_2m": 5.0, &"sandbag_wall_low_2m": 4.0, &"t_wall": 12.0}


## Supplies for `modules` modules of a line, or one building. 0 for roads and paved areas.
static func cost_of(def: StructureDef, modules := 1) -> float:
	if def == null or def.is_surface():
		return 0.0
	if def.linear:
		return float(MODULE_COST.get(def.id, 5.0)) * maxi(modules, 1)
	if COST.has(def.id):
		return COST[def.id]
	return clampf(roundf(def.size.x * def.size.z * 0.5 / 5.0) * 5.0, 15.0, 600.0)


## Soldier-seconds of work for the same.
static func work_of(def: StructureDef, modules := 1) -> float:
	if def == null or def.is_surface():
		return 0.0
	if def.linear:
		return float(MODULE_WORK.get(def.id, 4.0)) * maxi(modules, 1)
	if WORK.has(def.id):
		return WORK[def.id]
	return clampf(cost_of(def) * 0.6, 30.0, 540.0)


static func supplies(qty: float) -> Dictionary:
	return {&"supplies": qty}

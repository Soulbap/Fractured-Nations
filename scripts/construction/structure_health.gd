## How much a structure can take (GAMEPLAY-01F): one table for every type, like BuildCosts. Two numbers per type:
##   hp      condition points of a finished structure (lines: per built module)
##   resist  the share of a weapon's damage a hit does to it (WeaponDef.damage x structure_mult x resist): sandbags, HESCO
##           and steel take almost nothing from a rifle, light buildings (containers, shelters) a little more
## A structure below DISABLE_FRAC of its points is disabled: it stands (and keeps its owner, base and stores) but does not
## work - no recruiting, storage, beds or firing positions - until it is repaired. At 0 it is destroyed: the same, and it
## looks wrecked. Nothing is deleted by damage; a base is never removed because a building was destroyed.
class_name StructureHealth
extends RefCounted

const DISABLE_FRAC := 0.35
## A repair restores the structure for this share of its build cost / work per missing share of its points.
const REPAIR_COST_SHARE := 0.6
const REPAIR_WORK_SHARE := 0.6

const HP := {
	&"command_post": 900.0, &"hq_building": 2400.0, &"barracks_block": 1600.0, &"barracks": 700.0, &"supply_depot": 2000.0,
	&"supply_storage": 1400.0, &"vehicle_depot": 1800.0, &"ammo_magazine": 2200.0, &"fuel_point": 700.0, &"guard_tower_steel": 900.0,
	&"guard_tower": 600.0, &"fighting_position": 700.0, &"mg_emplacement": 900.0, &"sandbag_fighting_position": 500.0,
	&"bunker_fighting": 3000.0, &"mg_nest": 700.0, &"dfp_sandbag_ring": 600.0,
}
const MODULE_HP := {&"hesco": 220.0, &"hesco_tall": 360.0, &"sandbag_wall_2m": 140.0, &"sandbag_wall_low_2m": 110.0, &"t_wall": 400.0, &"fence": 40.0, &"concrete_barrier": 300.0}
const RESIST := {
	&"hesco": 0.01, &"hesco_tall": 0.01, &"sandbag_wall_2m": 0.015, &"sandbag_wall_low_2m": 0.015, &"fighting_position": 0.015,
	&"mg_emplacement": 0.015, &"sandbag_fighting_position": 0.015, &"dfp_sandbag_ring": 0.015, &"mg_nest": 0.015, &"bunker_fighting": 0.005,
	&"guard_tower_steel": 0.01, &"ammo_magazine": 0.01, &"t_wall": 0.005, &"concrete_barrier": 0.005, &"guard_tower": 0.04,
}
const RESIST_BUILDING := 0.06
## GAMEPLAY-02C: the share of an explosive's structure damage (WeaponDef.blast_structure) a structure takes: earth-filled
## walls soak most of it, light buildings and towers much less.
const BLAST_RESIST := {
	&"hesco": 0.35, &"hesco_tall": 0.3, &"sandbag_wall_2m": 0.5, &"sandbag_wall_low_2m": 0.5, &"fighting_position": 0.6,
	&"mg_emplacement": 0.6, &"sandbag_fighting_position": 0.6, &"dfp_sandbag_ring": 0.6, &"mg_nest": 0.6, &"bunker_fighting": 0.2,
	&"guard_tower_steel": 0.7, &"guard_tower": 0.9, &"ammo_magazine": 0.4, &"t_wall": 0.15, &"concrete_barrier": 0.15,
}
const BLAST_RESIST_BUILDING := 1.0


static func max_hp(s: StructureState) -> float:
	var def := StructureCatalog.get_def(s.type_id)
	if def == null or def.is_surface():
		return 0.0
	if def.linear:
		return float(MODULE_HP.get(def.id, 150.0)) * maxi(s.built_count(), 1)
	if HP.has(def.id):
		return HP[def.id]
	return clampf(roundf(def.size.x * def.size.z * 12.0 / 50.0) * 50.0, 200.0, 2500.0)


static func resist(type_id: StringName) -> float:
	return float(RESIST.get(type_id, RESIST_BUILDING))


static func blast_resist(type_id: StringName) -> float:
	return float(BLAST_RESIST.get(type_id, BLAST_RESIST_BUILDING))


## Supplies a repair of s costs now (0 when it needs none): the build cost per missing share, REPAIR_COST_SHARE of it.
static func repair_cost(s: StructureState) -> float:
	var def := StructureCatalog.get_def(s.type_id)
	var missing := 1.0 - s.health_frac()
	if def == null or missing <= 0.001:
		return 0.0
	return ceilf(BuildCosts.cost_of(def, s.built_count() if s.is_line() else 1) * missing * REPAIR_COST_SHARE)


## Soldier-seconds of work the repair takes.
static func repair_work(s: StructureState) -> float:
	var def := StructureCatalog.get_def(s.type_id)
	var missing := 1.0 - s.health_frac()
	if def == null or missing <= 0.001:
		return 0.0
	return maxf(20.0, BuildCosts.work_of(def, s.built_count() if s.is_line() else 1) * missing * REPAIR_WORK_SHARE)

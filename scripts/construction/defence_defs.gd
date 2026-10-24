## Defensive positions of the structure catalog (GAMEPLAY-01C): a table keyed by StructureDef id, like FacilityDefs, so
## a fortification's gameplay stays data next to the construction data. A slot is a place where one soldier fights from
## the structure; SquadPositions.fort_slots turns it into world positions through the structure's transform and
## SquadTactics assigns soldiers to it (UnitState.fort_slot). Nothing here is state: who holds a slot is read from the
## soldiers' records, so a slot is free again as soon as its soldier dies, leaves or is given another order.
##
## Building slots (local, Godot axes: -Z is the front, metres; the numbers follow the asset's IP_* / DEF_* markers):
##   p       where the soldier stands (y > 0.5: an elevated slot - tower platforms, reached through `access`)
##   yaw     the direction the slot faces (radians, 0 = the structure's front, -Z)
##   arc     the sector it covers (degrees, centred on yaw)
##   access  the ground point the soldier walks to before he takes the slot (outside every collision box)
##   role    "" any soldier; "mg" a machine-gun position (an MG-armed soldier first, any soldier when none is there)
## Line types (HESCO, sandbag walls): a slot behind every `every`-th module, `back` m behind the wall's centre line, facing
## across the wall; which side is "behind" is decided when the slots are read (the side towards the base, or both sides).
class_name DefenceDefs
extends RefCounted

const TABLE := {
	# Timber guard tower (WORLD-BASE-01): platform at 4.05 m, parapet to 5.15 m, stair foot at the back right.
	&"guard_tower": {"slots": [
		{"p": Vector3(-0.55, 4.05, -0.7), "yaw": 0.6, "arc": 220.0, "access": Vector3(0.95, 0.0, 6.7)},
		{"p": Vector3(0.6, 4.05, 0.35), "yaw": -2.2, "arc": 220.0, "access": Vector3(0.95, 0.0, 6.7)}]},
	# Steel guard tower (GAMEPLAY-01C rebuild): cabin floor 4.57 m, wall to 5.65 m, open firing band to 6.35 m.
	&"guard_tower_steel": {"slots": [
		{"p": Vector3(-0.55, 4.57, -0.55), "yaw": 0.8, "arc": 220.0, "access": Vector3(-1.85, 0.0, -2.4)},
		{"p": Vector3(0.55, 4.57, 0.55), "yaw": -2.35, "arc": 220.0, "access": Vector3(-1.85, 0.0, -2.4)}]},
	# GAMEPLAY-01C sandbag fighting position: 1.15 m parapet, firing step, open rear.
	&"fighting_position": {"slots": [
		{"p": Vector3(-0.6, 0.0, -0.35), "yaw": 0.15, "arc": 150.0, "access": Vector3(0.0, 0.0, 2.3)},
		{"p": Vector3(0.6, 0.0, -0.35), "yaw": -0.15, "arc": 150.0, "access": Vector3(0.0, 0.0, 2.3)}]},
	# GAMEPLAY-01C machine-gun emplacement: 1.2 m front parapet, roof at 2.2 m, wide forward slit; gunner and assistant.
	&"mg_emplacement": {"slots": [
		{"p": Vector3(0.0, 0.0, -0.75), "yaw": 0.0, "arc": 130.0, "role": "mg", "access": Vector3(0.0, 0.0, 2.6)},
		{"p": Vector3(-0.95, 0.0, -0.45), "yaw": 0.35, "arc": 110.0, "access": Vector3(0.0, 0.0, 2.6)}]},
	# Two-man sandbag position (ASSET-PRODUCTION-01 prop): 0.72 m walls, riflemen kneel at the firing gap.
	&"sandbag_fighting_position": {"slots": [
		{"p": Vector3(-0.6, 0.0, -0.4), "yaw": 0.1, "arc": 140.0, "access": Vector3(0.0, 0.0, 2.2)},
		{"p": Vector3(0.6, 0.0, -0.4), "yaw": -0.1, "arc": 140.0, "access": Vector3(0.0, 0.0, 2.2)}]},
	# Lines: low enough to fire over (HESCO MIL1 1.37 m, sandbag walls 0.96 m); the tall HESCO is a wall, not a position.
	&"hesco": {"line": true, "every": 3, "back": 1.05, "arc": 120.0},
	&"sandbag_wall_2m": {"line": true, "every": 1, "back": 0.8, "arc": 120.0},
	&"sandbag_wall_low_2m": {"line": true, "every": 1, "back": 0.8, "arc": 120.0},
}


static func has(type_id: StringName) -> bool:
	return TABLE.has(type_id)


static func is_line(type_id: StringName) -> bool:
	return TABLE.has(type_id) and bool(TABLE[type_id].get("line", false))


static func slots_of(type_id: StringName) -> Array:
	return TABLE[type_id].get("slots", []) if TABLE.has(type_id) else []


static func line_rule(type_id: StringName) -> Dictionary:
	return TABLE[type_id] if is_line(type_id) else {}


## How many soldiers a structure can take (lines: per built module group).
static func capacity(s: StructureState) -> int:
	if not TABLE.has(s.type_id):
		return 0
	if is_line(s.type_id):
		return ceili(float(s.built_count()) / float(int(TABLE[s.type_id].every))) * 2
	return slots_of(s.type_id).size()


## Direction a yaw faces (yaw 0 = -Z).
static func yaw_dir(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

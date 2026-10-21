## Persistent logistics state that does not belong to one unit or structure (LOGISTICS-01):
## convoys and the bookkeeping of the scenario's starting stockpile. Plain data in WorldState,
## saved and loaded with it. Inventories themselves live on the structures (depots) and
## vehicles (cargo); automation rules and bases (phase D) extend this record.
class_name LogisticsState
extends RefCounted

## convoy id -> {members: [vehicle ids, column order], dest: Vector3, leader: int, name: String}
var convoys := {}
var next_convoy_id := 1
## faction -> true once its starting stockpile was placed in its first supply depot.
var starter_given := {}
## Automation rules (see LogisticsSim): [{id, kind, ...}] saved as plain dictionaries.
var rules: Array = []
var next_rule_id := 1


func to_dict() -> Dictionary:
	var cv := {}
	for id in convoys:
		var c: Dictionary = convoys[id]
		cv[str(id)] = {"members": c.members, "dest": c.dest, "leader": c.leader, "name": c.name}
	return {"convoys": cv, "next_convoy": next_convoy_id, "starter": starter_given.duplicate(), "rules": rules.duplicate(true), "next_rule": next_rule_id}


func from_dict(d: Dictionary) -> void:
	convoys = {}
	for k in d.get("convoys", {}):
		var c: Dictionary = d.convoys[k]
		convoys[int(k)] = {"members": Array(c.members), "dest": c.dest, "leader": int(c.leader), "name": String(c.name)}
	next_convoy_id = int(d.get("next_convoy", 1))
	starter_given = {}
	for k in d.get("starter", {}):
		starter_given[int(k)] = true
	rules = Array(d.get("rules", [])).duplicate(true)
	next_rule_id = int(d.get("next_rule", 1))

## Authoritative state of one squad: a named group of soldiers with a leader, an order
## and a loose formation (UNIT-01A).
##
## Plain data, part of WorldState like UnitState. The soldiers stay independent units;
## the squad only records who belongs to it and what it was told to do. WorldSim turns a
## squad order into ordinary per-soldier move orders (one formation slot each), so bodies
## and the abstract tier execute it with the code they already have.
class_name SquadState
extends RefCounted

enum Order { NONE, MOVE, HOLD, FOLLOW, REGROUP }
enum Formation { LINE, COLUMN }
## Progress of the current order (set by WorldSim, for the HUD and tests).
enum Status { IDLE, MOVING, DONE, PARTIAL }

const ORDER_NAMES: Array[String] = ["None", "Move", "Hold", "Follow", "Regroup"]
const FORMATION_NAMES: Array[String] = ["Line", "Column"]

var id := 0
var squad_name := ""
var faction := 0
## Unit ids, leader first after creation (order is the slot order of the formation).
var members := PackedInt32Array()
var leader_id := -1
var order := Order.NONE
## MOVE: formation centre; REGROUP: regroup point (INF = around the leader).
var order_target := Vector3.INF
## Facing of the formation (radians, 0 = -Z), set when the order is given.
var order_yaw := 0.0
## FOLLOW: unit to follow (a squad is followed through its leader, follow_squad_id).
var follow_unit_id := -1
var follow_squad_id := -1
var formation := Formation.LINE
## Distance between neighbouring formation slots (m).
var spacing := 3.0
## Members given an individual order since the last squad order; the squad order does
## not drive them until the next squad order or a regroup.
var detached := PackedInt32Array()
var status := Status.IDLE
## Members that reported BLOCKED on the current order (genuinely unreachable slot).
var blocked := PackedInt32Array()


func has_member(unit_id: int) -> bool:
	return members.has(unit_id)


func is_detached(unit_id: int) -> bool:
	return detached.has(unit_id)


func order_name() -> String:
	return ORDER_NAMES[order]


func formation_name() -> String:
	return FORMATION_NAMES[formation]


func to_dict() -> Dictionary:
	return {
		"id": id, "name": squad_name, "faction": faction, "members": Array(members),
		"leader": leader_id, "order": order, "order_target": order_target, "order_yaw": order_yaw,
		"follow_unit": follow_unit_id, "follow_squad": follow_squad_id,
		"formation": formation, "spacing": spacing, "detached": Array(detached),
		"status": status, "blocked": Array(blocked),
	}


static func from_dict(d: Dictionary) -> SquadState:
	var s := SquadState.new()
	s.id = d.get("id", 0)
	s.squad_name = d.get("name", "")
	s.faction = d.get("faction", 0)
	s.members = PackedInt32Array(d.get("members", []))
	s.leader_id = d.get("leader", -1)
	s.order = d.get("order", Order.NONE)
	s.order_target = d.get("order_target", Vector3.INF)
	s.order_yaw = d.get("order_yaw", 0.0)
	s.follow_unit_id = d.get("follow_unit", -1)
	s.follow_squad_id = d.get("follow_squad", -1)
	s.formation = d.get("formation", Formation.LINE)
	s.spacing = d.get("spacing", 3.0)
	s.detached = PackedInt32Array(d.get("detached", []))
	s.status = d.get("status", Status.IDLE)
	s.blocked = PackedInt32Array(d.get("blocked", []))
	return s

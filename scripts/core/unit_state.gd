## Authoritative state of one unit (soldier or vehicle).
##
## Plain data with no scene nodes. A unit exists here whether or not a physical body
## currently represents it; bodies (SoldierBody, VehicleBody) are the detailed-tier
## presentation of this record and write their physics result back into it every tick.
## Units without a body are moved by WorldSim's abstract step (the future distant tier).
class_name UnitState
extends RefCounted

enum Kind { SOLDIER, VEHICLE }
enum Order { NONE, MOVE }
enum MoveState { IDLE, MOVING, ARRIVED, BLOCKED }

var id := 0
var unit_name := ""
var kind := Kind.SOLDIER
var faction := 0
var position := Vector3.ZERO
## Heading around +Y in radians (Godot convention, 0 = facing -Z).
var yaw := 0.0
var velocity := Vector3.ZERO
var health := 100.0
var max_health := 100.0
## Ground speed in m/s used by the abstract tier; bodies use their own controller speed.
var speed := 4.5
var order := Order.NONE
var order_target := Vector3.ZERO
var move_state := MoveState.IDLE
## True while the player drives this unit directly (orders are suspended, not lost).
var player_controlled := false
## True while a physical body executes this unit (set by WorldSim when a body binds).
var has_body := false


func is_vehicle() -> bool:
	return kind == Kind.VEHICLE


func has_order() -> bool:
	return order != Order.NONE


func kind_name() -> String:
	return "vehicle" if kind == Kind.VEHICLE else "soldier"


func to_dict() -> Dictionary:
	return {
		"id": id, "name": unit_name, "kind": kind, "faction": faction,
		"position": position, "yaw": yaw, "velocity": velocity,
		"health": health, "max_health": max_health, "speed": speed,
		"order": order, "order_target": order_target, "move_state": move_state,
		"player_controlled": player_controlled, "has_body": has_body,
	}


static func from_dict(d: Dictionary) -> UnitState:
	var u := UnitState.new()
	u.id = d.get("id", 0)
	u.unit_name = d.get("name", "")
	u.kind = d.get("kind", Kind.SOLDIER)
	u.faction = d.get("faction", 0)
	u.position = d.get("position", Vector3.ZERO)
	u.yaw = d.get("yaw", 0.0)
	u.velocity = d.get("velocity", Vector3.ZERO)
	u.health = d.get("health", 100.0)
	u.max_health = d.get("max_health", 100.0)
	u.speed = d.get("speed", 4.5)
	u.order = d.get("order", Order.NONE)
	u.order_target = d.get("order_target", Vector3.ZERO)
	u.move_state = d.get("move_state", MoveState.IDLE)
	u.player_controlled = d.get("player_controlled", false)
	u.has_body = d.get("has_body", false)
	return u

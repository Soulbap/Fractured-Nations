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

# --- Combat (COMBAT-01a). Authoritative weapon and life state; WeaponDef is static. ---
var alive := true
## WeaponDef id (assets/combat/<id>.tres); empty = unarmed.
var weapon_id: StringName = &""
var mag := 0
var reserve := 0
var fire_auto := true
## Simulation time (WorldState.time) from which the next shot may leave the barrel.
var next_shot_at := 0.0
## Simulation time at which a running reload completes (-1 = not reloading).
var reload_until := -1.0
## Shots fired so far; with the unit id it seeds the spread of each shot.
var shot_counter := 0
## Extra spread from sustained fire (degrees) as of last_shot_at.
var bloom := 0.0
var last_shot_at := -1.0e9
var died_at := -1.0
## Unit that fired the killing shot (-1 = none / unknown).
var killer_id := -1


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
		"alive": alive, "weapon_id": weapon_id, "mag": mag, "reserve": reserve, "fire_auto": fire_auto,
		"next_shot_at": next_shot_at, "reload_until": reload_until, "shot_counter": shot_counter,
		"bloom": bloom, "last_shot_at": last_shot_at, "died_at": died_at, "killer_id": killer_id,
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
	u.copy_combat_from(d)
	return u


## Combat fields from a saved dictionary (shared by from_dict and in-place loading).
func copy_combat_from(d: Dictionary) -> void:
	alive = d.get("alive", true)
	weapon_id = StringName(d.get("weapon_id", ""))
	mag = d.get("mag", 0)
	reserve = d.get("reserve", 0)
	fire_auto = d.get("fire_auto", true)
	next_shot_at = d.get("next_shot_at", 0.0)
	reload_until = d.get("reload_until", -1.0)
	shot_counter = d.get("shot_counter", 0)
	bloom = d.get("bloom", 0.0)
	last_shot_at = d.get("last_shot_at", -1.0e9)
	died_at = d.get("died_at", -1.0)
	killer_id = d.get("killer_id", -1)


func is_reloading() -> bool:
	return reload_until >= 0.0

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
## COMBAT-01b combat state of the soldier's AI (CombatBrain). PLAYER: possessed, the AI
## neither perceives nor fires for it.
enum AiState { IDLE, OBSERVING, ENGAGING, RELOADING, LOST_TARGET, DEAD, PLAYER }
const AI_STATE_NAMES: Array[String] = ["idle", "observing", "engaging", "reloading", "lost target", "dead", "player"]

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

# --- AI combat (COMBAT-01b). Written by CombatBrain only; persisted with the unit. ---
var ai_state := AiState.IDLE
## Enemy the soldier is tracking (-1 = none).
var target_id := -1
## Simulation time the target was last seen, and where (last known position).
var target_seen_at := -1.0e9
var target_last_pos := Vector3.INF
## Whether the target was visible at the last perception update.
var target_visible := false
## Aim height above the target's feet that was visible (torso or head).
var target_aim_y := 1.0
## Simulation time from which the first shot at a newly acquired target may leave.
var aim_ready_at := 0.0
## Rounds left in the current burst and when the next burst may start.
var burst_left := 0
var next_burst_at := 0.0
## Direction the soldier looks / turns to while standing (NAN = keep heading): the
## target, a reported contact or where it was shot from.
var watch_yaw := NAN
var watch_until := -1.0
## Why the AI is not firing right now (debugging; not saved).
var ai_reason := ""


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
		"ai_state": ai_state, "target_id": target_id, "target_seen_at": target_seen_at, "target_last_pos": target_last_pos,
		"target_visible": target_visible, "target_aim_y": target_aim_y, "aim_ready_at": aim_ready_at,
		"burst_left": burst_left, "next_burst_at": next_burst_at, "watch_yaw": watch_yaw, "watch_until": watch_until,
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
	ai_state = d.get("ai_state", AiState.IDLE if alive else AiState.DEAD)
	target_id = d.get("target_id", -1)
	target_seen_at = d.get("target_seen_at", -1.0e9)
	target_last_pos = d.get("target_last_pos", Vector3.INF)
	target_visible = d.get("target_visible", false)
	target_aim_y = d.get("target_aim_y", 1.0)
	aim_ready_at = d.get("aim_ready_at", 0.0)
	burst_left = d.get("burst_left", 0)
	next_burst_at = d.get("next_burst_at", 0.0)
	watch_yaw = d.get("watch_yaw", NAN)
	watch_until = d.get("watch_until", -1.0)
	ai_reason = ""


func is_reloading() -> bool:
	return reload_until >= 0.0


func ai_state_name() -> String:
	return AI_STATE_NAMES[ai_state]

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
## COMBAT-02 tactical reaction of the soldier (CombatBrain). A reaction moves the soldier
## through react_target, a temporary goal next to its order: the order itself (order,
## order_target, the squad's order) is never changed by the AI.
enum Tactic { NONE, SEEK_COVER, IN_COVER, RETURNING }
const TACTIC_NAMES: Array[String] = ["-", "seeking cover", "in cover", "returning"]
## Progress of the temporary movement (written by the body / abstract step).
enum ReactState { NONE, MOVING, ARRIVED, FAILED }

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
## Top ground speed in m/s (a run). VISUAL-03: how fast a soldier actually moves is its pace (WorldSim.move_speed), the
## same in both tiers; `speed` stays the ceiling (and what target leads assume).
var speed := 4.5
## VISUAL-03: locomotion paces and their speeds (m/s): patrol walk, brisk walk, jog (ordinary orders), run (assaults,
## withdrawals, movement under fire). The animation set has a captured gait at each.
enum Pace { WALK, BRISK, JOG, RUN }
const PACE_SPEED: Array[float] = [1.3, 1.8, 3.3, 4.5]
var order := Order.NONE
var order_target := Vector3.ZERO
var move_state := MoveState.IDLE
## NAVIGATION N1-A: concise reason for the current/last navigation outcome. This is
## diagnostic state, but persisted so a blocked unit remains explainable after load.
var nav_reason := ""
## True while the player drives this unit directly (orders are suspended, not lost).
var player_controlled := false
## True while a physical body executes this unit (set by WorldSim when a body binds).
var has_body := false
## Soldier equipment configuration (InfantryLoadout id, CHARACTER-01). Empty until the unit
## is first shown; then a deterministic default is stored so it persists.
var loadout := ""
## LOGISTICS-01: vehicle-only state (type, speed, fuel, route, ...); null for soldiers.
var veh: VehicleState
## LOGISTICS-01: id of the vehicle this soldier rides in (-1 = on foot). Aboard, the soldier
## has no body and no proxy, takes no part in combat and follows the vehicle; VehicleSim
## changes this together with the vehicle's `occupants`.
var vehicle_id := -1
## LOGISTICS-01: supply source the soldier was sent to for ammunition ("s<structure id>" or
## "v<vehicle id>"), "" = none. Cleared when the soldier has been resupplied.
var resupply_src := ""

# --- Combat (COMBAT-01a). Authoritative weapon and life state; WeaponDef is static. ---
var alive := true
## WeaponDef id (assets/combat/<id>.tres); empty = unarmed.
var weapon_id: StringName = &""
var mag := 0
var reserve := 0
var fire_auto := true
## GAMEPLAY-02B: InfantryRole id (rifleman, machine_gunner, grenadier ...); "" = not assigned yet (CombatSim.apply_composition).
var role: StringName = &""
## Last time (sim) the soldier moved faster than a shuffle: braced weapons (WeaponDef.settle_s) count from here. Derived
## each tick from the velocity, so it is not saved.
var moved_at := 0.0
## GAMEPLAY-02C: hand grenades carried; the secondary weapon (WeaponDef id, "" = none), its rounds, whether it is in the
## hands (first person: X; the AI raises it only to fire) and when it may fire again. Saved.
var grenades := 0
var sec_id: StringName = &""
var sec_ammo := 0
var sec_active := false
var sec_ready_at := 0.0
## GAMEPLAY-03D: the AI soldier shoulders the launcher before it fires (sec_raised_at, -1 = not raised) and holds it a moment
## after (sec_shown_until): bodies show the launcher in the hands and the rifle away while either says so. Saved.
var sec_raised_at := -1.0
var sec_shown_until := -1.0
## GAMEPLAY-03D: flat on the ground against a grenade until this time (sim): a burst reaches him lower and weaker. Saved.
var down_until := -1.0
## Last grenade throw (sim time): one grenade per soldier at a time.
var nade_at := -1.0e9
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
## GAMEPLAY-04C: when the soldier began aiming at its current target (acquisition, target switch); with moved_at it gives
## how settled the aim is (CombatBrain.aim_settle). Saved like aim_ready_at.
var aim_since := 0.0
## GAMEPLAY-04C: how well the soldier handles a weapon, 0..1 (0.5 = trained): it scales the AI's aim error and how fast it
## settles. A property of the soldier, never of the faction or the weapon (CombatBrain.proficiency_mult). Saved.
var proficiency := 0.5
## Rounds left in the current burst and when the next burst may start.
var burst_left := 0
var next_burst_at := 0.0
## Direction the soldier looks / turns to while standing (NAN = keep heading): the
## target, a reported contact or where it was shot from.
var watch_yaw := NAN
var watch_until := -1.0
## Why the AI is not firing right now (debugging; not saved).
var ai_reason := ""

# --- Tactical reactions (COMBAT-02). Written by CombatBrain; persisted. ---
var tactic := Tactic.NONE
var tactic_since := 0.0
## No new reaction before this time (after a player order, a failed cover, a brief one).
var tactic_cooldown_until := 0.0
## Temporary movement goal (INF = none). While set, the soldier walks there or waits
## there instead of following its order; clearing it resumes the order.
var react_target := Vector3.INF
var react_state := ReactState.NONE
## A Move / Follow / Regroup reaction ends at this time at the latest (INF = no limit).
var react_until := INF
## Cover the soldier chose (reserved: others do not pick the same spot).
var cover_pos := Vector3.INF
var cover_checked_at := -1.0e9
## Where the soldier believes fire comes from (approximate; INF = unknown), when it last
## came under fire, and until when it counts as under fire.
var threat_pos := Vector3.INF
var threat_at := -1.0e9
var under_fire_until := -1.0e9
## Centre of the area the soldier holds (Hold order / where its last order ended).
var anchor_pos := Vector3.INF
## Why the last cover was chosen or rejected (debugging; not saved).
var cover_note := ""

# --- Suppression and fire missions (AI-SQUAD-01). Persisted. ---
## Suppression 0..1 as of `suppression_t`, fed by shots passing close and by hits, decaying
## with time (suppression_at). It makes the soldier less accurate and slower to acquire,
## keeps it in cover and delays its dashes.
var suppression := 0.0
var suppression_t := -1.0e9
## Time of the last hit taken (self-defence under hold fire).
var hit_at := -1.0e9
## Fire mission: shoot at this position (a reported contact, a position the player chose -
## never a hidden enemy's true position) until `fire_until`, when no target is visible.
var fire_at := Vector3.INF
var fire_until := -1.0
## The firing position a squad tactic assigned (INF = none); cover reactions stay within a
## few metres of it.
var post_pos := Vector3.INF
## GAMEPLAY-01C: the fortification slot the soldier was assigned ("<structure id>:<slot>", "" none; DefenceDefs) and, once
## he has taken it, the position he holds there (INF: not in it yet) and the ground point he leaves it by. A soldier in a
## slot is held exactly at fort_pos by both tiers (a tower platform included) and makes no cover moves; any move order
## takes him out first (WorldState.issue_move). Saved, so who holds which slot survives a load.
var fort_slot := ""
var fort_pos := Vector3.INF
var fort_exit := Vector3.INF
## GAMEPLAY-01B: the soldier counted as working at a construction site until this time (set every BUILD step; runtime,
## not saved - only the body's work pose reads it, the work itself is on the site record).
var work_until := -1.0


## GAMEPLAY-01C: holding a fortification slot (standing in it).
func in_fort() -> bool:
	return fort_pos.is_finite()


func is_aboard() -> bool:
	return vehicle_id >= 0


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
		"order": order, "order_target": order_target, "move_state": move_state, "nav_reason": nav_reason,
		"player_controlled": player_controlled, "has_body": has_body, "loadout": loadout,
		"veh": veh.to_dict() if veh else null, "vehicle_id": vehicle_id, "resupply": resupply_src,
		"alive": alive, "weapon_id": weapon_id, "role": role, "grenades": grenades, "sec_id": sec_id, "sec_ammo": sec_ammo,
		"sec_active": sec_active, "sec_ready_at": sec_ready_at, "sec_raised_at": sec_raised_at, "sec_shown_until": sec_shown_until, "down_until": down_until, "nade_at": nade_at, "mag": mag, "reserve": reserve, "fire_auto": fire_auto,
		"next_shot_at": next_shot_at, "reload_until": reload_until, "shot_counter": shot_counter,
		"bloom": bloom, "last_shot_at": last_shot_at, "died_at": died_at, "killer_id": killer_id,
		"ai_state": ai_state, "target_id": target_id, "target_seen_at": target_seen_at, "target_last_pos": target_last_pos,
		"target_visible": target_visible, "target_aim_y": target_aim_y, "aim_ready_at": aim_ready_at, "aim_since": aim_since, "proficiency": proficiency,
		"burst_left": burst_left, "next_burst_at": next_burst_at, "watch_yaw": watch_yaw, "watch_until": watch_until,
		"tactic": tactic, "tactic_since": tactic_since, "tactic_cooldown_until": tactic_cooldown_until,
		"react_target": react_target, "react_state": react_state, "react_until": react_until, "cover_pos": cover_pos,
		"cover_checked_at": cover_checked_at, "threat_pos": threat_pos, "threat_at": threat_at,
		"under_fire_until": under_fire_until, "anchor_pos": anchor_pos,
		"suppression": suppression, "suppression_t": suppression_t, "hit_at": hit_at, "fire_at": fire_at,
		"fire_until": fire_until, "post_pos": post_pos, "fort_slot": fort_slot, "fort_pos": fort_pos, "fort_exit": fort_exit,
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
	u.nav_reason = d.get("nav_reason", "")
	u.player_controlled = d.get("player_controlled", false)
	u.has_body = d.get("has_body", false)
	u.copy_combat_from(d)
	u.loadout = d.get("loadout", "")
	if d.get("veh") is Dictionary:
		u.veh = VehicleState.from_dict(d.veh)
	u.vehicle_id = d.get("vehicle_id", -1)
	u.resupply_src = d.get("resupply", "")
	return u


## Combat fields from a saved dictionary (shared by from_dict and in-place loading).
func copy_combat_from(d: Dictionary) -> void:
	alive = d.get("alive", true)
	weapon_id = StringName(d.get("weapon_id", ""))
	role = StringName(d.get("role", ""))
	grenades = d.get("grenades", 0)
	sec_id = StringName(d.get("sec_id", ""))
	sec_ammo = d.get("sec_ammo", 0)
	sec_active = d.get("sec_active", false)
	sec_ready_at = d.get("sec_ready_at", 0.0)
	sec_raised_at = d.get("sec_raised_at", -1.0)
	sec_shown_until = d.get("sec_shown_until", -1.0)
	down_until = d.get("down_until", -1.0)
	nade_at = d.get("nade_at", -1.0e9)
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
	aim_since = d.get("aim_since", 0.0)
	proficiency = d.get("proficiency", 0.5)
	burst_left = d.get("burst_left", 0)
	next_burst_at = d.get("next_burst_at", 0.0)
	watch_yaw = d.get("watch_yaw", NAN)
	watch_until = d.get("watch_until", -1.0)
	ai_reason = ""
	tactic = d.get("tactic", Tactic.NONE)
	tactic_since = d.get("tactic_since", 0.0)
	tactic_cooldown_until = d.get("tactic_cooldown_until", 0.0)
	react_target = d.get("react_target", Vector3.INF)
	react_state = d.get("react_state", ReactState.NONE)
	react_until = d.get("react_until", INF)
	cover_pos = d.get("cover_pos", Vector3.INF)
	cover_checked_at = d.get("cover_checked_at", -1.0e9)
	threat_pos = d.get("threat_pos", Vector3.INF)
	threat_at = d.get("threat_at", -1.0e9)
	under_fire_until = d.get("under_fire_until", -1.0e9)
	anchor_pos = d.get("anchor_pos", Vector3.INF)
	cover_note = ""
	suppression = d.get("suppression", 0.0)
	suppression_t = d.get("suppression_t", -1.0e9)
	hit_at = d.get("hit_at", -1.0e9)
	fire_at = d.get("fire_at", Vector3.INF)
	fire_until = d.get("fire_until", -1.0)
	post_pos = d.get("post_pos", Vector3.INF)
	fort_slot = String(d.get("fort_slot", ""))
	fort_pos = d.get("fort_pos", Vector3.INF)
	fort_exit = d.get("fort_exit", Vector3.INF)


func is_reloading() -> bool:
	return reload_until >= 0.0


func ai_state_name() -> String:
	return AI_STATE_NAMES[ai_state]


func tactic_name() -> String:
	return TACTIC_NAMES[tactic]


## Suppression holds for SUPPRESSION_HOLD_S after the last incoming round, then decays
## exponentially (time constant SUPPRESSION_TAU_S).
const SUPPRESSION_HOLD_S := 1.2
const SUPPRESSION_TAU_S := 5.0


## GAMEPLAY-03D: the launcher is in the hands (first person: switched to it; AI: raised to fire or just fired).
func launcher_in_hands(now: float) -> bool:
	return sec_id != &"" and (sec_active or (sec_raised_at >= 0.0 and now - sec_raised_at < 6.0) or now < sec_shown_until)


func suppression_at(now: float) -> float:
	if suppression <= 0.001:
		return 0.0
	var idle := now - suppression_t - SUPPRESSION_HOLD_S
	if idle <= 0.0:
		return suppression
	return suppression * exp(-idle / SUPPRESSION_TAU_S)


## Adds incoming-fire pressure (the value first decays to now, then grows, capped at 1).
func add_suppression(amount: float, now: float) -> void:
	suppression = minf(suppression_at(now) + amount, 1.0)
	suppression_t = now


func is_reacting() -> bool:
	return react_target.is_finite()


## Ends a tactical reaction (the order, if any, resumes at once).
func clear_reaction() -> void:
	tactic = Tactic.NONE
	react_target = Vector3.INF
	react_state = ReactState.NONE
	react_until = INF
	cover_pos = Vector3.INF

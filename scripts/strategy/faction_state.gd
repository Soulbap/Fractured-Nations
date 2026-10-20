## One of the three warring factions (WORLD-SANDBOX-01): identity, strategic profile,
## finite reserves and war statistics. Plain data inside WarState (saved with the world).
## Soldiers and squads stay in WorldState.units / squads with their `faction` index.
class_name FactionState
extends RefCounted

var id := 0
var faction_name := ""
## True for the faction the player commands (no strategic AI, every order is the player's).
var player := false
## FactionProfile id (assets/strategy/<id>.tres) the strategic AI reads.
var profile_id: StringName = &""
## Objective that is the faction's headquarters: reserves arrive there.
var hq_objective := -1
## Soldiers still available as replacements (finite); arrive as new squads at the HQ.
var reserves := 0
var reserves_start := 0
var next_reinforcement_at := 0.0
## No new offensive before this time (after a failed attack: recovery).
var recovery_until := 0.0
var next_decision_at := 0.0
var squad_counter := 0
## War statistics.
var casualties := 0
var kills := 0
var objectives_captured := 0
var objectives_lost := 0
var ops_started := 0
var ops_succeeded := 0
var ops_failed := 0
## Last strategic decision (debug / map).
var last_decision := ""


func to_dict() -> Dictionary:
	return {"id": id, "name": faction_name, "player": player, "profile": profile_id, "hq": hq_objective,
		"reserves": reserves, "reserves_start": reserves_start, "next_reinf": next_reinforcement_at,
		"recovery_until": recovery_until, "next_decision": next_decision_at, "squad_counter": squad_counter,
		"casualties": casualties, "kills": kills, "captured": objectives_captured, "lost": objectives_lost,
		"ops_started": ops_started, "ops_succeeded": ops_succeeded, "ops_failed": ops_failed, "last_decision": last_decision}


static func from_dict(d: Dictionary) -> FactionState:
	var f := FactionState.new()
	f.id = d.get("id", 0)
	f.faction_name = d.get("name", "")
	f.player = d.get("player", false)
	f.profile_id = StringName(d.get("profile", ""))
	f.hq_objective = d.get("hq", -1)
	f.reserves = d.get("reserves", 0)
	f.reserves_start = d.get("reserves_start", 0)
	f.next_reinforcement_at = d.get("next_reinf", 0.0)
	f.recovery_until = d.get("recovery_until", 0.0)
	f.next_decision_at = d.get("next_decision", 0.0)
	f.squad_counter = d.get("squad_counter", 0)
	f.casualties = d.get("casualties", 0)
	f.kills = d.get("kills", 0)
	f.objectives_captured = d.get("captured", 0)
	f.objectives_lost = d.get("lost", 0)
	f.ops_started = d.get("ops_started", 0)
	f.ops_succeeded = d.get("ops_succeeded", 0)
	f.ops_failed = d.get("ops_failed", 0)
	f.last_decision = d.get("last_decision", "")
	return f

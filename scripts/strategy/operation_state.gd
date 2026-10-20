## A military operation (WORLD-SANDBOX-01): real squads of one faction sent to do one
## thing at one objective or place. Plain data inside WarState; WarSim advances it from
## what actually happens to its squads (positions, casualties, the objective's owner).
##
##   ATTACK    march to a staging point short of an enemy / neutral objective, assault,
##             hold it until it is captured.          -> COMPLETED when owned, FAILED when
##             too many are lost or it takes too long.
##   DEFEND    march to a friendly objective and hold it. Stays active while threatened;
##             COMPLETED after a quiet period (the squads stay as its garrison).
##   REINFORCE march to a friendly objective (or an operation's target) and join the
##             defence / the attack there.            -> COMPLETED on arrival.
##   MOVE      player only: march to a point.          -> COMPLETED on arrival.
class_name OperationState
extends RefCounted

enum Type { ATTACK, DEFEND, REINFORCE, MOVE }
enum Phase { PLANNING, MOVING, ENGAGING, SECURING, COMPLETED, FAILED, CANCELLED }
const TYPE_NAMES: Array[String] = ["Attack", "Defend", "Reinforce", "Move"]
const PHASE_NAMES: Array[String] = ["planning", "moving", "engaging", "securing", "completed", "failed", "cancelled"]

var id := 0
var faction := 0
var type := Type.ATTACK
## Objective id (-1 for a MOVE to a point).
var target_objective := -1
var target_pos := Vector3.ZERO
## Where the squads gather before the assault (ATTACK) / the end of the march.
var staging_pos := Vector3.INF
var squads := PackedInt32Array()
var phase := Phase.PLANNING
var started_at := 0.0
var phase_since := 0.0
var ended_at := -1.0
var outcome := ""
## Living soldiers when the operation started / joined since, and its losses so far.
var start_strength := 0
var losses := 0
## Ordered by the player (map / RTS) rather than a faction's strategic AI.
var player_ordered := false
## Route of the first squad (map display); each squad follows its own SquadState.route.
var route_preview := PackedVector3Array()


func is_active() -> bool:
	return phase < Phase.COMPLETED


func type_name() -> String:
	return TYPE_NAMES[type]


func phase_name() -> String:
	return PHASE_NAMES[phase]


func to_dict() -> Dictionary:
	return {"id": id, "faction": faction, "type": type, "target": target_objective, "target_pos": target_pos,
		"staging": staging_pos, "squads": Array(squads), "phase": phase, "started_at": started_at,
		"phase_since": phase_since, "ended_at": ended_at, "outcome": outcome, "start_strength": start_strength,
		"losses": losses, "player": player_ordered, "route": Array(route_preview)}


static func from_dict(d: Dictionary) -> OperationState:
	var o := OperationState.new()
	o.id = d.get("id", 0)
	o.faction = d.get("faction", 0)
	o.type = d.get("type", Type.ATTACK)
	o.target_objective = d.get("target", -1)
	o.target_pos = d.get("target_pos", Vector3.ZERO)
	o.staging_pos = d.get("staging", Vector3.INF)
	o.squads = PackedInt32Array(d.get("squads", []))
	o.phase = d.get("phase", Phase.PLANNING)
	o.started_at = d.get("started_at", 0.0)
	o.phase_since = d.get("phase_since", 0.0)
	o.ended_at = d.get("ended_at", -1.0)
	o.outcome = d.get("outcome", "")
	o.start_strength = d.get("start_strength", 0)
	o.losses = d.get("losses", 0)
	o.player_ordered = d.get("player", false)
	o.route_preview = PackedVector3Array(d.get("route", []))
	return o

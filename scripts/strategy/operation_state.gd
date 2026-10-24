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
##   MOVE      march to a point (the player's order, or an AI faction investigating a
##             contact: `contact_id`).                 -> COMPLETED on arrival.
##   COUNTER   AI-WAR-LOGISTICS-01: the local reserve of a defended objective attacks a weakened, exposed attacker near it
##             (`target_pos` = where the attackers are believed, `target_objective` = the objective defended); the squads
##             keep their station, and go back to their defensive posture when it ends (success, failure or timeout).
class_name OperationState
extends RefCounted

enum Type { ATTACK, DEFEND, REINFORCE, MOVE, COUNTER }
enum Phase { PLANNING, MOVING, ENGAGING, SECURING, COMPLETED, FAILED, CANCELLED }
const TYPE_NAMES: Array[String] = ["Attack", "Defend", "Reinforce", "Move", "Counterattack"]
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
## AI-INTEL-01: contact an AI MOVE investigates (-1 none) and why the operation exists, for
## the inspector ("reinforce: 4 enemy reported near X").
var contact_id := -1
## AI-COMBAT-STRAT-01: where a multi-squad attack stands (OpCoordination). APPROACH: marching to the
## staging point; DEPLOY: roles handed out, the fire support moves up; SUPPORT: support is set and
## suppressing; ASSAULT: the assault / maneuver squads close; SECURE: on the objective; WITHDRAW: breaking
## contact; DONE. Not a plan: the stage is read from what the squads actually do.
## AI-WAR-LOGISTICS-01: a mechanized operation first runs the transport stages ASSEMBLE (squads and vehicles gather),
## MOUNT (boarding), TRANSIT (the convoy drives) and DISEMBARK (unloading near the objective); they come before
## APPROACH (the walk from the unloading point to the staging point), so every `stage >= APPROACH` test of the
## attack stages is unchanged and the numeric values of the old stages are the same as in older saves.
enum Stage { ASSEMBLE = -4, MOUNT = -3, TRANSIT = -2, DISEMBARK = -1, APPROACH = 0, DEPLOY = 1, SUPPORT = 2, ASSAULT = 3, SECURE = 4, WITHDRAW = 5, DONE = 6 }
const STAGE_NAMES := {-4: "assemble", -3: "mount", -2: "transit", -1: "disembark", 0: "approach", 1: "deploy", 2: "support", 3: "assault", 4: "secure", 5: "withdraw", 6: "done"}
var stage := Stage.APPROACH
var stage_since := 0.0
## squad id -> SquadState.OpRole (temporary assignments, saved).
var roles := {}
## What the operation is waiting for / why it was last reassessed / why it withdrew (real decision text).
var wait_reason := ""
var stage_why := ""
var withdraw_why := ""
var fallback_pos := Vector3.INF
var reassess_at := 0.0
var assault_pos := Vector3.INF
var reason := ""
## GAMEPLAY-02A: the fire support's window. False: the support observes and fires only at enemies it sees (or that were just
## reported on the objective); true: the assault is crossing the last few hundred metres and the support covers it with
## fire at the believed defenders. Set by OpCoordination from where the assault squads are.
var cover_fire := false
## GAMEPLAY-02A: the assault's progress (closest assault squad to the objective) and since when it has not improved; squad id
## -> sim time it may start its assault (staggered starts).
var progress_best := INF
var progress_t := 0.0
var assault_at := {}
## NAVIGATION N1-C1: since when (sim time) no squad of the operation could be given a route to its goal; -1 = not blocked.
var blocked_since := -1.0
## NAV-PERF-01B: the operation was started and its squads' routes are being planned (RouteService); it begins (transport plan, the
## march) when the first route arrives. Saved: a load in that moment asks for the routes again.
var starting := false
## AI-WAR-LOGISTICS-01: vehicles assigned to the operation (VehicleState.assign_* says the same from the other side),
## the transport plan (assembly point, unloading point, drivers' task per vehicle, why foot / why mounted) and the
## supply side (readiness decision, missions requested). Plain data, saved.
var vehicles := PackedInt32Array()
var transport := {}
var readiness := {}
## Why the operation was launched with less than it wanted (inspector).
var supply_why := ""


func stage_name() -> String:
	return STAGE_NAMES[int(stage)]


## True while the operation is still moving by vehicle (assemble .. disembark).
func is_transport_stage() -> bool:
	return int(stage) < int(Stage.APPROACH)


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
		"losses": losses, "player": player_ordered, "route": Array(route_preview), "contact": contact_id, "reason": reason,
		"stage": stage, "stage_since": stage_since, "roles": roles.duplicate(), "wait": wait_reason, "stage_why": stage_why,
		"withdraw_why": withdraw_why, "fallback": fallback_pos, "reassess_at": reassess_at, "assault_pos": assault_pos,
		"vehicles": Array(vehicles), "transport": transport.duplicate(true), "readiness": readiness.duplicate(true), "supply_why": supply_why,
		"blocked_since": blocked_since, "starting": starting, "cover_fire": cover_fire, "progress_best": progress_best, "progress_t": progress_t,
		"assault_at": assault_at.duplicate()}


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
	o.contact_id = d.get("contact", -1)
	o.reason = d.get("reason", "")
	o.stage = d.get("stage", Stage.APPROACH)
	o.stage_since = d.get("stage_since", 0.0)
	for k in d.get("roles", {}):
		o.roles[int(k)] = int(d.roles[k])
	o.wait_reason = d.get("wait", "")
	o.stage_why = d.get("stage_why", "")
	o.withdraw_why = d.get("withdraw_why", "")
	o.fallback_pos = d.get("fallback", Vector3.INF)
	o.reassess_at = d.get("reassess_at", 0.0)
	o.blocked_since = d.get("blocked_since", -1.0)
	o.starting = d.get("starting", false)
	o.assault_pos = d.get("assault_pos", Vector3.INF)
	o.cover_fire = d.get("cover_fire", false)
	o.progress_best = d.get("progress_best", INF)
	o.progress_t = d.get("progress_t", 0.0)
	for k in d.get("assault_at", {}):
		o.assault_at[int(k)] = float(d.assault_at[k])
	o.vehicles = PackedInt32Array(d.get("vehicles", []))
	o.transport = d.get("transport", {}).duplicate(true)
	o.readiness = d.get("readiness", {}).duplicate(true)
	o.supply_why = d.get("supply_why", "")
	return o

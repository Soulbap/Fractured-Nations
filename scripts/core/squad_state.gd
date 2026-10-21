## Authoritative state of one squad: a named group of soldiers with a leader, an order
## and a loose formation (UNIT-01A).
##
## Plain data, part of WorldState like UnitState. The soldiers stay independent units;
## the squad only records who belongs to it and what it was told to do. WorldSim turns a
## squad order into ordinary per-soldier move orders (one formation slot each), so bodies
## and the abstract tier execute it with the code they already have.
class_name SquadState
extends RefCounted

enum Order { NONE, MOVE, HOLD, FOLLOW, REGROUP, TACTIC }
## COLUMN: roads and narrow routes; LINE: across the facing; WEDGE: open ground (leader
## forward, files back on both sides); STAGGERED: two offset files; DISPERSED: wide combat
## spacing (AI-SQUAD-01). SquadControl._slots fills the shapes in and moves slots that fall
## on unusable ground.
enum Formation { LINE, COLUMN, WEDGE, STAGGERED, DISPERSED }
## Progress of the current order (set by WorldSim, for the HUD and tests).
enum Status { IDLE, MOVING, DONE, PARTIAL }
## COMBAT-01b rules of engagement: WEAPONS_FREE engage detected enemies on their own;
## HOLD_FIRE observe and track, but never fire on their own.
enum Roe { WEAPONS_FREE, HOLD_FIRE }
const ROE_NAMES: Array[String] = ["Weapons free", "Hold fire"]

const ORDER_NAMES: Array[String] = ["None", "Move", "Hold", "Follow", "Regroup", "Tactic"]
const FORMATION_NAMES: Array[String] = ["Line", "Column", "Wedge", "Staggered", "Dispersed"]

## AI-SQUAD-01 squad tactics. One tactic at a time; the squad record owns the intent, the
## soldiers execute it with ordinary move orders and the CombatBrain reactions.
enum Tactic { NONE, DEFEND, SUPPRESS, ASSAULT, FLANK, BOUND, REPOSITION, WITHDRAW, REGROUP }
const TACTIC_NAMES: Array[String] = ["-", "Defend", "Suppress", "Assault", "Flank", "Bound", "Reposition", "Withdraw", "Regroup"]
## Who commands the current tactic: the player (an RTS order), an operation (the tactic
## serves its task) or the squad itself (chosen by SquadTactics from what it knows).
enum Owner { NONE, PLAYER, OPERATION, SQUAD }
## Temporary role of a squad in a multi-squad operation (not a squad class).
enum OpRole { NONE, ASSAULT, SUPPORT, MANEUVER, RESERVE, SECURITY, REINFORCE }
const OP_ROLE_NAMES: Array[String] = ["-", "assault", "fire support", "maneuver", "reserve", "security", "reinforcement"]
const OWNER_NAMES: Array[String] = ["-", "player", "operation", "squad"]
## What a fire team is doing within the tactic (temporary assignments, not unit classes).
enum TeamRole { SECURITY, SUPPORT, MANEUVER, ASSAULT, RESERVE }
const ROLE_NAMES: Array[String] = ["security", "support", "maneuver", "assault", "reserve"]

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
## COMBAT-01a: members killed (no longer in `members`; identity kept for the record).
var fallen := PackedInt32Array()
var roe := Roe.WEAPONS_FREE
## WORLD-SANDBOX-01: operation the squad serves (-1 = none: the player's or idle), the
## long-distance route it follows (waypoints from StrategicRoutes; SquadControl walks
## them one by one with ordinary squad Move orders) and the objective it garrisons.
var op_id := -1
var route := PackedVector3Array()
var route_i := 0
var station_objective := -1

# --- Fire teams and tactics (AI-SQUAD-01). Persisted with the squad. ---
## Fire teams: member ids per team (one team for small squads, two otherwise), the team
## leader and the current role of each. Validated against `members` after casualties.
var teams: Array[PackedInt32Array] = []
var team_leaders := PackedInt32Array()
var team_roles := PackedInt32Array()
var tactic := Tactic.NONE
var tactic_owner := Owner.NONE
## Tactic phase (meaning depends on the tactic, see SquadTactics) and when it began.
var tactic_phase := 0
var tactic_since := 0.0
var tactic_phase_since := 0.0
## The tactic's goal: the position to attack / suppress / defend / withdraw to, the contact
## it came from (-1: a position chosen by the player or by observation) and the direction
## of the expected threat. Never the true position of a hidden enemy.
var tactic_target := Vector3.INF
var tactic_contact := -1
var tactic_dir := Vector3.ZERO
## The destination of the current maneuver leg (bound / flank / withdraw).
var tactic_dest := Vector3.INF
## Flank route waypoints (terrain-checked when planned) and the next one.
var tactic_route := PackedVector3Array()
var tactic_route_i := 0
var tactic_replans := 0
## Leg counter of a bounding / flanking / assaulting maneuver (which team moves is derived from it).
var tactic_leg := 0
## AI-COMBAT-STRAT-01: the squad's temporary role in its operation (set by OpCoordination), and whether
## its ASSAULT / FLANK has external fire support (another squad of the operation suppresses), which
## lets it skip its own support set-up and close faster.
var op_role := OpRole.NONE
## AI-COMBAT-STRAT-01: sector or local reserve at a defended objective (saved, shown by the inspector).
var defence_role := ""
var tactic_ext := false
## The squad is recovering (regrouping, calming down) and is not offered to new offensives before this time.
var recover_until := 0.0
## The operation an OPERATION-owned tactic serves (-1: none, e.g. a test or script tasking).
var tactic_op := -1
var tactic_leg_since := 0.0
## Formation chosen from the terrain and the situation (column on roads and in woods, wedge in the
## open, dispersed under threat) instead of the player's V toggle. AI squads start with it on.
var formation_auto := false
## No new autonomous tactic before tactic_cooldown_until; the current one is kept at least
## until tactic_commit_until.
var tactic_cooldown_until := 0.0
var tactic_commit_until := 0.0
## The order the squad had before an autonomous tactic took over (restored afterwards).
var prev_order := Order.NONE
var prev_target := Vector3.INF
var prev_yaw := 0.0
## The last decision in words: why this tactic, why it ended, why another was rejected.
## Written by the decision code itself and saved, so a loaded squad still explains itself.
var tactic_why := ""
var tactic_rejected := ""


func tactic_name() -> String:
	return TACTIC_NAMES[tactic]


func owner_name() -> String:
	return OWNER_NAMES[tactic_owner]


## Index of the fire team a unit is in (-1: none).
func team_of(unit_id: int) -> int:
	for i in teams.size():
		if teams[i].has(unit_id):
			return i
	return -1


func team_role(i: int) -> int:
	return team_roles[i] if i >= 0 and i < team_roles.size() else TeamRole.SECURITY


func has_member(unit_id: int) -> bool:
	return members.has(unit_id)


func is_detached(unit_id: int) -> bool:
	return detached.has(unit_id)


func order_name() -> String:
	return ORDER_NAMES[order]


func roe_name() -> String:
	return ROE_NAMES[roe]


func formation_name() -> String:
	return FORMATION_NAMES[formation]


func to_dict() -> Dictionary:
	return {
		"id": id, "name": squad_name, "faction": faction, "members": Array(members),
		"leader": leader_id, "order": order, "order_target": order_target, "order_yaw": order_yaw,
		"follow_unit": follow_unit_id, "follow_squad": follow_squad_id,
		"formation": formation, "spacing": spacing, "detached": Array(detached),
		"status": status, "blocked": Array(blocked), "fallen": Array(fallen), "roe": roe,
		"op": op_id, "route": Array(route), "route_i": route_i, "station": station_objective,
		"teams": teams.map(func(t: PackedInt32Array) -> Array: return Array(t)), "team_leaders": Array(team_leaders), "team_roles": Array(team_roles),
		"tactic": tactic, "tactic_owner": tactic_owner, "tactic_phase": tactic_phase, "tactic_since": tactic_since,
		"tactic_phase_since": tactic_phase_since, "tactic_target": tactic_target, "tactic_contact": tactic_contact,
		"tactic_dir": tactic_dir, "tactic_dest": tactic_dest, "tactic_route": Array(tactic_route), "tactic_route_i": tactic_route_i,
		"tactic_replans": tactic_replans, "tactic_leg": tactic_leg, "op_role": op_role, "defence_role": defence_role, "tactic_ext": tactic_ext, "recover_until": recover_until, "tactic_op": tactic_op, "tactic_leg_since": tactic_leg_since, "formation_auto": formation_auto, "tactic_cooldown_until": tactic_cooldown_until, "tactic_commit_until": tactic_commit_until,
		"prev_order": prev_order, "prev_target": prev_target, "prev_yaw": prev_yaw, "tactic_why": tactic_why, "tactic_rejected": tactic_rejected,
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
	s.fallen = PackedInt32Array(d.get("fallen", []))
	s.roe = d.get("roe", Roe.WEAPONS_FREE)
	s.op_id = d.get("op", -1)
	s.route = PackedVector3Array(d.get("route", []))
	s.route_i = d.get("route_i", 0)
	s.station_objective = d.get("station", -1)
	for t in d.get("teams", []):
		s.teams.append(PackedInt32Array(t))
	s.team_leaders = PackedInt32Array(d.get("team_leaders", []))
	s.team_roles = PackedInt32Array(d.get("team_roles", []))
	s.tactic = d.get("tactic", Tactic.NONE)
	s.tactic_owner = d.get("tactic_owner", Owner.NONE)
	s.tactic_phase = d.get("tactic_phase", 0)
	s.tactic_since = d.get("tactic_since", 0.0)
	s.tactic_phase_since = d.get("tactic_phase_since", 0.0)
	s.tactic_target = d.get("tactic_target", Vector3.INF)
	s.tactic_contact = d.get("tactic_contact", -1)
	s.tactic_dir = d.get("tactic_dir", Vector3.ZERO)
	s.tactic_dest = d.get("tactic_dest", Vector3.INF)
	s.tactic_route = PackedVector3Array(d.get("tactic_route", []))
	s.tactic_route_i = d.get("tactic_route_i", 0)
	s.tactic_replans = d.get("tactic_replans", 0)
	s.tactic_leg = d.get("tactic_leg", 0)
	s.op_role = d.get("op_role", OpRole.NONE)
	s.defence_role = d.get("defence_role", "")
	s.tactic_ext = d.get("tactic_ext", false)
	s.recover_until = d.get("recover_until", 0.0)
	s.tactic_op = d.get("tactic_op", -1)
	s.tactic_leg_since = d.get("tactic_leg_since", 0.0)
	s.formation_auto = d.get("formation_auto", false)
	s.tactic_cooldown_until = d.get("tactic_cooldown_until", 0.0)
	s.tactic_commit_until = d.get("tactic_commit_until", 0.0)
	s.prev_order = d.get("prev_order", Order.NONE)
	s.prev_target = d.get("prev_target", Vector3.INF)
	s.prev_yaw = d.get("prev_yaw", 0.0)
	s.tactic_why = d.get("tactic_why", "")
	s.tactic_rejected = d.get("tactic_rejected", "")
	return s

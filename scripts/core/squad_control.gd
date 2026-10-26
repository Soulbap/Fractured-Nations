## Executes squad orders (UNIT-01A) on top of the per-unit move orders.
##
## The squad record (SquadState in WorldState) is the only authority. Giving a squad an
## order computes one formation slot per member and issues an ordinary move order to
## each soldier; bodies (navmesh + avoidance) and the abstract tier then walk there with
## their existing code. Slots are preferences: a soldier that cannot reach its slot ends
## its order as BLOCKED and the squad reports it, nothing re-plans in a loop.
##
## update() runs a few times per second (not per frame): it tracks progress (status) and
## keeps Follow slots behind the followed unit, re-issuing a move only when a slot moved
## more than follow_reissue_m. Possessed soldiers keep their (suspended) squad order and
## pick it up again when the player leaves them; the rest of the squad is not touched.
class_name SquadControl
extends RefCounted

## Distance kept behind the followed unit (m), before the formation starts.
var follow_distance := 5.0
## A Follow slot must move this far before the soldier gets a new move order.
var follow_reissue_m := 4.0
## Follow slots are placed where the followed unit will be this many seconds ahead, so a
## walking target does not need a new order for every few metres (kept below
## follow_distance / walking speed so followers stay behind).
var follow_lead_s := 1.0
## Follow slots are re-checked this often (s).
var follow_interval := 1.0
## A soldier this close to its Follow slot without an order stays put.
var follow_settle_m := 3.0
## COMBAT-01b: a follower whose slot has not moved since its last order is only sent
## back when it was pushed farther than this from it (crowding after arrival must not
## re-issue the same slot again and again while the followed unit stands still).
var follow_drift_m := 6.0
## Gap between squads that are ordered to the same point.
var squad_gap := 5.0
var update_interval := 0.5
## WORLD-SANDBOX-01 routes: the next waypoint is ordered when the squad's leader is this
## close to the current one (the squad keeps walking instead of stopping at each).
var route_reach_m := 30.0
## A leg whose leader gains nothing for this long counts as done (s).
var route_stall_s := 25.0
var route_skips := 0
## WORLD-PLAYTEST-01: a Move order farther than this (m), or one whose straight line crosses
## water or ground the strategic grid rules out, follows a strategic route (bridges, roads,
## round cliffs) instead of a straight walk; a stalled route leg is re-planned from where
## the squad is (at most route_replans times per order) before the waypoint is skipped.
var route_min_m := 150.0
## BRIDGE-NAV-01: a slot within this distance of a deck edge on water or on a bank too steep to stand on goes onto the deck.
const DECK_SIDE_M := 6.0
var route_replans := 3
var routed_orders := 0
var route_replanned := 0
## NAVIGATION N1: distinguishes obstacle stalls from stalls while CombatBrain has
## temporarily replaced the leader's movement with a reaction.
var route_stall_events := 0
var route_stall_while_reacting := 0
## N1-A member watchdog. SoldierBody and WorldSim own actual movement; this layer only
## notices an individual that the leader-level route watchdog cannot see and grants one
## fresh attempt at the same authoritative slot.
var member_stall_s := 25.0
var member_replans := 1
## NAV-INF-01: distance a member has to cover after a recovery for the next blockage to get a recovery of its own. The budget is
## per blockage, not per target: the last leg of a long march is one target for hundreds of metres.
var member_renew_m := 15.0
var member_stalls := 0
var member_recoveries := 0
var member_failures := 0
var _member_progress := {}
var _replans := {}
## squad id -> formation to take on the last leg of a routed player Move.
var _end_formation := {}
var _leg_progress := {}
## Emitted when a squad reached the last waypoint of its route (WarSim advances its
## operation).
signal route_finished(squad: SquadState)

var sim: WorldSim
var _timer := 0.0
var _follow_timer := 0.0
## unit id -> the Follow slot last ordered to it (not saved: after a load the first
## update compares with the soldier's order / position instead).
var _follow_slot := {}


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
	sim.state.roads.bridge_changed.connect(_on_bridge_changed)


## NAVIGATION N1-C1 counters and the last reason a squad's march was stopped by a bridge (squad id -> text).
var bridge_reroutes := 0
var bridge_blocked := 0
var route_block_reason := {}
## NAV-PERF-01B: route requests made, answered without a route; squad id -> the closed bridge a "bridge" request goes round.
var route_requests := 0
var route_failures := 0
var _bridge_wait := {}
## QOL-01: squad id -> the facts of its last behaviour route (StrategicRoutes.last_profile: profile, length, fallback); runtime.
var route_profile := {}


## A bridge was closed or disabled: squads on a route over its deck plan again from where they stand, or stop with a reason when
## no other way exists. A squad whose centroid is already on the deck finishes the crossing (nothing is teleported or cancelled).
## Opening a bridge changes nothing for a march in progress (a route that is valid stays valid).
func _on_bridge_changed(b: RoadNetwork.Bridge) -> void:
	# Deferred: the strategic grid listens to the same signal (connected later than this) and must have closed the bridge's
	# cells before a squad plans its way round.
	if not b.is_open():
		call_deferred("_reroute_for_bridge", b)


func _reroute_for_bridge(b: RoadNetwork.Bridge) -> void:
	if b.is_open():
		return
	for sq: SquadState in sim.state.all_squads():
		if sq.route.is_empty() or sq.route_i >= sq.route.size():
			continue
		if sim.state.roads.blocking_bridge_at(_centroid(sq), 8.0) == b:
			continue
		if not _route_crosses(sq, b):
			continue
		_reroute_around(sq, b)


## True when a remaining leg of the squad's route (from its centroid on) runs over the deck of b.
func _route_crosses(sq: SquadState, b: RoadNetwork.Bridge) -> bool:
	var prev := _centroid(sq)
	var reach: float = (b.segs[0][2] as float) + 4.0
	for i in range(sq.route_i, sq.route.size()):
		var to := sq.route[i]
		var d := _flat(prev, to)
		var n := maxi(1, ceili(d / 10.0))
		for k in n + 1:
			var q := prev.lerp(to, float(k) / n)
			if b.bounds.grow(4.0).has_point(Vector2(q.x, q.z)) and b.distance_to(Vector2(q.x, q.z)) <= reach:
				return true
		prev = to
	return false


func _reroute_around(sq: SquadState, b: RoadNetwork.Bridge) -> void:
	var routes: StrategicRoutes = sim.war.routes if sim.war else null
	var goal := sq.route[sq.route.size() - 1]
	if routes != null and routes.ready:
		# NAV-PERF-01B: asked for; the squad walks on meanwhile (its walkers refuse the closed deck), _on_route_job takes the answer.
		_bridge_wait[sq.id] = b.id
		request_route(sq, goal, "bridge", sq.formation)
		return
	_stop_for_bridge(sq, b)


## No other way round a closed bridge: the march stops where the squad stands, with the reason kept for whoever asked for it (an
## operation reads `route_block_reason` through WarSim; a player squad shows it in the log).
func _stop_for_bridge(sq: SquadState, b: RoadNetwork.Bridge) -> void:
	bridge_blocked += 1
	clear_route(sq)
	# After clear_route: a dropped route request clears the report (QOL-01), this one is the new report.
	route_block_reason[sq.id] = "%s is %s and no other crossing is reachable" % [b.name, b.state_name()]
	sq.order = SquadState.Order.HOLD
	sq.order_target = Vector3.INF
	for id in sq.members:
		sim.state.halt(id)
	sq.status = SquadState.Status.DONE
	sim.state.squad_changed.emit(sq)
	if sim.war:
		sim.war.log_event(sq.faction, "navigation", "%s: march stopped, %s" % [sq.squad_name, route_block_reason[sq.id]], _centroid(sq))


# --- Orders -----------------------------------------------------------------------

## Moves squads to a point: each keeps its formation, facing the direction of travel;
## several squads stand side by side across that direction.
func order_move(squad_ids: Array, target: Vector3, pace := -1) -> int:
	var sqs := _squads(squad_ids)
	if sqs.is_empty() or not target.is_finite():
		return 0
	var from := Vector3.ZERO
	for sq: SquadState in sqs:
		from += _centroid(sq)
	from /= sqs.size()
	var yaw := _yaw_towards(from, target, sqs[0].order_yaw)
	var right := _right(yaw)
	var widths := []
	var total := 0.0
	for sq: SquadState in sqs:
		sim.tactics.on_order(sq)
		drop_route_wait(sq)
		_auto_formation(sq, target)
		var w := _width(sq)
		widths.append(w)
		total += w
	total += squad_gap * (sqs.size() - 1)
	var x := -total * 0.5
	var n := 0
	for i in sqs.size():
		var sq: SquadState = sqs[i]
		var centre: Vector3 = target + right * (x + widths[i] * 0.5)
		x += widths[i] + squad_gap
		sq.order = SquadState.Order.MOVE
		sq.order_target = centre
		sq.pace = pace
		sq.order_yaw = yaw
		sq.follow_unit_id = -1
		sq.follow_squad_id = -1
		if _routed_move(sq, centre):
			n += sq.members.size()
			continue
		n += _send_to_slots(sq, centre, yaw, true)
	return n


## WORLD-PLAYTEST-01: the same strategic routes the war's operations use, for a player's
## (or anybody's) Move order that is long or would cross water or a cliff in a straight
## line. Before, such an order walked straight: into the river far from any bridge, or up
## an impassable slope, both near the camera (beyond the navmesh area the bodies headed
## straight for the target) and in the abstract tier. Returns false for short, clear moves.
func _routed_move(sq: SquadState, target: Vector3) -> bool:
	var routes: StrategicRoutes = sim.war.routes if sim.war else null
	if routes == null or not routes.ready:
		return false
	var from := _centroid(sq)
	if _flat(from, target) < route_min_m and routes._leg_clear(from, target):
		return false
	# NAV-PERF-01B: the route is asked for; the squad stands (status MOVING, "route pending") until it comes. No route: the old
	# straight walk to the slots (_on_route_job).
	request_route(sq, target, "move", sq.formation)
	return true


# --- Route requests (NAV-PERF-01B) --------------------------------------------------

## Asks RouteService for the squad's strategic route to `goal`. kind: "move" (an order: the route is walked when it comes, the
## squad stands meanwhile), "replan" (a stalled leg: the old route is walked on meanwhile), "bridge" (round a closed bridge), "op"
## (an operation's march: WarSim takes the answer). The request replaces any earlier one of the squad; asking again for the same
## thing keeps the search that is under way. Nothing is decided before the answer: pending is not "unreachable".
func request_route(sq: SquadState, goal: Vector3, kind: String, formation: int) -> void:
	var routes: StrategicRoutes = sim.war.routes if sim.war else null
	if routes == null or not routes.ready:
		return
	sq.route_wait_goal = goal
	sq.route_wait_kind = kind
	sq.route_wait_form = formation
	route_requests += 1
	if kind == "move" or kind == "op":
		sq.status = SquadState.Status.MOVING
	_submit_wait(sq)


func _submit_wait(sq: SquadState) -> void:
	var routes: StrategicRoutes = sim.war.routes
	var from := _centroid(sq)
	var goal := sq.route_wait_goal
	# QOL-01: an order's route (and its replans) follows the squad's behaviour mode and keeps clear of the faction's believed
	# threat; an operation's march ("op") is planned as before - the operation weighs its own route risk.
	var profile := ""
	var threat := {}
	var tag := ""
	if sq.route_wait_kind != "op":
		profile = SquadBehaviour.ROUTE[clampi(sq.behaviour, 0, 3)]
		if sim.war and sim.war.influence:
			threat = sim.war.influence.threat.get(sq.faction, {})
		tag = profile if threat.is_empty() else "%s.%d" % [profile, sim.war.influence.refreshes]
	var job := sim.routing.submit(&"infantry", "squad:%d" % sq.id, route_priority(sq), routes.job_key(from, goal, tag),
		StrategicRoutes.Runner.new(routes, from, goal, sim.terrain, profile, threat), _on_route_job.bind(sq.id), from, goal)
	sq.route_job = job.id
	if job.is_done():
		_on_route_job(job, sq.id)


## True while the squad waits for a route it asked for.
func route_waiting(sq: SquadState) -> bool:
	return sq.route_wait_goal.is_finite()


## On the march: walking a route, or waiting for the one it asked for (NAV-PERF-01B: an empty route alone does not mean idle).
func marching(sq: SquadState) -> bool:
	return not sq.route.is_empty() or sq.route_wait_goal.is_finite()


## Forgets a route request (a new order replaced it); its search is cancelled, a late answer is ignored.
func drop_route_wait(sq: SquadState) -> void:
	# QOL-01: a new order (or a new route) ends a "march stopped" report.
	route_block_reason.erase(sq.id)
	if not sq.route_wait_goal.is_finite():
		return
	sim.routing.cancel_owner("squad:%d" % sq.id, "squad order replaced")
	sq.route_wait_goal = Vector3.INF
	sq.route_wait_kind = ""
	sq.route_job = -1
	_bridge_wait.erase(sq.id)


func _on_route_job(job: RouteService.Job, sq_id: int) -> void:
	var sq := sim.state.get_squad(sq_id)
	if sq == null or sq.route_job != job.id or not sq.route_wait_goal.is_finite():
		return  # a newer request or order owns the squad
	var kind := sq.route_wait_kind
	var goal := sq.route_wait_goal
	var formation := sq.route_wait_form
	sq.route_wait_goal = Vector3.INF
	sq.route_wait_kind = ""
	sq.route_job = -1
	var r := PackedVector3Array()
	if job.ok():
		r = (job.result.route as PackedVector3Array).duplicate()
		# A shared or reused search started in the same 50 m cell: the squad starts from where it stands.
		if job.from.is_finite() and sim.war.routes.passable(job.from):
			r[0] = job.from
		r[r.size() - 1] = goal
	var why := job.reason if job.reason != "" else "no route"
	if job.ok() and job.result.has("profile"):
		route_profile[sq.id] = job.result.profile
	match kind:
		"move":
			if r.size() < 2:
				route_failures += 1
				_send_to_slots(sq, sq.order_target, sq.order_yaw, true)
				return
			_replans.erase(sq.id)
			routed_orders += 1
			# March in column (narrow enough for bridges and tracks), take the ordered formation again for the last leg.
			_end_formation[sq.id] = _end_formation.get(sq.id, formation)
			follow_route(sq, r, SquadState.Formation.COLUMN)
		"replan":
			if r.size() < 2:
				route_failures += 1
				route_skips += 1
				_skip_leg(sq)
				return
			route_replanned += 1
			_keep_route(sq, r, formation)
		"bridge":
			var bid: String = _bridge_wait.get(sq.id, "")
			_bridge_wait.erase(sq.id)
			var b := sim.state.roads.get_bridge(bid)
			if r.size() < 2:
				route_failures += 1
				if b != null and not b.is_open():
					_stop_for_bridge(sq, b)
				return
			bridge_reroutes += 1
			route_block_reason.erase(sq.id)
			_keep_route(sq, r, formation)
		"op":
			if sim.war:
				sim.war.on_route_ready(sq, r, why)


## A new route for a march under way: walked from its first waypoint, the order and the squad's state stay as they are.
func _keep_route(sq: SquadState, r: PackedVector3Array, formation: int) -> void:
	sq.route = r
	sq.route_i = 0
	sq.formation = formation
	_route_leg(sq)


## A leg the squad could not finish and no new route for: the next waypoint is tried (the last one ends the march).
func _skip_leg(sq: SquadState) -> void:
	if sq.route.is_empty():
		return
	if sq.route_i >= sq.route.size() - 1:
		clear_route(sq)
		route_finished.emit(sq)
		return
	sq.route_i += 1
	_route_leg(sq)


## NAV-PERF-01B: how urgent a squad's route is: the player's own squads, then squads in contact or running a tactic, then operations;
## everything else (strategic moves) last. RouteService ages waiting requests, so none waits for ever.
func route_priority(sq: SquadState) -> int:
	if sq == null:
		return RouteService.Priority.STRATEGIC
	var war := sim.state.war
	if sq.tactic_owner == SquadState.Owner.PLAYER or ((not war.active or sq.faction == war.player_faction) and sq.op_id < 0):
		return RouteService.Priority.PLAYER
	if sq.tactic != SquadState.Tactic.NONE:
		return RouteService.Priority.COMBAT
	if sq.op_id >= 0:
		return RouteService.Priority.OPERATION
	return RouteService.Priority.STRATEGIC


# --- Routes (WORLD-SANDBOX-01) ---------------------------------------------------

## Sends squads along a route of waypoints: one ordinary squad Move order per waypoint,
## the next one given as the leader comes within route_reach_m (column formation on the
## march). The squad's order is MOVE throughout, so bodies, the abstract tier, cover
## reactions and the HUD treat it like any other move.
func follow_route(sq: SquadState, route: PackedVector3Array, formation := SquadState.Formation.COLUMN) -> void:
	sim.tactics.on_order(sq)
	drop_route_wait(sq)
	sq.route = route
	sq.route_i = 0
	if route.is_empty():
		return
	sq.formation = formation
	_route_leg(sq)


## Drops a squad's route (its current order stays as it is).
func clear_route(sq: SquadState) -> void:
	drop_route_wait(sq)
	sq.route = PackedVector3Array()
	sq.route_i = 0
	if _end_formation.has(sq.id):
		sq.formation = _end_formation[sq.id]
		_end_formation.erase(sq.id)


func _route_leg(sq: SquadState) -> void:
	var target := sq.route[sq.route_i]
	if sq.route_i == sq.route.size() - 1 and _end_formation.has(sq.id):
		sq.formation = _end_formation[sq.id]
		_end_formation.erase(sq.id)
	# AI-SQUAD-01: a squad that picks its own formation spreads out as soon as it is in contact
	# and takes the shape the ground at the end of the march suits (wedge, column, dispersed).
	if sq.formation_auto:
		var assessed := sim.tactics.assessment(sq)
		if not assessed.is_empty() and assessed.get("in_contact", false):
			sq.formation = SquadState.Formation.DISPERSED
		elif sq.route_i == sq.route.size() - 1:
			sq.formation = choose_formation(sq, target)
	var from := _centroid(sq) if sq.route_i == 0 else sq.route[sq.route_i - 1]
	_order_move_one(sq, target, _yaw_towards(from, target, sq.order_yaw))


func _update_route(sq: SquadState) -> void:
	var leader := sim.state.get_unit(sq.leader_id)
	if leader == null:
		return
	var target := sq.route[sq.route_i]
	var last := sq.route_i >= sq.route.size() - 1
	# N1-C1: the waypoints on a bridge deck are the deck itself (StrategicRoutes lays them): a walker has to reach each one, it
	# may not cut the corner to a waypoint on the far bank across the river.
	var reach := 6.0 if last or sim.state.roads.bridge_at(target, 3.0) != null else route_reach_m
	var close := _flat(leader.position, target) <= reach
	# Done with the leg: close enough, or the squad's move finished / got stuck there, or
	# the leader made no progress for route_stall_s (an obstacle the abstract tier does not
	# get round): the next waypoint is tried.
	var finished := sq.order == SquadState.Order.MOVE and sq.status != SquadState.Status.MOVING
	var d := _flat(leader.position, target)
	var prog: Array = _leg_progress.get(sq.id, [INF, sim.state.time, -1])
	if prog[2] != sq.route_i or d < prog[0] - 2.0:
		_leg_progress[sq.id] = [d, sim.state.time, sq.route_i]
	elif sim.state.time - prog[1] > route_stall_s:
		route_stall_events += 1
		if leader.is_reacting():
			route_stall_while_reacting += 1
		_leg_progress.erase(sq.id)
		# NAV-PERF-01B: a new route is already on its way: no second request, no skipped leg (no request-cancel-request loop).
		if route_waiting(sq):
			return
		if _replan(sq):
			return
		finished = true
		route_skips += 1
	if not close and not finished:
		# A squad whose order was replaced (Hold, Follow, a player Move) keeps no route.
		if sq.order != SquadState.Order.MOVE:
			clear_route(sq)
		return
	if last:
		if finished or _flat(_centroid(sq), target) <= reach + _gap(sq) * sq.members.size() * 0.5:
			clear_route(sq)
			route_finished.emit(sq)
		return
	sq.route_i += 1
	_route_leg(sq)


## A stalled leg: plan again from where the squad stands to the route's end (the obstacle
## the old leg ran into is not on the grid: a structure, a crowd, an unmapped steep bank).
func _replan(sq: SquadState) -> bool:
	var routes: StrategicRoutes = sim.war.routes if sim.war else null
	var n: int = _replans.get(sq.id, 0)
	if routes == null or not routes.ready or n >= route_replans or sq.route.is_empty():
		return false
	var goal := sq.route[sq.route.size() - 1]
	# NAV-PERF-01B: asked for; the squad keeps walking its old route until the answer comes (_on_route_job).
	_replans[sq.id] = n + 1
	request_route(sq, goal, "replan", sq.formation)
	return true


## A squad Move for one squad that keeps its route, operation and detachment state.
func _order_move_one(sq: SquadState, target: Vector3, yaw: float) -> void:
	sq.order = SquadState.Order.MOVE
	sq.order_target = target
	sq.order_yaw = yaw
	sq.follow_unit_id = -1
	sq.follow_squad_id = -1
	_send_to_slots(sq, target, yaw, true)


## Stop where they are and stay.
func order_hold(squad_ids: Array) -> void:
	for sq: SquadState in _squads(squad_ids):
		sim.tactics.on_order(sq)
		drop_route_wait(sq)
		sq.order = SquadState.Order.HOLD
		sq.order_target = Vector3.INF
		sq.follow_unit_id = -1
		sq.follow_squad_id = -1
		sq.detached.clear()
		sq.blocked.clear()
		for id in sq.members:
			sim.state.halt(id)
		sq.status = SquadState.Status.DONE
		sim.state.squad_changed.emit(sq)


## Follow a unit; a unit that belongs to another squad means "follow that squad" (its
## leader, so a leader change is picked up). A squad cannot follow itself.
func order_follow(squad_ids: Array, unit_id: int) -> int:
	var target := sim.state.get_unit(unit_id)
	if target == null:
		return 0
	var target_squad := sim.state.squad_of(unit_id)
	var n := 0
	for sq: SquadState in _squads(squad_ids):
		if sq.has_member(unit_id):
			continue
		sim.tactics.on_order(sq)
		drop_route_wait(sq)
		sq.order = SquadState.Order.FOLLOW
		sq.order_target = Vector3.INF
		sq.follow_squad_id = target_squad.id if target_squad else -1
		sq.follow_unit_id = -1 if target_squad else unit_id
		sq.detached.clear()
		sq.blocked.clear()
		sq.status = SquadState.Status.MOVING
		_update_follow(sq, true)
		sim.state.squad_changed.emit(sq)
		n += 1
	return n


## Gather on the leader (point = INF) or at a point. The leader stays where it is when
## regrouping on itself.
func order_regroup(squad_ids: Array, point := Vector3.INF) -> int:
	var n := 0
	for sq: SquadState in _squads(squad_ids):
		var leader := sim.state.get_unit(sq.leader_id)
		if leader == null:
			continue
		sim.tactics.on_order(sq)
		drop_route_wait(sq)
		_auto_formation(sq, point if point.is_finite() else leader.position)
		var centre: Vector3 = point if point.is_finite() else leader.position
		var yaw := leader.yaw if not point.is_finite() else _yaw_towards(_centroid(sq), point, leader.yaw)
		sq.order = SquadState.Order.REGROUP
		sq.order_target = point
		sq.order_yaw = yaw
		sq.follow_unit_id = -1
		sq.follow_squad_id = -1
		n += _send_to_slots(sq, centre, yaw, true, not point.is_finite())
	return n


func set_formation(squad_ids: Array, formation: SquadState.Formation) -> void:
	for sq: SquadState in _squads(squad_ids):
		sq.formation = formation
		_reapply(sq)


## COMBAT-01b rules of engagement. Changes nothing about movement: the soldiers' AI
## reads the squad's ROE before every shot.
func set_roe(squad_ids: Array, roe: SquadState.Roe) -> int:
	var n := 0
	for sq: SquadState in _squads(squad_ids):
		sq.roe = roe
		sim.state.squad_changed.emit(sq)
		n += 1
	return n


func set_spacing(squad_ids: Array, spacing: float) -> void:
	for sq: SquadState in _squads(squad_ids):
		sq.spacing = clampf(spacing, 1.5, 10.0)
		_reapply(sq)


## QOL-01: the squads' behaviour mode (SquadBehaviour). Not an order: the current order, tactic and route stay; a march under
## way is re-planned for the new mode from where the squad stands (walking the old route until the new one comes), and the
## formation takes the mode's spacing. Returns the number of squads changed.
func set_behaviour(squad_ids: Array, b: int) -> int:
	var n := 0
	for sq: SquadState in _squads(squad_ids):
		if sq.behaviour == b:
			continue
		sq.behaviour = clampi(b, 0, 3)
		n += 1
		if sq.op_id < 0 and sq.order == SquadState.Order.MOVE and not sq.route.is_empty() and not route_waiting(sq):
			request_route(sq, sq.route[sq.route.size() - 1], "replan", sq.formation)
		elif sq.order == SquadState.Order.MOVE and sq.route.is_empty() and not route_waiting(sq) and sq.status == SquadState.Status.MOVING:
			_send_to_slots(sq, sq.order_target, sq.order_yaw, false)
		sim.state.squad_changed.emit(sq)
	return n


## QOL-01: where the squad's move is finally going: the end of its route, the goal of the route it waits for, else the move
## target (INF when it has no move).
func move_goal(sq: SquadState) -> Vector3:
	if sq.route_wait_goal.is_finite() and (sq.route_wait_kind == "move" or sq.route.is_empty()):
		return sq.route_wait_goal
	if not sq.route.is_empty():
		return sq.route[sq.route.size() - 1]
	if sq.order == SquadState.Order.MOVE:
		return sq.order_target
	return Vector3.INF


## QOL-01: what the squad's order is doing, from the records only (order, status, route, tactic, the reasons the systems
## wrote): {state, text, goal, left_m}. state: planning, moving, interrupted, blocked, route_blocked, arrived, holding,
## following, regrouping, tactic, garrison, aboard, idle. Every UI surface and the order notices read this; nothing here
## estimates a progress the records do not hold.
func describe_order(sq: SquadState) -> Dictionary:
	var c := _centroid(sq)
	var goal := move_goal(sq)
	var left := _flat(c, goal) if goal.is_finite() else -1.0
	var out := {"state": "idle", "text": "No order", "goal": goal, "left_m": left}
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u and u.vehicle_id >= 0:
			out.state = "aboard"
			out.text = "Aboard a vehicle"
			return out
	if route_block_reason.has(sq.id) and sq.order == SquadState.Order.HOLD:
		out.state = "route_blocked"
		out.text = "Route blocked: %s" % route_block_reason[sq.id]
		return out
	if sq.interrupted and sq.tactic != SquadState.Tactic.NONE:
		var g := sq.prev_target
		out.state = "interrupted"
		out.goal = g
		out.left_m = _flat(c, g) if g.is_finite() else -1.0
		out.text = "Move interrupted: %s - resumes when the contact is over (%.0f m to go)" % [sq.tactic_name().to_lower(), out.left_m]
		return out
	if sq.tactic != SquadState.Tactic.NONE:
		out.state = "garrison" if sq.garrison_base >= 0 else "tactic"
		out.text = sq.tactic_why if sq.tactic_why != "" else sq.tactic_name()
		return out
	match sq.order:
		SquadState.Order.MOVE:
			if route_waiting(sq) and sq.route.is_empty():
				out.state = "planning"
				out.text = "Planning the route (%.0f m)" % left
			elif sq.status == SquadState.Status.PARTIAL:
				out.state = "blocked"
				var why := ""
				for id in sq.blocked:
					var u := sim.state.get_unit(id)
					if u and u.nav_reason != "":
						why = u.nav_reason
						break
				out.text = "%s cannot reach %s%s" % ["1 soldier" if sq.blocked.size() == 1 else "%d soldiers" % sq.blocked.size(), "his place" if sq.blocked.size() == 1 else "their places", (": " + why) if why != "" else ""]
			elif sq.status == SquadState.Status.MOVING:
				out.state = "moving"
				var how := ""
				if not sq.route.is_empty():
					how = " by route, leg %d of %d" % [sq.route_i + 1, sq.route.size()]
				out.text = "Moving, %.0f m to go%s" % [left, how]
			else:
				out.state = "arrived"
				out.text = "Arrived"
		SquadState.Order.HOLD:
			out.state = "holding"
			out.text = "Holding position"
		SquadState.Order.FOLLOW:
			var t := follow_target(sq)
			out.state = "following"
			out.text = "Following %s" % (t.unit_name if t else "-")
		SquadState.Order.REGROUP:
			out.state = "regrouping"
			out.text = "Regrouping" if sq.status == SquadState.Status.MOVING else "Regrouped"
	return out


## AI-SQUAD-01: the formation a squad with formation_auto takes for a movement towards `at`:
## column on roads and in woods (narrow, navigable), dispersed while it is in contact, wedge in the
## open. Slots are preferences: _free_ground moves any that fall on unusable ground.
func choose_formation(sq: SquadState, at: Vector3) -> int:
	var assessed := sim.tactics.assessment(sq)
	if not assessed.is_empty() and assessed.get("in_contact", false):
		return SquadState.Formation.DISPERSED
	if sim.state.roads.on_road(at, 3.0):
		return SquadState.Formation.COLUMN
	if sim.structures != null:
		var trees := 0
		var c0 := VegetationChunk.cell_of(at - Vector3(22.0, 0, 22.0), 128.0)
		var c1 := VegetationChunk.cell_of(at + Vector3(22.0, 0, 22.0), 128.0)
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				for t: Array in sim.structures._trees_in(Vector2i(cx, cz)):
					if Vector2(t[0] - at.x, t[1] - at.z).length() <= 22.0 and int(t[3]) <= 6:
						trees += 1
		if trees >= 14:
			return SquadState.Formation.COLUMN
	return SquadState.Formation.WEDGE


func _auto_formation(sq: SquadState, at: Vector3) -> void:
	if sq.formation_auto and at.is_finite():
		sq.formation = choose_formation(sq, at)


## Formation or spacing changed: an active Move / Regroup takes the new shape.
func _reapply(sq: SquadState) -> void:
	match sq.order:
		SquadState.Order.MOVE:
			_send_to_slots(sq, sq.order_target, sq.order_yaw, false)
		SquadState.Order.REGROUP:
			var leader := sim.state.get_unit(sq.leader_id)
			if leader:
				var centre: Vector3 = sq.order_target if sq.order_target.is_finite() else leader.position
				_send_to_slots(sq, centre, sq.order_yaw, false, not sq.order_target.is_finite())
		SquadState.Order.FOLLOW:
			_update_follow(sq, true)
	sim.state.squad_changed.emit(sq)


# --- Per tick ---------------------------------------------------------------------

func update(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = update_interval
	_follow_timer -= update_interval
	var follow_now := _follow_timer <= 0.0
	if follow_now:
		_follow_timer = follow_interval
	for sq: SquadState in sim.state.squads.values():
		if sq.order == SquadState.Order.FOLLOW and follow_now:
			_update_follow(sq, false)
		if not sq.route.is_empty():
			_update_route(sq)
		elif sq.route_wait_goal.is_finite() and not sim.routing.is_pending(sq.route_job):
			# The request was lost (a save loaded, the queue reset): ask again, nothing else changes.
			_submit_wait(sq)
		_update_status(sq)


func _update_status(sq: SquadState) -> void:
	# NAV-PERF-01B: waiting for the route of an order: moving, not done.
	if sq.route.is_empty() and (sq.route_wait_kind == "move" or sq.route_wait_kind == "op") and sq.route_wait_goal.is_finite():
		if sq.status != SquadState.Status.MOVING:
			sq.status = SquadState.Status.MOVING
			sim.state.squad_changed.emit(sq)
		return
	if sq.order == SquadState.Order.NONE or sq.order == SquadState.Order.HOLD:
		return
	var moving := 0
	var blocked := PackedInt32Array()
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u == null or sq.is_detached(id) or u.player_controlled:
			_member_progress.erase(id)
			continue
		if _recover_member_if_needed(sq, u):
			moving += 1
			continue
		if u.move_state == UnitState.MoveState.MOVING and u.has_order():
			moving += 1
		elif u.move_state == UnitState.MoveState.BLOCKED:
			blocked.append(id)
	var status := SquadState.Status.MOVING if moving > 0 else (SquadState.Status.PARTIAL if not blocked.is_empty() else SquadState.Status.DONE)
	if status != sq.status or blocked != sq.blocked:
		sq.status = status
		sq.blocked = blocked
		sim.state.squad_changed.emit(sq)


func _recover_member_if_needed(sq: SquadState, u: UnitState) -> bool:
	# NAV-PERF-01B: a walker waiting for its local refinement is not stalled either.
	if u.vehicle_id >= 0 or u.is_reacting() or sq.order == SquadState.Order.HOLD or sim.local_route_pending(u.id):
		# A tactical reaction, transport or Hold legitimately pauses formation movement.
		var paused: Dictionary = _member_progress.get(u.id, {})
		if not paused.is_empty():
			paused.at = sim.state.time
			paused.best = _flat(u.position, paused.target)
			_member_progress[u.id] = paused
		return false
	if u.move_state == UnitState.MoveState.ARRIVED:
		_member_progress.erase(u.id)
		return false
	var target := u.order_target
	var p: Dictionary = _member_progress.get(u.id, {})
	if p.is_empty() or _flat(p.get("target", Vector3.INF), target) > 0.5:
		p = {"target": target, "best": _flat(u.position, target), "at": sim.state.time,
			"last_pos": u.position, "attempts": 0, "failed": false}
	var d := _flat(u.position, target)
	if int(p.attempts) > 0 and p.has("recovered_at") and _flat(u.position, p.recovered_at) >= member_renew_m:
		p.attempts = 0
		p.failed = false
	if _flat(u.position, p.get("last_pos", u.position)) > 1.0:
		p.last_pos = u.position
		p.best = minf(float(p.best), d)
		p.at = sim.state.time
	var stalled := u.move_state == UnitState.MoveState.BLOCKED \
		or (u.order == UnitState.Order.MOVE and sim.state.time - float(p.at) >= member_stall_s)
	if stalled and int(p.attempts) < member_replans:
		member_stalls += 1
		member_recoveries += 1
		p.attempts = int(p.attempts) + 1
		p.recovered_at = u.position
		p.at = sim.state.time
		p.best = d
		p.last_pos = u.position
		p.failed = false
		_member_progress[u.id] = p
		sim.invalidate_local_route(u.id)
		# GAMEPLAY-05: the same walk again, so a tactic's post stays his (issue_move ends posts; without it a soldier of a
		# defence that recovered here had no post left, and once the budget was spent the garrison read BLOCKED for good).
		var post := u.post_pos
		var key := u.fort_slot
		sim.state.issue_move(u.id, target, false)
		u.post_pos = post
		u.fort_slot = key
		return true
	if stalled and not bool(p.failed):
		member_failures += 1
		p.failed = true
		if u.nav_reason == "":
			u.nav_reason = "blocked after member recovery budget"
	_member_progress[u.id] = p
	return false


func _update_follow(sq: SquadState, force: bool) -> void:
	var t := follow_target(sq)
	if t == null:
		sq.order = SquadState.Order.HOLD
		sq.status = SquadState.Status.DONE
		sim.state.squad_changed.emit(sq)
		return
	var fwd := Vector3(t.velocity.x, 0.0, t.velocity.z)
	# A standing target keeps the last walking direction: its idle turning must not
	# shuffle the slots behind it.
	var yaw := sq.order_yaw if sq.order_target.is_finite() else t.yaw
	if fwd.length() > 0.5:
		yaw = atan2(-fwd.x, -fwd.z)
	var dir := _forward(yaw)
	var lead := _slot_count(sq)
	var anchor := t.position + Vector3(t.velocity.x, 0.0, t.velocity.z) * follow_lead_s - dir * follow_distance
	if sq.formation == SquadState.Formation.LINE:
		anchor -= dir * _gap(sq) * 0.5
	sq.order_target = anchor
	sq.order_yaw = yaw
	var slots := _slots(sq, anchor, yaw)
	var ids := _active_members(sq)
	for i in ids.size():
		var u := sim.state.get_unit(ids[i])
		var s: Vector3 = slots[mini(i, lead - 1)]
		var last: Vector3 = _follow_slot.get(u.id, Vector3.INF)
		if not force and last.is_finite() and _flat(last, s) < follow_reissue_m:
			# The slot is where it was last ordered: walking there, stopped near it, or
			# reported BLOCKED, the soldier keeps what it has. Only one pushed far away
			# goes back. (UNIT-01A compared the soldier's position with the slot, so a
			# follower that ended its walk 3-4 m off - crowding, stuck handling - got the
			# same slot again although the leader stood still.)
			if u.order == UnitState.Order.MOVE or u.move_state == UnitState.MoveState.BLOCKED or _flat(u.position, s) < follow_drift_m:
				continue
		elif not force and not last.is_finite():
			if u.order == UnitState.Order.MOVE and _flat(u.order_target, s) < follow_reissue_m:
				continue
			if u.order != UnitState.Order.MOVE and _flat(u.position, s) < follow_settle_m:
				continue
		# A new Follow order replaces a reaction; keeping the slots up to date does not
		# (a follower may finish a short dash to cover first).
		sim.state.issue_move(u.id, s, force)
		_follow_slot[u.id] = s


## The unit a following squad walks behind, or null.
func follow_target(sq: SquadState) -> UnitState:
	if sq.follow_squad_id > 0:
		var other := sim.state.get_squad(sq.follow_squad_id)
		return sim.state.get_unit(other.leader_id) if other else null
	return sim.state.get_unit(sq.follow_unit_id) if sq.follow_unit_id > 0 else null


# --- Formation --------------------------------------------------------------------

## Issues one move per member to the formation slots around centre. reset: the squad
## order is new (detached members rejoin). leader_stays: the leader keeps its place
## (regroup on the leader).
func _send_to_slots(sq: SquadState, centre: Vector3, yaw: float, reset: bool, leader_stays := false) -> int:
	if reset:
		sq.detached.clear()
	sq.blocked.clear()
	sq.status = SquadState.Status.MOVING
	var ids := _active_members(sq)
	var slots := _slots(sq, centre, yaw)
	var order := _assign(sq, ids, slots, yaw)
	for i in ids.size():
		var u := sim.state.get_unit(ids[i])
		if leader_stays and u.id == sq.leader_id:
			sim.state.halt(u.id)
			u.move_state = UnitState.MoveState.ARRIVED
			continue
		sim.state.issue_move(u.id, slots[order[i]])
	sim.state.squad_changed.emit(sq)
	return ids.size()


## Members the squad order drives (not detached), leader first.
func _active_members(sq: SquadState) -> Array:
	var out := []
	var lu := sim.state.get_unit(sq.leader_id)
	if not sq.is_detached(sq.leader_id) and lu and lu.vehicle_id < 0:
		out.append(sq.leader_id)
	for id in sq.members:
		var mu := sim.state.get_unit(id)
		if id != sq.leader_id and not sq.is_detached(id) and mu and mu.vehicle_id < 0:
			out.append(id)
	return out


func _slot_count(sq: SquadState) -> int:
	return maxi(_active_members(sq).size(), 1)


## Slot positions (on the ground) for the active members. Line: across the facing,
## leader in the middle. Column: one file behind the leader. Slots that fall into water
## or a structure move to the nearest free spot nearby.
func _slots(sq: SquadState, centre: Vector3, yaw: float) -> Array:
	var n := _slot_count(sq)
	var fwd := _forward(yaw)
	var right := _right(yaw)
	var out := []
	for i in n:
		var off := Vector3.ZERO
		match sq.formation:
			SquadState.Formation.LINE:
				# Slot 0 (leader) in the middle, then alternating right / left.
				var k := (i + 1) / 2 * (1 if i % 2 == 1 else -1)
				off = right * k * _gap(sq)
			SquadState.Formation.WEDGE, SquadState.Formation.DISPERSED:
				# Leader at the point, the others alternately right and left, a rank back each.
				var gap := _gap(sq) if sq.formation == SquadState.Formation.WEDGE else maxf(_gap(sq) * 1.8, 5.5)
				var rank := (i + 1) / 2
				var side := 1 if i % 2 == 1 else -1
				off = right * side * rank * gap * 0.9 - fwd * rank * gap * 0.8
			SquadState.Formation.STAGGERED:
				# Two files offset against each other.
				var row := i / 2
				var side2 := -1 if i % 2 == 0 else 1
				off = right * side2 * _gap(sq) * 0.6 - fwd * (row * _gap(sq) * 1.4 + (0.0 if i % 2 == 0 else _gap(sq) * 0.7))
			_:
				off = -fwd * i * _gap(sq)
		out.append(_free_ground(centre + off))
	return out


## Pairs members with slots so paths cross little: the leader takes slot 0; the others
## are matched by their order across (line) or along (column) the facing.
func _assign(sq: SquadState, ids: Array, slots: Array, yaw: float) -> Array:
	var across := sq.formation == SquadState.Formation.LINE or sq.formation == SquadState.Formation.WEDGE or sq.formation == SquadState.Formation.DISPERSED
	var axis := _right(yaw) if across else _forward(yaw)
	var result := []
	result.resize(ids.size())
	var rest_ids := []
	var rest_slots := []
	for i in ids.size():
		if ids[i] == sq.leader_id:
			result[i] = 0
		else:
			rest_ids.append(i)
	for k in range(1, slots.size()):
		rest_slots.append(k)
	if not ids.has(sq.leader_id):
		rest_slots.push_front(0)
	var key_u := func(i: int) -> float: return sim.state.get_unit(ids[i]).position.dot(axis)
	var key_s := func(k: int) -> float: return (slots[k] as Vector3).dot(axis)
	rest_ids.sort_custom(func(a: int, b: int) -> bool: return key_u.call(a) < key_u.call(b))
	rest_slots.sort_custom(func(a: int, b: int) -> bool: return key_s.call(a) < key_s.call(b))
	for j in rest_ids.size():
		result[rest_ids[j]] = rest_slots[mini(j, rest_slots.size() - 1)]
	return result


func _free_ground(p: Vector3) -> Vector3:
	var q := _ground(p)
	# BRIDGE-NAV-01: beside a bridge deck, ground nobody stands on - the river, or the bank under the abutment steeper than
	# infantry climbs - is no slot: the order means the deck. Left on such a bank face, the slot's nearest navmesh point was the
	# bare lip of the bank; the soldier slid off it to the river bank below, climbed back and slid again (Rv1 approach).
	var roads := sim.state.roads
	if roads.bridge_at(q, DECK_SIDE_M) != null and is_nan(roads.deck_height(q)) and (_steep(q) or not _usable(q)):
		var deck := roads.onto_deck(q)
		if deck.is_finite():
			return deck + Vector3.UP * 0.25
	if _usable(q):
		return q
	for r: float in [1.5, 3.0, 4.5, 6.0]:
		for k in 8:
			var a := k * TAU / 8.0
			var c := _ground(p + Vector3(cos(a), 0.0, sin(a)) * r)
			if _usable(c):
				return c
	# WORLD-PLAYTEST-01: a slot in the river beside a bridge goes onto the deck.
	var on := sim.state.roads.onto_deck(p)
	if on.is_finite():
		return on + Vector3.UP * 0.25
	return q


## True when the terrain at p is steeper than infantry climbs (central differences over 1 m).
func _steep(p: Vector3) -> bool:
	if sim.terrain == null:
		return false
	var d := sim.terrain.data
	var gx := (d.get_height(p + Vector3(1, 0, 0)) - d.get_height(p - Vector3(1, 0, 0))) * 0.5
	var gz := (d.get_height(p + Vector3(0, 0, 1)) - d.get_height(p - Vector3(0, 0, 1))) * 0.5
	return Vector2(gx, gz).length() > WorldSim.INFANTRY_MAX_GRADE


func _usable(p: Vector3) -> bool:
	var st := sim.structures
	if st == null:
		return true
	return not st.blocks_point(Vector2(p.x, p.z), 0.6) and not st._wet(p.x, p.z, p.y - 0.25)


func _ground(p: Vector3) -> Vector3:
	if sim.terrain:
		var h: float = sim.terrain.data.get_height(p)
		# On a bridge the ground is the deck, not the river bed under it.
		var deck := sim.state.roads.deck_height(p)
		if not is_nan(deck):
			h = deck if is_nan(h) else maxf(h, deck)
		if not is_nan(h):
			return Vector3(p.x, h + 0.25, p.z)
	return p


## QOL-01: the distance between neighbouring slots: the squad's spacing x its behaviour mode's (COMBAT and STEALTH spread
## out). The selected mode, not the situation: the shape does not change with every reaction.
func _gap(sq: SquadState) -> float:
	return sq.spacing * SquadBehaviour.SPACING[clampi(sq.behaviour, 0, 3)]


func _width(sq: SquadState) -> float:
	match sq.formation:
		SquadState.Formation.LINE:
			return (_slot_count(sq) - 1) * _gap(sq)
		SquadState.Formation.WEDGE:
			return _slot_count(sq) * 0.5 * _gap(sq) * 1.8
		SquadState.Formation.DISPERSED:
			return _slot_count(sq) * 0.5 * maxf(_gap(sq) * 1.8, 5.5) * 1.8
	return _gap(sq)


func _centroid(sq: SquadState) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u:
			c += u.position
			n += 1
	return c / maxi(n, 1)


func _squads(ids: Array) -> Array:
	var out := []
	for id in ids:
		var sq := sim.state.get_squad(id)
		if sq:
			out.append(sq)
	return out


static func _yaw_towards(from: Vector3, to: Vector3, fallback: float) -> float:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return atan2(-d.x, -d.z) if d.length() > 0.5 else fallback


## Facing direction for a yaw (0 = -Z, Godot convention).
static func _forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func _right(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

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
var route_replans := 3
var routed_orders := 0
var route_replanned := 0
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


# --- Orders -----------------------------------------------------------------------

## Moves squads to a point: each keeps its formation, facing the direction of travel;
## several squads stand side by side across that direction.
func order_move(squad_ids: Array, target: Vector3) -> int:
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
	var r := routes.route(from, target, sim.terrain)
	if r.size() < 2:
		return false
	r[r.size() - 1] = target
	_replans.erase(sq.id)
	routed_orders += 1
	# March in column (narrow enough for bridges and tracks), take the ordered formation
	# again for the last leg.
	_end_formation[sq.id] = _end_formation.get(sq.id, sq.formation)
	follow_route(sq, r, SquadState.Formation.COLUMN)
	return true


# --- Routes (WORLD-SANDBOX-01) ---------------------------------------------------

## Sends squads along a route of waypoints: one ordinary squad Move order per waypoint,
## the next one given as the leader comes within route_reach_m (column formation on the
## march). The squad's order is MOVE throughout, so bodies, the abstract tier, cover
## reactions and the HUD treat it like any other move.
func follow_route(sq: SquadState, route: PackedVector3Array, formation := SquadState.Formation.COLUMN) -> void:
	sim.tactics.on_order(sq)
	sq.route = route
	sq.route_i = 0
	if route.is_empty():
		return
	sq.formation = formation
	_route_leg(sq)


## Drops a squad's route (its current order stays as it is).
func clear_route(sq: SquadState) -> void:
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
	var reach := 6.0 if last else route_reach_m
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
		_leg_progress.erase(sq.id)
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
		if finished or _flat(_centroid(sq), target) <= reach + sq.spacing * sq.members.size() * 0.5:
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
	var r := routes.route(_centroid(sq), goal, sim.terrain)
	if r.size() < 2:
		return false
	r[r.size() - 1] = goal
	_replans[sq.id] = n + 1
	route_replanned += 1
	follow_route(sq, r, sq.formation)
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
		_update_status(sq)


func _update_status(sq: SquadState) -> void:
	if sq.order == SquadState.Order.NONE or sq.order == SquadState.Order.HOLD:
		return
	var moving := 0
	var blocked := PackedInt32Array()
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u == null or sq.is_detached(id) or u.player_controlled:
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
		anchor -= dir * sq.spacing * 0.5
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
				off = right * k * sq.spacing
			SquadState.Formation.WEDGE, SquadState.Formation.DISPERSED:
				# Leader at the point, the others alternately right and left, a rank back each.
				var gap := sq.spacing if sq.formation == SquadState.Formation.WEDGE else maxf(sq.spacing * 1.8, 5.5)
				var rank := (i + 1) / 2
				var side := 1 if i % 2 == 1 else -1
				off = right * side * rank * gap * 0.9 - fwd * rank * gap * 0.8
			SquadState.Formation.STAGGERED:
				# Two files offset against each other.
				var row := i / 2
				var side2 := -1 if i % 2 == 0 else 1
				off = right * side2 * sq.spacing * 0.6 - fwd * (row * sq.spacing * 1.4 + (0.0 if i % 2 == 0 else sq.spacing * 0.7))
			_:
				off = -fwd * i * sq.spacing
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


func _width(sq: SquadState) -> float:
	match sq.formation:
		SquadState.Formation.LINE:
			return (_slot_count(sq) - 1) * sq.spacing
		SquadState.Formation.WEDGE:
			return _slot_count(sq) * 0.5 * sq.spacing * 1.8
		SquadState.Formation.DISPERSED:
			return _slot_count(sq) * 0.5 * maxf(sq.spacing * 1.8, 5.5) * 1.8
	return sq.spacing


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

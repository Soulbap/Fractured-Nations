## The strategic simulation of the persistent war (WORLD-SANDBOX-01).
##
## Runs inside WorldSim's physics step at low frequency and changes only WarState and
## ordinary squad orders. Nothing here moves, shoots or kills a soldier directly:
##   - capture (every second): soldiers inside each objective's radius, per faction;
##   - operations (every second): squads march along StrategicRoutes waypoints with
##     SquadControl, assault / hold with squad orders, and the operation succeeds, fails or
##     stalls from what happens to them (losses, the objective's owner, time);
##   - faction AI (each AI faction every FactionProfile.decision_s): threats, garrisons,
##     reinforcement, attacks, recovery - all as operations of real squads;
##   - reserves: finite replacements arrive as new squads at a faction's HQ;
##   - intelligence (every 2 s): what each faction knows about enemy soldiers.
##
## Order ownership, highest first: the player's direct orders (RTS / map) > operations >
## CombatBrain's temporary reactions. A player order releases a squad from its operation
## (release_squads); operations never touch squads of the player's faction unless the
## player created that operation; AI factions only ever command their own squads.
class_name WarSim
extends RefCounted

signal event_logged(e: Dictionary)

const PROFILE_DIR := "res://assets/strategy/%s.tres"

## Capture: soldiers needed, seconds to capture with capture_ref soldiers, decay rates.
var capture_min := 2
var capture_s := 90.0
var capture_ref := 4.0
var decay_owner_s := 30.0
var decay_empty_s := 180.0
## Operations: give up an attack below this share of its strength, or after this long
## in the objective area (s); a DEFEND is done after this long without a threat (s).
var fail_ratio := 0.35
var assault_timeout_s := 1200.0
var defend_quiet_s := 150.0
## Staging point of an attack: this far short of the objective along the route (m).
var staging_m := 350.0
## Intelligence: enemy soldiers within this distance of one of a faction's soldiers or
## owned objectives are known to it; they are forgotten this long after (s).
var intel_m := 400.0
var intel_forget_s := 90.0
## Reserves arrive in squads of this size, at most this often (s), up to max_squads.
var reinforce_squad := 8
var reinforce_interval_s := 240.0
var max_squads := 9

var sim: WorldSim
var war: WarState
var routes: StrategicRoutes
var enabled := false
## faction id -> {unit id: [last known position, time seen]}
var known := {}
var _profiles := {}
var _t_capture := 0.0
var _t_ops := 0.0
var _t_intel := 0.0
var _t_reserves := 0.0
## Measurements.
var update_usec := 0
var update_usec_max := 0
var ai_usec := 0
var ai_usec_max := 0
var ops_usec := 0
var updates := 0
var stuck_reroutes := 0
var threatened := {}


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
	war = sim.state.war


func setup(p_routes: StrategicRoutes) -> void:
	routes = p_routes
	enabled = war.active
	sim.squads.route_finished.connect(_on_route_finished)
	sim.state.unit_died.connect(_on_unit_died)
	sim.state.restored.connect(func() -> void:
		war = sim.state.war
		enabled = war.active
		known.clear())


func profile(f: FactionState) -> FactionProfile:
	if not _profiles.has(f.profile_id):
		var path := PROFILE_DIR % f.profile_id
		_profiles[f.profile_id] = load(path) if ResourceLoader.exists(path) else FactionProfile.new()
	return _profiles[f.profile_id]


func update(delta: float) -> void:
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	_t_capture += delta
	_t_ops += delta
	_t_intel += delta
	_t_reserves += delta
	if _t_capture >= 1.0:
		_update_capture(_t_capture)
		_t_capture = 0.0
	if _t_intel >= 2.0:
		_t_intel = 0.0
		_update_intel()
	if _t_ops >= 1.0:
		var to := Time.get_ticks_usec()
		_t_ops = 0.0
		for op: OperationState in war.active_operations():
			_update_operation(op)
		ops_usec += Time.get_ticks_usec() - to
	if _t_reserves >= 5.0:
		_t_reserves = 0.0
		for f: FactionState in war.factions.values():
			_update_reserves(f)
	var now := sim.state.time
	for f: FactionState in war.factions.values():
		if not f.player and now >= f.next_decision_at:
			var ta := Time.get_ticks_usec()
			f.next_decision_at = now + profile(f).decision_s
			_decide(f)
			var dt := Time.get_ticks_usec() - ta
			ai_usec += dt
			ai_usec_max = maxi(ai_usec_max, dt)
	var dt_all := Time.get_ticks_usec() - t0
	update_usec += dt_all
	update_usec_max = maxi(update_usec_max, dt_all)
	updates += 1


# --- Log ---------------------------------------------------------------------------

## faction: who learns about it (-1 = everyone). kind: attack, contested, captured,
## reinforcements, op_done, op_failed, threat, info.
func log_event(faction: int, kind: String, text: String, pos := Vector3.INF) -> void:
	var e := {"t": snappedf(sim.state.time, 0.1), "faction": faction, "kind": kind, "text": text, "pos": pos}
	war.events.append(e)
	if war.events.size() > WarState.MAX_LOG:
		war.events.pop_front()
	event_logged.emit(e)


func events_for(faction: int, n := 8) -> Array:
	var out := []
	for i in range(war.events.size() - 1, -1, -1):
		var e: Dictionary = war.events[i]
		if e.faction < 0 or e.faction == faction:
			out.append(e)
			if out.size() >= n:
				break
	return out


# --- Capture ---------------------------------------------------------------------------

func _update_capture(dt: float) -> void:
	sim.brain._ensure_grid()
	for o: ObjectiveState in war.objectives.values():
		var count := {}
		for u: UnitState in sim.brain._near(o.position, o.radius):
			count[u.faction] = count.get(u.faction, 0) + 1
		o.presence = count
		var present := []
		for f in count:
			if count[f] >= capture_min:
				present.append(f)
		var was_contested := o.contested
		o.contested = present.size() >= 2 or (present.size() == 1 and o.owner >= 0 and present[0] != o.owner and count.get(o.owner, 0) > 0)
		if o.contested:
			if not was_contested:
				var sides := ", ".join(present.map(func(f: int) -> String: return WorldState.faction_name(f)))
				log_event(-1, "contested", "%s is contested (%s)" % [o.obj_name, sides], o.position)
			continue
		if present.size() == 1 and present[0] != o.owner:
			var f: int = present[0]
			if o.capture_faction != f:
				o.capture_faction = f
				o.capture_progress = 0.0
			var rate := clampf(count[f] / capture_ref, 0.5, 2.0) / capture_s
			o.capture_progress = minf(o.capture_progress + rate * dt, 1.0)
			if o.capture_progress >= 1.0:
				_transfer(o, f)
		elif present.size() == 1 and present[0] == o.owner and o.capture_faction >= 0:
			o.capture_progress = maxf(o.capture_progress - dt / decay_owner_s, 0.0)
			if o.capture_progress <= 0.0:
				o.capture_faction = -1
		elif present.is_empty() and o.capture_faction >= 0:
			o.capture_progress = maxf(o.capture_progress - dt / decay_empty_s, 0.0)
			if o.capture_progress <= 0.0:
				o.capture_faction = -1


func _transfer(o: ObjectiveState, f: int) -> void:
	var old := o.owner
	o.owner = f
	o.capture_faction = -1
	o.capture_progress = 0.0
	o.last_change_at = sim.state.time
	o.history.append([snappedf(sim.state.time, 0.1), f])
	if o.history.size() > 20:
		o.history.pop_front()
	var nf := war.faction(f)
	if nf:
		nf.objectives_captured += 1
	var of := war.faction(old)
	if of:
		of.objectives_lost += 1
	log_event(-1, "captured", "%s captured %s%s" % [WorldState.faction_name(f), o.obj_name,
		(" from " + WorldState.faction_name(old)) if old >= 0 else ""], o.position)


# --- Intelligence --------------------------------------------------------------------------

## A faction knows the enemy soldiers that are within intel_m of one of its living
## soldiers or within intel_m of the edge of an objective it owns; it remembers their
## last position for intel_forget_s. (No omniscience: an army far from anyone stays
## unseen.) Uses the brain's per-faction grid: each enemy soldier checks the own-faction
## cells around it, stopping at the first observer.
func _update_intel() -> void:
	var now := sim.state.time
	sim.brain._ensure_grid()
	var reach := ceili(intel_m / CombatBrain.FGRID)
	var r2 := intel_m * intel_m
	for f: FactionState in war.factions.values():
		var k: Dictionary = known.get(f.id, {})
		var own: Dictionary = sim.brain._fgrid.get(f.id, {})
		var owned := war.owned_by(f.id)
		for ef: int in sim.brain._fgrid:
			if ef == f.id:
				continue
			var cells: Dictionary = sim.brain._fgrid[ef]
			for cell: Vector2i in cells:
				for u: UnitState in cells[cell]:
					if _observed(u, own, cell, reach, r2, owned):
						k[u.id] = [u.position, now]
		for id in k.keys():
			var u := sim.state.get_unit(id)
			if u == null or not u.alive or now - k[id][1] > intel_forget_s:
				k.erase(id)
		known[f.id] = k


func _observed(u: UnitState, own: Dictionary, cell: Vector2i, reach: int, r2: float, owned: Array) -> bool:
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for o: UnitState in own.get(cell + Vector2i(dx, dz), []):
				var ddx := o.position.x - u.position.x
				var ddz := o.position.z - u.position.z
				if ddx * ddx + ddz * ddz <= r2:
					return true
	for ob: ObjectiveState in owned:
		if _flat(ob.position, u.position) <= ob.radius + intel_m:
			return true
	return false


## Known enemy soldiers of faction f near p (count).
func known_near(f: int, p: Vector3, r: float) -> int:
	var n := 0
	for id in known.get(f, {}):
		var e: Array = known[f][id]
		if Vector2(e[0].x - p.x, e[0].z - p.z).length() <= r:
			n += 1
	return n


# --- Squads ---------------------------------------------------------------------------

func squads_of(f: int) -> Array:
	return sim.state.all_squads().filter(func(s: SquadState) -> bool: return s.faction == f)


func strength(sq: SquadState) -> int:
	return sq.members.size() if sq else 0


func squad_center(sq: SquadState) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u:
			c += u.position
			n += 1
	return c / maxi(n, 1)


## Takes squads out of their operations (a player order, a cancelled operation).
func release_squads(squad_ids: Array, why: String) -> void:
	for sid in squad_ids:
		var sq := sim.state.get_squad(sid)
		if sq == null or sq.op_id < 0:
			if sq:
				sim.squads.clear_route(sq)
			continue
		var op := war.operation(sq.op_id)
		sq.op_id = -1
		sim.squads.clear_route(sq)
		if op:
			var i := op.squads.find(sq.id)
			if i >= 0:
				op.squads.remove_at(i)
			if op.squads.is_empty() and op.is_active():
				_end(op, OperationState.Phase.CANCELLED, why)


# --- Operations ---------------------------------------------------------------------------

## Starts an operation of faction f with squads against an objective (or a point for
## MOVE). Plans each squad's route; squads already in another operation leave it.
## Returns the operation, or null when no squad has a route.
func start_operation(f: int, type: OperationState.Type, squad_ids: Array, objective_id := -1, point := Vector3.INF, player := false) -> OperationState:
	var target := point
	var obj := war.objective(objective_id)
	if obj:
		target = obj.position
	if not target.is_finite() or squad_ids.is_empty():
		return null
	var op := OperationState.new()
	op.id = war.next_op_id
	war.next_op_id += 1
	op.faction = f
	op.type = type
	op.target_objective = objective_id
	op.target_pos = target
	op.started_at = sim.state.time
	op.phase_since = sim.state.time
	op.player_ordered = player
	war.operations[op.id] = op
	var any := false
	for sid in squad_ids:
		var sq := sim.state.get_squad(sid)
		if sq == null or sq.faction != f or sq.members.is_empty():
			continue
		if sq.op_id >= 0:
			release_squads([sq.id], "reassigned")
		if _send(op, sq):
			op.squads.append(sq.id)
			op.start_strength += strength(sq)
			sq.op_id = op.id
			sq.station_objective = -1
			any = true
	if not any:
		war.operations.erase(op.id)
		war.next_op_id -= 1
		return null
	op.phase = OperationState.Phase.MOVING
	var fs := war.faction(f)
	if fs:
		fs.ops_started += 1
	var where := obj.obj_name if obj else "(%.0f, %.0f)" % [target.x, target.z]
	log_event(f, "op_start", "%s #%d: %s, %d squads, %d soldiers" % [op.type_name(), op.id, where, op.squads.size(), op.start_strength], target)
	return op


## Plans and starts the march of one squad for op. ATTACK stops at a staging point short
## of the objective; the others march into the objective area.
func _send(op: OperationState, sq: SquadState) -> bool:
	var from := squad_center(sq)
	var r := routes.route(from, op.target_pos, sim.terrain)
	if r.is_empty():
		return false
	if op.type == OperationState.Type.ATTACK:
		r = _cut_before(r, op.target_pos, staging_m)
		op.staging_pos = r[r.size() - 1]
	else:
		var obj := war.objective(op.target_objective)
		if obj:
			# The end of the march: a spot inside the objective, spread per squad.
			r[r.size() - 1] = _slot_in(obj, op.squads.size())
	if op.route_preview.is_empty():
		op.route_preview = r
	sim.squads.follow_route(sq, r)
	return true


## The route up to the point where it first comes within dist of target.
func _cut_before(r: PackedVector3Array, target: Vector3, dist: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in r:
		out.append(p)
		if Vector2(p.x - target.x, p.z - target.z).length() <= dist:
			break
	if out.size() < 1:
		out.append(r[0])
	return out


## A position inside an objective for the k-th squad (spread round the centre).
func _slot_in(obj: ObjectiveState, k: int) -> Vector3:
	var a := k * 2.3
	var d := obj.radius * (0.25 + 0.15 * (k % 3))
	var p := obj.position + Vector3(cos(a), 0, sin(a)) * d
	if not routes.passable(p):
		p = obj.position
	return _ground(p)


func _ground(p: Vector3) -> Vector3:
	var h: float = sim.terrain.data.get_height(p) if sim.terrain else NAN
	return Vector3(p.x, p.y if is_nan(h) else h, p.z)


func _on_route_finished(_sq: SquadState) -> void:
	pass  # operations poll their squads every second (_update_operation)


func _update_operation(op: OperationState) -> void:
	var now := sim.state.time
	# Squads that were wiped out leave the operation.
	var alive := PackedInt32Array()
	var soldiers := 0
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq and not sq.members.is_empty() and sq.op_id == op.id:
			alive.append(sid)
			soldiers += strength(sq)
	op.squads = alive
	op.losses = maxi(op.start_strength - soldiers, 0)
	if op.squads.is_empty():
		_end(op, OperationState.Phase.FAILED, "all squads lost")
		return
	var obj := war.objective(op.target_objective)
	var marching := false
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if not sq.route.is_empty():
			marching = true
		elif op.phase == OperationState.Phase.MOVING and sq.order != SquadState.Order.MOVE and _far_from_goal(op, sq):
			# Lost its route (blocked, a reaction ended it): plan again from where it is.
			stuck_reroutes += 1
			_send(op, sq)
			marching = true
	match op.type:
		OperationState.Type.ATTACK:
			if obj and obj.owner == op.faction:
				_garrison(op, obj)
				_end(op, OperationState.Phase.COMPLETED, "%s captured" % obj.obj_name)
				return
			if soldiers < op.start_strength * fail_ratio:
				_end(op, OperationState.Phase.FAILED, "too many losses (%d of %d left)" % [soldiers, op.start_strength])
				return
			if op.phase == OperationState.Phase.MOVING and not marching:
				_set_phase(op, OperationState.Phase.ENGAGING)
				var k := 0
				for sid in op.squads:
					var sq := sim.state.get_squad(sid)
					sim.squads.follow_route(sq, PackedVector3Array([_slot_in(obj, k)]), SquadState.Formation.LINE)
					k += 1
				log_event(-1 if obj.owner >= 0 else op.faction, "attack", "%s attacks %s" % [WorldState.faction_name(op.faction), obj.obj_name], obj.position)
			elif op.phase >= OperationState.Phase.ENGAGING:
				if obj.capture_faction == op.faction and not obj.contested:
					_set_phase(op, OperationState.Phase.SECURING)
				elif op.phase == OperationState.Phase.SECURING and (obj.contested or obj.capture_faction != op.faction):
					_set_phase(op, OperationState.Phase.ENGAGING)
				if now - op.phase_since > assault_timeout_s and op.phase == OperationState.Phase.ENGAGING:
					_end(op, OperationState.Phase.FAILED, "assault stalled")
					return
				# Squads that finished their assault move but stand outside: go in again.
				for sid in op.squads:
					var sq := sim.state.get_squad(sid)
					if sq.route.is_empty() and sq.order != SquadState.Order.MOVE and _flat(squad_center(sq), obj.position) > obj.radius * 0.8:
						sim.squads.follow_route(sq, PackedVector3Array([_slot_in(obj, sid % 5)]), SquadState.Formation.LINE)
		OperationState.Type.DEFEND:
			if obj and obj.owner != op.faction and not obj.contested and obj.capture_faction < 0 and obj.owner >= 0:
				_end(op, OperationState.Phase.FAILED, "%s lost" % obj.obj_name)
				return
			if op.phase == OperationState.Phase.MOVING and not marching:
				_set_phase(op, OperationState.Phase.SECURING)
			elif op.phase == OperationState.Phase.SECURING:
				var threat := obj != null and (obj.contested or known_near(op.faction, obj.position, obj.radius + 400.0) > 0)
				if threat:
					op.phase_since = now
				elif now - op.phase_since > defend_quiet_s and obj:
					_garrison(op, obj)
					_end(op, OperationState.Phase.COMPLETED, "%s secure" % obj.obj_name)
		OperationState.Type.REINFORCE:
			if not marching:
				var join: OperationState = null
				for o2: OperationState in war.active_operations(op.faction):
					if o2 != op and o2.target_objective == op.target_objective and o2.type != OperationState.Type.REINFORCE:
						join = o2
				if obj and obj.owner >= 0 and obj.owner != op.faction:
					# The objective fell before the reinforcements arrived: they attack it.
					op.type = OperationState.Type.ATTACK
					_set_phase(op, OperationState.Phase.ENGAGING)
					var k := 0
					for sid in op.squads:
						sim.squads.follow_route(sim.state.get_squad(sid), PackedVector3Array([_slot_in(obj, k)]), SquadState.Formation.LINE)
						k += 1
					log_event(op.faction, "attack", "Reinforcements found %s in %s hands: counter-attack" % [obj.obj_name, WorldState.faction_name(obj.owner)], obj.position)
					return
				if join:
					for sid in op.squads:
						var sq := sim.state.get_squad(sid)
						sq.op_id = join.id
						join.squads.append(sid)
						join.start_strength += strength(sq)
					op.squads.clear()
					_end(op, OperationState.Phase.COMPLETED, "joined %s #%d" % [join.type_name(), join.id])
				elif obj:
					_garrison(op, obj)
					_end(op, OperationState.Phase.COMPLETED, "arrived at %s" % obj.obj_name)
				log_event(op.faction, "reinforcements", "Reinforcements arrived at %s" % (obj.obj_name if obj else "the front"), op.target_pos)
		OperationState.Type.MOVE:
			if not marching:
				for sid in op.squads:
					sim.state.get_squad(sid).op_id = -1
				op.squads.clear()
				_end(op, OperationState.Phase.COMPLETED, "arrived")


func _far_from_goal(op: OperationState, sq: SquadState) -> bool:
	var goal := op.staging_pos if op.type == OperationState.Type.ATTACK and op.staging_pos.is_finite() else op.target_pos
	return _flat(squad_center(sq), goal) > 120.0


func _set_phase(op: OperationState, p: OperationState.Phase) -> void:
	if op.phase != p:
		op.phase = p
		op.phase_since = sim.state.time


## The operation's squads stay at the objective as its garrison.
func _garrison(op: OperationState, obj: ObjectiveState) -> void:
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq:
			sq.op_id = -1
			sq.station_objective = obj.id
			sim.squads.clear_route(sq)


func _end(op: OperationState, phase: OperationState.Phase, why: String) -> void:
	if not op.is_active():
		return
	op.phase = phase
	op.ended_at = sim.state.time
	op.outcome = why
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq and sq.op_id == op.id:
			sq.op_id = -1
			sim.squads.clear_route(sq)
	var fs := war.faction(op.faction)
	if fs and phase == OperationState.Phase.COMPLETED:
		fs.ops_succeeded += 1
	elif fs and phase == OperationState.Phase.FAILED:
		fs.ops_failed += 1
		if op.type == OperationState.Type.ATTACK:
			fs.recovery_until = sim.state.time + profile(fs).recovery_s
	var kind := "op_done" if phase == OperationState.Phase.COMPLETED else ("op_failed" if phase == OperationState.Phase.FAILED else "op_cancelled")
	var obj := war.objective(op.target_objective)
	log_event(op.faction, kind, "%s #%d %s %s: %s" % [op.type_name(), op.id, obj.obj_name if obj else "", op.phase_name(), why], op.target_pos)


func cancel(op_id: int, why := "cancelled") -> void:
	var op := war.operation(op_id)
	if op and op.is_active():
		_end(op, OperationState.Phase.CANCELLED, why)


# --- Reserves -------------------------------------------------------------------------

## Finite replacements: when a faction has reserves left, fewer than max_squads squads
## and holds its HQ (else its most valuable objective), a new squad arrives there.
func _update_reserves(f: FactionState) -> void:
	var now := sim.state.time
	if f.reserves < 4 or now < f.next_reinforcement_at or squads_of(f.id).size() >= max_squads:
		return
	var at: ObjectiveState = war.objective(f.hq_objective)
	if at == null or at.owner != f.id:
		at = null
		for o: ObjectiveState in war.owned_by(f.id):
			if at == null or o.value > at.value:
				at = o
	if at == null:
		return
	var n := mini(reinforce_squad, f.reserves)
	f.reserves -= n
	f.next_reinforcement_at = now + reinforce_interval_s
	var sq := spawn_squad(f, at.position + Vector3(at.radius * 0.3, 0, at.radius * 0.3), n)
	sq.station_objective = at.id
	log_event(f.id, "reinforcements", "A new squad (%d) arrived at %s; %d in reserve" % [n, at.obj_name, f.reserves], at.position)


## New squad of n soldiers of faction f in a line around p (rifles equipped).
func spawn_squad(f: FactionState, p: Vector3, n: int) -> SquadState:
	var ids := []
	f.squad_counter += 1
	var tag := "%s%d" % [f.faction_name.left(1), f.squad_counter]
	for i in n:
		var q := p + Vector3((i % 4 - 1.5) * 3.0, 0, (i / 4) * 3.0)
		q = _ground(q)
		var u := sim.state.add_unit(UnitState.Kind.SOLDIER, f.id, q + Vector3.UP * 0.3, 0.0, "%s-%d" % [tag, i + 1])
		ids.append(u.id)
	var sq := sim.state.add_squad(tag, f.id, ids)
	sim.combat.equip_all(&"rifle")
	if sim.detail:
		sim.detail.create_missing_proxies()
	return sq


func _on_unit_died(u: UnitState) -> void:
	if not enabled:
		return
	var f := war.faction(u.faction)
	if f:
		f.casualties += 1
	var k := sim.state.get_unit(u.killer_id)
	if k:
		var kf := war.faction(k.faction)
		if kf:
			kf.kills += 1


# --- Faction AI ---------------------------------------------------------------------

## One strategic decision of an AI faction: defend what is threatened, keep garrisons,
## then (not in recovery, below its attack limit) attack the best reachable target with
## enough superiority; depleted squads go home. Each step uses only squads that serve no
## operation, and never the squads an HQ / garrison must keep.
func _decide(f: FactionState) -> void:
	var p := profile(f)
	var now := sim.state.time
	var notes: Array[String] = []
	# 0. Depleted squads go home to recover (they stay there as HQ reserve).
	var hq := war.objective(f.hq_objective)
	for sq: SquadState in squads_of(f.id):
		if sq.op_id < 0 and sq.members.size() < p.min_squad_size and hq and hq.owner == f.id and sq.station_objective != hq.id \
				and _flat(squad_center(sq), hq.position) > hq.radius * 2.0:
			start_operation(f.id, OperationState.Type.REINFORCE, [sq.id], hq.id)
			notes.append("%s home" % sq.squad_name)
	var free := _free_squads(f, p)
	# 1. Threatened objectives get reinforcements.
	for o: ObjectiveState in war.owned_by(f.id):
		var enemies := known_near(f.id, o.position, o.radius + p.threat_radius)
		var was: bool = threatened.get(o.id, false)
		threatened[o.id] = enemies > 0
		if enemies > 0 and not was:
			log_event(f.id, "threat", "Enemy forces near %s (%d seen)" % [o.obj_name, enemies], o.position)
		if enemies <= 0:
			continue
		var defenders := _strength_near(f.id, o.position, o.radius + 150.0) + _incoming(f.id, o.id)
		if defenders >= enemies * p.threat_ratio:
			continue
		var need := ceili(enemies * p.threat_ratio) - defenders
		var picked := _pick_near(free, o.position, need)
		if not picked.is_empty():
			start_operation(f.id, OperationState.Type.REINFORCE, picked, o.id)
			notes.append("reinforce %s" % o.obj_name)
			for s in picked:
				free.erase(s)
	# 2. Garrisons for valuable objectives without one.
	for o: ObjectiveState in war.owned_by(f.id):
		if o.is_hq() or o.value < p.garrison_min_value or p.garrison_squads <= 0:
			continue
		if _garrison_count(f.id, o.id) + _incoming_squads(f.id, o.id) >= p.garrison_squads:
			continue
		var picked := _pick_near(free, o.position, 1, true)
		if not picked.is_empty():
			start_operation(f.id, OperationState.Type.DEFEND, picked, o.id)
			notes.append("garrison %s" % o.obj_name)
			for s in picked:
				free.erase(s)
	# 3. Offensive.
	var attacks := war.active_operations(f.id).filter(func(o: OperationState) -> bool: return o.type == OperationState.Type.ATTACK).size()
	var free_soldiers := 0
	for sid in free:
		free_soldiers += strength(sim.state.get_squad(sid))
	if now < f.recovery_until:
		notes.append("recovering %.0f s" % (f.recovery_until - now))
	elif attacks >= p.max_attacks:
		notes.append("%d attacks running" % attacks)
	elif free_soldiers < p.min_attack_soldiers:
		notes.append("only %d soldiers free" % free_soldiers)
	else:
		var best: ObjectiveState = null
		var best_score := -INF
		var best_need := 0
		var owned := war.owned_by(f.id)
		for o: ObjectiveState in war.all_objectives():
			if o.owner == f.id or _attacked_by(f.id, o.id):
				continue
			# Distance from the faction's nearest held objective (its front), not from
			# where the free squads happen to stand.
			var d := INF
			for h: ObjectiveState in owned:
				d = minf(d, _flat(h.position, o.position))
			if d > p.max_attack_distance:
				continue
			var defenders := known_near(f.id, o.position, o.radius + 200.0)
			if defenders == 0 and o.owner >= 0:
				defenders = o.value * 4  # unseen garrison: assume one
			var need := maxi(ceili(defenders * p.attack_ratio), p.min_attack_soldiers)
			if need > free_soldiers:
				continue
			var score := o.value * p.w_value - d / 1000.0 * p.w_distance
			score += p.w_neutral if o.owner < 0 else p.w_enemy
			if _lost_by(f.id, o):
				score += p.w_retake
			if score > best_score:
				best_score = score
				best = o
				best_need = need
		if best:
			var picked := _pick_near(free, best.position, best_need)
			var op := start_operation(f.id, OperationState.Type.ATTACK, picked, best.id)
			if op:
				notes.append("attack %s (%d)" % [best.obj_name, op.start_strength])
		else:
			notes.append("no target worth attacking")
	f.last_decision = "; ".join(notes) if not notes.is_empty() else "hold"


## Squads serving no operation, minus what the HQ and the garrisons must keep.
func _free_squads(f: FactionState, p: FactionProfile) -> Array:
	var free := []
	var keep := {}
	for o: ObjectiveState in war.owned_by(f.id):
		keep[o.id] = p.hq_squads if o.is_hq() else (p.garrison_squads if o.value >= p.garrison_min_value else 0)
	var sqs := squads_of(f.id)
	sqs.sort_custom(func(a: SquadState, b: SquadState) -> bool: return a.members.size() < b.members.size())
	for sq: SquadState in sqs:
		if sq.op_id >= 0 or sq.members.size() < p.min_squad_size:
			continue
		var st := sq.station_objective
		if st >= 0 and keep.get(st, 0) > 0:
			keep[st] -= 1
			continue
		free.append(sq.id)
	return free


## Squads from `from` nearest to p until their soldiers reach need (or one squad).
func _pick_near(from: Array, p: Vector3, need: int, one := false) -> Array:
	var sorted := from.duplicate()
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return _flat(squad_center(sim.state.get_squad(a)), p) < _flat(squad_center(sim.state.get_squad(b)), p))
	var out := []
	var got := 0
	for sid in sorted:
		if got >= need and not out.is_empty():
			break
		out.append(sid)
		got += strength(sim.state.get_squad(sid))
		if one:
			break
	return out


func _strength_near(f: int, p: Vector3, r: float) -> int:
	var n := 0
	for u: UnitState in sim.brain._near(p, r):
		if u.faction == f:
			n += 1
	return n


func _incoming(f: int, obj_id: int) -> int:
	var n := 0
	for op: OperationState in war.active_operations(f):
		if op.target_objective == obj_id and op.phase == OperationState.Phase.MOVING:
			for sid in op.squads:
				n += strength(sim.state.get_squad(sid))
	return n


func _incoming_squads(f: int, obj_id: int) -> int:
	var n := 0
	for op: OperationState in war.active_operations(f):
		if op.target_objective == obj_id:
			n += op.squads.size()
	return n


func _garrison_count(f: int, obj_id: int) -> int:
	var n := 0
	for sq: SquadState in squads_of(f):
		if sq.station_objective == obj_id and sq.op_id < 0:
			n += 1
	return n


func _attacked_by(f: int, obj_id: int) -> bool:
	for op: OperationState in war.active_operations(f):
		if op.target_objective == obj_id and op.type == OperationState.Type.ATTACK:
			return true
	return false


## The faction held o at some point (and does not now): retaking it scores higher.
func _lost_by(f: int, o: ObjectiveState) -> bool:
	if o.owner == f:
		return false
	for h: Array in o.history:
		if h[1] == f:
			return true
	return false


func _centroid_of(squad_ids: Array) -> Vector3:
	var c := Vector3.ZERO
	for sid in squad_ids:
		c += squad_center(sim.state.get_squad(sid))
	return c / maxi(squad_ids.size(), 1)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Summary for tests, the map and the report.
func summary() -> Dictionary:
	var out := {"time": snappedf(sim.state.time, 0.1), "factions": {}, "objectives": {}, "ops_active": war.active_operations().size(),
		"ops_total": war.operations.size(), "update_us_avg": snappedf(float(update_usec) / maxi(updates, 1), 0.1), "update_us_max": update_usec_max,
		"ai_us_max": ai_usec_max, "routes": {"planned": routes.routes_planned if routes else 0, "ms_max": snappedf(routes.route_ms_max, 0.01) if routes else 0.0,
		"ms_avg": snappedf(routes.route_ms_total / maxi(routes.routes_planned, 1), 0.01) if routes else 0.0}, "reroutes": stuck_reroutes}
	for f: FactionState in war.factions.values():
		var soldiers := 0
		for sq: SquadState in squads_of(f.id):
			soldiers += sq.members.size()
		out.factions[f.faction_name] = {"objectives": war.owned_by(f.id).size(), "soldiers": soldiers, "squads": squads_of(f.id).size(),
			"reserves": f.reserves, "casualties": f.casualties, "kills": f.kills, "ops": [f.ops_started, f.ops_succeeded, f.ops_failed],
			"last_decision": f.last_decision}
	for o: ObjectiveState in war.all_objectives():
		out.objectives[o.obj_name] = WorldState.faction_name(o.owner) if o.owner >= 0 else "-"
	out["ops"] = []
	for op: OperationState in war.active_operations():
		var obj := war.objective(op.target_objective)
		var d := INF
		var soldiers := 0
		for sid in op.squads:
			var sq := sim.state.get_squad(sid)
			if sq:
				d = minf(d, _flat(squad_center(sq), op.target_pos))
				soldiers += sq.members.size()
		out.ops.append("#%d %s %s %s %s: %d sq, %d/%d, %.0f m" % [op.id, WorldState.faction_name(op.faction).left(1), op.type_name(),
			obj.obj_name if obj else "point", op.phase_name(), op.squads.size(), soldiers, op.start_strength, d])
	return out

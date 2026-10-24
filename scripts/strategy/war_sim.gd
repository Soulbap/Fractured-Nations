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
##   - intelligence (IntelSim, AI-INTEL-01): what each faction has been told about the enemy -
##     reports from soldiers who saw, heard or were shot at, ageing into stale beliefs; the
##     strategic decisions below read only that picture, never the enemy's true positions.
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
## AI-INTEL-01 decisions: a stale contact near an owned objective is investigated by one
## squad at most this often (s), and a decision snapshot list is kept per faction.
var investigate_cooldown_s := 150.0
const DECISIONS_MAX := 10
## Reserves arrive in squads of this size, at most this often (s), up to max_squads.
var reinforce_squad := 8
var reinforce_interval_s := 240.0
var max_squads := 9

var sim: WorldSim
var war: WarState
var routes: StrategicRoutes
var enabled := false
## AI-INTEL-01: the faction contact picture (contacts live in WarState, saved).
var intel: IntelSim
## AI-COMBAT-STRAT-01: roles and stages of multi-squad attacks.
var coord: OpCoordination
## AI-COMBAT-STRAT-01: the strategic picture (threat grid) and the decision scorer.
var influence: StrategicInfluence
var strat: StrategicDecision
## AI-WAR-LOGISTICS-01: the AI factions' economy (income, recruiting, purchases), their bases (start compound,
## later construction), mechanized transport of operations and supply missions / recovery.
var econ: WarEconomy
var bases: AiBases
var mech: OpTransport
var supply: WarLogistics
## GAMEPLAY-04B: Military Development (unlocks, projects, AI development policy).
var dev: MilitaryDevelopment
var _profiles := {}
var _t_capture := 0.0
var _t_ops := 0.0
var _t_reserves := 0.0
## Measurements.
var update_usec := 0
var update_usec_max := 0
var ai_usec := 0
var ai_usec_max := 0
var ops_usec := 0
var updates := 0
var stuck_reroutes := 0
## NAVIGATION N1-C1: a squad whose route could not be planned is tried again after this many seconds, and an operation that has
## had no route for this long fails with the reason (a closed bridge on the only way, for example).
const ROUTE_RETRY_S := 20.0
const ROUTE_BLOCKED_TIMEOUT_S := 300.0
var _route_retry := {}
## NAV-PERF-01B: routes of a starting operation's squads that came before the others (operation id -> squad id -> route); runtime only.
var _start_routes := {}
var _sending_op := -1
var blocked_routes := 0
var threatened := {}
## op id -> march progress (see _track_march; not saved).
var march := {}


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
	war = sim.state.war
	intel = IntelSim.new(self)
	coord = OpCoordination.new(self)
	influence = StrategicInfluence.new(self)
	strat = StrategicDecision.new(self)
	econ = WarEconomy.new(self)
	bases = AiBases.new(self)
	mech = OpTransport.new(self)
	supply = WarLogistics.new(self)
	dev = MilitaryDevelopment.new(self)


func setup(p_routes: StrategicRoutes) -> void:
	routes = p_routes
	enabled = war.active
	sim.squads.route_finished.connect(_on_route_finished)
	sim.state.unit_died.connect(_on_unit_died)
	sim.state.restored.connect(func() -> void:
		war = sim.state.war
		enabled = war.active
		march.clear()
		_alerts.clear()
		intel.rebuild())


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
	_t_reserves += delta
	if _t_capture >= 1.0:
		_update_capture(_t_capture)
		_t_capture = 0.0
	intel.update(delta)
	if _t_ops >= 1.0:
		var to := Time.get_ticks_usec()
		_t_ops = 0.0
		for op: OperationState in war.active_operations():
			_update_operation(op)
		ops_usec += Time.get_ticks_usec() - to
		bases.update()
		supply.update()
	if _t_reserves >= 5.0:
		_t_reserves = 0.0
		sync_bases()
		for f: FactionState in war.factions.values():
			_update_reserves(f)
			_update_garrisons(f)
			_update_base_alerts(f)
	econ.update(delta)
	dev.update(delta)
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
	_update_caches(dt)
	for o: ObjectiveState in war.objectives.values():
		var count := {}
		for u: UnitState in sim.brain._near(o.position, o.radius):
			count[u.faction] = count.get(u.faction, 0) + 1
		o.presence = count
		# AI-INTEL-01: soldiers standing in an objective see the enemy standing in it too.
		if count.size() >= 2:
			for f in count:
				for ef in count:
					if ef != f:
						intel.report_objective(f, ef, o, count[ef])
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


## GAMEPLAY-01B supply caches (WarState.caches), with the presence rule of the objectives: a faction's soldiers come within
## SPOT_M and the faction knows the cache; a faction alone in its radius (no other faction's soldier within the radius plus
## CACHE_SECURE_GAP_M) secures it in about CACHE_SECURE_S (one soldier takes half again as long); the content goes once to
## that faction (BaseSim.faction_deposit) and the cache is depleted for good. Unattended progress fades. A secured cache
## points the faction to the next one it does not know yet.
const CACHE_SECURE_S := 30.0
const CACHE_SECURE_GAP_M := 80.0


func _update_caches(dt: float) -> void:
	for c: Dictionary in war.caches:
		if c.state == "depleted":
			continue
		var p: Vector3 = c.pos
		var r := float(c.radius)
		var count := {}
		var near := {}
		for u: UnitState in sim.brain._near(p, SandboxSetup.CACHE_SPOT_M):
			var d := Vector2(u.position.x - p.x, u.position.z - p.z).length()
			if not (c.known as Array).has(u.faction):
				(c.known as Array).append(u.faction)
				log_event(u.faction, "cache", "Supply cache spotted: %s" % c.name, p)
			if d <= r + CACHE_SECURE_GAP_M:
				near[u.faction] = true
			if d <= r:
				count[u.faction] = int(count.get(u.faction, 0)) + 1
		if count.size() == 1 and near.size() == 1:
			var f: int = count.keys()[0]
			if int(c.faction) != f:
				c.faction = f
				c.progress = 0.0
				log_event(f, "cache", "Securing %s" % c.name, p)
			c.state = "securing"
			c.progress = minf(float(c.progress) + dt * (1.0 if int(count[f]) >= 2 else 0.67) / CACHE_SECURE_S, 1.0)
			if float(c.progress) >= 1.0:
				_collect_cache(c, f)
		elif count.is_empty():
			c.progress = maxf(float(c.progress) - dt / 60.0, 0.0)
			if float(c.progress) <= 0.0:
				c.state = "intact"
				c.faction = -1


func _collect_cache(c: Dictionary, f: int) -> void:
	var items := {}
	for k in ["supplies", "ammo", "fuel"]:
		if float(c.get(k, 0.0)) > 0.0:
			items[StringName(k)] = float(c[k])
	sim.logistics.bases.faction_deposit(f, items)
	var fs := war.faction(f)
	if fs:
		for k in ["supplies", "ammo", "fuel"]:
			fs.ledger["in"][k] = float(fs.ledger["in"][k]) + float(c.get(k, 0.0))
	c.state = "depleted"
	c.progress = 1.0
	c.taken_by = f
	c.taken_at = snappedf(sim.state.time, 0.1)
	var parts: Array[String] = []
	for k: StringName in items:
		parts.append("+%d %s" % [roundi(items[k]), Inventory.NAMES[k]])
	log_event(f, "cache_taken", "%s secured: %s" % [c.name, ", ".join(parts)], c.pos)
	for other: Dictionary in war.caches:
		if other.state != "depleted" and not (other.known as Array).has(f):
			(other.known as Array).append(f)
			log_event(f, "cache", "Papers at %s point to another cache: %s" % [c.name, other.name], other.pos)
			break


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
	# AI-WAR-LOGISTICS-01: the bases that stand on the objective change hands with it (their facilities serve
	# the new owner and stop serving the old one).
	# GAMEPLAY-01D: a base goes with the objective it is linked to (its own base objective, or the headquarters it stands
	# on) - never with a neighbouring objective it merely overlaps.
	if old >= 0:
		for b: Dictionary in sim.logistics.bases.bases_of(old):
			var link := int(b.get("objective", -1))
			if link == o.id or (link < 0 and _flat(b.anchor, o.position) <= o.radius + 60.0):
				sim.logistics.bases.capture_base(b.id, f)
	log_event(-1, "captured", "%s captured %s%s" % [WorldState.faction_name(f), o.obj_name,
		(" from " + WorldState.faction_name(old)) if old >= 0 else ""], o.position)


# --- Intelligence ----------------------------------------------------------------------------
# The contact picture is IntelSim's (scripts/strategy/intel_sim.gd).

## Enemy soldiers faction f believes to be near p (see IntelSim.threat_near).
func threat_near(f: int, p: Vector3, r: float) -> int:
	return intel.threat_near(f, p, r)


# --- Inspection (AI-OBS-01) -------------------------------------------------------------------
# Plain text assembled from the records and the decision snapshots the AI actually produced;
# nothing is reconstructed after the fact.

## Why a squad does what it does: who commands it, what it was told, what its soldiers see.
func explain_squad(sq: SquadState) -> Array[String]:
	var out: Array[String] = []
	var now := sim.state.time
	out.append("%s (%s) - %d soldiers, order %s%s, status %s" % [sq.squad_name, WorldState.faction_name(sq.faction), sq.members.size(), sq.order_name(),
		"" if not sq.order_target.is_finite() else " to (%.0f, %.0f)" % [sq.order_target.x, sq.order_target.z], SquadState.Status.keys()[sq.status].to_lower()])
	var op := war.operation(sq.op_id)
	if op:
		out.append("Commanded by: %s operation #%d %s, %s%s" % ["the player's" if op.player_ordered else "the faction AI's", op.id, op.type_name(), op.phase_name(),
			(", role: " + SquadState.OP_ROLE_NAMES[sq.op_role] + ", operation stage: " + op.stage_name()) if sq.op_role != SquadState.OpRole.NONE else ""])
		if op.reason != "":
			out.append("Reason: " + op.reason)
		if op.contact_id >= 0:
			var c := intel.get_contact(op.faction, op.contact_id)
			out.append("Goes to contact: " + (c.describe(now) if c else "#%d (no longer held)" % op.contact_id))
		if not sq.route.is_empty():
			var rem := 0.0
			var cur := squad_center(sq)
			for i in range(sq.route_i, sq.route.size()):
				rem += _flat(cur, sq.route[i])
				cur = sq.route[i]
			out.append("Route: waypoint %d of %d, %.0f m to go" % [sq.route_i + 1, sq.route.size(), rem])
		elif sim.squads.route_waiting(sq):
			out.append("Route: being planned (%s)" % sq.route_wait_kind)
	elif sq.station_objective >= 0 and war.objective(sq.station_objective):
		out.append("Commanded by: nobody - garrison of %s%s" % [war.objective(sq.station_objective).obj_name, (" (" + sq.defence_role + ")") if sq.defence_role != "" else ""])
	elif sq.faction == war.player_faction:
		out.append("Commanded by: the player's direct order (or idle)")
	else:
		out.append("Commanded by: nobody - idle")
	var engaged := 0
	var fire := 0
	var react := 0
	var sample := ""
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u == null:
			continue
		if u.ai_state == UnitState.AiState.ENGAGING and u.target_visible:
			engaged += 1
			if sample == "":
				var t := sim.state.get_unit(u.target_id)
				sample = "%s: %s (%s)" % [u.unit_name, t.unit_name if t else "target", u.ai_reason]
		if u.under_fire_until > now:
			fire += 1
		if u.is_reacting():
			react += 1
	out.append("Direct observation: %d engaging a visible enemy, %d under fire, %d taking cover%s" % [engaged, fire, react, "" if sample == "" else " - " + sample])
	out.append_array(sim.tactics.explain(sq))
	var near := intel.contacts_near(sq.faction, squad_center(sq), 600.0)
	if near.is_empty():
		out.append("Faction picture within 600 m: nothing reported")
	else:
		for c: ContactState in near.slice(0, 2):
			out.append("Faction picture: " + c.describe(now))
	return out


## The faction's current picture and its last strategic decision, as lines for the inspector.
func explain_faction(f: FactionState) -> Array[String]:
	var out: Array[String] = []
	var now := sim.state.time
	var ct := intel.counts(f.id)
	out.append("%s (%s): %d contacts - %d observed, %d reported, %d stale" % [WorldState.faction_name(f.id), "player" if f.player else profile(f).display_name.to_lower(), ct.total, ct.observed, ct.reported, ct.stale])
	if f.player:
		out.append("The player commands this faction; no strategic AI decisions.")
	elif f.decisions.is_empty():
		out.append("No decision yet.")
	else:
		var d: Dictionary = f.decisions.back()
		out.append("Decision at %d:%02d - %s" % [int(d.t / 3600.0), int(d.t / 60.0) % 60, d.notes])
		if d.has("forces") and not d.forces.is_empty():
			var fo: Dictionary = d.forces
			out.append("  forces: %d available (%d soldiers, reserve kept %d of %d), %d committed, %d recovering, %d garrison, %d newly recruited, %d squads with soldiers aboard" % [fo.available, fo.soldiers_available, fo.reserve_keep, fo.soldiers_total, fo.committed, fo.recovering, fo.garrison, fo.get("new", 0), fo.get("transported", 0)])
		out.append("  focus: " + str(d.get("focus", "none")))
		for e in d.get("exposed", []):
			out.append("  exposed front: " + e)
		for act: Dictionary in d.get("actions", []):
			out.append("  action %s %s: utility %.2f, need %d%s - %s%s" % [act.kind, act.name, act.utility, act.need, (", " + act.basis) if act.basis != "" else "", act.status, (" (" + act.note + ")") if act.note != "" else ""])
		for t: Dictionary in d.threats:
			out.append("  threat at %s: ~%d enemy reported (%s), %d defenders -> %s" % [t.objective, t.enemies, ", ".join(t.contacts), t.defenders, t.action])
		if d.investigate != "":
			out.append("  investigate: " + d.investigate)
		for i in mini(d.candidates.size(), 4):
			var c: Dictionary = d.candidates[i]
			out.append("  target %s: score %.2f (value %d, %.1f km)%s, %d defenders %s, needs %d%s%s" % [c.name, c.score, c.value, c.km, " retake" if c.retake else "", c.defenders, c.basis, c.need, " - too few free" if c.skipped else "", (" | " + c.get("logi", "")) if c.get("logi", "") != "" else ""])
		if d.attack != "":
			out.append("  attack chosen: " + d.attack)
	for op: OperationState in war.active_operations(f.id):
		var obj := war.objective(op.target_objective)
		out.append("Op #%d %s %s %s - %d squads, %s%s" % [op.id, op.type_name(), obj.obj_name if obj else "point", op.phase_name(), op.squads.size(),
			"player" if op.player_ordered else "AI", (": " + op.reason) if op.reason != "" else ""])
		for line in coord.explain(op):
			out.append("    " + line)
		for line in mech.explain(op):
			out.append("    " + line)
		if not op.readiness.is_empty():
			out.append("    Readiness: %s - %s" % [op.readiness.get("verdict", ""), op.readiness.get("why", "")])
		if op.supply_why != "":
			out.append("    Supply: " + op.supply_why)
	if not f.player or not sim.logistics.bases.bases_of(f.id).is_empty():
		out.append_array(econ.explain(f))
		out.append_array(supply.explain(f))
	var best := intel.contacts_of(f.id)
	best.sort_custom(func(a: ContactState, b: ContactState) -> bool: return a.conf * a.strength > b.conf * b.strength)
	for c: ContactState in best.slice(0, 6):
		out.append("  " + c.describe(now))
	return out


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
		sq.op_role = SquadState.OpRole.NONE
		sq.defence_role = ""
		sim.squads.clear_route(sq)
		if op and not op.transport.is_empty():
			mech.squad_released(op, sq)
		if op:
			var i := op.squads.find(sq.id)
			if i >= 0:
				op.squads.remove_at(i)
				# GAMEPLAY-01G: a squad taken out (a player order, a reassignment) is no loss of the operation: its soldiers
				# leave its strength (before, a released squad counted as casualties and a coordinated attack withdrew).
				op.start_strength = maxi(op.start_strength - strength(sq), 0)
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
		op.squads.append(sq.id)
		op.start_strength += strength(sq)
		sq.op_id = op.id
		if type != OperationState.Type.COUNTER:
			sq.station_objective = -1  # a counterattack keeps its station: the squad goes back to it
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
	if type == OperationState.Type.COUNTER:
		op.transport = {"mode": "foot", "why": "a counterattack is local: no transport"}
		coord.begin_counter(op, obj)
		return op
	# NAV-PERF-01B: the squads' routes are asked for (one RouteService search per start cell, shared by squads standing together);
	# the operation begins - transport plan, the march - when the first one arrives (on_route_ready). A squad that gets no route
	# leaves the operation as before; when none gets one the operation is cancelled ("no route").
	op.starting = true
	op.wait_reason = "planning routes"
	# A reused route can answer at once; the operation begins only after every squad has asked (and been answered).
	_sending_op = op.id
	for sid in op.squads.duplicate():
		if op.is_active() and op.squads.has(sid):
			_send(op, sim.state.get_squad(sid))
	_sending_op = -1
	if op.is_active() and op.starting and not _starting_wait(op):
		if (_start_routes.get(op.id, {}) as Dictionary).is_empty():
			_end(op, OperationState.Phase.CANCELLED, "no route")
		else:
			_begin(op)
	return op


## Asks for the march of one squad for op (the answer comes to on_route_ready). ATTACK stops at a staging point short of the
## objective; the others march into the objective area. Returns false when no route can be asked for.
func _send(op: OperationState, sq: SquadState) -> bool:
	if op.type == OperationState.Type.COUNTER:
		sim.squads.follow_route(sq, PackedVector3Array([op.target_pos]))  # the squad tactics move the reserve, there is no march
		return true
	if routes == null or not routes.ready:
		return false
	sim.squads.request_route(sq, op.target_pos, "op", SquadState.Formation.COLUMN)
	return true


## NAV-PERF-01B: a squad's operation route arrived (r empty: none, `why`). Starts the operation on its first answer, gives the squad
## its march, or records the failure (retried after ROUTE_RETRY_S, the operation fails after ROUTE_BLOCKED_TIMEOUT_S, as before).
func on_route_ready(sq: SquadState, r: PackedVector3Array, why: String) -> void:
	var op := war.operation(sq.op_id)
	if op == null or not op.is_active() or not op.squads.has(sq.id):
		return
	var now := sim.state.time
	if r.size() < 2:
		if op.starting:
			release_squads([sq.id], "no route")
			if op.is_active() and _sending_op != op.id and not _starting_wait(op):
				if (_start_routes.get(op.id, {}) as Dictionary).is_empty():
					_end(op, OperationState.Phase.CANCELLED, "no route (%s)" % why)
				else:
					_begin(op)
			return
		blocked_routes += 1
		_route_retry[sq.id] = now + ROUTE_RETRY_S
		var reason := String(sim.squads.route_block_reason.get(sq.id, ""))
		if reason == "":
			reason = "no route (%s)" % why
		op.wait_reason = "route blocked: " + reason
		if op.blocked_since < 0.0:
			op.blocked_since = now
			log_event(op.faction, "navigation", "Operation %d: %s" % [op.id, op.wait_reason], squad_center(sq))
		return
	r = _shape_route(op, sq, r)
	if op.starting:
		# The operation begins when every squad has its answer, as when they were all planned in start_operation: the transport
		# plan reads the staging point of the last route.
		if not _start_routes.has(op.id):
			_start_routes[op.id] = {}
		_start_routes[op.id][sq.id] = r
		if _sending_op != op.id and not _starting_wait(op):
			_begin(op)
		return
	_route_retry.erase(sq.id)
	op.blocked_since = -1.0
	if op.wait_reason.begins_with("route blocked") or op.wait_reason == "planning routes":
		op.wait_reason = ""
	sim.squads.follow_route(sq, r)


## True while one of op's squads still waits for its route (an operation that is starting).
func _starting_wait(op: OperationState) -> bool:
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq and sim.squads.route_waiting(sq):
			return true
	return false


## The operation begins once every squad has its route (the staging point is known): AI-WAR-LOGISTICS-01 - a long march of an AI
## operation is made by vehicle when transport is free (OpTransport); the squads it does not carry walk their routes now.
func _begin(op: OperationState) -> void:
	op.starting = false
	if op.wait_reason == "planning routes":
		op.wait_reason = ""
	var planned: Dictionary = _start_routes.get(op.id, {})
	_start_routes.erase(op.id)
	var carried: Array = mech.plan(op) if (not op.player_ordered and op.type != OperationState.Type.MOVE) else []
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq == null or carried.has(sid) or not planned.has(sid):
			continue
		sim.squads.follow_route(sq, planned[sid])


## The route of a squad for op, shaped for the operation: ATTACK ends at the staging point (set on the first route), the others at
## a spot inside the objective; the first route is the operation's preview.
func _shape_route(op: OperationState, sq: SquadState, r: PackedVector3Array) -> PackedVector3Array:
	if op.type == OperationState.Type.ATTACK:
		r = _cut_before(r, op.target_pos, staging_m)
		op.staging_pos = r[r.size() - 1]
	else:
		var obj := war.objective(op.target_objective)
		if obj:
			# The end of the march: a spot inside the objective, spread per squad.
			var k := op.squads.find(sq.id)
			r[r.size() - 1] = _slot_in(obj, k if k >= 0 else op.squads.size())
	if op.route_preview.is_empty():
		op.route_preview = r
	return r


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
	# AI-WAR-LOGISTICS-01: while the squads ride (assemble .. disembark) OpTransport owns their movement.
	if not op.transport.is_empty() and op.transport.get("mode", "foot") == "mech":
		mech.update(op)
		if op.is_transport_stage():
			return
	if op.starting and not _starting_wait(op):
		# The answers of a starting operation were lost (a save loaded while its routes were being planned): asked again.
		var got: Dictionary = _start_routes.get(op.id, {})
		var asked := false
		for sid in op.squads:
			if not got.has(sid):
				_send(op, sim.state.get_squad(sid))
				asked = true
		if not asked:
			_begin(op)
		return
	_track_march(op)
	var obj := war.objective(op.target_objective)
	var marching := false
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sim.squads.marching(sq):
			marching = true
		elif op.type != OperationState.Type.COUNTER and op.phase == OperationState.Phase.MOVING and sq.order != SquadState.Order.MOVE and _far_from_goal(op, sq):
			# Lost its route (blocked, a reaction ended it): plan again from where it is. A failed plan is not repeated every
			# second: it waits ROUTE_RETRY_S, says why in the operation (on_route_ready), and ends the operation after
			# ROUTE_BLOCKED_TIMEOUT_S. NAV-PERF-01B: the request is answered later; waiting for it is marching, not a failure.
			if now >= float(_route_retry.get(sq.id, 0.0)):
				stuck_reroutes += 1
				_route_retry[sq.id] = now + ROUTE_RETRY_S
				_send(op, sq)
			marching = true
	if op.blocked_since >= 0.0 and now - op.blocked_since > ROUTE_BLOCKED_TIMEOUT_S:
		_end(op, OperationState.Phase.FAILED, op.wait_reason)
		return
	match op.type:
		OperationState.Type.ATTACK:
			if obj and obj.owner == op.faction:
				_garrison(op, obj)
				_end(op, OperationState.Phase.COMPLETED, "%s captured" % obj.obj_name)
				return
			if op.stage == OperationState.Stage.WITHDRAW:
				coord.update(op, obj)
				return
			var coordinated := not op.roles.is_empty()
			if coordinated:
				var why := coord.should_withdraw(op)
				if why != "":
					coord.withdraw(op, why)
					return
			elif soldiers < op.start_strength * fail_ratio:
				_end(op, OperationState.Phase.FAILED, "too many losses (%d of %d left)" % [soldiers, op.start_strength])
				return
			if op.phase == OperationState.Phase.MOVING and not marching:
				_set_phase(op, OperationState.Phase.ENGAGING)
				if not coord.begin(op, obj):
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
				if coordinated:
					coord.update(op, obj)
				# Squads that finished their assault move but stand outside: go in again.
				for sid in op.squads:
					if coordinated:
						break
					var sq := sim.state.get_squad(sid)
					if not sim.squads.marching(sq) and sq.order != SquadState.Order.MOVE and sq.tactic == SquadState.Tactic.NONE and _flat(squad_center(sq), obj.position) > obj.radius * 0.8:
						sim.squads.follow_route(sq, PackedVector3Array([_slot_in(obj, sid % 5)]), SquadState.Formation.LINE)
		OperationState.Type.DEFEND:
			if obj and obj.owner != op.faction and not obj.contested and obj.capture_faction < 0 and obj.owner >= 0:
				_end(op, OperationState.Phase.FAILED, "%s lost" % obj.obj_name)
				return
			if op.phase == OperationState.Phase.MOVING and not marching:
				_set_phase(op, OperationState.Phase.SECURING)
			elif op.phase == OperationState.Phase.SECURING:
				var threat := obj != null and (obj.contested or intel.threat_near(op.faction, obj.position, obj.radius + 400.0) > 0)
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
		OperationState.Type.COUNTER:
			coord.update_counter(op, obj)
		OperationState.Type.MOVE:
			if not marching:
				for sid in op.squads:
					sim.state.get_squad(sid).op_id = -1
				op.squads.clear()
				var why := "arrived"
				if op.contact_id >= 0:
					# Investigation done: anything seen there since the order updated the contact;
					# otherwise the faction stops believing the old report.
					if intel.get_contact(op.faction, op.contact_id) == null:
						why = "arrived; the contact was already dropped"
					else:
						why = "arrived; nothing found" if intel.clear_contact(op.faction, op.contact_id, op.started_at) else "arrived; the contact was seen again"
				_end(op, OperationState.Phase.COMPLETED, why)


## WORLD-SANDBOX-01B, for the map: how far the operation's slowest squad still has to
## march along its route, and how fast that distance has actually been shrinking
## (smoothed over about a minute). Presentation only, not saved: after a load it is
## measured again.
func _track_march(op: OperationState) -> void:
	var rem := 0.0
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq.route.is_empty() or sq.route_i >= sq.route.size():
			continue
		var c := squad_center(sq)
		var l := _flat(c, sq.route[sq.route_i])
		for i in range(sq.route_i + 1, sq.route.size()):
			l += _flat(sq.route[i - 1], sq.route[i])
		rem = maxf(rem, l)
	var now := sim.state.time
	var m: Dictionary = march.get(op.id, {})
	if m.is_empty():
		march[op.id] = {"rem": rem, "total": rem, "rate": 0.0, "t": now, "since": now}
		return
	var dt: float = now - m.t
	if dt <= 0.0:
		return
	var inst: float = maxf((m.rem - rem) / dt, 0.0)
	m.rate = lerpf(m.rate, inst, clampf(dt / 45.0, 0.0, 1.0))
	m.rem = rem
	m.total = maxf(m.total, rem)
	m.t = now


## Remaining march (m), total, measured rate (m/s) and an arrival estimate in seconds -
## -1 when there is no trustworthy estimate (just started, halted, fighting, or not
## marching any more).
func march_info(op: OperationState) -> Dictionary:
	var m: Dictionary = march.get(op.id, {})
	if m.is_empty():
		return {"rem": -1.0, "total": -1.0, "rate": 0.0, "eta": -1.0}
	var eta := -1.0
	if op.phase == OperationState.Phase.MOVING and m.rem > 0.0 and m.rate >= 0.4 and sim.state.time - m.since >= 20.0:
		eta = m.rem / m.rate
	return {"rem": m.rem, "total": m.total, "rate": m.rate, "eta": eta}


func _far_from_goal(op: OperationState, sq: SquadState) -> bool:
	var goal := op.staging_pos if op.type == OperationState.Type.ATTACK and op.staging_pos.is_finite() else op.target_pos
	return _flat(squad_center(sq), goal) > 120.0


func _set_phase(op: OperationState, p: OperationState.Phase) -> void:
	if op.phase != p:
		op.phase = p
		op.phase_since = sim.state.time


## The operation's squads stay at the objective as its garrison.
func _garrison(op: OperationState, obj: ObjectiveState) -> void:
	var sqs: Array = []
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq:
			sq.op_id = -1
			sq.op_role = SquadState.OpRole.NONE
			sq.station_objective = obj.id
			sim.squads.clear_route(sq)
			sqs.append(sq)
	for other: SquadState in squads_of(op.faction):
		if other.station_objective == obj.id and other.op_id < 0 and not sqs.has(other) and other.tactic_owner != SquadState.Owner.PLAYER and other.order != SquadState.Order.MOVE:
			sqs.append(other)
	# GAMEPLAY-01C: at an objective with a base of the faction the garrison mans the base's fortifications (GARRISON_BASE).
	var bid := base_at_objective(op.faction, obj)
	if bid >= 0:
		for sq: SquadState in sqs:
			if sq.garrison_base != bid:
				sim.tactics.assign_garrison(sq, bid, SquadState.Owner.SQUAD)
		return
	_defence_posture(obj, sqs, op.faction)


# --- Bases as strategic targets (GAMEPLAY-01D) -------------------------------------------------------------------------
# One base is one target: every base has one objective (ConstructionState.bases[].objective). A base standing on an objective
# its faction holds (a headquarters) uses that one; any other base gets its own objective of kind "base" at its anchor, so
# the strategic AI, the map, operations and capture treat it like every other objective (no second ownership: the
# objective's owner is the base's, BaseSim.capture_base follows it). Base objectives give no income (the facilities are the
# base's value) and disappear with the base's last facility.
const BASE_OBJ_MIN_R := 90.0
const BASE_OBJ_MAX_R := 160.0


## Keeps every base linked to its objective (new bases, loaded saves, bases that lost their last facility). Every 5 s and
## after a load; cheap (a few bases).
func sync_bases() -> void:
	var cs := sim.state.construction
	var bs := sim.logistics.bases
	var alive := {}
	for b: Dictionary in cs.bases.values():
		var o := war.objective(int(b.get("objective", -1)))
		if o != null and o.is_base() and o.base_id != int(b.id):
			o = null
		if o == null:
			for x: ObjectiveState in war.all_objectives():
				if not x.is_base() and x.owner == int(b.faction) and _flat(x.position, b.anchor) <= x.radius + 60.0:
					o = x
					break
		if o == null:
			o = _add_base_objective(b)
			log_event(int(b.faction), "base", "%s is a strategic objective now" % b.name, b.anchor)
		b["objective"] = o.id
		if o.is_base():
			alive[o.id] = true
			o.obj_name = String(b.name)
			o.position = _ground(b.anchor)
			o.radius = clampf(float(b.get("radius", 0.0)) if float(b.get("radius", 0.0)) > 0.0 else 100.0, BASE_OBJ_MIN_R, BASE_OBJ_MAX_R)
			# Value: 1 for any base, +1 with stores, +1 with a barracks or a headquarters building (a command post alone is an
			# outpost).
			var stores := false
			var main := false
			for st: StructureState in bs.facilities_of(int(b.id)):
				var k := FacilityDefs.kind_of(st.type_id)
				stores = stores or k in [&"supply", &"storage", &"ammo", &"fuel", &"vehicle"]
				main = main or k == &"barracks" or st.type_id == &"hq_building"
			o.value = 1 + (1 if stores else 0) + (1 if main else 0)
			if o.owner != int(b.faction) and o.capture_faction < 0:
				# Ownership is the objective's; a base that disagrees (a save from before GAMEPLAY-01D) follows it.
				if o.owner >= 0:
					bs.capture_base(int(b.id), o.owner)
				else:
					o.owner = int(b.faction)
	for o: ObjectiveState in war.all_objectives():
		if o.is_base() and not alive.has(o.id):
			for op: OperationState in war.active_operations():
				if op.target_objective == o.id:
					_end(op, OperationState.Phase.CANCELLED, "%s no longer exists" % o.obj_name)
			for sq: SquadState in sim.state.squads.values():
				if sq.station_objective == o.id:
					sq.station_objective = -1
			war.objectives.erase(o.id)
			threatened.erase(o.id)
			log_event(o.owner, "base", "%s no longer exists" % o.obj_name, o.position)


func _add_base_objective(b: Dictionary) -> ObjectiveState:
	var o := ObjectiveState.new()
	var next := 1
	for id in war.objectives:
		next = maxi(next, int(id) + 1)
	o.id = next
	o.kind = &"base"
	o.base_id = int(b.id)
	o.obj_name = String(b.name)
	o.position = _ground(b.anchor)
	o.owner = int(b.faction)
	o.last_change_at = sim.state.time
	o.history.append([snappedf(sim.state.time, 0.1), o.owner])
	war.objectives[o.id] = o
	return o


## The objective a base is linked to (null before sync_bases ran).
func base_objective(base_id: int) -> ObjectiveState:
	var b: Dictionary = sim.state.construction.bases.get(base_id, {})
	return war.objective(int(b.get("objective", -1))) if not b.is_empty() else null


## Warnings about a faction's bases, from what it has been told (IntelSim) and the capture state - never from enemy
## positions it does not know: enemy activity near, a possible attack (enemy close to the base), the base under attack
## (contested or being captured). Each kind once per base until it has been quiet for ALERT_QUIET_S.
const ALERT_QUIET_S := 180.0
var _alerts := {}


func _update_base_alerts(f: FactionState) -> void:
	if not f.player:
		return  # the AI factions' own threat picture is StrategicDecision._collect_defence
	var now := sim.state.time
	for o: ObjectiveState in war.owned_by(f.id):
		if not o.is_base() and o.base_id < 0 and sim.logistics.bases.base_area_at(o.position, f.id) < 0:
			continue
		var key := "%d:%d" % [f.id, o.id]
		var st: Dictionary = _alerts.get(key, {"level": 0, "since": -1e9})
		var level := 0
		var near := intel.threat_near(f.id, o.position, o.radius + 700.0)
		var close := intel.threat_near(f.id, o.position, o.radius + 220.0)
		if near > 0:
			level = 1
		if close > 0:
			level = 2
		if o.contested or (o.capture_faction >= 0 and o.capture_faction != f.id and o.capture_progress > 0.0):
			level = 3
		if level > int(st.level):
			match level:
				1:
					log_event(f.id, "threat", "Enemy activity reported near %s (about %d)" % [o.obj_name, near], o.position)
				2:
					log_event(f.id, "threat", "Possible attack on %s: about %d enemy within %d m" % [o.obj_name, close, roundi(o.radius + 220.0)], o.position)
				3:
					log_event(f.id, "attack", "%s is under attack" % o.obj_name, o.position)
			st = {"level": level, "since": now}
		elif level > 0:
			st.since = now
		elif int(st.level) > 0 and now - float(st.since) > ALERT_QUIET_S:
			st = {"level": 0, "since": now}
		_alerts[key] = st


## GAMEPLAY-01C: the faction's base that stands on objective obj (its anchor within the objective's radius + 60 m, the
## rule by which bases change hands with their objective), or -1.
func base_at_objective(f: int, obj: ObjectiveState) -> int:
	if obj == null:
		return -1
	if obj.is_base():
		var bb: Dictionary = sim.state.construction.bases.get(obj.base_id, {})
		return obj.base_id if not bb.is_empty() and int(bb.faction) == f else -1
	var best := -1
	var best_d := INF
	for b: Dictionary in sim.logistics.bases.bases_of(f):
		var d := _flat(b.anchor, obj.position)
		if d <= obj.radius + 60.0 and d < best_d:
			best_d = d
			best = b.id
	return best


## GAMEPLAY-01C: AI squads stationed at an objective that holds one of their bases and doing nothing else take up the
## garrison of that base (every 5 s; the player's squads are garrisoned only by the player).
func _update_garrisons(f: FactionState) -> void:
	if f.player:
		return
	for sq: SquadState in squads_of(f.id):
		if sq.station_objective < 0 or sq.garrison_base >= 0 or sq.op_id >= 0 or sq.tactic != SquadState.Tactic.NONE or sim.squads.marching(sq):
			continue
		var bid := base_at_objective(f.id, war.objective(sq.station_objective))
		if bid >= 0:
			sim.tactics.assign_garrison(sq, bid, SquadState.Owner.SQUAD)


## AI-COMBAT-STRAT-01: several squads at one objective do not stack in the centre. With a believed threat
## they take sectors in an arc facing it (the faction's own picture, not the real enemy), and from three
## squads the last one is the local reserve behind the objective. Without a known threat the squads spread
## evenly around the objective. Squads that already stand within a sector do not move.
func _defence_posture(obj: ObjectiveState, sqs: Array, faction: int) -> void:
	var n := sqs.size()
	if n < 2:
		return
	var facing := Vector3.INF
	var best := 0.0
	for c: ContactState in intel.contacts_near(faction, obj.position, obj.radius + 500.0):
		var w: float = c.conf * float(maxi(c.strength, 1))
		if w > best:
			best = w
			facing = c.pos
	var base := 0.0
	if facing.is_finite():
		base = atan2(facing.z - obj.position.z, facing.x - obj.position.x)
	var front: int = n - 1 if (n >= 3 and facing.is_finite()) else n
	for i in n:
		var sq: SquadState = sqs[i]
		var ang := base
		var d := obj.radius * 0.55
		if i >= front:
			ang = base + PI  # local reserve behind the objective
			d = obj.radius * 0.3
		elif facing.is_finite():
			ang = base + (float(i) - float(front - 1) * 0.5) * 0.9
		else:
			ang = TAU * float(i) / float(n)
		var p := obj.position + Vector3(cos(ang), 0, sin(ang)) * d
		if not routes.passable(p):
			p = _slot_in(obj, i)
		sim.squads.follow_route(sq, PackedVector3Array([_ground(p)]), SquadState.Formation.LINE)
		sq.defence_role = "reserve" if i >= front else "sector %d" % (i + 1)


## More squads for a running operation (reinforcement): they march to its staging point and the
## coordinator gives them a role. No second operation. Returns false when no squad has a route.
func join_operation(op: OperationState, squad_ids: Array, why := "") -> bool:
	var any := false
	for sid in squad_ids:
		var sq := sim.state.get_squad(sid)
		if sq == null or sq.faction != op.faction or sq.members.is_empty() or sq.op_id == op.id:
			continue
		if sq.op_id >= 0:
			release_squads([sq.id], "reassigned")
		if routes == null or not routes.ready:
			continue
		op.squads.append(sq.id)
		op.start_strength += strength(sq)
		sq.op_id = op.id
		sq.station_objective = -1
		op.roles[sq.id] = SquadState.OpRole.REINFORCE
		sq.op_role = SquadState.OpRole.REINFORCE
		any = true
		# NAV-PERF-01B: the march is asked for after the squad joined (the answer finds it in the operation).
		_send(op, sq)
	if any:
		op.stage_why = "reinforced: " + why
		log_event(op.faction, "reinforce", "%s #%d receives %d more squads" % [op.type_name(), op.id, squad_ids.size()], op.target_pos)
	return any


## Public wrapper for the coordinator (a finished withdrawal ends the operation).
func end_operation(op: OperationState, phase: OperationState.Phase, why: String) -> void:
	_end(op, phase, why)


func _end(op: OperationState, phase: OperationState.Phase, why: String) -> void:
	if not op.is_active():
		return
	_start_routes.erase(op.id)
	op.stage = OperationState.Stage.DONE
	for sid in op.squads:
		var sq0 := sim.state.get_squad(sid)
		if sq0 and sq0.op_id == op.id:
			sq0.op_role = SquadState.OpRole.NONE
			sq0.defence_role = ""
	op.phase = phase
	op.ended_at = sim.state.time
	op.outcome = why
	march.erase(op.id)
	mech.release_op(op, why)
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
	# AI-WAR-LOGISTICS-01: an AI faction with a barracks recruits through it (WarEconomy: supplies, ammunition and
	# personnel are paid); the free arrival below remains for the player's faction and for worlds without bases.
	if not f.player and sim.logistics.bases.facility_of_kind(f.id, &"barracks") != null:
		return
	# GAMEPLAY-01B: in New Game the player's reserves come only through a barracks; the one free help is recovery after
	# the loss of every soldier.
	if f.player and not war.rule("free_reserves", true):
		_update_recovery(f)
		return
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


## GAMEPLAY-01B recovery: when the player has no soldier left and cannot recruit (no barracks, no personnel or not enough
## to pay a squad), a small section (rules recovery_size) arrives after recovery_delay_s at his command post (else where
## his soldiers started). Never while he has a soldier, so it is no source of free squads; it repeats if he is wiped out
## again. The arrival time is saved (FactionState.recovery_at).
func _update_recovery(f: FactionState) -> void:
	var delay := float(war.rule("recovery_delay_s", 0.0))
	var size := int(war.rule("recovery_size", 0))
	if delay <= 0.0 or size <= 0:
		return
	var bs := sim.logistics.bases
	if bs.soldiers_of(f.id) > 0 or bs.queued_recruits(f.id) > 0:
		if f.recovery_at >= 0.0:
			f.recovery_at = -1.0
		return
	var now := sim.state.time
	if f.recovery_at < 0.0:
		var barracks := bs.facility_of_kind(f.id, &"barracks")
		if barracks != null and barracks.is_operational() and f.reserves >= BaseSim.SQUAD_SIZE and bs.faction_can_pay(f.id, BaseSim.RECRUIT_COST):
			return  # the barracks can train a squad: that is the normal way back
		f.recovery_at = now + delay
		log_event(f.id, "threat", "Every soldier is lost. A section of %d is on its way and arrives in %d s" % [size, roundi(delay)], _recovery_point(f))
		return
	if now < f.recovery_at:
		return
	f.recovery_at = -1.0
	f.recoveries += 1
	var at := _recovery_point(f)
	var sq := spawn_squad(f, at, size)
	sq.origin = "recovery"
	log_event(f.id, "reinforcements", "Squad %s (%d soldiers) has arrived to carry on" % [sq.squad_name, size], at)


func _recovery_point(f: FactionState) -> Vector3:
	var bs := sim.logistics.bases
	var mb := bs.main_base(f.id)
	if mb >= 0:
		var a: Vector3 = sim.state.construction.bases[mb].anchor
		return _ground(a + Vector3(12.0, 0.0, 12.0))
	return _ground(f.home) if f.home.is_finite() else _ground(Vector3.ZERO)


## New squad of n soldiers of faction f in a line around p, armed by the squad composition (GAMEPLAY-02B).
func spawn_squad(f: FactionState, p: Vector3, n: int) -> SquadState:
	f.squad_counter += 1
	var tag := "%s%d" % [f.faction_name.left(1), f.squad_counter]
	var ids := spawn_recruits(f, p, n, tag)
	var sq := sim.state.add_squad(tag, f.id, ids)
	sim.combat.apply_composition(sq)
	# AI-SQUAD-01: war squads pick their formation from the terrain and the situation.
	sq.formation_auto = true
	sq.born_at = sim.state.time
	return sq


## n new soldiers (rifles equipped, no squad yet) in a line around p; the caller forms or joins a squad.
func spawn_recruits(f: FactionState, p: Vector3, n: int, tag := "") -> Array:
	var ids := []
	if tag == "":
		tag = "%s+" % f.faction_name.left(1)
	for i in n:
		var q := p + Vector3((i % 4 - 1.5) * 3.0, 0, (i / 4) * 3.0)
		q = _ground(q)
		var u := sim.state.add_unit(UnitState.Kind.SOLDIER, f.id, q + Vector3.UP * 0.3, 0.0, "%s-%d" % [tag, i + 1])
		ids.append(u.id)
	sim.combat.equip_all(&"rifle")
	if sim.detail:
		sim.detail.create_missing_proxies()
	return ids


func _on_unit_died(u: UnitState) -> void:
	if not enabled or u.kind == UnitState.Kind.VEHICLE:
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

## One strategic decision of an AI faction (the scoring lives in StrategicDecision).
func _decide(f: FactionState) -> void:
	strat.decide(f)


## An AI faction checks the most credible unconfirmed report near its own ground with one
## squad (a MOVE operation to the reported position). At most one investigation per faction at
## a time, and none for a contact already looked at recently or one being fought.
func _investigate(f: FactionState, p: FactionProfile, free: Array, notes: Array[String], snap: Dictionary) -> void:
	for op: OperationState in war.active_operations(f.id):
		if op.contact_id >= 0:
			return
	var now := sim.state.time
	var best: ContactState = null
	for c: ContactState in intel.contacts_of(f.id):
		if c.status == ContactState.Status.OBSERVED or c.investigated_until > now or c.conf < 0.2:
			continue
		var near := false
		for o: ObjectiveState in war.owned_by(f.id):
			if _flat(o.position, c.pos) <= o.radius + p.threat_radius * 1.5 and _incoming_squads(f.id, o.id) == 0:
				near = true
				break
		if near and (best == null or c.conf * c.strength > best.conf * best.strength):
			best = c
	if best == null:
		return
	var pool := free.filter(func(sid: int) -> bool: return _flat(squad_center(sim.state.get_squad(sid)), best.pos) <= 2500.0)
	if pool.is_empty():
		snap.investigate = "contact #%d: no free squad within 2.5 km" % best.id
		return
	var picked := _pick_near(pool, best.pos, 1, true)
	var op := start_operation(f.id, OperationState.Type.MOVE, picked, -1, best.pos)
	if op == null:
		return
	best.investigated_until = now + investigate_cooldown_s
	op.contact_id = best.id
	op.reason = "investigate contact #%d (%s, %d%% confidence, %d s old)" % [best.id, best.source_name(), roundi(best.conf * 100.0), roundi(now - best.t_seen)]
	snap.investigate = op.reason
	notes.append("investigate #%d" % best.id)
	for s in picked:
		free.erase(s)


## Moves up to two free squads that stand at the HQ to the held objective nearest any
## objective the faction does not hold (its front), while fewer than forward_squads are
## stationed or on their way there. Returns a note for last_decision.
func _forward(f: FactionState, p: FactionProfile, free: Array) -> String:
	var hq := war.objective(f.hq_objective)
	if p.forward_squads <= 0 or hq == null or hq.owner != f.id:
		return ""
	var front: ObjectiveState = null
	var best := INF
	for o: ObjectiveState in war.owned_by(f.id):
		if o.is_hq():
			continue
		for t: ObjectiveState in war.all_objectives():
			if t.owner != f.id:
				var d := _flat(o.position, t.position)
				if d < best:
					best = d
					front = o
	if front == null or _flat(front.position, hq.position) < 1500.0:
		return ""
	var there := _garrison_count(f.id, front.id) + _incoming_squads(f.id, front.id)
	var send := []
	for sid in free:
		if there + send.size() >= p.forward_squads or send.size() >= 2:
			break
		var sq := sim.state.get_squad(sid)
		if sq and _flat(squad_center(sq), hq.position) <= hq.radius * 2.0:
			send.append(sid)
	if send.is_empty():
		return ""
	start_operation(f.id, OperationState.Type.REINFORCE, send, front.id)
	for s in send:
		free.erase(s)
	return "%d squads forward to %s" % [send.size(), front.obj_name]


## Squads serving no operation, minus what the HQ and the garrisons must keep.
func _free_squads(f: FactionState, p: FactionProfile) -> Array:
	var free := []
	var keep := {}
	for o: ObjectiveState in war.owned_by(f.id):
		keep[o.id] = p.hq_squads if o.is_hq() else (p.garrison_squads if o.value >= p.garrison_min_value else 0)
	var sqs := squads_of(f.id)
	sqs.sort_custom(func(a: SquadState, b: SquadState) -> bool: return a.members.size() < b.members.size())
	for sq: SquadState in sqs:
		if sq.op_id >= 0 or sq.members.size() < p.min_squad_size or strat.is_recovering(sq, p):
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
		"ai_us_max": ai_usec_max, "intel": intel.stats(), "routes": {"planned": routes.routes_planned if routes else 0, "ms_max": snappedf(routes.route_ms_max, 0.01) if routes else 0.0,
		"ms_avg": snappedf(routes.route_ms_total / maxi(routes.routes_planned, 1), 0.01) if routes else 0.0}, "reroutes": stuck_reroutes,
		"econ": econ.summary(), "mech": mech.summary(), "supply": supply.summary(), "builds": bases.stats.duplicate()}
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

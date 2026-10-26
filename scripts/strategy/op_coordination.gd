## Multi-squad coordination of an attack operation (AI-COMBAT-STRAT-01).
##
## Not a planner: the operation (OperationState) already owns its squads; this gives them
## complementary temporary roles (SquadState.OpRole) and moves the operation through stages from what
## the squads actually do, then hands every squad its role as an ordinary squad tactic
## (SquadTactics.assign_for_operation: owner OPERATION, ending with the operation):
##
##   fire support  SUPPRESS from posts with a line to the objective, ~190 m out - engages what it
##                 sees and fires at the reported position of what it does not;
##   assault       holds in cover at the staging point, then ASSAULT with external support (it does
##                 not stop to set up its own, the support is already firing) towards its own spot in
##                 the objective;
##   maneuver      FLANK with external support along a covered route when the ground justifies it
##                 (SquadTactics._plan decides: exposure, detour), else a second assault squad;
##   reserve       holds back, takes over a depleted role or occupies when the objective falls.
##
## Why the first version failed (AI-SQUAD-01 offensive test, 24 v 8): all three squads walked to the same
## point as a mass, bounding half-speed under fire for 120 s; nobody suppressed the defenders until
## 130 m, nobody had another role. Here the support fires first, the assault closes only once it is set
## (or after a timeout), and a depleted or unreachable support squad is replaced or skipped.
##
## GAMEPLAY-02A (measured with CombatDiag, 3 seeds of the Haugen attack): the support never saw a defender and fired ~1500
## rounds blind at the objective's centre from the deployment on (defenders' mean suppression 0.02), so it was out of
## ammunition when the assault reached the defenders' range; the two assault squads left the staging point 330 m out together,
## on one line, bounding half-speed through open ground; depleted squads were sent back in one by one. Now: the support
## observes and fires at what it sees or was just told about, and covers with fire only while the assault crosses the last
## few hundred metres (OperationState.cover_fire); assault squads first move up to their own assault positions, spread
## sideways, and start one after the other; a squad at half strength or less becomes fire support instead of walking in
## again; an assault without progress for progress_stall_s commits everything once, then withdraws.
##
## Every stage has a success condition, a timeout and a fallback; the operation withdraws (all squads
## break contact to a fallback point, the support covering last) when its effectiveness is too low,
## instead of being marked FAILED while the survivors stand in the killing ground. Player-controlled
## squads are released by the existing rule (WarSim.release_squads) and simply drop out of the roles.
class_name OpCoordination
extends RefCounted

var deploy_timeout_s := 55.0
var support_timeout_s := 40.0
var assault_stall_s := 260.0
## No squad attacking for this long: promote the support or break off.
var idle_assault_s := 45.0
var idle_assault_max_s := 120.0
var support_standoff_m := 190.0
## An operation whose weighted effectiveness falls below this withdraws (the profile may override).
var withdraw_eff := 0.32
## Squads with fewer soldiers than this do not take part (they are recovering).
var min_squad_n := 2
## The assault goes in once the support is set or this long after deployment, whichever first.
var assault_hold_s := 35.0
## GAMEPLAY-02A: assault positions this far from the objective (m), squads this far apart sideways; assault squads start this
## many seconds after each other; the support covers with fire while the nearest assault squad is between these distances.
var assault_line_m := 250.0
var assault_spread_m := 50.0
var assault_stagger_s := 6.0
var cover_fire_far_m := 290.0
var cover_fire_near_m := 35.0
## No assault squad got 10 m closer for this long: commit everything once, then withdraw.
var progress_stall_s := 75.0
## GAMEPLAY-03C: no squad of the operation is actually attacking (all idle, depleted or out of ammunition): the same decision
## after this long instead (the Haugen trace sat 70 s with nobody moving before the 75 s rule fired).
var idle_commit_s := 40.0
## AI-ASSAULT-01: the assault squads close on the objective together. Inside sync_m (the defenders' effective rifle range) no
## squad's next bound may end more than line_lead_m ahead of the rearmost squad still attacking (a phase line, recomputed every
## second from the squads' positions); a squad that holds there longer than line_wait_max_s goes on, and one that has not got
## line_stuck_m closer for line_stuck_s does not hold the others back. Measured before: N8 reached the defenders at 128 s, N7 at
## 176 s, N6 at 197 s - eight defenders beat 24 attackers one squad at a time.
var sync_m := 170.0
var line_lead_m := 30.0
var line_wait_max_s := 40.0
var line_stuck_s := 35.0
var line_stuck_m := 10.0
var line_holds := 0
## AI-ASSAULT-01: a fire support squad that has seen nothing and taken no fire for support_blind_s while the assault runs moves up
## to support_move_f of its distance (not closer than support_near_m), at most support_moves times - Haugen: the 8-man support
## stood unseeing at 181 m for over 100 s while the assault squads were shot up 100 m ahead of it.
var support_blind_s := 30.0
var support_move_f := 0.65
var support_near_m := 100.0
var support_moves := 2
var support_displaced := 0
var _blind_since := {}
var _moves := {}

var ws: WarSim
var sim: WorldSim
## Measurements.
var stage_changes := 0
var role_changes := 0
var withdrawals := 0
var timeouts := 0
var usec := 0
var usec_max := 0
var updates := 0
var _cool := {}
var _tries := {}
## op id -> since when no squad of the operation has seen an enemy.
var _clear_since := {}
var _idle_since := {}
## Derived each second (never saved): op id -> {squad id: distance} of the squads that set the phase line; squad id -> [best
## distance, at]; squad id -> since when it holds at the line.
var _line := {}
var _line_best := {}
var _held_since := {}


func _init(p_ws: WarSim) -> void:
	ws = p_ws
	sim = p_ws.sim


# --- Entry points (WarSim) ----------------------------------------------------------------------

## An ATTACK reached its staging point: roles are handed out and the deployment starts.
func begin(op: OperationState, obj: ObjectiveState) -> bool:
	if not (sim.tactics.enabled and sim.tactics.ops_assault):
		return false
	_set_stage(op, OperationState.Stage.DEPLOY, "arrived at the staging point, %d squads" % op.squads.size())
	op.assault_pos = obj.position
	_assign_roles(op, obj)
	_issue_roles(op, obj)
	return true


## Once a second while the attack is engaging.
func update(op: OperationState, obj: ObjectiveState) -> void:
	var t0 := Time.get_ticks_usec()
	updates += 1
	var now := sim.state.time
	_prune(op)
	var sqs := _squads(op)
	if sqs.is_empty() or op.stage == OperationState.Stage.APPROACH:
		return
	# The objective is being taken (WarSim: SECURING): everybody walks in, the fighting tactics end.
	if op.phase == OperationState.Phase.SECURING and op.stage != OperationState.Stage.SECURE and op.stage != OperationState.Stage.WITHDRAW:
		_secure(op, obj, sqs)
		return
	var a := _op_status(op, sqs, obj)
	match op.stage:
		OperationState.Stage.DEPLOY:
			_update_deploy(op, obj, sqs, a, now)
		OperationState.Stage.SUPPORT:
			_update_support(op, obj, sqs, a, now)
		OperationState.Stage.ASSAULT:
			_update_assault(op, obj, sqs, a, now)
		OperationState.Stage.SECURE:
			pass
		OperationState.Stage.WITHDRAW:
			_update_withdraw(op, obj, sqs, now)
	var dt := Time.get_ticks_usec() - t0
	usec += dt
	usec_max = maxi(usec_max, dt)


## Should the operation break off? (called by WarSim instead of the plain loss ratio)
func should_withdraw(op: OperationState) -> String:
	if op.stage == OperationState.Stage.WITHDRAW or op.stage == OperationState.Stage.APPROACH:
		return ""
	var sqs := _squads(op)
	if sqs.is_empty():
		return ""
	var obj := ws.war.objective(op.target_objective)
	var a := _op_status(op, sqs, obj)
	if a.soldiers < op.start_strength * ws.fail_ratio:
		return "only %d of %d soldiers left" % [a.soldiers, op.start_strength]
	# A force that sees no enemy any more (for a while), or that is taking the objective, is not beaten:
	# its low effectiveness is the price of the fight, not a reason to leave.
	var now := sim.state.time
	if a.seen == 0:
		if not _clear_since.has(op.id):
			_clear_since[op.id] = now
	else:
		_clear_since.erase(op.id)
	if _clear_since.has(op.id) and now - float(_clear_since[op.id]) > 25.0:
		return ""
	if obj != null and obj.contested and obj.capture_faction == op.faction:
		return ""
	# Clearly superior in numbers to what it sees: keep going - leaving now would hand the defender the fight.
	if float(a.soldiers) >= 3.0 * float(a.seen):  # also covers "nothing seen at the moment"
		return ""
	var thr := ws.profile(ws.war.faction(op.faction)).withdraw_eff if ws.war.faction(op.faction) else withdraw_eff
	if a.eff < thr and sim.state.time - op.stage_since > 10.0 and op.stage >= OperationState.Stage.SUPPORT:
		return "combat effectiveness %.2f (strength %.2f, suppression %.2f, ammunition %.0f%%, %d of ours against %d seen)" % [a.eff, a.strength, a.supp, a.ammo * 100.0, a.soldiers, a.seen]
	if a.ammo < 0.18 and op.stage >= OperationState.Stage.ASSAULT:
		return "ammunition down to %.0f%%" % (a.ammo * 100.0)
	return ""


## Breaks the attack off: assault elements go first, the support covers and follows.
func withdraw(op: OperationState, why: String) -> void:
	if op.stage == OperationState.Stage.WITHDRAW:
		return
	withdrawals += 1
	op.withdraw_why = why
	op.cover_fire = false
	var sqs := _squads(op)
	var lead: SquadState = sqs[0] if not sqs.is_empty() else null
	var fb := Vector3.INF
	if lead:
		fb = sim.tactics._fallback_point(lead, sim.tactics._assess_squad(lead))
	if not fb.is_finite():
		fb = op.staging_pos if op.staging_pos.is_finite() else Vector3.INF
	op.fallback_pos = fb
	_set_stage(op, OperationState.Stage.WITHDRAW, "withdrawing: " + why)
	op.wait_reason = ""
	ws.log_event(op.faction, "withdraw", "%s #%d breaks off the attack: %s" % [op.type_name(), op.id, why], op.target_pos)
	var k := 0
	for sq: SquadState in sqs:
		var role: int = int(op.roles.get(sq.id, SquadState.OpRole.NONE))
		if role == SquadState.OpRole.SUPPORT:
			continue  # covers first, leaves in _update_withdraw
		_withdraw_squad(op, sq, k)
		k += 1


# --- Roles -------------------------------------------------------------------------------------------

## Distributes the roles over the available squads (see the file header). Deterministic: squads are ranked
## by effectiveness x ammunition, the best-equipped fires, the next is the maneuver element when the force
## is large enough, the weakest of a large force is the reserve.
func _assign_roles(op: OperationState, obj: ObjectiveState) -> void:
	var sqs := _squads(op)
	op.roles.clear()
	if sqs.is_empty():
		return
	var ranked: Array = sqs.duplicate()
	ranked.sort_custom(func(x: SquadState, y: SquadState) -> bool: return _fitness(x) > _fitness(y))
	var n := ranked.size()
	if n == 1:
		op.roles[ranked[0].id] = SquadState.OpRole.ASSAULT
	else:
		# Fire support: the best-equipped third (at least one).
		var support_n := maxi(1, int(round(n / 3.0)))
		for i in support_n:
			op.roles[ranked[i].id] = SquadState.OpRole.SUPPORT
		var rest := n - support_n
		var idx := support_n
		# Maneuver: one squad when at least three squads can maneuver / assault (flank decided on issue).
		if n >= 3 and rest >= 2:
			op.roles[ranked[idx].id] = SquadState.OpRole.MANEUVER
			idx += 1
		# Reserve: the weakest squad of a force of five or more.
		var reserve_id := -1
		if n >= 5:
			reserve_id = ranked[n - 1].id
		for i in range(idx, n):
			op.roles[ranked[i].id] = SquadState.OpRole.RESERVE if ranked[i].id == reserve_id else SquadState.OpRole.ASSAULT
	for sq: SquadState in sqs:
		sq.op_role = int(op.roles.get(sq.id, SquadState.OpRole.NONE))
	op.stage_why = "roles: " + _roles_text(op)
	role_changes += 1


func _fitness(sq: SquadState) -> float:
	var a := sim.tactics.assessment(sq)
	if a.is_empty():
		a = sim.tactics._assess_squad(sq)
	return float(a.get("eff", 0.0)) * (0.5 + 0.5 * float(a.get("ammo", 1.0))) + sq.members.size() * 0.001


func _roles_text(op: OperationState) -> String:
	var parts: Array[String] = []
	for sid in op.roles:
		var sq := sim.state.get_squad(sid)
		parts.append("%s %s" % [sq.squad_name if sq else "#%d" % sid, SquadState.OP_ROLE_NAMES[int(op.roles[sid])]])
	return ", ".join(parts)


## Hands every squad its role as a squad tactic (operation-owned).
func _issue_roles(op: OperationState, obj: ObjectiveState) -> void:
	var k := 0
	for sq: SquadState in _squads(op):
		var role: int = int(op.roles.get(sq.id, SquadState.OpRole.NONE))
		sq.op_role = role
		match role:
			SquadState.OpRole.SUPPORT:
				# Several stand-off distances are tried before the role is given up (terrain and woods decide
				# where a rifle can see the objective from).
				# The objective's centre may be inside a building or behind trees: the points around it (where its
				# defenders would stand) are tried as fire targets too.
				var res := {"ok": false, "reason": ""}
				var targets: Array[Vector3] = [_fire_target(op, obj)]
				for i in 4:
					targets.append(_slot(obj, i))
				for tgt: Vector3 in targets:
					for standoff: float in [support_standoff_m, support_standoff_m * 0.75, support_standoff_m * 1.25, support_standoff_m * 0.55]:
						res = sim.tactics.assign_for_operation(sq, SquadState.Tactic.SUPPRESS, tgt, "operation #%d: fire support for the attack on %s (from %.0f m)" % [op.id, obj.obj_name, standoff], {"standoff": standoff})
						if res.ok:
							break
					if res.ok:
						break
				if not res.ok:
					# No firing position with a line to the objective: it assaults instead (fallback).
					op.stage_why += "; %s has no firing position (%s), assaults instead" % [sq.squad_name, res.reason]
					op.roles[sq.id] = SquadState.OpRole.ASSAULT
					sq.op_role = SquadState.OpRole.ASSAULT
					role_changes += 1
					_hold(op, sq)
			SquadState.OpRole.MANEUVER:
				var fr := sim.tactics.assign_for_operation(sq, SquadState.Tactic.FLANK, _slot(obj, k), "operation #%d: flank the defenders of %s" % [op.id, obj.obj_name], {"ext": true})
				if not fr.ok:
					op.stage_why += "; %s cannot flank (%s), assaults straight" % [sq.squad_name, fr.reason]
					op.roles[sq.id] = SquadState.OpRole.ASSAULT
					sq.op_role = SquadState.OpRole.ASSAULT
					role_changes += 1
					_move_up(op, obj, sq)
			SquadState.OpRole.ASSAULT:
				_move_up(op, obj, sq)
			_:
				_hold(op, sq)
		k += 1


## GAMEPLAY-02A: an assault squad moves up by bounds to its own assault position (assault_line_m out, spread sideways from the
## other assault squads) and waits there in cover; one that is already that close holds where it is.
func _move_up(op: OperationState, obj: ObjectiveState, sq: SquadState) -> void:
	var p := _assault_position(op, obj, sq)
	if not p.is_finite() or _flat(sim.squads._centroid(sq), p) < 40.0 or _flat(sim.squads._centroid(sq), obj.position) < assault_line_m:
		_hold(op, sq)
		return
	var res := sim.tactics.assign_for_operation(sq, SquadState.Tactic.BOUND, p, "operation #%d: move up to the assault position %.0f m from %s" % [op.id, _flat(p, obj.position), obj.obj_name])
	if not res.ok:
		_hold(op, sq)


## Where the i-th assault squad waits: on the line from the objective towards the force, assault_line_m out, the squads
## assault_spread_m apart sideways (centred on the line), snapped to walkable ground.
func _assault_position(op: OperationState, obj: ObjectiveState, sq: SquadState) -> Vector3:
	var assault := _of_role(op, SquadState.OpRole.ASSAULT)
	var i := maxi(assault.find(sq), 0)
	var from := op.staging_pos if op.staging_pos.is_finite() else sim.squads._centroid(sq)
	var dir := Vector3(from.x - obj.position.x, 0.0, from.z - obj.position.z).normalized()
	if dir.length() < 0.1:
		return Vector3.INF
	var side := Vector3(-dir.z, 0.0, dir.x)
	var off := float(i) - float(assault.size() - 1) * 0.5
	return sim.tactics.pos.nearest_valid(obj.position + dir * assault_line_m + side * off * assault_spread_m, 30.0)


## A squad waiting for its turn: takes cover where it stands.
func _hold(op: OperationState, sq: SquadState) -> void:
	sim.tactics.assign_for_operation(sq, SquadState.Tactic.DEFEND, Vector3.INF, "operation #%d: waiting for the support to be set" % op.id)


func _fire_target(op: OperationState, obj: ObjectiveState) -> Vector3:
	# The best reported contact on the objective, else the objective's centre (the squad's belief of where
	# its defenders are: never the true position of a hidden soldier).
	for c: ContactState in ws.intel.contacts_near(op.faction, obj.position, obj.radius + 60.0):
		if c.status != ContactState.Status.LOST and c.conf >= 0.25:
			return c.pos
	return obj.position


func _slot(obj: ObjectiveState, k: int) -> Vector3:
	return ws._slot_in(obj, k)


# --- Phase line (AI-ASSAULT-01) -------------------------------------------------------------------------------

## The squads that set the phase line and their distances from the objective: assault and maneuver squads still attacking.
## Squads waiting for their staggered start count (they are about to come); a depleted squad or one that has stopped gaining
## ground does not hold the others back.
func _line_squads(op: OperationState, obj: ObjectiveState, sqs: Array, now: float) -> Dictionary:
	var out := {}
	for sq: SquadState in sqs:
		var role: int = int(op.roles.get(sq.id, SquadState.OpRole.NONE))
		if role != SquadState.OpRole.ASSAULT and role != SquadState.OpRole.MANEUVER:
			continue
		if _depleted(sq) or (not op.assault_at.has(sq.id) and sq.tactic != SquadState.Tactic.ASSAULT and sq.tactic != SquadState.Tactic.FLANK):
			continue
		var d := _flat(sim.squads._centroid(sq), obj.position)
		var b: Array = _line_best.get(sq.id, [INF, now])
		if d < float(b[0]) - line_stuck_m:
			b = [d, now]
			_line_best[sq.id] = b
		if not op.assault_at.has(sq.id) and now - float(b[1]) > line_stuck_s:
			continue
		out[sq.id] = d
	return out


## Called by SquadTactics before an assault squad's next bound of `step_m`: how far it may go (step_m, or less to end at the phase
## line), 0 when it waits there (`why` in the second element).
func line_step(sq: SquadState, step_m: float) -> Array:
	var op := ws.war.operation(sq.op_id) if sq.op_id >= 0 else null
	if op == null or op.stage != OperationState.Stage.ASSAULT or op.phase == OperationState.Phase.SECURING:
		_held_since.erase(sq.id)
		return [step_m, ""]
	var obj := ws.war.objective(op.target_objective)
	# The line: the rearmost of the *other* squads plus line_lead_m (the rearmost squad itself never waits).
	var line := -1.0
	var ds: Dictionary = _line.get(op.id, {})
	for sid in ds:
		if sid != sq.id:
			line = maxf(line, float(ds[sid]) - line_lead_m)
	if obj == null or line < 0.0:
		_held_since.erase(sq.id)
		return [step_m, ""]
	var d := _flat(sim.squads._centroid(sq), obj.position)
	var next := d - step_m
	if next >= line or next >= sync_m or d < 50.0:
		_held_since.erase(sq.id)
		return [step_m, ""]
	# Behind the line: it closes up to it.
	if d - line >= 12.0:
		_held_since.erase(sq.id)
		return [d - line, ""]
	var now := sim.state.time
	var since := float(_held_since.get(sq.id, now))
	_held_since[sq.id] = since
	if now - since > line_wait_max_s:
		return [step_m, ""]  # waited long enough: goes on (the entry stays until it is no longer at the line)
	if now == since:
		line_holds += 1
	return [0.0, "holds at the phase line %.0f m from %s for the other assault squads (%.0f s)" % [line + line_lead_m, obj.obj_name, now - since]]


## AI-ASSAULT-01: see support_blind_s. Reads only the squad's own assessment (what it sees, whether it is fired on).
func _displace_support(op: OperationState, obj: ObjectiveState, sq: SquadState, now: float) -> void:
	var a := sim.tactics.assessment(sq)
	if a.is_empty() or int(a.get("seen_n", 0)) > 0 or int(a.get("under_fire", 0)) > 0 or sq.tactic_phase < SquadTactics.PH_HOLD:
		_blind_since.erase(sq.id)
		return
	if not _blind_since.has(sq.id):
		_blind_since[sq.id] = now
		return
	var moves := int(_moves.get(sq.id, 0))
	if now - float(_blind_since[sq.id]) < support_blind_s or moves >= support_moves:
		return
	var d := _flat(sim.squads._centroid(sq), obj.position)
	var nd := maxf(d * support_move_f, support_near_m)
	if d - nd < 30.0:
		return
	_blind_since.erase(sq.id)
	_moves[sq.id] = moves + 1
	var res := sim.tactics.assign_for_operation(sq, SquadState.Tactic.SUPPRESS, _fire_target(op, obj), "operation #%d: fire support moves up to %.0f m (nothing seen from %.0f m for %d s)" % [op.id, nd, d, int(support_blind_s)], {"standoff": nd})
	if res.ok:
		support_displaced += 1
		op.stage_why = "%s moves up to %.0f m: it saw nothing from %.0f m" % [sq.squad_name, nd, d]


# --- Stages ----------------------------------------------------------------------------------------------

func _update_deploy(op: OperationState, obj: ObjectiveState, sqs: Array, a: Dictionary, now: float) -> void:
	var support := _of_role(op, SquadState.OpRole.SUPPORT)
	var ready := support.is_empty() or _support_set(support)
	var waited := now - op.stage_since
	op.wait_reason = "" if ready else "fire support is moving into position (%d s)" % int(waited)
	if ready:
		_set_stage(op, OperationState.Stage.SUPPORT, "fire support set (%s)" % _support_text(support))
	elif waited > deploy_timeout_s:
		timeouts += 1
		_set_stage(op, OperationState.Stage.SUPPORT, "support not set after %d s: going on without waiting" % int(waited))


func _update_support(op: OperationState, obj: ObjectiveState, sqs: Array, a: Dictionary, now: float) -> void:
	var held := now - op.stage_since
	# The maneuver element is on its way (it started in the deployment); the assault goes in once the
	# support has been firing for assault_hold_s, or at once when there is nothing to wait for.
	var man := _of_role(op, SquadState.OpRole.MANEUVER)
	var man_ready := true
	for sq: SquadState in man:
		if sq.tactic == SquadState.Tactic.FLANK and sq.tactic_phase < SquadTactics.PH_MOVE and held < support_timeout_s:
			man_ready = false
		# GAMEPLAY-02A: the assault waits until the flanking squad is about as close as the assault squads (an assault that
		# went in while the flank was still 250 m out met the defenders alone).
		if sq.tactic == SquadState.Tactic.FLANK and _flat(sim.squads._centroid(sq), obj.position) > assault_line_m * 0.85 and held < assault_hold_s + 40.0:
			man_ready = false
	# GAMEPLAY-02A: the assault squads are at their assault positions (or gave up moving there).
	var moving := 0
	for sq: SquadState in _of_role(op, SquadState.OpRole.ASSAULT):
		if sq.tactic == SquadState.Tactic.BOUND:
			moving += 1
	var in_place := moving == 0
	var go := (held >= 8.0 and in_place and man_ready) or held >= assault_hold_s + 30.0 \
			or (held >= 8.0 and man_ready and in_place and _of_role(op, SquadState.OpRole.SUPPORT).is_empty())
	op.wait_reason = "" if go else "support in overwatch for %d s; %s; maneuver %s" % [int(held), "assault squads in position" if in_place else "%d assault squad(s) moving up" % moving,
		"in position" if man_ready else "moving"]
	if go:
		_set_stage(op, OperationState.Stage.ASSAULT, "support in overwatch for %d s, assault squads %s: the assault goes in, one squad after the other" % [int(held),
			"in position" if in_place else "still moving up"])
		op.progress_best = INF
		op.progress_t = now
		# The squad nearest the objective goes first, the others follow at assault_stagger_s intervals.
		var order: Array = _of_role(op, SquadState.OpRole.ASSAULT)
		order.sort_custom(func(x: SquadState, y: SquadState) -> bool: return _flat(sim.squads._centroid(x), obj.position) < _flat(sim.squads._centroid(y), obj.position))
		var k := 0
		for sq: SquadState in order:
			if k == 0:
				_send_assault(op, sq, obj, k)
			else:
				op.assault_at[sq.id] = now + assault_stagger_s * k
			k += 1


func _update_assault(op: OperationState, obj: ObjectiveState, sqs: Array, a: Dictionary, now: float) -> void:
	var obj_pos := obj.position
	var closest := INF
	var closest_fit := INF
	for sq: SquadState in sqs:
		var role: int = int(op.roles.get(sq.id, SquadState.OpRole.NONE))
		if (role == SquadState.OpRole.ASSAULT or role == SquadState.OpRole.MANEUVER) and not op.assault_at.has(sq.id):
			closest = minf(closest, _flat(sim.squads._centroid(sq), obj_pos))
			if not _depleted(sq):
				closest_fit = minf(closest_fit, _flat(sim.squads._centroid(sq), obj_pos))
	# GAMEPLAY-02A: the support covers with fire while the assault crosses the ground the defenders can reach.
	op.cover_fire = closest <= cover_fire_far_m and closest >= cover_fire_near_m
	_line[op.id] = _line_squads(op, obj, sqs, now)
	if now < op.reassess_at:
		return
	op.reassess_at = now + 4.0
	if closest < op.progress_best - 10.0:
		op.progress_best = closest
		op.progress_t = now
	var k := 0
	for sq: SquadState in sqs:
		var role: int = int(op.roles.get(sq.id, SquadState.OpRole.NONE))
		match role:
			SquadState.OpRole.ASSAULT, SquadState.OpRole.MANEUVER:
				if op.assault_at.has(sq.id):
					# A staggered start: this squad goes once its time has come (the one before it is on its way).
					if now >= float(op.assault_at[sq.id]):
						op.assault_at.erase(sq.id)
						_send_assault(op, sq, obj, k)
						op.stage_why = "%s starts its assault (%.0f s after the first squad)" % [sq.squad_name, assault_stagger_s * k]
				# An assaulting squad whose tactic ended (done, failed, cancelled) is tasked again after a pause.
				elif sq.tactic == SquadState.Tactic.NONE and now >= float(_cool.get(sq.id, 0.0)) and obj.owner != op.faction:
					_cool[sq.id] = now + 10.0
					var f := _fitness(sq)
					# AI-ASSAULT-01: a squad that is not depleted but unfit (ammunition, suppression) is handled the same way - it
					# used to fall through both branches and stood idle for 90 s as an "assault" squad.
					if (_depleted(sq) or f < 0.3) and _flat(sim.squads._centroid(sq), obj_pos) > 60.0:
						# GAMEPLAY-02A: half the squad is gone - it does not walk in again on its own; it supports from where it is.
						if _to_support(op, obj, sq):
							op.stage_why = "%s (%d of %d left) supports the others from %.0f m instead of assaulting again" % [sq.squad_name, sq.members.size(),
								sq.members.size() + sq.fallen.size(), _flat(sim.squads._centroid(sq), obj_pos)]
						else:
							# GAMEPLAY-03C: no firing position (or ammunition) for it - it holds in cover as a reserve instead of
							# standing idle as an "assault" squad the operation keeps waiting for.
							op.roles[sq.id] = SquadState.OpRole.RESERVE
							sq.op_role = SquadState.OpRole.RESERVE
							role_changes += 1
							_hold(op, sq)
							op.stage_why = "%s (%d of %d left, no firing position) holds in cover as the reserve" % [sq.squad_name, sq.members.size(), sq.members.size() + sq.fallen.size()]
					elif f >= 0.3:
						# GAMEPLAY-03C: another try goes for another spot of the objective (not across the same ground again).
						var tries := int(_tries.get(sq.id, 0)) + 1
						_tries[sq.id] = tries
						_send_assault(op, sq, obj, k + 2 * tries)
						op.stage_why = "%s re-tasked to assault (its tactic ended), attempt %d from another side" % [sq.squad_name, tries + 1]
			SquadState.OpRole.SUPPORT:
				if closest_fit < cover_fire_near_m:
					# An assault squad that can still fight is on the objective: the support stops firing at it and moves in to
					# secure (GAMEPLAY-02A: only when it is on the objective, and not for a shattered squad - lifting the fire at 70 m let
					# the defenders shoot the last 50 m of the assault unhindered).
					if sq.tactic == SquadState.Tactic.SUPPRESS or sq.tactic == SquadState.Tactic.NONE:
						_send_assault(op, sq, obj, k + 3)
						op.stage_why = "assault on the objective: %s lifts fire and moves in" % sq.squad_name
				elif sq.tactic == SquadState.Tactic.SUPPRESS:
					_displace_support(op, obj, sq, now)
				elif sq.tactic == SquadState.Tactic.NONE and now >= float(_cool.get(sq.id, 0.0)):
					_cool[sq.id] = now + 10.0
					if _fitness(sq) >= 0.3 and sq.members.size() >= min_squad_n:
						var rs := sim.tactics.assign_for_operation(sq, SquadState.Tactic.SUPPRESS, _fire_target(op, obj), "operation #%d: fire support (resumed)" % op.id, {"standoff": support_standoff_m})
						if not rs.ok and not _depleted(sq) and obj.owner != op.faction:
							# GAMEPLAY-03C: the support cannot fire any more (its ammunition for suppression is spent) but is still a
							# strong squad: it joins the assault instead of standing idle behind it (the Haugen trace: an 8-man support
							# squad idle for 140 s while the assault went in three men at a time).
							op.roles[sq.id] = SquadState.OpRole.ASSAULT
							sq.op_role = SquadState.OpRole.ASSAULT
							role_changes += 1
							_send_assault(op, sq, obj, k + 3)
							op.stage_why = "%s cannot support any more (%s) and joins the assault" % [sq.squad_name, rs.reason]
			SquadState.OpRole.REINFORCE:
				# Joined while the assault runs: goes in as soon as it has arrived at the staging point.
				if not sim.squads.marching(sq) and sq.tactic == SquadState.Tactic.NONE and obj.owner != op.faction:
					op.roles[sq.id] = SquadState.OpRole.ASSAULT
					sq.op_role = SquadState.OpRole.ASSAULT
					_send_assault(op, sq, obj, k + 1)
					op.stage_why = "%s (reinforcement) arrives and assaults" % sq.squad_name
			SquadState.OpRole.RESERVE:
				if a.eff < 0.7 or closest < 60.0:
					op.roles[sq.id] = SquadState.OpRole.ASSAULT
					sq.op_role = SquadState.OpRole.ASSAULT
					role_changes += 1
					_send_assault(op, sq, obj, k + 2)
					op.stage_why = "%s (reserve) committed: operation effectiveness %.2f" % [sq.squad_name, a.eff]
		k += 1
	# Nobody left who is attacking: the fit support goes in, otherwise the operation breaks off now instead of
	# waiting for the stall timeout with squads that are too weak to move.
	var attacking := false
	for sq: SquadState in sqs:
		var r: int = int(op.roles.get(sq.id, SquadState.OpRole.NONE))
		if (r == SquadState.OpRole.ASSAULT or r == SquadState.OpRole.MANEUVER) and (sq.tactic != SquadState.Tactic.NONE or sim.squads.marching(sq)):
			attacking = true
	if attacking or obj.owner == op.faction:
		_idle_since.erase(op.id)
	else:
		if not _idle_since.has(op.id):
			_idle_since[op.id] = now
		elif now - float(_idle_since[op.id]) > idle_assault_s:
			var promoted := false
			for sq: SquadState in sqs:
				if int(op.roles.get(sq.id, 0)) == SquadState.OpRole.SUPPORT and _fitness(sq) >= 0.3:
					op.roles[sq.id] = SquadState.OpRole.ASSAULT
					sq.op_role = SquadState.OpRole.ASSAULT
					role_changes += 1
					_send_assault(op, sq, obj, 0)
					op.stage_why = "%s goes in: no squad is attacking" % sq.squad_name
					promoted = true
					break
			if not promoted:
				# Suppressed or shaken squads recover in a minute and are tasked again by the loop above. The operation
				# waits only for squads that can recover (people and ammunition left), and only against a weak enemy;
				# otherwise it breaks off now instead of waiting for the stall timeout.
				var recoverable := false
				for sq: SquadState in sqs:
					var sa := sim.tactics.assessment(sq)
					if sq.members.size() >= 3 and (sa.is_empty() or float(sa.get("ammo", 1.0)) >= 0.25):
						recoverable = true
				var idle_s := now - float(_idle_since[op.id])
				# Clearly stronger than what it believes is left: the squads walk in (taking ground needs people, not
				# ammunition) instead of waiting for the stall timeout.
				var believed := maxi(int(a.seen), ws.intel.threat_near(op.faction, obj.position, obj.radius + 150.0))
				if recoverable and float(a.soldiers) >= 2.5 * float(maxi(believed, 1)) and a.ammo >= 0.05:
					var kk := 0
					for sq: SquadState in sqs:
						if sq.tactic != SquadState.Tactic.NONE and sq.tactic_owner == SquadState.Owner.OPERATION:
							sim.tactics.cancel(sq, "final push")
						sim.squads.follow_route(sq, PackedVector3Array([_slot(obj, kk)]), SquadState.Formation.LINE)
						kk += 1
					op.stage_why = "final push: %d of ours against %d believed, the squads walk in" % [a.soldiers, believed]
					op.wait_reason = ""
					_idle_since.erase(op.id)
					return
				if not recoverable or float(a.soldiers) < 2.5 * float(maxi(int(a.seen), 1)) or a.ammo < 0.2 or idle_s > idle_assault_max_s:
					timeouts += 1
					_idle_since.erase(op.id)
					var detail: Array[String] = []
					for sq: SquadState in sqs:
						var sa2 := sim.tactics.assessment(sq)
						detail.append("%s %d men, ammo %d%%, eff %.2f" % [sq.squad_name, sq.members.size(), roundi(float(sa2.get("ammo", 1.0)) * 100.0), float(sa2.get("eff", 0.0))])
					withdraw(op, "no squad is fit to continue the assault (%d of ours against %d seen; %s)" % [a.soldiers, a.seen, "; ".join(detail)])
					return
				op.wait_reason = "squads regroup before the next push (%d s)" % int(idle_s)
			else:
				_idle_since.erase(op.id)
	# A depleted support squad is replaced by a reserve (rarely, explained).
	_replace_support(op, sqs, obj)
	# GAMEPLAY-02A: no assault squad got closer for progress_stall_s - every fit squad goes in together once (the support lifts
	# its fire and joins); a second stall breaks the attack off instead of waiting for assault_stall_s.
	# On the objective (closest < 40 m) the capture decides, not the distance.
	if closest < 40.0:
		op.progress_t = now
	var assaulting := false
	for sq: SquadState in sqs:
		var rr: int = int(op.roles.get(sq.id, SquadState.OpRole.NONE))
		if (rr == SquadState.OpRole.ASSAULT or rr == SquadState.OpRole.MANEUVER) and not op.assault_at.has(sq.id) \
				and (sq.tactic == SquadState.Tactic.ASSAULT or sq.tactic == SquadState.Tactic.FLANK or sim.squads.marching(sq)):
			assaulting = true
	var stall_limit := progress_stall_s if assaulting else idle_commit_s
	if obj.owner != op.faction and now - op.progress_t > stall_limit:
		var believed := maxi(int(a.seen), ws.intel.threat_near(op.faction, obj.position, obj.radius + 150.0))
		if not op.assault_at.has(-1) and float(a.soldiers) < 2.0 * float(maxi(believed, 1)):
			timeouts += 1
			withdraw(op, "no progress for %d s and too few to go in together (%d of ours against %d believed)" % [int(stall_limit), a.soldiers, believed])
			return
		if not op.assault_at.has(-1):
			op.assault_at[-1] = now
			op.progress_t = now
			var kk := 0
			var sent: Array[String] = []
			for sq: SquadState in sqs:
				if sq.members.size() >= min_squad_n and _fitness(sq) >= 0.2:
					op.roles[sq.id] = SquadState.OpRole.ASSAULT
					sq.op_role = SquadState.OpRole.ASSAULT
					if sq.tactic != SquadState.Tactic.ASSAULT:
						if sq.tactic != SquadState.Tactic.NONE and sq.tactic_owner == SquadState.Owner.OPERATION:
							sim.tactics.cancel(sq, "every squad goes in")
						_send_assault(op, sq, obj, kk)
					sent.append(sq.squad_name)
				kk += 1
			role_changes += 1
			op.stage_why = "no progress for %d s (closest %.0f m, %s): %s go in together" % [int(stall_limit), op.progress_best,
				"squads advancing" if assaulting else "nobody advancing", ", ".join(sent)]
			return
		timeouts += 1
		withdraw(op, "no progress for %d s after committing every squad (closest %.0f m)" % [int(stall_limit), op.progress_best])
		return
	if now - op.stage_since > assault_stall_s and obj.owner != op.faction:
		timeouts += 1
		withdraw(op, "the assault has not taken the objective in %d s" % int(now - op.stage_since))


func _update_withdraw(op: OperationState, obj: ObjectiveState, sqs: Array, now: float) -> void:
	var fb := op.fallback_pos
	var support := _of_role(op, SquadState.OpRole.SUPPORT)
	# The support covers until the others are well clear of the objective, then follows.
	var clear := true
	for sq: SquadState in sqs:
		if int(op.roles.get(sq.id, 0)) != SquadState.OpRole.SUPPORT and _flat(sim.squads._centroid(sq), obj.position) < 150.0:
			clear = false
	for sq: SquadState in support:
		if sq.tactic != SquadState.Tactic.WITHDRAW and (clear or now - op.stage_since > 25.0):
			_withdraw_squad(op, sq, 5)
	op.wait_reason = "support covering the withdrawal" if not clear else ""
	var at := 0
	for sq: SquadState in sqs:
		if not fb.is_finite() or _flat(sim.squads._centroid(sq), fb) < 60.0:
			at += 1
	if at >= sqs.size() or now - op.stage_since > 150.0:
		_finish_withdraw(op, sqs, now)


func _finish_withdraw(op: OperationState, sqs: Array, now: float) -> void:
	for sq: SquadState in sqs:
		sq.recover_until = now + 90.0
		sq.op_role = SquadState.OpRole.NONE
		if sq.tactic != SquadState.Tactic.NONE and sq.tactic_owner == SquadState.Owner.OPERATION:
			sim.tactics.cancel(sq, "withdrawal complete")
	_set_stage(op, OperationState.Stage.DONE, "withdrawal complete")
	ws.end_operation(op, OperationState.Phase.FAILED, "withdrew: " + op.withdraw_why)


func _secure(op: OperationState, obj: ObjectiveState, sqs: Array) -> void:
	_set_stage(op, OperationState.Stage.SECURE, "%s is being taken: the squads move in" % obj.obj_name)
	op.wait_reason = ""
	op.cover_fire = false
	var k := 0
	for sq: SquadState in sqs:
		if sq.tactic != SquadState.Tactic.NONE and sq.tactic_owner == SquadState.Owner.OPERATION:
			sim.tactics.cancel(sq, "objective taken")
		sq.op_role = SquadState.OpRole.SECURITY
		op.roles[sq.id] = SquadState.OpRole.SECURITY
		sim.squads.follow_route(sq, PackedVector3Array([_slot(obj, k)]), SquadState.Formation.LINE)
		k += 1


func _withdraw_squad(op: OperationState, sq: SquadState, k: int) -> void:
	var fb := op.fallback_pos
	if not fb.is_finite():
		return
	var side := Vector3(-(fb.z - op.target_pos.z), 0.0, fb.x - op.target_pos.x).normalized()
	var tgt := sim.tactics.pos.nearest_valid(fb + side * (k - 1) * 14.0, 10.0)
	sim.tactics.assign_for_operation(sq, SquadState.Tactic.WITHDRAW, tgt if tgt.is_finite() else fb, "operation #%d withdraws: %s" % [op.id, op.withdraw_why])


func _send_assault(op: OperationState, sq: SquadState, obj: ObjectiveState, k: int) -> void:
	if _flat(sim.squads._centroid(sq), _slot(obj, k)) < 25.0:
		return  # already there
	var res := sim.tactics.assign_for_operation(sq, SquadState.Tactic.ASSAULT, _slot(obj, k), "operation #%d: assault on %s" % [op.id, obj.obj_name], {"ext": true})
	if not res.ok:
		op.stage_why += "; %s cannot assault (%s)" % [sq.squad_name, res.reason]


## GAMEPLAY-02A: half or more of the squad is gone.
func _depleted(sq: SquadState) -> bool:
	return sq.members.size() * 2 <= sq.members.size() + sq.fallen.size()


## A depleted assault squad becomes fire support from about where it stands (it does not walk into the fire again).
func _to_support(op: OperationState, obj: ObjectiveState, sq: SquadState) -> bool:
	var d := clampf(_flat(sim.squads._centroid(sq), obj.position), 80.0, support_standoff_m)
	var res := sim.tactics.assign_for_operation(sq, SquadState.Tactic.SUPPRESS, _fire_target(op, obj), "operation #%d: depleted, supports the assault" % op.id, {"standoff": d})
	if not res.ok:
		return false
	op.roles[sq.id] = SquadState.OpRole.SUPPORT
	sq.op_role = SquadState.OpRole.SUPPORT
	role_changes += 1
	return true


## A support squad that can no longer fire (effectiveness low) hands its role to the reserve (if any).
func _replace_support(op: OperationState, sqs: Array, obj: ObjectiveState) -> void:
	var reserve: SquadState = null
	for sq: SquadState in sqs:
		if int(op.roles.get(sq.id, 0)) == SquadState.OpRole.RESERVE:
			reserve = sq
	if reserve == null:
		return
	for sq: SquadState in sqs:
		if int(op.roles.get(sq.id, 0)) == SquadState.OpRole.SUPPORT and _fitness(sq) < 0.3:
			op.roles[sq.id] = SquadState.OpRole.RESERVE
			op.roles[reserve.id] = SquadState.OpRole.SUPPORT
			sq.op_role = SquadState.OpRole.RESERVE
			reserve.op_role = SquadState.OpRole.SUPPORT
			role_changes += 1
			sim.tactics.assign_for_operation(reserve, SquadState.Tactic.SUPPRESS, _fire_target(op, obj), "operation #%d: replaces the depleted fire support" % op.id, {"standoff": support_standoff_m})
			sim.tactics.cancel(sq, "relieved as fire support")
			op.stage_why = "%s relieves %s as fire support (effectiveness %.2f)" % [reserve.squad_name, sq.squad_name, _fitness(sq)]
			return


# --- Counterattack of a defending reserve (AI-WAR-LOGISTICS-01) -------------------------------------------------------------

## Success, failure and timeout limits of a counterattack.
var counter_timeout_s := 260.0
var counter_abort_eff := 0.36
var counter_loss_ratio := 0.4
var counter_clear_s := 20.0
var counter_cool_ok_s := 150.0
var counter_cool_fail_s := 420.0


## The reserve attacks the believed attackers at op.target_pos with the ordinary squad tactics: a flank where the
## ground gives a covered way (SquadTactics._plan decides), else a straight assault; the rest of the garrison keeps
## its sector and fires. No new combat system: the operation owns the squads for its duration, then hands them back.
func begin_counter(op: OperationState, obj: ObjectiveState) -> void:
	op.phase = OperationState.Phase.ENGAGING
	_set_stage(op, OperationState.Stage.ASSAULT, "the reserve of %s counterattacks the attackers believed at (%.0f, %.0f)" % [obj.obj_name if obj else "the objective", op.target_pos.x, op.target_pos.z])
	var k := 0
	for sq: SquadState in _squads(op):
		op.roles[sq.id] = SquadState.OpRole.ASSAULT
		sq.op_role = SquadState.OpRole.ASSAULT
		var tactic := SquadState.Tactic.FLANK if k % 2 == 1 else SquadState.Tactic.ASSAULT
		var res := sim.tactics.assign_for_operation(sq, tactic, op.target_pos, "operation #%d: counterattack from %s" % [op.id, obj.obj_name if obj else "the defence"], {"ext": true})
		if not res.ok and tactic == SquadState.Tactic.FLANK:
			res = sim.tactics.assign_for_operation(sq, SquadState.Tactic.ASSAULT, op.target_pos, "operation #%d: counterattack from %s" % [op.id, obj.obj_name if obj else "the defence"], {"ext": true})
		if not res.ok:
			op.stage_why += "; %s cannot attack (%s)" % [sq.squad_name, res.reason]
		k += 1
	op.assault_pos = op.target_pos


## Once a second. Ends in success (no attacker is believed or seen near the target for counter_clear_s), failure
## (effectiveness, losses, the objective contested or lost, time) or when nothing is left to command.
func update_counter(op: OperationState, obj: ObjectiveState) -> void:
	var now := sim.state.time
	_prune(op)
	var sqs := _squads(op)
	if sqs.is_empty():
		ws.end_operation(op, OperationState.Phase.FAILED, "the reserve was destroyed")
		return
	var a := _op_status(op, sqs, obj)
	# The reserve has reached the place and sees nobody there: the report was out of date (or the attackers fell);
	# the contacts there are cleared like an investigation clears them.
	var nearest := INF
	for sq: SquadState in sqs:
		nearest = minf(nearest, _flat(sim.squads._centroid(sq), op.target_pos))
	var believed := ws.intel.threat_near(op.faction, op.target_pos, 160.0)
	if nearest < 80.0 and a.seen == 0:
		believed = 0
		for c: ContactState in ws.intel.contacts_near(op.faction, op.target_pos, 140.0):
			ws.intel.clear_contact(op.faction, c.id, now - 12.0)
	if a.seen == 0 and believed <= 0:
		if not _clear_since.has(op.id):
			_clear_since[op.id] = now
	else:
		_clear_since.erase(op.id)
	var why := ""
	var success := false
	if _clear_since.has(op.id) and now - float(_clear_since[op.id]) >= counter_clear_s:
		success = true
		why = "the attackers are gone from (%.0f, %.0f): the reserve returns" % [op.target_pos.x, op.target_pos.z]
	elif obj != null and obj.owner != op.faction:
		why = "%s was lost during the counterattack" % obj.obj_name
	elif obj != null and obj.contested and obj.capture_faction >= 0 and obj.capture_faction != op.faction and obj.capture_progress > 0.4:
		why = "the attackers are capturing %s: the reserve falls back to the defence" % obj.obj_name
	elif float(a.soldiers) < op.start_strength * (1.0 - counter_loss_ratio):
		why = "too many losses (%d of %d left)" % [a.soldiers, op.start_strength]
	elif a.eff < counter_abort_eff and now - op.stage_since > 12.0:
		why = "effectiveness %.2f: the counterattack is unfavourable" % a.eff
	elif a.ammo < 0.12:
		why = "ammunition down to %.0f%%" % (a.ammo * 100.0)
	elif now - op.stage_since > counter_timeout_s:
		why = "the counterattack took longer than %d s" % int(counter_timeout_s)
	op.wait_reason = "" if why != "" else "counterattack in progress: %d of ours against %d seen, effectiveness %.2f" % [a.soldiers, a.seen, a.eff]
	# A squad whose tactic ended (done, failed) is tasked again as long as the attack lasts.
	if why == "":
		for sq: SquadState in sqs:
			if sq.tactic == SquadState.Tactic.NONE and now >= float(_cool.get(sq.id, 0.0)):
				_cool[sq.id] = now + 10.0
				sim.tactics.assign_for_operation(sq, SquadState.Tactic.ASSAULT, op.target_pos, "operation #%d: counterattack (resumed)" % op.id, {"ext": true})
		return
	_finish_counter(op, obj, sqs, success, why)


func _finish_counter(op: OperationState, obj: ObjectiveState, sqs: Array, success: bool, why: String) -> void:
	for sq: SquadState in sqs:
		if sq.tactic != SquadState.Tactic.NONE and sq.tactic_owner == SquadState.Owner.OPERATION:
			sim.tactics.cancel(sq, "counterattack ended")
		sq.op_role = SquadState.OpRole.NONE
	ws.war.counter_cool[op.target_objective] = now_plus(counter_cool_ok_s if success else counter_cool_fail_s)
	_clear_since.erase(op.id)
	if obj != null and obj.owner == op.faction:
		ws._garrison(op, obj)  # back into the defensive posture: sectors and the local reserve
	ws.log_event(op.faction, "counter", "Counterattack #%d at %s %s: %s" % [op.id, obj.obj_name if obj else "the objective", "succeeded" if success else "ended", why], op.target_pos)
	_set_stage(op, OperationState.Stage.DONE, why)
	ws.end_operation(op, OperationState.Phase.COMPLETED if success else OperationState.Phase.FAILED, why)


func now_plus(s: float) -> float:
	return sim.state.time + s


# --- Measurements and helpers -------------------------------------------------------------------------------------

## The operation's combined state from its squads' own assessments: soldiers, a strength-weighted
## effectiveness, suppression and ammunition.
func _op_status(op: OperationState, sqs: Array, obj: ObjectiveState) -> Dictionary:
	var soldiers := 0
	var eff := 0.0
	var supp := 0.0
	var ammo := 0.0
	var w := 0.0
	var seen := 0
	for sq: SquadState in sqs:
		var a := sim.tactics.assessment(sq)
		if a.is_empty():
			a = sim.tactics._assess_squad(sq)
		var n := sq.members.size()
		soldiers += n
		seen = maxi(seen, int(a.get("seen_n", 0)))  # the same enemy is seen by several squads
		eff += float(a.get("eff", 0.0)) * n
		supp += float(a.get("supp", 0.0)) * n
		ammo += float(a.get("ammo", 1.0)) * n
		w += n
	w = maxf(w, 1.0)
	var strength := float(soldiers) / maxf(op.start_strength, 1.0)
	# Effectiveness already contains each squad's own losses; the operation also counts how much of the
	# force it started with is gone.
	return {"soldiers": soldiers, "seen": seen, "eff": (eff / w) * clampf(strength * 1.15, 0.0, 1.0), "strength": strength, "supp": supp / w, "ammo": ammo / w}


func _squads(op: OperationState) -> Array:
	var out := []
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq and sq.op_id == op.id and sq.members.size() >= 1:
			out.append(sq)
	return out


func _of_role(op: OperationState, role: int) -> Array:
	var out := []
	for sq: SquadState in _squads(op):
		if int(op.roles.get(sq.id, 0)) == role:
			out.append(sq)
	return out


## Roles of squads that left the operation (a player order, wiped out) are dropped; an attack that lost its
## only fire support or its only assault squad reassigns.
func _prune(op: OperationState) -> void:
	var changed := false
	for sid in op.roles.keys():
		var sq := sim.state.get_squad(sid)
		if sq == null or sq.op_id != op.id or not op.squads.has(sid):
			op.roles.erase(sid)
			changed = true
	for sq: SquadState in _squads(op):
		if not op.roles.has(sq.id):
			# A squad that joined (reinforcement): reserve until the assault needs it.
			op.roles[sq.id] = SquadState.OpRole.REINFORCE if op.stage >= OperationState.Stage.ASSAULT else SquadState.OpRole.ASSAULT
			sq.op_role = int(op.roles[sq.id])
			changed = true
	if changed:
		role_changes += 1
		var has_assault := false
		for sid in op.roles:
			var r := int(op.roles[sid])
			if r == SquadState.OpRole.ASSAULT or r == SquadState.OpRole.MANEUVER or r == SquadState.OpRole.REINFORCE:
				has_assault = true
		if not has_assault and not op.roles.is_empty():
			# Only support squads are left: one of them assaults (the operation adapts).
			var first: int = op.roles.keys()[0]
			op.roles[first] = SquadState.OpRole.ASSAULT
			var sq0 := sim.state.get_squad(first)
			if sq0:
				sq0.op_role = SquadState.OpRole.ASSAULT
		op.stage_why = "roles after a change: " + _roles_text(op)


func _support_set(support: Array) -> bool:
	for sq: SquadState in support:
		if sq.tactic == SquadState.Tactic.SUPPRESS and sq.tactic_phase >= SquadTactics.PH_HOLD:
			return true
		if sq.tactic == SquadState.Tactic.NONE:
			return true  # it could not take the role: do not wait for it
	return false


func _support_text(support: Array) -> String:
	var parts: Array[String] = []
	for sq: SquadState in support:
		parts.append(sq.squad_name)
	return ", ".join(parts)


func _set_stage(op: OperationState, stage: int, why: String) -> void:
	if op.stage != stage:
		stage_changes += 1
		op.stage = stage
		op.stage_since = sim.state.time
	op.stage_why = why
	ws.log_event(op.faction, "op_stage", "%s #%d: %s - %s" % [op.type_name(), op.id, op.stage_name(), why], op.target_pos)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Inspection ------------------------------------------------------------------------------------------------------------

## Lines for the inspector: stage and why, roles, what the operation is waiting for, each squad's tactic.
func explain(op: OperationState) -> Array[String]:
	var out: Array[String] = []
	if op.type != OperationState.Type.ATTACK or op.stage == OperationState.Stage.APPROACH and op.roles.is_empty():
		return out
	out.append("Stage: %s for %d s - %s" % [op.stage_name().to_upper(), int(sim.state.time - op.stage_since), op.stage_why])
	if op.wait_reason != "":
		out.append("Waiting: " + op.wait_reason)
	if op.withdraw_why != "":
		out.append("Withdrawal: %s%s" % [op.withdraw_why, "" if not op.fallback_pos.is_finite() else " to (%.0f, %.0f)" % [op.fallback_pos.x, op.fallback_pos.z]])
	for sq: SquadState in _squads(op):
		var a := sim.tactics.assessment(sq)
		out.append("  %s: %s - %s, effectiveness %.2f, %d soldiers" % [sq.squad_name, SquadState.OP_ROLE_NAMES[int(op.roles.get(sq.id, 0))], sim.tactics.short_text(sq) if sq.tactic != SquadState.Tactic.NONE else sq.order_name(),
			float(a.get("eff", 0.0)), sq.members.size()])
	return out


func summary() -> Dictionary:
	return {"updates": updates, "stage_changes": stage_changes, "role_changes": role_changes, "withdrawals": withdrawals, "timeouts": timeouts, "line_holds": line_holds, "support_displaced": support_displaced,
		"us_avg": snappedf(float(usec) / maxi(updates, 1), 0.1), "us_max": usec_max}

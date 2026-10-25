## Squad tactics (AI-SQUAD-01): fire teams, squad-level tactical decisions and the tactics
## themselves - DEFEND, SUPPRESS, ASSAULT, FLANK, BOUND, REPOSITION, WITHDRAW and REGROUP.
##
## The squad owns the tactical intent (SquadState.tactic and its target / phase / route fields,
## all saved); the soldiers execute it with the calls they already have: ordinary move orders to
## assigned posts (UnitState.post_pos), fire missions at a *reported* position
## (UnitState.fire_at, fired by CombatBrain through CombatSim like any shot) and their own
## CombatBrain reactions within a few metres of the post. Nothing here reads the true position of
## an enemy it has not been told about: targets are a faction contact (IntelSim), a position the
## soldiers of the squad are looking at right now, or a position the player chose.
##
## Authority stays player > operation > squad tactic > individual reaction:
##   * every ordinary squad order (SquadControl.order_move / hold / follow / regroup / follow_route)
##     calls on_order(), which ends the tactic and its fire missions at once;
##   * an operation may assign a tactic (assign_for_operation); it ends with the operation;
##   * a squad chooses a tactic itself (_consider) only when nobody commands it - idle, holding,
##     garrisoning, or an operation squad that has arrived and is fighting at its objective;
##   * a squad with a member aboard a vehicle never runs a tactic.
##
## All tactic state lives in the saved records (SquadState tactic_* fields, UnitState post_pos /
## fire_at): every step derives from them, so a loaded game, or a squad whose soldiers are all in
## the abstract tier, carries on exactly where it was.
##
## Cost: update() steps each squad twice a second (assessment: a loop over its soldiers and one
## contact query); a new tactic is chosen at most every eval_s per squad and planning (post
## search, flank routes) happens when a tactic or a leg starts, never per frame. No planner, no
## second blackboard: the choice is a handful of scores written next to the reasons it produced.
class_name SquadTactics
extends RefCounted

# --- Switches and tunables --------------------------------------------------------------
var enabled := true
## Squads choose tactics themselves (DEFEND, SUPPRESS, WITHDRAW; offensive ones only when an
## operation or the player gave the task).
var autonomous := true
## Attack operations coordinate their squads with roles and squad tactics (OpCoordination); false = the
## old walk-in, kept as a diagnostic comparison (--legacy-ops).
var ops_assault := true
var tick_s := 0.5
var eval_s := 2.0
## Contacts further than this from the squad are ignored by its tactics (m).
var engage_radius_m := 450.0
var contact_min_conf := 0.2
## Effectiveness below which an uncommanded squad withdraws, and below which an attack is
## broken off.
var withdraw_eff := 0.38
var abort_eff := 0.28
## A team starts its next move only when fewer than this fraction of it is pinned.
var pinned_go := 0.5
var calm_end_s := 40.0
var assault_timeout_s := 170.0
## GAMEPLAY-04A: an assault still approaching its target stops when it has not got 10 m closer for this long.
var approach_stall_s := 60.0
var flank_timeout_s := 160.0
## Bounding / advancing leg length (m) and how long a leg may take (s).
var leg_m := 30.0
var leg_timeout_s := 18.0
var flank_lateral_m := 75.0
var flank_max_detour := 2.3
## A flank must expose the maneuver team this much less than going straight in.
var flank_gain := 0.2
var reposition_cooldown_s := 25.0
var reposition_limit := 3
## Fire missions are refreshed for this long each time (s).
var mission_s := 3.0
## GAMEPLAY-01B BUILD: an idle squad of the player takes up a construction site within build_auto_m on its own (checked
## every build_check_s); a newly placed site calls the nearest idle squad within build_assign_m. A squad whose BUILD the
## player cancelled with an order is left alone for build_respect_s.
var build_auto_m := 150.0
var build_assign_m := 900.0
var build_check_s := 3.0
var build_respect_s := 120.0
## GAMEPLAY-01C: a defence uses the fortification slots within fort_radius_m of its spot; a garrison re-mans its base every
## garrison_check_s when it is not fighting from it.
var fort_radius_m := 35.0
var garrison_check_s := 2.0

# --- Measurements ---------------------------------------------------------------------------
var steps := 0
var step_usec := 0
var step_usec_max := 0
var ticks := 0
var started := {}
var finished := {}
var decisions := 0
var refusals := 0
var replans := 0
## Recent decisions of all squads, newest last: {t, text}.
var events: Array = []
const MAX_EVENTS := 200

const PH_SETUP := 0
const PH_SUPPORT := 1
const PH_MOVE := 2
const PH_OCCUPY := 3
const PH_FINAL := 4
## DEFEND / SUPPRESS / REPOSITION: 0 moving to the posts, 1 holding / firing.
const PH_HOLD := 1

var sim: WorldSim
var pos: SquadPositions
var _t := 0.0
var _assess := {}
var _next_eval := {}
var _avoid := {}
var _blind := {}
var _repos := {}
var _seen_at := {}
var _meta_store := {}
## True while the tactics call squad orders themselves (they must not cancel themselves).
var _internal := false
## GAMEPLAY-01B: simulated seconds of the current step, soldiers at work per site in this step, next auto-build check
## per squad, sites nobody could reach (site id -> time) - runtime only.
var _dt := 0.5
var _site_workers := {}
var _next_build := {}
var _site_block := {}
## GAMEPLAY-01C: next garrison check per squad (runtime).
var _next_garrison := {}


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
	pos = SquadPositions.new(p_sim)


func connect_signals() -> void:
	sim.state.unit_died.connect(_on_unit_died)
	sim.state.restored.connect(_on_restored)


# --- Per tick ----------------------------------------------------------------------------------

func update(delta: float) -> void:
	if not enabled:
		return
	_t += delta
	if _t < tick_s:
		return
	_dt = _t
	_t = 0.0
	ticks += 1
	_defence_starts = 0
	plans_tick = 0
	plan_tick_usec = 0
	var t0 := Time.get_ticks_usec()
	var counted := _site_workers.keys()
	_site_workers.clear()
	for sq: SquadState in sim.state.squads.values():
		_step(sq)
	# Workers per site for the HUD (several squads may work on one site).
	for sid in counted + _site_workers.keys():
		var s := sim.state.construction.get_structure(sid)
		if s and s.needs_work():
			s.work_record()["workers"] = int(_site_workers.get(sid, 0))
	var dt := Time.get_ticks_usec() - t0
	step_usec += dt
	step_usec_max = maxi(step_usec_max, dt)
	plans_tick_max = maxi(plans_tick_max, plans_tick)
	plan_tick_usec_max = maxi(plan_tick_usec_max, plan_tick_usec)


func _step(sq: SquadState) -> void:
	steps += 1
	var now := sim.state.time
	if sq.members.is_empty():
		return
	if _aboard(sq):
		if sq.tactic != SquadState.Tactic.NONE:
			_finish(sq, "aboard a vehicle: no infantry maneuver", SquadState.Tactic.NONE)
		return
	validate(sq)
	# A squad that completed a REGROUP order resumes what it was doing before its tactic.
	if sq.tactic == SquadState.Tactic.NONE and sq.order == SquadState.Order.REGROUP and sq.prev_order != SquadState.Order.NONE \
			and sq.status == SquadState.Status.DONE and sq.tactic_owner == SquadState.Owner.NONE:
		_resume_previous(sq)
	var a := _assess_squad(sq)
	if sq.formation_auto and sq.tactic == SquadState.Tactic.NONE and sq.order == SquadState.Order.MOVE:
		_formation_for_contact(sq, a, now)
	if sq.tactic != SquadState.Tactic.NONE:
		_run(sq, a)
	elif sq.garrison_base >= 0 and sq.order != SquadState.Order.REGROUP:
		_garrison_step(sq, a, now)
	elif autonomous and a.in_contact and now >= float(_next_eval.get(sq.id, 0.0)) and now >= sq.tactic_cooldown_until and _autonomy_ok(sq):
		_next_eval[sq.id] = now + eval_s
		_consider(sq, a)
	elif not a.in_contact and now >= float(_next_build.get(sq.id, 0.0)):
		_next_build[sq.id] = now + build_check_s
		_auto_build(sq, a.center, build_auto_m)


## A squad on the move that picks its own formation spreads out when it comes into contact and
## takes the shape its ground suits again once it has been quiet for a while (with hysteresis).
func _formation_for_contact(sq: SquadState, a: Dictionary, now: float) -> void:
	if a.in_contact:
		_set_meta(sq, "contact_at", now)
		if sq.formation != SquadState.Formation.DISPERSED and now >= float(_meta(sq, "formation_until", 0.0)):
			sq.formation = SquadState.Formation.DISPERSED
			_set_meta(sq, "formation_until", now + 10.0)
			sim.squads._reapply(sq)
	elif sq.formation == SquadState.Formation.DISPERSED and now - float(_meta(sq, "contact_at", -1000.0)) > 15.0 and now >= float(_meta(sq, "formation_until", 0.0)):
		sq.formation = sim.squads.choose_formation(sq, sq.order_target if sq.order_target.is_finite() else a.center)
		_set_meta(sq, "formation_until", now + 10.0)
		sim.squads._reapply(sq)


func _aboard(sq: SquadState) -> bool:
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u and u.vehicle_id >= 0:
			return true
	return false


## Nobody commands the squad right now (idle, holding, garrisoning, or at the objective its
## operation is attacking), so it may choose a tactic. Not while it marches or follows.
func _autonomy_ok(sq: SquadState) -> bool:
	if sim.squads.marching(sq):
		return false
	if sq.op_role != SquadState.OpRole.NONE and sq.op_id >= 0:
		return false  # the operation coordinates it
	if sq.op_id >= 0:
		var op := sim.state.war.operation(sq.op_id)
		if op != null and op.is_active() and op.phase < OperationState.Phase.ENGAGING:
			return false
	match sq.order:
		SquadState.Order.FOLLOW, SquadState.Order.REGROUP:
			return false
		SquadState.Order.MOVE:
			return sq.status != SquadState.Status.MOVING
	return true


## 0 neutral, 1 defensive (garrison, defence operation, securing), 2 offensive (an attack
## operation that has reached the objective).
func posture(sq: SquadState) -> int:
	if sq.op_id >= 0:
		var op := sim.state.war.operation(sq.op_id)
		if op != null and op.is_active():
			if op.type == OperationState.Type.ATTACK:
				return 2 if op.phase == OperationState.Phase.ENGAGING else 1
			if op.type == OperationState.Type.DEFEND:
				return 1
	if sq.station_objective >= 0:
		return 1
	return 0


# --- Fire teams -----------------------------------------------------------------------------------

## Keeps the fire teams valid: only living members, two teams of at least two for squads of four
## and more (one team below that), balanced within one soldier, every team with a leader. The
## squad leader leads its own team. Casualties, joiners and reassigned soldiers all go through
## here.
func validate(sq: SquadState) -> void:
	var members := sq.members
	var want := 2 if members.size() >= 4 else 1
	var dirty := sq.teams.size() != want or sq.team_leaders.size() != want or sq.team_roles.size() != want
	for i in sq.teams.size():
		var keep := PackedInt32Array()
		for id in sq.teams[i]:
			if members.has(id):
				keep.append(id)
		if keep.size() != sq.teams[i].size() or keep.is_empty():
			dirty = true
		sq.teams[i] = keep
	var assigned := 0
	for t in sq.teams:
		assigned += t.size()
	if assigned != members.size():
		dirty = true
	if sq.teams.size() == 2 and absi(sq.teams[0].size() - sq.teams[1].size()) >= 2:
		dirty = true
	if dirty:
		_rebuild_teams(sq, want)
	for i in sq.teams.size():
		var cur := sq.team_leaders[i]
		if not sq.teams[i].has(cur):
			var next := sq.leader_id if sq.teams[i].has(sq.leader_id) else sq.teams[i][0]
			if cur >= 0:
				_log(sq, "%s takes over fire team %s (%s is gone)" % [_name(next), "AB"[i], _name(cur)])
			sq.team_leaders[i] = next
	var lt := sq.team_of(sq.leader_id)
	if lt >= 0:
		sq.team_leaders[lt] = sq.leader_id


func _rebuild_teams(sq: SquadState, want: int) -> void:
	var old: Array[PackedInt32Array] = []
	for t in sq.teams:
		var keep := PackedInt32Array()
		for id in t:
			if sq.members.has(id):
				keep.append(id)
		if not keep.is_empty():
			old.append(keep)
	var loose := PackedInt32Array()
	for id in sq.members:
		var found := false
		for t in old:
			if t.has(id):
				found = true
				break
		if not found:
			loose.append(id)
	var all := PackedInt32Array()
	for id in sq.members:
		all.append(id)
	var teams: Array[PackedInt32Array] = []
	if want == 1:
		teams.append(all)
	elif old.size() >= 2:
		var t0: PackedInt32Array = old[0]
		var t1: PackedInt32Array = old[1]
		for k in range(2, old.size()):
			t1.append_array(old[k])
		for id in loose:
			if t0.size() <= t1.size():
				t0.append(id)
			else:
				t1.append(id)
		teams.append(t0)
		teams.append(t1)
	else:
		# Split by formation order: the first half (with the leader) and the rest.
		var half := (all.size() + 1) / 2
		teams.append(all.slice(0, half))
		teams.append(all.slice(half))
	# Balance within one soldier: the last of the larger team moves over.
	while teams.size() == 2 and absi(teams[0].size() - teams[1].size()) >= 2:
		var big := 0 if teams[0].size() > teams[1].size() else 1
		var id := teams[big][teams[big].size() - 1]
		teams[big].remove_at(teams[big].size() - 1)
		teams[1 - big].append(id)
	var before := sq.teams.size()
	var leaders := PackedInt32Array()
	var roles := PackedInt32Array()
	for i in teams.size():
		leaders.append(sq.team_leaders[i] if i < sq.team_leaders.size() else -1)
		roles.append(sq.team_roles[i] if i < sq.team_roles.size() else SquadState.TeamRole.SECURITY)
	sq.teams = teams
	sq.team_leaders = leaders
	sq.team_roles = roles
	if before != teams.size() or before == 0:
		_log(sq, "%s: %s" % [sq.squad_name, ("one fire team of %d" % sq.members.size()) if teams.size() == 1 else ("two fire teams (%d + %d)" % [teams[0].size(), teams[1].size()])])


func _set_roles(sq: SquadState, r0: int, r1: int) -> void:
	for i in sq.teams.size():
		sq.team_roles[i] = r0 if i == 0 else r1


## Living soldiers of the squad (a team: only that one) that tactics may order: not aboard, not
## possessed by the player, not given an individual order.
func _units(sq: SquadState, team := -1) -> Array:
	var out: Array = []
	var ids: PackedInt32Array = sq.members
	if team >= 0:
		ids = sq.teams[team] if team < sq.teams.size() else PackedInt32Array()
	for id in ids:
		var u := sim.state.get_unit(id)
		if u and u.alive and u.vehicle_id < 0 and not u.player_controlled and not sq.is_detached(id):
			out.append(u)
	return out


# --- Assessment ------------------------------------------------------------------------------------

## What the squad knows and how it stands, from its soldiers' own records and the faction
## picture. Cached per squad for the inspector.
func _assess_squad(sq: SquadState) -> Dictionary:
	var now := sim.state.time
	var units := _units(sq)
	var a := {"n": units.size(), "n0": sq.members.size() + sq.fallen.size(), "center": Vector3.ZERO, "supp": 0.0, "pinned": 0,
		"ammo": 1.0, "cas": 0.0, "engaged": 0, "under_fire": 0, "seen": [], "seen_n": 0, "contact": null, "threat_pos": Vector3.INF,
		"threat_conf": 0.0, "threat_src": "none", "dist": INF, "enemy_est": 0.0, "eff": 0.0, "parts": {}, "in_contact": false}
	if units.is_empty():
		_assess[sq.id] = a
		return a
	var c := Vector3.ZERO
	var supp := 0.0
	var ammo := 0.0
	var ammo_n := 0
	var seen_ids := {}
	var seen_list: Array = []
	var seen_pos := Vector3.ZERO
	var fire_sum := Vector3.ZERO
	var fire_n := 0
	var pinned := 0
	var engaged := 0
	var under_fire := 0
	for u: UnitState in units:
		c += u.position
		var s := u.suppression_at(now)
		supp += s
		if s >= sim.brain.pinned_at:
			pinned += 1
		var def := sim.combat.weapon(u.weapon_id)
		if def:
			ammo += float(u.mag + u.reserve) / float(def.magazine_size + def.reserve_start)
			ammo_n += 1
		if u.target_id > 0 and u.target_visible and u.target_last_pos.is_finite() and now - u.target_seen_at < 4.0:
			if not seen_ids.has(u.target_id):
				seen_ids[u.target_id] = true
				seen_pos += u.target_last_pos
				seen_list.append(u.target_last_pos)
			if u.ai_state == UnitState.AiState.ENGAGING:
				engaged += 1
		if u.under_fire_until >= now:
			under_fire += 1
			if u.threat_pos.is_finite():
				fire_sum += u.threat_pos
				fire_n += 1
	var n := units.size()
	var center := c / n
	var contact := _best_contact(sq, center)
	a.center = center
	a.supp = supp / n
	a.pinned = pinned
	a.engaged = engaged
	a.under_fire = under_fire
	a.ammo = ammo / maxi(ammo_n, 1)
	a.cas = float(sq.fallen.size()) / maxi(int(a.n0), 1)
	a.seen = seen_list
	a.seen_n = seen_ids.size()
	a.contact = contact
	if seen_ids.size() > 0:
		a.threat_pos = seen_pos / seen_ids.size()
		a.threat_conf = 1.0
		a.threat_src = "seen"
		_seen_at[sq.id] = now
	elif contact != null:
		a.threat_pos = contact.pos
		a.threat_conf = contact.conf
		a.threat_src = "reported (contact #%d)" % contact.id
	elif fire_n > 0:
		a.threat_pos = fire_sum / fire_n
		a.threat_conf = 0.35
		a.threat_src = "took fire from"
	var threat: Vector3 = a.threat_pos
	if threat.is_finite():
		a.dist = _flat(center, threat)
	var est := float(seen_ids.size())
	if contact != null:
		est = maxf(est, float(contact.strength) * contact.conf)
	if fire_n > 0:
		est = maxf(est, 2.0)
	a.enemy_est = est
	var size_f: float = float(n) / maxi(int(a.n0), 1)
	var supp_f: float = 1.0 - 0.6 * float(a.supp)
	var ammo_f: float = clampf(float(a.ammo) / 0.5, 0.0, 1.0)
	var threat_f: float = clampf(1.0 - 0.3 * maxf(est / maxi(n, 1) - 1.0, 0.0), 0.5, 1.0)
	if n <= 2:
		size_f *= 0.7
	a.eff = size_f * supp_f * ammo_f * threat_f
	a.parts = {"size": snappedf(size_f, 0.01), "suppression": snappedf(supp_f, 0.01), "ammo": snappedf(ammo_f, 0.01), "threat": snappedf(threat_f, 0.01)}
	a.in_contact = engaged > 0 or under_fire > 0 or seen_ids.size() > 0 \
			or (contact != null and (contact.status == ContactState.Status.OBSERVED or (float(a.dist) < 220.0 and now - contact.t_seen < 20.0)))
	_assess[sq.id] = a
	return a


## The most confident contact of the squad's faction near it that is not lost: the faction's
## belief (IntelSim), never the world.
func _best_contact(sq: SquadState, center: Vector3) -> ContactState:
	if sim.war == null or not sim.war.enabled:
		return null
	for c: ContactState in sim.war.intel.contacts_near(sq.faction, center, engage_radius_m):
		if c.status != ContactState.Status.LOST and c.conf >= contact_min_conf:
			return c
	return null


func assessment(sq: SquadState) -> Dictionary:
	return _assess.get(sq.id, {})


func effectiveness(sq: SquadState) -> float:
	return float(_assess_squad(sq).eff)


# --- Autonomous choice ------------------------------------------------------------------------------

## An uncommanded squad in contact picks a tactic from a handful of scores. The best candidate
## above the threshold wins; every candidate that was not chosen and why is kept in
## SquadState.tactic_rejected, the winner's reason in tactic_why.
func _consider(sq: SquadState, a: Dictionary) -> void:
	decisions += 1
	var now := sim.state.time
	var post := posture(sq)
	var cands: Array = []
	var rej: Array[String] = []
	var threat: Vector3 = a.threat_pos
	var eff: float = a.eff
	var parts: Dictionary = a.parts
	# WITHDRAW: the squad cannot take much more.
	var weak: bool = eff < withdraw_eff or (float(a.cas) >= 0.4 and float(a.supp) >= 0.4 and eff < 0.55) \
			or (float(a.enemy_est) > int(a.n) * 2.2 and eff < 0.6 and int(a.engaged) > 0)
	if weak:
		var f := _fallback_point(sq, a)
		if f.is_finite():
			cands.append({"t": SquadState.Tactic.WITHDRAW, "score": 0.8 + (withdraw_eff - eff) * 2.0, "target": f,
				"why": "effectiveness %.2f (size %.2f, suppression %.2f, ammo %.2f): break contact" % [eff, parts.size, parts.suppression, parts.ammo]})
		else:
			rej.append("withdraw: no fallback position clear of known enemy")
	# SUPPRESS: a reported but unseen enemy within reach.
	if int(a.seen_n) == 0 and threat.is_finite() and float(a.threat_conf) >= 0.4 and float(a.dist) >= 45.0 and float(a.dist) <= 230.0 \
			and float(a.ammo) >= 0.5 and eff >= 0.45 and a.contact != null:
		cands.append({"t": SquadState.Tactic.SUPPRESS, "score": 0.55 + 0.1 * float(a.threat_conf), "target": threat,
			"why": "enemy %s %.0f m away, not visible: pin it with fire" % [a.threat_src, a.dist]})
	elif int(a.seen_n) == 0 and threat.is_finite():
		rej.append("suppress: %s" % ("no reported contact to fire at" if a.contact == null else "out of useful range (%.0f m) or ammunition / effectiveness too low" % a.dist))
	# DEFEND: hold and fight from good posts.
	var d_score := 0.65 if post == 1 else (0.5 if sq.order != SquadState.Order.FOLLOW else 0.3)
	if threat.is_finite() and float(a.dist) < 150.0:
		d_score += 0.1
	cands.append({"t": SquadState.Tactic.DEFEND, "score": d_score, "target": Vector3.INF,
		"why": "%s in contact (%s, %.0f m): take firing posts" % ["garrison" if post == 1 else "squad", a.threat_src, a.dist]})
	# OFFENSIVE: only an operation or the player attacks; a squad on its own does not go looking.
	if post == 2 and threat.is_finite() and eff >= 0.5:
		cands.append({"t": SquadState.Tactic.ASSAULT, "score": 0.7, "target": threat, "why": "the operation is attacking here, enemy %.0f m away" % a.dist})
	elif post != 2:
		rej.append("assault / flank: not tasked by an operation or the player")
	# Hysteresis: the last tactic is slightly preferred, one that just failed is not.
	for c: Dictionary in cands:
		if c.t == int(_meta(sq, "last_tactic", -1)):
			c.score += 0.1
		if now < float(_meta(sq, "failed_%d" % c.t, 0.0)):
			c.score -= 0.5
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.score > y.score)
	if cands.is_empty() or float(cands[0].score) < 0.45:
		sq.tactic_rejected = "; ".join(rej) if not rej.is_empty() else "no tactic scored above the threshold"
		return
	var best: Dictionary = cands[0]
	for k in range(1, cands.size()):
		rej.append("%s (%.2f) < %s (%.2f)" % [SquadState.TACTIC_NAMES[cands[k].t], cands[k].score, SquadState.TACTIC_NAMES[best.t], best.score])
	var contact_id := -1
	if a.contact != null:
		contact_id = (a.contact as ContactState).id
	_deferrable = true
	var res := start(sq, best.t, SquadState.Owner.SQUAD, best.target, contact_id, best.why)
	_deferrable = false
	if res.get("deferred", false):
		_next_eval[sq.id] = now  # chosen again next step, no penalty
		return
	if res.ok:
		sq.tactic_rejected = "; ".join(rej)
	else:
		sq.tactic_rejected = "%s refused: %s" % [SquadState.TACTIC_NAMES[best.t], res.reason] + ("; " + "; ".join(rej) if not rej.is_empty() else "")
		_set_meta(sq, "failed_%d" % best.t, now + 30.0)


# --- Starting, replacing and ending a tactic ------------------------------------------------------

## Starts a tactic. Returns {ok, reason}. Planning happens first (nothing changes when it fails).
## target: the position to defend / suppress / assault / flank round / withdraw to / move to.
func start(sq: SquadState, tactic: int, owner: int, target := Vector3.INF, contact_id := -1, why := "", extra := {}) -> Dictionary:
	if not enabled:
		return _refuse(sq, "tactics are off")
	if _aboard(sq):
		return _refuse(sq, "the squad is aboard a vehicle")
	validate(sq)
	var a := _assess_squad(sq)
	if int(a.n) == 0:
		return _refuse(sq, "no soldier is available to carry it out")
	if _deferrable and (tactic == SquadState.Tactic.DEFEND or tactic == SquadState.Tactic.REPOSITION):
		if _defence_starts >= defence_plans_per_step:
			deferred += 1
			return {"ok": false, "reason": "deferred to the next step (one defence plan per step)", "deferred": true}
		_defence_starts += 1
	var now := sim.state.time
	var plan := _plan(sq, a, tactic, target, owner, extra)
	if not plan.ok:
		return _refuse(sq, plan.reason)
	# Commit.
	if sq.tactic == SquadState.Tactic.NONE and sq.order != SquadState.Order.TACTIC:
		sq.prev_order = sq.order
		sq.prev_target = sq.order_target
		sq.prev_yaw = sq.order_yaw
	elif sq.tactic != SquadState.Tactic.NONE:
		_clear_units(sq)
	_internal = true
	sim.squads.clear_route(sq)
	_internal = false
	sq.detached.clear()
	sq.order = SquadState.Order.TACTIC
	sq.tactic = plan.tactic
	sq.tactic_owner = owner
	sq.tactic_ext = bool(extra.get("ext", false))
	sq.tactic_op = sq.op_id if owner == SquadState.Owner.OPERATION else -1
	sq.tactic_phase = PH_SETUP
	sq.tactic_leg = 0
	sq.tactic_since = now
	_set_meta(sq, "approach_best", INF)
	_set_meta(sq, "approach_best_at", now)
	if sq.tactic == SquadState.Tactic.DEFEND:
		sq.defence_line = 0
	sq.tactic_phase_since = now
	sq.tactic_leg_since = now
	sq.tactic_target = plan.get("target", target)
	sq.tactic_contact = contact_id
	sq.tactic_site = int(plan.get("site", -1))
	sq.tactic_dir = plan.get("dir", Vector3.ZERO)
	sq.tactic_dest = Vector3.INF
	sq.tactic_route = plan.get("route", PackedVector3Array())
	sq.tactic_route_i = 0
	sq.tactic_replans = 0
	sq.tactic_commit_until = now + float(plan.get("commit", 8.0))
	sq.tactic_why = plan.get("why", why)
	if sq.tactic_why == "":
		sq.tactic_why = why
	sq.tactic_rejected = plan.get("rejected", "")
	if sq.tactic_dir.length() > 0.01:
		sq.order_yaw = atan2(-sq.tactic_dir.x, -sq.tactic_dir.z)
	started[sq.tactic] = int(started.get(sq.tactic, 0)) + 1
	_set_meta(sq, "last_tactic", sq.tactic)
	_log(sq, "%s %s (%s): %s" % [sq.squad_name, SquadState.TACTIC_NAMES[sq.tactic].to_upper(), SquadState.OWNER_NAMES[owner], sq.tactic_why])
	_enter(sq, a, plan)
	sim.state.squad_changed.emit(sq)
	return {"ok": true, "reason": "", "tactic": sq.tactic}


func _refuse(sq: SquadState, reason: String) -> Dictionary:
	refusals += 1
	sq.tactic_rejected = reason
	_log(sq, "%s: tactic refused - %s" % [sq.squad_name, reason])
	return {"ok": false, "reason": reason}


## Pure planning: can the tactic be carried out, and how. May change the tactic (an assault that
## is better made as a flank).
func _plan(sq: SquadState, a: Dictionary, tactic: int, target: Vector3, _owner: int, extra := {}) -> Dictionary:
	var c: Vector3 = a.center
	var units := _units(sq)
	var count := units.size()
	var uid: int = units[0].id
	var threat: Vector3 = a.threat_pos
	match tactic:
		SquadState.Tactic.DEFEND:
			var centre := target if target.is_finite() else c
			# GAMEPLAY-01C: a garrison defends its base (its whole area: the base's fortifications); a defence elsewhere uses
			# the fortifications within fort_radius_m of the spot.
			var gb: Dictionary = sim.state.construction.bases.get(int(extra.get("garrison", -1)), {})
			if not gb.is_empty():
				var ga := pos.nearest_valid(gb.anchor, 30.0)
				centre = ga if ga.is_finite() else c
			var dir := _dir_to(centre, threat) if threat.is_finite() else _dir_from_yaw(sq.order_yaw)
			var look: Vector3 = threat if threat.is_finite() and _flat(centre, threat) < 300.0 else Vector3.INF
			var slot_r := minf(BaseSim.reach_of(gb), 170.0) if not gb.is_empty() else fort_radius_m
			var posts := _defend_posts(sq, units, centre, dir, look, slot_r, gb.get("anchor", Vector3.INF))
			var covered := 0
			var forts := 0
			for p: Dictionary in posts:
				if p.protected:
					covered += 1
				if p.has("slot"):
					forts += 1
			var what := ("garrison %s" % gb.name) if not gb.is_empty() else "defend %s" % _xz(centre)
			return {"ok": true, "tactic": tactic, "target": centre, "dir": dir, "posts": posts, "commit": 10.0,
				"why": "%s: %d posts, %d in fortifications, %d with cover%s" % [what, posts.size(), forts, covered, "" if not threat.is_finite() else ", threat %s %.0f m" % [a.threat_src, _flat(centre, threat)]]}
		SquadState.Tactic.SUPPRESS:
			if not target.is_finite():
				return {"ok": false, "reason": "suppress needs a target position"}
			var d := _flat(c, target)
			if d > 300.0 and not extra.has("standoff"):
				return {"ok": false, "reason": "the target is %.0f m away, beyond rifle range for suppressive fire" % d}
			if float(a.ammo) < 0.25:
				return {"ok": false, "reason": "not enough ammunition left for suppressive fire (%.0f%%)" % (float(a.ammo) * 100.0)}
			var dir := _dir_to(c, target)
			var standoff: float = extra.get("standoff", 150.0)
			var from := c if d <= standoff + 40.0 else target - dir * standoff
			var posts := pos.find_posts(count, from, 28.0, target, {"mode": "fire", "los": target, "reserved": _reserved(sq, from), "avoid": _avoid_list(sq), "unit_id": uid, "min_enemy_m": 40.0})
			if posts.is_empty():
				return {"ok": false, "reason": "no firing position with a line to %s within rifle range" % _xz(target)}
			posts = pos.fill_open(posts, count, from, dir)
			return {"ok": true, "tactic": tactic, "target": target, "dir": dir, "posts": posts, "commit": 10.0,
				"why": "suppress %s from %d posts with a line of fire" % [_xz(target), posts.size()]}
		SquadState.Tactic.BOUND:
			if not target.is_finite():
				return {"ok": false, "reason": "bound needs a destination"}
			return {"ok": true, "tactic": tactic, "target": target, "dir": _dir_to(c, target), "commit": 6.0,
				"why": "move %.0f m by bounds: one fire team covers while the other moves" % _flat(c, target)}
		SquadState.Tactic.WITHDRAW:
			var f := target
			if not f.is_finite():
				f = _fallback_point(sq, a)
			if not f.is_finite():
				return {"ok": false, "reason": "no fallback position clear of known enemy"}
			return {"ok": true, "tactic": tactic, "target": f, "dir": _dir_to(c, f), "commit": 12.0,
				"why": "withdraw %.0f m to %s" % [_flat(c, f), _xz(f)]}
		SquadState.Tactic.ASSAULT, SquadState.Tactic.FLANK:
			if not target.is_finite():
				return {"ok": false, "reason": "%s needs a target position" % SquadState.TACTIC_NAMES[tactic].to_lower()}
			var d := _flat(c, target)
			if d < 12.0:
				return {"ok": false, "reason": "already at the target"}
			var dir := _dir_to(c, target)
			var want_flank := tactic == SquadState.Tactic.FLANK
			var report := ""
			var best := {}
			if sq.teams.size() >= 2 and d >= 70.0 and d <= 320.0 and not bool(extra.get("ext", false)) or want_flank and sq.teams.size() >= 2 and d >= 70.0 and d <= (460.0 if bool(extra.get("ext", false)) else 320.0):
				var frontal := pos.route_exposure([c, target], target)
				var plans: Array = []
				var rejected: Array[String] = []
				var man := _units(sq, 1)
				for side: int in [-1, 1]:
					var fp := pos.plan_flank(c, target, side, flank_lateral_m, man[0].id if not man.is_empty() else -1)
					if fp.ok:
						plans.append(fp)
					else:
						rejected.append(fp.reason)
				plans.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.exposure + (x.detour - 1.0) * 0.15 < y.exposure + (y.detour - 1.0) * 0.15)
				if not plans.is_empty():
					var p0: Dictionary = plans[0]
					var viable: bool = p0.detour <= flank_max_detour and p0.exposure <= 0.55 and (p0.exposure <= frontal - flank_gain or (want_flank and p0.exposure <= frontal + 0.05))
					if viable and (want_flank or frontal >= 0.4):
						best = p0
						report = "flank %s: exposure %d%% against %d%% straight in, %.0f m route (%.1fx the direct way)" % [p0.name, roundi(p0.exposure * 100.0), roundi(frontal * 100.0), p0.length, p0.detour]
					else:
						rejected.append("flank %s not worth it: exposure %d%% against %d%% straight in, detour %.1fx" % [p0.name, roundi(p0.exposure * 100.0), roundi(frontal * 100.0), p0.detour])
				if best.is_empty():
					report = "straight approach (" + ("; ".join(rejected) if not rejected.is_empty() else "exposure %d%%" % roundi(frontal * 100.0)) + ")"
			elif want_flank:
				return {"ok": false, "reason": "a flank needs two fire teams and 70-320 m to the target (%.0f m, %d team(s))" % [d, sq.teams.size()]}
			if want_flank and best.is_empty():
				return {"ok": false, "reason": "no safe flank: " + report}
			if not best.is_empty():
				var route := PackedVector3Array()
				for p: Vector3 in best.points:
					route.append(p)
				return {"ok": true, "tactic": SquadState.Tactic.FLANK, "target": target, "dir": dir, "route": route, "commit": 25.0, "why": report}
			return {"ok": true, "tactic": SquadState.Tactic.ASSAULT, "target": target, "dir": dir, "commit": 20.0,
				"why": report if report != "" else "assault %s, %.0f m" % [_xz(target), d]}
		SquadState.Tactic.REGROUP:
			return {"ok": true, "tactic": tactic, "target": c, "dir": Vector3.ZERO, "commit": 4.0, "why": "reassemble"}
		SquadState.Tactic.BUILD:
			var site := sim.state.construction.get_structure(int(extra.get("site", -1)))
			if site == null or not site.needs_work():
				return {"ok": false, "reason": "there is no construction site to build or structure to repair"}
			if site.faction != sq.faction:
				return {"ok": false, "reason": "that site belongs to another faction"}
			var posts := _work_posts(site, count, c)
			if posts.is_empty():
				return {"ok": false, "reason": "no free ground to work from round the site"}
			var def := StructureCatalog.get_def(site.type_id)
			var centre := site.site_center()
			return {"ok": true, "tactic": tactic, "target": centre, "dir": _dir_to(c, centre), "posts": posts, "commit": 4.0, "site": site.id,
				"why": "%s %s (%d%% done) from %d work posts" % ["build" if site.is_site() else "repair", def.display_name if def else String(site.type_id), roundi(site.work_progress() * 100.0), posts.size()]}
	return {"ok": false, "reason": "unknown tactic"}


## First moves of a tactic (posts and roles). Later steps happen in _run.
func _enter(sq: SquadState, a: Dictionary, plan: Dictionary) -> void:
	match sq.tactic:
		SquadState.Tactic.DEFEND:
			_set_roles(sq, SquadState.TeamRole.SUPPORT, SquadState.TeamRole.SECURITY)
			_send_posts(sq, _units(sq), plan.posts, sq.tactic_dir)
		SquadState.Tactic.SUPPRESS:
			_set_roles(sq, SquadState.TeamRole.SUPPORT, SquadState.TeamRole.SUPPORT)
			_send_posts(sq, _units(sq), plan.posts, sq.tactic_dir)
		SquadState.Tactic.BOUND, SquadState.Tactic.WITHDRAW, SquadState.Tactic.FLANK:
			_set_roles(sq, SquadState.TeamRole.SUPPORT, SquadState.TeamRole.MANEUVER)
		SquadState.Tactic.ASSAULT:
			_set_roles(sq, SquadState.TeamRole.SUPPORT, SquadState.TeamRole.ASSAULT)
		SquadState.Tactic.REGROUP:
			_set_roles(sq, SquadState.TeamRole.SECURITY, SquadState.TeamRole.SECURITY)
		SquadState.Tactic.BUILD:
			_set_roles(sq, SquadState.TeamRole.SECURITY, SquadState.TeamRole.SECURITY)
			_send_posts(sq, _units(sq), plan.posts, sq.tactic_dir)
	if sq.tactic == SquadState.Tactic.FLANK:
		# The support team sets up first; the maneuver team waits in cover where it is.
		_assault_support(sq, a, sq.tactic_target)


## A tactic is over. next: REGROUP to reassemble first, NONE to go straight back to the
## previous order.
func _finish(sq: SquadState, why: String, next: int) -> void:
	if sq.tactic == SquadState.Tactic.BUILD:
		_end_build(sq, why)
		return
	var old := sq.tactic
	finished[old] = int(finished.get(old, 0)) + 1
	_log(sq, "%s %s ended: %s" % [sq.squad_name, SquadState.TACTIC_NAMES[old].to_upper(), why])
	_clear_units(sq)
	sq.tactic_why = "%s ended: %s" % [SquadState.TACTIC_NAMES[old], why]
	sq.tactic_route = PackedVector3Array()
	sq.tactic_dest = Vector3.INF
	_set_meta(sq, "last_tactic", old)
	if next == SquadState.Tactic.REGROUP and sq.members.size() >= 2:
		var now := sim.state.time
		sq.tactic = SquadState.Tactic.REGROUP
		sq.tactic_phase = PH_SETUP
		sq.tactic_phase_since = now
		sq.tactic_commit_until = now + 3.0
		sq.tactic_target = _assess_squad(sq).center
		_set_roles(sq, SquadState.TeamRole.SECURITY, SquadState.TeamRole.SECURITY)
		return
	_restore(sq)


## Back to the order the squad had before its tactic: hold where it stands, or resume the move
## it was making.
func _restore(sq: SquadState) -> void:
	sq.tactic = SquadState.Tactic.NONE
	sq.tactic_cooldown_until = sim.state.time + 6.0
	var prev := sq.prev_order
	var target := sq.prev_target
	sq.tactic_owner = SquadState.Owner.NONE
	_internal = true
	if sq.order == SquadState.Order.TACTIC:
		if prev == SquadState.Order.MOVE and target.is_finite() and sq.op_id < 0 and _flat(_centroid(_units(sq)), target) > 25.0:
			sim.squads.order_move([sq.id], target)
		else:
			sim.squads.order_hold([sq.id])
	_internal = false
	sq.prev_order = SquadState.Order.NONE
	sim.state.squad_changed.emit(sq)


## A regroup order the tactics gave has finished: the squad takes up what it had before.
func _resume_previous(sq: SquadState) -> void:
	var prev := sq.prev_order
	var target := sq.prev_target
	sq.prev_order = SquadState.Order.NONE
	if prev == SquadState.Order.MOVE and target.is_finite() and sq.op_id < 0 and _flat(_centroid(_units(sq)), target) > 25.0:
		_internal = true
		sim.squads.order_move([sq.id], target)
		_internal = false


## Public: ends whatever tactic the squad has (the player cancels, a refusal, a test).
func cancel(sq: SquadState, why: String) -> void:
	if sq.tactic != SquadState.Tactic.NONE:
		_finish(sq, why, SquadState.Tactic.NONE)
	elif sq.order == SquadState.Order.TACTIC:
		_restore(sq)


## Called by SquadControl for every ordinary order (player, operation route): the tactic and its
## fire missions end at once - player > operation > squad tactic > reaction.
func on_order(sq: SquadState) -> void:
	if _internal:
		return
	# GAMEPLAY-01B: a new order replaces a march to a construction site.
	_set_meta(sq, "build_goal", null)
	# GAMEPLAY-04D: and a REARM search (SquadEquipment sets its own after the move it orders).
	sq.rearm_at = Vector3.INF
	# GAMEPLAY-01C: any other order ends a garrison assignment (the player's or an operation's: the squad is reassigned).
	if sq.garrison_base >= 0:
		var gb: Dictionary = sim.state.construction.bases.get(sq.garrison_base, {})
		if int(gb.get("objective", -2)) == sq.station_objective:
			sq.station_objective = -1
		sq.garrison_base = -1
	if sq.tactic == SquadState.Tactic.BUILD:
		# GAMEPLAY-01B: the player took the squad away from the site - it is not called back on its own for a while.
		_set_meta(sq, "no_build_until", sim.state.time + build_respect_s)
		var s := sim.state.construction.get_structure(sq.tactic_site)
		if s and s.needs_work():
			s.work_record()["why"] = "%s was given another order" % sq.squad_name
		sq.tactic_site = -1
		for u: UnitState in _units(sq):
			u.work_until = -1.0
	if sq.tactic != SquadState.Tactic.NONE:
		_log(sq, "%s %s cancelled by a new order" % [sq.squad_name, SquadState.TACTIC_NAMES[sq.tactic].to_upper()])
		finished[sq.tactic] = int(finished.get(sq.tactic, 0)) + 1
		_clear_units(sq)
		sq.tactic = SquadState.Tactic.NONE
		sq.tactic_owner = SquadState.Owner.NONE
		sq.tactic_route = PackedVector3Array()
		sq.tactic_dest = Vector3.INF
		sq.tactic_why = "cancelled by a new order"
	sq.prev_order = SquadState.Order.NONE
	if sq.order == SquadState.Order.TACTIC:
		sq.order = SquadState.Order.NONE


func _clear_units(sq: SquadState) -> void:
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u:
			u.fire_at = Vector3.INF
			u.fire_until = -1.0
			u.post_pos = Vector3.INF
			sim.state.leave_fort(u)


# --- Public orders (player and operations) ----------------------------------------------------------

## A tactical order for squads: {ok, n, results: [{squad, name, ok, reason}], text}. Several squads
## stand side by side when given one target. The player's order releases the squads from their
## operations.
func order_tactic(squad_ids: Array, tactic: int, target := Vector3.INF, owner := SquadState.Owner.PLAYER) -> Dictionary:
	var results: Array = []
	var ok_n := 0
	var sqs: Array = []
	for id in squad_ids:
		var sq := sim.state.get_squad(id)
		if sq:
			sqs.append(sq)
	var centre := Vector3.ZERO
	for sq: SquadState in sqs:
		centre += _centroid(_units(sq))
	if not sqs.is_empty():
		centre /= sqs.size()
	var dir := _dir_to(centre, target) if target.is_finite() else Vector3.FORWARD
	var right := Vector3(dir.z, 0.0, -dir.x)
	for i in sqs.size():
		var sq: SquadState = sqs[i]
		var tgt := target
		if target.is_finite() and sqs.size() > 1:
			tgt = pos.nearest_valid(target + right * (i - (sqs.size() - 1) * 0.5) * 16.0, 10.0)
			if not tgt.is_finite():
				tgt = target
		if owner == SquadState.Owner.PLAYER:
			sim.war.release_squads([sq.id], "player tactical order")
		var res := start(sq, tactic, owner, tgt, _contact_at(sq, tgt), "")
		results.append({"squad": sq.id, "name": sq.squad_name, "ok": res.ok, "reason": res.reason})
		if res.ok:
			ok_n += 1
	var parts: Array[String] = []
	for r: Dictionary in results:
		parts.append("%s: %s" % [r.name, ("%s accepted" % SquadState.TACTIC_NAMES[tactic].to_upper()) if r.ok else ("cannot - " + str(r.reason))])
	return {"ok": ok_n > 0, "n": ok_n, "results": results, "text": " | ".join(parts)}


## An operation tasks a squad with a tactic against a position (a held objective). {ok, reason}.
func assign_for_operation(sq: SquadState, tactic: int, target: Vector3, why: String, extra := {}) -> Dictionary:
	if sq.tactic == tactic and sq.tactic_owner == SquadState.Owner.OPERATION:
		return {"ok": true, "reason": "already tasked"}
	return start(sq, tactic, SquadState.Owner.OPERATION, target, _contact_at(sq, target), why, extra)


## The faction contact that explains a target position (within its uncertainty), or -1.
func _contact_at(sq: SquadState, p: Vector3) -> int:
	if not p.is_finite() or sim.war == null or not sim.war.enabled:
		return -1
	for c: ContactState in sim.war.intel.contacts_near(sq.faction, p, 60.0):
		if _flat(c.pos, p) <= 40.0 + 0.5 * c.unc and c.status != ContactState.Status.LOST:
			return c.id
	return -1


# --- Running tactics ------------------------------------------------------------------------------------

func _run(sq: SquadState, a: Dictionary) -> void:
	var now := sim.state.time
	if sq.tactic_owner == SquadState.Owner.OPERATION and sq.tactic_op >= 0:
		var op := sim.state.war.operation(sq.tactic_op)
		if op == null or not op.is_active() or sq.op_id != sq.tactic_op:
			_finish(sq, "the operation ended", SquadState.Tactic.NONE)
			return
	if int(a.n) == 0:
		return
	_face_all(sq, a)
	_tend_forts(sq, a, now)
	match sq.tactic:
		SquadState.Tactic.DEFEND:
			_run_defend(sq, a, now)
		SquadState.Tactic.REPOSITION:
			_run_reposition(sq, a, now)
		SquadState.Tactic.SUPPRESS:
			_run_suppress(sq, a, now)
		SquadState.Tactic.BOUND:
			_run_bound(sq, a, now, false)
		SquadState.Tactic.WITHDRAW:
			_run_bound(sq, a, now, true)
		SquadState.Tactic.ASSAULT:
			_run_assault(sq, a, now)
		SquadState.Tactic.FLANK:
			_run_flank(sq, a, now)
		SquadState.Tactic.REGROUP:
			_run_regroup(sq, a, now)
		SquadState.Tactic.BUILD:
			_run_build(sq, a, now)


# --- BUILD (GAMEPLAY-01B) ----------------------------------------------------------------------------------------------
# The soldiers walk to work posts round a construction site (ordinary move orders to UnitState.post_pos) and every soldier
# standing at his post, not under fire and not reacting adds tick seconds of work to the site record
# (ConstructionState.add_work). The same step runs for bodies and the abstract tier, so a site is built in the same
# time wherever the camera is. Contact ends a squad-owned BUILD (the squad defends itself, the progress stays); a player
# ordered BUILD pauses until it is quiet again. Any player order ends it (on_order).

## Player squads only, in the scenarios with build sites, when nobody commands them: no operation, no garrison, no other
## tactic, not marching, idle (no order or an arrived move; never HOLD, a deliberate instruction) and not just taken off
## a site by the player.
func build_eligible(sq: SquadState, ignore_cooldown := false) -> bool:
	var war := sim.state.war
	if not war.active or sq.faction != war.player_faction or not bool(war.rule("build_sites", false)):
		return false
	if sq.members.is_empty() or sq.op_id >= 0 or sq.station_objective >= 0 or sq.garrison_base >= 0 or sq.tactic != SquadState.Tactic.NONE or _aboard(sq):
		return false
	if sim.squads.marching(sq):
		return false
	var now := sim.state.time
	if (now < sq.tactic_cooldown_until and not ignore_cooldown) or now < float(_meta(sq, "no_build_until", 0.0)):
		return false
	match sq.order:
		SquadState.Order.NONE:
			return true
		SquadState.Order.MOVE:
			return sq.status != SquadState.Status.MOVING
	return false


## Starts BUILD on a site, or - for a squad more than 120 m away - first marches it there with an ordinary squad move (the
## route system: roads, bridges, terrain) and starts BUILD when it has arrived (_auto_build). {ok, reason, marching}.
func send_to_build(sq: SquadState, site: StructureState, owner: int) -> Dictionary:
	var c := _centroid(_units(sq))
	var centre := site.site_center()
	if _flat(c, centre) > 120.0:
		var goal := pos.nearest_valid(centre + _dir_to(centre, c) * 22.0, 30.0)
		sim.squads.order_move([sq.id], goal if goal.is_finite() else centre)
		_set_meta(sq, "build_goal", [site.id, owner])
		_log(sq, "%s marches %.0f m to build site #%d" % [sq.squad_name, _flat(c, centre), site.id])
		site.work_record()["why"] = "%s on the way (%.0f m)" % [sq.squad_name, _flat(c, centre)]
		return {"ok": true, "reason": "", "marching": true}
	var res := start(sq, SquadState.Tactic.BUILD, owner, centre, -1, "", {"site": site.id})
	res["marching"] = false
	return res


## An idle squad takes up the nearest site of its faction within radius that needs work and was not found unreachable;
## a squad that marched to a site to build it (send_to_build) takes up that site first.
func _auto_build(sq: SquadState, from: Vector3, radius: float) -> bool:
	if not build_eligible(sq):
		return false
	var goal: Variant = _meta(sq, "build_goal", null)
	if goal is Array:
		_set_meta(sq, "build_goal", null)
		var gs := sim.state.construction.get_structure(int(goal[0]))
		if gs and gs.needs_work():
			if _flat(from, gs.site_center()) <= radius:
				return bool(start(sq, SquadState.Tactic.BUILD, int(goal[1]), gs.site_center(), -1, "", {"site": gs.id}).ok)
			gs.work_record()["why"] = "%s could not get there" % sq.squad_name
	var best: StructureState = null
	var best_d := radius
	var now := sim.state.time
	for s: StructureState in sim.state.construction.all():
		if not s.needs_work() or s.faction != sq.faction or float(s.work_record().get("crew", 0.0)) > 0.0 or float(_site_block.get(s.id, 0.0)) > now:
			continue
		var d := _flat(from, s.site_center())
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		return false
	return bool(start(sq, SquadState.Tactic.BUILD, SquadState.Owner.SQUAD, best.site_center(), -1, "", {"site": best.id}).ok)


## A site was placed: the nearest idle squad of its faction within build_assign_m goes to build it. Returns the squad or null.
func assign_builders(site: StructureState) -> SquadState:
	var c := site.site_center()
	var sqs := sim.state.all_squads().filter(func(s: SquadState) -> bool: return s.faction == site.faction and build_eligible(s, true))
	sqs.sort_custom(func(a: SquadState, b: SquadState) -> bool: return _flat(_centroid(_units(a)), c) < _flat(_centroid(_units(b)), c))
	for sq: SquadState in sqs:
		if _flat(_centroid(_units(sq)), c) > build_assign_m:
			break
		if send_to_build(sq, site, SquadState.Owner.SQUAD).ok:
			return sq
	return null


## The player orders squads to build a site (right-click on it, or the site panel). Releases them from operations;
## {ok, n, text} like order_tactic.
func order_build(squad_ids: Array, site_id: int) -> Dictionary:
	var parts: Array[String] = []
	var n := 0
	for id in squad_ids:
		var sq := sim.state.get_squad(id)
		if sq == null:
			continue
		sim.war.release_squads([sq.id], "player build order")
		var site := sim.state.construction.get_structure(site_id)
		if site == null or not site.needs_work():
			parts.append("%s: cannot - there is no construction site or repair there" % sq.squad_name)
			continue
		var res := send_to_build(sq, site, SquadState.Owner.PLAYER)
		parts.append("%s: %s" % [sq.squad_name, ("marching to the site, then BUILD" if res.marching else "BUILD accepted") if res.ok else "cannot - " + str(res.reason)])
		if res.ok:
			n += 1
	return {"ok": n > 0, "n": n, "text": " | ".join(parts)}


func _run_build(sq: SquadState, a: Dictionary, now: float) -> void:
	var cs := sim.state.construction
	var s := cs.get_structure(sq.tactic_site)
	if s == null or not s.needs_work():
		_end_build(sq, "the work is finished" if s != null else "the site is gone")
		return
	if a.in_contact or int(a.under_fire) > 0:
		s.work_record()["why"] = "work stopped: enemy contact"
		for u: UnitState in _units(sq):
			u.work_until = -1.0
		if sq.tactic_owner != SquadState.Owner.PLAYER:
			_set_meta(sq, "no_build_until", now + 30.0)
			_end_build(sq, "enemy contact: work stopped, progress kept")
		return
	var centre := s.site_center()
	var working := 0
	var arrived := 0
	for u: UnitState in _units(sq):
		if not u.post_pos.is_finite():
			continue
		if _flat(u.position, u.post_pos) <= 3.0:
			arrived += 1
			if u.suppression_at(now) < 0.3 and u.under_fire_until < now and not u.is_reacting():
				working += 1
				u.work_until = now + tick_s * 2.5
				if u.order != UnitState.Order.MOVE:
					sim.brain._watch(u, centre, 1.5)
		elif u.order != UnitState.Order.MOVE and not u.is_reacting() and now - float(_meta(sq, "resend_%d" % u.id, -100.0)) > 8.0:
			# Pushed off the post (a reaction, a crowd): back to it, the post stays.
			_set_meta(sq, "resend_%d" % u.id, now)
			var post := u.post_pos
			sim.state.issue_move(u.id, post, false)
			u.post_pos = post
	if working > 0:
		_site_workers[s.id] = int(_site_workers.get(s.id, 0)) + working
		s.work_record()["why"] = ""
		sq.tactic_phase = PH_HOLD
		var def := StructureCatalog.get_def(s.type_id)
		var what := def.display_name if def else String(s.type_id)
		var repairing := not s.is_site()
		if cs.add_work(s, working * _dt):
			_log(sq, "%s finished %s" % [sq.squad_name, what])
			if sim.war:
				sim.war.log_event(sq.faction, "build_done", "%s %s by %s" % [what, "repaired" if repairing else "completed", sq.squad_name], centre)
			_end_build(sq, "%s %s" % [what, "repaired" if repairing else "finished"])
		return
	if arrived == 0 and now - sq.tactic_since > 90.0:
		s.work_record()["why"] = "the workers cannot reach the site"
		_site_block[s.id] = now + 60.0
		_end_build(sq, "could not reach the site")
	elif arrived == 0:
		s.work_record()["why"] = "%s on the way" % sq.squad_name


## BUILD is over: the soldiers stand where they are, the squad is idle (no order) and may take up the next site.
func _end_build(sq: SquadState, why: String) -> void:
	finished[SquadState.Tactic.BUILD] = int(finished.get(SquadState.Tactic.BUILD, 0)) + 1
	_log(sq, "%s BUILD ended: %s" % [sq.squad_name, why])
	_clear_units(sq)
	sq.tactic_why = "Build ended: %s" % why
	sq.tactic = SquadState.Tactic.NONE
	sq.tactic_owner = SquadState.Owner.NONE
	sq.tactic_site = -1
	sq.prev_order = SquadState.Order.NONE
	sq.tactic_cooldown_until = sim.state.time + 2.0
	_next_build[sq.id] = sim.state.time + 2.0
	if sq.order == SquadState.Order.TACTIC:
		sq.order = SquadState.Order.NONE
		sq.status = SquadState.Status.IDLE
	for u: UnitState in _units(sq):
		u.work_until = -1.0
		if u.order == UnitState.Order.MOVE:
			sim.state.halt(u.id)
	sim.state.squad_changed.emit(sq)


## Work posts round a site: points on a ring 1.4 m outside each building footprint (every 2.2 m) or both sides of each
## line module, plus a second ring further out; only valid ground (dry, walkable, not inside a structure, on the route
## grid), at least 1.8 m apart, nearest to the squad first. Exactly `count` posts (the last ones doubled up close by when
## the ground offers fewer), or [] when there is no valid ground at all.
func _work_posts(site: StructureState, count: int, from: Vector3) -> Array:
	var def := StructureCatalog.get_def(site.type_id)
	if def == null or count <= 0:
		return []
	var b := def.bounds()
	var cands: Array[Vector3] = []
	for i in site.instances.size():
		if site.is_line() and site.is_removed(i):
			continue
		var xf: Transform3D = site.instances[i]
		for ring: float in [1.4, 3.9]:
			if site.is_line():
				var cx := b.get_center().x
				for z: float in [b.position.z - ring, b.end.z + ring]:
					cands.append(xf * Vector3(cx, 0.0, z))
				continue
			var x0 := b.position.x - ring
			var x1 := b.end.x + ring
			var z0 := b.position.z - ring
			var z1 := b.end.z + ring
			for edge: Array in [[Vector3(x0, 0, z0), Vector3(x1, 0, z0)], [Vector3(x1, 0, z0), Vector3(x1, 0, z1)],
					[Vector3(x1, 0, z1), Vector3(x0, 0, z1)], [Vector3(x0, 0, z1), Vector3(x0, 0, z0)]]:
				var p0: Vector3 = edge[0]
				var p1: Vector3 = edge[1]
				var n := maxi(1, floori(p0.distance_to(p1) / 2.2))
				for k in n:
					cands.append(xf * p0.lerp(p1, (k + 0.5) / n))
	cands.sort_custom(func(p: Vector3, q: Vector3) -> bool: return _flat(p, from) < _flat(q, from))
	var out: Array = []
	for p in cands:
		if out.size() >= count:
			break
		var g := pos.ground(p)
		if not pos.valid_ground(g):
			continue
		var crowded := false
		for o: Dictionary in out:
			if _flat(o.p, g) < 1.8:
				crowded = true
				break
		if not crowded:
			out.append({"p": g, "protected": false})
	if out.is_empty():
		return []
	var k := 0
	while out.size() < count:
		var q: Vector3 = out[k % out.size()].p + Vector3(0.9 * (1 + k / out.size()), 0.0, 0.6)
		out.append({"p": pos.ground(q), "protected": false})
		k += 1
	return out


# --- Fortifications and GARRISON_BASE (GAMEPLAY-01C) ---------------------------------------------------------------------
# A defence first fills the free fortification slots near its spot (SquadPositions.fort_slots: towers, fighting positions,
# MG emplacements, walls), the rest of the squad takes natural cover there as before. A soldier walks to his slot's
# access point and then takes the slot (UnitState.fort_pos): both tiers hold him exactly there, a tower platform included.
# A garrison is the squad-level order GARRISON_BASE (SquadState.garrison_base): march to a friendly base and defend it from
# its fortifications until given another order; re-manned after every fight, cleared when the base is lost.

## Posts for a defence at `centre`: free fortification slots within slot_r (spread round the base when no threat is known),
## then firing / cover posts within nat_r for the soldiers left over.
## GAMEPLAY-03A: posts of a defence, fortification slots and natural cover judged on one scale against the believed
## threat (`look`): protection (it stops bullets from there), a line of fire, concealment (SquadPositions.exposure: seen from
## fewer of the believed viewpoints is better), sector (a slot facing the threat), a prepared position's value, distance
## from the defended spot. A poor slot - facing away, or a tower in plain view of the whole approach - can lose to a hedge
## nearby. Without a believed threat the slots are spread round the centre as before (nothing to hide from yet).
var post_w := {"protect": 3.0, "fire": 2.0, "conceal": 2.5, "prepared": 1.0, "sector": 1.0, "elevated": 0.4, "dist_slot": 0.008, "dist_nat": 0.04, "mg_slot": 2.0}
## Candidates whose exposure is measured, per post needed (the rest are judged without it: bounded sight checks).
var post_exposure_per := 2
var fallbacks := 0
var support_fort_targets := 0
var _fort_contact := {}
## Weapon modifiers when posts are handed out (configurable): the machine gunner values a wide arc and low exposure, the
## grenadier moves to a more concealed post only when it is clearly better.
var role_post_w := {"mg_arc": 1.0, "mg_exposure": 2.0, "grenadier_margin": 0.2}


func _defend_posts(sq: SquadState, units: Array, centre: Vector3, dir: Vector3, look: Vector3, slot_r: float, base_anchor := Vector3.INF, nat_r := 16.0) -> Array:
	var count := units.size()
	var mine := {}
	for u: UnitState in units:
		mine[u.id] = true
	var threat := centre + dir * 90.0 if look.is_finite() else Vector3.INF
	var slots := pos.fort_slots(centre, slot_r, sq.faction, threat, mine, base_anchor, 0.008 if base_anchor.is_finite() else 0.06)
	if look.is_finite():
		_set_meta(sq, "planned_blind", false)
		return _judged_posts(sq, units, centre, dir, look, slots, base_anchor, nat_r)
	_set_meta(sq, "planned_blind", true)
	slots = slots.filter(func(e: Dictionary) -> bool: return _inside_limit(sq, e.p))
	var posts: Array = []
	if not look.is_finite() and slots.size() > count:
		# No threat known: the slots that cover the most different directions round the centre.
		var left := slots.duplicate()
		while posts.size() < count and not left.is_empty():
			var best := 0
			var best_sc := -INF
			for i in left.size():
				var e: Dictionary = left[i]
				var sep := PI
				for q: Dictionary in posts:
					sep = minf(sep, absf(angle_difference(_bearing(centre, e.p), _bearing(centre, q.p))))
				var sc := sep + float(e.score) * 0.2 + (0.15 if bool(e.elevated) else 0.0)
				if sc > best_sc:
					best_sc = sc
					best = i
			posts.append(left[best])
			left.remove_at(best)
	else:
		posts = slots.slice(0, count)
	var need := count - posts.size()
	if need > 0:
		var uid: int = units[0].id
		var nat := pos.find_posts(need, centre, nat_r, centre + dir * 90.0, {"mode": "fire", "los": look, "reserved": _reserved(sq, centre) + posts.map(func(e: Dictionary) -> Vector3: return e.p), "avoid": _avoid_list(sq), "unit_id": uid})
		if nat.size() < need:
			nat = pos.find_posts(need, centre, nat_r, centre + dir * 90.0, {"mode": "cover", "reserved": _reserved(sq, centre), "avoid": _avoid_list(sq), "unit_id": uid})
		posts.append_array(nat.filter(func(e: Dictionary) -> bool: return _inside_limit(sq, e.p)).slice(0, need))
		posts = pos.fill_open(posts, count, centre, dir)
	return posts


## GAMEPLAY-04G: a defence plan judges its posts against the threat (~5 ms each); squads that choose DEFEND / REPOSITION on
## their own (_consider, a garrison taking up its posts) start at most defence_plans_per_step of them per step, the rest one
## step (tick_s) later - several squads alerted at once no longer plan in one frame. The player's and the operations' orders
## are never deferred.
var defence_plans_per_step := 1
var _deferrable := false
var _defence_starts := 0
var deferred := 0
## GAMEPLAY-04G: measured - the judged post plans of one step and their cost (the GAMEPLAY-03 DEFEND planning spike).
var plans_tick := 0
var plans_tick_max := 0
var plan_usec_max := 0
var plan_tick_usec := 0
var plan_tick_usec_max := 0


func _judged_posts(sq: SquadState, units: Array, centre: Vector3, dir: Vector3, look: Vector3, slots: Array, base_anchor: Vector3, nat_r: float) -> Array:
	var t0 := Time.get_ticks_usec()
	var out := _judged_posts_run(sq, units, centre, dir, look, slots, base_anchor, nat_r)
	var dt := Time.get_ticks_usec() - t0
	plans_tick += 1
	plan_tick_usec += dt
	plan_usec_max = maxi(plan_usec_max, dt)
	return out


func _judged_posts_run(sq: SquadState, units: Array, centre: Vector3, dir: Vector3, look: Vector3, slots: Array, base_anchor: Vector3, nat_r: float) -> Array:
	var count := units.size()
	var w := post_w
	var uid: int = units[0].id
	# Posts other soldiers of the squad keep (a partial reposition) are not offered again.
	var reserved: Array = _reserved(sq, centre) + (_meta(sq, "keep_posts", []) as Array)
	var nat := pos.find_posts(count + 4, centre, nat_r, centre + dir * 90.0, {"mode": "fire", "los": look, "reserved": reserved, "avoid": _avoid_list(sq), "unit_id": uid})
	if nat.size() < count:
		nat.append_array(pos.find_posts(count, centre, nat_r, centre + dir * 90.0, {"mode": "cover", "reserved": reserved, "avoid": _avoid_list(sq), "unit_id": uid}))
	var cands: Array = []
	var has_mg := units.any(func(u: UnitState) -> bool: return _is_mg(u))
	# GAMEPLAY-03B: inside the defended area only, and when falling back only behind the line it leaves.
	var behind: Dictionary = _meta(sq, "behind", {})
	var keep_in := func(e: Dictionary) -> bool:
		if not _inside_limit(sq, e.p):
			return false
		return behind.is_empty() or ((e.p as Vector3) - (behind.c as Vector3)).dot(behind.d) <= float(behind.max)
	slots = slots.filter(keep_in)
	nat = nat.filter(keep_in)
	for e: Dictionary in slots:
		var sector := maxf((e.facing as Vector3).dot(_dir_to(e.p, look)), 0.0)
		e["pre"] = w.protect + w.fire + w.prepared + w.sector * sector + (w.elevated if bool(e.elevated) else 0.0) - w.dist_slot * _flat(e.p, centre)
		# A machine-gun slot is worth most to a squad that has the gun for it.
		if has_mg and String(e.get("role", "")) == "mg":
			e["pre"] = float(e.pre) + w.mg_slot
		cands.append(e)
	for e: Dictionary in nat:
		e["pre"] = (w.protect if bool(e.get("protected", false)) else 0.0) + (w.fire if bool(e.get("can_fire", false)) and bool(e.get("los", true)) else 0.0) \
				- w.dist_nat * _flat(e.p, centre)
		cands.append(e)
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.pre) > float(y.pre))
	var top := cands.slice(0, count * post_exposure_per)
	for e: Dictionary in top:
		var ex := pos.exposure(e.p, look)
		e["exposure"] = ex
		e["score"] = float(e.pre) + w.conceal * (1.0 - ex)
	top.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.score) > float(y.score))
	var posts: Array = []
	for e: Dictionary in top:
		if posts.size() >= count:
			break
		var clash := false
		if not e.has("slot"):
			for o: Dictionary in posts:
				if _flat(o.p, e.p) < pos.post_spacing_m:
					clash = true
					break
		if not clash:
			posts.append(e)
	if posts.size() < count:
		posts = pos.fill_open(posts, count, centre, dir)
	_set_meta(sq, "posts_judged", {"n": posts.size(), "slots": posts.filter(func(e: Dictionary) -> bool: return e.has("slot")).size(),
		"exposure": snappedf(posts.reduce(func(acc: float, e: Dictionary) -> float: return acc + float(e.get("exposure", 1.0)), 0.0) / maxf(posts.size(), 1), 0.01),
		"candidates": top.size(), "cand_slots": top.filter(func(e: Dictionary) -> bool: return e.has("slot")).size(),
		"cand_exposure": snappedf(top.reduce(func(acc: float, e: Dictionary) -> float: return acc + float(e.get("exposure", 1.0)), 0.0) / maxf(top.size(), 1), 0.01)})
	return posts


static func _bearing(from: Vector3, to: Vector3) -> float:
	return atan2(to.z - from.z, to.x - from.x)


## The MG slot goes to an MG-armed soldier when the squad has one. GAMEPLAY-02D: without an MG slot among the posts, the
## machine gunner takes the post with the best field of fire towards the threat (its score, height, and how far forward
## it lies) - the gun that suppresses belongs where it sees the most.
func _mg_first(units: Array, posts: Array, idx: Array, dir := Vector3.ZERO) -> void:
	var has_slot := false
	for p: Dictionary in posts:
		has_slot = has_slot or String(p.get("role", "")) == "mg"
	if not has_slot:
		_mg_best_post(units, posts, idx, dir)
		_marksman_post(units, posts, idx)
		return
	for i in units.size():
		var post: Dictionary = posts[idx[i]]
		if String(post.get("role", "")) != "mg" or _is_mg(units[i]):
			continue
		for j in units.size():
			if j != i and _is_mg(units[j]):
				var t: int = idx[i]
				idx[i] = idx[j]
				idx[j] = t
				break


func _mg_best_post(units: Array, posts: Array, idx: Array, dir: Vector3) -> void:
	var gunner := -1
	for i in units.size():
		if _is_mg(units[i]):
			gunner = i
			break
	if gunner < 0 or units.size() < 2:
		return
	var c := Vector3.ZERO
	for p: Dictionary in posts:
		c += p.p
	c /= maxf(posts.size(), 1)
	var best_i := gunner
	var best_sc := -INF
	for i in units.size():
		var p: Dictionary = posts[idx[i]]
		var sc := float(p.get("score", 0.0)) + (0.5 if bool(p.get("elevated", false)) else 0.0)
		# GAMEPLAY-03A: the gun wants a wide arc and not to be seen first (posts judged against a threat carry exposure).
		sc += role_post_w.mg_arc * float(p.get("arc", 150.0)) / 180.0 - role_post_w.mg_exposure * float(p.get("exposure", 0.5))
		if dir.length() > 0.1:
			sc += 0.03 * (p.p as Vector3 - c).dot(dir)
		if sc > best_sc:
			best_sc = sc
			best_i = i
	if best_i != gunner:
		var t: int = idx[gunner]
		idx[gunner] = idx[best_i]
		idx[best_i] = t
	_grenadier_post(units, posts, idx, gunner)


## GAMEPLAY-03A: the grenadier (launcher, grenades: a few precious shots) takes the most concealed of the other posts.
func _grenadier_post(units: Array, posts: Array, idx: Array, gunner: int) -> void:
	var g := -1
	for i in units.size():
		if i != gunner and (units[i] as UnitState).sec_id != &"":
			g = i
			break
	if g < 0:
		return
	var best_i := g
	var best_ex: float = float((posts[idx[g]] as Dictionary).get("exposure", 0.5)) - float(role_post_w.grenadier_margin)
	for i in units.size():
		if i == gunner or i == g:
			continue
		var ex := float((posts[idx[i]] as Dictionary).get("exposure", 0.5))
		if ex < best_ex:
			best_ex = ex
			best_i = i
	if best_i != g:
		var t: int = idx[g]
		idx[g] = idx[best_i]
		idx[best_i] = t


## GAMEPLAY-02B: the soldier carries a machine gun (WeaponDef.role lmg).
## GAMEPLAY-04C: the designated marksman (a dmr-role weapon) takes the remaining post that sees farthest - elevated, the
## widest arc, the least exposed - instead of whatever post its place in the squad gave it. MG and grenadier keep theirs.
func _marksman_post(units: Array, posts: Array, idx: Array) -> void:
	var m := -1
	for i in units.size():
		var def := sim.combat.weapon((units[i] as UnitState).weapon_id)
		if def and def.role == &"dmr":
			m = i
			break
	if m < 0 or units.size() < 2:
		return
	var best_i := m
	var best_sc := -INF
	for i in units.size():
		if i != m and (_is_mg(units[i]) or (units[i] as UnitState).sec_id != &""):
			continue
		var p: Dictionary = posts[idx[i]]
		var sc := (1.0 if bool(p.get("elevated", false)) else 0.0) + float(p.get("arc", 150.0)) / 180.0 - float(p.get("exposure", 0.5)) + 0.3 * float(p.get("score", 0.0))
		if sc > best_sc:
			best_sc = sc
			best_i = i
	if best_i != m:
		var t: int = idx[m]
		idx[m] = idx[best_i]
		idx[best_i] = t


func _is_mg(u: UnitState) -> bool:
	var def := sim.combat.weapon(u.weapon_id)
	return def != null and def.role == &"lmg"


## Every tactic step: soldiers sent to a fortification slot take it once they stand at its access point (and are not walking
## or reacting); a soldier pushed away walks back; a slot that can no longer be used (structure destroyed, disabled,
## captured) is given up, and a defence then looks for posts again.
func _tend_forts(sq: SquadState, a: Dictionary, now: float) -> void:
	var lost := false
	for u: UnitState in _units(sq):
		if u.fort_slot == "":
			continue
		var e := pos.slot_by_key(u.fort_slot, sq.faction)
		if e.is_empty():
			_log(sq, "%s leaves %s: the position can no longer be used" % [u.unit_name, u.fort_slot])
			sim.state.leave_fort(u)
			u.post_pos = Vector3.INF
			lost = true
			continue
		if u.fort_pos.is_finite() or u.order == UnitState.Order.MOVE or u.is_reacting():
			continue
		var acc: Vector3 = e.access
		if _flat(u.position, acc) <= 2.5 or _flat(u.position, e.p) <= 1.5:
			u.fort_exit = acc
			u.fort_pos = e.p
			u.position = e.p
			u.anchor_pos = e.p
			u.velocity = Vector3.ZERO
			sim.brain._watch(u, e.p + (e.facing as Vector3) * 30.0, 3.0)
		elif now - float(_meta(sq, "fort_resend_%d" % u.id, -100.0)) > 8.0:
			_set_meta(sq, "fort_resend_%d" % u.id, now)
			var key := u.fort_slot
			var post := u.post_pos
			sim.state.issue_move(u.id, acc, false)
			u.fort_slot = key
			u.post_pos = post
	if lost and (sq.tactic == SquadState.Tactic.DEFEND or sq.tactic == SquadState.Tactic.REPOSITION):
		_reposition(sq, a, "a fortification was lost", now)


## The player assigns squads to a friendly base (RTS command, map, facility panel). Releases them from operations;
## {ok, n, text} like order_tactic.
func order_garrison(squad_ids: Array, base_id: int) -> Dictionary:
	var parts: Array[String] = []
	var n := 0
	var b: Dictionary = sim.state.construction.bases.get(base_id, {})
	for id in squad_ids:
		var sq := sim.state.get_squad(id)
		if sq == null:
			continue
		if b.is_empty() or int(b.faction) != sq.faction:
			parts.append("%s: cannot - that is not one of your bases" % sq.squad_name)
			continue
		sim.war.release_squads([sq.id], "player garrison order")
		var res := assign_garrison(sq, base_id, SquadState.Owner.PLAYER)
		parts.append("%s: %s" % [sq.squad_name, ("garrisons %s" % b.name) if res.ok else "cannot - " + str(res.reason)])
		if res.ok:
			n += 1
	return {"ok": n > 0, "n": n, "text": " | ".join(parts)}


## Assigns one squad to hold a base (player or faction AI). The squad leaves what it did (an ordinary order), then
## _garrison_step marches it there and mans the fortifications. {ok, reason}.
func assign_garrison(sq: SquadState, base_id: int, owner: int) -> Dictionary:
	var b: Dictionary = sim.state.construction.bases.get(base_id, {})
	if b.is_empty() or int(b.faction) != sq.faction:
		return {"ok": false, "reason": "no friendly base"}
	if _aboard(sq):
		return {"ok": false, "reason": "the squad is aboard a vehicle"}
	if owner == SquadState.Owner.PLAYER:
		on_order(sq)
		_clear_units(sq)
		sq.tactic = SquadState.Tactic.NONE
		sq.tactic_owner = SquadState.Owner.NONE
	sq.garrison_base = base_id
	var obj: int = int(b.get("objective", -1))
	if obj >= 0:
		sq.station_objective = obj
	sq.tactic_cooldown_until = 0.0
	# Several squads assigned at once plan in different steps (a plan is a slot search: spread the cost).
	_next_garrison[sq.id] = sim.state.time + float(sq.id % 4) * tick_s
	_log(sq, "%s assigned to garrison %s" % [sq.squad_name, b.name])
	if sim.war and sim.war.enabled:
		sim.war.log_event(sq.faction, "garrison", "%s garrisons %s" % [sq.squad_name, b.name], b.anchor)
	sim.state.squad_changed.emit(sq)
	return {"ok": true, "reason": ""}


## Ends a squad's garrison assignment (the player's cancel, a lost base). The squad stays where it is.
func clear_garrison(sq: SquadState, why: String) -> void:
	if sq.garrison_base < 0:
		return
	var b: Dictionary = sim.state.construction.bases.get(sq.garrison_base, {})
	if int(b.get("objective", -2)) == sq.station_objective:
		sq.station_objective = -1
	sq.garrison_base = -1
	_log(sq, "%s garrison ended: %s" % [sq.squad_name, why])
	if sq.tactic == SquadState.Tactic.DEFEND or sq.tactic == SquadState.Tactic.REPOSITION:
		_finish(sq, "garrison ended: " + why, SquadState.Tactic.NONE)
	sim.state.squad_changed.emit(sq)


## A garrisoned squad that is not defending its base goes back to it: march when it is away, else DEFEND at the base
## (the player's squads under the player's authority, an AI faction's under the squad's own).
func _garrison_step(sq: SquadState, a: Dictionary, now: float) -> void:
	if now < float(_next_garrison.get(sq.id, 0.0)):
		return
	_next_garrison[sq.id] = now + garrison_check_s
	var b: Dictionary = sim.state.construction.bases.get(sq.garrison_base, {})
	if b.is_empty() or int(b.faction) != sq.faction:
		clear_garrison(sq, "the base was lost" if not b.is_empty() else "the base no longer exists")
		return
	if sq.op_id >= 0:
		return
	if sim.squads.marching(sq) or (sq.order == SquadState.Order.MOVE and sq.status == SquadState.Status.MOVING):
		return
	if now < sq.tactic_cooldown_until and not a.in_contact:
		return
	var anchor: Vector3 = b.anchor
	var reach := minf(BaseSim.reach_of(b), 170.0)
	var owner := SquadState.Owner.PLAYER if sq.faction == sim.state.war.player_faction else SquadState.Owner.SQUAD
	if _flat(a.center, anchor) > reach + 30.0:
		var goal := pos.nearest_valid(anchor, 30.0)
		_internal = true
		sim.squads.order_move([sq.id], goal if goal.is_finite() else anchor)
		_internal = false
		_log(sq, "%s marches %.0f m to garrison %s" % [sq.squad_name, _flat(a.center, anchor), b.name])
		return
	_deferrable = owner != SquadState.Owner.PLAYER
	var res := start(sq, SquadState.Tactic.DEFEND, owner, anchor, -1, "", {"garrison": sq.garrison_base})
	_deferrable = false
	if not res.ok and not res.get("deferred", false):
		sq.tactic_rejected = "garrison: " + str(res.reason)


# --- DEFEND / REPOSITION -------------------------------------------------------------------------------

func _run_defend(sq: SquadState, a: Dictionary, now: float) -> void:
	var units := _units(sq)
	if sq.tactic_phase == PH_SETUP:
		if _arrived_frac(units) >= 0.7 or now - sq.tactic_phase_since > 14.0:
			sq.tactic_phase = PH_HOLD
			sq.tactic_phase_since = now
		return
	# A squad that cannot hold: withdraw unless the player ordered the defence. GAMEPLAY-03B: a garrison, or a defence of an
	# objective, judges this without the "outnumbered" factor (holding prepared posts against more is what a defence is for)
	# and first falls back a line inside its area; only from its last line does it leave (and a garrison keeps its base).
	var hold_eff := float(a.eff)
	var bound := sq.garrison_base >= 0 or sq.station_objective >= 0
	if bound:
		hold_eff = float(a.eff) / maxf(float(a.parts.get("threat", 1.0)), 0.01)
	if now >= sq.tactic_commit_until and a.in_contact and hold_eff < withdraw_eff:
		var parts: Dictionary = a.parts
		if bound and sq.defence_line < 2 and _fall_back(sq, a, now):
			return
		if sq.tactic_owner != SquadState.Owner.PLAYER:
			var f := _fallback_point(sq, a)
			if f.is_finite():
				_switch(sq, SquadState.Tactic.WITHDRAW, f, "defence failing: effectiveness %.2f (size %.2f, suppression %.2f, ammo %.2f)" % [a.eff, parts.size, parts.suppression, parts.ammo])
				return
			sq.tactic_rejected = "withdraw considered (effectiveness %.2f) but no safe fallback position" % a.eff
		else:
			sq.tactic_rejected = "withdraw considered (effectiveness %.2f) but the player ordered the defence" % a.eff
	# A threat that shows nowhere near the posts: look for better ones.
	if now - sq.tactic_phase_since >= 10.0:
		var why := _bad_posts(sq, a, now)
		if why != "":
			_reposition(sq, a, why, now)
			return
	if sq.tactic_owner == SquadState.Owner.SQUAD and sq.garrison_base < 0 and not a.in_contact and now - float(_seen_at.get(sq.id, sq.tactic_since)) > calm_end_s and now - sq.tactic_since > calm_end_s:
		_finish(sq, "no contact for %.0f s" % calm_end_s, SquadState.Tactic.REGROUP)


## Why the posts are no good any more ("" when they are): the squad is under fire but nobody has
## seen an enemy for a while, or the threat now comes from a direction the posts do not cover.
func _bad_posts(sq: SquadState, a: Dictionary, now: float) -> String:
	if int(a.under_fire) > 0 and int(a.seen_n) == 0:
		if not _blind.has(sq.id):
			_blind[sq.id] = now
		if now - float(_blind[sq.id]) >= 10.0:
			_blind.erase(sq.id)
			return "under fire for 10 s without seeing an enemy: no useful line of fire"
	else:
		_blind.erase(sq.id)
	var threat: Vector3 = a.threat_pos
	# GAMEPLAY-03A: posts chosen before any threat was believed are judged again once one is (concealment needs a viewpoint).
	if bool(_meta(sq, "planned_blind", false)) and threat.is_finite() and float(a.threat_conf) >= 0.4:
		_set_meta(sq, "planned_blind", false)
		return "a threat is believed %s (%s, %.0f m): posts judged against it" % [_xz(threat), a.threat_src, _flat(sq.tactic_target, threat)]
	if threat.is_finite() and float(a.threat_conf) >= 0.6 and sq.tactic_dir.length() > 0.1:
		var nd := _dir_to(sq.tactic_target, threat)
		var dot := nd.dot(sq.tactic_dir.normalized())
		if dot < cos(deg_to_rad(55.0)):
			var bad := 0
			var units := _units(sq)
			for u: UnitState in units:
				var p := u.post_pos if u.post_pos.is_finite() else u.position
				if u.fort_slot != "":
					# GAMEPLAY-01C: a fortification slot protects within its sector.
					var e := pos.slot_by_key(u.fort_slot, sq.faction)
					if e.is_empty() or (e.facing as Vector3).dot(_dir_to(p, threat)) < cos(deg_to_rad(float(e.arc) * 0.5)):
						bad += 1
				elif not sim.brain._evaluate_spot(null, p, threat).protected:
					bad += 1
			if bad * 2 >= units.size():
				return "the threat moved to a bearing %.0f degrees off and %d of %d posts no longer give cover" % [rad_to_deg(acos(clampf(dot, -1.0, 1.0))), bad, units.size()]
	return ""


func _reposition(sq: SquadState, a: Dictionary, why: String, now: float) -> void:
	var list: Array = _repos.get(sq.id, [])
	list = list.filter(func(t: float) -> bool: return now - t < 120.0)
	if list.size() >= reposition_limit or (not list.is_empty() and now - float(list[-1]) < reposition_cooldown_s):
		sq.tactic_rejected = "reposition declined (%s): %d already in 2 min" % [why, list.size()]
		_repos[sq.id] = list
		return
	list.append(now)
	_repos[sq.id] = list
	var centre: Vector3 = sq.tactic_target
	var threat: Vector3 = a.threat_pos
	var dir := _dir_to(centre, threat) if threat.is_finite() else sq.tactic_dir
	var units := _units(sq)
	for u: UnitState in units:
		if u.post_pos.is_finite():
			_remember_post(sq, u.post_pos)
	var look: Vector3 = threat if threat.is_finite() else Vector3.INF
	var gb: Dictionary = sim.state.construction.bases.get(sq.garrison_base, {})
	var slot_r := minf(BaseSim.reach_of(gb), 170.0) if not gb.is_empty() else fort_radius_m
	# GAMEPLAY-03A: soldiers whose post still covers them against the threat (a slot whose sector faces it, natural cover that
	# protects from it) stay; only the others get new posts - a garrison does not run round its base for a few degrees.
	var keep: Array = []
	var move: Array = []
	for u: UnitState in units:
		if threat.is_finite() and u.post_pos.is_finite() and _post_still_good(sq, u, threat):
			keep.append(u)
		else:
			move.append(u)
	if move.is_empty():
		move = units
		keep = []
	_set_meta(sq, "keep_posts", keep.map(func(u: UnitState) -> Vector3: return u.post_pos))
	units = move
	var posts := _defend_posts(sq, units, centre, dir, look, slot_r, gb.get("anchor", Vector3.INF), 24.0)
	_set_meta(sq, "keep_posts", [])
	sq.tactic_rejected = "reposition: %d of %d soldiers move, %d keep their posts" % [move.size(), move.size() + keep.size(), keep.size()]
	sq.tactic = SquadState.Tactic.REPOSITION
	sq.tactic_dir = dir
	sq.tactic_phase = PH_SETUP
	sq.tactic_phase_since = now
	sq.tactic_why = "reposition: " + why
	_log(sq, "%s REPOSITION: %s" % [sq.squad_name, why])
	started[SquadState.Tactic.REPOSITION] = int(started.get(SquadState.Tactic.REPOSITION, 0)) + 1
	_send_posts(sq, units, posts, dir)


# --- GAMEPLAY-03B: falling back a line ------------------------------------------------------------------------------------

## The area the defence must stay in: the capture radius of the objective it holds (a garrison's base objective, a stationed
## squad's objective), less a margin, so a defence never gives the objective away by where it stands. {} = no such limit.
func _defence_limit(sq: SquadState) -> Dictionary:
	var oid := -1
	if sq.garrison_base >= 0:
		oid = int(sim.state.construction.bases.get(sq.garrison_base, {}).get("objective", -1))
	if oid < 0:
		oid = sq.station_objective
	var o := sim.state.war.objective(oid) if oid >= 0 else null
	if o == null:
		return {}
	return {"c": o.position, "r": maxf(o.radius - 8.0, 20.0)}


func _inside_limit(sq: SquadState, p: Vector3) -> bool:
	var lim := _defence_limit(sq)
	return lim.is_empty() or _flat(p, lim.c) <= float(lim.r)


## Falls back one line: posts further from the believed threat but still inside the defended area (the objective's capture
## radius), the forward fire team first while the other covers, then the other. Returns true when it acted (or waits while
## the squad is pinned down: soldiers do not get up and run across open ground under heavy fire).
func _fall_back(sq: SquadState, a: Dictionary, now: float) -> bool:
	var threat: Vector3 = a.threat_pos
	var units := _units(sq)
	if not threat.is_finite() or units.is_empty():
		return false
	if _pinned_frac(units) >= 0.5:
		var since := float(_meta(sq, "fb_wait", now))
		_set_meta(sq, "fb_wait", since)
		if now - since < 20.0:
			sq.tactic_rejected = "falling back waits: %d%% of the squad is pinned" % roundi(_pinned_frac(units) * 100.0)
			return true
	_set_meta(sq, "fb_wait", now)
	var lim := _defence_limit(sq)
	var c: Vector3 = lim.get("c", sq.tactic_target)
	var r: float = float(lim.get("r", 40.0))
	var d := _dir_to(c, threat)
	var line := sq.defence_line + 1
	# The secondary line a third of the radius behind the centre's front edge, the last one round the centre itself.
	var front := 0.0
	for u: UnitState in units:
		front += ((u.post_pos if u.post_pos.is_finite() else u.position) - c).dot(d)
	front /= units.size()
	var centre := pos.nearest_valid(c + d * minf(front - 12.0, r * 0.15), 12.0) if line == 1 else pos.nearest_valid(c - d * 6.0, 12.0)
	if not centre.is_finite():
		centre = c
	for u: UnitState in units:
		if u.post_pos.is_finite():
			_remember_post(sq, u.post_pos)
	_set_meta(sq, "behind", {"c": c, "d": d, "max": front - 8.0})
	var gb: Dictionary = sim.state.construction.bases.get(sq.garrison_base, {})
	var posts := _defend_posts(sq, units, centre, d, threat, minf(r, 30.0 if line == 2 else 45.0), gb.get("anchor", Vector3.INF), 20.0 if line == 2 else 28.0)
	_set_meta(sq, "behind", {})
	if posts.size() < maxi(1, units.size() / 2):
		sq.tactic_rejected = "no line %d to fall back to behind the current posts" % line
		return false
	sq.defence_line = line
	sq.tactic = SquadState.Tactic.REPOSITION
	sq.tactic_dir = d
	sq.tactic_target = centre
	sq.tactic_phase = PH_SETUP
	sq.tactic_phase_since = now
	sq.tactic_leg_since = now
	var why := "falling back to line %d (%s): effectiveness %.2f, suppression %.2f, %d of %d left" % [line, "secondary" if line == 1 else "last, round the objective",
		float(a.eff), float(a.supp), int(a.n), int(a.n0)]
	sq.tactic_why = why
	_log(sq, "%s %s" % [sq.squad_name, why])
	fallbacks += 1
	# Every soldier gets his new post now (it is on his record: a load in the middle carries on); the forward team moves first.
	var dd := Vector3(d.x, 0.0, d.z)
	var axis := Vector3(-dd.z, 0.0, dd.x)
	var ups: Array = units.map(func(u: UnitState) -> Vector3: return u.position)
	var idx := pos.assign(ups, posts, axis)
	_mg_first(units, posts, idx, dd)
	for i in units.size():
		var u: UnitState = units[i]
		var post: Dictionary = posts[idx[i]]
		u.post_pos = post.p
		u.fort_slot = String(post.get("slot", ""))
		if u.fort_slot != "":
			u.fort_pos = Vector3.INF
	var mover := 0
	if sq.teams.size() == 2:
		var f0 := _team_front(sq, 0, c, d)
		var f1 := _team_front(sq, 1, c, d)
		mover = 0 if f0 >= f1 else 1
	sq.tactic_leg = 100 + mover
	_fall_back_move(sq, mover)
	return true


func _team_front(sq: SquadState, team: int, c: Vector3, d: Vector3) -> float:
	var us := _units(sq, team)
	if us.is_empty():
		return -INF
	return (_centroid(us) - c).dot(d)


## Sends the soldiers of `team` (-1: all) to their (new) posts; the others cover the move with fire at the threat.
func _fall_back_move(sq: SquadState, team: int) -> void:
	for u: UnitState in _units(sq, team if sq.teams.size() == 2 else -1):
		if not u.post_pos.is_finite():
			continue
		var goal := u.post_pos
		if u.fort_slot != "":
			var e := pos.slot_by_key(u.fort_slot, sq.faction)
			goal = e.get("access", u.post_pos)
		if _flat(u.position, goal) > 1.2:
			sim.state.issue_move(u.id, goal, true)


## The two halves of a fall back: the moving team goes (the other fires at the threat); when it is there (or 18 s), the other
## goes; when most are in place (or 20 s), the defence holds the new line.
func _run_fall_back(sq: SquadState, a: Dictionary, units: Array, now: float) -> void:
	var team := sq.tactic_leg - 100
	var two := sq.teams.size() == 2
	var movers := _units(sq, team) if two and team < 2 else units
	var threat: Vector3 = a.threat_pos
	if two and team < 2 and threat.is_finite() and float(a.ammo) > 0.25:
		_fire_on(_units(sq, 1 - team), threat, 10.0, mission_s)
	if _arrived_frac(movers, 4.0) >= 0.7 or now - sq.tactic_leg_since > 18.0:
		if two and team < 2 and sq.tactic_leg_since >= sq.tactic_phase_since and sq.tactic_leg < 102 and not bool(_meta(sq, "fb_second", false)):
			_set_meta(sq, "fb_second", true)
			sq.tactic_leg = 100 + (1 - team)
			sq.tactic_leg_since = now
			_cease_fire(units)
			_fall_back_move(sq, 1 - team)
			return
		_set_meta(sq, "fb_second", false)
		_cease_fire(units)
		sq.tactic_leg = 0
		sq.tactic = SquadState.Tactic.DEFEND
		sq.tactic_phase = PH_HOLD
		sq.tactic_phase_since = now
		sq.tactic_commit_until = now + 25.0
		sq.tactic_rejected = "holding line %d" % sq.defence_line


## The soldier's post still serves against `threat`: a fortification slot whose sector faces it, or natural cover that
## protects from it.
func _post_still_good(sq: SquadState, u: UnitState, threat: Vector3) -> bool:
	if u.fort_slot != "":
		var e := pos.slot_by_key(u.fort_slot, sq.faction)
		return not e.is_empty() and (e.facing as Vector3).dot(_dir_to(u.post_pos, threat)) >= cos(deg_to_rad(float(e.arc) * 0.5))
	return sim.brain._evaluate_spot(null, u.post_pos, threat).protected


func _run_reposition(sq: SquadState, _a: Dictionary, now: float) -> void:
	var units := _units(sq)
	if sq.tactic_leg >= 100:
		_run_fall_back(sq, _a, units, now)
		return
	if _arrived_frac(units) >= 0.7 or now - sq.tactic_phase_since > 14.0:
		sq.tactic = SquadState.Tactic.DEFEND
		sq.tactic_phase = PH_HOLD
		sq.tactic_phase_since = now
		sq.tactic_why = "defend %s from new posts" % _xz(sq.tactic_target)
		finished[SquadState.Tactic.REPOSITION] = int(finished.get(SquadState.Tactic.REPOSITION, 0)) + 1


# --- SUPPRESS --------------------------------------------------------------------------------------------------

func _run_suppress(sq: SquadState, a: Dictionary, now: float) -> void:
	var units := _units(sq)
	var target := _refresh_target(sq)
	if sq.tactic_phase == PH_SETUP:
		if _arrived_frac(units) >= 0.6 or now - sq.tactic_phase_since > 12.0:
			sq.tactic_phase = PH_HOLD
			sq.tactic_phase_since = now
		else:
			return
	var why := _suppress_over(sq, a, now)
	if why != "":
		_finish(sq, why, SquadState.Tactic.REGROUP)
		return
	if sq.tactic_owner == SquadState.Owner.OPERATION:
		_support_fire(sq, a, units, target, now)
		return
	_fire_on(units, target, _spread_for(sq), mission_s)


## GAMEPLAY-02A: fire control of an operation's fire support. Its soldiers engage every enemy they see on their own
## (CombatBrain); fire missions go to the freshest reports on the objective (several, one per soldier in turn) - always
## when a report is new (an enemy just seen or firing), otherwise only while the operation's cover-fire window is open (the
## assault is crossing the defenders' ground), then at the objective's believed centre if nothing better is known. Outside
## that the support observes: blind fire from the deployment on emptied its magazines before the assault needed it.
func _support_fire(sq: SquadState, a: Dictionary, units: Array, target: Vector3, now: float) -> void:
	var op := sim.state.war.operation(sq.tactic_op)
	var cover: bool = op != null and op.cover_fire
	var obj := sim.state.war.objective(op.target_objective) if op else null
	var centre: Vector3 = obj.position if obj else target
	var r: float = (obj.radius if obj else 60.0) + 60.0
	# GAMEPLAY-03C: the reports ranked by danger - an enemy reported at a fortification (a slot, an MG emplacement, a tower
	# the faction can see standing there) first, then by recency and strength. Only reported enemies are fired at; an
	# empty structure is never a target.
	var ranked: Array = []
	if sim.war != null and sim.war.enabled:
		for c: ContactState in sim.war.intel.contacts_near(sq.faction, centre, r):
			if c.status == ContactState.Status.LOST or c.conf < 0.3 or now - c.t_seen > 90.0:
				continue
			var fresh_c := now - c.t_seen <= 15.0
			if not cover and not fresh_c:
				continue
			var fortified := _contact_fortified(sq, c, now)
			ranked.append({"p": c.pos, "score": (3.0 if fortified else 0.0) + (1.5 if fresh_c else 0.0) + 0.2 * minf(c.strength, 6.0) * c.conf, "fort": fortified})
			if ranked.size() >= 6:
				break
	ranked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.score) > float(y.score))
	var targets: Array[Vector3] = []
	for e: Dictionary in ranked.slice(0, 4):
		targets.append(e.p)
	if not ranked.is_empty() and bool(ranked[0].fort):
		support_fort_targets += 1
	if targets.is_empty():
		# Nothing reported to fire at: fire at the objective's centre hit nobody when the defenders stood elsewhere (1000
		# rounds, no suppression), so the support watches until the first sighting or shot is reported.
		_cease_fire(units)
		sq.tactic_rejected = "observing: no report of the enemy on the objective to fire at" if cover else "observing: no fresh report of the enemy on the objective, the assault is not crossing yet"
		return
	sq.tactic_rejected = "" if cover else "fire at fresh reports with half the squad until the assault crosses"
	var spread := _spread_for(sq)
	var k := 0
	var j := 0
	for i in units.size():
		# Outside the window half the squad fires (the ammunition must last into the assault); a machine gun always does,
		# at the most dangerous report.
		if _is_mg(units[i]):
			_fire_on([units[i]], targets[0], spread, mission_s)
			continue
		if not cover:
			k += 1
			if k % 2 == 0:
				_cease_fire([units[i]])
				continue
		_fire_on([units[i]], targets[j % targets.size()], spread, mission_s)
		j += 1


## GAMEPLAY-03C: a reported enemy stands at a fortification of its side (within 6 m of one; cached per contact for 10 s).
func _contact_fortified(sq: SquadState, c: ContactState, now: float) -> bool:
	var key := "%d:%d" % [sq.faction, c.id]
	var hit: Array = _fort_contact.get(key, [])
	if not hit.is_empty() and now - float(hit[1]) < 10.0:
		return bool(hit[0])
	var yes := false
	for h: Dictionary in sim.combat.line.structures_near(c.pos, 6.0):
		var st := sim.state.construction.get_structure(int(h.id))
		if st and st.faction != sq.faction and st.faction >= 0 and DefenceDefs.has(st.type_id) and st.is_operational():
			yes = true
			break
	_fort_contact[key] = [yes, now]
	return yes


func _suppress_over(sq: SquadState, a: Dictionary, now: float) -> String:
	if float(a.ammo) < sim.brain.mission_stop_ammo + 0.05:
		return "ammunition low (%.0f%%)" % (float(a.ammo) * 100.0)
	if sq.tactic_contact >= 0:
		var c := sim.war.intel.get_contact(sq.faction, sq.tactic_contact)
		if c == null:
			return "the contact is no longer believed"
		if c.conf < 0.18 or now - c.t_seen > 120.0:
			return "the report is too old (confidence %d%%)" % roundi(c.conf * 100.0)
	elif sq.tactic_owner == SquadState.Owner.PLAYER and now - sq.tactic_since > 60.0:
		return "suppression time (60 s) over"
	if sq.tactic_owner == SquadState.Owner.SQUAD and int(a.seen_n) == 0 and now - sq.tactic_since > 40.0:
		return "no news of the enemy for 40 s"
	return ""


func _spread_for(sq: SquadState) -> float:
	if sq.tactic_contact >= 0:
		var c := sim.war.intel.get_contact(sq.faction, sq.tactic_contact)
		if c:
			# GAMEPLAY-02A: aimed at the reported position, spread over a third of its uncertainty (half of it scattered most
			# rounds beyond the 3 m a near miss needs: a thousand rounds suppressed nobody).
			return clampf(c.unc * 0.3, 3.0, 15.0)
	return 8.0


## The target of a tactic that follows a contact: the contact's reported position (which only
## moves when somebody reports it again). A position the player chose stays.
func _refresh_target(sq: SquadState) -> Vector3:
	if sq.tactic_contact >= 0:
		var c := sim.war.intel.get_contact(sq.faction, sq.tactic_contact)
		if c:
			sq.tactic_target = c.pos
	return sq.tactic_target


# --- Legs: the building block of BOUND / WITHDRAW / ASSAULT / FLANK ------------------------------------------

## The team that moves in leapfrog bounds: alternating; one team moves by itself.
## How long a pinned team waits before it moves anyway: an operation's squad has its support firing and a
## timetable, so it waits less than a squad on its own.
func _pinned_wait(sq: SquadState) -> float:
	return 9.0 if sq.tactic_owner == SquadState.Owner.OPERATION else 25.0


func _mover(sq: SquadState) -> int:
	return (sq.tactic_leg + 1) % 2 if sq.teams.size() == 2 else 0


## True when `team` may be given a new leg: the previous one is over (arrived or timed out).
func _leg_ready(sq: SquadState, team: int, now: float) -> bool:
	if not sq.tactic_dest.is_finite():
		return true
	var mu := _units(sq, team)
	if mu.is_empty() or _arrived_frac(mu, 6.0) >= 0.7 or now - sq.tactic_leg_since > leg_timeout_s:
		sq.tactic_dest = Vector3.INF
		sq.tactic_leg += 1
		return true
	return false


## Sends one team to the next leg: cover posts near the leg's end, spread across the line of
## travel, away from reserved spots and recently used ones.
func _begin_leg(sq: SquadState, team: int, dest: Vector3, threat: Vector3) -> void:
	var mu := _units(sq, team)
	if mu.is_empty():
		return
	var now := sim.state.time
	var from := _centroid(mu)
	var dir := _dir_to(from, dest)
	var posts := pos.find_posts(mu.size(), dest, 9.0, threat, {"mode": "cover", "reserved": _reserved(sq, dest, mu), "avoid": _avoid_list(sq), "unit_id": mu[0].id, "min_enemy_m": 20.0})
	posts = pos.fill_open(posts, mu.size(), dest, dir, 3.4)
	_send_posts(sq, mu, posts, dir)
	_set_meta(sq, "leg_team", team)
	sq.tactic_dest = dest
	sq.tactic_leg_since = now
	for p: Dictionary in posts:
		_remember_post(sq, p.p)


## Where the next leg of a move from `from` to `dest` ends (snapped to walkable ground; INF if none).
func _next_dest(from: Vector3, dest: Vector3, len: float) -> Vector3:
	var d := _flat(from, dest)
	var p := dest if d <= len else from + _dir_to(from, dest) * len
	return pos.nearest_valid(p, 14.0)


## The team that is not moving holds where it is (its soldiers keep that spot as their post).
func _hold_team(sq: SquadState, team: int) -> void:
	for u: UnitState in _units(sq, team):
		if not u.post_pos.is_finite():
			u.post_pos = u.position


# --- BOUND / WITHDRAW ----------------------------------------------------------------------------------------------

## One engine for bounding forward (BOUND) and back (WITHDRAW): the moving team goes one leg while
## the other covers, then they swap. A single-team squad moves in legs together.
func _run_bound(sq: SquadState, a: Dictionary, now: float, withdrawing: bool) -> void:
	var all := _units(sq)
	var dest: Vector3 = sq.tactic_target
	var centre := _centroid(all)
	var threat: Vector3 = a.threat_pos
	var done_m := 14.0 + sq.spacing * all.size() * 0.25
	if _flat(centre, dest) <= done_m and _arrived_frac(all, 8.0) >= 0.5:
		_finish(sq, "reached %s" % _xz(dest), SquadState.Tactic.REGROUP)
		return
	if now - sq.tactic_since > 45.0 + _flat(sq.tactic_dest if sq.tactic_dest.is_finite() else centre, dest) * 1.8 + _flat(centre, dest) * 1.2:
		_finish(sq, "took too long (%.0f s)" % (now - sq.tactic_since), SquadState.Tactic.REGROUP)
		return
	var teams := sq.teams.size()
	# Covering fire from the team that is not moving, when withdrawing from a reported enemy.
	if teams == 2:
		var idle := _units(sq, 1 - _mover(sq))
		_hold_team(sq, 1 - _mover(sq))
		if withdrawing and threat.is_finite() and float(a.threat_conf) >= 0.3 and float(a.ammo) > 0.3:
			_fire_on(idle, threat, 10.0, mission_s)
	if not _leg_ready(sq, _mover(sq), now):
		return
	var mover := _mover(sq)
	var mu := _units(sq, mover)
	if mu.is_empty():
		sq.tactic_leg += 1
		return
	if _pinned_frac(mu) >= pinned_go and now - sq.tactic_leg_since < _pinned_wait(sq):
		sq.tactic_rejected = "leg %d waits: %d%% of the moving team is pinned" % [sq.tactic_leg + 1, roundi(_pinned_frac(mu) * 100.0)]
		return
	var leg := _next_dest(centre, dest, leg_m * (1.5 if withdrawing else 1.0))
	if not leg.is_finite():
		_finish(sq, "no walkable ground towards %s" % _xz(dest), SquadState.Tactic.REGROUP)
		return
	# A plain bound never walks into a believed enemy position: it stops short of it.
	if not withdrawing and threat.is_finite() and float(a.threat_conf) >= 0.5 and _flat(leg, threat) < 45.0:
		_finish(sq, "stopped %.0f m short of the reported enemy" % _flat(leg, threat), SquadState.Tactic.NONE)
		return
	_begin_leg(sq, mover, leg, threat if threat.is_finite() else dest + sq.tactic_dir * 60.0)


# --- ASSAULT --------------------------------------------------------------------------------------------------------------

func _run_assault(sq: SquadState, a: Dictionary, now: float) -> void:
	var target := _refresh_target(sq)
	var all := _units(sq)
	var centre := _centroid(all)
	var d := _flat(centre, target)
	# GAMEPLAY-04A: the approach from far away is not part of the attack's time limit (a player ordering an assault 500 m
	# out had it "stall" after 170 s of steady progress). While approaching, the order stops only when the squad has not got
	# 10 m closer for approach_stall_s (runtime record: after loading the window starts again); the time limit counts from the
	# end of the approach (tactic_since is reset there).
	var why := ""
	if sq.tactic_phase == PH_SETUP and not sq.tactic_ext:
		if d < float(_meta(sq, "approach_best", INF)) - 10.0:
			_set_meta(sq, "approach_best", d)
			_set_meta(sq, "approach_best_at", now)
		if now - float(_meta(sq, "approach_best_at", now)) > approach_stall_s:
			why = "no progress towards the target for %.0f s" % approach_stall_s
	else:
		why = _attack_failed(sq, a, now, assault_timeout_s)
	if why != "":
		_fail(sq, a, why)
		return
	var support: Array = _units(sq, 0) if sq.teams.size() >= 2 else []
	var assault: Array = _units(sq, 1) if sq.teams.size() >= 2 else all
	match sq.tactic_phase:
		PH_SETUP:
			if sq.tactic_ext:
				# The operation's fire support suppresses the objective: close at once.
				sq.tactic_phase = PH_MOVE
				sq.tactic_phase_since = now
				sq.tactic_dest = Vector3.INF
				return
			# Approach: bound towards a staging point until the target is within reach.
			if d <= 130.0 or (int(a.seen_n) > 0 and d <= 170.0):
				sq.tactic_phase = PH_SUPPORT
				sq.tactic_since = now  # GAMEPLAY-04A: the attack (and its time limit) begins at the end of the approach
				sq.tactic_phase_since = now
				sq.tactic_dest = Vector3.INF
				_assault_support(sq, a, target)
				return
			_approach_leg(sq, a, target, now)
		PH_SUPPORT:
			var set_up := support.is_empty() or _arrived_frac(support) >= 0.6 or now - sq.tactic_phase_since > 12.0
			if not set_up:
				return
			if not support.is_empty():
				_fire_on(support, target, _spread_for(sq), mission_s)
			if now - sq.tactic_phase_since < (3.0 if not support.is_empty() else 0.0):
				return
			if _pinned_frac(assault) >= 0.7 and now - sq.tactic_phase_since < 30.0:
				sq.tactic_rejected = "assault waits: %d%% of the assault element is pinned" % roundi(_pinned_frac(assault) * 100.0)
				return
			sq.tactic_phase = PH_MOVE
			sq.tactic_phase_since = now
			sq.tactic_leg = 0
			sq.tactic_dest = Vector3.INF
			sq.tactic_why = "%s; support is firing, the assault element advances" % sq.tactic_why.split("; support")[0]
		PH_MOVE:
			var quiet_march: bool = int(a.seen_n) == 0 and int(a.under_fire) == 0
			var step := (42.0 if sq.tactic_ext else 28.0) * (2.2 if quiet_march else 1.0)
			if sq.teams.size() < 2:
				_advance(sq, a, 0, target, now, step)
			elif quiet_march and d > 160.0 and (not sq.tactic_dest.is_finite() or int(_meta(sq, "leg_team", 0)) < 0):
				# GAMEPLAY-02A: nobody sees or fires at the squad and it is still far out: both teams move together
				# (leapfrogging out of contact halved the speed across the open ground); the bounds start with the first
				# contact or 160 m out (a squad that marched on to 45 m of hidden defenders was shot in seconds).
				_advance(sq, a, -1, target, now, step)
			else:
				# Leapfrog: the team that is behind moves up (or the two take turns when level), the
				# other one fires; the squad closes as one body instead of one team running ahead.
				var front := minf(_team_dist(sq, 0, target), _team_dist(sq, 1, target))
				if front <= 26.0:
					sq.tactic_phase = PH_OCCUPY
					sq.tactic_phase_since = now
					sq.tactic_dest = Vector3.INF
					_cease_fire(_units(sq))
					return
				var team := _assault_mover(sq, target)
				if team < 0:
					team = 0
				# The covering team fires only where a rifle can reach the defenders (not from 300 m at a map position).
				if front > 40.0 and (front < 260.0 or int(a.seen_n) > 0):
					_fire_on(_units(sq, 1 - team), target, _spread_for(sq), mission_s)
				else:
					_cease_fire(_units(sq))
				_advance(sq, a, team, target, now, step)
		PH_OCCUPY:
			_occupy(sq, a, target, now)


func _team_dist(sq: SquadState, team: int, target: Vector3) -> float:
	var us := _units(sq, team)
	return _flat(_centroid(us), target) if not us.is_empty() else INF


## Which team moves next in an assault's leapfrog: the one that is further from the target when the gap is
## more than 35 m, else the other one than last time. A leg in progress keeps its team.
func _assault_mover(sq: SquadState, target: Vector3) -> int:
	if sq.tactic_dest.is_finite():
		return int(_meta(sq, "leg_team", 1))
	var d0 := _team_dist(sq, 0, target)
	var d1 := _team_dist(sq, 1, target)
	if absf(d0 - d1) > 35.0 or is_inf(d0) or is_inf(d1):
		return 0 if (d0 > d1 or is_inf(d1)) else 1
	return 1 - int(_meta(sq, "leg_team", 0))


## Phase 0 of an assault from far away: the squad bounds towards a staging point short of the target.
func _approach_leg(sq: SquadState, a: Dictionary, target: Vector3, now: float) -> void:
	var all := _units(sq)
	var centre := _centroid(all)
	if sq.teams.size() == 2:
		_hold_team(sq, 1 - _mover(sq))
	if not _leg_ready(sq, _mover(sq), now):
		return
	var mover := _mover(sq)
	var mu := _units(sq, mover)
	if mu.is_empty():
		sq.tactic_leg += 1
		return
	if _pinned_frac(mu) >= pinned_go and now - sq.tactic_leg_since < _pinned_wait(sq):
		sq.tactic_rejected = "approach leg waits: %d%% of the moving team is pinned" % roundi(_pinned_frac(mu) * 100.0)
		return
	var stage := target - _dir_to(centre, target) * 100.0
	# Nobody has seen or fired at the squad yet: it marches (long legs); bounds only under fire.
	var quiet: bool = int(a.seen_n) == 0 and int(a.under_fire) == 0
	var leg := _next_dest(centre, stage, leg_m * (3.0 if quiet else 1.0))
	if not leg.is_finite():
		_fail(sq, a, "no walkable ground towards the staging point")
		return
	_begin_leg(sq, mover, leg, target)


## Support team to firing posts with a line to the target (and the maneuver / assault team to
## cover where it is). FLANK uses the same set-up.
func _assault_support(sq: SquadState, a: Dictionary, target: Vector3) -> void:
	if sq.teams.size() < 2:
		return
	var support := _units(sq, 0)
	var other := _units(sq, 1)
	var centre: Vector3 = a.center
	var d := _flat(centre, target)
	var dir := _dir_to(centre, target)
	if not support.is_empty():
		var s_centre := _centroid(support)
		var from := s_centre if (d >= 55.0 and d <= 130.0) else target - dir * 85.0
		var posts := pos.find_posts(support.size(), from, 24.0, target, {"mode": "fire", "los": target, "reserved": _reserved(sq, from, support), "avoid": _avoid_list(sq), "unit_id": support[0].id, "min_enemy_m": 40.0})
		if posts.is_empty():
			sq.tactic_rejected = "no better firing position with a line to the target: supporting from where the team stands"
			_hold_team(sq, 0)
		else:
			posts = pos.fill_open(posts, support.size(), from, dir)
			_send_posts(sq, support, posts, dir)
			for p: Dictionary in posts:
				_remember_post(sq, p.p)
	if not other.is_empty():
		var c1 := _centroid(other)
		var posts := pos.find_posts(other.size(), c1, 9.0, target, {"mode": "cover", "reserved": _reserved(sq, c1, other), "avoid": _avoid_list(sq), "unit_id": other[0].id})
		posts = pos.fill_open(posts, other.size(), c1, dir)
		_send_posts(sq, other, posts, dir)


## The assault / maneuver element advances by legs towards the target until it is on top of it.
func _advance(sq: SquadState, a: Dictionary, team: int, target: Vector3, now: float, step_m: float) -> void:
	var units := _units(sq, team)
	if units.is_empty():
		return
	if not _leg_ready(sq, team, now):
		return
	var centre := _centroid(units)
	var d := _flat(centre, target)
	if d <= 26.0:
		sq.tactic_phase = PH_OCCUPY
		sq.tactic_phase_since = now
		sq.tactic_dest = Vector3.INF
		_cease_fire(_units(sq))
		return
	if _pinned_frac(units) >= pinned_go and now - sq.tactic_leg_since < _pinned_wait(sq):
		sq.tactic_rejected = "advance waits: %d%% of the element is pinned" % roundi(_pinned_frac(units) * 100.0)
		return
	var dest := _next_dest(centre, target - _dir_to(centre, target) * 14.0, step_m)
	if not dest.is_finite():
		_fail(sq, a, "no walkable ground towards the target")
		return
	_begin_leg(sq, team, dest, target)


## On the objective: everybody takes posts around it facing outward; done when most are there and
## no enemy is in sight near it.
func _occupy(sq: SquadState, a: Dictionary, target: Vector3, now: float) -> void:
	var all := _units(sq)
	if not sq.tactic_dest.is_finite():
		var outward := sq.tactic_dir if sq.tactic_dir.length() > 0.1 else _dir_from_yaw(sq.order_yaw)
		var posts := pos.find_posts(all.size(), target, 14.0, target + outward * 70.0, {"mode": "fire", "reserved": _reserved(sq, target, all), "avoid": [], "unit_id": all[0].id, "min_enemy_m": 0.0})
		posts = pos.fill_open(posts, all.size(), target, outward)
		_send_posts(sq, all, posts, outward)
		sq.tactic_dest = target
		sq.tactic_leg_since = now
		_set_roles(sq, SquadState.TeamRole.SECURITY, SquadState.TeamRole.SECURITY)
		return
	var near := _arrived_frac(all, 16.0)
	var clear := true
	for p: Vector3 in a.seen:
		if _flat(p, target) < 45.0:
			clear = false
	if near >= 0.6 and clear:
		if not _meta(sq, "clear_since", 0.0):
			_set_meta(sq, "clear_since", now)
		if now - float(_meta(sq, "clear_since", now)) >= 5.0:
			_set_meta(sq, "clear_since", 0.0)
			_finish(sq, "objective occupied", SquadState.Tactic.REGROUP)
			return
	else:
		_set_meta(sq, "clear_since", 0.0)
	if now - sq.tactic_phase_since > 60.0:
		_fail(sq, a, "could not clear the objective in 60 s")


func _attack_failed(sq: SquadState, a: Dictionary, now: float, limit: float) -> String:
	if now - sq.tactic_since > limit:
		return "stalled for %.0f s" % (now - sq.tactic_since)
	if float(a.eff) < abort_eff and now - sq.tactic_since > 12.0 and sq.tactic_phase >= PH_SUPPORT:
		var p: Dictionary = a.parts
		return "effectiveness %.2f (size %.2f, suppression %.2f, ammo %.2f)" % [a.eff, p.size, p.suppression, p.ammo]
	return ""


## An attack that cannot go on: the squad withdraws (its own or the operation's choice); an
## attack the player ordered stops and holds where it is.
func _fail(sq: SquadState, a: Dictionary, why: String) -> void:
	var name := SquadState.TACTIC_NAMES[sq.tactic]
	_set_meta(sq, "failed_%d" % sq.tactic, sim.state.time + 45.0)
	if sq.tactic_owner == SquadState.Owner.OPERATION:
		# An operation's squad reports back instead of deciding to leave on its own: the operation
		# re-tasks it, replaces it or withdraws as a whole (OpCoordination).
		_finish(sq, "%s failed: %s" % [name.to_lower(), why], SquadState.Tactic.NONE)
		return
	if sq.tactic_owner != SquadState.Owner.PLAYER:
		var f := _fallback_point(sq, a)
		if f.is_finite():
			_switch(sq, SquadState.Tactic.WITHDRAW, f, "%s broken off: %s" % [name.to_lower(), why])
			return
	_switch(sq, SquadState.Tactic.DEFEND, Vector3.INF, "%s stopped: %s; holding here" % [name.to_lower(), why])


## Replaces the tactic by another one with the same owner.
func _switch(sq: SquadState, tactic: int, target: Vector3, why: String) -> void:
	var owner := sq.tactic_owner
	var contact := sq.tactic_contact
	var res := start(sq, tactic, owner, target, contact, why)
	if res.ok:
		sq.tactic_why = why
	else:
		_finish(sq, "%s (and %s is not possible: %s)" % [why, SquadState.TACTIC_NAMES[tactic].to_lower(), res.reason], SquadState.Tactic.NONE)


# --- FLANK --------------------------------------------------------------------------------------------------------------------

func _run_flank(sq: SquadState, a: Dictionary, now: float) -> void:
	var target: Vector3 = sq.tactic_target
	var support: Array = _units(sq, 0)
	var man: Array = _units(sq, 1)
	if man.is_empty():
		_fail(sq, a, "the maneuver team is gone")
		return
	var why := _attack_failed(sq, a, now, flank_timeout_s)
	if why != "":
		_fail(sq, a, why)
		return
	# New intelligence: the contact moved - the flank is planned again (at most twice).
	if sq.tactic_phase <= PH_MOVE and sq.tactic_contact >= 0:
		var c := sim.war.intel.get_contact(sq.faction, sq.tactic_contact)
		if c != null and _flat(c.pos, target) > 45.0:
			if sq.tactic_replans >= 2:
				_fail(sq, a, "the enemy keeps moving: flank abandoned after 2 re-plans")
				return
			if not _replan_flank(sq, a, c, man):
				return
			target = sq.tactic_target
	match sq.tactic_phase:
		PH_SETUP:
			if sq.tactic_ext or support.is_empty() or _arrived_frac(support) >= 0.6 or now - sq.tactic_phase_since > 14.0:
				sq.tactic_phase = PH_MOVE
				sq.tactic_phase_since = now
				sq.tactic_dest = Vector3.INF
				sq.tactic_leg = 0
		PH_MOVE:
			if not support.is_empty():
				_fire_on(support, target, _spread_for(sq), mission_s)
			_flank_leg(sq, a, man, now)
		PH_FINAL:
			if not support.is_empty():
				if _flat(_centroid(man), target) > 40.0:
					_fire_on(support, target, _spread_for(sq), mission_s)
				else:
					_cease_fire(support)
			_advance(sq, a, 1, target, now, 26.0)
		PH_OCCUPY:
			_occupy(sq, a, target, now)


## One leg along the flank route for the maneuver team.
func _flank_leg(sq: SquadState, a: Dictionary, man: Array, now: float) -> void:
	if not _leg_ready(sq, 1, now):
		return
	var centre := _centroid(man)
	var wp: Vector3 = sq.tactic_route[mini(sq.tactic_route_i, sq.tactic_route.size() - 1)]
	if _flat(centre, wp) <= 14.0:
		sq.tactic_route_i += 1
		if sq.tactic_route_i >= sq.tactic_route.size():
			sq.tactic_phase = PH_FINAL
			sq.tactic_phase_since = now
			sq.tactic_dest = Vector3.INF
			sq.tactic_why = "%s; maneuver team in position, closing on the target" % sq.tactic_why.split("; maneuver")[0]
			return
		wp = sq.tactic_route[sq.tactic_route_i]
	if _pinned_frac(man) >= pinned_go and now - sq.tactic_leg_since < _pinned_wait(sq):
		sq.tactic_rejected = "flank leg waits: %d%% of the maneuver team is pinned" % roundi(_pinned_frac(man) * 100.0)
		return
	var dest := _next_dest(centre, wp, leg_m * 1.2)
	if not dest.is_finite():
		_fail(sq, a, "no walkable ground on the flank route")
		return
	_begin_leg(sq, 1, dest, sq.tactic_target)


func _replan_flank(sq: SquadState, a: Dictionary, c: ContactState, man: Array) -> bool:
	replans += 1
	sq.tactic_replans += 1
	var centre := _centroid(man)
	var best := {}
	for side: int in [-1, 1]:
		var fp := pos.plan_flank(centre, c.pos, side, flank_lateral_m, man[0].id)
		if fp.ok and (best.is_empty() or fp.exposure < best.exposure):
			best = fp
	if best.is_empty() or best.exposure > 0.6:
		_fail(sq, a, "the contact moved %.0f m and no safe flank is left" % _flat(c.pos, sq.tactic_target))
		return false
	var route := PackedVector3Array()
	for p: Vector3 in best.points:
		route.append(p)
	_log(sq, "%s FLANK re-planned: contact moved %.0f m, now the %s side (exposure %d%%)" % [sq.squad_name, _flat(c.pos, sq.tactic_target), best.name, roundi(best.exposure * 100.0)])
	sq.tactic_route = route
	sq.tactic_route_i = 0
	sq.tactic_target = c.pos
	sq.tactic_dest = Vector3.INF
	sq.tactic_why = "flank %s (re-planned): exposure %d%%, %.0f m" % [best.name, roundi(best.exposure * 100.0), best.length]
	if sq.tactic_phase == PH_FINAL:
		sq.tactic_phase = PH_MOVE
	_assault_support(sq, a, c.pos)
	return true


# --- REGROUP -------------------------------------------------------------------------------------------------------------------

func _run_regroup(sq: SquadState, a: Dictionary, now: float) -> void:
	# Not while shots are still landing: running back through fire is how a squad loses people.
	var calm: bool = int(a.under_fire) == 0 and float(a.supp) < 0.25 and int(a.engaged) == 0
	if not calm and now - sq.tactic_phase_since < 25.0:
		return
	var all := _units(sq)
	var centre := _centroid(all)
	var spread := 0.0
	for u: UnitState in all:
		spread = maxf(spread, _flat(u.position, centre))
	var point := Vector3.INF
	var threat: Vector3 = a.threat_pos
	if threat.is_finite():
		point = pos.nearest_valid(centre - _dir_to(centre, threat) * 8.0, 10.0)
	_log(sq, "%s REGROUP: calm, assembling (spread %.0f m)" % [sq.squad_name, spread])
	sq.tactic = SquadState.Tactic.NONE
	sq.tactic_owner = SquadState.Owner.NONE
	sq.tactic_cooldown_until = now + 8.0
	sq.tactic_why = "regrouped after %s" % SquadState.TACTIC_NAMES[int(_meta(sq, "last_tactic", 0))].to_lower()
	_clear_units(sq)
	_internal = true
	if spread > 14.0:
		sim.squads.order_regroup([sq.id], point if point.is_finite() else Vector3.INF)
	else:
		if sq.order == SquadState.Order.TACTIC:
			sim.squads.order_hold([sq.id])
		sq.prev_order = SquadState.Order.NONE
	_internal = false
	finished[SquadState.Tactic.REGROUP] = int(finished.get(SquadState.Tactic.REGROUP, 0)) + 1


# --- Fallback position --------------------------------------------------------------------------------------------------------

## A place to withdraw to: away from the believed threat, on walkable ground, hidden from the
## threat if possible, clear of every contact the faction holds (and of the line there).
func _fallback_point(sq: SquadState, a: Dictionary) -> Vector3:
	var centre: Vector3 = a.center
	var threat: Vector3 = a.threat_pos
	var back := _dir_to(threat, centre) if threat.is_finite() else -_dir_from_yaw(sq.order_yaw)
	var contacts: Array = []
	if sim.war != null and sim.war.enabled:
		for c: ContactState in sim.war.intel.contacts_of(sq.faction):
			if c.status != ContactState.Status.LOST and c.conf >= contact_min_conf:
				contacts.append(c)
	var line := sim.combat.line
	var scored: Array = []
	for ang: float in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0]:
		for dist: float in [110.0, 150.0, 190.0]:
			var p := pos.nearest_valid(centre + back.rotated(Vector3.UP, deg_to_rad(ang)) * dist, 12.0)
			if not p.is_finite():
				continue
			var bad := false
			for c: ContactState in contacts:
				if _flat(p, c.pos) < 120.0 + 0.5 * c.unc or _seg_dist(c.pos, centre, p) < 45.0:
					bad = true
					break
			if bad:
				continue
			var hidden: bool = threat.is_finite() and not line.sight(threat + Vector3.UP * 1.5, p + Vector3.UP * 1.0).visible
			scored.append({"p": p, "score": (2.5 if hidden else 0.0) - 0.01 * dist - absf(ang) * 0.012})
	scored.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.score > y.score)
	for s: Dictionary in scored.slice(0, 4):
		if pos.segment_clear(centre, s.p):
			return s.p
	return Vector3.INF


# --- Orders to soldiers ---------------------------------------------------------------------------------------------------------

## Gives each soldier a post (paired to keep paths from crossing) and sends it there.
func _send_posts(sq: SquadState, units: Array, posts: Array, dir: Vector3) -> void:
	if units.is_empty() or posts.is_empty():
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	var axis := Vector3(-d.z, 0.0, d.x) if d.length() > 0.1 else SquadControl._right(sq.order_yaw)
	var ups: Array = []
	for u: UnitState in units:
		ups.append(u.position)
	var idx := pos.assign(ups, posts, axis)
	_mg_first(units, posts, idx, d)
	for i in units.size():
		var u: UnitState = units[i]
		var post: Dictionary = posts[idx[i]]
		var p: Vector3 = post.p
		var key := String(post.get("slot", ""))
		if key != "" and u.fort_slot == key and u.fort_pos.is_finite():
			u.post_pos = p
			continue  # GAMEPLAY-01C: already standing in this slot
		# GAMEPLAY-01C: a fortification slot is entered from its access point (a tower's stair foot, a position's rear).
		var goal: Vector3 = post.get("access", p) if key != "" else p
		if _flat(u.position, goal) > 1.2:
			sim.state.issue_move(u.id, goal, true)
		else:
			sim.state.halt(u.id)
		u.post_pos = p
		u.fort_slot = key
		if _flat(u.position, p) <= 1.2:
			u.anchor_pos = p


## Fraction of the units that are at their post (or no longer walking to it: arrived or blocked).
func _arrived_frac(units: Array, tol := 3.5) -> float:
	if units.is_empty():
		return 1.0
	var n := 0
	for u: UnitState in units:
		if not u.post_pos.is_finite() or _flat(u.position, u.post_pos) <= tol or u.order != UnitState.Order.MOVE:
			n += 1
	return float(n) / units.size()


func _pinned_frac(units: Array) -> float:
	if units.is_empty():
		return 0.0
	var now := sim.state.time
	var n := 0
	for u: UnitState in units:
		if u.suppression_at(now) >= sim.brain.pinned_at:
			n += 1
	return float(n) / units.size()


## Fire missions: each soldier shoots at its own point inside the area around `target` (a
## deterministic scatter, re-drawn every few seconds), whenever it sees no target of its own.
func _fire_on(units: Array, target: Vector3, spread: float, seconds: float) -> void:
	if not target.is_finite():
		return
	var now := sim.state.time
	for u: UnitState in units:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([sim.state.world_seed, u.id, int(now / 6.0), 811])
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * spread
		var p := target + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var g := pos.ground(p)
		u.fire_at = Vector3(p.x, g.y, p.z)
		u.fire_until = now + seconds


func _cease_fire(units: Array) -> void:
	for u: UnitState in units:
		u.fire_at = Vector3.INF
		u.fire_until = -1.0


## Idle soldiers of a tactic look towards the threat or the target.
func _face_all(sq: SquadState, a: Dictionary) -> void:
	var look: Vector3 = a.threat_pos
	if not look.is_finite():
		look = sq.tactic_target
	if not look.is_finite():
		return
	for u: UnitState in _units(sq):
		if u.order != UnitState.Order.MOVE and u.target_id < 0 and not u.is_reacting():
			sim.brain._watch(u, look, 2.5)


# --- Spots -------------------------------------------------------------------------------------------------------------------------

## Positions other soldiers of the same faction hold (cover or post) near `centre`, excluding some units.
func _reserved(sq: SquadState, centre: Vector3, exclude := []) -> Array:
	sim.brain._ensure_grid()
	var ex := {}
	for u: UnitState in exclude:
		ex[u.id] = true
	var out: Array = []
	for e: Array in sim.brain._covers:
		var o: UnitState = e[1]
		# Only spots held by soldiers of the squad's own faction: where an enemy has chosen to
		# stand is not something this squad may know.
		if o.faction == sq.faction and not ex.has(o.id) and _flat(e[0], centre) < 50.0:
			out.append(e[0])
	return out


func _avoid_list(sq: SquadState) -> Array:
	var now := sim.state.time
	var out: Array = []
	var keep: Array = []
	for e: Array in _avoid.get(sq.id, []):
		if e[1] > now:
			keep.append(e)
			out.append(e[0])
	_avoid[sq.id] = keep
	return out


func _remember_post(sq: SquadState, p: Vector3) -> void:
	var list: Array = _avoid.get(sq.id, [])
	list.append([p, sim.state.time + 40.0])
	if list.size() > 24:
		list.pop_front()
	_avoid[sq.id] = list


# --- Events ----------------------------------------------------------------------------------------------------------------------

func _on_unit_died(u: UnitState) -> void:
	u.fire_at = Vector3.INF
	u.fire_until = -1.0
	u.post_pos = Vector3.INF
	# GAMEPLAY-01C: the slot is free at once (the body stays where it fell).
	u.fort_slot = ""
	u.fort_pos = Vector3.INF
	u.fort_exit = Vector3.INF
	for sq: SquadState in sim.state.squads.values():
		if sq.fallen.has(u.id):
			validate(sq)
			_next_eval[sq.id] = 0.0
			break


## After a load: runtime tables start fresh; the saved records carry the tactics on. Fire teams
## are checked against the loaded members (a soldier that died is not restored into a team).
func _on_restored() -> void:
	_assess.clear()
	_next_eval.clear()
	_avoid.clear()
	_blind.clear()
	_repos.clear()
	_seen_at.clear()
	_meta_store.clear()
	_site_workers.clear()
	_next_build.clear()
	_site_block.clear()
	_next_garrison.clear()
	for sq: SquadState in sim.state.squads.values():
		validate(sq)
		if sq.tactic != SquadState.Tactic.NONE and sq.order != SquadState.Order.TACTIC:
			sq.order = SquadState.Order.TACTIC


func _meta(sq: SquadState, key: String, fallback: Variant) -> Variant:
	return _meta_store.get(sq.id, {}).get(key, fallback)


func _set_meta(sq: SquadState, key: String, value: Variant) -> void:
	if not _meta_store.has(sq.id):
		_meta_store[sq.id] = {}
	_meta_store[sq.id][key] = value


func _log(sq: SquadState, text: String) -> void:
	events.append({"t": snappedf(sim.state.time, 0.1), "squad": sq.id, "text": text})
	if events.size() > MAX_EVENTS:
		events.pop_front()


# --- Inspection --------------------------------------------------------------------------------------------------------------------

## Lines for the inspector: command, tactic, teams, effectiveness, why / why not. Read from the
## squad's own records and the last assessment - nothing is reconstructed afterwards.
func explain(sq: SquadState) -> Array[String]:
	var out: Array[String] = []
	var now := sim.state.time
	var a := assessment(sq)
	if a.is_empty():
		a = _assess_squad(sq)
	if sq.tactic == SquadState.Tactic.NONE:
		out.append("Tactic: none%s" % ("" if sq.tactic_why == "" else " - " + sq.tactic_why))
	else:
		out.append("Tactic: %s, phase %s, leg %d, for %.0f s - commanded by %s" % [sq.tactic_name().to_upper(), _phase_name(sq), sq.tactic_leg, now - sq.tactic_since, _owner_text(sq)])
		out.append("Why: " + sq.tactic_why)
	if sq.tactic_rejected != "":
		out.append("Not chosen / cancelled: " + sq.tactic_rejected)
	var teams_text: Array[String] = []
	for i in sq.teams.size():
		var names: Array[String] = []
		for id in sq.teams[i]:
			names.append(_name(id) + ("*" if id == sq.team_leaders[i] else ""))
		teams_text.append("%s [%s] %s" % ["AB"[i], ", ".join(names), SquadState.ROLE_NAMES[sq.team_roles[i]]])
	out.append("Fire teams: " + ("; ".join(teams_text) if not teams_text.is_empty() else "-"))
	if not a.is_empty() and int(a.n) > 0:
		var p: Dictionary = a.parts
		out.append("Effectiveness %.2f (size %.2f, suppression %.2f, ammo %.2f, threat %.2f) - suppression avg %.2f, %d of %d pinned, ammunition %d%%, %d casualties" % [a.eff, p.size, p.suppression, p.ammo, p.threat, a.supp, a.pinned, a.n, roundi(float(a.ammo) * 100.0), sq.fallen.size()])
		var threat: Vector3 = a.threat_pos
		if threat.is_finite():
			out.append("Threat: %s at %s, %.0f m, confidence %d%%, enemy estimate %.1f" % [a.threat_src, _xz(threat), a.dist, roundi(float(a.threat_conf) * 100.0), a.enemy_est])
	if sq.tactic_target.is_finite() and sq.tactic != SquadState.Tactic.NONE:
		out.append("Target %s%s%s" % [_xz(sq.tactic_target), "" if sq.tactic_contact < 0 else " (contact #%d)" % sq.tactic_contact, "" if not sq.tactic_dest.is_finite() else ", leg destination " + _xz(sq.tactic_dest)])
	var firing := 0
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u and u.fire_at.is_finite() and now < u.fire_until:
			firing += 1
	if firing > 0:
		out.append("Fire missions: %d soldiers firing at a reported position" % firing)
	return out


func _phase_name(sq: SquadState) -> String:
	match sq.tactic:
		SquadState.Tactic.DEFEND, SquadState.Tactic.REPOSITION:
			return "moving to posts" if sq.tactic_phase == PH_SETUP else "holding"
		SquadState.Tactic.SUPPRESS:
			return "moving to firing posts" if sq.tactic_phase == PH_SETUP else "firing"
		SquadState.Tactic.ASSAULT:
			return ["approach", "support set-up", "advance", "occupy", "final"][clampi(sq.tactic_phase, 0, 4)]
		SquadState.Tactic.FLANK:
			return ["support set-up", "-", "maneuver", "occupy", "closing"][clampi(sq.tactic_phase, 0, 4)]
		SquadState.Tactic.BOUND, SquadState.Tactic.WITHDRAW:
			return "leg %d" % (sq.tactic_leg + 1)
		SquadState.Tactic.REGROUP:
			return "waiting for calm"
		SquadState.Tactic.BUILD:
			return "moving to the site" if sq.tactic_phase == PH_SETUP else "working"
	return str(sq.tactic_phase)


func _owner_text(sq: SquadState) -> String:
	match sq.tactic_owner:
		SquadState.Owner.PLAYER:
			return "the player's order"
		SquadState.Owner.OPERATION:
			return ("operation #%d" % sq.tactic_op) if sq.tactic_op >= 0 else "an operation-level tasking"
		SquadState.Owner.SQUAD:
			return "the squad itself (autonomous)"
	return "nobody"


## Short text for the squad list / HUD.
func short_text(sq: SquadState) -> String:
	if sq.tactic == SquadState.Tactic.NONE:
		return ""
	return "%s · %s" % [sq.tactic_name(), _phase_name(sq)]


func summary() -> Dictionary:
	return {"ticks": ticks, "steps": steps, "step_us_avg": snappedf(float(step_usec) / maxi(ticks, 1), 0.1), "step_us_max": step_usec_max,
		"judged_plans": {"per_tick_max": plans_tick_max, "plan_us_max": plan_usec_max, "tick_us_max": plan_tick_usec_max, "deferred": deferred},
		"started": started.duplicate(), "finished": finished.duplicate(), "decisions": decisions, "refusals": refusals, "replans": replans,
		"posts": {"searches": pos.searches, "evals": pos.evals, "us_avg": snappedf(float(pos.usec) / maxi(pos.searches, 1), 0.1), "us_max": pos.usec_max,
			"flank_plans": pos.flank_plans, "flank_us_avg": snappedf(float(pos.flank_usec) / maxi(pos.flank_plans, 1), 0.1),
			"slot_searches": pos.slot_searches, "slot_us_avg": snappedf(float(pos.slot_usec) / maxi(pos.slot_searches, 1), 0.1), "slot_us_max": pos.slot_usec_max}}


func reset_stats() -> void:
	steps = 0
	step_usec = 0
	step_usec_max = 0
	ticks = 0
	started.clear()
	finished.clear()
	decisions = 0
	refusals = 0
	replans = 0
	pos.searches = 0
	pos.evals = 0
	pos.usec = 0
	pos.usec_max = 0
	pos.flank_plans = 0
	pos.flank_usec = 0
	pos.slot_searches = 0
	pos.slot_usec = 0
	pos.slot_usec_max = 0


# --- Small helpers ---------------------------------------------------------------------------------------------------------------

func _centroid(units: Array) -> Vector3:
	if units.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for u: UnitState in units:
		c += u.position
	return c / units.size()


func _name(id: int) -> String:
	var u := sim.state.get_unit(id)
	return u.unit_name if u else "#%d" % id


func _xz(p: Vector3) -> String:
	return "(%.0f, %.0f)" % [p.x, p.z]


static func _dir_to(from: Vector3, to: Vector3) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


static func _dir_from_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Distance from point p to the 2D segment a-b.
static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf(ap.dot(ab) / l2, 0.0, 1.0)
	return (ap - ab * t).length()

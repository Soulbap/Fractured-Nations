## One strategic decision of an AI faction (AI-COMBAT-STRAT-01): a compact action-list utility scorer.
##
## WarSim owns the war and calls decide(f) every FactionProfile.decision_s; this is the part that chooses
## what the faction does, so the choice and its reasons are in one readable place. No planner: every
## candidate action gets one utility number from a handful of terms, the best ones are carried out while
## forces last, and the list (with what was chosen, skipped and why) is kept in the decision snapshot the
## inspector shows (FactionState.decisions, runtime) - the explanation is the scoring itself.
##
## Actions:
##   REINFORCE   an owned objective with believed enemies near it and too few defenders (the believed
##               enemy comes from IntelSim only; each estimate carries its basis: confirmed / reported /
##               stale / assumed / none);
##   JOIN        more squads for an attack that meets stronger resistance than it started with (no second
##               competing operation: the squads join the running one);
##   GARRISON    a valuable objective without a garrison;
##   ATTACK      an enemy or neutral objective, scored by value, distance, the faction's appetite and the
##               believed threat on the way (StrategicInfluence), only with force to spare beyond the
##               reserve the profile wants.
## Forces are derived from the squad and operation records (garrison / committed / recovering /
## available) - nothing is stored twice. Recovering squads (heavy losses, little ammunition, just
## withdrawn) are not offered to new offensives; a free squad without ammunition is not "available".
## A strategic focus (FactionState.focus_*) keeps a faction on what it chose for a commitment window
## unless something clearly more urgent appears (hysteresis).
class_name StrategicDecision
extends RefCounted

var ws: WarSim
var sim: WorldSim
## A critical threat overrides the focus when its utility beats the focus' action by this factor.
var override_factor := 1.4
## Squads whose average ammunition is below this fraction are not available for offensives.
var min_ammo := 0.3
## A squad leaving a failed operation recovers at least this long (s).
var recover_s := 120.0
## AI-WAR-LOGISTICS-01: objective id -> the largest believed attacker strength near it in the last 150 s (runtime).
var _peak := {}
## Measurements.
var decisions := 0
var usec := 0
var usec_max := 0
var joins := 0
var focus_changes := 0


func _init(p_ws: WarSim) -> void:
	ws = p_ws
	sim = p_ws.sim


func decide(f: FactionState) -> void:
	var t0 := Time.get_ticks_usec()
	decisions += 1
	var p := ws.profile(f)
	var now := sim.state.time
	ws.influence.update()
	var notes: Array[String] = []
	var snap := {"t": snappedf(now, 0.1), "threats": [], "candidates": [], "actions": [], "investigate": "", "attack": "",
		"intel": ws.intel.counts(f.id), "forces": {}, "focus": "", "exposed": []}
	# 0. Depleted squads go home to recover.
	var hq := ws.war.objective(f.hq_objective)
	for sq: SquadState in ws.squads_of(f.id):
		if sq.op_id < 0 and sq.members.size() < p.min_squad_size and hq and hq.owner == f.id and sq.station_objective != hq.id \
				and WarSim._flat(ws.squad_center(sq), hq.position) > hq.radius * 2.0:
			sq.recover_until = now + recover_s
			ws.start_operation(f.id, OperationState.Type.REINFORCE, [sq.id], hq.id)
			notes.append("%s home" % sq.squad_name)
	var forces := forces_of(f, p)
	snap.forces = {"new": forces.new, "transported": forces.transported, "garrison": forces.garrison.size(), "committed": forces.committed.size(), "recovering": forces.recovering.size(),
		"available": forces.available.size(), "soldiers_available": forces.soldiers_available, "soldiers_total": forces.soldiers_total, "reserve_keep": forces.reserve_keep}
	var free: Array = forces.available.duplicate()
	var actions: Array = []
	_collect_defence(f, p, free, actions, snap)
	_collect_counters(f, p, actions, now)
	_collect_joins(f, p, free, actions)
	_collect_garrisons(f, p, actions)
	_collect_attacks(f, p, forces, actions, snap, now)
	_apply_focus(f, p, actions, now)
	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.utility > b.utility)
	var chosen: Array = []
	for act: Dictionary in actions:
		if act.status != "candidate":
			continue
		var res := _execute(f, p, act, free, forces, notes)
		act.status = res
		if res == "chosen":
			chosen.append(act)
	_update_focus(f, p, chosen, now)
	snap.focus = describe_focus(f)
	snap.actions = actions.map(func(a: Dictionary) -> Dictionary:
		return {"kind": a.kind, "name": a.name, "utility": snappedf(a.utility, 0.01), "need": a.get("need", 0), "basis": a.get("basis", ""), "status": a.status, "note": a.get("note", "")}).slice(0, 8)
	for e: Dictionary in ws.influence.exposed(f.id, 600.0).slice(0, 3):
		snap.exposed.append("%s %.1f" % [e.objective.obj_name, e.threat])
	# 2b. An uncertain report near ground the faction holds: one squad goes and looks.
	ws._investigate(f, p, free, notes, snap)
	# 4. Forward deployment: free squads idling at the HQ move up to the front.
	var moved := ws._forward(f, p, free)
	if moved != "":
		notes.append(moved)
	f.last_decision = "; ".join(notes) if not notes.is_empty() else "hold"
	snap["notes"] = f.last_decision
	f.decisions.append(snap)
	if f.decisions.size() > WarSim.DECISIONS_MAX:
		f.decisions.pop_front()
	var dt := Time.get_ticks_usec() - t0
	usec += dt
	usec_max = maxi(usec_max, dt)


# --- Forces -----------------------------------------------------------------------------------------

## The faction's squads sorted into garrison / committed / recovering / available, from the squad and
## operation records (and the squads' own assessment of their ammunition).
func forces_of(f: FactionState, p: FactionProfile) -> Dictionary:
	var now := sim.state.time
	var out := {"garrison": [], "committed": [], "recovering": [], "available": [], "soldiers_available": 0, "soldiers_total": 0, "reserve_keep": 0, "new": 0, "transported": 0}
	var free := ws._free_squads(f, p)
	for sq: SquadState in ws.squads_of(f.id):
		out.soldiers_total += sq.members.size()
		if sq.origin == "recruit" and now - sq.born_at < 180.0:
			out.new += 1
		for id in sq.members:
			var su := sim.state.get_unit(id)
			if su and su.vehicle_id >= 0:
				out.transported += 1
				break
		if sq.op_id >= 0:
			out.committed.append(sq.id)
		elif is_recovering(sq, p):
			out.recovering.append(sq.id)
		elif free.has(sq.id):
			out.available.append(sq.id)
			out.soldiers_available += sq.members.size()
		else:
			out.garrison.append(sq.id)
	out.reserve_keep = ceili(out.soldiers_total * p.reserve_ratio)
	return out


## A squad that should not be offered to a new offensive: told to recover and not done yet, too few
## soldiers, or nearly out of ammunition (recovery is regrouping and waiting - no free supplies).
func is_recovering(sq: SquadState, p: FactionProfile) -> bool:
	if sq.recover_until > sim.state.time or sq.members.size() < p.min_squad_size or sq.recover_site >= 0:
		return true
	var a := sim.tactics.assessment(sq)
	return not a.is_empty() and int(a.n) > 0 and float(a.ammo) < min_ammo


# --- Candidate actions ----------------------------------------------------------------------------------

## How the faction knows what it believes near pos: confirmed (seen in the last seconds), reported (a
## recent report with confidence), stale (old or weak), none.
func basis_near(f: int, pos: Vector3, r: float) -> String:
	var best := "none"
	for c: ContactState in ws.intel.contacts_near(f, pos, r):
		if c.status == ContactState.Status.OBSERVED:
			return "confirmed"
		if c.status == ContactState.Status.REPORTED and c.conf >= 0.45:
			best = "reported"
		elif best == "none":
			best = "stale"
	return best


func _collect_defence(f: FactionState, p: FactionProfile, free: Array, actions: Array, snap: Dictionary) -> void:
	for o: ObjectiveState in ws.war.owned_by(f.id):
		var enemies := ws.intel.threat_near(f.id, o.position, o.radius + p.threat_radius)
		var was: bool = ws.threatened.get(o.id, false)
		ws.threatened[o.id] = enemies > 0
		if enemies > 0 and not was:
			ws.log_event(f.id, "threat", "Enemy forces reported near %s (about %d)" % [o.obj_name, enemies], o.position)
		if enemies <= 0:
			continue
		var basis := basis_near(f.id, o.position, o.radius + p.threat_radius)
		var defenders := ws._strength_near(f.id, o.position, o.radius + 150.0) + ws._incoming(f.id, o.id)
		var cids := []
		for c: ContactState in ws.intel.contacts_near(f.id, o.position, o.radius + p.threat_radius).slice(0, 3):
			cids.append("#%d %s %d%%" % [c.id, c.status_name(), roundi(c.conf * 100.0)])
		var entry := {"objective": o.obj_name, "enemies": enemies, "defenders": defenders, "contacts": cids, "action": "defenders suffice", "basis": basis}
		snap.threats.append(entry)
		var want := enemies * p.threat_ratio
		if defenders >= want:
			continue
		var need := ceili(want) - defenders
		var pressure := ws.influence.threat_at(f.id, o.position, o.radius + 300.0)
		var u := p.defend_weight * (1.0 + 0.9 * o.value + (3.0 if o.is_hq() else 0.0)) * clampf(float(need) / maxf(want, 1.0), 0.3, 1.5) + minf(pressure * 0.15, 2.0)
		if basis == "stale":
			u *= 0.6  # an old report is not a reason to strip other ground
		actions.append({"kind": "reinforce", "name": o.obj_name, "objective": o.id, "utility": u, "need": need, "basis": basis, "status": "candidate",
			"enemies": enemies, "defenders": defenders, "entry": entry})



## AI-WAR-LOGISTICS-01: limited counterattacks by the local reserve of a defended objective. A candidate only when
##  - nothing of the kind runs there and the last one ended long enough ago (a failed one blocks for 7 minutes),
##  - the attackers are believed (reported with confidence) outside the objective's core, within counter_range_m,
##  - they look weakened (the believed strength fell below 65% of its peak in the last 150 s, or the reserve alone is
##    at least twice their number) and a covered flank or a short assault is possible (the squad tactics decide),
##  - the reserve is fit (effectiveness 0.6, ammunition 40%, five soldiers) and out-numbers them by counter_ratio,
##  - the objective stays protected: the rest of the garrison, without the reserve, still holds a squad's strength.
## Reads only the faction's own picture (IntelSim) and its own squads.
func _collect_counters(f: FactionState, p: FactionProfile, actions: Array, now: float) -> void:
	for o: ObjectiveState in ws.war.owned_by(f.id):
		if float(ws.war.counter_cool.get(o.id, 0.0)) > now:
			continue
		var running := false
		for op: OperationState in ws.war.active_operations(f.id):
			if op.type == OperationState.Type.COUNTER and op.target_objective == o.id:
				running = true
		if running:
			continue
		var enemies := 0
		var target := Vector3.ZERO
		var wsum := 0.0
		for c: ContactState in ws.intel.contacts_near(f.id, o.position, o.radius + p.counter_range_m):
			if c.status == ContactState.Status.LOST or c.status == ContactState.Status.STALE or c.conf < 0.45:
				continue
			if WarSim._flat(c.pos, o.position) < o.radius * 0.35:
				continue  # in the core: that is a defence fight, not a counterattack
			var w := float(maxi(c.strength, 1))
			enemies += c.strength
			target += c.pos * w
			wsum += w
		var pk: Dictionary = _peak.get(o.id, {"v": 0, "t": now})
		if now - float(pk.t) > 150.0 or enemies > int(pk.v):
			pk = {"v": maxi(enemies, 0), "t": now}
		_peak[o.id] = pk
		if enemies <= 0 or wsum <= 0.0:
			continue
		target /= wsum
		# The garrison of this objective: the reserve first, then fit sector squads (never the last one).
		var garrison: Array = []
		for sq: SquadState in ws.squads_of(f.id):
			if sq.station_objective == o.id and sq.op_id < 0 and sq.tactic_owner != SquadState.Owner.PLAYER and not sq.members.is_empty():
				garrison.append(sq)
		if garrison.size() < 2:
			continue
		garrison.sort_custom(func(a: SquadState, b: SquadState) -> bool:
			return (a.defence_role == "reserve") and not (b.defence_role == "reserve"))
		var reserve: Array = []
		var res_soldiers := 0
		var total := 0
		for sq: SquadState in garrison:
			total += sq.members.size()
		for sq: SquadState in garrison:
			var a := sim.tactics.assessment(sq)
			if a.is_empty():
				a = sim.tactics._assess_squad(sq)
			var fit: bool = float(a.get("eff", 0.0)) >= 0.6 and float(a.get("ammo", 1.0)) >= 0.4 and sq.members.size() >= 5
			if sq.defence_role == "reserve" and fit or (reserve.is_empty() and sq.defence_role != "reserve" and fit and garrison.size() >= 3):
				reserve.append(sq)
				res_soldiers += sq.members.size()
				break
		var why_not := ""
		var weak: bool = float(enemies) <= float(pk.v) * 0.65 or float(res_soldiers) >= 2.0 * float(enemies)
		if reserve.is_empty():
			why_not = "no fit reserve (effectiveness, ammunition or numbers)"
		elif float(res_soldiers) < p.counter_ratio * float(enemies):
			why_not = "the reserve (%d) does not out-number the %d attackers by %.1f" % [res_soldiers, enemies, p.counter_ratio]
		elif not weak:
			why_not = "the attackers are not weakened (%d believed, peak %d)" % [enemies, int(pk.v)]
		elif total - res_soldiers < mini(6, int(enemies * 0.5) + 3):
			why_not = "the objective would be left with %d soldiers" % (total - res_soldiers)
		elif not ws.routes.passable(ws._ground(target)):
			why_not = "no route to the attackers"
		var u := p.defend_weight * (1.4 + 0.5 * o.value) * clampf(float(res_soldiers) / maxf(float(enemies) * p.counter_ratio, 1.0), 0.5, 1.6)
		var act := {"kind": "counter", "name": o.obj_name, "objective": o.id, "utility": u, "need": res_soldiers, "basis": basis_near(f.id, target, 120.0), "status": "candidate",
			"squads": reserve.map(func(sq: SquadState) -> int: return sq.id), "target": target, "enemies": enemies,
			"note": "%d attackers believed (peak %d), reserve %d" % [enemies, int(pk.v), res_soldiers]}
		if why_not != "":
			act.status = "skipped"
			act.note = why_not
		actions.append(act)

func _collect_joins(f: FactionState, p: FactionProfile, free: Array, actions: Array) -> void:
	for op: OperationState in ws.war.active_operations(f.id):
		if op.type != OperationState.Type.ATTACK or op.phase != OperationState.Phase.ENGAGING or op.stage < OperationState.Stage.DEPLOY \
				or op.stage == OperationState.Stage.WITHDRAW:
			continue
		var obj := ws.war.objective(op.target_objective)
		if obj == null:
			continue
		var soldiers := 0
		for sid in op.squads:
			soldiers += ws.strength(sim.state.get_squad(sid))
		var reported := ws.intel.threat_near(f.id, obj.position, obj.radius + 150.0)
		var status := ws.coord._op_status(op, ws.coord._squads(op), obj)
		var stronger: bool = reported * p.attack_ratio * 0.8 > soldiers
		if not stronger and not (status.eff < 0.65 and op.stage >= OperationState.Stage.ASSAULT):
			continue
		var need := maxi(ceili(reported * p.attack_ratio) - soldiers, 6)
		actions.append({"kind": "join", "name": "attack on %s (#%d)" % [obj.obj_name, op.id], "op": op.id, "objective": obj.id,
			"utility": 5.0 + 2.5 * clampf(float(reported) / maxf(soldiers, 1.0), 0.0, 1.5) + (1.0 if status.eff < 0.65 else 0.0), "need": need,
			"basis": basis_near(f.id, obj.position, obj.radius + 150.0), "status": "candidate",
			"note": "%d believed defenders against %d attackers, effectiveness %.2f" % [reported, soldiers, status.eff]})


func _collect_garrisons(f: FactionState, p: FactionProfile, actions: Array) -> void:
	if p.garrison_squads <= 0:
		return
	for o: ObjectiveState in ws.war.owned_by(f.id):
		if o.is_hq() or o.value < p.garrison_min_value:
			continue
		if ws._garrison_count(f.id, o.id) + ws._incoming_squads(f.id, o.id) >= p.garrison_squads:
			continue
		actions.append({"kind": "garrison", "name": o.obj_name, "objective": o.id, "utility": 2.0 + 0.5 * o.value, "need": 1, "basis": "", "status": "candidate"})


func _collect_attacks(f: FactionState, p: FactionProfile, forces: Dictionary, actions: Array, snap: Dictionary, now: float) -> void:
	var attacks := ws.war.active_operations(f.id).filter(func(o: OperationState) -> bool: return o.type == OperationState.Type.ATTACK).size()
	var beyond := int(forces.soldiers_available) - int(forces.reserve_keep)
	if now < f.recovery_until:
		snap.notes_extra = "recovering %.0f s" % (f.recovery_until - now)
		return
	if attacks >= p.max_attacks:
		return
	if beyond < p.min_attack_soldiers:
		return
	var owned := ws.war.owned_by(f.id)
	for o: ObjectiveState in ws.war.all_objectives():
		if o.owner == f.id or ws._attacked_by(f.id, o.id):
			continue
		# Distance from the faction's nearest held objective (its front), not from where the free squads stand.
		var d := INF
		var from := Vector3.ZERO
		for h: ObjectiveState in owned:
			var dh := WarSim._flat(h.position, o.position)
			if dh < d:
				d = dh
				from = h.position
		if d > p.max_attack_distance:
			continue
		var defenders := ws.intel.threat_near(f.id, o.position, o.radius + 200.0)
		var basis := basis_near(f.id, o.position, o.radius + 200.0)
		if defenders == 0 and o.owner >= 0:
			defenders = o.value * 4  # nothing reported there: assume a garrison (labelled as such)
			basis = "assumed"
			if o.is_hq():
				defenders = maxi(defenders, 24)
		elif defenders == 0:
			basis = "none reported"
		var need := maxi(ceili(defenders * p.attack_ratio), p.min_attack_soldiers)
		var score := o.value * p.w_value - d / 1000.0 * p.w_distance
		score += p.w_neutral if o.owner < 0 else p.w_enemy
		var retake := ws._lost_by(f.id, o)
		if retake:
			score += p.w_retake
		# The believed enemy on the way (not the objective itself): an attack is not sent through a
		# known concentration.
		var risk := ws.influence.route_risk(f.id, [from, o.position], 250.0) - float(ws.intel.threat_near(f.id, o.position, o.radius + 250.0)) * 0.5
		risk = maxf(risk, 0.0)
		var risk_pen := p.route_risk_weight * clampf(risk / maxf(float(beyond), 1.0), 0.0, 1.5) * 2.0
		score -= risk_pen
		# AI-WAR-LOGISTICS-01: what the logistics allow. A march by vehicle costs less of the distance term; a
		# distant target without transport is a long foot march; the ammunition the depots hold must cover the force.
		var logi_note := ""
		var logi_skip := ""
		if ws.supply.has_bases(f.id):
			var li := ws.supply.attack_inputs(f, o, from, maxi(need, p.min_attack_soldiers))
			if li.mech:
				score += d / 1000.0 * p.w_distance * 0.5
			elif d > p.mech_min_m * 2.0:
				score -= minf(li.foot_min * 0.04, 2.0)
			var ammo_short: bool = li.have_kg < li.need_kg
			if ammo_short:
				score -= 1.5 + 2.0 * clampf(1.0 - li.have_kg / maxf(li.need_kg, 1.0), 0.0, 1.0)
			if li.have_kg < li.need_kg * 0.25:
				logi_skip = "ammunition stock %d kg of the %d kg the force needs" % [roundi(li.have_kg), roundi(li.need_kg)]
			logi_note = "march ~%d min %s%s, ammunition %d of %d kg" % [roundi(li.travel_min), "by vehicle" if li.mech else "on foot", "" if li.mech or li.seats > 0 or d < p.mech_min_m else " (no free transport)", roundi(li.have_kg), roundi(li.need_kg)]
		var act := {"kind": "attack", "name": o.obj_name, "objective": o.id, "utility": score, "need": need, "basis": basis, "status": "candidate",
			"retake": retake, "defenders": defenders, "km": d / 1000.0, "risk": risk, "logi": logi_note}
		if logi_skip != "":
			act.status = "skipped"
			act.note = logi_skip
		elif need > beyond:
			act.status = "skipped"
			act.note = "needs %d soldiers, %d beyond the reserve" % [need, beyond]
		snap.candidates.append({"name": o.obj_name, "score": snappedf(score, 0.01), "value": o.value, "km": snappedf(d / 1000.0, 0.1), "defenders": defenders,
			"basis": basis, "need": need, "retake": retake, "skipped": need > beyond or logi_skip != "", "logi": logi_note if logi_skip == "" else logi_note + " | " + logi_skip})
		actions.append(act)
	snap.candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	snap["candidates"] = snap.candidates.slice(0, 6)


# --- Focus ------------------------------------------------------------------------------------------------------

func _class(kind: String) -> String:
	return "defence" if kind == "reinforce" or kind == "garrison" or kind == "counter" else "attack"


## What the faction is committed to adds a bonus to matching actions (same class, same objective) while its
## window lasts.
func _apply_focus(f: FactionState, p: FactionProfile, actions: Array, now: float) -> void:
	if f.focus_kind == "" or now > f.focus_until:
		return
	for act: Dictionary in actions:
		if _class(act.kind) == f.focus_kind and int(act.get("objective", -2)) == f.focus_objective:
			act.utility += p.focus_bonus
			act.note = (str(act.get("note", "")) + " focus +%.1f" % p.focus_bonus).strip_edges()


func _update_focus(f: FactionState, p: FactionProfile, chosen: Array, now: float) -> void:
	if chosen.is_empty():
		return
	var top: Dictionary = chosen[0]
	var cls := _class(top.kind)
	var expired := f.focus_kind == "" or now > f.focus_until
	var same: bool = cls == f.focus_kind and int(top.get("objective", -2)) == f.focus_objective
	if same:
		f.focus_until = maxf(f.focus_until, now + p.focus_commit_s * 0.5)
		return
	if expired or top.utility > f.focus_utility * override_factor:
		focus_changes += 1
		f.focus_kind = cls
		f.focus_objective = int(top.get("objective", -1))
		f.focus_since = now
		f.focus_until = now + p.focus_commit_s
		f.focus_utility = top.utility
		f.focus_why = "%s %s (utility %.1f%s)" % [top.kind, top.name, top.utility, ", overrides the previous focus" if not expired else ""]


func describe_focus(f: FactionState) -> String:
	if f.focus_kind == "" or sim.state.time > f.focus_until:
		return "none"
	var o := ws.war.objective(f.focus_objective)
	return "%s %s until %d:%02d - %s" % [f.focus_kind, o.obj_name if o else "-", int(f.focus_until / 60.0) % 60, int(f.focus_until) % 60, f.focus_why]


# --- Carrying actions out ---------------------------------------------------------------------------------------

## Returns "chosen", or the reason it was not carried out.
func _execute(f: FactionState, p: FactionProfile, act: Dictionary, free: Array, forces: Dictionary, notes: Array[String]) -> String:
	match act.kind:
		"reinforce":
			var o := ws.war.objective(act.objective)
			var picked := ws._pick_near(free, o.position, act.need)
			if picked.is_empty():
				act.entry.action = "no free squads"
				return "no free squads"
			var rop := ws.start_operation(f.id, OperationState.Type.REINFORCE, picked, o.id)
			if rop == null:
				return "no route"
			rop.reason = "about %d enemy reported near %s (%s), %d defenders" % [act.enemies, o.obj_name, act.basis, act.defenders]
			act.entry.action = "reinforce with %d squads" % picked.size()
			notes.append("reinforce %s" % o.obj_name)
			_take(free, forces, picked)
			return "chosen"
		"join":
			var op := ws.war.operation(act.op)
			var obj := ws.war.objective(act.objective)
			if op == null or not op.is_active() or obj == null:
				return "operation ended"
			var picked := ws._pick_near(free.filter(func(sid: int) -> bool: return WarSim._flat(ws.squad_center(sim.state.get_squad(sid)), obj.position) <= 3500.0), obj.position, act.need)
			if picked.is_empty():
				return "no free squad within 3.5 km"
			if ws.join_operation(op, picked, "reinforcement: " + str(act.get("note", ""))):
				joins += 1
				notes.append("%d squads join the attack on %s" % [picked.size(), obj.obj_name])
				_take(free, forces, picked)
				return "chosen"
			return "no route"
		"counter":
			var o := ws.war.objective(act.objective)
			var cop := ws.start_operation(f.id, OperationState.Type.COUNTER, act.squads, o.id, act.target)
			if cop == null:
				return "no squad could be tasked"
			cop.reason = "%d attackers believed near %s (%s), reserve of %d counterattacks" % [act.enemies, o.obj_name, act.basis, act.need]
			notes.append("counterattack at %s" % o.obj_name)
			return "chosen"
		"garrison":
			var o := ws.war.objective(act.objective)
			var picked := ws._pick_near(free, o.position, 1, true)
			if picked.is_empty():
				return "no free squad"
			ws.start_operation(f.id, OperationState.Type.DEFEND, picked, o.id)
			notes.append("garrison %s" % o.obj_name)
			_take(free, forces, picked)
			return "chosen"
		"attack":
			var o := ws.war.objective(act.objective)
			var attacks := ws.war.active_operations(f.id).filter(func(x: OperationState) -> bool: return x.type == OperationState.Type.ATTACK).size()
			if attacks >= p.max_attacks:
				return "%d attacks running" % attacks
			var free_soldiers := 0
			for sid in free:
				free_soldiers += ws.strength(sim.state.get_squad(sid))
			var beyond := free_soldiers - int(forces.reserve_keep)
			if act.need > beyond:
				return "needs %d soldiers, %d beyond the reserve" % [act.need, beyond]
			var commit := maxi(act.need, int(beyond * p.attack_commit))
			var picked := ws._pick_near(free, o.position, commit)
			# AI-WAR-LOGISTICS-01: readiness - is the force supplied? (full / delay for resupply / reduced / cancel)
			var ready := {"verdict": "go", "why": "", "squads": picked, "notes": []}
			if ws.supply.has_bases(f.id):
				ready = ws.supply.assess_attack(f, picked, o)
			if ready.verdict == "delay":
				act.note = "delayed: " + ready.why
				notes.append("attack %s delayed for resupply" % o.obj_name)
				return "delayed: " + ready.why
			if ready.verdict == "cancel":
				act.note = "cancelled: " + ready.why
				return "cancelled: " + ready.why
			picked = ready.squads
			var op := ws.start_operation(f.id, OperationState.Type.ATTACK, picked, o.id)
			if op == null:
				return "no route"
			op.readiness = {"verdict": ready.verdict, "why": ready.why, "need_kg": ready.get("need_kg", 0.0), "t": sim.state.time}
			op.reason = "best target: utility %.1f, %d defenders %s, needs %d%s" % [act.utility, act.defenders, act.basis, act.need, "" if act.risk < 0.5 else ", believed threat on the way %.1f" % act.risk]
			if ready.verdict != "go":
				op.reason += "; " + ready.verdict + ": " + ready.why
				op.supply_why = ready.verdict + ": " + ready.why
			notes.append("attack %s (%d)" % [o.obj_name, op.start_strength])
			act.note = op.reason
			_take(free, forces, picked)
			return "chosen"
	return "unknown"


func _take(free: Array, forces: Dictionary, picked: Array) -> void:
	for sid in picked:
		free.erase(sid)
		forces.soldiers_available -= ws.strength(sim.state.get_squad(sid))

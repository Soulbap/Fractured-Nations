## Combat diagnostics for scripted engagements (GAMEPLAY-02A): a time series and totals of what happened between an
## attacking and a defending group of squads - where the squads were, what they were told, how many stood / moved /
## searched for cover, how much suppression each side gave and took, shots, hits, casualties, blocked moves, the
## operation's stages and why it waited or withdrew.
##
## Test-only: a test creates it, calls sample() about once a simulated second and reads result(). It reads the records
## and the shot / damage / death signals; it changes nothing and costs nothing when no test uses it.
class_name CombatDiag
extends RefCounted

var sim: WorldSim
var op: OperationState
var obj_pos := Vector3.INF
var att: Array = []
var defs: Array = []
var att_f := -1
var def_f := -1
var t0 := 0.0
var rows: Array = []
var _next := 0.0
var interval := 5.0
var totals := {}
var squads := {}
var stages: Array = []
var first_contact := -1.0
var first_kill := {}
var _last_stage := -99
var _last_t := -1.0
## GAMEPLAY-03A: the defenders' side - the capture radius, first sightings each way (time, distance), first hits,
## defender soldier-seconds seen by an attacker / inside the capture radius, post changes, fortification slots given up.
var obj_r := 0.0
var seen := {}
var first_hit := {}
var def_exposed_s := 0.0
var def_inside_s := 0.0
var def_post_changes := 0
var def_slots_left := 0
var def_slot_s := 0.0
var _posts := {}
var _slots := {}


func start(p_sim: WorldSim, p_op: OperationState, attackers: Array, defenders: Array, objective_pos: Vector3, objective_r := 0.0) -> void:
	obj_r = objective_r
	sim = p_sim
	op = p_op
	att = attackers
	defs = defenders
	obj_pos = objective_pos
	att_f = (attackers[0] as SquadState).faction if not attackers.is_empty() else -1
	def_f = (defenders[0] as SquadState).faction if not defenders.is_empty() else -1
	t0 = sim.state.time
	_next = t0
	for k in ["att_shots", "def_shots", "att_hits", "def_hits", "att_kills", "def_kills", "att_mission_shots", "att_supp_given", "def_supp_given",
			"att_struct_hits", "def_struct_hits"]:
		totals[k] = 0.0
	for sq: SquadState in attackers + defenders:
		squads[sq.id] = {"name": sq.squad_name, "side": "att" if sq.faction == att_f else "def", "moving_s": 0.0, "still_s": 0.0, "cover_s": 0.0,
			"suppressed_soldier_s": 0.0, "pinned_soldier_s": 0.0, "blocked": 0, "progress_m": 0.0, "start_d": _dist(sq), "best_d": _dist(sq), "tactics": {}}
	sim.state.shot_fired.connect(_on_shot)
	sim.state.unit_damaged.connect(_on_damaged)
	sim.state.unit_died.connect(_on_died)


func stop() -> void:
	if sim.state.shot_fired.is_connected(_on_shot):
		sim.state.shot_fired.disconnect(_on_shot)
		sim.state.unit_damaged.disconnect(_on_damaged)
		sim.state.unit_died.disconnect(_on_died)


func _side(f: int) -> String:
	return "att" if f == att_f else ("def" if f == def_f else "")


func _on_shot(shot: Dictionary) -> void:
	var s := sim.state.get_unit(int(shot.shooter))
	if s == null:
		return
	var side := _side(s.faction)
	if side == "":
		return
	totals[side + "_shots"] += 1
	if first_contact < 0.0:
		first_contact = sim.state.time - t0
	if s.fire_at.is_finite() and sim.state.time < s.fire_until and s.target_id < 0:
		totals[side + "_mission_shots"] = float(totals.get(side + "_mission_shots", 0.0)) + 1
	if String(shot.get("blocker", "")) == "structure":
		totals[side + "_struct_hits"] += 1


func _on_damaged(t: UnitState, _amount: float, _zone: int, source: int) -> void:
	var s := sim.state.get_unit(source)
	if s == null:
		return
	var side := _side(s.faction)
	if side != "" and t.faction != s.faction:
		totals[side + "_hits"] += 1
		if not first_hit.has(side):
			first_hit[side] = snappedf(sim.state.time - t0, 0.1)


func _on_died(u: UnitState) -> void:
	var k := sim.state.get_unit(u.killer_id)
	if k == null:
		return
	var side := _side(k.faction)
	if side != "" and u.faction != k.faction:
		totals[side + "_kills"] += 1
		if not first_kill.has(side):
			first_kill[side] = snappedf(sim.state.time - t0, 0.1)


func _dist(sq: SquadState) -> float:
	if sim.state.get_squad(sq.id) == null or sq.members.is_empty() or not obj_pos.is_finite():
		return -1.0
	var c := sim.squads._centroid(sq)
	return Vector2(c.x - obj_pos.x, c.z - obj_pos.z).length()


## Call about once a simulated second (time is measured, not assumed).
func sample() -> void:
	var now := sim.state.time
	var dt := clampf(now - _last_t, 0.0, 5.0) if _last_t >= 0.0 else 0.0
	_last_t = now
	if op and int(op.stage) != _last_stage:
		_last_stage = int(op.stage)
		stages.append({"t": snappedf(now - t0, 0.1), "stage": op.stage_name(), "why": op.stage_why})
	var side_supp := {"att": 0.0, "def": 0.0}
	var side_n := {"att": 0, "def": 0}
	for sq: SquadState in att + defs:
		var d: Dictionary = squads[sq.id]
		if sim.state.get_squad(sq.id) == null:
			continue
		var side: String = d.side
		var moving := 0
		for id in sq.members:
			var u := sim.state.get_unit(id)
			if u == null or not u.alive:
				continue
			side_n[side] += 1
			var su := u.suppression_at(now)
			side_supp[side] += su
			if su >= sim.brain.suppressed_at:
				d.suppressed_soldier_s += dt
			if su >= sim.brain.pinned_at:
				d.pinned_soldier_s += dt
			if Vector2(u.velocity.x, u.velocity.z).length() > 0.6 or (u.order == UnitState.Order.MOVE and not u.has_body):
				moving += 1
			if u.tactic == UnitState.Tactic.SEEK_COVER or u.tactic == UnitState.Tactic.IN_COVER:
				d.cover_s += dt / maxf(sq.members.size(), 1)
			if u.move_state == UnitState.MoveState.BLOCKED and u.nav_reason != "":
				d.blocked += 1
				u.nav_reason = ""  # counted once
		if moving * 2 >= sq.members.size():
			d.moving_s += dt
		else:
			d.still_s += dt
		var dist := _dist(sq)
		if dist >= 0.0 and dist < float(d.best_d):
			d.best_d = dist
		var tn := sq.tactic_name()
		d.tactics[tn] = float(d.tactics.get(tn, 0.0)) + dt
	totals.att_supp_given += side_supp.def
	totals.def_supp_given += side_supp.att
	_sample_defence(now, dt)
	if now >= _next:
		_next = now + interval
		var parts: Array = []
		for sq: SquadState in att + defs:
			if sim.state.get_squad(sq.id) == null:
				parts.append({"sq": sq.squad_name, "n": 0})
				continue
			var a := sim.tactics.assessment(sq)
			parts.append({"sq": sq.squad_name, "role": SquadState.OP_ROLE_NAMES[sq.op_role], "tac": "%s/%d" % [sq.tactic_name(), sq.tactic_phase], "order": sq.order_name(),
				"n": sq.members.size(), "d": roundi(_dist(sq)), "supp": snappedf(float(a.get("supp", 0.0)), 0.01), "eff": snappedf(float(a.get("eff", 0.0)), 0.01),
				"ammo": snappedf(float(a.get("ammo", 1.0)), 0.01), "seen": int(a.get("seen_n", 0))})
		rows.append({"t": roundi(now - t0), "stage": op.stage_name() if op else "-", "wait": op.wait_reason if op else "", "sq": parts,
			"att_supp_avg": snappedf(side_supp.att / maxi(side_n.att, 1), 0.01), "def_supp_avg": snappedf(side_supp.def / maxi(side_n.def, 1), 0.01)})


func _sample_defence(now: float, dt: float) -> void:
	var def_ids := {}
	for sq: SquadState in defs:
		if sim.state.get_squad(sq.id) == null:
			continue
		for id in sq.members:
			var u := sim.state.get_unit(id)
			if u == null or not u.alive:
				continue
			def_ids[id] = u
			if obj_r > 0.0 and Vector2(u.position.x - obj_pos.x, u.position.z - obj_pos.z).length() <= obj_r:
				def_inside_s += dt
			if u.post_pos.is_finite():
				var last: Vector3 = _posts.get(id, Vector3.INF)
				if last.is_finite() and Vector2(last.x - u.post_pos.x, last.z - u.post_pos.z).length() > 3.0:
					def_post_changes += 1
				_posts[id] = u.post_pos
			if u.fort_slot != "":
				def_slot_s += dt
			elif _slots.get(id, "") != "":
				def_slots_left += 1
			_slots[id] = u.fort_slot
			# The defender's sightings of the attackers.
			if not seen.has("def") and u.target_visible and u.target_id >= 0:
				var t := sim.state.get_unit(u.target_id)
				if t and t.faction == att_f:
					seen["def"] = {"t": snappedf(now - t0, 0.1), "d": roundi(Vector2(t.position.x - u.position.x, t.position.z - u.position.z).length())}
	var exposed := {}
	for sq: SquadState in att:
		if sim.state.get_squad(sq.id) == null:
			continue
		for id in sq.members:
			var u := sim.state.get_unit(id)
			if u == null or not u.alive or not u.target_visible or not def_ids.has(u.target_id):
				continue
			exposed[u.target_id] = true
			if not seen.has("att"):
				var t: UnitState = def_ids[u.target_id]
				seen["att"] = {"t": snappedf(now - t0, 0.1), "d": roundi(Vector2(t.position.x - u.position.x, t.position.z - u.position.z).length())}
	def_exposed_s += dt * exposed.size()


func result() -> Dictionary:
	var dur := maxf(sim.state.time - t0, 1.0)
	var per := {}
	for id in squads:
		var d: Dictionary = squads[id]
		var sq := sim.state.get_squad(id)
		per[d.name] = {"side": d.side, "moving_s": roundi(d.moving_s), "still_s": roundi(d.still_s), "cover_soldier_s": roundi(d.cover_s),
			"suppressed_soldier_s": roundi(d.suppressed_soldier_s), "pinned_soldier_s": roundi(d.pinned_soldier_s), "blocked": d.blocked,
			"start_d": roundi(d.start_d), "best_d": roundi(d.best_d), "left": sq.members.size() if sq else 0, "tactics": d.tactics}
	return {"duration_s": roundi(dur), "first_contact_s": snappedf(first_contact, 0.1), "first_kill": first_kill, "totals": totals,
		"def_supp_avg": snappedf(float(totals.att_supp_given) / dur / maxf(_count(defs, true), 1.0), 0.01),
		"att_supp_avg": snappedf(float(totals.def_supp_given) / dur / maxf(_count(att, true), 1.0), 0.01),
		"att_accuracy": snappedf(float(totals.att_hits) / maxf(float(totals.att_shots), 1.0), 0.003), "def_accuracy": snappedf(float(totals.def_hits) / maxf(float(totals.def_shots), 1.0), 0.003),
		"squads": per, "stages": stages, "withdraw_why": op.withdraw_why if op else "", "outcome": op.outcome if op else "", "rows": rows,
		"defence": {"first_seen": seen, "first_hit": first_hit, "def_exposed_s": roundi(def_exposed_s), "def_inside_s": roundi(def_inside_s),
			"def_slot_s": roundi(def_slot_s), "def_post_changes": def_post_changes, "def_slots_left": def_slots_left}}


## Soldiers the squads started with (start = true) or have now.
func _count(sqs: Array, start: bool) -> int:
	var n := 0
	for sq: SquadState in sqs:
		n += (sq.members.size() + sq.fallen.size()) if start else sq.members.size()
	return n

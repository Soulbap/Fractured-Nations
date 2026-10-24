## Scripted checks of AI-COMBAT-STRAT-01 (multi-squad operations, strategic decisions) in the
## running sandbox war.
##
##   Godot.exe --path . --resolution 1600x900 --log-file st.log res://scenes/game/world_ref_20km.tscn -- --ai-strat-test [--shots] [--only a,b] [--shot-dir=res://docs/ai_strat01]
##
## Extends the AI-SQUAD-01 suite (CombatScenario helpers, shot log, inspector access). Prints
## "STRAT <check> <json>", writes res://benchmarks/raw/ai_strat_test.json.
class_name AIStratSelfTest
extends AISquadSelfTest

## Time series of the last diagnosis / scenario: one line per sample.
var trace: Array = []
## GAMEPLAY-02A: record a CombatDiag of every _run_attack (returned as "diag").
var diag_on := false
## Results file in res://benchmarks/raw and the print prefix (subclasses change them).
var out_file := "ai_strat_test.json"
var prefix := "STRAT"


func run(args: PackedStringArray) -> void:
	await _strat_setup(args, "res://docs/ai_strat01")
	_log("setup", {"soldiers": default_soldiers.size(), "ops_assault": demo.sim.tactics.ops_assault})
	if _want("a_assault"):
		_log("a_assault", await _a_assault())
	if _want("b_reduced"):
		_log("b_reduced", await _b_reduced())
	if _want("e_withdraw"):
		_log("e_withdraw", await _e_withdraw())
	if _want("c_reinforce"):
		_log("c_reinforce", await _c_reinforce())
	if _want("d_defence"):
		_log("d_defence", await _d_defence())
	if _want("f_fronts"):
		_log("f_fronts", await _f_fronts())
	if _want("g_intel"):
		_log("g_intel", await _g_intel())
	if _want("i_player"):
		_log("i_player", await _i_player())
	if _want("j_persist"):
		_log("j_persist", await _j_persist())
	if _want("h_deadlock"):
		_log("h_deadlock", await _h_deadlock())
	if _want("l_war"):
		_log("l_war", await _l_war())
	if _want("k_near"):
		_log("k_near", await _k_near())
	if _want("m_perf"):
		_log("m_perf", await _m_perf())
	if _want("z_visual"):
		_log("z_visual", await _z_visual())
	if only.has("s2_hunt_near"):
		_log("s2_hunt_near", await _s1_hunt(true, false))
	if only.has("s1_hunt"):
		_log("s1_hunt", await _s1_hunt())
	if _want("s0_repro"):
		_log("s0_repro", await _s0_repro())
	await _end_strat()


## Shared setup of the strategy suites: arguments, references, signal recorders, watchdog, world data, AI paused.
func _strat_setup(args: PackedStringArray, shot_dir: String) -> void:
	shots = "--shots" in args
	_shot_dir = shot_dir
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	lof = combat.line
	brain = demo.sim.brain
	def = combat.weapon(&"rifle")
	war = demo.sim.state.war
	ws = demo.sim.war
	SoldierBody.require_mouse_capture = false
	var state := demo.sim.state
	state.shot_fired.connect(_on_shot_rec)
	state.unit_damaged.connect(func(t: UnitState, _a: float, _z: int, _s: int) -> void:
		dmg_events += 1
		if not t.alive:
			dmg_on_dead += 1)
	state.unit_died.connect(func(u: UnitState) -> void:
		deaths.append({"id": u.id, "t": snappedf(state.time, 0.1)}))
	tree.create_timer(3300.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(60)
	_load_world_data()
	for u in state.soldiers():
		default_soldiers.append(u.position)
	_pause_ai(true)
	for sq: SquadState in state.all_squads():
		_stations[sq.id] = sq.station_objective


func _end_strat() -> void:
	TimeCompression.reset()
	for op: OperationState in war.active_operations():
		ws.cancel(op.id, "test end")
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	await _seconds(0.5)
	_finish()


# --- Attack scene helpers -----------------------------------------------------------------------------------------

## Haugen held by `n_def` South squads, `n_att` North squads 520 m short of it (the sandbox "offensive" setup).
## att_hp / def_hp > 0 set the soldiers' health (stated in the scenario, weapons are never changed).
func _scene(n_att: int, n_def: int, att_hp := 0.0, def_hp := 0.0, dist := 520.0) -> Dictionary:
	await _fresh()
	_pause_ai(true)
	var hau := _obj("Haugen")
	hau.owner = 1
	hau.capture_faction = -1
	hau.capture_progress = 0.0
	hau.contested = false
	hau.history.append([demo.sim.state.time, 1])
	var defs: Array = []
	for i in n_def:
		var d := _spawn(1, hau.position + Vector3(10 + i * 18, 0, -10 + i * 9))
		d.station_objective = hau.id
		if def_hp > 0.0:
			_tough(d, def_hp)
		defs.append(d)
	var start := _near_point(hau.position, _obj("North HQ").position, dist)
	var atk: Array = []
	for i in n_att:
		var a := _spawn(0, start + Vector3(((i % 3) - 1) * 25.0, 0, (i / 3) * 25.0 + 25.0 * (1 if i > 0 else 0)))
		if att_hp > 0.0:
			_tough(a, att_hp)
		atk.append(a)
	await _physics(10)
	return {"obj": hau, "atk": atk, "def": defs}


## Starts the attack as a (player-created) ATTACK operation and runs it up to `max_sim` simulated
## seconds, sampling every 10 s. Returns the operation's outcome, the stages and roles seen, the
## longest time the nearest attacker made no progress during the assault, and the trace.
func _run_attack(sc: Dictionary, max_sim := 700.0, scale := 12.0, near := false) -> Dictionary:
	var obj: ObjectiveState = sc.obj
	var atk: Array = sc.atk
	var defs: Array = sc.def
	var ids := atk.map(func(q: SquadState) -> int: return q.id)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, obj.id, Vector3.INF, true)
	if op == null:
		return {"started": false}
	demo.rts_camera.frame(obj.position if near else Vector3(9000, 0, 9000), 0.0, 120.0 if near else 150.0)
	trace.clear()
	var st := {"next": demo.sim.state.time, "stages": [], "whys": [], "roles": {}, "best": INF, "best_t": demo.sim.state.time, "max_stall": 0.0, "withdrew": false,
		"diag_next": demo.sim.state.time, "dist_t": demo.sim.state.time, "max_stall_dist": 0.0, "defs_alive": _alive_count(defs)}
	var dg: CombatDiag = null
	if diag_on:
		dg = CombatDiag.new()
		dg.start(demo.sim, op, atk, defs, obj.position, obj.radius)
		dg.objective = obj
	var w := await _warp(max_sim, scale, 200.0, func() -> bool:
		var now := demo.sim.state.time
		if dg and now >= st.diag_next:
			st.diag_next = now + 1.0
			dg.sample()
		if st.stages.is_empty() or st.stages[-1] != op.stage_name():
			st.stages.append(op.stage_name())
			st.whys.append("%s: %s" % [op.stage_name(), op.stage_why])
		for sid in op.roles:
			st.roles[SquadState.OP_ROLE_NAMES[int(op.roles[sid])]] = true
		if op.stage == OperationState.Stage.WITHDRAW:
			st.withdrew = true
		if now >= st.next:
			st.next += 10.0
			trace.append(_sample_op(op, atk, defs[0], obj))
			if op.stage == OperationState.Stage.ASSAULT and obj.owner != 0:
				var closest := INF
				for sq: SquadState in atk:
					if demo.sim.state.get_squad(sq.id):
						closest = minf(closest, _flat(demo.sim.squads._centroid(sq), obj.position))
				if closest < st.best - 10.0:
					st.best = closest
					st.best_t = now
					st.dist_t = now
				# GAMEPLAY-03C: a defender put out of the fight is progress too. Inside a village the assaulting squads fight
				# from the houses at the edge of the objective (their centres do not get closer while they clear it); the
				# distance-only measure counted that won close fight as a stall (Haugen: 121 s while the defenders went 6 -> 0).
				var alive := _alive_count(defs)
				if alive < int(st.defs_alive):
					st.defs_alive = alive
					st.best_t = now
				st.max_stall = maxf(st.max_stall, now - st.best_t)
				st.max_stall_dist = maxf(st.max_stall_dist, now - st.dist_t)
		return not op.is_active())
	var diag := {}
	if dg:
		dg.stop()
		diag = dg.result()
	var left := _alive_count(atk)
	var started := op.start_strength
	return {"diag": diag, "started": true, "op": {"phase": op.phase_name(), "stage": op.stage_name(), "outcome": op.outcome, "losses": op.losses, "start": started},
		"owner": obj.owner, "attackers_left": left, "defenders_left": _alive_count(defs), "stages": st.stages, "stage_whys": st.whys, "roles_seen": st.roles.keys(),
		"max_assault_stall_s": snappedf(st.max_stall, 1.0), "max_stall_distance_only_s": snappedf(st.max_stall_dist, 1.0), "withdrew": st.withdrew, "warp": w, "stage_why": op.stage_why, "withdraw_why": op.withdraw_why,
		"trace": trace.slice(0, 80), "consistency": _consistency(), "op_obj": op}


# --- A: three squads against a defended objective -------------------------------------------------------------------------

func _a_assault() -> Dictionary:
	var sc := await _scene(3, 1)
	var r := await _run_attack(sc)
	var op: OperationState = r.get("op_obj")
	r.erase("op_obj")
	_expect(r.started, "A: the attack could not start")
	if not r.started:
		return r
	_expect(r.roles_seen.size() >= 2, "A: the squads got no distinct roles (%s)" % str(r.roles_seen))
	_expect(r.stages.has("deploy") and r.stages.has("assault"), "A: the operation skipped its stages (%s)" % str(r.stages))
	_expect(op.phase == OperationState.Phase.COMPLETED and r.owner == 0, "A: the objective was not taken (%s)" % JSON.stringify({"op": r.op, "stage_why": r.stage_why}))
	_expect(r.max_assault_stall_s <= 90.0, "A: the assault stalled for %.0f s" % r.max_assault_stall_s)
	_expect(r.attackers_left >= 12, "A: too many losses (%d of 24 left)" % r.attackers_left)
	_expect(r.consistency.count == 0, "A: operation records inconsistent")
	return r


# --- B: reduced forces ---------------------------------------------------------------------------------------------------------

func _b_reduced() -> Dictionary:
	var out := {}
	for n: int in [1, 2]:
		var sc := await _scene(n, 1, 0.0, 0.0, 450.0)
		var r := await _run_attack(sc, 600.0)
		r.erase("op_obj")
		r.erase("trace")
		out["%d_squad" % n] = r
		_expect(r.started, "B(%d): the attack could not start" % n)
		if r.started:
			_expect(r.stages.has("deploy"), "B(%d): no deployment" % n)
			_expect(r.op.phase != "engaging" and r.op.phase != "moving", "B(%d): the operation never finished (%s)" % [n, r.op.phase])
			_expect(r.max_assault_stall_s <= 120.0, "B(%d): stalled for %.0f s" % [n, r.max_assault_stall_s])
			_expect(r.roles_seen.size() >= 1 and r.consistency.count == 0, "B(%d): roles or records wrong" % n)
	return out


# --- E: withdrawal ------------------------------------------------------------------------------------------------------------

## A weak attack (one squad whose soldiers fall to one or two hits) against two defending squads: the
## operation recognises that it is losing, withdraws, the survivors reach a fallback point, and the
## operation ends instead of standing in the killing ground.
func _e_withdraw() -> Dictionary:
	var sc := await _scene(2, 2, 70.0, 0.0, 420.0)
	var r := await _run_attack(sc, 700.0)
	var op: OperationState = r.get("op_obj")
	r.erase("op_obj")
	_expect(r.started, "E: the attack could not start")
	if not r.started:
		return r
	var survivors := 0
	var recovering := 0
	var far_enough := 0
	for sq: SquadState in sc.atk:
		if demo.sim.state.get_squad(sq.id):
			survivors += 1
			if sq.recover_until > demo.sim.state.time:
				recovering += 1
			if _flat(demo.sim.squads._centroid(sq), sc.obj.position) > 160.0:
				far_enough += 1
	r["survivor_squads"] = survivors
	r["recovering"] = recovering
	r["clear_of_objective"] = far_enough
	_expect(r.withdrew, "E: the operation never withdrew (%s)" % JSON.stringify({"op": r.op, "why": r.stage_why}))
	if r.withdrew:
		_expect(r.op.phase == "failed" and str(r.op.outcome).begins_with("withdrew"), "E: the operation did not end as a withdrawal (%s)" % str(r.op))
		_expect(far_enough == survivors, "E: survivors still stand in the combat area (%d of %d clear)" % [far_enough, survivors])
		_expect(recovering == survivors, "E: survivors are not marked as recovering")
	return r


# --- Strategic scenario helpers -------------------------------------------------------------------------------------------

## Reads the newest strategic decision of a faction (snapshot) after calling the scorer once.
func _decide_now(fid: int) -> Dictionary:
	var fs := war.faction(fid)
	fs.decisions.clear()
	ws.strat.decide(fs)
	return fs.decisions.back() if not fs.decisions.is_empty() else {}


func _action(snap: Dictionary, kind: String, objective := "") -> Dictionary:
	for a: Dictionary in snap.get("actions", []):
		if a.kind == kind and (objective == "" or a.name == objective):
			return a
	return {}


## Injects a report like a soldier who saw enemies would file it: it enters IntelSim's queue (and its delay)
## and becomes a contact of the faction. No enemy needs to stand there.
func _report(fid: int, at: Vector3, group := 6, src := ContactState.Source.SEEN) -> void:
	ws.intel._queue(fid, 1 if fid == 0 else 0, ContactState.Kind.INFANTRY, src, at, -1, 20.0, group, "test report", demo.sim.state.time, 0.0)
	ws.intel.update(1.0)


func _strat_reset_faction(fid: int) -> void:
	var fs := war.faction(fid)
	fs.recovery_until = 0.0
	fs.focus_kind = ""
	fs.focus_until = 0.0
	fs.decisions.clear()
	ws.threatened.clear()


# --- C: reinforcement of a running attack ---------------------------------------------------------------------------

## South (AI) attacks Haugen, held by North with 16 soldiers; its attack force is one squad. Once the
## defence is reported the scorer finds more resistance than the attack was built for and sends free
## squads to the running operation (JOIN), not a second operation.
func _c_reinforce() -> Dictionary:
	await _fresh()
	_pause_ai(true)
	var hau := _obj("Haugen")
	hau.owner = 0
	hau.capture_faction = -1
	hau.capture_progress = 0.0
	hau.history.append([demo.sim.state.time, 0])
	var d1 := _spawn(0, hau.position + Vector3(10, 0, -10))
	var d2 := _spawn(0, hau.position + Vector3(30, 0, 10))
	d1.station_objective = hau.id
	d2.station_objective = hau.id
	var sh := _obj("South HQ")
	var start := _near_point(hau.position, sh.position, 420.0)
	var a := _spawn(1, start)
	var free1 := _spawn(1, start + Vector3(0, 0, -260.0))
	var free2 := _spawn(1, start + Vector3(40, 0, -260.0))
	await _physics(10)
	_strat_reset_faction(1)
	var op := ws.start_operation(1, OperationState.Type.ATTACK, [a.id], hau.id, Vector3.INF, false)
	_expect(op != null, "C: the attack could not start")
	if op == null:
		return {}
	var ops_before := war.active_operations(1).size()
	# Run until the attack has met the defence (reports exist) or 150 s pass.
	var w := await _warp(200.0, 12.0, 90.0, func() -> bool:
		return op.stage >= OperationState.Stage.SUPPORT and ws.intel.threat_near(1, hau.position, hau.radius + 150.0) >= 5)
	var snap := _decide_now(1)
	var joined := _action(snap, "join")
	var squads_after := op.squads.size()
	var out := {"warp": w, "stage": op.stage_name(), "reported": ws.intel.threat_near(1, hau.position, hau.radius + 150.0), "join_action": joined,
		"squads_in_op": squads_after, "ops_before": ops_before, "ops_after": war.active_operations(1).size(), "roles": _roles_text_of(op), "actions": snap.get("actions", [])}
	_expect(not joined.is_empty(), "C: no join action was considered (%s)" % str(snap.get("actions", [])))
	if not joined.is_empty():
		_expect(joined.status == "chosen", "C: the join was not carried out (%s)" % joined.status)
		_expect(squads_after > 1, "C: no squad joined the attack")
		var attacks := war.active_operations(1).filter(func(o: OperationState) -> bool: return o.type == OperationState.Type.ATTACK and o.target_objective == hau.id).size()
		_expect(attacks == 1, "C: a competing second attack on the same objective exists (%d)" % attacks)
	_expect(_consistency().count == 0, "C: operation records inconsistent")
	return out


func _roles_text_of(op: OperationState) -> String:
	var parts: Array[String] = []
	for sid in op.roles:
		var sq := demo.sim.state.get_squad(sid)
		parts.append("%s %s" % [sq.squad_name if sq else "#%d" % sid, SquadState.OP_ROLE_NAMES[int(op.roles[sid])]])
	return ", ".join(parts)


# --- D: strategic defence ------------------------------------------------------------------------------------------------

## East (defensive AI) holds Elvetun with one squad; a report of about 14 enemies arrives from 500 m away (no
## enemy stands there). The scorer evaluates it from the faction's picture, sends free squads, and the
## objective is not abandoned: the defenders take positions around it.
func _d_defence() -> Dictionary:
	await _fresh()
	_pause_ai(true)
	var objs := war.all_objectives().filter(func(o: ObjectiveState) -> bool: return o.owner == 2 and not o.is_hq())
	if objs.is_empty():
		_expect(false, "D: East holds no objective besides its HQ")
		return {}
	var target: ObjectiveState = objs[0]
	var garrison := _spawn(2, target.position + Vector3(8, 0, 8))
	garrison.station_objective = target.id
	var hq := _obj("East HQ")
	var free_a := _spawn(2, _near_point(target.position, hq.position, 600.0))
	var free_b := _spawn(2, _near_point(target.position, hq.position, 640.0) + Vector3(30, 0, 0))
	await _physics(10)
	_strat_reset_faction(2)
	var enemy_at := _near_point(target.position, _obj("North HQ").position, 520.0)
	_report(2, enemy_at, 14, ContactState.Source.SEEN)
	var snap := _decide_now(2)
	var act := _action(snap, "reinforce", target.obj_name)
	var out := {"objective": target.obj_name, "action": act, "threats": snap.get("threats", []), "forces": snap.get("forces", {}), "focus": snap.get("focus", ""),
		"ops": war.active_operations(2).map(func(o: OperationState) -> String: return "%s -> %s" % [o.type_name(), o.reason])}
	_expect(not act.is_empty(), "D: a report of 14 enemies near an owned objective produced no reinforce action (%s)" % str(snap.get("actions", [])))
	if not act.is_empty():
		_expect(act.status == "chosen", "D: the reinforcement was not sent (%s)" % act.status)
		_expect(act.basis in ["confirmed", "reported"], "D: the estimate carries no basis (%s)" % act.basis)
	# Let the reinforcements arrive and take positions; the objective stays held.
	var reinforce_ops: Array = war.active_operations(2).filter(func(o: OperationState) -> bool: return o.type == OperationState.Type.REINFORCE)
	var reinforce_dist0 := 0.0
	for o: OperationState in reinforce_ops:
		for sid in o.squads:
			reinforce_dist0 = maxf(reinforce_dist0, _flat(demo.sim.squads._centroid(demo.sim.state.get_squad(sid)), target.position))
	out["reinforcement_start_m"] = snappedf(reinforce_dist0, 1.0)
	var w := await _warp(600.0, 12.0, 150.0, func() -> bool: return reinforce_ops.all(func(o: OperationState) -> bool: return not o.is_active()))
	out["wait"] = w
	out["reinforce_ops"] = reinforce_ops.map(func(o: OperationState) -> String: return "#%d %s %s" % [o.id, o.phase_name(), o.outcome])
	var defending := 0
	var posted := 0
	for sq: SquadState in demo.sim.state.all_squads():
		if sq.faction == 2 and _flat(demo.sim.squads._centroid(sq), target.position) < target.radius + 120.0:
			defending += 1
			if sq.tactic == SquadState.Tactic.DEFEND:
				posted += 1
	out["defending_squads"] = defending
	out["posted_squads"] = posted
	out["owner_after"] = target.owner
	var spots: Array = []
	var roles: Array = []
	for sq: SquadState in demo.sim.state.all_squads():
		if sq.faction == 2 and sq.station_objective == target.id:
			spots.append(demo.sim.squads._centroid(sq))
			roles.append(sq.defence_role)
	var apart := 0.0
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			apart = maxf(apart, _flat(spots[i], spots[j]))
	out["garrison_roles"] = roles
	out["garrison_spread_m"] = snappedf(apart, 1.0)
	if spots.size() >= 2:
		_expect(apart >= 25.0, "D: the squads at the objective stand on one spot (%.0f m apart)" % apart)
	var rd := 0.0
	for o: OperationState in reinforce_ops:
		for sid in o.squads:
			rd = maxf(rd, _flat(demo.sim.squads._centroid(demo.sim.state.get_squad(sid)), target.position)) if demo.sim.state.get_squad(sid) else rd
	out["reinforcement_distance_m"] = snappedf(rd, 1.0)
	_expect(defending >= 2 or (not reinforce_ops.is_empty() and rd < 450.0 and rd < reinforce_dist0 - 120.0), "D: the objective was not reinforced (%d squads there, the reinforcement is still %.0f m away, was %.0f m)" % [defending, rd, reinforce_dist0])
	_expect(target.owner == 2, "D: the objective was abandoned")
	return out


# --- F: two fronts ------------------------------------------------------------------------------------------------------------

## East holds two objectives besides its HQ, both reported threatened, with four free squads: the forces are
## split by importance and threat, a reserve is kept, no objective takes everything, and the decision list says why.
func _f_fronts() -> Dictionary:
	await _fresh()
	_pause_ai(true)
	var objs := war.all_objectives().filter(func(o: ObjectiveState) -> bool: return o.owner == 2 and not o.is_hq())
	if objs.size() < 2:
		# Hand East a second objective for the test (the war is paused; ownership is restored by the scenario end).
		for o: ObjectiveState in war.all_objectives():
			if o.owner != 2 and not o.is_hq() and objs.size() < 2 and o.owner != 0:
				o.owner = 2
				objs.append(o)
	var a: ObjectiveState = objs[0]
	var b: ObjectiveState = objs[1]
	var hq := _obj("East HQ")
	var sqs: Array = []
	for i in 5:
		sqs.append(_spawn(2, hq.position + Vector3(i * 12.0, 0, 30.0)))
	await _physics(10)
	_strat_reset_faction(2)
	_report(2, _near_point(a.position, _obj("North HQ").position, 450.0), 14)
	_report(2, _near_point(b.position, _obj("South HQ").position, 450.0), 12)
	var snap := _decide_now(2)
	var targets := {}
	for op: OperationState in war.active_operations(2):
		if op.type == OperationState.Type.REINFORCE:
			targets[op.target_objective] = targets.get(op.target_objective, 0) + op.squads.size()
	var committed := 0
	for k in targets:
		committed += targets[k]
	var out := {"objectives": [a.obj_name, b.obj_name], "targets": targets, "committed_squads": committed, "forces": snap.get("forces", {}), "actions": snap.get("actions", []), "focus": snap.get("focus", "")}
	var listed := 0
	for ob: ObjectiveState in [a, b]:
		if not _action(snap, "reinforce", ob.obj_name).is_empty():
			listed += 1
	_expect(listed == 2, "F: not both threatened objectives were weighed (%d of 2 in the action list)" % listed)
	_expect(targets.size() >= 2, "F: only %d objective(s) were reinforced (%s)" % [targets.size(), str(targets)])
	_expect(committed < sqs.size() + 3, "F: absurd commitment")
	var reserve_left := 0
	for sq: SquadState in sqs:
		if sq.op_id < 0:
			reserve_left += 1
	out["squads_kept_back"] = reserve_left
	_expect(snap.get("actions", []).size() >= 2, "F: the decision list is missing from the snapshot")
	return out


# --- G: imperfect intelligence --------------------------------------------------------------------------------------------------

## Confidence matters: a fresh sighting and a faint old report of the same size near an objective are not scored
## alike, the report is where it was reported (not where an enemy stands), and a new sighting changes the plan.
func _g_intel() -> Dictionary:
	await _fresh()
	_pause_ai(true)
	var objs := war.all_objectives().filter(func(o: ObjectiveState) -> bool: return o.owner == 2 and not o.is_hq())
	var o: ObjectiveState = objs[0]
	var hq := _obj("East HQ")
	_spawn(2, hq.position + Vector3(0, 0, 30.0))
	_spawn(2, hq.position + Vector3(30, 0, 30.0))
	var truth := _spawn(0, _near_point(o.position, _obj("North HQ").position, 2500.0))
	await _physics(10)
	_strat_reset_faction(2)
	var at := _near_point(o.position, _obj("North HQ").position, 500.0)
	_report(2, at, 10, ContactState.Source.HEARD)
	var stale_snap := _decide_now(2)
	var stale := _action(stale_snap, "reinforce", o.obj_name)
	# Cancel what the first decision did, then a fresh sighting of the same group.
	for op: OperationState in war.active_operations(2):
		ws.cancel(op.id, "test")
	await _physics(5)
	_strat_reset_faction(2)
	_report(2, at, 10, ContactState.Source.SEEN)
	var fresh_snap := _decide_now(2)
	var fresh := _action(fresh_snap, "reinforce", o.obj_name)
	var contact: ContactState = null
	for c: ContactState in ws.intel.contacts_of(2):
		contact = c
	var out := {"heard": stale, "seen": fresh, "contact_pos": _v(contact.pos) if contact else [], "true_enemy": _v(demo.sim.state.get_unit(truth.members[0]).position),
		"contacts": ws.intel.contacts_of(2).size()}
	_expect(not fresh.is_empty(), "G: a seen group near the objective produced no action")
	if not stale.is_empty():
		_expect(stale.status != "chosen" or stale.basis != "confirmed", "G: a sound report was treated as a confirmed sighting")
	if not fresh.is_empty() and not stale.is_empty():
		_expect(fresh.utility > stale.utility, "G: a sighting (%.2f) is not scored above a faint sound report (%.2f)" % [fresh.utility, stale.utility])
		_expect(fresh.basis == "confirmed" or fresh.basis == "reported", "G: the sighting is labelled %s" % fresh.basis)
	if contact:
		var enemy_pos := demo.sim.state.get_unit(truth.members[0]).position
		_expect(_flat(contact.pos, enemy_pos) > 1500.0, "G: the contact tracked a hidden enemy elsewhere")
	return out


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- I: the player takes a squad out of a running operation ------------------------------------------------------------

func _i_player() -> Dictionary:
	var sc := await _scene(3, 1)
	var obj: ObjectiveState = sc.obj
	var atk: Array = sc.atk
	var ids := atk.map(func(q: SquadState) -> int: return q.id)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, obj.id, Vector3.INF, true)
	_expect(op != null, "I: the attack could not start")
	if op == null:
		return {}
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _warp(300.0, 12.0, 120.0, func() -> bool: return op.stage >= OperationState.Stage.SUPPORT)
	var taken: SquadState = demo.sim.state.get_squad(op.roles.keys()[0])
	for sid in op.roles:
		if int(op.roles[sid]) == SquadState.OpRole.MANEUVER or int(op.roles[sid]) == SquadState.OpRole.SUPPORT:
			taken = demo.sim.state.get_squad(sid)
	var role_before := SquadState.OP_ROLE_NAMES[int(op.roles.get(taken.id, 0))]
	var res := demo.sim.tactics.order_tactic([taken.id], SquadState.Tactic.DEFEND, demo.sim.squads._centroid(taken))
	var out := {"role_before": role_before, "order": res.get("text", ""), "ok": res.get("ok", false)}
	_expect(res.get("ok", false), "I: the player's order was refused: %s" % res.get("text", ""))
	await _physics(5)
	_expect(taken.op_id == -1 and not op.squads.has(taken.id), "I: the squad is still in the operation after the player's order")
	_expect(taken.tactic_owner == SquadState.Owner.PLAYER, "I: the player's tactic does not belong to the player (%s)" % taken.owner_name())
	var w := await _warp(40.0, 12.0, 60.0)
	_expect(taken.op_id == -1 and taken.tactic_owner != SquadState.Owner.OPERATION, "I: the operation reclaimed the player's squad")
	_expect(not op.roles.has(taken.id), "I: the operation still lists a role for the player's squad")
	_expect(_consistency().count == 0, "I: operation records inconsistent")
	# The rest carries on: the operation finishes or at least keeps making progress (no deadlock).
	var w2 := await _warp(500.0, 12.0, 160.0, func() -> bool: return not op.is_active())
	out["op"] = {"phase": op.phase_name(), "stage": op.stage_name(), "outcome": op.outcome, "squads": op.squads.size()}
	out["owner"] = obj.owner
	_expect(not op.is_active() or op.stage != OperationState.Stage.APPROACH, "I: the operation stalled after the intervention")
	_expect(not op.is_active() or w2.sim_s < 499.0, "I: the operation neither finished nor changed stage")
	return out


# --- J: save and load during an operation ------------------------------------------------------------------------------------

func _j_persist() -> Dictionary:
	var sc := await _scene(3, 1)
	var obj: ObjectiveState = sc.obj
	var ids := (sc.atk as Array).map(func(q: SquadState) -> int: return q.id)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, obj.id, Vector3.INF, true)
	if op == null:
		_expect(false, "J: the attack could not start")
		return {}
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _warp(300.0, 12.0, 120.0, func() -> bool: return op.stage >= OperationState.Stage.ASSAULT)
	# Faction focus must survive too.
	var fs := war.faction(1)
	fs.focus_kind = "defence"
	fs.focus_objective = obj.id
	fs.focus_until = demo.sim.state.time + 100.0
	fs.focus_why = "test"
	var before := _op_sig(op)
	var state := demo.sim.state
	var snap := state.snapshot()
	state.apply_snapshot(snap)
	await tree.physics_frame
	war = demo.sim.state.war
	ws = demo.sim.war
	var op2 := war.operation(op.id)
	_expect(op2 != null, "J: the operation is gone after loading")
	if op2 == null:
		return {"before": before}
	var after := _op_sig(op2)
	_expect(before == after, "J: the operation differs after loading: %s vs %s" % [before, after])
	var fs2 := war.faction(1)
	_expect(fs2.focus_kind == "defence" and fs2.focus_objective == obj.id, "J: the strategic focus was lost")
	var roles_ok := true
	for sid in op2.roles:
		var sq := state.get_squad(sid)
		roles_ok = roles_ok and sq != null and sq.op_role == int(op2.roles[sid]) and sq.op_id == op2.id
	_expect(roles_ok, "J: squad roles and operation roles differ after loading")
	var w := await _warp(500.0, 12.0, 160.0, func() -> bool: return not op2.is_active())
	_expect(not op2.is_active() or op2.stage >= OperationState.Stage.ASSAULT, "J: the operation did not carry on after loading")
	_expect(_consistency().count == 0, "J: records inconsistent after loading")
	return {"before": before, "after": after, "ended": {"phase": op2.phase_name(), "outcome": op2.outcome}, "warp": w}


func _op_sig(op: OperationState) -> String:
	var roles := []
	for sid in op.roles:
		roles.append("%d:%d" % [sid, int(op.roles[sid])])
	roles.sort()
	return "%s %s squads=%s roles=%s fb=%s" % [op.phase_name(), op.stage_name(), str(op.squads), ",".join(roles), str(op.fallback_pos)]


# --- H: tactical deadlock ------------------------------------------------------------------------------------------------------------

## The defenders are practically unkillable, the attack cannot win. It must still end (withdrawal or a
## timeout), not hang, and the survivors must be released.
func _h_deadlock() -> Dictionary:
	var sc := await _scene(2, 2, 0.0, 900.0, 450.0)
	var r := await _run_attack(sc, 900.0)
	r.erase("op_obj")
	r.erase("trace")
	_expect(r.started, "H: the attack could not start")
	if r.started:
		_expect(r.op.phase == "failed" or r.op.phase == "completed", "H: the operation never ended (%s)" % str(r.op))
		var free := 0
		for sq: SquadState in sc.atk:
			if demo.sim.state.get_squad(sq.id) and sq.op_id == -1:
				free += 1
		r["released"] = free
		_expect(free == _alive_squads(sc.atk), "H: survivors are still bound to the ended operation")
		_expect(r.consistency.count == 0, "H: records inconsistent")
	return r


func _alive_squads(sqs: Array) -> int:
	var n := 0
	for sq: SquadState in sqs:
		if demo.sim.state.get_squad(sq.id):
			n += 1
	return n


# --- L / K / M: the autonomous war, far and near, with timings ----------------------------------------------------------------

func _war_sample(st: Dictionary) -> void:
	var now := demo.sim.state.time
	var lines: Array = []
	var dup := {}
	for op: OperationState in war.active_operations():
		var obj := war.objective(op.target_objective)
		var key := "%d-%d-%d" % [op.faction, op.type, op.target_objective]
		if op.type == OperationState.Type.ATTACK:
			if dup.has(key):
				st.duplicates += 1
			dup[key] = true
		var sk := "%d:%s" % [op.id, op.stage_name()]
		if st.stage_since.get(op.id, "") != sk:
			st.stage_since[op.id] = sk
			st.stage_t[op.id] = now
		if op.stage != OperationState.Stage.APPROACH:  # the approach is a march of kilometres
			if now - float(st.stage_t[op.id]) > st.max_stage_s:
				st["long_stage"] = "%s #%d %s %s, %s / %s" % [WorldState.faction_name(op.faction), op.id, op.type_name(), op.stage_name(), op.stage_why.left(90), op.wait_reason.left(60)]
			st.max_stage_s = maxf(st.max_stage_s, now - float(st.stage_t[op.id]))
		if op.roles.size() >= 2:
			st.coordinated.erase(op.id)
			st.coordinated[op.id] = true
		lines.append("%s #%d %s %s %s sq=%d" % [WorldState.faction_name(op.faction), op.id, op.type_name(), obj.obj_name if obj else "-", op.stage_name(), op.squads.size()])
	var s := ws.summary()
	st.samples.append({"t": snappedf(now, 1.0), "ops": lines, "factions": s.factions.keys().map(func(k) -> String:
		var f: Dictionary = s.factions[k]
		return "%s %d obj %d sold | %s" % [k, f.objectives, f.soldiers, f.last_decision])})


func _war_run(minutes: float, scale: float, st: Dictionary) -> Dictionary:
	var ms := PackedFloat32Array()
	var r0 := Time.get_ticks_msec()
	var t0 := demo.sim.state.time
	var next := t0
	TimeCompression.apply(scale, 64)
	while demo.sim.state.time - t0 < minutes * 60.0 and Time.get_ticks_msec() - r0 < 330000:
		var t := Time.get_ticks_usec()
		await tree.process_frame
		ms.append((Time.get_ticks_usec() - t) / 1000.0)
		if demo.sim.state.time >= next:
			next += 30.0
			_war_sample(st)
	TimeCompression.reset()
	var sorted := Array(ms)
	sorted.sort()
	return {"sim_min": snappedf((demo.sim.state.time - t0) / 60.0, 0.1), "real_s": snappedf((Time.get_ticks_msec() - r0) / 1000.0, 0.1),
		"frame_ms_avg": snappedf(float(sorted.reduce(func(a, b): return a + b, 0.0)) / maxf(sorted.size(), 1.0), 0.01) if not sorted.is_empty() else 0.0,
		"frame_ms_p99": snappedf(sorted[int(sorted.size() * 0.99)], 0.1) if not sorted.is_empty() else 0.0, "frame_ms_max": snappedf(sorted[-1], 0.1) if not sorted.is_empty() else 0.0}


func _new_war_stats() -> Dictionary:
	return {"samples": [], "duplicates": 0, "max_stage_s": 0.0, "stage_since": {}, "stage_t": {}, "coordinated": {}}


func _war_checks(tag: String, st: Dictionary, run: Dictionary) -> Dictionary:
	var done: Array = war.operations.values().filter(func(o: OperationState) -> bool: return not o.is_active())
	var attacks: Array = war.operations.values().filter(func(o: OperationState) -> bool: return o.type == OperationState.Type.ATTACK)
	var out := {"run": run, "operations_total": war.operations.size(), "attacks": attacks.size(), "coordinated_attacks": st.coordinated.size(),
		"duplicate_attack_samples": st.duplicates, "max_stage_s": snappedf(st.max_stage_s, 1.0), "withdrawals": ws.coord.withdrawals, "joins": ws.strat.joins,
		"decisions": ws.strat.decisions, "strat_us_max": ws.strat.usec_max, "coord_us_max": ws.coord.usec_max, "influence_us_max": ws.influence.usec_max,
		"update_us_avg": snappedf(float(ws.update_usec) / maxi(ws.updates, 1), 0.1), "ai_us_max": ws.ai_usec_max, "finished_ops": done.size(),
		"outcomes": done.slice(-12).map(func(o: OperationState) -> String: return "#%d %s %s: %s" % [o.id, o.type_name(), o.phase_name(), o.outcome]),
		"samples": st.samples.slice(0, 40), "summary": ws.summary().factions}
	_expect(st.duplicates == 0, "%s: two attacks of one faction on one objective ran at once" % tag)
	_expect(st.max_stage_s <= 600.0, "%s: an operation stayed %.0f s in one stage" % [tag, st.max_stage_s])
	_expect(_consistency().count == 0, "%s: operation records inconsistent" % tag)
	_expect(attacks.size() >= 1, "%s: no attack ran" % tag)
	_expect(run.frame_ms_max < 250.0, "%s: a frame took %.0f ms" % [tag, run.frame_ms_max])
	return out


## L: the war runs without the player (camera far away, abstract tier) for 40 simulated minutes.
func _l_war() -> Dictionary:
	await _fresh()
	_pause_ai(false)
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	await _seconds(1.0)
	var st := _new_war_stats()
	var run := await _war_run(40.0, 24.0, st)
	return _war_checks("L", st, run)


## K: the same attack seen from near (camera on the objective, tactical tier) and from far (abstract tier
## around the player's camera): the operation takes the same course - same stages, the same kind of outcome.
func _k_near() -> Dictionary:
	var out := {}
	for mode: String in ["far", "near", "far", "near"]:
		var sc := await _scene(3, 1)
		var r := await _run_attack(sc, 700.0, 12.0, mode == "near")
		r.erase("op_obj")
		r.erase("trace")
		out[mode + str(out.size())] = r
		_expect(r.started and r.op.phase != "engaging" and r.op.phase != "moving", "K(%s): the operation never finished (%s)" % [mode, str(r.get("op", ""))])
		_expect(r.consistency.count == 0, "K(%s): records inconsistent" % mode)
	var left := {"far": [], "near": []}
	var taken := 0
	for k: String in out:
		left[k.substr(0, 3 if k.begins_with("far") else 4)].append(out[k].get("attackers_left", -1))
		taken += 1 if out[k].get("owner", -1) == 0 else 0
	# Combat is stochastic (about one attack in five runs out of ammunition against the dug-in squad and breaks off):
	# at least three of four must take it, and every one must end.
	_expect(taken >= 3, "K: only %d of 4 attacks took the objective" % taken)
	out["taken"] = taken
	out["attackers_left"] = left
	return out


# --- M: cost ---------------------------------------------------------------------------------------------------------------------------------

## The strategic scorer, the influence grid and the coordinator measured in isolation: with the whole
## world's squads and a handful of reports and operations running.
func _m_perf() -> Dictionary:
	var sc := await _scene(3, 1)
	var ids := (sc.atk as Array).map(func(q: SquadState) -> int: return q.id)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, (sc.obj as ObjectiveState).id, Vector3.INF, true)
	for i in 6:
		_report(1 + (i % 2), _near_point((sc.obj as ObjectiveState).position, _obj("North HQ").position, 300.0 + i * 120.0), 6 + i)
	await _warp(60.0, 12.0, 30.0)
	var out := {}
	for fid in [1, 2]:
		var fs := war.faction(fid)
		var t0 := Time.get_ticks_usec()
		for i in 100:
			ws.strat.decide(fs)
		out["decide_f%d_us" % fid] = snappedf(float(Time.get_ticks_usec() - t0) / 100.0, 1.0)
	var t1 := Time.get_ticks_usec()
	for i in 100:
		ws.influence._t = -1000.0
		ws.influence.update()
	out["influence_us"] = snappedf(float(Time.get_ticks_usec() - t1) / 100.0, 1.0)
	var obj: ObjectiveState = sc.obj
	var t2 := Time.get_ticks_usec()
	for i in 100:
		if op.is_active():
			ws.coord.update(op, obj)
	out["coord_update_us"] = snappedf(float(Time.get_ticks_usec() - t2) / 100.0, 1.0)
	out["squads"] = demo.sim.state.all_squads().size()
	out["soldiers"] = demo.sim.state.soldiers().size()
	_expect(out.decide_f1_us < 8000.0 and out.decide_f2_us < 8000.0, "M: a strategic decision costs %s us" % str([out.decide_f1_us, out.decide_f2_us]))
	_expect(out.coord_update_us < 2000.0, "M: coordination costs %.0f us per update" % out.coord_update_us)
	return out


# --- Z: the autonomous attack as the player sees it (screenshots) ---------------------------------------------------------------

## Three squads attack Haugen as an AI operation. The camera follows the force and the objective, the
## debug overlay shows roles and stages; pictures at each stage change and at least every 15 s.
func _z_visual() -> Dictionary:
	var sc := await _scene(3, 1)
	var obj: ObjectiveState = sc.obj
	var atk: Array = sc.atk
	var ids := atk.map(func(q: SquadState) -> int: return q.id)
	demo.tactics_overlay.debug = true
	if shots and demo.hud:
		demo.hud.visible = false
	trace.clear()
	var next_sample := demo.sim.state.time
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, obj.id, Vector3.INF, false)
	if op == null:
		_expect(false, "Z: the attack could not start")
		return {}
	var yaw := atan2(-(obj.position.x - demo.sim.squads._centroid(atk[0]).x), -(obj.position.z - demo.sim.squads._centroid(atk[0]).z))
	var last := ""
	var last_t := -100.0
	var frames := 0
	var t0 := demo.sim.state.time
	TimeCompression.apply(4.0, 64)
	while op.is_active() and demo.sim.state.time - t0 < 600.0:
		await tree.process_frame
		var c := Vector3.ZERO
		var n := 0
		for sq: SquadState in atk:
			if demo.sim.state.get_squad(sq.id):
				c += demo.sim.squads._centroid(sq)
				n += 1
		if n == 0:
			break
		c /= n
		var d := _flat(c, obj.position)
		# High enough to see over the tree canopy: the rings and labels of the overlay carry the picture.
		var focus := c.lerp(obj.position, 0.5) if d < 330.0 else c
		var zoom := clampf(d * 0.38 + 55.0, 90.0, 170.0)
		demo.rts_camera.frame(focus, yaw, zoom)
		frames += 1
		if demo.sim.state.time >= next_sample:
			next_sample += 10.0
			trace.append(_sample_op(op, atk, sc.def[0], obj))
		var key := op.stage_name()
		var t := demo.sim.state.time
		if shots and frames > 20 and (key != last or t - last_t >= 15.0):
			last = key
			last_t = t
			await tree.process_frame
			_shot("z_%03d_%s" % [int(t - t0), key])
	TimeCompression.reset()
	demo.tactics_overlay.debug = false
	if demo.hud:
		demo.hud.visible = true
	var inspector := ws.explain_faction(war.faction(0)) if ws.has_method("explain_faction") else []
	return {"op": {"phase": op.phase_name(), "stage": op.stage_name(), "outcome": op.outcome}, "owner": obj.owner, "explain_op": ws.coord.explain(op), "trace": trace.slice(0, 70), "attackers_left": _alive_count(atk), "defenders_left": _alive_count(sc.def), "inspector_faction": inspector}


# --- S1: hunt for a bad assault (diagnostics, not an assertion) ---------------------------------------------------------------------

func _s1_hunt(near := false, stop_on_bad := true) -> Dictionary:
	var runs := []
	for i in 6:
		var sc := await _scene(3, 1)
		var r := await _run_attack(sc, 700.0, 12.0, near)
		r.erase("op_obj")
		var bad: bool = r.owner != 0 or r.attackers_left < 12
		runs.append({"i": i, "owner": r.owner, "left": r.attackers_left, "def_left": r.defenders_left, "outcome": r.op.outcome, "stages": r.stages})
		if bad and stop_on_bad:
			return {"runs": runs, "bad_trace": r.trace, "stage_why": r.stage_why}
		if bad:
			runs[-1]["bad_trace"] = r.trace.slice(7)
	return {"runs": runs}


# --- Output (own prefix and file) ----------------------------------------------------------------

func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("%s %s %s" % [prefix, check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print(prefix + " FAILED CHECK: ", msg)


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	img.save_jpg(ProjectSettings.globalize_path("%s/st01_%s.jpg" % [_shot_dir, shot_name]), 0.9)
	print("STRAT shot: ", shot_name)


func _finish() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	results["tactics"] = demo.sim.tactics.summary()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/" + out_file), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("%s %s %s" % [prefix, "PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	if keep_open:
		return
	demo.shutdown_cleanup()
	tree.quit()


# --- S0: the failed autonomous assault -------------------------------------------------------------------

## The sandbox "offensive" setup (three North squads against one South squad at Haugen), sampled every
## 5 s of simulated time: each squad's role, tactic, phase, strength, suppression, effectiveness and distance
## to the objective, plus the operation's phase. Used to find out why the assault stalls.
func _s0_repro() -> Dictionary:
	_pause_ai(true)
	var hau := _obj("Haugen")
	hau.owner = 1
	hau.history.append([demo.sim.state.time, 1])
	var defenders := _spawn(1, hau.position + Vector3(10, 0, -10))
	defenders.station_objective = hau.id
	var hq := _obj("North HQ")
	var start := _near_point(hau.position, hq.position, 520.0)
	var a := _spawn(0, start)
	var b := _spawn(0, start + Vector3(25, 0, 25))
	var c := _spawn(0, start + Vector3(-25, 0, 25))
	await _physics(10)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, [a.id, b.id, c.id], hau.id, Vector3.INF, true)
	_expect(op != null, "S0: the attack could not be started")
	if op == null:
		return {}
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	trace.clear()
	var next_sample := [demo.sim.state.time]
	var w := await _warp(700.0, 12.0, 160.0, func() -> bool:
		if demo.sim.state.time >= next_sample[0]:
			next_sample[0] += 10.0
			trace.append(_sample_op(op, [a, b, c], defenders, hau))
		return not op.is_active())
	var out := {"op": {"phase": op.phase_name(), "outcome": op.outcome, "losses": op.losses, "start": op.start_strength}, "owner": hau.owner,
		"defenders_left": _alive_count([defenders]), "attackers_left": _alive_count([a, b, c]), "warp": w, "stage_why": op.stage_why, "wait": op.wait_reason, "events": demo.sim.tactics.events.filter(func(e: Dictionary) -> bool: return not ("fire team" in e.text)).slice(-24).map(func(e: Dictionary) -> String: return "%.0f %s" % [e.t, e.text]), "trace": trace.slice(0, 60)}
	return out


func _sample_op(op: OperationState, sqs: Array, defenders: SquadState, obj: ObjectiveState) -> String:
	var parts: Array[String] = []
	for sq: SquadState in sqs:
		var cen: Vector3 = demo.sim.squads._centroid(sq) if demo.sim.state.get_squad(sq.id) else Vector3.ZERO
		var a := demo.sim.tactics.assessment(sq)
		var line := "%s %s %s/%d n=%d d=%.0f eff=%.2f sup=%.2f" % [sq.squad_name, SquadState.OP_ROLE_NAMES[sq.op_role], sq.tactic_name(), sq.tactic_phase, sq.members.size(),
			_flat(cen, obj.position), a.get("eff", -1.0), a.get("supp", -1.0)]
		if sq.tactic_rejected != "" and sq.tactic != SquadState.Tactic.NONE:
			line += " rej=" + sq.tactic_rejected.left(70)
		if sq.tactic_dest.is_finite():
			line += " dest=%.0f" % _flat(sq.tactic_dest, obj.position)
		parts.append(line)
	return "%.0f %s/%s | %s | def %d" % [demo.sim.state.time, op.phase_name(), op.stage_name(), " ; ".join(parts), _alive_count([defenders])]

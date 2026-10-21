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


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/ai_strat01"
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
	_log("setup", {"soldiers": default_soldiers.size(), "ops_assault": demo.sim.tactics.ops_assault})
	if _want("a_assault"):
		_log("a_assault", await _a_assault())
	if _want("b_reduced"):
		_log("b_reduced", await _b_reduced())
	if _want("e_withdraw"):
		_log("e_withdraw", await _e_withdraw())
	if _want("s0_repro"):
		_log("s0_repro", await _s0_repro())
	await _end_strat()


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
func _run_attack(sc: Dictionary, max_sim := 700.0, scale := 12.0) -> Dictionary:
	var obj: ObjectiveState = sc.obj
	var atk: Array = sc.atk
	var defs: Array = sc.def
	var ids := atk.map(func(q: SquadState) -> int: return q.id)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, obj.id, Vector3.INF, true)
	if op == null:
		return {"started": false}
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	trace.clear()
	var st := {"next": demo.sim.state.time, "stages": [], "roles": {}, "best": INF, "best_t": demo.sim.state.time, "max_stall": 0.0, "withdrew": false}
	var w := await _warp(max_sim, scale, 200.0, func() -> bool:
		var now := demo.sim.state.time
		if st.stages.is_empty() or st.stages[-1] != op.stage_name():
			st.stages.append(op.stage_name())
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
				st.max_stall = maxf(st.max_stall, now - st.best_t)
		return not op.is_active())
	var left := _alive_count(atk)
	var started := op.start_strength
	return {"started": true, "op": {"phase": op.phase_name(), "stage": op.stage_name(), "outcome": op.outcome, "losses": op.losses, "start": started},
		"owner": obj.owner, "attackers_left": left, "defenders_left": _alive_count(defs), "stages": st.stages, "roles_seen": st.roles.keys(),
		"max_assault_stall_s": snappedf(st.max_stall, 1.0), "withdrew": st.withdrew, "warp": w, "stage_why": op.stage_why, "withdraw_why": op.withdraw_why,
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


# --- Output (own prefix and file) ----------------------------------------------------------------

func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("STRAT %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("STRAT FAILED CHECK: ", msg)


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
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/ai_strat_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("STRAT %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
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

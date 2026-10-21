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

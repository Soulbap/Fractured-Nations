## QOL-01.1 checks in the real game on ref_20km (Development Scenario): the three paces, the behaviour's choice of them,
## animation sync, short tactical moves, repeated interruptions, STEALTH self-defence and the first-use route cost.
##
##   Godot.exe --path . --fullscreen --log-file q11.log res://scenes/game/world_ref_20km.tscn -- --qol011-test [--shots] [--only m_paces,...]
##
## m_paces      one squad walks, runs and sprints on the open site (explicit paces): measured body speed against the table,
##              the character's stride-matched playback (foot slip of the planted foot), crouch and prone capped at their clips.
## m_modes      four squads (SAFE / AWARE / COMBAT / STEALTH) march 300 m along an enemy's front (hold fire, reported): the pace
##              each soldier is given over time (share of walk / run / sprint), postures, pace changes per soldier per minute,
##              formation spread; and the same march with no enemy known.
## s_short      a COMBAT squad that knows of an enemy moves 70 m beside cover: how many soldiers end protected from the
##              believed threat with the cover slots off (QOL-01 behaviour) and on.
## i_multi      a player squad (AWARE) marches 650 m past three enemy groups: halts, resumes, its return fire, the interrupt
##              limit, arrival; a replacement order mid-halt.
## f_stealth    STEALTH self-defence: an enemy that holds fire 40 m away is engaged; one that fires from 140 m is answered;
##              a SUPPRESS order of the player at 150 m is carried out.
## q_spike      frame times around the first COMBAT and STEALTH orders after load (profile grids are built at load).
## c_views      the QOL-01 view continuity check again.
## Prints "Q11 <check> <json>", writes res://benchmarks/raw/qol011_test.json.
class_name Qol011SelfTest
extends Qol01SelfTest

const CHECKS11: Array[String] = ["q_spike", "m_paces", "m_modes", "s_short", "i_multi", "f_stealth", "c_views"]


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/qol01_1"
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKS11)
	SoldierBody.require_mouse_capture = false
	tree.create_timer(1800.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_cs = CombatScenario.new(demo)
	_site = _cs.find_site()
	_expect(not _site.is_empty(), "no open test site")
	if _site.is_empty():
		_finish()
		return
	_tcam = Camera3D.new()
	_tcam.fov = 50.0
	_tcam.far = 4000.0
	demo.add_child(_tcam)
	demo.rts.select_squads([])
	for n in CHECKS11:
		if only.has(n):
			if demo.game.mode != GameController.Mode.RTS:
				demo.game.enter_rts()
			_tcam.current = false
			demo.rts_camera.frame(_site.def, 0.6, 60.0)
			await _seconds(2.0)
			_log(n, await call("_" + n))
			_cs.reset()
			demo.rts.select_squads([])
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("Q11 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	CoreDemo.apply_time_scale(1.0)
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/qol011_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("Q11 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


# --- q_spike -------------------------------------------------------------------------------------------------------------------

func _q_spike() -> Dictionary:
	var routes: StrategicRoutes = demo.sim.war.routes
	var out := {"grids_built_at_load_ms": routes.profile_build_ms.duplicate()}
	_expect(routes.profile_build_ms.size() == 3, "q_spike: the profile grids were not built at load %s" % str(routes.profile_build_ms))
	var dir: Vector3 = _site.dir
	for b: int in [SquadBehaviour.COMBAT, SquadBehaviour.STEALTH]:
		var sq := _cs.spawn(0, _site.att, dir, 6, "QS%d" % b)
		sq.behaviour = b
		var goal := demo.on_ground(_site.att.x + dir.x * 1200.0, _site.att.z + dir.z * 1200.0, 0.0)
		var frames: Array = []
		var t := Time.get_ticks_usec()
		demo.sim.squads.order_move([sq.id], goal)
		for i in 90:
			await tree.process_frame
			var n := Time.get_ticks_usec()
			frames.append((n - t) / 1000.0)
			t = n
		frames.sort()
		out[SquadBehaviour.name_of(b)] = {"frame_ms_median": snappedf(frames[frames.size() / 2], 0.1), "frame_ms_max": snappedf(frames[-1], 0.1), "route": sq.route.size()}
	return out


# --- m_paces -------------------------------------------------------------------------------------------------------------------

func _m_paces() -> Dictionary:
	var out := {"table": UnitState.PACE_SPEED}
	var sp := _walk_spot()
	var at: Vector3 = sp[0]
	var dir: Vector3 = sp[1]
	var sq := _cs.spawn(0, at, dir, 1, "QM")
	var u := demo.sim.state.get_unit(sq.members[0])
	await _physics(20)
	var leg := 0
	for p: Array in [["walk", UnitState.Pace.WALK], ["run", UnitState.Pace.RUN], ["sprint", UnitState.Pace.SPRINT]]:
		var want: float = UnitState.PACE_SPEED[p[1]]
		var goal := demo.on_ground(u.position.x + dir.x * (want * 7.0 + 8.0) * (1 if leg % 2 == 0 else -1), u.position.z + dir.z * (want * 7.0 + 8.0) * (1 if leg % 2 == 0 else -1), 0.0)
		leg += 1
		demo.sim.squads.order_move([sq.id], goal, p[1])
		_cam_follow(u, 9.0, 1.2, 8.0)
		await _seconds(1.5)
		var foot := _foot_probe(u)
		var follow := func() -> Dictionary:
			_cam_follow(u, 7.0, 1.4, 6.0)
			return foot.call()
		var samples := await _record("pace_" + str(p[0]), 4.0, 3, follow)
		var vs: Array = []
		for s: Dictionary in samples:
			if s.has("v") and float(s.v) > 0.3:
				vs.append(float(s.v))
		vs.sort()
		var med: float = vs[vs.size() / 2] if not vs.is_empty() else -1.0
		out[p[0]] = {"want": want, "median_ms": snappedf(med, 0.01), "slip": _slip(samples), "pace_now": UnitState.PACE_NAMES[demo.sim.pace_of(u)]}
		_expect(absf(med - want) < want * 0.15 + 0.15, "m_paces: %s speed %.2f, want %.2f" % [p[0], med, want])
		_png("pace_" + str(p[0]))
		await _until(func() -> bool: return u.move_state != UnitState.MoveState.MOVING, 20.0, 1.0)
	# Crouched and prone: capped at what the clips stride.
	for pst: Array in [["crouch", Posture.CROUCH], ["prone", Posture.PRONE]]:
		Posture.set_now(u, pst[1])
		var goal := demo.on_ground(u.position.x + dir.x * 6.0, u.position.z + dir.z * 6.0, 0.0)
		demo.sim.squads.order_move([sq.id], goal, UnitState.Pace.SPRINT)
		Posture.set_now(u, pst[1])
		await _physics(5)
		var v := demo.sim.move_speed(u)
		out[pst[0] + "_sprint_ms"] = snappedf(v, 0.01)
		_expect(v <= Posture.MAX_SPEED[pst[1]] + 0.01, "m_paces: %s moves at %.2f m/s on a sprint order" % [pst[0], v])
		Posture.set_now(u, Posture.STAND)
	return out


# --- m_modes -------------------------------------------------------------------------------------------------------------------

func _m_modes() -> Dictionary:
	var out := {}
	var dir: Vector3 = _site.dir
	var side: Vector3 = _site.side
	var quiet := _quiet_spot()
	out["quiet_spot"] = {"at": _v(quiet[0]), "nearest_enemy_m": snappedf(float(quiet[1]), 1.0)}
	for known: bool in [true, false]:
		# Without an enemy the march runs where no soldier of another side stands within 1.2 km (the open site has a real
		# garrison of an AI faction about 250 m off, which a "no enemy" run there would meet).
		var base: Vector3 = _site.def if known else quiet[0]
		var enemy: SquadState = null
		if known:
			enemy = _cs.spawn(1, _site.def, -dir, 4, "QME")
			enemy.roe = SquadState.Roe.HOLD_FIRE
			_keep_alive([enemy])
		var sqs := []
		for b in 4:
			var st := demo.on_ground(base.x - dir.x * (180.0 + b * 30.0) - side.x * 150.0, base.z - dir.z * (180.0 + b * 30.0) - side.z * 150.0, 0.0)
			var sq := _cs.spawn(0, st, side, 6, "QB%d" % b)
			sq.behaviour = b
			sqs.append(sq)
		if known:
			# The faction is told where the enemy is (a report, as a sighting would): every squad believes in it.
			var eu := demo.sim.state.get_unit(enemy.members[0])
			demo.sim.war.intel.report_seen(demo.sim.state.get_unit((sqs[0] as SquadState).members[0]), eu, enemy.members.size())
		await _physics(30)
		for sq: SquadState in sqs:
			var c := demo.sim.squads._centroid(sq)
			demo.sim.squads.order_move([sq.id], demo.on_ground(c.x + side.x * 300.0, c.z + side.z * 300.0, 0.0))
		var counts := {}
		var post := {}
		var spread := {}
		var changes0 := demo.sim.pace_changes
		var t0 := demo.sim.state.time
		CoreDemo.apply_time_scale(2.0)
		var diag := {}
		for k in 60:
			await _physics(30)
			if k == 6 or k == 30:
				for sq: SquadState in sqs:
					var lu := demo.sim.state.get_unit(sq.leader_id)
					diag["%s_%d" % [sq.behaviour_name(), k]] = {"route": sq.route.size(), "route_i": sq.route_i, "wait": demo.sim.squads.route_waiting(sq),
						"goal_m": snappedf(demo.sim.squads._flat(lu.position, demo.sim.squads.move_goal(sq)), 1.0), "pace": UnitState.PACE_NAMES[demo.sim.pace_of(lu)],
						"threat_m": snappedf(demo.sim.tactics.threat_dist(sq), 1.0), "tactic": sq.tactic_name(), "text": demo.sim.squads.describe_order(sq).text}
			for sq: SquadState in sqs:
				var name := sq.behaviour_name()
				if not counts.has(name):
					counts[name] = [0, 0, 0]
					post[name] = [0, 0, 0]
					spread[name] = 0.0
				var c := demo.sim.squads._centroid(sq)
				for id in sq.members:
					var u := demo.sim.state.get_unit(id)
					if u.move_state == UnitState.MoveState.MOVING:
						counts[name][demo.sim.pace_of(u)] += 1
						post[name][u.posture] += 1
					spread[name] = maxf(float(spread[name]), demo.sim.squads._flat(u.position, c))
		CoreDemo.apply_time_scale(1.0)
		var minutes := maxf((demo.sim.state.time - t0) / 60.0, 0.01)
		out["diag_" + ("known" if known else "none")] = diag
		var row := {}
		for name: String in counts:
			var n := maxi(counts[name][0] + counts[name][1] + counts[name][2], 1)
			row[name] = {"walk": snappedf(counts[name][0] / float(n), 0.01), "run": snappedf(counts[name][1] / float(n), 0.01), "sprint": snappedf(counts[name][2] / float(n), 0.01),
				"crouched": snappedf(post[name][1] / float(n), 0.01), "prone": snappedf(post[name][2] / float(n), 0.01), "max_spread_m": snappedf(spread[name], 0.1)}
		row["pace_changes_per_soldier_min"] = snappedf((demo.sim.pace_changes - changes0) / (24.0 * minutes), 0.01)
		out["enemy_known" if known else "no_enemy"] = row
		for sq: SquadState in sqs:
			for id in sq.members:
				demo.sim.state.remove_unit(id)
		if enemy:
			for id in enemy.members:
				demo.sim.state.remove_unit(id)
		demo.sim.state.war.contacts.clear()
		demo.sim.war.intel.rebuild()
		await _physics(10)
	var k: Dictionary = out.enemy_known
	var q: Dictionary = out.no_enemy
	_expect(float(out.quiet_spot.nearest_enemy_m) > 1200.0, "m_modes: no quiet spot for the no-enemy march %s" % str(out.quiet_spot))
	_expect(float(q.Aware.run) > 0.8 and float(q.Combat.run) > 0.8 and float(q.Stealth.run) > 0.8, "m_modes: with nothing known the squads do not simply run %s" % str(q))
	_expect(float(k.Stealth.walk) + float(k.Stealth.sprint) > float(k.Stealth.run), "m_modes: STEALTH near a known enemy keeps running %s" % str(k.Stealth))
	_expect(float(k.Stealth.crouched) < 0.7, "m_modes: STEALTH crouch-walks most of the time %s" % str(k.Stealth))
	_expect(float(q.Safe.walk) < 0.2, "m_modes: SAFE walks a long march %s" % str(q.Safe))
	_expect(float(k.pace_changes_per_soldier_min) < 12.0, "m_modes: pace flicker %s per soldier and minute" % str(k.pace_changes_per_soldier_min))
	for name: String in k:
		if k[name] is Dictionary:
			_expect(float(k[name].max_spread_m) < 60.0, "m_modes: %s formation came apart (%.0f m)" % [name, k[name].max_spread_m])
	return out


## The point within 4 km of the site farthest from any soldier of another side (passable): [position, distance to the nearest].
func _quiet_spot() -> Array:
	var routes: StrategicRoutes = demo.sim.war.routes
	var best := [_site.def, 0.0]
	for r: float in [1500.0, 2500.0, 3500.0]:
		for k in 16:
			var a := k * TAU / 16.0
			var p := demo.on_ground(_site.def.x + cos(a) * r, _site.def.z + sin(a) * r, 0.0)
			if absf(p.x) > 9000.0 or absf(p.z) > 9000.0 or not routes.passable(p):
				continue
			var near := INF
			for u: UnitState in demo.sim.state.soldiers():
				if u.alive and u.faction != 0:
					near = minf(near, demo.sim.squads._flat(u.position, p))
			if near > float(best[1]):
				best = [p, near]
	return best


# --- s_short -------------------------------------------------------------------------------------------------------------------

func _protected_count(sq: SquadState, threat: Vector3) -> int:
	var n := 0
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if u and demo.sim.brain._evaluate_spot(u, u.position, threat).protected:
			n += 1
	return n


func _s_short() -> Dictionary:
	var out := {}
	var dir: Vector3 = _site.dir
	var side: Vector3 = _site.side
	var sc := demo.sim.squads
	# At the quiet spot (no live garrison near: at the open site the AI faction's soldiers 250 m off fire on the squad and its
	# tactics, not the move, decide where it stands). Cover beside the destination, not in front of it.
	var q: Vector3 = _quiet_spot()[0]
	var start := demo.on_ground(q.x - side.x * 35.0, q.z - side.z * 35.0, 0.0)
	var enemy_at := demo.on_ground(q.x + dir.x * 200.0, q.z + dir.z * 200.0, 0.0)
	var dest := demo.on_ground(q.x + side.x * 35.0, q.z + side.z * 35.0, 0.0)
	out["at"] = _v(q)
	var cs := demo.sim.state.construction
	var w0 := dest + dir * 4.0 + side * 6.0
	var w1 := dest + dir * 4.0 + side * 18.0
	_cs._track(cs.add_line(&"concrete_barrier", PackedVector3Array([demo.on_ground(w0.x, w0.z, 0.0), demo.on_ground(w1.x, w1.z, 0.0)])))
	await _physics(20)
	for b: int in [SquadBehaviour.AWARE, SquadBehaviour.COMBAT, SquadBehaviour.STEALTH]:
		# The enemy is reported (a contact the faction believes in), then leaves: nobody fires, the squad is not interrupted.
		var enemy := _cs.spawn(1, enemy_at, -dir, 4, "QSE")
		var sq := _cs.spawn(0, start, side, 6, "QSS")
		sq.behaviour = b
		demo.sim.war.intel.report_seen(demo.sim.state.get_unit(sq.members[0]), demo.sim.state.get_unit(enemy.members[0]), 4)
		await _until(func() -> bool: return demo.sim.tactics.threat_pos(sq).is_finite(), 10.0, 1.0)
		for id in enemy.members:
			demo.sim.state.remove_unit(id)
		var threat := demo.sim.tactics.threat_pos(sq)
		sc.order_move([sq.id], dest)
		await _until(func() -> bool: return sq.status != SquadState.Status.MOVING, 60.0, 2.0)
		await _physics(30)
		# Cover the ground offers: protected spots within 10 m of each soldier's end position (CombatBrain's own search).
		var near_cover := 0
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			for c: Dictionary in demo.sim.brain.cover_spots(u.position, 10.0, threat, u.position, 6):
				if demo.sim.brain._evaluate_spot(u, c.p, threat).protected:
					near_cover += 1
					break
		out[sq.behaviour_name()] = {"protected_at_end": _protected_count(sq, threat), "with_cover_within_10m": near_cover, "of": sq.members.size(),
			"threat_known": threat.is_finite(), "state": sc.describe_order(sq).text}
		if b == SquadBehaviour.COMBAT:
			demo.rts_camera.frame(dest, atan2(dir.x, dir.z), 45.0)
			await _seconds(1.0)
			_png("short_combat")
		for id in sq.members:
			demo.sim.state.remove_unit(id)
		demo.sim.state.war.contacts.clear()
		demo.sim.war.intel.rebuild()
		await _physics(10)
	_expect(bool(out.Combat.threat_known), "s_short: the squad did not know of the enemy - the check proves nothing")
	return out


# --- i_multi -------------------------------------------------------------------------------------------------------------------

func _i_multi() -> Dictionary:
	var out := {}
	var dir: Vector3 = _site.dir
	var side: Vector3 = _site.side
	var start := demo.on_ground(_site.def.x - dir.x * 160.0 - side.x * 300.0, _site.def.z - dir.z * 160.0 - side.z * 300.0, 0.0)
	var goal := demo.on_ground(start.x + side.x * 650.0, start.z + side.z * 650.0, 0.0)
	var groups := []
	for k in 3:
		var p := start + side * (130.0 + k * 190.0) + dir * 150.0
		var e := _cs.spawn(1, demo.on_ground(p.x, p.z, 0.0), -dir, 2, "QX%d" % k)
		groups.append(e)
	var sq := _cs.spawn(0, start, side, 6, "QI")
	_keep_alive([sq])
	for e: SquadState in groups:
		for id in e.members:
			demo.sim.state.get_unit(id).max_health = 60.0
	var shots0 := _shots_of(sq)
	var events0 := demo.sim.reports.log.size()
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(goal)
	var t := await _until(func() -> bool: return (sq.status != SquadState.Status.MOVING and not demo.sim.squads.marching(sq) and sq.tactic == SquadState.Tactic.NONE and sq.order == SquadState.Order.MOVE) or sq.order == SquadState.Order.HOLD, 600.0, 4.0)
	var c := demo.sim.squads._centroid(sq)
	var kinds := []
	for e: Dictionary in demo.sim.reports.log.slice(events0):
		if int(e.squad) == sq.id:
			kinds.append(e.kind)
	var enemy_alive := 0
	for e: SquadState in groups:
		enemy_alive += e.members.size()
	out["march"] = {"sim_s": snappedf(t, 1.0), "left_m": snappedf(demo.sim.squads._flat(c, goal), 1.0), "interrupts": sq.interrupts, "order": sq.order_name(),
		"shots": _shots_of(sq) - shots0, "enemy_left": enemy_alive, "notices": kinds}
	_expect(float(out.march.left_m) < 40.0, "i_multi: the squad did not reach its goal past three contacts %s" % str(out.march))
	_expect(_shots_of(sq) - shots0 > 0, "i_multi: the squad never fired back")
	_expect(sq.interrupts <= SquadBehaviour.MAX_INTERRUPTS + 2, "i_multi: interruptions ran away (%d)" % sq.interrupts)
	# A replacement order while halted takes over at once.
	var e2 := _cs.spawn(1, _site.def, -dir, 4, "QY")
	_keep_alive([e2])
	demo.rts.order_move(start)
	await _until(func() -> bool: return sq.interrupted, 90.0, 2.0)
	var halted := sq.interrupted
	var back := demo.on_ground(c.x - dir.x * 60.0, c.z - dir.z * 60.0, 0.0)
	demo.rts.order_move(back)
	await _physics(5)
	out["replacement"] = {"was_halted": halted, "interrupted": sq.interrupted, "goal": _v(demo.sim.squads.move_goal(sq)), "want": _v(back)}
	_expect(halted and not sq.interrupted and demo.sim.squads.move_goal(sq).distance_to(back) < 30.0, "i_multi: a new order did not replace the halted move %s" % str(out.replacement))
	return out


# --- f_stealth -----------------------------------------------------------------------------------------------------------------

func _f_stealth() -> Dictionary:
	var out := {}
	var dir: Vector3 = _site.dir
	# a) An enemy 40 m away holding fire (it has not shot): within the 50 m limit, the STEALTH squad engages it.
	var cases := [["close_40m", 40.0, SquadState.Roe.HOLD_FIRE], ["fired_on_140m", 140.0, SquadState.Roe.WEAPONS_FREE]]
	for cdef: Array in cases:
		var e := _cs.spawn(1, _site.def, -dir, 3, "QFE")
		e.roe = cdef[2]
		var p := demo.on_ground(_site.def.x - dir.x * float(cdef[1]), _site.def.z - dir.z * float(cdef[1]), 0.0)
		var sq := _cs.spawn(0, p, dir, 4, "QF")
		sq.behaviour = SquadBehaviour.STEALTH
		_keep_alive([sq, e])
		demo.sim.squads.order_hold([sq.id])
		var s0 := _shots_of(sq)
		var t := await _until(func() -> bool: return _shots_of(sq) > s0, 45.0, 2.0)
		out[cdef[0]] = {"answered_after_s": snappedf(t, 0.1), "shots": _shots_of(sq) - s0, "acts": SquadBehaviour.name_of(demo.sim.tactics.behaviour_now(sq))}
		_expect(_shots_of(sq) > s0, "f_stealth: %s - the STEALTH squad did not defend itself" % cdef[0])
		for id in sq.members + e.members:
			demo.sim.state.remove_unit(id)
		demo.sim.state.war.contacts.clear()
		demo.sim.war.intel.rebuild()
		await _physics(10)
	# c) The player orders SUPPRESS at a reported enemy 150 m away (not found yet): the order is carried out.
	var e3 := _cs.spawn(1, _site.def, -dir, 3, "QFS")
	e3.roe = SquadState.Roe.HOLD_FIRE
	var sq3 := _cs.spawn(0, demo.on_ground(_site.def.x - dir.x * 150.0, _site.def.z - dir.z * 150.0, 0.0), dir, 4, "QFP")
	sq3.behaviour = SquadBehaviour.STEALTH
	_keep_alive([sq3, e3])
	demo.sim.war.intel.report_seen(demo.sim.state.get_unit(sq3.members[0]), demo.sim.state.get_unit(e3.members[0]), 3)
	await _physics(20)
	demo.rts.select_squads([sq3.id])
	var res := demo.rts.order_tactic(SquadState.Tactic.SUPPRESS, _site.def)
	var s3 := _shots_of(sq3)
	var t3 := await _until(func() -> bool: return _shots_of(sq3) > s3, 45.0, 2.0)
	out["player_suppress_150m"] = {"accepted": res.ok, "text": res.text, "fired_after_s": snappedf(t3, 0.1), "shots": _shots_of(sq3) - s3}
	_expect(not res.ok or _shots_of(sq3) > s3, "f_stealth: the player's SUPPRESS order was not carried out by a STEALTH squad %s" % str(out.player_suppress_150m))
	return out

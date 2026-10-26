## QOL-01 checks in the real game on ref_20km (Development Scenario): behaviour modes, order feedback, interrupted moves,
## notices and view continuity. Short, deterministic set-ups on the CombatScenario site; time compressed where it only waits.
##
##   Godot.exe --path . --fullscreen --log-file q1.log res://scenes/game/world_ref_20km.tscn -- --qol01-test [--shots] [--only r_routes,...] [--shot-dir=res://docs/qol01]
##
## r_routes     the same start and destination planned for SAFE / AWARE / COMBAT / STEALTH on the world's grid (road share, forest
##              cover along the route, length, detour against the ordinary route), then with a believed enemy beside the
##              ordinary route (distance kept from it); profile grid build and route times. A live STEALTH march checks that an
##              order really gets the stealth route.
## b_modes      a squad's behaviour set while it moves (the order goes on, no tactic, a march re-plans), every mode, persisted
##              through a real save / load, never changed by a reaction (a SAFE squad under fire acts as COMBAT, stays SAFE).
## p_posture    an enemy fire team on hold fire 130 m away, seen: a STEALTH squad holding goes low (crouch / prone) and holds
##              its fire; SAFE stays upright; AWARE as before; STEALTH moving near it walks crouched; a STEALTH squad fires
##              once it is fired on (compromised).
## i_interrupt  a player squad (AWARE) moves past an enemy that fires on it: the move is interrupted (squad tactic, the
##              final goal kept), resumes when the enemy is gone, arrives; a HOLD given while interrupted is not overridden;
##              a new move replaces the interrupted one; at most MAX_INTERRUPTS per order.
## n_notices    notices about the player's squads (interrupted / resumed / arrived / blocked) reach the war log with the
##              squad; a click on one selects the squad and frames the camera on it; a notice of a squad that is gone does
##              nothing harmful; a vehicle failure carries its vehicle.
## c_views      selection and state through first person -> tactical -> map -> tactical; the possessed soldier's squad is
##              selected on return; the map opens with the tactical selection and hands its own back.
## z_shots      the command panel (two rows, behaviour group, order line), the roster with modes, a clickable notice, the map
##              and the first-person squad card (with --shots).
## Prints "Q1 <check> <json>", writes res://benchmarks/raw/qol01_test.json.
class_name Qol01SelfTest
extends Visual03SelfTest

const CHECKSQ: Array[String] = ["r_routes", "b_modes", "p_posture", "i_interrupt", "n_notices", "c_views", "z_shots", "q_perf"]


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/qol01"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKSQ)
	SoldierBody.require_mouse_capture = false
	tree.create_timer(1500.0, true, false, true).timeout.connect(func() -> void:
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
	for n in CHECKSQ:
		if only.has(n):
			if demo.game.mode != GameController.Mode.RTS:
				demo.game.enter_rts()
			demo.rts_camera.frame(_site.def, 0.6, 60.0)
			await _seconds(2.0)
			_log(n, await call("_" + n))
			_cs.reset()
			demo.rts.select_squads([])
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("Q1 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	CoreDemo.apply_time_scale(1.0)
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/qol01_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("Q1 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


func _keep_alive(squads: Array) -> void:
	var fn := func(_s: Variant = null) -> void:
		for sq: SquadState in squads:
			for id in sq.members:
				var uu := demo.sim.state.get_unit(id)
				if uu:
					uu.max_health = 100000.0
					uu.health = uu.max_health
	fn.call()
	demo.sim.state.shot_fired.connect(fn)


func _sim() -> WorldSim:
	return demo.sim


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.1), snappedf(p.z, 0.1)] if p.is_finite() else []


## Facts of a route on the grid: length, share on road cells, mean forest density, legs clear, closest approach to `near`.
func _route_facts(r: PackedVector3Array, near := Vector3.INF) -> Dictionary:
	var routes: StrategicRoutes = _sim().war.routes
	var n := 0
	var on_road := 0
	var cov := 0.0
	var clear := true
	var closest := INF
	for i in range(1, r.size()):
		if not routes._leg_clear(r[i - 1], r[i]):
			clear = false
		var d := Vector2(r[i].x - r[i - 1].x, r[i].z - r[i - 1].z).length()
		var k := maxi(1, ceili(d / 10.0))
		for j in k:
			var p := r[i - 1].lerp(r[i], float(j) / k)
			var c := routes.world_to_cell(p)
			if not routes._in(c):
				continue
			var idx := c.y * routes.size.x + c.x
			n += 1
			on_road += routes.road[idx]
			cov += routes.cover[idx] / 255.0 if idx < routes.cover.size() else 0.0
			if near.is_finite():
				closest = minf(closest, Vector2(p.x - near.x, p.z - near.z).length())
	return {"length": snappedf(routes.route_length(r), 1.0), "road": snappedf(float(on_road) / maxi(n, 1), 0.01),
		"cover": snappedf(cov / maxi(n, 1), 0.01), "clear": clear and r.size() >= 2, "closest_to_threat": snappedf(closest, 1.0) if near.is_finite() else -1.0}


# --- r_routes -------------------------------------------------------------------------------------------------------------

func _r_routes() -> Dictionary:
	var routes: StrategicRoutes = _sim().war.routes
	var terrain := _sim().terrain
	var out := {"cover_cells": routes.cover.size(), "pairs": []}
	_expect(routes.cover.size() == routes.size.x * routes.size.y, "r_routes: the grid has no cover layer")
	# Candidate pairs: 1.6 km chords through the open site and the objectives, 8 headings each (deterministic).
	var centres: Array[Vector3] = [_site.def]
	for o: ObjectiveState in demo.sim.state.war.all_objectives():
		centres.append(o.position)
		if centres.size() >= 5:
			break
	var best := {}
	var best_score := -INF
	var t_routes := []
	for c in centres:
		for k in 8:
			var a := k * TAU / 8.0 + 0.2
			var d := Vector3(cos(a), 0, sin(a)) * 800.0
			var from := demo.on_ground(c.x - d.x, c.z - d.z, 0.0)
			var to := demo.on_ground(c.x + d.x, c.z + d.z, 0.0)
			if not routes.passable(from) or not routes.passable(to):
				continue
			var facts := {}
			for p: String in ["safe", "aware", "combat", "stealth"]:
				var t0 := Time.get_ticks_usec()
				var r := routes.route_profiled(from, to, terrain, p)
				t_routes.append((Time.get_ticks_usec() - t0) / 1000.0)
				facts[p] = _route_facts(r)
				facts[p]["fallback"] = routes.last_profile.get("fallback", "")
				_expect(r.size() < 2 or bool(facts[p].clear), "r_routes: a %s route crosses an impassable cell" % p)
			if not bool(facts.aware.clear):
				continue
			var score := float(facts.stealth.cover) - float(facts.safe.cover) + float(facts.safe.road) - float(facts.stealth.road)
			var row := {"from": _v(from), "to": _v(to), "routes": facts}
			out.pairs.append(row)
			if score > best_score:
				best_score = score
				best = row
	_expect(not best.is_empty(), "r_routes: no usable pair")
	if best.is_empty():
		return out
	out["best"] = best
	# Over all pairs: stealth keeps to cover and off roads, safe keeps to roads (on average; where one route is best for
	# every mode they are allowed to be the same).
	var sums := {"safe": [0.0, 0.0], "aware": [0.0, 0.0], "combat": [0.0, 0.0], "stealth": [0.0, 0.0]}
	var differ := 0
	for row: Dictionary in out.pairs:
		for p: String in sums:
			sums[p][0] += float(row.routes[p].road)
			sums[p][1] += float(row.routes[p].cover)
		if row.routes.safe.length != row.routes.stealth.length:
			differ += 1
	var np := maxi(out.pairs.size(), 1)
	var means := {}
	for p: String in sums:
		means[p] = {"road": snappedf(sums[p][0] / np, 0.01), "cover": snappedf(sums[p][1] / np, 0.01)}
	out["means"] = means
	out["pairs_differing"] = differ
	_expect(float(means.stealth.cover) > float(means.aware.cover), "r_routes: stealth routes are not in more cover than aware ones %s" % str(means))
	_expect(float(means.safe.road) >= float(means.aware.road), "r_routes: safe routes keep less to roads than aware ones %s" % str(means))
	_expect(float(means.stealth.road) < float(means.aware.road), "r_routes: stealth routes do not avoid roads %s" % str(means))
	# Detour limit: no profile route longer than its limit x the ordinary route (+100 m).
	for row: Dictionary in out.pairs:
		for p: String in ["safe", "combat", "stealth"]:
			_expect(float(row.routes[p].length) <= float(row.routes.aware.length) * float(StrategicRoutes.PROFILES[p].detour) + 101.0,
				"r_routes: %s route beyond its detour limit %s" % [p, str(row.routes)])
	# A believed enemy (strength 4) on the ordinary route's midpoint.
	var bf := Vector3(best.from[0], 0, best.from[1])
	var bt := Vector3(best.to[0], 0, best.to[1])
	var plain := routes.route(bf, bt, terrain)
	var mid := plain[plain.size() / 2]
	var threat := {StrategicInfluence._cell(mid): 4.0}
	var with_threat := {}
	for p: String in ["safe", "aware", "combat", "stealth"]:
		var r := routes.route_profiled(bf, bt, terrain, p, threat)
		with_threat[p] = _route_facts(r, mid)
		with_threat[p]["fallback"] = routes.last_profile.get("fallback", "")
	out["threat_at"] = _v(mid)
	out["with_threat"] = with_threat
	out["plain_closest"] = _route_facts(plain, mid).closest_to_threat
	_expect(float(with_threat.stealth.closest_to_threat) > float(out.plain_closest) or with_threat.stealth.fallback != "",
		"r_routes: the stealth route does not keep away from the believed enemy %s" % str(with_threat))
	_expect(float(with_threat.combat.closest_to_threat) >= float(with_threat.safe.closest_to_threat) - 1.0,
		"r_routes: combat keeps less distance from the enemy than safe %s" % str(with_threat))
	t_routes.sort()
	out["route_ms"] = {"median": snappedf(t_routes[t_routes.size() / 2], 0.01), "max": snappedf(t_routes[-1], 0.01), "n": t_routes.size()}
	out["grid_build_ms"] = routes.profile_build_ms
	# A live order: a STEALTH squad's move gets the stealth route.
	var sq := _cs.spawn(0, bf, (bt - bf).normalized(), 4, "QS")
	sq.behaviour = SquadBehaviour.STEALTH
	demo.sim.squads.order_move([sq.id], demo.on_ground(bt.x, bt.z, 0.0))
	await _until(func() -> bool: return not sq.route.is_empty(), 20.0, 1.0)
	var rp: Dictionary = demo.sim.squads.route_profile.get(sq.id, {})
	out["live"] = {"route_points": sq.route.size(), "profile": rp, "described": demo.sim.squads.describe_order(sq).text}
	_expect(String(rp.get("profile", "")) == "stealth", "r_routes: the live STEALTH order did not get a stealth route %s" % str(rp))
	return out


# --- b_modes ---------------------------------------------------------------------------------------------------------------

func _b_modes() -> Dictionary:
	var out := {}
	var sq := _cs.spawn(0, _site.att, _site.dir, 6, "QB")
	var goal := demo.on_ground(_site.att.x + _site.side.x * 110.0, _site.att.z + _site.side.z * 110.0, 0.0)
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(goal)
	out["ack"] = demo.rts.tactic_feedback
	_expect(demo.rts.tactic_feedback.begins_with("Move accepted") and demo.rts.tactic_feedback.contains(sq.squad_name), "b_modes: no move acknowledgement (%s)" % demo.rts.tactic_feedback)
	await _seconds(2.0)
	var steps := []
	for b: int in [SquadBehaviour.COMBAT, SquadBehaviour.STEALTH, SquadBehaviour.SAFE, SquadBehaviour.AWARE]:
		demo.rts.set_behaviour(b)
		await _physics(30)
		steps.append({"mode": sq.behaviour_name(), "order": sq.order_name(), "status": sq.status, "tactic": sq.tactic_name(), "target": _v(sq.order_target), "spacing_gap": snappedf(demo.sim.squads._gap(sq), 0.01)})
		_expect(sq.behaviour == b, "b_modes: behaviour %d not set" % b)
		_expect(sq.order == SquadState.Order.MOVE and sq.tactic == SquadState.Tactic.NONE, "b_modes: changing the mode changed the order (%s)" % str(steps[-1]))
		_expect(sq.order_target.distance_to(goal) < 30.0, "b_modes: the move target moved when the mode changed")
	out["steps"] = steps
	# A reaction never rewrites the selected mode: SAFE under fire acts as COMBAT and stays SAFE.
	demo.sim.squads.set_behaviour([sq.id], SquadBehaviour.SAFE)
	var fake := {"n": 6, "under_fire": 2, "in_contact": true}
	out["safe_under_fire_acts"] = SquadBehaviour.name_of(SquadBehaviour.effective(SquadBehaviour.SAFE, fake, false))
	_expect(SquadBehaviour.effective(SquadBehaviour.SAFE, fake, false) == SquadBehaviour.COMBAT and sq.behaviour == SquadBehaviour.SAFE, "b_modes: SAFE under fire")
	_expect(SquadBehaviour.effective(SquadBehaviour.STEALTH, {"n": 6}, true) == SquadBehaviour.COMBAT, "b_modes: compromised STEALTH")
	# Save / load: the mode and the interruption record survive.
	demo.sim.squads.set_behaviour([sq.id], SquadBehaviour.STEALTH)
	sq.interrupts = 2
	var sid := sq.id
	_expect(demo.construction.save(), "b_modes: save failed")
	demo.sim.squads.set_behaviour([sq.id], SquadBehaviour.SAFE)
	var lr: Dictionary = demo.construction.load_game()
	await _physics(10)
	var back := demo.sim.state.get_squad(sid)
	out["after_load"] = {"ok": lr.get("ok", false), "mode": back.behaviour_name() if back else "-", "interrupts": back.interrupts if back else -1}
	_expect(back != null and back.behaviour == SquadBehaviour.STEALTH and back.interrupts == 2, "b_modes: behaviour not restored by load %s" % str(out.after_load))
	return out


# --- p_posture -------------------------------------------------------------------------------------------------------------

func _postures(sq: SquadState) -> Dictionary:
	var c := {"standing": 0, "crouching": 0, "prone": 0}
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if u and u.alive:
			c[Posture.NAMES[u.posture]] += 1
	return c


func _shots_of(sq: SquadState) -> int:
	var n := 0
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if u:
			n += u.shot_counter
	return n


func _p_posture() -> Dictionary:
	var out := {}
	var dir: Vector3 = _site.dir
	var enemy := _cs.spawn(1, _site.def, -dir, 4, "QE")
	enemy.roe = SquadState.Roe.HOLD_FIRE
	_keep_alive([enemy])
	var at := demo.on_ground(_site.def.x - dir.x * 130.0, _site.def.z - dir.z * 130.0, 0.0)
	var per := {}
	for b: int in [SquadBehaviour.SAFE, SquadBehaviour.AWARE, SquadBehaviour.STEALTH]:
		var sq := _cs.spawn(0, at, dir, 4, "QP%d" % b)
		sq.behaviour = b
		demo.sim.squads.order_hold([sq.id])
		var shots0 := _shots_of(sq)
		await _until(func() -> bool: return false, 25.0, 2.0)
		var a := demo.sim.tactics.assessment(sq)
		per[SquadBehaviour.name_of(b)] = {"postures": _postures(sq), "shots": _shots_of(sq) - shots0, "threat_m": snappedf(float(a.get("dist", INF)), 1.0) if a.get("dist", INF) != INF else -1,
			"acts": SquadBehaviour.name_of(demo.sim.tactics.behaviour_now(sq)), "reason": demo.sim.state.get_unit(sq.members[0]).ai_reason}
		for id in sq.members:
			demo.sim.state.remove_unit(id)
		demo.sim.state.war.contacts.clear()
		demo.sim.war.intel.rebuild()
		await _physics(5)
	out["holding"] = per
	_expect(int(per.Stealth.shots) == 0, "p_posture: STEALTH fired at range while not found %s" % str(per.Stealth))
	_expect(int(per.Stealth.postures.standing) == 0, "p_posture: STEALTH squad stood up near the enemy %s" % str(per.Stealth))
	_expect(String(per.Safe.acts) == "Aware", "p_posture: SAFE in contact does not act AWARE %s" % str(per.Safe))
	_expect(int(per.Aware.shots) > 0, "p_posture: AWARE (control) did not fire at a visible enemy - the set-up proves nothing %s" % str(per.Aware))
	# STEALTH moving across the enemy's front, 120 m out: crouched on the move.
	var sq2 := _cs.spawn(0, at, dir, 4, "QM")
	sq2.behaviour = SquadBehaviour.STEALTH
	var side: Vector3 = _site.side
	await _until(func() -> bool: return not demo.sim.tactics.assessment(sq2).is_empty() and demo.sim.tactics.threat_dist(sq2) < 250.0, 20.0, 2.0)
	demo.sim.squads.order_move([sq2.id], demo.on_ground(at.x + side.x * 60.0, at.z + side.z * 60.0, 0.0))
	var moving_crouched := 0
	var moving := 0
	for i in 40:
		await _physics(6)
		for id in sq2.members:
			var u := demo.sim.state.get_unit(id)
			if u and u.move_state == UnitState.MoveState.MOVING and u.order == UnitState.Order.MOVE:
				moving += 1
				if u.posture == Posture.CROUCH:
					moving_crouched += 1
	out["stealth_moving"] = {"samples": moving, "crouched": moving_crouched, "threat_m": snappedf(demo.sim.tactics.threat_dist(sq2), 1.0)}
	_expect(moving > 10 and moving_crouched * 2 >= moving, "p_posture: STEALTH did not move crouched near the enemy %s" % str(out.stealth_moving))
	# Compromised: the enemy opens fire; the STEALTH squad answers.
	enemy.roe = SquadState.Roe.WEAPONS_FREE
	var shots0 := _shots_of(sq2)
	await _until(func() -> bool: return _shots_of(sq2) > shots0, 40.0, 2.0)
	out["compromised"] = {"answered": _shots_of(sq2) - shots0, "acts": SquadBehaviour.name_of(demo.sim.tactics.behaviour_now(sq2)), "mode": sq2.behaviour_name()}
	_expect(_shots_of(sq2) > shots0 and sq2.behaviour == SquadBehaviour.STEALTH, "p_posture: a compromised STEALTH squad did not fight back (or lost its mode) %s" % str(out.compromised))
	return out


# --- i_interrupt -----------------------------------------------------------------------------------------------------------

func _i_interrupt() -> Dictionary:
	var out := {}
	var dir: Vector3 = _site.dir
	var side: Vector3 = _site.side
	var enemy := _cs.spawn(1, _site.def, -dir, 4, "QX")
	var start := demo.on_ground(_site.def.x - dir.x * 150.0 - side.x * 160.0, _site.def.z - dir.z * 150.0 - side.z * 160.0, 0.0)
	var goal := demo.on_ground(_site.def.x - dir.x * 150.0 + side.x * 200.0, _site.def.z - dir.z * 150.0 + side.z * 200.0, 0.0)
	var sq := _cs.spawn(0, start, side, 6, "QI")
	_keep_alive([sq, enemy])
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(goal)
	var events0 := demo.sim.reports.log.size()
	var t := await _until(func() -> bool: return sq.interrupted, 90.0, 2.0)
	out["interrupt"] = {"after_s": snappedf(t, 0.1), "interrupted": sq.interrupted, "tactic": sq.tactic_name(), "owner": sq.owner_name(), "why": sq.tactic_why,
		"resume_to": _v(sq.prev_target), "goal": _v(goal), "described": demo.sim.squads.describe_order(sq).text}
	_expect(sq.interrupted and sq.prev_target.is_finite() and Vector2(sq.prev_target.x - goal.x, sq.prev_target.z - goal.z).length() < 30.0,
		"i_interrupt: the move was not interrupted with its goal kept %s" % str(out.interrupt))
	# The enemy is gone (and forgotten): the squad resumes its move by itself.
	for id in enemy.members:
		demo.sim.state.remove_unit(id)
	demo.sim.state.war.contacts.clear()
	demo.sim.war.intel.rebuild()
	t = await _until(func() -> bool: return not sq.interrupted and sq.order == SquadState.Order.MOVE, 120.0, 4.0)
	out["resume"] = {"after_s": snappedf(t, 0.1), "order": sq.order_name(), "target": _v(demo.sim.squads.move_goal(sq)), "resumes": demo.sim.tactics.resumes}
	_expect(sq.order == SquadState.Order.MOVE and Vector2(demo.sim.squads.move_goal(sq).x - goal.x, demo.sim.squads.move_goal(sq).z - goal.z).length() < 30.0,
		"i_interrupt: the move did not resume to its goal %s" % str(out.resume))
	t = await _until(func() -> bool: return sq.status != SquadState.Status.MOVING and not demo.sim.squads.marching(sq), 240.0, 4.0)
	var c := demo.sim.squads._centroid(sq)
	out["arrived"] = {"after_s": snappedf(t, 0.1), "left_m": snappedf(Vector2(c.x - goal.x, c.z - goal.z).length(), 1.0), "state": demo.sim.squads.describe_order(sq).state}
	_expect(float(out.arrived.left_m) < 30.0, "i_interrupt: the resumed move did not arrive %s" % str(out.arrived))
	var kinds := []
	for e: Dictionary in demo.sim.reports.log.slice(events0):
		if int(e.squad) == sq.id:
			kinds.append(e.kind)
	await _physics(90)
	kinds = []
	for e: Dictionary in demo.sim.reports.log.slice(events0):
		if int(e.squad) == sq.id:
			kinds.append(e.kind)
	out["notices"] = kinds
	_expect(kinds.has("interrupted") and kinds.has("resumed") and kinds.has("arrived"), "i_interrupt: notices missing %s" % str(kinds))
	# HOLD wins: interrupted, then the player holds - no resume.
	var enemy2 := _cs.spawn(1, _site.def, -dir, 4, "QY")
	_keep_alive([enemy2])
	demo.rts.order_move(start)
	await _until(func() -> bool: return sq.interrupted, 90.0, 2.0)
	var was := sq.interrupted
	demo.rts.order_hold()
	for id in enemy2.members:
		demo.sim.state.remove_unit(id)
	demo.sim.state.war.contacts.clear()
	demo.sim.war.intel.rebuild()
	await _until(func() -> bool: return false, 50.0, 4.0)
	var c2 := demo.sim.squads._centroid(sq)
	out["hold"] = {"was_interrupted": was, "order": sq.order_name(), "tactic": sq.tactic_name(), "prev": SquadState.ORDER_NAMES[sq.prev_order], "interrupted": sq.interrupted,
		"moved_on_m": snappedf(Vector2(c2.x - start.x, c2.z - start.z).length(), 1.0), "goal": _v(demo.sim.squads.move_goal(sq))}
	# The hold is the order now: no move resumes (it may defend where it holds, as any holding squad does).
	_expect(was and not sq.interrupted and sq.order != SquadState.Order.MOVE and sq.prev_order != SquadState.Order.MOVE,
		"i_interrupt: the interrupted move resumed over the player's HOLD %s" % str(out.hold))
	out["interruptions_total"] = demo.sim.tactics.interruptions
	_expect(sq.interrupts <= SquadBehaviour.MAX_INTERRUPTS, "i_interrupt: more interruptions than allowed")
	return out


# --- n_notices ---------------------------------------------------------------------------------------------------------------

func _n_notices() -> Dictionary:
	var out := {}
	var sq := _cs.spawn(0, _site.att, _site.dir, 4, "QN")
	var goal := demo.on_ground(_site.att.x + _site.side.x * 60.0, _site.att.z + _site.side.z * 60.0, 0.0)
	demo.sim.squads.order_move([sq.id], goal)
	await _until(func() -> bool: return sq.status != SquadState.Status.MOVING, 60.0, 2.0)
	await _physics(80)
	var war := demo.sim.state.war
	var arrived := war.events.filter(func(e: Dictionary) -> bool: return e.kind == "squad_arrived" and int(e.get("squad", -1)) == sq.id)
	out["arrived_event"] = arrived.back() if not arrived.is_empty() else {}
	_expect(not arrived.is_empty(), "n_notices: no arrival notice in the war log")
	# Blocked: a member reports BLOCKED (the navigation's own state) -> describe_order and a notice with the reason.
	demo.sim.squads.order_move([sq.id], demo.on_ground(goal.x + 40.0, goal.z, 0.0))
	await _physics(10)
	var u := demo.sim.state.get_unit(sq.members[1])
	await _until(func() -> bool:
		for id in sq.members:
			var m := demo.sim.state.get_unit(id)
			if m.id != u.id and m.move_state == UnitState.MoveState.MOVING:
				return false
		return true, 40.0, 2.0)
	# The soldier reports BLOCKED as the navigation does when a slot cannot be reached; SquadControl's member recovery (one
	# fresh attempt, which here would simply succeed) is switched off for the check so the report stands.
	var replans := demo.sim.squads.member_replans
	demo.sim.squads.member_replans = 0
	u.move_state = UnitState.MoveState.BLOCKED
	u.order = UnitState.Order.NONE
	u.nav_reason = "QOL test: slot unreachable"
	await _physics(120)
	demo.sim.squads.member_replans = replans
	var blocked := war.events.filter(func(e: Dictionary) -> bool: return e.kind == "squad_blocked" and int(e.get("squad", -1)) == sq.id)
	out["blocked"] = {"described": demo.sim.squads.describe_order(sq), "event": blocked.back() if not blocked.is_empty() else {}}
	_expect(not blocked.is_empty() and String(blocked.back().text).contains("QOL test"), "n_notices: no blocked notice with its reason %s" % str(out.blocked))
	# A click on the notice (from first person): tactical view, the squad selected, the camera on it.
	demo.rts.select_squads([])
	demo.rts_camera.frame(_site.def + Vector3(800, 0, 800), 0.3, 60.0)
	await _physics(5)
	var shown := demo.hud.show_event(blocked.back() if not blocked.is_empty() else {"squad": sq.id})
	await _physics(5)
	var c := demo.sim.squads._centroid(sq)
	var focus: Vector3 = demo.rts_camera.focus
	out["click"] = {"shown": shown, "selected": demo.rts.selected_squads(), "camera_focus_m": snappedf(Vector2(focus.x - c.x, focus.z - c.z).length(), 0.1) if focus.is_finite() else -1}
	_expect(shown and demo.rts.selected_squads() == [sq.id], "n_notices: a click did not select the squad %s" % str(out.click))
	_expect(not focus.is_finite() or float(out.click.camera_focus_m) < 20.0, "n_notices: the camera did not go to the squad %s" % str(out.click))
	# A squad that no longer exists: nothing selected, no error.
	var gone := demo.hud.show_event({"squad": 999999, "pos": _site.def})
	out["gone_squad_click"] = gone
	_expect(not gone, "n_notices: a click on a vanished squad claimed success")
	return out


# --- c_views -----------------------------------------------------------------------------------------------------------------

func _c_views() -> Dictionary:
	var out := {}
	var a := _cs.spawn(0, _site.att, _site.dir, 4, "QA")
	var b := _cs.spawn(0, _site.att + _site.side * 30.0, _site.dir, 4, "QC")
	a.behaviour = SquadBehaviour.COMBAT
	demo.rts.select_squads([a.id])
	var ok := demo.game.possess(a.members[0])
	await _physics(20)
	out["fps"] = {"possessed": ok, "mode": demo.game.mode, "selected_kept": demo.rts.selected_squads()}
	demo.rts.select([])
	demo.game.enter_rts()
	await _physics(10)
	out["back_to_rts"] = {"selected": demo.rts.selected_squads(), "mode": a.behaviour_name()}
	_expect(demo.rts.selected_squads() == [a.id], "c_views: the possessed soldier's squad is not selected after first person %s" % str(out.back_to_rts))
	_expect(a.behaviour == SquadBehaviour.COMBAT, "c_views: the behaviour changed through possession")
	demo.toggle_map()
	await _physics(10)
	out["map_open"] = {"map_selected": Array(demo.strategic_map.selected_squads)}
	_expect(Array(demo.strategic_map.selected_squads) == [a.id], "c_views: the map did not open with the tactical selection %s" % str(out.map_open))
	demo.strategic_map.select_squads_from([b.id])
	demo.strategic_map.close()
	await _physics(10)
	out["map_closed"] = {"rts_selected": demo.rts.selected_squads()}
	_expect(demo.rts.selected_squads() == [b.id], "c_views: the map's selection did not come back to the tactical view %s" % str(out.map_closed))
	return out


# --- q_perf -----------------------------------------------------------------------------------------------------------------

## Four player squads of eight march 400 m past an enemy squad for 40 simulated seconds, once all AWARE (the behaviour every
## squad had before QOL-01) and once one squad per mode: the cost of the tactics step, the brain and the notices per tick.
func _q_perf() -> Dictionary:
	var out := {}
	for run: String in ["all_aware", "four_modes"]:
		var dir: Vector3 = _site.dir
		var side: Vector3 = _site.side
		var enemy := _cs.spawn(1, _site.def, -dir, 8, "QPE")
		var sqs := []
		for i in 4:
			var st := demo.on_ground(_site.def.x - dir.x * (160.0 + i * 25.0) - side.x * 200.0, _site.def.z - dir.z * (160.0 + i * 25.0) - side.z * 200.0, 0.0)
			var sq := _cs.spawn(0, st, side, 8, "QP%d" % i)
			sq.behaviour = SquadBehaviour.AWARE if run == "all_aware" else i
			sqs.append(sq)
		_keep_alive(sqs + [enemy])
		for i in 4:
			var sq: SquadState = sqs[i]
			var c := demo.sim.squads._centroid(sq)
			demo.sim.squads.order_move([sq.id], demo.on_ground(c.x + side.x * 400.0, c.z + side.z * 400.0, 0.0))
		var tac := demo.sim.tactics
		var brain := demo.sim.brain
		var rep := demo.sim.reports
		var s0 := [tac.step_usec, tac.ticks, brain.update_usec, brain.frames, rep.usec, rep.passes]
		tac.step_usec_max = 0
		brain.update_usec_max = 0
		rep.usec_max = 0
		await _until(func() -> bool: return false, 40.0, 2.0)
		out[run] = {"tactics_us_avg": snappedf(float(tac.step_usec - s0[0]) / maxi(tac.ticks - s0[1], 1), 1.0), "tactics_us_max": tac.step_usec_max,
			"brain_us_avg": snappedf(float(brain.update_usec - s0[2]) / maxi(brain.frames - s0[3], 1), 1.0), "brain_us_max": brain.update_usec_max,
			"reports_us_avg": snappedf(float(rep.usec - s0[4]) / maxi(rep.passes - s0[5], 1), 1.0), "reports_us_max": rep.usec_max,
			"interruptions": tac.interruptions, "squads": demo.sim.state.squads.size()}
		for sq: SquadState in sqs + [enemy]:
			for id in sq.members:
				demo.sim.state.remove_unit(id)
		demo.sim.state.war.contacts.clear()
		demo.sim.war.intel.rebuild()
		await _physics(10)
	return out


# --- z_shots -----------------------------------------------------------------------------------------------------------------

func _z_shots() -> Dictionary:
	var out := {}
	var dir: Vector3 = _site.dir
	var sq := _cs.spawn(0, _site.att, dir, 8, "Alpha")
	var sq2 := _cs.spawn(0, _site.att + _site.side * 40.0, dir, 8, "Bravo")
	sq.behaviour = SquadBehaviour.STEALTH
	sq2.behaviour = SquadBehaviour.COMBAT
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(demo.on_ground(_site.att.x + _site.side.x * 300.0, _site.att.z + _site.side.z * 300.0, 0.0))
	demo.rts_camera.frame(_site.att, 0.6, 70.0)
	await _seconds(4.0)
	_png("01_rts_panel_stealth_move")
	# The tooltip of a command tile under the mouse (the real hover path).
	var tp := demo.hud.tactical_panel
	var tile: Control = tp._buttons[TacticalPanel.BEHAVIOUR - SquadBehaviour.STEALTH]
	var at := tile.get_global_rect().get_center() * demo.get_viewport().get_final_transform().get_scale()
	Input.warp_mouse(at)
	var mm := InputEventMouseMotion.new()
	mm.position = tile.get_global_rect().get_center()
	mm.global_position = mm.position
	demo.get_viewport().push_input(mm)
	await _seconds(1.6)
	_png("01b_tile_tooltip")
	demo.sim.war.log_event(0, "squad_interrupted", "Alpha: contact on the move - DEFEND; resumes when it is over", demo.sim.war.squad_center(sq), {"squad": sq.id})
	await _seconds(1.0)
	_png("02_notice_and_roster")
	demo.rts.select_squads([sq.id, sq2.id])
	await _seconds(1.0)
	_png("03_two_squads_mixed")
	demo.toggle_map()
	await _seconds(1.5)
	_png("04_map_selection")
	demo.strategic_map.close()
	demo.game.possess(sq.members[0])
	await _seconds(2.0)
	_png("05_fps_squad_card")
	demo.game.enter_rts()
	out["shots"] = shots
	return out

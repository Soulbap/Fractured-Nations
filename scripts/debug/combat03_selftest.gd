## GAMEPLAY-03 checks: defensive warfare, concealment and tactical depth in the real game on ref_20km.
##
##   Godot.exe --path . --resolution 1600x900 --log-file c3.log res://scenes/game/world_ref_20km.tscn -- --combat03-test [--shots] [--only d_open,...] [--seeds=1,2,3]
##
## Layered defence (f_*): a new threat direction moves only the soldiers whose posts no longer cover them (f_threat); a save
## in the middle of a fall back is identical after loading and the fall back completes (f_persist); a player order takes a
## falling-back garrison out of it (f_override).
## Defence scenarios (d_*): one standard South squad garrisons a small base (a command post) and three standard North squads
## attack it from 500 m with an ATTACK operation, camera far away, once per world seed. The places differ only in ground:
##   d_open     fortified outpost on open ground (two fighting positions, an MG emplacement, a steel guard tower)
##   d_village  the command post in Haugen (buildings, gardens), no fortifications
##   d_forest   at a forest edge facing open ground, no fortifications
##   d_reverse  just behind a crest (the ground in front rises), no fortifications
## The sites are found by a deterministic search round Haugen (trees, crest height); each run is recorded by CombatDiag with
## the defence metrics (first sighting each way, first hits, defenders seen / inside the capture radius, post changes, slots
## given up). Prints "C3 <check> <json>", writes res://benchmarks/raw/combat03_test.json.
class_name Combat03SelfTest
extends Combat02SelfTest

var _sites := {}


func run(args: PackedStringArray) -> void:
	out_file = "combat03_test.json"
	prefix = "C3"
	diag_on = true
	for a in args:
		if a.begins_with("--seeds="):
			seeds = Array(a.trim_prefix("--seeds=").split(",")).map(func(x: String) -> int: return int(x))
	await _strat_setup(args, "res://docs/gameplay03")
	_log("setup", {"soldiers": default_soldiers.size(), "seeds": seeds})
	if _want("p_posts"):
		_log("p_posts", await _p_posts())
	for key: String in ["f_threat", "f_persist", "f_override"]:
		if _want(key):
			var rf: Variant = await call("_" + key)
			_expect(rf is Dictionary and not (rf as Dictionary).is_empty(), "%s: the check did not finish (script error?)" % key)
			_log(key, rf if rf is Dictionary else {})
	for key: String in ["d_open", "d_village", "d_forest", "d_reverse"]:
		if _want(key):
			var r: Variant = await _defence_series(key)
			_expect(r is Dictionary and not (r as Dictionary).is_empty(), "%s: the check did not finish (script error?)" % key)
			_log(key, r if r is Dictionary else {})
	await _end_strat()


# --- Sites ---------------------------------------------------------------------------------------------------------------

## A defended site of `kind`: {p, dir (towards the attackers), info}; searched once per run on a ring round Haugen, the
## attackers always coming from the North HQ side.
func _site(kind: String) -> Dictionary:
	if _sites.has(kind):
		return _sites[kind]
	var hau := _obj("Haugen").position
	var hq := _obj("North HQ").position
	if kind == "village":
		var d := Vector3(hq.x - hau.x, 0, hq.z - hau.z).normalized()
		_sites[kind] = {"p": hau, "dir": d, "info": {"trees_back": _trees_round(hau, 35.0), "front": _trees_along(hau, d, 400.0), "crest": snappedf(_crest(hau, d), 0.1)}}
		return _sites[kind]
	var best := {}
	var best_v := -INF
	for dist: float in [700.0, 1000.0, 1300.0, 1600.0, 1900.0, 2200.0]:
		for k in 24:
			var p := hau + Vector3(cos(k * TAU / 24.0), 0, sin(k * TAU / 24.0)) * dist
			p = demo.on_ground(p.x, p.z, 0.0)
			if not ws.routes.passable(p) or not demo.sim.tactics.pos.valid_ground(p):
				continue
			var d := Vector3(hq.x - p.x, 0, hq.z - p.z).normalized()
			var start := p + d * 500.0
			# The attack must be able to walk straight in (no river or cliff between: a detour of kilometres is no test).
			if not ws.routes.passable(start) or not demo.sim.tactics.pos.segment_clear(start, p):
				continue
			var back := _trees_round(p - d * 15.0, 30.0)
			var front := _trees_along(p, d, 400.0)
			var crest := _crest(p, d)
			var slope := absf(demo.sim.tactics.pos.ground(p + Vector3(6, 0, 0)).y - demo.sim.tactics.pos.ground(p - Vector3(6, 0, 0)).y) \
					+ absf(demo.sim.tactics.pos.ground(p + Vector3(0, 0, 6)).y - demo.sim.tactics.pos.ground(p - Vector3(0, 0, 6)).y)
			if slope > 2.5:
				continue
			var v := -INF
			match kind:
				"open":
					v = -float(back) - float(front) * 0.5 - absf(crest) * 4.0
				"forest":
					v = float(mini(back, 40)) - float(front) * 0.8 - absf(crest) * 2.0 if back >= 12 else -INF
				"reverse":
					# A crest of a few metres just in front, not a hill: the site is hidden from the approach until close.
					v = -absf(crest - 6.0) * 2.0 - float(front) * 0.3 - float(back) * 0.3 if crest >= 3.0 and crest <= 12.0 else -INF
			if v > best_v:
				best_v = v
				best = {"p": p, "dir": d, "info": {"trees_back": back, "front": front, "crest": snappedf(crest, 0.1), "dist_from_haugen": dist}}
	_sites[kind] = best
	return best


func _trees_round(c: Vector3, r: float) -> int:
	var buf := PackedFloat32Array()
	demo.structures.trunks_in_rect(Rect2(c.x - r, c.z - r, 2.0 * r, 2.0 * r), buf)
	var n := 0
	for i in range(0, buf.size(), 3):
		if Vector2(buf[i] - c.x, buf[i + 1] - c.z).length() <= r:
			n += 1
	return n


## How much higher than p the ground rises 30-150 m towards d (m): a crest that hides the site from the approach.
func _crest(p: Vector3, d: Vector3) -> float:
	var h0 := demo.sim.tactics.pos.ground(p).y
	var top := -INF
	var x := 30.0
	while x <= 150.0:
		top = maxf(top, demo.sim.tactics.pos.ground(p + d * x).y - h0)
		x += 15.0
	return top


# --- The defence series ----------------------------------------------------------------------------------------------------

func _defence_series(key: String) -> Dictionary:
	var kind := key.trim_prefix("d_")
	var site := _site(kind)
	_expect(not site.is_empty(), "%s: no site of this kind was found" % key)
	if site.is_empty():
		return {"site": {}}
	var seed0 := demo.sim.state.world_seed
	var runs: Array = []
	for s: int in seeds:
		demo.sim.state.world_seed = s
		var sc := await _defence_scene(kind, site)
		if sc.is_empty():
			_expect(false, "%s: scene could not be set up (seed %d)" % [key, s])
			continue
		var r := await _run_attack(sc, 900.0, 12.0)
		r.erase("op_obj")
		var g: Dictionary = r.get("diag", {})
		var one := {"seed": s, "owner": r.get("owner", -1), "won": int(r.get("owner", -1)) == 0, "attackers_left": r.get("attackers_left", 0), "attackers": 24,
			"defenders_left": r.get("defenders_left", 0), "defenders": 8, "max_stall_s": r.get("max_assault_stall_s", 0.0), "stages": r.get("stages", []),
			"withdraw_why": r.get("withdraw_why", ""), "in_slots_at_start": sc.get("in_slots", 0), "diag": g,
			"posts_judged": demo.sim.tactics._meta(sc.def[0], "posts_judged", {})}
		var dd: Dictionary = g.get("defence", {})
		print("C3 run %s seed %d: won=%s att %d/24 def %d/8 seen(att) %s seen(def) %s exposed %s inside %s posts %s slots_left %s line %s contested %s kept %s %s" % [key, s, one.won,
			one.attackers_left, one.defenders_left, str(dd.get("first_seen", {}).get("att", "-")), str(dd.get("first_seen", {}).get("def", "-")),
			dd.get("def_exposed_s", "-"), dd.get("def_inside_s", "-"), dd.get("def_post_changes", "-"), dd.get("def_slots_left", "-"), dd.get("def_line_max", "-"),
			dd.get("contested_s", "-"), dd.get("garrison_kept", "-"), one.withdraw_why])
		runs.append(one)
		_remove_structures(sc.get("ids", []))
		_expect(int(g.get("totals", {}).get("att_shots", 0)) > 0, "%s seed %d: no fight happened" % [key, s])
	demo.sim.state.world_seed = seed0
	return {"site": {"p": [roundi(site.p.x), roundi(site.p.z)], "info": site.info}, "summary": _defence_summary(runs), "detail": runs}


## Averages of the defence metrics over the runs.
func _defence_summary(runs: Array) -> Dictionary:
	var n := maxf(runs.size(), 1)
	var acc := {"won": 0, "att_loss": 0.0, "def_loss": 0.0, "att_seen_t": 0.0, "att_seen_d": 0.0, "def_seen_d": 0.0, "first_def_hit_t": 0.0,
		"def_exposed_s": 0.0, "def_inside_s": 0.0, "def_post_changes": 0.0, "def_slots_left": 0.0, "att_supp_avg": 0.0, "def_supp_avg": 0.0,
		"def_line_max": 0.0, "contested_s": 0.0, "duration_s": 0.0}
	for r: Dictionary in runs:
		var g: Dictionary = r.diag
		var dd: Dictionary = g.get("defence", {})
		acc.won += 1 if r.won else 0
		acc.att_loss += 1.0 - float(r.attackers_left) / 24.0
		acc.def_loss += 1.0 - float(r.defenders_left) / 8.0
		acc.att_seen_t += float(dd.get("first_seen", {}).get("att", {}).get("t", 0.0))
		acc.att_seen_d += float(dd.get("first_seen", {}).get("att", {}).get("d", 0.0))
		acc.def_seen_d += float(dd.get("first_seen", {}).get("def", {}).get("d", 0.0))
		acc.first_def_hit_t += float(dd.get("first_hit", {}).get("def", 0.0))
		acc.def_exposed_s += float(dd.get("def_exposed_s", 0))
		acc.def_inside_s += float(dd.get("def_inside_s", 0))
		acc.def_post_changes += float(dd.get("def_post_changes", 0))
		acc.def_slots_left += float(dd.get("def_slots_left", 0))
		acc.def_line_max += float(dd.get("def_line_max", 0))
		acc.contested_s += float(dd.get("contested_s", 0))
		acc.duration_s += float(g.get("duration_s", 0))
		acc.att_supp_avg += float(g.get("att_supp_avg", 0.0))
		acc.def_supp_avg += float(g.get("def_supp_avg", 0.0))
	var out := {"runs": runs.size(), "taken": acc.won}
	for k in acc:
		if k != "won":
			out[k] = snappedf(float(acc[k]) / n, 0.01)
	return out


## One scene: a South command post at the site (and the fortifications for "open"), a standard South squad garrisoning it,
## three standard North squads 500 m out towards North HQ.
func _defence_scene(kind: String, site: Dictionary) -> Dictionary:
	await _fresh_c()
	_pause_ai(true)
	war.rules["squad_composition"] = "standard"
	var p: Vector3 = site.p
	var dir: Vector3 = site.dir
	if kind == "village":
		var hau := _obj("Haugen")
		hau.owner = 1
		hau.capture_faction = -1
		hau.capture_progress = 0.0
		hau.contested = false
		hau.history.append([demo.sim.state.time, 1])
	var cp := CoreSelfTest.add_built(demo, &"command_post", p - dir * 10.0, dir, 1)
	if cp == null:
		return {}
	var ids: Array = [cp.id]
	if kind == "open":
		for e: Array in [[&"fighting_position", dir, 22.0], [&"mg_emplacement", dir.rotated(Vector3.UP, 0.5), 20.0], [&"fighting_position", dir.rotated(Vector3.UP, -0.6), 22.0],
				[&"guard_tower_steel", dir.rotated(Vector3.UP, 1.4), 16.0]]:
			var st := CoreSelfTest.add_built(demo, e[0], cp.position + (e[1] as Vector3) * float(e[2]), dir, 1)
			if st:
				ids.append(st.id)
	ws.sync_bases()
	var obj := ws.base_objective(cp.base_id)
	if obj == null:
		_remove_structures(ids)
		return {}
	obj.owner = 1
	var d := _spawn(1, demo.sim.tactics.pos.nearest_valid(cp.position - dir * 12.0, 20.0), 8)
	demo.sim.tactics.assign_garrison(d, cp.base_id, SquadState.Owner.SQUAD)
	await _warp(45.0, 8.0, 30.0)
	var in_slots := 0
	for id in d.members:
		if _u(id).fort_slot != "":
			in_slots += 1
	var start := _passable_near(p + dir * 500.0)
	var atk: Array = []
	for i in 3:
		atk.append(_spawn(0, start + Vector3(((i % 3) - 1) * 25.0, 0, 25.0 * (1 if i > 0 else 0))))
	await _physics(10)
	return {"obj": obj, "atk": atk, "def": [d], "ids": ids, "in_slots": in_slots}


# --- Position choice --------------------------------------------------------------------------------------------------------

## A standard squad told to defend at the forest edge and at the fortified open outpost, with an enemy reported 250 m out:
## at the forest edge the posts are concealed; on open ground the fortifications are used (their cover is the only one); no
## two soldiers share a post or a slot, the machine gunner sits in the MG emplacement, and the search cost is measured.
func _p_posts() -> Dictionary:
	var out := {}
	for kind: String in ["forest", "open"]:
		var site := _site(kind)
		if site.is_empty():
			_expect(false, "p_posts: no %s site" % kind)
			continue
		await _fresh_c()
		war.rules["squad_composition"] = "standard"
		var p: Vector3 = site.p
		var dir: Vector3 = site.dir
		var ids: Array = []
		if kind == "open":
			for e: Array in [[&"fighting_position", dir, 12.0], [&"mg_emplacement", dir.rotated(Vector3.UP, 0.5), 10.0], [&"fighting_position", dir.rotated(Vector3.UP, -0.6), 12.0],
					[&"guard_tower_steel", dir.rotated(Vector3.UP, 1.4), 8.0]]:
				var st := CoreSelfTest.add_built(demo, e[0], p + (e[1] as Vector3) * float(e[2]), dir, 1)
				if st:
					ids.append(st.id)
		var sq := _spawn(1, demo.sim.tactics.pos.nearest_valid(p - dir * 10.0, 15.0), 8)
		await _physics(5)
		_report(1, p + dir * 250.0, 6)
		var e0 := demo.sim.tactics.pos.exposure_evals
		var u0 := demo.sim.tactics.pos.exposure_usec
		var t0 := Time.get_ticks_usec()
		demo.sim.tactics.order_tactic([sq.id], SquadState.Tactic.DEFEND, p, SquadState.Owner.PLAYER)
		var plan_us := Time.get_ticks_usec() - t0
		await _warp(25.0, 4.0, 20.0)
		var judged: Dictionary = demo.sim.tactics._meta(sq, "posts_judged", {})
		var posts := []
		var slots := {}
		var dup := 0
		for id in sq.members:
			var u := _u(id)
			if u.fort_slot != "":
				dup += 1 if slots.has(u.fort_slot) else 0
				slots[u.fort_slot] = true
			for q: Vector3 in posts:
				if u.post_pos.is_finite() and Vector2(q.x - u.post_pos.x, q.z - u.post_pos.z).length() < 1.0 and u.fort_slot == "":
					dup += 1
			if u.post_pos.is_finite():
				posts.append(u.post_pos)
		var mg := _u(sq.members[1])
		out[kind] = {"judged": judged, "posts": posts.size(), "in_slots": slots.size(), "duplicates": dup, "plan_us": plan_us,
			"exposure_checks": demo.sim.tactics.pos.exposure_evals - e0, "exposure_us": demo.sim.tactics.pos.exposure_usec - u0,
			"mg": {"slot": mg.fort_slot, "role": demo.sim.tactics.pos.slot_by_key(mg.fort_slot, 1).get("role", "") if mg.fort_slot != "" else ""}}
		_expect(not judged.is_empty(), "p_posts(%s): the posts were not judged against the reported enemy" % kind)
		_expect(posts.size() == 8 and dup == 0, "p_posts(%s): posts missing or shared %s" % [kind, str(out[kind])])
		# Where the ground offers concealment the posts use it; where it offers none, the prepared positions' cover wins.
		if kind == "forest":
			_expect(float(judged.get("exposure", 1.0)) <= 0.34, "p_posts(forest): the posts at the forest edge are not concealed %s" % str(judged))
		if kind == "open":
			_expect(int(judged.get("slots", 0)) >= 6, "p_posts(open): the fortifications were not used on open ground %s" % str(judged))
			_expect(String(out[kind].mg.role) == "mg", "p_posts(open): the machine gunner is not in the MG emplacement %s" % str(out[kind].mg))
		if shots:
			demo.rts_camera.frame(p, 0.6, 45.0)
			await _seconds(1.5)
			_png("p_posts_%s" % kind)
		_remove_structures(ids)
	war.rules.erase("squad_composition")
	return out


# --- Layered defence ------------------------------------------------------------------------------------------------------

## A squad defends at the forest edge against an enemy reported in front; then the enemy is reported from 120 degrees to
## the side (the faction's belief changes: the old report is forgotten). The squad repositions, moving the soldiers whose
## posts do not cover them against the new bearing and keeping the others.
func _f_threat() -> Dictionary:
	var site := _site("open")
	await _fresh_c()
	war.rules["squad_composition"] = "standard"
	var p: Vector3 = site.p
	var dir: Vector3 = site.dir
	var sq := _spawn(1, demo.sim.tactics.pos.nearest_valid(p - dir * 8.0, 15.0), 8)
	await _physics(5)
	_report(1, p + dir * 200.0, 6)
	demo.sim.tactics.order_tactic([sq.id], SquadState.Tactic.DEFEND, p, SquadState.Owner.PLAYER)
	await _warp(25.0, 4.0, 20.0)
	var before := {}
	for id in sq.members:
		before[id] = _u(id).post_pos
	war.contacts.clear()
	ws.intel.rebuild()
	var side := dir.rotated(Vector3.UP, deg_to_rad(120.0))
	var r0 := int(demo.sim.tactics.started.get(SquadState.Tactic.REPOSITION, 0))
	for k in 6:
		_report(1, p + side * 150.0, 6)
		await _warp(5.0, 4.0, 10.0)
	await _warp(20.0, 4.0, 20.0)
	var moved := 0
	var kept := 0
	for id in sq.members:
		var a: Vector3 = before[id]
		var b := _u(id).post_pos
		if a.is_finite() and b.is_finite() and Vector2(a.x - b.x, a.z - b.z).length() > 2.0:
			moved += 1
		else:
			kept += 1
	var out := {"repositions": int(demo.sim.tactics.started.get(SquadState.Tactic.REPOSITION, 0)) - r0, "moved": moved, "kept": kept,
		"why": sq.tactic_why, "note": sq.tactic_rejected, "tactic": sq.tactic_name()}
	_expect(int(out.repositions) >= 1 and moved >= 1, "f_threat: the squad did not react to the new bearing %s" % str(out))
	if shots:
		demo.rts_camera.frame(p, 0.6, 45.0)
		await _seconds(1.5)
		_png("f_threat_reoriented")
	war.rules.erase("squad_composition")
	return out


## The fortified outpost under attack until its garrison falls back: a save to the test save folder in the middle of the
## move, a load, the same squad record (line, garrison, posts, the stage of the move), and the move completes to a held line.
func _f_persist() -> Dictionary:
	var site := _site("open")
	var sc := await _defence_scene("open", site)
	if sc.is_empty():
		_expect(false, "f_persist: scene not set up")
		return {}
	var d: SquadState = sc.def[0]
	var ids := (sc.atk as Array).map(func(q: SquadState) -> int: return q.id)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, sc.obj.id, Vector3.INF, true)
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _warp(500.0, 8.0, 160.0, func() -> bool: return d.tactic == SquadState.Tactic.REPOSITION and d.tactic_leg >= 100 or not op.is_active())
	var out := {"falling_back": d.tactic == SquadState.Tactic.REPOSITION and d.tactic_leg >= 100, "line": d.defence_line}
	_expect(out.falling_back, "f_persist: the garrison never fell back (precondition)")
	if not out.falling_back:
		_remove_structures(sc.ids)
		return out
	var sig := func() -> String:
		var a: Array = [d.defence_line, d.garrison_base, d.tactic, d.tactic_leg]
		for id in d.members:
			var u := _u(id)
			a.append("%d:%s:%s" % [id, str(u.post_pos.snapped(Vector3.ONE * 0.1)), u.fort_slot])
		return str(a)
	var before: String = sig.call()
	var path := demo.save_dir() + "/combat03_fallback.sav"
	var err := demo.sim.state.save_file(path)
	demo.sim.state.load_file(path)
	await tree.physics_frame
	war = demo.sim.state.war
	ws = demo.sim.war
	d = demo.sim.state.get_squad(d.id)
	var after: String = sig.call()
	out["same"] = before == after
	out["saved"] = err == OK and path.contains("test_saves")
	_expect(out.saved and out.same, "f_persist: the fall back differs after loading %s / %s" % [before, after])
	await _warp(40.0, 4.0, 40.0, func() -> bool: return d.tactic == SquadState.Tactic.DEFEND)
	out["after"] = {"tactic": d.tactic_name(), "line": d.defence_line, "garrison": d.garrison_base}
	_expect(d.tactic == SquadState.Tactic.DEFEND and d.defence_line >= 1 and d.garrison_base >= 0, "f_persist: the fall back did not complete after loading %s" % str(out.after))
	_remove_structures(sc.ids)
	return out


## A player order to a garrison that is falling back: the squad obeys (its tactic ends, it walks where it was sent) and
## its garrison assignment ends (GAMEPLAY-01C: any other order reassigns the squad).
func _f_override() -> Dictionary:
	var site := _site("open")
	var sc := await _defence_scene("open", site)
	if sc.is_empty():
		_expect(false, "f_override: scene not set up")
		return {}
	var d: SquadState = sc.def[0]
	var ids := (sc.atk as Array).map(func(q: SquadState) -> int: return q.id)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, sc.obj.id, Vector3.INF, true)
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _warp(500.0, 8.0, 160.0, func() -> bool: return d.tactic == SquadState.Tactic.REPOSITION and d.tactic_leg >= 100 or not op.is_active())
	var was := d.tactic == SquadState.Tactic.REPOSITION
	_expect(was, "f_override: the garrison never fell back (precondition)")
	var goal: Vector3 = demo.sim.tactics.pos.nearest_valid(demo.sim.squads._centroid(d) - (site.dir as Vector3) * 60.0, 20.0)
	demo.sim.squads.order_move([d.id], goal)
	await _physics(5)
	var out := {"was_falling_back": was, "tactic": d.tactic_name(), "garrison": d.garrison_base, "order": d.order_name()}
	_expect(d.tactic == SquadState.Tactic.NONE and d.garrison_base < 0 and d.order == SquadState.Order.MOVE, "f_override: the player's order did not take over %s" % str(out))
	_remove_structures(sc.ids)
	return out

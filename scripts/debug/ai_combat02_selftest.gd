## AI-COMBAT-02 checks in the real game on ref_20km (a few, short):
##
##   Godot.exe --path . --log-file ac2.log res://scenes/game/world_ref_20km.tscn -- --scenario=dev --ai-combat02-test [--shots] [--only ...]
##
## d_detect   one enemy observer, one target on the open test site's sight line: how long until he is noticed - crouched still at
##            150 m, standing still at 150 m, prone still at 200 m, walking across at 70 m - with the COMBAT-01 rule
##            (CombatBrain.legacy_perception, HARD) and the new one (NORMAL)
## l_track    a target seen beside a cover object ducks behind it: the observer loses sight, keeps the last seen place (never the
##            true one), drops the target; the target shows again 15 m away: picked up again only after a new noticing time
## k_levels   Easy / Normal / Hard: noticing time (crouched, 150 m) and 4 enemy riflemen against one standing soldier of the player at
##            150 m for 30 s (hits, first hit); the same for 4 riflemen of the player's side (friendly AI is barely changed)
## p_placed   a player squad placed by right-drag (order_place) meets an enemy squad: the soldiers stay at their places
## b_firefight two 8-man squads on open ground with cover, uncommanded (arrived moves), 100 s: shots, cover, and the purposeful moves
##            (firing positions, stalemate shifts, initiative flanks, repositions); `--no-stalemate` gives the before numbers
## Prints "AC2 <check> <json>", writes res://benchmarks/raw/ai_combat02_test.json.
class_name AiCombat02SelfTest
extends WorldCoverSelfTest

const CHECKSAC: Array[String] = ["d_detect", "l_track", "k_levels", "p_placed", "b_firefight"]


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/ai_combat02"
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKSAC)
	SoldierBody.require_mouse_capture = false
	tree.create_timer(1500.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CoverLayer.path(demo.config.world_name)))
	_layer = j.records if j is Dictionary else {}
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
	if demo.hud:
		demo.hud.visible = false
	_quiet_area(_site.def, 2500.0)
	results["difficulty"] = Difficulty.id_of(Difficulty.level)
	for n in CHECKSAC:
		if only.has(n):
			# The development war goes on round the test area: soldiers who walked in since are removed before each check.
			_quiet_area(_site.def, 2500.0)
			_log(n, await call("_" + n))
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("AC2 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	CoreDemo.apply_time_scale(1.0)
	Difficulty.level = Difficulty.NORMAL
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/ai_combat02_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("AC2 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


# --- helpers ---------------------------------------------------------------------------------------------------------------

func _one(faction: int, at: Vector3, facing: Vector3, tag: String) -> UnitState:
	var sq := _cs.spawn(faction, at, facing, 1, tag)
	sq.roe = SquadState.Roe.HOLD_FIRE
	demo.sim.squads.order_hold([sq.id])
	_tough([sq])
	return demo.sim.state.get_unit(sq.members[0])


## A fresh observer's mind: nothing seen, told or heard.
func _fresh(o: UnitState) -> void:
	var b := demo.sim.brain
	b._spot.erase(o.id)
	o.target_id = -1
	o.target_visible = false
	o.watch_until = -INF
	o.watch_yaw = NAN
	o.under_fire_until = -INF
	o.threat_pos = Vector3.INF
	b._recent_shots.clear()


## Seconds until `o` has `t` as its target (INF: not within limit).
func _until_seen(o: UnitState, t: UnitState, limit: float) -> float:
	var t0 := demo.sim.state.time
	# The target keeps the posture the case gave him (his own AI would stand a held soldier up).
	var keep := t.posture
	while demo.sim.state.time - t0 < limit:
		Posture.set_now(t, keep)
		t.posture_hold_until = demo.sim.state.time + 5.0
		await _physics(2)
		if o.target_id == t.id:
			return snappedf(demo.sim.state.time - t0, 0.05)
	return INF


func _site_point(d: float) -> Vector3:
	var dir: Vector3 = _site.dir
	return demo.on_ground(_site.def.x - dir.x * d, _site.def.z - dir.z * d, 0.0)


## One noticing case: observer at the defence point facing the approach, the target d m out on the sight line in `posture`,
## still or walking across. {s, visible}
func _case(o: UnitState, t: UnitState, d: float, posture: int, walk: bool) -> Dictionary:
	var p := _site_point(d)
	var side: Vector3 = _site.side
	t.position = p - side * (12.0 if walk else 0.0)
	var tb := _body(t)
	if tb:
		tb.teleport(t.position, t.yaw)
	demo.sim.state.halt(t.id)
	await _physics(4)
	Posture.set_now(t, posture)
	var eye := CombatSim.eye_of(o)
	var vis: bool = demo.sim.combat.line.sight(eye, Posture.aim_point(t, false)).visible or demo.sim.combat.line.sight(eye, Posture.aim_point(t, true)).visible
	# The noticing time itself, looking straight at him (the measured time adds the observer's idle scan sweeping past).
	o.target_id = t.id
	o.target_last_pos = t.position
	var now := demo.sim.state.time
	var v0 := t.velocity
	if walk:
		t.velocity = side * 4.5
	var need := demo.sim.brain.acquire_delay(o, t, now)
	t.velocity = v0
	_fresh(o)
	if walk:
		demo.sim.state.issue_move(t.id, p + side * 40.0, false)
	var o_at := o.position
	var s := await _until_seen(o, t, 25.0)
	demo.sim.state.halt(t.id)
	var row := {"s": s if s < INF else "not within 25 s", "delay_s": snappedf(need, 0.01), "visible": vis}
	if s == INF:
		var other := demo.sim.state.get_unit(o.target_id)
		row["observer"] = {"target": other.unit_name if other else "none", "reason": o.ai_reason, "cover": o.cover_note,
			"moved_m": snappedf(o.position.distance_to(o_at), 0.1), "alive": [o.alive, t.alive], "d": snappedf(o.position.distance_to(t.position), 0.1),
			"sight_now": demo.sim.combat.line.sight(CombatSim.eye_of(o), Posture.aim_point(t, true)).visible}
	return row


func _detect_set(o: UnitState, t: UnitState) -> Dictionary:
	var out := {}
	out["crouch_still_150"] = await _case(o, t, 150.0, Posture.CROUCH, false)
	out["stand_still_150"] = await _case(o, t, 150.0, Posture.STAND, false)
	out["prone_still_200"] = await _case(o, t, 200.0, Posture.PRONE, false)
	out["walk_across_70"] = await _case(o, t, 70.0, Posture.STAND, true)
	return out


# --- checks ----------------------------------------------------------------------------------------------------------------

func _d_detect() -> Dictionary:
	var out := {}
	var o := _one(1, _site.def, -(_site.dir as Vector3), "OB")
	var t := _one(0, _site_point(150.0), _site.dir, "TG")
	demo.rts_camera.frame(_site_point(80.0), 0.6, 120.0)
	await _seconds(2.0)
	var b := demo.sim.brain
	Difficulty.level = Difficulty.HARD
	b.legacy_perception(true)
	out["before"] = await _detect_set(o, t)
	b.legacy_perception(false)
	Difficulty.level = Difficulty.NORMAL
	out["after"] = await _detect_set(o, t)
	var bf: Dictionary = out.before
	var af: Dictionary = out.after
	for k: String in ["crouch_still_150", "stand_still_150", "prone_still_200"]:
		if bool(af[k].visible):
			_expect(float(af[k].delay_s) > float(bf[k].delay_s), "d_detect %s: noticing not slower than before (%s vs %s s)" % [k, af[k].delay_s, bf[k].delay_s])
	if bool(af.walk_across_70.visible) and bool(af.crouch_still_150.visible):
		_expect(float(af.walk_across_70.delay_s) < float(af.crouch_still_150.delay_s),
			"d_detect: a walking man at 70 m is not noticed sooner than a crouched one at 150 m")
	_expect(bool(af.stand_still_150.visible), "d_detect: the test site's sight line is blocked (precondition)")
	out["suspicions"] = b.suspicions
	await _drop([o, t])
	return out


func _l_track() -> Dictionary:
	var out := {}
	# A cover object of the layer near the site with open ground round it: the observer 90 m off, a hidden spot behind it.
	var best := {}
	for rec: Dictionary in _layer.values():
		var tr: Array = rec.transform
		var p := Vector3(tr[9], tr[10], tr[11])
		var d := Vector2(p.x - _site.def.x, p.z - _site.def.z).length()
		if d < 1500.0 and (best.is_empty() or d < float(best.d)):
			var ob := p + (_site.dir as Vector3) * 90.0
			ob = demo.on_ground(ob.x, ob.z, 0.0)
			var spots := demo.sim.brain.cover_spots(p, 4.0, ob, p, 6)
			for e: Dictionary in spots:
				var eye := ob + Vector3.UP * Posture.EYE[Posture.STAND].y
				var hid: bool = not demo.sim.combat.line.sight(eye, (e.p as Vector3) + Vector3.UP * 0.55).visible \
					and not demo.sim.combat.line.sight(eye, (e.p as Vector3) + Vector3.UP * 0.25).visible
				var lat := (e.p as Vector3) + (_site.side as Vector3) * 8.0
				lat = demo.on_ground(lat.x, lat.z, 0.0)
				var shown: bool = demo.sim.combat.line.sight(eye, lat + Vector3.UP * 1.2).visible
				if hid and shown:
					best = {"d": d, "obj": p, "obs": ob, "hide": e.p, "show": lat}
					break
	_expect(not best.is_empty(), "l_track: no cover object near the site to hide behind (precondition)")
	if best.is_empty():
		return out
	out["object"] = _v(best.obj)
	var o := _one(1, best.obs, -(_site.dir as Vector3), "OB")
	var t := _one(0, best.show, _site.dir, "TG")
	demo.rts_camera.frame(best.obj, 0.6, 90.0)
	await _seconds(1.5)
	_fresh(o)
	out["seen_after_s"] = await _until_seen(o, t, 20.0)
	var seen_at := o.target_last_pos
	# Ducks behind the object.
	t.position = best.hide
	if _body(t):
		_body(t).teleport(t.position, t.yaw)
	Posture.set_now(t, Posture.PRONE)
	var t0 := demo.sim.state.time
	var lost_s := INF
	var dropped_s := INF
	var leaked := false
	while demo.sim.state.time - t0 < 12.0:
		await _physics(2)
		if lost_s == INF and not o.target_visible:
			lost_s = demo.sim.state.time - t0
		if o.target_id == t.id and o.target_last_pos.is_finite() and o.target_last_pos.distance_to(t.position) < 2.0 and not o.target_visible:
			leaked = true
		if dropped_s == INF and o.target_id != t.id:
			dropped_s = demo.sim.state.time - t0
	out["lost_sight_s"] = snappedf(lost_s, 0.05)
	out["dropped_target_s"] = snappedf(dropped_s, 0.05)
	out["kept_last_seen_place"] = not leaked and (not seen_at.is_finite() or seen_at.distance_to(best.hide) > 2.0)
	_expect(lost_s < 2.0, "l_track: the observer still sees the target behind cover")
	_expect(not leaked, "l_track: the hidden target's true position reached the observer")
	# Shows again 15 m from where he was last seen, 12 s later.
	var again: Vector3 = best.show + (_site.side as Vector3) * 15.0
	t.position = demo.on_ground(again.x, again.z, 0.0)
	if _body(t):
		_body(t).teleport(t.position, t.yaw)
	Posture.set_now(t, Posture.STAND)
	out["reacquired_after_s"] = await _until_seen(o, t, 20.0)
	await _drop([o, t])
	return out


var _hits := 0
var _first_hit := INF
var _dummy := -1
var _t_start := 0.0


func _on_hit(t: UnitState, _amount: float, _zone: int, _src: int) -> void:
	if t.id == _dummy:
		_hits += 1
		_first_hit = minf(_first_hit, demo.sim.state.time - _t_start)


## 4 riflemen of `shooters_faction` at the defence point against one standing soldier 150 m out on the sight line, 30 s.
func _duel(shooters_faction: int) -> Dictionary:
	var sq := _cs.spawn(shooters_faction, _site.def, -(_site.dir as Vector3), 4, "SH")
	demo.sim.squads.order_hold([sq.id])
	var dummy := _one(1 - shooters_faction, _site_point(150.0), _site.dir, "DM")
	dummy.max_health = 100000.0
	dummy.health = 100000.0
	Posture.set_now(dummy, Posture.STAND)
	_dummy = dummy.id
	_hits = 0
	_first_hit = INF
	if not demo.sim.state.unit_damaged.is_connected(_on_hit):
		demo.sim.state.unit_damaged.connect(_on_hit)
	var shots0 := demo.sim.brain.ai_shots
	_t_start = demo.sim.state.time
	CoreDemo.apply_time_scale(2.0)
	var spot := dummy.position
	while demo.sim.state.time - _t_start < 30.0:
		await _physics(5)
		# A fixed, standing target: no cover reaction moves him (the measure is the shooters' fire, not his survival).
		dummy.clear_reaction()
		dummy.tactic = UnitState.Tactic.NONE
		demo.sim.state.halt(dummy.id)
		if dummy.position.distance_to(spot) > 0.3:
			dummy.position = spot
			if _body(dummy):
				_body(dummy).teleport(spot, dummy.yaw)
		Posture.set_now(dummy, Posture.STAND)
	CoreDemo.apply_time_scale(1.0)
	var out := {"hits": _hits, "first_hit_s": snappedf(_first_hit, 0.1) if _first_hit < INF else "none", "shots": demo.sim.brain.ai_shots - shots0}
	await _clear_squads([sq])
	await _drop([dummy])
	return out


func _k_levels() -> Dictionary:
	var out := {}
	for lv in 3:
		Difficulty.level = lv
		_quiet_area(_site.def, 2500.0)
		var row := {"outsiders_removed": results.get("quiet_area_removed", 0)}
		var o := _one(1, _site.def, -(_site.dir as Vector3), "OB")
		var t := _one(0, _site_point(150.0), _site.dir, "TG")
		await _physics(10)
		row["notice_crouched_150"] = await _case(o, t, 150.0, Posture.CROUCH, false)
		await _drop([o, t])
		row["enemy_rifles_vs_player"] = await _duel(1)
		row["player_side_rifles_vs_enemy"] = await _duel(0)
		out[Difficulty.id_of(lv)] = row
	Difficulty.level = Difficulty.NORMAL
	# Judged per shot: how many rounds a squad fires depends on its bursts and reactions, the share that hits on its aim.
	var rate := func(r: Dictionary) -> float: return float(r.hits) / maxf(float(r.shots), 1.0)
	var e: float = rate.call(out.easy.enemy_rifles_vs_player)
	var n: float = rate.call(out.normal.enemy_rifles_vs_player)
	var h: float = rate.call(out.hard.enemy_rifles_vs_player)
	for k: String in ["easy", "normal", "hard"]:
		out[k]["enemy_hit_rate"] = snappedf(rate.call(out[k].enemy_rifles_vs_player), 0.01)
		out[k]["player_side_hit_rate"] = snappedf(rate.call(out[k].player_side_rifles_vs_enemy), 0.01)
	_expect(int(out.hard.enemy_rifles_vs_player.hits) > 0, "k_levels: hard enemies never hit a standing man at 150 m in 30 s (no fight)")
	_expect(e < n and n < h, "k_levels: the enemy hit rate does not fall from hard to easy (%.2f / %.2f / %.2f)" % [h, n, e])
	return out


func _p_placed() -> Dictionary:
	var out := {}
	var dir: Vector3 = _site.dir
	var side: Vector3 = _site.side
	var sq := _cs.spawn(0, _site.att, dir, 6, "PL")
	_tough([sq])
	var c: Vector3 = _site.att + dir * 15.0
	var a := demo.on_ground(c.x - side.x * 9.0, c.z - side.z * 9.0, 0.0)
	var b := demo.on_ground(c.x + side.x * 9.0, c.z + side.z * 9.0, 0.0)
	var n := demo.sim.squads.order_place([sq.id], a, b, dir)
	_expect(n > 0, "p_placed: placement order refused")
	demo.rts_camera.frame(c, 0.6, 60.0)
	await _seconds(14.0)
	var places: Dictionary = sq.placed.duplicate()
	_expect(places.size() == sq.members.size(), "p_placed: not every soldier has a place (%d of %d)" % [places.size(), sq.members.size()])
	# An enemy squad 140 m ahead that fires.
	var en := _cs.spawn(1, demo.on_ground(c.x + dir.x * 140.0, c.z + dir.z * 140.0, 0.0), -dir, 6, "PE")
	_tough([en])
	var t0 := demo.sim.state.time
	var max_off := 0.0
	var tactics := {}
	var shots0 := demo.sim.brain.ai_shots
	CoreDemo.apply_time_scale(2.0)
	while demo.sim.state.time - t0 < 45.0:
		await _physics(15)
		tactics[sq.tactic_name()] = int(tactics.get(sq.tactic_name(), 0)) + 1
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			if u and u.alive and places.has(id):
				max_off = maxf(max_off, Vector2(u.position.x - places[id].x, u.position.z - places[id].z).length())
	CoreDemo.apply_time_scale(1.0)
	_png("placed_under_fire")
	out["places"] = places.size()
	out["max_off_place_m"] = snappedf(max_off, 0.1)
	out["tactics_sampled"] = tactics
	out["still_placed"] = not sq.placed.is_empty()
	out["shots"] = demo.sim.brain.ai_shots - shots0
	out["status"] = demo.sim.tactics.short_text(sq)
	_expect(int(out.shots) > 20, "p_placed: no fight happened")
	_expect(max_off <= 6.0, "p_placed: a soldier left his place by %.1f m" % max_off)
	_expect(not tactics.has("Reposition") and not tactics.has("Withdraw"), "p_placed: the squad re-planned its places itself %s" % str(tactics))
	await _clear_squads([sq, en])
	return out


func _b_firefight() -> Dictionary:
	var out := {}
	var pick := _firefight_site()
	_expect(not pick.is_empty(), "b_firefight: no open cover object with a sight line across it (precondition)")
	if pick.is_empty():
		return out
	var centre: Vector3 = pick.centre
	var dir: Vector3 = pick.dir
	var pa := demo.on_ground(centre.x - dir.x * 70.0, centre.z - dir.z * 70.0, 0.0)
	var pb := demo.on_ground(centre.x + dir.x * 70.0, centre.z + dir.z * 70.0, 0.0)
	var a := _cs.spawn(0, pa - dir * 10.0, dir, 8, "FA")
	var b := _cs.spawn(1, pb + dir * 10.0, -dir, 8, "FB")
	_tough([a, b])
	# Uncommanded: a move that arrives (the squads then choose their own tactics, as after any move order).
	demo.sim.squads.order_move([a.id], pa)
	demo.sim.squads.order_move([b.id], pb)
	demo.rts_camera.frame(centre, 0.6, 90.0)
	var br := demo.sim.brain
	var ta := demo.sim.tactics
	var c0 := {"fire_moves": br.fire_moves, "stalemates": ta.stalemates, "initiative": ta.initiative_flanks,
		"repos": int(ta.started.get(SquadState.Tactic.REPOSITION, 0)), "flanks": int(ta.started.get(SquadState.Tactic.FLANK, 0)),
		"supp": br.suppression_events, "shots": br.ai_shots}
	var timeline := {"FA": [], "FB": []}
	var t0 := demo.sim.state.time
	var m := {}
	# _watch samples exposure; the timeline is sampled every 10 s alongside.
	var probe := func() -> void:
		while demo.sim.state.time - t0 < 100.0 and not _done:
			(timeline.FA as Array).append(ta.short_text(a))
			(timeline.FB as Array).append(ta.short_text(b))
			await _seconds(5.0)
	probe.call()
	m = await _watch([a, b], 100.0)
	_png("firefight")
	out["at"] = _v(centre)
	out["exposure"] = m
	out["moves"] = {"firing_positions": br.fire_moves - int(c0.fire_moves), "stalemate_breaks": ta.stalemates - int(c0.stalemates),
		"initiative_flanks": ta.initiative_flanks - int(c0.initiative), "repositions": int(ta.started.get(SquadState.Tactic.REPOSITION, 0)) - int(c0.repos),
		"flanks": int(ta.started.get(SquadState.Tactic.FLANK, 0)) - int(c0.flanks)}
	out["suppression_events"] = br.suppression_events - int(c0.supp)
	out["shots"] = br.ai_shots - int(c0.shots)
	out["timeline"] = timeline
	out["alive"] = [a.members.size(), b.members.size()]
	out["stalemate_on"] = ta.stalemate_on
	_expect(int(out.shots) > 50, "b_firefight: no fight happened (%d shots)" % int(out.shots))
	var mv: Dictionary = out.moves
	if ta.stalemate_on:
		_expect(int(mv.firing_positions) + int(mv.stalemate_breaks) + int(mv.repositions) + int(mv.flanks) > 0,
			"b_firefight: nobody moved with a purpose in 100 s %s" % str(mv))
	await _clear_squads([a, b])
	return out


## The firefight's ground: a cover-layer object on open ground (forest cover under 0.2), nearest the test site first, with a
## direction across it where both sides stand on dry, gentle ground 70 m out and see each other (eye to chest). Only the nearest
## object used to be tried: run alone, the check got a hollow with no sight line in any direction and no fight. {centre, dir} or {}.
func _firefight_site() -> Dictionary:
	var routes: StrategicRoutes = demo.sim.war.routes
	var line := demo.sim.combat.line
	var cands: Array = []
	for rec: Dictionary in _layer.values():
		var t: Array = rec.transform
		var p := Vector3(t[9], t[10], t[11])
		if routes.cover_at(p) > 0.2 or absf(p.x) > 9000.0 or absf(p.z) > 9000.0:
			continue
		cands.append([Vector2(p.x - _site.def.x, p.z - _site.def.z).length(), p])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e: Array in cands.slice(0, 40):
		var centre: Vector3 = e[1]
		for k in 12:
			var d := Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0))
			var pa := demo.on_ground(centre.x - d.x * 70.0, centre.z - d.z * 70.0, 0.0)
			var pb := demo.on_ground(centre.x + d.x * 70.0, centre.z + d.z * 70.0, 0.0)
			if not _cs._dry(pa, 6.0) or not _cs._dry(pb, 6.0) or _cs._slope(pa, 5.0) > 12.0 or _cs._slope(pb, 5.0) > 12.0:
				continue
			if line.sight(pa + Vector3.UP * 1.6, pb + Vector3.UP * 1.1).visible and line.sight(pb + Vector3.UP * 1.6, pa + Vector3.UP * 1.1).visible:
				return {"centre": centre, "dir": d}
	return {}


## Removes single soldiers (their one-man squads may already be gone), and the contact picture they made.
func _drop(units: Array) -> void:
	for u: UnitState in units:
		if u and demo.sim.state.get_unit(u.id):
			demo.sim.state.remove_unit(u.id)
	demo.sim.state.war.contacts.clear()
	demo.sim.war.intel.rebuild()
	await _physics(10)

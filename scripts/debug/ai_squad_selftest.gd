## Scripted checks of AI-SQUAD-01 (fire teams, suppression, tactics, player tactical orders)
## in the running sandbox war, on a controlled encounter inside the real terrain
## (CombatScenario).
##
##   Godot.exe --path . --resolution 1600x900 --log-file sq.log res://scenes/game/world_ref_20km.tscn -- --ai-squad-test [--shots] [--only a,b] [--shot-dir=res://docs/ai_squad01]
##
## Baseline checks (base_*) run the encounter with the tactical layer OFF and record what the
## unchanged combat does; the scenario checks (a_ ... l_) run it ON. Every check resets its own
## state through CombatScenario.reset(), so each runs alone or in any order. Prints
## "SQUAD <check> <json>", writes res://benchmarks/raw/ai_squad_test.json.
class_name AISquadSelfTest
extends AIIntelSelfTest

var sc: CombatScenario
## --squad-demo: run the showcase and leave the game running afterwards.
var keep_open := false


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/ai_squad01"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	if "--squad-demo" in args:
		only = PackedStringArray(["z_showcase"])
		keep_open = true
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
	tree.create_timer(2700.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(60)
	_load_world_data()
	for u in state.soldiers():
		default_soldiers.append(u.position)
	_pause_ai(true)
	for sq: SquadState in state.all_squads():
		_stations[sq.id] = sq.station_objective
	sc = CombatScenario.new(demo)
	var site := sc.find_site()
	_expect(not site.is_empty(), "no encounter site found on the terrain")
	if site.is_empty():
		_finish()
		return
	_log("setup", {"site": {"def": _v(site.def), "att": _v(site.att), "dist": site.dist}, "soldiers": default_soldiers.size()})
	if _want("a_engagement"):
		_log("a_engagement", await _a_engagement())
	if _want("b_suppress"):
		_log("b_suppress", await _b_suppress())
	if _want("c_flank"):
		_log("c_flank", await _c_flank())
	if _want("d_assault"):
		_log("d_assault", await _d_assault())
	if _want("f_withdraw"):
		_log("f_withdraw", await _f_withdraw())
	if _want("h_intel"):
		_log("h_intel", await _h_intel())
	if _want("i_casualties"):
		_log("i_casualties", await _i_casualties())
	if _want("j_near_far"):
		_log("j_near_far", await _j_near_far())
	if _want("k_persist"):
		_log("k_persist", await _k_persist())
	if _want("l_perf"):
		_log("l_perf", await _l_perf())
	if _want("z_showcase"):
		_log("z_showcase", await _z_showcase())
	if _want("base_fight"):
		_log("base_fight", await _base_fight())
	if _want("base_far"):
		_log("base_far", await _base_far())
	if _want("base_orders"):
		_log("base_orders", await _base_orders())
	await _end_run()


func _end_run() -> void:
	sc.reset()
	await _physics(5)
	TimeCompression.reset()
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	await _seconds(0.5)
	_finish()


# --- Helpers ---------------------------------------------------------------------------------

## Frames the camera on the encounter and waits for the navmesh and the bodies.
func _stage_camera(zoom := 130.0) -> void:
	var site: Dictionary = sc.site
	demo.rts_camera.frame((site.def as Vector3).lerp(site.att, 0.5), 0.0, zoom)
	await _seconds(2.5)
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	await _seconds(0.5)


## Spawns through the scenario and registers the ids with the shot log of the inherited
## bookkeeping (which only records shots of spawned_ids).
func _sp(faction: int, at: Vector3, facing: Vector3, n := 8, tag := "") -> SquadState:
	var sq := sc.spawn(faction, at, facing, n, tag)
	for id in sq.members:
		spawned_ids.append(id)
	return sq


func _alive_of(sq: SquadState) -> int:
	return sq.members.size() if sq and demo.sim.state.get_squad(sq.id) == sq else 0


# --- Baseline: the unchanged combat in the encounter ------------------------------------------

## Two eight-soldier squads at 170 m face each other, tactical layer off. Records what the
## existing perception, cover reactions, ammunition and intelligence do on today's terrain.
func _base_fight() -> Dictionary:
	sc.reset()
	await _physics(5)
	var site: Dictionary = sc.site
	var n := _sp(0, site.att, site.dir, 8, "N-base")
	var s := _sp(1, site.def, -site.dir, 8, "S-base")
	_tough(n, 160.0)
	_tough(s, 160.0)
	await _stage_camera()
	_begin()
	var ammo0 := _ammo_of([n, s])
	var t0 := demo.sim.state.time
	var cover_peak := 0
	var contact_peak := 0
	while demo.sim.state.time - t0 < 40.0:
		await tree.physics_frame
		var cov := 0
		for sq in [n, s]:
			for id in sq.members:
				var u := _u(id)
				if u and u.tactic != UnitState.Tactic.NONE:
					cov += 1
		cover_peak = maxi(cover_peak, cov)
		contact_peak = maxi(contact_peak, _contacts(0).size() + _contacts(1).size())
	var hp := {"n": _hp_of(n), "s": _hp_of(s)}
	var out := {"shots": shot_log.size(), "shots_n": _shots_of(0), "shots_s": _shots_of(1), "damage_events": dmg_events,
		"cover_peak": cover_peak, "contacts_peak": contact_peak, "hp": hp, "ammo_used": ammo0 - _ammo_of([n, s]),
		"alive": [_alive_of(n), _alive_of(s)], "bodies": _bodies_of([n, s])}
	_expect(shot_log.size() > 20, "baseline: soldiers did not fire")
	_expect(dmg_events > 0, "baseline: no damage was dealt")
	_expect(contact_peak > 0, "baseline: the factions received no contact reports")
	return out


func _hp_of(sq: SquadState) -> float:
	var h := 0.0
	for id in sq.members:
		h += _u(id).health
	return snappedf(h, 1.0)


func _ammo_of(sqs: Array) -> int:
	var a := 0
	for sq: SquadState in sqs:
		for id in Array(sq.members) + Array(sq.fallen):
			var u := _u(id)
			if u:
				a += u.mag + u.reserve
	return a


func _bodies_of(sqs: Array) -> int:
	var b := 0
	for sq: SquadState in sqs:
		for id in sq.members:
			if _u(id).has_body:
				b += 1
	return b


## The same fight with the camera 6 km away: nobody has a body, the fight must still run
## (shots, damage, contacts) in the abstract tier.
func _base_far() -> Dictionary:
	sc.reset()
	await _physics(5)
	var site: Dictionary = sc.site
	var n := _sp(0, site.att, site.dir, 8, "N-far")
	var s := _sp(1, site.def, -site.dir, 8, "S-far")
	_tough(n, 160.0)
	_tough(s, 160.0)
	_far_camera()
	await _seconds(2.0)
	_begin()
	var t0 := demo.sim.state.time
	var bodies := _bodies_of([n, s])
	while demo.sim.state.time - t0 < 40.0:
		await tree.physics_frame
	var out := {"bodies": bodies, "shots": shot_log.size(), "damage_events": dmg_events, "alive": [_alive_of(n), _alive_of(s)],
		"hp": {"n": _hp_of(n), "s": _hp_of(s)}, "contacts": _contacts(0).size() + _contacts(1).size()}
	_expect(bodies == 0, "base_far: soldiers still had bodies far from the camera")
	_expect(shot_log.size() > 20, "base_far: no fighting in the abstract tier")
	return out


## Orders in the encounter: a Move order is carried out, a player Move cancels a cover
## reaction, Hold keeps soldiers where they are.
func _base_orders() -> Dictionary:
	sc.reset()
	await _physics(5)
	var site: Dictionary = sc.site
	var n := _sp(0, site.att, site.dir, 8, "N-ord")
	_tough(n, 400.0)
	await _stage_camera()
	var dest: Vector3 = (site.att as Vector3) + (site.dir as Vector3) * 40.0
	demo.sim.squads.order_move([n.id], dest)
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 30.0 and n.status == SquadState.Status.MOVING:
		await tree.physics_frame
	var c := demo.sim.squads._centroid(n)
	var d_move := _flat(c, dest)
	# Reaction cancelled by a player order: an enemy shoots, a soldier takes cover, a new Move overrides it.
	var s := _sp(1, site.def, -site.dir, 8, "S-ord")
	_tough(s, 400.0)
	var reacted := 0
	var t1 := demo.sim.state.time
	while demo.sim.state.time - t1 < 25.0 and reacted == 0:
		await tree.physics_frame
		for id in n.members:
			if _u(id).tactic != UnitState.Tactic.NONE:
				reacted += 1
	var back: Vector3 = (site.att as Vector3) - (site.dir as Vector3) * 30.0
	demo.sim.squads.order_move([n.id], back)
	await _physics(3)
	var still := 0
	for id in n.members:
		if _u(id).tactic != UnitState.Tactic.NONE or _u(id).is_reacting():
			still += 1
	_expect(d_move < 12.0, "base_orders: the squad did not reach its Move destination (%.1f m off)" % d_move)
	_expect(reacted > 0, "base_orders: nobody reacted to fire")
	_expect(still == 0, "base_orders: a player order did not cancel the reactions (%d)" % still)
	return {"move_end_dist_m": snappedf(d_move, 0.1), "reacted": reacted, "reactions_after_order": still}


# --- Helpers for the scenarios ----------------------------------------------------------------

func _tac() -> SquadTactics:
	return demo.sim.tactics


func _alive_units(sq: SquadState) -> Array:
	var out := []
	for id in sq.members:
		var u := _u(id)
		if u and u.alive:
			out.append(u)
	return out


## Spacing statistics of a squad: closest pair, pairs under 1.2 m, farthest from the centre.
func _spread_stats(sq: SquadState) -> Dictionary:
	var us := _alive_units(sq)
	var c := Vector3.ZERO
	for u in us:
		c += u.position
	c /= maxi(us.size(), 1)
	var closest := INF
	var crowded := 0
	var far := 0.0
	for i in us.size():
		far = maxf(far, _flat(us[i].position, c))
		for j in range(i + 1, us.size()):
			var d := _flat(us[i].position, us[j].position)
			closest = minf(closest, d)
			if d < 1.2:
				crowded += 1
	return {"n": us.size(), "closest_m": snappedf(closest, 0.1), "crowded_pairs": crowded, "max_from_centre_m": snappedf(far, 0.1), "centre": c}


func _units_in_cover(sq: SquadState) -> int:
	var n := 0
	for u in _alive_units(sq):
		if u.tactic == UnitState.Tactic.IN_COVER or (u.post_pos.is_finite() and _flat(u.position, u.post_pos) < 3.5):
			n += 1
	return n


func _distinct_posts(sq: SquadState) -> int:
	var posts: Array[Vector3] = []
	for u in _alive_units(sq):
		if u.post_pos.is_finite():
			var dup := false
			for q in posts:
				if _flat(q, u.post_pos) < 1.5:
					dup = true
			if not dup:
				posts.append(u.post_pos)
	return posts.size()


## Runs simulated time until cond returns true or `max_s` simulated seconds pass.
func _until(cond: Callable, max_s: float) -> float:
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < max_s:
		await tree.physics_frame
		if cond.call():
			break
	return demo.sim.state.time - t0


func _peak_supp(sq: SquadState) -> float:
	var m := 0.0
	var now := demo.sim.state.time
	for u in _alive_units(sq):
		m = maxf(m, u.suppression_at(now))
	return m


func _mission_ids(sq: SquadState) -> int:
	var n := 0
	var now := demo.sim.state.time
	for u in _alive_units(sq):
		if u.fire_at.is_finite() and now < u.fire_until:
			n += 1
	return n


# --- A: basic coordinated engagement ---------------------------------------------------------------

func _a_engagement() -> Dictionary:
	sc.reset()
	await _physics(5)
	var site: Dictionary = sc.site
	var n := _sp(0, site.att, site.dir, 8, "N-A")
	var s := _sp(1, site.def, -site.dir, 8, "S-A")
	_tough(n, 220.0)
	_tough(s, 220.0)
	await _stage_camera()
	_begin()
	var t0 := demo.sim.state.time
	var max_crowd := 0
	var peak_cover := [0, 0]
	var teams := [n.teams.size(), s.teams.size()]
	var frame := 0
	while demo.sim.state.time - t0 < 45.0:
		await tree.physics_frame
		frame += 1
		if frame % 20 == 0 and demo.sim.state.time - t0 > 6.0:
			max_crowd = maxi(max_crowd, int(_spread_stats(n).crowded_pairs) + int(_spread_stats(s).crowded_pairs))
			peak_cover[0] = maxi(peak_cover[0], _units_in_cover(n))
			peak_cover[1] = maxi(peak_cover[1], _units_in_cover(s))
	var stn := _spread_stats(n)
	var sts := _spread_stats(s)
	var out := {"tactics": [n.tactic_name(), s.tactic_name()], "owners": [n.owner_name(), s.owner_name()], "teams": teams,
		"roles": [Array(n.team_roles), Array(s.team_roles)], "spread_n": stn, "spread_s": sts, "max_crowded_pairs": max_crowd,
		"cover_peak": peak_cover, "distinct_posts": [_distinct_posts(n), _distinct_posts(s)], "shots": shot_log.size(),
		"contacts": [_contacts(0).size(), _contacts(1).size()], "why_n": n.tactic_why, "why_s": s.tactic_why, "alive": [_alive_of(n), _alive_of(s)],
		"supp_peak": [snappedf(_peak_supp(n), 0.01), snappedf(_peak_supp(s), 0.01)]}
	_expect(n.tactic != SquadState.Tactic.NONE and s.tactic != SquadState.Tactic.NONE or (_alive_of(n) < 3 or _alive_of(s) < 3), "A: squads in contact took no tactic")
	_expect(teams[0] == 2 and teams[1] == 2, "A: eight-soldier squads were not split into two fire teams")
	_expect(max_crowd == 0, "A: soldiers crowded (%d pairs closer than 1.2 m)" % max_crowd)
	_expect(float(stn.max_from_centre_m) < 45.0 and float(sts.max_from_centre_m) < 45.0, "A: a squad lost cohesion")
	_expect(shot_log.size() > 40, "A: no firefight")
	return out


# --- B: suppression and maneuver against a defended position ----------------------------------------------

func _setup_attack(def_n: int, att_hp: float, def_hp: float, defence := true) -> Dictionary:
	sc.reset()
	await _physics(5)
	if defence:
		sc.build_defence()
	var site: Dictionary = sc.site
	var n := _sp(0, site.att, site.dir, 8, "N-att")
	var s := _sp(1, site.def, -site.dir, def_n, "S-def")
	_tough(n, att_hp)
	_tough(s, def_hp)
	await _stage_camera()
	return {"n": n, "s": s}


func _b_suppress() -> Dictionary:
	var g := await _setup_attack(8, 260.0, 260.0)
	var n: SquadState = g.n
	var s: SquadState = g.s
	var site: Dictionary = sc.site
	_tac().order_tactic([s.id], SquadState.Tactic.DEFEND, site.def, SquadState.Owner.SQUAD)
	await _seconds(6.0)
	_begin()
	var m0 := brain.mission_shots
	var ammo0 := _ammo_of([n])
	var res := _tac().assign_for_operation(n, SquadState.Tactic.ASSAULT, site.def, "test: the operation attacks the position")
	_expect(res.ok, "B: the assault was refused: %s" % res.get("reason", ""))
	var t0 := demo.sim.state.time
	var supp_peak := 0.0
	var mission_peak := 0
	var min_dist := INF
	var tactics_seen := {}
	var support_ids: Array = Array(n.teams[0]) if n.teams.size() > 0 else []
	var support_shots_before := 0
	while demo.sim.state.time - t0 < 150.0 and n.tactic != SquadState.Tactic.NONE or demo.sim.state.time - t0 < 3.0:
		await tree.physics_frame
		supp_peak = maxf(supp_peak, _peak_supp(s))
		mission_peak = maxi(mission_peak, _mission_ids(n))
		tactics_seen[n.tactic_name()] = true
		var c := demo.sim.squads._centroid(n)
		min_dist = minf(min_dist, _flat(c, site.def))
		if _alive_of(n) == 0 or _alive_of(s) == 0:
			break
	var out := {"result": n.tactic_name(), "why": n.tactic_why, "rejected": n.tactic_rejected, "tactics_seen": tactics_seen.keys(),
		"duration_s": snappedf(demo.sim.state.time - t0, 0.1), "mission_shots": brain.mission_shots - m0, "mission_peak": mission_peak,
		"ammo_used_attackers": ammo0 - _ammo_of([n]), "defender_supp_peak": snappedf(supp_peak, 0.01), "closest_m": snappedf(min_dist, 0.1),
		"alive": [_alive_of(n), _alive_of(s)], "events": _recent_events(n.id, 8)}
	_expect(brain.mission_shots - m0 > 0, "B: the support team never fired a mission")
	_expect(supp_peak >= 0.35, "B: the defenders were never suppressed (peak %.2f)" % supp_peak)
	_expect(ammo0 - _ammo_of([n]) > 20, "B: no ammunition used by the attackers")
	_expect(n.tactic != SquadState.Tactic.ASSAULT or demo.sim.state.time - t0 >= 150.0, "B: the assault never ended")
	return out


func _recent_events(squad_id: int, k: int) -> Array:
	var out := []
	for e in _tac().events:
		if e.squad == squad_id:
			out.append("%.0f %s" % [e.t, e.text])
	return out.slice(-k)


# --- C: flank --------------------------------------------------------------------------------------------

func _c_flank() -> Dictionary:
	var g := await _setup_attack(8, 260.0, 260.0)
	var n: SquadState = g.n
	var s: SquadState = g.s
	var site: Dictionary = sc.site
	_tac().order_tactic([s.id], SquadState.Tactic.DEFEND, site.def, SquadState.Owner.SQUAD)
	await _seconds(5.0)
	var plans0 := _tac().pos.flank_plans
	var res := _tac().order_tactic([n.id], SquadState.Tactic.FLANK, site.def)
	var started_as := n.tactic_name()
	var route: PackedVector3Array = n.tactic_route.duplicate()
	var support_start := _centroid_of(n.teams[0]) if n.teams.size() >= 2 else Vector3.ZERO
	var man_start := _centroid_of(n.teams[1]) if n.teams.size() >= 2 else Vector3.ZERO
	var t0 := demo.sim.state.time
	var closest_to_route_end := INF
	var support_moved := 0.0
	var phases := {}
	while demo.sim.state.time - t0 < 130.0 and n.tactic != SquadState.Tactic.NONE and _alive_of(n) > 0:
		await tree.physics_frame
		phases[n.tactic_name() + ":" + str(n.tactic_phase)] = true
		if route.size() > 0 and n.teams.size() >= 2:
			closest_to_route_end = minf(closest_to_route_end, _flat(_centroid_of(n.teams[1]), route[route.size() - 1]))
			support_moved = maxf(support_moved, _flat(_centroid_of(n.teams[0]), support_start))
	var out := {"order": res.get("text", ""), "started_as": started_as, "route": route.size(), "route_len_m": snappedf(_route_len(route, man_start), 1.0),
		"man_closest_to_stage_m": snappedf(closest_to_route_end, 0.1), "support_max_move_m": snappedf(support_moved, 0.1),
		"flank_plans": _tac().pos.flank_plans - plans0, "replans": n.tactic_replans, "phases": phases.keys(), "end": n.tactic_name(), "why": n.tactic_why,
		"alive": [_alive_of(n), _alive_of(s)], "events": _recent_events(n.id, 8)}
	_expect(res.ok, "C: the flank was refused: %s" % res.get("text", ""))
	if res.ok:
		_expect(started_as == "Flank", "C: the order did not become a flank (%s)" % started_as)
		_expect(route.size() >= 2, "C: no flank route")
		_expect(closest_to_route_end < 30.0 or n.tactic_phase >= SquadTactics.PH_FINAL or n.tactic == SquadState.Tactic.NONE, "C: the maneuver team never reached the flank position (%.0f m away)" % closest_to_route_end)
		_expect(support_moved < 35.0, "C: the support team left its role (moved %.0f m)" % support_moved)
		_expect(_tac().pos.flank_plans - plans0 <= 6, "C: the flank was calculated %d times" % (_tac().pos.flank_plans - plans0))
	return out


func _centroid_of(ids: PackedInt32Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for id in ids:
		var u := _u(id)
		if u and u.alive:
			c += u.position
			n += 1
	return c / maxi(n, 1)


func _route_len(route: PackedVector3Array, from: Vector3) -> float:
	var d := 0.0
	var prev := from
	for p in route:
		d += _flat(prev, p)
		prev = p
	return d


# --- D: assault ----------------------------------------------------------------------------------------------

func _d_assault() -> Dictionary:
	var g := await _setup_attack(4, 260.0, 120.0)
	var n: SquadState = g.n
	var s: SquadState = g.s
	var site: Dictionary = sc.site
	_tac().order_tactic([s.id], SquadState.Tactic.DEFEND, site.def, SquadState.Owner.SQUAD)
	await _seconds(4.0)
	var res := _tac().order_tactic([n.id], SquadState.Tactic.ASSAULT, site.def)
	var t0 := demo.sim.state.time
	var phases := {}
	var on_target := 0.0
	while demo.sim.state.time - t0 < 170.0 and _alive_of(n) > 0:
		await tree.physics_frame
		phases[n.tactic_name() + ":" + str(n.tactic_phase)] = true
		if n.tactic == SquadState.Tactic.NONE and n.order != SquadState.Order.REGROUP and n.order != SquadState.Order.TACTIC:
			break
	var stn := _spread_stats(n)
	var out := {"order": res.get("text", ""), "phases": phases.keys(), "end": n.tactic_name(), "order_after": n.order_name(), "why": n.tactic_why,
		"duration_s": snappedf(demo.sim.state.time - t0, 0.1), "centre_to_target_m": snappedf(_flat(stn.centre, site.def), 0.1),
		"alive": [_alive_of(n), _alive_of(s)], "spread": stn, "events": _recent_events(n.id, 10)}
	_expect(res.ok, "D: the assault was refused")
	_expect(phases.size() >= 3, "D: the assault did not go through its phases (%s)" % str(phases.keys()))
	_expect(n.tactic != SquadState.Tactic.ASSAULT, "D: the assault never completed or failed")
	return out


# --- F: withdrawal -----------------------------------------------------------------------------------------

## A weak squad (one or two hits kill) meets a strong one: it breaks contact on its own.
func _f_withdraw() -> Dictionary:
	var g := await _setup_attack(8, 50.0, 400.0, false)
	var n: SquadState = g.n
	var s: SquadState = g.s
	_begin()
	var m0 := brain.mission_shots
	var w0 := int(_tac().started.get(SquadState.Tactic.WITHDRAW, 0))
	var t0 := demo.sim.state.time
	var d0 := _flat(demo.sim.squads._centroid(n), demo.sim.squads._centroid(s))
	var withdraw_t := -1.0
	var spread_max := 0.0
	while demo.sim.state.time - t0 < 110.0 and _alive_of(n) > 0:
		await tree.physics_frame
		if n.tactic == SquadState.Tactic.WITHDRAW and withdraw_t < 0.0:
			withdraw_t = demo.sim.state.time - t0
		if n.tactic == SquadState.Tactic.WITHDRAW:
			spread_max = maxf(spread_max, float(_spread_stats(n).max_from_centre_m))
		if withdraw_t >= 0.0 and n.tactic != SquadState.Tactic.WITHDRAW and demo.sim.state.time - t0 > withdraw_t + 12.0:
			break
	var d1 := _flat(demo.sim.squads._centroid(n), demo.sim.squads._centroid(s)) if _alive_of(n) > 0 else 0.0
	var out := {"withdraw_started_s": snappedf(withdraw_t, 0.1), "started": int(_tac().started.get(SquadState.Tactic.WITHDRAW, 0)) - w0,
		"distance_before_m": snappedf(d0, 0.1), "distance_after_m": snappedf(d1, 0.1), "spread_max_m": snappedf(spread_max, 0.1),
		"cover_fire_shots": brain.mission_shots - m0, "alive": [_alive_of(n), _alive_of(s)], "tactic_end": n.tactic_name(), "why": n.tactic_why,
		"events": _recent_events(n.id, 8)}
	_expect(withdraw_t >= 0.0, "F: the weak squad never withdrew (eff %.2f)" % _tac().effectiveness(n))
	if withdraw_t >= 0.0 and _alive_of(n) > 1:
		_expect(d1 > d0 + 40.0, "F: the squad did not get away (%.0f m -> %.0f m)" % [d0, d1])
		_expect(spread_max < 70.0, "F: the withdrawal lost cohesion (spread %.0f m)" % spread_max)
	return out


# --- H: intelligence integration ---------------------------------------------------------------------------------

## The faction holds a report of enemies that are not there (any more): the squad shoots at the
## reported place, never at the real enemy elsewhere, and stops when the report is old.
func _h_intel() -> Dictionary:
	sc.reset()
	await _physics(5)
	var site: Dictionary = sc.site
	var n := _sp(0, site.att, site.dir, 8, "N-int")
	# The real enemy stands 260 m to the side, out of sight and out of range.
	var side: Vector3 = site.side
	var far_pos: Vector3 = (site.att as Vector3) + side * 260.0 - (site.dir as Vector3) * 40.0
	var s := _sp(1, far_pos, -side, 4, "S-int")
	_hold(s, 400.0)
	_tough(n, 400.0)
	await _stage_camera()
	# Soldiers of n took fire from P (a report): a FIRE contact at P, 120 m ahead.
	var P: Vector3 = (site.att as Vector3) + (site.dir as Vector3) * 120.0
	P = demo.on_ground(P.x, P.z, 0.0)
	var observer := _u(n.members[0])
	ws.intel.report_fire(observer, P)
	_begin()
	var m0 := brain.mission_shots
	var t0 := demo.sim.state.time
	var mission_ends: Array = []
	var cb := func(shot: Dictionary) -> void:
		var u := _u(shot.shooter)
		if u and u.faction == 0 and u.fire_at.is_finite() and demo.sim.state.time < u.fire_until and not (u.target_id > 0 and u.target_visible):
			mission_ends.append(shot.end)
	demo.sim.state.shot_fired.connect(cb)
	var started_t := -1.0
	var target_when_started := Vector3.INF
	var conf_at_start := 0.0
	var ended_t := -1.0
	while demo.sim.state.time - t0 < 80.0:
		await tree.physics_frame
		if n.tactic == SquadState.Tactic.SUPPRESS and started_t < 0.0:
			started_t = demo.sim.state.time - t0
			target_when_started = n.tactic_target
			var c := ws.intel.get_contact(0, n.tactic_contact)
			conf_at_start = c.conf if c else 0.0
		if started_t >= 0.0 and n.tactic != SquadState.Tactic.SUPPRESS and ended_t < 0.0:
			ended_t = demo.sim.state.time - t0
			break
	demo.sim.state.shot_fired.disconnect(cb)
	var enemy_pos: Vector3 = demo.sim.squads._centroid(s)
	var near_p := 0
	var near_enemy := 0
	for e: Vector3 in mission_ends:
		if _flat(e, P) < 45.0:
			near_p += 1
		if _flat(e, enemy_pos) < 45.0:
			near_enemy += 1
	var out := {"suppress_started_s": snappedf(started_t, 0.1), "suppress_ended_s": snappedf(ended_t, 0.1), "target": _v(target_when_started),
		"reported": _v(P), "true_enemy": _v(enemy_pos), "target_to_report_m": snappedf(_flat(target_when_started, P), 0.1),
		"target_to_enemy_m": snappedf(_flat(target_when_started, enemy_pos), 0.1), "conf_at_start": snappedf(conf_at_start, 0.01),
		"mission_shots": brain.mission_shots - m0, "shots_near_report": near_p, "shots_near_true_enemy": near_enemy,
		"why": n.tactic_why, "events": _recent_events(n.id, 6)}
	_expect(started_t >= 0.0, "H: the squad did not act on the report")
	if started_t >= 0.0:
		_expect(_flat(target_when_started, P) < 15.0, "H: the target is not the reported position")
		_expect(_flat(target_when_started, enemy_pos) > 100.0, "H: the target is near the true enemy")
		_expect(brain.mission_shots - m0 > 0, "H: no suppressive fire was fired")
		_expect(near_enemy == 0, "H: shots fell near the true enemy (%d)" % near_enemy)
		_expect(ended_t > 0.0, "H: the expired report is still a target after 80 s")
	return out


# --- I: casualties and reorganization ------------------------------------------------------------------------------

func _i_casualties() -> Dictionary:
	sc.reset()
	await _physics(5)
	var site: Dictionary = sc.site
	var n := _sp(0, site.att, site.dir, 8, "N-cas")
	await _stage_camera()
	await _seconds(1.5)
	var before := {"teams": n.teams.size(), "sizes": [n.teams[0].size(), n.teams[1].size()], "leaders": Array(n.team_leaders), "leader": n.leader_id}
	var squad_leader := n.leader_id
	var lt := n.team_of(squad_leader)
	var other_team: int = 1 - lt
	var killed: Array[int] = [squad_leader, n.teams[other_team][1]]
	for id in killed:
		combat.kill(_u(id), -1)
	await _seconds(1.5)
	var after_ok := true
	var alive_ids := {}
	for id in n.members:
		alive_ids[id] = true
	for t in n.teams:
		for id in t:
			if not alive_ids.has(id) or not _u(id).alive:
				after_ok = false
	var leaders_ok := true
	for i in n.teams.size():
		if not n.teams[i].has(n.team_leaders[i]) or not _u(n.team_leaders[i]).alive:
			leaders_ok = false
	var balanced := n.teams.size() == 2 and absi(n.teams[0].size() - n.teams[1].size()) <= 1
	var squad_leader_leads := n.team_leaders[n.team_of(n.leader_id)] == n.leader_id
	# The squad still obeys: a move works.
	var dest: Vector3 = (site.att as Vector3) + (site.dir as Vector3) * 25.0
	demo.sim.squads.order_move([n.id], dest)
	await _until_squad_idle(n, 40.0)
	var moved := _flat(demo.sim.squads._centroid(n), dest)
	# Save / load: dead soldiers do not come back into the teams.
	var snap := demo.sim.state.snapshot()
	demo.sim.state.apply_snapshot(snap)
	await _physics(3)
	var reload_ok := true
	for t in n.teams:
		for id in t:
			if killed.has(id) or not _u(id).alive:
				reload_ok = false
	var n2 := demo.sim.state.get_squad(n.id)
	for t in n2.teams:
		for id in t:
			if killed.has(id) or not _u(id).alive:
				reload_ok = false
	var out := {"before": before, "killed": killed, "teams_after": n.teams.map(func(t: PackedInt32Array) -> Array: return Array(t)), "leaders_after": Array(n.team_leaders),
		"squad_leader_after": n.leader_id, "valid": after_ok, "leaders_valid": leaders_ok, "balanced": balanced, "squad_leader_leads": squad_leader_leads,
		"move_end_dist_m": snappedf(moved, 0.1), "reload_valid": reload_ok, "fallen": Array(n.fallen), "events": _recent_events(n.id, 6)}
	_expect(after_ok, "I: a dead soldier is still in a fire team")
	_expect(leaders_ok, "I: a fire team has no living leader")
	_expect(balanced, "I: the fire teams are unbalanced after casualties")
	_expect(squad_leader_leads, "I: the squad leader does not lead its team")
	_expect(moved < 12.0, "I: the reduced squad did not carry out a move order")
	_expect(reload_ok, "I: a dead soldier came back after save/load")
	return out


func _until_squad_idle(sq: SquadState, max_s: float) -> void:
	var t0 := demo.sim.state.time
	await tree.create_timer(0.5).timeout
	while demo.sim.state.time - t0 < max_s and sq.status == SquadState.Status.MOVING:
		await tree.physics_frame


# --- J: near / far -------------------------------------------------------------------------------------------------

## The same assault with the camera on it and 6 km away (everybody abstract), and the camera
## leaving and coming back in the middle: the tactic, its phase and the soldiers' posts survive, no
## entity is duplicated.
func _j_near_far() -> Dictionary:
	var out := {}
	for mode: String in ["near", "far"]:
		var g := await _setup_attack(6, 260.0, 260.0)
		var n: SquadState = g.n
		var s: SquadState = g.s
		var site: Dictionary = sc.site
		_tac().order_tactic([s.id], SquadState.Tactic.DEFEND, site.def, SquadState.Owner.SQUAD)
		await _seconds(3.0)
		_tac().order_tactic([n.id], SquadState.Tactic.ASSAULT, site.def)
		if mode == "far":
			_far_camera()
			await _seconds(2.0)
		_begin()
		var units0 := demo.sim.state.units.size()
		var bodies0 := _bodies_of([n, s])
		var t0 := demo.sim.state.time
		var seen := {}
		var swap := {}
		while demo.sim.state.time - t0 < 60.0 and _alive_of(n) > 0:
			await tree.physics_frame
			seen[n.tactic_name()] = true
			if mode == "near" and not swap.has("away") and demo.sim.state.time - t0 > 15.0:
				swap["before"] = _tactic_sig(n)
				_far_camera()
				swap["away"] = true
			elif mode == "near" and swap.has("away") and not swap.has("back") and demo.sim.state.time - t0 > 28.0:
				swap["after_away"] = _tactic_sig(n)
				_frame_mid(site.att, site.def, 130.0)
				swap["back"] = true
			elif mode == "near" and swap.has("back") and not swap.has("done") and demo.sim.state.time - t0 > 36.0:
				swap["after_back"] = _tactic_sig(n)
				swap["done"] = true
		var dup := 0
		for id in demo.sim.bodies:
			if demo.sim.proxies.has(id):
				dup += 1
		out[mode] = {"bodies_at_start": bodies0, "tactics_seen": seen.keys(), "end": n.tactic_name(), "why": n.tactic_why, "shots": shot_log.size(),
			"alive": [_alive_of(n), _alive_of(s)], "units_before": units0, "units_after": demo.sim.state.units.size(), "body_and_proxy": dup, "swap": swap}
		_expect(seen.size() >= 2 or n.tactic != SquadState.Tactic.NONE, "J(%s): the squad did not run a tactic" % mode)
		_expect(shot_log.size() > 30, "J(%s): no fighting" % mode)
		_expect(dup == 0, "J(%s): a soldier has a body and a proxy" % mode)
		_expect(demo.sim.state.units.size() == units0, "J(%s): units appeared or vanished" % mode)
		if mode == "near" and swap.has("after_back"):
			var a1: Dictionary = swap.before
			var a2: Dictionary = swap.after_back
			_expect(int(a2.posts) >= int(a1.posts) - 2 or n.tactic == SquadState.Tactic.NONE, "J: soldiers lost their posts while the camera was away")
			_expect(a2.tactic == a1.tactic or a1.tactic != "-", "J: the tactic was reset by the camera change")
	return out


func _tactic_sig(sq: SquadState) -> Dictionary:
	var posts := 0
	for u in _alive_units(sq):
		if u.post_pos.is_finite():
			posts += 1
	return {"tactic": sq.tactic_name(), "phase": sq.tactic_phase, "leg": sq.tactic_leg, "posts": posts, "owner": sq.owner_name(), "order": sq.order_name()}


# --- K: save / load during a tactic --------------------------------------------------------------------------------

func _k_persist() -> Dictionary:
	var out := {}
	for kind: String in ["suppress", "flank", "bound", "withdraw"]:
		var g := await _setup_attack(6, 300.0, 300.0)
		var n: SquadState = g.n
		var s: SquadState = g.s
		var site: Dictionary = sc.site
		var state := demo.sim.state
		_tac().order_tactic([s.id], SquadState.Tactic.DEFEND, site.def, SquadState.Owner.SQUAD)
		await _seconds(3.0)
		var res := {}
		match kind:
			"suppress":
				res = _tac().order_tactic([n.id], SquadState.Tactic.SUPPRESS, site.def)
			"flank":
				res = _tac().order_tactic([n.id], SquadState.Tactic.FLANK, site.def)
			"bound":
				_hold(s, 600.0)
				res = _tac().order_tactic([n.id], SquadState.Tactic.BOUND, (site.att as Vector3) + (site.dir as Vector3) * 90.0)
			"withdraw":
				res = _tac().order_tactic([n.id], SquadState.Tactic.WITHDRAW, (site.att as Vector3) - (site.dir as Vector3) * 90.0)
		_expect(res.get("ok", false), "K(%s): the order was refused: %s" % [kind, res.get("text", "")])
		if not res.get("ok", false):
			out[kind] = {"refused": res.get("text", "")}
			continue
		await _seconds(14.0)
		var sig1 := _full_sig(n)
		var snap := state.snapshot()
		state.apply_snapshot(snap)
		await tree.physics_frame
		var n2 := state.get_squad(n.id)
		var sig2 := _full_sig(n2)
		var same := _sig_diff(sig1, sig2)
		await _seconds(16.0)
		var n3 := state.get_squad(n.id)
		var progressed := n3.tactic != n2.tactic or n3.tactic_phase != n2.tactic_phase or n3.tactic_leg != n2.tactic_leg or n3.tactic_route_i != n2.tactic_route_i \
				or _flat(demo.sim.squads._centroid(n3), demo.sim.squads._centroid(n2)) > 3.0
		out[kind] = {"before": sig1, "after_load": sig2, "diff": same, "later": _tactic_sig(n3), "progressed": progressed, "why": n3.tactic_why}
		_expect(same.is_empty(), "K(%s): the loaded state differs: %s" % [kind, str(same)])
		_expect(progressed or n3.tactic == SquadState.Tactic.NONE, "K(%s): the squad did not carry on after loading" % kind)
		_expect(n3.tactic_why != "cancelled by a new order", "K(%s): loading cancelled the tactic" % kind)
	return out


func _full_sig(sq: SquadState) -> Dictionary:
	var posts := {}
	var missions := {}
	for id in sq.members:
		var u := _u(id)
		posts[str(id)] = _v(u.post_pos) if u.post_pos.is_finite() else []
		missions[str(id)] = _v(u.fire_at) if u.fire_at.is_finite() else []
	return {"tactic": sq.tactic, "owner": sq.tactic_owner, "phase": sq.tactic_phase, "leg": sq.tactic_leg, "route_i": sq.tactic_route_i,
		"route": sq.tactic_route.size(), "target": _v(sq.tactic_target) if sq.tactic_target.is_finite() else [], "dest": _v(sq.tactic_dest) if sq.tactic_dest.is_finite() else [],
		"teams": sq.teams.map(func(t: PackedInt32Array) -> Array: return Array(t)), "roles": Array(sq.team_roles), "posts": posts, "missions": missions,
		"order": sq.order}


func _sig_diff(a: Dictionary, b: Dictionary) -> Array:
	var diffs := []
	for k in a:
		if k == "posts" or k == "missions":
			for id in a[k]:
				var x: Array = a[k][id]
				var y: Array = b[k].get(id, [])
				if x.size() != y.size() or (x.size() == 3 and (absf(x[0] - y[0]) > 0.2 or absf(x[2] - y[2]) > 0.2)):
					diffs.append("%s %s: %s -> %s" % [k, id, str(x), str(y)])
		elif str(a[k]) != str(b[k]):
			diffs.append("%s: %s -> %s" % [k, str(a[k]), str(b[k])])
	return diffs


# --- L: performance ---------------------------------------------------------------------------------------------------

func _l_perf() -> Dictionary:
	var out := {}
	for on: bool in [false, true]:
		sc.reset()
		await _physics(5)
		sc.build_defence()
		var site: Dictionary = sc.site
		var att: Vector3 = site.att
		var def: Vector3 = site.def
		var side: Vector3 = site.side
		var north: Array = []
		var south: Array = []
		for k in 3:
			north.append(_sp(0, att + side * (k - 1) * 34.0, site.dir, 8, "N-p%d" % k))
			south.append(_sp(1, def + side * (k - 1) * 30.0, -site.dir, 8, "S-p%d" % k))
		for sq: SquadState in north + south:
			_tough(sq, 600.0)
		demo.sim.tactics.enabled = on
		if on:
			_tac().order_tactic(south.map(func(q: SquadState) -> int: return q.id), SquadState.Tactic.DEFEND, def, SquadState.Owner.SQUAD)
			_tac().order_tactic(north.map(func(q: SquadState) -> int: return q.id), SquadState.Tactic.ASSAULT, def)
		else:
			for sq: SquadState in south:
				sq.tactic = SquadState.Tactic.NONE
		await _stage_camera(170.0)
		await _seconds(6.0)
		brain.reset_stats()
		_tac().reset_stats()
		var tick0: Dictionary = demo.sim.tick_usec.duplicate()
		var fs := await _frame_stats(25.0)
		var bs := brain.summary()
		var ticks: int = demo.sim.tick_usec.ticks - int(tick0.ticks)
		out["tactics_on" if on else "tactics_off"] = {"frames": fs, "brain_us_avg": bs.update_us_avg, "brain_us_max": bs.update_us_max, "prof_us": bs.prof_us_per_frame,
			"sim_us_per_tick": {"tactics": snappedf(float(demo.sim.tick_usec.tactics - int(tick0.tactics)) / maxi(ticks, 1), 0.1),
				"brain": snappedf(float(demo.sim.tick_usec.brain - int(tick0.brain)) / maxi(ticks, 1), 0.1), "squads": snappedf(float(demo.sim.tick_usec.squads - int(tick0.squads)) / maxi(ticks, 1), 0.1)},
			"tactics": _tac().summary(), "cover": bs.cover, "soldiers": 48, "alive": _alive_total(north + south)}
		demo.sim.tactics.enabled = true
	var on_stats: Dictionary = out.tactics_on
	_expect(float(on_stats.frames.avg_ms) < 16.7, "L: frame time with tactics %.1f ms" % float(on_stats.frames.avg_ms))
	_expect(float(on_stats.tactics.step_us_avg) < 2000.0, "L: squad tactic update %.0f us per tick" % float(on_stats.tactics.step_us_avg))
	return out


func _alive_total(sqs: Array) -> int:
	var n := 0
	for sq: SquadState in sqs:
		n += _alive_of(sq)
	return n

# --- Z: the showcase (visual inspection and the --squad-demo scenario) -------------------------------------------------

## A complete encounter through the real RTS controls: two North squads march to a start line (wedge /
## column by terrain), then are ordered to assault a South squad dug in behind HESCO on a rise. Camera
## from the RTS view; with --shots a picture at every phase change and every 12 s. With --squad-demo
## the game stays running afterwards for the player to command (select a squad, Z K L J Backspace, F7).
func _z_showcase() -> Dictionary:
	sc.reset()
	await _physics(5)
	sc.build_defence()
	var site: Dictionary = sc.site
	var dir: Vector3 = site.dir
	var side: Vector3 = site.side
	var def: Vector3 = site.def
	var yaw := atan2(-dir.x, -dir.z)
	# The attackers start beyond sight range (440 m), so the march is not a firefight yet.
	var start_line: Vector3 = (site.att as Vector3) + dir * 10.0
	var s := _sp(1, def, -dir, 8, "South-1")
	var n1 := _sp(0, (site.att as Vector3) - dir * 270.0 - side * 14.0, dir, 8, "North-1")
	var n2 := _sp(0, (site.att as Vector3) - dir * 280.0 + side * 22.0, dir, 6, "North-2")
	for sq: SquadState in [n1, n2, s]:
		_tough(sq, 220.0)
	_tac().order_tactic([s.id], SquadState.Tactic.DEFEND, def, SquadState.Owner.SQUAD)
	_follow_cam(n1, n2, def, yaw, 120.0)
	await _seconds(3.0)
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	var out := {"phases": []}
	var t0 := demo.sim.state.time
	# 1. The march: selection and a Move order the way the player gives them.
	demo.rts.select_squads([n1.id, n2.id])
	demo.rts.order_move(start_line)
	if shots:
		_shot("z01_march_start")
	var last_shot := demo.sim.state.time
	var marching := true
	await _seconds(1.0)
	while marching and demo.sim.state.time - t0 < 90.0:
		await tree.physics_frame
		_follow_cam(n1, n2, def, yaw, 120.0)
		if shots and demo.sim.state.time - last_shot >= 12.0:
			last_shot = demo.sim.state.time
			_shot("z02_march_%02d" % int(demo.sim.state.time - t0))
		marching = n1.status == SquadState.Status.MOVING or n2.status == SquadState.Status.MOVING
	out.phases.append({"phase": "march", "s": snappedf(demo.sim.state.time - t0, 0.1), "formation": [n1.formation_name(), n2.formation_name()], "auto": [n1.formation_auto, n2.formation_auto],
		"contact": [n1.tactic_name(), s.tactic_name()]})
	# 2. The attack, ordered through the RTS controller (the same call as the Z key).
	var res := demo.rts.order_tactic(SquadState.Tactic.ASSAULT, def)
	out["order"] = res.get("text", "")
	if shots:
		_shot("z03_assault_ordered")
	var t1 := demo.sim.state.time
	var seen := {}
	last_shot = t1
	var last_sig := ""
	var end_reason := "time"
	while demo.sim.state.time - t1 < 240.0:
		await tree.physics_frame
		_follow_cam(n1, n2, def, yaw, 90.0)
		var sig := "%s:%d|%s:%d" % [n1.tactic_name(), n1.tactic_phase, n2.tactic_name(), n2.tactic_phase]
		seen[sig] = true
		if shots and (sig != last_sig or demo.sim.state.time - last_shot >= 12.0):
			last_shot = demo.sim.state.time
			last_sig = sig
			await tree.process_frame
			_shot("z04_%03d_%s" % [int(demo.sim.state.time - t1), sig.replace(":", "").replace("|", "_")])
		if _alive_of(s) == 0 or (_alive_of(n1) + _alive_of(n2) == 0):
			end_reason = "one side destroyed"
			break
		if n1.tactic == SquadState.Tactic.NONE and n2.tactic == SquadState.Tactic.NONE and demo.sim.state.time - t1 > 20.0:
			end_reason = "tactics ended"
			break
	await _seconds(6.0)
	if shots:
		_shot("z05_end")
	out["attack"] = {"end": end_reason, "s": snappedf(demo.sim.state.time - t1, 0.1), "signatures": seen.keys(), "alive": [_alive_of(n1), _alive_of(n2), _alive_of(s)],
		"why": [n1.tactic_why, n2.tactic_why], "events": _recent_events(n1.id, 12), "events2": _recent_events(n2.id, 8)}
	return out


## RTS camera on the action: between the attackers and the position, looking along the attack,
## close enough to see soldiers (zoom follows the distance, at least min_zoom), the action in the
## upper part of the screen above the HUD text.
func _follow_cam(n1: SquadState, n2: SquadState, def: Vector3, yaw: float, max_zoom: float) -> void:
	var a: Vector3 = demo.sim.squads._centroid(n1).lerp(demo.sim.squads._centroid(n2), 0.5)
	var d := _flat(a, def)
	var mid := a.lerp(def, 0.5)
	var zoom := clampf(d * 0.62 + 18.0, 38.0, max_zoom)
	demo.rts_camera.frame(mid - SquadControl._forward(yaw) * zoom * 0.22, yaw, zoom)


# --- Output ---------------------------------------------------------------------------------------------------

func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("SQUAD %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("SQUAD FAILED CHECK: ", msg)


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/sq01_%s.jpg" % [_shot_dir, shot_name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("SQUAD shot: ", path)


func _finish() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	results["tactics"] = demo.sim.tactics.summary()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/ai_squad_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("SQUAD %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	if keep_open:
		print("SQUAD demo running: the encounter stays for inspection (select a squad, Z/K/L/J/Backspace, F7 shows the fire teams)")
		return
	demo.shutdown_cleanup()
	tree.quit()

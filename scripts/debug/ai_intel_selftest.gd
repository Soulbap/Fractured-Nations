## Scripted checks of AI-INTEL-01 / AI-OBS-01 (faction intelligence, contact reports, the
## strategic AI reading them, the developer inspector) in the running sandbox war.
##
##   Godot.exe --path . --resolution 1600x900 --log-file ai.log res://scenes/game/world_ref_20km.tscn -- --ai-intel-test [--shots] [--only a,b] [--shot-dir=res://docs/ai_intel01]
##
## Checks (A-J are the brief's scenarios): a_initial, b_lost, c_reacquire, d_hearing, e_tiers,
## f_persist, g_strategy, h_player, i_factions, j_perf; k_investigate (the AI acts on a stale
## report), z_old_rule (nothing in the strategic path reads true positions).
## Every scenario resets its own state (contacts, operations, test units) and runs alone or in
## any order. Squads are real WorldState squads in the real game; hold fire / raised health
## are stated where used (the soldiers still perceive and report exactly as in play).
## Prints "INTEL <check> <json>", writes res://benchmarks/raw/ai_intel_test.json.
class_name AIIntelSelfTest
extends SandboxSelfTest

var stage := {}
var _vis_n := 0
## squad id -> station objective at the start (the war's garrisons), restored by _fresh().
var _stations := {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/ai_intel01"
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
	_log("setup", {"soldiers": default_soldiers.size(), "factions": war.factions.size(), "intel": ws.intel.stats()})
	if _want("z_old_rule"):
		_log("z_old_rule", await _old_rule())
	if _want("a_initial"):
		_log("a_initial", await _a_initial())
	if _want("b_lost"):
		_log("b_lost", await _b_lost())
	if _want("c_reacquire"):
		_log("c_reacquire", await _c_reacquire())
	if _want("d_hearing"):
		_log("d_hearing", await _d_hearing())
	if _want("e_tiers"):
		_log("e_tiers", await _e_tiers())
	if _want("f_persist"):
		_log("f_persist", await _f_persist())
	if _want("g_strategy"):
		_log("g_strategy", await _g_strategy())
	if _want("k_investigate"):
		_log("k_investigate", await _k_investigate())
	if _want("h_player"):
		_log("h_player", await _h_player())
	if _want("i_factions"):
		_log("i_factions", await _i_factions())
	if _want("j_perf"):
		_log("j_perf", await _j_perf())
	await _fresh()
	TimeCompression.reset()
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	await _seconds(0.5)
	_finish()


func _want(n: String) -> bool:
	return only.is_empty() or only.has(n)


# --- Helpers --------------------------------------------------------------------------------

## Back to a known state: test units gone, no contacts or reports in flight, no operations of
## the AI factions, decisions paused, runtime tables empty.
func _fresh() -> void:
	await _clear()
	for op: OperationState in war.active_operations():
		ws.cancel(op.id, "test reset")
	for sq: SquadState in demo.sim.state.all_squads():
		if _stations.has(sq.id):
			sq.station_objective = _stations[sq.id]
	war.contacts.clear()
	war.intel_pending.clear()
	ws.intel.rebuild()
	ws.threatened.clear()
	for f: FactionState in war.factions.values():
		f.decisions.clear()
	_pause_ai(true)
	TimeCompression.reset()


func _north() -> int:
	return war.player_faction


func _contacts(f: int) -> Array:
	return ws.intel.contacts_of(f)


## The most confident contact of faction f about enemy faction ef (null: none).
func _contact_about(f: int, ef: int) -> ContactState:
	var best: ContactState = null
	for c: ContactState in _contacts(f):
		if c.enemy_faction == ef and (best == null or c.conf > best.conf):
			best = c
	return best


func _hold(sq: SquadState, hp := 400.0) -> void:
	sq.roe = SquadState.Roe.HOLD_FIRE
	_tough(sq, hp)


func _yaw(a: Vector3, b: Vector3) -> float:
	return _yaw_to(a, b)


func _ridge_stage() -> Dictionary:
	if not stage.is_empty():
		return stage
	var centers: Array[Vector3] = [_obj("Sentrum").position, Vector3.ZERO, _obj("North HQ").position, _obj("East HQ").position, _obj("South HQ").position]
	for c in centers:
		var g := _find_ridge(c)
		if not g.is_empty():
			stage = g
			return stage
	return {}


## Two points 60 to 140 m apart with a ridge or fold between them (neither sees the other).
func _hidden_pair() -> Dictionary:
	var centers: Array[Vector3] = [_obj("Sentrum").position, Vector3.ZERO, _obj("North HQ").position, _obj("East HQ").position, _obj("South HQ").position]
	for center in centers:
		for r: float in [0.0, 400.0, 800.0, 1200.0, 1700.0, 2300.0, 3000.0, 4000.0]:
			var n := 1 if r == 0.0 else 20
			for k in n:
				var a := k * TAU / n + 0.2
				var p := demo.on_ground(center.x + cos(a) * r, center.z + sin(a) * r, 0.0)
				if absf(p.x) > 9200.0 or absf(p.z) > 9200.0 or not _far_from_soldiers(p, 900.0):
					continue
				if _solids(p, 20.0).trees > 0 or not _dry(p, 15.0) or _slope_at(p, 10.0) > 10.0:
					continue
				for j in 12:
					var dir := Vector3(cos(j * TAU / 12.0), 0, sin(j * TAU / 12.0))
					var side := Vector3(-dir.z, 0, dir.x)
					for dist: float in [70.0, 90.0, 110.0, 130.0]:
						var q := demo.on_ground(p.x + dir.x * dist, p.z + dir.z * dist, 0.0)
						if _solids(q, 20.0).trees > 0 or not _dry(q, 15.0) or _slope_at(q, 10.0) > 10.0:
							continue
						var hidden := true
						for off: float in [-12.0, 0.0, 12.0]:
							for off2: float in [-14.0, 0.0, 14.0, 28.0]:
								var e1 := demo.on_ground(p.x + side.x * off, p.z + side.z * off, 1.6)
								var e2 := demo.on_ground(q.x + side.x * off2, q.z + side.z * off2, 1.6)
								if lof.sight(e1, e2).blocker != "terrain":
									hidden = false
						if not hidden:
							continue
						# The two shooting squads (q and 14 m to the side) must see each other.
						var a1 := demo.on_ground(q.x, q.z, 1.6)
						var a2 := demo.on_ground(q.x + side.x * 14.0, q.z + side.z * 14.0, 1.6)
						if lof.sight(a1, a2).visible:
							return {"p": p, "q": q, "dir": dir, "side": side, "dist": dist}
	return {}


func _frame_mid(a: Vector3, b: Vector3, zoom := 150.0) -> void:
	demo.rts_camera.frame(a.lerp(b, 0.5), 0.0, zoom)


func _far_camera() -> void:
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)


## Units listed twice in the world's records or sharing an id with a body that is also a proxy.
func _duplicate_ids() -> int:
	var dup := 0
	for id in demo.sim.state.units:
		if demo.sim.bodies.has(id) and demo.sim.proxies.has(id):
			dup += 1
	return dup


func _any_body(sq: SquadState) -> bool:
	for id in sq.members:
		if _u(id).has_body:
			return true
	return false


## North at p, South hidden at q; South walks to r (in view) and North's faction receives the
## first report. Returns the squads, the contact and the timings, or {} when no contact came.
func _encounter(frame_near := true) -> Dictionary:
	await _fresh()
	var g := _ridge_stage()
	if g.is_empty():
		_expect(false, "no ridge stage found")
		return {}
	var p: Vector3 = g.p
	var q: Vector3 = g.q
	var n := _squad("North-I", _north(), 8, p, _yaw(p, q), 2, 2.2)
	var s := _squad("South-I", 1, 8, q, _yaw(q, p), 2, 2.2)
	_hold(n)
	_hold(s)
	if frame_near:
		_frame_mid(p, q)
	await _seconds(2.0)
	var out := {"n": n, "s": s, "g": g}
	var t_order := demo.sim.state.time
	demo.sim.squads.order_move([s.id], g.r)
	var t_see := -1.0
	var t_contact := -1.0
	var c: ContactState = null
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 60.0:
		await tree.physics_frame
		if t_see < 0.0 and _seeing(_ids(n)) > 0:
			t_see = demo.sim.state.time
		c = _contact_about(_north(), 1)
		if c != null and c.source == ContactState.Source.SEEN:
			t_contact = demo.sim.state.time
			break
	out["c"] = c
	out["t_order"] = t_order
	out["t_see"] = t_see
	out["t_contact"] = t_contact
	return out


# --- Old rule gone ------------------------------------------------------------------------------

## Nothing the strategic path reads is a true position: the old table is gone and threat
## figures come from the faction's contacts only.
func _old_rule() -> Dictionary:
	await _fresh()
	var out := {}
	out["has_known_table"] = "known" in ws
	out["has_old_tunables"] = "intel_m" in ws or "intel_forget_s" in ws
	var f := war.faction(1)
	var hq := war.objective(f.hq_objective)
	# An enemy squad inside the old rule's reach (objective edge + 400 m) but farther than any
	# South soldier can see (400 m): the old table flagged it, nobody has reported it, so the
	# threat estimate must be zero.
	var spot := _near_point(hq.position, _obj("Sentrum").position, hq.radius + 380.0)
	var enemy := _spawn(_north(), spot, 8)
	_hold(enemy)
	await _physics(30)
	out["distance_to_hq_m"] = snappedf(WarSim._flat(enemy_center(enemy), hq.position), 1.0)
	out["threat_near_hq"] = ws.threat_near(1, hq.position, hq.radius + 1200.0)
	out["contacts_south"] = _contacts(1).size()
	_expect(not out.has_known_table and not out.has_old_tunables, "old omniscient intel members still exist")
	_expect(out.threat_near_hq == 0 and out.contacts_south == 0, "South knows of enemies nobody has seen (%s)" % JSON.stringify(out))
	await _fresh()
	return out


func enemy_center(sq: SquadState) -> Vector3:
	return ws.squad_center(sq)


# --- A: initial contact -----------------------------------------------------------------------

func _a_initial() -> Dictionary:
	await _fresh()
	var out := {}
	var g := _ridge_stage()
	_expect(not g.is_empty(), "A: no ridge stage found")
	if g.is_empty():
		return {"found": false}
	var p: Vector3 = g.p
	var q: Vector3 = g.q
	var n := _squad("North-A", _north(), 8, p, _yaw(p, q), 2, 2.2)
	var s := _squad("South-A", 1, 8, q, _yaw(q, p), 2, 2.2)
	_hold(n)
	_hold(s)
	_frame_mid(p, q)
	await _seconds(2.0)
	var pair := _pair_sight(n, s)
	await _run_for(25.0)
	var apart := WarSim._flat(p, q)
	out["geometry"] = {"p": _v(p), "q": _v(q), "distance_m": snappedf(apart, 1.0), "visible_p_q": lof.sight(CombatSim.eye_of(_u(n.members[0])), _u(s.members[0]).position + Vector3.UP * 1.55).visible}
	out["before"] = {"north_contacts": _contacts(_north()).size(), "south_contacts": _contacts(1).size()}
	out["pair_sight"] = pair
	_expect(apart < 400.0 and pair.clear == 0, "A: the squads must be within the old 400 m radius and hidden from each other (%s)" % JSON.stringify(pair))
	_expect(out.before.north_contacts == 0 and out.before.south_contacts == 0, "A: a faction knows the other without having seen it (%s)" % JSON.stringify(out.before))
	await _dbg_map_shot("a1_before_no_contact", p.lerp(q, 0.5), 0.9, _north(), true)
	# South walks into view.
	var t_order := demo.sim.state.time
	demo.sim.squads.order_move([s.id], g.r)
	var t_see := -1.0
	var t_contact := -1.0
	var c: ContactState = null
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 60.0:
		await tree.physics_frame
		if t_see < 0.0 and _seeing(_ids(n)) > 0:
			t_see = demo.sim.state.time
		c = _contact_about(_north(), 1)
		if c != null and c.source == ContactState.Source.SEEN:
			t_contact = demo.sim.state.time
			break
	_expect(c != null, "A: no contact after South came into view")
	if c == null:
		await _fresh()
		return out
	var s_center := ws.squad_center(s)
	out["contact"] = {"id": c.id, "kind": c.kind_name(), "enemy_faction": c.enemy_faction, "source": c.source_name(), "status": c.status_name(),
		"conf": snappedf(c.conf, 0.01), "unc_m": snappedf(c.unc, 0.1), "strength": c.strength, "error_m": snappedf(WarSim._flat(c.pos, s_center), 0.1), "describe": c.describe(demo.sim.state.time)}
	out["timing"] = {"first_seen_s": snappedf(t_see - t_order, 0.1), "contact_s": snappedf(t_contact - t_order, 0.1), "report_delay_s": snappedf(t_contact - t_see, 0.1)}
	_expect(c.enemy_faction == 1 and c.kind == ContactState.Kind.INFANTRY and c.source == ContactState.Source.SEEN, "A: wrong contact %s" % JSON.stringify(out.contact))
	_expect(t_see > 0.0 and t_contact - t_see >= ws.intel.report_delay_s - 0.6, "A: the report arrived without the delay (%s)" % JSON.stringify(out.timing))
	# South sees North back, and the map would show both.
	await _run_for(10.0, func() -> bool: return _contact_about(1, _north()) != null)
	var back := _contact_about(1, _north())
	out["south_sees_north"] = back != null
	_expect(back != null, "A: South does not know about North although North's squad stands in view")
	# The overlay shows it.
	demo.toggle_map()
	var m := demo.strategic_map
	m.dbg_faction = _north()
	m.view_center = Vector2(s_center.x, s_center.z)
	m.zoom = 0.9
	await _frames(6)
	var markers := m.contact_markers()
	out["overlay_markers"] = markers.size()
	_expect(markers.size() >= 1 and markers.any(func(mk: Dictionary) -> bool: return (mk.c as ContactState).id == c.id), "A: the contact is not on the intelligence overlay")
	m.dbg_faction = -1
	demo.toggle_map()
	await _frames(2)
	await _dbg_map_shot("a2_contact_on_overlay", s_center, 0.9, _north(), true)
	await _player_map_shot("a3_player_view_no_dev_overlay", s_center, 0.9)
	# The strategic AI of the observing side can read it (through the same table the decision uses).
	out["threat_near_contact"] = ws.threat_near(_north(), c.pos, 100.0)
	_expect(out.threat_near_contact >= 1, "A: threat_near ignores the fresh contact")
	await _fresh()
	return out


# --- B: lost contact ---------------------------------------------------------------------------

func _b_lost() -> Dictionary:
	var e := await _encounter()
	if e.is_empty() or e.c == null:
		_expect(false, "B: no encounter")
		return {}
	var out := {}
	var n: SquadState = e.n
	var s: SquadState = e.s
	var g: Dictionary = e.g
	var c: ContactState = e.c
	var cid := c.id
	# South walks back behind the ridge.
	demo.sim.squads.order_move([s.id], g.q)
	await _run_for(40.0, func() -> bool: return s.status == SquadState.Status.DONE)
	await _run_for(8.0)
	var pos0 := c.pos
	var t_seen0 := c.t_seen
	var conf1 := c.conf
	var unc1 := c.unc
	var truth := ws.squad_center(s)
	out["left"] = {"contact_id": cid, "reported_at": _v(pos0), "south_now": _v(truth), "distance_belief_to_truth_m": snappedf(WarSim._flat(pos0, truth), 1.0),
		"walked_m": g.step, "status": c.status_name(), "conf": snappedf(conf1, 0.01), "unc_m": snappedf(unc1, 0.1)}
	_expect(WarSim._flat(pos0, truth) >= minf(20.0, g.step * 0.5), "B: South did not leave the reported spot (precondition) %s" % JSON.stringify(out.left))
	await _dbg_map_shot("b1_south_hidden_contact_reported", pos0.lerp(truth, 0.5), 1.1, _north(), true)
	await _warp(60.0, 8.0)
	var cc := ws.intel.get_contact(_north(), cid)
	_expect(cc != null, "B: the contact vanished after 60 s")
	if cc == null:
		await _fresh()
		return out
	out["after_60s"] = {"pos_moved_m": snappedf(WarSim._flat(cc.pos, pos0), 0.1), "belief_to_truth_m": snappedf(WarSim._flat(cc.pos, ws.squad_center(s)), 1.0),
		"conf": snappedf(cc.conf, 0.01), "unc_m": snappedf(cc.unc, 0.1), "status": cc.status_name(), "t_seen_changed": cc.t_seen != t_seen0}
	_expect(WarSim._flat(cc.pos, pos0) < 1.0 and cc.t_seen == t_seen0, "B: the contact moved or was refreshed while nobody observed (%s)" % JSON.stringify(out.after_60s))
	_expect(cc.conf < conf1 - 0.15 and cc.unc > unc1 + 30.0, "B: confidence did not fall / uncertainty did not grow (%s vs %s)" % [JSON.stringify(out.left), JSON.stringify(out.after_60s)])
	_expect(cc.status == ContactState.Status.REPORTED or cc.status == ContactState.Status.STALE, "B: status after 60 s should be reported or stale, is %s" % cc.status_name())
	await _dbg_map_shot("b2_contact_aging", pos0.lerp(truth, 0.5), 1.1, _north(), true)
	await _warp(60.0, 8.0)
	out["after_120s"] = {"conf": snappedf(cc.conf, 0.01), "unc_m": snappedf(cc.unc, 0.1), "status": cc.status_name()}
	_expect(cc.status == ContactState.Status.STALE, "B: status after 120 s should be stale, is %s" % cc.status_name())
	await _dbg_map_shot("b3_contact_stale", pos0.lerp(truth, 0.5), 1.1, _north(), true)
	await _warp(110.0, 8.0)
	out["after_230s"] = {"still_held": ws.intel.get_contact(_north(), cid) != null, "contacts": _contacts(_north()).size()}
	_expect(not out.after_230s.still_held, "B: the contact was never dropped")
	out["north_alive"] = _alive(n)
	await _fresh()
	return out


# --- C: reacquisition --------------------------------------------------------------------------

func _c_reacquire() -> Dictionary:
	var e := await _encounter()
	if e.is_empty() or e.c == null:
		_expect(false, "C: no encounter")
		return {}
	var out := {}
	var s: SquadState = e.s
	var g: Dictionary = e.g
	var cid: int = e.c.id
	demo.sim.squads.order_move([s.id], g.q)
	await _run_for(40.0, func() -> bool: return s.status == SquadState.Status.DONE)
	await _warp(100.0, 8.0)
	var c := ws.intel.get_contact(_north(), cid)
	_expect(c != null, "C: contact dropped before the reacquisition test")
	if c == null:
		await _fresh()
		return out
	var pos_old := c.pos
	out["before"] = {"id": cid, "status": c.status_name(), "conf": snappedf(c.conf, 0.01), "unc_m": snappedf(c.unc, 0.1), "t_seen_age_s": snappedf(demo.sim.state.time - c.t_seen, 0.1)}
	_expect(c.status == ContactState.Status.STALE or c.status == ContactState.Status.REPORTED, "C: the contact should be old (%s)" % JSON.stringify(out.before))
	# South comes back into view at a different spot of the visible side.
	var back_to: Vector3 = g.r + Vector3(g.dir.z, 0, -g.dir.x) * 6.0
	demo.sim.squads.order_move([s.id], back_to)
	var t0 := demo.sim.state.time
	await _run_for(60.0, func() -> bool:
		var cc := ws.intel.get_contact(_north(), cid)
		return cc != null and cc.status == ContactState.Status.OBSERVED)
	var c2 := ws.intel.get_contact(_north(), cid)
	var about := _contacts(_north()).filter(func(x: ContactState) -> bool: return x.enemy_faction == 1)
	out["after"] = {"same_contact": c2 != null, "contacts_about_south": about.size(), "status": c2.status_name() if c2 else "-", "conf": snappedf(c2.conf, 0.01) if c2 else 0.0,
		"unc_m": snappedf(c2.unc, 0.1) if c2 else 0.0, "moved_m": snappedf(WarSim._flat(c2.pos, pos_old), 1.0) if c2 else 0.0,
		"error_to_truth_m": snappedf(WarSim._flat(c2.pos, ws.squad_center(s)), 1.0) if c2 else 0.0, "took_s": snappedf(demo.sim.state.time - t0, 0.1)}
	_expect(c2 != null and c2.status == ContactState.Status.OBSERVED, "C: South was not reacquired (%s)" % JSON.stringify(out.after))
	if c2:
		_expect(about.size() == 1, "C: reacquisition created a duplicate (%d contacts about South)" % about.size())
		_expect(c2.conf >= 0.9 and WarSim._flat(c2.pos, ws.squad_center(s)) < 60.0, "C: the updated contact is not accurate / confident (%s)" % JSON.stringify(out.after))
		await _dbg_map_shot("c1_reacquired", c2.pos, 1.1, _north(), true)
	await _fresh()
	return out


# --- D: hearing without sight ----------------------------------------------------------------

func _d_hearing() -> Dictionary:
	await _fresh()
	var g := _hidden_pair()
	_expect(not g.is_empty(), "D: no hidden pair of points 70-130 m apart found")
	if g.is_empty():
		return {"found": false}
	var p: Vector3 = g.p
	var q: Vector3 = g.q
	var n := _squad("North-D", _north(), 8, p, _yaw(p, q), 2, 2.2)
	_hold(n)
	# South and East shoot at each other beyond the fold; North listens.
	var s := _squad("South-D", 1, 8, q, _yaw(q, q + g.side), 2, 2.2)
	var east_at := demo.on_ground(q.x + g.side.x * 14.0, q.z + g.side.z * 14.0, 0.3)
	var ea := _squad("East-D", 2, 8, east_at, _yaw(east_at, q), 2, 2.2)
	_tough(s, 2000.0)
	_tough(ea, 2000.0)
	_frame_mid(p, q, 130.0)
	await _seconds(2.0)
	var t0 := demo.sim.state.time
	await _run_for(40.0, func() -> bool: return not _contacts(_north()).is_empty())
	await _run_for(10.0)
	var shooters := ws.squad_center(s).lerp(ws.squad_center(ea), 0.5)
	var north_c := _contacts(_north())
	var out := {"geometry": {"p": _v(p), "q": _v(q), "dist_m": g.dist, "se_sight": _pair_sight(s, ea), "s_states": _ids(s).map(func(id: int) -> String: return "%d/%d/%s" % [_u(id).ai_state, _u(id).target_id, _u(id).ai_reason]),
		"e_states": _ids(ea).map(func(id: int) -> String: return "%d/%d/%s" % [_u(id).ai_state, _u(id).target_id, _u(id).ai_reason])}, "shots": _shots_of(1, t0) + _shots_of(2, t0), "north_contacts": north_c.size(),
		"north_seeing": _seeing(_ids(n)), "describe": north_c.map(func(x: ContactState) -> String: return x.describe(demo.sim.state.time))}
	_expect(out.shots > 0, "D: nobody fired (precondition)")
	_expect(north_c.size() >= 1, "D: North heard nothing (%s)" % JSON.stringify(out.geometry))
	for c: ContactState in north_c:
		_expect(c.source == ContactState.Source.HEARD, "D: a contact that is not a sound report: %s" % c.describe(demo.sim.state.time))
		_expect(c.enemy_faction == -1 and c.kind == ContactState.Kind.UNKNOWN, "D: a heard contact identifies the enemy: %s" % c.describe(demo.sim.state.time))
		_expect(c.unc0 >= 40.0 and c.conf0 < 0.5, "D: a heard contact is too certain: %s" % c.describe(demo.sim.state.time))
	if not north_c.is_empty():
		var c: ContactState = north_c[0]
		var err := WarSim._flat(c.pos, shooters)
		out["position_error_m"] = snappedf(err, 1.0)
		out["unc_m"] = snappedf(c.unc, 1.0)
		_expect(err > 1.0 and err < c.unc0 + 100.0, "D: the reported position is exact or absurd (%.1f m off, uncertainty %.0f)" % [err, c.unc0])
	_expect(out.north_seeing == 0, "D: North sees the shooters (precondition: no line of sight)")
	await _dbg_map_shot("d1_heard_contact", shooters, 1.2, _north(), true)
	await _fresh()
	return out


# --- E: near / far ---------------------------------------------------------------------------

func _e_tiers() -> Dictionary:
	var e := await _encounter(true)
	if e.is_empty() or e.c == null:
		_expect(false, "E: no encounter")
		return {}
	var out := {}
	var n: SquadState = e.n
	var s: SquadState = e.s
	var g: Dictionary = e.g
	var latency_near: float = e.t_contact - e.t_order
	var cid: int = e.c.id
	var members0 := n.members.size() + s.members.size()
	# Near: South hidden again, nothing refreshes it.
	demo.sim.squads.order_move([s.id], g.q)
	await _run_for(40.0, func() -> bool: return s.status == SquadState.Status.DONE)
	await _run_for(6.0)
	var c := ws.intel.get_contact(_north(), cid)
	var seen_near := c.t_seen
	var pos_near := c.pos
	await _run_for(25.0)
	out["near_hidden"] = {"t_seen_unchanged": c.t_seen == seen_near, "pos_unchanged": WarSim._flat(c.pos, pos_near) < 0.5, "bodies": _any_body(n)}
	_expect(out.near_hidden.t_seen_unchanged and out.near_hidden.pos_unchanged and out.near_hidden.bodies, "E: near tier, hidden: %s" % JSON.stringify(out.near_hidden))
	# Far: the camera leaves, both squads become abstract.
	_far_camera()
	await _seconds(3.0)
	var abstract_ok := not _any_body(n) and not _any_body(s)
	var seen_far := c.t_seen
	var pos_far := c.pos
	await _run_for(25.0)
	out["far_hidden"] = {"abstract": abstract_ok, "same_id": ws.intel.get_contact(_north(), cid) == c, "t_seen_unchanged": c.t_seen == seen_far, "pos_unchanged": WarSim._flat(c.pos, pos_far) < 0.5,
		"contacts_about_south": _contacts(_north()).filter(func(x: ContactState) -> bool: return x.enemy_faction == 1).size()}
	_expect(abstract_ok and out.far_hidden.same_id and out.far_hidden.t_seen_unchanged and out.far_hidden.pos_unchanged and out.far_hidden.contacts_about_south == 1, "E: far tier, hidden: %s" % JSON.stringify(out.far_hidden))
	# Far, South walks into view: detection works without any body.
	var t_order := demo.sim.state.time
	demo.sim.squads.order_move([s.id], g.r)
	await _run_for(60.0, func() -> bool: return c.t_seen > t_order and c.status == ContactState.Status.OBSERVED)
	var latency_far := c.t_seen - t_order
	out["far_seen"] = {"observed": c.status == ContactState.Status.OBSERVED, "latency_far_s": snappedf(latency_far, 0.1), "latency_near_s": snappedf(latency_near, 0.1), "bodies": _any_body(n), "same_id": ws.intel.get_contact(_north(), cid) == c}
	_expect(c.status == ContactState.Status.OBSERVED and not out.far_seen.bodies, "E: the distant squad did not detect South (%s)" % JSON.stringify(out.far_seen))
	_expect(absf(latency_far - (latency_near - ws.intel.report_delay_s)) < 14.0, "E: detection latency differs between tiers (near %.1f far %.1f)" % [latency_near, latency_far])
	# Back near: still one contact, no new units.
	demo.rts_camera.frame(g.p.lerp(g.q, 0.5), 0.0, 140.0)
	await _seconds(4.0)
	out["back_near"] = {"bodies": _any_body(n), "same_id": ws.intel.get_contact(_north(), cid) == c, "contacts": _contacts(_north()).size(),
		"members_before": members0, "members_after": n.members.size() + s.members.size(), "duplicate_ids": _duplicate_ids()}
	_expect(out.back_near.bodies and out.back_near.same_id and out.back_near.contacts == 1 and members0 == out.back_near.members_after and out.back_near.duplicate_ids == 0, "E: after the camera returned: %s" % JSON.stringify(out.back_near))
	await _fresh()
	return out


# --- F: save / load ---------------------------------------------------------------------------

func _contact_sig() -> Dictionary:
	var s := {}
	for f in war.contacts:
		for c: ContactState in war.contacts[f].values():
			s["c%d" % c.id] = "%d|%d|%d|%d|%s|%.2f|%.3f|%.2f|%.3f|%.1f|%d|%s|%s|%.2f|%d" % [c.faction, c.enemy_faction, c.kind, c.source, str(c.pos), c.t_seen, c.conf0, c.unc0,
				c.t_first, c.t_report, c.strength, str(Array(c.ids)), str(Array(c.ids_t)), c.investigated_until, c.reports]
	s["next"] = war.next_contact_id
	s["pending"] = JSON.stringify(war.intel_pending.map(func(r: Dictionary) -> String: return "%s|%s|%s|%s" % [r.f, r.src, r.p, r.due]))
	return s


func _f_persist() -> Dictionary:
	await _fresh()
	var out := {}
	var site := _near_point(_obj("Sentrum").position, _obj("North HQ").position, 700.0)
	if not _far_from_soldiers(site, 500.0):
		site = _near_point(_obj("Sentrum").position, _obj("East HQ").position, 1400.0)
	var n := _squad("North-F", _north(), 8, site, 0.0)
	var s1 := _squad("South-F1", 1, 8, site + Vector3(700, 0, 0), 0.0)
	var s2 := _squad("South-F2", 1, 8, site + Vector3(-900, 0, 60), 0.0)
	var e1 := _squad("East-F", 2, 8, site + Vector3(60, 0, -1100), 0.0)
	for sq: SquadState in [n, s1, s2, e1]:
		_hold(sq)
	_frame_mid(site, site)
	await _seconds(2.0)
	var me: UnitState = _u(n.members[0])
	var intel := ws.intel
	# Reports of every kind and age, through the same entry points CombatBrain uses.
	intel.report_seen(me, _u(s1.members[0]))
	await _warp(20.0, 8.0)
	intel.report_heard(_u(n.members[1]), ws.squad_center(s2), 90.0)
	await _warp(40.0, 8.0)
	intel.report_fire(_u(n.members[2]), ws.squad_center(e1))
	await _warp(8.0, 8.0)
	intel.report_objective(_north(), 1, _obj("Sentrum"), 5)
	await _warp(8.0, 8.0)
	intel.report_seen(_u(n.members[3]), _u(e1.members[0]))   # still in flight when saved
	_expect(not war.intel_pending.is_empty(), "F: nothing in flight at the time of the save (precondition)")
	var now := demo.sim.state.time
	var ages := _contacts(_north()).map(func(c: ContactState) -> float: return snappedf(now - c.t_seen, 1.0))
	out["before"] = {"contacts": _contacts(_north()).size(), "ages_s": ages, "kinds": _contacts(_north()).map(func(c: ContactState) -> String: return c.source_name()),
		"conf": _contacts(_north()).map(func(c: ContactState) -> float: return snappedf(c.conf, 0.01)), "pending": war.intel_pending.size()}
	_expect(out.before.contacts >= 3, "F: too few contacts to test persistence (%s)" % JSON.stringify(out.before))
	var saved := {}
	var restored := {}
	var on_save := func() -> void: saved.merge(_contact_sig(), true)
	demo.sim.state.saving.connect(on_save)
	_press(KEY_F5)
	await _frames(2)
	demo.sim.state.saving.disconnect(on_save)
	_expect(not saved.is_empty(), "F: F5 did not save")
	var t_save := demo.sim.state.time
	await _warp(30.0, 8.0)
	var n_before_load := _contacts(_north()).size()
	var on_restore := func() -> void: restored.merge(_contact_sig(), true)
	demo.sim.state.restored.connect(on_restore)
	_press(KEY_F9)
	await _frames(2)
	demo.sim.state.restored.disconnect(on_restore)
	var diff := []
	for k in saved:
		if saved[k] != restored.get(k):
			diff.append({"key": k, "saved": saved[k], "loaded": restored.get(k)})
	for k in restored:
		if not saved.has(k):
			diff.append({"key": k, "extra": restored[k]})
	out["load"] = {"keys": saved.size(), "differences": diff.slice(0, 4), "difference_count": diff.size(), "state_time_back_to_save_s": snappedf(demo.sim.state.time - t_save, 0.5), "contacts_changed_by_ageing": n_before_load}
	_expect(diff.is_empty(), "F: save / load changed the intelligence (%s)" % JSON.stringify(out.load.differences))
	# Time resumes from the saved ageing: nothing was refreshed by the load, the pending report arrives once.
	var ids_after := _contacts(_north()).map(func(c: ContactState) -> int: return c.id)
	var before_state := {}
	for c: ContactState in _contacts(_north()):
		before_state[c.id] = [c.t_seen, c.reports]
	var pending_at_load := war.intel_pending.size()
	await _warp(8.0, 8.0)
	var coherent := true
	var detail := []
	var reported_again := 0
	for c: ContactState in _contacts(_north()):
		if before_state.has(c.id):
			if c.reports != before_state[c.id][1]:
				reported_again += 1   # the report that was in flight at the save reached this one
				continue
			var expect_conf := c.conf0 * exp(-(demo.sim.state.time - c.t_seen) / IntelSim.TAU[c.source])
			if c.t_seen != before_state[c.id][0] or absf(c.conf - expect_conf) > 0.02:
				coherent = false
				detail.append(c.describe(demo.sim.state.time))
	var created_new := _contacts(_north()).filter(func(c: ContactState) -> bool: return not before_state.has(c.id)).size()
	out["resume"] = {"ids_after_load": ids_after, "coherent": coherent, "detail": detail, "pending_at_load": pending_at_load, "pending_now": war.intel_pending.size(),
		"in_flight_report_applied_once": reported_again + created_new}
	_expect(coherent, "F: contacts refreshed or inconsistent after the load (%s)" % JSON.stringify(detail))
	_expect(pending_at_load >= 1 and war.intel_pending.is_empty() and reported_again + created_new == 1, "F: the report in flight at the save was not applied exactly once (%s)" % JSON.stringify(out.resume))
	# No duplicates: the same unit reported again joins its contact (found through the unit index).
	var s1u: UnitState = _u(s1.members[1])
	intel._next_seen.clear()
	intel.report_seen(_u(n.members[0]), s1u)
	await _warp(5.0, 8.0)
	var count0 := _contacts(_north()).size()
	var tracked_before: int = intel._by_unit.get(_north(), {}).get(s1u.id, -1)
	var s1_c := intel.get_contact(_north(), tracked_before)
	var reports0 := s1_c.reports if s1_c else -1
	intel._next_seen.clear()
	intel.report_seen(_u(n.members[0]), s1u)
	await _warp(5.0, 8.0)
	var tracked_after: int = intel._by_unit.get(_north(), {}).get(s1u.id, -1)
	var s1_c2 := intel.get_contact(_north(), tracked_after)
	out["no_duplicate"] = {"count_before": count0, "count_after": _contacts(_north()).size(), "tracked_contact_before": tracked_before, "tracked_contact_after": tracked_after,
		"reports": [reports0, s1_c2.reports if s1_c2 else -1]}
	_expect(s1_c != null and tracked_before == tracked_after and _contacts(_north()).size() == count0 and s1_c2 != null and s1_c2.reports == reports0 + 1, "F: a duplicate contact or a lost identity after the load (%s)" % JSON.stringify(out.no_duplicate))
	# The strategic reading resumes from the restored picture.
	if s1_c2:
		out["threat_after_load"] = ws.threat_near(_north(), s1_c2.pos, 100.0)
		_expect(out.threat_after_load >= 1, "F: threat_near does not see the restored contact")
	await _fresh()
	return out


# --- G: strategic behaviour --------------------------------------------------------------------

## A site beside South's Verket garrison from which the garrison can see an enemy squad.
func _verket_site() -> Dictionary:
	var o := _obj("Verket")
	var garrison: SquadState = null
	for sq in ws.squads_of(1):
		if sq.station_objective == o.id:
			garrison = sq
	if garrison == null:
		garrison = _spawn(1, o.position, 8)
		garrison.station_objective = o.id
	var eye := CombatSim.eye_of(_u(garrison.members[0]))
	for dist: float in [220.0, 260.0, 180.0, 300.0]:
		for k in 24:
			var a := k * TAU / 24.0
			var p := demo.on_ground(o.position.x + cos(a) * dist, o.position.z + sin(a) * dist, 0.0)
			if not ws.routes.passable(p) or not _dry(p, 12.0) or _solids(p, 14.0).trees > 0:
				continue
			if lof.sight(eye, p + Vector3.UP * 1.55).visible:
				return {"obj": o, "garrison": garrison, "enemy_at": p, "dir": Vector3(cos(a), 0, sin(a)), "dist": dist}
	return {}


func _g_strategy() -> Dictionary:
	await _fresh()
	var out := {}
	var site := _verket_site()
	_expect(not site.is_empty(), "G: no site in view of the Verket garrison")
	if site.is_empty():
		return {"found": false}
	var o: ObjectiveState = site.obj
	var garrison: SquadState = site.garrison
	garrison.roe = SquadState.Roe.HOLD_FIRE
	_tough(garrison, 3000.0)
	var south := war.faction(1)
	south.recovery_until = demo.sim.state.time + 1.0e6   # no new attack: the test is about the threat response
	# Free reinforcements exist, away from the enemy.
	var hq := war.objective(south.hq_objective)
	var spare := _spawn(1, _near_point(hq.position, o.position, hq.radius * 0.5 + 40.0), 8)
	var spare2 := _spawn(1, _near_point(hq.position, o.position, hq.radius * 0.5 + 80.0), 8)
	var enemies: Array[SquadState] = []
	for k in 3:
		var e := _squad("North-G%d" % k, _north(), 8, site.enemy_at + site.dir.rotated(Vector3.UP, PI * 0.5) * (k * 22.0 - 22.0), _yaw(site.enemy_at, o.position))
		_hold(e, 3000.0)
		enemies.append(e)
	demo.rts_camera.frame(o.position.lerp(site.enemy_at, 0.5), 0.0, 170.0)
	var t0 := demo.sim.state.time
	await _run_for(40.0, func() -> bool: return ws.threat_near(1, o.position, o.radius + 700.0) >= 12)
	var threat := ws.threat_near(1, o.position, o.radius + 700.0)
	out["picture"] = {"threat_near_verket": threat, "contacts": _contacts(1).map(func(c: ContactState) -> String: return c.describe(demo.sim.state.time)), "true_enemies": 24,
		"delay_s": snappedf(demo.sim.state.time - t0, 0.1)}
	_expect(threat >= 12, "G: South's picture of 24 visible enemies is too weak (%s)" % JSON.stringify(out.picture))
	# South decides now (its natural cadence, triggered at once).
	south.next_decision_at = demo.sim.state.time + 0.5
	await _run_for(5.0, func() -> bool: return not south.decisions.is_empty())
	_expect(not south.decisions.is_empty(), "G: South made no decision")
	if south.decisions.is_empty():
		await _fresh()
		return out
	var d: Dictionary = south.decisions.back()
	var ops := war.active_operations(1).filter(func(op: OperationState) -> bool: return op.type == OperationState.Type.REINFORCE and op.target_objective == o.id)
	out["decision"] = {"notes": d.notes, "threats": d.threats, "reinforce_ops": ops.map(func(op: OperationState) -> String: return "#%d %s" % [op.id, op.reason])}
	_expect(not d.threats.is_empty() and ops.size() >= 1, "G: South did not reinforce Verket (%s)" % JSON.stringify(out.decision))
	_expect(ops.size() >= 1 and ops[0].reason.contains("reported"), "G: the operation does not say why (%s)" % [ops[0].reason if ops.size() >= 1 else ""])
	var lines := ws.explain_faction(south)
	out["explained"] = lines
	_expect(lines.any(func(l: String) -> bool: return l.contains("Verket")), "G: the inspector does not mention the threat")
	await _dbg_map_shot("g1_south_reinforces_verket", o.position.lerp(site.enemy_at, 0.5), 0.5, 1, true)
	# Stale intelligence eventually changes the picture: the enemy leaves (is removed from view).
	for e in enemies:
		demo.sim.squads.order_move([e.id], site.enemy_at + site.dir * 900.0)
	await _warp(130.0, 8.0)
	var later := ws.threat_near(1, o.position, o.radius + 700.0)
	out["later"] = {"threat_after_130s": later, "contacts": _contacts(1).size()}
	_expect(later < threat, "G: the threat estimate did not fall as the reports aged (%d -> %d)" % [threat, later])
	await _fresh()
	return out


# --- K: investigation of a stale report -------------------------------------------------------

func _k_investigate() -> Dictionary:
	await _fresh()
	var out := {}
	var site := _verket_site()
	_expect(not site.is_empty(), "K: no site in view of the Verket garrison")
	if site.is_empty():
		return {"found": false}
	var o: ObjectiveState = site.obj
	var garrison: SquadState = site.garrison
	garrison.roe = SquadState.Roe.HOLD_FIRE
	_tough(garrison, 3000.0)
	var south := war.faction(1)
	south.recovery_until = demo.sim.state.time + 1.0e6
	var away: Vector3 = -site.dir
	var free_at := _near_point(o.position, o.position + away * 500.0, 330.0)
	var free := _spawn(1, free_at, 8)
	free.roe = SquadState.Roe.HOLD_FIRE
	var intruder := _squad("North-K", _north(), 8, site.enemy_at, _yaw(site.enemy_at, o.position))
	_hold(intruder, 3000.0)
	demo.rts_camera.frame(o.position.lerp(site.enemy_at, 0.5), 0.0, 170.0)
	await _run_for(40.0, func() -> bool: return _contact_about(1, _north()) != null)
	var c := _contact_about(1, _north())
	_expect(c != null, "K: South never saw the intruder")
	if c == null:
		await _fresh()
		return out
	await _dbg_map_shot("k1_intruder_seen", o.position.lerp(site.enemy_at, 0.5), 0.6, 1, true)
	# The intruder walks away out of sight (beyond 400 m).
	var away_to: Vector3 = site.enemy_at + site.dir * 1100.0
	demo.sim.squads.order_move([intruder.id], away_to)
	await _run_for(240.0, func() -> bool: return WarSim._flat(ws.squad_center(intruder), o.position) > 620.0)
	await _warp(15.0, 8.0)
	var cid := c.id
	var pos_reported := c.pos
	out["belief"] = {"contact_id": cid, "status": c.status_name(), "reported_at": _v(pos_reported), "intruder_now": _v(ws.squad_center(intruder)),
		"distance_belief_truth_m": snappedf(WarSim._flat(pos_reported, ws.squad_center(intruder)), 1.0)}
	_expect(c.status != ContactState.Status.OBSERVED and WarSim._flat(pos_reported, ws.squad_center(intruder)) > 150.0, "K: the intruder is still in view (precondition) %s" % JSON.stringify(out.belief))
	# South decides: one free squad goes to the reported position, not to the intruder.
	south.next_decision_at = demo.sim.state.time + 0.5
	await _run_for(6.0, func() -> bool: return war.active_operations(1).any(func(op: OperationState) -> bool: return op.contact_id == cid))
	var ops := war.active_operations(1).filter(func(op: OperationState) -> bool: return op.contact_id == cid)
	_expect(ops.size() == 1, "K: South did not investigate the contact (%s)" % south.last_decision)
	if ops.is_empty():
		await _fresh()
		return out
	var op: OperationState = ops[0]
	var sent: SquadState = demo.sim.state.get_squad(op.squads[0])
	out["op"] = {"id": op.id, "type": op.type_name(), "target": _v(op.target_pos), "to_report_m": snappedf(WarSim._flat(op.target_pos, pos_reported), 1.0),
		"to_truth_m": snappedf(WarSim._flat(op.target_pos, ws.squad_center(intruder)), 1.0), "reason": op.reason, "squad": sent.squad_name, "stationed_at_verket_before": sent.id == garrison.id,
		"squad_to_report_m": snappedf(WarSim._flat(ws.squad_center(sent), pos_reported), 1.0)}
	_expect(WarSim._flat(op.target_pos, pos_reported) < 2.0 and WarSim._flat(op.target_pos, ws.squad_center(intruder)) > 100.0, "K: the squad was sent to the true position, not the reported one (%s)" % JSON.stringify(out.op))
	_expect(sent.faction == 1 and sent.op_id == op.id, "K: the investigating squad is not South's")
	var insp := ws.explain_squad(sent)
	out["inspector"] = insp
	_expect(insp.any(func(l: String) -> bool: return l.contains("investigate")), "K: the squad inspector does not state the reason")
	await _dbg_map_shot("k2_south_investigates", pos_reported.lerp(o.position, 0.5), 0.55, 1, true)
	await _run_for(240.0, func() -> bool: return not op.is_active())
	out["result"] = {"op_phase": op.phase_name(), "outcome": op.outcome, "contact_conf_now": snappedf(c.conf, 0.01) if ws.intel.get_contact(1, cid) else -1.0}
	_expect(not op.is_active() and op.outcome.contains("nothing found"), "K: the investigation did not end with 'nothing found' (%s)" % JSON.stringify(out.result))
	var after := ws.intel.get_contact(1, cid)
	_expect(after == null or after.conf < 0.3, "K: the faction still believes the checked report")
	# The inspector explains the decision.
	out["faction_lines"] = ws.explain_faction(south).slice(0, 6)
	await _dbg_map_shot("k3_after_investigation", pos_reported.lerp(o.position, 0.5), 0.55, 1, true)
	await _fresh()
	return out


# --- H: player authority ----------------------------------------------------------------------

func _h_player() -> Dictionary:
	await _fresh()
	var out := {}
	var g := _ridge_stage()
	_expect(not g.is_empty(), "H: no stage")
	if g.is_empty():
		return {"found": false}
	var p: Vector3 = g.p
	var r: Vector3 = g.r
	var n := _squad("North-H", _north(), 8, p, _yaw(p, r))
	var s := _squad("South-H", 1, 8, r, _yaw(r, p))
	_tough(n, 3000.0)
	_hold(s, 3000.0)   # South does not shoot; North may defend itself
	_frame_mid(p, r)
	await _seconds(2.0)
	await _run_for(30.0, func() -> bool: return _contact_about(_north(), 1) != null and _seeing(_ids(n)) > 0)
	_expect(_contact_about(_north(), 1) != null, "H: North has no contact (precondition)")
	# The player orders North elsewhere, away from the enemy.
	var away := demo.on_ground(p.x - (r.x - p.x) * 0.5, p.z - (r.z - p.z) * 0.5, 0.0)
	var target := _near_point(p, away, 60.0)
	ws.release_squads([n.id], "player order")
	demo.sim.squads.order_move([n.id], target)
	var engaged_max := 0
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 14.0:
		await tree.physics_frame
		engaged_max = maxi(engaged_max, _seeing(_ids(n)))
	out["order"] = {"order": n.order_name(), "target_kept": WarSim._flat(n.order_target, target) < 5.0, "op_id": n.op_id, "moved_toward_target_m": snappedf(WarSim._flat(p, target) - WarSim._flat(ws.squad_center(n), target), 1.0),
		"ops_of_player": war.active_operations(_north()).size(), "player_decisions": war.faction(_north()).decisions.size(), "soldiers_seeing_enemy": engaged_max}
	_expect(n.order == SquadState.Order.MOVE and out.order.target_kept and n.op_id == -1, "H: the intelligence system changed the player's order (%s)" % JSON.stringify(out.order))
	_expect(out.order.ops_of_player == 0 and out.order.player_decisions == 0, "H: the player's faction got AI operations or decisions")
	_expect(out.order.moved_toward_target_m > 5.0, "H: the squad did not carry out the order (%s)" % JSON.stringify(out.order))
	_expect(engaged_max > 0, "H: the soldiers stopped perceiving the enemy they could see")
	# The inspector tells the truth about who commands the squad.
	var lines := ws.explain_squad(n)
	out["inspector"] = lines
	_expect(lines.any(func(l: String) -> bool: return l.contains("player")), "H: the inspector does not say the player commands the squad")
	await _fresh()
	return out


# --- I: several factions ----------------------------------------------------------------------

func _i_factions() -> Dictionary:
	await _fresh()
	var out := {}
	var g := _ridge_stage()
	_expect(not g.is_empty(), "I: no stage")
	if g.is_empty():
		return {"found": false}
	var p: Vector3 = g.p
	var q: Vector3 = g.q
	var r: Vector3 = g.r
	var n := _squad("North-X", _north(), 8, p, _yaw(p, r), 2, 2.2)
	var s := _squad("South-X", 1, 8, r, _yaw(r, q), 2, 2.2)   # looks towards East, with North behind it
	var e := _squad("East-X", 2, 8, q, _yaw(q, r), 2, 2.2)
	for sq: SquadState in [n, s, e]:
		_hold(sq, 3000.0)
	_frame_mid(p, q)
	await _seconds(2.0)
	await _run_for(45.0, func() -> bool: return _contact_about(_north(), 1) != null and _contact_about(1, 2) != null and _contact_about(2, 1) != null)
	await _run_for(5.0)
	var north_about := _contacts(0).map(func(c: ContactState) -> int: return c.enemy_faction)
	var south_about := _contacts(1).map(func(c: ContactState) -> int: return c.enemy_faction)
	var east_about := _contacts(2).map(func(c: ContactState) -> int: return c.enemy_faction)
	out["tables"] = {"north_knows": north_about, "south_knows": south_about, "east_knows": east_about}
	_expect(north_about.has(1) and not north_about.has(2), "I: North's picture is wrong (%s)" % JSON.stringify(out.tables))
	_expect(south_about.has(2) , "I: South's picture is wrong (%s)" % JSON.stringify(out.tables))
	_expect(east_about.has(1) and not east_about.has(0), "I: East inherited North's knowledge (%s)" % JSON.stringify(out.tables))
	# Structural: every contact sits in its own faction's table, names only enemy units, ids unique.
	var seen_ids := {}
	var bad := []
	for f in war.contacts:
		for c: ContactState in war.contacts[f].values():
			if c.faction != f or seen_ids.has(c.id):
				bad.append("misfiled #%d" % c.id)
			seen_ids[c.id] = true
			for uid in c.ids:
				var u := _u(uid)
				if u == null or u.faction == f or (c.enemy_faction >= 0 and u.faction != c.enemy_faction):
					bad.append("#%d names unit %d of the wrong faction" % [c.id, uid])
	out["structure_problems"] = bad
	_expect(bad.is_empty(), "I: contact tables are inconsistent (%s)" % JSON.stringify(bad))
	await _dbg_map_shot("i1_three_factions_north_view", q.lerp(r, 0.5), 1.0, _north(), true)
	await _dbg_map_shot("i2_three_factions_south_view", q.lerp(r, 0.5), 1.0, 1, true)
	await _fresh()
	return out


# --- J: performance ---------------------------------------------------------------------------

func _j_perf() -> Dictionary:
	await _fresh()
	var out := {}
	var center := _find_far("meadow", _obj("Sentrum").position, 1000.0)
	_expect(center.is_finite(), "J: no open meadow found")
	if not center.is_finite():
		return {"found": false}
	area = center
	demo.rts_camera.frame(center, 0.0, 130.0)
	await _seconds(2.0)
	out["baseline"] = await _measure_fight(6.0)
	var i0 := ws.intel.stats()
	var u0 := ws.intel.report_usec + ws.intel.group_usec
	var sw0 := ws.intel.usec
	ws.intel.usec_max = 0
	var m := await _perf_case("64v64 open RTS", center, 64, Vector3(0, 0, 1), 60.0, false)
	var i1 := ws.intel.stats()
	var calls_us := ws.intel.report_usec + ws.intel.group_usec - u0
	out["fight"] = m
	out["intel"] = {"soldiers_total": demo.sim.state.count_of(UnitState.Kind.SOLDIER), "reports_in": i1.reports_in - i0.reports_in, "applied": i1.applied - i0.applied,
		"throttled": i1.throttled - i0.throttled, "dropped": i1.dropped - i0.dropped, "contacts_now": i1.contacts, "created": i1.created - i0.created, "merged": i1.merged - i0.merged,
		"report_calls_us_total": calls_us, "sweep_us_avg": i1.sweep_us_avg, "sweep_us_max": i1.sweep_us_max, "pending_now": i1.pending,
		"max_contacts_per_faction": ws.intel.max_contacts}
	var added_ms: float = m.frame_ms_avg - out.baseline.frame_ms_avg
	var per_frame_us: float = float(calls_us) / maxf(m.frames, 1)
	out["cost"] = {"frame_ms_added_vs_idle": snappedf(added_ms, 0.01), "report_calls_us_per_frame": snappedf(per_frame_us, 0.1), "sweep_us_max": i1.sweep_us_max}
	_expect(per_frame_us < 300.0, "J: report calls cost %.0f us per frame" % per_frame_us)
	_expect(i1.sweep_us_max < 2000, "J: an intelligence sweep took %d us" % i1.sweep_us_max)
	_expect(m.frames_over_33ms == 0 and m.frame_ms_p99 < 33.0, "J: frame spikes in the big fight (%s)" % JSON.stringify({"over33": m.frames_over_33ms, "p99": m.frame_ms_p99}))
	_expect(i1.dropped == i0.dropped, "J: reports were dropped (pending queue overflow)")
	await _fresh()
	return out


# --- Output ----------------------------------------------------------------------------------

## Map screenshot with the developer inspector for faction f (and the true positions).
func _dbg_map_shot(shot_name: String, center: Vector3, zoom: float, f: int, truth: bool) -> void:
	if not shots:
		return
	var m := demo.strategic_map
	var was := m.visible
	if not was:
		demo.toggle_map()
	m.dbg_faction = f
	m.dbg_truth = truth
	m.view_center = Vector2(center.x, center.z)
	m.zoom = zoom
	await _frames(8)
	_shot(shot_name)
	m.dbg_faction = -1
	m.dbg_truth = false
	m.dbg_squad = -1
	if not was:
		demo.toggle_map()
	await _frames(2)


## What the player sees: the normal map, no developer overlay.
func _player_map_shot(shot_name: String, center: Vector3, zoom: float) -> void:
	if not shots:
		return
	var m := demo.strategic_map
	var was := m.visible
	if not was:
		demo.toggle_map()
	m.dbg_faction = -1
	m.dbg_truth = false
	m.view_center = Vector2(center.x, center.z)
	m.zoom = zoom
	await _frames(8)
	_shot(shot_name)
	if not was:
		demo.toggle_map()
	await _frames(2)


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("INTEL %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("INTEL FAILED CHECK: ", msg)


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	_vis_n += 1
	var path := "%s/i01_%s.jpg" % [_shot_dir, shot_name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("INTEL shot: ", path)


func _finish() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["warps"] = warps
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	results["intel"] = ws.intel.stats()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/ai_intel_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("INTEL %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.shutdown_cleanup()
	tree.quit()

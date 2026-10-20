## Scripted checks of COMBAT-02 (tactical reactions, cover, orders, persistence) on the
## reference world.
##
##   Godot.exe --path . --resolution 1600x900 res://scenes/game/world_ref_20km.tscn -- --combat-tactics-test [--shots] [--only a,b]
##
## Ordinary squads (WorldState.add_unit / add_squad, rifles from CombatSim.equip_all) on
## the COMBAT-01b meadow, ordinary HESCO lines and buildings placed through
## ConstructionState, the real systems running them (DetailManager bodies and navigation,
## SquadControl orders, CombatBrain, CombatSim). "Threat" squads hold position 110 m
## south and fire with raised health so they keep shooting; the soldiers under test have
## raised health only where a scenario must last (stated in the log). Weapons, accuracy
## and line of fire are never changed. Prints "TAC <check> <json>", writes
## res://benchmarks/raw/combat_tactics_test.json and (with --shots) docs/combat02/c02_*.jpg.
class_name CombatTacticsSelfTest
extends CombatAISelfTest

var only: PackedStringArray = []
var walls: Array[int] = []
var new_orders := {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/combat02"
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
	brain.enabled = true
	SoldierBody.require_mouse_capture = false
	def = combat.weapon(&"rifle")
	tree.create_timer(1700.0).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish in 1700 s")
		_finish())
	var state := demo.sim.state
	state.shot_fired.connect(_on_shot_rec)
	state.unit_damaged.connect(func(t: UnitState, _a: float, _z: int, _s: int) -> void:
		dmg_events += 1
		if not t.alive:
			dmg_on_dead += 1)
	state.unit_died.connect(func(u: UnitState) -> void:
		deaths.append({"id": u.id, "name": u.unit_name, "t": snappedf(state.time, 0.01)}))
	state.order_changed.connect(func(u: UnitState) -> void:
		if u.order == UnitState.Order.MOVE:
			new_orders[u.id] = new_orders.get(u.id, 0) + 1)
	await _physics(60)
	_load_world_data()
	for u in state.soldiers():
		default_soldiers.append(u.position)
	_press(KEY_TAB)
	await _physics(3)
	area = _find_spot("meadow", demo.sites[0].position)
	if not area.is_finite():
		_expect(false, "no meadow")
		_finish()
		return
	demo.rts_camera.frame(area, 0.0, 100.0)
	await _seconds(2.0)
	_log("startup", {"area": _describe(area), "tactics": {"near_miss_m": brain.near_miss_m, "under_fire_s": brain.under_fire_s,
		"cover_radius": {"hold": brain.cover_radius_hold, "move": brain.cover_radius_move, "follow": brain.cover_radius_follow, "regroup": brain.cover_radius_regroup},
		"react_s": {"move": brain.react_s_move, "follow": brain.react_s_follow, "regroup": brain.react_s_regroup},
		"calm_s": brain.calm_s, "min_dwell_s": brain.min_dwell_s, "cover_budget": brain.cover_budget}})
	if _want("evaluation"):
		_log("cover_evaluation", await _evaluation())
	if _want("open_to_cover"):
		_log("open_to_cover", await _open_to_cover(false))
	if _want("hold_fire"):
		_log("hold_fire_defensive", await _open_to_cover(true))
	if _want("stay"):
		_log("stay_in_cover", await _stay_in_cover())
	if _want("wrong_side"):
		_log("wrong_side_of_wall", await _wrong_side())
	if _want("unreachable"):
		_log("unreachable_cover", await _unreachable())
	if _want("stacking"):
		_log("no_stacking", await _no_stacking())
	if _want("hold_area"):
		_log("hold_area", await _hold_area())
	if _want("move"):
		_log("move_continues", await _move_continues())
	if _want("follow"):
		_log("follow_continues", await _follow_continues())
	if _want("persistence"):
		_log("save_load_tactics", await _save_load_tactics())
	if _want("tiers"):
		_log("tiers_with_tactics", await _tiers())
	if _want("panel"):
		_log("squad_panel", await _panel())
	# Let a navmesh bake started by the last structure removal finish before quitting.
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	await _seconds(0.5)
	_finish()


func _want(name: String) -> bool:
	return only.is_empty() or only.has(name)


# --- Helpers ---------------------------------------------------------------------------

## Threat squad: n South soldiers holding 110 m south of c, firing (health raised).
func _threat(c: Vector3, n := 6, tag := "Threat", dist := 110.0) -> SquadState:
	var s := _squad(tag, 1, n, c + Vector3(0, 0, -dist), PI)
	_tough(s, 1.0e6)
	demo.sim.squads.order_hold([s.id])
	return s


## A straight line of standard HESCO from a to b (ground points); returns its id.
func _wall(a: Vector3, b: Vector3, type := &"hesco") -> StructureState:
	var w := cs.add_line(type, PackedVector3Array([demo.on_ground(a.x, a.z, 0.0), demo.on_ground(b.x, b.z, 0.0)]))
	walls.append(w.id)
	return w


func _clear_all() -> void:
	await _clear()
	for id in walls:
		cs.remove(id)
	walls.clear()
	await _seconds(0.6)


func _sq_ids(sq: SquadState) -> Array:
	return Array(sq.members) + Array(sq.fallen)


func _count_tactic(ids: Array, tactics: Array) -> int:
	var n := 0
	for id in ids:
		var u := _u(id)
		if u and u.alive and tactics.has(u.tactic):
			n += 1
	return n


func _centroid_ids(ids: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for id in ids:
		if _u(id) and _u(id).alive:
			c += _u(id).position
			n += 1
	return c / maxi(n, 1)


func _min_pair_pos(ps: Array) -> float:
	var m := INF
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			m = minf(m, _flat(ps[i], ps[j]))
	return m


## Shots by these soldiers that their own cover stopped within 3 m of the muzzle.
func _own_cover_hits(ids: Array, since: float) -> int:
	var n := 0
	for s in shot_log:
		if ids.has(s.shooter) and s.t >= since and s.blocker == "structure" and (s.end as Vector3).distance_to(s.origin) < 3.0:
			n += 1
	return n


## Soldiers that the AI reports in cover although the spot does not protect against the
## real threat (the threat squad's centre).
func _unprotected_in_cover(ids: Array, threat: Vector3) -> Array:
	var bad := []
	for id in ids:
		var u := _u(id)
		if u and u.alive and u.tactic == UnitState.Tactic.IN_COVER:
			var ev := brain._evaluate_spot(u, u.position, threat)
			if not ev.protected:
				bad.append(u.unit_name)
	return bad


func _tac_sig(u: UnitState) -> String:
	return "%d|%s|%d|%s|%s|%s|%.3f|%.3f|%s" % [u.tactic, str(u.react_target.snapped(Vector3.ONE * 0.001)) if u.react_target.is_finite() else "inf",
		u.react_state, str(u.cover_pos.snapped(Vector3.ONE * 0.001)) if u.cover_pos.is_finite() else "inf",
		str(u.threat_pos.snapped(Vector3.ONE * 0.001)) if u.threat_pos.is_finite() else "inf",
		str(u.anchor_pos.snapped(Vector3.ONE * 0.001)) if u.anchor_pos.is_finite() else "inf", u.under_fire_until, u.react_until, u.alive]


# --- Cover evaluation (direct) -----------------------------------------------------------

func _evaluation() -> Dictionary:
	var c := area
	_wall(c + Vector3(-6, 0, -6), c + Vector3(6, 0, -6))
	var probe := _squad("Probe", 0, 1, c + Vector3(30, 0, 20), 0.0)
	await _seconds(2.5)
	var u := _u(probe.members[0])
	var south := c + Vector3(0, 0, -110)
	var north := c + Vector3(0, 0, 110)
	var behind := demo.on_ground(c.x, c.z - 4.9, 0.0)
	var front := demo.on_ground(c.x, c.z - 7.4, 0.0)
	var open := demo.on_ground(c.x + 25.0, c.z - 4.9, 0.0)
	var out := {
		"behind_wall_threat_south": brain._evaluate_spot(u, behind, south),
		"behind_wall_threat_north": brain._evaluate_spot(u, behind, north),
		"in_front_of_wall_threat_south": brain._evaluate_spot(u, front, south),
		"open_ground": brain._evaluate_spot(u, open, south),
		"raw_torso_line_behind": lof.trace(behind + Vector3.UP * 1.1, south + Vector3.UP * 1.6, -1, false),
		"structures": cs.count(),
		"wall_modules": cs.get_structure(walls[0]).instances.size() if not walls.is_empty() else -1,
		"index_cells": sm._index.size(),
		"short_probe": lof.trace(demo.on_ground(c.x, c.z - 3.0, 0.6), demo.on_ground(c.x, c.z - 9.0, 0.6), -1, false).blocker,
		"first_module": _v(cs.get_structure(walls[0]).instances[0].origin) if not walls.is_empty() and cs.get_structure(walls[0]).instances.size() > 0 else [],
		"wall_y_vs_ground": snappedf(demo.ground_height(c + Vector3(0, 0, -6)), 0.01),
	}
	_expect(out.behind_wall_threat_south.protected and out.behind_wall_threat_south.can_fire, "a spot behind standard HESCO is not a fighting position (%s)" % JSON.stringify(out))
	_expect(not out.behind_wall_threat_north.protected and not out.in_front_of_wall_threat_south.protected and not out.open_ground.protected,
		"cover that does not face the threat was accepted (%s)" % JSON.stringify(out))
	await _clear_all()
	return out


# --- Under fire in the open, HESCO nearby ------------------------------------------------

## North (6) stands in the open 10 m behind a HESCO line; South fires from 110 m. With
## hold_fire North is on Hold Fire (defensive reaction without firing).
func _open_to_cover(hold_fire: bool) -> Dictionary:
	var c := area
	_wall(c + Vector3(-12, 0, -6), c + Vector3(12, 0, -6))
	var tag := "HF" if hold_fire else "OC"
	var n := _squad("North-" + tag, 0, 6, c + Vector3(0, 0, 4), 0.0, 1, 3.0)
	_tough(n, 3000.0)
	if hold_fire:
		demo.sim.squads.set_roe([n.id], SquadState.Roe.HOLD_FIRE)
	demo.rts_camera.frame(c, 0.0, 100.0)
	await _seconds(1.0)
	var s := _threat(c)
	_begin()
	var ids := _sq_ids(n)
	var t0 := demo.sim.state.time
	var first := {"under_fire": -1.0, "seek": -1.0, "in_cover_half": -1.0}
	var snapped := {"before": false, "moving": false, "cover": false}
	var moves := {}
	var seek_since := {}
	var max_seek := 0.0
	var possessed_check := {}
	var t_cover := -1.0
	while demo.sim.state.time - t0 < 30.0:
		await tree.physics_frame
		_invariants()
		var now := demo.sim.state.time
		var uf := 0
		for id in ids:
			var u := _u(id)
			if u.under_fire_until >= now:
				uf += 1
			if u.tactic == UnitState.Tactic.SEEK_COVER and u.react_state == UnitState.ReactState.MOVING:
				if not seek_since.has(id):
					seek_since[id] = now
					moves[id] = moves.get(id, 0) + 1
				max_seek = maxf(max_seek, now - seek_since[id])
			else:
				seek_since.erase(id)
		if first.under_fire < 0.0 and uf > 0:
			first.under_fire = now - t0
		if first.seek < 0.0 and _count_tactic(ids, [UnitState.Tactic.SEEK_COVER]) > 0:
			first.seek = now - t0
		if shots and not hold_fire:
			if not snapped.before and _shots_of(1) > 0 and first.seek < 0.0:
				snapped.before = true
				_frame_action(c + Vector3(0, 0, -30), PI * 0.5, 75.0)
				await _snap_firing("01_open_before_reaction")
			if not snapped.moving and _count_tactic(ids, [UnitState.Tactic.SEEK_COVER]) >= 2:
				snapped.moving = true
				_frame_action(c + Vector3(0, 0, -2), PI * 0.5, 40.0)
				demo.hud.combat_debug = true
				await _frames(2)
				_shot("02_moving_to_cover_f4")
				demo.hud.combat_debug = false
				await _frames(1)
				_shot("02_moving_to_cover")
		var in_cover := _count_tactic(ids, [UnitState.Tactic.IN_COVER])
		if first.in_cover_half < 0.0 and in_cover * 2 >= ids.size():
			first.in_cover_half = now - t0
			t_cover = now
		if t_cover > 0.0 and now - t_cover > 6.0 and not snapped.cover:
			snapped.cover = true
			if shots:
				_frame_action(c + Vector3(0, 0, -3), PI * 0.5 + 0.5, 30.0)
				await _snap_firing("03_fighting_from_hesco" if not hold_fire else "03b_hold_fire_in_cover")
				if not hold_fire:
					demo.hud.combat_debug = true
					_frame_action(c + Vector3(0, 0, -3), PI * 0.5, 45.0)
					await _frames(2)
					_shot("08_f4_tactical_diagnostics")
					demo.hud.combat_debug = false
			# Possession overrides at once: take a soldier that is reacting.
			if not hold_fire:
				for id in ids:
					var u := _u(id)
					if u.alive and u.tactic != UnitState.Tactic.NONE:
						var body := await _possess(id)
						possessed_check = {"possessed": body != null, "tactic_after": u.tactic_name(), "reacting_after": u.is_reacting()}
						if body and shots:
							await _fps_shot_at(body, _centroid_ids(_sq_ids(s)) + Vector3.UP * 1.3)
							Input.action_press("fire")
							await _physics(3)
							_shot("06_fps_possession_in_firefight")
							Input.action_release("fire")
						await _physics(30)
						possessed_check["tactic_while_possessed_1s"] = u.tactic_name()
						await _leave()
						break
	var threat_c := _centroid_ids(_sq_ids(s))
	var cover_positions := []
	for id in ids:
		var u := _u(id)
		if u.alive and u.tactic == UnitState.Tactic.IN_COVER:
			cover_positions.append(u.position)
	var since := t_cover if t_cover > 0.0 else t0
	var stats := _combat_stats([n, s])
	var out := {"first_seconds": first, "in_cover_end": _count_tactic(ids, [UnitState.Tactic.IN_COVER]), "seeking_end": _count_tactic(ids, [UnitState.Tactic.SEEK_COVER]),
		"cover_min_pair_m": snappedf(_min_pair_pos(cover_positions), 0.01) if cover_positions.size() > 1 else -1.0,
		"unprotected_in_cover": _unprotected_in_cover(ids, threat_c), "north_shots_from_cover": _shots_by(ids, since),
		"own_cover_hits": _own_cover_hits(ids, t0), "own_cover_holds": brain.own_cover_holds,
		"south_hits_on_north_after_cover": shot_log.filter(func(sh: Dictionary) -> bool: return sh.faction == 1 and sh.t >= since and ids.has(sh.hit)).size(),
		"south_seeing_north": _seeing(_sq_ids(s)), "cover_moves_per_soldier_max": moves.values().max() if not moves.is_empty() else 0,
		"longest_seek_s": snappedf(max_seek, 0.1), "possession": possessed_check, "notes": ids.map(func(id: int) -> String: return "%s: %s / %s" % [_u(id).unit_name, _u(id).tactic_name(), _u(id).cover_note]),
		"cover_stats": brain.summary().cover, "stats": {"shots": stats.shots, "sides": stats.sides, "damage_events": stats.damage_events, "damaging_shots": stats.damaging_shots}}
	_expect(first.under_fire >= 0.0 and first.seek >= 0.0 and out.in_cover_end >= 4, "%s: soldiers under fire did not reach the HESCO cover (%s)" % [tag, JSON.stringify(out)])
	_expect(out.unprotected_in_cover.is_empty() and (cover_positions.size() < 2 or out.cover_min_pair_m >= 1.0), "%s: cover unprotected or stacked (%s)" % [tag, JSON.stringify(out)])
	_expect(out.own_cover_hits == 0 and out.cover_moves_per_soldier_max <= 3 and max_seek <= 20.0, "%s: fired into own cover or looped between covers (%s)" % [tag, JSON.stringify(out)])
	if hold_fire:
		_expect(_shots_by(ids, t0) == 0, "Hold Fire squad fired while taking cover (%d shots)" % _shots_by(ids, t0))
	else:
		_expect(out.north_shots_from_cover > 0, "no return fire from cover (%s)" % JSON.stringify(out))
		_expect(possessed_check.get("possessed", false) and possessed_check.tactic_after == "-" and not possessed_check.reacting_after
			and possessed_check.tactic_while_possessed_1s == "-", "possession did not override the AI at once (%s)" % JSON.stringify(possessed_check))
	_expect(stats.damage_events == stats.damaging_shots, "duplicate damage (%s)" % JSON.stringify(stats))
	await _clear_all()
	return out


## Soldiers already behind HESCO stay there (no move) and fight.
func _stay_in_cover() -> Dictionary:
	var c := area
	_wall(c + Vector3(-12, 0, -6), c + Vector3(12, 0, -6))
	var n := _squad("North-ST", 0, 4, c + Vector3(0, 0, -4.9), 0.0, 1, 2.5)
	_tough(n, 3000.0)
	demo.sim.squads.order_hold([n.id])
	await _seconds(1.0)
	var start := {}
	for id in n.members:
		start[id] = _u(id).position
	var s := _threat(c)
	_begin()
	await _run_for(15.0)
	var drift := 0.0
	for id in n.members:
		drift = maxf(drift, _flat(start[id], _u(id).position))
	var out := {"in_cover": _count_tactic(n.members, [UnitState.Tactic.IN_COVER]), "max_drift_m": snappedf(drift, 0.01),
		"notes": Array(n.members).map(func(id: int) -> String: return _u(id).cover_note), "shots": _shots_by(n.members),
		"unprotected": _unprotected_in_cover(n.members, _centroid_ids(_sq_ids(s)))}
	_expect(out.in_cover >= 3 and drift < 1.5 and out.unprotected.is_empty() and out.shots > 0, "soldiers already in cover did not stay and fight (%s)" % JSON.stringify(out))
	if shots:
		_frame_action(c + Vector3(0, 0, -4), PI * 0.5 + 0.4, 28.0)
		await _snap_firing("03c_staying_behind_hesco")
	await _clear_all()
	return out


## Soldiers on the threat side of a wall: their spot is not cover. They either go round to
## its far side (within the Hold radius) or keep fighting in the open; never "in cover"
## where nothing protects them.
func _wrong_side() -> Dictionary:
	var c := area
	_wall(c + Vector3(-5, 0, 0), c + Vector3(5, 0, 0))
	var n := _squad("North-WS", 0, 4, c + Vector3(0, 0, -3), 0.0, 1, 2.5)
	_tough(n, 3000.0)
	await _seconds(1.0)
	var s := _threat(c)
	_begin()
	var unprotected_frames := 0
	var t0 := demo.sim.state.time
	var threat := c + Vector3(0, 0, -110)
	while demo.sim.state.time - t0 < 20.0:
		await tree.physics_frame
		if Engine.get_physics_frames() % 30 == 0:
			unprotected_frames += _unprotected_in_cover(n.members, threat).size()
	var out := {"in_cover": _count_tactic(n.members, [UnitState.Tactic.IN_COVER]), "unprotected_in_cover_samples": unprotected_frames,
		"positions_z_rel_wall": Array(n.members).map(func(id: int) -> float: return snappedf(_u(id).position.z - c.z, 0.1)),
		"notes": Array(n.members).map(func(id: int) -> String: return _u(id).cover_note)}
	_expect(unprotected_frames == 0, "soldiers reported cover on the threat side of a wall (%s)" % JSON.stringify(out))
	await _clear_all()
	return out


## A closed HESCO square next to a soldier: the spot inside is protected but cannot be
## reached; it must be rejected, not chosen again and again.
func _unreachable() -> Dictionary:
	var c := area
	var q := c + Vector3(8, 0, 0)
	var pts := PackedVector3Array()
	for p: Vector3 in [q + Vector3(-3, 0, -3), q + Vector3(3, 0, -3), q + Vector3(3, 0, 3), q + Vector3(-3, 0, 3), q + Vector3(-3, 0, -3)]:
		pts.append(demo.on_ground(p.x, p.z, 0.0))
	var ring := cs.add_line(&"hesco", pts)
	walls.append(ring.id)
	# The soldier stands 3 m south of the ring (the threat side): the spots inside it are
	# the nearest protected ones, the reachable ones lie north of the ring.
	var n := _squad("North-UR", 0, 1, q + Vector3(0, 0, -6), 0.0)
	_tough(n, 3000.0)
	await _seconds(1.5)
	var s := _threat(c)
	_begin()
	var inside_choices := 0
	var last := Vector3.INF
	var t0 := demo.sim.state.time
	var u := _u(n.members[0])
	while demo.sim.state.time - t0 < 25.0:
		await tree.physics_frame
		var cp := u.cover_pos
		if cp.is_finite() and absf(cp.x - q.x) < 2.6 and absf(cp.z - q.z) < 2.6 and not cp.is_equal_approx(last):
			inside_choices += 1
		last = cp
	var out := {"chose_inside_ring": inside_choices, "unreachable_rejected": brain.cover_unreachable, "tactic": u.tactic_name(), "note": u.cover_note,
		"position": _v(u.position), "searches": brain.cover_searches}
	_expect(inside_choices == 0 and brain.cover_unreachable >= 1, "unreachable cover inside a closed HESCO ring was chosen or never considered (%s)" % JSON.stringify(out))
	await _clear_all()
	return out


## Eight soldiers, one short wall: each picks its own spot.
func _no_stacking() -> Dictionary:
	var c := area
	_wall(c + Vector3(-4, 0, -6), c + Vector3(4, 0, -6))
	var n := _squad("North-NS", 0, 8, c + Vector3(0, 0, 3), 0.0, 2, 2.5)
	_tough(n, 3000.0)
	await _seconds(1.0)
	var s := _threat(c)
	_begin()
	await _run_for(25.0)
	var covers := []
	var positions := []
	for id in n.members:
		var u := _u(id)
		positions.append(u.position)
		if u.cover_pos.is_finite():
			covers.append(u.cover_pos)
	var out := {"with_cover": covers.size(), "cover_min_pair_m": snappedf(_min_pair_pos(covers), 0.01) if covers.size() > 1 else -1.0,
		"position_min_pair_m": snappedf(_min_pair_pos(positions), 0.01), "in_cover": _count_tactic(n.members, [UnitState.Tactic.IN_COVER]),
		"notes": Array(n.members).map(func(id: int) -> String: return _u(id).cover_note)}
	_expect(covers.size() >= 3 and (covers.size() < 2 or out.cover_min_pair_m >= 1.0) and out.position_min_pair_m >= 0.7,
		"soldiers stacked on the same cover (%s)" % JSON.stringify(out))
	await _clear_all()
	return out


# --- Orders under fire -------------------------------------------------------------------

## A squad on Hold under fire uses cover within its area and returns when calm.
func _hold_area() -> Dictionary:
	var c := area
	_wall(c + Vector3(-4, 0, -9), c + Vector3(4, 0, -9))      # 9 m away: inside the area
	_wall(c + Vector3(20, 0, -14), c + Vector3(28, 0, -14))   # 25 m away: outside
	var n := _squad("North-HA", 0, 6, c + Vector3(0, 0, 0), 0.0, 1, 3.0)
	_tough(n, 3000.0)
	demo.sim.squads.order_hold([n.id])
	await _seconds(1.0)
	var anchors := {}
	for id in n.members:
		anchors[id] = _u(id).anchor_pos
	var s := _threat(c)
	_begin()
	var max_from_anchor := 0.0
	var t0 := demo.sim.state.time
	var reacted := 0
	while demo.sim.state.time - t0 < 25.0:
		await tree.physics_frame
		for id in n.members:
			var u := _u(id)
			if u.alive:
				max_from_anchor = maxf(max_from_anchor, _flat(u.position, anchors[id]))
	reacted = _count_tactic(n.members, [UnitState.Tactic.IN_COVER, UnitState.Tactic.SEEK_COVER])
	if shots:
		_frame_action(c + Vector3(0, 0, -5), PI * 0.5, 50.0)
		await _snap_firing("04_hold_squad_keeps_its_area")
	# The threat stops; after the calm period the squad walks back to its held spots.
	demo.sim.squads.set_roe([s.id], SquadState.Roe.HOLD_FIRE)
	var t1 := demo.sim.state.time
	await _run_for(brain.calm_s + brain.under_fire_s + 12.0, func() -> bool:
		return _count_tactic(n.members, [UnitState.Tactic.IN_COVER, UnitState.Tactic.SEEK_COVER, UnitState.Tactic.RETURNING]) == 0)
	var back := 0.0
	for id in n.members:
		back = maxf(back, _flat(_u(id).position, anchors[id]))
	var out := {"reacted": reacted, "max_distance_from_held_spot_m": snappedf(max_from_anchor, 0.1), "radius_m": brain.cover_radius_hold,
		"returned_after_s": snappedf(demo.sim.state.time - t1, 0.1), "max_distance_after_return_m": snappedf(back, 0.1),
		"squad_order": n.order_name(), "unit_orders": Array(n.members).filter(func(id: int) -> bool: return _u(id).has_order()).size()}
	_expect(reacted >= 2 and max_from_anchor <= brain.cover_radius_hold + 1.5, "Hold squad left its area or did not react (%s)" % JSON.stringify(out))
	_expect(back <= 2.5 and n.order == SquadState.Order.HOLD and out.unit_orders == 0, "Hold squad did not return to its spots (%s)" % JSON.stringify(out))
	await _clear_all()
	return out


## A squad on a Move order crosses the front under fire, with HESCO along its path: it
## may take a short cover break but arrives.
func _move_continues() -> Dictionary:
	var c := area
	_wall(c + Vector3(-6, 0, -6), c + Vector3(6, 0, -6))
	var n := _squad("North-MV", 0, 6, c + Vector3(-50, 0, 0), -PI * 0.5, 1, 3.0)
	_tough(n, 3000.0)
	await _seconds(1.0)
	var s := _threat(c)
	await _run_for(2.0)
	_begin()
	var dest := demo.on_ground(c.x + 55.0, c.z, 0.0)
	demo.sim.squads.order_move([n.id], dest)
	var t0 := demo.sim.state.time
	var reacted := {}
	var longest := {"s": 0.0}
	var since := {}
	await _run_for(70.0, func() -> bool:
		var now := demo.sim.state.time
		for id in n.members:
			var u := _u(id)
			if u.is_reacting():
				reacted[id] = true
				if not since.has(id):
					since[id] = now
				longest.s = maxf(longest.s, now - since[id])
			else:
				since.erase(id)
		return n.status == SquadState.Status.DONE and now - t0 > 3.0)
	var out := {"status": SquadState.Status.keys()[n.status], "seconds": snappedf(demo.sim.state.time - t0, 0.1), "soldiers_that_reacted": reacted.size(),
		"longest_reaction_s": snappedf(longest.s, 0.1), "limit_s": brain.react_s_move,
		"events": brain.events.filter(func(e: Dictionary) -> bool: return String(e.unit).begins_with("North-MV")).slice(-12), "dist_to_destination_m": snappedf(_flat(_centroid_ids(n.members), dest), 0.1),
		"shots_while_moving": shot_log.filter(func(sh: Dictionary) -> bool: return n.members.has(sh.shooter) and sh.speed > 0.5).size(),
		"squad_order": n.order_name()}
	_expect(n.status == SquadState.Status.DONE and out.dist_to_destination_m < 8.0 and longest.s <= brain.react_s_move + 1.0,
		"Move squad abandoned its order under fire (%s)" % JSON.stringify(out))
	await _clear_all()
	return out


## A Follow squad under fire keeps following its leader's squad; once the leader stands,
## no follower gets the same slot again and again.
func _follow_continues() -> Dictionary:
	var c := area
	var lead := _squad("North-LD", 0, 4, c + Vector3(-40, 0, 10), -PI * 0.5, 1, 3.0)
	var fol := _squad("North-FL", 0, 4, c + Vector3(-50, 0, 18), -PI * 0.5, 1, 3.0)
	_tough(lead, 3000.0)
	_tough(fol, 3000.0)
	demo.sim.squads.order_follow([fol.id], lead.leader_id)
	await _seconds(1.0)
	var s := _threat(c)
	_begin()
	demo.sim.squads.order_move([lead.id], demo.on_ground(c.x + 40.0, c.z + 10.0, 0.0))
	var t0 := demo.sim.state.time
	var max_d := {"m": 0.0}
	await _run_for(60.0, func() -> bool:
		var l := _u(lead.leader_id)
		for id in fol.members:
			max_d.m = maxf(max_d.m, _flat(_u(id).position, l.position))
		return lead.status == SquadState.Status.DONE and demo.sim.state.time - t0 > 3.0)
	await _run_for(8.0)
	new_orders.clear()
	await _run_for(8.0)
	var standing := 0
	for id in fol.members:
		standing += new_orders.get(id, 0)
	var out := {"follow_order": fol.order_name(), "max_dist_to_leader_m": snappedf(max_d.m, 0.1), "orders_while_leader_stands_8s": standing,
		"reactions": brain.summary().tactics, "leader_status": SquadState.Status.keys()[lead.status]}
	_expect(fol.order == SquadState.Order.FOLLOW and max_d.m < 30.0 and max_d.m > 0.0 and standing == 0, "Follow broke under fire (%s)" % JSON.stringify(out))
	await _clear_all()
	return out


# --- Persistence ------------------------------------------------------------------------------

func _save_load_tactics() -> Dictionary:
	var c := area
	_wall(c + Vector3(-12, 0, -6), c + Vector3(12, 0, -6))
	var n := _squad("North-SL", 0, 6, c + Vector3(0, 0, 4), 0.0, 1, 3.0)
	_tough(n, 600.0)
	demo.sim.squads.order_hold([n.id])
	await _seconds(1.0)
	var s := _threat(c, 6, "Threat-SL", 80.0)
	for id in s.members:
		_u(id).health = 60.0  # some South soldiers will die: the dead must stay dead
		_u(id).max_health = 60.0
	_begin()
	await _run_for(30.0, func() -> bool: return _count_tactic(n.members, [UnitState.Tactic.IN_COVER, UnitState.Tactic.SEEK_COVER]) >= 3)
	var saved := {}
	var restored := {}
	var grab := func(into: Dictionary) -> void:
		for id in spawned_ids:
			var u := _u(id)
			if u:
				into[id] = _tac_sig(u) + "#" + _ai_sig(u)
		var nn := _sq("North-SL")
		into["squad"] = [nn.order_name(), nn.roe, Array(nn.members), Array(nn.fallen)] if nn else []
	_press(KEY_F5)
	await _frames(1)
	await tree.process_frame
	grab.call(saved)
	var tactics_saved: Dictionary = brain.summary().tactics
	var dead_saved := spawned_ids.filter(func(id: int) -> bool: return _u(id) and not _u(id).alive)
	await _run_for(4.0)
	var on_restore := func() -> void: grab.call(restored)
	demo.sim.state.restored.connect(on_restore)
	_press(KEY_F9)
	await _frames(2)
	demo.sim.state.restored.disconnect(on_restore)
	var diff := []
	for k in saved:
		if saved[k] != restored.get(k):
			diff.append({"key": k, "saved": saved[k], "loaded": restored.get(k)})
	var t1 := demo.sim.state.time
	_begin()
	await _run_for(5.0)
	var dead_shots := shot_log.filter(func(sh: Dictionary) -> bool: return dead_saved.has(sh.shooter)).size()
	var out := {"tactics_when_saved": tactics_saved, "dead_when_saved": dead_saved.size(), "differences": diff.slice(0, 5),
		"shots_after_load": shot_log.size(), "shots_by_dead_after_load": dead_shots, "tactics_after_load": brain.summary().tactics,
		"damage_events": dmg_events, "damaging_shots": shot_log.filter(func(sh: Dictionary) -> bool: return sh.damage > 0.0).size()}
	_expect(diff.is_empty() and not tactics_saved.is_empty() and dead_shots == 0 and out.shots_after_load > 0 and out.damage_events == out.damaging_shots,
		"tactical state or orders not restored by save / load (%s)" % JSON.stringify(out))
	await _clear_all()
	return out


# --- Squad panel ---------------------------------------------------------------------------

func _panel() -> Dictionary:
	var c := area
	var sqs := []
	for k in 6:
		sqs.append(_squad("Extra-%d" % k, k % 2, 4, c + Vector3(-60 + k * 24, 0, 40 + (k % 2) * 80), 0.0 if k % 2 == 0 else PI, 1, 3.0))
	for sq: SquadState in sqs:
		_tough(sq, 5000.0)
	demo.sim.squads.set_roe([sqs[2].id], SquadState.Roe.HOLD_FIRE)
	demo.rts.select_squads([sqs[0].id])
	_frame_action(c + Vector3(0, 0, 80), 0.0, 150.0)
	await _run_for(6.0)
	var panel := demo.hud.squad_panel
	var label_top := demo.hud._label.position.y
	var panel_bottom := panel.get_global_rect().end.y
	var out := {"squads": demo.sim.state.squads.size(), "panel_bottom": snappedf(panel_bottom, 1.0), "hud_text_top": snappedf(label_top, 1.0),
		"overlap_px": snappedf(maxf(panel_bottom - label_top, 0.0), 1.0), "row": panel.row_text(sqs[0])}
	if shots:
		await _frames(3)
		_shot("07_squad_panel_many_squads")
	_expect(panel_bottom <= label_top, "squad panel overlaps the HUD text (%s)" % JSON.stringify(out))
	demo.rts.select([])
	await _clear_all()
	return out


# --- Output ---------------------------------------------------------------------------

func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/c02_%s.jpg" % [_shot_dir, shot_name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("TAC shot: ", path)


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("TAC %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("TAC FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	Input.action_release("fire")
	results["deaths"] = deaths.size()
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/combat_tactics_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("TAC %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()

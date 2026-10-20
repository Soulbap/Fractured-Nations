## Scripted checks of UNIT-01A (squads and tactical orders) on the reference world.
##
##   Godot.exe --path . --resolution 1600x900 --log-file unit.log res://scenes/game/world_ref_20km.tscn -- --squad-test [--shots]
##
## Moves the three test squads (Alpha 8, Bravo 4, Sierra 4) to an open meadow found from
## the map data, builds a small HESCO base there, and drives everything through the real
## input (Ctrl+click, the squad panel, RMB, H, F + click, G, V, P, Tab, F5 / F9, wheel):
## an 8-soldier move without stacking, line and column, two squads passing each other,
## a squad walking around the base wall to its entrance, hold / follow / regroup,
## possession of one soldier while the squad moves, a long camera jump, save / load and
## the 5..200 m zoom. Prints "UNIT <check> <json>", writes res://benchmarks/raw/unit_test.json
## and (with --shots) docs/unit01a/u01a_*.jpg.
class_name SquadSelfTest
extends IntegrationSelfTest

var alpha: SquadState
var bravo: SquadState
var sierra: SquadState
var area := Vector3.INF
var base_c := Vector3.INF
var perim: StructureState


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	# COMBAT-01b: earlier milestones test without autonomous fire (their squads would
	# otherwise start shooting each other); combat01b_selftest.gd tests the AI.
	demo.sim.brain.enabled = false
	_shot_dir = "res://docs/unit01a"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	tree.create_timer(900.0).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish in 900 s")
		_finish())
	var rig := demo.rts_camera
	var state := demo.sim.state
	await _physics(60)
	_load_world_data()
	for sq: SquadState in state.all_squads():
		match sq.squad_name:
			"Alpha": alpha = sq
			"Bravo": bravo = sq
			"Sierra": sierra = sq

	# 0. Start: squads exist, camera defaults.
	_press(KEY_TAB)
	await _physics(3)
	_log("startup", {"squads": state.all_squads().map(func(s: SquadState) -> Dictionary:
			return {"name": s.squad_name, "faction": s.faction, "members": s.members.size(), "leader": s.leader_id, "order": s.order_name(), "formation": s.formation_name()}),
		"rts_zoom_start": snappedf(rig.zoom, 0.01), "zoom_min": rig.zoom_min, "zoom_max": rig.zoom_max, "zoom_default": rig.zoom_default,
		"soldiers": state.count_of(UnitState.Kind.SOLDIER)})
	_expect(alpha != null and alpha.members.size() == 8 and bravo != null and bravo.members.size() == 4 and sierra != null and sierra.members.size() == 4, "test squads missing")
	_expect(is_equal_approx(rig.zoom, 80.0) and is_equal_approx(rig.zoom_min, 5.0) and is_equal_approx(rig.zoom_max, 200.0), "RTS camera not 80 m default / 5..200 m")
	if alpha == null or bravo == null or sierra == null:
		_finish()
		return

	# 1. Open meadow and a HESCO base next to it; squads stationed there.
	area = _find_spot("meadow", demo.sites[0].position)
	_expect(area.is_finite(), "no open area found")
	if not area.is_finite():
		_finish()
		return
	# The base stands on its own open spot (another meadow at least 150 m away).
	base_c = _find_open(area, 35.0)
	if not base_c.is_finite():
		base_c = demo.on_ground(area.x + 110.0, area.z, 0.0)
	rig.frame(area, 0.0, 80.0)
	await _seconds(3.0)
	_build_base(base_c)
	_station(alpha, area + Vector3(-30, 0, 20), 0.0)
	_station(bravo, area + Vector3(-30, 0, 35), 0.0)
	_station(sierra, area + Vector3(40, 0, -30), PI)
	await _seconds(2.5)
	var with_body := 0
	for sq: SquadState in [alpha, bravo, sierra]:
		for id in sq.members:
			if state.get_unit(id).has_body:
				with_body += 1
	_log("setup", {"area": _describe(area), "base_center": _v(base_c), "bodies_in_squads": with_body, "structures": cs.count()})
	_expect(with_body == 16, "not all squad soldiers have bodies at the test area (%d of 16)" % with_body)
	# COMBAT-01b: only the Follow check, repeated (reproducing the UNIT-01A follow failure).
	var rep := args.find("--follow-repeat")
	if rep >= 0:
		var n := int(args[rep + 1]) if rep + 1 < args.size() else 5
		for i in n:
			_log("follow_%d" % i, await _follow_check())
		_finish()
		return

	# 2. Selection: Ctrl+click a soldier selects its squad; the panel selects one too.
	var cam := rig.camera
	var au := state.get_unit(alpha.members[3])
	rig.frame(au.position, 0.0, 45.0)
	await _frames(3)
	_click_mod(MOUSE_BUTTON_LEFT, cam.unproject_position(au.position + Vector3.UP), true, false)
	await _frames(3)
	var sel_ctrl := demo.rts.selected_squads()
	await _frames(20)
	var panel := demo.hud.squad_panel
	var bbtn: Button = panel._buttons.get(bravo.id)
	var panel_ok := false
	if bbtn:
		var c := bbtn.get_global_rect().get_center()
		_click_mod(MOUSE_BUTTON_LEFT, c, false, true)  # Shift+click on the Bravo row adds it
		await _frames(3)
		panel_ok = demo.rts.selected_squads() == [alpha.id, bravo.id]
	if shots:
		rig.frame(area + Vector3(-30, 0, 27), 0.3, 55.0)
		await _seconds(1.0)
		_shot("squad_selection")
	_log("selection", {"ctrl_click_squads": sel_ctrl, "after_panel_shift_click": demo.rts.selected_squads(), "selected_soldiers": demo.rts.selected.size(),
		"single_click_individual": await _single_click_check()})
	_expect(sel_ctrl == [alpha.id], "Ctrl+click did not select squad Alpha")
	_expect(panel_ok, "Shift+click on the squad panel did not add squad Bravo")

	# 3. Eight soldiers, line formation, 70 m: no stacking.
	demo.rts.select_squads([alpha.id])
	var line_target := demo.on_ground(area.x - 30.0, area.z - 50.0, 0.0)
	rig.frame(area + Vector3(-30, 0, -15), 0.0, 90.0)
	await _frames(3)
	_click(MOUSE_BUTTON_RIGHT, cam.unproject_position(line_target))
	var line := await _watch([alpha.id], 45.0, "line_formation", line_target)
	line["final"] = _formation_check(alpha)
	_log("move_line_8", line)
	if shots:
		rig.frame(_centroid(alpha), 0.3, 40.0)
		await _seconds(1.0)
		_shot("line_formation_done")
	_expect(line.done and line.final.min_pair_m >= 1.5 and line.final.distinct_targets, "8-soldier line move stacked or did not finish (%s)" % JSON.stringify(line.final))

	# 4. Column (V) and move again.
	_press(KEY_V)
	await _frames(2)
	var col_target := demo.on_ground(area.x - 30.0, area.z + 20.0, 0.0)
	rig.frame(area + Vector3(-30, 0, -15), 0.0, 90.0)
	await _frames(3)
	_click(MOUSE_BUTTON_RIGHT, cam.unproject_position(col_target))
	var column := await _watch([alpha.id], 45.0, "column_formation", col_target)
	column["final"] = _formation_check(alpha)
	column["formation"] = alpha.formation_name()
	_log("move_column", column)
	if shots:
		rig.frame(_centroid(alpha), 1.2, 40.0)
		await _seconds(1.0)
		_shot("column_formation_done")
	_expect(alpha.formation == SquadState.Formation.COLUMN and column.done and column.final.min_pair_m >= 1.5, "column move failed (%s)" % JSON.stringify(column.final))
	_press(KEY_V)  # back to line
	await _frames(2)

	# 5. Two squads pass each other (Alpha west -> east, Sierra east -> west).
	_station(alpha, area + Vector3(-35, 0, 0), -PI * 0.5)
	_station(sierra, area + Vector3(35, 0, 0), PI * 0.5)
	await _seconds(1.0)
	demo.rts.select_squads([alpha.id])
	demo.rts.order_move(demo.on_ground(area.x + 35.0, area.z, 0.0))
	demo.rts.select_squads([sierra.id])
	demo.rts.order_move(demo.on_ground(area.x - 35.0, area.z, 0.0))
	demo.rts.select_squads([alpha.id, sierra.id])
	rig.frame(area, 0.0, 70.0)
	var pass_ := await _watch([alpha.id, sierra.id], 50.0, "squads_passing", area, true)
	_log("two_squads_pass", pass_)
	_expect(pass_.done and pass_.min_cross_pair_m >= 0.6, "squads did not pass each other cleanly (%s)" % JSON.stringify(pass_))

	# 6. Around a structure: Alpha from north of the HESCO base to its inside (entrance south).
	_station(alpha, base_c + Vector3(0, 0, -40), PI)
	await _seconds(1.5)
	demo.rts.select_squads([alpha.id])
	rig.frame(base_c, 0.0, 110.0)
	await _frames(3)
	var inside := demo.on_ground(base_c.x - 4.0, base_c.z + 4.0, 0.0)
	_click(MOUSE_BUTTON_RIGHT, cam.unproject_position(inside))
	var around := await _watch([alpha.id], 70.0, "around_base", base_c, false, perim)
	around["final"] = _formation_check(alpha)
	around["inside_base"] = _members_inside(alpha, base_c, 20.0)
	_log("around_structure", around)
	_expect(around.done and around.frames_in_structure == 0 and around.inside_base >= 7, "squad did not walk around the base to its inside (%s)" % JSON.stringify(around))

	# 7. Hold, Follow, Regroup.
	_log("hold", await _hold_check())
	_log("follow", await _follow_check())
	_log("regroup", await _regroup_check())
	_log("blocked_report", await _blocked_check())

	# 8. Possession while the squad moves; release resumes, the others are not reset.
	_log("possession", await _possession_check())

	# 9. Long camera jump: the squad keeps walking in the abstract tier and is intact.
	_log("long_jump", await _jump_check())

	# 10. Save / load.
	_log("save_load", await _save_load_check())

	# 11. Zoom 5 .. 200 m with the wheel, controls at the closest zoom.
	_log("zoom", await _zoom_check())

	# 12. Frame times with the squads.
	_log("performance", await _perf())
	_finish()


# --- Setup ----------------------------------------------------------------------------

## A 40 x 40 m HESCO square with a 6-cell entrance in the south wall and a barracks.
func _build_base(c: Vector3) -> void:
	var h := 20.0
	var corners := [c + Vector3(-h, 0, -h), c + Vector3(h, 0, -h), c + Vector3(h, 0, h), c + Vector3(-h, 0, h), c + Vector3(-h, 0, -h)]
	var pts := PackedVector3Array()
	for p: Vector3 in corners:
		pts.append(demo.on_ground(p.x, p.z, 0.0))
	perim = cs.add_line(&"hesco", pts)
	var mods := ModularLine.modules(StructureCatalog.get_def(&"hesco"), perim.points)
	var seg2: Array[int] = []
	for i in mods.size():
		if mods[i].segment == 2:
			seg2.append(i)
	var mid := seg2.size() / 2
	for k in range(mid - 3, mid + 3):
		cs.remove_module(perim.id, seg2[k])
	var bdef := StructureCatalog.get_def(&"barracks")
	var chk := sm.check_building(bdef, demo.on_ground(c.x + 8.0, c.z - 8.0, 0.0), 0.0, -1, true)
	if chk.ok:
		cs.add_building(&"barracks", chk.xform.origin, 0.0)


## Puts a squad's soldiers in a grid around p facing yaw (records and bodies), no orders.
func _station(sq: SquadState, p: Vector3, yaw: float) -> void:
	demo.sim.squads.order_hold([sq.id])
	var right := SquadControl._right(yaw)
	var back := -SquadControl._forward(yaw)
	var i := 0
	for id in sq.members:
		var col := i % 4
		var row := i / 4
		var q := p + right * ((col - 1.5) * 3.0) + back * (row * 3.0)
		var g := demo.on_ground(q.x, q.z, 0.3)
		var u := demo.sim.state.get_unit(id)
		var b := demo.sim.body_of(id) as SoldierBody
		u.position = g
		u.yaw = yaw
		if b:
			b.teleport(g, yaw)
		i += 1
	sq.order = SquadState.Order.NONE
	sq.status = SquadState.Status.IDLE


# --- Measurements ---------------------------------------------------------------------

## Follows squads until none is moving (or timeout). Records the smallest distance between
## two soldiers of the same squad (stacking) and of different squads (passing), frames in
## a structure, and takes a screenshot halfway.
func _watch(squad_ids: Array, timeout: float, shot_name: String, look_at: Vector3, cross := false, wall: StructureState = null) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var min_pair := INF
	var min_cross := INF
	var in_wall := 0
	var shot_done := not shots
	var worst := 0.0
	var frames := 0
	await _physics(2)
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		var tf := Time.get_ticks_usec()
		await tree.physics_frame
		worst = maxf(worst, (Time.get_ticks_usec() - tf) / 1000.0)
		frames += 1
		var all_ids := []
		for sid in squad_ids:
			var sq := demo.sim.state.get_squad(sid)
			min_pair = minf(min_pair, _min_pair(sq.members))
			all_ids.append(Array(sq.members))
			if wall:
				for id in sq.members:
					if _inside_line(demo.sim.state.get_unit(id).position, wall, 0.1):
						in_wall += 1
		if cross and all_ids.size() == 2:
			min_cross = minf(min_cross, _min_cross(all_ids[0], all_ids[1]))
		if not shot_done and Time.get_ticks_msec() - t0 > 5000:
			shot_done = true
			await _frames(5)
			_shot(shot_name)
		var moving := false
		for sid in squad_ids:
			if demo.sim.state.get_squad(sid).status == SquadState.Status.MOVING:
				moving = true
		if not moving and Time.get_ticks_msec() - t0 > 1500:
			break
	var done := true
	var statuses := []
	for sid in squad_ids:
		var sq := demo.sim.state.get_squad(sid)
		statuses.append(SquadState.Status.keys()[sq.status])
		if sq.status != SquadState.Status.DONE:
			done = false
	var out := {"done": done, "status": statuses, "seconds": (Time.get_ticks_msec() - t0) / 1000.0, "min_pair_during_m": snappedf(min_pair, 0.01),
		"worst_physics_wait_ms": snappedf(worst, 0.1), "frames": frames}
	if cross:
		out["min_cross_pair_m"] = snappedf(min_cross, 0.01)
	if wall:
		out["frames_in_structure"] = in_wall
	if shots and not shot_done:
		_shot(shot_name)
	return out


func _formation_check(sq: SquadState) -> Dictionary:
	var targets := {}
	var distinct := true
	var err := 0.0
	var arrived := 0
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		var key := Vector2i(roundi(u.order_target.x), roundi(u.order_target.z))
		if targets.has(key):
			distinct = false
		targets[key] = true
		if u.move_state == UnitState.MoveState.ARRIVED:
			arrived += 1
		err = maxf(err, _flat(u.position, u.order_target))
	return {"min_pair_m": snappedf(_min_pair(sq.members), 0.01), "distinct_targets": distinct, "arrived": arrived,
		"members": sq.members.size(), "max_slot_error_m": snappedf(err, 0.01), "blocked": Array(sq.blocked)}


func _min_pair(ids: PackedInt32Array) -> float:
	var best := INF
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			best = minf(best, _flat(demo.sim.state.get_unit(ids[i]).position, demo.sim.state.get_unit(ids[j]).position))
	return best


func _min_cross(a: Array, b: Array) -> float:
	var best := INF
	for i in a:
		for j in b:
			best = minf(best, _flat(demo.sim.state.get_unit(i).position, demo.sim.state.get_unit(j).position))
	return best


func _members_inside(sq: SquadState, c: Vector3, h: float) -> int:
	var n := 0
	for id in sq.members:
		var p := demo.sim.state.get_unit(id).position
		if absf(p.x - c.x) < h - 0.5 and absf(p.z - c.z) < h - 0.5:
			n += 1
	return n


## A plain click on a soldier still selects just that soldier.
func _single_click_check() -> Dictionary:
	var u := demo.sim.state.get_unit(bravo.members[1])
	var cam := demo.rts_camera.camera
	demo.rts_camera.frame(u.position, 0.0, 40.0)
	await _frames(3)
	var before := demo.rts.selected.duplicate()
	_click(MOUSE_BUTTON_LEFT, cam.unproject_position(u.position + Vector3.UP))
	await _frames(3)
	var ok := demo.rts.selected.size() == 1 and demo.rts.selected[0] == u.id and demo.rts.selected_squads().is_empty()
	demo.rts.select(before)
	_expect(ok, "a plain click did not select a single soldier")
	return {"selected": Array(demo.rts.selected).size(), "ok": ok}


func _hold_check() -> Dictionary:
	demo.rts.select_squads([alpha.id])
	demo.rts.order_move(demo.on_ground(area.x - 40.0, area.z - 40.0, 0.0))
	await _seconds(2.0)
	_press(KEY_H)
	await _seconds(1.0)
	var p0 := {}
	for id in alpha.members:
		p0[id] = demo.sim.state.get_unit(id).position
	await _seconds(3.0)
	var drift := 0.0
	var orders := 0
	for id in alpha.members:
		var u := demo.sim.state.get_unit(id)
		drift = maxf(drift, _flat(u.position, p0[id]))
		if u.has_order():
			orders += 1
	var out := {"order": alpha.order_name(), "max_drift_3s_m": snappedf(drift, 0.01), "members_with_orders": orders}
	_expect(alpha.order == SquadState.Order.HOLD and drift < 0.3 and orders == 0, "Hold did not stop the squad (%s)" % JSON.stringify(out))
	return out


func _follow_check() -> Dictionary:
	var cam := demo.rts_camera.camera
	# Bravo follows Alpha (F, then click an Alpha soldier); Alpha walks 80 m.
	_station(bravo, area + Vector3(-60, 0, 30), 0.0)
	_station(alpha, area + Vector3(-60, 0, 0), 0.0)
	await _seconds(1.5)
	demo.rts.select_squads([bravo.id])
	demo.rts_camera.frame(area + Vector3(-60, 0, 10), 0.0, 70.0)
	await _frames(3)
	_press(KEY_F)
	await _frames(2)
	var target := demo.sim.state.get_unit(alpha.members[2])
	_click(MOUSE_BUTTON_LEFT, cam.unproject_position(target.position + Vector3.UP))
	await _frames(3)
	var follows := bravo.order == SquadState.Order.FOLLOW and bravo.follow_squad_id == alpha.id
	# order_changed fires for new orders and for arrivals / stops: count them apart. A new
	# order is a MOVE with a target the soldier did not have; after Alpha stops, each one
	# is recorded with what the follower and the leader were doing.
	var issued := {"n": 0, "arrivals": 0, "stop_t": -1.0, "stop_pos": Vector3.INF, "late": []}
	var last_target := {}
	var last_issued := {}
	for id in bravo.members:
		var m := demo.sim.state.get_unit(id)
		last_target[id] = m.order_target if m.order == UnitState.Order.MOVE else Vector3.INF
	var counter := func(u: UnitState) -> void:
		if not bravo.has_member(u.id):
			return
		if u.order != UnitState.Order.MOVE:
			issued.arrivals += 1
			last_target[u.id] = Vector3.INF
			return
		var prev: Vector3 = last_target.get(u.id, Vector3.INF)
		if prev.is_finite() and prev.is_equal_approx(u.order_target):
			return
		issued.n += 1
		var prev_issued: Vector3 = last_issued.get(u.id, Vector3.INF)
		last_issued[u.id] = u.order_target
		if issued.stop_t >= 0.0:
			var l := demo.sim.state.get_unit(alpha.leader_id)
			issued.late.append({"t_after_stop": snappedf(demo.sim.state.time - issued.stop_t, 0.01), "unit": u.id,
				"new_target_shift_m": snappedf(_flat(prev, u.order_target), 0.01) if prev.is_finite() else -1.0,
				"unit_to_new_target_m": snappedf(_flat(u.position, u.order_target), 0.01),
				"shift_from_last_order_m": snappedf(_flat(prev_issued, u.order_target), 0.01) if prev_issued.is_finite() else -1.0,
				"leader_moved_since_stop_m": snappedf(_flat(l.position, issued.stop_pos), 0.01),
				"leader_speed": snappedf(Vector2(l.velocity.x, l.velocity.z).length(), 0.01)})
		last_target[u.id] = u.order_target
	demo.sim.state.order_changed.connect(counter)
	demo.sim.squads.order_move([alpha.id], demo.on_ground(area.x - 60.0, area.z - 80.0, 0.0))
	var t0 := Time.get_ticks_msec()
	var min_pair := INF
	var shot_done := not shots
	while Time.get_ticks_msec() - t0 < 30000:
		await tree.physics_frame
		min_pair = minf(min_pair, _min_pair(bravo.members))
		if not shot_done and Time.get_ticks_msec() - t0 > 8000:
			shot_done = true
			var l := demo.sim.state.get_unit(alpha.leader_id)
			demo.rts_camera.frame(l.position + Vector3(0, 0, 12), 0.0, 60.0)
			await _frames(10)
			_shot("follow")
		if alpha.status == SquadState.Status.DONE and Time.get_ticks_msec() - t0 > 3000:
			break
	var walk_s := (Time.get_ticks_msec() - t0) / 1000.0
	var during_walk: int = issued.n
	issued.stop_t = demo.sim.state.time
	issued.stop_pos = demo.sim.state.get_unit(alpha.leader_id).position
	var arrivals0: int = issued.arrivals
	await _seconds(6.0)
	var settle: int = issued.n - during_walk
	await _seconds(6.0)
	var while_standing: int = issued.n - during_walk - settle
	demo.sim.state.order_changed.disconnect(counter)
	var leader := demo.sim.state.get_unit(alpha.leader_id)
	var dist := 0.0
	var behind := 0
	var fwd := SquadControl._forward(leader.yaw)
	for id in bravo.members:
		var u := demo.sim.state.get_unit(id)
		dist = maxf(dist, _flat(u.position, leader.position))
		if (u.position - leader.position).dot(fwd) < 0.0:
			behind += 1
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var per10 := during_walk / 4.0 / walk_s * 10.0
	var out := {"follow_order": follows, "alpha_status": SquadState.Status.keys()[alpha.status], "max_dist_to_alpha_leader_m": snappedf(dist, 0.1),
		"bravo_behind_leader": behind, "min_pair_during_m": snappedf(min_pair, 0.01), "final_min_pair_m": snappedf(_min_pair(bravo.members), 0.01),
		"walk_s": snappedf(walk_s, 0.1), "orders_while_alpha_walks": during_walk, "orders_per_soldier_per_10s_walking": snappedf(per10, 0.01),
		"orders_while_settling_6s": settle, "orders_while_alpha_stands_6s": while_standing, "seconds": snappedf(secs, 0.1),
		"arrivals_after_stop": issued.arrivals - arrivals0, "orders_after_stop": issued.late}
	_expect(follows and dist < 25.0 and behind >= 3 and _min_pair(bravo.members) >= 1.5, "Follow did not keep Bravo behind Alpha (%s)" % JSON.stringify(out))
	# After the leader stops, each follower may get its final slot once (the slots stop
	# leading ahead of a walking leader); nothing after that.
	_expect(per10 <= 12.0 and while_standing == 0 and settle <= bravo.members.size(), "Follow re-issued orders too often (%s)" % JSON.stringify(out))
	demo.sim.squads.order_hold([bravo.id])
	return out


func _regroup_check() -> Dictionary:
	# Scatter Alpha with individual orders (detaches them), then G.
	var leader := demo.sim.state.get_unit(alpha.leader_id)
	var i := 0
	for id in alpha.members:
		if id == alpha.leader_id:
			continue
		var a := i * TAU / 7.0
		demo.rts.select([id])
		demo.rts.order_move(demo.on_ground(leader.position.x + cos(a) * 25.0, leader.position.z + sin(a) * 25.0, 0.0))
		i += 1
	await _seconds(7.0)
	var spread_before := 0.0
	for id in alpha.members:
		spread_before = maxf(spread_before, _flat(demo.sim.state.get_unit(id).position, leader.position))
	var detached := alpha.detached.size()
	demo.rts.select_squads([alpha.id])
	demo.rts_camera.frame(leader.position, 0.0, 70.0)
	await _frames(3)
	_press(KEY_G)
	var res := await _watch([alpha.id], 30.0, "regroup", leader.position)
	var spread_after := 0.0
	for id in alpha.members:
		spread_after = maxf(spread_after, _flat(demo.sim.state.get_unit(id).position, leader.position))
	var out := {"detached_before": detached, "detached_after": alpha.detached.size(), "spread_before_m": snappedf(spread_before, 0.1),
		"spread_after_m": snappedf(spread_after, 0.1), "done": res.done, "seconds": res.seconds, "min_pair_m": snappedf(_min_pair(alpha.members), 0.01)}
	_expect(detached == 7 and alpha.detached.is_empty() and spread_before > 15.0 and spread_after < 14.0 and res.done, "Regroup did not gather the squad (%s)" % JSON.stringify(out))
	return out


## A squad ordered into a closed HESCO square cannot get there: each soldier ends its
## order as BLOCKED (navmesh path ends at the wall, or stuck handling), the squad reports
## them, and nobody keeps walking in place.
func _blocked_check() -> Dictionary:
	var c := demo.on_ground(area.x + 35.0, area.z + 40.0, 0.0)
	var h := 8.0
	var pts := PackedVector3Array()
	for p: Vector3 in [c + Vector3(-h, 0, -h), c + Vector3(h, 0, -h), c + Vector3(h, 0, h), c + Vector3(-h, 0, h), c + Vector3(-h, 0, -h)]:
		pts.append(demo.on_ground(p.x, p.z, 0.0))
	var box := cs.add_line(&"hesco", pts)
	_station(bravo, c + Vector3(0, 0, -25), PI)
	demo.rts_camera.frame(c, 0.0, 60.0)
	await _seconds(2.0)  # debounced async navmesh bake with the box
	demo.sim.squads.order_move([bravo.id], c)
	var res := await _watch([bravo.id], 40.0, "blocked_box", c, false, box)
	var out := {"status": SquadState.Status.keys()[bravo.status], "blocked": Array(bravo.blocked), "members": bravo.members.size(),
		"seconds": res.seconds, "frames_in_structure": res.frames_in_structure, "panel_text": demo.hud.squad_panel.row_text(bravo)}
	_expect(bravo.status == SquadState.Status.PARTIAL and bravo.blocked.size() == bravo.members.size() and res.frames_in_structure == 0,
		"unreachable slots were not reported as blocked (%s)" % JSON.stringify(out))
	cs.remove(box.id)
	demo.sim.squads.order_hold([bravo.id])
	await _seconds(1.0)
	return out


## Open ground for the test base: no trees, rocks or houses within r, gentle, dry, at
## least 130 m from the squad area.
func _find_open(center: Vector3, r: float) -> Vector3:
	for ring: float in [130.0, 180.0, 240.0, 320.0, 420.0, 550.0, 700.0, 900.0, 1200.0]:
		for k in 32:
			var a := k * TAU / 32.0
			var p := demo.on_ground(center.x + cos(a) * ring, center.z + sin(a) * ring, 0.0)
			if _slope_at(p, 15.0) > 4.0 or _height_range(p, 30.0) > 3.0 or _road_dist(p) < 50.0:
				continue
			var so := _solids(p, r + 25.0)
			if so.trees + so.rocks + so.houses == 0 and _dry(p, r + 25.0):
				return p
	return Vector3.INF


func _centroid(sq: SquadState) -> Vector3:
	var c := Vector3.ZERO
	for id in sq.members:
		c += demo.sim.state.get_unit(id).position
	return c / sq.members.size()


func _possession_check() -> Dictionary:
	var state := demo.sim.state
	_station(alpha, area + Vector3(-40, 0, 40), 0.0)
	await _seconds(1.5)
	demo.rts.select_squads([alpha.id])
	var target := demo.on_ground(area.x - 40.0, area.z - 30.0, 0.0)
	demo.rts.order_move(target)
	await _seconds(2.0)
	var pid: int = alpha.members[4]
	var targets_before := {}
	for id in alpha.members:
		targets_before[id] = state.get_unit(id).order_target
	demo.rts.select([pid])
	_press(KEY_P)
	await _physics(10)
	var possessed := demo.game.mode == GameController.Mode.FPS and demo.game.possessed_id == pid
	var p_at := state.get_unit(pid).position
	if shots:
		var body := demo.game.possessed_body()
		if body:
			_aim(body, state.get_unit(alpha.leader_id).position + Vector3(0, 1.2, 0))
			await _frames(30)
			_shot("fps_possessed_in_squad")
	await _seconds(5.0)
	var p_moved := _flat(state.get_unit(pid).position, p_at)
	var others_moving := 0
	var others_same_target := 0
	for id in alpha.members:
		if id == pid:
			continue
		var u := state.get_unit(id)
		if u.order_target.is_equal_approx(targets_before[id]):
			others_same_target += 1
		if u.move_state == UnitState.MoveState.MOVING or u.move_state == UnitState.MoveState.ARRIVED:
			others_moving += 1
	var pu := state.get_unit(pid)
	var order_kept := pu.order == UnitState.Order.MOVE and pu.order_target.is_equal_approx(targets_before[pid])
	_press(KEY_TAB)
	await _physics(5)
	var res := await _watch([alpha.id], 40.0, "after_possession", target)
	var out := {"possessed": possessed, "possessed_moved_without_input_m": snappedf(p_moved, 0.01), "possessed_order_kept": order_kept,
		"others_same_target": others_same_target, "others_moving_or_arrived": others_moving, "squad_done_after_release": res.done,
		"possessed_arrived": state.get_unit(pid).move_state == UnitState.MoveState.ARRIVED, "squad_order": alpha.order_name()}
	_expect(possessed and p_moved < 0.5 and order_kept and others_same_target == 7 and res.done and out.possessed_arrived,
		"possession disturbed the squad order (%s)" % JSON.stringify(out))
	return out


func _jump_check() -> Dictionary:
	var state := demo.sim.state
	var rig := demo.rts_camera
	_station(alpha, area + Vector3(-40, 0, 40), 0.0)
	await _seconds(1.0)
	demo.sim.squads.order_move([alpha.id], demo.on_ground(area.x - 40.0, area.z - 260.0, 0.0))
	await _seconds(1.0)
	var before := alpha.to_dict()
	var far: Vector3 = demo.sites[2].position
	rig.frame(far, 0.0, 80.0)
	var jump_out := await _worst_frame(2.0)
	await _seconds(8.0)
	var abstract := 0
	for id in alpha.members:
		if not state.get_unit(id).has_body:
			abstract += 1
	var mid_min_pair := _min_pair(alpha.members)
	var leader := state.get_unit(alpha.leader_id)
	rig.frame(leader.position, 0.0, 80.0)
	var jump_back := await _worst_frame(2.0)
	await _seconds(2.0)
	var bodies := 0
	for id in alpha.members:
		if state.get_unit(id).has_body:
			bodies += 1
	var after := alpha.to_dict()
	var same: bool = before.id == after.id and before.members == after.members and before.leader == after.leader and before.order == after.order \
		and (before.order_target as Vector3).is_equal_approx(after.order_target) and before.formation == after.formation
	var res := await _watch([alpha.id], 60.0, "after_jump", leader.position)
	var out := {"camera_dist_m": snappedf(_flat(far, area), 1.0), "abstract_while_away": abstract, "min_pair_while_abstract_m": snappedf(mid_min_pair, 0.01),
		"bodies_after_return": bodies, "squad_record_unchanged": same, "jump_out_worst_ms": jump_out, "jump_back_worst_ms": jump_back,
		"done_after_return": res.done, "final": _formation_check(alpha)}
	_expect(abstract == 8 and same and bodies == 8 and res.done, "squad state did not survive the long jump (%s)" % JSON.stringify(out))
	return out


func _save_load_check() -> Dictionary:
	var state := demo.sim.state
	_station(alpha, area + Vector3(-40, 0, 40), 0.0)
	await _seconds(1.0)
	demo.rts.select_squads([alpha.id])
	_press(KEY_V)  # column
	await _frames(2)
	var target := demo.on_ground(area.x - 40.0, area.z - 40.0, 0.0)
	demo.rts.order_move(target)
	demo.sim.squads.order_follow([bravo.id], alpha.leader_id)
	await _seconds(2.0)
	_press(KEY_F5)
	await _frames(2)
	var saved_squads := []
	for sq: SquadState in state.all_squads():
		saved_squads.append(JSON.stringify(sq.to_dict()))
	var saved_pos := {}
	for id in alpha.members:
		saved_pos[id] = state.get_unit(id).position
	var path: String = con.world_save_path()
	var size := FileAccess.get_file_as_string(path).length()
	# Change everything: other order, line formation, another follow, leader change.
	_press(KEY_V)
	await _frames(2)
	demo.sim.squads.order_move([alpha.id], demo.on_ground(area.x + 30.0, area.z + 30.0, 0.0))
	demo.sim.squads.order_hold([bravo.id])
	state.set_leader(alpha.id, alpha.members[5])
	await _seconds(3.0)
	_press(KEY_F9)
	await _physics(3)
	var loaded_squads := []
	for sq: SquadState in state.all_squads():
		loaded_squads.append(JSON.stringify(sq.to_dict()))
	var pos_err := 0.0
	for id in alpha.members:
		pos_err = maxf(pos_err, _flat(state.get_unit(id).position, saved_pos[id]))
	var a2: SquadState = null
	for sq: SquadState in state.all_squads():
		if sq.squad_name == "Alpha":
			a2 = sq
	var res := await _watch([a2.id], 45.0, "after_load", target)
	var out := {"path": ProjectSettings.globalize_path(path), "bytes": size, "squads_identical": saved_squads == loaded_squads,
		"max_position_error_m": snappedf(pos_err, 0.001), "order_after_load": a2.order_name(), "formation_after_load": a2.formation_name(),
		"resumed_and_done": res.done}
	alpha = a2
	for sq: SquadState in state.all_squads():
		if sq.squad_name == "Bravo":
			bravo = sq
		elif sq.squad_name == "Sierra":
			sierra = sq
	_expect(saved_squads == loaded_squads and pos_err < 0.3 and res.done, "squads not restored by load (%s)" % JSON.stringify(out))
	demo.sim.squads.order_hold([bravo.id])
	return out


func _zoom_check() -> Dictionary:
	var rig := demo.rts_camera
	rig.frame(base_c + Vector3(0, 0, -21.5), 0.0, 40.0)  # right next to the north wall
	await _frames(3)
	for i in 40:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	await _frames(3)
	var zmin := rig.zoom
	var cam := rig.camera
	var cpos := cam.global_position
	var clear := cpos.y - demo.ground_height(cpos)
	var in_wall := sm.blocks_point(Vector2(cpos.x, cpos.z), 0.05) and cpos.y < demo.ground_height(cpos) + 2.6
	if shots:
		await _frames(20)
		_shot("zoom_5m")
	# Pan at the closest zoom.
	var f0 := rig.focus
	Input.action_press("move_forward")
	await _seconds(0.6)
	Input.action_release("move_forward")
	var panned := _flat(rig.focus, f0)
	for i in 60:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _frames(3)
	var zmax := rig.zoom
	if shots:
		rig.frame(area + Vector3(0, 0, 0), 0.4, rig.zoom)
		await _frames(30)
		_shot("zoom_200m")
	# Selection still works at 200 m.
	var u := demo.sim.state.get_unit(alpha.members[0])
	rig.frame(u.position, 0.0, 200.0)
	await _frames(3)
	_click(MOUSE_BUTTON_LEFT, cam.unproject_position(u.position + Vector3.UP))
	await _frames(3)
	var pick := demo.rts.selected.has(u.id)
	rig.frame(area, 0.0, 80.0)
	var out := {"reached_min": snappedf(zmin, 0.01), "reached_max": snappedf(zmax, 0.01), "camera_clearance_at_min_m": snappedf(clear, 0.01),
		"camera_inside_structure": in_wall, "pan_at_min_m": snappedf(panned, 0.01), "pick_at_200m": pick}
	_expect(is_equal_approx(zmin, 5.0) and is_equal_approx(zmax, 200.0) and clear >= 1.0 and not in_wall and panned > 0.5 and pick, "zoom / controls failed (%s)" % JSON.stringify(out))
	return out


func _perf() -> Dictionary:
	var rig := demo.rts_camera
	var out := {}
	_station(alpha, area + Vector3(-35, 0, 0), -PI * 0.5)
	_station(sierra, area + Vector3(35, 0, 0), PI * 0.5)
	_station(bravo, area + Vector3(-35, 0, 20), -PI * 0.5)
	await _seconds(1.0)
	demo.sim.squads.order_move([alpha.id, bravo.id], demo.on_ground(area.x + 40.0, area.z + 10.0, 0.0))
	demo.sim.squads.order_move([sierra.id], demo.on_ground(area.x - 40.0, area.z, 0.0))
	rig.frame(area, 0.0, 80.0)
	await _seconds(1.0)
	out.rts_80m_three_squads_moving = await _measure(300)
	rig.frame(base_c, 0.0, 15.0)
	await _seconds(2.5)  # the detail area re-centres (async bake + terrain collision) first
	out.rts_15m_base = await _measure(200)
	rig.frame(area, 0.6, 200.0)
	await _seconds(2.5)
	out.rts_200m = await _measure(200)
	# First person inside Alpha while the others walk.
	demo.rts.select([alpha.members[2]])
	_press(KEY_P)
	await _seconds(2.0)
	out.fps_in_squad = await _measure(240)
	_press(KEY_TAB)
	await _physics(5)
	var t := Time.get_ticks_usec()
	for i in 100:
		demo.sim.squads.order_move([alpha.id], demo.on_ground(area.x - 20.0 + i % 2 * 40.0, area.z, 0.0))
	out.order_move_8_cost_ms = snappedf((Time.get_ticks_usec() - t) / 100000.0, 0.001)
	t = Time.get_ticks_usec()
	for i in 100:
		demo.sim.squads.update(1.0)
	out.squad_update_cost_ms = snappedf((Time.get_ticks_usec() - t) / 100000.0, 0.001)
	return out


# --- Input / output -------------------------------------------------------------------

func _click_mod(button: MouseButton, pos: Vector2, ctrl: bool, shift: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = _win(pos)
	ev.global_position = _win(pos)
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/u01a_%s.jpg" % [_shot_dir, name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.88)
	print("UNIT shot: ", path)


func _log(name: String, data: Dictionary) -> void:
	results[name] = data
	print("UNIT %s %s" % [name, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("UNIT FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/unit_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("UNIT %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()

## Scripted checks of the WORLD-CORE-01 prototype against the real scene.
##
##   Godot.exe --path . --resolution 1600x900 --log-file core.log res://scenes/game/core_demo.tscn -- --core-test [--shots]
##
## Drives the game through its real input actions (Tab, mouse clicks injected with
## Input.parse_input_event) and the state API, prints "CORE <check> <json>" lines and
## a PASS/FAIL summary, writes res://benchmarks/raw/core_test.json and, with --shots,
## screenshots from both perspectives to res://docs/screenshots/core01_*.jpg.
## Checks: spawn integrity, orders executed while in FPS, Tab switching, RTS click
## selection and right-click orders, box selection, repeated switches preserving ids,
## bodies, orders and positions, arrival, suspended order resuming after possession,
## the abstract (bodiless) tier, and frame times in both views.
class_name CoreSelfTest
extends RefCounted

var demo: CoreDemo
var tree: SceneTree
var results := {}
var failures: Array[String] = []
var shots := false
var _shot_dir := "res://docs/screenshots"


func _init(p_demo: CoreDemo) -> void:
	demo = p_demo
	tree = demo.get_tree()


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var sim := demo.sim
	var state := sim.state
	var game := demo.game
	var rts := demo.rts
	await _physics(40)

	# 1. Spawn integrity: one body per unit, everyone on the ground, navmesh present.
	var one_body_each := true
	var grounded := 0
	for u in state.all_units():
		var b := sim.body_of(u.id)
		if b == null or b.unit != u:
			one_body_each = false
		elif b is SoldierBody and b.is_on_floor():
			grounded += 1
	var soldiers := state.count_of(UnitState.Kind.SOLDIER)
	_log("spawn", {"units": state.units.size(), "soldiers": soldiers, "vehicles": state.count_of(UnitState.Kind.VEHICLE),
		"bodies": sim.bodies.size(), "one_body_per_unit": one_body_each, "soldiers_on_floor": grounded,
		"nav": demo.nav_info, "terrain_collision_mode": demo.terrain.collision_mode})
	_expect(one_body_each, "a unit has no body or a wrong body")
	_expect(sim.bodies.size() == state.units.size(), "body count differs from unit count")
	_expect(grounded == soldiers, "%d of %d soldiers not on the floor" % [soldiers - grounded, soldiers])
	_expect(demo.nav_info.get("polygons", 0) > 0, "navigation mesh has no polygons")

	# 2. Start in FPS, possessing a North soldier.
	var first_body := game.possessed_body()
	_log("start_mode", {"mode": game.mode, "possessed": game.possessed_id, "controlled": first_body != null and first_body.player_controlled,
		"camera_current": first_body != null and first_body.camera.current})
	_expect(game.mode == GameController.Mode.FPS, "did not start in FPS mode")
	_expect(first_body != null and first_body.player_controlled and first_body.camera.current, "possessed body not controlled / camera not current")

	# 3. Orders execute while the player is in FPS: six North soldiers walk 70 m north.
	var north := state.units_where(func(u: UnitState) -> bool: return u.faction == 0 and u.kind == UnitState.Kind.SOLDIER and u.id != game.possessed_id)
	var group := []
	for i in mini(6, north.size()):
		group.append(north[i].id)
	var target := demo.on_ground(demo.area_center.x - 10.0, demo.area_center.z - 70.0, 0.0)
	state.issue_group_move(group, target, 2.5)
	var d0 := _distances(group)
	await _seconds(3.0)
	var d1 := _distances(group)
	var progressed := 0
	var paths := 0
	for id in group:
		if d1[id] < d0[id] - 5.0:
			progressed += 1
		if sim.body_of(id).nav.get_current_navigation_path().size() > 1:
			paths += 1
	_log("orders_in_fps", {"ordered": group.size(), "progressed_5m_in_3s": progressed, "with_path": paths,
		"example_distance_before_after": [d0[group[0]], d1[group[0]]]})
	_expect(progressed == group.size(), "%d of %d ordered soldiers did not progress while in FPS" % [group.size() - progressed, group.size()])
	if shots:
		_aim(first_body, sim.body_of(group[0]).global_position)
		await _frames(30)
		_shot("fps_watching_orders")

	# 4. Tab to RTS through the real input action.
	_press(KEY_TAB)
	await _physics(3)
	var fb_unit := state.get_unit(game.possessed_id)
	_log("tab_to_rts", {"mode": game.mode, "rts_camera_current": demo.rts_camera.camera.current,
		"released_body_controlled": first_body.player_controlled, "state_player_controlled": fb_unit.player_controlled,
		"mouse_mode": Input.mouse_mode})
	_expect(game.mode == GameController.Mode.RTS and demo.rts_camera.camera.current, "Tab did not switch to RTS")
	_expect(not first_body.player_controlled and not fb_unit.player_controlled, "released soldier still flagged as controlled")

	# 5. RTS: click-select a South soldier, right-click a ground point, check the order.
	var south := state.units_where(func(u: UnitState) -> bool: return u.faction == 1 and u.kind == UnitState.Kind.SOLDIER and not u.has_order())
	var s_unit: UnitState = south[0]
	var s_body: SoldierBody = sim.body_of(s_unit.id)
	demo.rts_camera.frame(s_body.global_position, PI * 0.5, 60.0)
	await _frames(3)
	var cam := demo.rts_camera.camera
	_click(MOUSE_BUTTON_LEFT, cam.unproject_position(s_body.global_position + Vector3.UP * 1.0))
	await _physics(2)
	var click_ok := rts.selected == [s_unit.id]
	var ground_target := demo.on_ground(s_body.global_position.x - 35.0, s_body.global_position.z + 10.0, 0.0)
	var gp := cam.unproject_position(ground_target)
	_click(MOUSE_BUTTON_RIGHT, gp)
	await _physics(2)
	var order_err := Vector2(s_unit.order_target.x - ground_target.x, s_unit.order_target.z - ground_target.z).length()
	_log("rts_click_order", {"click_selected": click_ok, "selected": rts.selected, "order": s_unit.order,
		"visible_rect": demo.get_viewport().get_visible_rect().size, "window": DisplayServer.window_get_size(),
		"order_target_error_m": order_err, "picked_ground": rts.last_order_target})
	_expect(click_ok, "click did not select the soldier under the cursor")
	_expect(s_unit.order == UnitState.Order.MOVE and order_err < 2.0, "right-click order missing or off by %.1f m" % order_err)
	# Box selection around the whole South group.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for u in state.units_where(func(u: UnitState) -> bool: return u.faction == 1):
		var sp := cam.unproject_position(sim.body_of(u.id).global_position + Vector3.UP)
		lo = Vector2(minf(lo.x, sp.x), minf(lo.y, sp.y))
		hi = Vector2(maxf(hi.x, sp.x), maxf(hi.y, sp.y))
	_drag(lo - Vector2(30, 30), hi + Vector2(30, 30))
	await _physics(2)
	var south_count := state.units_where(func(u: UnitState) -> bool: return u.faction == 1).size()
	_log("rts_box_select", {"selected": rts.selected.size(), "south_units": south_count})
	_expect(rts.selected.size() == south_count, "box selected %d of %d South units" % [rts.selected.size(), south_count])
	if shots:
		var g_body := sim.body_of(group[0])
		demo.rts_camera.frame(g_body.global_position if g_body else demo.area_center, 0.4, 55.0)
		await _frames(40)
		_shot("rts_group_55m")
		demo.rts_camera.frame(demo.area_center + Vector3(50, 0, -30), 0.6, 160.0)
		await _frames(40)
		_shot("rts_overview_160m")

	# 6. Repeated switches: possess a different soldier each time via selection + Tab.
	var moving_ids := []
	var saved_targets := {}
	for u in state.all_units():
		if u.has_order():
			moving_ids.append(u.id)
			saved_targets[u.id] = u.order_target
	var cycle := []
	for u in state.soldiers():
		cycle.append(u.id)
	var max_jump := 0.0
	var max_speed_ratio := 0.0
	var max_ticks := 0
	var orders_kept := true
	var counts_kept := true
	var possessed_seq := []
	var tick_s := 1.0 / Engine.physics_ticks_per_second
	for i in 12:
		var before := _positions()
		var t0 := Engine.get_physics_frames()
		if game.mode == GameController.Mode.RTS:
			var pick: int = cycle[(i / 2) % cycle.size()]
			rts.select([pick])
		_press(KEY_TAB)
		await _physics(1)
		var after := _positions()
		# A long frame (camera switch, streaming) lets physics catch up with several ticks,
		# so judge continuity against the distance a soldier can legitimately cover.
		var ticks := maxi(Engine.get_physics_frames() - t0, 1)
		max_ticks = maxi(max_ticks, ticks)
		for id in before:
			if after.has(id):
				var d: float = before[id].distance_to(after[id])
				max_jump = maxf(max_jump, d)
				max_speed_ratio = maxf(max_speed_ratio, d / (ticks * tick_s * 7.5))
		if game.mode == GameController.Mode.FPS:
			possessed_seq.append(game.possessed_id)
		counts_kept = counts_kept and sim.bodies.size() == state.units.size() and state.units.size() == soldiers + 2
		for id in moving_ids:
			var u := state.get_unit(id)
			if u.has_order() and u.order_target != saved_targets[id]:
				orders_kept = false
	# Any body per id is unique and matches.
	var seen := {}
	var unique_bodies := true
	for id in sim.bodies:
		var b: Node = sim.bodies[id]
		if seen.has(b) or b.unit.id != id:
			unique_bodies = false
		seen[b] = true
	_log("switching", {"switches": 12, "possessed_sequence": possessed_seq, "max_position_change_m": max_jump,
		"max_physics_ticks_per_switch": max_ticks, "max_change_over_sprint_distance": snappedf(max_speed_ratio, 0.01),
		"orders_preserved": orders_kept, "counts_preserved": counts_kept, "unique_bodies": unique_bodies,
		"final_mode": game.mode, "units": state.units.size(), "bodies": sim.bodies.size()})
	_expect(max_speed_ratio <= 1.0, "a unit moved %.2fx farther than sprint speed allows across a switch" % max_speed_ratio)
	_expect(orders_kept and counts_kept and unique_bodies, "orders, counts or body uniqueness broken by switching")
	_expect(possessed_seq.size() >= 5, "possession sequence too short: %s" % str(possessed_seq))
	if shots:
		# Possess a soldier of the other row through the tactical controls and look at the group.
		if game.mode == GameController.Mode.RTS:
			rts.select([cycle[7]])
			_press(KEY_TAB)
			await _physics(2)
		var pb := game.possessed_body()
		var look_at := sim.body_of(group[0]).global_position if sim.body_of(group[0]) else demo.area_center
		_aim(pb, look_at)
		await _frames(30)
		_shot("fps_possessed_other_soldier")

	# 7. Arrival: the North group reaches its targets and stays there.
	if game.mode == GameController.Mode.FPS:
		_press(KEY_TAB)
		await _physics(2)
	var t_wait := 0.0
	while t_wait < 60.0:
		var done := true
		for id in group:
			if state.get_unit(id).has_order():
				done = false
		if done:
			break
		await _seconds(0.5)
		t_wait += 0.5
	var arrive := {}
	var arrived := 0
	var dist_after := _distances(group, target)
	for id in group:
		var u := state.get_unit(id)
		arrive[str(id)] = {"state": u.move_state, "dist_to_formation_target_m": snappedf(dist_after[id], 0.01)}
		if u.move_state == UnitState.MoveState.ARRIVED:
			arrived += 1
	var p_before := _positions()
	await _seconds(2.0)
	var p_after := _positions()
	var drift := 0.0
	for id in group:
		drift = maxf(drift, p_before[id].distance_to(p_after[id]))
	_log("arrival", {"waited_s": t_wait, "arrived": arrived, "of": group.size(), "max_drift_after_arrival_m": drift, "per_unit": arrive})
	_expect(arrived == group.size(), "%d of %d soldiers did not arrive" % [group.size() - arrived, group.size()])
	_expect(drift < 0.5, "arrived soldiers drifted %.2f m" % drift)

	# 8. Suspended order resumes: order a soldier, possess it, walk it away, release.
	var sub: UnitState = north[north.size() - 1]
	var sub_body: SoldierBody = sim.body_of(sub.id)
	var sub_target := demo.on_ground(sub_body.global_position.x + 45.0, sub_body.global_position.z, 0.0)
	state.issue_move(sub.id, sub_target)
	await _seconds(1.0)
	game.possess(sub.id)
	await _physics(2)
	var p_possess := sub_body.global_position
	sub_body.rotation.y = PI  # face south: open ground, away from the target to the east
	Input.action_press("move_forward")
	await _seconds(1.5)
	Input.action_release("move_forward")
	var walked := sub_body.global_position.distance_to(p_possess)
	var order_kept := sub.order == UnitState.Order.MOVE and sub.order_target == sub_target
	var d_release := Vector2(sub_body.global_position.x - sub_target.x, sub_body.global_position.z - sub_target.z).length()
	game.enter_rts()
	await _seconds(3.0)
	var d_resumed := Vector2(sub_body.global_position.x - sub_target.x, sub_body.global_position.z - sub_target.z).length()
	_log("suspend_resume", {"walked_by_player_m": walked, "order_kept_while_possessed": order_kept,
		"distance_at_release_m": d_release, "distance_3s_later_m": d_resumed, "state": sub.move_state})
	_expect(walked > 3.0, "player input did not move the possessed soldier")
	_expect(order_kept, "order lost during possession")
	_expect(d_resumed < d_release - 5.0, "soldier did not resume its order after release")

	# 9. Abstract tier: a unit with no body moves by the state alone.
	var ghost := state.add_unit(UnitState.Kind.SOLDIER, 0, demo.on_ground(demo.area_center.x, demo.area_center.z + 40.0, 0.0), 0.0, "ghost")
	state.issue_move(ghost.id, ghost.position + Vector3(30, 0, 0))
	var g0 := ghost.position
	await _seconds(2.0)
	var g_moved := g0.distance_to(ghost.position)
	await _seconds(6.0)
	_log("abstract_tier", {"has_body": ghost.has_body, "moved_in_2s_m": g_moved, "final_state": ghost.move_state,
		"final_distance_m": Vector2(ghost.position.x - (g0.x + 30.0), ghost.position.z - g0.z).length()})
	_expect(not ghost.has_body and g_moved > 7.0 and ghost.move_state == UnitState.MoveState.ARRIVED, "abstract unit did not travel and arrive")
	state.remove_unit(ghost.id)

	# 10. Frame times in both views (VSync off).
	var perf := {}
	demo.rts_camera.frame(demo.area_center + Vector3(40, 0, -20), 0.6, 140.0)
	perf["rts_140m"] = await _measure(180)
	game.possess(cycle[0])
	await _physics(2)
	perf["fps"] = await _measure(180)
	_log("performance", perf)
	_expect(perf.rts_140m.frame_ms_avg < 33.0 and perf.fps.frame_ms_avg < 33.0, "average frame time above 33 ms")

	_finish()


# ------------------------------------------------------------------------------

func _finish() -> void:
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/core_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("CORE %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func _log(name: String, data: Dictionary) -> void:
	results[name] = data
	print("CORE %s %s" % [name, JSON.stringify(data)])


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _physics(n: int) -> void:
	for i in n:
		await tree.physics_frame
	await tree.process_frame


func _seconds(s: float) -> void:
	await tree.create_timer(s).timeout


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


## Injected mouse events carry window pixels; Camera3D.unproject_position gives logical
## (stretched canvas) coordinates, so convert with the viewport's final transform.
func _win(pos: Vector2) -> Vector2:
	return demo.get_viewport().get_final_transform() * pos


func _click(button: MouseButton, pos: Vector2, double := false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = _win(pos)
	ev.global_position = _win(pos)
	ev.pressed = true
	ev.double_click = double
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	up.double_click = false
	Input.parse_input_event(up)


func _drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = _win(from)
	down.global_position = _win(from)
	down.pressed = true
	Input.parse_input_event(down)
	var mv := InputEventMouseMotion.new()
	mv.position = _win(to)
	mv.global_position = _win(to)
	mv.relative = _win(to) - _win(from)
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = _win(to)
	up.global_position = _win(to)
	up.pressed = false
	Input.parse_input_event(up)


func _positions() -> Dictionary:
	var out := {}
	for u in demo.sim.state.all_units():
		out[u.id] = u.position
	return out


func _distances(ids: Array, target := Vector3.INF) -> Dictionary:
	var out := {}
	for id in ids:
		var u := demo.sim.state.get_unit(id)
		var t := u.order_target if target == Vector3.INF else target
		out[id] = Vector2(u.position.x - t.x, u.position.z - t.z).length()
	return out


func _aim(body: SoldierBody, at: Vector3) -> void:
	var d := at - body.global_position
	body.rotation.y = atan2(-d.x, -d.z)
	body.head.rotation.x = clampf(asin(clampf(d.normalized().y, -1.0, 1.0)), -0.6, 0.6)


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/core01_%s.jpg" % [_shot_dir, name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("CORE shot: ", path)


func _measure(frames: int) -> Dictionary:
	var ms := PackedFloat32Array()
	await _frames(10)
	for i in frames:
		var t := Time.get_ticks_usec()
		await tree.process_frame
		ms.append((Time.get_ticks_usec() - t) / 1000.0)
	var sorted := ms.duplicate()
	sorted.sort()
	var sum := 0.0
	for v in ms:
		sum += v
	return {"frames": frames, "frame_ms_avg": snappedf(sum / frames, 0.01), "frame_ms_p99": snappedf(sorted[int(frames * 0.99)], 0.01),
		"frame_ms_max": snappedf(sorted[frames - 1], 0.01),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"nav_ms": snappedf(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0, 0.01)}

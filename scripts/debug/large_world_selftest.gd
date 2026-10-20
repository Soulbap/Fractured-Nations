## Scripted checks of WORLD-CORE-02 on the real 20 x 20 km world.
##
##   Godot.exe --path . --resolution 1600x900 --log-file wc02.log res://scenes/game/world_core_02.tscn -- --large-test [--shots]
##
## Short and targeted: spawn layout and tiers, abstract execution of orders away from the
## camera, 8 km possession jumps through the real input actions (1/2/3, Tab, N, P), terrain
## collision / navigation / vegetation at the new place, return to the first site and
## comparison of identity, position and order of every unit, body <-> abstract transitions
## in transit, and frame times. Prints "LARGE <check> <json>", writes
## res://benchmarks/raw/large_test.json and (with --shots) docs/screenshots/core02_*.jpg.
class_name LargeWorldSelfTest
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
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var sim := demo.sim
	var state := sim.state
	var game := demo.game
	var rts := demo.rts
	var detail := demo.detail
	var veg := demo.vegetation
	await _physics(60)

	# 1. Layout: 26 soldiers + 3 vehicles at three sites kilometers apart; detail only at A.
	var sites := demo.sites
	var site_d := []
	for i in 3:
		for j in range(i + 1, 3):
			site_d.append(snappedf(Vector2(sites[i].position.x - sites[j].position.x, sites[i].position.z - sites[j].position.z).length(), 1.0))
	var per_site := [0, 0, 0]
	for u in state.soldiers():
		per_site[_site_of(u.position)] += 1
	var near_a_bodies := 0
	var floor_ok := 0
	var floor_n := 0
	for id in sim.bodies:
		var b: Node3D = sim.bodies[id]
		if b is SoldierBody:
			floor_n += 1
			if b.is_on_floor():
				floor_ok += 1
		if _site_of(b.unit.position) == 0:
			near_a_bodies += 1
	_log("layout", {"world_m": demo.config.snapped_size(), "soldiers": state.count_of(UnitState.Kind.SOLDIER), "vehicles": state.count_of(UnitState.Kind.VEHICLE),
		"soldiers_per_site": per_site, "site_distances_m": site_d, "bodies": sim.bodies.size(), "proxies": sim.proxies.size(),
		"bodies_at_site_a": near_a_bodies, "soldiers_on_floor": [floor_ok, floor_n], "terrain_collision_mode": demo.terrain.collision_mode,
		"nav_first_bake": demo.nav_info, "possessed": game.possessed_id, "mode": game.mode})
	_expect(state.count_of(UnitState.Kind.SOLDIER) == 26 and per_site == [10, 8, 8], "unexpected soldier layout %s" % str(per_site))
	_expect(sim.bodies.size() + sim.proxies.size() == state.units.size(), "a unit has neither a body nor a proxy")
	_expect(sim.bodies.size() == near_a_bodies and sim.bodies.size() > 0 and sim.bodies.size() < state.units.size(), "bodies exist away from the camera")
	_expect(floor_ok == floor_n and floor_n > 0, "%d of %d soldiers not on the floor at start" % [floor_n - floor_ok, floor_n])
	_expect(game.mode == GameController.Mode.FPS and game.possessed_body() != null, "did not start possessing a soldier")
	var all_ids := state.units.keys()
	all_ids.sort()

	# 2. Orders keep running where nobody looks: the B and C walkers are abstract and progress.
	var away := state.units_where(func(u: UnitState) -> bool: return u.has_order() and _site_of(u.position) != 0)
	var d0 := _target_dist(away)
	var p0 := _pos_of(away)
	await _seconds(4.0)
	var d1 := _target_dist(away)
	var progressed := 0
	var bodyless := 0
	for u in away:
		if d1[u.id] < d0[u.id] - 10.0:
			progressed += 1
		if not u.has_body:
			bodyless += 1
	_log("abstract_orders_away", {"units": away.size(), "bodyless": bodyless, "progressed_10m_in_4s": progressed,
		"example": [d0[away[0].id], d1[away[0].id]], "states": away.map(func(u: UnitState) -> int: return u.move_state)})
	_expect(away.size() >= 6 and bodyless == away.size() and progressed == away.size(), "orders away from the camera did not run in the abstract tier")

	# 3. Command at A in first person's tactical view: Tab, box-select a group, right-click the ground.
	_press(KEY_TAB)
	await _physics(3)
	var a_units := state.units_where(func(u: UnitState) -> bool: return u.kind == UnitState.Kind.SOLDIER and _site_of(u.position) == 0 and not u.has_order() and u.id != game.possessed_id)
	var a_group := a_units.slice(0, 4).map(func(u: UnitState) -> int: return u.id)
	demo.rts_camera.frame(sites[0].position + Vector3(0, 0, 10), 0.0, 90.0)
	await _frames(5)
	rts.select(a_group)
	var cam := demo.rts_camera.camera
	var ground := demo.on_ground(sites[0].position.x - 30.0, sites[0].position.z - 60.0, 0.0)
	_click(MOUSE_BUTTON_RIGHT, cam.unproject_position(ground))
	await _physics(3)
	var a_ordered := 0
	for id in a_group:
		if state.get_unit(id).order == UnitState.Order.MOVE:
			a_ordered += 1
	_log("rts_order_at_a", {"selected": rts.selected.size(), "ordered": a_ordered, "ground_error_m": snappedf(Vector2(rts.last_order_target.x - ground.x, rts.last_order_target.z - ground.z).length(), 0.01)})
	_expect(a_ordered == 4, "right-click order reached %d of 4 soldiers" % a_ordered)
	if shots:
		demo.rts_camera.frame(sites[0].position + Vector3(10, 0, -20), 0.5, 120.0)
		await _frames(45)
		_shot("rts_site_a")

	# 4. Snapshot, then jump ~8 km to site B with the real key (RTS: camera, then possess in FPS).
	var snap_a := _identity()
	var pos_before := _positions()
	var orders_before := _orders()
	var old_possessed := game.possessed_id
	var t_sim := state.time
	_press(KEY_2)  # tactical: frame the camera on site B
	await _seconds(1.0)
	var b_bodies_rts := 0
	for id in sim.bodies:
		if _site_of(sim.bodies[id].unit.position) == 1:
			b_bodies_rts += 1
	_log("rts_jump_to_b", {"focus": [demo.rts_camera.focus.x, demo.rts_camera.focus.z], "dist_to_site_b_m": _flat(demo.rts_camera.focus, sites[1].position),
		"bodies_at_b": b_bodies_rts, "bodies_total": sim.bodies.size(), "nav_bakes": detail.bake_count, "nav_center_to_b_m": _flat(detail.nav_center, sites[1].position),
		"terrain_camera_is_anchor": demo.terrain.get_camera() == detail.anchor_cam})
	_expect(_flat(demo.rts_camera.focus, sites[1].position) < 30.0, "tactical camera did not reach site B")
	_expect(b_bodies_rts >= 8 and sim.bodies.size() == b_bodies_rts, "site B units did not get bodies in the tactical view (%d, total %d)" % [b_bodies_rts, sim.bodies.size()])
	_expect(demo.terrain.get_camera() == detail.anchor_cam, "terrain not following the anchor camera in RTS")
	# Ground and navigation exist under the new focus: ray + navmesh query.
	var gp := _ground_ray(demo.rts_camera.focus)
	var nav_pt := NavigationServer3D.map_get_closest_point(demo.navigation.get_navigation_map(), demo.rts_camera.focus)
	_log("rts_b_ground", {"collision_ray_hit_y": gp.y, "terrain_y": demo.ground_height(demo.rts_camera.focus), "navmesh_point_dist_m": snappedf(nav_pt.distance_to(demo.rts_camera.focus), 0.01)})
	_expect(gp.is_finite() and absf(gp.y - demo.ground_height(demo.rts_camera.focus)) < 1.0, "no terrain collision under the tactical focus at B")
	_expect(nav_pt.distance_to(demo.rts_camera.focus) < 3.0, "navmesh missing under the tactical focus at B")
	if shots:
		demo.rts_camera.frame(sites[1].position + Vector3(10, 0, 20), 0.6, 110.0)
		await _frames(45)
		_shot("rts_site_b")
	# Select one B soldier by clicking it and possess it with P.
	demo.rts_camera.frame(sites[1].position + Vector3(0, 0, 8), 0.0, 60.0)
	await _frames(4)
	var b_target: UnitState = state.units_where(func(u: UnitState) -> bool: return u.kind == UnitState.Kind.SOLDIER and _site_of(u.position) == 1 and not u.has_order())[0]
	cam = demo.rts_camera.camera
	_click(MOUSE_BUTTON_LEFT, cam.unproject_position(b_target.position + Vector3.UP))
	await _physics(2)
	var clicked := rts.selected == [b_target.id]
	var t_possess := Time.get_ticks_usec()
	_press(KEY_P)
	await _physics(1)
	var possess_ms := (Time.get_ticks_usec() - t_possess) / 1000.0
	await _physics(12)
	var pb := game.possessed_body()
	_log("possess_at_b", {"clicked_selected": clicked, "possessed": game.possessed_id, "expected": b_target.id, "mode": game.mode,
		"camera_current": pb != null and pb.camera.current, "on_floor": pb != null and pb.is_on_floor(), "possess_call_ms": snappedf(possess_ms, 0.1),
		"terrain_camera_is_body_cam": pb != null and demo.terrain.get_camera() == pb.camera})
	_expect(clicked, "click did not select the B soldier")
	_expect(game.possessed_id == b_target.id and game.mode == GameController.Mode.FPS and pb != null and pb.camera.current, "possession at B failed")
	_expect(pb != null and pb.is_on_floor(), "possessed soldier at B not on the floor")
	# FPS at B: walk with the real input action; stays on the terrain.
	var wp := pb.global_position
	pb.rotation.y = 0.0
	Input.action_press("move_forward")
	await _seconds(2.0)
	Input.action_release("move_forward")
	var walked := pb.global_position.distance_to(wp)
	var above := pb.global_position.y - demo.ground_height(pb.global_position)
	await _frames(40)
	var vs := veg.get_stats()
	var grass_ok: bool = demo.world.get_node("Grass").active
	_log("fps_at_b", {"walked_m": snappedf(walked, 0.01), "height_above_terrain_m": snappedf(above, 0.02), "vegetation": vs, "grass_active": grass_ok,
		"tree_colliders": demo.world.get_node("InstanceColliderStreamer").active_count, "nav_bakes": detail.bake_count})
	_expect(walked > 5.0 and absf(above) < 0.6, "FPS movement at B wrong (walked %.1f m, %.2f m above terrain)" % [walked, above])
	_expect(vs.active_mmis > 0 and vs.active_instances > 0, "no vegetation streamed in at B")
	_expect(grass_ok, "grass layer inactive at B")
	if shots:
		_aim(pb, pb.global_position + Vector3(-12, 1.0, -40))
		await _frames(30)
		_shot("fps_site_b")

	# 5. Orders given at B: the possessed soldier's own order, and the rest of the world kept going.
	var b_other: UnitState = state.units_where(func(u: UnitState) -> bool: return u.kind == UnitState.Kind.SOLDIER and _site_of(u.position) == 1 and u.id != game.possessed_id and not u.has_order())[0]
	state.issue_move(b_other.id, demo.on_ground(b_other.position.x + 25.0, b_other.position.z + 20.0, 0.0))
	await _seconds(1.0)
	var a_abstract := 0
	for id in a_group:
		var u := state.get_unit(id)
		if not u.has_body and (u.move_state == UnitState.MoveState.MOVING or u.move_state == UnitState.MoveState.ARRIVED):
			a_abstract += 1
	_log("a_runs_while_at_b", {"a_group_abstract_and_executing": a_abstract, "of": a_group.size(), "sim_time_advanced_s": snappedf(state.time - t_sim, 0.1)})
	_expect(a_abstract == a_group.size(), "site A group stopped executing its order while the camera is at B")

	# 6. Jump to C through RTS (Tab), possess a C soldier with N-cycling and with key 3 in FPS.
	_press(KEY_3)  # FPS: possess the soldier nearest to site C
	await _physics(14)
	var cpb := game.possessed_body()
	var at_c := cpb != null and _site_of(cpb.global_position) == 2
	_log("fps_jump_to_c", {"possessed": game.possessed_id, "site": _site_of(state.get_unit(game.possessed_id).position), "mode": game.mode,
		"on_floor": cpb != null and cpb.is_on_floor(), "bodies": sim.bodies.size(), "bodies_at_c": sim.bodies.values().filter(func(b: Node3D) -> bool: return _site_of(b.unit.position) == 2).size()})
	_expect(at_c and game.mode == GameController.Mode.FPS and cpb.is_on_floor(), "key 3 did not put the player on a soldier at C")
	# An order at C walked by the real navmesh: ordered 45 m, arrives.
	var c_mover: UnitState = state.units_where(func(u: UnitState) -> bool: return u.kind == UnitState.Kind.SOLDIER and _site_of(u.position) == 2 and u.id != game.possessed_id and not u.has_order())[0]
	var c_target := demo.on_ground(c_mover.position.x, c_mover.position.z + 45.0, 0.0)
	state.issue_move(c_mover.id, c_target)
	var t_arr := 0.0
	while t_arr < 30.0 and c_mover.has_order():
		await _seconds(0.5)
		t_arr += 0.5
	var c_err := Vector2(c_mover.position.x - c_target.x, c_mover.position.z - c_target.z).length()
	_log("order_at_c", {"state": c_mover.move_state, "seconds": t_arr, "error_m": snappedf(c_err, 0.01), "has_body": c_mover.has_body})
	_expect(c_mover.move_state == UnitState.MoveState.ARRIVED and c_err < 3.7, "order at C: state %d, %.1f m off" % [c_mover.move_state, c_err])
	if shots:
		_press(KEY_TAB)
		await _physics(3)
		demo.rts_camera.frame(sites[2].position, 0.3, 150.0)
		await _frames(45)
		_shot("rts_site_c")
		demo.rts_camera.frame(sites[2].position, 0.3, 2800.0)
		await _frames(45)
		_shot("rts_overview_2800m")
		_press(KEY_TAB)
		await _physics(3)

	# 7. N cycles through every soldier of the world, 26 presses visit each once.
	var seen := {}
	var far_jumps := 0
	var last_pos := state.get_unit(game.possessed_id).position
	for i in 26:
		_press(KEY_N)
		await _physics(1)
		var cu := state.get_unit(game.possessed_id)
		seen[cu.id] = true
		if _flat(cu.position, last_pos) > 1000.0:
			far_jumps += 1
		last_pos = cu.position
	await _physics(10)
	var cb := game.possessed_body()
	_log("cycle_all_soldiers", {"distinct_visited": seen.size(), "far_jumps_over_1km": far_jumps, "final_on_floor": cb != null and cb.is_on_floor(),
		"bodies": sim.bodies.size(), "proxies": sim.proxies.size(), "unique_units": state.units.size()})
	_expect(seen.size() == 26, "N visited %d of 26 soldiers" % seen.size())
	_expect(sim.bodies.size() + sim.proxies.size() == state.units.size() and cb != null and cb.is_on_floor(), "tier bookkeeping broken after cycling")

	# 8. Return to site A (key 1) and compare every unit with what we left.
	_press(KEY_1)
	await _physics(20)
	var snap_back := _identity()
	var same_ids: bool = snap_back.keys() == snap_a.keys()
	var ident_ok := same_ids
	for id in snap_a:
		if snap_back.get(id) != snap_a[id]:
			ident_ok = false
	var idle_drift := 0.0
	var idle_n := 0
	var arrived_ok := 0
	var ordered_n := 0
	var order_kept := 0
	for id in all_ids:
		var u := state.get_unit(id)
		var o: Dictionary = orders_before[id]
		if o.order == UnitState.Order.NONE and _site_of(pos_before[id]) == 0 and id != game.possessed_id and id != old_possessed:
			idle_drift = maxf(idle_drift, _flat(u.position, pos_before[id]))
			idle_n += 1
		elif o.order == UnitState.Order.MOVE and _site_of(pos_before[id]) == 0:
			ordered_n += 1
			if u.order == UnitState.Order.NONE and u.move_state == UnitState.MoveState.ARRIVED and _flat(u.position, o.target) < 3.7:
				arrived_ok += 1
			elif u.order == UnitState.Order.MOVE and u.order_target == o.target:
				order_kept += 1
	_log("return_to_a", {"identity_ok": ident_ok, "ids": all_ids.size(), "idle_units_checked": idle_n, "max_idle_drift_m": snappedf(idle_drift, 0.001),
		"ordered_units_at_a": ordered_n, "finished_their_walk": arrived_ok, "still_executing_same_order": order_kept,
		"bodies": sim.bodies.size(), "proxies": sim.proxies.size(), "possessed_site": _site_of(state.get_unit(game.possessed_id).position)})
	_expect(ident_ok, "unit identity (id, name, kind, faction) changed during the trip")
	_expect(idle_n >= 3 and idle_drift < 0.25, "idle units at A drifted %.3f m (%d checked)" % [idle_drift, idle_n])
	_expect(ordered_n > 0 and arrived_ok + order_kept == ordered_n, "orders at A lost: %d finished, %d running of %d" % [arrived_ok, order_kept, ordered_n])
	_expect(game.possessed_body() != null and _site_of(state.get_unit(game.possessed_id).position) == 0, "key 1 did not return to site A")
	if shots:
		await _frames(30)
		_shot("fps_site_a_return")

	# 9. Tier transitions in transit: one soldier walks out of the detail radius and back.
	var tr: UnitState = state.units_where(func(u: UnitState) -> bool: return u.kind == UnitState.Kind.SOLDIER and u.has_body and u.id != game.possessed_id and not u.has_order() and _flat(u.position, game.possessed_body().global_position) < 40.0)[0]
	var tr_id := tr.id
	var tr_name := tr.unit_name
	var tr_body := sim.body_of(tr_id) as SoldierBody
	tr.speed = 12.0
	tr_body.walk_speed = 12.0
	tr_body.nav.max_speed = 12.0
	var obs_pos := game.possessed_body().global_position
	var out_dir := Vector3(1, 0, 0)
	var out_target := demo.on_ground(obs_pos.x + 230.0, obs_pos.z, 0.0)
	state.issue_move(tr_id, out_target)
	var lost_body_at := -1.0
	var max_step := 0.0
	var prev := tr.position
	var t := 0.0
	var phases := []
	while t < 40.0 and tr.order == UnitState.Order.MOVE:
		var f0 := Engine.get_physics_frames()
		await _physics(3)
		var ticks := maxi(Engine.get_physics_frames() - f0, 1)
		t += ticks / 60.0
		# Judge continuity against what walking at 12 m/s covers in the elapsed ticks.
		var ratio := _flat(tr.position, prev) / (ticks * 12.0 / 60.0)
		# The final step may include the abstract tier's snap onto the target (< 1 m).
		if tr.order == UnitState.Order.MOVE:
			max_step = maxf(max_step, ratio)
		prev = tr.position
		if phases.is_empty() or phases[-1] != tr.has_body:
			phases.append(tr.has_body)
			if not tr.has_body:
				lost_body_at = _flat(tr.position, game.possessed_body().global_position)
	var out_err := _flat(tr.position, out_target)
	var same_unit := state.get_unit(tr_id) == tr and tr.unit_name == tr_name
	# Inbound: ordered to a point 100 m from the observer; abstract until 120 m, then a body.
	var in_target := demo.on_ground(obs_pos.x + 100.0, obs_pos.z + 10.0, 0.0)
	state.issue_move(tr_id, in_target)
	var gained_body_at := -1.0
	var phases_in := [tr.has_body]
	t = 0.0
	while t < 40.0 and tr.order == UnitState.Order.MOVE:
		await _physics(3)
		t += 3.0 / 60.0
		if phases_in[-1] != tr.has_body:
			phases_in.append(tr.has_body)
			print("LARGE inbound tier -> %s at %.1f m from observer, obs %s unit %s order %d state %d" % [tr.has_body, _flat(tr.position, game.possessed_body().global_position), str(game.possessed_body().global_position), str(tr.position), tr.order, tr.move_state])
			if tr.has_body:
				gained_body_at = _flat(tr.position, game.possessed_body().global_position)
	var in_err := _flat(tr.position, in_target)
	_log("transitions_in_transit", {"out_tiers": phases, "demoted_at_m": snappedf(lost_body_at, 0.1), "out_arrival_error_m": snappedf(out_err, 0.01), "out_state": "arrived" if tr.move_state == UnitState.MoveState.ARRIVED else tr.move_state,
		"max_step_over_walk_distance": snappedf(max_step, 0.01), "in_tiers": phases_in, "promoted_at_m": snappedf(gained_body_at, 0.1),
		"in_arrival_error_m": snappedf(in_err, 0.01), "in_state": tr.move_state, "same_record": same_unit, "has_body_now": tr.has_body})
	_expect(phases == [true, false] and lost_body_at > detail.demote_radius - 5.0 and lost_body_at < detail.demote_radius + 15.0, "outbound tier change wrong: %s at %.0f m" % [str(phases), lost_body_at])
	_expect(out_err < 1.5 and tr.move_state == UnitState.MoveState.ARRIVED, "abstract tier did not finish the outbound order (%.1f m)" % out_err)
	_expect(max_step <= 1.2, "unit moved %.2fx its walking distance across a tier change" % max_step)
	_expect(phases_in == [false, true] and gained_body_at < detail.promote_radius + 8.0 and gained_body_at > 60.0, "inbound tier change wrong: %s at %.0f m" % [str(phases_in), gained_body_at])
	_expect(in_err < 3.7 and tr.move_state == UnitState.MoveState.ARRIVED and same_unit, "inbound order did not finish (%.1f m)" % in_err)

	# 10. Costs: frame times in FPS, RTS close, RTS far; navmesh bakes; a far possession.
	var perf := {}
	perf["fps_site_a"] = await _measure(150)
	_press(KEY_TAB)
	await _physics(3)
	demo.rts_camera.frame(sites[0].position, 0.5, 160.0)
	perf["rts_160m"] = await _measure(150)
	demo.rts_camera.frame(sites[0].position, 0.5, 1500.0)
	perf["rts_1500m"] = await _measure(150)
	var jump_ms := []
	for i in 3:
		var tgt: Vector3 = sites[(i + 1) % 3].position
		var t0 := Time.get_ticks_usec()
		var best := _nearest_soldier(tgt)
		game.possess(best)
		jump_ms.append(snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1))
		await _physics(3)
		_press(KEY_TAB)
		await _physics(3)
	perf["possess_jump_ms"] = jump_ms
	perf["nav_last_bake"] = detail.last_bake
	perf["nav_bakes_total"] = detail.bake_count
	perf["promotions"] = detail.promotions
	perf["demotions"] = detail.demotions
	perf["memory_static_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 1.0)
	perf["objects"] = Performance.get_monitor(Performance.OBJECT_COUNT)
	perf["terrain_collision_radius"] = demo.terrain.collision_radius
	_log("performance", perf)
	_expect(perf.fps_site_a.frame_ms_avg < 33.0 and perf.rts_160m.frame_ms_avg < 33.0 and perf.rts_1500m.frame_ms_avg < 33.0, "average frame time above 33 ms")
	_expect(not jump_ms.any(func(v: float) -> bool: return v > 1500.0), "a far possession took more than 1.5 s")

	_finish()


# ------------------------------------------------------------------------------

func _site_of(p: Vector3) -> int:
	var best := -1
	var best_d := 600.0
	for i in demo.sites.size():
		var d := _flat(p, demo.sites[i].position)
		if d < best_d:
			best_d = d
			best = i
	return best


func _nearest_soldier(p: Vector3) -> int:
	var best := -1
	var best_d := INF
	for u in demo.sim.state.soldiers():
		var d := _flat(u.position, p)
		if d < best_d:
			best_d = d
			best = u.id
	return best


func _ground_ray(p: Vector3) -> Vector3:
	var space := demo.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 400.0, p + Vector3.DOWN * 400.0)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3.INF


func _identity() -> Dictionary:
	var out := {}
	for u in demo.sim.state.all_units():
		out[u.id] = [u.unit_name, u.kind, u.faction, u.max_health]
	return out


func _orders() -> Dictionary:
	var out := {}
	for u in demo.sim.state.all_units():
		out[u.id] = {"order": u.order, "target": u.order_target}
	return out


func _pos_of(units: Array) -> Dictionary:
	var out := {}
	for u in units:
		out[u.id] = u.position
	return out


func _target_dist(units: Array) -> Dictionary:
	var out := {}
	for u in units:
		out[u.id] = _flat(u.position, u.order_target)
	return out


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _finish() -> void:
	# CHARACTER-01: soldiers wear their persisted loadout, pieces attached, proxies in place.
	var ch := CharacterIntegrationCheck.run(demo.sim)
	_log("character01", ch.data)
	for msg in ch.failures:
		_expect(false, msg)
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/large_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("LARGE %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("LARGE FAILED CHECK: ", msg)


func _log(name: String, data: Dictionary) -> void:
	results[name] = data
	print("LARGE %s %s" % [name, JSON.stringify(data)])


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


func _win(pos: Vector2) -> Vector2:
	return demo.get_viewport().get_final_transform() * pos


func _click(button: MouseButton, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = _win(pos)
	ev.global_position = _win(pos)
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _positions() -> Dictionary:
	var out := {}
	for u in demo.sim.state.all_units():
		out[u.id] = u.position
	return out


func _aim(body: SoldierBody, at: Vector3) -> void:
	var d := at - body.global_position
	body.rotation.y = atan2(-d.x, -d.z)
	body.head.rotation.x = clampf(asin(clampf(d.normalized().y, -1.0, 1.0)), -0.6, 0.6)


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/core02_%s.jpg" % [_shot_dir, name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("LARGE shot: ", path)


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

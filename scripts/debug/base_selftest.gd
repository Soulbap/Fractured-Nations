## Scripted checks of WORLD-BASE-01 (construction) on the real 20 x 20 km world.
##
##   Godot.exe --path . --resolution 1600x900 --log-file base.log res://scenes/game/world_core_02.tscn -- --base-test [--shots]
##
## Builds a small military installation through the real construction input (B, type
## selection, cursor, clicks, R, Enter, Esc, X), then checks: placement on flat and
## moderately sloped ground, rejection of steep ground, rotation, cancellation,
## deletion, a closed HESCO perimeter with exact corners, a long fence run, snapping of
## fence to gate, removal of single modules, blocked sections, navmesh carving and a
## soldier walking around the wall, FPS collision, a 7.6 km trip and back, save/clear/load,
## the RTS zoom limits and frame times. Prints "BASE <check> <json>", writes
## res://benchmarks/raw/base_test.json and (with --shots) docs/screenshots/base01_*.jpg.
class_name BaseSelfTest
extends LargeWorldSelfTest

var con: ConstructionController
var sm: StructureManager
var cs: ConstructionState
## Base center (flat ground near site A) and the spots found for the slope checks.
var base := Vector3.ZERO
var _done := false


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	# A script error stops this coroutine; never leave the window hanging.
	tree.create_timer(420.0).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish in 420 s")
		_finish())
	var game := demo.game
	var rig := demo.rts_camera
	await _physics(60)

	# 0. Tactical view and the zoom limits (editable exports, wheel input).
	_press(KEY_TAB)
	await _physics(3)
	base = _find_base_site(demo.sites[0].position)
	rig.frame(base, 0.0, 100.0)
	await _frames(3)
	for i in 40:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _frames(2)
	var zmax := rig.zoom
	for i in 60:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	await _frames(2)
	var zmin := rig.zoom
	_log("rts_zoom_limits", {"zoom_min_property": rig.zoom_min, "zoom_max_property": rig.zoom_max, "reached_max": snappedf(zmax, 0.01), "reached_min": snappedf(zmin, 0.01)})
	_expect(is_equal_approx(zmax, rig.zoom_max) and is_equal_approx(zmin, rig.zoom_min) and is_equal_approx(rig.zoom_min, 5.0) and is_equal_approx(rig.zoom_max, 200.0), "zoom limits not 5..200 m (%.1f..%.1f)" % [zmin, zmax])

	# 1. Construction mode with B.
	rig.frame(base, 0.0, 140.0)
	_press(KEY_B)
	await _frames(3)
	_log("construction_mode", {"active": con.active, "panel_visible": con.panel.visible, "rts_selection_active": demo.rts.active,
		"base_center": [snappedf(base.x, 0.1), snappedf(base.z, 0.1)], "dist_to_site_a_m": _flat(base, demo.sites[0].position)})
	_expect(con.active and con.panel.visible and not demo.rts.active, "B did not enter construction mode")

	# 2. Buildings on flat ground, with rotation (R) and a rejected spot.
	var placed := {}
	placed.cp = await _place(&"command_post", base + Vector3(-6, 0, -14), 0)
	placed.b1 = await _place(&"barracks", base + Vector3(-22, 0, 4), 6)  # R x6 = 90°
	placed.b2 = await _place(&"barracks", base + Vector3(-22, 0, 12), 6)
	placed.b3 = await _place(&"barracks", base + Vector3(-22, 0, 20), 6)
	placed.storage = await _place(&"supply_storage", base + Vector3(18, 0, 14), 0)
	placed.tower1 = await _place(&"guard_tower", base + Vector3(-30, 0, -31), 0)
	placed.tower2 = await _place(&"guard_tower", base + Vector3(29, 0, -31), 0)
	var b1: StructureState = placed.b1
	_log("buildings_flat", {"placed": placed.keys().filter(func(k: String) -> bool: return placed[k] != null),
		"barracks_yaw_deg": snappedf(rad_to_deg(b1.yaw), 0.1) if b1 else null, "structures": cs.count()})
	_expect(placed.values().all(func(s: Variant) -> bool: return s != null), "a building could not be placed on the flat base site")
	_expect(b1 != null and absf(rad_to_deg(b1.yaw) - 90.0) < 0.5, "R rotation was not applied (barracks yaw)")
	# Overlap: a second command post on top of the first is refused.
	var dup := await _place(&"command_post", base + Vector3(-5, 0, -13), 0, false)
	_expect(dup == null and con.check.get("reason", "").begins_with("blocked"), "overlapping building was accepted (%s)" % con.check.get("reason", ""))

	# 3. Moderate slope accepted, steep slope refused (spots searched within 2 km).
	var moderate := _find_slope(&"command_post", 3.0, 6.5)
	# Above the groundwork limit (StructureManager.level_max_slope_deg, WORLD-INTEGRATION-01).
	var steep := _find_slope(&"command_post", sm.level_max_slope_deg + 2.0, 45.0)
	var mod_s: StructureState = null
	var mod_slope := -1.0
	if moderate.is_finite():
		mod_s = await _place(&"command_post", moderate, 0)
		mod_slope = _slope_at(moderate, 6.0)
	var steep_s: StructureState = null
	if steep.is_finite():
		steep_s = await _place(&"command_post", steep, 0, false)
	var steep_reason: String = con.check.get("reason", "")
	_log("slopes", {"moderate_spot": _v(moderate), "moderate_slope_deg": snappedf(mod_slope, 0.1), "moderate_built": mod_s != null,
		"steep_spot": _v(steep), "steep_slope_deg": snappedf(_slope_at(steep, 6.0), 0.1) if steep.is_finite() else -1, "steep_built": steep_s != null, "steep_reason": steep_reason})
	_expect(moderate.is_finite() and mod_s != null, "no command post on moderately sloped ground")
	_expect(steep.is_finite() and steep_s == null and steep_reason.begins_with("too steep"), "steep ground was not refused")
	if shots and steep.is_finite():
		con.select_type(&"command_post")
		rig.frame(steep, 0.6, 45.0)
		await _cursor_at(steep)
		await _frames(30)
		_shot("preview_invalid_steep")
	if mod_s:
		cs.remove(mod_s.id)

	# 4. Cancel (Esc keeps nothing), delete with X + click.
	rig.frame(base, 0.0, 140.0)
	con.select_type(&"vehicle_shelter")
	await _cursor_at(base + Vector3(0, 0, 0))
	var n_before := cs.count()
	_press(KEY_ESCAPE)
	await _frames(2)
	var cancelled := con.tool == ConstructionController.Tool.NONE and cs.count() == n_before
	var temp: StructureState = await _place(&"barracks", base + Vector3(4, 0, 2), 0)
	_press(KEY_X)
	await _frames(2)
	await _cursor_at(temp.instances[0] * Vector3(0, 1.4, 0) if temp else base)
	if shots:
		rig.frame(base + Vector3(4, 0, 2), 0.5, 35.0)
		await _cursor_at(temp.instances[0] * Vector3(0, 1.4, 0))
		await _frames(20)
		_shot("delete_highlight")
	var hovered: bool = not con.hover.is_empty() and temp != null and con.hover.id == temp.id
	_click(MOUSE_BUTTON_LEFT, _screen(temp.instances[0] * Vector3(0, 1.4, 0)))
	await _frames(2)
	var deleted := temp != null and cs.get_structure(temp.id) == null
	_press(KEY_ESCAPE)
	await _frames(2)
	_log("cancel_delete", {"esc_cancelled_tool": cancelled, "delete_hover_found": hovered, "deleted": deleted, "structures": cs.count()})
	_expect(cancelled, "Esc did not cancel the tool without building")
	_expect(hovered and deleted, "delete tool did not remove the clicked building")

	# 5. Closed HESCO perimeter, 4 corners, closed by clicking the start again.
	rig.frame(base, 0.0, 200.0)
	await _frames(3)
	var h := 35.0
	var corners := [base + Vector3(-h, 0, -h), base + Vector3(h, 0, -h), base + Vector3(h, 0, h), base + Vector3(-h, 0, h), base + Vector3(-h, 0, -h)]
	var perim: StructureState = await _draw_line(&"hesco", corners, false)
	var perim_info := _line_info(perim)
	# Cost of a placement alone (camera at rest, so no re-centre bake from camera moves):
	# cell rebuild, grass mask update and the debounced async navmesh bake.
	await _seconds(2.0)
	var probe := cs.add_line(&"concrete_barrier", PackedVector3Array([base + Vector3(-20, 0, 10), base + Vector3(-11, 0, 10)]))
	var hitch := await _worst_frame(1.5)
	perim_info["placement_worst_frame_ms"] = hitch
	perim_info["placement_timings"] = sm.timings.duplicate()
	perim_info["placement_nav"] = {"bake_ms": demo.detail.last_bake.get("bake_ms", -1), "async": demo.detail.last_bake.get("async", false),
		"async_done_ms": demo.detail.last_bake.get("async_done_ms", -1)}
	cs.remove(probe.id)
	await _seconds(1.0)
	_log("hesco_perimeter", perim_info)
	_expect(perim != null and perim.points.size() == 5 and perim.points[0].is_equal_approx(perim.points[4]), "HESCO perimeter did not close on its start")
	_expect(perim != null and perim_info.max_joint_error_m < 0.01 and perim_info.corner_gap_m < 0.01, "HESCO cells do not meet exactly (joint %.3f, corner %.3f)" % [perim_info.get("max_joint_error_m", -1), perim_info.get("corner_gap_m", -1)])
	if shots:
		rig.frame(base + Vector3(-h, 0, -h), 0.7, 40.0)
		await _frames(40)
		_shot("hesco_corner_rts")

	# 6. Gate in the south wall: delete 5 cells one by one (single-module removal).
	con.select_delete()
	var removed_ok := 0
	# The five cells in the middle of the south wall (third segment).
	var south: Array[int] = []
	var hmods := ModularLine.modules(StructureCatalog.get_def(&"hesco"), perim.points)
	var seg2: Array[int] = []
	for i in hmods.size():
		if hmods[i].segment == 2:
			seg2.append(i)
	var mid := seg2.size() / 2
	for k in range(mid - 2, mid + 3):
		south.append(seg2[k])
	rig.frame(base + Vector3(0, 0, h), 0.0, 40.0)
	await _frames(5)
	for i in south:
		var tgt := perim.instances[i] * Vector3(0, 0.9, 0)
		await _cursor_at(tgt)
		if con.hover.get("id", -1) == perim.id and con.hover.get("index", -1) == i:
			_click(MOUSE_BUTTON_LEFT, _screen(tgt))
			await _frames(2)
			if perim.is_removed(i):
				removed_ok += 1
	con.clear_tool()
	_log("single_module_removal", {"targets": south, "removed": removed_ok, "line_still_exists": cs.get_structure(perim.id) != null, "line_removed_list": Array(perim.removed)})
	_expect(south.size() == 5 and removed_ok == 5 and cs.get_structure(perim.id) != null, "single HESCO modules could not be removed (%d of %d)" % [removed_ok, south.size()])

	# 7. Concrete chicane in front of the opening (multi-point, pitch fit).
	var chic: StructureState = await _draw_line(&"concrete_barrier", [base + Vector3(-12, 0, h + 7), base + Vector3(-3, 0, h + 7), base + Vector3(-3, 0, h + 12)], true)
	_log("concrete_line", _line_info(chic))
	_expect(chic != null and chic.built_count() >= 4, "concrete barrier line not built")

	# 8. Vehicle yard east of the wall: fence L -> gate snapped to its end -> fence from the
	# gate's other post (snapping both ways), vehicle shelter inside.
	var y0 := base + Vector3(h + 4, 0, -h)
	var fence1: StructureState = await _draw_line(&"fence", [y0, y0 + Vector3(36, 0, 0), y0 + Vector3(36, 0, 45)], true)
	var f_end := fence1.points[-1] if fence1 else Vector3.INF
	con.select_type(&"fence_gate")
	rig.frame(f_end, 0.0, 60.0)
	await _frames(3)
	# Cursor roughly where the gate should go, just beyond the fence end.
	await _cursor_at(f_end + Vector3(0.7, 0, 1.6))
	var gate_snapped := not con.snap.is_empty()
	var gate: StructureState = null
	if con.check.get("ok", false):
		_click(MOUSE_BUTTON_LEFT, _screen(con.cursor))
		await _frames(2)
		gate = cs.get_structure(cs.all()[-1].id) if cs.all()[-1].type_id == &"fence_gate" else null
	var gate_post_err := INF
	var far_post := Vector3.INF
	if gate:
		var gdef := StructureCatalog.get_def(&"fence_gate")
		var p0 := gate.instances[0] * gdef.snap_points[0]
		var p1 := gate.instances[0] * gdef.snap_points[1]
		gate_post_err = minf(_flat(p0, f_end), _flat(p1, f_end))
		far_post = p1 if _flat(p0, f_end) < _flat(p1, f_end) else p0
	var fence2: StructureState = null
	if far_post.is_finite():
		fence2 = await _draw_line(&"fence", [far_post + Vector3(0.6, 0, 0.9), base + Vector3(h + 4, 0, h + 3)], true)
	var start_err := _flat(fence2.points[0], far_post) if fence2 else INF
	placed.shelter = await _place(&"vehicle_shelter", base + Vector3(h + 22, 0, -12), 0)
	_log("fence_gate_snap", {"fence1": _line_info(fence1), "gate_snapped": gate_snapped, "gate_post_to_fence_end_m": snappedf(gate_post_err, 0.001),
		"fence2_start_to_gate_post_m": snappedf(start_err, 0.001), "fence2": _line_info(fence2), "shelter": placed.shelter != null})
	_expect(fence1 != null and gate != null and gate_snapped and gate_post_err < 0.01, "gate did not snap onto the fence end")
	_expect(fence2 != null and start_err < 0.01, "fence did not snap onto the gate post")

	# 9. Long straight fence (150 m) north of the base.
	var long_f: StructureState = await _draw_line(&"fence", [base + Vector3(-70, 0, -60), base + Vector3(80, 0, -60)], true)
	var lf := _line_info(long_f)
	_log("long_fence", lf)
	_expect(long_f != null and lf.modules == 50 and lf.max_joint_error_m < 0.01, "150 m fence is not 50 exact 3 m modules")

	# 10. Invalid sections: a HESCO line straight through the command post and supply storage.
	rig.frame(base, 0.0, 160.0)
	await _frames(3)
	var through: Array = [base + Vector3(-25, 0, -14), base + Vector3(28, 0, -14)]
	con.select_type(&"hesco")
	await _cursor_at(through[0])
	_click(MOUSE_BUTTON_LEFT, _screen(through[0]))
	await _frames(2)
	await _cursor_at(through[1])
	var bad_preview: int = con.check.modules.size() - con.check.ok_count if con.check.has("modules") else -1
	if shots:
		rig.frame(base + Vector3(0, 0, -14), 0.3, 70.0)
		await _cursor_at(through[1])
		await _frames(25)
		_shot("preview_line_blocked")
	_click(MOUSE_BUTTON_LEFT, _screen(through[1]))
	await _frames(2)
	_press(KEY_ENTER)
	await _frames(3)
	var blocked_line: StructureState = cs.all()[-1]
	var blocked_info := _line_info(blocked_line)
	_log("blocked_sections", {"preview_blocked_modules": bad_preview, "line": blocked_info})
	_expect(bad_preview > 0 and blocked_line.is_line() and blocked_line.removed.size() > 0 and blocked_line.built_count() > 0, "blocked sections not shown / not left out")
	cs.remove(blocked_line.id)  # not part of the base

	# 11. Navigation: navmesh carved around the walls, a soldier walks out through the gap.
	_press(KEY_B)  # leave construction mode
	await _frames(2)
	rig.frame(base, 0.0, 120.0)
	await _seconds(1.5)
	var detail := demo.detail
	var inside := demo.on_ground(base.x + 8.0, base.z + 26.0)
	var outside := demo.on_ground(base.x + 8.0, base.z + h + 18.0)
	var map := demo.navigation.get_navigation_map()
	var path := NavigationServer3D.map_get_path(map, inside, outside, true)
	var plen := 0.0
	for i in path.size() - 1:
		plen += path[i].distance_to(path[i + 1])
	var crosses := _path_crosses(path, perim)
	_log("navigation", {"structure_obstructions": detail.last_bake.get("structure_obstructions", 0), "bakes": detail.bake_count,
		"bake_ms": detail.last_bake.get("bake_ms", -1), "polygons": detail.last_bake.get("polygons", -1),
		"path_points": path.size(), "path_len_m": snappedf(plen, 0.1), "straight_m": snappedf(_flat(inside, outside), 0.1), "path_crosses_wall": crosses})
	_expect(detail.last_bake.get("structure_obstructions", 0) > 100, "structures not carved into the navmesh")
	_expect(path.size() > 2 and plen > _flat(inside, outside) + 3.0 and not crosses, "path from inside the base does not go around the wall")
	# A soldier walks it (record placed inside the base, DetailManager gives it a body).
	var walker := demo.sim.state.add_unit(UnitState.Kind.SOLDIER, 0, inside, 0.0, "N-Builder")
	await _physics(10)
	demo.sim.state.issue_move(walker.id, outside)
	var in_wall := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and walker.move_state == UnitState.MoveState.MOVING:
		await tree.physics_frame
		if _inside_line(walker.position, perim, 0.1):
			in_wall += 1
	var wb := demo.sim.body_of(walker.id) as SoldierBody
	var wpath := []
	if wb:
		for q in wb.nav.get_current_navigation_path():
			wpath.append([snappedf(q.x - base.x, 0.1), snappedf(q.z - base.z, 0.1)])
	_log("soldier_around_wall", {"pos_rel": [snappedf(walker.position.x - base.x, 0.1), snappedf(walker.position.z - base.z, 0.1)], "agent_path": wpath, "has_body": walker.has_body, "state": walker.move_state, "end_error_m": snappedf(_flat(walker.position, outside), 0.01),
		"frames_inside_hesco": in_wall, "seconds": (Time.get_ticks_msec() - t0) / 1000.0})
	_expect(walker.has_body and walker.move_state == UnitState.MoveState.ARRIVED and in_wall == 0, "soldier did not walk around the HESCO wall to the target")

	# 12. Screenshots of the finished installation (RTS) and FPS inspection with collision.
	if shots:
		rig.frame(base + Vector3(10, 0, 5), 0.65, 210.0)
		await _frames(60)
		_shot("rts_base_overview")
		rig.frame(base + Vector3(-10, 0, 0), -0.5, 85.0)
		await _frames(40)
		_shot("rts_base_close")
		rig.frame(base + Vector3(h + 20, 0, 0), 0.4, 70.0)
		await _frames(40)
		_shot("rts_vehicle_yard")
	var fps_id := walker.id
	demo.rts.select([fps_id])
	_press(KEY_P)
	await _physics(10)
	var body := game.possessed_body()
	var col := {}
	if body:
		body.teleport(demo.on_ground(base.x + 6.0, base.z + 20.0, 0.3), 0.0)
		await _physics(20)
		# Physics ray straight at the HESCO wall north of the soldier and down onto a barracks roof.
		col.hesco_ray = _ray_hit_structure(demo.on_ground(base.x + 6.0, base.z - h + 4.0, 1.0), Vector3(0, 0, -1), 8.0)
		col.barracks_roof = _ray_hit_structure(placed.b2.instances[0].origin + Vector3(0, 10, 0), Vector3.DOWN, 12.0)
		col.tower_stairs = _ray_hit_structure(placed.tower1.instances[0] * Vector3(0.95, 6.0, 3.9), Vector3.DOWN, 6.0)
		col.collision_cells = sm.stats().collision_cells
		# Walk into the wall: the body must stop at it.
		body.teleport(demo.on_ground(base.x + 6.0, base.z - h + 4.5, 0.3), 0.0)
		await _physics(10)
		var walk_t := 0.0
		Input.action_press("move_forward")
		while walk_t < 3.0:
			await tree.physics_frame
			walk_t += 1.0 / Engine.physics_ticks_per_second
		Input.action_release("move_forward")
		col.stopped_at_wall_z = snappedf(body.global_position.z - (base.z - h), 0.01)
		col.passed_wall = body.global_position.z < base.z - h
		if shots:
			body.teleport(demo.on_ground(base.x + 2.0, base.z + 6.0, 0.3), 0.0)
			await _physics(5)
			_aim(body, placed.cp.instances[0].origin + Vector3(0, 1.5, 0))
			await _frames(60)
			_shot("fps_inside_base")
			body.teleport(demo.on_ground(base.x + 3.0, base.z + h + 9.0, 0.3), 0.0)
			await _physics(5)
			_aim(body, base + Vector3(0, 1.0, h))
			await _frames(60)
			_shot("fps_gate_opening")
			body.teleport(demo.on_ground(base.x - h + 4.0, base.z - h + 6.0, 0.3), 0.0)
			await _physics(5)
			_aim(body, base + Vector3(-h, 0.9, -h))
			await _frames(60)
			_shot("fps_hesco_corner_closeup")
			body.teleport(far_post + Vector3(-3.5, 0.3, 3.0) if far_post.is_finite() else body.global_position, 0.0)
			await _physics(5)
			_aim(body, f_end + Vector3(0, 1.2, 0))
			await _frames(60)
			_shot("fps_fence_gate")
			body.teleport(demo.on_ground(base.x + h + 12.0, base.z - 25.0, 0.3), 0.0)
			await _physics(5)
			_aim(body, base + Vector3(h + 22, 2.0, -14))
			await _frames(60)
			_shot("fps_vehicle_shelter")
			body.teleport(demo.on_ground(base.x - 18.0, base.z - 5.0, 0.3), 0.0)
			await _physics(5)
			_aim(body, placed.tower1.instances[0].origin + Vector3(0, 4.5, 0))
			await _frames(60)
			_shot("fps_guard_tower")
			body.teleport(demo.on_ground(base.x + 4.0, base.z + 3.0, 0.3), 0.0)
			await _physics(5)
			_aim(body, placed.storage.instances[0].origin + Vector3(0, 2.5, 0))
			await _frames(60)
			_shot("fps_supply_storage")
	_log("fps_collision", col)
	_expect(body != null and col.get("hesco_ray", false) and col.get("barracks_roof", false) and col.get("tower_stairs", false), "structure collision missing in first person")
	_expect(body != null and not col.get("passed_wall", true), "the possessed soldier walked through the HESCO wall")

	# 13. Performance in and over the base.
	var perf := {}
	perf.fps_in_base = await _measure(240)
	_press(KEY_TAB)
	await _physics(3)
	rig.frame(base, 0.6, 150.0)
	perf.rts_150m = await _measure(240)
	rig.frame(base, 0.6, 300.0)
	perf.rts_300m = await _measure(240)
	perf.structures = sm.stats()
	_log("performance", perf)

	# 14. Travel 7.6 km away and back: records untouched, nodes released and rebuilt.
	var snap_before: Dictionary = cs.to_dict()
	var xf_before := _all_instances()
	_press(KEY_2)
	await _seconds(1.5)
	var away := sm.stats()
	_press(KEY_1)
	await _seconds(0.5)
	rig.frame(base, 0.6, 150.0)
	await _seconds(1.0)
	var back := sm.stats()
	var same := JSON.stringify(cs.to_dict()) == JSON.stringify(snap_before)
	var xf_same := _all_instances() == xf_before
	_log("travel_and_return", {"away_dist_m": _flat(demo.sites[1].position, base), "away": away, "back": back,
		"records_identical": same, "instance_transforms_identical": xf_same})
	_expect(away.visible_cells == 0 and away.collision_cells == 0 and away.structures == snap_before.structures.size(), "distant base still has nodes or lost records")
	_expect(same and xf_same and back.visible_cells > 0 and back.drawn_instances == away.instances, "base changed after travelling away and back")

	# 15. Save, clear, load (F5 / F9 through the input map).
	_press(KEY_F5)
	await _frames(2)
	var saved_text := FileAccess.get_file_as_string(con.save_path)
	cs.clear()
	await _frames(3)
	var cleared := sm.stats()
	_press(KEY_F9)
	await _seconds(0.5)
	var loaded := sm.stats()
	var restored := JSON.stringify(cs.to_dict()) == JSON.stringify(snap_before)
	_log("save_load", {"path": ProjectSettings.globalize_path(con.save_path), "bytes": saved_text.length(), "cleared_structures": cleared.structures,
		"loaded": loaded, "identical_after_load": restored, "max_instance_offset_m": snappedf(_max_offset(_all_instances(), xf_before), 0.0001)})
	_expect(saved_text.length() > 100 and cleared.structures == 0 and restored and _max_offset(_all_instances(), xf_before) < 0.005, "save/load did not restore the base")
	await _seconds(1.0)
	_log("navigation_after_load", {"structure_obstructions": demo.detail.last_bake.get("structure_obstructions", 0)})
	if shots:
		rig.frame(base + Vector3(0, 0, 0), 2.3, 160.0)
		await _frames(60)
		_shot("rts_base_after_reload")
	_finish()


# --- Construction through the UI ---------------------------------------------------

func _worst_frame(seconds: float) -> float:
	var worst := 0.0
	var t_end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < t_end:
		var t := Time.get_ticks_usec()
		await tree.process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t) / 1000.0)
	return snappedf(worst, 0.1)


## Selects a type, points the cursor at pos, presses R `rotations` times and clicks.
func _place(id: StringName, pos: Vector3, rotations := 0, expect_ok := true) -> StructureState:
	con.select_type(id)
	con.yaw = 0.0
	for i in rotations:
		_press(KEY_R)
	await _frames(1)
	demo.rts_camera.frame(demo.on_ground(pos.x, pos.z, 0.0), demo.rts_camera.yaw, 90.0)
	await _frames(2)
	var g := demo.on_ground(pos.x, pos.z, 0.0)
	await _cursor_at(g)
	var n := cs.count()
	_click(MOUSE_BUTTON_LEFT, _screen(g))
	await _frames(2)
	if cs.count() > n:
		return cs.all()[-1]
	if expect_ok:
		print("BASE could not place %s at %s: %s" % [id, _v(pos), con.check.get("reason", "?")])
	return null


## Draws a line through world points (clicks) and finishes with Enter (unless the last
## click closes it on its start).
func _draw_line(id: StringName, pts: Array, finish_with_enter: bool) -> StructureState:
	con.select_type(id)
	var n := cs.count()
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var ext := 0.0
	for p in pts:
		ext = maxf(ext, _flat(p, c))
	demo.rts_camera.frame(demo.on_ground(c.x, c.z, 0.0), 0.0, clampf(ext * 2.6, 60.0, 300.0))
	await _frames(3)
	for p in pts:
		var g := demo.on_ground(p.x, p.z, 0.0)
		await _cursor_at(g)
		_click(MOUSE_BUTTON_LEFT, _screen(g))
		await _frames(2)
	if finish_with_enter:
		_press(KEY_ENTER)
		await _frames(2)
	con.clear_tool()
	if cs.count() > n:
		return cs.all()[-1]
	print("BASE line %s not built: %s" % [id, con.message])
	return null


func _cursor_at(p: Vector3) -> void:
	con.mouse_override = _screen(p)
	await _frames(2)
	con.update_cursor(con.mouse_override)


func _screen(p: Vector3) -> Vector2:
	return demo.rts_camera.camera.unproject_position(p)


func _wheel(button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = _win(demo.get_viewport().get_visible_rect().size * 0.5)
	ev.pressed = true
	Input.parse_input_event(ev)


# --- Checks -----------------------------------------------------------------------

## Flat-ish 100 m square near a position, away from the site's units and trees.
func _find_base_site(center: Vector3) -> Vector3:
	var best := center
	var best_score := INF
	# WORLD-INTEGRATION-01: never in water or outside the map (the reference world has
	# lakes and its sites lie near the map edge).
	var lim := demo.config.half_size() - 120.0
	for ring: float in [180.0, 260.0, 340.0, 420.0]:
		for k in 16:
			var a := k * TAU / 16.0
			var p := center + Vector3(cos(a), 0, sin(a)) * ring
			if absf(p.x) > lim or absf(p.z) > lim:
				continue
			var hs := []
			var wet := false
			for ix in range(-5, 6):
				for iz in range(-5, 6):
					var q := p + Vector3(ix * 10.0, 0, iz * 10.0)
					hs.append(demo.ground_height(q))
					wet = wet or sm._wet(q.x, q.z, hs[-1])
			if wet:
				continue
			var rng: float = hs.max() - hs.min()
			var trees := 0
			for cx in range(-1, 2):
				for cz in range(-1, 2):
					for t in sm._trees_in(VegetationChunk.cell_of(p + Vector3(cx * 60.0, 0, cz * 60.0), 128.0)):
						if absf(t[0] - p.x) < 90.0 and absf(t[1] - p.z) < 90.0:
							trees += 1
			var score := rng + trees * 0.5
			if score < best_score:
				best_score = score
				best = p
	_log("base_site", {"center": _v(best), "score": snappedf(best_score, 0.01)})
	return demo.on_ground(best.x, best.z, 0.0)


## A spot within 2 km of the base whose terrain slope (6 m footprint) lies in [lo, hi] deg.
func _find_slope(id: StringName, lo: float, hi: float) -> Vector3:
	var def := StructureCatalog.get_def(id)
	for r: float in [120.0, 250.0, 400.0, 600.0, 900.0, 1300.0, 1800.0, 2500.0, 3500.0, 5000.0]:
		for k in 48:
			var a := k * TAU / 48.0
			var p := demo.on_ground(base.x + cos(a) * r, base.z + sin(a) * r, 0.0)
			var s := _slope_at(p, 6.0)
			if s < lo or s > hi:
				continue
			var chk := sm.check_building(def, p, 0.0)
			if hi < 10.0 and not chk.ok:
				continue
			if hi >= 10.0 and not str(chk.reason).begins_with("too steep"):
				continue
			return p
	return Vector3.INF


func _slope_at(p: Vector3, half: float) -> float:
	var gx := (demo.ground_height(p + Vector3(half, 0, 0)) - demo.ground_height(p - Vector3(half, 0, 0))) / (2.0 * half)
	var gz := (demo.ground_height(p + Vector3(0, 0, half)) - demo.ground_height(p - Vector3(0, 0, half))) / (2.0 * half)
	return rad_to_deg(atan(sqrt(gx * gx + gz * gz)))


func _line_info(s: StructureState) -> Dictionary:
	if s == null:
		return {"built": false}
	var def := StructureCatalog.get_def(s.type_id)
	var mods := ModularLine.modules(def, s.points)
	var worst := 0.0
	for i in mods.size() - 1:
		if mods[i].segment == mods[i + 1].segment:
			worst = maxf(worst, absf(mods[i].center.distance_to(mods[i + 1].center) - def.module_length))
	# Corner: the first module of the next segment touches the corner module face to face.
	var corner := 0.0
	for i in mods.size() - 1:
		if mods[i].segment != mods[i + 1].segment and def.layout == StructureDef.Layout.CENTERED:
			corner = maxf(corner, absf(mods[i].center.distance_to(mods[i + 1].center) - def.module_length))
	return {"built": true, "type": String(s.type_id), "points": s.points.size(), "modules": mods.size(), "built_modules": s.built_count(),
		"removed": s.removed.size(), "length_m": snappedf(ModularLine.length_of(s.points), 0.01),
		"max_joint_error_m": snappedf(worst, 0.0001), "corner_gap_m": snappedf(corner, 0.0001)}


func _inside_line(p: Vector3, s: StructureState, shrink: float) -> bool:
	var def := StructureCatalog.get_def(s.type_id)
	for i in s.instances.size():
		if s.is_removed(i):
			continue
		if StructureManager._obb_circle(StructureManager._obb(def, s.instances[i], shrink), Vector2(p.x, p.z), 0.05):
			return true
	return false


func _path_crosses(path: PackedVector3Array, s: StructureState) -> bool:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var n := maxi(1, ceili(a.distance_to(b) / 0.25))
		for k in n + 1:
			if _inside_line(a.lerp(b, float(k) / n), s, 0.15):
				return true
	return false


func _ray_hit_structure(from: Vector3, dir: Vector3, dist: float) -> bool:
	var space := demo.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and hit.collider is StaticBody3D and hit.collider.get_parent() == sm


func _all_instances() -> Array:
	var out := []
	for s: StructureState in cs.all():
		for i in s.instances.size():
			if not (s.is_line() and s.is_removed(i)):
				out.append(s.instances[i])
	return out


## Largest origin / axis difference between two transform lists (JSON keeps mm precision).
static func _max_offset(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return INF
	var worst := 0.0
	for i in a.size():
		var x: Transform3D = a[i]
		var y: Transform3D = b[i]
		worst = maxf(worst, x.origin.distance_to(y.origin))
		worst = maxf(worst, (x.basis.x - y.basis.x).length() + (x.basis.z - y.basis.z).length())
	return worst


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)] if p.is_finite() else []


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/base01_%s.jpg" % [_shot_dir, name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("BASE shot: ", path)


func _log(name: String, data: Dictionary) -> void:
	results[name] = data
	print("BASE %s %s" % [name, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("BASE FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/base_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("BASE %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()

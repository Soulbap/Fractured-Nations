## GAMEPLAY-02 (controls) checks in the real game on ref_20km: short probes of the interactions the milestone fixed, driven by
## real input events pushed into the viewport (the same path as the keyboard and mouse).
##
##   Godot.exe --path . --fullscreen --log-file c2.log res://scenes/game/world_ref_20km.tscn -- --scenario=new_game --controls-test [--shots] [--only ...]
##
## m_mouse   the mouse policy: tactical view shows the cursor, first person captures it, a soldier body streamed in changes
##           nothing, the in-game menu shows it and resume gives first person its capture back
## e_escape  Esc opens and closes the in-game menu several times in a row, with squads selected in the tactical view and in first
##           person (the hidden menu used to swallow every later Esc)
## f_weapon  the first squad's soldier possessed like Tab: the first-person weapon is drawn in front of the camera
## u_scale   the interface scale (125 %, 175 %, back): the window's content scale factor, the HUD laid out on the smaller canvas
## s_speed   Space pauses (the simulation clock stops, the view still moves), 1-4 set 1/2/4/8 x and resume, first person is 1 x
## d_drag    a right-drag across the front of the player's squad: preview, the order, every soldier's place, spacing, the places
##           kept after the move (no automatic cover step), a short click still a plain move
## b_build   a sandbag fighting position built by the squad: work needed and the simulated seconds it took
## Prints "C2 <check> <json>", writes res://benchmarks/raw/controls_test.json and (with --shots) PNGs into docs/gameplay02_controls.
class_name ControlsSelfTest
extends GameplaySelfTest

const CHECKS_C: Array[String] = ["m_mouse", "e_escape", "f_weapon", "u_scale", "s_speed", "d_drag", "b_build"]


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/gameplay02_controls"
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKS_C)
	SoldierBody.require_mouse_capture = false
	tree.create_timer(600.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	for n in CHECKS_C:
		if only.has(n):
			if demo.menu_open():
				demo.toggle_pause()
			if demo.game.mode != GameController.Mode.RTS:
				demo.game.enter_rts()
			_log(n, await call("_" + n))
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("C2 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/controls_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("C2 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


# --- Helpers -------------------------------------------------------------------------------------------------------------

func _player_squad() -> SquadState:
	var war := demo.sim.state.war
	for sq: SquadState in demo.sim.state.all_squads():
		if sq.faction == war.player_faction and not sq.members.is_empty():
			return sq
	return null


func _player_soldier() -> UnitState:
	var sq := _player_squad()
	if sq:
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			if u and u.alive:
				return u
	return null


func _key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = down
		demo.get_viewport().push_input(ev, true)
		await _physics(2)


func _mouse_button(button: MouseButton, at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.global_position = at
	ev.pressed = down
	ev.button_mask = MOUSE_BUTTON_MASK_RIGHT if down and button == MOUSE_BUTTON_RIGHT else 0
	Input.warp_mouse(at * demo.get_viewport().get_screen_transform().get_scale())
	demo.get_viewport().push_input(ev, true)


func _mouse_move(at: Vector2, mask: int) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.button_mask = mask
	Input.warp_mouse(at * demo.get_viewport().get_screen_transform().get_scale())
	demo.get_viewport().push_input(ev, true)


func _possess_first() -> UnitState:
	var u := _player_soldier()
	if u == null:
		return null
	demo.rts.select([u.id])
	demo.game.toggle()
	await _seconds(1.5)
	return u


# --- Checks --------------------------------------------------------------------------------------------------------------

func _m_mouse() -> Dictionary:
	var g := demo.game
	var out := {"rts_visible": not g.wants_capture() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE}
	var u: UnitState = await _possess_first()
	out["fps_wants_capture"] = g.wants_capture()
	# a soldier body set up near the camera (as the detail tier does) must not free the player's mouse
	var extra := demo.SOLDIER_SCENE.instantiate() as SoldierBody
	demo.units_root.add_child(extra)
	await _physics(2)
	out["fps_after_body_spawn"] = g.wants_capture()
	extra.queue_free()
	demo.toggle_pause()
	await _physics(2)
	out["menu_shows_cursor"] = not g.wants_capture() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	demo.toggle_pause()
	await _physics(2)
	out["resume_wants_capture"] = g.wants_capture()
	g.enter_rts()
	await _physics(2)
	out["back_rts_visible"] = not g.wants_capture() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	out["soldier"] = u.id if u else -1
	for k in ["rts_visible", "fps_wants_capture", "fps_after_body_spawn", "menu_shows_cursor", "resume_wants_capture", "back_rts_visible"]:
		_expect(bool(out[k]), "m_mouse: %s" % k)
	return out


func _e_escape() -> Dictionary:
	var out := {}
	var sq := _player_squad()
	demo.rts.select_squads([sq.id])
	var rows := []
	for i in 3:
		await _key(KEY_ESCAPE)
		var opened := demo.menu_open()
		await _key(KEY_ESCAPE)
		rows.append([opened, demo.menu_open()])
	out["rts_with_selection"] = rows
	out["selection_kept"] = demo.rts.selected_squads().has(sq.id)
	_png("e_menu_rts")
	await _possess_first()
	var rows_f := []
	for i in 3:
		await _key(KEY_ESCAPE)
		var opened := demo.menu_open()
		if i == 0:
			_png("e_menu_fps")
		await _key(KEY_ESCAPE)
		rows_f.append([opened, demo.menu_open(), demo.game.wants_capture()])
	out["fps"] = rows_f
	for r: Array in rows + rows_f:
		_expect(bool(r[0]) and not bool(r[1]), "e_escape: Esc did not open and close the menu %s" % str(r))
	return out


func _f_weapon() -> Dictionary:
	var u: UnitState = await _possess_first()
	_expect(u != null, "f_weapon: no player soldier")
	if u == null:
		return {}
	await _seconds(0.5)
	var b := demo.sim.body_of(u.id) as SoldierBody
	var out := {"mode": demo.game.mode, "weapon_id": String(u.weapon_id), "loadout": u.loadout, "body": b != null}
	if b == null:
		_expect(false, "f_weapon: no body")
		return out
	var vm := b.viewmodel
	out["viewmodel"] = vm != null
	var in_view := false
	if vm and vm._weapon_root:
		var wp: Vector3 = b.camera.global_transform.affine_inverse() * vm._weapon_root.global_position
		out["weapon_in_camera"] = str(wp.snapped(Vector3.ONE * 0.01))
		# in front of the eye, below and right of the centre, inside the view
		in_view = wp.z < -0.05 and wp.z > -1.0 and absf(wp.x) < 0.5 and wp.y < 0.1 and wp.y > -0.6
		out["arms_tilt_off"] = vm.arms != null and not vm.arms.ground_tilt
	out["in_view"] = in_view
	_expect(in_view, "f_weapon: the first-person weapon is not in front of the camera")
	_png("f_weapon_hip")
	Input.action_press("aim")
	await _seconds(0.9)
	_png("f_weapon_ads")
	Input.action_release("aim")
	return out


func _u_scale() -> Dictionary:
	var root := demo.get_tree().root
	var out := {"start": root.content_scale_factor}
	var sq := _player_squad()
	demo.rts.select_squads([sq.id])
	demo.rts_camera.frame(demo.sim.squads._centroid(sq), 0.6, 70.0)
	for k: float in [1.25, 1.75]:
		UISettings.set_ui_scale(demo.get_tree(), k, false)
		await _seconds(0.6)
		var vp := demo.get_viewport().get_visible_rect().size
		var tp := demo.hud.tactical_panel
		out["s%d" % int(k * 100)] = {"factor": root.content_scale_factor, "canvas": str(vp.round()),
			"command_panel": str(Rect2(tp.position, tp.size).abs()) if tp.visible else "hidden",
			"panel_inside": tp.visible and Rect2(Vector2.ZERO, vp).encloses(Rect2(tp.position, tp.size))}
		_expect(is_equal_approx(root.content_scale_factor, k), "u_scale: factor %.2f not applied" % k)
		_expect(bool(out["s%d" % int(k * 100)].panel_inside), "u_scale: command panel off screen at %d %%" % int(k * 100))
		_png("u_scale_%d" % int(k * 100))
	demo.toggle_pause()
	UISettings.set_ui_scale(demo.get_tree(), 1.25, false)
	await _physics(4)
	_png("u_scale_125_menu")
	demo.pause_menu._choose("settings")
	await _physics(4)
	_png("u_settings_panel")
	var sp := demo.pause_menu.get_node_or_null("Settings") as SettingsPanel
	out["settings_panel"] = sp != null
	_expect(sp != null, "u_scale: the settings panel did not open")
	if sp:
		sp.close()
	await _physics(2)
	demo.toggle_pause()
	UISettings.set_ui_scale(demo.get_tree(), 1.0, false)
	return out


func _s_speed() -> Dictionary:
	var out := {}
	var sim := demo.sim
	await _key(KEY_SPACE)
	var t0 := sim.state.time
	var f0 := demo.rts_camera.focus
	Input.action_press("move_forward")
	await _seconds(0.8)
	Input.action_release("move_forward")
	out["paused_tree"] = demo.get_tree().paused
	out["sim_advanced_s"] = snappedf(sim.state.time - t0, 0.01)
	out["camera_moved_m"] = snappedf(demo.rts_camera.focus.distance_to(f0), 0.1)
	_png("s_paused")
	_expect(demo.get_tree().paused and sim.state.time - t0 < 0.05, "s_speed: Space did not stop the simulation")
	_expect(demo.rts_camera.focus.distance_to(f0) > 1.0, "s_speed: the view did not move while paused")
	await _key(KEY_SPACE)
	out["resumed"] = not demo.get_tree().paused
	_expect(not demo.get_tree().paused, "s_speed: Space did not resume")
	var speeds := {}
	for k: Key in [KEY_2, KEY_3, KEY_4, KEY_1]:
		await _key(k)
		speeds[OS.get_keycode_string(k)] = Engine.time_scale
	out["speeds"] = speeds
	_expect(speeds == {"2": 2.0, "3": 4.0, "4": 8.0, "1": 1.0}, "s_speed: 1-4 gave %s" % str(speeds))
	await _key(KEY_4)
	await _key(KEY_SPACE)
	await _possess_first()
	await _physics(2)
	out["fps_scale"] = Engine.time_scale
	out["fps_paused"] = demo.get_tree().paused
	await _key(KEY_4)
	out["fps_after_key4"] = Engine.time_scale
	_expect(Engine.time_scale == 1.0 and not demo.get_tree().paused, "s_speed: first person not at 1 x / still paused")
	demo.game.enter_rts()
	return out


func _d_drag() -> Dictionary:
	var out := {}
	var sq := _player_squad()
	var sim := demo.sim
	sim.squads.order_hold([sq.id])
	var c := sim.squads._centroid(sq)
	demo.rts_camera.frame(c, demo.rts_camera.yaw, 55.0)
	await _seconds(1.0)
	demo.rts.select_squads([sq.id])
	await _physics(2)
	var cam := demo.rts_camera.camera
	var fwd := Vector3(-sin(demo.rts_camera.yaw), 0.0, -cos(demo.rts_camera.yaw))
	var right := Vector3(cos(demo.rts_camera.yaw), 0.0, -sin(demo.rts_camera.yaw))
	var a3 := demo.on_ground(c.x + fwd.x * 18.0 - right.x * 9.0, c.z + fwd.z * 18.0 - right.z * 9.0, 0.0)
	var b3 := demo.on_ground(c.x + fwd.x * 18.0 + right.x * 9.0, c.z + fwd.z * 18.0 + right.z * 9.0, 0.0)
	var a := cam.unproject_position(a3)
	var b := cam.unproject_position(b3)
	_mouse_button(MOUSE_BUTTON_RIGHT, a, true)
	await _physics(2)
	for i in range(1, 9):
		_mouse_move(a.lerp(b, i / 8.0), MOUSE_BUTTON_MASK_RIGHT)
		await _physics(3)
	await _seconds(0.4)
	out["preview"] = demo.rts.rdrag_plan.size()
	out["preview_cover"] = demo.rts.rdrag_cover.size()
	_png("d_drag_preview")
	_mouse_button(MOUSE_BUTTON_RIGHT, b, false)
	await _physics(3)
	out["placed"] = sq.placed.size()
	out["feedback"] = demo.rts.tactic_feedback
	var ids := sim.squads._active_members(sq)
	_expect(int(out.preview) == ids.size(), "d_drag: preview shows %d of %d soldiers" % [out.preview, ids.size()])
	_expect(sq.placed.size() == ids.size(), "d_drag: %d of %d soldiers placed" % [sq.placed.size(), ids.size()])
	var gaps := []
	var pts: Array = sq.placed.values()
	var min_gap := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			min_gap = minf(min_gap, SquadControl._flat(pts[i], pts[j]))
	out["min_gap_m"] = snappedf(min_gap, 0.01)
	_expect(min_gap >= 1.1, "d_drag: two places %.2f m apart" % min_gap)
	# the places lie along the dragged line (within the cover snap distance)
	var off := 0.0
	for p: Vector3 in pts:
		var t := clampf((p - a3).dot((b3 - a3).normalized()), 0.0, a3.distance_to(b3))
		off = maxf(off, SquadControl._flat(p, a3 + (b3 - a3).normalized() * t))
	out["max_off_line_m"] = snappedf(off, 0.1)
	_expect(off < 4.5, "d_drag: a place %.1f m off the line" % off)
	await _seconds(8.0)
	TimeCompression.apply(4.0)
	var t0 := sim.state.time
	while sim.state.time - t0 < 60.0 and sq.status == SquadState.Status.MOVING:
		await _physics(10)
	TimeCompression.apply(1.0)
	await _seconds(1.0)
	var dist := []
	for id in ids:
		var u := sim.state.get_unit(id)
		if u and sq.placed.has(id):
			dist.append(snappedf(SquadControl._flat(u.position, sq.placed[id]), 0.1))
	out["arrived_off_m"] = dist
	out["status"] = sq.status
	_expect(dist.filter(func(d: float) -> bool: return d <= 2.5).size() >= ids.size() - 1, "d_drag: soldiers not at their places %s" % str(dist))
	_png("d_drag_done")
	# a short right click is still the plain move
	var e3 := demo.on_ground(c.x - fwd.x * 12.0, c.z - fwd.z * 12.0, 0.0)
	var e := cam.unproject_position(e3)
	_mouse_button(MOUSE_BUTTON_RIGHT, e, true)
	await _physics(2)
	_mouse_move(e + Vector2(3, 2), MOUSE_BUTTON_MASK_RIGHT)
	await _physics(2)
	_mouse_button(MOUSE_BUTTON_RIGHT, e + Vector2(3, 2), false)
	await _physics(3)
	out["click_move"] = {"order": sq.order, "placed": sq.placed.size(), "target_off_m": snappedf(SquadControl._flat(sq.order_target, e3), 0.1)}
	_expect(sq.order == SquadState.Order.MOVE and sq.placed.is_empty() and SquadControl._flat(sq.order_target, e3) < 6.0,
		"d_drag: a short right click was not a plain move %s" % str(out.click_move))
	return out


func _b_build() -> Dictionary:
	var out := {}
	var sq := _player_squad()
	var sim := demo.sim
	var def := StructureCatalog.get_def(&"sandbag_fighting_position")
	_expect(def != null, "b_build: no sandbag fighting position in the catalogue")
	if def == null:
		return out
	var c := sim.squads._centroid(sq)
	var at := demo.on_ground(c.x + 6.0, c.z + 6.0, 0.0)
	var need := BuildCosts.work_of(def)
	var site := demo.structures.state.add_site(def.id, at, 0.0, sim.state.war.player_faction, need, {})
	out["work_need"] = need
	out["soldiers"] = sim.squads._active_members(sq).size()
	demo.rts.select_squads([sq.id])
	var n := demo.rts.order_build(site.id)
	_expect(n > 0, "b_build: the squad did not take the build order")
	TimeCompression.apply(4.0)
	var t0 := sim.state.time
	var done_at := -1.0
	while sim.state.time - t0 < 180.0:
		await _physics(10)
		var s := demo.structures.state.get_structure(site.id)
		if s != null and not s.is_site():
			done_at = sim.state.time
			break
	TimeCompression.apply(1.0)
	out["sim_seconds"] = snappedf(done_at - t0, 0.1) if done_at > 0.0 else -1.0
	_expect(done_at > 0.0, "b_build: not finished in 180 simulated seconds")
	demo.rts_camera.frame(at, demo.rts_camera.yaw, 30.0)
	await _seconds(1.0)
	_png("b_build_done")
	return out

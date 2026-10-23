## UI-01C phase 1: screenshots and short functional checks of the RTS HUD (Task Force roster,
## selection and command panel, hint bar) in the real game on ref_20km.
##
##   Godot.exe --path . --resolution 1920x1080 --log-file ui01c.log res://scenes/game/world_ref_20km.tscn -- --ui01c-test [--shots] [--only shots,checks,small]
##
## Uses the player's starting squads and, for the many-squads picture, temporary extra squads spawned
## for this run only (nothing is saved). Clicks and keys go through Input.parse_input_event, so the
## real GUI and RTSController paths are exercised. Prints "UI01C <check> <json>", writes
## res://benchmarks/raw/ui01c_test.json and (with --shots) docs/ui_01c/phase1/*.png.
class_name UI01CSelfTest
extends CombatAISelfTest

var only: PackedStringArray = []
var hud: GameHUD
var rts: RTSController
var squads: Array = []
var center := Vector3.ZERO


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/ui_01c/phase1"
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	SoldierBody.require_mouse_capture = false
	combat = demo.sim.combat
	def = combat.weapon(&"rifle")
	hud = demo.hud
	rts = demo.rts
	tree.create_timer(600.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	var pf := demo.sim.state.war.player_faction
	for sq: SquadState in demo.sim.state.all_squads():
		if sq.faction == pf and rts._can_command(sq.leader_id):
			squads.append(sq)
	_expect(squads.size() >= 3, "precondition: the player needs at least three squads (%d)" % squads.size())
	if squads.size() < 3:
		_finish()
		return
	center = demo.sim.squads._centroid(squads[0])
	_frame_on_squads()
	await _seconds(2.0)
	if _want("shots"):
		await _shots()
	if _want("checks"):
		_log("checks", await _checks())
	if _want("small"):
		_log("small_window", await _small_window())
	_finish()


func _want(n: String) -> bool:
	return only.is_empty() or only.has(n)


func _frame_on_squads() -> void:
	var c := Vector3.ZERO
	for sq: SquadState in squads.slice(0, 3):
		c += demo.sim.squads._centroid(sq)
	c /= 3.0
	demo.rts_camera.frame(c + Vector3(0, 0, 18), 0.6, 95.0)


# --- Screenshots ---------------------------------------------------------------------------------------

func _shots() -> void:
	var a: SquadState = squads[0]
	var b: SquadState = squads[1]
	var c: SquadState = squads[2]
	rts.select([])
	await _seconds(1.0)
	_png("01_rts_idle")
	# One squad, moving.
	rts.select_squads([a.id])
	rts.order_move(demo.sim.squads._centroid(a) + Vector3(60, 0, -40))
	await _seconds(2.5)
	_png("02_rts_squad_selected")
	# Three squads with different orders: moving, holding, defending.
	rts.select_squads([b.id])
	rts.order_hold()
	rts.select_squads([c.id])
	rts.order_tactic(SquadState.Tactic.DEFEND, demo.sim.squads._centroid(c))
	rts.select_squads([a.id, b.id, c.id])
	await _seconds(2.0)
	_png("03_rts_multi_selected")
	# Many squads: temporary extra squads near the first (this run only), one with a long name, one
	# under fire, one on hold fire; the roster has to scroll.
	var pf := demo.sim.state.war.player_faction
	var f := demo.sim.state.war.faction(pf)
	var extra: Array = []
	for i in 14:
		var p := center + Vector3(-120 + (i % 7) * 40, 0, 90 + (i / 7) * 40)
		var sq := demo.sim.war.spawn_squad(f, p, 8 if i % 3 else 6)
		extra.append(sq)
		spawned_ids.append_array(Array(sq.members))
	extra[2].squad_name = "N-Recon Platoon Bravo"
	demo.sim.squads.set_roe([extra[4].id], SquadState.Roe.HOLD_FIRE)
	for id in extra[1].members:
		demo.sim.state.get_unit(id).under_fire_until = demo.sim.state.time + 60.0
	rts.select_squads([extra[1].id, extra[2].id])
	await _seconds(1.5)
	_png("04_rts_many_squads")
	_log("many_squads", {"squads": hud.squad_panel._rows.size(), "scroll_h": hud.squad_panel._scroll.size.y,
		"rows_h": hud.squad_panel._list.get_combined_minimum_size().y})
	_expect(hud.squad_panel._list.get_combined_minimum_size().y > hud.squad_panel._scroll.size.y + 1.0, "many squads: the roster should scroll")
	for sq: SquadState in extra:
		for id in Array(sq.members) + Array(sq.fallen):
			demo.sim.state.remove_unit(id)
	spawned_ids.clear()
	await _physics(5)
	# Command states: hold fire, an order in progress (defend: current), an armed order (assault: amber)
	# and the mouse over a button (hover).
	rts.select_squads([c.id])
	rts.set_roe([c.id], SquadState.Roe.HOLD_FIRE)
	rts.arm_tactic(SquadState.Tactic.ASSAULT)
	await _seconds(0.6)
	var sup: FNCommandButton = hud.tactical_panel._buttons[SquadState.Tactic.FLANK]
	_hover(sup.get_global_rect().get_center())
	await _seconds(0.25)
	_png("05_rts_command_states")
	_log("command_states", {"armed": hud.tactical_panel._buttons[SquadState.Tactic.ASSAULT].armed,
		"current_defend": hud.tactical_panel._buttons[SquadState.Tactic.DEFEND].current, "hover": sup.is_hovered(),
		"roe_title": hud.tactical_panel._buttons[TacticalPanel.ROE].title_label.text})
	_press(KEY_ESCAPE)
	await _physics(3)
	rts.set_roe([c.id], SquadState.Roe.WEAPONS_FREE)
	_hover(Vector2(960, 300))


# --- Functional checks ---------------------------------------------------------------------------------

func _checks() -> Dictionary:
	var out := {}
	var a: SquadState = squads[0]
	var b: SquadState = squads[1]
	var c: SquadState = squads[2]
	_frame_on_squads()
	rts.select([])
	await _physics(10)
	out.idle = {"roster": hud.squad_panel.visible, "panel": hud.tactical_panel.visible, "hints": hud._hints.visible,
		"badge_in_rts": hud._badge.visible, "faction_chip": hud.squad_panel._chip.text if hud.squad_panel._chip else ""}
	_expect(hud.squad_panel.visible and not hud.tactical_panel.visible and hud._hints.visible, "idle: roster and hints, no command panel")
	_expect(not hud._badge.visible and hud.squad_panel._chip != null, "idle: faction shown in the roster, not as a separate badge")
	# Select one squad by clicking its roster row (real GUI input).
	await _click_at(hud.squad_panel._rows[a.id].get_global_rect().get_center(), false)
	await _seconds(0.5)
	out.one = {"selected": rts.selected_squads(), "panel": hud.tactical_panel.visible, "title": hud.tactical_panel._title.text,
		"row_selected": hud.squad_panel._rows[a.id].selected, "hints": hud._hints.visible}
	_expect(rts.selected_squads() == [a.id], "row click selects the squad")
	_expect(hud.tactical_panel.visible and not hud._hints.visible, "one squad: command panel replaces the hints")
	# Shift+click adds two more.
	await _click_at(hud.squad_panel._rows[b.id].get_global_rect().get_center(), true)
	await _click_at(hud.squad_panel._rows[c.id].get_global_rect().get_center(), true)
	await _seconds(0.5)
	var marked := 0
	for id in hud.squad_panel._rows:
		marked += 1 if hud.squad_panel._rows[id].selected else 0
	out.multi = {"selected": rts.selected_squads().size(), "rows_marked": marked, "title": hud.tactical_panel._title.text}
	_expect(rts.selected_squads().size() == 3 and marked == 3, "shift+click: three squads selected and marked")
	_expect(hud.tactical_panel._title.text == "3 SQUADS", "multi: panel title counts the squads")
	# Orders through the panel buttons (real clicks): hold, then arm assault and cancel with Esc.
	await _click_at(hud.tactical_panel._buttons[TacticalPanel.HOLD].get_global_rect().get_center(), false)
	await _physics(5)
	out.hold_button = {"orders": [a.order_name(), b.order_name(), c.order_name()]}
	_expect(a.order == SquadState.Order.HOLD and c.order == SquadState.Order.HOLD, "hold button orders hold")
	await _seconds(0.3)
	out.hold_status = hud.tactical_panel._status.text_label.text
	_expect(out.hold_status == "HOLD", "panel shows the hold order (%s)" % out.hold_status)
	await _click_at(hud.tactical_panel._buttons[SquadState.Tactic.ASSAULT].get_global_rect().get_center(), false)
	await _seconds(0.3)
	out.armed = {"armed_tactic": rts.armed_tactic, "button_armed": hud.tactical_panel._buttons[SquadState.Tactic.ASSAULT].armed,
		"footer": hud.tactical_panel._feedback.text_label.text}
	_expect(rts.armed_tactic == SquadState.Tactic.ASSAULT and out.armed.button_armed, "assault button arms the order")
	_press(KEY_ESCAPE)
	await _physics(3)
	out.cancel = {"armed_tactic": rts.armed_tactic, "still_selected": rts.selected_squads().size()}
	_expect(rts.armed_tactic == -1 and rts.selected_squads().size() == 3, "Esc cancels the armed order and keeps the selection")
	# Keyboard: J defends at the cursor (a real tactic order), Y toggles ROE, V the formation.
	rts.select_squads([a.id])
	_hover(_screen(demo.sim.squads._centroid(a)))
	await _physics(3)
	_press(KEY_J)
	await _seconds(0.5)
	_press(KEY_Y)
	_press(KEY_V)
	await _seconds(0.4)
	out.keys = {"tactic": a.tactic_name(), "feedback": rts.tactic_feedback, "feedback_ok": rts.tactic_feedback_ok, "roe": a.roe_name(),
		"roe_button": hud.tactical_panel._buttons[TacticalPanel.ROE].title_label.text, "formation": a.formation_name(),
		"defend_current": hud.tactical_panel._buttons[SquadState.Tactic.DEFEND].current}
	_expect(a.tactic == SquadState.Tactic.DEFEND, "J orders defend")
	_expect(a.roe == SquadState.Roe.HOLD_FIRE and out.keys.roe_button == "Hold fire", "Y toggles hold fire and the button follows")
	_expect(out.keys.defend_current, "the running order is marked on its button")
	_press(KEY_Y)
	_press(KEY_V)
	await _physics(3)
	# Deselect with Esc.
	_press(KEY_ESCAPE)
	await _seconds(0.4)
	out.deselect = {"selected": rts.selected.size(), "panel": hud.tactical_panel.visible, "hints": hud._hints.visible}
	_expect(rts.selected.is_empty() and not hud.tactical_panel.visible and hud._hints.visible, "Esc deselects; panel hides, hints return")
	# F1 / F3.
	_press(KEY_F1)
	await _seconds(0.3)
	out.f1 = {"on": hud.show_controls, "label": hud._label.visible, "has_camera_help": hud._label.text.contains("Camera:")}
	_expect(hud.show_controls and hud._label.visible and out.f1.has_camera_help, "F1 shows the detailed controls")
	_expect(hud._label.get_global_rect().end.y <= hud._hints.position.y, "F1 text stays above the hint bar")
	_press(KEY_F1)
	await _seconds(0.3)
	_expect(not hud._label.text.contains("Camera:"), "F1 again hides the controls")
	_press(KEY_F3)
	await _seconds(0.4)
	out.f3 = {"debug": hud.show_debug, "label": hud._label.text.contains("Units"), "roster_top": hud.squad_panel.position.y,
		"diag_bottom": demo.game.diagnostics.overlay_bottom() if demo.game.diagnostics else -1.0}
	_expect(hud.show_debug and out.f3.label, "F3 shows the diagnostics")
	_expect(hud.squad_panel.position.y >= out.f3.diag_bottom, "roster moves below the F3 overlay")
	_press(KEY_F3)
	await _seconds(0.3)
	# Mode switches: map, first person, back.
	demo.toggle_map()
	await _physics(5)
	out.map = {"open": demo.strategic_map.visible}
	_expect(demo.strategic_map.visible, "M opens the map")
	demo.toggle_map()
	await _physics(5)
	var body := await _possess(a.leader_id)
	await _physics(5)
	out.fps = {"mode": demo.game.mode, "roster": hud.squad_panel.visible, "panel": hud.tactical_panel.visible, "badge": hud._badge.visible,
		"hints": hud._hints.visible, "body": body != null}
	_expect(demo.game.mode == GameController.Mode.FPS and not hud.squad_panel.visible and not hud._hints.visible and hud._badge.visible,
		"first person: RTS HUD hidden, faction badge shown")
	await _leave()
	await _physics(5)
	out.back = {"mode": demo.game.mode, "roster": hud.squad_panel.visible}
	_expect(demo.game.mode == GameController.Mode.RTS and hud.squad_panel.visible, "Tab returns to the RTS HUD")
	rts.select([])
	return out


## Layout at 1280 x 720 with three squads selected: nothing off screen, roster and panel apart.
func _small_window() -> Dictionary:
	var prev_mode := DisplayServer.window_get_mode()
	var prev := DisplayServer.window_get_size()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await _seconds(0.5)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _seconds(1.0)
	_frame_on_squads()
	rts.select_squads([squads[0].id, squads[1].id, squads[2].id])
	await _seconds(1.0)
	var vp := demo.get_viewport().get_visible_rect().size
	var tp := hud.tactical_panel.get_global_rect()
	var sp := hud.squad_panel.get_global_rect()
	var out := {"viewport": [vp.x, vp.y], "panel": [tp.position.x, tp.position.y, tp.size.x, tp.size.y],
		"roster": [sp.position.x, sp.position.y, sp.size.x, sp.size.y], "overlap": tp.intersects(sp)}
	_expect(tp.position.x >= 0.0 and tp.end.x <= vp.x and tp.end.y <= vp.y, "720p: command panel inside the screen")
	_expect(not tp.intersects(sp), "720p: roster and command panel do not overlap")
	if shots:
		_png("06_rts_720p_multi_selected")
	rts.select([])
	await _seconds(0.5)
	if shots:
		_png("07_rts_720p_idle")
	DisplayServer.window_set_size(prev)
	DisplayServer.window_set_mode(prev_mode)
	await _seconds(0.5)
	return out


# --- Helpers -------------------------------------------------------------------------------------------

func _click_at(at: Vector2, shift: bool) -> void:
	_hover(at)
	await _physics(2)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = _window_pos(at)
		ev.global_position = ev.position
		ev.shift_pressed = shift
		if pressed:
			ev.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(ev)
		await _physics(1)


func _hover(at: Vector2) -> void:
	demo.get_viewport().warp_mouse(at)
	var ev := InputEventMouseMotion.new()
	ev.position = _window_pos(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)


## Input events arrive in window pixels; the HUD works in the stretched 1152 x 648 canvas.
func _window_pos(at: Vector2) -> Vector2:
	return demo.get_viewport().get_final_transform() * at


func _png(shot_name: String) -> void:
	if not shots:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_shot_dir, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("UI01C shot: ", path, " ", img.get_size())


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("UI01C %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("UI01C FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/ui01c_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("UI01C %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	demo.shutdown_cleanup()
	tree.quit()

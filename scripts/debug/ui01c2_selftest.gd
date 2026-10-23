## UI-01C phase 2: screenshots and short functional checks of the construction, first-person,
## strategic-map, vehicle / facility and RTS-marker HUD in the real game on ref_20km.
##
##   Godot.exe --path . --fullscreen --log-file ui01c2.log res://scenes/game/world_ref_20km.tscn -- --ui01c2-test [--shots] [--only construction,fps,map,vehicle,markers]
##
## Isolated test state for this run only (nothing saved, world data untouched): a player base built
## through the real construction input next to the North HQ (as BASE-01's test does), and for the
## vehicle pictures a truck acquired at that base's depot through BaseSim. Prints "UI01C2 <check> <json>",
## writes res://benchmarks/raw/ui01c2_test.json and (with --shots) docs/ui_01c/phase2/*.png.
class_name UI01C2SelfTest
extends UI01CSelfTest

var bs: BaseSim
var placed := {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/ui_01c/phase2"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	SoldierBody.require_mouse_capture = false
	combat = demo.sim.combat
	def = combat.weapon(&"rifle")
	hud = demo.hud
	rts = demo.rts
	con = demo.construction
	con.base_rules = true
	sm = demo.structures
	cs = demo.sim.state.construction
	bs = demo.sim.logistics.bases
	tree.create_timer(900.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(40)
	var pf := demo.sim.state.war.player_faction
	for sq: SquadState in demo.sim.state.all_squads():
		if sq.faction == pf and rts._can_command(sq.leader_id):
			squads.append(sq)
	_expect(squads.size() >= 3, "precondition: the player needs at least three squads (%d)" % squads.size())
	center = demo.sim.squads._centroid(squads[0]) if not squads.is_empty() else Vector3.ZERO
	if _want("construction"):
		_log("construction", await _construction())
	if _want("vehicle"):
		_log("vehicle", await _vehicle())
	if _want("markers"):
		_log("markers", await _markers())
	if _want("map"):
		_log("map", await _map())
	if _want("fps"):
		_log("fps", await _fps())
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("UI01C2 %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("UI01C2 FAILED CHECK: ", msg)


# --- Construction ------------------------------------------------------------------------------------

func _construction() -> Dictionary:
	var out := {}
	var fac := con.player_faction()
	var hq := demo.sim.state.war.objective(demo.sim.state.war.faction(fac).hq_objective)
	base = _find_base_site(hq.position)
	demo.rts_camera.frame(base, 0.4, 150.0)
	await _seconds(1.0)
	# Open with B; the BASE category shows, only the command post is available without a base.
	_press(KEY_B)
	await _seconds(0.6)
	var panel := con.panel
	out.open = {"active": con.active, "menu": panel._menu.visible, "category": panel._category,
		"barracks_available": not (panel._base_buttons[&"barracks_block"] as Button).disabled,
		"cp_available": not (panel._base_buttons[&"command_post"] as Button).disabled, "base_title": panel._base_title.text}
	_expect(con.active and panel.visible, "B opens construction")
	_expect(out.open.cp_available and not out.open.barracks_available, "without a base only the command post is available")
	# A category through a real click on its tile.
	await _click_at(panel._tiles["Defences"].get_global_rect().get_center(), false)
	await _seconds(0.4)
	out.category = {"shown": panel._category, "cards": panel._list.get_child_count()}
	_expect(panel._category == "Defences" and panel._list.get_child_count() == panel._cards["Defences"].size(), "category tile shows its cards")
	if shots:
		await _seconds(0.4)
		_png("01_construction_menu")
	await _click_at(panel._tiles[ConstructionPanel.BASE].get_global_rect().get_center(), false)
	await _seconds(0.3)
	# Command post through a click on its card: valid spot, then a road (invalid with a reason).
	await _click_at(panel._base_buttons[&"command_post"].get_global_rect().get_center(), false)
	await _seconds(0.3)
	out.select = {"tool": con.tool, "def": String(con.def.id) if con.def else "", "context": panel._context.visible}
	_expect(con.def != null and con.def.id == &"command_post" and panel._context.visible, "card click selects the type and opens the context panel")
	var cp_at := _spot(&"command_post", base, 0)
	con.select_type(&"command_post")
	demo.rts_camera.frame(cp_at, 0.4, 110.0)
	await _seconds(0.5)
	await _cursor_at(cp_at)
	var yaw0 := con.yaw
	_press(KEY_R)
	_press(KEY_R)
	_press(KEY_R)
	await _seconds(0.5)
	await _cursor_at(cp_at)
	await _seconds(0.4)
	out.valid = {"ok": con.check.get("ok", false), "status": panel._ctx_status.text_label.text, "detail": panel._ctx_detail.text,
		"yaw_deg": snappedf(rad_to_deg(con.yaw - yaw0), 0.1)}
	_expect(bool(out.valid.ok) and String(out.valid.status).to_upper() == "VALID PLACEMENT", "valid spot shows VALID PLACEMENT (%s)" % out.valid.status)
	_expect(absf(out.valid.yaw_deg - 45.0) < 0.5 and String(out.valid.detail).contains("45"), "R rotates and the panel shows it")
	if shots:
		_png("02_construction_valid")
	var road_pt := _road_spot2(base)
	if road_pt.is_finite():
		demo.rts_camera.frame(road_pt, 0.5, 80.0)
		await _seconds(0.5)
		await _cursor_at(road_pt)
		await _seconds(0.5)
	out.invalid = {"ok": con.check.get("ok", true), "reason": con.check.get("reason", ""), "status": panel._ctx_status.text_label.text,
		"shown_reason": panel._ctx_reason.text, "road": road_pt.is_finite()}
	_expect(road_pt.is_finite() and not bool(out.invalid.ok) and out.invalid.shown_reason != "", "invalid spot shows the reason (%s)" % JSON.stringify(out.invalid))
	if shots:
		_png("03_construction_invalid")
	# Build the base through the real input: command post, barracks, depot, parking, two guard posts.
	placed.cp = await _place(&"command_post", cp_at, 3)
	_expect(placed.cp != null, "command post placed")
	if placed.cp == null:
		return out
	var c: Vector3 = placed.cp.position
	placed.barracks = await _place(&"barracks_block", _spot(&"barracks_block", c + Vector3(-34, 0, 22), 6), 6)
	placed.depot = await _place(&"supply_depot", _spot(&"supply_depot", c + Vector3(34, 0, 22), 0), 0)
	placed.parking = await _place(&"vehicle_parking_pad", _spot(&"vehicle_parking_pad", c + Vector3(30, 0, -26), 0), 0)
	placed.guard1 = await _place(&"guard_tower_steel", _spot(&"guard_tower_steel", c + Vector3(-48, 0, -40), 0), 0)
	await _seconds(0.5)
	out.base = {"placed": placed.keys().filter(func(k) -> bool: return placed[k] != null), "base_title": panel._base_title.text,
		"fields": panel._base_fields.get_child_count(), "barracks_available": not (panel._base_buttons[&"barracks_block"] as Button).disabled}
	_expect(panel._base_fields.get_child_count() > 0 and out.base.barracks_available, "with a base the menu shows it and unlocks the buildings")
	# 04: the partly built base with a second guard post being placed.
	con.select_type(&"guard_tower_steel")
	var g2 := _spot(&"guard_tower_steel", c + Vector3(52, 0, 58), 0)
	con.select_type(&"guard_tower_steel")
	demo.rts_camera.frame(c + Vector3(6, 0, 14), 0.5, 170.0)
	await _seconds(0.6)
	await _cursor_at(g2)
	await _seconds(0.6)
	if shots:
		_png("04_construction_base")
	# Close with Esc (tool) and B (mode).
	_press(KEY_ESCAPE)
	await _seconds(0.2)
	_press(KEY_B)
	await _seconds(0.3)
	out.closed = {"active": con.active, "panel": panel.visible}
	_expect(not con.active and not panel.visible, "B closes construction")
	return out


# --- Vehicle and facility panels -------------------------------------------------------------------

var vehicle_id := -1


func _vehicle() -> Dictionary:
	var out := {}
	if placed.get("cp") == null:
		_expect(false, "vehicle: needs the base from the construction part")
		return out
	var c: Vector3 = placed.cp.position
	con.set_active(true)
	await _seconds(0.3)
	placed.vdepot = await _place(&"vehicle_depot", _spot(&"vehicle_depot", c + Vector3(-30, 0, -55), 0), 0)
	con.set_active(false)
	await _seconds(0.3)
	_expect(placed.vdepot != null, "vehicle depot placed in the base")
	if placed.vdepot == null:
		return out
	# The depot through the facility panel: Acquire a truck with a real click.
	var depot: StructureState = placed.vdepot
	rts.select([])
	rts.selected_structure = depot.id
	demo.rts_camera.frame(depot.position, 0.5, 90.0)
	await _seconds(1.0)
	var lp := hud.logistics_panel
	var acquire: Button = null
	for row in lp._actions.get_children():
		for b in row.get_children():
			if b is Button and String(b.text).contains("TRUCK"):
				acquire = b
	out.facility = {"panel": lp.visible, "title": lp._title.text, "acquire_button": acquire != null}
	_expect(lp.visible and acquire != null, "facility panel shows the depot and its Acquire buttons")
	if acquire:
		await _click_at(acquire.get_global_rect().get_center(), false)
		await _seconds(0.5)
	out.queue = depot.facility.get("queue", []).size()
	_expect(out.queue > 0, "Acquire queues a truck (%s)" % lp._status.text)
	if shots:
		_png("15b_facility_selected")
	# Let the depot finish (30 s simulated, time compressed).
	var pf := demo.sim.state.war.player_faction
	var before := {}
	for id in demo.sim.vehicles.ids:
		before[id] = true
	TimeCompression.apply(8.0, 64)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await _seconds(0.25)
		for id in demo.sim.vehicles.ids:
			var u := _u(id)
			if not before.has(id) and u and u.faction == pf:
				vehicle_id = id
		if vehicle_id > 0:
			break
	TimeCompression.reset()
	_expect(vehicle_id > 0, "the truck was delivered")
	if vehicle_id <= 0:
		return out
	rts.select([vehicle_id])
	await _seconds(0.2)
	demo.rts_camera.frame(_u(vehicle_id).position, 0.7, 45.0)
	await _seconds(1.2)
	out.vehicle = {"panel": lp.visible, "title": lp._title.text, "meters": lp._meters.get_child_count(), "actions": lp._actions.get_child_count()}
	_expect(lp.visible and lp._title.text == _u(vehicle_id).unit_name and lp._meters.get_child_count() == 3, "vehicle panel shows the truck with its meters")
	if shots:
		_png("15_vehicle_selected")
	rts.select([])
	return out


# --- RTS markers ---------------------------------------------------------------------------------------

func _markers() -> Dictionary:
	var out := {}
	rts.select_squads([squads[0].id])
	demo.rts_camera.frame(demo.sim.squads._centroid(squads[0]) + Vector3(0, 0, 10), 0.6, 70.0)
	await _seconds(1.5)
	out.dot_scale_near = _dot_scale(squads[0])
	if shots:
		_png("13_rts_markers")
	rts.select_squads([squads[0].id, squads[1].id, squads[2].id])
	_frame_on_squads()
	demo.rts_camera.frame(demo.rts_camera.focus, 0.6, 170.0)
	await _seconds(1.5)
	out.dot_scale_far = _dot_scale(squads[0])
	var marked := 0
	for id in squads[0].members:
		var v := demo.sim.view_of(id)
		if v and "selected" in v and v.selected:
			marked += 1
	out.selected_markers = marked
	if shots:
		_png("14_rts_multi_selected")
	_expect(marked == squads[0].members.size(), "selected squad's soldiers are marked")
	_expect(out.dot_scale_far > 0.0 and out.dot_scale_far <= 0.34 * 7.0 + 0.01, "soldier dots stop growing at distance (%.2f)" % out.dot_scale_far)
	rts.select([])
	return out


func _dot_scale(sq: SquadState) -> float:
	var v := demo.sim.view_of(sq.members[0])
	if v == null or not ("ring" in v) or v.ring == null:
		return -1.0
	return snappedf((v.ring as MeshInstance3D).scale.x, 0.01)


# --- Strategic map -------------------------------------------------------------------------------------

func _map() -> Dictionary:
	var out := {}
	rts.select([])
	demo.toggle_map()
	await _seconds(0.8)
	var m := demo.strategic_map
	m.fit_all()
	await _seconds(0.6)
	out.open = {"visible": m.visible, "inspector": m._insp.visible, "ops": m._ops_box.get_child_count()}
	_expect(m.visible and not m._insp.visible, "M opens the map without an inspector")
	if shots:
		_png("08_map_default")
	# Layers: switch territory off and on through the tile.
	await _click_at(m._layer_buttons["territory"].get_global_rect().get_center(), false)
	await _seconds(0.2)
	var off: bool = not m.layers.territory
	await _click_at(m._layer_buttons["territory"].get_global_rect().get_center(), false)
	await _seconds(0.2)
	out.layer_toggle = off and m.layers.territory
	_expect(out.layer_toggle, "layer tile switches the layer")
	# Zoom (wheel at the first squad) and pan (middle drag).
	var sq: SquadState = squads[0]
	var z0 := m.zoom
	for i in 4:
		_wheel_at(m.to_screen(demo.sim.war.squad_center(sq)), true)
		await _seconds(0.15)
	await _seconds(0.6)
	var vc0 := m.view_center
	await _mid_drag(Vector2(576, 324), Vector2(536, 304))
	await _seconds(0.3)
	out.zoom = {"from": snappedf(z0, 0.001), "to": snappedf(m.zoom, 0.001), "panned": m.view_center.distance_to(vc0) > 1.0}
	_expect(m.zoom > z0 * 2.0 and out.zoom.panned, "wheel zooms and middle drag pans")
	# A squad: click its marker.
	await _click_at(m.to_screen(demo.sim.war.squad_center(sq)), false)
	await _seconds(0.5)
	out.squad = {"selected": m.selected_squads.duplicate(), "inspector": m._insp.visible}
	_expect(m.selected_squads.has(sq.id) and m._insp.visible, "clicking a squad selects it and opens the inspector")
	if shots:
		_png("09_map_squad")
	# The player's base: click the command post.
	var home := center
	if placed.get("cp") != null:
		home = placed.cp.position
		m.view_center = Vector2(home.x, home.z)
		m.zoom = 0.6
		await _seconds(0.6)
		await _click_at(m.to_screen(home), false)
		await _seconds(0.5)
		out.base = {"structure": m.selected_structure, "inspector": m._insp.visible}
		_expect(m.selected_structure == placed.cp.id, "clicking the command post selects the base facility")
		if shots:
			_png("10_map_base")
	# An operation: two squads ordered to attack the nearest objective not held by the player, with RMB,
	# then picked in the list.
	m.fit_all()
	await _seconds(0.4)
	m.selected_structure = -1
	m.selected_vehicles.clear()
	m.selected_squads.clear()
	m.selected_squads.append(squads[1].id)
	m.selected_squads.append(squads[2].id)
	var target: ObjectiveState = null
	for o: ObjectiveState in demo.sim.state.war.all_objectives():
		if o.owner != demo.sim.state.war.player_faction and (target == null or o.position.distance_to(home) < target.position.distance_to(home)):
			target = o
	await _rmb_at(m.to_screen(target.position))
	await _seconds(0.5)
	var ops := demo.sim.state.war.active_operations(demo.sim.state.war.player_faction).filter(func(o: OperationState) -> bool: return o.player_ordered)
	_expect(not ops.is_empty(), "RMB on an objective orders an operation")
	await _seconds(1.0)
	if not ops.is_empty():
		var row: Control = m._ops_box.get_child(0)
		var tile: Control = row.get_child(0)
		await _click_at(tile.get_global_rect().get_center(), false)
		await _seconds(0.6)
		out.operation = {"id": ops[0].id, "selected_op": m.selected_op, "rows": m._ops_box.get_child_count(), "target": target.obj_name}
		_expect(m.selected_op == ops[0].id and m._insp.visible, "clicking an operation in the list shows it")
		if shots:
			_png("11_map_operations")
	# Logistics: the truck on the map, then a drive order with RMB.
	if vehicle_id > 0:
		var vu := _u(vehicle_id)
		m.select_operation(-1)
		m.selected_squads.clear()
		m.view_center = Vector2(vu.position.x, vu.position.z)
		m.zoom = 0.35
		await _seconds(0.6)
		await _click_at(m.to_screen(vu.position), false)
		await _seconds(0.4)
		out.vehicle = {"selected": m.selected_vehicles.duplicate(), "inspector": m._insp.visible}
		_expect(m.selected_vehicles.has(vehicle_id), "clicking the truck on the map selects it")
		await _rmb_at(m.to_screen(vu.position + Vector3(120, 0, 60)))
		await _seconds(1.5)
		out.vehicle["order"] = vu.order
		_expect(vu.order == UnitState.Order.MOVE, "RMB with the truck selected gives it a drive order")
		if shots:
			_png("12_map_logistics")
	demo.toggle_map()
	await _seconds(0.5)
	out.closed = not m.visible
	_expect(not m.visible, "M closes the map")
	return out


func _wheel_at(at: Vector2, up: bool) -> void:
	_hover(at)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = _window_pos(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	# A wheel sends press and release like any button; a press alone keeps the GUI's mouse focus.
	var rel := ev.duplicate()
	rel.pressed = false
	Input.parse_input_event(rel)


func _rmb_at(at: Vector2) -> void:
	_hover(at)
	await _physics(2)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed
		ev.position = _window_pos(at)
		ev.global_position = ev.position
		Input.parse_input_event(ev)
		await _physics(1)


func _mid_drag(from: Vector2, to: Vector2) -> void:
	_hover(from)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_MIDDLE
	ev.pressed = true
	ev.position = _window_pos(from)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _physics(1)
	for k in range(1, 6):
		var mm := InputEventMouseMotion.new()
		mm.position = _window_pos(from.lerp(to, k / 5.0))
		mm.global_position = mm.position
		mm.relative = _window_pos(from.lerp(to, k / 5.0)) - _window_pos(from.lerp(to, (k - 1) / 5.0))
		mm.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		Input.parse_input_event(mm)
		await _physics(1)
	var up := ev.duplicate()
	up.pressed = false
	up.position = _window_pos(to)
	up.global_position = up.position
	Input.parse_input_event(up)
	await _physics(1)


# --- First person -----------------------------------------------------------------------------------

func _fps() -> Dictionary:
	var out := {}
	var sq: SquadState = squads[0]
	# The squad moves off; the player takes over a rifleman (not the leader) facing the march.
	var dest := demo.sim.squads._centroid(sq) + Vector3(-160, 0, 120)
	rts.select_squads([sq.id])
	rts.order_move(dest)
	await _seconds(1.0)
	var pid := -1
	for id in sq.members:
		if id != sq.leader_id:
			pid = id
			break
	var body := await _possess(pid)
	await _seconds(1.2)
	var u := _u(pid)
	var fh: FPSHud = hud._fps
	out.normal = {"mode": demo.game.mode, "body": body != null, "fps_hud": fh.visible, "weapon": fh._weapon.visible, "mag": fh._weapon.mag,
		"reserve": fh._weapon.reserve, "health": fh._health.value, "squad_card": fh._squad.visible, "squad_title": fh._sq_title.text,
		"order": fh._sq_status.text_label.text, "badge": hud._badge.visible, "bottom_text": hud._label.visible}
	_expect(demo.game.mode == GameController.Mode.FPS and fh.visible and fh._weapon.visible, "first person shows the FPS HUD")
	_expect(fh._weapon.mag == u.mag and fh._weapon.reserve == u.reserve, "weapon status shows the magazine and reserve")
	_expect(fh._squad.visible and String(out.normal.squad_title).contains(sq.squad_name.to_upper()), "squad card shows the squad")
	_expect(not hud._label.visible, "no permanent control text in first person")
	if shots:
		_png("05_fps_normal")
	# Ammunition and health update: one shot, some damage.
	var mag0 := u.mag
	await _click_fire()
	await _seconds(0.3)
	out.after_shot = {"mag": u.mag, "shown": fh._weapon.mag}
	_expect(u.mag < mag0 and fh._weapon.mag == u.mag, "firing updates the magazine count (%d -> %d, shown %d)" % [mag0, u.mag, fh._weapon.mag])
	u.health = 62.0
	await _seconds(0.3)
	out.after_damage = {"health": u.health, "shown": fh._health.value}
	_expect(is_equal_approx(fh._health.value, u.health), "health bar follows the unit")
	if shots:
		_png("06_fps_squad")
	# Contextual prompt: an empty magazine (test state on the possessed soldier only) and low health.
	var keep := [u.mag, u.health]
	u.mag = 0
	u.health = 28.0
	await _seconds(0.4)
	out.prompt = {"visible": fh._prompt.visible, "key": fh._prompt.key.text, "action": fh._prompt.action.text}
	_expect(fh._prompt.visible and fh._prompt.key.text == "R", "empty magazine shows the reload prompt")
	if shots:
		_png("07_fps_interaction")
	_press(KEY_R)
	await _seconds(0.5)
	out.reloading = {"reloading": u.is_reloading(), "progress": fh._weapon.reload, "prompt": fh._prompt.visible}
	_expect(u.is_reloading() and fh._weapon.reload >= 0.0 and not fh._prompt.visible, "R reloads; the weapon shows progress and the prompt goes")
	u.health = keep[1]
	# F1 in first person, then back to the tactical view.
	_press(KEY_F1)
	await _seconds(0.3)
	out.f1 = hud._label.visible and hud._label.text.contains("LMB fire")
	_expect(out.f1, "F1 shows the first-person controls")
	_press(KEY_F1)
	await _leave()
	await _seconds(0.5)
	out.back = {"mode": demo.game.mode, "fps_hud": fh.visible, "roster": hud.squad_panel.visible}
	_expect(demo.game.mode == GameController.Mode.RTS and not fh.visible and hud.squad_panel.visible, "Tab back hides the FPS HUD")
	rts.select([])
	return out


## A spot near `want` where the type passes every check (terrain, overlap, trees, base rules), searched in rings.
func _spot(id: StringName, want: Vector3, rotations: int, inside := true) -> Vector3:
	var d := StructureCatalog.get_def(id)
	con.select_type(id)
	var yaw := deg_to_rad(15.0 * rotations)
	for ring: float in [0.0, 6.0, 12.0, 18.0, 26.0, 34.0]:
		for k in (1 if ring == 0.0 else 12):
			var a := k * TAU / 12.0
			var p := demo.on_ground(want.x + cos(a) * ring, want.z + sin(a) * ring, 0.0)
			var chk := sm.check_building(d, p, yaw, -1, con.clear_trees)
			if not chk.ok:
				continue
			con.def = d
			if inside and con._base_reason(chk.xform) != "":
				continue
			return p
	return demo.on_ground(want.x, want.z, 0.0)


## A point on a road near p where the terrain would take a command post (so the road rule refuses it).
func _road_spot2(p: Vector3) -> Vector3:
	var d := StructureCatalog.get_def(&"command_post")
	for r: RoadNetwork.Road in demo.sim.state.roads.roads_in(Rect2(Vector2(p.x, p.z), Vector2.ZERO).grow(1500.0)):
		for i in range(0, r.points.size(), 6):
			var q := r.points[i]
			var g := demo.on_ground(q.x, q.z, 0.0)
			if sm.check_building(d, g, 0.0, -1, true).ok and bs.placement_rule(&"command_post", g, con.player_faction()) == "":
				return g
	return Vector3.INF


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/ui01c2_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("UI01C2 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	demo.shutdown_cleanup()
	tree.quit()

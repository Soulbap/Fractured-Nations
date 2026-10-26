## UI-UX-03: screenshots and short functional checks of the redesigned tactical HUD (squad card, dropdowns, main navigation,
## right-hand column), the tactical map, the RTS camera near buildings and the two runtime errors, in the real game on ref_20km.
##
##   Godot.exe --path . --fullscreen --log-file uiux03.log res://scenes/game/world_ref_20km.tscn -- --scenario=dev --uiux03-test
##       [--shots] [--shot-dir=res://docs/ui_ux03] [--shot-tag=before] [--scale=1.25]
##       [--only shots,dropdowns,nav,layout,map,camera,streamer,econ,small]
##
## Uses the Development Scenario's starting squads and North HQ base; an opportunity record is added for this run only
## (nothing is saved). Clicks go through Input.parse_input_event, so the real GUI paths are exercised. Prints
## "UIUX03 <check> <json>", writes res://benchmarks/raw/uiux03_test.json and (with --shots) docs/ui_ux03/*.png.
class_name UIUX03SelfTest
extends UI01CSelfTest

var tag := ""
var house := {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/ui_ux03"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
		elif a.begins_with("--shot-tag="):
			tag = a.trim_prefix("--shot-tag=") + "_"
		elif a.begins_with("--scale="):
			UISettings.set_ui_scale(tree, float(a.trim_prefix("--scale=")), false)
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	SoldierBody.require_mouse_capture = false
	combat = demo.sim.combat
	def = combat.weapon(&"rifle")
	hud = demo.hud
	rts = demo.rts
	tree.create_timer(900.0, true, false, true).timeout.connect(func() -> void:
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
	if _want("streamer"):
		_log("streamer", await _streamer())
	if _want("econ"):
		_log("econ", await _econ())
	if _want("shots"):
		await _shots_uiux()
	if _want("dropdowns"):
		_log("dropdowns", await _dropdowns())
	if _want("nav"):
		_log("nav", await _nav())
	if _want("layout"):
		_log("layout", await _layout())
	if _want("map"):
		_log("map", await _map())
	if _want("camera"):
		_log("camera", await _camera())
	if _want("small"):
		_log("small", await _small())
	_finish()


# --- Screenshots ---------------------------------------------------------------------------------------

func _shots_uiux() -> void:
	var a: SquadState = squads[0]
	var b: SquadState = squads[1]
	var c: SquadState = squads[2]
	_frame_on_squads()
	rts.select_squads([a.id])
	rts.order_move(demo.sim.squads._centroid(a) + Vector3(60, 0, -40))
	await _seconds(2.5)
	_png(tag + "01_rts_one_squad")
	rts.select_squads([b.id])
	rts.order_hold()
	rts.select_squads([c.id])
	rts.order_tactic(SquadState.Tactic.DEFEND, demo.sim.squads._centroid(c))
	rts.select_squads([a.id, b.id, c.id])
	await _seconds(2.0)
	_png(tag + "02_rts_multi_squads")
	var tp := hud.tactical_panel
	if tp.get("formation_dd") != null:
		rts.select_squads([a.id])
		await _seconds(0.5)
		await _click_at(tp.formation_dd.get_global_rect().get_center(), false)
		await _seconds(0.4)
		_png(tag + "03_formation_dropdown")
		_press(KEY_ESCAPE)
		await _seconds(0.3)
		await _click_at(tp.behaviour_dd.get_global_rect().get_center(), false)
		await _seconds(0.4)
		_png(tag + "04_behaviour_dropdown")
		_press(KEY_ESCAPE)
		await _seconds(0.3)
	# A building of the player's base, with an opportunity offered (the right-hand column holds both).
	var st := _player_facility()
	_expect(st != null, "precondition: the player has a facility")
	if st:
		rts.select([])
		rts.selected_structure = st.id
		rts.selection_changed.emit(rts.selected)
		demo.rts_camera.frame(st.position, 0.5, 70.0)
		await _seconds(1.5)
		_png(tag + "05_building_selected")
		_offer_opportunity()
		await _seconds(1.5)
		_png(tag + "06_building_and_opportunities")
		rts.selected_structure = -1
	if hud.get("nav_bar") != null:
		demo.sim.state.war.rules["development"] = true
		_frame_on_squads()
		rts.select([])
		await _seconds(1.0)
		_hover(hud.nav_bar.button_rect(&"development").get_center())
		await _seconds(1.0)
		_png(tag + "07a_navigation_hover")
		await _click_at(hud.nav_bar.button_rect(&"development").get_center(), false)
		await _seconds(0.8)
		_png(tag + "07_navigation_research")
		hud.development.visible = false
	rts.select_squads([a.id, b.id])
	demo.toggle_map()
	await _seconds(1.0)
	var m := demo.strategic_map
	m.fit_all()
	await _seconds(1.0)
	_png(tag + "08_map_overview")
	m.zoom = 0.35
	m.view_center = Vector2(center.x, center.z)
	await _seconds(1.0)
	_png(tag + "09_map_local")
	m.zoom = 1.2
	await _seconds(1.0)
	_png(tag + "09b_map_close")
	m.close()
	await _seconds(0.8)
	house = _house_near(center)
	if not house.is_empty():
		# The focus beside the house, the camera on the far side: the house stands between them (the reported case).
		var y: float = house.yaw + 0.3
		var p: Vector3 = house.pos - Vector3(sin(y), 0, cos(y)) * 9.0
		for z: float in [38.0, 22.0, 9.0]:
			demo.rts_camera.frame(p, y, z)
			await _seconds(1.2)
			_png(tag + "10_camera_building_%dm" % int(z))


func _player_facility() -> StructureState:
	var pf := demo.sim.state.war.player_faction
	var best: StructureState = null
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == pf and FacilityDefs.has(s.type_id) and not s.is_site():
			if best == null or FacilityDefs.kind_of(s.type_id) == &"barracks":
				best = s
	if best == null:
		# The Development Scenario starts without facilities: a command post and a barracks beside the squads (this run only).
		var at := center + Vector3(60, 0, 50)
		CoreSelfTest.add_built(demo, &"command_post", at, Vector3(0, 0, 1), pf)
		best = CoreSelfTest.add_built(demo, &"barracks_block", at + Vector3(35, 0, 0), Vector3(0, 0, 1), pf)
	return best


func _offer_opportunity() -> void:
	var ws := demo.sim.war
	if not ws.opps.open().is_empty():
		return
	ws.opps._add("recon", 9001, "Recon: Haugen", "Bring a soldier within 300 m of Haugen and keep him there for 20 s: what holds it now is unknown.", center + Vector3(800, 0, 900))
	ws.opps._add("supplies", 9002, "Secure the supply cache", "Move a squad onto the cache and hold it for about 30 s.", center + Vector3(-400, 0, 600))


## The settlement house (library id 16-18) nearest to `p`: its position and yaw.
func _house_near(p: Vector3) -> Dictionary:
	var ov: RefCounted = demo.vegetation.overrides
	if ov == null:
		return {}
	var best := {}
	var bd := INF
	for id in ov.records:
		var r: Dictionary = ov.records[id]
		if r.get("removed", false) or not int(r.get("mesh", -1)) in [16, 17, 18]:
			continue
		var xf: Transform3D = ov._decode(r.transform)
		var d := Vector2(xf.origin.x - p.x, xf.origin.z - p.z).length()
		if d < bd:
			bd = d
			best = {"pos": xf.origin, "yaw": VegetationMeshDef.yaw_of(xf), "mesh": int(r.mesh), "dist": d}
	return best


# --- Functional checks ---------------------------------------------------------------------------------

## Formation and behaviour through the dropdowns' real clicks: the menu opens inside the screen, the choice reaches the squad,
## a click outside closes it, the hotkeys still work.
func _dropdowns() -> Dictionary:
	var out := {}
	var tp := hud.tactical_panel
	if tp.get("formation_dd") == null:
		_expect(false, "dropdowns: the squad card has no formation dropdown")
		return out
	var a: SquadState = squads[0]
	var b: SquadState = squads[1]
	rts.select_squads([a.id])
	await _seconds(0.5)
	var vp := demo.get_viewport().get_visible_rect()
	# Formation -> Column.
	await _click_at(tp.formation_dd.get_global_rect().get_center(), false)
	await _seconds(0.3)
	var menu = tp.formation_dd.menu
	out.formation_open = menu.visible
	var mr: Rect2 = menu.get_global_rect()
	out.formation_menu = [mr.position.x, mr.position.y, mr.size.x, mr.size.y]
	_expect(menu.visible, "formation dropdown opens on click")
	_expect(vp.encloses(mr), "formation menu lies inside the screen")
	_expect(mr.end.y <= tp.formation_dd.get_global_rect().position.y + 1.0, "formation menu opens upwards from the bottom card")
	var col_i: int = menu.index_of(SquadState.Formation.COLUMN)
	await _click_at(menu.item_rect(col_i).get_center(), false)
	await _seconds(0.3)
	out.formation_after = a.formation_name()
	_expect(a.formation == SquadState.Formation.COLUMN and not a.formation_auto, "formation dropdown sets Column (%s)" % a.formation_name())
	_expect(not menu.visible, "formation menu closes after a choice")
	await _seconds(0.3)
	out.formation_label = tp.formation_dd.value_label.text
	_expect(tp.formation_dd.value_label.text.to_lower() == "column", "formation dropdown shows the chosen formation (%s)" % tp.formation_dd.value_label.text)
	# Auto through the dropdown.
	await _click_at(tp.formation_dd.get_global_rect().get_center(), false)
	await _seconds(0.3)
	await _click_at(menu.item_rect(menu.index_of(-1)).get_center(), false)
	await _seconds(0.3)
	_expect(a.formation_auto, "formation dropdown sets Auto")
	# Outside click dismisses without an order.
	await _click_at(tp.behaviour_dd.get_global_rect().get_center(), false)
	await _seconds(0.3)
	var bmenu = tp.behaviour_dd.menu
	_expect(bmenu.visible, "behaviour dropdown opens on click")
	var beh0 := a.behaviour
	await _click_at(Vector2(vp.size.x * 0.5, vp.size.y * 0.35), false)
	await _seconds(0.3)
	out.outside_closed = not bmenu.visible
	_expect(not bmenu.visible and a.behaviour == beh0 and rts.selected_squads() == [a.id], "a click outside closes the menu and changes nothing")
	# Two squads: behaviour Stealth for both.
	rts.select_squads([a.id, b.id])
	await _seconds(0.4)
	await _click_at(tp.behaviour_dd.get_global_rect().get_center(), false)
	await _seconds(0.3)
	await _click_at(bmenu.item_rect(bmenu.index_of(SquadBehaviour.STEALTH)).get_center(), false)
	await _seconds(0.4)
	out.behaviour_multi = [a.behaviour_name(), b.behaviour_name()]
	_expect(a.behaviour == SquadBehaviour.STEALTH and b.behaviour == SquadBehaviour.STEALTH, "behaviour dropdown applies to every selected squad")
	# Hotkeys: X cycles the behaviour, V toggles line / column.
	rts.select_squads([a.id])
	await _seconds(0.3)
	_hover(Vector2(vp.size.x * 0.5, vp.size.y * 0.4))
	await _physics(2)
	_press(KEY_X)
	await _seconds(0.3)
	_press(KEY_V)
	await _seconds(0.3)
	out.hotkeys = [a.behaviour_name(), a.formation_name()]
	_expect(a.behaviour == SquadBehaviour.SAFE, "X still cycles the behaviour (%s)" % a.behaviour_name())
	_expect(a.formation == SquadState.Formation.LINE or a.formation == SquadState.Formation.COLUMN, "V still sets line / column")
	rts.select_squads([a.id, b.id])
	rts.set_behaviour(SquadBehaviour.AWARE)
	await _seconds(0.3)
	# Mixed values read "Mixed".
	demo.sim.squads.set_behaviour([b.id], SquadBehaviour.COMBAT)
	await _seconds(0.5)
	out.mixed = tp.behaviour_dd.value_label.text
	_expect(tp.behaviour_dd.value_label.text.to_lower() == "mixed", "two squads in different modes read Mixed (%s)" % tp.behaviour_dd.value_label.text)
	demo.sim.squads.set_behaviour([b.id], SquadBehaviour.AWARE)
	# The card's size (logical px).
	var r := tp.get_global_rect()
	out.card = [r.size.x, r.size.y]
	return out


## The main navigation: every entry opens its screen by mouse; the shortcuts still work.
func _nav() -> Dictionary:
	var out := {}
	if hud.get("nav_bar") == null:
		_expect(false, "nav: no navigation bar")
		return out
	var nb = hud.nav_bar
	# The Development Scenario has no Military Development; the New Game has (rule development).
	demo.sim.state.war.rules["development"] = true
	_player_facility()
	rts.select([])
	await _seconds(0.5)
	await _seconds(0.5)
	out.entries = nb.entry_ids()
	_expect(nb.visible, "the navigation bar shows in the tactical view")
	# Development (research) by mouse.
	await _click_at(nb.button_rect(&"development").get_center(), false)
	await _seconds(0.5)
	out.research_click = hud.development.visible
	_expect(hud.development.visible, "Development opens with a click on the navigation bar")
	await _click_at(nb.button_rect(&"development").get_center(), false)
	await _seconds(0.4)
	_expect(not hud.development.visible, "a second click closes Development")
	_press(KEY_F2)
	await _seconds(0.4)
	out.research_key = hud.development.visible
	_expect(hud.development.visible, "F2 still opens Development")
	_press(KEY_F2)
	await _seconds(0.3)
	# Construction by mouse.
	await _click_at(nb.button_rect(&"build").get_center(), false)
	await _seconds(0.6)
	out.build_click = demo.construction.active
	_expect(demo.construction.active, "Build opens construction with a click")
	_press(KEY_B)
	await _seconds(0.5)
	_expect(not demo.construction.active, "B closes construction")
	# Base (the player's base panel: recruitment, stores).
	if nb.has_entry(&"base"):
		await _click_at(nb.button_rect(&"base").get_center(), false)
		await _seconds(0.6)
		out.base_click = rts.selected_structure
		_expect(rts.selected_structure >= 0 and hud.logistics_panel.visible, "Base selects the player's base building and shows its panel")
		rts.select([])
	# Map by mouse, back with M.
	await _click_at(nb.button_rect(&"map").get_center(), false)
	await _seconds(0.6)
	out.map_click = demo.strategic_map.visible
	_expect(demo.strategic_map.visible, "Map opens with a click")
	_press(KEY_M)
	await _seconds(0.5)
	_expect(not demo.strategic_map.visible, "M closes the map")
	# Time: pause by mouse.
	if nb.has_entry(&"pause"):
		await _click_at(nb.button_rect(&"pause").get_center(), false)
		await _seconds(0.3)
		out.paused = demo.sim_paused
		_expect(demo.sim_paused, "the pause button pauses")
		await _click_at(nb.button_rect(&"pause").get_center(), false)
		await _seconds(0.3)
		_expect(not demo.sim_paused, "the pause button resumes")
	return out


## The right-hand column: a selected building's panel and the opportunities never overlap; the building comes first.
func _layout() -> Dictionary:
	var out := {}
	var st := _player_facility()
	if st == null:
		_expect(false, "layout: no player facility")
		return out
	_offer_opportunity()
	rts.select([])
	rts.selected_structure = st.id
	rts.selection_changed.emit(rts.selected)
	await _seconds(1.5)
	var lp := hud.logistics_panel.get_global_rect()
	var tr: Rect2 = hud.tracker._panel.get_global_rect()
	out.logistics = [lp.position.x, lp.position.y, lp.size.x, lp.size.y]
	out.tracker = [tr.position.x, tr.position.y, tr.size.x, tr.size.y]
	out.tracker_visible = hud.tracker._panel.visible
	_expect(hud.logistics_panel.visible, "layout: the building panel shows")
	_expect(not hud.tracker._panel.visible or not lp.intersects(tr), "layout: opportunities do not overlap the building panel")
	_expect(not hud.tracker._panel.visible or tr.position.y >= lp.end.y, "layout: the building panel comes first")
	var vp := demo.get_viewport().get_visible_rect()
	_expect(vp.encloses(lp), "layout: the building panel lies inside the screen")
	rts.selected_structure = -1
	await _seconds(0.6)
	return out


## The map: markers for the player's squads at their real places, an order from the map reaches the squads.
func _map() -> Dictionary:
	var out := {}
	var m := demo.strategic_map
	rts.select_squads([squads[0].id])
	demo.toggle_map()
	await _seconds(1.0)
	out.open = m.visible
	m.zoom = 0.3
	m.view_center = Vector2(center.x, center.z)
	await _seconds(0.8)
	var groups := m.squad_groups()
	var placed := 0
	for g: Dictionary in groups:
		for sid in g.ids:
			var sq := demo.sim.state.get_squad(sid)
			var sp := m.to_screen(demo.sim.war.squad_center(sq))
			if (g.get("draw_at", g.pos) as Vector2).distance_to(sp) < 40.0:
				placed += 1
	out.groups = groups.size()
	out.markers_at_squads = placed
	_expect(placed >= 1, "map: squad markers sit at the squads")
	# A move order by right click on open ground.
	var sq0: SquadState = squads[0]
	var target := demo.sim.war.squad_center(sq0) + Vector3(250, 0, 120)
	m.selected_squads = [sq0.id]
	var sp2 := m.to_screen(target)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.position = sp2
	ev.pressed = true
	m._gui_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	m._gui_input(up)
	await _seconds(0.6)
	out.order = sq0.order_name()
	_expect(sq0.op_id >= 0 or sq0.order != SquadState.Order.HOLD, "map: a right click orders the squad (%s)" % sq0.order_name())
	out.topo = m.get("_topo") != null
	m.close()
	await _seconds(0.5)
	rts.order_hold()
	return out


## The RTS camera beside a house: pans along the wall, rotates round it and zooms in and out; the camera must never jump
## (largest step of its distance to the focus per frame) or flip round (look direction against the yaw).
func _camera() -> Dictionary:
	var out := {}
	house = _house_near(center) if house.is_empty() else house
	_expect(not house.is_empty(), "camera: no settlement house found")
	if house.is_empty():
		return out
	out.house = house.dist
	var rig := demo.rts_camera
	var p: Vector3 = house.pos
	rig.frame(p + Vector3(6, 0, 0).rotated(Vector3.UP, house.yaw), house.yaw, 12.0)
	await _seconds(1.0)
	var worst := 0.0
	var flips := 0
	var prev := -1.0
	var prev_zoom := rig.zoom
	var prev_us := Time.get_ticks_usec()
	var frames := 0
	var t0 := Time.get_ticks_msec()
	# 6 s: pan across the house, rotate round it, zoom in and out next to it.
	while Time.get_ticks_msec() - t0 < 6000:
		var k := (Time.get_ticks_msec() - t0) / 6000.0
		rig.focus = p + Vector3(lerpf(-14.0, 14.0, fmod(k * 2.0, 1.0)), 0, 3.0).rotated(Vector3.UP, house.yaw)
		rig.yaw = house.yaw + k * TAU
		rig.zoom = 6.0 + 20.0 * absf(sin(k * PI * 3.0))
		await tree.process_frame
		frames += 1
		var cam := rig.camera
		var d := cam.global_position.distance_to(rig.focus)
		# A jump: the camera distance changing faster than the zoom itself changed, in m/s (a smooth glide stays below the
		# camera's correction speed; a snap is a whole change in one frame).
		var now_us := Time.get_ticks_usec()
		var dt := maxf((now_us - prev_us) / 1.0e6, 0.001)
		prev_us = now_us
		var excess := (absf(d - prev) - absf(rig.zoom - prev_zoom)) / dt
		prev_zoom = rig.zoom
		if prev >= 0.0 and frames > 3 and excess > worst:
			worst = excess
			out.worst_at = {"frame": frames, "d": snappedf(d, 0.01), "prev": snappedf(prev, 0.01), "zoom": snappedf(rig.zoom, 0.01),
				"dist": snappedf(rig._dist, 0.01), "lift": snappedf(rig._lift, 0.01), "fps": Engine.get_frames_per_second()}
		prev = d
		var look := -cam.global_transform.basis.z
		var want := Vector3(-sin(rig.yaw), 0, -cos(rig.yaw))
		if Vector2(look.x, look.z).normalized().dot(Vector2(want.x, want.z)) < 0.0:
			flips += 1
	out.frames = frames
	out.worst_speed_ms = snappedf(worst, 0.1)
	out.flips = flips
	_expect(flips == 0, "camera: the view never turns round near the house (%d frames)" % flips)
	_expect(worst < 60.0, "camera: no jump of the camera distance near the house (worst %.1f m/s beyond the zoom)" % worst)
	return out


## VegetationStreamer: a cell hidden, shown again from the release queue and hidden again is queued once; draining frees it
## without touching a freed instance (the reported error). Then a fast camera sweep over forest.
func _streamer() -> Dictionary:
	var out := {}
	var vs := demo.vegetation
	await _seconds(0.5)
	var key = null
	for k in vs.active:
		key = k
		break
	_expect(key != null, "streamer: no active cell")
	if key == null:
		return out
	var mmi: MultiMeshInstance3D = vs.active[key]
	var id := mmi.get_instance_id()
	vs._deactivate(key, true)
	vs._activate(key, 10.0)
	var reused: bool = vs.active.get(key) == mmi
	vs._deactivate(key, true)
	var n := 0
	for i in range(vs._release_pos, vs._release.size()):
		if vs._release[i][1] == id:
			n += 1
	out.reused = reused
	out.queued_entries = n
	_expect(reused, "streamer: the hidden cell is shown again from the queue")
	_expect(n == 1, "streamer: a cell is queued for release once (%d)" % n)
	# Drain everything now: the instance is freed once, no freed instance is read.
	vs.release_frames = 1
	for i in 50:
		vs._drain_release()
	out.freed = not is_instance_valid(instance_from_id(id))
	_expect(out.freed, "streamer: the queued cell is freed")
	vs.release_frames = 30
	# Sweep the camera fast back and forth across the map near the squads (streaming in and out, reuse).
	var rig := demo.rts_camera
	for i in 40:
		rig.frame(center + Vector3(sin(i * 0.7) * 900.0, 0, cos(i * 0.45) * 700.0), i * 0.3, 40.0 if i % 2 else 160.0)
		await _physics(3)
	await _seconds(1.0)
	out.stats = vs.get_stats()
	return out


## EconomyHud: a cache marker just in front of the camera plane (the reported "triangulation failed") is not drawn; markers on
## screen still are.
func _econ() -> Dictionary:
	var out := {}
	var cam := demo.rts_camera.camera
	var near := cam.global_position - cam.global_transform.basis.z * 0.001
	out.near_plane = FNUI.project(cam, near) == Vector2.INF
	_expect(FNUI.project(cam, near) == Vector2.INF, "econ: a point at the camera plane is not projected")
	var front := cam.global_position - cam.global_transform.basis.z * 50.0
	_expect(FNUI.project(cam, front).is_finite(), "econ: a point in view is projected")
	# Draw a frame with a known cache at the camera (the reported case) and one in view.
	var w := demo.sim.state.war
	var rules := w.rules.duplicate()
	w.rules["player_income"] = true
	w.caches.append({"id": 990, "name": "Test cache A", "pos": near - Vector3.UP * 3.0, "supplies": 100.0, "state": "intact", "known": [w.player_faction], "faction": -1, "progress": 0.0, "taken_by": -1})
	w.caches.append({"id": 991, "name": "Test cache B", "pos": front, "supplies": 100.0, "state": "intact", "known": [w.player_faction], "faction": -1, "progress": 0.0, "taken_by": -1})
	hud.economy.queue_redraw()
	await _physics(6)
	w.caches.pop_back()
	w.caches.pop_back()
	w.rules = rules
	out.drawn = true
	return out


## 1280 x 720 at 125 %: the squad card, its menus and the navigation inside the screen and apart from the roster.
func _small() -> Dictionary:
	var prev_mode := DisplayServer.window_get_mode()
	var prev := DisplayServer.window_get_size()
	var prev_scale := tree.root.content_scale_factor
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await _seconds(0.5)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	UISettings.set_ui_scale(tree, 1.25, false)
	await _seconds(1.0)
	_frame_on_squads()
	rts.select_squads([squads[0].id, squads[1].id, squads[2].id])
	await _seconds(1.0)
	var vp := demo.get_viewport().get_visible_rect()
	var tp := hud.tactical_panel.get_global_rect()
	var sp := hud.squad_panel.get_global_rect()
	var out := {"viewport": [vp.size.x, vp.size.y], "card": [tp.position.x, tp.position.y, tp.size.x, tp.size.y],
		"roster": [sp.position.x, sp.position.y, sp.size.x, sp.size.y]}
	_expect(vp.encloses(tp), "720p 125%: the squad card is inside the screen")
	_expect(not tp.intersects(sp), "720p 125%: roster and squad card do not overlap")
	if hud.get("nav_bar") != null:
		var nr: Rect2 = hud.nav_bar.left_rect()
		out.nav = [nr.position.x, nr.position.y, nr.size.x, nr.size.y]
		_expect(vp.encloses(nr), "720p 125%: the navigation bar is inside the screen")
		_expect(not nr.intersects(sp), "720p 125%: navigation and roster do not overlap")
	if hud.tactical_panel.get("behaviour_dd") != null:
		await _click_at(hud.tactical_panel.behaviour_dd.get_global_rect().get_center(), false)
		await _seconds(0.4)
		var mr: Rect2 = hud.tactical_panel.behaviour_dd.menu.get_global_rect()
		out.menu = [mr.position.x, mr.position.y, mr.size.x, mr.size.y]
		_expect(vp.encloses(mr), "720p 125%: the behaviour menu is inside the screen")
		if shots:
			_png(tag + "11_720p_125_menu")
		_press(KEY_ESCAPE)
		await _seconds(0.3)
	if shots:
		_png(tag + "12_720p_125_multi")
	rts.select([])
	UISettings.set_ui_scale(tree, prev_scale, false)
	DisplayServer.window_set_size(prev)
	DisplayServer.window_set_mode(prev_mode)
	await _seconds(0.5)
	return out


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("UIUX03 %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("UIUX03 FAILED CHECK: ", msg)


func _png(shot_name: String) -> void:
	if not shots:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_shot_dir, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("UIUX03 shot: ", path, " ", img.get_size())


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/uiux03_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("UIUX03 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	demo.shutdown_cleanup()
	tree.quit()

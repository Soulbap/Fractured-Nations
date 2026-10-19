## Construction mode of the tactical view: pick a type, preview, place, draw lines, delete.
##
## B toggles the mode in RTS (unit selection and orders pause meanwhile, the camera keeps
## working). Buildings follow the cursor as a transparent preview, green where they can
## be built and red where not (the reason is shown in the HUD); R / Shift+R or Ctrl+wheel
## rotate, left click builds. Linear types are drawn: left click sets the start, each
## further click adds a corner, Enter, right click or a double click finishes, Backspace
## removes the last corner, Esc cancels. Ends snap to compatible structures (Ctrl
## disables snapping), Shift snaps the direction to 15° steps. Blocked modules of a line
## are shown red and left out when it is built. X switches to deletion: click a building
## or a single line module, Shift+click removes a whole line.
## Everything placed goes to WorldState.construction; nothing here renders placed
## structures (StructureManager does).
class_name ConstructionController
extends Node

signal mode_changed(active: bool)
signal built(s: StructureState)

enum Tool { NONE, PLACE, DELETE }

@export var structures: StructureManager
@export var rig: RTSCamera
@export var rts: RTSController
@export var game: GameController
@export var terrain: Terrain3D
## Quick save target (F5 save, F9 load).
@export var save_path := "user://saves/construction.json"
@export var rotate_step_deg := 15.0
@export var angle_snap_deg := 15.0
@export var max_line_modules := 800

var active := false
var tool := Tool.NONE
var def: StructureDef
var yaw := 0.0
## Corners clicked so far for the line being drawn.
var line_points := PackedVector3Array()
## Modules of the line in progress that duplicate a snapped HESCO cell (not built).
var line_skip := PackedInt32Array()
var cursor := Vector3.INF
## Live end of the line (cursor snapped to whole modules or a connection point).
var line_end := Vector3.INF
var snap := {}
## Last validation result: building {ok, reason, xform}, line {modules, ok_count, length_m}.
var check := {}
var hover := {}
var message := ""
## Scripted tests point the tools here instead of at the OS mouse (INF = real mouse).
var mouse_override := Vector2.INF
var _message_until := 0.0

var _ghost: MeshInstance3D
var _line_ghost: MultiMeshInstance3D
var _markers: MultiMeshInstance3D
var _snap_ring: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _line_mat: StandardMaterial3D
var panel: ConstructionPanel


func _ready() -> void:
	_ensure_input_actions()
	_ghost_mat = _make_ghost_material(Color(0.25, 1.0, 0.35, 0.42))
	_bad_mat = _make_ghost_material(Color(1.0, 0.2, 0.15, 0.45))
	_line_mat = _make_ghost_material(Color(1, 1, 1, 0.45))
	_line_mat.vertex_color_use_as_albedo = true
	var root := Node3D.new()
	root.name = "ConstructionPreview"
	add_child(root)
	_ghost = MeshInstance3D.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	root.add_child(_ghost)
	_line_ghost = MultiMeshInstance3D.new()
	_line_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line_ghost.material_override = _line_mat
	root.add_child(_line_ghost)
	_markers = MultiMeshInstance3D.new()
	var marker := CylinderMesh.new()
	marker.top_radius = 0.35
	marker.bottom_radius = 0.35
	marker.height = 4.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = marker
	_markers.multimesh = mm
	_markers.material_override = _make_ghost_material(Color(1.0, 0.85, 0.2, 0.7))
	root.add_child(_markers)
	_snap_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.2
	_snap_ring.mesh = torus
	_snap_ring.material_override = _make_ghost_material(Color(0.3, 0.8, 1.0, 0.85))
	_snap_ring.visible = false
	root.add_child(_snap_ring)
	panel = ConstructionPanel.new()
	panel.controller = self
	panel.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 41
	add_child(layer)
	layer.add_child(panel)
	set_process(false)


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	cancel()
	tool = Tool.NONE
	def = null
	panel.visible = on
	if rts:
		rts.set_active(not on and game.mode == GameController.Mode.RTS)
		if on:
			rts.select([])
	set_process(on)
	_update_preview()
	mode_changed.emit(on)


func select_type(id: StringName) -> void:
	var d := StructureCatalog.get_def(id)
	if d == null:
		return
	cancel()
	def = d
	tool = Tool.PLACE
	panel.refresh()


func select_delete() -> void:
	cancel()
	def = null
	tool = Tool.DELETE
	panel.refresh()


## Drops the line in progress (or nothing to drop).
func cancel() -> void:
	line_points.clear()
	line_skip.clear()
	line_end = Vector3.INF
	check = {}
	snap = {}
	_update_preview()


func clear_tool() -> void:
	cancel()
	tool = Tool.NONE
	def = null
	if panel:
		panel.refresh()


func save() -> bool:
	var err := structures.state.save_json(save_path)
	_say("Saved %d structures to %s" % [structures.state.count(), save_path] if err == OK else "Save failed (%s)" % error_string(err))
	return err == OK


func load_saved() -> bool:
	cancel()
	var err := structures.state.load_json(save_path)
	_say("Loaded %d structures" % structures.state.count() if err == OK else "Load failed (%s)" % error_string(err))
	return err == OK


func _say(text: String) -> void:
	message = text
	_message_until = Time.get_ticks_msec() / 1000.0 + 4.0
	print("BASE ", text)


# --- Input ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("construction_save"):
		save()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("construction_load"):
		load_saved()
		get_viewport().set_input_as_handled()
		return
	if game and game.mode != GameController.Mode.RTS:
		return
	if event.is_action_pressed("construction_mode"):
		set_active(not active)
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	var handled := true
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				update_cursor(event.position)
				if event.double_click and tool == Tool.PLACE and def.linear:
					finish_line()
				else:
					primary_action(event.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				secondary_action()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.ctrl_pressed and tool == Tool.PLACE and not def.linear:
					rotate_by(rotate_step_deg if event.button_index == MOUSE_BUTTON_WHEEL_UP else -rotate_step_deg)
				else:
					handled = false
			_:
				handled = false
	elif event.is_action_pressed("construction_rotate"):
		rotate_by(-rotate_step_deg if Input.is_key_pressed(KEY_SHIFT) else rotate_step_deg)
	elif event.is_action_pressed("construction_finish"):
		finish_line()
	elif event.is_action_pressed("construction_undo_point"):
		if line_points.size() > 0:
			line_points.remove_at(line_points.size() - 1)
			var n := ModularLine.modules(def, line_points).size() if line_points.size() >= 2 else 1
			for i in range(line_skip.size() - 1, -1, -1):
				if line_skip[i] >= n or line_points.is_empty():
					line_skip.remove_at(i)
	elif event.is_action_pressed("construction_delete"):
		if tool == Tool.DELETE:
			clear_tool()
		else:
			select_delete()
	elif event.is_action_pressed("ui_cancel"):
		if not line_points.is_empty():
			cancel()
		elif tool != Tool.NONE:
			clear_tool()
		else:
			set_active(false)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func rotate_by(deg: float) -> void:
	yaw = wrapf(yaw + deg_to_rad(deg), -PI, PI)


## Left click: build, add a corner, or delete.
func primary_action(shift := false) -> void:
	match tool:
		Tool.PLACE:
			if def.linear:
				add_line_point()
			else:
				place_building()
		Tool.DELETE:
			delete_hovered(shift)


## Right click: finish a line, or cancel the current tool.
func secondary_action() -> void:
	if tool == Tool.PLACE and def.linear and line_points.size() >= 2:
		finish_line()
	elif tool == Tool.PLACE and def.linear and line_points.size() == 1:
		cancel()
	else:
		clear_tool()


func place_building() -> StructureState:
	_refresh_check()
	if not check.get("ok", false):
		_say("Cannot build here: %s" % check.get("reason", "no ground"))
		return null
	var xf: Transform3D = check.xform
	var s := structures.state.add_building(def.id, xf.origin, yaw)
	_say("Built %s" % def.display_name)
	built.emit(s)
	return s


func add_line_point() -> void:
	if not cursor.is_finite():
		return
	if line_points.is_empty():
		var start := cursor
		if not snap.is_empty():
			start = snap.point
			if snap.centered:
				line_skip.append(0)
		line_points.append(start)
		return
	if not line_end.is_finite():
		return
	line_points.append(line_end)
	if _closes_own_line():
		finish_line()
		return
	# Ending on a HESCO cell of another line: that cell exists already.
	if not snap.is_empty() and snap.centered and snap.id != -1 and line_end.is_equal_approx(snap.point):
		line_skip.append(ModularLine.modules(def, line_points).size() - 1)


## Builds the clicked corners (the dangling segment to the cursor is dropped).
func finish_line() -> StructureState:
	if line_points.size() < 2:
		cancel()
		return null
	var pts := line_points.duplicate()  # packed arrays are shared; cancel() clears line_points
	var result := structures.check_line(def, pts)
	var removed := PackedInt32Array()
	var mods: Array = result.modules
	for i in mods.size():
		if not mods[i].ok or line_skip.has(i):
			removed.append(i)
	if removed.size() >= mods.size():
		_say("Cannot build: every module is blocked (%s)" % (mods[0].reason if not mods.is_empty() else "too short"))
		cancel()
		return null
	var s := structures.state.add_line(def.id, pts, removed)
	var blocked := 0
	for m in mods:
		if not m.ok:
			blocked += 1
	_say("Built %s: %d modules, %.0f m%s" % [def.display_name, mods.size() - removed.size(), result.length_m,
		"  (%d blocked sections left out)" % blocked if blocked > 0 else ""])
	cancel()
	built.emit(s)
	return s


func delete_hovered(whole_line := false) -> bool:
	if hover.is_empty():
		return false
	var s := structures.state.get_structure(hover.id)
	if s == null:
		return false
	var d := StructureCatalog.get_def(s.type_id)
	if s.is_line() and not whole_line:
		structures.state.remove_module(s.id, hover.index)
		_say("Removed one %s module" % d.display_name)
	else:
		structures.state.remove(s.id)
		_say("Removed %s" % d.display_name)
	hover = {}
	return true


func _closes_own_line() -> bool:
	return line_points.size() > 2 and Vector2(line_points[-1].x - line_points[0].x, line_points[-1].z - line_points[0].z).length() < 0.05


# --- Per frame --------------------------------------------------------------------

func _process(_delta: float) -> void:
	update_cursor(mouse_override if mouse_override.is_finite() else get_viewport().get_mouse_position())
	if message != "" and Time.get_ticks_msec() / 1000.0 > _message_until:
		message = ""


## Moves the tool to a screen position (also used by the scripted tests).
func update_cursor(screen_pos: Vector2) -> void:
	cursor = ground_at(screen_pos)
	snap = {}
	hover = {}
	if tool == Tool.PLACE and def and cursor.is_finite():
		if def.linear and not Input.is_key_pressed(KEY_CTRL):
			snap = _find_snap(cursor)
		elif not def.linear and not def.snap_points.is_empty() and not Input.is_key_pressed(KEY_CTRL):
			_snap_building()
		_refresh_check()
	elif tool == Tool.DELETE:
		var cam := rig.camera
		hover = structures.pick(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	_update_preview()


## Terrain under a screen point (structures are ignored so they never block placement).
func ground_at(screen_pos: Vector2) -> Vector3:
	var cam := rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var p: Vector3 = terrain.get_intersection(from, dir, false)
	if not p.is_finite() or is_nan(p.x) or absf(p.x) > 1e6 or absf(p.z) > 1e6:
		return Vector3.INF
	# Terrain3D's CPU ray march stops within a few decimetres; refine on the height map so
	# corners land where the cursor points (fixed-point steps along the ray).
	if dir.y < -0.05:
		var t := (p - from).dot(dir)
		for i in 6:
			var q := from + dir * t
			var h: float = terrain.data.get_height(q)
			if is_nan(h):
				break
			t += (q.y - h) / -dir.y
		var r := from + dir * t
		var hr: float = terrain.data.get_height(r)
		if not is_nan(hr) and absf(r.y - hr) < 0.05:
			p = Vector3(r.x, hr, r.z)
	return p


func _find_snap(p: Vector3) -> Dictionary:
	var radius := clampf(rig.zoom * 0.025, 1.5, 5.0)
	var found := structures.snap_point(def.connect_group, p, radius)
	# Closing the line in progress on its own start.
	if line_points.size() >= 2:
		var s0 := line_points[0]
		var d := Vector2(s0.x - p.x, s0.z - p.z).length()
		if d < radius and (found.is_empty() or d < Vector2(found.point.x - p.x, found.point.z - p.z).length()):
			found = {"point": s0, "dir": Vector2.ZERO, "id": -1, "index": 0, "centered": false}
	if not found.is_empty() and not line_points.is_empty() and not ModularLine.fits_exactly(def, line_points[-1], found.point):
		return {}  # would stretch the last segment's spacing too much
	return found


## Gates: near a fence end the gate continues the fence, its left post on the end and
## its axis along the fence direction (independent of the current rotation).
func _snap_building() -> void:
	var radius := clampf(rig.zoom * 0.025, 1.5, 5.0)
	var post := def.snap_points[0]
	var found := structures.snap_point(def.connect_group, cursor, absf(post.x) + radius)
	if found.is_empty() or found.dir == Vector2.ZERO:
		return
	var out: Vector2 = found.dir
	yaw = ModularLine.yaw_of(out)
	cursor = found.point - Basis(Vector3.UP, yaw) * post
	snap = found


func _refresh_check() -> void:
	if def == null or not cursor.is_finite():
		check = {}
		line_end = Vector3.INF
		return
	if not def.linear:
		check = structures.check_building(def, cursor, yaw)
		return
	if line_points.is_empty():
		var p: Vector3 = snap.point if not snap.is_empty() else cursor
		var dir := Vector2.RIGHT
		if not snap.is_empty() and snap.dir != Vector2.ZERO:
			dir = snap.dir
		line_end = Vector3.INF
		var r := structures.fit_module(def, Vector2(p.x, p.z) + (dir * def.module_length * 0.5 if def.layout == StructureDef.Layout.SPAN else Vector2.ZERO), dir)
		if r.ok:
			r.reason = structures._blocked(def, StructureManager._obb(def, r.xform), -1, -1)
			r.ok = r.reason == ""
		check = {"modules": [r], "ok_count": 1 if r.ok else 0, "length_m": 0.0}
		return
	var last := line_points[-1]
	var ref := Vector2.ZERO
	if line_points.size() >= 2:
		ref = Vector2(last.x - line_points[-2].x, last.z - line_points[-2].z).normalized()
	if not snap.is_empty():
		line_end = snap.point
	else:
		line_end = ModularLine.snap_end(def, last, cursor, angle_snap_deg if Input.is_key_pressed(KEY_SHIFT) else 0.0, ref)
	var pts := line_points.duplicate()
	pts.append(line_end)
	var total := 0
	for i in pts.size() - 1:
		total += ModularLine.segment_modules(def, pts[i], pts[i + 1])
	if total > max_line_modules:
		line_end = last
		pts = line_points
	check = structures.check_line(def, pts) if pts.size() >= 2 else {}


# --- Preview ----------------------------------------------------------------------

func _update_preview() -> void:
	_ghost.visible = false
	_line_ghost.visible = false
	_markers.visible = false
	_snap_ring.visible = false
	if not active:
		return
	if tool == Tool.DELETE and not hover.is_empty():
		var s := structures.state.get_structure(hover.id)
		if s:
			var d := StructureCatalog.get_def(s.type_id)
			_ghost.mesh = StructureCatalog.mesh_of(d)
			_ghost.material_override = _bad_mat
			_ghost.transform = s.instances[hover.index if s.is_line() else 0].scaled_local(Vector3(1.03, 1.03, 1.03))
			_ghost.visible = true
		return
	if tool != Tool.PLACE or def == null or check.is_empty():
		return
	if not snap.is_empty():
		_snap_ring.global_position = snap.point + Vector3.UP * 0.3
		_snap_ring.visible = true
	if not def.linear:
		_ghost.mesh = StructureCatalog.mesh_of(def)
		_ghost.material_override = _ghost_mat if check.ok else _bad_mat
		_ghost.transform = check.xform
		_ghost.visible = true
		return
	var mods: Array = check.get("modules", [])
	var mm := _line_ghost.multimesh
	if mm == null or mm.mesh != StructureCatalog.mesh_of(def):
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = StructureCatalog.mesh_of(def)
		_line_ghost.multimesh = mm
	mm.instance_count = mods.size()
	var end_snapped: bool = not snap.is_empty() and snap.centered and snap.id != -1 and line_points.size() > 0
	for i in mods.size():
		mm.set_instance_transform(i, mods[i].xform)
		var col := Color(0.25, 1.0, 0.35, 0.42) if mods[i].ok else Color(1.0, 0.15, 0.1, 0.55)
		if line_skip.has(i) or (end_snapped and i == mods.size() - 1 and i > 0):
			col = Color(0.6, 0.6, 0.6, 0.15)
		mm.set_instance_color(i, col)
	_line_ghost.visible = mods.size() > 0
	var markers := line_points.duplicate()
	if line_end.is_finite():
		markers.append(line_end)
	var mk := _markers.multimesh
	mk.instance_count = markers.size()
	for i in markers.size():
		mk.set_instance_transform(i, Transform3D(Basis.IDENTITY, markers[i] + Vector3.UP * 2.0))
	_markers.visible = markers.size() > 0


## One or two lines for the HUD.
func status_lines() -> Array[String]:
	var out: Array[String] = []
	if not active:
		return out
	match tool:
		Tool.NONE:
			out.append("CONSTRUCTION  choose a type on the left | X delete | F5 save, F9 load | B or Esc leave")
		Tool.DELETE:
			var what := "nothing under the cursor"
			if not hover.is_empty():
				var s := structures.state.get_structure(hover.id)
				what = StructureCatalog.get_def(s.type_id).display_name + (" module %d" % hover.index if s.is_line() else "")
			out.append("DELETE  click removes one building or line module, Shift+click a whole line | %s | RMB/Esc stop" % what)
		Tool.PLACE:
			if def.linear:
				var info := ""
				if check.has("modules"):
					var n: int = check.modules.size()
					var bad: int = n - check.ok_count
					info = "%d modules, %.0f m%s" % [n, check.length_m, (", %d blocked: %s" % [bad, _first_reason()]) if bad > 0 else ""]
				out.append("%s  LMB %s | Enter/RMB/double-click finish | Backspace undo corner | Shift 15° | Ctrl no snap | Esc cancel" % [
					def.display_name.to_upper(), "start" if line_points.is_empty() else "add corner"])
				out.append("%s%s" % [info, "  | snapped" if not snap.is_empty() else ""])
			else:
				out.append("%s  LMB build | R / Shift+R / Ctrl+wheel rotate (%.0f°) | RMB/Esc cancel" % [def.display_name.to_upper(), rad_to_deg(yaw)])
				out.append("OK to build" if check.get("ok", false) else "Cannot build: %s" % check.get("reason", "point at the ground"))
	if message != "":
		out.append(message)
	return out


func _first_reason() -> String:
	for m in check.get("modules", []):
		if not m.ok:
			return m.reason
	return ""


static func _make_ghost_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b) * 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.roughness = 0.6
	return m


static func _ensure_input_actions() -> void:
	var binds := {
		"construction_mode": [KEY_B], "construction_rotate": [KEY_R], "construction_finish": [KEY_ENTER, KEY_KP_ENTER],
		"construction_undo_point": [KEY_BACKSPACE], "construction_delete": [KEY_X, KEY_DELETE],
		"construction_save": [KEY_F5], "construction_load": [KEY_F9],
	}
	for action in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

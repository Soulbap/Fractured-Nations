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
## or a single line module, Shift+click removes a whole line. C toggles vegetation clearing:
## on (default), trees, shrubs and debris inside a new footprint are removed (persistent,
## saved with the base); off, trees block placement. Rocks and settlements always block.
##
## WORLD-PLAYTEST-01 roads and paved areas (category "Roads"). Roads are curves: each left
## click adds a control point, the road bends smoothly through them; a point can be dragged
## with the left button to reshape the curve before the road is built. Road ends snap to
## existing roads, road ends and junctions (Ctrl disables it); clicking onto a road with
## two or more points finishes there, as do Enter, right click and double click. The road
## is graded (cut and fill, grade limit per type) and shown green / red per section. Paved
## areas (yards, motor pools) are polygons: click the corners, click the first corner
## again or press Enter to close. Delete (X) removes a whole road or area.
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
## UNIT-01A: when set, F5 / F9 also save and load units and squads (world.json).
var world_state: WorldState
@export var rotate_step_deg := 15.0
@export var angle_snap_deg := 15.0
@export var max_line_modules := 800
## Clear trees and undergrowth inside new footprints (C toggles).
@export var clear_trees := true

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
var _check_key := []
## Bumped on every construction change so cached line checks are redone.
var _state_version := 0

## WORLD-PLAYTEST-01 surfaces: the road network for snapping, the snap of each placed
## point ({} = free, else a RoadNetwork.nearest() result), the point being dragged.
var point_snaps: Array = []
var _drag_index := -1
var _surface_key := []

var _ghost: MeshInstance3D
var _surface_ghost: MeshInstance3D
var _surface_mat: StandardMaterial3D
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
	_surface_ghost = MeshInstance3D.new()
	_surface_ghost.mesh = ImmediateMesh.new()
	_surface_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface_mat = _make_ghost_material(Color(1, 1, 1, 0.5))
	_surface_mat.vertex_color_use_as_albedo = true
	_surface_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_surface_mat.no_depth_test = false
	_surface_ghost.material_override = _surface_mat
	_surface_ghost.visible = false
	root.add_child(_surface_ghost)
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
	var st := structures.state
	if not st.structure_changed.is_connected(_on_state_changed):
		st.structure_added.connect(_on_state_changed)
		st.structure_removed.connect(_on_state_changed)
		st.structure_changed.connect(_on_state_changed)
		st.cleared.connect(_on_state_changed)
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


func _on_state_changed(_a = null) -> void:
	_state_version += 1


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
	point_snaps.clear()
	_drag_index = -1
	_surface_key = []
	line_end = Vector3.INF
	check = {}
	snap = {}
	_check_key = []
	_update_preview()


func clear_tool() -> void:
	cancel()
	tool = Tool.NONE
	def = null
	if panel:
		panel.refresh()


func save() -> bool:
	var err := structures.state.save_json(save_path)
	var units := ""
	if world_state:
		var werr := world_state.save_file(world_save_path())
		units = ", %d units, %d squads" % [world_state.units.size(), world_state.squads.size()] if werr == OK else ", units: save failed (%s)" % error_string(werr)
	_say(("Saved %d structures%s to %s" % [structures.state.count(), units, save_path.get_base_dir()]) if err == OK else "Save failed (%s)" % error_string(err))
	return err == OK


func load_saved() -> bool:
	cancel()
	var units := ""
	if world_state and FileAccess.file_exists(world_save_path()):
		var r: Variant = world_state.load_file(world_save_path())
		units = (", %d units, %d squads" % [world_state.units.size(), world_state.squads.size()]) if r is Dictionary else ", units: load failed"
	var err := structures.state.load_json(save_path)
	_say(("Loaded %d structures%s" % [structures.state.count(), units]) if err == OK else "Load failed (%s)" % error_string(err))
	return err == OK


## UNIT-01A: units and squads are saved next to the construction file.
func world_save_path() -> String:
	return save_path.get_base_dir().path_join("world.json")


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
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _drag_index >= 0:
		end_drag()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				update_cursor(event.position)
				if event.double_click and tool == Tool.PLACE and (def.linear or def.is_surface()):
					if def.is_surface():
						finish_surface()
					else:
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
	elif event.is_action_pressed("construction_clear"):
		clear_trees = not clear_trees
		_say("Vegetation clearing %s" % ("ON: trees inside new footprints are cut" if clear_trees else "OFF: trees block placement"))
	elif event.is_action_pressed("construction_rotate"):
		rotate_by(-rotate_step_deg if Input.is_key_pressed(KEY_SHIFT) else rotate_step_deg)
	elif event.is_action_pressed("construction_finish"):
		if tool == Tool.PLACE and def and def.is_surface():
			finish_surface()
		else:
			finish_line()
	elif event.is_action_pressed("construction_undo_point"):
		if line_points.size() > 0 and def and def.is_surface():
			line_points.remove_at(line_points.size() - 1)
			point_snaps.remove_at(point_snaps.size() - 1)
			_surface_key = []
		elif line_points.size() > 0:
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
			if def.is_surface():
				add_surface_point()
			elif def.linear:
				add_line_point()
			else:
				place_building()
		Tool.DELETE:
			delete_hovered(shift)


## Right click: finish a line, or cancel the current tool.
func secondary_action() -> void:
	if tool == Tool.PLACE and def.is_surface():
		if line_points.size() >= (3 if def.surface == StructureDef.Surface.AREA else 2):
			finish_surface()
		elif not line_points.is_empty():
			cancel()
		else:
			clear_tool()
		return
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
	structures.state.add_clearings(structures.clearings_for(s, clear_trees))
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
	var result := structures.check_line(def, pts, -1, clear_trees)
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
	structures.state.add_clearings(structures.clearings_for(s, clear_trees))
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
	if d.is_surface():
		structures.state.remove(s.id)
		_say("Removed %s" % d.display_name)
	elif s.is_line() and not whole_line:
		structures.state.remove_module(s.id, hover.index)
		_say("Removed one %s module" % d.display_name)
	else:
		structures.state.remove(s.id)
		_say("Removed %s" % d.display_name)
	hover = {}
	return true


func _closes_own_line() -> bool:
	return line_points.size() > 2 and Vector2(line_points[-1].x - line_points[0].x, line_points[-1].z - line_points[0].z).length() < 0.05


# --- Roads and paved areas (WORLD-PLAYTEST-01) -------------------------------------

## Radius (m) within which the cursor grabs a control point or snaps to a road.
func _grab_radius() -> float:
	return clampf(rig.zoom * 0.03, 2.0, 8.0)


## Left click with a road / area type: drag a nearby control point, or add one. A road
## point that snapped onto another road ends the road there (with two or more points); an
## area closes when its first corner is clicked again.
func add_surface_point() -> void:
	if not cursor.is_finite():
		return
	var grab := _grab_radius()
	for i in line_points.size():
		if Vector2(line_points[i].x - cursor.x, line_points[i].z - cursor.z).length() < grab:
			if def.surface == StructureDef.Surface.AREA and i == 0 and line_points.size() >= 3:
				finish_surface()
				return
			_drag_index = i
			return
	var p: Vector3 = snap.point if not snap.is_empty() else cursor
	line_points.append(p)
	point_snaps.append(snap.get("road", {}))
	_surface_key = []
	if def.surface == StructureDef.Surface.ROAD and line_points.size() >= 2 and not snap.is_empty():
		finish_surface()


## Ends dragging a control point (it keeps the position and snap it was dragged to).
func end_drag() -> void:
	_drag_index = -1
	_surface_key = []


## Builds the road / area through the points placed so far (the cursor is not a point).
func finish_surface() -> StructureState:
	var min_n := 3 if def.surface == StructureDef.Surface.AREA else 2
	if line_points.size() < min_n:
		_say("Place at least %d points" % min_n)
		return null
	var pts := line_points.duplicate()
	var res := _check_surface(pts)
	if not res.ok:
		_say("Cannot build %s: %s" % [def.display_name.to_lower(), res.reason])
		return null
	var s := structures.state.add_surface(def.id, pts, res.profile)
	if s == null:
		return null
	structures.state.add_clearings(structures.clearings_for(s, clear_trees))
	if def.surface == StructureDef.Surface.ROAD:
		_say("Built %s: %.0f m, steepest %.0f %%, cut / fill up to %.1f m%s" % [def.display_name, res.length_m, res.grade * 100.0,
			res.max_cut_m, _joins_text()])
	else:
		_say("Built %s: %.0f m², slope %.1f %%, cut / fill up to %.1f m" % [def.display_name, res.area_m2, res.grade * 100.0, res.max_cut_m])
	cancel()
	built.emit(s)
	return s


func _joins_text() -> String:
	var n := 0
	for sn in [point_snaps[0], point_snaps[-1]] if not point_snaps.is_empty() else []:
		if not (sn as Dictionary).is_empty():
			n += 1
	return "" if n == 0 else ", joined to %d road%s" % [n, "s" if n > 1 else ""]


func _check_surface(pts: PackedVector3Array) -> Dictionary:
	if def.surface == StructureDef.Surface.ROAD:
		var start: Dictionary = point_snaps[0] if point_snaps.size() > 0 else {}
		var end: Dictionary = point_snaps[pts.size() - 1] if point_snaps.size() >= pts.size() and pts.size() > 1 else {}
		return structures.check_road(def, pts, start, end, clear_trees)
	return structures.check_area(def, pts, clear_trees)


## Snap target for a road point: the nearest road, road end or junction in reach.
func _road_snap(p: Vector3) -> Dictionary:
	if world_state == null or Input.is_key_pressed(KEY_CTRL):
		return {}
	var n := world_state.roads.nearest(p, _grab_radius(), 0, maxf(6.0, _grab_radius()))
	if n.is_empty():
		return {}
	return {"point": n.pos, "dir": n.dir, "id": -1, "index": 0, "centered": false, "road": n}


func _refresh_surface_check() -> void:
	if _drag_index >= 0 and _drag_index < line_points.size():
		var free_end := _drag_index == 0 or _drag_index == line_points.size() - 1
		var use_snap := free_end and not snap.is_empty() and def.surface == StructureDef.Surface.ROAD
		line_points[_drag_index] = snap.point if use_snap else cursor
		point_snaps[_drag_index] = snap.get("road", {}) if use_snap else {}
	var pts := line_points.duplicate()
	var snaps_backup := point_snaps.duplicate()
	if _drag_index < 0 and cursor.is_finite():
		pts.append(snap.point if not snap.is_empty() else cursor)
		point_snaps.append(snap.get("road", {}))
	var min_n := 3 if def.surface == StructureDef.Surface.AREA else 2
	var key := [def.id, pts, _state_version, clear_trees]
	if key != _surface_key:
		_surface_key = key
		check = _check_surface(pts) if pts.size() >= min_n else {}
		check["points"] = pts
	point_snaps = snaps_backup


func _draw_surface_preview() -> void:
	var im := _surface_ghost.mesh as ImmediateMesh
	im.clear_surfaces()
	var drew := false
	var pts: PackedVector3Array = check.get("points", line_points)
	if def.surface == StructureDef.Surface.ROAD and check.has("profile") and (check.profile as PackedVector3Array).size() >= 2:
		var prof: PackedVector3Array = check.profile
		var bad := {}
		for i in check.get("bad", PackedInt32Array()):
			bad[i] = true
		var half := def.surface_width * 0.5
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in prof.size() - 1:
			var a := prof[i]
			var b := prof[i + 1]
			var d := Vector2(b.x - a.x, b.z - a.z).normalized()
			var side := Vector3(-d.y, 0.0, d.x) * half
			var col := Color(1.0, 0.2, 0.15, 0.55) if (bad.has(i) or bad.has(i + 1) or not check.ok and bad.is_empty()) else Color(0.3, 1.0, 0.4, 0.45)
			var up := Vector3.UP * 0.25
			for v in [a - side, b - side, b + side, a - side, b + side, a + side]:
				im.surface_set_color(col)
				im.surface_add_vertex(v + up)
		im.surface_end()
		drew = true
	elif def.surface == StructureDef.Surface.AREA and pts.size() >= 2:
		var ok: bool = check.get("ok", false)
		var col := Color(0.3, 1.0, 0.4, 0.4) if ok else Color(1.0, 0.2, 0.15, 0.5)
		var poly := PackedVector2Array()
		for p in pts:
			poly.append(Vector2(p.x, p.z))
		var c := Vector3.ZERO
		var g := Vector3.ZERO
		if check.has("profile") and (check.profile as PackedVector3Array).size() >= 2:
			c = check.profile[0]
			g = check.profile[1]
		var tri := Geometry2D.triangulate_polygon(poly) if pts.size() >= 3 else PackedInt32Array()
		if not tri.is_empty():
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in tri:
				var q := poly[i]
				var y: float = c.y + g.x * (q.x - c.x) + g.z * (q.y - c.z) if c != Vector3.ZERO else pts[i].y
				im.surface_set_color(col)
				im.surface_add_vertex(Vector3(q.x, y + 0.3, q.y))
			im.surface_end()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			if i == pts.size() - 1 and pts.size() < 3:
				break
			im.surface_set_color(Color(1, 1, 1, 0.9))
			im.surface_add_vertex(a + Vector3.UP * 0.4)
			im.surface_set_color(Color(1, 1, 1, 0.9))
			im.surface_add_vertex(b + Vector3.UP * 0.4)
		im.surface_end()
		drew = true
	_surface_ghost.visible = drew
	var markers := line_points.duplicate()
	var mk := _markers.multimesh
	mk.instance_count = markers.size()
	for i in markers.size():
		var scale := 1.6 if i == _drag_index else 1.0
		mk.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(scale, 0.5, scale)), markers[i] + Vector3.UP * 1.0))
	_markers.visible = markers.size() > 0


## Delete tool: a road / area under the cursor is highlighted in red.
func _draw_surface_hover(s: StructureState) -> void:
	var d := StructureCatalog.get_def(s.type_id)
	var im := _surface_ghost.mesh as ImmediateMesh
	im.clear_surfaces()
	var col := Color(1.0, 0.2, 0.15, 0.6)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if d.surface == StructureDef.Surface.ROAD:
		var half := d.surface_width * 0.5 + 0.2
		for i in s.profile.size() - 1:
			var a := s.profile[i]
			var b := s.profile[i + 1]
			var dd := Vector2(b.x - a.x, b.z - a.z).normalized()
			var side := Vector3(-dd.y, 0.0, dd.x) * half
			for v in [a - side, b - side, b + side, a - side, b + side, a + side]:
				im.surface_set_color(col)
				im.surface_add_vertex(v + Vector3.UP * 0.3)
	else:
		var poly := PackedVector2Array()
		for p in s.points:
			poly.append(Vector2(p.x, p.z))
		var c: Vector3 = s.profile[0]
		var g: Vector3 = s.profile[1]
		for i in Geometry2D.triangulate_polygon(poly):
			var q := poly[i]
			im.surface_set_color(col)
			im.surface_add_vertex(Vector3(q.x, c.y + g.x * (q.x - c.x) + g.z * (q.y - c.z) + 0.35, q.y))
	im.surface_end()
	_surface_ghost.visible = true


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
	if tool == Tool.PLACE and def and def.is_surface() and cursor.is_finite():
		if def.surface == StructureDef.Surface.ROAD:
			snap = _road_snap(cursor)
		_refresh_surface_check()
	elif tool == Tool.PLACE and def and cursor.is_finite():
		if def.linear and not Input.is_key_pressed(KEY_CTRL):
			snap = _find_snap(cursor)
		elif not def.linear and not def.snap_points.is_empty() and not Input.is_key_pressed(KEY_CTRL):
			_snap_building()
		_refresh_check()
	elif tool == Tool.DELETE:
		var cam := rig.camera
		hover = structures.pick(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
		if hover.is_empty():
			var sid := structures.pick_surface(cursor)
			if sid >= 0:
				hover = {"id": sid, "index": -1, "surface": true}
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
		check = structures.check_building(def, cursor, yaw, -1, clear_trees)
		return
	if line_points.is_empty():
		var p: Vector3 = snap.point if not snap.is_empty() else cursor
		var dir := Vector2.RIGHT
		if not snap.is_empty() and snap.dir != Vector2.ZERO:
			dir = snap.dir
		line_end = Vector3.INF
		var r := structures.fit_module(def, Vector2(p.x, p.z) + (dir * def.module_length * 0.5 if def.layout == StructureDef.Layout.SPAN else Vector2.ZERO), dir)
		if r.ok:
			r.reason = structures._blocked(def, StructureManager._obb(def, r.xform), -1, -1, clear_trees)
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
	# The cursor often rests: validate a line only when its points changed.
	var key := [def.id, pts, structures.state.count(), _state_version, clear_trees]
	if key == _check_key:
		return
	_check_key = key
	var total := 0
	for i in pts.size() - 1:
		total += ModularLine.segment_modules(def, pts[i], pts[i + 1])
	if total > max_line_modules:
		line_end = last
		pts = line_points
	check = structures.check_line(def, pts, -1, clear_trees) if pts.size() >= 2 else {}


# --- Preview ----------------------------------------------------------------------

func _update_preview() -> void:
	_ghost.visible = false
	_line_ghost.visible = false
	_markers.visible = false
	_snap_ring.visible = false
	_surface_ghost.visible = false
	if not active:
		return
	if tool == Tool.DELETE and not hover.is_empty() and hover.get("surface", false):
		var ss := structures.state.get_structure(hover.id)
		if ss:
			_draw_surface_hover(ss)
		return
	if tool == Tool.PLACE and def and def.is_surface():
		if not snap.is_empty():
			_snap_ring.global_position = snap.point + Vector3.UP * 0.3
			_snap_ring.visible = true
		_draw_surface_preview()
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
			out.append("CONSTRUCTION  choose a type on the left | X delete | C clearing %s | F5 save, F9 load | B or Esc leave" % ("ON" if clear_trees else "OFF"))
		Tool.DELETE:
			var what := "nothing under the cursor"
			if not hover.is_empty():
				var s := structures.state.get_structure(hover.id)
				what = StructureCatalog.get_def(s.type_id).display_name + (" module %d" % hover.index if s.is_line() and not hover.get("surface", false) else "")
			out.append("DELETE  click removes one building or line module, Shift+click a whole line | %s | RMB/Esc stop" % what)
		Tool.PLACE:
			if def.is_surface():
				out.append_array(_surface_status())
			elif def.linear:
				var info := ""
				if check.has("modules"):
					var n: int = check.modules.size()
					var bad: int = n - check.ok_count
					info = "%d modules, %.0f m%s" % [n, check.length_m, (", %d blocked: %s" % [bad, _first_reason()]) if bad > 0 else ""]
				out.append("%s  LMB %s | Enter/RMB/double-click finish | Backspace undo corner | Shift 15° | Ctrl no snap | Esc cancel" % [
					def.display_name.to_upper(), "start" if line_points.is_empty() else "add corner"])
				out.append("%s%s  | C clearing %s" % [info, "  | snapped" if not snap.is_empty() else "", "ON" if clear_trees else "OFF"])
			else:
				out.append("%s  LMB build | R / Shift+R / Ctrl+wheel rotate (%.0f°) | RMB/Esc cancel" % [def.display_name.to_upper(), rad_to_deg(yaw)])
				var lvl: float = check.get("level_m", 0.0)
				out.append(("OK to build%s" % ("  (groundwork: levels up to %.1f m)" % lvl if lvl >= 0.1 else "") if check.get("ok", false) else "Cannot build: %s" % check.get("reason", "point at the ground"))
					+ "  | C clearing %s" % ("ON" if clear_trees else "OFF"))
	if message != "":
		out.append(message)
	return out


func _surface_status() -> Array[String]:
	var out: Array[String] = []
	var road := def.surface == StructureDef.Surface.ROAD
	if road:
		out.append("%s  LMB %s | drag a point to bend | click a road / Enter / RMB finish | Backspace undo | Ctrl no snap | Esc cancel" % [
			def.display_name.to_upper(), "start" if line_points.is_empty() else "add control point"])
	else:
		out.append("%s  LMB add corner | click the first corner / Enter / RMB close | drag a corner to move it | Backspace undo | Esc cancel" % def.display_name.to_upper())
	var info := ""
	if check.has("ok"):
		if road:
			info = "%.0f m, steepest %.0f %% (max %.0f %%), cut / fill %.1f m" % [check.length_m, check.grade * 100.0, def.max_grade * 100.0, check.max_cut_m]
		else:
			info = "%.0f m², slope %.1f %%, cut / fill %.1f m" % [check.area_m2, check.grade * 100.0, check.max_cut_m]
		info += "  OK" if check.ok else "  - cannot build: %s" % check.reason
	if not snap.is_empty():
		info += "  | snapped to %s" % ((snap.road.road as RoadNetwork.Road).name if snap.has("road") else "road")
	out.append(info + "  | C clearing %s" % ("ON" if clear_trees else "OFF"))
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
		"construction_save": [KEY_F5], "construction_load": [KEY_F9], "construction_clear": [KEY_C],
	}
	for action in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

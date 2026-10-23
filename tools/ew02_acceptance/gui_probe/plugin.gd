## EDITOR-WORLD-02B GUI acceptance. Run ONLY in an isolated project copy (copy of worlds/ref_20km) with
## FRACTURED_WORLD_OVERRIDES pointing to a scratch file and EW02_OUT to a scratch directory.
##   EW02_PHASE=1  first editor session: select / transform / undo / add / remove / restore / save
##   EW02_PHASE=2  fresh editor session: persisted state, remove / restore after restart, digest for the runtime
## Results: $EW02_OUT/gui_phase<N>.json, screenshots $EW02_OUT/shots/*.png, digest $EW02_OUT/gui_digest.json
@tool
extends EditorPlugin

const SCENE := "res://scenes/world/ref_20km.tscn"
const Digest = preload("res://tools/ew02_acceptance/world_digest.gd")

var rep := {}
var out_dir := ""
var plugin: Object
var streamer: VegetationStreamer
var layer: RefCounted
var viewport: SubViewport
var phase := 1


func _enter_tree() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _dump() -> void:
	var f := FileAccess.open(out_dir.path_join("gui_phase%d.json" % phase), FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()


func _chk(name: String, ok: bool, info: Variant = null) -> bool:
	rep[name] = {"ok": ok} if info == null else {"ok": ok, "info": info}
	print("EW02GUI ", name, " ", ok, " ", info if info != null else "")
	_dump()
	return ok


func _shot(name: String) -> void:
	await _frames(8)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("shots"))
	var img := EditorInterface.get_base_control().get_window().get_texture().get_image()
	img.save_png(out_dir.path_join("shots/%s.png" % name))


func _button(text: String) -> Button:
	for n in plugin.bar.get_children():
		if n is Button and n.text == text:
			return n
	return null


func _cam() -> Camera3D:
	return viewport.get_camera_3d()


## Places the editor camera `dist` metres from `target`, looking at it.
func _look_at(target: Vector3, dist := 16.0, height := 9.0) -> void:
	var pos := target + Vector3(dist * 0.5, height, dist * 0.87)
	_cam().global_transform = Transform3D(Basis(), pos).looking_at(target, Vector3.UP)


## Screen position of a world point in window coordinates (for Input.parse_input_event).
func _window_pos(world: Vector3) -> Vector2:
	var container := viewport.get_parent() as Control
	var local := _cam().unproject_position(world)
	return container.get_global_rect().position + local * (container.size / Vector2(viewport.size))


func _click_world(world: Vector3, ctrl := false) -> String:
	var wp := _window_pos(world)
	var local := _cam().unproject_position(world)
	var before_id: String = plugin.selected.get("id", "")
	var move := InputEventMouseMotion.new()
	move.position = wp
	move.global_position = wp
	Input.parse_input_event(move)
	await _frames(3)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.ctrl_pressed = ctrl
		ev.position = wp
		ev.global_position = wp
		Input.parse_input_event(ev)
		await _frames(3)
	if plugin.selected.get("id", "") != before_id and not plugin.selected.is_empty():
		return "gui"
	# Fall back to the plugin's own input handler (the window may not have focus): reported as such.
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = true
	ev2.position = local
	ev2.ctrl_pressed = ctrl
	plugin._forward_3d_gui_input(_cam(), ev2)
	await _frames(3)
	return "direct"


func _key(code: Key, ctrl := true, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await _frames(3)


func _has(cell: Vector2i, mesh: int, origin: Vector3, tol := 0.02) -> bool:
	for v in streamer.get_cell_instances(cell, [mesh]):
		if v[1].origin.distance_to(origin) < tol:
			return true
	return false


func _cell(p: Vector3) -> Vector2i:
	return VegetationChunk.cell_of(p, streamer.cell_size_m)


func _displayed(origin: Vector3, mesh: int, tol := 0.02) -> int:
	var n := 0
	for key: Vector3i in streamer.active:
		if key.z != mesh:
			continue
		var buf: PackedFloat32Array = streamer.active[key].multimesh.buffer
		for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
			if VegetationChunk.instance_transform(buf, i).origin.distance_to(origin) < tol:
				n += 1
	return n


func _scene_tab_dirty() -> bool:
	for tb in EditorInterface.get_base_control().find_children("*", "TabBar", true, false):
		for i in tb.tab_count:
			var t: String = tb.get_tab_title(i)
			if t.begins_with("ref_20km") and t.contains("(*)"):
				return true
	return false


func _first_instance(chunk: VegetationChunk, mesh_ids: Array, skip := 0) -> Dictionary:
	var seen := 0
	for cell in chunk.cells:
		for mesh_id in mesh_ids:
			if chunk.cells[cell].has(mesh_id):
				var buf: PackedFloat32Array = chunk.cells[cell][mesh_id]
				for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
					if seen >= skip:
						return {"cell": cell, "mesh": mesh_id, "index": i, "xf": VegetationChunk.instance_transform(buf, i)}
					seen += 1
	return {}


## A tree (or a house) with no other solid instance within `gap` metres, so a click on it is unambiguous.
func _isolated(chunk: VegetationChunk, mesh_ids: Array, gap := 9.0, skip := 0) -> Dictionary:
	var all := []
	for cell in chunk.cells:
		for mesh_id in chunk.cells[cell]:
			if [1, 2, 3, 4, 5, 6, 9, 10, 12, 16, 17, 18].has(int(mesh_id)):
				var buf: PackedFloat32Array = chunk.cells[cell][mesh_id]
				for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
					all.append([cell, int(mesh_id), i, VegetationChunk.instance_transform(buf, i)])
	var seen := 0
	for a in all:
		if not mesh_ids.has(a[1]):
			continue
		var lonely := true
		for b in all:
			if b != a and Vector2(a[3].origin.x - b[3].origin.x, a[3].origin.z - b[3].origin.z).length() < gap:
				lonely = false
				break
		if lonely:
			if seen >= skip:
				return {"cell": a[0], "mesh": a[1], "index": a[2], "xf": a[3]}
			seen += 1
	return {}


func _t(xf: Transform3D) -> Array:
	return layer._encode(xf)


func _setup() -> bool:
	out_dir = OS.get_environment("EW02_OUT")
	phase = int(OS.get_environment("EW02_PHASE"))
	await _frames(120)
	EditorInterface.open_scene_from_path(SCENE)
	await _frames(600)
	var root := EditorInterface.get_edited_scene_root()
	if not _chk("scene_open", root != null and root.scene_file_path == SCENE):
		return false
	_chk("world_edit_enabled", EditorInterface.is_plugin_enabled("res://addons/world_edit/plugin.cfg"))
	_chk("viewpoints_enabled", EditorInterface.is_plugin_enabled("res://tools/editor_viewpoints/plugin.cfg"))
	for n in root.find_children("*", "Node3D", true, false):
		if n is VegetationStreamer:
			streamer = n
			break
	_chk("override_file_isolated", streamer != null and streamer.overrides.path == OS.get_environment("FRACTURED_WORLD_OVERRIDES"), streamer.overrides.path if streamer else "")
	layer = streamer.overrides
	viewport = EditorInterface.get_editor_viewport_3d(0)
	var terrain := root.find_children("*", "Terrain3D", true, false)
	_chk("terrain_present", not terrain.is_empty() and terrain[0].data != null)
	var containers := root.find_children("*", "RoadContainer", true, false)
	_chk("roads_present", containers.size() > 100, containers.size())
	_chk("scene_not_dirty_after_open", not _scene_tab_dirty())
	var ur := EditorInterface.get_editor_undo_redo()
	var conn := root.get_node_or_null("Roads/Terrain3DRoadConnector")
	var hist := ur.get_history_undo_redo(ur.get_object_history_id(conn)) if conn else null
	_chk("no_automatic_flatten", hist != null and hist.get_current_action_name() != "Flatten terrain under roads", hist.get_current_action_name() if hist else "")
	var vp = load("res://tools/editor_viewpoints/plugin.gd")
	var ok_vp: bool = vp.move_camera({"xz": Vector2(-917.0, -2045.0), "alt": 60.0, "dist": 120.0})
	await _frames(300)
	_chk("viewpoint_moves_camera", ok_vp)
	await _shot("p%d_01_haugen_overview" % phase)
	var toggle: CheckButton = null
	for n in EditorInterface.get_base_control().find_children("*", "CheckButton", true, false):
		if n.text == "World objects":
			toggle = n
	_chk("toolbar_found", toggle != null)
	plugin = toggle.toggled.get_connections()[0].callable.get_object()
	toggle.button_pressed = true
	await _frames(30)
	_chk("plugin_bound_to_streamer", plugin.streamer == streamer)
	return true


func _phase1() -> void:
	var chunk := streamer.get_chunk_sync(Vector2i(-2, -5))
	# EW02B-01: select a tree through the GUI path
	var tree_i := _isolated(chunk, [3, 4, 5], 9.0, 0)
	var txf: Transform3D = tree_i.xf
	_look_at(txf.origin + Vector3(0, 3, 0), 12.0, 4.0)
	await _frames(240)
	var path := await _click_world(txf.origin + Vector3(0, 3, 0))
	var sel: Dictionary = plugin.selected
	_chk("EW02B-01_select_tree", not sel.is_empty() and sel.get("kind") == "generated" and int(sel.mesh) in [3, 4, 5] and sel.transform.origin.distance_to(txf.origin) < 1.5,
		{"path": path, "id": sel.get("id", ""), "target": txf.origin, "describe": plugin.describe(sel) if not sel.is_empty() else "", "pick": plugin.last_pick})
	await _shot("p1_02_tree_selected")
	var tree_id: String = sel.get("id", "")
	var orig: Transform3D = sel.transform
	# EW02B-03: move, rotate, scale through the proxy (auto-applied by the plugin)
	var target := Transform3D(orig.basis.rotated(Vector3.UP, deg_to_rad(30.0)).scaled(Vector3(1.4, 1.4, 1.4)), orig.origin + Vector3(7, 0, 3))
	var src_cell: Vector2i = sel.cell
	var src_mesh: int = sel.mesh
	var color_before: PackedFloat32Array = chunk.cells[src_cell][src_mesh].slice(sel.index * 16 + 12, sel.index * 16 + 16)
	plugin.proxy.global_transform = target
	await _frames(10)
	var dest := _cell(target.origin)
	_chk("EW02B-03_tree_moved_rotated_scaled", layer.records.has(tree_id) and _has(dest, src_mesh, target.origin) and not _has(_cell(orig.origin), src_mesh, orig.origin),
		{"describe": plugin.describe(plugin.selected), "records": layer.records.size()})
	var eff: Dictionary = streamer._effective_cell(dest)
	var found_color := false
	for i in eff[src_mesh].size() / 16:
		if VegetationChunk.instance_transform(eff[src_mesh], i).origin.distance_to(target.origin) < 0.02:
			found_color = eff[src_mesh].slice(i * 16 + 12, i * 16 + 16) == color_before
	_chk("EW02B-03_colour_preserved", found_color)
	await _shot("p1_03_tree_moved")
	# EW02B-04: undo / redo via toolbar, then keyboard
	_button("Undo").pressed.emit()
	await _frames(5)
	_chk("EW02B-04_undo_button", _has(_cell(orig.origin), src_mesh, orig.origin) and not layer.records.has(tree_id))
	_button("Redo").pressed.emit()
	await _frames(5)
	_chk("EW02B-04_redo_button", _has(dest, src_mesh, target.origin) and layer.records.has(tree_id))
	await _key(KEY_Z)
	var undone_by_key: bool = not layer.records.has(tree_id)
	await _key(KEY_Z, true, true)
	var redone_by_key: bool = layer.records.has(tree_id)
	_chk("EW02B-04_ctrl_z_ctrl_shift_z", undone_by_key and redone_by_key, {"undo": undone_by_key, "redo": redone_by_key})
	# EW02B-02: select a house, move 20 m + rotate 30
	var house_i := _first_instance(streamer.get_chunk_sync(Vector2i(-2, -5)), [16])
	var hxf: Transform3D = house_i.xf
	_look_at(hxf.origin + Vector3(0, 3, 0), 40.0, 25.0)
	await _frames(240)
	var path2 := await _click_world(hxf.origin + Vector3(0, 3, 0))
	var hsel: Dictionary = plugin.selected
	_chk("EW02B-02_select_house", not hsel.is_empty() and int(hsel.mesh) == 16 and hsel.transform.origin.distance_to(hxf.origin) < 12.0,
		{"path": path2, "id": hsel.get("id", ""), "describe": plugin.describe(hsel) if not hsel.is_empty() else ""})
	await _shot("p1_04_house_selected")
	var house_id: String = hsel.get("id", "")
	var horig: Transform3D = hsel.transform
	var hmoved := Transform3D(horig.basis.rotated(Vector3.UP, deg_to_rad(30.0)), horig.origin + Vector3(20, 0, 0))
	plugin.proxy.global_transform = hmoved
	await _frames(10)
	_chk("EW02B-03_house_moved_rotated", _has(_cell(hmoved.origin), 16, hmoved.origin) and not _has(_cell(horig.origin), 16, horig.origin), plugin.describe(plugin.selected))
	await _shot("p1_05_house_moved")
	# EW02B-05: ADD tree / stone / house through the toolbar
	var added := {}
	for item in [["tree", 3], ["stone", 9], ["house", 16]]:
		plugin.palette.select(plugin.palette.get_item_index(item[1]))
		_look_at(hmoved.origin + Vector3(-30, 0, 30), 30.0, 20.0)
		await _frames(30)
		_button("Add").pressed.emit()
		await _frames(6)
		var id: String = plugin.selected.get("id", "")
		added[item[0]] = id
		_chk("EW02B-05_add_" + item[0], id.begins_with("a:") and layer.records.has(id) and _has(_cell(plugin.selected.transform.origin), item[1], plugin.selected.transform.origin), plugin.describe(plugin.selected))
		plugin.proxy.global_transform = Transform3D(Basis.IDENTITY, plugin.selected.transform.origin + Vector3(10.0 * added.size(), 0, 6.0 * added.size()))
		await _frames(10)
	await _shot("p1_06_added_objects")
	# place mode: click on the terrain
	plugin.place_toggle.button_pressed = true
	plugin.palette.select(plugin.palette.get_item_index(3))
	var ground := Vector3(hmoved.origin.x - 25.0, 0, hmoved.origin.z + 35.0)
	var terrain_node: Terrain3D = EditorInterface.get_edited_scene_root().find_children("*", "Terrain3D", true, false)[0]
	ground.y = terrain_node.data.get_height(ground)
	_look_at(ground, 22.0, 14.0)
	await _frames(60)
	var records_before: int = layer.records.size()
	var pm := await _click_world(ground)
	plugin.place_toggle.button_pressed = false
	_chk("EW02B-05_place_mode_click", layer.records.size() == records_before + 1, {"path": pm, "describe": plugin.describe(plugin.selected)})
	added["placed"] = plugin.selected.get("id", "")
	# EW02B-06: REMOVE generated, REMOVE added, RESTORE
	var neigh := _isolated(streamer.get_chunk_sync(Vector2i(-2, -5)), [3, 4, 5], 9.0, 3)
	var nxf: Transform3D = neigh.xf
	_look_at(nxf.origin + Vector3(0, 3, 0), 12.0, 4.0)
	await _frames(240)
	await _click_world(nxf.origin + Vector3(0, 3, 0))
	var rm_id: String = plugin.selected.get("id", "")
	var rm_xf: Transform3D = plugin.selected.transform
	var rm_mesh: int = plugin.selected.get("mesh", 3)
	_button("Remove").pressed.emit()
	await _frames(6)
	_chk("EW02B-06_remove_generated", rm_id.begins_with("g:") and layer.records.get(rm_id, {}).get("removed", false) and not _has(_cell(rm_xf.origin), rm_mesh, rm_xf.origin), rm_id)
	var removed_list: Array = plugin.removed_ids()
	_chk("EW02B-06_removed_list_contains", removed_list.has(rm_id), removed_list)
	plugin._fill_removed()
	plugin.removed_menu.get_popup().id_pressed.emit(removed_list.find(rm_id))
	await _frames(6)
	_chk("EW02B-06_restore_generated_via_menu", not layer.records.has(rm_id) and _has(_cell(rm_xf.origin), rm_mesh, rm_xf.origin), plugin.describe(plugin.selected))
	plugin._select({"id": added.stone, "mesh": 9, "kind": "added", "transform": layer._decode(layer.records[added.stone].transform)})
	_button("Remove").pressed.emit()
	await _frames(6)
	_chk("EW02B-06_remove_added", layer.records[added.stone].removed == true)
	plugin.restore_removed(added.stone)
	await _frames(6)
	_chk("EW02B-06_restore_added", layer.records[added.stone].removed == false)
	plugin._select({"id": added.tree, "mesh": 3, "kind": "added", "transform": layer._decode(layer.records[added.tree].transform)})
	_button("Remove").pressed.emit()
	await _frames(4)
	var removed_ok: bool = layer.records[added.tree].removed
	_button("Undo").pressed.emit()
	await _frames(4)
	_chk("EW02B-04_undo_removal", removed_ok and not layer.records[added.tree].removed)
	# one generated object stays removed through the restart
	await _click_world(nxf.origin + Vector3(0, 3, 0))
	var kept_removed: String = plugin.selected.get("id", "")
	_button("Remove").pressed.emit()
	await _frames(6)
	# gizmo drag through the real mouse path (informational)
	plugin._select({"id": added.placed, "mesh": 3, "kind": "added", "transform": layer._decode(layer.records[added.placed].transform)})
	await _frames(10)
	if is_instance_valid(plugin.proxy):
		var proxy_before: Vector3 = plugin.proxy.global_transform.origin
		var swallowed_before: int = plugin.swallowed_actions
		_look_at(plugin.proxy.global_position + Vector3(0, 2, 0), 12.0, 6.0)
		await _frames(30)
		var o: Vector3 = plugin.proxy.global_position
		var origin_px := _window_pos(o)
		var dir := (_window_pos(o + Vector3(1, 0, 0)) - origin_px).normalized()
		var start := origin_px + dir * 55.0
		var m := InputEventMouseMotion.new()
		m.position = start
		m.global_position = start
		Input.parse_input_event(m)
		await _frames(4)
		var d := InputEventMouseButton.new()
		d.button_index = MOUSE_BUTTON_LEFT
		d.pressed = true
		d.position = start
		d.global_position = start
		Input.parse_input_event(d)
		await _frames(3)
		for step in 8:
			var mm := InputEventMouseMotion.new()
			mm.position = start + dir * 8.0 * (step + 1)
			mm.global_position = mm.position
			mm.relative = dir * 8.0
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(mm)
			await _frames(2)
		var u := InputEventMouseButton.new()
		u.button_index = MOUSE_BUTTON_LEFT
		u.pressed = false
		u.position = start + dir * 64.0
		u.global_position = u.position
		Input.parse_input_event(u)
		await _frames(30)
		var moved_m: float = plugin.proxy.global_transform.origin.distance_to(proxy_before) if is_instance_valid(plugin.proxy) else -1.0
		rep.gizmo_real_mouse_drag = {"moved_m": moved_m, "swallowed_scene_actions": plugin.swallowed_actions - swallowed_before, "scene_dirty": _scene_tab_dirty(),
			"note": "informational: gizmo handle drag with synthetic OS-level mouse events"}
		print("EW02GUI gizmo_real_mouse_drag ", rep.gizmo_real_mouse_drag)
		_dump()
	# EW02B-07: save (button)
	_button("Save").pressed.emit()
	await _frames(10)
	_chk("EW02B-07_saved", FileAccess.file_exists(layer.path) and not plugin.dirty, FileAccess.get_file_as_string(layer.path).length())
	rep.phase1_state = {"tree_id": tree_id, "tree_target": _t(target), "tree_orig": _t(orig), "tree_mesh": src_mesh, "house_id": house_id, "house_target": _t(hmoved),
		"house_orig": _t(horig), "added": added, "kept_removed": kept_removed, "records": layer.records.size()}
	_chk("scene_not_dirty_at_end", not _scene_tab_dirty(), "tab asterisk after all operations")
	await _shot("p1_07_final")


func _phase2() -> void:
	var p1: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out_dir.path_join("gui_phase1.json"))).phase1_state
	_chk("EW02B-07_records_reloaded", layer.records.size() == int(p1.records) and layer.unresolved.is_empty(), {"records": layer.records.size(), "unresolved": layer.unresolved.size()})
	var tt: Transform3D = layer._decode(p1.tree_target)
	var to: Transform3D = layer._decode(p1.tree_orig)
	var tmesh := int(p1.tree_mesh)
	var ht: Transform3D = layer._decode(p1.house_target)
	var ho: Transform3D = layer._decode(p1.house_orig)
	_chk("EW02B-07_tree_at_new_place", _has(_cell(tt.origin), tmesh, tt.origin) and not _has(_cell(to.origin), tmesh, to.origin))
	_chk("EW02B-07_house_at_new_place", _has(_cell(ht.origin), 16, ht.origin) and not _has(_cell(ho.origin), 16, ho.origin))
	var added_ok := true
	for k in p1.added:
		added_ok = added_ok and layer.records.has(p1.added[k])
	_chk("EW02B-07_added_objects_persist", added_ok)
	var kr: String = p1.kept_removed
	_chk("EW02B-07_removed_persists", layer.records.get(kr, {}).get("removed", false) == true and plugin.removed_ids().has(kr))
	_look_at(tt.origin, 40.0, 25.0)
	await _frames(300)
	_chk("EW02B-07_tree_displayed_once", _displayed(tt.origin, tmesh) == 1 and _displayed(to.origin, tmesh) == 0)
	await _shot("p2_01_tree_after_restart")
	_look_at(ht.origin, 60.0, 35.0)
	await _frames(300)
	_chk("EW02B-07_house_displayed_once", _displayed(ht.origin, 16) == 1 and _displayed(ho.origin, 16) == 0)
	await _shot("p2_02_house_after_restart")
	# REMOVE + RESTORE after restart on the persisted tree: select it again by click
	_look_at(tt.origin + Vector3(0, 3, 0), 12.0, 4.0)
	await _frames(240)
	var path := await _click_world(tt.origin + Vector3(0, 3, 0))
	var sel: Dictionary = plugin.selected
	_chk("EW02B-06_select_persisted_tree", sel.get("id", "") == p1.tree_id, {"path": path, "id": sel.get("id", "")})
	_button("Remove").pressed.emit()
	await _frames(6)
	_chk("EW02B-06_remove_after_restart", not _has(_cell(tt.origin), tmesh, tt.origin) and layer.records[p1.tree_id].removed)
	plugin._fill_removed()
	var ids: Array = plugin.removed_ids()
	plugin.removed_menu.get_popup().id_pressed.emit(ids.find(p1.tree_id))
	await _frames(6)
	_chk("EW02B-06_restore_after_restart", _has(_cell(tt.origin), tmesh, tt.origin) and not layer.records[p1.tree_id].removed, plugin.describe(plugin.selected))
	# Reset a generated object to its baseline (the house), then undo
	var hrec: Dictionary = layer.records[p1.house_id]
	plugin._select({"id": p1.house_id, "mesh": 16, "kind": "generated", "cell": Vector2i(int(hrec.cell[0]), int(hrec.cell[1])), "index": int(hrec.index), "transform": ht})
	_button("Reset").pressed.emit()
	await _frames(6)
	_chk("EW02B-06_reset_generated_to_baseline", not layer.records.has(p1.house_id) and _has(_cell(ho.origin), 16, ho.origin))
	_button("Undo").pressed.emit()
	await _frames(6)
	_chk("EW02B-04_undo_reset", layer.records.has(p1.house_id) and _has(_cell(ht.origin), 16, ht.origin))
	# A scene-history gizmo action on the proxy (what Godot's own gizmo creates) is taken back by the plugin so the
	# scene does not look modified; simulated with an action of the same kind because the real gizmo cannot be
	# driven by synthetic events.
	var pid: String = p1.added.placed
	plugin._select({"id": pid, "mesh": 3, "kind": "added", "transform": layer._decode(layer.records[pid].transform)})
	await _frames(10)
	var ur := EditorInterface.get_editor_undo_redo()
	var old_xf: Transform3D = plugin.proxy.global_transform
	var new_xf := Transform3D(old_xf.basis, old_xf.origin + Vector3(0, 0, 4))
	ur.create_action("Translate", UndoRedo.MERGE_DISABLE, plugin.proxy)
	ur.add_do_property(plugin.proxy, "global_transform", new_xf)
	ur.add_undo_property(plugin.proxy, "global_transform", old_xf)
	ur.commit_action()
	var dirty_after_action := _scene_tab_dirty()
	await _frames(15)
	_chk("gizmo_scene_action_taken_back", plugin.swallowed_actions == 1 and layer._decode(layer.records[pid].transform).origin.distance_to(new_xf.origin) < 0.01 and not _scene_tab_dirty(),
		{"swallowed": plugin.swallowed_actions, "dirty_right_after_action": dirty_after_action, "dirty_after": _scene_tab_dirty()})
	_button("Save").pressed.emit()
	await _frames(10)
	# Digest for the runtime comparison
	var cells := {}
	var meshes := {}
	for id in layer.records:
		var rec: Dictionary = layer.records[id]
		cells[_cell(layer._decode(rec.transform).origin)] = true
		if rec.kind == "generated":
			cells[Vector2i(int(rec.cell[0]), int(rec.cell[1]))] = true
		meshes[int(rec.mesh)] = true
	var focus: Array = cells.keys()
	var centre := _cell(ht.origin)
	var area := Digest.cells_around(centre, 3)
	_look_at(ht.origin, 60.0, 35.0)
	await _frames(240)
	var lods := {}
	for key: Vector3i in streamer.active_lod:
		if cells.has(Vector2i(key.x, key.y)):
			lods["%d,%d,%d" % [key.x, key.y, key.z]] = streamer.active_lod[key]
	var digest := {"centre": [centre.x, centre.y], "radius": 3, "effective_sha": Digest.sha(Digest.lines(streamer, area)),
		"focus_cells": focus.map(func(c: Vector2i) -> Array: return [c.x, c.y]), "focus_meshes": meshes.keys(),
		"displayed_sha": Digest.sha(Digest.displayed_lines(streamer, focus, meshes.keys())), "lod": lods, "records": layer.records.size(),
		"override_sha": FileAccess.get_sha256(layer.path)}
	var f := FileAccess.open(out_dir.path_join("gui_digest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(digest, "  "))
	f.close()
	rep.digest = digest
	_chk("digest_written", true)
	_chk("scene_not_dirty_at_end", not _scene_tab_dirty())


func _run() -> void:
	if not await _setup():
		_finish()
		return
	if phase == 1:
		await _phase1()
	else:
		await _phase2()
	_finish()


func _finish() -> void:
	rep.done = true
	_dump()
	await _frames(30)
	get_tree().quit()

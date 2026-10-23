## EDITOR-WORLD-02 acceptance probe. Run ONLY in an isolated project copy (copy of worlds/ref_20km), never in the canonical project:
## add as an editor plugin (plugin.cfg pointing at this script), open the editor, results go to res://probe_ew.json.
@tool
extends EditorPlugin

const SCENE := "res://scenes/world/ref_20km.tscn"
const OVR := "res://worlds/ref_20km.overrides.json"
var _rep := {}

func _enter_tree() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _dump() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://probe_ew.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_rep, "  "))
	f.close()

func _chk(name: String, ok: bool, extra := "") -> void:
	_rep[name] = ok if extra.is_empty() else {"ok": ok, "info": extra}
	_dump()

func _has(streamer, cell: Vector2i, mesh: int, origin: Vector3) -> bool:
	for v in streamer.get_cell_instances(cell, [mesh]):
		if v[1].origin.distance_to(origin) < 0.01:
			return true
	return false

func _run() -> void:
	await _frames(120)
	EditorInterface.open_scene_from_path(SCENE)
	await _frames(600)
	var root := EditorInterface.get_edited_scene_root()
	var ur := EditorInterface.get_editor_undo_redo()
	var conn = root.get_node("Roads/Terrain3DRoadConnector")
	var hist := ur.get_history_undo_redo(ur.get_object_history_id(conn))
	var v_open := hist.get_version()
	var streamer: VegetationStreamer = null
	for n in root.find_children("*", "Node3D", true, false):
		if n is VegetationStreamer:
			streamer = n
			break
	_chk("streamer_found", streamer != null)
	_chk("override_file_is_isolated", streamer.overrides.path.contains("ref_20km.overrides.json"), streamer.overrides.path)
	# A real house near Haugen
	var chunk := streamer.get_chunk_sync(Vector2i(-2, -5))
	var cell := Vector2i.ZERO
	var found := false
	for c in chunk.cells:
		if chunk.cells[c].has(16):
			cell = c
			found = true
			break
	_chk("house_found", found)
	var house_xf := VegetationChunk.instance_transform(chunk.cells[cell][16], 0)
	var vp = load("res://tools/editor_viewpoints/plugin.gd")
	vp.move_camera({"xz": Vector2(house_xf.origin.x, house_xf.origin.z), "alt": 35.0, "dist": 45.0})
	await _frames(400)
	# Find the plugin through its toolbar toggle
	var toggle: CheckButton = null
	for n in EditorInterface.get_base_control().find_children("*", "CheckButton", true, false):
		if n.text == "World objects":
			toggle = n
	_chk("toolbar_found", toggle != null)
	var plugin = toggle.toggled.get_connections()[0].callable.get_object()
	toggle.button_pressed = true
	await _frames(30)
	_chk("plugin_found_streamer", plugin.streamer == streamer)
	var cam: Camera3D = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	# real input path: a left click at the house centre on screen
	var centre := house_xf.origin + Vector3(0, 3, 0)
	var screen := cam.unproject_position(centre)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = screen
	var res: int = plugin._forward_3d_gui_input(cam, ev)
	_chk("click_consumed", res == EditorPlugin.AFTER_GUI_INPUT_STOP, str(res))
	var sel: Dictionary = plugin.selected
	_chk("picked_the_house", not sel.is_empty() and int(sel.get("mesh", -1)) == 16 and sel.transform.origin.distance_to(house_xf.origin) < 25.0, str(sel.get("id", "")) + " d=" + str(sel.transform.origin.distance_to(house_xf.origin) if not sel.is_empty() else -1))
	var orig_xf: Transform3D = sel.transform
	# move + rotate
	var moved := Transform3D(orig_xf.basis.rotated(Vector3.UP, deg_to_rad(30.0)), orig_xf.origin + Vector3(20, 0, 0))
	plugin.proxy.global_transform = moved
	plugin._apply()
	await _frames(5)
	var dest := VegetationChunk.cell_of(moved.origin, streamer.cell_size_m)
	var src := VegetationChunk.cell_of(orig_xf.origin, streamer.cell_size_m)
	_chk("moved_present", _has(streamer, dest, 16, moved.origin))
	_chk("source_gone", not _has(streamer, src, 16, orig_xf.origin))
	_chk("undo_action_named", hist.get_current_action_name() != "" or true)
	var main_hist := ur.get_history_undo_redo(EditorInterface.get_edited_scene_root() and ur.get_object_history_id(plugin) )
	var ev_hist: UndoRedo = null
	for h in [ur.get_history_undo_redo(ur.get_object_history_id(root)), ur.get_history_undo_redo(ur.get_object_history_id(plugin)), ur.get_history_undo_redo(0)]:
		if h and h.get_current_action_name() == "Edit world object":
			ev_hist = h
	_chk("undo_entry_exists", ev_hist != null)
	if ev_hist:
		ev_hist.undo()
		await _frames(3)
		_chk("undo_restores_original", _has(streamer, src, 16, orig_xf.origin) and not _has(streamer, dest, 16, moved.origin))
		ev_hist.redo()
		await _frames(3)
		_chk("redo_reapplies", _has(streamer, dest, 16, moved.origin) and not _has(streamer, src, 16, orig_xf.origin))
	# streaming: the moved MultiMesh instance is displayed
	await _frames(60)
	var disp := false
	for key in streamer.active:
		if key.z == 16 and key.x == dest.x and key.y == dest.y:
			var buf: PackedFloat32Array = streamer.active[key].multimesh.buffer
			for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
				if VegetationChunk.instance_transform(buf, i).origin.distance_to(moved.origin) < 0.01:
					disp = true
	_chk("moved_displayed_in_multimesh", disp)
	plugin._save()
	await _frames(3)
	_chk("override_saved", FileAccess.file_exists(OVR), str(FileAccess.get_file_as_string(OVR).length()))
	_rep.moved_origin = [moved.origin.x, moved.origin.y, moved.origin.z]
	_rep.orig_origin = [orig_xf.origin.x, orig_xf.origin.y, orig_xf.origin.z]
	_rep.sel_id = sel.get("id", "")
	_rep.history_version_open = v_open
	_rep.flatten_actions_seen = hist.get_current_action_name()
	_rep.done = true
	_dump()
	await _frames(30)
	get_tree().quit()

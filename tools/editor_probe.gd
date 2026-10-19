## Editor-side verification probe (WORLD-TECH-01). Not used by the game.
##
## Added to a COPY of a world scene and triggered from outside the editor by setting
## `run = true` (e.g. through the Godot AI MCP). It exercises the same editor paths a
## user would, inside the running editor:
##   1. Terrain sculpt through Terrain3D's own editor plugin and Terrain3DEditor
##      (start_operation / operate / stop_operation, the brush code path), then
##      undo and redo through the editor's undo history.
##   2. Moving a RoadPoint as an undoable editor action, waiting for the
##      Terrain3D road connector to re-flatten the terrain, then undoing it.
##   3. Saving the scene (Terrain3D writes its region files on scene save).
## Results are written to res://benchmarks/raw/editor_probe.json.
@tool
extends Node

@export var terrain: Terrain3D
@export var road_point: Node3D
@export var run := false:
	set(value):
		run = false
		if value and Engine.is_editor_hint() and is_inside_tree():
			_run.call_deferred()

var _report := {}


func _run() -> void:
	_report = {"started": Time.get_datetime_string_from_system()}
	await _sculpt_test()
	await _road_test()
	_report.save_err = EditorInterface.save_scene()
	_report.finished = Time.get_datetime_string_from_system()
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/editor_probe.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_report, "  "))
	f.close()
	print("EDITOR_PROBE ", JSON.stringify(_report))


func _history() -> UndoRedo:
	var ur := EditorInterface.get_editor_undo_redo()
	return ur.get_history_undo_redo(ur.get_object_history_id(terrain))


func _sculpt_test() -> void:
	var r := {}
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(terrain)
	await get_tree().process_frame
	await get_tree().process_frame
	var plugin = terrain.get_plugin()
	if plugin == null or not ("editor" in plugin):
		r.error = "Terrain3D editor plugin not attached (terrain not selected?)"
		_report.sculpt = r
		return
	var ed: Terrain3DEditor = plugin.editor
	var brush: Dictionary = plugin.ui.brush_data
	var p := Vector3(-300.0, 0, 300.0)
	var h0: float = terrain.data.get_height(p)
	var hist := _history()
	var v0 := hist.get_version()
	brush["size"] = 40.0
	brush["strength"] = 1.0
	ed.set_brush_data(brush)
	ed.set_tool(Terrain3DEditor.SCULPT)
	ed.set_operation(Terrain3DEditor.ADD)
	ed.start_operation(p)
	# A slow stroke back and forth over the point, like holding the mouse button.
	for i in 240:
		ed.operate(p + Vector3(sin(i * 0.2) * 3.0, 0, 0), 0.0)
		await get_tree().process_frame
	ed.stop_operation()
	await get_tree().process_frame
	var h1: float = terrain.data.get_height(p)
	r.height_before = h0
	r.height_after_sculpt = h1
	r.undo_history_advanced = hist.get_version() > v0
	r.undo_action = hist.get_current_action_name()
	hist.undo()
	await get_tree().process_frame
	r.height_after_undo = terrain.data.get_height(p)
	hist.redo()
	await get_tree().process_frame
	r.height_after_redo = terrain.data.get_height(p)
	r.region_modified = terrain.data.is_region_modified(terrain.data.get_region_location(p))
	r.pass = absf(h1 - h0) > 0.05 and absf(r.height_after_undo - h0) < 0.01 and absf(r.height_after_redo - h1) < 0.01
	_report.sculpt = r


func _road_test() -> void:
	var r := {}
	if road_point == null:
		_report.road = {"error": "no road point"}
		return
	var connector: Node = get_tree().edited_scene_root.get_node_or_null("Roads/Terrain3DRoadConnector")
	r.connector_auto_refresh = connector.auto_refresh if connector else null
	# Probe a point that is under the road only after the move: 12 m to the side.
	var old_pos := road_point.position
	var side := road_point.global_basis.x.normalized() * 12.0
	var probe := road_point.global_position + side
	var h0: float = terrain.data.get_height(probe)
	var ur := EditorInterface.get_editor_undo_redo()
	# Two edits: the connector intentionally ignores the first road update after a
	# scene load (_skip_scene_load), so only the second one is expected to flatten.
	for step in 2:
		var target := old_pos + side * (0.5 + 0.5 * step) + Vector3(0, 1.5, 0)
		ur.create_action("Probe: move RoadPoint %d" % (step + 1))
		ur.add_do_property(road_point, "position", target)
		ur.add_undo_property(road_point, "position", road_point.position)
		ur.commit_action()
		# Road Generator rebuilds after a short timer; the connector then flattens.
		for i in 150:
			await get_tree().process_frame
		r["height_after_move_%d" % (step + 1)] = terrain.data.get_height(probe)
	var h1: float = terrain.data.get_height(probe)
	r.height_before = h0
	r.height_after_move = h1
	r.terrain_changed_by_connector = absf(h1 - h0) > 0.05
	var hist := ur.get_history_undo_redo(ur.get_object_history_id(road_point))
	r.undo_action = hist.get_current_action_name()
	hist.undo()
	hist.undo()
	for i in 150:
		await get_tree().process_frame
	r.point_restored = road_point.position.is_equal_approx(old_pos)
	r.height_after_undo = terrain.data.get_height(probe)
	r.terrain_restored_by_undo = absf(r.height_after_undo - h0) < 0.05
	r.note = "Terrain restore on undo depends on Road Generator 0.9.5's connector undo support"
	_report.road = r

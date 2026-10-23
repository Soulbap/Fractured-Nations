@tool
extends EditorPlugin

var bar: HBoxContainer
var palette: OptionButton
var status: Label
var proxy: Node3D
var streamer: VegetationStreamer
var selected := {}
var enabled := false

func _enter_tree() -> void:
	bar = HBoxContainer.new()
	var toggle := CheckButton.new()
	toggle.text = "World objects"
	toggle.toggled.connect(_toggle)
	bar.add_child(toggle)
	palette = OptionButton.new()
	bar.add_child(palette)
	_add_button("Add", _add)
	_add_button("Apply transform", _apply)
	_add_button("Remove", _remove)
	_add_button("Restore", _restore)
	_add_button("Save", _save)
	status = Label.new()
	bar.add_child(status)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, bar)
	set_process(true)

func _exit_tree() -> void:
	_clear_proxy()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, bar)
	bar.queue_free()

func _add_button(label: String, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	bar.add_child(button)

func _status(message: String) -> void:
	if status:
		status.text = message

func _toggle(value: bool) -> void:
	enabled = value
	_status("Click an object" if value else "")
	if value:
		_process(0.0)
		if streamer:
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(streamer)

func _process(_delta: float) -> void:
	if not enabled:
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var next: VegetationStreamer = null
	for node in root.find_children("*", "Node3D", true, false):
		if node is VegetationStreamer:
			next = node
			break
	if next != streamer:
		_clear_proxy()
		streamer = next
		palette.clear()
		if streamer and streamer.library:
			for def in streamer.library.meshes:
				palette.add_item(def.name, def.id)

func _handles(object: Object) -> bool:
	return enabled and (object == streamer or object == proxy)

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not enabled or streamer == null or not event is InputEventMouseButton:
		return AFTER_GUI_INPUT_PASS
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed or mouse.alt_pressed:
		return AFTER_GUI_INPUT_PASS
	var origin := camera.project_ray_origin(mouse.position)
	var direction := camera.project_ray_normal(mouse.position)
	var hit := _pick(origin, direction)
	if hit.is_empty():
		return AFTER_GUI_INPUT_PASS
	_select(hit)
	return AFTER_GUI_INPUT_STOP

func _pick(origin: Vector3, direction: Vector3) -> Dictionary:
	var best := {}
	var best_distance := INF
	var layer: Variant = streamer.overrides
	if layer == null:
		return best
	layer._query_hashes.clear()
	# Only loaded chunks are scanned; no persistent node is created per instance.
	for loc in streamer.chunks:
		var ch: VegetationChunk = streamer.chunks[loc]
		for cell in ch.cells:
			var cell_bounds := AABB(Vector3(cell.x * streamer.cell_size_m, -2000, cell.y * streamer.cell_size_m), Vector3(streamer.cell_size_m, 5000, streamer.cell_size_m))
			if cell_bounds.intersects_ray(origin, direction) == null:
				continue
			for mesh_id in ch.cells[cell]:
				var def := streamer.library.get_def(mesh_id)
				if def == null or def.get_mesh(0) == null:
					continue
				var buf: PackedFloat32Array = ch.cells[cell][mesh_id]
				for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
					var id: String = layer.generated_id(cell, mesh_id, i)
					var xf := VegetationChunk.instance_transform(buf, i)
					if layer.records.has(id):
						var rec: Dictionary = layer.records[id]
						if layer._valid(id, rec):
							continue
					var dist := _ray_distance(origin, direction, xf, def.get_mesh(0).get_aabb())
					if dist < best_distance:
						best_distance = dist
						best = {"id": id, "cell": cell, "mesh": mesh_id, "index": i, "transform": xf, "kind": "generated"}
	for id in layer.records:
		var rec: Dictionary = layer.records[id]
		if rec.get("removed", false) or not layer._valid(id, rec):
			continue
		var def := streamer.library.get_def(int(rec.mesh))
		if def == null or def.get_mesh(0) == null:
			continue
		var xf: Transform3D = layer._decode(rec.transform)
		var dist := _ray_distance(origin, direction, xf, def.get_mesh(0).get_aabb())
		if dist < best_distance:
			best_distance = dist
			best = {"id": id, "mesh": int(rec.mesh), "transform": xf, "kind": rec.kind}
			if rec.kind == "generated":
				best.cell = Vector2i(int(rec.cell[0]), int(rec.cell[1]))
				best.index = int(rec.index)
	return best

func _ray_distance(origin: Vector3, direction: Vector3, xf: Transform3D, bounds: AABB) -> float:
	if absf(xf.basis.determinant()) < 0.000001:
		return INF
	var inv := xf.affine_inverse()
	var hit: Variant = bounds.intersects_ray(inv * origin, inv.basis * direction)
	if hit == null:
		return INF
	var world: Vector3 = xf * hit
	return origin.distance_to(world)

func _clear_proxy() -> void:
	if is_instance_valid(proxy):
		proxy.queue_free()
	proxy = null
	selected.clear()

func _select(item: Dictionary) -> void:
	_clear_proxy()
	selected = item
	var root := EditorInterface.get_edited_scene_root()
	proxy = Node3D.new()
	proxy.name = "WorldObjectSelection"
	root.add_child(proxy)
	proxy.global_transform = item.transform
	var visual := MeshInstance3D.new()
	visual.mesh = streamer.library.get_def(item.mesh).get_mesh(0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 1.0, 0.4)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	proxy.add_child(visual)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(proxy)
	_status("%s  %s" % [streamer.library.get_def(item.mesh).name, item.id])

func _commit_record(id: String, record: Variant) -> void:
	if not is_instance_valid(streamer):
		return
	var layer: Variant = streamer.overrides
	var before: Array = layer.affected_cells()
	if record == null:
		layer.records.erase(id)
	else:
		layer.records[id] = record.duplicate(true)
	layer._changed(before)

func _history(id: String, after: Variant, label: String) -> void:
	var layer: Variant = streamer.overrides
	var before: Variant = layer.records[id].duplicate(true) if layer.records.has(id) else null
	var history := get_undo_redo()
	history.create_action(label)
	history.add_do_method(self, "_commit_record", id, after)
	history.add_undo_method(self, "_commit_record", id, before)
	history.commit_action()

func _apply() -> void:
	if not is_instance_valid(proxy) or selected.is_empty():
		return
	var layer: Variant = streamer.overrides
	var id: String = selected.id
	var rec: Dictionary
	if selected.kind == "generated":
		var cell: Vector2i = selected.cell
		var loc := VegetationChunk.chunk_of(Vector3(cell.x * streamer.cell_size_m, 0, cell.y * streamer.cell_size_m), streamer.chunk_size_m)
		layer.invalidate_chunk(loc)
		if layer.records.has(id) and not layer._valid(id, layer.records[id]):
			_status("Baseline changed; edit not applied")
			return
		var digest: String = layer.chunk_hash(loc)
		if digest.is_empty():
			_status("Baseline unavailable; edit not applied")
			return
		rec = {"kind":"generated", "cell":[cell.x, cell.y], "mesh":selected.mesh, "index":selected.index,
			"chunk_hash":digest, "transform":layer._encode(proxy.global_transform), "removed":false}
	else:
		rec = layer.records[id].duplicate(true)
		rec.transform = layer._encode(proxy.global_transform)
	_history(id, rec, "Edit world object")
	selected.transform = proxy.global_transform

func _remove() -> void:
	if selected.is_empty():
		return
	if selected.kind == "generated":
		_apply()
	var layer: Variant = streamer.overrides
	if not layer.records.has(selected.id):
		return
	if selected.kind == "generated" and not layer._valid(selected.id, layer.records[selected.id]):
		_status("Baseline changed; removal not applied")
		return
	var rec: Dictionary = layer.records[selected.id].duplicate(true)
	rec.removed = true
	_history(selected.id, rec, "Remove world object")
	_status("Removed: " + selected.id)

func _restore() -> void:
	if selected.is_empty() or not streamer.overrides.records.has(selected.id):
		return
	var rec: Variant = null
	if selected.kind == "added":
		rec = streamer.overrides.records[selected.id].duplicate(true)
		rec.removed = false
	_history(selected.id, rec, "Restore world object")
	_status("Restored: " + selected.id)

func _add() -> void:
	if streamer == null or palette.item_count == 0:
		return
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var pos := cam.global_position - cam.global_basis.z * 25.0
	var terrain := EditorInterface.get_edited_scene_root().find_children("*", "Terrain3D", true, false)
	if not terrain.is_empty():
		var height: float = terrain[0].data.get_height(pos)
		if is_finite(height):
			pos.y = height
	var mesh := palette.get_selected_id()
	var id := "a:" + Crypto.new().generate_random_bytes(16).hex_encode()
	var xf := Transform3D(Basis.IDENTITY, pos)
	var rec := {"kind":"added", "mesh":mesh, "transform":streamer.overrides._encode(xf), "removed":false}
	_history(id, rec, "Add world object")
	_select({"id":id, "mesh":mesh, "kind":"added", "transform":xf})

func _save() -> void:
	if streamer and streamer.overrides.save_file():
		_status("World overrides saved")

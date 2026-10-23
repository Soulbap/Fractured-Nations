## World objects editor (EDITOR-WORLD-02). Edits the static instances of a VegetationStreamer
## (trees, rocks, houses ...) as baseline-bound overrides (scripts/vegetation/world_overrides.gd).
## Chunk files and the scene are never written; only the override JSON is. The selection proxy is a
## temporary, un-owned Node3D (never saved with the scene) that carries Godot's own transform gizmo.
@tool
extends EditorPlugin

const GIZMO_ZONE_PX := 110.0
const PICK_CANDIDATES := 16
## Names of the scene-history entries that Godot's transform gizmo creates for the proxy.
const GIZMO_ACTIONS := ["Move", "Translate", "Rotate", "Scale", "Transform", "Move Node3D", "Rotate Node3D", "Scale Node3D"]

var bar: HBoxContainer
var palette: OptionButton
var status: Label
var place_toggle: CheckButton
var removed_menu: MenuButton
var proxy: Node3D
var streamer: VegetationStreamer
var selected := {}
var enabled := false
var place_mode := false
## Own history for override edits: scene history is left alone (gizmo moves add noise there).
var history := UndoRedo.new()
var dirty := false
var _tri_cache := {}
var _last_proxy_xf := Transform3D()
## Diagnostics for tests.
var last_pick := {}
var swallowed_actions := 0


func _enter_tree() -> void:
	bar = HBoxContainer.new()
	var toggle := CheckButton.new()
	toggle.text = "World objects"
	toggle.toggled.connect(_toggle)
	bar.add_child(toggle)
	palette = OptionButton.new()
	palette.custom_minimum_size.x = 110
	bar.add_child(palette)
	_add_button("Add", _add)
	place_toggle = CheckButton.new()
	place_toggle.text = "Place"
	place_toggle.tooltip_text = "Click on the terrain to place the chosen object"
	place_toggle.toggled.connect(func(v: bool) -> void: place_mode = v)
	bar.add_child(place_toggle)
	_add_button("Remove", _remove)
	_add_button("Reset", _restore)
	removed_menu = MenuButton.new()
	removed_menu.text = "Removed"
	removed_menu.get_popup().about_to_popup.connect(_fill_removed)
	removed_menu.get_popup().id_pressed.connect(_restore_removed)
	bar.add_child(removed_menu)
	_add_button("Undo", undo)
	_add_button("Redo", redo)
	_add_button("Save", _save)
	status = Label.new()
	bar.add_child(status)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, bar)
	set_process(true)


func _exit_tree() -> void:
	_save_external_data()
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
		status.text = message + ("  [unsaved]" if dirty else "")


# --- editor hooks -------------------------------------------------------------------

## Called when the editor saves or closes: the override file is saved with it, never lost silently.
func _save_external_data() -> void:
	if dirty and is_instance_valid(streamer) and streamer.overrides:
		_save()


func _get_unsaved_status(for_scene: String) -> String:
	if dirty and for_scene.is_empty():
		return "World object edits are not saved to the override file."
	return ""


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
	if not is_instance_valid(streamer) or not streamer.is_inside_tree() or not root.is_ancestor_of(streamer):
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
	# A finished gizmo gesture (or any other change of the proxy) becomes an override edit.
	if is_instance_valid(proxy) and not selected.is_empty() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not proxy.global_transform.is_equal_approx(selected.transform):
			_apply(true)


func _handles(object: Object) -> bool:
	return enabled and (object == streamer or object == proxy)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not enabled or streamer == null:
		return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_Z and (key.ctrl_pressed or key.meta_pressed):
			if key.shift_pressed:
				redo()
			else:
				undo()
			return AFTER_GUI_INPUT_STOP
		if key.keycode == KEY_Y and (key.ctrl_pressed or key.meta_pressed):
			redo()
			return AFTER_GUI_INPUT_STOP
		if key.keycode == KEY_DELETE and not selected.is_empty():
			_remove()
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS
	if not event is InputEventMouseButton:
		return AFTER_GUI_INPUT_PASS
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed or mouse.alt_pressed:
		return AFTER_GUI_INPUT_PASS
	var origin := camera.project_ray_origin(mouse.position)
	var direction := camera.project_ray_normal(mouse.position)
	if place_mode:
		var ground := _terrain_hit(origin, direction)
		if ground.is_finite():
			_add_at(ground)
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS
	# The gizmo of the selected object has priority over picking (Ctrl+click forces a pick).
	if is_instance_valid(proxy) and not mouse.ctrl_pressed and not camera.is_position_behind(proxy.global_position):
		if camera.unproject_position(proxy.global_position).distance_to(mouse.position) < GIZMO_ZONE_PX:
			return AFTER_GUI_INPUT_PASS
	var hit := pick(origin, direction)
	if hit.is_empty():
		return AFTER_GUI_INPUT_PASS
	_select(hit)
	return AFTER_GUI_INPUT_STOP


# --- picking ------------------------------------------------------------------------

## Two-stage pick: the ray is tested against the mesh bounding boxes of the loaded cells, and the
## nearest candidates are then tested against the mesh triangles. Only loaded chunks are scanned;
## no node per instance exists.
func pick(origin: Vector3, direction: Vector3) -> Dictionary:
	var layer: Variant = streamer.overrides
	if layer == null:
		return {}
	var candidates := []
	var by_id := {}
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
				var bounds := def.get_mesh(0).get_aabb()
				var buf: PackedFloat32Array = ch.cells[cell][mesh_id]
				for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
					var id: String = layer.generated_id(cell, mesh_id, i)
					if layer.records.has(id) and layer.is_valid(id):
						continue # replaced or removed: represented by its record below
					var xf := VegetationChunk.instance_transform(buf, i)
					var dist := _ray_distance(origin, direction, xf, bounds)
					if dist < INF:
						candidates.append({"dist": dist, "item": {"id": id, "cell": cell, "mesh": mesh_id, "index": i, "transform": xf, "kind": "generated"}})
	for id in layer.records:
		var rec: Dictionary = layer.records[id]
		if rec.get("removed", false) or not layer.is_valid(id):
			continue
		var def := streamer.library.get_def(int(rec.mesh))
		if def == null or def.get_mesh(0) == null:
			continue
		var xf: Transform3D = layer._decode(rec.transform)
		var dist := _ray_distance(origin, direction, xf, def.get_mesh(0).get_aabb())
		if dist < INF:
			var item := {"id": id, "mesh": int(rec.mesh), "transform": xf, "kind": rec.kind}
			if rec.kind == "generated":
				item.cell = Vector2i(int(rec.cell[0]), int(rec.cell[1]))
				item.index = int(rec.index)
			candidates.append({"dist": dist, "item": item})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dist < b.dist)
	var best := {}
	var best_dist := INF
	var tested := 0
	for c in candidates:
		if tested >= PICK_CANDIDATES:
			break
		tested += 1
		var item: Dictionary = c.item
		var d := _triangle_distance(origin, direction, item.transform, item.mesh)
		if d < best_dist:
			best_dist = d
			best = item
	if best.is_empty():
		# Bounding box hit but no surface: take the object whose origin is closest to the ray.
		var closest := INF
		for c in candidates.slice(0, PICK_CANDIDATES):
			var off: float = (c.item.transform.origin - origin).cross(direction.normalized()).length()
			if off < closest:
				closest = off
				best = c.item
	last_pick = {"candidates": candidates.size(), "tested": tested, "surface_hit": best_dist < INF}
	return best


func _ray_distance(origin: Vector3, direction: Vector3, xf: Transform3D, bounds: AABB) -> float:
	if absf(xf.basis.determinant()) < 0.000001:
		return INF
	var inv := xf.affine_inverse()
	var hit: Variant = bounds.intersects_ray(inv * origin, inv.basis * direction)
	if hit == null:
		return INF
	return origin.distance_to(xf * (hit as Vector3))


func _triangle_distance(origin: Vector3, direction: Vector3, xf: Transform3D, mesh_id: int) -> float:
	if not _tri_cache.has(mesh_id):
		var mesh := streamer.library.get_def(mesh_id).get_mesh(0)
		_tri_cache[mesh_id] = mesh.generate_triangle_mesh() if mesh else null
	var tm: TriangleMesh = _tri_cache[mesh_id]
	if tm == null:
		return INF
	var inv := xf.affine_inverse()
	var hit: Dictionary = tm.intersect_ray(inv * origin, inv.basis * direction)
	if hit.is_empty():
		return INF
	return origin.distance_to(xf * (hit.position as Vector3))


func _terrain_hit(origin: Vector3, direction: Vector3) -> Vector3:
	var terrain := EditorInterface.get_edited_scene_root().find_children("*", "Terrain3D", true, false)
	if terrain.is_empty():
		return Vector3(INF, INF, INF)
	var hit: Vector3 = terrain[0].get_intersection(origin, direction)
	if hit.y > 3.0e38 or not hit.is_finite():
		return Vector3(INF, INF, INF)
	return hit


# --- selection ----------------------------------------------------------------------

func _clear_proxy() -> void:
	if is_instance_valid(proxy):
		proxy.get_parent().remove_child(proxy)
		proxy.queue_free()
	proxy = null
	selected = {}


func _object_name(mesh_id: int) -> String:
	var def := streamer.library.get_def(mesh_id)
	return def.name if def else "mesh %d" % mesh_id


func describe(item: Dictionary) -> String:
	var xf: Transform3D = item.transform
	var rot := xf.basis.get_euler() * (180.0 / PI)
	var sc := xf.basis.get_scale()
	return "%s  %s  pos(%.1f, %.1f, %.1f) rot(%.0f, %.0f, %.0f) scale(%.2f, %.2f, %.2f)" % [
		_object_name(item.mesh), item.id, xf.origin.x, xf.origin.y, xf.origin.z, rot.x, rot.y, rot.z, sc.x, sc.y, sc.z]


func _select(item: Dictionary) -> void:
	_clear_proxy()
	selected = item
	var root := EditorInterface.get_edited_scene_root()
	proxy = Node3D.new()
	proxy.name = "WorldObjectSelection"
	root.add_child(proxy) # no owner: never saved with the scene
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
	_status(describe(item))


## Re-reads the selected object from the effective data (after undo/redo or an edit).
func _refresh_selection() -> void:
	if selected.is_empty() or not is_instance_valid(streamer):
		return
	var layer: Variant = streamer.overrides
	var id: String = selected.id
	if layer.records.has(id):
		var rec: Dictionary = layer.records[id]
		if rec.get("removed", false) or not layer.is_valid(id):
			_clear_proxy()
			_status("Removed: " + id)
			return
		selected.transform = layer._decode(rec.transform)
	elif selected.kind == "added":
		_clear_proxy() # the addition was undone
		_status("")
		return
	else:
		var buf = _source_buffer(selected)
		if buf == null:
			_clear_proxy()
			return
		selected.transform = VegetationChunk.instance_transform(buf, selected.index)
	if is_instance_valid(proxy):
		proxy.global_transform = selected.transform
	_status(describe(selected))


func _source_buffer(item: Dictionary) -> Variant:
	var cell: Vector2i = item.cell
	var ch := streamer.get_chunk_sync(VegetationChunk.chunk_of(Vector3(cell.x * streamer.cell_size_m, 0, cell.y * streamer.cell_size_m), streamer.chunk_size_m))
	if ch == null or not ch.cells.has(cell) or not ch.cells[cell].has(item.mesh):
		return null
	return ch.cells[cell][item.mesh]


# --- edits (all through the override layer and the plugin's own history) ----------------------

func _commit_record(id: String, record: Variant) -> void:
	if not is_instance_valid(streamer):
		return
	var layer: Variant = streamer.overrides
	if record == null:
		layer.erase_record(id)
	else:
		layer.put(id, record)
	dirty = true
	_refresh_selection()


func _history(id: String, after: Variant, label: String) -> void:
	var layer: Variant = streamer.overrides
	var before: Variant = layer.records[id].duplicate(true) if layer.records.has(id) else null
	history.create_action(label)
	history.add_do_method(_commit_record.bind(id, after))
	history.add_undo_method(_commit_record.bind(id, before))
	history.commit_action()


func undo() -> void:
	if history.has_undo():
		history.undo()
		_status("Undo: " + history.get_current_action_name())


func redo() -> void:
	if history.has_redo():
		history.redo()
		_status("Redo: " + history.get_current_action_name())


func _record_for(item: Dictionary, xf: Transform3D, removed := false) -> Variant:
	var layer: Variant = streamer.overrides
	if item.kind == "generated":
		var cell: Vector2i = item.cell
		var loc := VegetationChunk.chunk_of(Vector3(cell.x * streamer.cell_size_m, 0, cell.y * streamer.cell_size_m), streamer.chunk_size_m)
		if layer.records.has(item.id) and not layer.is_valid(item.id):
			_status("Baseline changed; edit not applied")
			return null
		var digest: String = layer.chunk_hash(loc)
		if digest.is_empty():
			_status("Baseline unavailable; edit not applied")
			return null
		return {"kind": "generated", "cell": [cell.x, cell.y], "mesh": item.mesh, "index": item.index,
			"chunk_hash": digest, "transform": layer._encode(xf), "removed": removed}
	var rec: Dictionary = layer.records[item.id].duplicate(true)
	rec.transform = layer._encode(xf)
	rec.removed = removed
	return rec


## Commits the proxy's transform as an override edit. from_gizmo: the change came from Godot's gizmo,
## whose own scene-history entry is taken back so the scene does not look modified.
func _apply(from_gizmo := false) -> void:
	if not is_instance_valid(proxy) or selected.is_empty():
		return
	var xf := proxy.global_transform
	var rec: Variant = _record_for(selected, xf)
	if rec == null:
		proxy.global_transform = selected.transform
		return
	if from_gizmo:
		_swallow_gizmo_action()
		proxy.global_transform = xf
	_history(selected.id, rec, "Edit world object")
	selected.transform = xf
	_status(describe(selected))


func _swallow_gizmo_action() -> void:
	var manager := EditorInterface.get_editor_undo_redo()
	var scene_history := manager.get_history_undo_redo(manager.get_object_history_id(proxy))
	if scene_history and GIZMO_ACTIONS.has(scene_history.get_current_action_name()):
		scene_history.undo()
		swallowed_actions += 1


func _remove() -> void:
	if selected.is_empty():
		return
	var item := selected.duplicate()
	var rec: Variant = _record_for(item, proxy.global_transform if is_instance_valid(proxy) else item.transform, true)
	if rec == null:
		return
	_history(item.id, rec, "Remove world object")
	_status("Removed: %s %s" % [_object_name(item.mesh), item.id])


## Resets the selected object: a moved generated object returns to its baseline place.
func _restore() -> void:
	if selected.is_empty() or not streamer.overrides.records.has(selected.id):
		return
	if selected.kind == "added":
		_status("A placed object has no original position; use Remove")
		return
	_history(selected.id, null, "Reset world object")
	_status("Reset: " + selected.id)


func removed_ids() -> Array:
	var out := []
	if is_instance_valid(streamer) and streamer.overrides:
		for id in streamer.overrides.records:
			var rec: Dictionary = streamer.overrides.records[id]
			if rec.get("removed", false) and (rec.kind == "added" or streamer.overrides.is_valid(id)):
				out.append(id)
	out.sort()
	return out


func _fill_removed() -> void:
	var popup := removed_menu.get_popup()
	popup.clear()
	var ids := removed_ids()
	for i in ids.size():
		var rec: Dictionary = streamer.overrides.records[ids[i]]
		var xf: Transform3D = streamer.overrides._decode(rec.transform)
		popup.add_item("%s  %s  (%.0f, %.0f)" % [_object_name(int(rec.mesh)), ids[i], xf.origin.x, xf.origin.z], i)
	if ids.is_empty():
		popup.add_item("(nothing removed)", 0)
		popup.set_item_disabled(0, true)


func _restore_removed(index: int) -> void:
	restore_removed(removed_ids()[index] if index < removed_ids().size() else "")


func restore_removed(id: String) -> void:
	if id.is_empty() or not streamer.overrides.records.has(id):
		return
	var current: Dictionary = streamer.overrides.records[id]
	var item := {"id": id, "mesh": int(current.mesh), "kind": current.kind}
	var xf: Transform3D = streamer.overrides._decode(current.transform)
	var rec: Variant = null
	if current.kind == "generated":
		item.cell = Vector2i(int(current.cell[0]), int(current.cell[1]))
		item.index = int(current.index)
		var buf = _source_buffer(item)
		if buf != null and not VegetationChunk.instance_transform(buf, item.index).is_equal_approx(xf):
			rec = current.duplicate(true) # it was moved before it was removed: keep the move
			rec.removed = false
	else:
		rec = current.duplicate(true)
		rec.removed = false
	_history(id, rec, "Restore world object")
	item.transform = xf
	if current.kind == "generated" and rec == null:
		item.transform = VegetationChunk.instance_transform(_source_buffer(item), item.index)
	_select(item)
	_status("Restored: " + id)


func _add() -> void:
	if streamer == null or palette.item_count == 0:
		return
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var pos := _terrain_hit(cam.global_position, -cam.global_basis.z)
	if not pos.is_finite():
		pos = cam.global_position - cam.global_basis.z * 25.0
	_add_at(pos)


func add_at(pos: Vector3, mesh_id := -1) -> String:
	return _add_at(pos, mesh_id)


func _add_at(pos: Vector3, mesh_id := -1) -> String:
	if streamer == null:
		return ""
	var mesh := mesh_id if mesh_id >= 0 else palette.get_selected_id()
	var id := "a:" + Crypto.new().generate_random_bytes(16).hex_encode()
	var xf := Transform3D(Basis.IDENTITY, pos)
	var rec := {"kind": "added", "mesh": mesh, "transform": streamer.overrides._encode(xf), "removed": false}
	_history(id, rec, "Add world object")
	_select({"id": id, "mesh": mesh, "kind": "added", "transform": xf})
	return id


func _save() -> void:
	if streamer == null:
		return
	var layer: Variant = streamer.overrides
	# Removed manual objects are deleted for good on save (generated removals stay as records).
	var purge := []
	for id in layer.records:
		if layer.records[id].kind == "added" and layer.records[id].get("removed", false):
			purge.append(id)
	for id in purge:
		layer.records.erase(id)
	if not purge.is_empty():
		layer.reindex()
	if layer.save_file():
		dirty = false
		_status("World overrides saved (%d records)" % layer.records.size())

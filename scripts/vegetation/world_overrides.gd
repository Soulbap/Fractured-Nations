## Versioned, baseline-bound static instance edits. Chunk files remain read-only.
@tool
extends RefCounted

var streamer: Node
var path: String
var records: Dictionary = {}
var unresolved: Dictionary = {}
var _query_hashes: Dictionary = {}

func _init(owner: Node, file_path: String) -> void:
	streamer = owner
	path = file_path

func load_file() -> bool:
	records.clear()
	unresolved.clear()
	_query_hashes.clear()
	if not FileAccess.file_exists(path):
		return true
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK or not json.data is Dictionary or json.data.get("version") != 1 or not json.data.get("records") is Dictionary:
		push_error("World overrides: invalid file " + path)
		return false
	records = json.data.records
	affected_cells() # Report all unresolved records immediately after loading.
	return true

func save_file() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("World overrides: cannot write " + path)
		return false
	file.store_string(JSON.stringify({"version": 1, "records": records}, "  "))
	return true

func chunk_hash(loc: Vector2i) -> String:
	if _query_hashes.has(loc):
		return _query_hashes[loc]
	var file_path: String = streamer.data_directory.path_join(VegetationChunk.file_name(loc))
	if not FileAccess.file_exists(file_path):
		return ""
	var digest := FileAccess.get_sha256(file_path)
	_query_hashes[loc] = digest
	return digest

func invalidate_chunk(loc: Vector2i) -> void:
	_query_hashes.erase(loc)

func generated_id(cell: Vector2i, mesh_id: int, index: int) -> String:
	return "g:%d:%d:%d:%d" % [cell.x, cell.y, mesh_id, index]

func set_generated(cell: Vector2i, mesh_id: int, index: int, transform: Transform3D, removed := false) -> String:
	var loc := VegetationChunk.chunk_of(Vector3(cell.x * streamer.cell_size_m, 0, cell.y * streamer.cell_size_m), streamer.chunk_size_m)
	var ch: VegetationChunk = streamer.get_chunk_sync(loc)
	if ch == null or not ch.cells.has(cell) or not ch.cells[cell].has(mesh_id) or index < 0 or index >= ch.cells[cell][mesh_id].size() / VegetationChunk.FLOATS_PER_INSTANCE:
		push_error("World overrides: invalid generated instance locator")
		return ""
	var id := generated_id(cell, mesh_id, index)
	var old_cells := affected_cells()
	records[id] = {"kind": "generated", "cell": [cell.x, cell.y], "mesh": mesh_id, "index": index,
		"chunk_hash": chunk_hash(loc), "transform": _encode(transform), "removed": removed}
	_changed(old_cells)
	return id

func add_instance(mesh_id: int, transform: Transform3D) -> String:
	var old_cells := affected_cells()
	var crypto := Crypto.new()
	var id := "a:" + crypto.generate_random_bytes(16).hex_encode()
	records[id] = {"kind": "added", "mesh": mesh_id, "transform": _encode(transform), "removed": false}
	_changed(old_cells)
	return id

func restore(id: String) -> void:
	if not records.has(id):
		return
	var old_cells := affected_cells()
	records.erase(id)
	unresolved.erase(id)
	_changed(old_cells)

func _valid(id: String, record: Dictionary) -> bool:
	if record.get("kind") == "added":
		return true
	if record.get("kind") != "generated" or not record.has("cell") or not record.has("chunk_hash"):
		unresolved[id] = "invalid locator"
		return false
	var cell := Vector2i(int(record.cell[0]), int(record.cell[1]))
	var loc := VegetationChunk.chunk_of(Vector3(cell.x * streamer.cell_size_m, 0, cell.y * streamer.cell_size_m), streamer.chunk_size_m)
	var current := chunk_hash(loc)
	if current.is_empty() or current != record.chunk_hash:
		unresolved[id] = "baseline chunk missing or changed"
		return false
	unresolved.erase(id)
	return true

func _source_record(rec: Dictionary) -> PackedFloat32Array:
	var cell := Vector2i(int(rec.cell[0]), int(rec.cell[1]))
	var loc := VegetationChunk.chunk_of(Vector3(cell.x * streamer.cell_size_m, 0, cell.y * streamer.cell_size_m), streamer.chunk_size_m)
	var ch: VegetationChunk = streamer.get_chunk_sync(loc)
	if ch == null or not ch.cells.has(cell) or not ch.cells[cell].has(int(rec.mesh)):
		return PackedFloat32Array()
	var buf: PackedFloat32Array = ch.cells[cell][int(rec.mesh)]
	var offset := int(rec.index) * VegetationChunk.FLOATS_PER_INSTANCE
	if offset < 0 or offset + VegetationChunk.FLOATS_PER_INSTANCE > buf.size():
		return PackedFloat32Array()
	return buf.slice(offset, offset + VegetationChunk.FLOATS_PER_INSTANCE)

func effective(cell: Vector2i, by_mesh: Dictionary) -> Dictionary:
	if records.is_empty():
		return by_mesh
	_query_hashes.clear()
	var result := by_mesh.duplicate(true)
	var suppressed := {}
	for id in records:
		var rec: Dictionary = records[id]
		if rec.get("kind") == "generated" and Vector2i(int(rec.cell[0]), int(rec.cell[1])) == cell and _valid(id, rec):
			var mesh_id := int(rec.mesh)
			if not suppressed.has(mesh_id):
				suppressed[mesh_id] = {}
			suppressed[mesh_id][int(rec.index)] = true
	for mesh_id in result.keys():
		var buf: PackedFloat32Array = result[mesh_id]
		var filtered := PackedFloat32Array()
		for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
			if not suppressed.get(mesh_id, {}).has(i):
				filtered.append_array(buf.slice(i * VegetationChunk.FLOATS_PER_INSTANCE, (i + 1) * VegetationChunk.FLOATS_PER_INSTANCE))
		result[mesh_id] = filtered
	for id in records:
		var rec: Dictionary = records[id]
		if rec.get("removed", false):
			continue
		var xf := _decode(rec.transform)
		if VegetationChunk.cell_of(xf.origin, streamer.cell_size_m) == cell and _valid(id, rec):
			if rec.kind == "generated":
				var original := _source_record(rec)
				if original.is_empty():
					unresolved[id] = "source instance missing"
					continue
				var replacement := {}
				VegetationChunk.append_to(replacement, int(rec.mesh), xf, Color.WHITE)
				var updated: PackedFloat32Array = replacement[int(rec.mesh)]
				for i in range(12, VegetationChunk.FLOATS_PER_INSTANCE):
					updated[i] = original[i]
				var target: PackedFloat32Array = result.get(int(rec.mesh), PackedFloat32Array())
				target.append_array(updated)
				result[int(rec.mesh)] = target
			else:
				VegetationChunk.append_to(result, int(rec.mesh), xf, Color.WHITE)
	return result

func affected_cells() -> Array:
	_query_hashes.clear()
	var cells := {}
	for id in records:
		var rec: Dictionary = records[id]
		if not _valid(id, rec):
			continue
		if rec.kind == "generated":
			cells[Vector2i(int(rec.cell[0]), int(rec.cell[1]))] = true
		if not rec.get("removed", false):
			cells[VegetationChunk.cell_of(_decode(rec.transform).origin, streamer.cell_size_m)] = true
	return cells.keys()

func _changed(before: Array) -> void:
	var cells := before
	for cell in affected_cells():
		if not cells.has(cell):
			cells.append(cell)
	streamer.overrides_changed(cells)

static func _encode(xf: Transform3D) -> Array:
	return [xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y, xf.basis.y.z, xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z]

static func _decode(a: Array) -> Transform3D:
	return Transform3D(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]), Vector3(a[9], a[10], a[11]))

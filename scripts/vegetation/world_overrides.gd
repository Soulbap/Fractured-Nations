## Versioned, baseline-bound static instance edits. Chunk files remain read-only.
##
## Identity: a generated instance is addressed by (cell, mesh, index) inside its source chunk and the
## record carries the SHA-256 of that chunk file (the baseline). A record is only applied while the
## chunk file still has that hash; otherwise it is "unresolved" and never touches another object.
## Added objects carry a random id and need no baseline.
##
## Revision model (EDITOR-WORLD-02C). Hashing a 1-2 MB chunk costs several ms, so the digest is
## kept as the *revision* of the chunk file: {hash, mtime, size, checked_at}.
##  - The hash is computed when a revision is first needed and whenever the streamer (re)loads the
##    chunk, so the in-memory chunk is bound to the hash taken at load time.
##  - Normal lookups reuse the revision; they never read the file.
##  - Source change is detected, not assumed away: poll() (about once a second, driven by the
##    streamer) and chunk_hash() compare mtime and size of the file with the revision. Any difference
##    drops the revision, makes the streamer reload the chunk and hashes again. mtime/size only ever
##    trigger *more* hashing; they are never accepted as proof that the content is unchanged.
##  - invalidate_chunk()/invalidate_all() are the explicit hooks for controlled operations (generator,
##    editor file reload).
##  - Without a revision (file missing, unreadable) generated records are unresolved and unused.
## Trust boundary: the chunk files are immutable base-world data while a session runs. A writer that
## replaces a file with different bytes of the same size and the same mtime between two polls is
## outside what this layer can see; the next chunk (re)load always rehashes.
@tool
extends RefCounted

## Minimum time between two stat checks of one chunk file (ms).
const GUARD_INTERVAL_MS := 1000

var streamer: Node
var path: String
## id -> record. Mutate with put()/erase_record() (or call reindex() after replacing the dictionary).
var records: Dictionary = {}
var unresolved: Dictionary = {}
## Counters for measurements. hashes = SHA-256 computations of chunk files.
var stats := {"hashes": 0, "stat_checks": 0, "cell_builds": 0, "cell_hits": 0, "source_changes": 0}

## Vector2i chunk location -> {hash, mtime, size, checked}
var _rev: Dictionary = {}
var _src: Dictionary = {}    # source cell -> Array of generated record ids
var _dst: Dictionary = {}    # destination cell -> Array of live record ids
var _index_ok := false
var _cells_cache: Dictionary = {}   # cell -> effective by-mesh dictionary
var _affected_cache: Array = []
var _affected_ok := false
var _last_poll := 0


func _init(owner: Node, file_path: String) -> void:
	streamer = owner
	path = file_path


func load_file() -> bool:
	records = {}
	unresolved.clear()
	_forget_state()
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


# --- Chunk revisions ---------------------------------------------------------------------

func _chunk_file(loc: Vector2i) -> String:
	return streamer.data_directory.path_join(VegetationChunk.file_name(loc))


func _file_signature(file_path: String) -> Dictionary:
	stats.stat_checks += 1
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return {}
	return {"mtime": FileAccess.get_modified_time(file_path), "size": f.get_length()}


## SHA-256 of the chunk file for the current revision ("" when the file is missing). Computes it
## only when there is no valid revision.
func chunk_hash(loc: Vector2i) -> String:
	var now := Time.get_ticks_msec()
	var rev: Variant = _rev.get(loc)
	if rev != null:
		if now - int(rev.checked) < GUARD_INTERVAL_MS:
			return rev.hash
		var sig := _file_signature(_chunk_file(loc))
		if sig.is_empty() or sig.mtime != rev.mtime or sig.size != rev.size:
			_source_changed(loc)
		else:
			rev.checked = now
			return rev.hash
	var file_path := _chunk_file(loc)
	var sig2 := _file_signature(file_path)
	if sig2.is_empty():
		return ""
	var digest := FileAccess.get_sha256(file_path)
	stats.hashes += 1
	_rev[loc] = {"hash": digest, "mtime": sig2.mtime, "size": sig2.size, "checked": now}
	return digest


## The file changed behind our back (or disappeared): drop the revision and what was derived from it,
## and have the streamer re-read the chunk so memory and hash describe the same bytes.
func _source_changed(loc: Vector2i) -> void:
	stats.source_changes += 1
	_rev.erase(loc)
	_invalidate_derived()
	if streamer and streamer.has_method("reload_chunk"):
		streamer.reload_chunk(loc)


## Controlled operations that rewrote a chunk file call this.
func invalidate_chunk(loc: Vector2i) -> void:
	_rev.erase(loc)
	_invalidate_derived()


func invalidate_all() -> void:
	_rev.clear()
	_invalidate_derived()


## For measurements: forget all revisions and caches without touching records.
func forget_revisions() -> void:
	_forget_state()


## The streamer stored a freshly loaded chunk: bind it to a fresh hash when records depend on it.
func on_chunk_loaded(loc: Vector2i) -> void:
	_rev.erase(loc)
	if _chunk_has_records(loc):
		_invalidate_derived()
		chunk_hash(loc)


func on_chunk_unloaded(loc: Vector2i) -> void:
	if _rev.erase(loc):
		_invalidate_derived()


## Called by the streamer about once per frame; checks file signatures at the guard interval.
func poll() -> void:
	var now := Time.get_ticks_msec()
	if _rev.is_empty() or now - _last_poll < GUARD_INTERVAL_MS:
		return
	_last_poll = now
	for loc in _rev.keys():
		var rev: Dictionary = _rev[loc]
		if now - int(rev.checked) >= GUARD_INTERVAL_MS:
			chunk_hash(loc)


func _chunk_has_records(loc: Vector2i) -> bool:
	_ensure_index()
	for cell in _src:
		if _chunk_of_cell(cell) == loc:
			return true
	return false


func _chunk_of_cell(cell: Vector2i) -> Vector2i:
	return VegetationChunk.chunk_of(Vector3(cell.x * streamer.cell_size_m, 0, cell.y * streamer.cell_size_m), streamer.chunk_size_m)


func _invalidate_derived() -> void:
	_cells_cache.clear()
	_affected_ok = false


func _forget_state() -> void:
	_rev.clear()
	_index_ok = false
	_invalidate_derived()


# --- Record editing -------------------------------------------------------------------

func reindex() -> void:
	_index_ok = false
	_invalidate_derived()


func _ensure_index() -> void:
	if _index_ok:
		return
	_src.clear()
	_dst.clear()
	for id in records:
		var rec: Dictionary = records[id]
		if rec.get("kind") == "generated" and rec.has("cell"):
			var cell := Vector2i(int(rec.cell[0]), int(rec.cell[1]))
			if not _src.has(cell):
				_src[cell] = []
			_src[cell].append(id)
		if not rec.get("removed", false) and rec.has("transform"):
			var dest := VegetationChunk.cell_of(_decode(rec.transform).origin, streamer.cell_size_m)
			if not _dst.has(dest):
				_dst[dest] = []
			_dst[dest].append(id)
	_index_ok = true


func generated_id(cell: Vector2i, mesh_id: int, index: int) -> String:
	return "g:%d:%d:%d:%d" % [cell.x, cell.y, mesh_id, index]


## Stores or replaces one record and refreshes every cell it touches (before and after).
func put(id: String, record: Dictionary) -> void:
	var before := affected_cells()
	records[id] = record.duplicate(true)
	reindex()
	_changed(before)


## Stores many records at once (one refresh); used by tools that edit in bulk.
func put_many(new_records: Dictionary) -> void:
	var before := affected_cells()
	for id in new_records:
		records[id] = (new_records[id] as Dictionary).duplicate(true)
	reindex()
	_changed(before)


func erase_record(id: String) -> void:
	if not records.has(id):
		return
	var before := affected_cells()
	records.erase(id)
	unresolved.erase(id)
	reindex()
	_changed(before)


func set_generated(cell: Vector2i, mesh_id: int, index: int, transform: Transform3D, removed := false) -> String:
	var loc := _chunk_of_cell(cell)
	var ch: VegetationChunk = streamer.get_chunk_sync(loc)
	if ch == null or not ch.cells.has(cell) or not ch.cells[cell].has(mesh_id) or index < 0 or index >= ch.cells[cell][mesh_id].size() / VegetationChunk.FLOATS_PER_INSTANCE:
		push_error("World overrides: invalid generated instance locator")
		return ""
	var digest := chunk_hash(loc)
	if digest.is_empty():
		push_error("World overrides: baseline chunk unavailable")
		return ""
	var id := generated_id(cell, mesh_id, index)
	put(id, {"kind": "generated", "cell": [cell.x, cell.y], "mesh": mesh_id, "index": index,
		"chunk_hash": digest, "transform": _encode(transform), "removed": removed})
	return id


func add_instance(mesh_id: int, transform: Transform3D) -> String:
	var id := "a:" + Crypto.new().generate_random_bytes(16).hex_encode()
	put(id, {"kind": "added", "mesh": mesh_id, "transform": _encode(transform), "removed": false})
	return id


func restore(id: String) -> void:
	erase_record(id)


func _valid(id: String, record: Dictionary) -> bool:
	if record.get("kind") == "added":
		return true
	if record.get("kind") != "generated" or not record.has("cell") or not record.has("chunk_hash"):
		unresolved[id] = "invalid locator"
		return false
	var current := chunk_hash(_chunk_of_cell(Vector2i(int(record.cell[0]), int(record.cell[1]))))
	if current.is_empty() or current != record.chunk_hash:
		unresolved[id] = "baseline chunk missing or changed"
		return false
	unresolved.erase(id)
	return true


func is_valid(id: String) -> bool:
	return records.has(id) and _valid(id, records[id])


func _source_record(rec: Dictionary) -> PackedFloat32Array:
	var cell := Vector2i(int(rec.cell[0]), int(rec.cell[1]))
	var ch: VegetationChunk = streamer.get_chunk_sync(_chunk_of_cell(cell))
	if ch == null or not ch.cells.has(cell) or not ch.cells[cell].has(int(rec.mesh)):
		return PackedFloat32Array()
	var buf: PackedFloat32Array = ch.cells[cell][int(rec.mesh)]
	var offset := int(rec.index) * VegetationChunk.FLOATS_PER_INSTANCE
	if offset < 0 or offset + VegetationChunk.FLOATS_PER_INSTANCE > buf.size():
		return PackedFloat32Array()
	return buf.slice(offset, offset + VegetationChunk.FLOATS_PER_INSTANCE)


## Effective { mesh_id: buffer } of one cell. The result is cached per cell and shared: callers
## must not modify it. Cells without any override return `by_mesh` unchanged.
func effective(cell: Vector2i, by_mesh: Dictionary) -> Dictionary:
	if records.is_empty():
		return by_mesh
	_ensure_index()
	var src_ids: Array = _src.get(cell, [])
	var dst_ids: Array = _dst.get(cell, [])
	if src_ids.is_empty() and dst_ids.is_empty():
		return by_mesh
	# Records are validated first: that may reload a changed chunk and clear the cache.
	var generation: int = stats.source_changes
	var suppressed := {}
	for id in src_ids:
		if _valid(id, records[id]):
			var rec: Dictionary = records[id]
			var mesh_id := int(rec.mesh)
			if not suppressed.has(mesh_id):
				suppressed[mesh_id] = {}
			suppressed[mesh_id][int(rec.index)] = true
	if _cells_cache.has(cell):
		stats.cell_hits += 1
		return _cells_cache[cell]
	stats.cell_builds += 1
	var fpi := VegetationChunk.FLOATS_PER_INSTANCE
	var result := by_mesh.duplicate()
	for mesh_id in suppressed:
		var buf: PackedFloat32Array = result.get(mesh_id, PackedFloat32Array())
		var filtered := PackedFloat32Array()
		for i in buf.size() / fpi:
			if not suppressed[mesh_id].has(i):
				filtered.append_array(buf.slice(i * fpi, (i + 1) * fpi))
		result[mesh_id] = filtered
	# Packed arrays are shared by reference: copy each buffer once before appending to it, or the
	# loaded chunk itself would change.
	var copied := {}
	for id in dst_ids:
		var rec: Dictionary = records[id]
		if not _valid(id, rec):
			continue
		var mesh_key := int(rec.mesh)
		if not copied.has(mesh_key):
			copied[mesh_key] = true
			result[mesh_key] = (result[mesh_key] as PackedFloat32Array).duplicate() if result.has(mesh_key) else PackedFloat32Array()
		var xf := _decode(rec.transform)
		if rec.kind == "generated":
			var original := _source_record(rec)
			if original.is_empty():
				unresolved[id] = "source instance missing"
				continue
			# Same attributes as the source record (colour etc.); only the transform is replaced.
			var replacement := {}
			VegetationChunk.append_to(replacement, int(rec.mesh), xf, Color.WHITE)
			var updated: PackedFloat32Array = replacement[int(rec.mesh)]
			for i in range(12, fpi):
				updated[i] = original[i]
			var target: PackedFloat32Array = result.get(int(rec.mesh), PackedFloat32Array())
			target.append_array(updated)
			result[int(rec.mesh)] = target
		else:
			var c: Array = rec.get("color", [1.0, 1.0, 1.0])
			VegetationChunk.append_to(result, int(rec.mesh), xf, Color(c[0], c[1], c[2]))
	# A source change during validation means by_mesh may describe the old chunk: do not cache.
	if generation == stats.source_changes:
		_cells_cache[cell] = result
	return result


## Cells whose effective content differs from the chunk data (sources and destinations of valid records).
func affected_cells() -> Array:
	if _affected_ok:
		return _affected_cache.duplicate()
	_ensure_index()
	var cells := {}
	# Validation may find a changed chunk file; the second pass then runs on settled revisions.
	for attempt in 2:
		var generation: int = stats.source_changes
		cells.clear()
		for id in records:
			var rec: Dictionary = records[id]
			if not _valid(id, rec):
				continue
			if rec.kind == "generated":
				cells[Vector2i(int(rec.cell[0]), int(rec.cell[1]))] = true
			if not rec.get("removed", false):
				cells[VegetationChunk.cell_of(_decode(rec.transform).origin, streamer.cell_size_m)] = true
		if generation == stats.source_changes:
			break
	_affected_cache = cells.keys()
	_affected_ok = true
	return _affected_cache.duplicate()


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

extends SceneTree

const Layer = preload("res://scripts/vegetation/world_overrides.gd")
const FILE := "res://.godot/ew02_ref_overrides.json"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var streamer := VegetationStreamer.new()
	streamer.data_directory = "res://worlds/ref_20km/vegetation"
	streamer.library = load("res://assets/environment/nordic_library.tres")
	root.add_child(streamer)
	var layer = Layer.new(streamer, FILE)
	streamer.overrides = layer
	var chunk := streamer.get_chunk_sync(Vector2i(-2, -5))
	assert(chunk != null)
	var tree := []
	var house := []
	for cell in chunk.cells:
		for mesh in chunk.cells[cell]:
			if tree.is_empty() and int(mesh) >= 1 and int(mesh) <= 6:
				tree = [cell, int(mesh)]
			if house.is_empty() and int(mesh) == 16:
				house = [cell, int(mesh)]
	assert(not tree.is_empty() and not house.is_empty())
	for item in [tree, house]:
		var cell: Vector2i = item[0]
		var mesh: int = item[1]
		var original := VegetationChunk.instance_transform(chunk.cells[cell][mesh], 0)
		var moved := original
		moved.origin += Vector3(160, 0, 0)
		var id: String = layer.set_generated(cell, mesh, 0, moved)
		assert(not id.is_empty())
		var dest := VegetationChunk.cell_of(moved.origin, streamer.cell_size_m)
		var values := streamer.get_cell_instances(dest, [mesh])
		assert(values.any(func(v): return v[1].origin.is_equal_approx(moved.origin)))
		streamer._activate(Vector3i(dest.x, dest.y, mesh), 0.0)
		assert(streamer.active.has(Vector3i(dest.x, dest.y, mesh)))
		layer.set_generated(cell, mesh, 0, moved, true)
		assert(not streamer.get_cell_instances(dest, [mesh]).any(func(v): return v[1].origin.is_equal_approx(moved.origin)))
		layer.restore(id)
		assert(streamer.get_cell_instances(cell, [mesh]).any(func(v): return v[1].origin.is_equal_approx(original.origin)))
		layer.set_generated(cell, mesh, 0, moved)
		print("EW02 REF mesh=", mesh, " source=", original.origin, " destination=", moved.origin)
	var added: String = layer.add_instance(16, Transform3D(Basis.IDENTITY, Vector3(-1500, 270, -4400)))
	assert(layer.save_file())
	streamer.chunks.clear()
	var reloaded = Layer.new(streamer, FILE)
	streamer.overrides = reloaded
	assert(reloaded.load_file() and reloaded.records.has(added))
	assert(reloaded.unresolved.is_empty())
	for item in [tree, house]:
		var cell: Vector2i = item[0]
		var mesh: int = item[1]
		var original := VegetationChunk.instance_transform(chunk.cells[cell][mesh], 0)
		var moved := original.origin + Vector3(160, 0, 0)
		var dest := VegetationChunk.cell_of(moved, streamer.cell_size_m)
		assert(streamer.get_cell_instances(dest, [mesh]).any(func(v): return v[1].origin.is_equal_approx(moved)))
		var key := Vector3i(dest.x, dest.y, mesh)
		if streamer.active.has(key):
			streamer._deactivate(key)
		streamer._activate(key, 0.0)
		assert(streamer.active.has(key))
		var buffer: PackedFloat32Array = streamer.active[key].multimesh.buffer
		var found := false
		for i in buffer.size() / VegetationChunk.FLOATS_PER_INSTANCE:
			if VegetationChunk.instance_transform(buffer, i).origin.is_equal_approx(moved):
				found = true
				break
		assert(found)
		var manager := StructureManager.new()
		manager.vegetation = streamer
		assert(manager._trees_in(dest).any(func(v): return is_equal_approx(v[0], moved.x) and is_equal_approx(v[1], moved.z)))
		manager.free()
	print("EW02 REF isolated override checks passed")
	streamer.free()
	quit()

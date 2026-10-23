extends SceneTree

const Layer = preload("res://scripts/vegetation/world_overrides.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var s := VegetationStreamer.new()
	s.data_directory = "res://worlds/ref_20km/vegetation"
	root.add_child(s)
	var layer = Layer.new(s, "res://.godot/ew02_bench.json")
	s.overrides = layer
	var loc := Vector2i(-1, -1)
	var ch := s.get_chunk_sync(loc)
	var digest: String = layer.chunk_hash(loc)
	var cells := []
	var count := 0
	for cell in ch.cells:
		cells.append(cell)
		for mesh in ch.cells[cell]:
			var buf: PackedFloat32Array = ch.cells[cell][mesh]
			for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
				var xf := VegetationChunk.instance_transform(buf, i)
				var id: String = layer.generated_id(cell, mesh, i)
				layer.records[id] = {"kind":"generated", "cell":[cell.x, cell.y], "mesh":mesh, "index":i,
					"chunk_hash":digest, "transform":layer._encode(xf), "removed":false}
				count += 1
				if count == 100:
					break
			if count == 100:
				break
		if count == 100:
			break
	assert(count == 100)
	var start := Time.get_ticks_usec()
	for i in 100:
		s.get_cell_instances(cells[i % cells.size()], [1, 2, 3, 4, 5, 13, 14, 15])
	print("EW02 BENCH 100 overrides, 100 cell reads: ", (Time.get_ticks_usec() - start) / 1000.0, " ms")
	s.free()
	quit()

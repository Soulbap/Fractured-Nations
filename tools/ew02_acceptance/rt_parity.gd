## EDITOR-WORLD-02 runtime parity check (reads the override file the editor probe saved). Isolated project copy only:
## godot --headless --path <copy> --script res://tools/ew02_acceptance/rt_parity.gd
extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func _ray(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return not root.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _near(col, p: Vector3) -> int:
	var n := 0
	for cs in col._pool:
		if not cs.disabled and cs.global_position.distance_to(p) < 6.0 and cs.global_position.y > p.y - 50.0:
			n += 1
	return n

func run() -> void:
	var rep := {}
	var j = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/ref_20km.overrides.json"))
	var rec = j.records.values()[0]
	var moved := Vector3(rec.transform[9], rec.transform[10], rec.transform[11])
	var src: Vector3
	var s := VegetationStreamer.new()
	s.data_directory = "res://worlds/ref_20km/vegetation"
	s.library = load("res://assets/environment/nordic_library.tres")
	root.add_child(s)
	var cell := Vector2i(int(rec.cell[0]), int(rec.cell[1]))
	var ch := s.get_chunk_sync(VegetationChunk.chunk_of(Vector3(cell.x * s.cell_size_m, 0, cell.y * s.cell_size_m), s.chunk_size_m))
	src = VegetationChunk.instance_transform(ch.cells[cell][16], int(rec.index)).origin
	var dest := VegetationChunk.cell_of(moved, s.cell_size_m)
	rep.loaded_overrides = s.overrides.records.size()
	rep.unresolved = s.overrides.unresolved.size()
	rep.runtime_has_moved = s.get_cell_instances(dest, [16]).any(func(v): return v[1].origin.distance_to(moved) < 0.01)
	rep.runtime_source_gone = not s.get_cell_instances(cell, [16]).any(func(v): return v[1].origin.distance_to(src) < 0.01)
	var terrain_dummy := Node3D.new()
	root.add_child(terrain_dummy)
	var col := InstanceColliderStreamer.new()
	col.vegetation = s
	col.target = terrain_dummy
	root.add_child(col)
	terrain_dummy.global_position = moved
	await physics_frame
	col._physics_process(0.0)
	await physics_frame
	await physics_frame
	var c := Vector3(0, 2.0, 0)
	rep.collider_active_near_moved = col.active_count
	rep.shapes_near_moved = _near(col, moved)
	rep.ray_hits_at_moved = _ray(moved + Vector3(-25, 2, 0), moved + Vector3(25, 2, 0)) or _ray(moved + Vector3(0, 2, -25), moved + Vector3(0, 2, 25))
	terrain_dummy.global_position = src
	col._physics_process(0.0)
	await physics_frame
	await physics_frame
	# at the old place the house must no longer block (other objects nearby may; test exact centre ray)
	rep.shapes_near_source = _near(col, src)
	rep.ray_hits_at_source_centre = (_ray(src + Vector3(-25, 2, 0), src + Vector3(25, 2, 0)) or _ray(src + Vector3(0, 2, -25), src + Vector3(0, 2, 25)))
	# baseline: with overrides removed the source centre WOULD block
	s.overrides.records.clear()
	s.overrides_changed([cell, dest])
	col._physics_process(0.0)
	terrain_dummy.global_position = src + Vector3(15, 0, 15)
	col._physics_process(0.0)
	terrain_dummy.global_position = src
	col._physics_process(0.0)
	await physics_frame
	await physics_frame
	rep.baseline_shapes_near_source = _near(col, src)
	rep.baseline_ray_hits_at_source_centre = (_ray(src + Vector3(-25, 2, 0), src + Vector3(25, 2, 0)) or _ray(src + Vector3(0, 2, -25), src + Vector3(0, 2, 25)))
	var f := FileAccess.open("res://probe_rt.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	print("RT ", JSON.stringify(rep))
	quit()

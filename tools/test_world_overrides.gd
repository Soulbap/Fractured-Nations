extends SceneTree

const DIR := "res://.godot/ew02_test"
const OverrideLayer = preload("res://scripts/vegetation/world_overrides.gd")

class TestBuilder extends WorldBuilder:
	func vegetation_directory() -> String:
		return "res://.godot/ew02_test"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var ch := VegetationChunk.new()
	ch.chunk_size_m = 1024.0
	ch.cell_size_m = 128.0
	ch.add_instance(1, Transform3D(Basis.IDENTITY, Vector3(5, 0, 5)), Color(0.4, 0.5, 0.6, 1.0))
	ch.add_instance(13, Transform3D(Basis.IDENTITY, Vector3(10, 0, 10)), Color.WHITE)
	assert(ResourceSaver.save(ch, DIR.path_join("veg_0_0.res")) == OK)
	var s := VegetationStreamer.new()
	s.data_directory = DIR
	var mesh_root := Node3D.new()
	for n in ["LOD0", "LOD1"]:
		var mesh_node := MeshInstance3D.new()
		mesh_node.name = n
		mesh_node.mesh = BoxMesh.new()
		mesh_root.add_child(mesh_node)
		mesh_node.owner = mesh_root
	var packed := PackedScene.new()
	assert(packed.pack(mesh_root) == OK)
	mesh_root.free()
	var def := VegetationMeshDef.new()
	def.id = 1
	def.scene = packed
	def.near_range = 100.0
	def.collider = Vector3(0, 0.35, 8.0)
	var house_def := VegetationMeshDef.new()
	house_def.id = 13
	house_def.scene = packed
	house_def.collider = Vector3(1, 3.0, 0.0)
	var lib := VegetationLibrary.new()
	lib.meshes = [def, house_def]
	s.library = lib
	root.add_child(s)
	var layer = OverrideLayer.new(s, DIR.path_join("overrides.json"))
	s.overrides = layer
	assert(s.get_cell_instances(Vector2i.ZERO, [1, 13]).size() == 2)
	var moved := Transform3D(Basis.IDENTITY, Vector3(300, 0, 300))
	var tree: String = layer.set_generated(Vector2i.ZERO, 1, 0, moved)
	var house: String = layer.set_generated(Vector2i.ZERO, 13, 0, moved, true)
	assert(not tree.is_empty() and not house.is_empty())
	assert(s.get_cell_instances(Vector2i.ZERO, [1, 13]).is_empty())
	assert(s.get_cell_instances(Vector2i(2, 2), [1, 13]).size() == 1)
	var rendered: PackedFloat32Array = s._effective_cell(Vector2i(2, 2))[1]
	var original: PackedFloat32Array = ch.cells[Vector2i.ZERO][1]
	for i in range(16):
		if i not in [3, 7, 11]:
			assert(is_equal_approx(rendered[i], original[i]))
	assert(is_equal_approx(rendered[3], 300.0) and is_equal_approx(rendered[7], 0.0) and is_equal_approx(rendered[11], 300.0))
	var key := Vector3i(2, 2, 1)
	s._activate(key, 20.0)
	assert(s.active.has(key))
	assert(s.active[key].multimesh.buffer == rendered)
	s._update_lod(key, 200.0)
	assert(s.active_lod[key] == 1 and s.active[key].multimesh.buffer == rendered)
	s._update_lod(key, 10.0)
	assert(s.active_lod[key] == 0 and s.active[key].multimesh.buffer == rendered)
	var added: String = layer.add_instance(13, Transform3D(Basis.IDENTITY, Vector3(1800, 0, 0)))
	assert(not added.is_empty())
	assert(s.get_cell_instances(Vector2i(14, 0), [13]).size() == 1)
	assert(layer.save_file())
	s.chunks.clear()
	var reloaded = OverrideLayer.new(s, DIR.path_join("overrides.json"))
	s.overrides = reloaded
	assert(reloaded.load_file())
	assert(s.get_cell_instances(Vector2i.ZERO, [1, 13]).is_empty())
	assert(s.get_cell_instances(Vector2i(2, 2), [1]).size() == 1)
	assert(s._effective_cell(Vector2i(2, 2))[1] == rendered)
	assert(s.get_cell_instances(Vector2i(14, 0), [13]).size() == 1)
	var manager := StructureManager.new()
	manager.vegetation = s
	s.clearings_changed.connect(manager._on_vegetation_cells_changed)
	assert(manager.blocks_trunk(Vector2(300, 300)))
	var line := LineOfFire.new()
	line.setup(null, null, s, manager)
	line.warm(Vector2i(2, 2))
	assert(line._loaded_cells.has(Vector2i(2, 2)))
	assert(is_finite(line._trees_hit(Vector3(295, 1, 300), Vector3(305, 1, 300), 10.0)))
	var collider := InstanceColliderStreamer.new()
	collider.vegetation = s
	root.add_child(collider)
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(300, 0, 300)
	collider.target = target
	collider._physics_process(0.0)
	assert(collider.active_count == 1)
	reloaded.set_generated(Vector2i.ZERO, 1, 0, Transform3D(Basis.IDENTITY, Vector3(600, 0, 600)))
	assert(not manager.blocks_trunk(Vector2(300, 300)))
	assert(manager.blocks_trunk(Vector2(600, 600)))
	assert(not line._loaded_cells.has(Vector2i(2, 2)))
	assert(not is_finite(line._trees_hit(Vector3(295, 1, 300), Vector3(305, 1, 300), 10.0)))
	assert(is_finite(line._trees_hit(Vector3(595, 1, 600), Vector3(605, 1, 600), 10.0)))
	collider._physics_process(0.0)
	assert(collider.active_count == 0)
	target.position = Vector3(600, 0, 600)
	collider._physics_process(0.0)
	assert(collider.active_count == 1)
	var nav := AreaNavigation.new()
	nav.vegetation = s
	var geom := NavigationMeshSourceGeometryData3D.new()
	assert(nav._add_tree_obstructions(geom, Vector3(600, 0, 600), 30.0) == 1)
	var detail := DetailManager.new()
	detail.navigation = nav
	detail.nav_center = Vector3(600, 0, 600)
	root.add_child(detail)
	reloaded.set_generated(Vector2i.ZERO, 1, 0, Transform3D(Basis.IDENTITY, Vector3(601, 0, 600)))
	assert(detail._rebake_in >= 0.0)
	detail.free()
	var far_observer: Array[Vector3] = [Vector3(10000, 0, 10000)]
	s._update_sets(far_observer)
	s._drain_queue()
	assert(not s.chunks.has(Vector2i.ZERO))
	assert(not s.active.has(key))
	var near_observer: Array[Vector3] = [Vector3(600, 0, 600)]
	s._update_sets(near_observer)
	while not s.is_settled() and s._queue_pos < s._queue.size():
		s._drain_queue()
	assert(s.active.has(Vector3i(4, 4, 1)))
	assert(s.active[Vector3i(4, 4, 1)].multimesh.buffer.slice(12, 16) == original.slice(12, 16))
	nav.free()
	collider.free()
	target.free()
	manager.free()
	reloaded.restore(house)
	assert(s.get_cell_instances(Vector2i.ZERO, [13]).size() == 1)
	var moved_house := Transform3D(Basis.IDENTITY, Vector3(450, 0, 450))
	reloaded.set_generated(Vector2i.ZERO, 13, 0, moved_house)
	assert(s.get_cell_instances(Vector2i.ZERO, [13]).is_empty())
	assert(s.get_cell_instances(Vector2i(3, 3), [13])[0][1].origin == moved_house.origin)
	assert(reloaded.save_file())
	var baseline_hash := FileAccess.get_sha256(DIR.path_join("veg_0_0.res"))
	var builder := TestBuilder.new()
	assert(not builder._vegetation_replacement_allowed())
	builder.scatter_vegetation()
	assert(FileAccess.get_sha256(DIR.path_join("veg_0_0.res")) == baseline_hash)
	builder.allow_replace_existing_vegetation = true
	assert(builder._vegetation_replacement_allowed())
	assert(FileAccess.get_sha256(DIR.path_join("veg_0_0.res")) == baseline_hash)
	builder.free()
	# Change only a synthetic source chunk and reopen the layer to test mismatch handling.
	ch.add_instance(1, Transform3D(Basis.IDENTITY, Vector3(30, 0, 30)), Color.WHITE)
	assert(ResourceSaver.save(ch, DIR.path_join("veg_0_0.res")) == OK)
	s.chunks.clear()
	assert(s.get_cell_instances(Vector2i(4, 4), [1]).is_empty())
	assert(reloaded.unresolved.has(tree))
	var mismatch = OverrideLayer.new(s, DIR.path_join("overrides.json"))
	s.overrides = mismatch
	assert(mismatch.load_file())
	assert(s.get_cell_instances(Vector2i(2, 2), [1]).is_empty())
	assert(mismatch.unresolved.has(tree))
	assert(mismatch.records.has(tree))
	assert(s.get_cell_instances(Vector2i(14, 0), [13]).size() == 1)
	print("EW02 synthetic effective-cell checks passed")
	s.queue_free()
	quit()

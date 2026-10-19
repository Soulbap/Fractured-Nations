## Rebuilds the vegetation of an existing world scene (WORLD-TECH-02 storage):
## grass exclusion mask, deterministic VegetationChunk files, forest tint in the color
## map, and removal of the old stored Terrain3D instances. Adds the Vegetation
## (VegetationStreamer) and Grass (GrassLayer) nodes to the scene when missing.
##
##   Godot_console.exe --headless --path . --script res://tools/rebuild_vegetation.gd -- \
##       --scene=res://scenes/world/test_2km.tscn [--veg-extent=<m>] [--single-thread]
##       [--save-scene] [--no-tint]
##
## --veg-extent  overrides and saves WorldConfig.vegetation_extent_m (0 = whole map)
## --save-scene  re-save the scene even if no nodes were added (headless pack)
extends SceneTree

var opts := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else true
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var scene_path: String = opts.get("scene", "res://scenes/world/test_2km.tscn")
	var ps: PackedScene = load(scene_path)
	var world: Node3D = ps.instantiate()
	root.add_child(world)
	var builder: WorldBuilder = world.get_node("WorldBuilder")
	var terrain: Terrain3D = world.get_node("Terrain3D")
	builder.threaded_scatter = not opts.has("single-thread")
	if opts.has("veg-extent"):
		builder.config.vegetation_extent_m = float(opts["veg-extent"])
		if builder.config.resource_path != "":
			ResourceSaver.save(builder.config, builder.config.resource_path)
	# Let the road container finish its deferred setup so road nodes are connected.
	for i in 5:
		await process_frame
	print("REBUILD world=%s regions=%d old_instances=%s" % [
		builder.config.world_name, terrain.data.get_region_count(), JSON.stringify(_instance_counts(terrain))])

	var had_nodes := world.get_node_or_null("Vegetation") != null and world.get_node_or_null("Grass") != null
	builder.ensure_vegetation_nodes(world)
	builder._collect_road_polylines()
	print("REBUILD roads: %d polylines" % builder.road_polylines.size())
	builder.scatter_vegetation()
	if opts.has("no-tint"):
		pass
	var t_save := Time.get_ticks_msec()
	terrain.data.save_directory(terrain.data_directory)
	print("REBUILD saved terrain data (%d regions) in %d ms" % [terrain.data.get_region_count(), Time.get_ticks_msec() - t_save])
	_report(builder)

	if not had_nodes or opts.has("save-scene"):
		_strip_generated_owners(world)
		var packed := PackedScene.new()
		var err := packed.pack(world)
		if err == OK:
			err = ResourceSaver.save(packed, scene_path)
		print("REBUILD scene %s saved err=%d" % [scene_path, err])
	print("REBUILD done in %d ms" % (Time.get_ticks_msec() - t0))
	quit()


func _instance_counts(terrain: Terrain3D) -> Dictionary:
	var out := {}
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		var inst: Dictionary = region.get_instances()
		for mesh_id in inst:
			for cell in inst[mesh_id]:
				out[mesh_id] = out.get(mesh_id, 0) + inst[mesh_id][cell][0].size()
	return out


func _report(builder: WorldBuilder) -> void:
	var dir := ProjectSettings.globalize_path(builder.vegetation_directory())
	var total := 0
	var files := 0
	var bytes := 0
	var counts := {}
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("veg_") and f.ends_with(".res"):
			var ch: VegetationChunk = load(builder.vegetation_directory() + "/" + f)
			files += 1
			bytes += FileAccess.get_file_as_bytes(dir.path_join(f)).size()
			total += ch.instance_count()
			for k in ch.counts_by_mesh():
				counts[k] = counts.get(k, 0) + ch.counts_by_mesh()[k]
	var mask_bytes := FileAccess.get_file_as_bytes(dir.path_join("mask.res")).size()
	print("REBUILD vegetation: %d chunks, %d instances, %.1f MB on disk, mask %.1f MB, per mesh %s" % [
		files, total, bytes / 1048576.0, mask_bytes / 1048576.0, counts])


## Road meshes are regenerated from RoadPoints on load; don't serialize them.
func _strip_generated_owners(scene_root: Node) -> void:
	for n in scene_root.find_children("*", "", true, false):
		if n.owner == scene_root and n.get_parent() and n.get_parent().has_method("is_road_container") \
				and not (n.has_method("is_road_point") or n.has_method("is_road_intersection")):
			n.owner = null

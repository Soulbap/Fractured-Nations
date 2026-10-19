## Builds SYNTHETIC stress-test maps by mirror-tiling an existing Terrain3D world.
##
## Not representative final-world terrain: the source world's 2x2 region block is
## repeated with mirroring so every region edge matches its neighbour (period of four
## regions per axis: c0, c1, mirror(c1), mirror(c0)). The central block keeps the
## source orientation, so the source scene's roads still line up with the terrain at
## the map center. Vegetation instances are copied (mirrored) from the source regions,
## so instance density per area equals the source world.
##
## This only validates scaling of Terrain3D data, rendering and instancing. It does not
## validate the world-generation pipeline (tools/build_world.gd does that).
##
##   Godot_console.exe --headless --path . --script res://tools/tile_world.gd -- \
##       --name=tile_8km --regions=8 [--source=test_2km] [--veg=all|trees|none]
##       [--veg-window=<m>] [--grass-window=<m>]
##
## --regions  regions per side (map = regions * 1024 m at the source's 1 m spacing)
## --veg      which instanced meshes to copy (default all)
## --veg-window / --grass-window  only copy instances inside a centered square
extends SceneTree

const GRASS := 0
const TREES: Array[int] = [1, 2]

var opts := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else true
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var source: String = opts.get("source", "test_2km")
	var out_name: String = opts.get("name", "tile_4km")
	var n := int(opts.get("regions", 4))
	var veg: String = opts.get("veg", "all")
	var veg_window := float(opts.get("veg-window", 0.0))
	var grass_window := float(opts.get("grass-window", 0.0))

	# Source data (assets are only needed for rendering, not for copying).
	var src := Terrain3D.new()
	root.add_child(src)
	src.data_directory = "res://worlds/%s/terrain" % source
	var region_size := src.region_size
	var spacing := src.vertex_spacing
	var region_m := region_size * spacing
	var src_regions := {}
	for r: Terrain3DRegion in src.data.get_regions_active():
		src_regions[r.location] = r
	assert(src_regions.size() == 4, "source must be a 2x2 region world")

	var dst := Terrain3D.new()
	root.add_child(dst)
	dst.region_size = region_size
	dst.vertex_spacing = spacing
	dst.assets = load("res://worlds/%s/terrain_assets.tres" % source)
	var out_dir := "res://worlds/%s/terrain" % out_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(out_dir)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out_dir).path_join(f))

	var half := n / 2
	var counts := {}
	var all_xforms := {} # mesh_id -> Array[Transform3D]
	var all_colors := {} # mesh_id -> PackedColorArray
	var t_copy := Time.get_ticks_msec()
	for rz in range(-half, n - half):
		for rx in range(-half, n - half):
			var sx := _phase(rx)
			var sz := _phase(rz)
			var s: Terrain3DRegion = src_regions[Vector2i(sx.x, sz.x)]
			var r := Terrain3DRegion.new()
			r.region_size = region_size
			r.vertex_spacing = spacing
			r.location = Vector2i(rx, rz)
			var maps: Array[Image] = []
			for img: Image in [s.height_map, s.control_map, s.color_map]:
				var c := img.duplicate() as Image
				if sx.y:
					c.flip_x()
				if sz.y:
					c.flip_y()
				maps.append(c)
			r.height_map = maps[0]
			r.control_map = maps[1]
			r.color_map = maps[2]
			r.calc_height_range()
			dst.data.add_region(r, false)
			# Instances: copy with mirrored region-local positions.
			var offset := Vector3(rx * region_m, 0, rz * region_m)
			var inst: Dictionary = s.get_instances()
			for mesh_id in inst:
				if veg == "none" or (veg == "trees" and not mesh_id in TREES):
					continue
				var window := grass_window if mesh_id == GRASS else veg_window
				if not all_xforms.has(mesh_id):
					var typed: Array[Transform3D] = []
					all_xforms[mesh_id] = typed
					all_colors[mesh_id] = PackedColorArray()
				var xforms: Array[Transform3D] = all_xforms[mesh_id]
				var colors: PackedColorArray = all_colors[mesh_id]
				for cell in inst[mesh_id]:
					var entry: Array = inst[mesh_id][cell]
					for i in entry[0].size():
						var xf: Transform3D = entry[0][i]
						var o := xf.origin
						# Image flips mirror vertex i to (size-1-i), i.e. around region_m - spacing.
						if sx.y:
							o.x = region_m - spacing - o.x
						if sz.y:
							o.z = region_m - spacing - o.z
						var g := o + offset
						if window > 0.0 and (absf(g.x) > window * 0.5 or absf(g.z) > window * 0.5):
							continue
						xforms.append(Transform3D(xf.basis, g))
						colors.append(entry[1][i] if i < entry[1].size() else Color.WHITE)
				all_colors[mesh_id] = colors
	# One add_transforms call per mesh: the instancer re-bins per call, so per-region
	# calls were ~100x slower.
	var t_inst := Time.get_ticks_msec()
	for mesh_id in all_xforms:
		dst.instancer.add_transforms(mesh_id, all_xforms[mesh_id], all_colors[mesh_id], false)
		counts[mesh_id] = all_xforms[mesh_id].size()
	print("TILE instancer add: %d ms" % (Time.get_ticks_msec() - t_inst))
	var t_save := Time.get_ticks_msec()
	dst.data.save_directory(out_dir)
	var t_end := Time.get_ticks_msec()
	print("TILE %s: %dx%d regions (%.1f km), copy %d ms, save %d ms, total %d ms, instances %s" % [
		out_name, n, n, n * region_m / 1000.0, t_save - t_copy, t_end - t_save, t_end - t0, counts])
	_write_scene(out_name, source, n * region_m)
	quit()


## Region index along one axis -> (source index -1 or 0, mirrored?)
## Index -1 -> c0, 0 -> c1, 1 -> mirror(c1), 2 -> mirror(c0), repeating every 4.
func _phase(i: int) -> Vector2i:
	match posmod(i + 1, 4):
		0: return Vector2i(-1, 0)
		1: return Vector2i(0, 0)
		2: return Vector2i(0, 1)
		_: return Vector2i(-1, 1)


## A world scene for the tiled data: copy of the source scene with the terrain pointed
## at the new data and a WorldConfig whose size matches (roads stay at the center).
func _write_scene(out_name: String, source: String, size_m: float) -> void:
	var src_scene: PackedScene = load("res://scenes/world/%s.tscn" % source)
	var world := src_scene.instantiate()
	world.name = "World_" + out_name
	var cfg: WorldConfig = (world.get_node("WorldBuilder").config as WorldConfig).duplicate()
	cfg.world_name = out_name
	cfg.world_size_m = size_m
	# Keep the road layout where it physically is (the central 2 km block).
	var k := 2048.0 / size_m
	for i in cfg.main_road.size():
		cfg.main_road[i] *= k
	var cfg_path := "res://worlds/%s/world_config.tres" % out_name
	ResourceSaver.save(cfg, cfg_path)
	cfg.take_over_path(cfg_path)
	world.get_node("WorldBuilder").config = cfg
	world.get_node("WorldDiagnostics").config = cfg
	var t: Terrain3D = world.get_node("Terrain3D")
	t.data_directory = "res://worlds/%s/terrain" % out_name
	var ps := PackedScene.new()
	ps.pack(world)
	ResourceSaver.save(ps, "res://scenes/world/%s.tscn" % out_name)
	world.free()
	print("TILE scene res://scenes/world/%s.tscn" % out_name)

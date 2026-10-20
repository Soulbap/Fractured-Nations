## Times ReferenceWorldBuilder.build_roads() alone (no terrain data needed).
##   Godot_console.exe --headless --path . --script res://tools/terrain_ref/test_roads.gd
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var cfg: WorldConfig = load("res://worlds/ref_20km/world_config.tres")
	var root := Node3D.new()
	get_root().add_child(root)
	var terrain := Terrain3D.new()
	root.add_child(terrain)
	var roads := Node3D.new()
	root.add_child(roads)
	var b: ReferenceWorldBuilder = cfg.create_builder()
	b.config = cfg
	b.terrain = terrain
	b.road_parent = roads
	root.add_child(b)
	var t := Time.get_ticks_msec()
	await b.build_roads(root)
	printerr("TEST build_roads total %d ms" % (Time.get_ticks_msec() - t))
	quit()

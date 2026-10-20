## Re-places the bridges and culverts of a built reference world (ReferenceWorldBuilder.
## place_structures) and saves the world scene, without rebuilding terrain, roads or
## vegetation (WORLD-PLAYTEST-01: decks following the road slope).
##
##   Godot_console.exe --headless --path . --script res://tools/terrain_ref/rebuild_structures.gd -- [--scene=res://scenes/world/ref_20km.tscn]
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://scenes/world/ref_20km.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			path = a.trim_prefix("--scene=")
	var root: Node3D = (load(path) as PackedScene).instantiate()
	get_root().add_child(root)
	for i in 5:
		await process_frame
	var builder: ReferenceWorldBuilder = root.get_node("WorldBuilder")
	builder.place_structures(root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, path)
	print("REBUILD structures -> %s err=%d" % [path, err])
	quit(0 if err == OK else 1)

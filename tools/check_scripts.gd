## Compiles every GDScript under res://scripts (parse / type errors are printed by the engine) and exits 1 when any
## fails. A cheap check before a runtime test: a script that does not compile makes a test hang until its timeout.
##   Godot_console.exe --headless --path . --script res://tools/check_scripts.gd
extends SceneTree


func _init() -> void:
	var bad: Array[String] = []
	var n := 0
	var stack: Array[String] = ["res://scripts"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for d in dir.get_directories():
			stack.append(dir_path.path_join(d))
		for f in dir.get_files():
			if not f.ends_with(".gd"):
				continue
			n += 1
			var path := dir_path.path_join(f)
			var scr := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
			if scr == null or not scr.can_instantiate() and not scr.is_abstract():
				bad.append(path)
	print("CHECK %d scripts, %d failed: %s" % [n, bad.size(), str(bad)])
	quit(1 if not bad.is_empty() else 0)

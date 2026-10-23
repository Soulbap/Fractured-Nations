## Prints how far the road centre line and its edges lie above the terrain (m): mean / max / share above 0.1 m.
##   Godot_console.exe --headless --path . --script res://tools/terrain_ref/road_lip_stats.gd
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var root: Node3D = (load("res://scenes/world/ref_20km.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in 5:
		await process_frame
	var terrain: Terrain3D = root.get_node("WorldBuilder").terrain
	var data = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://worlds/ref_20km/source/roads.json")))
	for off: float in [0.0, 4.0, 6.0]:
		var n := 0
		var sum := 0.0
		var mx := 0.0
		var hi := 0
		for r in data.roads:
			if not r.mesh:
				continue
			var inb := {}
			for span in r.bridges:
				for i in range(int(span[0]) - 4, int(span[1]) + 5):
					inb[i] = true
			for i in range(1, r.points.size() - 1, 3):
				if inb.has(i):
					continue
				var p: Array = r.points[i]
				var q: Array = r.points[i + 1]
				var dir := Vector2(q[0] - p[0], q[2] - p[2]).normalized()
				var side: Vector2 = Vector2(-dir.y, dir.x) * float(off)
				var h: float = terrain.data.get_height(Vector3(p[0] + side.x, 0.0, p[2] + side.y))
				if is_nan(h):
					continue
				var d: float = p[1] - h
				if d > 1.0 or d < -1.0:
					continue
				n += 1
				sum += d
				mx = maxf(mx, d)
				hi += 1 if d > 0.1 else 0
		print("LIPSTAT offset=%.0f m samples=%d mean=%.3f max=%.3f above_0.1m=%.1f%%" % [off, n, sum / maxf(n, 1), mx, 100.0 * hi / maxf(n, 1)])
	quit(0)

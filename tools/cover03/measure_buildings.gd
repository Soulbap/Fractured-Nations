## COMBAT-COVER-03: prints the LOD0 bounds of the settlement building meshes (library ids 16-18) and their height profiles
## (max height per 0.5 m slice across x and along z) - the source of their box colliders in nordic_library.tres.
##   Godot_console.exe --headless --path . --script res://tools/cover03/measure_buildings.gd
extends SceneTree


func _init() -> void:
	for p in ["res://assets/environment/scenes/house.tscn", "res://assets/environment/scenes/barn.tscn", "res://assets/environment/scenes/shed.tscn"]:
		var root: Node = (load(p) as PackedScene).instantiate()
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if not String(mi.name).ends_with("LOD0"):
				continue
			var aabb := mi.transform * mi.mesh.get_aabb()
			print(p.get_file(), " aabb ", aabb.position, " size ", aabb.size)
			var faces := mi.mesh.get_faces()
			# Dense sample of the triangles (0.25 m), max height per cell.
			var cells := {}
			for i in range(0, faces.size(), 3):
				var a := faces[i]
				var b := faces[i + 1]
				var c := faces[i + 2]
				var n := maxi(1, ceili(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / 0.15))
				for u in n + 1:
					for v in n + 1 - u:
						var q := a + (b - a) * (float(u) / n) + (c - a) * (float(v) / n)
						var k := Vector2i(floori(q.x / 0.5), floori(q.z / 0.5))
						cells[k] = maxf(float(cells.get(k, -INF)), q.y)
			var row := ""
			for kx in range(floori(aabb.position.x / 0.5), ceili(aabb.end.x / 0.5)):
				var h := -INF
				for k: Vector2i in cells:
					if k.x == kx and absi(k.y) <= 1:
						h = maxf(h, cells[k])
				row += "%.1f:%.1f " % [kx * 0.5, h]
			print("  across x (z~0): ", row)
			row = ""
			for kz in range(floori(aabb.position.z / 0.5), ceili(aabb.end.z / 0.5)):
				var h := -INF
				for k: Vector2i in cells:
					if k.y == kz and absi(k.x) <= 1:
						h = maxf(h, cells[k])
				row += "%.1f:%.1f " % [kz * 0.5, h]
			print("  along z (x~0): ", row)
		root.free()
	quit()

extends SceneTree
# ASSET-INTEGRATION-01 developer tool: top-of-geometry profile along the bore (x = 0) of a weapon GLB's LOD0 meshes,
# used to read iron-sight heights (rear notch, front post) for WeaponDef.sight_line.
func _init() -> void:
	for p in OS.get_cmdline_user_args():
		var inst: Node3D = (load(p) as PackedScene).instantiate()
		var tris := PackedVector3Array()
		for mi in inst.find_children("*_LOD0", "MeshInstance3D", true, false):
			var n := String(mi.name)
			if n.contains("_Mag_") or n.contains("Belt") or n.contains("Bipod") or n.contains("Grenade"):
				continue
			var xf: Transform3D = Transform3D.IDENTITY
			var q: Node = mi
			while q != inst:
				xf = (q as Node3D).transform * xf
				q = q.get_parent()
			var faces: PackedVector3Array = (mi as MeshInstance3D).mesh.get_faces()
			for v in faces:
				tris.append(xf * v)
		var line := ""
		var z := 0.30
		while z > -1.0:
			var top := -1.0
			for i in range(0, tris.size(), 3):
				var a := tris[i]; var b := tris[i + 1]; var c := tris[i + 2]
				if minf(a.z, minf(b.z, c.z)) > z or maxf(a.z, maxf(b.z, c.z)) < z or minf(a.x, minf(b.x, c.x)) > 0.0 or maxf(a.x, maxf(b.x, c.x)) < 0.0:
					continue
				var hit = Geometry3D.ray_intersects_triangle(Vector3(0, 1, z), Vector3.DOWN, a, b, c)
				if hit != null:
					top = maxf(top, (hit as Vector3).y)
			line += "%d:%.3f " % [roundi(-z * 100), top]
			z -= 0.01
		print(p.get_file(), " ", line)
		inst.free()
	quit()

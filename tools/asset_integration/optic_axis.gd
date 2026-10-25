extends SceneTree
# ASSET-INTEGRATION-01 developer tool: the optic's eyepiece axis in weapon space - the centre (x, y) of the vertices in the
# rear-most 8 mm of each weapon's PIV_Optic part (the eyepiece ring / rear face), and its rear z.
func _init() -> void:
	for p in OS.get_cmdline_user_args():
		var inst: Node3D = (load(p) as PackedScene).instantiate()
		var piv := inst.find_child("PIV_Optic", true, false) as Node3D
		if piv == null:
			print(p.get_file(), " no optic")
			inst.free()
			continue
		var pts := PackedVector3Array()
		for mi in piv.find_children("*_LOD0", "MeshInstance3D", true, false):
			for v in (mi as MeshInstance3D).mesh.get_faces():
				pts.append(piv.transform * v)
		var zmax := -INF
		for v in pts:
			zmax = maxf(zmax, v.z)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for v in pts:
			if v.z > zmax - 0.008:
				lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
				hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
		print(p.get_file(), " eyepiece centre x=%.4f y=%.4f  size=%s  rear z=%.3f" % [(lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (hi - lo), zmax])
		inst.free()
	quit()

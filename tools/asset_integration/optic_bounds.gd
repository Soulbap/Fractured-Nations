extends SceneTree
# ASSET-INTEGRATION-01 developer tool: weapon-space bounds of each weapon's optic / sight parts (eye relief check).
func _init() -> void:
	for p in OS.get_cmdline_user_args():
		var inst: Node3D = (load(p) as PackedScene).instantiate()
		for piv in inst.find_children("PIV_*", "Node3D", true, false):
			var n := String(piv.name)
			if not (n.contains("Optic") or n.contains("Sight")):
				continue
			for mi in piv.find_children("*_LOD0", "MeshInstance3D", true, false):
				var ab: AABB = (piv as Node3D).transform * (mi as MeshInstance3D).get_aabb()
				print(p.get_file(), " ", n, " min=", ab.position.snapped(Vector3.ONE * 0.001), " max=", ab.end.snapped(Vector3.ONE * 0.001))
		inst.free()
	quit()

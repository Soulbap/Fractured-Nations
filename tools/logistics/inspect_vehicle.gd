extends SceneTree
func _init() -> void:
	for id in ["truck_6x6", "apc_8x8", "wheel_truck", "wheel_apc"]:
		var ps: PackedScene = load("res://assets/military/vehicles/%s.glb" % id)
		var n: Node = ps.instantiate()
		print("=== ", id)
		_dump(n, 0)
		n.free()
	quit()
func _dump(n: Node, d: int) -> void:
	var s := "  ".repeat(d) + n.name + " [" + n.get_class() + "]"
	if n is Node3D:
		var t := (n as Node3D).transform
		s += " pos=" + str(t.origin.snapped(Vector3.ONE * 0.001))
		if abs(t.basis.get_euler().y) > 0.001 or n.get_class() == "Node3D":
			pass
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		s += " surf=%d aabb=%s" % [m.get_surface_count(), str(m.get_aabb().size.snapped(Vector3.ONE * 0.01))]
	if n.has_meta("fn_asset"): s += " META"
	print(s)
	for c in n.get_children():
		_dump(c, d + 1)

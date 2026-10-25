extends SceneTree
# Dumps the node tree of the integration assets (developer inspection).
func _dump(n: Node, depth: int, maxd: int) -> void:
	var s := "  ".repeat(depth) + String(n.name) + " <" + n.get_class() + ">"
	if n is Node3D:
		s += " pos=%s rot=%s" % [(n as Node3D).position, (n as Node3D).rotation_degrees]
	print(s)
	if depth < maxd:
		for c in n.get_children():
			_dump(c, depth + 1, maxd)
func _init() -> void:
	print("IK classes: TwoBoneIK3D=%s SkeletonModifier3D=%s" % [ClassDB.class_exists("TwoBoneIK3D"), ClassDB.class_exists("SkeletonModifier3D")])
	var args := OS.get_cmdline_user_args()
	for p in args:
		var sc := load(p) as PackedScene
		var inst := sc.instantiate()
		print("=== ", p)
		_dump(inst, 0, 6)
		inst.free()
	quit()

extends SceneTree
# ASSET-INTEGRATION-01 developer tool: one character with a loadout, weapon raised, headless - prints the grip modifier's
# state and the posed hand / head (bone attachments) against the held weapon.
var ch: InfantryCharacter
var frames := 0
var probes := {}
func _initialize() -> void:
	var lo := InfantryLoadout.by_id(OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "NATO_w_glock_17")
	var root := Node3D.new()
	get_root().add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.5, 3)
	ch = InfantryCharacter.new()
	root.add_child(ch)
	ch.setup(lo, 0)
	if OS.get_cmdline_user_args().size() > 1:
		var wd := load("res://assets/combat/weapons/%s.tres" % OS.get_cmdline_user_args()[1]) as WeaponDef
		ch.show_secondary(true, wd.held_scene(), wd.held_piece)
	ch.alert = true
	ch.aim_point = Vector3(0, 1.5, -60)
	for b in ["RightHand", "LeftHand", "Head"]:
		var ba := BoneAttachment3D.new()
		ba.bone_name = b
		ch.skeleton.add_child(ba)
		probes[b] = ba
func _process(_d: float) -> bool:
	frames += 1
	if frames == 60:
		var g := ch._grip
		print("grip: has_weapon=", g.has_weapon, " eye_local=", g.eye_local, " fwd=", g.head_fwd_local, " aim_w=", g.aim_w, " support_delta=", g.support_delta, " aim_eye=", g.aim_eye)
		print("modifier active=", g.active, " influence=", g.influence, " parent=", g.get_parent().name, " children order=", ch.skeleton.get_children().map(func(n): return n.name))
		var w := (ch._held_secondary if ch.secondary_shown() else ch._weapon_root_node()).global_transform
		var head: Transform3D = probes.Head.global_transform
		var eye := head * g.eye_local
		print("eye off sight: ", eye.distance_to(w * g.aim_eye), " look vs bore deg: ", rad_to_deg((head.basis * g.head_fwd_local).angle_to(w.basis * Vector3.FORWARD)))
		print("pose head: ", ch.skeleton.get_bone_global_pose(ch.skeleton.find_bone("Head")).origin, " attach head: ", ch.skeleton.global_transform.affine_inverse() * head.origin)
		print("arm reach: ", ch.skeleton.get_bone_global_pose(ch.skeleton.find_bone("RightHand")).origin)
		return true
	return false

## VISUAL-03: turns the upper body of an infantry character towards its aim point.
##
## The Aim clip holds the rifle shouldered straight ahead of the body; this modifier, run after the AnimationTree,
## spreads the remaining yaw and pitch towards the target over Spine, Chest and UpperChest (the arms, the head and the
## rifle follow as their children), so a soldier aims where its AI aims without a clip per direction. Its influence is
## the character's aim blend, so it does nothing while the rifle is lowered.
class_name InfantryAimModifier
extends SkeletonModifier3D

## Wanted rotation (radians) relative to the body: yaw + = to the character's left, pitch + = up.
var yaw := 0.0
var pitch := 0.0

const BONES := ["Spine", "Chest", "UpperChest"]
const SHARES := [0.30, 0.35, 0.35]
var _ids := PackedInt32Array()


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or (absf(yaw) < 1e-4 and absf(pitch) < 1e-4):
		return
	if _ids.is_empty():
		for n in BONES:
			_ids.append(sk.find_bone(n))
	# Skeleton space: Y up, the character faces -Z, +X is its right.
	for i in _ids.size():
		var b := _ids[i]
		if b < 0:
			continue
		var q := Quaternion(Vector3.UP, yaw * SHARES[i]) * Quaternion(Vector3.RIGHT, pitch * SHARES[i])
		var g := sk.get_bone_global_pose(b)
		sk.set_bone_global_pose(b, Transform3D(Basis(q) * g.basis, g.origin))

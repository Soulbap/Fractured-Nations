## ASSET-INTEGRATION-01: the aiming hold - eye on the sight line, hands on the held weapon's own grips.
##
## The clips (VISUAL-03, char_anim.weapon_layer) hold the shared rifle with the cheek welded towards its sight line, but
## the head ends up tipped down over the receiver: seen from outside the soldier looks into the weapon, not along it. And
## every weapon other than the shared rifle sits in that rifle's hold: the support hand on the rifle's handguard, a pistol
## at the shoulder, a launcher's offset sight nowhere near the eye. Run after the aim and flinch modifiers, while the weapon
## is raised (aim_w), this modifier
##  1. turns Neck and Head so the head looks along the bore (the eyes are fixed in the head: this is what "looking down
##     the sight" is),
##  2. moves the weapon so that its own aiming eye (InfantryEquipment.aim_eye: sight line x / height and eye relief) is at
##     the right eye - a pistol goes out to arm's length, a launcher's sight on the left of its tube comes to the eye - and
##  3. solves both arms onto the moved weapon: the firing hand keeps its grip, the support hand goes from the rifle's
##     handguard (STD_SUPPORT) to the weapon's own support point (GRIP_Support marker or InfantryEquipment.support_grip),
##     keeping its orientation to the weapon.
## The arms are analytic two-bone solves that keep the clip's elbow plane. Presentation only: nothing reads it back (first
## person lays the same weapon's sight line on the camera, Viewmodel).
class_name InfantryGripIK
extends SkeletonModifier3D

## The shared rifle's support-hand point in weapon space (Godot axes, origin at the pistol grip, -Z muzzle).
const STD_SUPPORT := Vector3(0.0, 0.074, -0.165)
const STD_EYE := Vector3(0.0, 0.172, 0.24)
## The weapon is never moved further than this from where the clip holds it (m).
const MAX_SHIFT := 0.40
## Share of the head turn taken by the neck (the head takes the rest).
const NECK_SHARE := 0.35

## The held weapon's aiming eye and its extra hold shift (weapon space), the support hand's move from STD_SUPPORT.
var aim_eye := STD_EYE
var hold_shift := Vector3.ZERO
var support_delta := Vector3.ZERO
var has_weapon := false
## Set by the character every frame: the aim blend (0..1) and the support hand's weight (0 while reloading).
var aim_w := 0.0
var support_w := 1.0
## Rest correction of the attachment bones (InfantryCharacter._att_correction): ATT_Weapon pose x this = weapon space.
var att_corr := Basis.IDENTITY
## The right eye and the look direction in the Head bone's space (InfantryCharacter measures them on the rig).
var eye_local := Vector3.INF
var head_fwd_local := Vector3.ZERO

## The weapon's last move in the hands (m, skeleton space; diagnostics).
var last_shift := Vector3.ZERO
var _ids := {}


## Configures the modifier for a held weapon piece (null: nothing held). support: the piece's GRIP_Support marker
## position (weapon space), or INF when it has none.
func configure(piece: InfantryEquipment, support: Vector3) -> void:
	has_weapon = piece != null
	aim_eye = piece.aim_eye if piece else STD_EYE
	hold_shift = piece.hold_shift if piece else Vector3.ZERO
	support_delta = Vector3.ZERO
	if piece == null:
		return
	var grip := piece.support_grip if piece.support_grip != Vector3.ZERO else support
	if grip.is_finite() and (grip - STD_SUPPORT).length() >= 0.01:
		support_delta = grip - STD_SUPPORT


func holding() -> bool:
	return has_weapon and eye_local.is_finite()


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or not holding() or (aim_w < 0.01 and support_delta == Vector3.ZERO):
		return
	if _ids.is_empty():
		for n in ["ATT_Weapon", "Neck", "Head", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand"]:
			_ids[n] = sk.find_bone(n)
		if _ids.values().has(-1):
			push_warning("InfantryGripIK: rig lacks a neck, arm or weapon bone")
	if _ids.values().has(-1):
		return
	var w := sk.get_bone_global_pose(_ids.ATT_Weapon) * Transform3D(att_corr, Vector3.ZERO)
	var moved := w
	if aim_w >= 0.01:
		# 1. the head looks along the bore
		var bore := (w.basis * Vector3.FORWARD).normalized()
		var h := sk.get_bone_global_pose(_ids.Head)
		var f := (h.basis * head_fwd_local).normalized()
		var turn := Quaternion.IDENTITY.slerp(Quaternion(f, bore), aim_w)
		var qn := Quaternion.IDENTITY.slerp(turn, NECK_SHARE)
		var gn := sk.get_bone_global_pose(_ids.Neck)
		sk.set_bone_global_pose(_ids.Neck, Transform3D(Basis(qn) * gn.basis, gn.origin))
		h = sk.get_bone_global_pose(_ids.Head)
		var f2 := (h.basis * head_fwd_local).normalized()
		var qh := Quaternion.IDENTITY.slerp(Quaternion(f2, bore), aim_w)
		sk.set_bone_global_pose(_ids.Head, Transform3D(Basis(qh) * h.basis, h.origin))
		# 2. the weapon's aiming eye to the right eye
		var eye := sk.get_bone_global_pose(_ids.Head) * eye_local
		var shift := (eye - w * aim_eye) * aim_w + w.basis * (hold_shift * aim_w)
		if shift.length() > MAX_SHIFT:
			shift = shift.normalized() * MAX_SHIFT
		last_shift = shift
		moved = Transform3D(w.basis, w.origin + shift)
	# 3. both hands onto the moved weapon
	var to_moved := moved * w.affine_inverse()
	var left := sk.get_bone_global_pose(_ids.LeftHand)
	if not moved.origin.is_equal_approx(w.origin):
		_solve(sk, _ids.RightUpperArm, _ids.RightLowerArm, _ids.RightHand, to_moved * sk.get_bone_global_pose(_ids.RightHand))
	if support_w > 0.001:
		var target := moved * Transform3D(Basis.IDENTITY, support_delta) * w.affine_inverse() * left
		_solve(sk, _ids.LeftUpperArm, _ids.LeftLowerArm, _ids.LeftHand, left.interpolate_with(target, support_w))


## Two-bone solve (skeleton space): the hand onto `target` (position and orientation), the elbow staying in the plane
## the clip put it in.
static func _solve(sk: Skeleton3D, upper: int, lower: int, hand: int, target: Transform3D) -> void:
	var gu := sk.get_bone_global_pose(upper)
	var a := gu.origin
	var b := sk.get_bone_global_pose(lower).origin
	var c := sk.get_bone_global_pose(hand).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to_t := target.origin - a
	if l1 < 1e-4 or l2 < 1e-4 or to_t.length() < 1e-4:
		return
	var dir := to_t.normalized()
	var dist := clampf(to_t.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	var pole := (b - a) - dir * (b - a).dot(dir)
	if pole.length_squared() < 1e-8:
		pole = (c - a).cross(dir).cross(dir)
		if pole.length_squared() < 1e-8:
			return
	pole = pole.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var elbow := a + dir * (l1 * cos_a) + pole * (l1 * sqrt(1.0 - cos_a * cos_a))
	var r1 := Quaternion((b - a).normalized(), (elbow - a).normalized())
	sk.set_bone_global_pose(upper, Transform3D(Basis(r1) * gu.basis, a))
	var gl := sk.get_bone_global_pose(lower)
	var c1 := sk.get_bone_global_pose(hand).origin
	var reach := a + dir * dist
	var r2 := Quaternion((c1 - gl.origin).normalized(), (reach - gl.origin).normalized())
	sk.set_bone_global_pose(lower, Transform3D(Basis(r2) * gl.basis, gl.origin))
	sk.set_bone_global_pose(hand, Transform3D(target.basis.orthonormalized(), reach))

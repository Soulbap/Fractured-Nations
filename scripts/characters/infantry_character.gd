## The shared modern infantry character (CHARACTER-01): one rig, one body, one animation
## set, dressed by a data-driven InfantryLoadout.
##
## Assembly (setup()): instance the rig (Skeleton3D + base body + AnimationPlayer), move
## every skinned piece's meshes onto that skeleton (skins bind by bone name), hang rigid
## pieces on BoneAttachment3D nodes (ATT_* bones) or on mount nodes of other pieces
## (weapon accessories), hide body regions covered by clothing, swap all materials for
## the shared InfantryMaterials library (faction camo + patch colour) and give every
## <piece>_LOD0/1/2 mesh its visibility range.
##
## Animation is gameplay-driven and in place: the owner's velocity (body) is converted to
## a local move vector that drives a BlendTree (idle <-> 2D locomotion blend space, stand
## <-> crouch). Locomotion clips are one gait cycle each and play at the rate that makes
## the authored stride match the actual speed, so feet stay planted at any speed.
class_name InfantryCharacter
extends Node3D

const RIG_SCENE := preload("res://assets/characters/infantry/rig/infantry_rig.glb")
const META_PATH := "res://assets/characters/infantry/animation_meta.json"

## LOD switch distances (m from the camera): LOD0 close/FPS, LOD1 medium, LOD2 far RTS.
const LOD_DISTANCES := [0.0, 12.0, 28.0]
const LOD_MARGIN := 1.0
## Beyond this distance the animation is advanced every ANIM_FAR_STEP frames.
const ANIM_FAR_DISTANCE := 45.0
const ANIM_FAR_STEP := 3
## Gait table (speed m/s -> stride m per cycle), mirrors animation_meta.json "gait".
const GAIT_FALLBACK := {"Walk": [1.40, 1.00], "Jog": [3.00, 0.78], "Run": [4.50, 0.70], "Sprint": [7.50, 0.62], "CrouchWalk": [1.20, 1.05]}
const LOCO_CLIP_S := 32.0 / 30.0

@export var loadout: InfantryLoadout
@export var faction := 0
## Project setting that switches soldiers between this character and the WORLD-CORE-01
## placeholder model (true by default).
const SETTING := "fractured_nations/characters/use_infantry_character"

## Body whose velocity drives the animation (CharacterBody3D). Without one, debug_velocity
## (world space) is used, which the validation scenes set directly.
var body: CharacterBody3D
var debug_velocity := Vector3.ZERO
var crouched := false

var rig: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var pieces := {}            # equipment id -> Array[Node3D] (meshes or attached roots)
var mounts := {}            # "slot:node" -> Node3D mount point
var attachments := {}       # bone name -> BoneAttachment3D
var lod_meshes: Array[MeshInstance3D] = []

var _move := Vector2.ZERO       # smoothed local velocity (x right, y forward), m/s
var _move_amount := 0.0
var _crouch_amount := 0.0
var _last_yaw := NAN
var _yaw_rate := 0.0
var _frame_skip := 0
var _skip_delta := 0.0

static var _tree_root: AnimationNodeBlendTree
static var _strides := {}       # speed -> stride table (sorted speeds) for stand / crouch
static var _loops_set := false
## Accumulated animation update time (usec) of all characters, for profiling.
static var anim_usec := 0


static func enabled() -> bool:
	return ProjectSettings.get_setting(SETTING, true) and not "--old-soldier" in OS.get_cmdline_user_args()


func _ready() -> void:
	if anim_tree and rig:
		_apply_params(0.0, true)
		anim_tree.advance(0.0)


func setup(p_loadout: InfantryLoadout, p_faction: int, merge_lods := true) -> void:
	loadout = p_loadout
	faction = p_faction
	_clear()
	rig = RIG_SCENE.instantiate()
	rig.name = "Rig"
	add_child(rig)
	skeleton = _find(rig, func(n: Node) -> bool: return n is Skeleton3D)
	anim_player = _find(rig, func(n: Node) -> bool: return n is AnimationPlayer)
	var hidden := {}
	for it in loadout.items:
		for r in it.hides_body:
			hidden[r] = true
	for mi in _meshes(rig):
		var region := String(mi.name).trim_prefix("Char_").get_slice("_", 0)
		if hidden.has(region):
			mi.free()
		else:
			_register_mesh(mi)
	# Skinned and skeleton-rigid pieces first, then pieces mounted on other pieces.
	for pass_i in 2:
		for it in loadout.items:
			var mounted := it.attach.contains(":")
			if (pass_i == 0) == mounted:
				continue
			_add_piece(it)
	if merge_lods:
		_merge_distance_lods()
	_setup_animation()


## Replaces the per-piece LOD1/LOD2 meshes by the loadout's cached merged meshes.
func _merge_distance_lods() -> void:
	var merged := InfantryLodMerge.get_merged(self)
	var keep: Array[MeshInstance3D] = []
	for mi in lod_meshes:
		var n := String(mi.name)
		if n.ends_with("_LOD1") or n.ends_with("_LOD2"):
			mi.get_parent().remove_child(mi)
			mi.free()
		else:
			keep.append(mi)
	lod_meshes = keep
	for lod in [1, 2]:
		var mi := MeshInstance3D.new()
		mi.name = "Merged_LOD%d" % lod
		mi.mesh = merged["lod%d" % lod]
		mi.skin = merged.skin
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.visibility_range_begin = LOD_DISTANCES[lod]
		mi.visibility_range_begin_margin = LOD_MARGIN
		mi.visibility_range_end = LOD_DISTANCES[lod + 1] if lod + 1 < LOD_DISTANCES.size() else 0.0
		mi.visibility_range_end_margin = LOD_MARGIN if lod + 1 < LOD_DISTANCES.size() else 0.0
		lod_meshes.append(mi)


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	pieces.clear()
	mounts.clear()
	attachments.clear()
	lod_meshes.clear()


func _add_piece(it: InfantryEquipment) -> void:
	if it.scene == null:
		push_warning("InfantryCharacter: piece %s has no scene" % it.id)
		return
	var inst: Node3D = it.scene.instantiate()
	var nodes: Array = []
	if it.mode == InfantryEquipment.Mode.SKINNED:
		for mi in _meshes(inst):
			mi.owner = null
			mi.get_parent().remove_child(mi)
			skeleton.add_child(mi)
			mi.skeleton = NodePath("..")
			_register_mesh(mi)
			nodes.append(mi)
		inst.free()
	else:
		var parent: Node3D = _attach_point(it.attach)
		if parent == null:
			push_warning("InfantryCharacter: no attach point %s for %s" % [it.attach, it.id])
			inst.free()
			return
		parent.add_child(inst)
		if not it.attach.contains(":"):
			# Rigid pieces are modelled in attachment space (character axes at the rest
			# pose). Undo the attachment bone's rest orientation so the piece keeps them.
			inst.transform = Transform3D(_att_correction(), Vector3.ZERO)
		for mi in _meshes(inst):
			_register_mesh(mi)
		for m in _find_all(inst, func(n: Node) -> bool: return String(n.name).begins_with("ATT_") or String(n.name).begins_with("GRIP_")):
			mounts["%s:%s" % [it.slot, m.name]] = m
		nodes.append(inst)
	pieces[it.id] = nodes


func _attach_point(spec: String) -> Node3D:
	if spec.contains(":"):
		return mounts.get(spec)
	if attachments.has(spec):
		return attachments[spec]
	if skeleton.find_bone(spec) < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.name = "At_" + spec
	ba.bone_name = spec
	skeleton.add_child(ba)
	attachments[spec] = ba
	return ba


## Rest basis of the character-aligned attachment bones (identity in Blender); its inverse
## maps a piece authored in character axes onto any ATT_* bone (the weapon bone too:
## its rest frame is the weapon's, built with the same bone-axis convention).
func _att_correction() -> Basis:
	var i := skeleton.find_bone("ATT_Head")
	return skeleton.get_bone_global_rest(i).basis.orthonormalized().inverse() if i >= 0 else Basis.IDENTITY


func _register_mesh(mi: MeshInstance3D) -> void:
	var n := String(mi.name)
	var lod := 0
	if n.contains("_LOD"):
		lod = int(n.get_slice("_LOD", 1))
	mi.visibility_range_begin = LOD_DISTANCES[lod]
	mi.visibility_range_begin_margin = LOD_MARGIN if lod > 0 else 0.0
	mi.visibility_range_end = LOD_DISTANCES[lod + 1] if lod + 1 < LOD_DISTANCES.size() else 0.0
	mi.visibility_range_end_margin = LOD_MARGIN if lod + 1 < LOD_DISTANCES.size() else 0.0
	var mesh := mi.mesh
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat:
			mi.set_surface_override_material(s, InfantryMaterials.get_material(mat.resource_name, faction))
	lod_meshes.append(mi)


# ------------------------------------------------------------------------------ animation


func _setup_animation() -> void:
	_prepare_shared()
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	add_child(anim_tree)
	anim_tree.tree_root = _tree_root
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim_tree.active = true
	_set_loops()
	if is_inside_tree():
		_apply_params(0.0, true)
		anim_tree.advance(0.0)


static func _prepare_shared() -> void:
	if _tree_root:
		return
	var gait: Dictionary = GAIT_FALLBACK.duplicate()
	if FileAccess.file_exists(META_PATH):
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
		if meta is Dictionary and meta.has("gait"):
			for k in meta.gait:
				gait[k] = [float(meta.gait[k].speed), float(meta.gait[k].period)]
	_strides = {
		"stand": [[gait.Walk[0], gait.Walk[0] * gait.Walk[1]], [gait.Jog[0], gait.Jog[0] * gait.Jog[1]], [gait.Run[0], gait.Run[0] * gait.Run[1]],
				[gait.Sprint[0], gait.Sprint[0] * gait.Sprint[1]]],
		"crouch": [[gait.CrouchWalk[0], gait.CrouchWalk[0] * gait.CrouchWalk[1]]],
	}
	var walk: float = gait.Walk[0]
	var jog: float = gait.Jog[0]
	var run: float = gait.Run[0]
	var cw: float = gait.CrouchWalk[0]
	var loco := AnimationNodeBlendSpace2D.new()
	loco.sync = true
	loco.min_space = Vector2(-run, -run)
	loco.max_space = Vector2(run, gait.Sprint[0])
	for p in [["Walk_F", Vector2(0, walk)], ["Walk_B", Vector2(0, -walk)], ["Walk_L", Vector2(-walk, 0)], ["Walk_R", Vector2(walk, 0)],
			["Jog_F", Vector2(0, jog)], ["Jog_B", Vector2(0, -jog)], ["Jog_L", Vector2(-jog, 0)], ["Jog_R", Vector2(jog, 0)],
			["Run_F", Vector2(0, run)], ["Run_B", Vector2(0, -run)], ["Run_L", Vector2(-run, 0)], ["Run_R", Vector2(run, 0)],
			["Sprint_F", Vector2(0, gait.Sprint[0])]]:
		loco.add_blend_point(_anim(p[0]), p[1])
	var cloco := AnimationNodeBlendSpace2D.new()
	cloco.sync = true
	cloco.min_space = Vector2(-cw, -cw)
	cloco.max_space = Vector2(cw, cw)
	for p in [["CrouchWalk_F", Vector2(0, cw)], ["CrouchWalk_B", Vector2(0, -cw)], ["CrouchWalk_L", Vector2(-cw, 0)], ["CrouchWalk_R", Vector2(cw, 0)]]:
		cloco.add_blend_point(_anim(p[0]), p[1])
	var t := AnimationNodeBlendTree.new()
	t.add_node("idle", _anim("Idle"), Vector2(0, 0))
	t.add_node("cidle", _anim("Crouch_Idle"), Vector2(0, 300))
	t.add_node("loco", loco, Vector2(0, 100))
	t.add_node("cloco", cloco, Vector2(0, 400))
	t.add_node("scale", AnimationNodeTimeScale.new(), Vector2(200, 100))
	t.add_node("cscale", AnimationNodeTimeScale.new(), Vector2(200, 400))
	t.add_node("move", AnimationNodeBlend2.new(), Vector2(400, 50))
	t.add_node("cmove", AnimationNodeBlend2.new(), Vector2(400, 350))
	t.add_node("crouch", AnimationNodeBlend2.new(), Vector2(600, 200))
	t.connect_node("scale", 0, "loco")
	t.connect_node("cscale", 0, "cloco")
	t.connect_node("move", 0, "idle")
	t.connect_node("move", 1, "scale")
	t.connect_node("cmove", 0, "cidle")
	t.connect_node("cmove", 1, "cscale")
	t.connect_node("crouch", 0, "move")
	t.connect_node("crouch", 1, "cmove")
	t.connect_node("output", 0, "crouch")
	_tree_root = t


static func _anim(clip: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	return a


func _set_loops() -> void:
	if _loops_set or anim_player == null:
		return
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		for n in lib.get_animation_list():
			lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_loops_set = true


## Stride (m per gait cycle) at speed v by linear interpolation of the authored clips.
static func stride_at(v: float, table: Array) -> float:
	if v <= table[0][0]:
		return table[0][1]
	for i in range(1, table.size()):
		if v <= table[i][0]:
			var t: float = (v - table[i - 1][0]) / (table[i][0] - table[i - 1][0])
			return lerpf(table[i - 1][1], table[i][1], t)
	return table[-1][1] * v / table[-1][0]


func _process(delta: float) -> void:
	if anim_tree == null or not anim_tree.active:
		return
	_set_loops()
	_apply_params(delta, false)
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_squared_to(global_position) > ANIM_FAR_DISTANCE * ANIM_FAR_DISTANCE
	_skip_delta += delta
	_frame_skip += 1
	if not far or _frame_skip >= ANIM_FAR_STEP:
		var t0 := Time.get_ticks_usec()
		anim_tree.advance(_skip_delta)
		anim_usec += Time.get_ticks_usec() - t0
		_skip_delta = 0.0
		_frame_skip = 0


## GAMEPLAY-03D: the secondary weapon (the launcher) in the hands instead of the rifle: the rifle, its accessories and the
## launcher carried on the back are hidden, `scene` is held at the weapon bone; false restores the loadout's look. Only the
## full-detail meshes change (the merged distance LODs keep the carried look).
var _held_secondary: Node3D


func show_secondary(on: bool, scene: PackedScene) -> void:
	if on == (_held_secondary != null) or skeleton == null:
		return
	for it in loadout.items:
		if it.slot == "weapon" or it.slot == "back_weapon" or it.attach.begins_with("weapon:"):
			for n: Node3D in pieces.get(it.id, []):
				if is_instance_valid(n):
					n.visible = not on
	if on and scene:
		var parent := _attach_point("ATT_Weapon")
		if parent:
			_held_secondary = scene.instantiate()
			_held_secondary.name = "HeldSecondary"
			parent.add_child(_held_secondary)
			_held_secondary.transform = Transform3D(_att_correction(), Vector3.ZERO)
			# The character's materials; the closest LOD only, at every distance (a small piece; it is held briefly).
			for mi in _meshes(_held_secondary):
				var n := String(mi.name)
				mi.visible = not n.contains("_LOD") or n.ends_with("_LOD0")
				for s in mi.mesh.get_surface_count():
					var mat := mi.mesh.surface_get_material(s)
					if mat:
						mi.set_surface_override_material(s, InfantryMaterials.get_material(mat.resource_name, faction))
	elif not on and _held_secondary:
		_held_secondary.queue_free()
		_held_secondary = null


func secondary_shown() -> bool:
	return _held_secondary != null


## Muzzle mount of the held weapon (null when the loadout has no weapon with one).
func muzzle() -> Node3D:
	return mounts.get("weapon:ATT_Muzzle")


func world_velocity() -> Vector3:
	return body.velocity if body else debug_velocity


func _apply_params(delta: float, snap: bool) -> void:
	var v := world_velocity()
	v.y = 0.0
	var local := global_basis.orthonormalized().inverse() * v
	var target := Vector2(local.x, -local.z)
	# Turning on the spot: step sideways in the turn direction.
	var yaw := global_rotation.y
	if not is_nan(_last_yaw) and delta > 0.0:
		_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, clampf(delta * 10.0, 0.0, 1.0))
	_last_yaw = yaw
	if target.length() < 0.3 and absf(_yaw_rate) > 1.2:
		target = Vector2(-signf(_yaw_rate) * 0.8, 0.0)
	var k := 1.0 if snap else clampf(delta * 8.0, 0.0, 1.0)
	_move = _move.lerp(target, k)
	var speed := _move.length()
	var moving := clampf((speed - 0.15) / 0.6, 0.0, 1.0)
	_move_amount = lerpf(_move_amount, moving, 1.0 if snap else clampf(delta * 10.0, 0.0, 1.0))
	_crouch_amount = move_toward(_crouch_amount, 1.0 if crouched else 0.0, 1.0 if snap else delta * 4.0)
	var table: Array = _strides.crouch if crouched else _strides.stand
	var min_speed: float = table[0][0]
	var dir := _move.normalized() if speed > 0.01 else Vector2(0, 1)
	var pos := dir * maxf(speed, min_speed)
	# Playback rate: gait cycles per second x clip length, so the stride matches the speed.
	var cycles := maxf(speed, 0.35) / stride_at(maxf(speed, min_speed), table)
	anim_tree.set("parameters/loco/blend_position", pos)
	anim_tree.set("parameters/cloco/blend_position", dir * maxf(speed, _strides.crouch[0][0]))
	anim_tree.set("parameters/scale/scale", cycles * LOCO_CLIP_S)
	anim_tree.set("parameters/cscale/scale", maxf(speed, 0.35) / stride_at(maxf(speed, 0.0), _strides.crouch) * LOCO_CLIP_S)
	anim_tree.set("parameters/move/blend_amount", _move_amount)
	anim_tree.set("parameters/cmove/blend_amount", _move_amount)
	anim_tree.set("parameters/crouch/blend_amount", _crouch_amount)


## Current animation state for tests/diagnostics.
func anim_state() -> Dictionary:
	return {"move": _move, "move_amount": _move_amount, "crouch": _crouch_amount,
		"rate": anim_tree.get("parameters/scale/scale") if anim_tree else 0.0}


# ------------------------------------------------------------------------------ helpers


func triangle_count(lod := 0) -> int:
	var tris := 0
	for mi in lod_meshes:
		if not is_instance_valid(mi) or not mi.visible:
			continue
		var n := String(mi.name)
		var l := int(n.get_slice("_LOD", 1)) if n.contains("_LOD") else 0
		if l != lod:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return tris


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in _find_all(root, func(x: Node) -> bool: return x is MeshInstance3D):
		out.append(n)
	return out


static func _find(root: Node, pred: Callable) -> Node:
	if pred.call(root):
		return root
	for c in root.get_children():
		var r := _find(c, pred)
		if r:
			return r
	return null


static func _find_all(root: Node, pred: Callable, out: Array = []) -> Array:
	if pred.call(root):
		out.append(root)
	for c in root.get_children():
		_find_all(c, pred, out)
	return out

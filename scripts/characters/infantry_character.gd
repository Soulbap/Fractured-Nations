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
## Clip set (VISUAL-03: motion capture + weapon layer, see tools/blender/character/char_anim.py): relaxed / ready idle,
## walk, brisk walk, jog, run, sprint, crouch, turn-in-place clips; aim (upper body, turned to the target by
## InfantryAimModifier), fire and reload as upper-body layers, all blended over short times so nothing snaps. A weapon's
## detachable magazine (<weapon>_Mag_LOD* meshes) hangs on the ATT_Magazine bone, which the reload carries in the hand.
class_name InfantryCharacter
extends Node3D

const ASSET_ROOT := "res://assets/characters/infantry/"
## Bones the upper-body layers (aim, fire, reload) drive; the legs and pelvis stay with locomotion.
const UPPER_BONES := ["Spine", "Chest", "UpperChest", "Neck", "Head"]
const UPPER_SIDE := ["Shoulder", "UpperArm", "LowerArm", "Hand"]
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Little"]

## LOD switch distances (m from the camera): LOD0 close/FPS, LOD1 medium, LOD2 far RTS.
const LOD_DISTANCES := [0.0, 12.0, 28.0]
## GAMEPLAY-05: the LODs cross-fade over this band (VISIBILITY_RANGE_FADE_SELF). Each mesh measures its range from its own
## AABB centre (boots, jacket, helmet and the merged mesh sit at different heights), so plain hysteresis left a gap at the
## switch: a soldier 12 m from the camera drew no mesh at all (two of eight invisible in the squad close-up).
const LOD_MARGIN := 1.5
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
## VISUAL-03 layer inputs (set by the owner every frame): ready stance, aim point (INF = rifle not raised), reloading.
var alert := false
var aim_point := Vector3.INF
var reloading := false
## COMBAT-01 posture from the record (set_posture): from, to (Posture.STAND / CROUCH / PRONE) and the change's progress.
var posture_from := 0
var posture_to := 0
var posture_k := 1.0
var _prone_amount := 0.0
var _trans_amount := 0.0
static var _has_prone := false
static var _prone_len := {}
static var _crawl_stride := 1.08
var _alert_amount := 0.0
var _aim_amount := 0.0
var _turn_amount := 0.0
var _aim_mod: InfantryAimModifier
var _flinch_mod: InfantryAimModifier
## ASSET-INTEGRATION-01: the hands on a weapon held differently from the shared rifle (pistol, launcher, MG).
var _grip: InfantryGripIK
var _support_amount := 1.0
var _flinch := Vector2.ZERO
var _was_reloading := false

static var _tree_root: AnimationNodeBlendTree
static var _rig_scene: PackedScene
static var _turn_rate := 1.5      # rad/s the turn clips turn at (meta)
static var _lat_stride := 0.0     # stride (m per cycle) of the sideways clips; 0 = use the forward table
static var _strides := {}       # speed -> stride table (sorted speeds) for stand / crouch
static var _loops_set := false
## Accumulated animation update time (usec) of all characters, for profiling.
static var anim_usec := 0


static func rig_scene() -> PackedScene:
	if _rig_scene == null:
		_rig_scene = load(ASSET_ROOT + "rig/infantry_rig.glb")
	return _rig_scene


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
	rig = rig_scene().instantiate()
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
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		lod_meshes.append(mi)


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	pieces.clear()
	mounts.clear()
	attachments.clear()
	lod_meshes.clear()
	# ASSET-INTEGRATION-01: a rebuilt character holds nothing until the owner shows the secondary again
	_held_secondary = null
	_held_scene = null


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
		if it.attach == "ATT_Weapon":
			var mag := _hang_magazine(inst)
			if mag:
				nodes.append(mag)
	pieces[it.id] = nodes


## Moves the weapon's detachable magazine meshes (<weapon>_Mag_LOD*) onto the ATT_Magazine bone, keeping their place:
## the bone rests on ATT_Weapon, and the reload clip carries it in the support hand. Returns the holder (null: none).
func _hang_magazine(weapon: Node3D) -> Node3D:
	var mags := _find_all(weapon, func(n: Node) -> bool: return n is MeshInstance3D and String(n.name).contains("_Mag_LOD"))
	var bone := _attach_point("ATT_Magazine")
	if mags.is_empty() or bone == null:
		return null
	var holder := Node3D.new()
	holder.name = "Magazine"
	bone.add_child(holder)
	holder.transform = weapon.transform
	for mi: Node3D in mags:
		var xf := mi.transform
		var n := mi.get_parent()
		while n != weapon:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		mi.owner = null
		mi.get_parent().remove_child(mi)
		holder.add_child(mi)
		mi.transform = xf
	return holder


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
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var mesh := mi.mesh
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat:
			mi.set_surface_override_material(s, InfantryMaterials.get_material(mat.resource_name, faction))
	lod_meshes.append(mi)


# ------------------------------------------------------------------------------ animation


func _setup_animation() -> void:
	_prepare_shared(anim_player)
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	add_child(anim_tree)
	anim_tree.tree_root = _tree_root
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim_tree.active = true
	_set_loops()
	_aim_mod = InfantryAimModifier.new()
	_aim_mod.name = "AimModifier"
	_aim_mod.influence = 0.0
	skeleton.add_child(_aim_mod)
	# COMBAT-01: a hit flinch on the same spine bones, independent of the aim (decays in ~0.3 s).
	_flinch_mod = InfantryAimModifier.new()
	_flinch_mod.name = "FlinchModifier"
	_flinch_mod.influence = 1.0
	skeleton.add_child(_flinch_mod)
	# ASSET-INTEGRATION-01: last, so it holds the weapon where the aimed and flinched pose put it.
	_grip = InfantryGripIK.new()
	_grip.name = "GripIK"
	_grip.att_corr = _att_correction()
	_measure_eye()
	var hb := skeleton.find_bone("Head")
	if hb >= 0 and _eye_head.is_finite():
		var rest := skeleton.get_bone_global_rest(hb)
		_grip.eye_local = _eye_head
		# the character faces -Z in skeleton space: the head's look direction at rest
		_grip.head_fwd_local = rest.basis.inverse() * Vector3.FORWARD
	skeleton.add_child(_grip)
	_configure_grip(loadout.item_in_slot("weapon"), _weapon_root_node())
	if is_inside_tree():
		_apply_params(0.0, true)
		anim_tree.advance(0.0)


static func _prepare_shared(player: AnimationPlayer) -> void:
	if _tree_root:
		return
	var gait: Dictionary = GAIT_FALLBACK.duplicate()
	var meta_path := ASSET_ROOT + "animation_meta.json"
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path)) if FileAccess.file_exists(meta_path) else null
	if meta is Dictionary and meta.has("gait"):
		for k in meta.gait:
			gait[k] = [float(meta.gait[k].speed), float(meta.gait[k].period)]
	if meta is Dictionary and meta.get("clip_meta", {}).has("Turn_L"):
		_turn_rate = maxf(0.3, absf(float(meta.clip_meta.Turn_L.get("turn_rate", 1.5))))
	if meta is Dictionary and meta.get("clip_meta", {}).has("Walk_L"):
		# the captured side steps are short: sideways the clip plays faster instead of letting the feet slide
		var lm: Dictionary = meta.clip_meta.Walk_L
		_lat_stride = float(lm.get("speed", 0.0)) * float(lm.get("period", 0.0))
	var stand := [[gait.Walk[0], gait.Walk[0] * gait.Walk[1]]]
	if gait.has("Brisk"):
		stand.append([gait.Brisk[0], gait.Brisk[0] * gait.Brisk[1]])
	for k in ["Jog", "Run", "Sprint"]:
		stand.append([gait[k][0], gait[k][0] * gait[k][1]])
	_strides = {"stand": stand, "crouch": [[gait.CrouchWalk[0], gait.CrouchWalk[0] * gait.CrouchWalk[1]]]}
	var walk: float = gait.Walk[0]
	var jog: float = gait.Jog[0]
	var run: float = gait.Run[0]
	var cw: float = gait.CrouchWalk[0]
	var loco := AnimationNodeBlendSpace2D.new()
	loco.sync = true
	loco.min_space = Vector2(-run, -run)
	loco.max_space = Vector2(run, gait.Sprint[0])
	var pts := [["Walk_F", Vector2(0, walk)], ["Walk_B", Vector2(0, -walk)], ["Walk_L", Vector2(-walk, 0)], ["Walk_R", Vector2(walk, 0)],
			["Jog_F", Vector2(0, jog)], ["Jog_B", Vector2(0, -jog)], ["Jog_L", Vector2(-jog, 0)], ["Jog_R", Vector2(jog, 0)],
			["Run_F", Vector2(0, run)], ["Run_B", Vector2(0, -run)], ["Run_L", Vector2(-run, 0)], ["Run_R", Vector2(run, 0)],
			["Sprint_F", Vector2(0, gait.Sprint[0])]]
	if gait.has("Brisk") and player.has_animation("Brisk_F"):
		pts.append(["Brisk_F", Vector2(0, gait.Brisk[0])])
	for p in pts:
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
	t.connect_node("cmove", 0, "cidle")
	t.connect_node("cmove", 1, "cscale")
	t.connect_node("move", 1, "scale")
	t.connect_node("crouch", 0, "move")
	t.connect_node("crouch", 1, "cmove")
	# Relaxed <-> ready idle, turning in place, then the upper-body layers.
	var upper := _upper_paths(player)
	t.add_node("ready", _anim("Ready_Idle"), Vector2(0, -150))
	t.add_node("alert", AnimationNodeBlend2.new(), Vector2(200, -100))
	t.connect_node("alert", 0, "idle")
	t.connect_node("alert", 1, "ready")
	t.add_node("turn_l", _anim("Turn_L"), Vector2(0, -300))
	t.add_node("turn_r", _anim("Turn_R"), Vector2(0, -400))
	t.add_node("tscale_l", AnimationNodeTimeScale.new(), Vector2(150, -300))
	t.add_node("tscale_r", AnimationNodeTimeScale.new(), Vector2(150, -400))
	t.connect_node("tscale_l", 0, "turn_l")
	t.connect_node("tscale_r", 0, "turn_r")
	var turn := AnimationNodeBlend3.new()
	t.add_node("turn", turn, Vector2(300, -200))
	t.connect_node("turn", 0, "tscale_l")
	t.connect_node("turn", 1, "alert")
	t.connect_node("turn", 2, "tscale_r")
	t.connect_node("move", 0, "turn")
	t.add_node("aim_pose", _anim("Aim"), Vector2(600, 400))
	var aim := AnimationNodeBlend2.new()
	_filter(aim, upper)
	t.add_node("aim", aim, Vector2(800, 200))
	t.connect_node("aim", 0, "crouch")
	t.connect_node("aim", 1, "aim_pose")
	var fire := AnimationNodeOneShot.new()
	fire.fadein_time = 0.02
	fire.fadeout_time = 0.08
	_filter(fire, upper)
	t.add_node("fire_pose", _anim("Fire"), Vector2(800, 400))
	t.add_node("fire", fire, Vector2(1000, 200))
	t.connect_node("fire", 0, "aim")
	t.connect_node("fire", 1, "fire_pose")
	var reload := AnimationNodeOneShot.new()
	reload.fadein_time = 0.2
	reload.fadeout_time = 0.25
	_filter(reload, upper)
	t.add_node("reload_pose", _anim("Reload"), Vector2(1000, 400))
	t.add_node("reload", reload, Vector2(1200, 200))
	t.connect_node("reload", 0, "fire")
	t.connect_node("reload", 1, "reload_pose")
	_has_prone = player.has_animation("Prone_Idle") and player.has_animation("Stand_To_Prone")
	if _has_prone:
		_add_prone(t, player, gait)
		t.connect_node("output", 0, "prone")
	else:
		t.connect_node("output", 0, "reload")
	_tree_root = t


## COMBAT-01: the prone branch over the standing tree: prone idle <-> aim, crawl, fire one-shot, and the change of posture
## (Stand_To_Prone / Prone_To_Stand) held at the time the record's progress gives (seeked every frame, never advancing on
## its own), so the clip is exactly where the authoritative change is.
static func _add_prone(t: AnimationNodeBlendTree, player: AnimationPlayer, gait: Dictionary) -> void:
	for n in ["Stand_To_Prone", "Prone_To_Stand"]:
		_prone_len[n] = player.get_animation(n).length
	if gait.has("ProneCrawl"):
		_crawl_stride = float(gait.ProneCrawl[0]) * float(gait.ProneCrawl[1])
	t.add_node("p_idle", _anim("Prone_Idle"), Vector2(1200, 600))
	t.add_node("p_aim_pose", _anim("Prone_Aim" if player.has_animation("Prone_Aim") else "Prone_Idle"), Vector2(1200, 700))
	t.add_node("p_aim", AnimationNodeBlend2.new(), Vector2(1400, 600))
	t.connect_node("p_aim", 0, "p_idle")
	t.connect_node("p_aim", 1, "p_aim_pose")
	t.add_node("p_crawl", _anim("ProneCrawl_F" if player.has_animation("ProneCrawl_F") else "Prone_Idle"), Vector2(1200, 800))
	t.add_node("p_cscale", AnimationNodeTimeScale.new(), Vector2(1400, 800))
	t.connect_node("p_cscale", 0, "p_crawl")
	t.add_node("p_move", AnimationNodeBlend2.new(), Vector2(1600, 650))
	t.connect_node("p_move", 0, "p_aim")
	t.connect_node("p_move", 1, "p_cscale")
	var pfire := AnimationNodeOneShot.new()
	pfire.fadein_time = 0.02
	pfire.fadeout_time = 0.08
	t.add_node("p_fire_pose", _anim("Prone_Fire" if player.has_animation("Prone_Fire") else "Prone_Idle"), Vector2(1600, 800))
	t.add_node("p_fire", pfire, Vector2(1800, 650))
	t.connect_node("p_fire", 0, "p_move")
	t.connect_node("p_fire", 1, "p_fire_pose")
	for k in [["down", "Stand_To_Prone"], ["up", "Prone_To_Stand"]]:
		t.add_node("t_" + k[0], _anim(k[1]), Vector2(1600, 950 + (100 if k[0] == "up" else 0)))
		t.add_node("seek_" + k[0], AnimationNodeTimeSeek.new(), Vector2(1800, 950 + (100 if k[0] == "up" else 0)))
		t.add_node("hold_" + k[0], AnimationNodeTimeScale.new(), Vector2(2000, 950 + (100 if k[0] == "up" else 0)))
		t.connect_node("seek_" + k[0], 0, "t_" + k[0])
		t.connect_node("hold_" + k[0], 0, "seek_" + k[0])
	t.add_node("t_kind", AnimationNodeBlend2.new(), Vector2(2200, 1000))
	t.connect_node("t_kind", 0, "hold_down")
	t.connect_node("t_kind", 1, "hold_up")
	t.add_node("trans", AnimationNodeBlend2.new(), Vector2(2400, 700))
	t.connect_node("trans", 0, "p_fire")
	t.connect_node("trans", 1, "t_kind")
	t.add_node("prone", AnimationNodeBlend2.new(), Vector2(2600, 300))
	t.connect_node("prone", 0, "reload")
	t.connect_node("prone", 1, "trans")


## COMBAT-01: the record's posture (from, to, progress 0..1) - SoldierBody sets it every tick.
func set_posture(p_from: int, p_to: int, k: float) -> void:
	posture_from = p_from
	posture_to = p_to
	posture_k = k


## Track paths of the upper-body bones in the rig's clips (filters of the upper-body layers), the magazine bone too.
static func _upper_paths(player: AnimationPlayer) -> Array[NodePath]:
	var names := {"ATT_Magazine": true}
	for n in UPPER_BONES:
		names[n] = true
	for side in ["Left", "Right"]:
		for n in UPPER_SIDE:
			names[side + n] = true
		for f in FINGERS:
			for seg in ["Metacarpal", "Proximal", "Intermediate", "Distal"]:
				names[side + f + seg] = true
	var out: Array[NodePath] = []
	for clip in ["Aim", "Reload"]:
		var anim := player.get_animation(clip)
		for i in anim.get_track_count():
			var p := anim.track_get_path(i)
			if p.get_subname_count() > 0 and names.has(String(p.get_subname(0))) and not p in out:
				out.append(p)
	return out


static func _filter(node: AnimationNode, paths: Array[NodePath]) -> void:
	node.filter_enabled = true
	for p in paths:
		node.set_filter_path(p, true)


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
			# the one-shots play once
			lib.get_animation(n).loop_mode = Animation.LOOP_NONE if n in ["Fire", "Reload", "Prone_Fire", "Stand_To_Prone", "Prone_To_Stand"] \
				else Animation.LOOP_LINEAR
	_loops_set = true


## One shot (recoil) on the upper body; ignored while the rifle is not raised.
func fire() -> void:
	if anim_tree and _aim_amount > 0.3:
		anim_tree.set("parameters/%s/request" % ("p_fire" if _prone_amount > 0.5 else "fire"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## COMBAT-01: a short flinch away from a hit coming from world direction `from` (strength 0..1): the upper body twists and
## rocks back, then recovers. Presentation only (the record already took the damage).
func flinch(from: Vector3, strength := 1.0) -> void:
	var local := global_basis.orthonormalized().inverse() * from
	var side := signf(local.x) if absf(local.x) > 0.05 else 1.0
	_flinch = Vector2(-side * 0.28, 0.22 if local.z < 0.0 else -0.12) * clampf(strength, 0.2, 1.0)


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
var _held_scene: PackedScene


func show_secondary(on: bool, scene: PackedScene, piece: InfantryEquipment = null) -> void:
	if skeleton == null or (on == (_held_secondary != null) and (not on or scene == _held_scene)):
		return
	if on and _held_secondary:
		# another secondary weapon than the one held (re-equipped): swap it
		_held_secondary.queue_free()
		_held_secondary = null
	for it in loadout.items:
		if it.slot == "weapon" or it.slot == "back_weapon" or it.attach.begins_with("weapon:"):
			for n: Node3D in pieces.get(it.id, []):
				if is_instance_valid(n):
					n.visible = not on
	if on and scene:
		var parent := _attach_point("ATT_Weapon")
		if parent:
			_held_secondary = scene.instantiate()
			_held_scene = scene
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
			# ASSET-INTEGRATION-01: a held piece with its own hold (a launcher on the shoulder) gets the hands put on it.
			if piece:
				_configure_grip(piece, _held_secondary)
	elif not on and _held_secondary:
		_held_secondary.queue_free()
		_held_secondary = null
		_configure_grip(loadout.item_in_slot("weapon"), _weapon_root_node())


func secondary_shown() -> bool:
	return _held_secondary != null


func secondary_scene() -> PackedScene:
	return _held_scene if _held_secondary else null


## ASSET-INTEGRATION-01: the right eye in the Head bone's rest space, measured once on the rig's head mesh (the centre of
## the `Eye` surface's vertices on the right, +X, side; char_anim welds the same eye to the sight line in Blender).
static var _eye_head := Vector3.INF
static var _eye_measured := false


func _measure_eye() -> void:
	if _eye_measured:
		return
	_eye_measured = true
	# on a fresh rig: a loadout may have freed this character's head mesh (hides_body)
	var r: Node3D = rig_scene().instantiate()
	var head := _find(r, func(n: Node) -> bool: return n is MeshInstance3D and String(n.name) == "Char_Head_LOD0") as MeshInstance3D
	var hb := skeleton.find_bone("Head")
	if head == null or hb < 0:
		r.free()
		return
	var sum := Vector3.ZERO
	var n := 0
	for si in head.mesh.get_surface_count():
		var mat := head.mesh.surface_get_material(si)
		if mat == null or mat.resource_name != "Eye":
			continue
		for v: Vector3 in head.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			if v.x > 0.0:
				sum += v
				n += 1
	if n > 0:
		_eye_head = skeleton.get_bone_global_rest(hb).affine_inverse() * (sum / n)
	r.free()


## The held weapon's root node (the loadout's weapon piece; null without one).
func _weapon_root_node() -> Node3D:
	var it := loadout.item_in_slot("weapon") if loadout else null
	var nodes: Array = pieces.get(it.id, []) if it else []
	return nodes[0] if not nodes.is_empty() else null


## ASSET-INTEGRATION-01: the grip modifier for the weapon in the hands (piece = its equipment data, root = its node; the
## support marker is read from the node, in weapon space).
func _configure_grip(piece: InfantryEquipment, root: Node3D) -> void:
	if _grip == null:
		return
	var marker := root.find_child("GRIP_Support", true, false) as Node3D if root else null
	_grip.configure(piece, _local_in(root, marker) if marker else Vector3.INF)


static func _local_in(root: Node3D, n: Node3D) -> Vector3:
	var xf := n.transform
	var p := n.get_parent()
	while p != root and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf.origin


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
	var yaw := global_rotation.y
	if not is_nan(_last_yaw) and delta > 0.0:
		_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, clampf(delta * 10.0, 0.0, 1.0))
	_last_yaw = yaw
	# Blend steps use at most 1/20 s per frame: after a hitch the pose still eases instead of snapping.
	delta = minf(delta, 0.05)
	var k := 1.0 if snap else clampf(delta * 6.0, 0.0, 1.0)      # accelerate / brake over ~0.3 s
	_move = _move.lerp(target, k)
	var speed := _move.length()
	var moving := clampf((speed - 0.15) / 0.6, 0.0, 1.0)
	_move_amount = lerpf(_move_amount, moving, 1.0 if snap else clampf(delta * 8.0, 0.0, 1.0))
	_crouch_amount = move_toward(_crouch_amount, 1.0 if crouched else 0.0, 1.0 if snap else delta * 3.0)
	var table: Array = _strides.crouch if crouched else _strides.stand
	var min_speed: float = table[0][0]
	var dir := _move.normalized() if speed > 0.01 else Vector2(0, 1)
	var pos := dir * maxf(speed, min_speed)
	# Playback rate: gait cycles per second x clip length, so the stride matches the speed.
	var stride := stride_at(maxf(speed, min_speed), table)
	if _lat_stride > 0.05 and not crouched:
		stride = lerpf(stride, _lat_stride, clampf(absf(dir.x), 0.0, 1.0))
	var cycles := maxf(speed, 0.35) / stride
	anim_tree.set("parameters/loco/blend_position", pos)
	anim_tree.set("parameters/cloco/blend_position", dir * maxf(speed, _strides.crouch[0][0]))
	anim_tree.set("parameters/scale/scale", cycles * LOCO_CLIP_S)
	anim_tree.set("parameters/cscale/scale", maxf(speed, 0.35) / stride_at(maxf(speed, 0.0), _strides.crouch) * LOCO_CLIP_S)
	anim_tree.set("parameters/move/blend_amount", _move_amount)
	anim_tree.set("parameters/cmove/blend_amount", _move_amount)
	anim_tree.set("parameters/crouch/blend_amount", _crouch_amount)
	var step := 1.0 if snap else delta
	_alert_amount = move_toward(_alert_amount, 1.0 if alert or aim_point.is_finite() else 0.0, step * 2.5)
	_aim_amount = move_toward(_aim_amount, 1.0 if aim_point.is_finite() and not reloading else 0.0, step * 4.0)
	var turning := clampf((absf(_yaw_rate) - 0.5) / 0.7, 0.0, 1.0) * (1.0 - _move_amount)
	_turn_amount = move_toward(_turn_amount, -signf(_yaw_rate) * turning, step * 5.0)
	var trate := clampf(absf(_yaw_rate) / _turn_rate, 0.6, 2.0)
	anim_tree.set("parameters/alert/blend_amount", _alert_amount)
	anim_tree.set("parameters/turn/blend_amount", _turn_amount)
	anim_tree.set("parameters/tscale_l/scale", trate)
	anim_tree.set("parameters/tscale_r/scale", trate)
	anim_tree.set("parameters/aim/blend_amount", _aim_amount)
	if reloading and not _was_reloading:
		anim_tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_was_reloading = reloading
	if _has_prone:
		_apply_prone(delta, snap, speed)
	if _grip:
		_support_amount = move_toward(_support_amount, 0.0 if reloading else 1.0, step * 5.0)
		_grip.aim_w = _aim_amount
		_grip.support_w = _support_amount
	if _flinch_mod:
		_flinch = _flinch.move_toward(Vector2.ZERO, delta * 1.6)
		_flinch_mod.yaw = _flinch.x
		_flinch_mod.pitch = _flinch.y
	if _aim_mod:
		# prone, the whole body points the rifle: the spine turns only a little towards the aim point
		_aim_mod.influence = _aim_amount * (1.0 - 0.75 * _prone_amount)
		if aim_point.is_finite():
			var chest := global_position + Vector3.UP * 1.4
			var d := global_basis.orthonormalized().inverse() * (aim_point - chest)
			var want_yaw := clampf(atan2(-d.x, -d.z), -1.2, 1.2)
			var want_pitch := clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.8, 0.8)
			var s := 1.0 if snap else clampf(delta * 8.0, 0.0, 1.0)
			_aim_mod.yaw = lerpf(_aim_mod.yaw, want_yaw, s)
			_aim_mod.pitch = lerpf(_aim_mod.pitch, want_pitch, s)


## COMBAT-01: the prone branch's weights and the change of posture's clip time.
func _apply_prone(delta: float, snap: bool, speed: float) -> void:
	var changing := posture_from != posture_to and posture_k < 1.0 and (posture_from == 2 or posture_to == 2)
	var lying := posture_to == 2 and not changing
	var want := 1.0 if (changing or lying) else 0.0
	var step := 1.0 if snap else clampf(delta * 8.0, 0.0, 1.0)
	_prone_amount = move_toward(_prone_amount, want, step)
	_trans_amount = move_toward(_trans_amount, 1.0 if changing else 0.0, step)
	if changing:
		var down := posture_to == 2
		var clip := "Stand_To_Prone" if down else "Prone_To_Stand"
		anim_tree.set("parameters/t_kind/blend_amount", 0.0 if down else 1.0)
		anim_tree.set("parameters/seek_%s/seek_request" % ("down" if down else "up"), posture_k * float(_prone_len.get(clip, 1.0)))
	anim_tree.set("parameters/hold_down/scale", 0.0)
	anim_tree.set("parameters/hold_up/scale", 0.0)
	anim_tree.set("parameters/prone/blend_amount", _prone_amount)
	anim_tree.set("parameters/trans/blend_amount", _trans_amount)
	anim_tree.set("parameters/p_aim/blend_amount", _aim_amount)
	anim_tree.set("parameters/p_move/blend_amount", clampf((speed - 0.1) / 0.3, 0.0, 1.0))
	anim_tree.set("parameters/p_cscale/scale", maxf(speed, 0.2) / maxf(_crawl_stride, 0.1) * float(_prone_len.get("crawl_s", 40.0 / 30.0)))


## Current animation state for tests/diagnostics.
func anim_state() -> Dictionary:
	return {"move": _move, "move_amount": _move_amount, "crouch": _crouch_amount, "prone": _prone_amount, "trans": _trans_amount,
		"rate": anim_tree.get("parameters/scale/scale") if anim_tree else 0.0,
		"alert": _alert_amount, "aim": _aim_amount, "turn": _turn_amount}


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

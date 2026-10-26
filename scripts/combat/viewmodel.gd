## First-person weapon (COMBAT-01a, CHARACTER-01): the weapon pieces of the possessed
## soldier's loadout (weapon, optic, foregrip ...), the same assets the third-person
## character carries, held in front of the camera. Presentation only: it kicks back on a
## shot and moves to the centre while aiming. The muzzle mount is where the first-person
## muzzle flash and tracer start.
##
## COMBAT-01 (Arma-style first person): the soldier's own arms hold the weapon - an InfantryCharacter of the loadout, with
## only its sleeves, gloves, hands and weapon pieces shown, posed by the VISUAL-03 clips (Ready_Idle at the hip, Aim with
## the cheek weld when aiming, Fire and the magazine-change Reload as the AI soldiers have them). At the hip the character's
## eye sits on the camera (the rifle low and to the right, muzzle towards the centre, both hands on it); aiming, the sight
## line is laid along the camera axis. A secondary weapon held instead (launcher, held_scene) is shown on its own as before.
##
## ASSET-INTEGRATION-01: the sight line and the aiming eye are the held weapon's own (InfantryEquipment.aim_eye: a pistol
## at arm's length, the SVD's lower scope, a launcher's sight on the left of its tube); the arms hold it through
## InfantryGripIK. A secondary weapon with an equipment piece (WeaponDef.held_piece) is held by the arms the same way.
class_name Viewmodel
extends Node3D

## Weapon space has its origin at the pistol grip (CHARACTER_STANDARD.md); these place the
## grip relative to the camera (Godot axes: -Z forward).
const HIP := Vector3(0.16, -0.27, -0.50)
## Aiming: the line of sight runs through the optic window (its lens is see-through here).
const ADS := Vector3(0.0, -0.172, -0.36)

## Loadout whose weapon pieces are shown; set before the node enters the tree.
var loadout: InfantryLoadout
## GAMEPLAY-02C: a weapon held instead of the loadout's (the secondary weapon, WeaponDef.viewmodel_scene).
var held_scene: PackedScene
## ASSET-INTEGRATION-01: the held secondary weapon's piece (its scene and hold); with it the arms hold the secondary.
var held_piece: InfantryEquipment
var faction := 0
var aiming := false
var muzzle: Node3D
## COMBAT-01: set every frame by the owner (the record reloads / fires).
var reloading := false
var arms: InfantryCharacter
var _weapon_root: Node3D
var _ads := 0.0
var _kick := 0.0
## ASSET-INTEGRATION-01: the hold kept while a reload runs (the clip lowers the weapon in front of a still body).
var _steady := Transform3D.IDENTITY
var _reload_k := 0.0
static var _lens_mat: StandardMaterial3D
static var _housing_mat: ShaderMaterial


func _ready() -> void:
	if (held_scene == null or held_piece != null) and loadout and _build_arms():
		return
	var mounts := {}
	if held_scene:
		var held: Node3D = held_scene.instantiate()
		add_child(held)
		for n in held.find_children("*", "", true, false):
			if n is MeshInstance3D:
				_style(n)
			elif String(n.name).begins_with("ATT_"):
				mounts["weapon:" + String(n.name)] = n
	# Weapon first, then the accessories mounted on it ("weapon:ATT_Optic" ...).
	for pass_i in (0 if held_scene else 2):
		for it in loadout.items:
			if not it.slot.begins_with("weapon") or it.scene == null or it.attach.contains(":") != (pass_i == 1):
				continue
			var parent: Node3D = mounts.get(it.attach) if pass_i == 1 else self
			if parent == null:
				continue
			var inst: Node3D = it.scene.instantiate()
			parent.add_child(inst)
			for n in inst.find_children("*", "", true, false):
				if n is MeshInstance3D:
					_style(n, it.slot == "weapon_optic")
				elif String(n.name).begins_with("ATT_") or String(n.name).begins_with("GRIP_"):
					mounts["%s:%s" % [it.slot, n.name]] = n
	muzzle = mounts.get("weapon:ATT_Muzzle")
	if muzzle == null:
		muzzle = Node3D.new()
		add_child(muzzle)
	position = HIP


## Only the closest LOD is shown, with the character's materials, and no shadow of its own
## (the first-person body already casts one).
func _style(mi: MeshInstance3D, sight := false) -> void:
	if String(mi.name).contains("_LOD") and not String(mi.name).ends_with("_LOD0"):
		mi.queue_free()
		return
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		if mat:
			var override: Material
			if mat.resource_name == "Lens":
				override = _lens()
			elif sight and mat.resource_name == "Metal_Black":
				override = _sight_housing()
			else:
				override = InfantryMaterials.get_material(mat.resource_name, faction)
			mi.set_surface_override_material(s, override)


## Sight housing for the first-person view. The third-person model's tube is a solid
## cylinder; here the faces across the bore are cut away so the line of sight passes
## through the optic (the rim, mount and turrets stay). Optic axis: z in mesh space,
## centre height 0.058 above the mount (char_weapon.build_red_dot).
static func _sight_housing() -> ShaderMaterial:
	if _housing_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 v_pos;
varying vec3 v_nrm;
void vertex() { v_pos = VERTEX; v_nrm = NORMAL; }
void fragment() {
	if (length(vec2(v_pos.x, v_pos.y - 0.058)) < 0.0195 && abs(v_nrm.z) > 0.7) { discard; }
	ALBEDO = vec3(0.045, 0.045, 0.048);
	METALLIC = 0.85;
	ROUGHNESS = 0.42;
}"""
		_housing_mat = ShaderMaterial.new()
		_housing_mat.shader = sh
	return _housing_mat


## The see-through first-person glass on a mesh's `Lens` surfaces, its other materials left as they are.
func _clear_lens(mi: MeshInstance3D) -> void:
	for si in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(si)
		if mat and mat.resource_name == "Lens":
			mi.set_surface_override_material(si, _lens())


## ASSET-INTEGRATION-01: an optic built into the weapon (PIV_Optic, the WEAPON-ASSETS-01 pack) is looked through: the faces
## across the sight axis within the eyepiece's inner radius are cut away (the tube walls, mount and turrets stay), the axis
## being the weapon's own aiming eye (InfantryEquipment.aim_eye) and the radius measured on the eyepiece ring.
static var _cut_shader: Shader
## A magnified scope (a long optic: PIV_Optic deeper than SCOPE_LEN): at full aim the weapon is hidden and the sight picture is
## drawn over the zoomed view (ring and cross hairs), as a tube 30 cm long seen at 8-15 degrees leaves only a pinhole.
const SCOPE_LEN := 0.25
var _scope_meshes: Array = []
var _scope_overlay: Control


func _scope_view(on: bool) -> void:
	if _scope_meshes.is_empty():
		return
	for mi: MeshInstance3D in _scope_meshes:
		mi.visible = not on
	if on and _scope_overlay == null:
		_scope_overlay = ScopeReticle.new()
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		layer.add_child(_scope_overlay)
	if _scope_overlay:
		_scope_overlay.visible = on


func _open_optic(root: Node3D) -> void:
	var piv := root.find_child("PIV_Optic", true, false) as Node3D
	if piv == null:
		return
	var meshes := piv.find_children("*_LOD0", "MeshInstance3D", true, false)
	var zmax := -INF
	var zmin := INF
	for mi: MeshInstance3D in meshes:
		zmax = maxf(zmax, mi.get_aabb().end.z)
		zmin = minf(zmin, mi.get_aabb().position.z)
	if zmax - zmin > SCOPE_LEN:
		# the whole weapon: its front sight or muzzle would stand in the zoomed picture
		_scope_meshes = root.find_children("*_LOD0", "MeshInstance3D", true, false)
	var centre := Vector2(_eye.x - piv.position.x, _eye.y - piv.position.y)
	var r := INF
	for mi: MeshInstance3D in meshes:
		for v in mi.mesh.get_faces():
			if v.z > zmax - 0.008:
				r = minf(r, maxf(absf(v.x - centre.x), absf(v.y - centre.y)))
	r = clampf(r * 0.85 if r < INF else 0.012, 0.008, 0.02)
	if _cut_shader == null:
		_cut_shader = Shader.new()
		_cut_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec2 centre;
uniform float radius;
uniform vec3 albedo : source_color = vec3(0.045);
varying vec3 v_pos;
varying vec3 v_nrm;
void vertex() { v_pos = VERTEX; v_nrm = NORMAL; }
void fragment() {
	if (length(v_pos.xy - centre) < radius && abs(v_nrm.z) > 0.7) { discard; }
	ALBEDO = albedo;
	METALLIC = 0.6;
	ROUGHNESS = 0.45;
}"""
	for mi: MeshInstance3D in meshes:
		for si in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(si)
			if mat and mat.resource_name == "Lens":
				mi.set_surface_override_material(si, _lens())
				continue
			var m := ShaderMaterial.new()
			m.shader = _cut_shader
			m.set_shader_parameter("centre", centre)
			m.set_shader_parameter("radius", r)
			var lib := InfantryMaterials.get_material(mat.resource_name if mat else "", faction)
			if lib is StandardMaterial3D:
				m.set_shader_parameter("albedo", (lib as StandardMaterial3D).albedo_color)
			mi.set_surface_override_material(si, m)


## Optic glass for the first-person view: nearly clear, so the sight picture is visible.
static func _lens() -> StandardMaterial3D:
	if _lens_mat == null:
		_lens_mat = StandardMaterial3D.new()
		_lens_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_lens_mat.albedo_color = Color(0.55, 0.75, 0.9, 0.08)
		_lens_mat.roughness = 0.05
		_lens_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _lens_mat


func kick(strength := 1.0) -> void:
	_kick = clampf(strength, 0.2, 2.0)
	if arms:
		arms.fire()


## Sight line above the weapon's grip origin (char_anim.SIGHT_Z: the optic rail + 0.058; the faction optics and the DMR
## scope share it) and how far in front of the eye it is laid when aiming.
const SIGHT_Y := 0.172
const EYE_RELIEF := 0.24
## ASSET-INTEGRATION-01: the held weapon's aiming eye in weapon space (x, sight line height, distance behind the grip).
var _eye := Vector3(0.0, SIGHT_Y, EYE_RELIEF)


## The arms: the loadout's character, everything but sleeves, gloves, hands and the weapon hidden. False when the loadout
## has no weapon piece (the floating weapon is used then).
func _build_arms() -> bool:
	if not InfantryCharacter.enabled():
		return false
	var c := InfantryCharacter.new()
	c.name = "Arms"
	c.ground_tilt = false
	add_child(c)
	c.setup(loadout, faction, false)
	var keep := {}
	for it in loadout.items:
		var shown := it.slot.begins_with("weapon") or String(it.id).contains("glove") or String(it.id).contains("jacket")
		for n: Node in c.pieces.get(it.id, []):
			if is_instance_valid(n):
				for mi in [n] + n.find_children("*", "MeshInstance3D", true, false):
					if mi is MeshInstance3D:
						keep[mi] = shown
						# the sight is looked through: clear glass, the tube cut open along its axis (as the floating weapon)
						if it.slot == "weapon_optic" and String(mi.name).ends_with("_LOD0"):
							_style(mi, true)
						# ASSET-INTEGRATION-01: a weapon with its optic built in (the WEAPON-ASSETS-01 pack) is looked through its glass
						elif it.slot == "weapon" and String(mi.name).ends_with("_LOD0"):
							_clear_lens(mi)
		if it.slot == "weapon" and not c.pieces.get(it.id, []).is_empty():
			_weapon_root = c.pieces[it.id][0]
			_eye = it.aim_eye
	if held_piece and held_piece.scene:
		c.show_secondary(true, held_piece.scene, held_piece)
		_weapon_root = c._held_secondary
		_eye = held_piece.aim_eye
		for mi in c._meshes(_weapon_root):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if String(mi.name).ends_with("_LOD0"):
				_style(mi, false)
	if _weapon_root == null:
		c.queue_free()
		return false
	_open_optic(_weapon_root)
	for mi in c.lod_meshes:
		if not is_instance_valid(mi):
			continue
		var n := String(mi.name)
		var on: bool = keep.get(mi, n.contains("Arms") or n.contains("Hands"))
		mi.visible = on and (not n.contains("_LOD") or n.ends_with("_LOD0"))
		mi.visibility_range_begin = 0.0
		mi.visibility_range_end = 0.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arms = c
	arms.alert = true
	muzzle = c.muzzle() if c.muzzle() else _weapon_root
	if held_piece and _weapon_root:
		var tip := _weapon_root.find_child("ATT_Muzzle", true, false) as Node3D
		muzzle = tip if tip else _weapon_root
	return true


## Camera-space transform of the arms. The weapon is always shouldered (the Aim clip, as an Arma soldier carries it ready):
## aiming, its sight line lies on the camera axis EYE_RELIEF in front; at the hip the same hold sits lower and to the right,
## the muzzle turned in a little towards the centre (HIP_OFFSET, HIP_TURN). Reloading lowers it (the Reload layer).
const HIP_OFFSET := Vector3(0.075, -0.12, -0.14)
const HIP_TURN := Vector3(1.0, 4.0, -5.0)  # pitch, yaw (+ = muzzle left), roll (deg)


func _place_arms(delta: float) -> void:
	_ads = move_toward(_ads, 1.0 if aiming and not reloading else 0.0, delta * 4.5)
	arms.aim_point = arms.global_position + arms.global_basis * Vector3(0, 1.45, -100.0)
	arms.reloading = reloading
	var inv := arms.global_transform.affine_inverse()
	var w := inv * _weapon_root.global_transform
	var wb := w.basis.orthonormalized()
	var sight := Transform3D(wb, w.origin + wb * Vector3(_eye.x, _eye.y, 0.0))
	var ads := Transform3D(Basis.IDENTITY, Vector3(0, 0, -_eye.z)) * sight.affine_inverse()
	var turn := Basis.from_euler(Vector3(deg_to_rad(HIP_TURN.x), deg_to_rad(HIP_TURN.y), deg_to_rad(HIP_TURN.z)))
	var hip := Transform3D(turn, HIP_OFFSET + Vector3(0, 0, -_eye.z)) * sight.affine_inverse()
	var xf := hip.interpolate_with(ads, smoothstep(0.0, 1.0, _ads))
	# ASSET-INTEGRATION-01: placed from the moving weapon, a reload would swing the body up to the camera (sleeves fill the
	# view); while it runs the arms keep the hold they had, so the weapon visibly comes down and back.
	_reload_k = move_toward(_reload_k, 1.0 if reloading else 0.0, delta * 6.0)
	if _reload_k <= 0.0:
		_steady = xf
	# halfway between: the body stays below the view and the weapon stays in it
	arms.transform = xf.interpolate_with(_steady, 0.55 * smoothstep(0.0, 1.0, _reload_k))
	_scope_view(_ads > 0.85 and not reloading)
	# The glass is looked through only when aiming; at the hip it is dark, reflecting glass (else the muzzle flash in front
	# of the barrel shows through the side of the optic as if it burnt inside it).
	_lens().albedo_color = Color(0.55, 0.75, 0.9, 0.08).lerp(Color(0.05, 0.07, 0.09, 0.92), 1.0 - smoothstep(0.6, 1.0, _ads))
	position = Vector3(0, 0.004, 0.035) * _kick
	rotation = Vector3(deg_to_rad(2.5) * _kick, 0.0, 0.0)


func _process(delta: float) -> void:
	_kick = maxf(_kick - delta * 12.0, 0.0)
	if arms:
		_place_arms(delta)
		return
	var target := ADS if aiming else HIP
	position = position.lerp(target, clampf(delta * 14.0, 0.0, 1.0)) + Vector3(0, 0.004, 0.035) * _kick
	rotation.x = deg_to_rad(2.5) * _kick


## ASSET-INTEGRATION-01: the sight picture of a magnified scope at full aim: a dark ring round the field of view and thin
## cross hairs with a heavier lower post (a plain duplex reticle; the weapon's own reticle is not modelled).
class ScopeReticle extends Control:
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		var black := Color(0.0, 0.0, 0.0, 1.0)
		# the ring: everything outside the circle dark
		draw_arc(c, r + size.x, 0.0, TAU, 96, black, size.x * 2.0)
		draw_arc(c, r, 0.0, TAU, 96, Color(0, 0, 0, 0.85), 6.0)
		var ink := Color(0.02, 0.02, 0.02, 0.95)
		draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), ink, 1.5)
		draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.12), ink, 1.5)
		draw_line(c + Vector2(0, r * 0.12), c + Vector2(0, r), ink, 5.0)
		draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.55, 0), ink, 5.0)
		draw_line(c + Vector2(r * 0.55, 0), c + Vector2(r, 0), ink, 5.0)

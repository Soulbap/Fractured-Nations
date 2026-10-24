## First-person weapon (COMBAT-01a, CHARACTER-01): the weapon pieces of the possessed
## soldier's loadout (weapon, optic, foregrip ...), the same assets the third-person
## character carries, held in front of the camera. Presentation only: it kicks back on a
## shot and moves to the centre while aiming. The muzzle mount is where the first-person
## muzzle flash and tracer start.
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
var faction := 0
var aiming := false
var muzzle: Node3D
var _kick := 0.0
static var _lens_mat: StandardMaterial3D
static var _housing_mat: ShaderMaterial


func _ready() -> void:
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


## Optic glass for the first-person view: nearly clear, so the sight picture is visible.
static func _lens() -> StandardMaterial3D:
	if _lens_mat == null:
		_lens_mat = StandardMaterial3D.new()
		_lens_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_lens_mat.albedo_color = Color(0.55, 0.75, 0.9, 0.08)
		_lens_mat.roughness = 0.05
		_lens_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _lens_mat


func kick() -> void:
	_kick = 1.0


func _process(delta: float) -> void:
	_kick = maxf(_kick - delta * 12.0, 0.0)
	var target := ADS if aiming else HIP
	position = position.lerp(target, clampf(delta * 14.0, 0.0, 1.0)) + Vector3(0, 0.004, 0.035) * _kick
	rotation.x = deg_to_rad(2.5) * _kick

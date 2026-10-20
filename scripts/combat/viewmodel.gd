## First-person rifle (COMBAT-01a): the soldier model's carbine rebuilt from the same
## part sizes as tools/blender/make_soldier.py, held in front of the possessed soldier's
## camera. Presentation only: it kicks back on a shot and moves to the centre while
## aiming. The muzzle marker is where the first-person muzzle flash and tracer start.
class_name Viewmodel
extends Node3D

const HIP := Vector3(0.17, -0.19, -0.42)
## Aiming: centred just below the line of sight, so the target stays visible over the
## optic (no see-through sight model in this milestone).
const ADS := Vector3(0.0, -0.135, -0.34)

var aiming := false
var muzzle: Marker3D
var _kick := 0.0


func _ready() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.13, 0.14, 0.13)
	metal.roughness = 0.55
	metal.metallic = 0.4
	var furniture := StandardMaterial3D.new()
	furniture.albedo_color = Color(0.22, 0.23, 0.19)
	furniture.roughness = 0.85
	# Blender part (size x, y forward, z up; offset) -> Godot box (x, z, y) at (x, z, -y).
	_part(Vector3(0.05, 0.28, 0.075), Vector3(0, 0.0, 0.0), metal)       # receiver
	_part(Vector3(0.045, 0.26, 0.055), Vector3(0, 0.27, 0.005), furniture)  # handguard
	_part(Vector3(0.045, 0.24, 0.06), Vector3(0, -0.25, -0.005), furniture) # stock
	_part(Vector3(0.03, 0.045, 0.11), Vector3(0, -0.04, -0.085), furniture) # grip
	_part(Vector3(0.03, 0.065, 0.17), Vector3(0, 0.07, -0.11), metal)       # magazine
	_part(Vector3(0.035, 0.10, 0.05), Vector3(0, 0.0, 0.06), metal)         # optic
	_part(Vector3(0.04, 0.44, 0.012), Vector3(0, 0.17, 0.042), metal)       # rail
	_part(Vector3(0.016, 0.16, 0.016), Vector3(0, 0.46, 0.008), metal)      # barrel
	muzzle = Marker3D.new()
	muzzle.position = Vector3(0, 0.008, -0.55)
	add_child(muzzle)
	position = HIP


func _part(size: Vector3, off: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.z, size.y)
	mi.mesh = box
	mi.material_override = mat
	mi.position = Vector3(off.x, off.z, -off.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func kick() -> void:
	_kick = 1.0


func _process(delta: float) -> void:
	_kick = maxf(_kick - delta * 12.0, 0.0)
	var target := ADS if aiming else HIP
	position = position.lerp(target, clampf(delta * 14.0, 0.0, 1.0)) + Vector3(0, 0.004, 0.035) * _kick
	rotation.x = deg_to_rad(2.5) * _kick

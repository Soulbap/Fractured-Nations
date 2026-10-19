## Abstract-tier visual of a unit: a simple marker driven only by the UnitState.
##
## Units far from the active camera have no physics body (see DetailManager), but the
## tactical view must still show and select them. The proxy is a faction-coloured
## capsule (box for vehicles) plus the selection ring; it reads position and heading from
## the record every frame and owns no physics, navigation or collision.
class_name UnitProxy
extends Node3D

var unit: UnitState
var sim: WorldSim
var selected := false:
	set(v):
		selected = v
		if ring:
			UnitVisuals.style_ring(ring, unit.faction if unit else 0, selected)

var ring: MeshInstance3D
var _marker: MeshInstance3D


func bind(p_unit: UnitState, p_sim: WorldSim) -> void:
	unit = p_unit
	sim = p_sim
	name = "Proxy_%d" % unit.id
	_marker = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UnitVisuals.uniform_color(unit.faction)
	mat.roughness = 0.9
	if unit.is_vehicle():
		var box := BoxMesh.new()
		box.size = Vector3(2.9, 2.5, 6.1)
		_marker.mesh = box
		_marker.position.y = 1.25
	else:
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = 1.8
		_marker.mesh = cap
		_marker.position.y = 0.9
	_marker.material_override = mat
	add_child(_marker)
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.1 if unit.is_vehicle() else 0.55
	torus.outer_radius = 3.4 if unit.is_vehicle() else 0.75
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.1
	add_child(ring)
	UnitVisuals.style_ring(ring, unit.faction, selected)
	_follow()
	sim.register_proxy(unit.id, self)


func _exit_tree() -> void:
	if sim and unit and sim.proxies.get(unit.id) == self:
		sim.unregister_proxy(unit.id)


func _process(_delta: float) -> void:
	_follow()
	UnitVisuals.scale_ring_for_camera(ring, selected)


func _follow() -> void:
	global_position = unit.position
	rotation.y = unit.yaw

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
## COMBAT-01a: the marker shows a casualty (lying, dark, no ring) once the unit is dead.
var _shows_dead := false


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
	elif InfantryCharacter.enabled():
		# CHARACTER-01: static posed far-view mesh of the unit's loadout (one draw call).
		if unit.loadout == "":
			unit.loadout = InfantryLoadout.default_for(unit.id)
		var pm := InfantryProxyMesh.get_mesh(unit.loadout, unit.faction)
		if pm:
			_marker.mesh = pm
			mat = null
	if _marker.mesh == null:
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
	if not unit.alive:
		_show_dead()
	sim.register_proxy(unit.id, self)


func _exit_tree() -> void:
	if sim and unit and sim.proxies.get(unit.id) == self:
		sim.unregister_proxy(unit.id)


func _process(_delta: float) -> void:
	_follow()
	if not unit.alive and not _shows_dead:
		_show_dead()
	if ring.visible:
		UnitVisuals.scale_ring_for_camera(ring, selected)


## Casualty marker: the capsule lies on the ground in a darkened uniform colour.
func _show_dead() -> void:
	_shows_dead = true
	ring.visible = false
	if not unit.is_vehicle():
		_marker.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		_marker.position = Vector3(0.0, 0.3, 0.0)
	var mat := _marker.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = UnitVisuals.uniform_color(unit.faction).darkened(0.45)


func _follow() -> void:
	global_position = unit.position
	rotation.y = unit.yaw

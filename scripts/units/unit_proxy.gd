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
			UnitVisuals.style_ring(ring, unit.faction if unit else 0, selected, unit != null and not unit.is_vehicle())

var ring: MeshInstance3D
var _marker: MeshInstance3D
var _vehicle_visual: VehicleVisual
## COMBAT-01a: the marker shows a casualty (lying, dark, no ring) once the unit is dead.
var _shows_dead := false
var _shown_posture := 0


func bind(p_unit: UnitState, p_sim: WorldSim) -> void:
	unit = p_unit
	sim = p_sim
	name = "Proxy_%d" % unit.id
	_marker = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UnitVisuals.uniform_color(unit.faction)
	mat.roughness = 0.9
	if unit.is_vehicle():
		# LOGISTICS-01: the hull at its coarsest LOD (about 100 triangles), no wheels.
		_vehicle_visual = VehicleVisual.new()
		_vehicle_visual.name = "Hull"
		add_child(_vehicle_visual)
		_vehicle_visual.build(unit.veh.type_id if unit.veh else VehicleDefs.TRUCK, unit.faction, true)
		_marker.mesh = null
	elif InfantryCharacter.enabled():
		# CHARACTER-01: static posed far-view mesh of the unit's loadout (one draw call); refresh_look swaps it.
		if unit.loadout == "":
			unit.loadout = InfantryLoadout.default_for(unit.id, unit.faction)
		var pm := InfantryProxyMesh.get_mesh(unit.loadout, unit.faction, Posture.current(unit))
		_shown_posture = Posture.current(unit)
		if pm:
			_marker.mesh = pm
			mat = null
	if _marker.mesh == null and not unit.is_vehicle():
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = 1.8
		_marker.mesh = cap
		_marker.position.y = 0.9
	_marker.material_override = mat
	add_child(_marker)
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = (unit.veh.def().length * 0.5 + 0.4 if unit.veh else 3.1) if unit.is_vehicle() else 0.55
	torus.outer_radius = torus.inner_radius + (0.3 if unit.is_vehicle() else 0.2)
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.1
	add_child(ring)
	UnitVisuals.style_ring(ring, unit.faction, selected, not unit.is_vehicle())
	_follow()
	if not unit.alive:
		_show_dead()
	sim.register_proxy(unit.id, self)


func _exit_tree() -> void:
	if sim and unit and sim.proxies.get(unit.id) == self:
		sim.unregister_proxy(unit.id)


func _process(_delta: float) -> void:
	_follow()
	# COMBAT-01: the far mesh shows the record's posture (standing, crouched, prone).
	if not unit.is_vehicle() and unit.alive and InfantryCharacter.enabled() and unit.loadout != "":
		var p := Posture.current(unit)
		if p != _shown_posture:
			_shown_posture = p
			var pm := InfantryProxyMesh.get_mesh(unit.loadout, unit.faction, p)
			if pm:
				_marker.mesh = pm
	if not unit.alive and not _shows_dead:
		_show_dead()
	if ring.visible:
		UnitVisuals.scale_ring_for_camera(ring, selected, not unit.is_vehicle())


## Casualty marker: the capsule lies on the ground in a darkened uniform colour.
func _show_dead() -> void:
	_shows_dead = true
	ring.visible = false
	if not unit.is_vehicle():
		_marker.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		_marker.position = Vector3(0.0, 0.3, 0.0)
	if unit.is_vehicle():
		return
	var mat := _marker.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = UnitVisuals.uniform_color(unit.faction).darkened(0.45)


func _follow() -> void:
	global_position = unit.position
	rotation.y = unit.yaw


## GAMEPLAY-04D: the record's loadout changed (re-equipped): the far-view mesh of the new loadout.
func refresh_look() -> void:
	if unit and not unit.is_vehicle() and InfantryCharacter.enabled() and unit.loadout != "":
		var pm := InfantryProxyMesh.get_mesh(unit.loadout, unit.faction, _shown_posture)
		if pm:
			_marker.mesh = pm

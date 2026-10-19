## Physical vehicle: a parked body for a UnitState of kind VEHICLE.
##
## Driving is out of scope for WORLD-CORE-01, so the body is static: it occupies space
## (soldiers path around it, the navmesh is carved around its footprint), is selectable
## in the tactical view and keeps its record in WorldState up to date. A later driving
## layer replaces the StaticBody3D without touching the state.
class_name VehicleBody
extends StaticBody3D

## Footprint (width, length) in meters used to carve the navigation mesh.
@export var footprint := Vector2(2.6, 5.8)

var unit: UnitState
var sim: WorldSim
var selected := false:
	set(v):
		selected = v
		if is_node_ready():
			UnitVisuals.style_ring(ring, unit.faction if unit else 0, selected)

@onready var visual: Node3D = $Visual
@onready var ring: MeshInstance3D = $Ring


func bind(p_unit: UnitState, p_sim: WorldSim) -> void:
	unit = p_unit
	sim = p_sim
	name = "Vehicle_%d" % unit.id
	global_position = unit.position
	rotation.y = unit.yaw
	UnitVisuals.apply_faction(visual, unit.faction)
	UnitVisuals.style_ring(ring, unit.faction, selected)
	sim.register_body(unit.id, self)
	unit.move_state = UnitState.MoveState.IDLE


func _exit_tree() -> void:
	if sim and unit:
		sim.unregister_body(unit.id)


func _process(_delta: float) -> void:
	UnitVisuals.scale_ring_for_camera(ring, selected)


func _physics_process(_delta: float) -> void:
	if unit:
		unit.position = global_position
		unit.yaw = rotation.y


## Obstacle description for AreaNavigation.
func nav_obstacle() -> Dictionary:
	return {"position": global_position, "yaw": rotation.y, "size": footprint}

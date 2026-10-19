## Tactical input: selecting units and issuing orders from the RTS camera.
##
## Selection is screen-space (nearest projected unit within a few pixels, or a drag
## box), which works at any zoom. Orders go to WorldState only; nothing here moves a
## unit. The ground point of a move order comes from a physics ray against the terrain
## collision, with Terrain3D's height-map ray march as fallback.
class_name RTSController
extends Node

signal selection_changed(ids: Array)
signal possess_requested(unit_id: int)
signal order_issued(count: int, target: Vector3)

@export var rig: RTSCamera
@export var sim: WorldSim
@export var terrain: Terrain3D
## Where the move-order marker lives.
@export var marker_parent: Node3D
@export var pick_radius_px := 22.0
@export var drag_threshold_px := 6.0
@export var formation_spacing := 2.5
## Allow ordering and possessing units of any faction (no combat yet, useful for testing).
@export var command_any_faction := true
@export var player_faction := 0

var selected: Array[int] = []
var active := false
var drag_start := Vector2.INF
var drag_current := Vector2.ZERO
var dragging := false
var last_order_target := Vector3.INF

var _marker: MeshInstance3D
var _marker_until := 0.0


func _ready() -> void:
	GameController.ensure_input_actions()
	set_process_unhandled_input(false)
	_marker = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 0.08
	_marker.mesh = cyl
	var m := UnitVisuals.make_ring_material()
	m.albedo_color = Color(0.4, 1.0, 0.4, 0.8)
	_marker.material_override = m
	_marker.visible = false
	(marker_parent if marker_parent else self).add_child.call_deferred(_marker)


func set_active(on: bool) -> void:
	active = on
	set_process_unhandled_input(on)
	if not on:
		_end_drag()


func _process(_delta: float) -> void:
	if _marker.visible and Time.get_ticks_msec() / 1000.0 > _marker_until:
		_marker.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_start = event.position
				drag_current = event.position
				dragging = false
				if event.double_click:
					var id := _unit_at(event.position)
					if id > 0 and _can_command(id):
						select([id])
						possess_requested.emit(id)
			else:
				if dragging:
					_box_select(Rect2(drag_start, drag_current - drag_start).abs(), event.shift_pressed)
				elif drag_start != Vector2.INF:
					_click_select(event.position, event.shift_pressed)
				_end_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			order_move_at(event.position)
	elif event is InputEventMouseMotion and drag_start != Vector2.INF and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		drag_current = event.position
		if drag_current.distance_to(drag_start) > drag_threshold_px:
			dragging = true
	elif event.is_action_pressed("possess"):
		var id := first_selected_soldier()
		if id > 0:
			possess_requested.emit(id)
	elif event.is_action_pressed("halt"):
		for id in selected:
			sim.state.halt(id)
	elif event.is_action_pressed("select_all"):
		var ids := []
		for u in sim.state.soldiers():
			if _can_command(u.id):
				ids.append(u.id)
		select(ids)
	elif event.is_action_pressed("ui_cancel"):
		select([])


func select(ids: Array) -> void:
	for id in selected:
		var b := sim.body_of(id)
		if b and "selected" in b:
			b.selected = false
	selected.clear()
	for id in ids:
		if sim.state.get_unit(id) == null or selected.has(id):
			continue
		selected.append(id)
		var b := sim.body_of(id)
		if b and "selected" in b:
			b.selected = true
	selection_changed.emit(selected)


func first_selected_soldier() -> int:
	for id in selected:
		var u := sim.state.get_unit(id)
		if u and u.kind == UnitState.Kind.SOLDIER:
			return id
	return -1


## Issues a group move order to the selected soldiers toward the ground under a
## screen position. Returns the number of soldiers ordered.
func order_move_at(screen_pos: Vector2) -> int:
	var hit := ground_point(screen_pos)
	if not hit.is_finite():
		return 0
	var ids := []
	for id in selected:
		if _can_command(id):
			ids.append(id)
	var n := sim.state.issue_group_move(ids, hit, formation_spacing)
	if n > 0:
		last_order_target = hit
		_marker.global_position = hit + Vector3.UP * 0.1
		_marker.visible = true
		_marker_until = Time.get_ticks_msec() / 1000.0 + 2.5
		order_issued.emit(n, hit)
	return n


## World position of the terrain under a screen point, or Vector3.INF.
func ground_point(screen_pos: Vector2) -> Vector3:
	var cam := rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 6000.0)
	q.collide_with_areas = false
	var exclude: Array[RID] = []
	for b in sim.bodies.values():
		if b is CollisionObject3D:
			exclude.append(b.get_rid())
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit.position
	if terrain:
		var p: Vector3 = terrain.get_intersection(from, dir, false)
		if p.is_finite() and not is_nan(p.x):
			return p
	return Vector3.INF


func _can_command(id: int) -> bool:
	var u := sim.state.get_unit(id)
	return u != null and (command_any_faction or u.faction == player_faction)


func _unit_at(screen_pos: Vector2) -> int:
	var cam := rig.camera
	var best := -1
	var best_d := INF
	for id in sim.bodies:
		var b: Node3D = sim.bodies[id]
		var u := sim.state.get_unit(id)
		if u == null:
			continue
		var p := b.global_position + Vector3.UP * (1.0 if u.kind == UnitState.Kind.SOLDIER else 1.3)
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var radius := pick_radius_px * (1.0 if u.kind == UnitState.Kind.SOLDIER else 2.2)
		var d := sp.distance_to(screen_pos)
		if d <= radius and d < best_d:
			best_d = d
			best = id
	return best


func _click_select(screen_pos: Vector2, add: bool) -> void:
	var id := _unit_at(screen_pos)
	if id < 0:
		if not add:
			select([])
		return
	if add:
		var ids := Array(selected)
		if ids.has(id):
			ids.erase(id)
		else:
			ids.append(id)
		select(ids)
	else:
		select([id])


func _box_select(rect: Rect2, add: bool) -> void:
	var cam := rig.camera
	var ids := Array(selected) if add else []
	for id in sim.bodies:
		var b: Node3D = sim.bodies[id]
		var p := b.global_position + Vector3.UP
		if cam.is_position_behind(p):
			continue
		if rect.has_point(cam.unproject_position(p)) and not ids.has(id):
			ids.append(id)
	select(ids)


func _end_drag() -> void:
	drag_start = Vector2.INF
	dragging = false

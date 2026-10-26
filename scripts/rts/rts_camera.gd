## Tactical (RTS) camera rig: a focus point on the ground, a yaw and a zoom distance.
##
## Pan with the movement keys (speed scales with zoom), rotate with Q/E or middle-mouse
## drag, zoom with the wheel. Pitch steepens as the camera rises so close views look
## along the ground and far views look down; dragging with the middle mouse button up and
## down tilts the view on top of that (WORLD-PLAYTEST-01), clamped to pitch_min_deg ..
## pitch_max_deg. The rig never touches the world state; it is one of two cameras looking
## at the same scene.
class_name RTSCamera
extends Node3D

@export var terrain: Terrain3D
## Closest zoom distance (m). UNIT-01A: 5 m, close enough to read a single soldier.
@export var zoom_min := 5.0
## Farthest zoom distance (m). Large-scale overview belongs to the future 2D strategic map.
@export var zoom_max := 200.0
## Zoom distance at start (m).
@export var zoom_default := 80.0
@export var zoom_factor := 1.15
## Pan speed as a fraction of the zoom distance per second.
@export var pan_speed := 0.9
@export var rotate_speed := 1.8
@export var drag_sensitivity := 0.005
@export var pitch_near_deg := 28.0
@export var pitch_far_deg := 65.0
## Limits of the tilted pitch (degrees below the horizon): never level with the ground,
## never straight down past the focus.
@export var pitch_min_deg := 8.0
@export var pitch_max_deg := 84.0
## Middle-drag tilt per pixel of vertical mouse motion (radians).
@export var tilt_sensitivity := 0.004
@export var ground_clearance := 3.0
## Clearance above the terrain at the closest zoom (blends to ground_clearance by 40 m).
@export var ground_clearance_near := 1.2
## Below this zoom the camera keeps out of buildings and structures (UI-UX-03, see _step).
@export var collision_below_zoom := 40.0
## Distance kept from a hit surface (m).
@export var collision_margin := 0.4
## UI-UX-03: a building closer to the focus than this (m) does not pull the camera in (the camera rises over it instead):
## pulling in to a wall the focus stands at put the camera at the focus and turned the view around.
@export var pull_min_dist := 4.0
## Height kept above a roof the camera passes over (m).
@export var roof_clearance := 1.5
## Smoothing rates (1/s): the camera distance moves in fast and back out slowly; the lift over roofs rises fast and sinks slowly.
@export var pull_in_rate := 8.0
@export var pull_out_rate := 3.0
@export var lift_up_rate := 12.0
@export var lift_down_rate := 2.5
## The corrections never move the camera faster than this (m/s).
@export var max_correction_speed := 35.0
## Focus is clamped to this half extent (map half size) when > 0.
@export var map_half_size := 0.0

var focus := Vector3.ZERO
var yaw := 0.0
var zoom := 80.0
## Player tilt added to the zoom-dependent pitch (radians, + = steeper).
var pitch_offset := 0.0
var active := false
var _last_us := 0
## UI-UX-03: smoothed camera state. _dist is the distance from the focus the camera stands at (<= zoom: pulled in front of a
## building), _lift the height added to clear a roof under the camera. Both follow targets measured each frame from the
## unpulled pose, so the measurement never depends on the smoothed result (no feedback, no oscillation).
var _dist := -1.0
var _lift := 0.0
## Seconds since a building last pulled the camera in.
var _pulled_s := 99.0
## Wheel zoom follows at this rate (1/s).
const zoom_rate := 14.0
static var legacy := "--legacy-rts-camera" in OS.get_cmdline_user_args()

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	zoom = clampf(zoom_default, zoom_min, zoom_max)
	FPSController.ensure_input_actions()
	GameController.ensure_input_actions()
	set_process(false)
	set_process_unhandled_input(false)


func set_active(on: bool) -> void:
	active = on
	set_process(on)
	set_process_unhandled_input(on)
	if on:
		camera.make_current()
		_update_transform()


## Centers the view on a position; keeps the current zoom unless one is given.
func frame(pos: Vector3, p_yaw: float, p_zoom := -1.0) -> void:
	focus = pos
	yaw = p_yaw
	if p_zoom > 0.0:
		zoom = clampf(p_zoom, zoom_min, zoom_max)
	_update_transform()


func _process(_delta: float) -> void:
	# GAMEPLAY-02 (controls): the view moves in real time - the same speed at 8 x and while the simulation is paused.
	var now := Time.get_ticks_usec()
	var delta := clampf((now - _last_us) / 1.0e6, 0.0, 0.1) if _last_us > 0 else 0.0
	_last_us = now
	var pan := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if pan != Vector2.ZERO:
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var boost := 2.5 if Input.is_action_pressed("sprint") else 1.0
		focus += (fwd * pan.y + right * pan.x) * pan_speed * zoom * boost * delta
	var rot := Input.get_axis("rts_rotate_right", "rts_rotate_left")
	if rot != 0.0:
		yaw += rot * rotate_speed * delta
	_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# The next _process frame moves the camera (smoothly, see _step).
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(zoom / zoom_factor, zoom_min)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(zoom * zoom_factor, zoom_max)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		yaw -= event.relative.x * drag_sensitivity
		tilt_by(event.relative.y * tilt_sensitivity)


## Tilts the view (radians, + = steeper), keeping the resulting pitch inside the limits.
func tilt_by(delta_rad: float) -> void:
	var base := _base_pitch()
	pitch_offset = clampf(base + pitch_offset + delta_rad, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg)) - base


## Pitch below the horizon (radians) the camera uses now.
func pitch() -> float:
	return clampf(_base_pitch() + pitch_offset, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


func _base_pitch() -> float:
	var t := log(zoom / zoom_min) / log(zoom_max / zoom_min)
	return deg_to_rad(lerpf(pitch_near_deg, pitch_far_deg, clampf(t, 0.0, 1.0)))


func _ground_height(p: Vector3) -> float:
	if terrain == null:
		return NAN
	return terrain.data.get_height(p)


## Places the camera at once (framing, tests, mode switches): no smoothing.
func _update_transform() -> void:
	_step(0.0)


## UI-UX-03: one camera step; delta 0 snaps the smoothed state to its targets.
## Before UI-UX-03 a ray from the focus to the camera put the camera on the first thing it hit, every frame. Since
## COMBAT-COVER-03 settlement houses are full-volume boxes, and the collider pool around the camera anchor is rebuilt every
## 10 m, so that ray kept switching between a house and nothing while panning, rotating or zooming: the camera jumped between
## its zoom distance and a wall, and with the focus at a wall it was put at the focus and the view turned round. Now only
## buildings and structures (box solids) count - trees, rocks, soldiers and vehicles never move the camera -, a building next
## to the focus lifts the camera over its roof instead of pulling it in, and both corrections are smoothed.
func _step(delta: float) -> void:
	if map_half_size > 0.0:
		var lim := map_half_size - 10.0
		focus.x = clampf(focus.x, -lim, lim)
		focus.z = clampf(focus.z, -lim, lim)
	var h := _ground_height(focus)
	if not is_nan(h):
		focus.y = h
	var pitch_r := pitch()
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var dir := (back * cos(pitch_r) + Vector3.UP * sin(pitch_r)).normalized()
	var clearance := lerpf(ground_clearance_near, ground_clearance, clampf((zoom - zoom_min) / maxf(collision_below_zoom - zoom_min, 0.01), 0.0, 1.0))
	var want_dist := zoom
	var want_lift := 0.0
	var collide := zoom < collision_below_zoom and is_inside_tree()
	if collide:
		var hit_d := _structure_between(focus + Vector3.UP * 1.6, focus + dir * zoom)
		if hit_d >= pull_min_dist:
			want_dist = minf(zoom, hit_d - collision_margin)
	var snap := delta <= 0.0 or _dist < 0.0
	if want_dist < zoom:
		_pulled_s = 0.0
	else:
		_pulled_s += delta
	# Out again slowly after a building let go of the camera (no pop), at the zoom's own pace otherwise.
	var out_rate := pull_out_rate if _pulled_s < 0.8 else zoom_rate
	var cap := max_correction_speed if want_dist < zoom or _pulled_s < 0.8 else INF  # the wheel zoom itself is never capped
	_dist = want_dist if snap else _approach(_dist, want_dist, pull_in_rate if want_dist < _dist else out_rate, delta, cap)
	_dist = minf(_dist, zoom)  # zooming in is never delayed
	var pos := focus + dir * _dist
	var gh := _ground_height(pos)
	if not is_nan(gh) and pos.y < gh + clearance:
		pos.y = gh + clearance
	if legacy and zoom < collision_below_zoom and is_inside_tree():
		pos = _avoid_obstacles(focus + Vector3.UP * 1.6, focus + dir * zoom)
		camera.global_position = pos
		camera.look_at(focus, Vector3.UP)
		return
	if collide:
		var top := _roof_under(pos)
		if not is_nan(top):
			want_lift = maxf(top + roof_clearance - pos.y, 0.0)
	_lift = want_lift if snap else _approach(_lift, want_lift, lift_up_rate if want_lift > _lift else lift_down_rate, delta, max_correction_speed)
	pos.y += _lift
	camera.global_position = pos
	camera.look_at(focus, Vector3.UP)


## `--legacy-rts-camera` (comparison only): the pre-UI-UX-03 obstacle handling - the camera put in front of the first static
## hit between the focus and the camera, every frame, unsmoothed.
func _avoid_obstacles(from: Vector3, pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, pos)
	var exclude: Array[RID] = []
	for i in 4:
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return pos
		if hit.collider is CharacterBody3D or hit.collider is RigidBody3D:
			exclude.append(hit.rid)
			continue
		return (hit.position as Vector3) - (pos - from).normalized() * collision_margin
	return pos


## Exponential approach, at most max_speed m/s (a long frame must not turn the glide into a jump).
static func _approach(cur: float, target: float, rate: float, delta: float, max_speed := INF) -> float:
	var step := (target - cur) * (1.0 - exp(-rate * delta))
	return cur + clampf(step, -max_speed * delta, max_speed * delta)


## A building or structure collider: a box in the instance collider pool (settlement houses, walls, cover objects) or a body
## of StructureManager. Tree trunks (capsules), rocks (spheres), the terrain and moving bodies are not.
static func _is_structure(hit: Dictionary) -> bool:
	var body := hit.get("collider") as StaticBody3D
	if body == null:
		return false
	if String(body.name).begins_with("SC_"):
		return true
	var owner_id := body.shape_find_owner(int(hit.get("shape", 0)))
	if owner_id < 0:
		return false
	var cs := body.shape_owner_get_owner(owner_id) as CollisionShape3D
	return cs != null and cs.shape is BoxShape3D


## Distance from `from` to the first building / structure on the way to `to`, or INF.
func _structure_between(from: Vector3, to: Vector3) -> float:
	var hit := _first_structure(from, to)
	return INF if hit.is_empty() else from.distance_to(hit.position)


## Highest building / structure top under the camera (a ray down from above), or NAN.
func _roof_under(pos: Vector3) -> float:
	var hit := _first_structure(pos + Vector3.UP * 30.0, pos - Vector3.UP * 4.0)
	return NAN if hit.is_empty() else (hit.position as Vector3).y


## The first building / structure hit on the segment. Other hits are stepped past (every instance collider shares one body, so
## excluding a tree's body would hide the houses behind it too).
func _first_structure(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var dir := (to - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, to)
	for i in 6:
		var hit := space.intersect_ray(q)
		if hit.is_empty() or _is_structure(hit):
			return hit
		q.from = (hit.position as Vector3) + dir * 0.05
		if (to - q.from).dot(dir) <= 0.0:
			break
	return {}

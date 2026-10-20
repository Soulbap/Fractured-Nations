## Decides, per unit, whether it is simulated in detail (physics body + navmesh agent)
## or abstractly (UnitState advanced by WorldSim), based on distance to the observer.
##
## The observer is the active camera's point of interest: the possessed soldier in first
## person, the tactical camera's ground focus in RTS. Units closer than promote_radius
## get a body, units farther than demote_radius lose it (hysteresis). The UnitState is
## the same object in both tiers, so identity, position, heading, order and move state
## carry over unchanged; only the node that represents it changes. Bodies are removed
## from the tree at demotion and replaced by a UnitProxy so the tactical view still shows
## and selects the unit.
##
## Around the observer the manager also keeps what bodies need: one runtime-baked
## navmesh area that re-centres when the observer drifts, Terrain3D's dynamic collision
## (it follows the terrain camera, which is the real camera in first person and an
## invisible anchor camera at the focus point in RTS) and the tree-collider streamer.
## Nothing here is sized for the whole map; cost follows the area around one observer.
class_name DetailManager
extends Node

signal bodies_changed(promoted: int, demoted: int)
signal zone_rebaked(info: Dictionary)

const SOLDIER_SCENE := preload("res://scenes/units/soldier.tscn")
const VEHICLE_SCENE := preload("res://scenes/units/vehicle.tscn")

@export var sim: WorldSim
@export var navigation: AreaNavigation
@export var terrain: Terrain3D
@export var game: GameController
@export var rts_camera: RTSCamera
@export var collider_streamer: InstanceColliderStreamer
@export var units_root: Node3D
## Placed structures carve the navmesh (WORLD-BASE-01).
@export var structures: StructureManager
## Units closer than this to the observer get a body.
@export var promote_radius := 120.0
## Bodies farther than this lose it. Must stay below nav_area_size / 2 - nav_max_drift.
@export var demote_radius := 150.0
@export var nav_area_size := 440.0
## Re-bake the navmesh around the observer once it is this far from the area center.
@export var nav_recenter_m := 45.0
## Observer speed above which detail changes wait (fast tactical panning).
@export var settle_speed := 20.0
## Dynamic terrain collision radius (m) around the terrain camera.
@export var collision_radius := 200.0
## Re-centre the navmesh on a worker thread when the observer drifts (camera panning,
## walking, RTS jumps); units in the new area get bodies once it is ready. Possession
## (activate_at) stays synchronous because the body needs ground and a path at once.
@export var async_recenter := true

var observer := Vector3.ZERO
## Invisible camera that Terrain3D follows (collision + LOD) while the tactical camera is active.
var anchor_cam: Camera3D
var nav_center := Vector3(INF, 0, INF)
var last_bake := {}
var bake_count := 0
var promotions := 0
var demotions := 0
var _last_observer := Vector3(INF, 0, INF)
var _speed := 0.0
## Seconds until a requested navmesh rebake (structures changed); < 0: none pending.
var _rebake_in := -1.0
## Centre of a re-centre bake running on a worker (INF: none).
var _recenter_to := Vector3(INF, 0, INF)
var _recenter_t0 := 0


func _ready() -> void:
	anchor_cam = Camera3D.new()
	anchor_cam.name = "TerrainAnchorCamera"
	anchor_cam.current = false
	add_child(anchor_cam)
	process_physics_priority = -10  # before the bodies' own physics step


## Creates the proxy for every unit that has no body yet (call after spawning records).
func create_missing_proxies() -> void:
	for u in sim.state.all_units():
		if not sim.bodies.has(u.id) and not sim.proxies.has(u.id):
			_make_proxy(u)


func nav_covers(p: Vector3) -> bool:
	return absf(p.x - nav_center.x) <= nav_area_size * 0.5 - 8.0 and absf(p.z - nav_center.z) <= nav_area_size * 0.5 - 8.0


func observer_position() -> Vector3:
	if game and game.mode == GameController.Mode.FPS:
		var b := game.possessed_body()
		if b:
			return b.global_position
	return rts_camera.focus if rts_camera else observer


func _physics_process(delta: float) -> void:
	observer = observer_position()
	if _last_observer.is_finite() and delta > 0.0:
		_speed = lerpf(_speed, observer.distance_to(_last_observer) / delta, 0.3)
	_last_observer = observer
	_follow_observer()
	_update(false)
	if _rebake_in >= 0.0 and not _recenter_to.is_finite():
		_rebake_in -= delta
		if _rebake_in < 0.0:
			_rebake(false)


## Structures changed inside rect: rebake the navmesh soon if it covers that area.
## Debounced, so drawing a wall or placing several buildings costs one bake.
func structures_changed(rect: Rect2, delay := 0.4) -> void:
	if not nav_center.is_finite():
		return
	var half := nav_area_size * 0.5
	var area := Rect2(nav_center.x - half, nav_center.z - half, nav_area_size, nav_area_size)
	if area.intersects(rect):
		_rebake_in = delay


## Forces the detailed tier to exist around a position right now (used before possessing
## or framing a unit that is currently abstract). Synchronous: bakes the navmesh for the
## area, builds terrain collision there and gives every unit in range a body.
func activate_at(pos: Vector3) -> void:
	observer = pos
	_last_observer = pos
	_speed = 0.0
	_follow_observer()
	# Terrain3D builds collision around its camera, which may still be a body far away.
	terrain.set_camera(anchor_cam)
	_update(true)


func _follow_observer() -> void:
	var h: float = terrain.data.get_height(observer)
	anchor_cam.global_position = Vector3(observer.x, (0.0 if is_nan(h) else h) + 2.0, observer.z)
	if collider_streamer:
		collider_streamer.target = anchor_cam
	if game and game.mode == GameController.Mode.RTS and terrain.get_camera() != anchor_cam:
		terrain.set_camera(anchor_cam)


func _update(force: bool) -> void:
	var settled := force or _speed < settle_speed
	var demoted := 0
	for id in sim.bodies.keys():
		var b: Node3D = sim.bodies[id]
		var u: UnitState = b.unit
		if u.player_controlled:
			continue
		if _flat_dist(u.position, observer) > demote_radius:
			_demote(u)
			demoted += 1
	if not settled:
		return
	if _recenter_to.is_finite():
		if navigation.has_pending_bake() and not force:
			return  # no new bodies until the area they will walk on is baked
		_finish_recenter()
	var drift := _flat_dist(nav_center, observer) if nav_center.is_finite() else INF
	if drift > nav_recenter_m or force and drift > 1.0:
		_rebake(true, async_recenter and not force and nav_center.is_finite())
		if _recenter_to.is_finite():
			return
	var promoted := 0
	for u in sim.state.units.values():
		if not u.has_body and _flat_dist(u.position, observer) <= promote_radius:
			_promote(u)
			promoted += 1
	if promoted > 0 or demoted > 0:
		promotions += promoted
		demotions += demoted
		bodies_changed.emit(promoted, demoted)


## full: re-centre on the observer with terrain collision (sync). Otherwise only the
## obstacles changed (structures): same area, async bake, collision untouched.
func _rebake(full := true, async := false) -> void:
	var obstacles := []
	var half := nav_area_size * 0.5
	for u in sim.state.units.values():
		if u.kind == UnitState.Kind.VEHICLE and absf(u.position.x - observer.x) < half and absf(u.position.z - observer.z) < half:
			obstacles.append({"position": u.position, "yaw": u.yaw, "size": VehicleBody.FOOTPRINT})
	var vehicles := obstacles.size()
	if structures:
		obstacles.append_array(structures.nav_obstacles(observer, half))
	var h: float = terrain.data.get_height(observer)
	if not full and nav_center.is_finite():
		obstacles = obstacles.slice(0, vehicles)
		if structures:
			obstacles.append_array(structures.nav_obstacles(nav_center, half))
		last_bake = navigation.bake_area(navigation.area_center, nav_area_size, obstacles, true)
		last_bake["vehicle_obstructions"] = vehicles
		last_bake["structure_obstructions"] = obstacles.size() - vehicles
		_rebake_in = -1.0
		bake_count += 1
		zone_rebaked.emit(last_bake)
		return
	last_bake = navigation.bake_area(Vector3(observer.x, 0.0 if is_nan(h) else h, observer.z), nav_area_size, obstacles, async)
	last_bake["vehicle_obstructions"] = vehicles
	last_bake["structure_obstructions"] = obstacles.size() - vehicles
	last_bake["recenter"] = "async" if async else "sync"
	_rebake_in = -1.0
	bake_count += 1
	if async:
		_recenter_to = observer
		_recenter_t0 = Time.get_ticks_usec()
		return
	nav_center = observer
	_update_collision()
	zone_rebaked.emit(last_bake)


## The worker finished the re-centre bake: switch the area and build terrain collision.
func _finish_recenter() -> void:
	nav_center = _recenter_to
	_recenter_to = Vector3(INF, 0, INF)
	last_bake["recenter_wait_ms"] = (Time.get_ticks_usec() - _recenter_t0) / 1000.0
	_update_collision()
	zone_rebaked.emit(last_bake)


## Terrain collision follows the terrain camera; build it for the new area now so
## bodies promoted in the same tick have ground under them.
func _update_collision() -> void:
	var t := Time.get_ticks_usec()
	terrain.collision_radius = collision_radius
	terrain.collision.update(true)
	last_bake["collision_ms"] = (Time.get_ticks_usec() - t) / 1000.0


func _promote(u: UnitState) -> void:
	var proxy: UnitProxy = sim.proxies.get(u.id)
	if proxy:
		sim.unregister_proxy(u.id)
		proxy.get_parent().remove_child(proxy)
		proxy.queue_free()
	var body: Node3D = (SOLDIER_SCENE if u.kind == UnitState.Kind.SOLDIER else VEHICLE_SCENE).instantiate()
	units_root.add_child(body)
	# Lift a little so a body never starts inside the collision shell; gravity settles it.
	if u.kind == UnitState.Kind.SOLDIER:
		var h: float = terrain.data.get_height(u.position)
		u.position.y = (u.position.y if is_nan(h) else h) + 0.3
	body.bind(u, sim)


func _demote(u: UnitState) -> void:
	var body: Node3D = sim.bodies.get(u.id)
	if body == null:
		return
	# The body wrote its final result into the record on its last physics tick; the record
	# is the unit, so nothing needs copying. Remove from the tree first so the registry
	# entry is dropped immediately.
	body.get_parent().remove_child(body)
	body.queue_free()
	u.velocity = Vector3.ZERO
	_make_proxy(u)


func _make_proxy(u: UnitState) -> void:
	var proxy := UnitProxy.new()
	units_root.add_child(proxy)
	proxy.bind(u, sim)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

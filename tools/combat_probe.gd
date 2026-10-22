## COMBAT-TECH-01 research probe (read-only, not gameplay): how well can line of sight
## and shots be resolved on the real reference world at combat ranges?
##   Godot.exe --path . --resolution 1280x720 --script res://tools/combat_probe.gd -- [--at=x,z]
## Loads scenes/world/ref_20km.tscn with the game's physics setup (Terrain3D dynamic
## collision, 200 m radius around the camera; tree colliders 40 m around the observer)
## and compares, for targets 50..800 m away in 32 directions:
##   physics ray (Jolt, what a bullet ray would see),
##   terrain height-map march (Terrain3DData.get_height every 2 m),
##   vegetation trunks from the chunk data (VegetationStreamer.get_cell_instances).
## Prints "PROBE <name> <json>".
extends SceneTree

const RINGS := [50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 600.0, 800.0]
const DIRS := 32
const EYE := 1.6

var world: Node3D
var terrain: Terrain3D
var veg: VegetationStreamer
var cam: Camera3D
var _trees := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var at := Vector2(-7100.0, -7560.0)  # near site A (Nordvest-moen)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var p := a.substr(5).split(",")
			at = Vector2(float(p[0]), float(p[1]))
	world = load("res://scenes/world/ref_20km.tscn").instantiate()
	get_root().add_child(world)
	terrain = world.get_node("Terrain3D")
	veg = world.get_node("Vegetation")
	var player := world.get_node_or_null("Player")
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	terrain.collision_mode = Terrain3DCollision.DYNAMIC_GAME
	terrain.collision_radius = 200
	cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	var o := Vector3(at.x, terrain.data.get_height(Vector3(at.x, 0, at.y)) + EYE, at.y)
	cam.global_position = o + Vector3(0, 2, 0)
	terrain.set_camera(cam)
	var cs: InstanceColliderStreamer = world.get_node_or_null("InstanceColliderStreamer")
	if cs:
		cs.target = cam
	for i in 120:
		await physics_frame
	terrain.collision.update(true)
	for i in 30:
		await physics_frame
	for d in veg.library.meshes:
		if d.collider.x >= 0.0:
			_trees[d.id] = maxf(d.collider.y, 0.25)
	print("PROBE setup ", JSON.stringify({"observer": [o.x, o.y, o.z], "terrain_collision_radius": terrain.collision_radius,
		"tree_collider_radius": cs.radius if cs else -1, "active_tree_colliders": cs.active_count if cs else -1}))

	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 0xFFFFFFFF
	var per_ring := {}
	var t_phys := 0
	var t_height := 0
	var t_trees := 0
	var n := 0
	for r: float in RINGS:
		var stat := {"rays": 0, "phys_blocked": 0, "height_blocked": 0, "trees_blocked": 0,
			"height_blocked_phys_clear": 0, "trees_blocked_phys_clear": 0}
		for k in DIRS:
			var a := k * TAU / DIRS
			var tx := o.x + cos(a) * r
			var tz := o.z + sin(a) * r
			var th: float = terrain.data.get_height(Vector3(tx, 0, tz))
			if is_nan(th):
				continue
			var t := Vector3(tx, th + EYE - 0.2, tz)
			stat.rays += 1
			n += 1
			var u := Time.get_ticks_usec()
			q.from = o
			q.to = t
			var ph := not space.intersect_ray(q).is_empty()
			t_phys += Time.get_ticks_usec() - u
			u = Time.get_ticks_usec()
			var hb := _height_blocked(o, t, 2.0)
			t_height += Time.get_ticks_usec() - u
			u = Time.get_ticks_usec()
			var tb := _trees_blocked(o, t)
			t_trees += Time.get_ticks_usec() - u
			if ph:
				stat.phys_blocked += 1
			if hb:
				stat.height_blocked += 1
				if not ph:
					stat.height_blocked_phys_clear += 1
			if tb:
				stat.trees_blocked += 1
				if not ph:
					stat.trees_blocked_phys_clear += 1
		per_ring[str(int(r))] = stat
	print("PROBE los_by_range ", JSON.stringify(per_ring))
	print("PROBE cost ", JSON.stringify({"rays": n, "us_physics_ray": snappedf(float(t_phys) / n, 0.01),
		"us_heightmap_march_2m": snappedf(float(t_height) / n, 0.01), "us_tree_trunk_test": snappedf(float(t_trees) / n, 0.01)}))
	quit()


## True if the straight segment dips below the terrain anywhere (sampled every step m).
func _height_blocked(a: Vector3, b: Vector3, step: float) -> bool:
	var len := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(1, int(len / step))
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		var h: float = terrain.data.get_height(p)
		if not is_nan(h) and h > p.y:
			return true
	return false


## True if a tree trunk (collider radius from the library) lies on the segment, from the
## stored vegetation cells (what a data-based shot or LOS test would use).
func _trees_blocked(a: Vector3, b: Vector3) -> bool:
	var cs := veg.cell_size_m
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2(1, 1)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2(1, 1)
	var seg := Vector2(b.x - a.x, b.z - a.z)
	var seg_len := seg.length()
	var dir := seg / seg_len
	for cx in range(floori(lo.x / cs), floori(hi.x / cs) + 1):
		for cz in range(floori(lo.y / cs), floori(hi.y / cs) + 1):
			for inst in veg.get_cell_instances(Vector2i(cx, cz), _trees.keys()):
				var p: Vector3 = (inst[1] as Transform3D).origin
				var rel := Vector2(p.x - a.x, p.z - a.z)
				var along := rel.dot(dir)
				if along < 1.0 or along > seg_len - 1.0:
					continue
				var off := absf(rel.x * dir.y - rel.y * dir.x)
				var r: float = _trees[inst[0]] * (inst[1] as Transform3D).basis.get_scale().x
				if off < r:
					# Trunks are tall enough to block an eye-height line near the ground.
					var y := a.y + (b.y - a.y) * along / seg_len
					if y - p.y < 8.0:
						return true
	return false

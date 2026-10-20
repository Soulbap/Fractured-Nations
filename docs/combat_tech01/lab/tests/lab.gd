## COMBAT-TECH-01 isolated experiments (not part of the game).
##   Godot_console.exe --headless --path <lab> --script res://tests/lab.gd
## Prints "LAB <name> <json>".
extends SceneTree

const L_WORLD := 1      # terrain / structures
const L_UNIT := 2       # soldier CharacterBody3D capsules
const L_HURT := 8       # hurtbox areas

var root3d: Node3D


func _init() -> void:
	_run.call_deferred()


func _log(name: String, d: Variant) -> void:
	print("LAB %s %s" % [name, JSON.stringify(d)])


func _run() -> void:
	root3d = Node3D.new()
	get_root().add_child(root3d)
	_log("engine", {"version": Engine.get_version_info().string, "physics": ProjectSettings.get_setting("physics/3d/physics_engine")})
	await _exp_hurtbox()
	await _exp_bukkbeek_weapon()
	await _exp_raycast_cost()
	_exp_load_addons()
	await _exp_record_hits()
	quit()


# --- 5. record-based hit test vs physics hurtboxes ----------------------------------

## A shot tested against soldier records (position + capsule + head sphere, no nodes)
## with Geometry3D, compared ray by ray with the Jolt hurtbox result.
func _exp_record_hits() -> void:
	var space := root3d.get_world_3d().direct_space_state
	var units := []  # [base position, health node] of fresh soldiers in an empty area
	for i in 40:
		var p := Vector3(randf_range(-40, 40), 0, randf_range(-40, 40)) + Vector3(0, 0, 400)
		var s := _soldier(p, 0.38)
		units.append(p)
	await _frames(5)
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = L_HURT
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var agree := 0
	var disagree := 0
	var phys_hits := 0
	var rec_hits := 0
	var t_phys := 0
	var t_rec := 0
	for i in 3000:
		var from := Vector3(randf_range(-60, 60), randf_range(0.5, 2.0), 400 + randf_range(-60, 60))
		var to := from + Vector3(randf_range(-1, 1), randf_range(-0.05, 0.05), randf_range(-1, 1)).normalized() * 120.0
		var u := Time.get_ticks_usec()
		q.from = from
		q.to = to
		var r := space.intersect_ray(q)
		t_phys += Time.get_ticks_usec() - u
		var phys := ""
		if not r.is_empty():
			var area: Node = r.collider
			phys = "%d:%s" % [units.find(area.get_parent().global_position), area.name]
			phys_hits += 1
		u = Time.get_ticks_usec()
		var rec := _record_hit(from, to, units)
		t_rec += Time.get_ticks_usec() - u
		if rec != "":
			rec_hits += 1
		if rec == phys:
			agree += 1
		else:
			disagree += 1
	_log("exp5_record_hits_vs_hurtboxes", {"rays": 3000, "physics_hits": phys_hits, "record_hits": rec_hits, "agree": agree, "disagree": disagree,
		"us_physics_area_ray": snappedf(float(t_phys) / 3000.0, 0.01), "us_record_test_40_units": snappedf(float(t_rec) / 3000.0, 0.01)})


## Nearest hit among soldier records: head sphere (r 0.15 at 1.65 m) and body capsule
## (r 0.38, from 0.375 to 1.125 m between the hemisphere centres, like the hurtbox).
func _record_hit(from: Vector3, to: Vector3, units: Array) -> String:
	var best := INF
	var out := ""
	for i in units.size():
		var p: Vector3 = units[i]
		var hs := Geometry3D.segment_intersects_sphere(from, to, p + Vector3(0, 1.65, 0), 0.15)
		if not hs.is_empty():
			var d := from.distance_to(hs[0])
			if d < best:
				best = d
				out = "%d:HurtHead" % i
		var hb := _segment_capsule(from, to, p + Vector3(0, 0.375, 0), p + Vector3(0, 1.125, 0), 0.38)
		if hb >= 0.0 and hb < best:
			best = hb
			out = "%d:HurtBody" % i
	return out


## Distance along the segment to a vertical capsule, or -1.
func _segment_capsule(from: Vector3, to: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var best := -1.0
	# Geometry3D's cylinder runs along Z: swap Y and Z (distances are preserved).
	var m := (a + b) * 0.5
	var f := from - m
	var t := to - m
	var c := Geometry3D.segment_intersects_cylinder(Vector3(f.x, f.z, f.y), Vector3(t.x, t.z, t.y), b.y - a.y, r)
	if not c.is_empty():
		var h: Vector3 = c[0]
		best = from.distance_to(Vector3(h.x, h.z, h.y) + m)
	for cap in [a, b]:
		var s := Geometry3D.segment_intersects_sphere(from, to, cap, r)
		if not s.is_empty():
			var d := from.distance_to(s[0])
			if best < 0.0 or d < best:
				best = d
	return best


# --- helpers ----------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## A soldier like ours: CharacterBody3D capsule (layer 2) plus hurtbox areas (layer 8):
## body capsule and a head sphere with a x2 multiplier, all feeding one Health.
func _soldier(pos: Vector3, hurt_radius: float) -> Dictionary:
	var body := CharacterBody3D.new()
	body.collision_layer = L_UNIT
	body.collision_mask = L_WORLD
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	var health := Health.new()
	health.name = "Health"
	body.add_child(health)
	var hurt := HurtBox3D.new()
	hurt.name = "HurtBody"
	hurt.collision_layer = L_HURT
	hurt.collision_mask = 0
	hurt.health = health
	var hs := CollisionShape3D.new()
	var hcap := CapsuleShape3D.new()
	hcap.radius = hurt_radius
	hcap.height = 1.5
	hs.shape = hcap
	hs.position.y = 0.75
	hurt.add_child(hs)
	body.add_child(hurt)
	var head := HurtBox3D.new()
	head.name = "HurtHead"
	head.collision_layer = L_HURT
	head.collision_mask = 0
	head.health = health
	head.modifiers = {HealthActionType.Enum.KINETIC: HealthModifier.new(0, 2.0)}
	var hd := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.15
	hd.shape = sph
	hd.position.y = 1.65
	head.add_child(hd)
	body.add_child(head)
	root3d.add_child(body)
	body.global_position = pos
	return {"body": body, "health": health}


func _wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = L_WORLD
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	w.add_child(cs)
	root3d.add_child(w)
	w.global_position = pos
	return w


func _hitscan(from: Vector3, to: Vector3, mask: int, bodies: bool) -> HitScan3D:
	var hs := HitScan3D.new()
	hs.collide_with_areas = true
	hs.collide_with_bodies = bodies
	hs.collision_mask = mask
	hs.actions = [HealthAction.new(Health.Affect.DAMAGE, HealthActionType.Enum.KINETIC, 25)]
	root3d.add_child(hs)
	hs.global_position = from
	hs.target_position = hs.to_local(to)
	return hs


# --- 1. health / hurtbox / hitscan through Jolt -------------------------------------

func _exp_hurtbox() -> void:
	var out := {}
	# a) mask = hurtboxes only, bodies off: hits the area, damage applied.
	var s := _soldier(Vector3(0, 0, -10), 0.38)
	await _frames(3)
	var hs := _hitscan(Vector3(0, 1.0, 0), Vector3(0, 1.0, -20), L_HURT, false)
	hs.force_raycast_update()
	var hit_a := str(hs.get_collider().name) if hs.get_collider() else "none"
	hs.fire()
	out.a_areas_only = {"collider": hit_a, "health": s.health.current}
	# b) head shot: x2 multiplier from the head hurtbox.
	var hs2 := _hitscan(Vector3(0, 1.65, 0), Vector3(0, 1.65, -20), L_HURT, false)
	hs2.force_raycast_update()
	var hit_b := str(hs2.get_collider().name) if hs2.get_collider() else "none"
	var before: int = s.health.current
	hs2.fire()
	out.b_head = {"collider": hit_b, "damage": before - s.health.current}
	# c) wall in front, mask = hurtboxes only: the shot goes THROUGH the wall.
	_wall(Vector3(0, 1, -5), Vector3(4, 3, 0.5))
	await _frames(3)
	var hs3 := _hitscan(Vector3(0, 1.0, 0), Vector3(0, 1.0, -20), L_HURT, false)
	hs3.force_raycast_update()
	out.c_wall_mask_hurt_only = {"collider": str(hs3.get_collider().name) if hs3.get_collider() else "none"}
	# d) wall in front, mask = world + hurtboxes, bodies on: the wall stops it.
	var hs4 := _hitscan(Vector3(0, 1.0, 0), Vector3(0, 1.0, -20), L_WORLD | L_HURT, true)
	hs4.force_raycast_update()
	out.d_wall_mask_world_hurt = {"collider": str(hs4.get_collider().get_class()) if hs4.get_collider() else "none"}
	# e) no wall, mask = world + unit body + hurtbox, hurtbox same size as capsule: which wins?
	var s2 := _soldier(Vector3(6, 0, -10), 0.35)
	await _frames(3)
	var hs5 := _hitscan(Vector3(6, 1.0, 0), Vector3(6, 1.0, -20), L_WORLD | L_UNIT | L_HURT, true)
	hs5.force_raycast_update()
	out.e_body_vs_hurt_same_size = {"collider_class": hs5.get_collider().get_class() if hs5.get_collider() else "none",
		"collider": str(hs5.get_collider().name) if hs5.get_collider() else "none"}
	# f) shooter inside its own hurtbox (shooting from the chest): Jolt hit_from_inside.
	var s3 := _soldier(Vector3(-6, 0, 0), 0.38)
	await _frames(3)
	var hs6 := _hitscan(Vector3(-6, 1.0, 0), Vector3(-6, 1.0, -20), L_HURT, false)
	hs6.hit_from_inside = true
	hs6.force_raycast_update()
	var own_true := str(hs6.get_collider().get_parent().name) if hs6.get_collider() else "none"
	hs6.hit_from_inside = false
	hs6.force_raycast_update()
	var own_false := "hit" if hs6.get_collider() else "none"
	var q := PhysicsRayQueryParameters3D.create(Vector3(-6, 1.0, 0), Vector3(-6, 1.0, -20), L_HURT)
	q.collide_with_areas = true
	var default_hfi := q.hit_from_inside
	out.f_shooter_inside_own_hurtbox = {"hit_from_inside_true": own_true, "hit_from_inside_false": own_false,
		"query_default_hit_from_inside": default_hfi, "raycast3d_default": RayCast3D.new().hit_from_inside, "shooter": str(s3.body.name)}
	# g) death signal.
	var died := {"n": 0}
	s.health.died.connect(func(_e: Node) -> void: died.n += 1)
	for i in 6:
		hs.fire()
	out.g_death = {"health": s.health.current, "died_signals": died.n, "is_dead": s.health.is_dead()}
	_log("exp1_hurtbox_jolt", out)


# --- 2. bukkbeek weapon fired from code, no player -----------------------------------

class Target extends StaticBody3D:
	var hits := 0
	var damage := 0.0
	func get_damage(amount: float, _dir: Vector3) -> void:
		hits += 1
		damage += amount


func _exp_bukkbeek_weapon() -> void:
	var out := {}
	var weapon_script: GDScript = load("res://third/bukkbeek/weapon.gd")
	var w: Node3D = Node3D.new()
	# The nodes weapon.gd reads with $ in _ready.
	for n in ["CooldownTimer", "ReloadTimer"]:
		var t := Timer.new()
		t.name = n
		t.one_shot = true
		w.add_child(t)
	for n in ["StandardAimPosition", "FocusedAimPosition"]:
		var m := Marker3D.new()
		m.name = n
		w.add_child(m)
	for n in ["TestCamera", "TestTarget"]:
		var x := Node3D.new()
		x.name = n
		w.add_child(x)
	w.set_script(weapon_script)
	w.set("damage", 34.0)
	w.set("cooldown", 0.1)
	w.set("mag_capacity", 3)
	w.set("reload_time", 0.2)
	w.set("bullet_type", 3)  # ASSAULT
	w.set("firing_distance", 50.0)
	w.set("standard_aim_angle", 0.0)
	root3d.add_child(w)
	w.get_node("CooldownTimer").timeout.connect(w._on_cooldown_timer_timeout)
	w.get_node("ReloadTimer").timeout.connect(w._on_reload_timer_timeout)
	# An "AI" muzzle: a RayCast3D on a pivot we own, aimed at a target 20 m away.
	var pivot := Node3D.new()
	root3d.add_child(pivot)
	pivot.global_position = Vector3(20, 1.2, 0)
	var ray := RayCast3D.new()
	ray.target_position = Vector3(0, 0, -50)
	ray.collision_mask = L_WORLD
	pivot.add_child(ray)
	var tgt := Target.new()
	tgt.collision_layer = L_WORLD
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1, 2, 1)
	cs.shape = b
	tgt.add_child(cs)
	root3d.add_child(tgt)
	tgt.global_position = Vector3(20, 1.0, -20)
	w.initialize(null, ray, pivot)
	w.activate(false)
	await _frames(3)
	var fired := 0
	var reserve_before: int = get_root().get_node("Bullets")._get_ammo(3)
	for i in 40:
		if w.try_fire(i == 0):
			fired += 1
		await _frames(3)
	out.fired = fired
	out.target_hits = tgt.hits
	out.target_damage = tgt.damage
	out.mag_now = w.get_current_mag()
	out.global_reserve_before = reserve_before
	out.global_reserve_after = get_root().get_node("Bullets")._get_ammo(3)
	out.reserve_is_global_autoload = true
	_log("exp2_bukkbeek_weapon_from_code", out)


# --- 3. Jolt ray cost for perception / line of sight --------------------------------

func _exp_raycast_cost() -> void:
	var space := root3d.get_world_3d().direct_space_state
	# 64 soldiers in a field with 40 walls, like a mid-size firefight.
	var units: Array[Vector3] = []
	for i in 64:
		var p := Vector3(randf_range(-150, 150) + 100, 0, randf_range(-150, 150))
		_soldier(p, 0.38)
		units.append(p + Vector3.UP * 1.6)
	for i in 40:
		_wall(Vector3(randf_range(-150, 150) + 100, 1.5, randf_range(-150, 150)), Vector3(randf_range(2, 10), 3, 0.6))
	await _frames(5)
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = L_WORLD
	var n := 0
	var blocked := 0
	var t0 := Time.get_ticks_usec()
	for a in units.size():
		for b in range(a + 1, units.size()):
			q.from = units[a]
			q.to = units[b]
			if not space.intersect_ray(q).is_empty():
				blocked += 1
			n += 1
	var dt := Time.get_ticks_usec() - t0
	# Shots: world + hurtboxes, areas on.
	var q2 := PhysicsRayQueryParameters3D.new()
	q2.collision_mask = L_WORLD | L_HURT
	q2.collide_with_areas = true
	var t1 := Time.get_ticks_usec()
	for i in 1000:
		q2.from = units[i % units.size()]
		q2.to = units[(i * 7 + 3) % units.size()]
		space.intersect_ray(q2)
	var dt2 := Time.get_ticks_usec() - t1
	_log("exp3_jolt_ray_cost", {"los_pairs": n, "los_blocked": blocked, "los_total_ms": dt / 1000.0, "us_per_los_ray": float(dt) / n,
		"shot_rays": 1000, "us_per_shot_ray_with_areas": dt2 / 1000.0})


# --- 4. third-party scripts load under 4.7.2 ---------------------------------------

func _exp_load_addons() -> void:
	var out := {}
	for p in ["res://addons/beehave/nodes/beehave_tree.gd", "res://addons/beehave/nodes/composites/selector.gd",
			"res://addons/beehave/nodes/leaves/action.gd", "res://addons/tattomoosa.vision_cone_3d/src/VisionCone3D.gd",
			"res://addons/health_hitbox_hurtbox/health/health.gd"]:
		var s: Script = load(p)
		out[p.get_file()] = s != null and s.can_instantiate()
	_log("exp4_script_load", out)

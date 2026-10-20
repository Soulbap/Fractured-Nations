## Scripted checks of COMBAT-01a (combat core and FPS rifle) on the reference world.
##
##   Godot.exe --path . --resolution 1600x900 --log-file combat.log res://scenes/game/world_ref_20km.tscn -- --combat-test [--shots]
##
## Uses the UNIT-01A test squads on an open meadow found from the map: Alpha fires, Sierra
## (South) and Bravo are targets. First-person shots go through the real input (LMB, R,
## V, RMB, Tab, P, F5 / F9); other shots through CombatSim.request_fire, the interface AI
## will use. Prints "COMBAT <check> <json>", writes res://benchmarks/raw/combat_test.json
## and (with --shots) docs/combat01a/c01a_*.jpg.
class_name CombatSelfTest
extends SquadSelfTest

var combat: CombatSim
var lof: LineOfFire
var def: WeaponDef
var shooter := -1
## Every death during the run (diagnostics).
var deaths := []


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/combat01a"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	lof = combat.line
	# The test window may not get OS mouse capture; the trigger must still work.
	SoldierBody.require_mouse_capture = false
	def = combat.weapon(&"rifle")
	tree.create_timer(900.0).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish in 900 s")
		_finish())
	var state := demo.sim.state
	state.unit_died.connect(func(u: UnitState) -> void:
		deaths.append({"id": u.id, "name": u.unit_name, "killer": u.killer_id, "t": snappedf(state.time, 0.01)}))
	await _physics(60)
	_load_world_data()
	for sq: SquadState in state.all_squads():
		match sq.squad_name:
			"Alpha": alpha = sq
			"Bravo": bravo = sq
			"Sierra": sierra = sq
	var armed := 0
	for u in state.soldiers():
		if u.weapon_id == &"rifle" and u.mag == def.magazine_size and u.reserve == def.reserve_start and u.alive:
			armed += 1
	_log("startup", {"soldiers": state.count_of(UnitState.Kind.SOLDIER), "armed_full": armed, "weapon": {"rpm": def.rounds_per_minute,
		"mag": def.magazine_size, "reload_s": def.reload_time, "damage": def.damage, "head_x": def.head_multiplier,
		"falloff": [def.falloff_start, def.falloff_end, def.min_damage_fraction], "spread_base_deg": def.spread_base_deg}})
	_expect(armed == state.count_of(UnitState.Kind.SOLDIER), "not every soldier starts with a full rifle")

	# Test area: open meadow; shooter = Alpha's first soldier.
	_press(KEY_TAB)
	await _physics(3)
	area = _find_spot("meadow", demo.sites[0].position)
	_expect(area.is_finite(), "no open area")
	if not area.is_finite():
		_finish()
		return
	demo.rts_camera.frame(area, 0.0, 80.0)
	await _seconds(3.0)
	shooter = alpha.members[0]
	_station(alpha, area + Vector3(-20, 0, 15), PI)
	_station(bravo, area + Vector3(-20, 0, 30), PI)
	_station(sierra, area + Vector3(20, 0, -30), 0.0)
	_put(shooter, area, PI)  # facing +Z is yaw PI; we aim explicitly anyway
	await _seconds(2.5)

	_log("ranges_fps", await _ranges_check())
	_log("zones", await _zones_check())
	_log("self_hit", await _self_hit_check())
	_log("friendly_fire", await _friendly_check())
	_log("occlusion", await _occlusion_check())
	_log("determinism", await _determinism_check())
	_log("ammo_rate_reload", await _ammo_check())
	_log("persistence", await _persistence_check())
	_log("death", await _death_check())
	_log("death_while_possessed", await _possessed_death_check())
	_log("analytic_vs_physics", await _agreement_check())
	_log("performance", await _perf_check())
	_finish()


# --- Helpers -------------------------------------------------------------------------

func _u(id: int) -> UnitState:
	return demo.sim.state.get_unit(id)


## Moves one soldier record (and its body) to p, facing yaw, without orders.
func _put(id: int, p: Vector3, yaw: float) -> void:
	var g := demo.on_ground(p.x, p.z, 0.3)
	var u := _u(id)
	demo.sim.state.halt(id)
	u.position = g
	u.yaw = yaw
	var b := demo.sim.body_of(id) as SoldierBody
	if b:
		b.teleport(g, yaw)


func _reset(id: int) -> void:
	var u := _u(id)
	u.health = 100.0
	u.mag = def.magazine_size
	u.reserve = def.reserve_start
	u.reload_until = -1.0
	u.next_shot_at = 0.0
	u.bloom = 0.0


func _torso(id: int) -> Vector3:
	return _u(id).position + Vector3(0, 0.9, 0)


func _head(id: int) -> Vector3:
	return _u(id).position + Vector3(0, LineOfFire.HEAD_Y, 0)


## A point at distance d from the shooter in a direction whose line of fire is clear
## (terrain, trees, structures), on the ground.
func _clear_spot(from_id: int, d: float) -> Vector3:
	var eye := CombatSim.eye_of(_u(from_id))
	for k in 48:
		var a := k * TAU / 48.0
		var p := demo.on_ground(_u(from_id).position.x + cos(a) * d, _u(from_id).position.z + sin(a) * d, 0.3)
		if absf(p.x) > 9500.0 or absf(p.z) > 9500.0:
			continue
		if lof.clear_line(eye, p + Vector3(0, 0.9, 0)) and lof.clear_line(eye, p + Vector3(0, LineOfFire.HEAD_Y, 0)):
			return p
	return Vector3.INF


func _possess(id: int) -> SoldierBody:
	demo.rts.select([id])
	_press(KEY_P)
	await _physics(8)
	return demo.game.possessed_body()


func _leave() -> void:
	if demo.game.mode == GameController.Mode.FPS:
		_press(KEY_TAB)
		await _physics(5)


## One trigger pull in first person (press, two ticks, release, settle).
func _click_fire() -> void:
	Input.action_press("fire")
	await _physics(2)
	Input.action_release("fire")
	await _physics(4)


## Points the possessed soldier's camera (not its feet) at a world point.
func _fps_shot_at(body: SoldierBody, at: Vector3) -> void:
	var d := at - body.camera.global_position
	body.rotation.y = atan2(-d.x, -d.z)
	body.head.rotation.x = asin(clampf(d.normalized().y, -1.0, 1.0))
	await _physics(1)
	d = at - body.camera.global_position
	body.rotation.y = atan2(-d.x, -d.z)
	body.head.rotation.x = asin(clampf(d.normalized().y, -1.0, 1.0))


# --- 1. ranges -----------------------------------------------------------------------

func _ranges_check() -> Dictionary:
	var out := {}
	var targets: Array = sierra.members
	var body := await _possess(shooter)
	_expect(body != null, "could not possess the shooter")
	if body == null:
		return out
	await _physics(5)
	var i := 0
	for d: float in [20.0, 150.0, 250.0]:
		var tid: int = targets[i]
		i += 1
		var spot := _clear_spot(shooter, d)
		if not spot.is_finite():
			out[str(d)] = {"error": "no clear line"}
			_expect(false, "no clear line at %d m" % d)
			continue
		_put(tid, spot, 0.0)
		_reset(tid)
		await _physics(5)
		var hp0 := _u(tid).health
		var shots_fired := 0
		var hits := []
		var damage_each := []
		var fired := []
		var listener := func(shot: Dictionary) -> void:
			if shot.shooter == shooter:
				fired.append(shot.blocker)
				if shot.hit_unit == tid:
					hits.append(shot.zone)
					damage_each.append(snappedf(shot.damage, 0.01))
		demo.sim.state.shot_fired.connect(listener)
		# Semi-automatic aimed shots at the torso; at 250 m a few may miss (spread).
		combat.set_fire_mode(shooter, false)
		for k in 6:
			await _fps_shot_at(body, _torso(tid))
			await _click_fire()
			shots_fired += 1
			await _physics(int(def.fire_interval() * 60.0) + 2)
			if hits.size() >= 2:
				break
		demo.sim.state.shot_fired.disconnect(listener)
		var dist := CombatSim.eye_of(_u(shooter)).distance_to(_torso(tid))
		var expected := def.damage * def.body_multiplier * def.falloff(dist)
		var ok := not hits.is_empty() and absf(float(damage_each[0]) - expected) < 0.6
		out[str(int(d))] = {"distance_m": snappedf(dist, 0.1), "target_has_body": _u(tid).has_body, "trigger_pulls": shots_fired, "fired": fired.size(), "results": fired, "hits": hits.size(),
			"zones": hits, "damage_each": damage_each, "expected_body_damage": snappedf(expected, 0.01), "hp": [hp0, _u(tid).health], "hud_hits": demo.hud.hits_seen}
		_expect(ok, "FPS shots at %d m did not do the expected damage (%s)" % [d, JSON.stringify(out[str(int(d))])])
		_reset(tid)
		if shots and d == 20.0:
			await _fps_shot_at(body, _torso(tid))
			Input.action_press("fire")
			await _physics(2)
			_shot("fps_rifle_hit")
			Input.action_release("fire")
			await _physics(10)
		if shots and d == 250.0:
			Input.action_press("aim")
			await _physics(20)
			await _fps_shot_at(body, _torso(tid))
			await _physics(4)
			Input.action_press("fire")
			await _physics(2)
			_shot("long_range_250m_ads")
			Input.action_release("fire")
			Input.action_release("aim")
			await _physics(10)
		_reset(tid)
	_reset(shooter)
	return out


# --- 2. zones ------------------------------------------------------------------------

func _zones_check() -> Dictionary:
	var tid: int = sierra.members[0]
	var spot := _clear_spot(shooter, 20.0)
	_put(tid, spot, 0.0)
	_reset(tid)
	await _physics(3)
	var body := demo.game.possessed_body()
	combat.set_fire_mode(shooter, false)
	var res := {}
	for zone in ["head", "body"]:
		_reset(tid)
		var dmg := []
		var listener := func(shot: Dictionary) -> void:
			if shot.shooter == shooter and shot.hit_unit == tid:
				dmg.append([shot.zone, snappedf(shot.damage, 0.01)])
		demo.sim.state.shot_fired.connect(listener)
		await _fps_shot_at(body, _head(tid) if zone == "head" else _torso(tid))
		await _click_fire()
		demo.sim.state.shot_fired.disconnect(listener)
		res[zone] = dmg
	var head_ok: bool = not res.head.is_empty() and res.head[0][0] == LineOfFire.Zone.HEAD and absf(res.head[0][1] - def.damage * def.head_multiplier) < 0.6
	var body_ok: bool = not res.body.is_empty() and res.body[0][0] == LineOfFire.Zone.BODY and absf(res.body[0][1] - def.damage) < 0.6
	_expect(head_ok and body_ok, "head / body damage wrong (%s)" % JSON.stringify(res))
	_reset(tid)
	return {"head": res.head, "body": res.body, "expected": {"head": def.damage * def.head_multiplier, "body": def.damage}}


# --- 3. self-hit ---------------------------------------------------------------------

func _self_hit_check() -> Dictionary:
	var body := demo.game.possessed_body()
	var u := _u(shooter)
	_reset(shooter)
	var hp := u.health
	# Straight down through the own body and feet, then along the body at the chest.
	body.head.rotation.x = -deg_to_rad(88.0)
	await _physics(1)
	var hits_self := 0
	var listener := func(shot: Dictionary) -> void:
		if shot.hit_unit == shooter:
			hits_self += 1
	demo.sim.state.shot_fired.connect(listener)
	await _click_fire()
	var down := combat.preview_shot(shooter, CombatSim.eye_of(u), Vector3(0.05, -1, 0), 1, 0.0)
	var along := combat.preview_shot(shooter, u.position + Vector3(0, 1.0, 0), Vector3(0, 0, -1), 1, 0.0)
	demo.sim.state.shot_fired.disconnect(listener)
	var out := {"hp_before": hp, "hp_after": u.health, "shots_hitting_self": hits_self, "down_blocker": down.blocker,
		"down_distance_m": snappedf(down.distance, 0.01), "from_inside_chest_blocker": along.blocker}
	_expect(u.health == hp and hits_self == 0 and down.hit_unit != shooter and along.hit_unit != shooter, "a soldier hit itself (%s)" % JSON.stringify(out))
	body.head.rotation.x = 0.0
	return out


# --- 4. friendly fire ----------------------------------------------------------------

func _friendly_check() -> Dictionary:
	var mate: int = alpha.members[1]
	var spot := _clear_spot(shooter, 20.0)
	_put(mate, spot, 0.0)
	_reset(mate)
	await _physics(3)
	var body := demo.game.possessed_body()
	await _fps_shot_at(body, _torso(mate))
	await _click_fire()
	var out := {"same_faction": _u(mate).faction == _u(shooter).faction, "hp": _u(mate).health}
	_expect(_u(mate).health < 100.0, "friendly fire did not damage a squad mate")
	_reset(mate)
	_put(mate, area + Vector3(-20, 0, 15), PI)
	return out


# --- 5. / 6. occlusion ---------------------------------------------------------------

func _occlusion_check() -> Dictionary:
	await _leave()
	var out := {}
	var s := _u(shooter)
	var eye := CombatSim.eye_of(s)
	var tid: int = sierra.members[1]
	# a) HESCO wall 10 m in front of a target 20 m away.
	var dir := Vector3(1, 0, 0)
	var t_pos := demo.on_ground(s.position.x + 20.0, s.position.z, 0.3)
	var w0 := demo.on_ground(s.position.x + 10.0, s.position.z - 4.0, 0.0)
	var w1 := demo.on_ground(s.position.x + 10.0, s.position.z + 4.0, 0.0)
	# Tall HESCO (2.2 m): the standard 1.4 m cell is below the eye-to-torso line at 10 m.
	var wall := cs.add_line(&"hesco_tall", PackedVector3Array([w0, w1]))
	# b) a barracks between the shooter and a target 20 m the other way.
	var bdef := StructureCatalog.get_def(&"barracks")
	var chk := sm.check_building(bdef, demo.on_ground(s.position.x - 10.0, s.position.z, 0.0), PI * 0.5, -1, true)
	var barracks: StructureState = cs.add_building(&"barracks", chk.xform.origin, PI * 0.5) if chk.ok else null
	await _seconds(1.0)
	_put(tid, t_pos, 0.0)
	_reset(tid)
	var hesco := _occlusion_case(eye, _torso(tid), tid)
	_put(tid, demo.on_ground(s.position.x - 20.0, s.position.z, 0.3), 0.0)
	var bld := _occlusion_case(eye, _torso(tid), tid)
	out.hesco = hesco
	out.building = bld
	out.building_placed = barracks != null
	_expect(hesco.blocker == "structure" and hesco.target_hp == 100.0, "HESCO did not stop the shot (%s)" % JSON.stringify(hesco))
	_expect(barracks != null and bld.blocker == "structure" and bld.target_hp == 100.0, "the building did not stop the shot (%s)" % JSON.stringify(bld))
	if shots:
		var body := await _possess(shooter)
		if body:
			_put(tid, t_pos, 0.0)
			await _physics(3)
			combat.set_fire_mode(shooter, true)
			await _fps_shot_at(body, _torso(tid))
			Input.action_press("fire")
			await _physics(9)
			_shot("shooting_at_hesco")
			Input.action_release("fire")
			await _physics(10)
			_reset(shooter)
			await _leave()
	# c) terrain: a target behind a hill 250-600 m away (data-blocked).
	var hill := _find_blocked(eye, "terrain", 250.0, 600.0)
	# d) vegetation: a target 25 m behind a tree trunk 60-160 m away (beyond 40 m colliders).
	var tree_t := _find_tree_target(eye, 60.0, 160.0)
	out.terrain = _far_case(eye, hill, tid, "terrain")
	out.tree = _far_case(eye, tree_t, tid, "tree")
	# 6. The same with the camera 12 km away: no physics anywhere near, same answers.
	demo.rts_camera.frame(demo.sites[2].position, 0.0, 80.0)
	await _seconds(3.0)
	var far := {}
	_put(tid, t_pos, 0.0)
	far.hesco = _occlusion_case(eye, _torso(tid), tid).blocker
	_put(tid, demo.on_ground(s.position.x - 20.0, s.position.z, 0.3), 0.0)
	far.building = _occlusion_case(eye, _torso(tid), tid).blocker
	far.terrain = _far_case(eye, hill, tid, "terrain").blocker if hill.is_finite() else "n/a"
	far.tree = _far_case(eye, tree_t, tid, "tree").blocker if tree_t.is_finite() else "n/a"
	far.target_has_body = _u(tid).has_body
	far.shooter_has_body = _u(shooter).has_body
	out.camera_12km_away = far
	_expect(far.hesco == "structure" and far.building == "structure" and far.terrain == "terrain" and far.tree == "tree",
		"occlusion changed with the camera far away (%s)" % JSON.stringify(far))
	demo.rts_camera.frame(area, 0.0, 80.0)
	await _seconds(3.0)
	_put(tid, area + Vector3(20, 0, -30), 0.0)
	_reset(tid)
	if wall:
		cs.remove(wall.id)
	if barracks:
		cs.remove(barracks.id)
	await _seconds(0.5)
	return out


## A shot by the shooter's AI path (not possessed) at a point: blocker + target health,
## plus what a physics ray would have said (camera-local).
func _occlusion_case(eye: Vector3, at: Vector3, tid: int) -> Dictionary:
	_reset(tid)
	_reset(shooter)
	var dir := (at - eye).normalized()
	var r := combat.request_fire(shooter, eye, dir, CombatSim.Source.AI)
	var phys := _physics_world_dist(eye, at)
	return {"fired": r.get("fired", false), "blocker": r.get("blocker", ""), "distance_m": snappedf(r.get("distance", -1.0), 0.01),
		"target_hp": _u(tid).health, "physics_world_hit_m": snappedf(phys, 0.01) if phys < INF else "none"}


func _far_case(eye: Vector3, p: Vector3, tid: int, expect: String) -> Dictionary:
	if not p.is_finite():
		_expect(false, "no %s test geometry found" % expect)
		return {"blocker": "n/a"}
	_put(tid, p, 0.0)
	var res := _occlusion_case(eye, _torso(tid), tid)
	res["target_distance_m"] = snappedf(eye.distance_to(_torso(tid)), 0.1)
	res["target_has_body"] = _u(tid).has_body
	_expect(res.blocker == expect and res.target_hp == 100.0, "%s did not stop the shot (%s)" % [expect, JSON.stringify(res)])
	return res


func _find_blocked(eye: Vector3, kind: String, lo: float, hi: float) -> Vector3:
	for d in range(int(lo), int(hi), 25):
		for k in 32:
			var a := k * TAU / 32.0
			var p := demo.on_ground(eye.x + cos(a) * d, eye.z + sin(a) * d, 0.3)
			if absf(p.x) > 9500.0 or absf(p.z) > 9500.0:
				continue
			var r := lof.trace(eye, p + Vector3(0, 0.9, 0), shooter, false)
			if r.blocker == kind and r.distance > 120.0:
				return p
	return Vector3.INF


func _find_tree_target(eye: Vector3, lo: float, hi: float) -> Vector3:
	var cs_m := 128.0
	for cell_r in range(0, 3):
		for cx in range(floori((eye.x - hi) / cs_m), floori((eye.x + hi) / cs_m) + 1):
			for cz in range(floori((eye.z - hi) / cs_m), floori((eye.z + hi) / cs_m) + 1):
				for inst in demo.vegetation.get_cell_instances(Vector2i(cx, cz), [1, 2, 3, 4, 5, 6]):
					var o: Vector3 = (inst[1] as Transform3D).origin
					var d := Vector2(o.x - eye.x, o.z - eye.z).length()
					if d < lo or d > hi:
						continue
					var flat := Vector3(o.x - eye.x, 0, o.z - eye.z).normalized()
					var p := demo.on_ground(o.x + flat.x * 25.0, o.z + flat.z * 25.0, 0.3)
					var r := lof.trace(eye, p + Vector3(0, 0.9, 0), shooter, false)
					if r.blocker == "tree" and absf(r.distance - eye.distance_to(Vector3(o.x, eye.y, o.z))) < 3.0:
						return p
		break
	return Vector3.INF


## Distance to the first static world collider (terrain, trees, structures) along the
## line, ignoring soldier bodies - what camera-local physics would see.
func _physics_world_dist(a: Vector3, b: Vector3) -> float:
	var space := demo.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b)
	var ex: Array[RID] = []
	for n in demo.sim.bodies.values():
		if n is CollisionObject3D:
			ex.append(n.get_rid())
	q.exclude = ex
	var h := space.intersect_ray(q)
	return a.distance_to(h.position) if not h.is_empty() else INF


# --- 7. determinism ------------------------------------------------------------------

func _determinism_check() -> Dictionary:
	var tid: int = sierra.members[2]
	# 100 m: inside the 120 m body radius when the camera is at the shooter.
	var spot := _clear_spot(shooter, 100.0)
	_put(tid, spot, 0.0)
	_reset(tid)
	demo.rts_camera.frame(_u(shooter).position, 0.0, 60.0)
	await _seconds(2.5)
	var eye := CombatSim.eye_of(_u(shooter))
	var dir := (_torso(tid) - eye).normalized()
	var near := []
	for c in range(1, 41):
		near.append(_sig(combat.preview_shot(shooter, eye, dir, c, 1.2)))
	var near_body := _u(tid).has_body
	demo.rts_camera.frame(demo.sites[2].position, 0.0, 80.0)
	await _seconds(3.0)
	var far := []
	for c in range(1, 41):
		far.append(_sig(combat.preview_shot(shooter, eye, dir, c, 1.2)))
	var far_body := _u(tid).has_body
	var hits := near.filter(func(s: String) -> bool: return s.begins_with("unit")).size()
	var out := {"shots": 40, "identical": near == far, "hits_of_40": hits, "target_body_near": near_body, "target_body_far": far_body,
		"spread_deg": 1.2, "distance_m": snappedf(eye.distance_to(_torso(tid)), 0.1)}
	_expect(near == far and near_body and not far_body and hits > 0 and hits < 40, "seeded shots differ with the camera / body (%s)" % JSON.stringify(out))
	demo.rts_camera.frame(area, 0.0, 80.0)
	await _seconds(3.0)
	return out


func _sig(r: Dictionary) -> String:
	return "%s|%d|%d|%.3f" % [r.blocker, r.hit_unit, r.zone, r.distance]


# --- 8. ammo, fire rate, reload ------------------------------------------------------

func _ammo_check() -> Dictionary:
	var a_id: int = alpha.members[2]
	var b_id: int = alpha.members[3]
	_reset(a_id)
	_reset(b_id)
	var a := _u(a_id)
	var b := _u(b_id)
	var sky := Vector3(0, 0.3, -1).normalized()
	# Fire rate: trigger every physics tick for 1.0 s of simulation time.
	combat.set_fire_mode(a_id, true)
	var t0 := demo.sim.state.time
	var fired := 0
	while demo.sim.state.time - t0 < 1.0:
		if combat.request_fire(a_id, CombatSim.eye_of(a), sky, CombatSim.Source.AI).get("fired", false):
			fired += 1
		await tree.physics_frame
	var expected_rate := def.rounds_per_minute / 60.0
	for i in 3:
		combat.request_fire(b_id, CombatSim.eye_of(b), sky, CombatSim.Source.AI)
		await _physics(10)
	var a_mag := a.mag
	var b_mag := b.mag
	# Reload timing.
	var started := combat.request_reload(a_id)
	var r_start := demo.sim.state.time
	var during: String = combat.request_fire(a_id, CombatSim.eye_of(a), sky, CombatSim.Source.AI).get("reason", "")
	var mag_mid := -1
	var done_at := -1.0
	while demo.sim.state.time - r_start < def.reload_time + 0.5:
		await tree.physics_frame
		if demo.sim.state.time - r_start > def.reload_time * 0.5 and mag_mid < 0:
			mag_mid = a.mag
		if not a.is_reloading() and done_at < 0.0:
			done_at = demo.sim.state.time - r_start
	var out := {"fired_in_1s": fired, "expected_per_s": snappedf(expected_rate, 0.01), "a_mag_after_burst": a_mag, "b_mag_after_3": b_mag,
		"reload_started": started, "fire_during_reload": during, "mag_halfway": mag_mid, "reload_done_after_s": snappedf(done_at, 0.02),
		"a_after_reload": [a.mag, a.reserve], "b_unchanged": [b.mag, b.reserve]}
	_expect(absi(fired - roundi(expected_rate)) <= 1, "fire rate wrong (%s)" % JSON.stringify(out))
	_expect(a_mag == def.magazine_size - fired and b_mag == def.magazine_size - 3 and b.reserve == def.reserve_start, "ammunition not per soldier (%s)" % JSON.stringify(out))
	_expect(started and during == "reloading" and mag_mid == a_mag and absf(done_at - def.reload_time) < 0.06 and a.mag == def.magazine_size and a.reserve == def.reserve_start - fired,
		"reload wrong (%s)" % JSON.stringify(out))
	_reset(a_id)
	_reset(b_id)
	return out


# --- 9. persistence ------------------------------------------------------------------

func _persistence_check() -> Dictionary:
	var u := _u(shooter)
	_reset(shooter)
	var body := await _possess(shooter)
	# V: semi; fire 3 shots into the sky; take some damage.
	_press(KEY_V)
	await _physics(3)
	body.head.rotation.x = deg_to_rad(30.0)
	for i in 3:
		await _click_fire()
		await _physics(int(def.fire_interval() * 60.0) + 2)
	combat.apply_damage(shooter, 20.0, LineOfFire.Zone.BODY, -1)
	var snap := _combat_sig(u)
	var steps := {}
	_press(KEY_TAB)
	await _physics(5)
	steps.tab = _combat_sig(u) == snap
	var other: int = alpha.members[4]
	var b2 := await _possess(other)
	steps.possess_other = _combat_sig(u) == snap and b2 != null
	await _leave()
	demo.rts_camera.frame(demo.sites[2].position, 0.0, 80.0)
	await _seconds(3.0)
	steps.long_jump_abstract = _combat_sig(u) == snap and not u.has_body
	demo.rts_camera.frame(area, 0.0, 80.0)
	await _seconds(3.0)
	steps.back_with_body = _combat_sig(u) == snap and u.has_body
	_press(KEY_F5)
	await _frames(2)
	var saved := _combat_sig(u)
	# Change it: reload, more damage, mode back to auto.
	combat.request_reload(shooter)
	combat.apply_damage(shooter, 10.0, LineOfFire.Zone.BODY, -1)
	combat.set_fire_mode(shooter, true)
	await _seconds(0.5)
	_press(KEY_F9)
	await _physics(3)
	steps.save_load = _combat_sig(_u(shooter)) == saved
	# Squads are rebuilt by a load: refresh the references.
	for sq: SquadState in demo.sim.state.all_squads():
		match sq.squad_name:
			"Alpha": alpha = sq
			"Bravo": bravo = sq
			"Sierra": sierra = sq
	var out := {"signature": snap, "after_load": _combat_sig(_u(shooter)), "steps": steps, "fire_auto_saved": not snap.contains("auto=true")}
	_expect(steps.values().all(func(v: bool) -> bool: return v), "combat state changed across Tab / possession / jump / save-load (%s)" % JSON.stringify(out))
	_reset(shooter)
	combat.set_fire_mode(shooter, true)
	return out


func _combat_sig(u: UnitState) -> String:
	return "alive=%s hp=%.1f mag=%d reserve=%d auto=%s reload=%s shots=%d" % [u.alive, u.health, u.mag, u.reserve, u.fire_auto, u.is_reloading(), u.shot_counter]


# --- 10. death -----------------------------------------------------------------------

func _death_check() -> Dictionary:
	var tid: int = sierra.members[sierra.members.size() - 1]
	var spot := _clear_spot(shooter, 25.0)
	_put(tid, spot, 0.0)
	_reset(tid)
	demo.sim.squads.order_move([sierra.id], demo.on_ground(spot.x + 30.0, spot.z, 0.0))
	await _physics(10)
	var eye := CombatSim.eye_of(_u(shooter))
	var shots_needed := 0
	while _u(tid).alive and shots_needed < 12:
		await _physics(int(def.fire_interval() * 60.0) + 1)
		combat.request_fire(shooter, eye, (_head(tid) - eye).normalized(), CombatSim.Source.AI)
		shots_needed += 1
	var t := _u(tid)
	var died_pos := t.position
	await _seconds(2.0)
	var moved := _flat(t.position, died_pos)
	var order_ok := demo.sim.state.issue_move(tid, died_pos + Vector3(10, 0, 0))
	demo.rts.select([tid])
	var selectable := demo.rts.selected.has(tid)
	var fire := combat.request_fire(tid, CombatSim.eye_of(t), Vector3(0, 0, -1), CombatSim.Source.AI)
	var hp_before_more := t.health
	combat.request_fire(shooter, eye, (_torso(tid) - eye).normalized(), CombatSim.Source.AI)
	var out := {"alive": t.alive, "killer": t.killer_id, "shots": shots_needed, "moved_after_death_m": snappedf(moved, 0.01),
		"move_order_accepted": order_ok, "selectable": selectable, "dead_can_fire": fire.get("fired", false),
		"in_squad": sierra.has_member(tid), "in_fallen": sierra.fallen.has(tid), "has_body": t.has_body,
		"corpse_marker": demo.sim.proxies.has(tid), "hp_after_more_shots": t.health, "name_kept": t.unit_name}
	_expect(not t.alive and t.killer_id == shooter and moved < 0.05 and not order_ok and not selectable and not fire.get("fired", true)
		and not sierra.has_member(tid) and sierra.fallen.has(tid) and not t.has_body and demo.sim.proxies.has(tid) and t.health == 0.0,
		"death handling wrong (%s)" % JSON.stringify(out))
	if shots:
		demo.rts_camera.frame(t.position, 0.7, 14.0)
		await _seconds(1.5)
		_shot("casualty_rts")
		var body := await _possess(shooter)
		if body:
			_aim(body, t.position + Vector3(0, 0.3, 0))
			await _seconds(1.0)
			_shot("casualty_fps")
			await _leave()
	return out


# --- 11. death while possessed -------------------------------------------------------

func _possessed_death_check() -> Dictionary:
	var victim: int = alpha.members[5]
	var killer: int = alpha.members[6]
	_reset(victim)
	_reset(killer)
	# Off to the side: friendly fire is on, nobody else may stand on the line.
	_put(victim, area + Vector3(45, 0, -10), 0.0)
	_put(killer, area + Vector3(45, 0, 10), PI)
	await _seconds(1.0)
	var body := await _possess(victim)
	var was_fps := demo.game.mode == GameController.Mode.FPS and demo.game.possessed_id == victim
	var errors_before := 0
	var shots_fired := 0
	while _u(victim).alive and shots_fired < 15:
		await _physics(int(def.fire_interval() * 60.0) + 1)
		var e := CombatSim.eye_of(_u(killer))
		combat.request_fire(killer, e, (_torso(victim) - e).normalized(), CombatSim.Source.AI)
		shots_fired += 1
	await _physics(10)
	var out := {"was_fps": was_fps, "victim_alive": _u(victim).alive, "mode": "RTS" if demo.game.mode == GameController.Mode.RTS else "FPS",
		"rts_active": demo.rts.active, "rts_camera_current": demo.rts_camera.camera.current, "mouse_visible": Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"possess_dead_refused": not demo.game.possess(victim), "shots": shots_fired}
	_press(KEY_TAB)
	await _physics(5)
	out["tab_after_death_mode"] = "RTS" if demo.game.mode == GameController.Mode.RTS else "FPS"
	_expect(was_fps and not out.victim_alive and out.mode == "RTS" and out.rts_active and out.rts_camera_current and out.possess_dead_refused and out.tab_after_death_mode == "RTS",
		"death while possessed not handled (%s)" % JSON.stringify(out))
	if shots:
		await _seconds(0.5)
		_shot("possessed_death_back_to_rts")
	var other := await _possess(alpha.members[1])
	out["possess_living_after"] = other != null
	await _leave()
	return out


# --- analytic vs physics -------------------------------------------------------------

## Near the camera, everything also has physics. Random rays compare: soldiers (analytic
## head + torso vs the bodies' 0.35 m capsule), terrain (height march vs Terrain3D
## collision), trees (trunk data vs streamed colliders) and structures (record boxes vs
## structure colliders).
func _agreement_check() -> Dictionary:
	var space := demo.get_viewport().world_3d.direct_space_state
	var out := {}
	# Soldiers: rays through and around Alpha's bodies.
	var units := []
	for id in alpha.members:
		var b := demo.sim.body_of(id)
		if b:
			units.append(id)
	var agree := 0
	var phys_only := 0
	var ana_only := 0
	var both := 0
	var mismatch_edge := []
	for i in 2000:
		var id: int = units[i % units.size()]
		var body: Node3D = demo.sim.body_of(id)
		var p: Vector3 = body.global_position
		var target := p + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 1.9), randf_range(-0.6, 0.6))
		var from := target + Vector3(randf_range(-1, 1), randf_range(-0.2, 0.2), randf_range(-1, 1)).normalized() * 3.0
		var to := target + (target - from).normalized() * 3.0
		var ana: bool = LineOfFire.unit_hit(from, to, p).d < INF
		# Only this soldier's body: everything else (terrain, other soldiers) excluded.
		var q := PhysicsRayQueryParameters3D.create(from, to)
		var ex: Array[RID] = [demo.terrain.collision.get_rid()]
		for n in demo.sim.bodies.values():
			if n != body:
				ex.append(n.get_rid())
		q.exclude = ex
		var h := space.intersect_ray(q)
		var phys: bool = not h.is_empty() and h.collider == body
		if ana == phys:
			agree += 1
			if ana:
				both += 1
		else:
			if phys:
				phys_only += 1
			else:
				ana_only += 1
			# How far from the soldier's axis the ray passes: mismatches are a grazing band.
			mismatch_edge.append(_ray_axis_dist(from, to, p))
	mismatch_edge.sort()
	out.soldiers = {"rays": 2000, "agree": agree, "both_hit": both, "physics_only": phys_only, "analytic_only": ana_only,
		"mismatch_axis_dist_m": [snappedf(mismatch_edge[0], 0.01), snappedf(mismatch_edge[mismatch_edge.size() / 2], 0.01), snappedf(mismatch_edge[-1], 0.01)] if not mismatch_edge.is_empty() else [],
		"model": "analytic head sphere r0.14 @1.62 + torso capsule r0.30 0..1.50; physics capsule r0.35 0..1.80"}
	# Terrain within 150 m: grazing lines 0.2-1.5 m above ground.
	var s := _u(shooter)
	var tagree := 0
	var tn := 0
	var dist_err := 0.0
	for i in 400:
		var a := randf() * TAU
		var d := randf_range(30.0, 150.0)
		var from := demo.on_ground(s.position.x + randf_range(-20, 20), s.position.z + randf_range(-20, 20), randf_range(0.3, 2.0))
		var to := demo.on_ground(from.x + cos(a) * d, from.z + sin(a) * d, randf_range(0.2, 1.5))
		var ana: float = lof._terrain_hit(from, to, INF)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		var ex: Array[RID] = []
		for n in demo.sim.bodies.values():
			ex.append(n.get_rid())
		q.exclude = ex
		var h := space.intersect_ray(q)
		var phys := from.distance_to(h.position) if not h.is_empty() else INF
		tn += 1
		if (ana < INF) == (phys < INF):
			tagree += 1
			if ana < INF:
				dist_err = maxf(dist_err, absf(ana - phys))
	out.terrain_grazing = {"rays": tn, "agree": tagree, "max_distance_diff_m": snappedf(dist_err, 0.01)}
	return out


## Closest horizontal distance between a ray and the vertical axis through p.
func _ray_axis_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	return LineOfFire._point_segment_dist2d(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z))


# --- 12. performance -----------------------------------------------------------------

func _perf_check() -> Dictionary:
	var out := {}
	_reset(shooter)
	var body := await _possess(shooter)
	if body == null:
		return out
	body.head.rotation.x = deg_to_rad(-2.0)
	await _seconds(1.0)
	out.fps_idle = await _measure(240)
	combat.set_fire_mode(shooter, true)
	combat.shots_total = 0
	combat.shot_usec_total = 0
	combat.shot_usec_max = 0
	var fx0 := demo.combat_fx.shown
	await _physics(3)
	# Sustained fire: hold LMB for 6 s; the magazine runs dry, reloads, continues.
	Input.action_press("fire")
	var res := await _measure_while(6.0)
	Input.action_release("fire")
	out.fps_sustained_auto_fire = res
	out.shooter_state = {"possessed": demo.game.possessed_id == shooter, "mode_fps": demo.game.mode == GameController.Mode.FPS,
		"player_controlled": _u(shooter).player_controlled, "alive": _u(shooter).alive, "mag": _u(shooter).mag, "auto": _u(shooter).fire_auto}
	out.shots = combat.shots_total
	out.resolve_us_avg = snappedf(float(combat.shot_usec_total) / maxi(combat.shots_total, 1), 0.1)
	out.resolve_us_max = combat.shot_usec_max
	out.fx_shown = demo.combat_fx.shown - fx0
	out.last_trace_cost_us = lof.last_cost
	_reset(shooter)
	await _leave()
	return out


func _measure_while(seconds: float) -> Dictionary:
	var ms := PackedFloat32Array()
	var t_end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < t_end:
		var t := Time.get_ticks_usec()
		await tree.process_frame
		ms.append((Time.get_ticks_usec() - t) / 1000.0)
		if _u(shooter).mag == 0 and not _u(shooter).is_reloading():
			combat.request_reload(shooter)
	var frames := ms.size()
	var sorted := ms.duplicate()
	sorted.sort()
	var sum := 0.0
	for v in ms:
		sum += v
	return {"frames": frames, "seconds": seconds, "frame_ms_avg": snappedf(sum / frames, 0.01), "frame_ms_p99": snappedf(sorted[int(frames * 0.99)], 0.01),
		"frame_ms_max": snappedf(sorted[frames - 1], 0.01)}


# --- Output ---------------------------------------------------------------------------

func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/c01a_%s.jpg" % [_shot_dir, name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("COMBAT shot: ", path)


func _log(name: String, data: Dictionary) -> void:
	results[name] = data
	print("COMBAT %s %s" % [name, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("COMBAT FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	Input.action_release("fire")
	Input.action_release("aim")
	results["deaths"] = deaths
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/combat_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("COMBAT %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()

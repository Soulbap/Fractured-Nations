## BASE-01 player base construction, checked in the normal game (the three-faction war on ref_20km).
##
##   Godot.exe --path . --resolution 1600x900 --log-file base01.log res://scenes/game/world_ref_20km.tscn -- --base01-test [--shots]
##
## Builds the player's first base through the real construction input (B, the base menu, cursor,
## R, left click, Esc) next to the North HQ: refused placements (no base yet, steep ground, a road,
## outside the base area, overlap, a second command post), the command post establishing the base,
## barracks / supply depot / vehicle parking / two guard posts inside its area, collision, infantry
## and a vehicle route around the buildings, save -> clear -> load, leaving the area and coming back,
## and the FPS, RTS and map views. Prints "BASE01 <check> <json>", writes
## res://benchmarks/raw/base01_test.json and (with --shots) docs/base_01/base01_*.jpg.
class_name Base01SelfTest
extends BaseSelfTest

var bs: BaseSim
var rig: RTSCamera
var placed := {}
## `--only a,b`: the checks after building the base to run (collision, infantry, vehicle, persist, far, views);
## empty = all. Building the base (menu, refusals, the six buildings) always runs: everything else needs it.
var only: Array[String] = []


func _want(part: String) -> bool:
	return only.is_empty() or only.has(part)


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		for p in args[oi + 1].split(","):
			only.append(p.strip_edges())
	_shot_dir = "res://docs/base_01"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	con.base_rules = true
	sm = demo.structures
	cs = demo.sim.state.construction
	bs = demo.sim.logistics.bases
	rig = demo.rts_camera
	# The world stays still while the base is built: no AI decisions, no firing.
	demo.sim.war.enabled = false
	demo.sim.brain.enabled = false
	tree.create_timer(480.0).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish in 480 s")
		_finish())
	await _physics(60)
	var fac := con.player_faction()
	var hq := demo.sim.state.war.objective(demo.sim.state.war.faction(fac).hq_objective)
	base = _find_base_site(hq.position)
	_log("start", {"player_faction": fac, "player_bases": bs.bases_of(fac).size(), "hq": _v(hq.position), "site": _v(base),
		"site_to_hq_m": snappedf(_flat(base, hq.position), 1.0)})
	_expect(bs.bases_of(fac).is_empty(), "the player already has a base at the start")

	# 1. Construction mode and the base menu.
	rig.frame(base, 0.0, 140.0)
	await _frames(3)
	_press(KEY_B)
	await _frames(4)
	var panel := con.panel
	var disabled := {}
	for id in panel._base_buttons:
		disabled[String(id)] = (panel._base_buttons[id] as Button).disabled
	_log("menu", {"active": con.active, "panel": panel.visible, "base_buttons": disabled, "info": panel._base_info.text})
	_expect(con.active and panel.visible, "B did not open construction mode")
	_expect(not disabled.get("command_post", true) and disabled.get("barracks_block", false), "base menu: only the command post may be chosen without a base")
	if shots:
		con.mouse_override = Vector2(400, 450)
		await _frames(20)
		_shot("menu")

	# 2. Refused: a barracks with no base, a command post on steep ground and on a road.
	var r_nobase := await _try(&"barracks_block", base, 0)
	var steep := _find_slope(&"command_post", sm.level_max_slope_deg + 2.0, 45.0)
	var r_steep := await _try(&"command_post", steep, 0) if steep.is_finite() else "no steep spot"
	var road_pt := _road_spot(base)
	var r_road := await _try(&"command_post", road_pt, 0) if road_pt.is_finite() else "no road"
	if shots and road_pt.is_finite():
		con.select_type(&"command_post")
		rig.frame(road_pt, 0.5, 60.0)
		await _frames(3)
		await _cursor_at(road_pt)
		await _frames(25)
		_shot("preview_invalid_road")
	_log("refused_before_base", {"no_base": r_nobase, "steep": r_steep, "steep_spot": _v(steep), "road": r_road, "road_spot": _v(road_pt)})
	_expect(r_nobase.begins_with("no base"), "a barracks was not refused without a base (%s)" % r_nobase)
	_expect(r_steep.begins_with("too steep"), "steep ground was not refused (%s)" % r_steep)
	_expect(r_road.contains("road") or r_road.contains("bridge"), "a command post on a road was not refused (%s)" % r_road)

	# 3. The command post, rotated 45° (R x3), establishes the base.
	var cp_at := _spot(&"command_post", base, 3)
	if shots:
		con.select_type(&"command_post")
		con.yaw = deg_to_rad(45.0)
		rig.frame(cp_at, 0.4, 200.0)
		await _frames(3)
		await _cursor_at(cp_at)
		await _frames(25)
		_shot("preview_command_post")
	placed.cp = await _place(&"command_post", cp_at, 3)
	var cp: StructureState = placed.cp
	var b: Dictionary = cs.bases.get(cp.base_id, {}) if cp else {}
	_log("command_post", {"built": cp != null, "yaw_deg": snappedf(rad_to_deg(cp.yaw), 0.1) if cp else null, "base": _base_info(b), "message": con.message})
	_expect(cp != null, "the command post could not be placed")
	if cp == null:
		_finish()
		return
	_expect(absf(rad_to_deg(cp.yaw) - 45.0) < 0.5, "rotation was not applied to the command post")
	_expect(not b.is_empty() and int(b.faction) == fac and int(b.founder) == cp.id and is_equal_approx(float(b.radius), 150.0)
		and Vector2(b.anchor.x - cp.position.x, b.anchor.z - cp.position.z).length() < 0.1, "the command post did not establish a base of the player's faction")
	var bid: int = cp.base_id
	var c := cp.position

	# 4. The other buildings inside the area (barracks rotated 90°), and the refusals that need a base.
	placed.barracks = await _place(&"barracks_block", _spot(&"barracks_block", c + Vector3(-34, 0, 22), 6), 6)
	placed.depot = await _place(&"supply_depot", _spot(&"supply_depot", c + Vector3(34, 0, 22), 0), 0)
	placed.parking = await _place(&"vehicle_parking_pad", _spot(&"vehicle_parking_pad", c + Vector3(30, 0, -26), 0), 0)
	placed.guard1 = await _place(&"guard_tower_steel", _spot(&"guard_tower_steel", c + Vector3(-48, 0, -40), 0), 0)
	placed.guard2 = await _place(&"guard_tower_steel", _spot(&"guard_tower_steel", c + Vector3(52, 0, 58), 0), 0)
	var all_in := true
	for k in placed:
		var s: StructureState = placed[k]
		all_in = all_in and s != null and s.base_id == bid
	var outside := _outside_spot(c)
	var r_out := await _try(&"barracks_block", outside, 0) if outside.is_finite() else "no spot"
	var r_overlap := await _try(&"guard_tower_steel", c, 0)
	var r_second := await _try(&"command_post", _spot(&"command_post", c + Vector3(-20, 0, -30), 0, false), 0)
	if shots and outside.is_finite():
		con.select_type(&"barracks_block")
		con.yaw = 0.0
		rig.frame(outside, 0.3, 120.0)
		await _frames(3)
		await _cursor_at(outside)
		await _frames(25)
		_shot("preview_invalid_outside")
	con.clear_tool()
	var sm_b := bs.summary(bid)
	var by := placed.barracks as StructureState
	var roads_near := {}
	for k in placed:
		var s: StructureState = placed[k]
		var nr := demo.sim.state.roads.nearest(s.position, 80.0, 0, 0.0)
		roads_near[k] = {"pos": _v(s.position), "road_m": snappedf(float(nr.get("dist", -1.0)), 0.1), "road_w": snappedf((nr.road as RoadNetwork.Road).width, 0.1) if not nr.is_empty() else 0.0,
			"conflict_now": sm.road_conflict(StructureCatalog.get_def(s.type_id), s.instances[0])}
	_log("road_clearance", roads_near)
	_log("buildings", {"placed": placed.keys().filter(func(k: String) -> bool: return placed[k] != null), "all_in_base": all_in,
		"barracks_yaw_deg": snappedf(rad_to_deg(by.yaw), 0.1) if by else null, "outside": r_out, "overlap": r_overlap, "second_cp": r_second,
		"capacity": sm_b.capacity, "parking_bays": sm_b.parking, "guard_posts": sm_b.guard_posts, "stock": sm_b.stock, "kind": sm_b.kind})
	_expect(all_in and placed.size() == 6, "not every base building was placed inside the base")
	_expect(by != null and absf(absf(rad_to_deg(by.yaw)) - 90.0) < 0.5, "barracks rotation (R x6) not applied")
	_expect(r_out.begins_with("outside the base area"), "a barracks outside the base area was not refused (%s)" % r_out)
	_expect(r_overlap.begins_with("blocked"), "an overlapping building was accepted (%s)" % r_overlap)
	_expect(r_second.begins_with("too close to"), "a second command post inside the base was accepted (%s)" % r_second)
	_expect(sm_b.capacity == 40 and sm_b.parking == 6 and sm_b.guard_posts == 2, "facility properties wrong (beds %d, bays %d, posts %d)" % [sm_b.capacity, sm_b.parking, sm_b.guard_posts])
	_expect(float(sm_b.stock.supplies) > 0.0, "the first supply depot did not receive the starting stock")

	var pad := placed.parking as StructureState

	# 5. Collision and blocking footprint.
	if _want("collision"):
		rig.frame(c, 0.0, 120.0)
		await _seconds(1.5)
		sm.refresh_now()
		await _physics(4)
		var coll := {}
		for k in ["cp", "barracks", "depot", "guard1"]:
			var s: StructureState = placed[k]
			var top := s.instances[0].origin + Vector3.UP * 30.0
			coll[k] = {"ray_hit": _ray_hit_structure(top, Vector3.DOWN, 40.0), "blocks": sm.blocks_point(Vector2(s.position.x, s.position.z), 0.05)}
		coll["parking_walkable"] = not sm.blocks_point(Vector2(pad.position.x, pad.position.z), 0.05)
		_log("collision", coll)
		for k in ["cp", "barracks", "depot", "guard1"]:
			_expect(coll[k].ray_hit and coll[k].blocks, "%s has no collision / blocking footprint" % k)

	# 6. Infantry: the nearest North squad walks to a point behind the barracks (its straight way crosses it).
	var inf := {}
	if _want("infantry"):
		inf = await _infantry_check(by, c)
		_log("infantry", inf)
		_expect(inf.get("arrived", false), "the squad did not reach the far side of the barracks (%s)" % inf)
		_expect(int(inf.get("inside_samples", 1)) == 0, "soldiers walked through a base building (%d samples inside)" % inf.get("inside_samples", -1))

	# 7. A truck on a parking bay; its route to the far side of the barracks keeps out of every building.
	var veh := {}
	if _want("vehicle"):
		veh = _vehicle_check(bid, by)
		_log("vehicle", veh)
		_expect(veh.get("parked", false) and veh.get("next_bay_differs", false), "the parking bays do not work (%s)" % veh)
		_expect(veh.get("route_ok", false) and int(veh.get("route_points_blocked", 1)) == 0, "the vehicle route crosses a base building (%s)" % veh)
	if shots:
		con.set_active(false)
		rig.frame(c, 0.6, 175.0)
		rig.pitch_offset = 0.0
		await _frames(60)
		_shot("base_rts")
		_press(KEY_B)
		await _frames(30)
		_shot("base_rts_areas")
		_press(KEY_B)
		await _frames(5)
		if not veh.is_empty():
			# Close on the vehicle park with the truck in its bay.
			rig.frame(pad.position, 0.5, 34.0)
			# The truck gets its body once the detail area around the camera is ready.
			await _seconds(4.0)
			await _frames(30)
			_shot("parking")
			var tu := demo.sim.state.get_unit(int(veh.get("vehicle_id", -1)))
			_log("parking_later", {"pad": _v(pad.position), "bay": veh.get("bay_pos", []), "truck_now": _v(tu.position) if tu else [],
				"truck_local": _v(Basis(Vector3.UP, pad.yaw).inverse() * (tu.position - pad.position)) if tu else []})
		if not inf.is_empty():
			# Low over the ground by the squad, looking at the barracks behind it.
			var sq_at: Vector3 = inf.get("target_v", by.position)
			var look := (by.position - sq_at).normalized()
			# The camera stands behind the focus (RTSCamera: back = (sin yaw, cos yaw)), on the far side from the barracks.
			rig.frame(sq_at, atan2(-look.x, -look.z), 24.0)
			rig.pitch_offset = 0.0
			rig.tilt_by(deg_to_rad(10.0) - rig.pitch())
			await _frames(60)
			_shot("base_units")
			rig.pitch_offset = 0.0

	# 8. Save, clear, load (F5 / F9 of the construction mode).
	if _want("persist"):
		var before := _player_part(fac)
		var saved := con.save()
		cs.clear()
		await _frames(5)
		var cleared := cs.count() == 0 and cs.bases.is_empty()
		var loaded := con.load_saved()
		await _frames(10)
		var after := _player_part(fac)
		var b2: Dictionary = cs.bases.get(bid, {})
		_log("persist", {"saved": saved, "cleared": cleared, "loaded": loaded, "same_dict": before == after,
			"base_after": _base_info(b2), "structures": cs.count(), "capacity_after": bs.capacity(bid), "file": con.save_path})
		_expect(saved and cleared and loaded, "save / clear / load did not run")
		_expect(before == after, "the base did not survive save / load unchanged")
		_expect(not b2.is_empty() and int(b2.founder) == cp.id and int(b2.faction) == fac and bs.capacity(bid) == 40, "base record lost on load")

	# 9. Far away (6 km) and back: records stay, visuals and collision are rebuilt.
	if _want("far"):
		var far := Vector3(clampf(c.x + 6000.0, -9000.0, 9000.0), 0.0, c.z)
		if absf(far.x - c.x) < 3000.0:
			far.x = c.x - 6000.0
		rig.frame(demo.on_ground(far.x, far.z, 0.0), 0.0, 120.0)
		await _seconds(4.0)
		var drawn_far := _base_drawn(c)
		rig.frame(c, 0.0, 120.0)
		await _seconds(4.0)
		sm.refresh_now()
		await _physics(4)
		var drawn_back := _base_drawn(c)
		var hit_back := _ray_hit_structure((placed.depot as StructureState).instances[0].origin + Vector3.UP * 30.0, Vector3.DOWN, 40.0)
		_log("far_and_back", {"far": _v(far), "drawn_far": drawn_far, "drawn_back": drawn_back, "collision_back": hit_back, "base_kept": cs.bases.has(bid)})
		_expect(drawn_far == 0 and drawn_back >= 6 and hit_back and cs.bases.has(bid), "base not rebuilt after leaving and coming back")

	# 10. Views: first person next to the base, and the strategic map.
	if _want("views"):
		var view := await _views(c, placed.depot)
		_log("views", view)
		_expect(view.get("fps", false), "no first-person view of the base")
		_expect(view.get("map_base", false), "the base is not on the strategic map")
	_finish()


## Selects a type, points at p with `rotations` R presses and clicks; the placement must be refused.
## Returns the reason shown ("" when it was built - then it is removed again and "BUILT" returned).
func _try(id: StringName, p: Vector3, rotations: int) -> String:
	if not p.is_finite():
		return "no spot"
	var s := await _place(id, p, rotations, false)
	if s != null:
		cs.remove(s.id)
		return "BUILT"
	return String(con.check.get("reason", "?"))


## A spot near `want` where the type passes every check (terrain, overlap, trees, base rules), searched in rings.
func _spot(id: StringName, want: Vector3, rotations: int, inside := true) -> Vector3:
	var def := StructureCatalog.get_def(id)
	con.select_type(id)
	var yaw := deg_to_rad(15.0 * rotations)
	for ring: float in [0.0, 6.0, 12.0, 18.0, 26.0, 34.0]:
		for k in (1 if ring == 0.0 else 12):
			var a := k * TAU / 12.0
			var p := demo.on_ground(want.x + cos(a) * ring, want.z + sin(a) * ring, 0.0)
			var chk := sm.check_building(def, p, yaw, -1, con.clear_trees)
			if not chk.ok:
				continue
			con.def = def
			if inside and con._base_reason(chk.xform) != "":
				continue
			return p
	return demo.on_ground(want.x, want.z, 0.0)


## A spot 190-260 m from the command post where a barracks passes the terrain checks (so only the base rule refuses it).
func _outside_spot(c: Vector3) -> Vector3:
	var def := StructureCatalog.get_def(&"barracks_block")
	for r: float in [190.0, 220.0, 260.0]:
		for k in 16:
			var a := k * TAU / 16.0
			var p := demo.on_ground(c.x + cos(a) * r, c.z + sin(a) * r, 0.0)
			var chk := sm.check_building(def, p, 0.0, -1, true)
			if chk.ok and sm.road_conflict(def, chk.xform) == "":
				return p
	return Vector3.INF


## A point on a world road within 1.5 km of p where a command post passes the terrain checks.
func _road_spot(p: Vector3) -> Vector3:
	var def := StructureCatalog.get_def(&"command_post")
	for r: RoadNetwork.Road in demo.sim.state.roads.roads_in(Rect2(Vector2(p.x, p.z), Vector2.ZERO).grow(1500.0)):
		for i in range(0, r.points.size(), 6):
			var q := r.points[i]
			var g := demo.on_ground(q.x, q.z, 0.0)
			if sm.check_building(def, g, 0.0, -1, true).ok and bs.placement_rule(&"command_post", g, con.player_faction()) == "":
				return g
	return Vector3.INF


func _infantry_check(barracks: StructureState, c: Vector3) -> Dictionary:
	var fac := con.player_faction()
	var best: SquadState = null
	var best_d := INF
	for sq: SquadState in demo.sim.state.all_squads():
		if sq.faction != fac or sq.members.is_empty():
			continue
		var d := _flat(demo.sim.war.squad_center(sq), c)
		if d < best_d:
			best_d = d
			best = sq
	if best == null:
		return {"arrived": false, "why": "no squad"}
	var from := demo.sim.war.squad_center(best)
	var dir := Vector3(barracks.position.x - from.x, 0.0, barracks.position.z - from.z).normalized()
	var target := demo.on_ground(barracks.position.x + dir.x * 16.0, barracks.position.z + dir.z * 16.0, 0.0)
	demo.sim.squads.order_move([best.id], target)
	Engine.time_scale = 4.0
	var route_cross := 0
	var routes_seen := {}
	var inside := 0
	var samples := 0
	var arrived := false
	var t_end := Time.get_ticks_msec() + 45000
	var tiers := {}
	while Time.get_ticks_msec() < t_end:
		await _seconds(0.25)
		samples += 1
		# The squad's route (it may be replanned): does any leg run through a building?
		var rkey := str(best.route)
		if not routes_seen.has(rkey):
			var cross := 0
			for i in best.route.size() - 1:
				for k in 21:
					var q := best.route[i].lerp(best.route[i + 1], k / 20.0)
					if sm.blocks_point(Vector2(q.x, q.z), 0.0):
						cross += 1
			routes_seen[rkey] = {"points": best.route.size(), "cross_samples": cross, "last": _v(best.route[best.route.size() - 1]) if best.route.size() > 0 else []}
			route_cross += cross
		var far_m := 0.0
		var moving := 0
		for id in best.members:
			var u := demo.sim.state.get_unit(id)
			if u == null or not u.alive:
				continue
			if sm.blocks_point(Vector2(u.position.x, u.position.z), 0.0):
				inside += 1
			far_m = maxf(far_m, _flat(u.position, target))
			if u.velocity.length() > 0.3:
				moving += 1
			tiers["body" if demo.sim.bodies.has(id) else "abstract"] = true
		# A squad ends in formation round its target: arrived when the centre is there and everyone has stopped near it.
		if _flat(demo.sim.war.squad_center(best), target) < 12.0 and far_m < 30.0 and moving == 0:
			arrived = true
			break
	# After arriving the squad must stay put (earlier runs found it later against the barracks wall): 80 s more.
	var after_arrival := []
	var arrived_at := {}
	for id in best.members:
		var u := demo.sim.state.get_unit(id)
		if u:
			arrived_at[id] = u.position
	if arrived:
		for k in 16:
			await _seconds(5.0)
			var moved := 0.0
			var who := -1
			for id in best.members:
				var u := demo.sim.state.get_unit(id)
				if u and arrived_at.has(id) and _flat(u.position, arrived_at[id]) > moved:
					moved = _flat(u.position, arrived_at[id])
					who = id
			var w := demo.sim.state.get_unit(who)
			after_arrival.append([5 * (k + 1), snappedf(moved, 0.1), _v(w.position) if w else [], int(w.order) if w else -1, w.nav_reason if w else "",
				int(best.tactic), best.tactic_why, int(best.order)])
	Engine.time_scale = 1.0
	# Navigation diagnostics: what the navmesh offers from each soldier to its own target.
	var nav := demo.detail.navigation
	var map_rid := nav.get_navigation_map()
	var nav_paths := []
	for id in best.members.slice(0, 3):
		var u := demo.sim.state.get_unit(id)
		if u == null:
			continue
		var path := NavigationServer3D.map_get_path(map_rid, u.position, u.order_target, true)
		var blocked := 0
		for i in path.size() - 1:
			for k in 11:
				var q := path[i].lerp(path[i + 1], k / 10.0)
				if sm.blocks_point(Vector2(q.x, q.z), 0.0):
					blocked += 1
		nav_paths.append({"from": _v(u.position), "to": _v(u.order_target), "points": path.size(), "blocked_samples": blocked,
			"end_gap_m": snappedf(_flat(path[path.size() - 1], u.order_target), 0.1) if path.size() > 0 else -1.0})
	var obst := sm.nav_obstacles(c, 120.0)
	_log("infantry_nav", {"paths": nav_paths, "last_bake": demo.detail.last_bake, "nav_center": _v(demo.detail.nav_center),
		"area_m": demo.detail.nav_area_size, "obstacles_near_base": obst.size(), "nav_covers_target": demo.detail.nav_covers(target)})
	var dists := []
	for id in best.members:
		var u := demo.sim.state.get_unit(id)
		if u:
			dists.append([snappedf(_flat(u.position, target), 0.1), int(u.move_state), u.nav_reason])
	return {"target_v": target, "squad": best.squad_name, "start_m": snappedf(best_d, 1.0), "target": _v(target), "arrived": arrived, "samples": samples,
		"sim_s": snappedf(float(samples) * 0.25, 0.1), "inside_samples": inside, "bodies_seen": tiers.keys(), "members": best.members.size(),
		"centre_m": snappedf(_flat(demo.sim.war.squad_center(best), target), 0.1), "final": dists, "after_arrival": after_arrival.slice(-1), "routes": routes_seen.values(), "route_cross_samples": route_cross,
		"stayed": after_arrival.is_empty() or float(after_arrival[-1][1]) < 6.0}


func _vehicle_check(bid: int, barracks: StructureState) -> Dictionary:
	var sp := bs.free_parking_spot(bid)
	if sp.is_empty():
		return {"parked": false, "why": "no free bay"}
	var p: Vector3 = sp.pos
	p.y = demo.sim.vehicles.ground_at(p)
	var u := demo.sim.state.add_vehicle(&"truck_6x6", con.player_faction(), p, sp.yaw)
	if demo.detail:
		demo.detail.create_missing_proxies()
	var nxt := bs.free_parking_spot(bid)
	var away := Vector3(barracks.position.x - p.x, 0.0, barracks.position.z - p.z).normalized()
	var goal := barracks.position + away * 22.0
	goal.y = demo.sim.vehicles.ground_at(goal)
	var def := VehicleDefs.get_def(&"truck_6x6")
	var res: Dictionary = demo.sim.vehicles.router.plan(u.position, goal, def)
	var blocked := 0
	var pts: PackedVector3Array = res.get("points", PackedVector3Array())
	for i in pts.size() - 1:
		var n := maxi(1, ceili(pts[i].distance_to(pts[i + 1]) / 1.0))
		for k in n + 1:
			var q := pts[i].lerp(pts[i + 1], float(k) / n)
			if sm.blocks_point(Vector2(q.x, q.z), 0.3):
				blocked += 1
	return {"vehicle": u.unit_name, "vehicle_id": u.id, "bay_pos": _v(p), "bay": int(sp.slot), "parked": _flat(u.position, sp.pos) < 0.5, "next_bay_differs": not nxt.is_empty() and int(nxt.slot) != int(sp.slot),
		"route_ok": res.get("ok", false), "route_m": snappedf(float(res.get("length_m", 0.0)), 0.1), "route_points_blocked": blocked, "reason": res.get("reason", "")}


## Structure instances drawn within 200 m of c.
func _base_drawn(c: Vector3) -> int:
	var n := 0
	for cell in sm._visual:
		for t in sm._visual[cell]:
			var mmi: MultiMeshInstance3D = sm._visual[cell][t]
			for i in mmi.multimesh.instance_count:
				if _flat(mmi.multimesh.get_instance_transform(i).origin, c) < 200.0:
					n += 1
	return n


func _views(c: Vector3, barracks: StructureState) -> Dictionary:
	var out := {}
	# First person: a North soldier near the base looks at the barracks.
	var fac := con.player_faction()
	var best := -1
	var bd := INF
	for u: UnitState in demo.sim.state.units.values():
		if u.kind == UnitState.Kind.SOLDIER and u.alive and u.faction == fac:
			var d := _flat(u.position, c)
			if d < bd:
				bd = d
				best = u.id
	if best >= 0 and bd < 200.0:
		demo.game.possess(best)
		await _frames(30)
		var body := demo.game.possessed_body()
		if body:
			_aim(body, barracks.position + Vector3.UP * 3.0)
		await _frames(40)
		out["fps"] = demo.game.mode == GameController.Mode.FPS
		out["fps_soldier_dist_m"] = snappedf(bd, 1.0)
		if shots:
			_shot("base_ground_fps")
		demo.game.enter_rts()
		await _frames(10)
	else:
		out["fps"] = false
		out["fps_why"] = "no soldier within 200 m (%.0f m)" % bd
	# Strategic map, zoomed in on the base.
	demo.toggle_map()
	await _frames(5)
	var m := demo.strategic_map
	m.zoom = 1.6
	m.view_center = Vector2(c.x, c.z)
	await _frames(20)
	out["map_open"] = m.visible
	out["map_base"] = m.visible and not bs.bases_of(fac).is_empty()
	if shots:
		_shot("map")
	demo.toggle_map()
	await _frames(5)
	return out


## The player's structures and bases as saved JSON (the AI factions keep running their economy meanwhile). Both
## sides go through JSON, whose numbers come back as floats.
func _player_part(fac: int) -> String:
	var d: Dictionary = JSON.parse_string(JSON.stringify(cs.to_dict()))
	var out := {"structures": [], "bases": []}
	for s: Dictionary in d.structures:
		if int(s.faction) == fac:
			out.structures.append(s)
	for b: Dictionary in d.bases:
		if int(b.faction) == fac:
			out.bases.append(b)
	return JSON.stringify(out)


func _base_info(b: Dictionary) -> Dictionary:
	if b.is_empty():
		return {}
	return {"id": b.id, "name": b.name, "faction": b.faction, "anchor": _v(b.anchor), "radius": b.get("radius", 0.0), "founder": b.get("founder", -1)}


func _log(name: String, data: Dictionary) -> void:
	results[name] = data
	print("BASE01 %s %s" % [name, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("BASE01 FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/base01_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("BASE01 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()

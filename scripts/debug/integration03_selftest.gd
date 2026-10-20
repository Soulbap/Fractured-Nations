## Scripted checks of WORLD-INTEGRATION-03 on ref_20km: the WORLD-PLAYTEST-01 world and the
## ASSET-PRODUCTION-01 library together in the running sandbox war.
##
##   Godot.exe --path . --resolution 1600x900 res://scenes/game/world_ref_20km.tscn -- --integration03-test [--shots] [--only a,b]
##
## Checks (the milestone's scenarios A-G): catalog, factions, base, base_nav, long_route,
## views, persist, perf, vehicles. Prints "WI03 <check> <json>", writes
## res://benchmarks/raw/integration03_test.json and (with --shots) docs/integration03/wi03_*.jpg.
## Scenarios that need the constructed base build it first when it is not there yet.
class_name Integration03SelfTest
extends PlaytestSelfTest

const BUILDINGS: Array[StringName] = [&"hq_building", &"barracks_block", &"supply_depot", &"vehicle_depot", &"medical_station",
	&"guard_tower_steel", &"bunker_fighting", &"comms_station", &"training_facility"]
const VEHICLE_GLBS := {"truck_6x6": "res://assets/military/vehicles/truck_6x6.glb", "apc_8x8": "res://assets/military/vehicles/apc_8x8.glb"}

## The constructed base (fob): centre, gate, placed structures by role, road to the world network.
var fob := {}
var _vehicle_nodes: Array[Node3D] = []


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/integration03"
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	lof = combat.line
	def = combat.weapon(&"rifle")
	brain = demo.sim.brain
	war = demo.sim.state.war
	ws = demo.sim.war
	SoldierBody.require_mouse_capture = false
	demo.sim.state.shot_fired.connect(_on_shot_rec)
	tree.create_timer(2400.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_pause_ai(true)
	_log("setup", {"roads_world": demo.sim.state.roads.world.size(), "road_km": snappedf(demo.sim.state.roads.total_length_m() / 1000.0, 0.1),
		"grid_cached": ws.routes.loaded_from_cache, "grid_ms": snappedf(ws.routes.build_ms, 0.1),
		"soldiers": demo.sim.state.count_of(UnitState.Kind.SOLDIER), "structures_at_start": cs.count()})
	if _want("catalog"):
		_log("catalog", _catalog())
	if _want("factions"):
		_log("factions", await _factions())
	if _want("base"):
		_log("base", await _base())
	if _want("base_nav"):
		_log("base_nav", await _base_nav())
	if _want("long_route"):
		_log("long_route", await _nav_river())
	if _want("views"):
		_log("views", await _views())
	if _want("persist"):
		_log("persist", await _persist_all())
	if _want("vehicles"):
		_log("vehicles", await _vehicles())
	if _want("perf"):
		_log("perf", await _perf_all())
	TimeCompression.reset()
	await _seconds(1.5)
	while demo.navigation.has_pending_bake() or demo.detail._rebake_in >= 0.0:
		await _seconds(0.2)
	await _seconds(0.5)
	_finish()


func _want(n: String) -> bool:
	return only.is_empty() or only.has(n)


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("WI03 %s %s" % [check, JSON.stringify(data)])


func _shot(shot_name: String) -> void:
	if not shots:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/wi03_%s.jpg" % [_shot_dir, shot_name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("WI03 shot: ", path)


func _finish() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/integration03_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("WI03 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.shutdown_cleanup()
	tree.quit()


# --- Catalog -------------------------------------------------------------------------------

## Every type the menu offers: the nine buildings and 24 modules registered, categories
## populated, every mesh loads (no placeholder boxes for library assets), walkable types
## have no collision.
func _catalog() -> Dictionary:
	var per_cat := {}
	var placeholders := []
	var ids := []
	for d: StructureDef in StructureCatalog.all():
		ids.append(String(d.id))
		per_cat[d.category] = per_cat.get(d.category, 0) + 1
		if not d.is_surface():
			var m := StructureCatalog.mesh_of(d)
			if m is ArrayMesh and (m as ArrayMesh).get_surface_count() == 1 and (m as ArrayMesh).surface_get_material(0) is StandardMaterial3D \
					and ((m as ArrayMesh).surface_get_material(0) as StandardMaterial3D).albedo_color == d.color and d.mesh_path.begins_with("res://assets/military/"):
				placeholders.append(String(d.id))
	var missing_buildings := []
	for id in BUILDINGS:
		if StructureCatalog.get_def(id) == null:
			missing_buildings.append(String(id))
	var modules := 0
	for d: StructureDef in StructureCatalog.all():
		if d.mesh_path.begins_with("res://assets/military/modules/"):
			modules += 1
	var walkable := []
	var walkable_bad := []
	for d: StructureDef in StructureCatalog.all():
		if d.walkable:
			walkable.append(String(d.id))
			if not d.get_collision_boxes().is_empty() or d.bounds().size.x < 0.1:
				walkable_bad.append(String(d.id))
	var out := {"types": ids.size(), "per_category": per_cat, "categories": StructureCatalog.CATEGORIES, "modules": modules,
		"missing_buildings": missing_buildings, "placeholder_meshes": placeholders, "walkable": walkable, "walkable_bad": walkable_bad}
	_expect(missing_buildings.is_empty(), "catalog: buildings missing %s" % str(missing_buildings))
	_expect(modules == 24, "catalog: %d of 24 modules registered" % modules)
	_expect(placeholders.is_empty(), "catalog: library meshes did not load %s" % str(placeholders))
	_expect(walkable_bad.is_empty(), "catalog: walkable types with collision or no footprint %s" % str(walkable_bad))
	for cat in StructureCatalog.CATEGORIES:
		_expect(per_cat.get(cat, 0) > 0, "catalog: empty category %s" % cat)
	return out


# --- Scenario A: the three faction families -------------------------------------------------

## The sandbox garrisons wear their faction's family at every HQ; one squad of each family
## side by side: bodies with every piece, walking animation, first-person weapon of the
## possessed NATO soldier, kit kept through demotion / promotion.
func _factions() -> Dictionary:
	var out := {}
	var hq_shots := {0: "01_nato_north_hq", 1: "02_ru_south_hq", 2: "03_cn_east_hq"}
	for f in 3:
		var hq := war.objective(war.faction(f).hq_objective)
		demo.rts_camera.frame(hq.position, 0.6, 45.0)
		await _seconds(4.0)
		var fam := WorldState.faction_loadout(f)
		var bodies := 0
		var right := 0
		var wrong := []
		for id in demo.sim.bodies:
			var b := demo.sim.bodies[id] as SoldierBody
			if b == null or b.unit.faction != f or _flat(b.unit.position, hq.position) > 90.0:
				continue
			bodies += 1
			if b.unit.loadout == fam and b.character and b.character.loadout and b.character.loadout.id == fam:
				right += 1
			else:
				wrong.append([id, b.unit.loadout])
		var proxies_right := 0
		var proxies := 0
		for u in demo.sim.state.soldiers():
			if u.faction == f:
				proxies += 1
				proxies_right += 1 if u.loadout == fam or u.loadout == "" else 0
		out["hq_%d" % f] = {"faction": WorldState.faction_name(f), "family": fam, "bodies_near_hq": bodies, "wearing_family": right, "wrong": wrong.slice(0, 4),
			"soldiers": proxies, "records_family_or_unset": proxies_right}
		_expect(bodies >= 8 and right == bodies, "factions: %s HQ bodies %d/%d wear %s" % [WorldState.faction_name(f), right, bodies, fam])
		_expect(proxies_right == proxies, "factions: %d %s soldiers carry another family's loadout" % [proxies - proxies_right, WorldState.faction_name(f)])
		_shot(hq_shots[f])
	# All three together, in the open, far from the war.
	var hq0 := war.objective(war.faction(0).hq_objective)
	var spot := _near_point(hq0.position, _obj("Sentrum").position, 220.0)
	var sqs := []
	for f in 3:
		sqs.append(_spawn(f, spot + Vector3((f - 1) * 14.0, 0, 0), 6))
	brain.enabled = false
	demo.rts_camera.frame(spot, 0.0, 30.0)
	await _seconds(4.0)
	var check := CharacterIntegrationCheck.run(demo.sim)
	out["together"] = check.data
	for msg in check.failures:
		_expect(false, msg)
	_shot("04_three_families_rts_30m")
	demo.rts_camera.frame(spot, 0.0, 90.0)
	await _seconds(1.0)
	_shot("04b_three_families_rts_90m")
	# Walking: every moving body animates with its velocity.
	for sq: SquadState in sqs:
		demo.sim.squads.order_move([sq.id], spot + Vector3(0, 0, 50))
	await _seconds(2.5)
	var moving := 0
	var animating := 0
	var stance := {}
	for sq: SquadState in sqs:
		for id in sq.members:
			var b := demo.sim.body_of(id) as SoldierBody
			if b == null or b.character == null:
				continue
			var v := Vector2(b.velocity.x, b.velocity.z).length()
			if v > 0.5:
				moving += 1
				var st: Dictionary = b.character.anim_state()
				if st.move_amount > 0.5:
					animating += 1
				stance[String(b.unit.loadout)] = {"speed": snappedf(v, 0.1), "move_amount": snappedf(st.move_amount, 0.01), "crouch": snappedf(st.crouch, 0.01)}
	out["walking"] = {"moving": moving, "animating": animating, "sample": stance}
	_expect(moving >= 9 and animating == moving, "factions: %d of %d moving soldiers animate" % [animating, moving])
	_frame_action(ws.squad_center(sqs[1]), demo.rts_camera.yaw, 22.0)
	await _seconds(0.3)
	_shot("05_three_families_walking")
	await _seconds(4.0)
	# First person: the North soldier holds the NATO carbine; it fires.
	var pid: int = sqs[0].members[0]
	var body := await _possess(pid)
	var fps := {"possessed": body != null}
	if body:
		fps["viewmodel_loadout"] = body.viewmodel.loadout.id if body.viewmodel and body.viewmodel.loadout else ""
		_expect(fps.viewmodel_loadout == WorldState.faction_loadout(0), "factions: first-person weapon is from %s" % fps.viewmodel_loadout)
		var tgt: Vector3 = _u(sqs[2].members[0]).position + Vector3.UP * 1.3
		await _fps_shot_at(body, tgt)
		await _seconds(0.3)
		_shot("06_fps_nato_hip")
		Input.action_press("aim")
		await _seconds(0.6)
		_shot("06b_fps_nato_ads")
		var n0 := shot_log.size()
		Input.action_press("fire")
		await _physics(3)
		_shot("06c_fps_nato_firing")
		await _physics(8)
		Input.action_release("fire")
		Input.action_release("aim")
		fps["player_shots"] = shot_log.size() - n0
		_expect(fps.player_shots > 0, "factions: possessed soldier did not fire")
		_press(KEY_TAB)
		await _physics(8)
	out["fps"] = fps
	# Far and back: the same kit after demotion and promotion, in all three families.
	var kit := {}
	for sq: SquadState in sqs:
		for id in sq.members:
			if _u(id) and _u(id).alive:
				kit[id] = _u(id).loadout
	demo.rts_camera.frame(spot + Vector3(2500, 0, 2500), 0.0, 100.0)
	await _seconds(4.0)
	var far_bodies := 0
	for id in kit:
		far_bodies += 1 if demo.sim.body_of(id) is SoldierBody else 0
	demo.rts_camera.frame(spot, 0.0, 40.0)
	await _seconds(5.0)
	var same := 0
	var back := 0
	for id in kit:
		var b := demo.sim.body_of(id) as SoldierBody
		if b and b.character:
			back += 1
			same += 1 if _u(id).loadout == kit[id] and b.character.loadout.id == kit[id] else 0
	out["near_far"] = {"soldiers": kit.size(), "far_bodies": far_bodies, "back_bodies": back, "same_kit": same}
	_expect(far_bodies == 0 and back == kit.size() and same == back, "factions: kit lost across tiers (%s)" % str(out.near_far))
	brain.enabled = true
	return out


# --- Scenario B: a military base from the new library -------------------------------------

func _base() -> Dictionary:
	if not fob.is_empty():
		return fob.info
	var out := {}
	con.set_active(true)
	con.clear_trees = true
	var hq0 := war.objective(war.faction(0).hq_objective)
	var c := _find_base_site(hq0.position)
	out["site"] = [snappedf(c.x, 1.0), snappedf(c.y, 0.1), snappedf(c.z, 1.0)] if c.is_finite() else "none"
	_expect(c.is_finite(), "base precondition: no open site within 1 km of the North HQ")
	if not c.is_finite():
		fob = {"info": out}
		con.set_active(false)
		return out
	demo.rts_camera.frame(c, 0.0, 160.0)
	await _seconds(3.0)
	var placed := {}
	placed.hq = await _build(&"hq_building", c + Vector3(0, 0, -30), 0.0)
	placed.barracks_1 = await _build(&"barracks_block", c + Vector3(-42, 0, -8), 0.0)
	placed.barracks_2 = await _build(&"barracks_block", c + Vector3(-42, 0, 8), 0.0)
	placed.supply = await _build(&"supply_depot", c + Vector3(42, 0, -18), 0.0)
	placed.vehicle_depot = await _build(&"vehicle_depot", c + Vector3(42, 0, 22), 0.0)
	placed.tower_nw = await _build(&"guard_tower_steel", c + Vector3(-68, 0, -58), 0.0)
	placed.tower_ne = await _build(&"guard_tower_steel", c + Vector3(68, 0, -58), 0.0)
	placed.generator = await _build(&"generator_60kw", c + Vector3(14, 0, -14), 0.0)
	placed.container_1 = await _build(&"iso_container_20_od", c + Vector3(54, 0, -46), 0.0)
	placed.container_2 = await _build(&"iso_container_20_od", c + Vector3(58, 0, -46), 0.0)
	placed.tent = await _build(&"tent_frame_10x6", c + Vector3(-18, 0, 30), 0.0)
	placed.light_tower = await _build(&"light_tower", c + Vector3(14, 0, 30), 0.0)
	placed.parking_pad = await _build(&"vehicle_parking_pad", c + Vector3(-42, 0, 42), 0.0)
	placed.gate = await _build(&"fence_gate", c + Vector3(0, 0, 65), 0.0)
	# Perimeter: HESCO on three sides (open polyline), chain-link along the south side
	# snapped to the gate posts, a T-wall behind the HQ, a sandbag position inside.
	var hx := 75.0
	var hz := 65.0
	placed.hesco = await _line(&"hesco", [c + Vector3(-hx, 0, hz), c + Vector3(-hx, 0, -hz), c + Vector3(hx, 0, -hz), c + Vector3(hx, 0, hz)])
	placed.fence_w = await _line(&"fence", [c + Vector3(-hx, 0, hz), c + Vector3(-2.1, 0, 65)])
	placed.fence_e = await _line(&"fence", [c + Vector3(2.1, 0, 65), c + Vector3(hx, 0, hz)])
	placed.t_wall = await _line(&"t_wall", [c + Vector3(-12, 0, -46), c + Vector3(12, 0, -46)])
	placed.sandbags = await _line(&"sandbag_wall_2m", [c + Vector3(22, 0, 2), c + Vector3(30, 0, 2)])
	await _physics(3)
	# Gravel yard in front of the vehicle depot.
	con.select_type(&"area_gravel")
	for o in [Vector2(22, 40), Vector2(62, 40), Vector2(62, 58), Vector2(22, 58)]:
		await _tool_click(c + Vector3(o.x, 0, o.y))
	var ychk: Dictionary = con.check.duplicate()
	placed.yard = con.finish_surface()
	out["yard"] = {"built": placed.yard != null, "reason": ychk.get("reason", ""), "area_m2": ychk.get("area_m2", 0.0), "grade": ychk.get("grade", 0.0)}
	await _physics(3)
	# A gravel (or dirt) road from the gate to the nearest world road. Like a player, try
	# junction points along that road until the tool accepts one (a junction on a steep
	# stretch is refused by the grade rule).
	var net: RoadNetwork = demo.sim.state.roads
	var gate_out := c + Vector3(0, 0, 76)
	var road := {}
	var near := net.nearest(gate_out, 2000.0, 0, 0.0)
	if near.is_empty():
		road = {"built": false, "reason": "no world road within 2 km"}
	else:
		var wroad := near.road as RoadNetwork.Road
		var cands: Array = []
		for i in range(0, wroad.points.size(), 4):
			if _flat(wroad.points[i], gate_out) < 900.0:
				cands.append(wroad.points[i])
		cands.sort_custom(func(a: Vector3, b: Vector3) -> bool: return _flat(a, gate_out) < _flat(b, gate_out))
		var attempts := 0
		for end: Vector3 in cands.slice(0, 10):
			for type in [&"road_gravel", &"road_dirt"]:
				attempts += 1
				var mid := gate_out.lerp(end, 0.5)
				var n0 := cs.count()
				con.cancel()
				con.select_type(type)
				await _tool_click(gate_out)
				await _tool_click(mid)
				# The last point lands on the world road: the tool validates the whole curve
				# and, like a player's click onto a road, builds it at once when it passes.
				con.cursor = demo.on_ground(end.x, end.z, 0.0)
				con.snap = con._road_snap(con.cursor)
				con._refresh_surface_check()
				var rchk: Dictionary = con.check.duplicate()
				con.add_surface_point()
				if cs.count() == n0:
					con.finish_surface()
				var built := cs.count() > n0
				road = {"built": built, "type": String(type), "reason": rchk.get("reason", ""), "length_m": snappedf(rchk.get("length_m", 0.0), 1.0),
					"grade": rchk.get("grade", 0.0), "max_cut_m": rchk.get("max_cut_m", 0.0), "world_road": wroad.name, "attempts": attempts}
				if built:
					placed.road = cs.all()[-1]
					break
				con.cancel()
			if placed.has("road"):
				break
		if placed.has("road"):
			var r: StructureState = placed.road
			await _physics(5)
			var prof := r.profile
			var cells := 0
			var on_road := 0
			for i in range(0, prof.size(), 10):
				cells += 1
				var cell := ws.routes.world_to_cell(prof[i])
				on_road += 1 if ws.routes.road[cell.y * ws.routes.size.x + cell.x] == 1 else 0
			road["grid_road_cells"] = "%d/%d" % [on_road, cells]
			road["junction_step_m"] = snappedf(absf(prof[prof.size() - 1].y - demo.terrain.data.get_height(prof[prof.size() - 1])), 0.01)
			_expect(on_road == cells, "base: route grid marks %d of %d cells of the base road" % [on_road, cells])
	out["road"] = road
	_expect(road.get("built", false), "base: no road from the gate to the world network (%s)" % road.get("reason", "?"))
	if shots:
		con.select_type(&"t_wall")
		con.cursor = c + Vector3(30, 0, 50)
		demo.rts_camera.frame(c + Vector3(20, 0, 30), 0.4, 80.0)
		await _seconds(1.5)
		_shot("15_construction_menu")
	con.clear_tool()
	con.set_active(false)
	# What stands: every role placed, groundwork pads, grass cleared, collision and nav
	# obstacles present, the walkable pad absent from both.
	var missing := []
	for k in placed:
		if placed[k] == null:
			missing.append(k)
	out["placed"] = placed.keys().filter(func(k: String) -> bool: return placed[k] != null)
	out["missing"] = missing
	_expect(missing.is_empty(), "base: not built: %s" % str(missing))
	var pads := {}
	for k in ["hq", "barracks_1", "supply", "vehicle_depot", "tower_nw"]:
		var s: StructureState = placed.get(k)
		if s:
			var def := StructureCatalog.get_def(s.type_id)
			var xf: Transform3D = s.instances[0]
			# The pad is level: the terrain under the four footprint corners within a few cm of the floor.
			var b := def.bounds()
			var worst := 0.0
			for sx in [-0.5, 0.5]:
				for sz in [-0.5, 0.5]:
					var p := xf * Vector3(b.get_center().x + sx * b.size.x * 0.9, 0, b.get_center().z + sz * b.size.z * 0.9)
					worst = maxf(worst, absf(demo.ground_height(p) - (xf.origin.y + def.sink)))
			pads[k] = snappedf(worst, 0.01)
			_expect(worst < 0.25, "base: %s stands %.2f m off its pad" % [k, worst])
	out["pad_corner_error_m"] = pads
	await _seconds(1.0)
	var obstacles := sm.nav_obstacles(c, 110.0)
	var pad_def := StructureCatalog.get_def(&"vehicle_parking_pad")
	var pad_in_grid := placed.parking_pad != null and sm.blocks_point(Vector2(placed.parking_pad.position.x, placed.parking_pad.position.z), 0.3)
	var hq_in_grid := placed.hq != null and sm.blocks_point(Vector2(placed.hq.position.x, placed.hq.position.z), 0.3)
	var gate_in_grid := placed.gate != null and sm.blocks_point(Vector2(placed.gate.position.x, placed.gate.position.z), 0.3)
	out["navigation"] = {"nav_obstacles": obstacles.size(), "hq_blocks_abstract": hq_in_grid, "gate_opening_blocks_abstract": gate_in_grid,
		"parking_pad_blocks_abstract": pad_in_grid, "parking_pad_collision_boxes": pad_def.get_collision_boxes().size()}
	_expect(obstacles.size() > 20 and hq_in_grid and not gate_in_grid and not pad_in_grid, "base: blocking data wrong (%s)" % JSON.stringify(out.navigation))
	out["manager"] = sm.stats()
	out["structures"] = cs.count()
	fob = {"info": out, "center": c, "gate": c + Vector3(0, 0, 65), "inside": c + Vector3(0, 0, 10), "placed": placed, "hx": hx, "hz": hz}
	if shots:
		demo.rts_camera.frame(c + Vector3(0, 0, 10), 0.75, 190.0)
		await _seconds(3.0)
		_shot("07_base_rts_overview")
		demo.rts_camera.frame(c + Vector3(0, 0, -20), 2.4, 70.0)
		await _seconds(2.0)
		_shot("08_base_rts_hq_close")
		demo.rts_camera.frame(c + Vector3(42, 0, 30), 0.3, 90.0)
		await _seconds(2.0)
		_shot("08b_base_rts_motorpool")
		demo.rts_camera.frame(gate_out + Vector3(0, 0, 60), PI, 160.0)
		await _seconds(2.0)
		_shot("09_base_road_to_network")
		await _map_shot("10_map_base_area", Vector2(c.x, c.z), 5.0)
	return out


## An open, flat, dry site 350-950 m from the North HQ with no structure within 140 m.
func _find_base_site(origin: Vector3) -> Vector3:
	var hq_def := StructureCatalog.get_def(&"hq_building")
	var net: RoadNetwork = demo.sim.state.roads
	for r in [350.0, 500.0, 650.0, 800.0, 950.0]:
		for k in 16:
			var a := k * TAU / 16.0
			var c := demo.on_ground(origin.x + cos(a) * r, origin.z + sin(a) * r, 0.0)
			if not sm._ids_in(Rect2(Vector2(c.x, c.z), Vector2.ZERO).grow(140.0)).is_empty():
				continue
			# No world road under the perimeter (150 x 130 m), one within reach for the access road.
			if not net.nearest(c, 135.0, 0, 0.0).is_empty() or net.nearest(c, 1200.0, 0, 0.0).is_empty():
				continue
			# The HQ footprint must be buildable (slope, water, boulders, settlement
			# buildings) everywhere inside the perimeter and out to the access road's start.
			var ok := true
			var hs := []
			for ix in range(-70, 71, 14):
				for iz in range(-62, 91, 15):
					var off := Vector3(ix, 0, iz)
					var chk := sm.check_building(hq_def, c + off, 0.0)
					hs.append(demo.ground_height(c + off))
					if not chk.ok:
						ok = false
						break
				if not ok:
					break
			if ok and hs.max() - hs.min() < 9.0:
				return c
	return Vector3.INF


func _build(id: StringName, pos: Vector3, yaw: float) -> StructureState:
	con.select_type(id)
	con.yaw = yaw
	con.cursor = demo.on_ground(pos.x, pos.z, 0.0)
	con.snap = {}
	var s := con.place_building()
	if s == null:
		print("WI03 could not place %s at (%.0f, %.0f): %s" % [id, pos.x, pos.z, con.check.get("reason", "?")])
	await _physics(2)
	return s


func _line(id: StringName, pts: Array) -> StructureState:
	con.select_type(id)
	var n := cs.count()
	for p: Vector3 in pts:
		con.cursor = demo.on_ground(p.x, p.z, 0.0)
		con.snap = con._find_snap(con.cursor)
		con._refresh_check()
		con.add_line_point()
	if cs.count() == n:
		con.finish_line()
	await _physics(2)
	if cs.count() > n:
		return cs.all()[-1]
	print("WI03 line %s not built: %s" % [id, con.message])
	return null


# --- Scenario C: infantry through the base ---------------------------------------------------

## A squad outside walks in through the gate (bodies), another crosses the base in the
## abstract tier; nobody stands inside a blocking footprint, everybody arrives.
func _base_nav() -> Dictionary:
	await _base()
	if not fob.has("center"):
		return {"skipped": "no base"}
	var c: Vector3 = fob.center
	var out := {}
	brain.enabled = false
	# Bodies: the camera watches the gate.
	var sq := _spawn(0, c + Vector3(6, 0, 112), 8)
	demo.rts_camera.frame(c + Vector3(0, 0, 50), 0.0, 70.0)
	await _seconds(3.0)
	out["in_through_gate_bodies"] = await _march(sq, c + Vector3(0, 0, 8), 240.0, 6.0)
	_shot("11_infantry_through_gate")
	out["across_to_hq_bodies"] = await _march(sq, c + Vector3(-15, 0, -6), 240.0, 6.0)
	_shot("11b_infantry_inside_base")
	# Abstract: the camera far away, a squad from the north side must round the HESCO wall.
	var sq2 := _spawn(0, c + Vector3(0, 0, -115), 8)
	demo.rts_camera.frame(c + Vector3(3000, 0, 3000), 0.0, 120.0)
	await _seconds(3.0)
	out["abstract_round_wall_into_base"] = await _march(sq2, c + Vector3(0, 0, 20), 600.0, 12.0)
	brain.enabled = true
	for k in out:
		var r: Dictionary = out[k]
		_expect(r.arrived >= 6 and r.inside_blocking == 0, "base_nav %s: %s" % [k, JSON.stringify(r)])
	return out


func _march(sq: SquadState, goal: Vector3, sim_s: float, scale: float) -> Dictionary:
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(goal)
	var track := {"n": 0, "inside_blocking": 0, "stall_max_s": 0.0, "tier": "body" if _u(sq.members[0]).has_body else "abstract"}
	var last := {}
	var t_last := {}
	await _warp(sim_s, scale, 150.0, func() -> bool:
		var now := demo.sim.state.time
		var done := true
		for id in sq.members:
			var u := _u(id)
			if u == null or not u.alive:
				continue
			track.n += 1
			if sm.blocks_point(Vector2(u.position.x, u.position.z), 0.2):
				track.inside_blocking += 1
			var prev: Vector3 = last.get(id, Vector3.INF)
			if not prev.is_finite() or _flat(prev, u.position) > 1.0:
				last[id] = u.position
				t_last[id] = now
			elif u.has_order():
				track.stall_max_s = maxf(track.stall_max_s, now - t_last[id])
			if _flat(u.position, goal) > 14.0:
				done = false
		return done)
	var arrived := 0
	var dists := []
	for id in sq.members:
		var d := _flat(_u(id).position, goal)
		dists.append(snappedf(d, 0.1))
		arrived += 1 if d <= 14.0 else 0
	track["arrived"] = arrived
	track["of"] = sq.members.size()
	track["dist_m"] = dists
	track["stall_max_s"] = snappedf(track.stall_max_s, 0.1)
	return track


# --- Scenario E: strategic map, RTS, first person ---------------------------------------------

func _views() -> Dictionary:
	var before := {}
	for u in demo.sim.state.soldiers():
		before[u.id] = [u.loadout, u.faction]
	var units0 := demo.sim.state.units.size()
	var out := {"map_rts_fps": await _map_to_fps()}
	var changed := 0
	for id in before:
		var u := _u(id)
		if u and [u.loadout, u.faction] != before[id]:
			changed += 1
	out["identity"] = {"soldiers_before": before.size(), "loadout_or_faction_changed": changed, "units": [units0, demo.sim.state.units.size()]}
	_expect(changed == 0, "views: %d soldiers changed loadout or faction across view transitions" % changed)
	# Camera jumps between the base, a far HQ and back: no duplicate or lost records.
	if demo.strategic_map and demo.strategic_map.visible:
		demo.toggle_map()
	if fob.has("center"):
		var c: Vector3 = fob.center
		var n0 := demo.sim.state.units.size()
		for target in [c, war.objective(war.faction(2).hq_objective).position, c]:
			demo.rts_camera.frame(target, 0.0, 90.0)
			await _seconds(3.0)
		var chk := CharacterIntegrationCheck.run(demo.sim)
		for msg in chk.failures:
			_expect(false, msg)
		out["camera_jumps"] = {"units": [n0, demo.sim.state.units.size()], "check": chk.data, "consistency": _consistency()}
		_expect(n0 == demo.sim.state.units.size() and out.camera_jumps.consistency.count == 0, "views: camera jumps changed the unit set")
		_shot("12_rts_structures_and_soldiers")
	return out


# --- Scenario F: save / load of the combined state --------------------------------------------

func _persist_all() -> Dictionary:
	await _base()
	var out := {}
	var sig_before := _world_sig()
	_press(KEY_F5)
	await _frames(3)
	# Wreck the live state, then load: structures gone, kit forgotten.
	var n_struct := cs.count()
	cs.clear()
	for u in demo.sim.state.soldiers():
		u.loadout = ""
	await _frames(2)
	_press(KEY_F9)
	await _seconds(3.0)
	var sig_after := _world_sig()
	var diff := []
	for k in sig_before:
		if sig_before[k] != sig_after.get(k):
			diff.append({"key": k, "saved": str(sig_before[k]).left(120), "loaded": str(sig_after.get(k)).left(120)})
	out["construction"] = {"structures_saved": n_struct, "structures_loaded": cs.count(), "differences": diff.slice(0, 6), "difference_count": diff.size(),
		"manager": sm.stats()}
	_expect(diff.is_empty() and cs.count() == n_struct and n_struct > 0, "persist: construction / loadouts not restored (%s)" % JSON.stringify(out.construction.differences))
	var chk := CharacterIntegrationCheck.run(demo.sim)
	for msg in chk.failures:
		_expect(false, msg)
	out["characters_after_load"] = chk.data
	# The war itself (operations, squads, objectives) through the same save / load; the AI
	# factions must be running for it (the sandbox check needs active operations).
	_pause_ai(false)
	out["war"] = await _persist()
	_pause_ai(true)
	return out


## Everything the combined save must keep: every structure (type, position / points,
## removed modules), every soldier's loadout and faction, built roads in the network.
func _world_sig() -> Dictionary:
	var sig := {}
	for s: StructureState in cs.all():
		var key := "s:%s:%d" % [s.type_id, s.id]
		# Positions to 0.1 m: the JSON save rounds floats, a building re-fitted on load may
		# differ by a centimetre.
		sig[key] = [s.type_id, s.position.snapped(Vector3.ONE * 0.1), snappedf(s.yaw, 0.001), s.points.size(), s.removed.size(), s.instances.size()]
	for u in demo.sim.state.soldiers():
		sig["u:%d" % u.id] = [u.loadout, u.faction]
	sig["roads_built"] = demo.sim.state.roads.built.size()
	return sig


# --- Vehicle prototypes ----------------------------------------------------------------------

## The 6x6 truck and the 8x8 APC as scene instances on the base yard: imported size equals
## the asset metadata, wheels / suspension / door / seat / cargo markers present, the
## vehicle stands on the ground, LOD ranges contiguous.
func _vehicles() -> Dictionary:
	await _base()
	var out := {}
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/military/catalog.json"))
	var spots := {}
	if fob.has("center"):
		var c: Vector3 = fob.center
		spots["truck_6x6"] = [c + Vector3(34, 0, 49), 0.0]
		spots["apc_8x8"] = [c + Vector3(50, 0, 49), 0.0]
	else:
		var hq := war.objective(war.faction(0).hq_objective).position
		spots["truck_6x6"] = [hq + Vector3(40, 0, 60), 0.0]
		spots["apc_8x8"] = [hq + Vector3(48, 0, 60), 0.0]
	for id in VEHICLE_GLBS:
		var ps := load(VEHICLE_GLBS[id]) as PackedScene
		var v := ps.instantiate() as Node3D
		demo.add_child(v)
		_vehicle_nodes.append(v)
		var p: Vector3 = spots[id][0]
		v.global_position = demo.on_ground(p.x, p.z, 0.0)
		v.rotation.y = spots[id][1]
		await _frames(2)
		var meta: Dictionary = v.get_meta("fn_asset", {})
		var lod0: MeshInstance3D = null
		var lods := {}
		var markers := []
		for n in v.get_children():
			var nm := String(n.name)
			if n is MeshInstance3D and nm.contains("_LOD"):
				lods[nm] = [(n as MeshInstance3D).visibility_range_begin, (n as MeshInstance3D).visibility_range_end]
				if nm.ends_with("_LOD0"):
					lod0 = n
			elif n is Node3D and not (n is MeshInstance3D) and not (n is CollisionShape3D) and not (n is StaticBody3D):
				markers.append(nm)
		var aabb := lod0.get_aabb() if lod0 else AABB()
		var want: Array = catalog.get(id, {}).get("size_above_ground", [0, 0, 0])
		# Blender (W, D, H) -> Godot (x, z, y).
		var size_err := [snappedf(aabb.size.x - want[0], 0.01), snappedf(aabb.size.y - want[2], 0.01), snappedf(aabb.size.z - want[1], 0.01)]
		var ground_gap := snappedf((v.global_position.y + aabb.position.y) - demo.ground_height(v.global_position), 0.01)
		var counts := {}
		for m: String in markers:
			var pre := m.get_slice("_", 0)
			counts[pre] = counts.get(pre, 0) + 1
		out[id] = {"meta": not meta.is_empty(), "size_godot": [snappedf(aabb.size.x, 0.01), snappedf(aabb.size.y, 0.01), snappedf(aabb.size.z, 0.01)],
			"size_error_m": size_err, "lods": lods, "markers": counts, "lowest_point_above_ground_m": ground_gap,
			"materials": _material_names(lod0)}
		_expect(not meta.is_empty(), "vehicles: %s has no fn_asset metadata (import script)" % id)
		_expect(absf(size_err[0]) < 0.05 and absf(size_err[1]) < 0.05 and absf(size_err[2]) < 0.05, "vehicles: %s size differs from the asset metadata %s" % [id, str(size_err)])
		_expect(counts.get("WHEEL", 0) == (6 if id == "truck_6x6" else 8), "vehicles: %s has %d WHEEL markers" % [id, counts.get("WHEEL", 0)])
		_expect(counts.get("SEAT", 0) > 0 and counts.get("DOOR", 0) > 0, "vehicles: %s lacks seat / door markers" % id)
		_expect(absf(ground_gap) < 0.12, "vehicles: %s lowest point %.2f m from the ground" % [id, ground_gap])
		_expect(lods.size() == 3, "vehicles: %s has %d LOD meshes" % [id, lods.size()])
	if shots:
		var look: Vector3 = spots["truck_6x6"][0].lerp(spots["apc_8x8"][0], 0.5)
		demo.rts_camera.frame(look, 0.5, 26.0)
		await _seconds(2.0)
		_shot("13_vehicles_on_yard")
		demo.rts_camera.frame(look, 2.6, 14.0)
		await _seconds(1.0)
		_shot("13b_vehicles_close")
	return out


func _material_names(mi: MeshInstance3D) -> Array:
	var names := []
	if mi and mi.mesh:
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			names.append(m.resource_name if m else "none")
	return names


# --- Scenario G: representative performance ------------------------------------------------------

func _perf_all() -> Dictionary:
	await _base()
	var out := {}
	if fob.has("center"):
		var c: Vector3 = fob.center
		brain.enabled = false
		var garrison := [_spawn(0, c + Vector3(-20, 0, 20), 8), _spawn(0, c + Vector3(20, 0, 20), 8), _spawn(0, c + Vector3(0, 0, 40), 8)]
		demo.rts_camera.frame(c, 0.6, 120.0)
		await _seconds(3.0)
		out["rts_base_120m"] = await _measure_render(6.0)
		demo.rts_camera.frame(c + Vector3(0, 0, 10), 0.8, 45.0)
		await _seconds(2.0)
		out["rts_base_45m"] = await _measure_render(6.0)
		var pid: int = garrison[0].members[0]
		var body := await _possess(pid)
		if body:
			await _fps_shot_at(body, c + Vector3(0, 1.5, -30))
			await _seconds(1.0)
			out["fps_in_base"] = await _measure_render(6.0)
			_shot("14_fps_in_base")
			_press(KEY_TAB)
			await _physics(5)
		demo.toggle_map()
		await _frames(5)
		out["map_with_base"] = await _measure_render(4.0)
		demo.toggle_map()
		brain.enabled = true
	# The sandbox baseline cases (HQ, map, far war, 8 x, 50 v 50 RTS / FPS) for comparison
	# with INTEGRATION-02 / WORLD-PLAYTEST-01 numbers.
	out["sandbox"] = await _perf()
	return out


func _measure_render(seconds: float) -> Dictionary:
	var m := await _measure_case(seconds)
	m["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	m["primitives_k"] = snappedf(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0, 1.0)
	m["video_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 1.0)
	m["structures"] = sm.stats()
	return m

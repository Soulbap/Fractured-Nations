## GAMEPLAY-01B checks: scenarios and safe saves (A), the early economy (B), construction sites and the BUILD
## tactic (C), and the integrated first-playable loop, in the real game on ref_20km.
##
##   Godot.exe --path . --resolution 1600x900 --log-file gp.log res://scenes/game/world_ref_20km.tscn -- --scenario=new_game --gameplay01b-test [--shots] [--only a_new,a_save,...]
##
## Runs in the test save folder (user://test_saves, CoreDemo.automated_run). Prints "GP <check> <json>", writes
## res://benchmarks/raw/gameplay01b_test.json and (with --shots) docs/gameplay01b/*.png.
class_name GameplaySelfTest
extends CoreSelfTest

var only: PackedStringArray = []
var _done := false


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/gameplay01b"
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	SoldierBody.require_mouse_capture = false
	tree.create_timer(1500.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	if _want("probe"):
		_log("probe", _probe())
	if _want("a_dev"):
		_log("a_dev", _a_dev())
	if _want("a_new"):
		_log("a_new", await _a_new())
	if _want("a_save"):
		_log("a_save", await _a_save())
	if _want("a_continue"):
		_log("a_continue", _a_continue())
	_finish()


func _war() -> WarState:
	return demo.sim.state.war


func _player_squads() -> Array:
	return demo.sim.war.squads_of(_war().player_faction)


func _vehicles_of(f: int) -> int:
	var n := 0
	for u: UnitState in demo.sim.state.units.values():
		if u.kind == UnitState.Kind.VEHICLE and u.faction == f and u.alive:
			n += 1
	return n


func _owner_of(oname: String) -> int:
	for o: ObjectiveState in _war().all_objectives():
		if o.obj_name == oname:
			return o.owner
	return -2


# --- Stage A ------------------------------------------------------------------------------------------------------

## Development Scenario regression: the audit baseline (3 factions, 12 objectives, 15 squads, 120 soldiers), North HQ held
## by the player, AI bases for South and East, the old rules.
func _a_dev() -> Dictionary:
	var war := _war()
	_expect(war.scenario_id == "dev", "a_dev: scenario is %s (run with --scenario=dev)" % war.scenario_id)
	var bs := demo.sim.logistics.bases
	var out := {"factions": war.factions.size(), "objectives": war.objectives.size(), "squads": demo.sim.state.squads.size(),
		"soldiers": demo.sim.state.count_of(UnitState.Kind.SOLDIER), "north_hq": _owner_of("North HQ"),
		"bases": {"North": bs.bases_of(0).size(), "South": bs.bases_of(1).size(), "East": bs.bases_of(2).size()},
		"rules": war.rules, "camera": [roundi(demo.rts_camera.focus.x), roundi(demo.rts_camera.focus.z)]}
	_expect(out.factions == 3 and out.objectives == 12 and out.squads == 15 and out.soldiers == 120,
		"a_dev: baseline counts differ: %s" % str([out.factions, out.objectives, out.squads, out.soldiers]))
	_expect(out.north_hq == 0, "a_dev: North HQ is not the player's")
	_expect(out.bases.South == 1 and out.bases.East == 1 and out.bases.North == 0, "a_dev: AI bases %s" % str(out.bases))
	_expect(war.rule("free_reserves", false) and war.rule("start_stock_gift", false) and not war.rule("build_sites", true), "a_dev: rules %s" % str(war.rules))
	return out


## New Game: one North squad of eight in the south, no base / structures / vehicles / objectives of the player, South in
## the north with its base there, East unchanged; the camera on the squad; RTS, possession and the map work.
func _a_new() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	_expect(war.scenario_id == "new_game", "a_new: scenario is %s (run with --scenario=new_game)" % war.scenario_id)
	var sqs := _player_squads()
	var soldiers := 0
	for sq: SquadState in sqs:
		soldiers += sq.members.size()
	var player_structures := 0
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == pf and not s.is_line():
			player_structures += 1
	var bs := demo.sim.logistics.bases
	var south_bases: Array = bs.bases_of(1)
	var start: Vector3 = demo.sim.war.squad_center(sqs[0]) if not sqs.is_empty() else Vector3.INF
	var nearest_enemy_base := INF
	for f in [1, 2]:
		for b: Dictionary in bs.bases_of(f):
			nearest_enemy_base = minf(nearest_enemy_base, Vector2(b.anchor.x - start.x, b.anchor.z - start.z).length())
	var nearest_enemy := INF
	for u: UnitState in demo.sim.state.units.values():
		if u.alive and u.faction != pf and u.kind == UnitState.Kind.SOLDIER:
			nearest_enemy = minf(nearest_enemy, Vector2(u.position.x - start.x, u.position.z - start.z).length())
	var out := {"squads": sqs.size(), "soldiers": soldiers, "faction": pf, "player_bases": bs.bases_of(pf).size(), "player_structures": player_structures,
		"player_vehicles": _vehicles_of(pf), "player_objectives": war.owned_by(pf).size(), "start": [roundi(start.x), roundi(start.z)],
		"owners": {"Nordmoen HQ": _owner_of("Nordmoen HQ"), "Elvetun": _owner_of("Elvetun"), "North Bridge": _owner_of("North Bridge"),
			"Verket": _owner_of("Verket"), "Sørmoen": _owner_of("Sørmoen"), "East HQ": _owner_of("East HQ"), "Østby": _owner_of("Østby")},
		"south_base_z": roundi(south_bases[0].anchor.z) if not south_bases.is_empty() else 0, "nearest_enemy_base_m": roundi(nearest_enemy_base),
		"nearest_enemy_soldier_m": roundi(nearest_enemy), "pool": war.faction(pf).pool.to_dict().items, "rules": war.rules,
		"squads_total": demo.sim.state.squads.size(), "soldiers_total": demo.sim.state.count_of(UnitState.Kind.SOLDIER),
		"overlay_faction": demo.tactics_overlay.player_faction, "rts_faction": demo.rts.player_faction}
	_expect(sqs.size() == 1 and soldiers == 8, "a_new: player has %d squads / %d soldiers (want 1 / 8)" % [sqs.size(), soldiers])
	_expect(pf == 0 and war.faction(0).faction_name == "North", "a_new: the player is not North")
	_expect(out.player_bases == 0 and player_structures == 0 and out.player_vehicles == 0 and out.player_objectives == 0,
		"a_new: the player starts with something: %s" % str([out.player_bases, player_structures, out.player_vehicles, out.player_objectives]))
	_expect(out.owners["Nordmoen HQ"] == 1 and out.owners.Elvetun == 1 and out.owners["North Bridge"] == 1, "a_new: South does not hold the north: %s" % str(out.owners))
	_expect(out.owners.Verket == -1 and out.owners["Sørmoen"] == -1, "a_new: the south is not neutral: %s" % str(out.owners))
	_expect(out.owners["East HQ"] == 2 and out.owners["Østby"] == 2, "a_new: East lost its ground: %s" % str(out.owners))
	_expect(south_bases.size() == 1 and out.south_base_z < -5000, "a_new: South's base is not in the north (%s)" % str(out.south_base_z))
	_expect(nearest_enemy_base > 5000.0 and nearest_enemy > 2500.0, "a_new: enemy too close to the start (base %d m, soldier %d m)" % [out.nearest_enemy_base_m, out.nearest_enemy_soldier_m])
	_expect(start.z > 5000.0, "a_new: the start is not in the south (%s)" % str(out.start))
	_expect(out.overlay_faction == pf and out.rts_faction == pf, "a_new: overlay / RTS faction differ from the war's player faction")
	var cam := demo.rts_camera.focus
	out["camera_to_squad_m"] = roundi(Vector2(cam.x - start.x, cam.z - start.z).length())
	_expect(float(out.camera_to_squad_m) < 80.0, "a_new: the camera does not start on the squad (%d m)" % out.camera_to_squad_m)
	if sqs.is_empty():
		return out
	# Controls: RTS selection and a move order, the strategic map, first person and back.
	var sq: SquadState = sqs[0]
	demo.rts.select_squads([sq.id])
	var n := demo.rts.order_move(demo.on_ground(start.x + 25.0, start.z - 20.0))
	await _seconds(3.0)
	out["move_ordered"] = n
	out["move_status"] = SquadState.Status.keys()[sq.status]
	_expect(n == 8 and sq.order == SquadState.Order.MOVE, "a_new: the squad did not take an RTS move order (%d)" % n)
	demo.toggle_map()
	await _seconds(1.0)
	out["map_open"] = demo.strategic_map.visible
	_png("a_new_map")
	demo.toggle_map()
	await _seconds(0.5)
	_expect(bool(out.map_open), "a_new: the strategic map did not open")
	demo.game.possess(sq.leader_id)
	await _seconds(1.5)
	out["fps"] = demo.game.mode == GameController.Mode.FPS
	_png("a_new_fps")
	demo.game.enter_rts()
	await _seconds(1.0)
	_expect(bool(out.fps) and demo.game.mode == GameController.Mode.RTS, "a_new: possession / return to RTS failed")
	demo.rts_camera.frame(demo.sim.war.squad_center(sq), 0.5, 70.0)
	await _seconds(1.5)
	_png("a_new_start_rts")
	return out


## Saves go to the test folder; a damaged save is refused with a reason and changes nothing; a New Game save loads back
## with its scenario, rules, ownership and without duplicates. The player's own save folder is not touched.
func _a_save() -> Dictionary:
	var war := _war()
	var con := demo.construction
	var out := {"save_dir": demo.save_dir(), "save_path": con.save_path}
	_expect(con.save_path.begins_with("user://test_saves/"), "a_save: a test would write the player's save (%s)" % con.save_path)
	var user_world := "user://saves/%s/world.json" % demo.config.world_name
	var user_mtime := FileAccess.get_modified_time(user_world) if FileAccess.file_exists(user_world) else -1
	var sq: SquadState = _player_squads()[0]
	var before := {"squads": demo.sim.state.squads.size(), "units": demo.sim.state.units.size(), "structures": demo.sim.state.construction.count(),
		"vehicles": demo.sim.vehicles.ids.size(), "owners": _owners(), "pool": war.faction(war.player_faction).pool.get_qty(Inventory.SUPPLIES),
		"squad_pos": demo.sim.war.squad_center(sq)}
	_expect(con.save(), "a_save: save failed")
	var peek := demo.peek_save()
	out["peek"] = peek
	_expect(peek.ok and peek.scenario == war.scenario_id, "a_save: the save is not recognised: %s" % str(peek))
	# Damage the world file: Continue must refuse it and F9 must not change the running game.
	var wpath := con.world_save_path()
	var good := FileAccess.get_file_as_string(wpath)
	var f := FileAccess.open(wpath, FileAccess.WRITE)
	f.store_string("{ not a save")
	f.close()
	var bad_peek := demo.peek_save()
	var bad_load := con.load_game()
	out["damaged"] = {"peek": bad_peek, "load": bad_load, "units_after": demo.sim.state.units.size()}
	_expect(not bad_peek.ok and String(bad_peek.reason) != "" and not bad_load.ok and demo.sim.state.units.size() == before.units,
		"a_save: a damaged save was not refused cleanly: %s" % str(out.damaged))
	f = FileAccess.open(wpath, FileAccess.WRITE)
	f.store_string(good)
	f.close()
	# Change the world, then load: everything is back as saved, nothing doubled.
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(demo.on_ground(before.squad_pos.x - 40.0, before.squad_pos.z + 30.0))
	await _seconds(4.0)
	war.faction(war.player_faction).pool.add(Inventory.SUPPLIES, 777.0)
	var res := con.load_game()
	await _physics(10)
	var sq2: SquadState = _player_squads()[0] if not _player_squads().is_empty() else null
	var after := {"squads": demo.sim.state.squads.size(), "units": demo.sim.state.units.size(), "structures": demo.sim.state.construction.count(),
		"vehicles": demo.sim.vehicles.ids.size(), "owners": _owners(), "pool": _war().faction(_war().player_faction).pool.get_qty(Inventory.SUPPLIES),
		"scenario": _war().scenario_id, "rules": _war().rules.size()}
	out["load"] = res
	out["before"] = {"squads": before.squads, "units": before.units, "structures": before.structures, "vehicles": before.vehicles, "pool": before.pool}
	out["after"] = after
	_expect(res.ok, "a_save: load failed: %s" % str(res))
	_expect(after.squads == before.squads and after.units == before.units and after.structures == before.structures and after.vehicles == before.vehicles,
		"a_save: counts changed by save / load: %s -> %s" % [str(out.before), str(after)])
	_expect(after.owners == before.owners and absf(float(after.pool) - float(before.pool)) < 0.01 and after.scenario == "new_game" and int(after.rules) > 0,
		"a_save: ownership / pool / scenario not restored")
	if sq2:
		_expect(Vector2(demo.sim.war.squad_center(sq2).x - before.squad_pos.x, demo.sim.war.squad_center(sq2).z - before.squad_pos.z).length() < 6.0,
			"a_save: the squad is not where it was saved")
	var user_mtime2 := FileAccess.get_modified_time(user_world) if FileAccess.file_exists(user_world) else -1
	out["user_save_untouched"] = user_mtime == user_mtime2
	_expect(user_mtime == user_mtime2, "a_save: the player's own save was modified by the test")
	return out


## Run after a_save in a second process with --continue: the game started from the save (scenario, squads, pool).
func _a_continue() -> Dictionary:
	var war := _war()
	var out := {"continue": demo.continue_result, "scenario": war.scenario_id, "squads": _player_squads().size(),
		"pool": war.faction(war.player_faction).pool.get_qty(Inventory.SUPPLIES), "rules": war.rules.size()}
	_expect(bool(demo.continue_result.get("ok", false)), "a_continue: the game did not continue from the save: %s" % str(demo.continue_result))
	_expect(war.scenario_id == "new_game" and int(out.squads) == 1, "a_continue: wrong scenario / squads after Continue: %s" % str(out))
	return out


func _owners() -> Dictionary:
	var out := {}
	for o: ObjectiveState in _war().all_objectives():
		out[o.obj_name] = o.owner
	return out


func _want(n: String) -> bool:
	return only.is_empty() or only.has(n)


# --- Probe: where the New Game start and the caches can be -------------------------------------------------------

## Candidate start points in the south (Verket / Moen) where a command post fits, with a road near and the distance
## to the objectives; and passable cache spots off the roads at a few distances. Prints, changes nothing.
func _probe() -> Dictionary:
	var sim := demo.sim
	var war := sim.state.war
	var sm := demo.structures
	var cp := StructureCatalog.get_def(&"command_post")
	var objs := {}
	for o: ObjectiveState in war.all_objectives():
		objs[o.obj_name] = [roundi(o.position.x), roundi(o.position.z), o.owner]
	var cands: Array = []
	var center := Vector3(-900.0, 0.0, 6600.0)
	var x := -1600.0
	while x <= 1600.0:
		var z := -1300.0
		while z <= 1300.0:
			var p := demo.on_ground(center.x + x, center.z + z, 0.0)
			z += 100.0
			if not sim.war.routes.passable(p):
				continue
			var road := sim.state.roads.nearest(p, 160.0, 0, 0.0)
			if road.is_empty():
				continue
			var chk := sm.check_building(cp, p, 0.0, -1, true)
			if not chk.ok:
				continue
			var rule := sim.logistics.bases.placement_rule(&"command_post", p, war.player_faction)
			if rule != "":
				continue
			var d_road := Vector2(road.pos.x - p.x, road.pos.z - p.z).length()
			var best_o := ""
			var best_d := INF
			for o: ObjectiveState in war.all_objectives():
				var d := Vector2(o.position.x - p.x, o.position.z - p.z).length()
				if d < best_d:
					best_d = d
					best_o = o.obj_name
			cands.append({"x": roundi(p.x), "z": roundi(p.z), "y": roundi(p.y), "road_m": roundi(d_road), "level_m": snappedf(float(chk.get("level_m", 0.0)), 0.1),
				"nearest": best_o, "nearest_m": roundi(best_d)})
		x += 100.0
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.level_m) + float(a.road_m) * 0.01 < float(b.level_m) + float(b.road_m) * 0.01)
	var caches: Array = []
	for r: float in [500.0, 900.0, 1500.0, 2500.0, 3500.0]:
		for k in 12:
			var a := TAU * k / 12.0
			var p := demo.on_ground(center.x + cos(a) * r, center.z + sin(a) * r, 0.0)
			if not sim.war.routes.passable(p) or not sm.check_building(StructureCatalog.get_def(&"command_post"), p, 0.0, -1, true).ok:
				continue
			var road := sim.state.roads.nearest(p, 400.0, 0, 0.0)
			caches.append({"r": r, "deg": roundi(rad_to_deg(a)), "x": roundi(p.x), "z": roundi(p.z), "road_m": roundi(Vector2(road.pos.x - p.x, road.pos.z - p.z).length()) if not road.is_empty() else -1})
	return {"objectives": objs, "start_candidates": cands.slice(0, 25), "n_candidates": cands.size(), "cache_spots": caches}


# --- Output ------------------------------------------------------------------------------------------------------

func _png(shot_name: String) -> void:
	if not shots:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_shot_dir, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("GP shot: ", path)


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("GP %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		print("GP FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/gameplay01b_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("GP %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()

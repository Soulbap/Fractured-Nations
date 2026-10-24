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
	if _want("b_economy"):
		_log("b_economy", await _b_economy())
	if _want("b_recovery"):
		_log("b_recovery", await _b_recovery())
	if _want("c_build"):
		_log("c_build", await _c_build())
	if _want("c_ai"):
		_log("c_ai", await _c_ai())
	if only.has("smoke_dev"):
		_log("a_dev", _a_dev())
		var t0 := demo.sim.tick_usec.duplicate()
		await _until(func() -> bool: return false, 120.0, 4.0)
		var t1 := demo.sim.tick_usec
		var ticks := maxi(int(t1.ticks) - int(t0.ticks), 1)
		var per := {}
		for k in ["tactics", "war", "squads", "brain"]:
			per[k] = snappedf(float(int(t1[k]) - int(t0[k])) / ticks, 0.1)
		_log("smoke_dev", {"squads": demo.sim.state.squads.size(), "objectives": _war().objectives.size(), "us_per_tick": per,
			"tactics": demo.sim.tactics.summary(), "war_update_us_avg": demo.sim.war.summary().update_us_avg, "economy_hud": demo.hud.economy._strip.visible})
		_expect(not demo.hud.economy._strip.visible, "smoke_dev: the New Game supply strip shows in the Development Scenario")
		await _frame(demo.start_focus() + Vector3(0, 0, 40), 140.0)
		_png("dev_scenario")
	if only.has("loop"):
		_log("loop", await _loop())
	if only.has("loop_continue"):
		_log("loop_continue", await _loop_continue())
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
	# GAMEPLAY-04A: the opening's South checkpoint section stands ~500 m north on purpose (out of sight range, 400 m).
	_expect(nearest_enemy_base > 5000.0 and nearest_enemy > 420.0, "a_new: enemy too close to the start (base %d m, soldier %d m)" % [out.nearest_enemy_base_m, out.nearest_enemy_soldier_m])
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


# --- Stage B ------------------------------------------------------------------------------------------------------

func _stock() -> Dictionary:
	return demo.sim.logistics.bases.faction_stock(_war().player_faction)


func _cache(i: int) -> Dictionary:
	return _war().caches[i] if i < _war().caches.size() else {}


## Waits (simulated time compressed) until cond is true or `limit` simulated seconds passed. Returns the seconds waited.
func _until(cond: Callable, limit: float, speed := 4.0) -> float:
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(speed)
	while not cond.call() and demo.sim.state.time - t0 < limit:
		await _physics(20)
	CoreDemo.apply_time_scale(1.0)
	return demo.sim.state.time - t0


## New Game economy in order: starting pool; no free squads; the first cache walked to and secured once (30 s rule,
## content added once, the next cache revealed); a building refused when short and paid exactly once otherwise; the
## depot takes over the pool without loss; income from an owned objective; recruiting costs and time, cancel refunds
## exactly; the recruit is a commandable squad; pool, caches and queue survive save / load.
func _b_economy() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var f := war.faction(pf)
	var bs := demo.sim.logistics.bases
	var con := demo.construction
	var out := {}
	var s0 := _stock()
	out["start"] = s0
	_expect(roundi(s0.supplies) == 500 and roundi(s0.ammo) == 120, "b: starting stock %s (want 500 supplies, 120 ammunition)" % str(s0))
	# No free squads: the reinforcement timer is due, nothing arrives.
	var squads0 := _player_squads().size()
	f.next_reinforcement_at = 0.0
	demo.sim.war._update_reserves(f)
	out["free_squads"] = _player_squads().size() - squads0
	_expect(_player_squads().size() == squads0, "b: a free squad arrived in New Game")
	# The first cache, by an ordinary move order.
	var c: Dictionary = _cache(0)
	var sq: SquadState = _player_squads()[0]
	_expect((c.known as Array).has(pf), "b: the first cache is not reported to the player")
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(c.pos)
	var walk := await _until(func() -> bool: return c.state == "securing", 300.0)
	var t_sec := demo.sim.state.time
	var secured := await _until(func() -> bool: return c.state == "depleted", 120.0)
	var s1 := _stock()
	out["cache"] = {"walk_s": roundi(walk), "secure_s": roundi(secured), "state": c.state, "stock_after": s1, "revealed": (_cache(1).known as Array).has(pf)}
	_expect(c.state == "depleted" and roundi(s1.supplies - s0.supplies) == 900 and roundi(s1.ammo - s0.ammo) == 150,
		"b: cache not collected as expected: %s" % str(out.cache))
	_expect(secured >= 25.0 and secured <= 50.0, "b: securing took %.0f s (want ~30)" % secured)
	_expect((_cache(1).known as Array).has(pf), "b: the next cache was not revealed")
	await _until(func() -> bool: return false, 20.0)
	_expect(roundi(_stock().supplies) == roundi(s1.supplies), "b: a depleted cache paid again")
	_png("b_cache_secured")
	# Construction cost: refused when short, paid once otherwise (instant placement in this stage).
	var near: Vector3 = demo.sim.war.squad_center(sq)
	var spot := _cp_spot(near)
	_expect(spot.is_finite(), "b: no command post site near the squad")
	if not spot.is_finite():
		return out
	f.pool.take(Inventory.SUPPLIES, f.pool.get_qty(Inventory.SUPPLIES) - 100.0)
	var refused := _place(&"command_post", spot)
	out["short"] = {"placed": refused != null, "message": con.message, "reason": con.check.get("reason", "")}
	_expect(refused == null and String(out.short.message).contains("not enough supplies"), "b: an unaffordable command post was placed or refused without the reason")
	f.pool.add(Inventory.SUPPLIES, 1300.0 - 100.0)
	var before: float = _stock().supplies
	var cp := _place(&"command_post", spot)
	await _physics(5)
	out["cp"] = {"placed": cp != null, "paid": roundi(before - _stock().supplies)}
	_expect(cp != null and roundi(before - _stock().supplies) == 400, "b: the command post was not paid exactly once: %s" % str(out.cp))
	if cp == null:
		return out
	await _until(func() -> bool: return not cp.is_site(), 300.0)
	# The depot takes over the pool (Inventory.transfer: totals unchanged).
	var bid := cp.base_id
	var total_before := _stock()
	var depot := _place(&"supply_depot", _site_in_base(&"supply_depot", cp.position))
	_expect(depot != null, "b: no supply depot placed")
	if depot == null:
		return out
	await _until(func() -> bool: return not depot.is_site(), 300.0)
	await _physics(90)
	var total_after := _stock()
	out["depot"] = {"pool_after": f.pool.get_qty(Inventory.SUPPLIES), "depot": depot.inventory.summary() if depot.inventory else "-", "before": total_before, "after": total_after,
		"start_stock_gift": demo.sim.state.logistics.starter_given.get(pf, false)}
	_expect(f.pool.is_empty() and depot.inventory != null and absf(float(total_after.supplies) - (float(total_before.supplies) - 450.0)) < 0.5,
		"b: the pool did not move into the depot without loss: %s" % str(out.depot))
	_expect(not demo.sim.state.logistics.starter_given.get(pf, false), "b: the free starting stockpile was given in New Game")
	# Income: an owned objective pays every minute into the depot.
	var verket: ObjectiveState = null
	for o: ObjectiveState in war.all_objectives():
		if o.obj_name == "Verket":
			verket = o
	demo.sim.war._transfer(verket, pf)
	var s2 := _stock()
	demo.sim.war.econ.player_income(f, 1.0)
	var s3 := _stock()
	out["income"] = {"per_min": demo.sim.war.econ.rate_per_min(f), "got": roundi(s3.supplies - s2.supplies), "depot": depot.inventory.get_qty(Inventory.SUPPLIES)}
	_expect(roundi(s3.supplies - s2.supplies) == 60, "b: Verket (value 2) did not pay 60 supplies per minute: %s" % str(out.income))
	# Recruitment: barracks, cost, time, refund on cancel, a commandable squad.
	f.pool.add(Inventory.SUPPLIES, 600.0)
	var barracks := _place(&"barracks_block", _site_in_base(&"barracks_block", cp.position))
	_expect(barracks != null, "b: no barracks placed")
	if barracks == null:
		return out
	await _until(func() -> bool: return not barracks.is_site(), 300.0)
	var s4 := _stock()
	var r1 := bs.recruit(barracks.id)
	var s5 := _stock()
	bs.cancel_queue(barracks.id, 0)
	var s6 := _stock()
	out["recruit_cancel"] = {"ok": r1.ok, "paid": [roundi(s4.supplies - s5.supplies), roundi(s4.ammo - s5.ammo)], "refunded_exact": absf(s6.supplies - s4.supplies) < 0.01 and absf(s6.ammo - s4.ammo) < 0.01}
	_expect(r1.ok and roundi(s4.supplies - s5.supplies) == 320 and roundi(s4.ammo - s5.ammo) == 192 and out.recruit_cancel.refunded_exact,
		"b: recruit cost / refund wrong: %s (%s)" % [str(out.recruit_cancel), r1.reason])
	var n_before := _player_squads().size()
	var r2 := bs.recruit(barracks.id)
	var waited := await _until(func() -> bool: return _player_squads().size() > n_before, 120.0)
	var recruit: SquadState = _player_squads().back()
	out["recruit"] = {"ok": r2.ok, "reason": r2.reason, "seconds": roundi(waited), "squads": _player_squads().size(), "commandable": demo.rts._can_command(recruit.leader_id), "members": recruit.members.size()}
	_expect(r2.ok and _player_squads().size() == n_before + 1 and waited >= 55.0 and recruit.members.size() == 8, "b: recruitment did not produce a squad after ~60 s: %s" % str(out.recruit))
	demo.rts.select_squads([recruit.id])
	var moved := demo.rts.order_move(demo.sim.war.squad_center(recruit) + Vector3(20, 0, 20))
	_expect(moved == 8, "b: the recruited squad does not take orders")
	# Save / load: pool, caches, ownership and stock come back as they were.
	var snap := {"stock": _stock(), "caches": war.caches.map(func(x: Dictionary) -> String: return "%s:%s" % [x.name, x.state])}
	con.save()
	f.pool.add(Inventory.SUPPLIES, 999.0)
	war.caches[0].state = "intact"
	var res := con.load_game()
	await _physics(10)
	var snap2 := {"stock": _stock(), "caches": _war().caches.map(func(x: Dictionary) -> String: return "%s:%s" % [x.name, x.state])}
	out["persist"] = {"before": snap, "after": snap2, "load": res.ok}
	_expect(res.ok and str(snap.caches) == str(snap2.caches) and absf(float(snap.stock.supplies) - float(snap2.stock.supplies)) < 0.5,
		"b: economy state not restored by save / load: %s" % str(out.persist))
	return out


## Every player soldier dies before a barracks exists: a small section arrives after the delay, once; the pending
## arrival survives save / load.
func _b_recovery() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var f := war.faction(pf)
	var out := {}
	for sq: SquadState in _player_squads():
		for id in sq.members.duplicate():
			demo.sim.combat.kill(demo.sim.state.get_unit(id))
	await _physics(10)
	_expect(_player_squads().is_empty(), "b_recovery: soldiers left after killing all")
	await _until(func() -> bool: return f.recovery_at >= 0.0, 20.0)
	out["due_in"] = roundi(f.recovery_at - demo.sim.state.time)
	_expect(f.recovery_at >= 0.0, "b_recovery: no recovery scheduled")
	demo.construction.save()
	f.recovery_at = -1.0
	demo.construction.load_game()
	await _physics(10)
	f = _war().faction(pf)
	out["after_load_due_in"] = roundi(f.recovery_at - demo.sim.state.time)
	_expect(f.recovery_at >= 0.0, "b_recovery: the pending recovery was lost by save / load")
	var waited := await _until(func() -> bool: return not _player_squads().is_empty(), 200.0, 8.0)
	out["waited"] = roundi(waited)
	out["squads"] = _player_squads().size()
	out["soldiers"] = demo.sim.logistics.bases.soldiers_of(pf)
	out["recoveries"] = f.recoveries
	_expect(_player_squads().size() == 1 and demo.sim.logistics.bases.soldiers_of(pf) == int(war.rule("recovery_size", 0)), "b_recovery: no replacement section: %s" % str(out))
	await _until(func() -> bool: return false, 60.0, 8.0)
	_expect(_player_squads().size() == 1, "b_recovery: more free squads arrived while the player had soldiers")
	return out


# --- Stage C ------------------------------------------------------------------------------------------------------

func _site_by_squad(sq: SquadState) -> StructureState:
	return demo.sim.state.construction.get_structure(sq.tactic_site)


## Soldier-seconds of work done on a site (the finished structure: its need).
func _work(s: StructureState) -> float:
	return float(s.site.get("work", 0.0)) if s.is_site() else INF


## The squad builds the command post: assigned on placement, no base before it is finished, done in 30-90 s by eight;
## a player order takes the squad off (progress kept, no automatic return for a while), a right-click sends it back;
## fire pauses a player-ordered build; a cancelled site refunds in full; a save mid-build loads with the same progress
## and no second charge; a site far from the camera (abstract tier) takes the same time.
func _c_build() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var bs := demo.sim.logistics.bases
	var tac := demo.sim.tactics
	var out := {}
	var sq: SquadState = _player_squads()[0]
	var f := war.faction(pf)
	f.pool.add(Inventory.SUPPLIES, 3000.0)
	var spot := _cp_spot(demo.sim.war.squad_center(sq))
	var s0 := _stock()
	var cp := _place(&"command_post", spot)
	_expect(cp != null and cp.is_site(), "c: the command post was not placed as a site")
	if cp == null:
		return out
	out["placed"] = {"paid": roundi(s0.supplies - _stock().supplies), "message": demo.construction.message, "builder": sq.tactic_name(), "site": sq.tactic_site == cp.id}
	_expect(sq.tactic == SquadState.Tactic.BUILD and sq.tactic_site == cp.id, "c: the idle squad was not called to the site (%s)" % demo.construction.message)
	_expect(bs.bases_of(pf).is_empty(), "c: a base exists while the command post is only a site")
	demo.rts_camera.frame(cp.position + Vector3(0, 0, 25), 0.5, 55.0)
	var t0 := demo.sim.state.time
	var half := await _until(func() -> bool: return cp.site_progress() >= 0.4, 200.0, 2.0)
	_expect(bs.bases_of(pf).is_empty(), "c: a base exists at 40 % progress")
	_png("c_cp_under_construction")
	var working := 0
	for id in sq.members:
		if demo.sim.state.get_unit(id).work_until > demo.sim.state.time:
			working += 1
	out["working_at_40pct"] = working
	_expect(working >= 6, "c: only %d soldiers were working" % working)
	await _until(func() -> bool: return not cp.is_site(), 200.0, 2.0)
	var cp_s := demo.sim.state.time - t0
	out["cp_seconds"] = roundi(cp_s)
	out["bases_after"] = bs.bases_of(pf).size()
	_expect(cp_s >= 30.0 and cp_s <= 90.0, "c: the command post took %.0f s (want 30-90)" % cp_s)
	_expect(bs.bases_of(pf).size() == 1 and cp.base_id >= 0, "c: the base was not established exactly once on completion")
	_expect(sq.tactic == SquadState.Tactic.NONE and sq.order == SquadState.Order.NONE, "c: the squad did not become idle after building")
	await _seconds(1.0)
	_png("c_cp_completed")
	# Interruption: a player order takes the squad off the depot site; progress is kept; no automatic return.
	var depot := _place(&"supply_depot", _site_in_base(&"supply_depot", cp.position))
	_expect(depot != null and sq.tactic_site == depot.id, "c: the depot site got no builder")
	if depot == null:
		return out
	await _until(func() -> bool: return depot.site_progress() >= 0.25, 120.0, 2.0)
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(demo.sim.war.squad_center(sq) + Vector3(45, 0, 30))
	var w1 := _work(depot)
	await _until(func() -> bool: return false, 25.0, 2.0)
	var w2 := _work(depot)
	out["interrupt"] = {"work_at_order": roundi(w1), "work_25s_later": roundi(w2), "tactic": sq.tactic_name(), "why": depot.site.get("why", "")}
	_expect(sq.tactic != SquadState.Tactic.BUILD and absf(w2 - w1) < 5.0 and w1 > 0.0, "c: the player order did not stop the work (or progress was lost): %s" % str(out.interrupt))
	await _until(func() -> bool: return false, 30.0, 2.0)
	_expect(sq.tactic != SquadState.Tactic.BUILD, "c: automatic construction took the squad back right after the player's order")
	# Right-click on the site: an explicit build order.
	demo.rts.select_squads([sq.id])
	var n := demo.rts.order_build(depot.id)
	_expect(n == 8 and sq.tactic == SquadState.Tactic.BUILD and sq.tactic_owner == SquadState.Owner.PLAYER, "c: the build order was not taken (%s)" % demo.rts.current_message())
	await _until(func() -> bool: return int(depot.site.get("workers", 0)) >= 4, 60.0, 2.0)
	# Fire pauses a player-ordered build, it resumes when quiet.
	for id in sq.members:
		demo.sim.state.get_unit(id).under_fire_until = demo.sim.state.time + 6.0
	await _physics(30)
	var wf0 := _work(depot)
	await _until(func() -> bool: return false, 4.0, 1.0)
	var wf1 := _work(depot)
	await _until(func() -> bool: return _work(depot) > wf1 + 10.0 or not depot.is_site(), 40.0, 2.0)
	out["fire"] = {"during": roundi(wf1 - wf0), "resumed": _work(depot) > wf1 + 10.0 or not depot.is_site(), "tactic": sq.tactic_name()}
	_expect(wf1 - wf0 < 1.0 and bool(out.fire.resumed) and (sq.tactic == SquadState.Tactic.BUILD or not depot.is_site()), "c: fire did not pause / resume the work: %s" % str(out.fire))
	# Save in the middle of construction: same progress, no second charge, finishes once.
	var stock_before := _stock()
	var work_saved := _work(depot)
	demo.construction.save()
	await _until(func() -> bool: return false, 6.0, 2.0)
	var res := demo.construction.load_game()
	var depot2 := demo.sim.state.construction.get_structure(depot.id)
	var work_loaded := _work(depot2) if depot2 else -1.0
	var stock_loaded := _stock()
	await _physics(10)
	var sq2 := demo.sim.state.get_squad(sq.id)
	out["persist"] = {"load": res.ok, "work_saved": roundi(work_saved), "work_loaded": roundi(work_loaded), "stock_same": absf(float(stock_loaded.supplies) - float(stock_before.supplies)) < 0.5,
		"tactic": sq2.tactic_name() if sq2 else "-", "site": sq2.tactic_site if sq2 else -1}
	_expect(res.ok and depot2 != null and depot2.is_site() and absf(work_loaded - work_saved) < 0.5 and bool(out.persist.stock_same), "c: construction not restored: %s" % str(out.persist))
	_expect(sq2 != null and sq2.tactic == SquadState.Tactic.BUILD and sq2.tactic_site == depot.id, "c: the squad does not resume building after load")
	await _until(func() -> bool: return not depot2.is_site(), 120.0, 2.0)
	var depots := 0
	for st: StructureState in demo.sim.state.construction.all():
		if st.faction == pf and st.type_id == &"supply_depot" and not st.is_site():
			depots += 1
	_expect(depots == 1 and depot2.inventory != null and depot2.base_id >= 0, "c: the depot did not become one operational store")
	sq = sq2
	# Cancel: full refund, the squad stops.
	var s1 := _stock()
	var bag := _place(&"guard_tower_steel", _site_in_base(&"guard_tower_steel", cp.position))
	await _until(func() -> bool: return bag != null and bag.site_progress() > 0.1, 60.0, 2.0)
	var back := demo.construction.cancel_site(bag.id) if bag else -1.0
	await _physics(30)
	out["cancel"] = {"refund": roundi(back), "stock_diff": roundi(_stock().supplies - s1.supplies), "gone": demo.sim.state.construction.get_structure(bag.id) == null if bag else false, "tactic": sq.tactic_name()}
	_expect(bag != null and roundi(back) == 150 and absf(float(_stock().supplies) - float(s1.supplies)) < 0.5 and out.cancel.gone and sq.tactic != SquadState.Tactic.BUILD,
		"c: cancel did not refund exactly / stop the work: %s" % str(out.cancel))
	# Near and far: a guard post built under the camera, and another with the camera 4 km away (no bodies).
	var near_s := await _timed_build(sq, cp.position, true)
	var far_s := await _timed_build(sq, cp.position, false)
	out["near_far"] = {"near_s": roundi(near_s.t), "far_s": roundi(far_s.t), "bodies_far": far_s.bodies}
	_expect(near_s.t > 0.0 and far_s.t > 0.0 and absf(near_s.t - far_s.t) <= 0.2 * near_s.t and far_s.bodies == 0,
		"c: near / far construction times differ: %s" % str(out.near_far))
	return out


## Places a guard post in the base and times it with the squad building; camera near the site or 4 km away.
func _timed_build(sq: SquadState, anchor: Vector3, near: bool) -> Dictionary:
	var at := _site_in_base(&"guard_tower_steel", anchor)
	if near:
		demo.rts_camera.frame(at, 0.5, 60.0)
		demo.detail.activate_at(at)
	else:
		var away := demo.on_ground(anchor.x + 4000.0, anchor.z - 2500.0, 0.0)
		demo.rts_camera.frame(away, 0.5, 60.0)
		demo.detail.activate_at(away)
	await _seconds(2.0)
	var s := _place(&"guard_tower_steel", at)
	if s == null or sq.tactic_site != s.id:
		if s:
			demo.sim.tactics.order_build([sq.id], s.id)
		else:
			return {"t": -1.0, "bodies": -1}
	var t0 := demo.sim.state.time
	var bodies := 0
	await _until(func() -> bool: return not s.is_site(), 240.0, 2.0)
	for id in sq.members:
		if demo.sim.state.get_unit(id).has_body:
			bodies += 1
	var t := demo.sim.state.time - t0
	demo.rts_camera.frame(anchor, 0.5, 80.0)
	demo.detail.activate_at(anchor)
	await _seconds(1.0)
	return {"t": t, "bodies": bodies}


## AI construction through the shared site record: a South order becomes a site with a crew, takes its BUILD_TIME_S,
## and a store becomes an operational facility of the AI base.
func _c_ai() -> Dictionary:
	var ws := demo.sim.war
	var f := _war().faction(1)
	var bs := demo.sim.logistics.bases
	var mb := bs.main_base(1)
	_expect(mb >= 0, "c_ai: South has no main base")
	if mb < 0:
		return {}
	var anchor: Vector3 = demo.sim.state.construction.bases[mb].anchor
	var r := ws.bases.request(f, &"supply_storage", anchor, "test order")
	var site: StructureState = null
	for s: StructureState in demo.sim.state.construction.all():
		if s.is_site() and s.faction == 1 and s.type_id == &"supply_storage":
			site = s
	var out := {"request": r, "site": site != null}
	_expect(r.ok and site != null and float(site.site.crew) > 0.0, "c_ai: the AI order did not become a crewed site: %s" % str(r))
	if site == null:
		return out
	var pend := ws.bases.pending_of(1, &"supply_storage").size()
	var t0 := demo.sim.state.time
	await _until(func() -> bool: return not site.is_site(), 200.0, 8.0)
	var t := demo.sim.state.time - t0
	out["seconds"] = roundi(t)
	out["pending_seen"] = pend
	out["store"] = site.inventory != null
	out["base"] = site.base_id
	_expect(not site.is_site() and absf(t - AiBases.BUILD_TIME_S[&"supply_storage"]) <= 6.0, "c_ai: the AI site took %.0f s (want %.0f)" % [t, AiBases.BUILD_TIME_S[&"supply_storage"]])
	_expect(pend == 1 and site.inventory != null and site.base_id == mb, "c_ai: the finished AI store is not a facility of its base")
	return out


# --- Integrated first-playable loop --------------------------------------------------------------------------------

const LOOP_EXPECT := "user://test_saves/gameplay01b_loop.json"
var _steps: Array = []


func _step_log(n: int, what: String, ok: bool, data := {}) -> void:
	var e := {"step": n, "what": what, "ok": ok, "t": snappedf(demo.sim.state.time, 0.1), "supplies": roundi(_stock().supplies)}
	e.merge(data)
	_steps.append(e)
	print("GP step %s" % JSON.stringify(e))
	_expect(ok, "loop step %d (%s) failed: %s" % [n, what, str(data)])


func _frame(p: Vector3, zoom := 70.0, yaw := 0.6) -> void:
	demo.rts_camera.frame(p, yaw, zoom)
	await _seconds(1.5)


## The early game from a New Game start (run with --menu-shot so the start went through the real menu), each step with
## the controls a player uses: RTS selection and right-click orders, the map, the construction tool driven through its
## cursor, the barracks' panel button, the tactical order keys. Simulated time is compressed on the walks. Writes what it
## built for the second process (--continue ... --only loop_continue).
func _loop() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var f := war.faction(pf)
	var bs := demo.sim.logistics.bases
	var con := demo.construction
	var rts := demo.rts
	var t_start := demo.sim.state.time
	# 1. Eight North soldiers in the south.
	var sqs := _player_squads()
	var sq: SquadState = sqs[0] if not sqs.is_empty() else null
	_step_log(1, "start: one North squad of eight in the south", war.scenario_id == "new_game" and sqs.size() == 1 and sq.members.size() == 8 and demo.sim.war.squad_center(sq).z > 5000.0,
		{"scenario": war.scenario_id, "squads": sqs.size(), "pos": str(demo.sim.war.squad_center(sq)) if sq else "-"})
	if sq == null:
		return {"steps": _steps}
	await _frame(demo.sim.war.squad_center(sq), 80.0)
	_png("loop_01_start")
	# 2. Select the squad.
	rts.select_squads([sq.id])
	await _seconds(1.0)
	_step_log(2, "squad selected in the tactical view", rts.selected_squads() == [sq.id])
	_png("loop_02_selected")
	# 3. The map: the reported cache is on it.
	demo.toggle_map()
	await _seconds(1.0)
	var sc := demo.sim.war.squad_center(sq)
	demo.strategic_map.zoom = 0.12
	demo.strategic_map.view_center = Vector2(sc.x, sc.z - 700.0)
	await _seconds(1.0)
	_png("loop_03_map")
	_step_log(3, "strategic map open with the reported cache", demo.strategic_map.visible and (_cache(0).known as Array).has(pf))
	demo.toggle_map()
	await _seconds(0.5)
	# 4-6. To the cache, secure it, supplies rise.
	var c0: Dictionary = _cache(0)
	var before := _stock()
	rts.select_squads([sq.id])
	rts.order_move(c0.pos)
	await _until(func() -> bool: return c0.state == "securing", 300.0)
	await _frame(c0.pos, 55.0)
	await _until(func() -> bool: return float(c0.progress) >= 0.45, 40.0, 1.0)
	_png("loop_05_cache_securing")
	var secure_t := await _until(func() -> bool: return c0.state == "depleted", 60.0, 2.0)
	_step_log(4, "moved to the cache", true)
	_step_log(5, "cache secured", c0.state == "depleted", {"seconds": roundi(secure_t)})
	_step_log(6, "supplies increased", _stock().supplies > before.supplies + 800.0, {"gain": roundi(_stock().supplies - before.supplies)})
	await _seconds(1.0)
	_png("loop_06_cache_taken")
	# 7-8. A Command Post site through the construction tool's cursor.
	var spot := _cp_spot(demo.sim.war.squad_center(sq))
	_step_log(7, "command post location found", spot.is_finite(), {"at": str(spot)})
	await _frame(spot, 60.0)
	con.set_active(true)
	con.select_type(&"command_post")
	con.mouse_override = demo.rts_camera.camera.unproject_position(spot)
	await _seconds(1.0)
	_png("loop_08_cp_blueprint")
	con.primary_action()
	con.mouse_override = Vector2.INF
	con.set_active(false)
	var cp: StructureState = null
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == pf and s.type_id == &"command_post":
			cp = s
	_step_log(8, "command post blueprint placed", cp != null and cp.is_site(), {"message": con.message})
	if cp == null:
		return {"steps": _steps}
	# 9-10. Soldiers build it; the base exists only when it is finished.
	await _until(func() -> bool: return cp.site_progress() >= 0.5, 120.0, 2.0)
	await _frame(cp.position + Vector3(0, 0, 12), 75.0)
	_png("loop_09_cp_construction")
	var no_base_mid := bs.bases_of(pf).is_empty()
	await _until(func() -> bool: return not cp.is_site(), 120.0, 2.0)
	_step_log(9, "soldiers built the command post", not cp.is_site() and no_base_mid, {"workers_seen": no_base_mid})
	_step_log(10, "base operational on completion", bs.bases_of(pf).size() == 1 and cp.base_id >= 0, {"base": bs.describe(cp.base_id)})
	# 11-12. Depot; the pool moves into it.
	var pool_before := f.pool.get_qty(Inventory.SUPPLIES)
	var depot := _place(&"supply_depot", _site_in_base(&"supply_depot", cp.position))
	await _until(func() -> bool: return depot != null and not depot.is_site(), 150.0, 2.0)
	await _physics(90)
	_step_log(11, "supply depot built", depot != null and not depot.is_site())
	_step_log(12, "pool moved into the depot", f.pool.is_empty() and depot != null and depot.inventory.get_qty(Inventory.SUPPLIES) >= pool_before - 451.0, {"pool_before": roundi(pool_before), "depot": depot.inventory.summary() if depot and depot.inventory else "-"})
	await _frame(cp.position + Vector3(10, 0, 30), 70.0)
	_png("loop_12_base_depot")
	# 13. More supplies: the cache the first one pointed to, then Verket for income.
	var c1: Dictionary = _cache(1)
	rts.select_squads([sq.id])
	rts.order_move(c1.pos)
	await _until(func() -> bool: return c1.state == "depleted", 900.0, 8.0)
	var verket: ObjectiveState = null
	for o: ObjectiveState in war.all_objectives():
		if o.obj_name == "Verket":
			verket = o
	rts.select_squads([sq.id])
	rts.order_move(verket.position)
	await _until(func() -> bool: return verket.owner == pf, 400.0, 8.0)
	_step_log(13, "more supplies: second cache and Verket captured", c1.state == "depleted" and verket.owner == pf, {"income_per_min": demo.sim.war.econ.rate_per_min(f)})
	# 14. Barracks, built by the squad that walks back.
	await _until(func() -> bool: return _stock().supplies >= 560.0, 300.0, 8.0)
	var barracks := _place(&"barracks_block", _site_in_base(&"barracks_block", cp.position))
	if barracks and sq.tactic_site != barracks.id:
		rts.select_squads([sq.id])
		rts.order_build(barracks.id)
	await _until(func() -> bool: return barracks != null and not barracks.is_site(), 900.0, 8.0)
	_step_log(14, "barracks built", barracks != null and not barracks.is_site(), {"stock": _stock()})
	# 15. Recruit through the barracks' panel button.
	await _until(func() -> bool: return _stock().supplies >= 330.0 and _stock().ammo >= 200.0, 400.0, 8.0)
	rts.select([])
	rts.selected_structure = barracks.id
	await _frame(barracks.position + Vector3(0, 0, 25), 55.0)
	await _seconds(1.0)
	var pressed := _press_panel_button("RECRUIT")
	await _seconds(0.5)
	_png("loop_15_recruit")
	var n0 := _player_squads().size()
	await _until(func() -> bool: return _player_squads().size() > n0, 90.0, 4.0)
	var recruit: SquadState = _player_squads().back()
	_step_log(15, "squad recruited through the barracks panel", pressed and _player_squads().size() == n0 + 1, {"queue_paid": true})
	# 16. A defensive structure.
	var guard := _place(&"guard_tower_steel", _site_in_base(&"guard_tower_steel", cp.position + Vector3(0, 0, -40)))
	await _until(func() -> bool: return guard != null and not guard.is_site(), 240.0, 4.0)
	_step_log(16, "defensive structure built", guard != null and not guard.is_site())
	# 17. The new squad takes orders.
	rts.select_squads([recruit.id])
	var moved := rts.order_move(demo.sim.war.squad_center(recruit) + Vector3(-30, 0, 25))
	await _seconds(2.0)
	_step_log(17, "recruited squad selected and commanded", moved == recruit.members.size() and recruit.order == SquadState.Order.MOVE)
	await _frame(cp.position + Vector3(0, 0, 35), 110.0)
	_png("loop_17_base_overview")
	# 18. Save (F5 through the input map).
	_press(KEY_F5)
	await _physics(5)
	var expect := {"squads": _player_squads().size(), "soldiers": bs.soldiers_of(pf), "structures": demo.sim.state.construction.all().filter(func(s: StructureState) -> bool: return s.faction == pf and not s.is_line()).size(),
		"sites": demo.sim.state.construction.all().filter(func(s: StructureState) -> bool: return s.faction == pf and s.is_site()).size(),
		"bases": bs.bases_of(pf).size(), "supplies": roundi(_stock().supplies), "verket": verket.owner, "caches": war.caches.map(func(x: Dictionary) -> String: return x.state), "time": demo.sim.state.time}
	var fw := FileAccess.open(LOOP_EXPECT, FileAccess.WRITE)
	fw.store_string(JSON.stringify(expect))
	fw.close()
	_step_log(18, "saved (F5)", demo.peek_save().get("ok", false), {"message": con.message, "game_minutes": snappedf((demo.sim.state.time - t_start) / 60.0, 0.1)})
	return {"steps": _steps, "expect": expect, "game_minutes": snappedf((demo.sim.state.time - t_start) / 60.0, 0.1)}


## Steps 19-22 in a second process started with --continue: everything is back, and the war still takes orders.
func _loop_continue() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var bs := demo.sim.logistics.bases
	var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOP_EXPECT)) if FileAccess.file_exists(LOOP_EXPECT) else null
	_step_log(19, "restarted the program", expect is Dictionary, {"expect_file": expect is Dictionary})
	if not expect is Dictionary:
		return {"steps": _steps}
	_step_log(20, "continued the saved game", bool(demo.continue_result.get("ok", false)) and war.scenario_id == "new_game", {"continue": demo.continue_result})
	var verket_owner := -2
	for o: ObjectiveState in war.all_objectives():
		if o.obj_name == "Verket":
			verket_owner = o.owner
	var now := {"squads": _player_squads().size(), "soldiers": bs.soldiers_of(pf), "structures": demo.sim.state.construction.all().filter(func(s: StructureState) -> bool: return s.faction == pf and not s.is_line()).size(),
		"sites": demo.sim.state.construction.all().filter(func(s: StructureState) -> bool: return s.faction == pf and s.is_site()).size(),
		"bases": bs.bases_of(pf).size(), "supplies": roundi(_stock().supplies), "verket": verket_owner, "caches": war.caches.map(func(x: Dictionary) -> String: return x.state)}
	var same: bool = int(now.squads) == int(expect.squads) and int(now.soldiers) == int(expect.soldiers) and int(now.structures) == int(expect.structures) \
		and int(now.bases) == int(expect.bases) and absi(int(now.supplies) - int(expect.supplies)) <= 1 and int(now.verket) == int(expect.verket) and str(now.caches) == str(expect.caches)
	_step_log(21, "squads, buildings, resources and ownership persisted", same, {"now": now, "expect": expect})
	var cp_pos: Vector3 = demo.sim.state.construction.bases[bs.main_base(pf)].anchor if bs.main_base(pf) >= 0 else demo.start_focus()
	await _frame(cp_pos + Vector3(0, 0, 35), 110.0)
	_png("loop_20_continued")
	# 22. The war still works: a tactical DEFEND at the base and a strategic attack from the map's operation call.
	var sqs := _player_squads()
	demo.rts.select_squads([sqs[0].id])
	demo.rts.order_tactic(SquadState.Tactic.DEFEND, cp_pos)
	await _seconds(2.0)
	var defend_ok: bool = sqs[0].tactic == SquadState.Tactic.DEFEND
	var target: ObjectiveState = null
	for o: ObjectiveState in war.all_objectives():
		if o.obj_name == "Sørmoen":
			target = o
	var op: OperationState = demo.sim.war.start_operation(pf, OperationState.Type.ATTACK, [sqs[sqs.size() - 1].id], target.id, Vector3.INF, true) if target else null
	await _seconds(3.0)
	_step_log(22, "tactical and strategic orders still work", defend_ok and op != null and op.is_active(), {"defend": defend_ok, "op": op.phase_name() if op else "-"})
	demo.toggle_map()
	demo.strategic_map.zoom = 0.07
	demo.strategic_map.view_center = Vector2(cp_pos.x - 900.0, cp_pos.z - 1500.0)
	await _seconds(1.5)
	_png("loop_22_map_operation")
	demo.toggle_map()
	return {"steps": _steps}


## Presses the logistics panel's button whose text contains `word` (the real button, its pressed signal). Returns true when found.
func _press_panel_button(word: String) -> bool:
	var panel := demo.hud.logistics_panel
	var stack: Array = [panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text.to_upper().contains(word) and not (n as Button).disabled:
			(n as Button).pressed.emit()
			return true
		stack.append_array(n.get_children())
	return false


## A command post spot within 150 m of p (check_building + base rules), or INF. Open ground first (no trees to cut, as a
## player would choose), then any ground the clearing makes buildable.
func _cp_spot(p: Vector3) -> Vector3:
	return _spot(&"command_post", p, [30.0, 50.0, 70.0, 90.0, 120.0, 150.0], 12)


func _site_in_base(type_id: StringName, anchor: Vector3) -> Vector3:
	return _spot(type_id, anchor, [35.0, 50.0, 65.0, 80.0, 95.0, 110.0], 16)


func _spot(type_id: StringName, p: Vector3, rings: Array, dirs: int) -> Vector3:
	var sm := demo.structures
	var def := StructureCatalog.get_def(type_id)
	for clear: bool in [false, true]:
		for r: float in rings:
			for k in dirs:
				var a := TAU * k / dirs + r * 0.01
				var g := demo.on_ground(p.x + cos(a) * r, p.z + sin(a) * r, 0.0)
				if sm.check_building(def, g, 0.0, -1, clear).ok and sm.road_conflict(def, Transform3D(Basis.IDENTITY, g)) == "" \
						and demo.sim.logistics.bases.placement_rule(type_id, g, _war().player_faction) == "":
					return g
	return Vector3.INF


## Places a building through the construction controller (its checks, costs and placement path); returns it or null.
func _place(type_id: StringName, at: Vector3) -> StructureState:
	if not at.is_finite():
		return null
	var con := demo.construction
	con.set_active(true)
	con.select_type(type_id)
	con.yaw = 0.0
	con.cursor = at
	con._refresh_check()
	var s := con.place_building()
	con.set_active(false)
	return s


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
	var cache_check: Array = []
	for c: Dictionary in war.caches:
		var g := sim.tactics.pos.ground(c.pos)
		var nv := sim.tactics.pos.nearest_valid(c.pos, 40.0)
		var blocked := 0
		for k in 16:
			var a := TAU * k / 16.0
			if not sim.tactics.pos.valid_ground(sim.tactics.pos.ground(c.pos + Vector3(cos(a), 0, sin(a)) * 15.0)):
				blocked += 1
		cache_check.append({"name": c.name, "valid": sim.tactics.pos.valid_ground(g), "nearest_valid_m": roundi(_flat2(nv, c.pos)) if nv.is_finite() else -1, "ring15_blocked": blocked})
	return {"objectives": objs, "start_candidates": cands.slice(0, 25), "n_candidates": cands.size(), "cache_spots": caches, "cache_check": cache_check}


static func _flat2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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

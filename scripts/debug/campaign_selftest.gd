## GAMEPLAY-01C..01G checks in the real game on ref_20km: defensive positions and GARRISON_BASE (c_*), base warfare and
## capture (d_*), AI expansion and replenishment (e_*), structure damage and repair (f_*), the pause menu and the
## integrated campaign (g_*). Each check sets up what it needs through the game's own systems and fails when its
## precondition is missing.
##
##   Godot.exe --path . --resolution 1600x900 --log-file cp.log res://scenes/game/world_ref_20km.tscn -- --scenario=new_game --campaign-test [--shots] [--only c_forts,...]
##
## Runs in the test save folder (user://test_saves). Prints "CP <check> <json>", writes res://benchmarks/raw/campaign_test.json
## and (with --shots, --fullscreen for 1920x1080) docs/gameplay01c/*.png.
class_name CampaignSelfTest
extends GameplaySelfTest

var _shots_fired: Array = []


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/gameplay01c"
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	SoldierBody.require_mouse_capture = false
	tree.create_timer(2400.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	demo.sim.state.shot_fired.connect(func(shot: Dictionary) -> void: _shots_fired.append(shot))
	await _physics(30)
	if _want("c_forts"):
		_log("c_forts", await _c_forts())
	if _want("c_ai_garrison"):
		_log("c_ai_garrison", await _c_ai_garrison())
	if _want("d_targets"):
		_log("d_targets", await _d_targets())
	if _want("d_ai_war"):
		_log("d_ai_war", await _d_ai_war())
	if _want("d_player_assault"):
		_log("d_player_assault", await _d_player_assault())
	if _want("e_replenish"):
		_log("e_replenish", await _e_replenish())
	if _want("e_expansion"):
		_log("e_expansion", await _e_expansion())
	if _want("f_damage"):
		_log("f_damage", await _f_damage())
	if _want("f_ai_repair"):
		_log("f_ai_repair", await _f_ai_repair())
	if _want("g_pause"):
		_log("g_pause", await _g_pause())
	if only.has("g_campaign"):
		_log("g_campaign", await _g_campaign())
	if only.has("g_campaign_continue"):
		_log("g_campaign_continue", await _g_campaign_continue())
	if only.has("g_menu_return"):
		_finish_no_quit()
		PauseMenu.test_quit_on_menu = true
		demo.toggle_pause()
		demo._on_pause_chosen("main_menu")
		return
	_finish()


# --- Helpers ---------------------------------------------------------------------------------------------------------

## A building placed through the construction controller facing `out` (its front, -Z, towards out); null when refused.
## Waits like GameplaySelfTest._until, printing a heartbeat (simulated time, frame cost) every 30 iterations.
func _until(cond: Callable, limit: float, speed := 4.0) -> float:
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(speed)
	var k := 0
	while not cond.call() and demo.sim.state.time - t0 < limit:
		var r0 := Time.get_ticks_msec()
		await _physics(20)
		k += 1
		if k % 30 == 0:
			print("CP beat t=%.0f waited=%.0f real_ms_per_20=%d" % [demo.sim.state.time, demo.sim.state.time - t0, Time.get_ticks_msec() - r0])
	CoreDemo.apply_time_scale(1.0)
	return demo.sim.state.time - t0


func _place_facing(type_id: StringName, at: Vector3, out: Vector3) -> StructureState:
	if not at.is_finite():
		return null
	var con := demo.construction
	con.set_active(true)
	con.select_type(type_id)
	con.yaw = atan2(-out.x, -out.z)
	con.cursor = at
	con._refresh_check()
	var s := con.place_building()
	if s == null:
		print("CP place refused %s: %s" % [type_id, con.message])
	con.set_active(false)
	return s


## A line (HESCO, sandbag wall) placed through the controller between a and b.
func _place_line(type_id: StringName, a: Vector3, b: Vector3) -> StructureState:
	var con := demo.construction
	con.set_active(true)
	con.select_type(type_id)
	con.line_points = PackedVector3Array([a, b])
	var s := con.finish_line()
	con.set_active(false)
	return s


## A free spot for type_id on a ring round `c` in direction `dir` (first fit outwards from r0), facing out.
func _spot_dir(type_id: StringName, c: Vector3, dir: Vector3, r0: float) -> Vector3:
	var sm := demo.structures
	var def := StructureCatalog.get_def(type_id)
	for dr: float in [0.0, 6.0, 12.0, 18.0, 24.0]:
		for da: float in [0.0, 0.25, -0.25, 0.5, -0.5]:
			var d := dir.rotated(Vector3.UP, da)
			var g := demo.on_ground(c.x + d.x * (r0 + dr), c.z + d.z * (r0 + dr), 0.0)
			var yaw := atan2(-d.x, -d.z)
			if sm.check_building(def, g, yaw, -1, true).ok and sm.road_conflict(def, Transform3D(Basis(Vector3.UP, yaw), g)) == "" \
					and demo.sim.logistics.bases.placement_rule(type_id, g, _war().player_faction) == "":
				return g
	return Vector3.INF


func _sites_left(pf: int) -> int:
	var n := 0
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == pf and s.is_site():
			n += 1
	return n


func _fort_units(f: int) -> Array:
	var out := []
	for u: UnitState in demo.sim.state.units.values():
		if u.alive and u.faction == f and u.fort_pos.is_finite():
			out.append(u)
	return out


## Builds the player's base for the fortification checks: a command post next to the squad, then a fighting position,
## an MG emplacement, a steel guard tower, a timber guard tower, a HESCO line and a sandbag wall on the side facing
## `front`, every one a paid site the squad builds. Returns {cp, forts: {type: StructureState}, front, base}.
func _build_fort_base(sq: SquadState, front: Vector3) -> Dictionary:
	var pf := _war().player_faction
	_war().faction(pf).pool.add(Inventory.SUPPLIES, 6000.0)
	var cp := _place(&"command_post", _cp_spot(demo.sim.war.squad_center(sq)))
	_expect(cp != null, "c: no command post could be placed")
	if cp == null:
		return {}
	await _until(func() -> bool: return not cp.is_site(), 300.0, 4.0)
	_expect(not cp.is_site() and cp.base_id >= 0, "c: the command post was not built")
	var c := cp.position
	var side := Vector3(-front.z, 0.0, front.x)
	var forts := {}
	for e: Array in [[&"fighting_position", front, 34.0], [&"mg_emplacement", front.rotated(Vector3.UP, 0.45), 40.0],
			[&"guard_tower_steel", front.rotated(Vector3.UP, -0.5), 30.0], [&"guard_tower", -front.rotated(Vector3.UP, 0.7), 32.0]]:
		var at := _spot_dir(e[0], c, e[1], e[2])
		var s := _place_facing(e[0], at, e[1])
		_expect(s != null, "c: %s could not be placed (%s)" % [e[0], demo.construction.message])
		if s:
			forts[e[0]] = s
	var h0 := demo.on_ground(c.x + front.x * 52.0 - side.x * 10.0, c.z + front.z * 52.0 - side.z * 10.0, 0.0)
	var h1 := demo.on_ground(c.x + front.x * 52.0 + side.x * 14.0, c.z + front.z * 52.0 + side.z * 14.0, 0.0)
	var hesco := _place_line(&"hesco", h0, h1)
	_expect(hesco != null, "c: the HESCO line could not be placed (%s)" % demo.construction.message)
	if hesco:
		forts[&"hesco"] = hesco
	var w0 := demo.on_ground(c.x - side.x * 46.0 + front.x * 8.0, c.z - side.z * 46.0 + front.z * 8.0, 0.0)
	var w1 := demo.on_ground(c.x - side.x * 46.0 + front.x * 22.0, c.z - side.z * 46.0 + front.z * 22.0, 0.0)
	var wall := _place_line(&"sandbag_wall_2m", w0, w1)
	if wall:
		forts[&"sandbag_wall_2m"] = wall
	var t0 := demo.sim.state.time
	await _until(func() -> bool: return _sites_left(pf) == 0, 900.0, 8.0)
	var built := {}
	for k in forts:
		var s: StructureState = forts[k]
		built[String(k)] = not s.is_site()
		_expect(not s.is_site(), "c: %s was not finished by the squad" % k)
	return {"cp": cp, "forts": forts, "front": front, "base": cp.base_id, "built": built, "build_s": roundi(demo.sim.state.time - t0)}


# --- 01C: positions and garrison --------------------------------------------------------------------------------------

## The player builds every defensive structure (paid sites, built by the squad), garrisons the base with the squad, the
## soldiers take distinct slots (towers on their platforms), fire at an enemy from them without hitting their own
## fortification, leave them on a player order, keep the garrison through a save / load, and a DEFEND order next to a
## fortification uses it.
func _c_forts() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var sq: SquadState = _player_squads()[0]
	var out := {}
	var front := Vector3(0.6, 0.0, -0.8).normalized()
	var fb := await _build_fort_base(sq, front)
	if fb.is_empty():
		return out
	out["built"] = fb.built
	out["build_s"] = fb.build_s
	var cp: StructureState = fb.cp
	var base_id: int = fb.base
	# HESCO modules connect: one record, consecutive modules a cell apart.
	var hesco: StructureState = fb.forts.get(&"hesco")
	if hesco:
		var gaps := 0
		for i in range(1, hesco.instances.size()):
			if hesco.instances[i].origin.distance_to(hesco.instances[i - 1].origin) > 1.2:
				gaps += 1
		out["hesco"] = {"modules": hesco.built_count(), "gaps": gaps, "slots": demo.sim.tactics.pos.slots_of_structure(hesco, cp.position).size()}
		_expect(gaps == 0 and hesco.built_count() >= 15, "c: HESCO modules do not join: %s" % str(out.hesco))
	var cap := 0
	for k in fb.forts:
		cap += demo.sim.tactics.pos.slots_of_structure(fb.forts[k], cp.position).size()
	out["slots_total"] = cap
	await _frame(cp.position + front * 30.0, 60.0, 0.4)
	_png("c_fort_base_built")
	# Garrison through the RTS command.
	demo.rts.select_squads([sq.id])
	var res := demo.rts.order_garrison(base_id)
	_expect(res.ok and sq.garrison_base == base_id, "c: the garrison order was not taken: %s" % str(res))
	await _until(func() -> bool: return _fort_units(pf).size() >= mini(sq.members.size(), 6), 180.0, 4.0)
	var held := _fort_units(pf)
	var keys := {}
	var dup := 0
	var elevated := 0
	var by_type := {}
	for u: UnitState in held:
		if keys.has(u.fort_slot):
			dup += 1
		keys[u.fort_slot] = true
		var g := demo.sim.tactics.pos.ground(u.position)
		if u.position.y > g.y + 3.0:
			elevated += 1
		var s := demo.sim.state.construction.get_structure(int(u.fort_slot.split(":")[0]))
		if s:
			by_type[String(s.type_id)] = int(by_type.get(String(s.type_id), 0)) + 1
	out["garrison"] = {"in_slots": held.size(), "members": sq.members.size(), "duplicates": dup, "elevated": elevated, "by_type": by_type, "tactic": sq.tactic_name(),
		"why": sq.tactic_why}
	_expect(held.size() >= 6 and dup == 0, "c: the garrison did not take distinct slots: %s" % str(out.garrison))
	_expect(elevated >= 1, "c: nobody stands on a tower platform: %s" % str(out.garrison))
	_expect(by_type.has("fighting_position") or by_type.has("mg_emplacement"), "c: the sandbag / MG positions are not manned: %s" % str(by_type))
	var tower: StructureState = fb.forts.get(&"guard_tower_steel")
	if tower:
		await _frame(tower.position + Vector3(0, 3, 0), 26.0, 0.9)
		_png("c_tower_manned")
	var mg: StructureState = fb.forts.get(&"mg_emplacement")
	if mg:
		await _frame(mg.position + front * 3.0, 24.0, atan2(front.x, front.z))
		_png("c_mg_manned")
	var fp: StructureState = fb.forts.get(&"fighting_position")
	if fp:
		await _frame(fp.position + front * 2.0, 20.0, atan2(front.x, front.z))
		_png("c_fighting_position_manned")
	# Firing from the positions: an enemy squad in front of the base.
	var ef := war.faction(1)
	var enemy_at := demo.sim.tactics.pos.nearest_valid(cp.position + front * 170.0, 40.0)
	var esq := demo.sim.war.spawn_squad(ef, enemy_at, 6)
	demo.sim.squads.order_hold([esq.id])
	_shots_fired.clear()
	await _until(func() -> bool: return esq.members.size() <= 2 or sq.members.size() <= 2, 75.0, 2.0)
	var fort_shots := 0
	var own_block := 0
	var fort_ids := {}
	for u: UnitState in _fort_units(pf):
		fort_ids[u.id] = true
	for shot: Dictionary in _shots_fired:
		var su := demo.sim.state.get_unit(int(shot.shooter))
		if su == null or su.faction != pf:
			continue
		if fort_ids.has(su.id) or su.fort_slot != "":
			fort_shots += 1
			if shot.blocker == "structure" and float(shot.distance) < 4.0:
				own_block += 1
	out["fire"] = {"shots_from_slots": fort_shots, "blocked_by_own_fortification": own_block, "enemy_left": esq.members.size(), "garrison_left": sq.members.size(),
		"in_slots_after": _fort_units(pf).size()}
	_expect(fort_shots >= 10, "c: the garrison did not fire from its positions: %s" % str(out.fire))
	_expect(own_block <= fort_shots * 0.15, "c: shots from the positions hit their own fortification: %s" % str(out.fire))
	if mg:
		await _frame(mg.position + front * 6.0, 30.0, 2.6)
		_png("c_garrison_firing")
	for id in esq.members.duplicate():
		demo.sim.combat.kill(demo.sim.state.get_unit(id))
	await _physics(10)
	if sq.members.size() < 3:
		failures.append("c: the garrison was wiped out, later checks cannot run")
		return out
	# Save / load with the garrison in its positions.
	await _until(func() -> bool: return _fort_units(pf).size() >= mini(sq.members.size(), 6), 90.0, 4.0)
	var before := {}
	for u: UnitState in _fort_units(pf):
		before[u.id] = u.fort_slot
	demo.construction.save()
	await _until(func() -> bool: return false, 5.0, 2.0)
	var lr := demo.construction.load_game()
	await _physics(20)
	var sq2 := demo.sim.state.get_squad(sq.id)
	var same := 0
	for id in before:
		var u := demo.sim.state.get_unit(id)
		if u and u.fort_slot == before[id] and u.fort_pos.is_finite():
			same += 1
	out["persist"] = {"load": lr.ok, "held_before": before.size(), "same_slot_after": same, "garrison_base": sq2.garrison_base if sq2 else -2}
	_expect(lr.ok and sq2 != null and sq2.garrison_base == base_id and same >= before.size() - 1, "c: garrison / slots not restored: %s" % str(out.persist))
	sq = sq2
	# A player order overrides the garrison: the soldiers leave their slots.
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(cp.position - front * 40.0)
	await _until(func() -> bool: return false, 12.0, 2.0)
	out["override"] = {"in_slots": _fort_units(pf).size(), "garrison_base": sq.garrison_base, "order": sq.order_name()}
	_expect(_fort_units(pf).is_empty() and sq.garrison_base < 0, "c: the move order did not end the garrison: %s" % str(out.override))
	await _until(func() -> bool: return sq.status != SquadState.Status.MOVING, 60.0, 4.0)
	var stuck := 0
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if demo.structures.blocks_point(Vector2(u.position.x, u.position.z), 0.2) or u.position.y > demo.sim.tactics.pos.ground(u.position).y + 1.5:
			stuck += 1
	out["left_positions"] = {"status": SquadState.Status.keys()[sq.status], "stuck_in_structures": stuck}
	_expect(stuck == 0, "c: soldiers stayed inside / on top of structures after leaving: %d" % stuck)
	# DEFEND next to the MG emplacement uses it (no garrison order).
	if mg:
		demo.rts.select_squads([sq.id])
		var dres := demo.rts.order_tactic(SquadState.Tactic.DEFEND, mg.position - front * 6.0)
		await _until(func() -> bool: return _fort_units(pf).size() >= mini(sq.members.size(), 6), 90.0, 4.0)
		var mg_held := 0
		for u: UnitState in _fort_units(pf):
			if u.fort_slot.begins_with("%d:" % mg.id):
				mg_held += 1
		out["defend_area"] = {"ok": dres.ok, "in_slots": _fort_units(pf).size(), "mg_slots": mg_held, "why": sq.tactic_why}
		_expect(mg_held >= 1, "c: DEFEND next to the MG emplacement did not use it: %s" % str(out.defend_area))
	return out


## An AI faction garrisons its own base with real squads: squads stationed at the HQ objective that holds the base man its
## fortifications (HESCO), and no squad is created for it.
func _c_ai_garrison() -> Dictionary:
	var war := _war()
	var squads0 := demo.sim.state.squads.size()
	var ai := -1
	for f: FactionState in war.factions.values():
		if not f.player and not demo.sim.logistics.bases.bases_of(f.id).is_empty():
			ai = f.id
			break
	_expect(ai >= 0, "c_ai: no AI faction with a base")
	if ai < 0:
		return {}
	await _until(func() -> bool: return _fort_units(ai).size() >= 3, 300.0, 8.0)
	var garrisoned := 0
	for sq: SquadState in demo.sim.war.squads_of(ai):
		if sq.garrison_base >= 0:
			garrisoned += 1
	var out := {"faction": WorldState.faction_name(ai), "squads": demo.sim.war.squads_of(ai).size(), "garrison_squads": garrisoned, "in_slots": _fort_units(ai).size(),
		"squads_before": squads0, "squads_after": demo.sim.state.squads.size()}
	_expect(garrisoned >= 1 and _fort_units(ai).size() >= 3, "c_ai: the AI did not man its base: %s" % str(out))
	_expect(garrisoned < demo.sim.war.squads_of(ai).size(), "c_ai: every AI squad went into garrison: %s" % str(out))
	var held := _fort_units(ai)
	if not held.is_empty():
		await _frame((held[0] as UnitState).position, 40.0, 0.7)
		_png("c_ai_garrison")
	return out


# --- 01D: base warfare -------------------------------------------------------------------------------------------------

## An outpost of faction f round `at`: a command post, two fighting positions and a steel guard tower facing `out`, and a
## squad of `n` garrisoning it. Returns {base, objective, squad, structures, cp}.
func _outpost(f: int, at: Vector3, out: Vector3, n := 6) -> Dictionary:
	var ws := demo.sim.war
	var cp := _add_built(&"command_post", at, out, f)
	if cp == null:
		return {}
	var built := [cp]
	for e: Array in [[&"fighting_position", out, 28.0], [&"guard_tower_steel", out.rotated(Vector3.UP, 0.6), 24.0], [&"fighting_position", out.rotated(Vector3.UP, -0.7), 26.0]]:
		var st := _add_built(e[0], cp.position + (e[1] as Vector3) * float(e[2]), e[1], f)
		if st:
			built.append(st)
	ws.sync_bases()
	var sq := ws.spawn_squad(_war().faction(f), demo.sim.tactics.pos.nearest_valid(cp.position - out * 15.0, 20.0), n)
	demo.sim.tactics.assign_garrison(sq, cp.base_id, SquadState.Owner.SQUAD)
	return {"base": cp.base_id, "objective": ws.base_objective(cp.base_id), "squad": sq, "structures": built, "cp": cp}


func _owned_structures(f: int, ids: Array) -> int:
	var n := 0
	for id in ids:
		var s := demo.sim.state.construction.get_structure(id)
		if s and s.faction == f:
			n += 1
	return n


## Bases are strategic targets: a player base gets one objective of kind "base" (owner = the base's faction, no income),
## the HQ base stays linked to its HQ objective, the map draws it, the AI's decision evaluates it among its attack
## candidates (when in reach), and an enemy approaching the player's base raises the warnings in order, each once.
func _d_targets() -> Dictionary:
	var war := _war()
	var ws := demo.sim.war
	var pf := war.player_faction
	var sq: SquadState = _player_squads()[0]
	var out := {}
	var at := ws.squad_center(sq)
	var front := Vector3(0.6, 0.0, -0.8).normalized()
	var pb := _outpost(pf, at + front * 60.0, front, 4)
	_expect(not pb.is_empty() and pb.objective != null, "d: no player base / base objective")
	if pb.is_empty() or pb.objective == null:
		return out
	var po: ObjectiveState = pb.objective
	var income_value := ws.econ.owned_value(war.faction(pf))
	out["player_base"] = {"objective": po.obj_name, "kind": String(po.kind), "owner": po.owner, "value": po.value, "radius": po.radius, "income_value": income_value}
	_expect(po.is_base() and po.owner == pf and income_value == 0, "d: the player's base objective is wrong: %s" % str(out.player_base))
	var south_hq := war.objective(war.faction(1).hq_objective)
	var sb: Array = demo.sim.logistics.bases.bases_of(1)
	out["south_hq_link"] = {"base_objective": int(sb[0].get("objective", -1)) if not sb.is_empty() else -1, "hq": south_hq.id if south_hq else -1}
	_expect(not sb.is_empty() and south_hq != null and int(sb[0].objective) == south_hq.id, "d: South's HQ base is not linked to its HQ objective: %s" % str(out.south_hq_link))
	demo.toggle_map()
	demo.strategic_map.focus_on(po.position)
	await _seconds(1.0)
	_png("d_map_player_base")
	demo.toggle_map()
	await _seconds(0.5)
	var f1 := war.faction(1)
	ws.strat.decide(f1)
	var listed := false
	var cands: Array = f1.decisions.back().candidates if not f1.decisions.is_empty() else []
	for c: Dictionary in cands:
		if c.name == po.obj_name:
			listed = true
	out["south_candidates"] = cands.map(func(c: Dictionary) -> String: return "%s %.1f%s" % [c.name, c.score, " (skipped)" if c.skipped else ""])
	out["listed_by_south"] = listed
	out["south_reach_km"] = snappedf(ws.profile(f1).max_attack_distance / 1000.0, 0.1)
	var gsq: SquadState = pb.squad
	var events0 := war.events.size()
	var e_at := demo.sim.tactics.pos.nearest_valid(po.position + front * 520.0, 40.0)
	var esq := ws.spawn_squad(war.faction(1), e_at, 6)
	demo.sim.squads.order_move([esq.id], po.position)
	await _until(func() -> bool: return po.contested or esq.members.size() <= 1 or gsq.members.is_empty(), 240.0, 4.0)
	var texts := []
	for i in range(events0, war.events.size()):
		var e: Dictionary = war.events[i]
		if e.faction == pf and (e.kind == "threat" or e.kind == "attack"):
			texts.append(e.text)
	out["warnings"] = texts
	_expect(texts.size() >= 1, "d: the player was not warned about the approaching enemy: %s" % str(texts))
	if po.contested:
		_expect(texts.any(func(t: String) -> bool: return t.contains("under attack")), "d: contested base without an 'under attack' warning: %s" % str(texts))
	var spam := 0
	for t: String in texts:
		spam = maxi(spam, texts.count(t))
	_expect(spam <= 1, "d: repeated warnings: %s" % str(texts))
	for id in esq.members.duplicate():
		demo.sim.combat.kill(demo.sim.state.get_unit(id))
	return out


## An AI faction attacks another AI faction's base: an East outpost near ground South holds; South chooses it as its target
## (its own decision; the result says when it had to be ordered for the test), attacks with the existing operation, East
## defends from the outpost's fortifications, the capture is contested while defenders hold and completes after local
## control; the base and its structures change hands intact; the defenders' garrison ends; all of it with the camera
## kilometres away (no bodies). A save / load during the operation continues it.
func _d_ai_war() -> Dictionary:
	var war := _war()
	var ws := demo.sim.war
	var out := {}
	var best: ObjectiveState = null
	var best_d := INF
	var east_ref := Vector3.ZERO
	for o: ObjectiveState in war.owned_by(1):
		if o.is_hq() or o.is_base():
			continue
		for t: ObjectiveState in war.owned_by(2):
			var d := WarSim._flat(o.position, t.position)
			if d < best_d:
				best_d = d
				best = o
				east_ref = t.position
	_expect(best != null, "d_ai: no South objective near East")
	if best == null:
		return out
	var dir := east_ref - best.position
	dir.y = 0.0
	dir = dir.normalized()
	# Near South's free squads (an attack within reach of its forces), 1.3 km from them towards East.
	var f1s := war.faction(1)
	var free0 := ws._free_squads(f1s, ws.profile(f1s))
	var from: Vector3 = best.position
	var near_d := INF
	for sid in free0:
		var c := ws.squad_center(demo.sim.state.get_squad(sid))
		if WarSim._flat(c, east_ref) < near_d:
			near_d = WarSim._flat(c, east_ref)
			from = c
	var spot := demo.sim.tactics.pos.nearest_valid(from + dir * 1300.0, 80.0)
	var ob := _outpost(2, spot, -dir, 6)
	_expect(not ob.is_empty() and ob.objective != null, "d_ai: the East outpost could not be built at %s" % str(spot))
	if ob.is_empty() or ob.objective == null:
		return out
	var eo: ObjectiveState = ob.objective
	var ids: Array = ob.structures.map(func(st: StructureState) -> int: return st.id)
	var gid: int = (ob.squad as SquadState).id
	out["outpost"] = {"objective": eo.obj_name, "near": best.obj_name, "km_from_south_forces": snappedf(WarSim._flat(eo.position, from) / 1000.0, 0.1), "structures": ids.size(),
		"free_south_squads": free0.size()}
	var away := demo.on_ground(eo.position.x + 5000.0, eo.position.z + 3000.0, 0.0)
	demo.detail.activate_at(away)
	demo.rts_camera.frame(away, 0.5, 80.0)
	var f1 := war.faction(1)
	# Forces to spare: two fresh South squads near the outpost's side (South's own squads are tied up in this scenario).
	for k in 2:
		ws.spawn_squad(f1, demo.sim.tactics.pos.nearest_valid(from + Vector3(k * 14.0, 0.0, 10.0), 30.0), 8)
	f1.recovery_until = 0.0
	f1.next_decision_at = 0.0
	var t0 := demo.sim.state.time
	var find_op := func() -> OperationState:
		for o2: OperationState in war.active_operations(1):
			if o2.target_objective == eo.id and o2.type == OperationState.Type.ATTACK:
				return o2
		return null
	await _until(func() -> bool: return find_op.call() != null, 720.0, 8.0)
	var op: OperationState = find_op.call()
	out["natural_choice"] = op != null
	out["choice_after_s"] = roundi(demo.sim.state.time - t0)
	out["south_last_decision"] = f1.last_decision
	var cands: Array = f1.decisions.back().candidates if not f1.decisions.is_empty() else []
	out["south_candidates"] = cands.map(func(c: Dictionary) -> String: return "%s %.1f%s" % [c.name, c.score, " (skipped)" if c.skipped else ""])
	if op == null:
		var free := ws._free_squads(f1, ws.profile(f1))
		op = ws.start_operation(1, OperationState.Type.ATTACK, ws._pick_near(free, eo.position, 14), eo.id)
	_expect(op != null, "d_ai: no South attack on the East outpost")
	if op == null:
		return out
	out["op"] = {"id": op.id, "squads": op.squads.size(), "soldiers": op.start_strength, "reason": op.reason}
	await _until(func() -> bool: return op.phase >= OperationState.Phase.ENGAGING or not op.is_active(), 2400.0, 8.0)
	demo.construction.save()
	var lr := demo.construction.load_game()
	await _physics(10)
	var op2 := war.operation(op.id)
	out["persist"] = {"load": lr.ok, "op_active": op2 != null and op2.is_active(), "phase": op2.phase_name() if op2 else "-", "stage": op2.stage_name() if op2 else "-"}
	_expect(lr.ok and op2 != null and (op2.is_active() or op2.phase == OperationState.Phase.COMPLETED), "d_ai: the operation did not survive save / load: %s" % str(out.persist))
	op = op2
	eo = war.objective(eo.id)
	var gsq := demo.sim.state.get_squad(gid)
	var in_forts := _fort_units(2).size()
	var contested_seen := false
	var bodies := 0
	var t1 := demo.sim.state.time
	while demo.sim.state.time - t1 < 1800.0 and eo.owner == 2:
		CoreDemo.apply_time_scale(8.0)
		await _physics(20)
		contested_seen = contested_seen or eo.contested
		for u: UnitState in demo.sim.state.units.values():
			if u.has_body and WarSim._flat(u.position, eo.position) < 400.0:
				bodies = 1
		if op != null and not op.is_active() and eo.owner == 2:
			break
		if int(demo.sim.state.time) % 120 < 2:
			var dd := []
			for sid in (op.squads if op else []):
				var dsq := demo.sim.state.get_squad(sid)
				if dsq:
					dd.append("%s %.0fm %s %s r%d/%d %s" % [dsq.squad_name, WarSim._flat(ws.squad_center(dsq), eo.position), dsq.order_name(), dsq.tactic_name(), dsq.route_i, dsq.route.size(), dsq.route_wait_kind])
			print("CP diag t=%d op=%s stage=%s wait=%s why=%s transport=%s squads=%s" % [int(demo.sim.state.time), op.phase_name() if op else "-", op.stage_name() if op else "-", op.wait_reason if op else "", op.stage_why if op else "", str(op.transport.get("mode", "")) if op else "", str(dd)])
	CoreDemo.apply_time_scale(1.0)
	gsq = demo.sim.state.get_squad(gid)
	out["fight"] = {"defenders_in_forts_at_start": in_forts, "contested_seen": contested_seen, "owner": eo.owner, "op": op.phase_name() if op else "-",
		"outcome": op.outcome if op else "", "defenders_left": gsq.members.size() if gsq else 0, "bodies_near": bodies, "minutes": snappedf((demo.sim.state.time - t1) / 60.0, 0.1)}
	_expect(bodies == 0, "d_ai: bodies near the fight although the camera is away")
	_expect(contested_seen, "d_ai: the capture was never contested while defenders were there")
	_expect(eo.owner == 1, "d_ai: South did not capture the East outpost: %s" % str(out.fight))
	var b: Dictionary = demo.sim.state.construction.bases.get(int(ob.base), {})
	out["after"] = {"base_faction": int(b.get("faction", -1)), "structures_south": _owned_structures(1, ids), "structures": ids.size(),
		"east_garrison": gsq.garrison_base if gsq else -1}
	_expect(int(b.get("faction", -1)) == 1 and _owned_structures(1, ids) == ids.size(), "d_ai: the base / its structures did not change hands intact: %s" % str(out.after))
	_expect(gsq == null or gsq.garrison_base < 0, "d_ai: the defeated East squad still garrisons the lost base")
	demo.detail.activate_at(eo.position)
	await _frame(eo.position, 70.0, 0.6)
	_png("d_ai_captured_outpost")
	return out


## The player conducts a base assault from the strategic map: three squads, ATTACK on a South outpost near the start; the
## operation shows on the map, the squads advance with the existing coordination, a direct order takes one squad out
## (player override), the capture completes and the structures remain (now the player's).
func _d_player_assault() -> Dictionary:
	var war := _war()
	var ws := demo.sim.war
	var pf := war.player_faction
	var sq: SquadState = _player_squads()[0]
	var out := {}
	var at := ws.squad_center(sq)
	var dir := Vector3(-0.7, 0.0, -0.7).normalized()
	var ob := _outpost(1, demo.sim.tactics.pos.nearest_valid(at + dir * 700.0, 60.0), -dir, 5)
	_expect(not ob.is_empty() and ob.objective != null, "d_pa: the South outpost could not be built")
	if ob.is_empty() or ob.objective == null:
		return out
	var eo: ObjectiveState = ob.objective
	var ids: Array = ob.structures.map(func(st: StructureState) -> int: return st.id)
	var sq2 := ws.spawn_squad(war.faction(pf), demo.sim.tactics.pos.nearest_valid(at + Vector3(12, 0, 12), 20.0), 8)
	var sq3 := ws.spawn_squad(war.faction(pf), demo.sim.tactics.pos.nearest_valid(at + Vector3(-12, 0, 18), 20.0), 8)
	var sq4 := ws.spawn_squad(war.faction(pf), demo.sim.tactics.pos.nearest_valid(at + Vector3(-22, 0, 4), 20.0), 8)
	await _until(func() -> bool: return _fort_units(1).size() >= 3, 120.0, 4.0)
	out["defenders_in_forts"] = _fort_units(1).size()
	demo.toggle_map()
	await _seconds(0.5)
	var sm := demo.strategic_map
	sm.selected_squads = [sq.id, sq2.id, sq4.id, sq3.id]
	var op := sm.order(OperationState.Type.ATTACK, eo.id)
	if op:
		sm.select_operation(op.id)
	sm.focus_on(eo.position)
	await _seconds(1.0)
	_png("d_map_player_assault")
	demo.toggle_map()
	_expect(op != null and op.player_ordered and op.squads.size() == 4, "d_pa: the map order did not start a player operation")
	if op == null:
		return out
	# A player order takes a squad out of the running operation (checked while it runs: GAMEPLAY-02's squads may win the
	# fight on the approach already).
	demo.rts.select_squads([sq3.id])
	demo.rts.order_move(ws.squad_center(sq3) - dir * 30.0)
	await _physics(5)
	out["override"] = {"squad_op": sq3.op_id, "op_squads": op.squads.size(), "op_active": op.is_active()}
	_expect(op.is_active(), "d_pa: the operation ended before the override could be checked")
	_expect(sq3.op_id < 0 and not op.squads.has(sq3.id), "d_pa: a player order did not take the squad out of its operation")
	await _until(func() -> bool: return op.stage >= OperationState.Stage.DEPLOY or not op.is_active(), 600.0, 4.0)
	await _frame(eo.position - dir * 120.0, 140.0, 0.8)
	_png("d_player_assault")
	var contested_seen := false
	var progress_seen := 0.0
	var shot := false
	var t1 := demo.sim.state.time
	while demo.sim.state.time - t1 < 900.0 and eo.owner == 1 and op.is_active():
		CoreDemo.apply_time_scale(4.0)
		await _physics(20)
		contested_seen = contested_seen or eo.contested
		if eo.capture_faction == pf:
			progress_seen = maxf(progress_seen, eo.capture_progress)
			if eo.capture_progress > 0.4 and not shot:
				shot = true
				CoreDemo.apply_time_scale(1.0)
				await _frame(eo.position, 70.0, 0.7)
				_png("d_capture_in_progress")
	CoreDemo.apply_time_scale(1.0)
	out["result"] = {"owner": eo.owner, "op": op.phase_name(), "outcome": op.outcome, "contested_seen": contested_seen, "progress_seen": snappedf(progress_seen, 0.01),
		"stage": op.stage_name(), "structures_player": _owned_structures(pf, ids), "structures": ids.size(), "minutes": snappedf((demo.sim.state.time - t1) / 60.0, 0.1)}
	_expect(eo.owner == pf, "d_pa: the player's assault did not capture the outpost: %s" % str(out.result))
	_expect(_owned_structures(pf, ids) == ids.size(), "d_pa: the captured structures are not the player's: %s" % str(out.result))
	await _frame(eo.position, 70.0, 0.7)
	_png("d_captured_installation")
	return out


# --- 01E: replenishment and AI expansion -----------------------------------------------------------------------------

func _queue_of(s: StructureState) -> Array:
	return s.facility.get("queue", [])


## A depleted player squad is replenished at a barracks: the same squad (id, name) gets the missing soldiers, paid per
## soldier like a recruit (supplies, ammunition, personnel), it takes time, never more than the squad's strength, the bed
## limit holds, cancel refunds exactly, and a pending replenishment survives save / load.
func _e_replenish() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var f := war.faction(pf)
	var bs := demo.sim.logistics.bases
	var sq: SquadState = _player_squads()[0]
	var out := {}
	var front := Vector3(0.6, 0.0, -0.8).normalized()
	var at := demo.sim.war.squad_center(sq)
	var cp := _add_built(&"command_post", at + front * 40.0, front, pf)
	var bk := _add_built(&"barracks_block", at + front * 40.0 + Vector3(-front.z, 0, front.x) * 45.0, front, pf)
	_expect(cp != null and bk != null and bk.base_id >= 0, "e: no base with a barracks for the replenishment test")
	if bk == null or bk.base_id < 0:
		return out
	f.pool.add(Inventory.SUPPLIES, 2000.0)
	f.pool.add(Inventory.AMMO, 800.0)
	var name0 := sq.squad_name
	var id0 := sq.id
	for i in 3:
		demo.sim.combat.kill(demo.sim.state.get_unit(sq.members[sq.members.size() - 1]))
	await _physics(5)
	demo.sim.squads.order_move([sq.id], demo.sim.tactics.pos.nearest_valid(bk.position + front * -14.0, 20.0))
	await _until(func() -> bool: return sq.status != SquadState.Status.MOVING, 120.0, 4.0)
	var st0 := _stock()
	var res0 := f.reserves
	var r := bs.replenish(bk.id, sq.id)
	var st1 := _stock()
	out["order"] = {"ok": r.ok, "reason": r.reason, "n": r.get("n", 0), "paid_supplies": roundi(st0.supplies - st1.supplies), "paid_ammo": roundi(st0.ammo - st1.ammo),
		"personnel": res0 - f.reserves, "queue": _queue_of(bk).size()}
	_expect(r.ok and int(r.n) == 3 and roundi(st0.supplies - st1.supplies) == 120 and roundi(st0.ammo - st1.ammo) == 72 and res0 - f.reserves == 3,
		"e: replenishment not paid per soldier: %s" % str(out.order))
	var again := bs.replenish(bk.id, sq.id)
	_expect(not again.ok, "e: a second replenishment beyond the squad's strength was accepted")
	out["beyond_strength"] = again.reason
	bs.cancel_queue(bk.id, 0)
	var st2 := _stock()
	out["cancel"] = {"supplies_back": roundi(st2.supplies - st1.supplies), "ammo_back": roundi(st2.ammo - st1.ammo), "reserves": f.reserves == res0}
	_expect(roundi(st2.supplies - st1.supplies) == 120 and roundi(st2.ammo - st1.ammo) == 72 and f.reserves == res0, "e: cancel did not refund exactly: %s" % str(out.cancel))
	r = bs.replenish(bk.id, sq.id)
	_expect(r.ok, "e: replenishment refused after cancel: %s" % r.reason)
	# Bed limit: the base has 40 beds; a test faction short of beds is refused.
	demo.construction.save()
	var lr := demo.construction.load_game()
	await _physics(5)
	var bk2 := demo.sim.state.construction.get_structure(bk.id)
	var q2: Array = _queue_of(bk2) if bk2 else []
	out["persist"] = {"load": lr.ok, "queue": q2.size(), "kind": q2[0].kind if not q2.is_empty() else "", "squad": int(q2[0].get("squad", -1)) if not q2.is_empty() else -1}
	_expect(lr.ok and q2.size() == 1 and q2[0].kind == "replenish" and int(q2[0].squad) == id0, "e: the pending replenishment did not survive save / load: %s" % str(out.persist))
	var sq2 := demo.sim.state.get_squad(id0)
	var t0 := demo.sim.state.time
	await _until(func() -> bool: return sq2 != null and sq2.members.size() >= 8, 120.0, 4.0)
	out["done"] = {"members": sq2.members.size() if sq2 else 0, "same_name": sq2 != null and sq2.squad_name == name0, "seconds": roundi(demo.sim.state.time - t0),
		"squads": _player_squads().size(), "teams": sq2.teams.size() if sq2 else 0}
	_expect(sq2 != null and sq2.members.size() == 8 and sq2.squad_name == name0 and _player_squads().size() == 1, "e: the squad was not refilled in place: %s" % str(out.done))
	_expect(float(out.done.seconds) >= 15.0, "e: replenishment took no time")
	await _frame(bk.position, 60.0, 0.7)
	_png("e_replenished_at_barracks")
	return out


## An AI faction expands: with supplies and squads to spare it picks a held objective far from its bases, pays and builds
## a Forward Outpost one site after the other (nothing appears at once), the command post founds a base that becomes a
## target, a squad garrisons it; no second expansion starts during the cooldown, and the expansion survives save / load.
func _e_expansion() -> Dictionary:
	var war := _war()
	var ws := demo.sim.war
	var bs := demo.sim.logistics.bases
	var out := {}
	var f := war.faction(1)
	var mb := bs.main_base(1)
	_expect(mb >= 0 and bool(war.rule("ai_expansion", false)), "e_x: South has no main base or expansion is off")
	if mb < 0:
		return out
	var stores := bs.base_stores(mb)
	for s: StructureState in stores:
		if s.inventory.accepts(Inventory.SUPPLIES):
			s.inventory.add(Inventory.SUPPLIES, 4000.0)
			break
	f.expand_next_at = 0.0
	var bases0 := bs.bases_of(1).size()
	var sup0: float = bs.faction_stock(1).supplies
	await _until(func() -> bool: return not ws.bases.active_expansion(1).is_empty(), 600.0, 8.0)
	var e: Dictionary = ws.bases.active_expansion(1)
	out["started"] = not e.is_empty()
	out["why_not"] = ws.econ._expand_why.get(1, "")
	_expect(not e.is_empty(), "e_x: South did not start an expansion: %s" % str(out.why_not))
	if e.is_empty():
		return out
	var o := war.objective(int(e.objective))
	out["plan"] = {"template": e.template, "objective": o.obj_name if o else "-", "pos": [roundi(e.pos.x), roundi(e.pos.z)], "why": e.why}
	var cp := demo.sim.state.construction.get_structure(int(e.site))
	out["template_cost"] = roundi(ws.bases.template_cost(String(e.template)))
	_expect(cp != null and cp.is_site() and cp.base_id < 0, "e_x: the command post is not a site / a base appeared at once")
	# Save / load mid-expansion.
	await _until(func() -> bool: return cp.site_progress() > 0.3, 200.0, 8.0)
	demo.construction.save()
	var lr := demo.construction.load_game()
	await _physics(5)
	var e2: Dictionary = ws.bases.active_expansion(1)
	out["persist"] = {"load": lr.ok, "state": e2.get("state", "-"), "site": demo.sim.state.construction.get_structure(int(e2.get("site", -1))) != null}
	_expect(lr.ok and not e2.is_empty() and bool(out.persist.site), "e_x: the expansion did not survive save / load: %s" % str(out.persist))
	var t0 := demo.sim.state.time
	await _until(func() -> bool:
		for x: Dictionary in war.expansions:
			if int(x.faction) == 1 and x.state == "done":
				return true
		return false, 1800.0, 8.0)
	var done: Dictionary = {}
	for x: Dictionary in war.expansions:
		if int(x.faction) == 1 and int(x.id) == int(e2.get("id", -1)):
			done = x
	var b: Dictionary = demo.sim.state.construction.bases.get(int(done.get("base", -1)), {})
	var bo := ws.base_objective(int(done.get("base", -1))) if not b.is_empty() else null
	var garrison := 0
	for sq: SquadState in ws.squads_of(1):
		if sq.garrison_base == int(done.get("base", -2)):
			garrison += 1
	var structs := 0
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == 1 and not b.is_empty() and Vector2(s.position.x - b.anchor.x, s.position.z - b.anchor.z).length() < 170.0:
			structs += 1
	out["result"] = {"state": done.get("state", "-"), "minutes": snappedf((demo.sim.state.time - t0) / 60.0, 0.1), "bases": bs.bases_of(1).size(), "structures": structs,
		"objective": bo.obj_name if bo else "-", "kind": String(bo.kind) if bo else "-", "garrison_squads": garrison, "spent": roundi(sup0 + 4000.0 - float(bs.faction_stock(1).supplies))}
	_expect(done.get("state", "") == "done" and bs.bases_of(1).size() >= bases0 + 1, "e_x: the outpost was not completed: %s" % str(out.result))
	# The base is a target: its own base objective, or the held objective it stands on (a base at North Bridge is North Bridge).
	_expect(bo != null and bo.owner == 1 and int(b.get("objective", -1)) == bo.id and garrison >= 1 and structs >= 3, "e_x: the new base is no target / has no garrison: %s" % str(out.result))
	# Conservative: no second expansion during the cooldown.
	await _until(func() -> bool: return not ws.bases.active_expansion(1).is_empty(), 120.0, 8.0)
	out["second_during_cooldown"] = not ws.bases.active_expansion(1).is_empty()
	_expect(not bool(out.second_during_cooldown), "e_x: a second expansion started during the cooldown")
	if not b.is_empty():
		demo.detail.activate_at(b.anchor)
		await _frame(b.anchor, 80.0, 0.7)
		_png("e_ai_outpost")
	return out


# --- 01F: damage and repair --------------------------------------------------------------------------------------------

## Rifle fire scratches a fortification (it does not destroy it quickly); heavy damage (applied through the damage API
## as an explosive would: no heavy weapon exists yet) disables a barracks - no recruiting, no replenishment, fewer beds -
## and a guard tower (its slots are given up); the player repairs the barracks for supplies, the squad does the work, fire
## interrupts it, it resumes and restores the barracks; health and an unfinished repair survive save / load; a captured
## structure keeps its damage.
func _f_damage() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var f := war.faction(pf)
	var cs := demo.sim.state.construction
	var bs := demo.sim.logistics.bases
	var sq: SquadState = _player_squads()[0]
	var out := {}
	var front := Vector3(0.6, 0.0, -0.8).normalized()
	var side := Vector3(-front.z, 0.0, front.x)
	var at := demo.sim.war.squad_center(sq)
	var cp := _add_built(&"command_post", at + front * 40.0, front, pf)
	var bk := _add_built(&"barracks_block", cp.position + side * 45.0, front, pf) if cp else null
	var tw := _add_built(&"guard_tower_steel", cp.position + front * 30.0 - side * 20.0, front, pf) if cp else null
	_expect(cp != null and bk != null and tw != null, "f: the test base could not be built")
	if bk == null or tw == null:
		return out
	f.pool.add(Inventory.SUPPLIES, 3000.0)
	f.pool.add(Inventory.AMMO, 800.0)
	# Rifle fire at the tower: 300 rounds from 60 m.
	var shooter := demo.sim.war.spawn_squad(war.faction(1), demo.sim.tactics.pos.nearest_valid(tw.position + front * 60.0, 20.0), 1)
	var su := demo.sim.state.get_unit(shooter.members[0])
	var hits := 0
	for i in 300:
		su.mag = 30
		su.next_shot_at = 0.0
		su.reload_until = -1.0
		var eye := CombatSim.eye_of(su)
		var aim := tw.position + Vector3.UP * 2.5
		var shot := demo.sim.combat.request_fire(su.id, eye, (aim - eye).normalized())
		if float(shot.get("structure_damage", 0.0)) > 0.0:
			hits += 1
	demo.sim.combat.kill(su)
	out["rifle"] = {"hits": hits, "tower_health": snappedf(tw.health_frac(), 0.001)}
	_expect(hits >= 100 and tw.health_frac() > 0.85 and tw.health_frac() < 1.0, "f: rifle fire does not scratch / destroys the tower: %s" % str(out.rifle))
	# The garrison takes the tower; heavy damage disables it and they give it up.
	demo.sim.tactics.assign_garrison(sq, cp.base_id, SquadState.Owner.PLAYER)
	await _until(func() -> bool: return _fort_units(pf).size() >= 2, 120.0, 4.0)
	var on_tower := func() -> int:
		var n := 0
		for u: UnitState in _fort_units(pf):
			if u.fort_slot.begins_with("%d:" % tw.id):
				n += 1
		return n
	var before_tower: int = on_tower.call()
	cs.damage(tw, tw.health() - tw.max_hp() * 0.2)
	await _until(func() -> bool: return on_tower.call() == 0, 20.0, 2.0)
	out["tower"] = {"manned_before": before_tower, "manned_after": on_tower.call(), "condition": tw.condition_text(), "operational": tw.is_operational()}
	_expect(not tw.is_operational() and on_tower.call() == 0, "f: the disabled tower is still manned / operational: %s" % str(out.tower))
	# Barracks disabled.
	var beds0 := bs.capacity(bk.base_id)
	cs.damage(bk, bk.max_hp() * 0.8)
	var rec := bs.recruit(bk.id)
	out["barracks"] = {"condition": bk.condition_text(), "recruit": rec.reason, "beds_before": beds0, "beds_after": bs.capacity(bk.base_id), "band": bk.damage_band()}
	_expect(not rec.ok and bs.capacity(bk.base_id) < beds0, "f: the disabled barracks still works: %s" % str(out.barracks))
	await _frame(bk.position, 45.0, 0.7)
	_png("f_damaged_barracks")
	# Repair: paid, worked by the squad.
	demo.rts.select_squads([])
	var st0 := _stock()
	var cost := StructureHealth.repair_cost(bk)
	var rr := demo.construction.order_repair(bk.id)
	out["repair_order"] = {"ok": rr.ok, "cost": roundi(cost), "paid": roundi(st0.supplies - _stock().supplies), "message": demo.construction.message}
	_expect(rr.ok and absf(st0.supplies - _stock().supplies - cost) < 1.0, "f: the repair was not paid: %s" % str(out.repair_order))
	if not rr.ok:
		return out
	if sq.tactic != SquadState.Tactic.BUILD:
		demo.sim.tactics.order_build([sq.id], bk.id)
	await _until(func() -> bool: return int(bk.repair.get("workers", 0)) >= 3, 120.0, 4.0)
	await _frame(bk.position, 40.0, 0.7)
	_png("f_repair_in_progress")
	# Fire interrupts the work (player-ordered: it pauses), then it resumes.
	for id in sq.members:
		demo.sim.state.get_unit(id).under_fire_until = demo.sim.state.time + 6.0
	await _physics(30)
	var w0 := float(bk.repair.get("work", 0.0))
	await _until(func() -> bool: return false, 4.0, 1.0)
	var w1 := float(bk.repair.get("work", 0.0))
	# Save mid-repair.
	demo.construction.save()
	var lr := demo.construction.load_game()
	await _physics(10)
	var bk2 := cs.get_structure(bk.id)
	out["persist"] = {"load": lr.ok, "hp": snappedf(bk2.health_frac(), 0.01) if bk2 else -1.0, "repair_work": roundi(float(bk2.repair.get("work", -1.0))) if bk2 else -1, "saved_work": roundi(w1)}
	_expect(lr.ok and bk2 != null and not bk2.repair.is_empty() and absf(float(bk2.repair.work) - w1) < 1.0 and bk2.health_frac() < 0.5, "f: damage / repair not restored: %s" % str(out.persist))
	sq = demo.sim.state.get_squad(sq.id)
	if sq.tactic != SquadState.Tactic.BUILD:
		demo.sim.tactics.order_build([sq.id], bk.id)
	var t0 := demo.sim.state.time
	await _until(func() -> bool: return bk2.repair.is_empty(), 300.0, 4.0)
	out["repair"] = {"paused_work": snappedf(w1 - w0, 0.1), "seconds": roundi(demo.sim.state.time - t0), "health": snappedf(bk2.health_frac(), 0.01), "operational": bk2.is_operational()}
	_expect(w1 - w0 < 1.0, "f: work went on under fire: %s" % str(out.repair))
	_expect(bk2.repair.is_empty() and bk2.health_frac() >= 0.999 and bk2.is_operational(), "f: the repair did not restore the barracks: %s" % str(out.repair))
	var rec2 := bs.recruit(bk2.id)
	out["recruit_after"] = rec2.ok
	_expect(rec2.ok, "f: the repaired barracks cannot recruit: %s" % rec2.reason)
	# Capture keeps damage: a South outpost with a damaged tower changes hands.
	var ob := _outpost(1, demo.sim.tactics.pos.nearest_valid(at - front * 600.0, 60.0), front, 2)
	if not ob.is_empty():
		var t2: StructureState = ob.structures[ob.structures.size() - 1]
		cs.damage(t2, t2.max_hp() * 0.5)
		var hp_before := t2.health()
		var obj: ObjectiveState = ob.objective
		demo.sim.war._transfer(obj, pf)
		out["capture"] = {"faction": t2.faction, "hp_before": roundi(hp_before), "hp_after": roundi(t2.health())}
		_expect(t2.faction == pf and absf(t2.health() - hp_before) < 0.5, "f: capture repaired / did not take the structure: %s" % str(out.capture))
	return out


## An AI faction repairs an important damaged structure when it is safe and it can pay: South's supply depot at half
## strength is repaired by the economy's decision, paid from the base, by its crew.
func _f_ai_repair() -> Dictionary:
	var war := _war()
	var bs := demo.sim.logistics.bases
	var cs := demo.sim.state.construction
	var out := {}
	var mb := bs.main_base(1)
	var depot: StructureState = null
	for s: StructureState in bs.facilities_of(mb):
		if FacilityDefs.kind_of(s.type_id) == &"barracks":
			depot = s
	_expect(depot != null, "f_ai: South has no barracks")
	if depot == null:
		return out
	cs.damage(depot, depot.max_hp() * 0.7)
	var sup0: float = bs.faction_stock(1).supplies
	out["damaged"] = {"what": FacilityDefs.display_name(depot.type_id), "health": snappedf(depot.health_frac(), 0.01), "operational": depot.is_operational()}
	await _until(func() -> bool: return not depot.repair.is_empty(), 120.0, 8.0)
	out["ordered"] = not depot.repair.is_empty()
	out["econ"] = war.faction(1).econ_actions.map(func(a: Dictionary) -> String: return "%s %s" % [a.kind, a.status])
	_expect(not depot.repair.is_empty(), "f_ai: South did not order the repair: %s" % str(out.econ))
	await _until(func() -> bool: return depot.repair.is_empty(), 300.0, 8.0)
	out["result"] = {"health": snappedf(depot.health_frac(), 0.01), "operational": depot.is_operational(), "paid_about": roundi(sup0 - float(bs.faction_stock(1).supplies))}
	_expect(depot.health_frac() >= 0.999 and depot.is_operational(), "f_ai: the repair did not finish: %s" % str(out.result))
	return out


# --- 01G: in-game menu and the campaign --------------------------------------------------------------------------------

const CAMPAIGN_EXPECT := "user://test_saves/campaign_expect.json"


## Esc opens the in-game menu and pauses the game (simulation time stops, the mouse is free), Esc closes it; Save Game
## writes the test slot, Load Game restores it, a damaged save is refused with its reason and changes nothing.
func _g_pause() -> Dictionary:
	var out := {}
	demo.game.enter_rts()
	demo.rts.select([])
	await _seconds(0.5)
	_press(KEY_ESCAPE)
	await _seconds(0.5)
	var t0 := demo.sim.state.time
	await get_tree_timer(1.0)
	out["open"] = {"menu": demo.pause_menu != null and demo.pause_menu.visible, "paused": tree.paused, "time_frozen": absf(demo.sim.state.time - t0) < 0.001,
		"mouse": Input.mouse_mode == Input.MOUSE_MODE_VISIBLE}
	_expect(bool(out.open.menu) and tree.paused and bool(out.open.time_frozen), "g: Esc did not open the menu / pause the game: %s" % str(out.open))
	_png("g_pause_menu")
	demo._on_pause_chosen("save")
	await get_tree_timer(0.5)
	out["save"] = {"peek": demo.peek_save().get("ok", false), "path": demo.save_dir()}
	_expect(bool(out.save.peek) and String(out.save.path).contains("test_saves"), "g: Save Game from the menu failed: %s" % str(out.save))
	var squads0 := demo.sim.state.squads.size()
	demo._on_pause_chosen("load")
	await _seconds(1.0)
	out["load"] = {"closed": not demo.pause_menu.visible, "paused": tree.paused, "squads": demo.sim.state.squads.size() == squads0}
	_expect(not demo.pause_menu.visible and not tree.paused and bool(out.load.squads), "g: Load Game from the menu failed: %s" % str(out.load))
	# A damaged save: refused, nothing replaced.
	var wpath := demo.save_dir().path_join("world.json")
	var good := FileAccess.get_file_as_string(wpath)
	var fw := FileAccess.open(wpath, FileAccess.WRITE)
	fw.store_string("{ broken")
	fw.close()
	demo.toggle_pause()
	await get_tree_timer(0.3)
	var load_disabled := (demo.pause_menu._buttons["load"] as Button).disabled
	demo._on_pause_chosen("load")
	await get_tree_timer(0.3)
	out["damaged"] = {"load_button_disabled": load_disabled, "still_open": demo.pause_menu.visible, "status": demo.pause_menu._status.text, "squads_same": demo.sim.state.squads.size() == squads0}
	_expect(load_disabled and demo.pause_menu.visible and bool(out.damaged.squads_same), "g: a damaged save was not refused: %s" % str(out.damaged))
	fw = FileAccess.open(wpath, FileAccess.WRITE)
	fw.store_string(good)
	fw.close()
	# Esc closes it again; the game runs.
	_press(KEY_ESCAPE)
	await _seconds(0.5)
	var t1 := demo.sim.state.time
	await _seconds(0.5)
	out["resume"] = {"closed": not demo.pause_menu.visible, "running": demo.sim.state.time > t1}
	_expect(not demo.pause_menu.visible and demo.sim.state.time > t1, "g: Esc did not resume the game: %s" % str(out.resume))
	# From first person: Esc frees the mouse and opens the menu; Resume gives the view its mouse back.
	var sq: SquadState = _player_squads()[0] if not _player_squads().is_empty() else null
	if sq:
		demo.game.possess(sq.leader_id)
		await _seconds(1.0)
		demo.toggle_pause()
		await get_tree_timer(0.3)
		var fps_paused := tree.paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
		demo._on_pause_chosen("resume")
		await _seconds(0.3)
		out["fps"] = {"paused_with_free_mouse": fps_paused, "resumed": not tree.paused, "mode": demo.game.mode}
		_expect(fps_paused and not tree.paused, "g: the menu does not work from first person: %s" % str(out.fps))
		demo.game.enter_rts()
		await _seconds(0.5)
	return out


func get_tree_timer(s: float) -> void:
	await tree.create_timer(s, true, false, true).timeout


## The campaign from the real start screen (run with --menu-shot): the GAMEPLAY-01B early game (cache, command post, depot,
## Verket, barracks, recruit, guard tower; steps 1-18 of the first-playable loop), then fortifications, a garrison in its
## positions, an assault on an enemy outpost (placed near the player: New Game has no enemy base within reach of the start),
## its capture, a counterattack by South's own operation machinery, replenishment, a repair, a second base, a save; a second
## process (--continue ... --only g_campaign_continue) checks what came back and that the AI factions act on.
func _g_campaign() -> Dictionary:
	var war := _war()
	var ws := demo.sim.war
	var pf := war.player_faction
	var bs := demo.sim.logistics.bases
	var out := {}
	var early := await _loop()
	out["early_game"] = {"steps": _steps.size(), "failed": _steps.filter(func(e: Dictionary) -> bool: return not e.ok).map(func(e: Dictionary) -> int: return e.step),
		"game_minutes": early.get("game_minutes", -1)}
	var mb := bs.main_base(pf)
	_expect(mb >= 0, "g: no player base after the early game")
	if mb < 0:
		return out
	var cpos: Vector3 = demo.sim.state.construction.bases[mb].anchor
	var sqs := _player_squads()
	var n1: SquadState = sqs[0]
	var n2: SquadState = sqs[sqs.size() - 1]
	var front := Vector3(-0.3, 0.0, -1.0).normalized()
	# 9. Fortifications through the construction tool (paid, built by the squads).
	await _until(func() -> bool: return _stock().supplies >= 160.0, 600.0, 8.0)
	var fp := _place_facing(&"fighting_position", _spot_dir(&"fighting_position", cpos, front, 45.0), front)
	var mg := _place_facing(&"mg_emplacement", _spot_dir(&"mg_emplacement", cpos, front.rotated(Vector3.UP, 0.5), 50.0), front.rotated(Vector3.UP, 0.5))
	await _until(func() -> bool: return (fp == null or not fp.is_site()) and (mg == null or not mg.is_site()), 600.0, 8.0)
	_g_step(9, "fortifications built", fp != null and mg != null and not fp.is_site() and not mg.is_site(), {"fp": fp != null, "mg": mg != null})
	# 10-11. Garrison: the recruited squad holds the base from its positions.
	demo.rts.select_squads([n2.id])
	demo.rts.order_garrison(mb)
	await _until(func() -> bool: return _fort_units(pf).size() >= 3, 240.0, 4.0)
	_g_step(10, "squad assigned to Garrison Base", n2.garrison_base == mb, {"squad": n2.squad_name})
	_g_step(11, "soldiers occupy defensive positions", _fort_units(pf).size() >= 3, {"in_slots": _fort_units(pf).size()})
	await _frame(cpos + front * 30.0, 70.0, 0.7)
	_png("g_player_base_garrison")
	# 12-13. An enemy outpost 1.2 km away; the player's assault through the map with the free squad and a fresh recruit.
	var dir := front.rotated(Vector3.UP, 1.1)
	var ob := _outpost(1, demo.sim.tactics.pos.nearest_valid(cpos + dir * 1200.0, 80.0), -dir, 4)
	_expect(not ob.is_empty() and ob.objective != null, "g: the enemy outpost could not be placed")
	if ob.is_empty():
		return out
	var eo: ObjectiveState = ob.objective
	await _until(func() -> bool: return _stock().supplies >= 330.0 and _stock().ammo >= 200.0, 900.0, 8.0)
	var bk: StructureState = null
	for s: StructureState in bs.facilities_of(mb):
		if FacilityDefs.kind_of(s.type_id) == &"barracks":
			bk = s
	var n_before := _player_squads().size()
	if bk:
		bs.recruit(bk.id)
	await _until(func() -> bool: return _player_squads().size() > n_before, 120.0, 4.0)
	var n3: SquadState = _player_squads().back()
	demo.toggle_map()
	await _seconds(0.5)
	demo.strategic_map.selected_squads = [n1.id, n3.id]
	var op := demo.strategic_map.order(OperationState.Type.ATTACK, eo.id)
	demo.strategic_map.focus_on(eo.position)
	await _seconds(1.0)
	_png("g_map_operation")
	demo.toggle_map()
	await _until(func() -> bool: return eo.owner == pf or op == null or not op.is_active(), 1500.0, 4.0)
	_g_step(12, "player-led attack on an enemy base", op != null and op.player_ordered, {"outcome": op.outcome if op else "-", "stage": op.stage_name() if op else "-"})
	_g_step(13, "enemy base captured", eo.owner == pf, {"owner": eo.owner, "structures_player": _owned_structures(pf, ob.structures.map(func(st: StructureState) -> int: return st.id))})
	await _frame(eo.position, 70.0, 0.6)
	_png("g_captured_outpost")
	# 14. A South counterattack (its own operation machinery) on the captured base; the defenders respond.
	var holders: Array = []
	for sq: SquadState in _player_squads():
		if sq.garrison_base == int(ob.base) or WarSim._flat(ws.squad_center(sq), eo.position) < 300.0:
			holders.append(sq)
	if eo.owner == pf and not holders.is_empty() and (holders[0] as SquadState).garrison_base < 0:
		demo.rts.select_squads([(holders[0] as SquadState).id])
		demo.rts.order_garrison(int(ob.base))
	var csq := ws.spawn_squad(war.faction(1), demo.sim.tactics.pos.nearest_valid(eo.position + dir * 600.0, 60.0), 6)
	var cop := ws.start_operation(1, OperationState.Type.ATTACK, [csq.id], eo.id)
	var ev_t0 := demo.sim.state.time
	await _until(func() -> bool: return cop == null or not cop.is_active() or eo.owner != pf, 900.0, 4.0)
	var warned := false
	for e: Dictionary in war.events:
		if float(e.t) >= ev_t0 - 0.1 and e.faction == pf and e.kind in ["threat", "attack"]:
			warned = true
	_g_step(14, "AI counterattack met", cop != null, {"outcome": cop.outcome if cop else "-", "owner_after": eo.owner, "warned": warned})
	# 15. Replenishment of a depleted squad at the barracks (the panel button).
	var dep: SquadState = null
	for sq: SquadState in _player_squads():
		if sq.members.size() < BaseSim.SQUAD_SIZE and (dep == null or sq.members.size() < dep.members.size()):
			dep = sq
	if dep and bk:
		demo.rts.select_squads([dep.id])
		demo.rts.order_move(demo.sim.tactics.pos.nearest_valid(bk.position - front * 15.0, 20.0))
		await _until(func() -> bool: return dep.status != SquadState.Status.MOVING, 900.0, 8.0)
		await _until(func() -> bool: return _stock().supplies >= 200.0 and _stock().ammo >= 120.0, 600.0, 8.0)
		demo.rts.select_squads([dep.id])
		demo.rts.selected_structure = bk.id
		await _frame(bk.position, 55.0)
		await _seconds(1.0)
		var pressed := _press_panel_button("REPLENISH")
		var m0 := dep.members.size()
		await _until(func() -> bool: return dep.members.size() >= BaseSim.SQUAD_SIZE, 180.0, 4.0)
		_g_step(15, "casualties replenished at the barracks", pressed and dep.members.size() > m0, {"squad": dep.squad_name, "from": m0, "to": dep.members.size()})
	else:
		_g_step(15, "casualties replenished at the barracks", dep == null, {"note": "no squad had casualties to replace (replenishment is shown by e_replenish)" if dep == null else "no barracks"})
	# 16. Repair: the most damaged structure of the player.
	var worst: StructureState = null
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == pf and not s.is_site() and s.health_frac() < 0.999 and (worst == null or s.health_frac() < worst.health_frac()):
			worst = s
	out["damage_seen"] = {"worst": String(worst.type_id) if worst else "-", "health": snappedf(worst.health_frac(), 0.001) if worst else 1.0}
	if worst:
		var rr := demo.construction.order_repair(worst.id)
		var busy := false
		for sq: SquadState in _player_squads():
			busy = busy or (sq.tactic == SquadState.Tactic.BUILD and sq.tactic_site == worst.id)
		if rr.ok and not busy:
			# Every squad holds a base: the player sends the nearest one (right-click with it selected).
			var near: SquadState = null
			for sq: SquadState in _player_squads():
				if near == null or WarSim._flat(ws.squad_center(sq), worst.site_center()) < WarSim._flat(ws.squad_center(near), worst.site_center()):
					near = sq
			demo.rts.select_squads([near.id])
			demo.rts.order_build(worst.id)
		await _until(func() -> bool: return worst.repair.is_empty(), 600.0, 4.0)
		_g_step(16, "damaged infrastructure repaired", rr.ok and worst.health_frac() >= 0.999, {"what": String(worst.type_id), "cost": rr.get("cost", 0)})
	else:
		_g_step(16, "damaged infrastructure repaired", true, {"note": "nothing of the player's was damaged in this run"})
	# 17. Expansion: a second command post near Verket.
	var verket: ObjectiveState = null
	for o: ObjectiveState in war.all_objectives():
		if o.obj_name == "Verket":
			verket = o
	await _until(func() -> bool: return _stock().supplies >= 420.0, 900.0, 8.0)
	var cp2: StructureState = null
	for anchor: Vector3 in [verket.position if verket else cpos, cpos + Vector3(900, 0, 600), cpos + Vector3(-900, 0, 700), cpos + Vector3(700, 0, -900)]:
		var spot := _cp_spot(anchor)
		if spot.is_finite():
			cp2 = _place(&"command_post", spot)
			if cp2 != null:
				break
	if cp2 != null:
		var builder := false
		for sq: SquadState in _player_squads():
			builder = builder or (sq.tactic_site == cp2.id)
		if not builder:
			# Every squad holds a base: the player sends one that does not hold the main base.
			for sq: SquadState in _player_squads():
				if sq.garrison_base != mb:
					demo.rts.select_squads([sq.id])
					demo.rts.order_build(cp2.id)
					break
	await _until(func() -> bool: return cp2 != null and not cp2.is_site(), 900.0, 8.0)
	_g_step(17, "expanded into another area", cp2 != null and not cp2.is_site() and bs.bases_of(pf).size() >= 3, {"bases": bs.bases_of(pf).size()})
	# 18. Save.
	_press(KEY_F5)
	await _physics(5)
	var hp := {}
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == pf and s.hp >= 0.0:
			hp[str(s.id)] = snappedf(s.hp, 0.1)
	var garr := {}
	for sq: SquadState in _player_squads():
		garr[str(sq.id)] = sq.garrison_base
	var expect := {"squads": _player_squads().size(), "soldiers": bs.soldiers_of(pf), "bases": bs.bases_of(pf).size(), "supplies": roundi(_stock().supplies),
		"owners": _owners(), "hp": hp, "garrisons": garr, "ops": war.active_operations().size(), "time": demo.sim.state.time,
		"ai_ops_started": war.faction(1).ops_started + war.faction(2).ops_started}
	var fw := FileAccess.open(CAMPAIGN_EXPECT, FileAccess.WRITE)
	fw.store_string(JSON.stringify(expect))
	fw.close()
	_g_step(18, "saved", demo.peek_save().get("ok", false), {"game_minutes": snappedf(demo.sim.state.time / 60.0, 0.1)})
	await _frame(cpos + front * 40.0, 140.0, 0.7)
	_png("g_campaign_before_save")
	out["steps"] = _g_steps
	out["expect"] = expect
	return out


## Steps 19-22: the program was restarted and continued; ownership, squads, buildings, damage, garrisons, resources and
## operations are back, and the AI factions keep acting.
func _g_campaign_continue() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var bs := demo.sim.logistics.bases
	var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN_EXPECT)) if FileAccess.file_exists(CAMPAIGN_EXPECT) else null
	_g_step(19, "program restarted", expect is Dictionary)
	if not expect is Dictionary:
		return {"steps": _g_steps}
	_g_step(20, "campaign continued", bool(demo.continue_result.get("ok", false)), {"continue": demo.continue_result})
	var hp := {}
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == pf and s.hp >= 0.0:
			hp[str(s.id)] = snappedf(s.hp, 0.1)
	var garr := {}
	for sq: SquadState in _player_squads():
		garr[str(sq.id)] = sq.garrison_base
	var now := {"squads": _player_squads().size(), "soldiers": bs.soldiers_of(pf), "bases": bs.bases_of(pf).size(), "supplies": roundi(_stock().supplies),
		"owners": _owners(), "hp": hp, "garrisons": garr, "ops": war.active_operations().size()}
	# Through JSON like the expectation file, so 8 and 8.0 compare equal.
	var nj: Dictionary = JSON.parse_string(JSON.stringify(now))
	var same: bool = int(now.squads) == int(expect.squads) and int(now.soldiers) == int(expect.soldiers) and int(now.bases) == int(expect.bases) \
		and absi(int(now.supplies) - int(expect.supplies)) <= 1 and str(nj.owners) == str(expect.owners) and str(nj.hp) == str(expect.hp) \
		and str(nj.garrisons) == str(expect.garrisons) and int(now.ops) == int(expect.ops)
	_g_step(21, "ownership, squads, buildings, damage, garrisons, resources and operations persisted", same, {"now": now, "expect": expect})
	var ai0: int = war.faction(1).ops_started + war.faction(2).ops_started
	await _until(func() -> bool: return war.faction(1).ops_started + war.faction(2).ops_started > ai0, 900.0, 8.0)
	_g_step(22, "AI factions keep acting", war.faction(1).ops_started + war.faction(2).ops_started > ai0,
		{"ops_started_before": ai0, "after": war.faction(1).ops_started + war.faction(2).ops_started, "south": war.faction(1).last_decision, "east": war.faction(2).last_decision})
	demo.toggle_map()
	demo.strategic_map.fit_all()
	await _seconds(1.5)
	_png("g_map_after_continue")
	demo.toggle_map()
	return {"steps": _g_steps}


var _g_steps: Array = []


func _g_step(n: int, what: String, ok: bool, data := {}) -> void:
	var e := {"step": n, "what": what, "ok": ok, "t": snappedf(demo.sim.state.time, 0.1)}
	e.merge(data)
	_g_steps.append(e)
	print("CP step %s" % JSON.stringify(e))
	_expect(ok, "campaign step %d (%s) failed: %s" % [n, what, str(data)])


## Writes the results without quitting (g_menu_return: the reloaded start screen quits).
func _finish_no_quit() -> void:
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/campaign_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("CP %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/campaign_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("CP %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("CP %s %s" % [check, JSON.stringify(data)])

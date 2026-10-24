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
	_finish()


# --- Helpers ---------------------------------------------------------------------------------------------------------

## A building placed through the construction controller facing `out` (its front, -Z, towards out); null when refused.
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

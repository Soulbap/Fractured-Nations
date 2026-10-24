## GAMEPLAY-02 checks: infantry combat, support weapons and tactical AI in the real game on ref_20km.
##
##   Godot.exe --path . --resolution 1600x900 --log-file c2.log res://scenes/game/world_ref_20km.tscn -- --combat02-test [--shots] [--only a_haugen,...] [--seeds=1,2,3]
##
## 02B weapon roles (b_*): squad composition and replacements, machine-gun suppression against a rifle, braced / moving
## handling, the MG emplacement's gunner slot, first person with the LMG, save / load and near / far of the equipment.
## 02C explosives (c_*): a grenade against open and covered soldiers, AI grenades in a close fight (no friends hit, rate
## limited), the grenadier's launcher disabling an MG emplacement in combat and the repair, first person (G, X, LMB), and a
## grenade in the air across a save and load.
## 02D (d_*): the machine gunner's post, soldiers getting clear of a grenade they see land, suppression felt in first
## person, the support weapons named in the RTS command panel, and pictures of a machine gun firing and a burst.
## 02E (e_*): the assault series with the standard squads (e_haugen ... like a_*), AI against AI off-screen with the new
## weapons, first person as the machine gunner inside a running operation, save / load in mid-assault, a large fight's cost.
## 02A assault scenarios (a_*): an ATTACK operation of North squads against South defenders, run once per world seed (the
## seed drives every aim error, spread and scatter), each recorded by a CombatDiag (positions, roles, stages, suppression,
## shots, hits, casualties, movement, cover, blocked moves). Each scenario states what it expects over all seeds.
## Prints "C2 <check> <json>", writes res://benchmarks/raw/combat02_test.json.
class_name Combat02SelfTest
extends AIStratSelfTest

var seeds: Array = [1, 2, 3]


func run(args: PackedStringArray) -> void:
	out_file = "combat02_test.json"
	prefix = "C2"
	diag_on = true
	for a in args:
		if a.begins_with("--seeds="):
			seeds = Array(a.trim_prefix("--seeds=").split(",")).map(func(x: String) -> int: return int(x))
	await _strat_setup(args, "res://docs/gameplay02")
	_log("setup", {"soldiers": default_soldiers.size(), "seeds": seeds})
	for key: String in ["a_haugen", "a_cover", "a_two", "a_three", "a_limited", "a_unfavourable", "a_fortified",
			"e_haugen", "e_cover", "e_two", "e_three", "e_limited", "e_unfavourable", "e_fortified"]:
		if _want(key):
			_log(key, await _assault_series(key))
	for key: String in ["b_compose", "b_suppress", "b_handling", "b_emplacement", "b_fps", "b_persist", "b_nearfar",
			"c_grenade", "c_ai_grenade", "c_launcher", "c_fps", "c_persist", "d_mg_post", "d_grenade_dodge", "d_fps_suppressed", "d_readability",
			"e_ai_war", "e_fps_operation", "e_persist", "e_perf"]:
		if _want(key):
			var r: Variant = await call("_" + key)
			# A check that stopped on a script error returns nothing: that is a failure, not a pass.
			_expect(r is Dictionary and not (r as Dictionary).is_empty(), "%s: the check did not finish (script error?)" % key)
			_log(key, r if r is Dictionary else {})
	await _end_strat()


# --- 02A: assault scenarios ---------------------------------------------------------------------------------------------

## Scenario table: objective, attacking squads, defending squads, start distance, approach ("hq": from North HQ, "wooded" /
## "open": the direction with the most / fewest trees on the last 300 m), attackers' rounds (0 = the weapon's full load),
## whether the defenders hold an outpost, and what the series must show.
const SCEN := {
	"a_haugen": {"obj": "Haugen", "att": 3, "def": 1, "dist": 520.0, "from": "hq", "want": "win"},
	"a_cover": {"obj": "Haugen", "att": 3, "def": 1, "dist": 480.0, "from": "wooded", "want": "win"},
	"a_two": {"obj": "Haugen", "att": 2, "def": 1, "dist": 450.0, "from": "hq", "want": "win_or_clean_withdraw"},
	"a_three": {"obj": "Elvetun", "att": 3, "def": 1, "dist": 500.0, "from": "open", "want": "win"},
	"a_limited": {"obj": "Haugen", "att": 3, "def": 1, "dist": 520.0, "from": "hq", "ammo": 60, "want": "win_or_clean_withdraw"},
	"a_unfavourable": {"obj": "Haugen", "att": 2, "def": 2, "dist": 480.0, "from": "hq", "want": "clean_withdraw_or_win"},
	"a_fortified": {"obj": "Haugen", "att": 3, "def": 1, "dist": 500.0, "from": "hq", "fort": true, "want": "win_or_clean_withdraw"},
}
## 02E: the same scenarios with the standard squads (a machine gunner and a grenadier each, on both sides).
static func scen(key: String) -> Dictionary:
	if key.begins_with("e_"):
		return (SCEN["a_" + key.substr(2)] as Dictionary).merged({"comp": "standard"}, true)
	return SCEN[key]


func _assault_series(key: String) -> Dictionary:
	var sc: Dictionary = scen(key)
	var seed0 := demo.sim.state.world_seed
	var runs: Array = []
	for s: int in seeds:
		demo.sim.state.world_seed = s
		var setup := await _assault_scene(sc)
		if setup.is_empty():
			_expect(false, "%s: scene could not be set up (seed %d)" % [key, s])
			continue
		var r := await _run_attack(setup, 900.0, 12.0)
		r.erase("op_obj")
		var one := {"seed": s, "owner": r.get("owner", -1), "outcome": r.get("op", {}).get("outcome", ""), "attackers_left": r.get("attackers_left", 0),
			"attackers": int(sc.att) * 8, "defenders_left": r.get("defenders_left", 0), "defenders": int(sc.def) * 8, "max_stall_s": r.get("max_assault_stall_s", 0.0),
			"stages": r.get("stages", []), "withdraw_why": r.get("withdraw_why", ""), "sim_s": r.get("warp", {}).get("sim_s", 0.0), "speed": r.get("warp", {}).get("speed", 0.0),
			"approach": setup.get("approach", {}), "diag": r.get("diag", {})}
		one["won"] = int(one.owner) == 0
		runs.append(one)
		print("C2 run %s seed %d: won=%s left %d/%d, defenders %d/%d, stall %.0f, %s" % [key, s, one.won, one.attackers_left, one.attackers, one.defenders_left,
			one.defenders, one.max_stall_s, one.withdraw_why])
		if setup.has("fort_ids"):
			_remove_structures(setup.fort_ids)
	demo.sim.state.world_seed = seed0
	return _judge(key, sc, runs)


## What a series must show. "win": most runs take the objective, losses below 60 %; no assault stalls beyond 160 s. A "clean withdrawal" is a
## withdrawal decided by the operation with at least 40 % of the attackers left (not wiped out, not stuck in the open).
func _judge(key: String, sc: Dictionary, runs: Array) -> Dictionary:
	var wins := 0
	var clean := 0
	var losses := 0.0
	var stall := 0.0
	for r: Dictionary in runs:
		var left_f := float(r.attackers_left) / float(r.attackers)
		losses += 1.0 - left_f
		stall = maxf(stall, float(r.max_stall_s))
		if r.won:
			wins += 1
		elif r.stages.has("withdraw") and left_f >= 0.4:
			clean += 1
	var n := maxi(runs.size(), 1)
	var out := {"wins": wins, "clean_withdrawals": clean, "runs": runs.size(), "avg_losses": snappedf(losses / n, 0.01), "max_stall_s": stall,
		"per_seed": runs.map(func(r: Dictionary) -> String: return "seed %d %s %d/%d left, def %d/%d, stall %.0f" % [r.seed, "WON" if r.won else ("withdrew" if r.stages.has("withdraw") else "-"),
			r.attackers_left, r.attackers, r.defenders_left, r.defenders, r.max_stall_s]), "detail": runs}
	match String(sc.want):
		"win":
			_expect(wins * 3 >= n * 2, "%s: objective taken in %d of %d runs" % [key, wins, n])
			_expect(losses / n <= 0.6, "%s: average losses %.0f %%" % [key, losses / n * 100.0])
		"win_or_clean_withdraw", "clean_withdraw_or_win":
			_expect(wins + clean == n, "%s: %d of %d runs neither took the objective nor withdrew cleanly" % [key, n - wins - clean, n])
	# An assault without progress commits everything after 75 s and breaks off after another 75 s (OpCoordination
	# progress_stall_s): 160 s is the longest a stuck assault may last.
	_expect(stall <= 160.0, "%s: an assault made no progress for %.0f s" % [key, stall])
	return out


## Sets up one scenario: the objective held by South (an outpost of fortifications for "fort"), North squads `dist` short of it.
func _assault_scene(sc: Dictionary) -> Dictionary:
	await _fresh()
	_pause_ai(true)
	# 02A measures the coordination with the rifle squads it was diagnosed with; the 02B weapons are measured separately.
	war.rules["squad_composition"] = String(sc.get("comp", "riflemen"))
	var obj := _obj(String(sc.obj))
	obj.owner = 1
	obj.capture_faction = -1
	obj.capture_progress = 0.0
	obj.contested = false
	obj.history.append([demo.sim.state.time, 1])
	var dir := _approach_dir(obj.position, float(sc.dist), String(sc.from))
	var out := {"approach": {"from": sc.from, "trees": _trees_along(obj.position, dir, 300.0)}}
	var target := obj
	var defs: Array = []
	if sc.get("fort", false):
		var f := _fort_outpost(obj.position + dir * 40.0, dir)
		if f.is_empty():
			return {}
		target = f.objective
		defs.append(f.squad)
		out["fort_ids"] = f.ids
		out["approach"]["forts"] = f.ids.size()
		await _warp(40.0, 8.0, 30.0)  # the garrison takes its slots
		out["approach"]["in_slots"] = _fort_count(f.squad)
	for i in int(sc.def) - defs.size():
		var d := _spawn(1, obj.position + Vector3(10 + i * 18, 0, -10 + i * 9))
		d.station_objective = obj.id
		defs.append(d)
	var start := _passable_near(obj.position + dir * float(sc.dist))
	var atk: Array = []
	for i in int(sc.att):
		var a := _spawn(0, start + Vector3(((i % 3) - 1) * 25.0, 0, (i / 3) * 25.0 + 25.0 * (1 if i > 0 else 0)))
		if int(sc.get("ammo", 0)) > 0:
			for id in a.members:
				var u := _u(id)
				u.mag = mini(u.mag, int(sc.ammo))
				u.reserve = maxi(int(sc.ammo) - u.mag, 0)
		atk.append(a)
	await _physics(10)
	out.merge({"obj": target, "atk": atk, "def": defs})
	return out


## Unit direction from the objective towards the attackers' start.
func _approach_dir(o: Vector3, dist: float, mode: String) -> Vector3:
	var hq := _obj("North HQ").position
	var to_hq := Vector3(hq.x - o.x, 0, hq.z - o.z).normalized()
	if mode == "hq":
		return to_hq
	var best := to_hq
	var best_v := -INF
	for k in 16:
		var d := to_hq.rotated(Vector3.UP, k * TAU / 16.0)
		var p := o + d * dist
		if not ws.routes.passable(p) or absf(k * TAU / 16.0 - PI) < PI / 4.0:  # not from behind the defenders' own lines
			continue
		var trees := _trees_along(o, d, 300.0)
		var v := float(trees) if mode == "wooded" else -float(trees)
		if v > best_v:
			best_v = v
			best = d
	return best


## Trunks within 20 m of the line from 60 m to `len` m out of o along d.
func _trees_along(o: Vector3, d: Vector3, length: float) -> int:
	var n := 0
	var buf := PackedFloat32Array()
	var x := 60.0
	while x < length:
		var c := o + d * x
		buf.clear()
		demo.structures.trunks_in_rect(Rect2(c.x - 20.0, c.z - 20.0, 40.0, 40.0), buf)
		n += buf.size() / 3
		x += 40.0
	return n


func _passable_near(p: Vector3) -> Vector3:
	return demo.on_ground(p.x, p.z, 0.0) if ws.routes.passable(p) else demo.sim.tactics.pos.nearest_valid(p, 80.0)


## A South outpost at `at` facing `out` (command post, two fighting positions, a steel guard tower) with a garrison of 8.
func _fort_outpost(at: Vector3, out: Vector3) -> Dictionary:
	var cp := CoreSelfTest.add_built(demo, &"command_post", at, out, 1)
	if cp == null:
		return {}
	var ids: Array = [cp.id]
	for e: Array in [[&"fighting_position", out, 26.0], [&"guard_tower_steel", out.rotated(Vector3.UP, 0.6), 22.0], [&"fighting_position", out.rotated(Vector3.UP, -0.7), 24.0]]:
		var st := CoreSelfTest.add_built(demo, e[0], cp.position + (e[1] as Vector3) * float(e[2]), e[1], 1)
		if st:
			ids.append(st.id)
	ws.sync_bases()
	var sq := _spawn(1, demo.sim.tactics.pos.nearest_valid(cp.position - out * 15.0, 20.0), 8)
	demo.sim.tactics.assign_garrison(sq, cp.base_id, SquadState.Owner.SQUAD)
	return {"objective": ws.base_objective(cp.base_id), "squad": sq, "ids": ids}


func _fort_count(sq: SquadState) -> int:
	var n := 0
	for id in sq.members:
		if _u(id) and _u(id).fort_slot != "":
			n += 1
	return n


func _remove_structures(ids: Array) -> void:
	for id in ids:
		if demo.sim.state.construction.structures.has(id):
			demo.sim.state.construction.remove(id)
	ws.sync_bases()


# --- 02B: weapon roles and the machine gun ------------------------------------------------------------------------------

## A screenshot (1920 x 1080 with --fullscreen) into docs/gameplay02.
func _png(shot_name: String) -> void:
	if not shots:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var path := "%s/%s.png" % [_shot_dir, shot_name]
	demo.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("C2 shot: ", path)


func _roles_of(sq: SquadState) -> Array:
	return Array(sq.members).map(func(id: int) -> String: return String(_u(id).role))


func _start_near(d: float) -> Vector3:
	return _near_point(_obj("North HQ").position, _obj("Haugen").position, d)


## A fresh squad gets the standard composition (machine gunner second, grenadier sixth, the rest riflemen) with the
## faction's machine-gunner look; a squad that lost its gunner gets the next recruit as one; the "riflemen" table arms
## everybody with rifles (the composition is the scenario's choice, data only).
func _b_compose() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var sq := _spawn(0, _start_near(300.0))
	var out := {"roles": _roles_of(sq)}
	var mg := _u(sq.members[1])
	out["mg"] = {"weapon": mg.weapon_id, "mag": mg.mag, "reserve": mg.reserve, "loadout": mg.loadout, "auto": mg.fire_auto}
	_expect(out.roles[1] == "machine_gunner" and out.roles[5] == "grenadier" and out.roles.count("rifleman") == 6, "b_compose: wrong roles %s" % str(out.roles))
	_expect(mg.weapon_id == &"lmg" and mg.mag == 100 and mg.reserve == 300 and mg.loadout == "NATO_mg", "b_compose: machine gunner not equipped %s" % str(out.mg))
	_expect(_u(sq.members[0]).weapon_id == &"rifle" and _u(sq.members[0]).loadout == "NATO_rifleman", "b_compose: rifleman not equipped")
	# The machine gunner falls; a replacement joins and takes the gun, the veterans keep their weapons.
	demo.sim.combat.kill(mg, -1)
	await _physics(3)
	var before := Array(sq.members).map(func(id: int) -> StringName: return _u(id).weapon_id)
	var ids := ws.spawn_recruits(war.faction(0), demo.sim.squads._centroid(sq), 1, sq.squad_name)
	for id in ids:
		spawned_ids.append(id)
	demo.sim.state.add_to_squad(sq.id, ids)
	demo.sim.combat.apply_composition(sq, ids)
	var rec := _u(ids[0])
	out["replacement"] = {"role": rec.role, "weapon": rec.weapon_id, "loadout": rec.loadout}
	_expect(rec.role == &"machine_gunner" and rec.weapon_id == &"lmg", "b_compose: the replacement did not take the machine gun %s" % str(out.replacement))
	var same := true
	for i in before.size():
		same = same and _u(sq.members[i]).weapon_id == before[i]
	_expect(same, "b_compose: a veteran was re-armed")
	# South and East wear their own machine-gunner loadouts.
	var s2 := _spawn(1, _start_near(360.0))
	var s3 := _spawn(2, _start_near(420.0))
	out["looks"] = [_u(s2.members[1]).loadout, _u(s3.members[1]).loadout]
	_expect(out.looks == ["RU_mg", "CN_mg"], "b_compose: faction machine-gunner loadouts %s" % str(out.looks))
	war.rules["squad_composition"] = "riflemen"
	var r := _spawn(0, _start_near(480.0))
	out["riflemen_table"] = Array(r.members).map(func(id: int) -> String: return String(_u(id).weapon_id))
	_expect(not out.riflemen_table.has("lmg"), "b_compose: the riflemen table still gave a machine gun")
	war.rules.erase("squad_composition")
	return out


## One soldier (rifleman, then machine gunner) fires at four soldiers 150 m away for 30 simulated seconds; the targets do
## not fire back and cannot die. Suppression is the time integral of the targets' mean suppression; the damage per hit
## must be the same (a 5.56 round is a 5.56 round: suppression is not bought with damage).
func _b_suppress() -> Dictionary:
	var out := {}
	for role: StringName in [&"rifleman", &"machine_gunner"]:
		await _fresh()
		war.rules["squad_composition"] = "riflemen"
		var at := _start_near(250.0)
		var dir := _obj("Haugen").position - at
		dir.y = 0.0
		dir = dir.normalized()
		var shooter := _spawn(0, at, 1)
		var u := _u(shooter.members[0])
		demo.sim.combat._equip_role(u, role)
		var tgt := _spawn(1, demo.sim.tactics.pos.nearest_valid(at + dir * 150.0, 20.0), 4)
		tgt.roe = SquadState.Roe.HOLD_FIRE
		_tough(tgt, 100000.0)
		await _physics(10)
		var st := {"shots": 0, "hits": 0, "dmg": 0.0, "supp_s": 0.0, "next": demo.sim.state.time, "ammo0": u.mag + u.reserve}
		var on_shot := func(shot: Dictionary) -> void:
			if int(shot.shooter) == u.id:
				st.shots += 1
				if int(shot.get("hit_unit", -1)) > 0:
					st.hits += 1
					st.dmg += float(shot.damage)
		demo.sim.state.shot_fired.connect(on_shot)
		demo.rts_camera.frame(at + dir * 75.0, 0.0, 140.0)
		var t0 := demo.sim.state.time
		await _warp(30.0, 4.0, 60.0, func() -> bool:
			var now := demo.sim.state.time
			if now >= st.next:
				st.next = now + 0.5
				var sum := 0.0
				for id in tgt.members:
					sum += _u(id).suppression_at(now)
				st.supp_s += sum / maxf(tgt.members.size(), 1) * 0.5
			return false)
		demo.sim.state.shot_fired.disconnect(on_shot)
		if shots and role == &"machine_gunner":
			demo.rts_camera.frame(u.position + dir * 20.0, 0.0, 45.0)
			await _seconds(0.6)
			_png("b_mg_firing_rts")
		out[String(role)] = {"shots": st.shots, "hits": st.hits, "dmg_per_hit": snappedf(st.dmg / maxf(st.hits, 1), 0.1), "supp_integral": snappedf(st.supp_s, 0.01),
			"ammo_used": st.ammo0 - (u.mag + u.reserve), "sim_s": snappedf(demo.sim.state.time - t0, 0.1)}
	var r: Dictionary = out.rifleman
	var m: Dictionary = out.machine_gunner
	_expect(int(r.shots) > 5 and int(m.shots) > 5, "b_suppress: too few shots %s" % str(out))
	_expect(float(m.supp_integral) >= 2.0 * float(r.supp_integral), "b_suppress: the MG does not suppress clearly more than a rifle (%s vs %s)" % [m.supp_integral, r.supp_integral])
	_expect(int(m.ammo_used) > int(r.ammo_used), "b_suppress: the MG did not fire more")
	if int(r.hits) > 0 and int(m.hits) > 0:
		_expect(absf(float(m.dmg_per_hit) - float(r.dmg_per_hit)) <= 12.0, "b_suppress: damage per hit differs (%s vs %s)" % [m.dmg_per_hit, r.dmg_per_hit])
	war.rules.erase("squad_composition")
	return out


## The LMG: braced (still for settle_s) it shoots tighter than a standing rifle; on the move much wider; a long reload.
func _b_handling() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var sq := _spawn(0, _start_near(300.0))
	var mg := _u(sq.members[1])
	var rf := _u(sq.members[0])
	var cs := demo.sim.combat
	var lmg := cs.weapon(&"lmg")
	var rifle := cs.weapon(&"rifle")
	var now := demo.sim.state.time
	mg.velocity = Vector3.ZERO
	mg.moved_at = now - 5.0
	mg.bloom = 0.0
	var braced := cs.current_spread(mg, lmg)
	mg.moved_at = now - 0.3
	var unsettled := cs.current_spread(mg, lmg)
	mg.velocity = Vector3(3.5, 0, 0)
	mg.moved_at = now
	var moving := cs.current_spread(mg, lmg)
	rf.velocity = Vector3(3.5, 0, 0)
	rf.bloom = 0.0
	var rifle_moving := cs.current_spread(rf, rifle)
	mg.velocity = Vector3.ZERO
	rf.velocity = Vector3.ZERO
	var out := {"lmg_braced": snappedf(braced, 0.001), "lmg_unsettled": snappedf(unsettled, 0.001), "lmg_moving": snappedf(moving, 0.001),
		"rifle_moving": snappedf(rifle_moving, 0.001), "rifle_still": snappedf(rifle.spread_base_deg, 0.001), "lmg_reload_s": lmg.reload_time, "rifle_reload_s": rifle.reload_time}
	_expect(braced < unsettled and braced < rifle.spread_base_deg, "b_handling: a braced LMG is not tighter %s" % str(out))
	_expect(moving > rifle_moving * 2.0, "b_handling: the LMG on the move is not clearly worse than a rifle %s" % str(out))
	mg.mag = 0
	cs.request_reload(mg.id)
	out["reload_until"] = snappedf(mg.reload_until - demo.sim.state.time, 0.1)
	_expect(absf(float(out.reload_until) - lmg.reload_time) < 0.1, "b_handling: the LMG reload does not take its time")
	war.rules.erase("squad_composition")
	return out


## A South garrison (standard squad) in a base with an MG emplacement: the machine gunner takes the gunner slot.
func _b_emplacement() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var hau := _obj("Haugen").position
	var dir := _obj("North HQ").position - hau
	dir.y = 0.0
	dir = dir.normalized()
	var at := demo.sim.tactics.pos.nearest_valid(hau + dir * 60.0, 30.0)
	var cp := CoreSelfTest.add_built(demo, &"command_post", at, dir, 1)
	var em: StructureState = CoreSelfTest.add_built(demo, &"mg_emplacement", cp.position + dir * 24.0, dir, 1) if cp else null
	var out := {"built": cp != null and em != null}
	_expect(cp != null and em != null, "b_emplacement: the base could not be built")
	if em == null:
		return out
	ws.sync_bases()
	var sq := _spawn(1, demo.sim.tactics.pos.nearest_valid(cp.position - dir * 15.0, 20.0), 8)
	demo.sim.tactics.assign_garrison(sq, cp.base_id, SquadState.Owner.SQUAD)
	var gunner := _u(sq.members[1])
	await _warp(60.0, 6.0, 40.0, func() -> bool: return gunner.fort_slot != "")
	var slot := demo.sim.tactics.pos.slot_by_key(gunner.fort_slot, 1)
	out["gunner"] = {"weapon": gunner.weapon_id, "slot": gunner.fort_slot, "role": slot.get("role", ""), "structure": slot.get("structure", -1)}
	_expect(gunner.fort_slot != "" and String(slot.get("role", "")) == "mg" and int(slot.get("structure", -1)) == em.id, "b_emplacement: the machine gunner is not on the MG slot %s" % str(out.gunner))
	if shots:
		demo.rts_camera.frame(em.position - dir * 6.0, 0.6, 26.0)
		await _seconds(1.5)
		_png("b_mg_emplacement_manned")
	_remove_structures([cp.id, em.id])
	war.rules.erase("squad_composition")
	return out


## First person with the machine gun: the viewmodel is the LMG (with the faction optic), a held trigger fires a stream from
## the 100-round box, the reload takes its time. The same CombatSim rules as the AI's.
func _b_fps() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var at := _start_near(300.0)
	var sq := _spawn(0, at)
	var mg := _u(sq.members[1])
	demo.rts_camera.frame(at, 0.0, 60.0)
	await _seconds(1.5)
	var body := await _possess(mg.id)
	await _seconds(1.0)
	var out := {"possessed": body != null and demo.game.mode == GameController.Mode.FPS}
	_expect(out.possessed, "b_fps: could not take over the machine gunner")
	if body == null:
		return out
	var items: Array = []
	if body.viewmodel and body.viewmodel.loadout:
		for it in body.viewmodel.loadout.items:
			if it.slot.begins_with("weapon"):
				items.append(it.id)
	out["viewmodel"] = items
	_expect(items.has("lmg") and not items.has("nato_rifle"), "b_fps: the first-person weapon is not the LMG %s" % str(items))
	await _fps_shot_at(body, body.camera.global_position + (-body.global_basis.z) * 80.0 + Vector3.DOWN * 1.0)
	var mag0 := mg.mag
	Input.action_press("fire")
	await _physics(60)
	if shots:
		_png("b_fps_lmg")
	Input.action_release("fire")
	await _physics(4)
	out["burst"] = mag0 - mg.mag
	_expect(int(out.burst) >= 8, "b_fps: holding the trigger did not fire a stream (%d rounds)" % out.burst)
	mg.mag = 0
	_press(KEY_R)
	await _physics(3)
	out["reload_s"] = snappedf(mg.reload_until - demo.sim.state.time, 0.1)
	_expect(mg.is_reloading() and float(out.reload_s) > 5.5, "b_fps: the LMG reload is not the LMG's (%s s)" % out.reload_s)
	await _leave()
	war.rules.erase("squad_composition")
	return out


## Role, weapon, rounds and look of every soldier survive a save to the test save folder and a load.
func _b_persist() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var sq := _spawn(0, _start_near(300.0))
	var mg := _u(sq.members[1])
	mg.mag = 37
	mg.reserve = 211
	var before := _equip_sig(sq)
	var path := demo.save_dir() + "/combat02_persist.sav"
	var err := demo.sim.state.save_file(path)
	mg.mag = 100
	mg.role = &"rifleman"
	mg.weapon_id = &"rifle"
	mg.loadout = "NATO_rifleman"
	demo.sim.state.load_file(path)
	await _physics(3)
	var after := _equip_sig(sq)
	var out := {"path": path, "saved": err == OK, "before": before, "after": after}
	_expect(err == OK and path.contains("test_saves"), "b_persist: the save did not go to the test save folder (%s)" % path)
	_expect(before == after, "b_persist: equipment differs after loading")
	war.rules.erase("squad_composition")
	return out


func _equip_sig(sq: SquadState) -> Array:
	var out := []
	for id in sq.members:
		var u := _u(id)
		out.append("%s/%s/%d/%d/%s" % [u.role, u.weapon_id, u.mag, u.reserve, u.loadout])
	return out


## The camera comes near (a body with the machine-gunner character and the LMG in its hands), goes far (no body) and back:
## the record and the look are the same every time.
func _b_nearfar() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var at := _start_near(300.0)
	var sq := _spawn(0, at)
	var mg := _u(sq.members[1])
	var out := {}
	var s0 := _equip_sig(sq)
	for k in 2:
		demo.rts_camera.frame(at, 0.0, 40.0)
		await _seconds(3.0)
		var body: SoldierBody = demo.sim.bodies.get(mg.id)
		var look := ""
		if body and body.character and body.character.loadout:
			look = body.character.loadout.id
		out["near%d" % k] = {"body": mg.has_body, "character": look}
		_expect(mg.has_body and look == "NATO_mg", "b_nearfar: near, the machine gunner has no body with the LMG %s" % str(out["near%d" % k]))
		if shots and k == 0:
			demo.rts_camera.frame(mg.position, 0.4, 7.0)
			await _seconds(1.2)
			_png("b_mg_gunner_near")
		demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
		await _seconds(3.0)
		out["far%d" % k] = {"body": mg.has_body}
		_expect(not mg.has_body, "b_nearfar: far away the machine gunner still has a body")
	out["record_same"] = _equip_sig(sq) == s0
	_expect(out.record_same, "b_nearfar: the record changed between near and far")
	war.rules.erase("squad_composition")
	return out


# --- 02C: grenades and the anti-structure launcher -----------------------------------------------------------------------

## Open ground near Haugen, the direction towards it and a point `d` further on.
func _field(d := 300.0) -> Dictionary:
	var at := _start_near(d)
	var dir := _obj("Haugen").position - at
	dir.y = 0.0
	return {"at": at, "dir": dir.normalized()}


func _burst_wait(e: Dictionary) -> Dictionary:
	var done := {}
	var on := func(x: Dictionary) -> void:
		if int(x.id) == int(e.id):
			done.merge(x)
	demo.sim.state.exploded.connect(on)
	await _warp(float(e.t) - demo.sim.state.time + 1.0, 4.0, 30.0, func() -> bool: return not done.is_empty())
	demo.sim.state.exploded.disconnect(on)
	return done


## The usual reset, and no grenade or rocket of an earlier check still in the air.
func _fresh_c() -> void:
	await _fresh()
	demo.sim.state.explosives.clear()


## A grenade thrown at three soldiers in the open and one behind a sandbag wall (camera far: abstract tier): the open ones
## are hurt by distance, the covered one barely; soldiers out of the radius are only suppressed; the thrower's count drops.
func _c_grenade() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "riflemen"
	var f := _field()
	var at: Vector3 = f.at
	var dir: Vector3 = f.dir
	var side := Vector3(-dir.z, 0.0, dir.x)
	var thrower := _spawn(0, at, 1)
	thrower.roe = SquadState.Roe.HOLD_FIRE
	var u := _u(thrower.members[0])
	var aim := at + dir * 22.0
	var tgt := _spawn(1, aim, 4)
	tgt.roe = SquadState.Roe.HOLD_FIRE
	_tough(tgt, 400.0)
	var ids := Array(tgt.members)
	var spots := [aim + side * 1.5, aim + side * 5.0, aim - side * 4.0, aim + dir * 16.0]
	for i in 4:
		var t := _u(tgt.members[i])
		t.position = demo.on_ground(spots[i].x, spots[i].z, 0.0)
		t.order = UnitState.Order.NONE
	var wall: StructureState = null
	var covered_id: int = ids[2]
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _physics(5)
	var hp := {}
	for id in ids:
		hp[id] = _u(id).health
	var n0 := u.grenades
	u.grenades = maxi(u.grenades, 1)
	n0 = u.grenades
	var res := demo.sim.combat.throw_grenade(u.id, aim)
	var out := {"thrown": res.get("ok", false), "reason": res.get("reason", ""), "wall": wall != null}
	_expect(res.get("ok", false), "c_grenade: the throw was refused (%s)" % res.get("reason", ""))
	if not res.get("ok", false):
		return out
	for i in ids.size():
		_u(ids[i]).position = demo.on_ground(spots[i].x, spots[i].z, 0.0)
	var e: Dictionary = res.e
	out["landed_off_m"] = snappedf(_flat(e.at, aim), 0.1)
	# The targets run from a grenade they see land (their own reaction); for the blast check they stand where the test
	# put them, relative to where it landed, at the moment it bursts.
	await _warp(float(e.t) - demo.sim.state.time - 0.1, 4.0, 20.0)
	var land: Vector3 = e.at
	spots = [land + side * 1.5, land + side * 5.0, land - side * 4.0, land + dir * 16.0]
	# A fighting position (1.08 m front wall towards the burst) round the third soldier; a 0.72 m sandbag ring would not
	# cover the chest of a man standing behind it.
	wall = CoreSelfTest.add_built(demo, &"fighting_position", land - side * 4.0, side, 1)
	out["wall"] = wall != null
	if wall:
		spots[2] = wall.position
	for i in ids.size():
		var tu := _u(ids[i])
		tu.position = demo.on_ground(spots[i].x, spots[i].z, 0.0)
		tu.velocity = Vector3.ZERO
		if tu.has_body and demo.sim.bodies.has(tu.id):
			(demo.sim.bodies[tu.id] as Node3D).global_position = tu.position
	var b := await _burst_wait(e)
	out["burst"] = not b.is_empty()
	var dmg := {}
	for id in ids:
		dmg[str(id)] = snappedf(float(hp[id]) - _u(id).health, 0.1) if _u(id) else -1.0
	out["damage"] = dmg
	out["hits"] = b.get("hits", [])
	out["grenades_left"] = u.grenades
	out["far_tier"] = not u.has_body
	_expect(not b.is_empty(), "c_grenade: no burst")
	_expect(u.grenades == n0 - 1, "c_grenade: the grenade count did not drop")
	var near_open := float(dmg[str(ids[0])])
	var covered := float(dmg[str(covered_id)])
	var outside := float(dmg[str(ids[3])])
	_expect(near_open >= 40.0, "c_grenade: the soldier next to the burst was not hurt (%.0f)" % near_open)
	_expect(wall != null, "c_grenade: the sandbags could not be placed")
	_expect(covered < near_open * 0.5, "c_grenade: cover did not protect (%.0f vs %.0f)" % [covered, near_open])
	_expect(outside == 0.0 and _u(ids[3]).suppression_at(demo.sim.state.time) > 0.0, "c_grenade: the soldier outside the radius was hurt or not suppressed")
	if wall:
		_remove_structures([wall.id])
	war.rules.erase("squad_composition")
	return out


## Grenades in a close firefight: a standard North squad holds 25 m from a South squad in fighting positions. Grenades are
## thrown by the AI at enemies it saw in their positions, never with a friend near the landing point, and a squad throws at
## most one per grenade_squad_gap_s. (Grenades during a moving assault are measured by the 02E scenarios.)
func _c_ai_grenade() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "standard"
	var hau := _obj("Haugen").position
	var dir := _obj("North HQ").position - hau
	dir.y = 0.0
	dir = dir.normalized()
	var base := demo.sim.tactics.pos.nearest_valid(hau + dir * 60.0, 30.0)
	var fp1 := CoreSelfTest.add_built(demo, &"fighting_position", base, dir, 1)
	var fp2 := CoreSelfTest.add_built(demo, &"fighting_position", base + dir.rotated(Vector3.UP, PI / 2) * 9.0, dir, 1)
	var defs := _spawn(1, base - dir * 6.0, 4)
	_tough(defs, 400.0)  # both sides must live long enough for the fight to come within throwing range
	demo.sim.tactics.order_tactic([defs.id], SquadState.Tactic.DEFEND, base, SquadState.Owner.PLAYER)
	await _warp(20.0, 6.0, 20.0)
	var atk := _spawn(0, demo.sim.tactics.pos.nearest_valid(base + dir * 25.0, 12.0), 8)
	_tough(atk, 400.0)
	demo.sim.tactics.order_tactic([atk.id], SquadState.Tactic.DEFEND, demo.sim.squads._centroid(atk), SquadState.Owner.PLAYER)
	var log: Array = []
	var on := func(e: Dictionary) -> void:
		if String(e.def) == "grenade":
			log.append({"t": snappedf(demo.sim.state.time, 0.1), "f": int(e.f), "src": int(e.src), "at": e.at})
	demo.sim.state.explosive_launched.connect(on)
	var bursts: Array = []
	var on_b := func(e: Dictionary) -> void:
		if String(e.def) == "grenade":
			bursts.append(e)
	demo.sim.state.exploded.connect(on_b)
	demo.rts_camera.frame(base + dir * 15.0, 0.5, 60.0)
	await _warp(90.0, 4.0, 90.0, func() -> bool:
		return _alive_count([defs]) == 0 or log.size() >= 3)
	if shots:
		await _seconds(0.5)
		_png("c_grenade_firefight")
	demo.sim.state.explosive_launched.disconnect(on)
	demo.sim.state.exploded.disconnect(on_b)
	var friendly := 0
	var enemy := 0
	for e: Dictionary in bursts:
		for h: Dictionary in e.get("hits", []):
			if int(h.f) == int(e.f):
				friendly += 1
			else:
				enemy += 1
	var gaps := []
	var by_f := {}
	for x: Dictionary in log:
		if by_f.has(x.f):
			gaps.append(snappedf(float(x.t) - float(by_f[x.f]), 0.1))
		by_f[x.f] = x.t
	var out := {"thrown": log.size(), "bursts": bursts.size(), "enemy_hits": enemy, "friendly_hits": friendly, "gaps_s": gaps,
		"defenders_left": _alive_count([defs]), "attackers_left": _alive_count([atk]), "brain": {"thrown": brain.grenades_thrown, "held": brain.grenade_holds}}
	_expect(log.size() >= 1, "c_ai_grenade: no grenade was thrown in the close fight %s" % str(out))
	_expect(friendly == 0, "c_ai_grenade: a grenade hurt a friend")
	var min_gap := 99.0
	for g in gaps:
		min_gap = minf(min_gap, float(g))
	_expect(gaps.is_empty() or min_gap >= brain.grenade_squad_gap_s - 1.5, "c_ai_grenade: grenades thrown too often (%s)" % str(gaps))
	_remove_structures([fp1.id if fp1 else -1, fp2.id if fp2 else -1])
	war.rules.erase("squad_composition")
	return out


## Anti-structure: a standard North squad (its grenadier carries two rockets) engages a small South base (command post and
## MG emplacement, two soldiers) from 150 m. The grenadier fires at an enemy structure where it saw the enemy, and the hit
## damages it through ConstructionState.damage. Then rockets from a soldier 60 m out (the same CombatSim call, aimed as the AI
## aims) disable the emplacement (two direct hits do; its firing slots go), and a repair restores it.
func _c_launcher() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "standard"
	var hau := _obj("Haugen").position
	var dir := _obj("North HQ").position - hau
	dir.y = 0.0
	dir = dir.normalized()
	var at := demo.sim.tactics.pos.nearest_valid(hau + dir * 60.0, 30.0)
	var cp := CoreSelfTest.add_built(demo, &"command_post", at - dir * 20.0, dir, 1)
	var em := CoreSelfTest.add_built(demo, &"mg_emplacement", at, dir, 1)
	var out := {"built": cp != null and em != null}
	_expect(em != null and cp != null, "c_launcher: the base could not be built")
	if em == null or cp == null:
		return out
	ws.sync_bases()
	var defs := _spawn(1, demo.sim.tactics.pos.nearest_valid(cp.position, 20.0), 2)
	_tough(defs, 600.0)
	demo.sim.tactics.assign_garrison(defs, cp.base_id, SquadState.Owner.SQUAD)
	await _warp(60.0, 6.0, 40.0, func() -> bool: return _u(defs.members[0]).fort_slot != "" and _u(defs.members[1]).fort_slot != "")
	out["slots"] = [_u(defs.members[0]).fort_slot, _u(defs.members[1]).fort_slot]
	var atk := _spawn(0, demo.sim.tactics.pos.nearest_valid(em.position + dir * 150.0, 25.0), 8)
	var gren := _u(atk.members[5])
	out["grenadier"] = {"role": gren.role, "sec": gren.sec_id, "rounds": gren.sec_ammo, "loadout": gren.loadout}
	_expect(gren.sec_id == &"launcher" and gren.sec_ammo == 2 and gren.loadout == "NATO_gren", "c_launcher: the grenadier is not equipped %s" % str(out.grenadier))
	var hp0 := em.health()
	var bursts: Array = []
	var on_b := func(e: Dictionary) -> void:
		if String(e.def) == "launcher":
			bursts.append(e)
	demo.sim.state.exploded.connect(on_b)
	demo.sim.tactics.order_tactic([atk.id], SquadState.Tactic.SUPPRESS, em.position, SquadState.Owner.PLAYER)
	demo.rts_camera.frame(em.position + dir * 40.0, 0.5, 80.0)
	await _warp(180.0, 4.0, 120.0, func() -> bool:
		return (gren.sec_ammo == 0 and demo.sim.state.explosives.is_empty()) or not gren.alive)
	demo.sim.state.exploded.disconnect(on_b)
	out["rockets"] = bursts.size()
	out["holds"] = brain.rocket_holds.duplicate()
	out["aimed_at"] = brain.events.filter(func(x: Dictionary) -> bool: return String(x.text).begins_with("launcher at")).map(func(x: Dictionary) -> String: return x.text)
	out["structures"] = {"cp": [cp.type_id, roundi(_flat(cp.position, em.position))], "em": em.id}
	out["rocket_impacts"] = bursts.map(func(e: Dictionary) -> String: return "%s %.1f m from it" % [e.get("blocker", "?"), _flat(e.at, em.position)])
	out["struct_hits"] = bursts.map(func(e: Dictionary) -> Array: return e.get("structures", []))
	out["emplacement"] = {"hp0": hp0, "hp": snappedf(em.health(), 0.1), "frac": snappedf(em.health_frac(), 0.01), "operational": em.is_operational()}
	var hit_ids := {}
	for e: Dictionary in bursts:
		for h: Dictionary in e.get("structures", []):
			hit_ids[int(h.id)] = true
	_expect(bursts.size() >= 1, "c_launcher: the grenadier never fired at an enemy structure")
	_expect(not hit_ids.is_empty(), "c_launcher: no rocket damaged a structure %s" % str(out.rocket_impacts))
	# The rest of the way through the same CombatSim call (any soldier with the launcher, aimed like the AI aims): rockets
	# until the emplacement is disabled, counted.
	var gsq := _spawn(0, demo.sim.tactics.pos.nearest_valid(em.position + dir * 60.0, 15.0), 1)
	gsq.roe = SquadState.Roe.HOLD_FIRE
	var gun := _u(gsq.members[0])
	_tough(gsq, 5000.0)
	gun.sec_id = &"launcher"
	gun.sec_active = false
	var spot := demo.sim.tactics.pos.nearest_valid(em.position + dir * 60.0, 15.0)
	gun.position = spot
	gun.velocity = Vector3.ZERO
	var extra := 0
	var per: Array = []
	while em.is_operational() and extra < 4:
		gun.sec_ammo = 1
		gun.sec_ready_at = 0.0
		gun.moved_at = -100.0
		var origin := CombatSim.eye_of(gun)
		var aim := brain._structure_aim(em)
		var r := demo.sim.combat.fire_secondary(gun.id, origin, (aim - origin).normalized())
		if not r.get("fired", false):
			break
		extra += 1
		var hit := await _burst_wait(r.e)
		per.append("%s %.1f m: %s" % [r.get("blocker", ""), _flat(r.e.at, em.position), ", ".join(hit.get("structures", []).map(func(h: Dictionary) -> String: return "%s -%d" % [h.type, roundi(h.dmg)]))])
	out["to_disable"] = {"ai_rockets_on_it": int(hit_ids.has(em.id)), "more": extra, "per_rocket": per, "frac": snappedf(em.health_frac(), 0.01)}
	out["emplacement"] = {"hp0": hp0, "hp": snappedf(em.health(), 0.1), "frac": snappedf(em.health_frac(), 0.01), "operational": em.is_operational()}
	_expect(not em.is_operational() and extra <= 3, "c_launcher: rockets did not disable the emplacement %s" % str(out.to_disable))
	if shots:
		demo.rts_camera.frame(em.position, 0.7, 30.0)
		await _seconds(1.5)
		_png("c_emplacement_disabled")
	# Repair restores it (the GAMEPLAY-01F path).
	var need := StructureHealth.repair_work(em)
	demo.sim.state.construction.start_repair(em, need, {}, 0.0)
	demo.sim.state.construction.add_work(em, need + 1.0)
	out["repaired"] = {"frac": snappedf(em.health_frac(), 0.01), "operational": em.is_operational()}
	_expect(em.is_operational() and em.health_frac() > 0.99, "c_launcher: the repair did not restore the emplacement %s" % str(out.repaired))
	_remove_structures([cp.id, em.id])
	war.rules.erase("squad_composition")
	return out


## First person as the grenadier: G throws (count down, the burst follows), X raises the launcher (the first-person model
## is the launcher, the HUD names it), LMB fires it, X lowers it again.
func _c_fps() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "standard"
	var f := _field()
	var sq := _spawn(0, f.at)
	var g := _u(sq.members[5])
	demo.rts_camera.frame(f.at, 0.0, 60.0)
	await _seconds(1.5)
	var body := await _possess(g.id)
	await _seconds(0.8)
	var out := {"possessed": body != null}
	_expect(body != null, "c_fps: could not take over the grenadier")
	if body == null:
		return out
	await _fps_shot_at(body, body.camera.global_position + Vector3(f.dir.x, 0, f.dir.z) * 25.0 + Vector3.DOWN * 1.6)
	var n0 := g.grenades
	var launched: Array = []
	var on := func(e: Dictionary) -> void: launched.append(e)
	demo.sim.state.explosive_launched.connect(on)
	_press(KEY_G)
	await _physics(3)
	out["grenade"] = {"before": n0, "after": g.grenades, "launched": launched.size()}
	_expect(g.grenades == n0 - 1 and launched.size() == 1, "c_fps: G did not throw %s" % str(out.grenade))
	await _seconds(4.5)
	if shots:
		_png("c_fps_grenade_burst")
	_press(KEY_X)
	await _physics(4)
	var held := body.viewmodel != null and body.viewmodel.held_scene != null
	out["launcher_raised"] = {"sec_active": g.sec_active, "viewmodel_launcher": held, "hud": (demo.hud._fps as FPSHud)._weapon.visible}
	_expect(g.sec_active and held, "c_fps: X did not raise the launcher %s" % str(out.launcher_raised))
	await _fps_shot_at(body, body.camera.global_position + Vector3(f.dir.x, 0, f.dir.z) * 120.0 + Vector3.DOWN * 3.0)
	if shots:
		_png("c_fps_launcher")
	var r0 := g.sec_ammo
	await _click_fire()
	await _physics(4)
	out["rocket"] = {"before": r0, "after": g.sec_ammo, "launched": launched.size()}
	_expect(g.sec_ammo == r0 - 1 and launched.size() == 2, "c_fps: LMB did not fire the launcher %s" % str(out.rocket))
	_press(KEY_X)
	await _physics(4)
	_expect(not g.sec_active, "c_fps: X did not lower the launcher")
	demo.sim.state.explosive_launched.disconnect(on)
	await _leave()
	war.rules.erase("squad_composition")
	return out


## A grenade in the air at a save bursts after the load; grenades and rockets carried are saved.
func _c_persist() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "standard"
	var f := _field()
	var sq := _spawn(0, f.at)
	sq.roe = SquadState.Roe.HOLD_FIRE
	var g := _u(sq.members[5])
	var tgt := _spawn(1, f.at + f.dir * 20.0, 2)
	tgt.roe = SquadState.Roe.HOLD_FIRE
	var res := demo.sim.combat.throw_grenade(g.id, f.at + f.dir * 20.0)
	_expect(res.get("ok", false), "c_persist: the throw was refused")
	g.sec_ammo = 1
	var path := demo.save_dir() + "/combat02_explosive.sav"
	var err := demo.sim.state.save_file(path)
	var keep := {"grenades": g.grenades, "sec": g.sec_ammo, "pending": demo.sim.state.explosives.size()}
	demo.sim.state.explosives.clear()
	g.grenades = 0
	g.sec_ammo = 0
	demo.sim.state.load_file(path)
	await _physics(2)
	var out := {"saved": err == OK, "before": keep, "after": {"grenades": g.grenades, "sec": g.sec_ammo, "pending": demo.sim.state.explosives.size()}}
	_expect(out.after == keep and int(keep.pending) == 1, "c_persist: explosives / equipment differ after loading %s" % str(out))
	var b := await _burst_wait(demo.sim.state.explosives[0] if not demo.sim.state.explosives.is_empty() else {"id": -1, "t": demo.sim.state.time})
	out["burst_after_load"] = not b.is_empty()
	_expect(not b.is_empty(), "c_persist: the grenade did not burst after loading")
	war.rules.erase("squad_composition")
	return out


# --- 02D: weapon-aware squad behaviour, reactions, readability ---------------------------------------------------------------

## A standard squad told to defend with a reported enemy in front: the machine gunner takes one of the most forward posts
## (the best field of fire), not whatever post the formation order gave it.
func _d_mg_post() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "standard"
	var f := _field()
	var sq := _spawn(0, f.at)
	var mg := _u(sq.members[1])
	await _physics(5)
	_report(0, f.at + f.dir * 160.0, 6)
	demo.sim.tactics.order_tactic([sq.id], SquadState.Tactic.DEFEND, f.at, SquadState.Owner.PLAYER)
	await _warp(20.0, 4.0, 20.0)
	var fwd := []
	for id in sq.members:
		var u := _u(id)
		if u.post_pos.is_finite():
			fwd.append([(u.post_pos - f.at).dot(f.dir), id])
	fwd.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var rank := -1
	for i in fwd.size():
		if fwd[i][1] == mg.id:
			rank = i
	var out := {"posts": fwd.size(), "mg_rank_forward": rank, "mg_forward_m": snappedf(float(fwd[rank][0]) if rank >= 0 else 0.0, 0.1),
		"spread_m": snappedf(float(fwd[0][0]) - float(fwd[-1][0]), 0.1) if fwd.size() > 1 else 0.0}
	_expect(fwd.size() >= 6 and rank >= 0 and rank <= 2, "d_mg_post: the machine gunner is not on a forward post %s" % str(out))
	war.rules.erase("squad_composition")
	return out


## Three soldiers who see a grenade land among them get clear before it bursts (and are hurt less than standing still -
## c_grenade measures the same blast on soldiers held in place: 147 / 48 hp at 1.6 / 5 m).
func _d_grenade_dodge() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "riflemen"
	var f := _field()
	var thrower := _spawn(0, f.at, 1)
	thrower.roe = SquadState.Roe.HOLD_FIRE
	var u := _u(thrower.members[0])
	var aim: Vector3 = f.at + f.dir * 20.0
	var tgt := _spawn(1, aim, 3)
	tgt.roe = SquadState.Roe.HOLD_FIRE
	_tough(tgt, 400.0)
	var ids := Array(tgt.members)
	demo.rts_camera.frame(aim, 0.5, 45.0)
	await _seconds(1.5)
	var d0 := {}
	var dodges0 := brain.grenade_dodges
	var res := demo.sim.combat.throw_grenade(u.id, aim)
	_expect(res.get("ok", false), "d_grenade_dodge: the throw was refused")
	if not res.get("ok", false):
		return {}
	var e: Dictionary = res.e
	for id in ids:
		d0[str(id)] = snappedf(_flat(_u(id).position, e.at), 0.1)
	if shots:
		await _warp(float(e.t) - demo.sim.state.time - 0.6, 1.0, 10.0)
		_png("d_grenade_dodge")
	var b := await _burst_wait(e)
	var d1 := {}
	var hurt := 0.0
	for h: Dictionary in b.get("hits", []):
		hurt += float(h.dmg)
	for id in ids:
		d1[str(id)] = snappedf(_flat(_u(id).position, e.at), 0.1)
	var gained := 0
	for k in d0:
		if float(d1[k]) > float(d0[k]) + 2.0:
			gained += 1
	var out := {"dodges": brain.grenade_dodges - dodges0, "dist_before": d0, "dist_at_burst": d1, "damage_total": snappedf(hurt, 0.1)}
	_expect(brain.grenade_dodges - dodges0 >= 2 and gained >= 2, "d_grenade_dodge: the soldiers did not get clear %s" % str(out))
	war.rules.erase("squad_composition")
	return out


## First person under machine-gun fire: the possessed soldier's record takes the suppression (only the HUD reads it), the
## status says Suppressed and the screen edges darken.
func _d_fps_suppressed() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "standard"
	var f := _field()
	var sq := _spawn(0, f.at, 2)
	var me := _u(sq.members[0])
	_tough(sq, 5000.0)
	var foe := _spawn(1, demo.sim.tactics.pos.nearest_valid(f.at + f.dir * 110.0, 15.0), 2)
	demo.sim.combat._equip_role(_u(foe.members[0]), &"machine_gunner")
	_tough(foe, 5000.0)
	demo.rts_camera.frame(f.at, 0.0, 50.0)
	await _seconds(1.0)
	var body := await _possess(me.id)
	_expect(body != null, "d_fps_suppressed: could not take over the soldier")
	if body == null:
		return {}
	await _fps_shot_at(body, demo.sim.squads._centroid(foe) + Vector3.UP * 1.2)
	var peak := 0.0
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 25.0 and peak < 0.45:
		await _physics(10)
		peak = maxf(peak, me.suppression_at(demo.sim.state.time))
	var fh: FPSHud = demo.hud._fps
	await _physics(2)
	var out := {"peak_suppression": snappedf(peak, 0.01), "vignette": snappedf(fh._vignette.modulate.a, 0.01), "status_visible": fh._state.visible}
	if shots:
		_png("d_fps_suppressed")
	_expect(peak >= 0.3 and fh._vignette.modulate.a > 0.1, "d_fps_suppressed: no suppression feedback in first person %s" % str(out))
	await _leave()
	war.rules.erase("squad_composition")
	return out


## The RTS command panel names the selection's support weapons; an RTS view of a machine gun firing and a burst.
func _d_readability() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "standard"
	var f := _field()
	var sq := _spawn(0, f.at)
	demo.rts.select_squads([sq.id])
	demo.rts_camera.frame(f.at, 0.5, 60.0)
	await _seconds(1.0)
	var txt: String = demo.hud.tactical_panel._settings.text
	var out := {"panel": txt}
	_expect(txt.contains("MG 1") and txt.contains("rockets 2") and txt.contains("grenades"), "d_readability: the panel does not list the support weapons: %s" % txt)
	if shots:
		_png("d_rts_support_panel")
		# The machine gun firing at a target 120 m away, and a grenade burst, seen from the tactical camera.
		var foe := _spawn(1, demo.sim.tactics.pos.nearest_valid(f.at + f.dir * 120.0, 15.0), 3)
		_tough(foe, 5000.0)
		_tough(sq, 5000.0)
		demo.rts_camera.frame(f.at + f.dir * 30.0, 0.4, 55.0)
		await _seconds(6.0)
		_png("d_rts_mg_tracers")
		var g := _u(sq.members[2])
		g.grenades = 1
		var res := demo.sim.combat.throw_grenade(g.id, f.at + f.dir * 25.0)
		if res.get("ok", false):
			demo.rts_camera.frame(res.e.at, 0.5, 40.0)
			await _warp(float(res.e.t) - demo.sim.state.time + 0.15, 1.0, 10.0)
			_png("d_rts_grenade_burst")
			await _seconds(1.5)
			_png("d_rts_grenade_smoke")
	demo.rts.select([])
	war.rules.erase("squad_composition")
	return out


# --- 02E: integrated scenarios ---------------------------------------------------------------------------------------------

## AI against AI with the camera far away (abstract tier): South's AI attacks Haugen, held by a North squad, with three
## standard squads (its own operation, not the player's); the fight runs off-screen through the same records - shots,
## casualties, grenades, rockets and bursts happen, the operation ends, the records stay consistent. (The free-running war
## of --ai-strat-test l_war was measured separately before and after this work: same frame times and the same two failures.)
func _e_ai_war() -> Dictionary:
	await _fresh_c()
	war.rules["squad_composition"] = "standard"
	var hau := _obj("Haugen")
	hau.owner = 0
	hau.capture_faction = -1
	hau.capture_progress = 0.0
	hau.history.append([demo.sim.state.time, 0])
	var d := _spawn(0, hau.position + Vector3(10, 0, -10))
	d.station_objective = hau.id
	var start := _near_point(hau.position, _obj("South HQ").position, 500.0)
	var atk: Array = []
	for i in 3:
		atk.append(_spawn(1, start + Vector3((i - 1) * 25.0, 0, 25.0 * (1 if i > 0 else 0))))
	await _physics(10)
	var op := ws.start_operation(1, OperationState.Type.ATTACK, atk.map(func(q: SquadState) -> int: return q.id), hau.id, Vector3.INF, false)
	_expect(op != null, "e_ai_war: South's attack could not start")
	if op == null:
		return {}
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	var c0 := {"nades": brain.grenades_thrown, "rockets": brain.rockets_fired, "bursts": demo.sim.combat.detonated, "dodges": brain.grenade_dodges}
	var count := {"shots": 0, "killed": 0, "body_shots": 0}
	var on_shot := func(_s: Dictionary) -> void: count.shots += 1
	var on_died := func(_u: UnitState) -> void: count.killed += 1
	demo.sim.state.shot_fired.connect(on_shot)
	demo.sim.state.unit_died.connect(on_died)
	var w := await _warp(900.0, 12.0, 200.0, func() -> bool:
		for sq: SquadState in atk + [d]:
			for id in sq.members:
				if _u(id) and _u(id).has_body:
					count.body_shots += 1
		return not op.is_active())
	demo.sim.state.shot_fired.disconnect(on_shot)
	demo.sim.state.unit_died.disconnect(on_died)
	var out := {"op": {"phase": op.phase_name(), "outcome": op.outcome, "stages": op.stage_name()}, "owner": hau.owner, "warp": w,
		"combat": {"shots": count.shots, "killed": count.killed, "grenades": brain.grenades_thrown - int(c0.nades), "rockets": brain.rockets_fired - int(c0.rockets),
			"bursts": demo.sim.combat.detonated - int(c0.bursts), "grenade_dodges": brain.grenade_dodges - int(c0.dodges)},
		"abstract_tier": count.body_shots == 0, "consistency": _consistency().count}
	_expect(count.shots > 100 and count.killed > 0, "e_ai_war: no real fight happened %s" % str(out.combat))
	_expect(not op.is_active(), "e_ai_war: South's attack did not end")
	_expect(count.body_shots == 0, "e_ai_war: soldiers had bodies (the fight was not off-screen)")
	_expect(_consistency().count == 0, "e_ai_war: records inconsistent")
	war.rules.erase("squad_composition")
	return out


## First person in a running operation (scenario H): North's standard squads attack Haugen with the camera near; when the
## assault goes in the player takes over the support squad's machine gunner, fires a long burst at the objective, hands
## him back; the operation carries on and its records stay consistent.
func _e_fps_operation() -> Dictionary:
	war.rules["squad_composition"] = "standard"
	var sc := await _assault_scene(SCEN.a_haugen.merged({"comp": "standard"}))
	war.rules["squad_composition"] = "standard"
	var obj: ObjectiveState = sc.obj
	var ids := (sc.atk as Array).map(func(q: SquadState) -> int: return q.id)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, obj.id, Vector3.INF, true)
	_expect(op != null, "e_fps_operation: the attack could not start")
	if op == null:
		return {}
	demo.rts_camera.frame(obj.position, 0.0, 120.0)
	await _warp(400.0, 8.0, 160.0, func() -> bool: return op.stage >= OperationState.Stage.ASSAULT or not op.is_active())
	var support: SquadState = null
	for sid in op.roles:
		if int(op.roles[sid]) == SquadState.OpRole.SUPPORT:
			support = demo.sim.state.get_squad(sid)
	var out := {"stage": op.stage_name()}
	_expect(support != null, "e_fps_operation: no fire support to take over")
	if support == null:
		return out
	var gunner: UnitState = null
	for id in support.members:
		if _u(id).weapon_id == &"lmg":
			gunner = _u(id)
	_expect(gunner != null, "e_fps_operation: the support squad has no machine gunner")
	if gunner == null:
		return out
	demo.rts_camera.frame(gunner.position, 0.0, 40.0)
	await _seconds(2.0)
	var body := await _possess(gunner.id)
	_expect(body != null, "e_fps_operation: could not take over the machine gunner")
	if body == null:
		return out
	await _fps_shot_at(body, obj.position + Vector3.UP * 1.0)
	# A loaded gun and a fresh trigger pull (the trigger re-arms after a release).
	if gunner.mag <= 0 and not gunner.is_reloading():
		demo.sim.combat.request_reload(gunner.id)
	await _warp(8.0, 1.0, 12.0, func() -> bool: return not gunner.is_reloading() and gunner.mag > 0)
	Input.action_release("fire")
	await _physics(3)
	out["gun_before"] = {"mag": gunner.mag, "reserve": gunner.reserve, "reloading": gunner.is_reloading()}
	var r0 := gunner.mag + gunner.reserve
	Input.action_press("fire")
	await _physics(120)
	if shots:
		_png("e_fps_mg_in_operation")
	Input.action_release("fire")
	await _physics(5)
	out["player_rounds"] = r0 - (gunner.mag + gunner.reserve)
	out["in_operation_while_possessed"] = support.op_id == op.id
	await _leave()
	await _physics(10)
	out["gunner_ai_again"] = not gunner.player_controlled
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _warp(500.0, 12.0, 160.0, func() -> bool: return not op.is_active())
	out["end"] = {"phase": op.phase_name(), "outcome": op.outcome, "owner": obj.owner, "consistency": _consistency().count}
	_expect(int(out.player_rounds) >= 15, "e_fps_operation: the player's burst did not fire (%d rounds)" % out.player_rounds)
	_expect(not gunner.player_controlled, "e_fps_operation: the gunner was not handed back")
	_expect(not op.is_active() or op.stage >= OperationState.Stage.ASSAULT, "e_fps_operation: the operation stopped after the possession")
	_expect(_consistency().count == 0, "e_fps_operation: records inconsistent")
	war.rules.erase("squad_composition")
	return out


## Save in the middle of an assault with the new weapons (grenades and rockets carried, perhaps one in the air) to the
## test save folder, load, compare, and let the operation finish.
func _e_persist() -> Dictionary:
	war.rules["squad_composition"] = "standard"
	var sc := await _assault_scene(SCEN.a_haugen.merged({"comp": "standard"}))
	war.rules["squad_composition"] = "standard"
	var obj: ObjectiveState = sc.obj
	var ids := (sc.atk as Array).map(func(q: SquadState) -> int: return q.id)
	var op := ws.start_operation(0, OperationState.Type.ATTACK, ids, obj.id, Vector3.INF, true)
	if op == null:
		_expect(false, "e_persist: the attack could not start")
		return {}
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _warp(500.0, 12.0, 160.0, func() -> bool: return op.stage >= OperationState.Stage.ASSAULT or not op.is_active())
	await _warp(25.0, 6.0, 30.0)
	var sig := func() -> Array:
		var a: Array = [_op_sig(op) if war.operation(op.id) else "-", demo.sim.state.explosives.size()]
		for sq: SquadState in sc.atk + sc.def:
			if demo.sim.state.get_squad(sq.id):
				a.append(_equip_sig(demo.sim.state.get_squad(sq.id)))
		return a
	var before: Array = sig.call()
	var path := demo.save_dir() + "/combat02_assault.sav"
	var err := demo.sim.state.save_file(path)
	demo.sim.state.load_file(path)
	await tree.physics_frame
	war = demo.sim.state.war
	ws = demo.sim.war
	op = war.operation(op.id)
	var after: Array = sig.call()
	var out := {"saved": err == OK, "path": path, "same": before == after, "explosives_in_air": before[1]}
	_expect(err == OK and path.contains("test_saves"), "e_persist: the save did not go to the test save folder")
	_expect(before == after, "e_persist: the assault differs after loading")
	if op:
		await _warp(500.0, 12.0, 160.0, func() -> bool: return not op.is_active())
		out["end"] = {"phase": op.phase_name(), "outcome": op.outcome}
	_expect(_consistency().count == 0, "e_persist: records inconsistent after loading")
	war.rules.erase("squad_composition")
	return out


## Cost of a large fight with the new weapons: four standard squads against four 150 m apart, 60 simulated seconds far
## (abstract tier) and 60 near (bodies, effects), and the same far with rifle squads for comparison: CombatBrain per
## update and its parts, the slowest burst, frame times.
func _e_perf() -> Dictionary:
	var out := {}
	for mode: String in ["far", "near", "far_riflemen"]:
		await _fresh_c()
		war.rules["squad_composition"] = "riflemen" if mode.ends_with("riflemen") else "standard"
		var f := _field(350.0)
		var side := Vector3(-f.dir.z, 0.0, f.dir.x)
		var sqs: Array = []
		for i in 4:
			sqs.append(_spawn(0, demo.sim.tactics.pos.nearest_valid(f.at + side * (i - 1.5) * 30.0, 15.0)))
			sqs.append(_spawn(1, demo.sim.tactics.pos.nearest_valid(f.at + f.dir * 150.0 + side * (i - 1.5) * 30.0, 15.0)))
		for sq: SquadState in sqs:
			_tough(sq, 300.0)
		demo.rts_camera.frame(f.at + f.dir * 75.0 if mode == "near" else Vector3(9000, 0, 9000), 0.4, 110.0 if mode == "near" else 150.0)
		await _seconds(2.0)
		demo.sim.brain.reset_stats()
		demo.sim.combat.blast_usec_max = 0
		var b0 := demo.sim.combat.detonated
		var ms := PackedFloat32Array()
		var t0 := demo.sim.state.time
		TimeCompression.apply(2.0, 16)
		while demo.sim.state.time - t0 < 60.0:
			var t := Time.get_ticks_usec()
			await tree.process_frame
			ms.append((Time.get_ticks_usec() - t) / 1000.0)
		TimeCompression.reset()
		var sorted := Array(ms)
		sorted.sort()
		var bs := demo.sim.brain.summary()
		out[mode] = {"soldiers": 64, "brain_update_us_avg": bs.update_us_avg, "brain_update_us_max": bs.update_us_max, "ai_shots": bs.ai_shots,
			"bursts": demo.sim.combat.detonated - b0, "blast_us_max": demo.sim.combat.blast_usec_max,
			"frame_ms_avg": snappedf(float(sorted.reduce(func(a, b): return a + b, 0.0)) / maxf(sorted.size(), 1.0), 0.01),
			"frame_ms_p99": snappedf(sorted[int(sorted.size() * 0.99)], 0.1), "frame_ms_max": snappedf(sorted[-1], 0.1),
			"brain_prof_us_per_frame": bs.prof_us_per_frame}
		if shots and mode == "near":
			_png("e_large_fight_near")
		_expect(int(out[mode].ai_shots) > 50, "e_perf(%s): the fight did not happen" % mode)
		_expect(int(out[mode].blast_us_max) < 5000, "e_perf(%s): a burst took %d us" % [mode, out[mode].blast_us_max])
	war.rules.erase("squad_composition")
	return out

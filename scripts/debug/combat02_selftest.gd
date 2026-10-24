## GAMEPLAY-02 checks: infantry combat, support weapons and tactical AI in the real game on ref_20km.
##
##   Godot.exe --path . --resolution 1600x900 --log-file c2.log res://scenes/game/world_ref_20km.tscn -- --combat02-test [--shots] [--only a_haugen,...] [--seeds=1,2,3]
##
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
	for key: String in ["a_haugen", "a_cover", "a_two", "a_three", "a_limited", "a_unfavourable", "a_fortified"]:
		if _want(key):
			_log(key, await _assault_series(key))
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


func _assault_series(key: String) -> Dictionary:
	var sc: Dictionary = SCEN[key]
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


## What a series must show. "win": most runs take the objective, none stalls, losses below 60 %. A "clean withdrawal" is a
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
	_expect(stall <= 120.0, "%s: an assault made no progress for %.0f s" % [key, stall])
	return out


## Sets up one scenario: the objective held by South (an outpost of fortifications for "fort"), North squads `dist` short of it.
func _assault_scene(sc: Dictionary) -> Dictionary:
	await _fresh()
	_pause_ai(true)
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

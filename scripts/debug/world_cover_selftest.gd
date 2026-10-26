## WORLD-COVER-01 checks in the real game on ref_20km with the natural cover layer (worlds/cover/ref_20km.cover.json):
##
##   Godot.exe --path . --fullscreen --log-file wc.log res://scenes/game/world_ref_20km.tscn -- --scenario=dev --world-cover-test [--shots] [--only ...]
##   (the same with --no-natural-cover gives the "before" numbers of the combat scenarios)
##
## v_kinds    every cover kind of the layer near the test area, close up from the side and from the RTS camera
## b_ballistic shots through each kind from eight directions at standing / crouched / prone heights: blocked by the object
##            (LineOfFire), and CombatBrain's cover test behind it against a threat on either side (directional protection)
## a_open     8 v 8 on the test area's open ground (sparse cover), 45 s: exposure, cover objects used, stuck, shots stopped
## b_forest   8 v 8 among the trees, logs and root plates, 45 s: the same numbers
## c_road     a squad crosses a road 140 m from an enemy that fires on it: time to cross, halts, stuck
## d_two_threats a squad defends near a stone wall against two enemy teams from two directions: its posts against each threat
## e_modes    AWARE / COMBAT / STEALTH move 120 m past a reported enemy: where they end (protected), time
## With --no-natural-cover the same scenarios give the "before" numbers (compare benchmarks/raw/world_cover_test*.json).
## Prints "WC <check> <json>", writes res://benchmarks/raw/world_cover_test.json.
class_name WorldCoverSelfTest
extends Qol011SelfTest

const CHECKSWC: Array[String] = ["v_kinds", "b_ballistic", "a_open", "b_forest", "c_road", "d_two_threats", "e_modes", "n_vehicles", "q_perf", "z_fight"]
var _layer: Dictionary = {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/world_cover01"
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKSWC)
	SoldierBody.require_mouse_capture = false
	tree.create_timer(1800.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CoverLayer.path(demo.config.world_name)))
	_layer = j.records if j is Dictionary else {}
	results["layer_records"] = _layer.size()
	results["natural_cover"] = CoverLayer.enabled()
	_cs = CombatScenario.new(demo)
	_site = _cs.find_site()
	_tcam = Camera3D.new()
	_tcam.fov = 50.0
	_tcam.far = 4000.0
	demo.add_child(_tcam)
	if demo.hud:
		demo.hud.visible = false
	_quiet_area(_site.def, 2500.0)
	for n in CHECKSWC:
		if only.has(n):
			_log(n, await call("_" + n))
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("WC %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	CoreDemo.apply_time_scale(1.0)
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/world_cover_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("WC %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


## The layer's objects of mesh id near p, nearest first: [{pos, yaw, scale}].
func _objects(id: int, near: Vector3, limit := 4) -> Array:
	var out: Array = []
	for rec: Dictionary in _layer.values():
		if int(rec.mesh) != id:
			continue
		var t: Array = rec.transform
		var pos := Vector3(t[9], t[10], t[11])
		out.append({"pos": pos, "yaw": atan2(-float(t[2]), float(t[0])), "scale": Vector3(t[0], t[1], t[2]).length(), "d": Vector2(pos.x - near.x, pos.z - near.z).length()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return out.slice(0, limit)


func _v_kinds() -> Dictionary:
	var out := {}
	for name: String in CoverLayer.IDS:
		var id: int = CoverLayer.IDS[name]
		var objs := _objects(id, _site.def, 12)
		out[name] = objs.size()
		if objs.is_empty():
			continue
		# The one with the fewest trunks round it (a clear view of it), the camera on its open side.
		var best: Dictionary = objs[0]
		var best_n := 1 << 30
		for o: Dictionary in objs:
			var n := _trunks_near(o.pos, 9.0)
			if n < best_n:
				best_n = n
				best = o
		var p: Vector3 = best.pos
		demo.rts_camera.frame(p, 0.6, 25.0)
		await _seconds(4.0)
		var yaw := _open_side(p, float(best.yaw) + PI * 0.5)
		_cam(p + Vector3.UP * 0.7, 7.5, yaw, 9.0)
		await _seconds(1.5)
		_png("kind_%s_side" % name)
		_tcam.current = false
		demo.rts_camera.camera.make_current()
		demo.rts_camera.frame(p, yaw, 22.0)
		await _seconds(2.0)
		_png("kind_%s_rts" % name)
	return out


func _trunks_near(p: Vector3, r: float) -> int:
	var n := 0
	var st := demo.sim.structures
	var c := VegetationChunk.cell_of(p, 128.0)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for t: Array in st._trees_in(c + Vector2i(dx, dz)):
				if Vector2(t[0] - p.x, t[1] - p.z).length() < r and int(t[3]) <= 8:
					n += 1
	return n


## Of eight headings round p, the one (closest to `prefer`) whose camera spot 7.5 m out has the fewest trunks near it.
func _open_side(p: Vector3, prefer: float) -> float:
	var best := prefer
	var best_score := INF
	for k in 8:
		var a := prefer + k * TAU / 8.0
		var q := p + Vector3(sin(a), 0, cos(a)) * 7.5
		var score := _trunks_near(q, 4.0) * 10.0 + absf(wrapf(a - prefer, -PI, PI))
		if score < best_score:
			best_score = score
			best = a
	return best


func _b_ballistic() -> Dictionary:
	var out := {}
	var line := demo.sim.combat.line
	for name: String in CoverLayer.IDS:
		var id: int = CoverLayer.IDS[name]
		var objs := _objects(id, _site.def, 3)
		if objs.is_empty():
			continue
		var row := {"stand": 0, "crouch": 0, "prone": 0, "n": 0, "protect_far_side": 0, "protect_near_side": 0, "probes": 0, "terrain": 0}
		for o: Dictionary in objs:
			var p: Vector3 = o.pos
			demo.rts_camera.frame(p, 0.6, 40.0)
			await _seconds(1.0)
			for k in 8:
				var a := k * TAU / 8.0
				var dir := Vector3(cos(a), 0, sin(a))
				var behind := p - dir * (2.0 + float(o.scale))
				var gy: float = demo.sim.terrain.data.get_height(behind)
				# A shooter level with the target's ground (eye 1.5 m), 40 m off: the object's own effect, not the hill's.
				var from := p + dir * 40.0
				from.y = gy + 1.5
				row.n += 1
				for h: Array in [["stand", 1.45], ["crouch", 0.7], ["prone", 0.25]]:
					var tr := line.trace(from, Vector3(behind.x, gy + float(h[1]), behind.z), -1, false)
					if tr.blocker == "tree" and float(tr.distance) < 41.0:
						row[h[0]] += 1
					elif tr.blocker == "terrain":
						row.terrain += 1
				# The soldier's own cover test behind the object, against a threat on this side and on the other side.
				var u: UnitState = demo.sim.state.soldiers()[0]
				var spot := Vector3(behind.x, gy, behind.z)
				row.probes += 1
				if demo.sim.brain._evaluate_spot(u, spot, from).protected:
					row.protect_far_side += 1
				if demo.sim.brain._evaluate_spot(u, spot, p - dir * 40.0).protected:
					row.protect_near_side += 1
		out[name] = row
	return out


## No soldier of the war's own squads within r of p (the AI factions' patrols and garrisons would join the scenarios), the
## AI's decisions paused (CombatScenario.reset): the scenarios see only their own soldiers.
func _quiet_area(p: Vector3, r: float) -> void:
	var gone := 0
	for u: UnitState in demo.sim.state.soldiers():
		if Vector2(u.position.x - p.x, u.position.z - p.z).length() < r and not _cs.unit_ids.has(u.id):
			demo.sim.state.remove_unit(u.id)
			gone += 1
	_cs.reset()
	results["quiet_area_removed"] = gone


# --- Combat scenarios -------------------------------------------------------------------------------------------------------

## Nearest layer object (any kind) to p: distance (INF without).
func _cover_dist(p: Vector3) -> float:
	var best := INF
	for rec: Dictionary in _layer.values():
		var t: Array = rec.transform
		best = minf(best, Vector2(float(t[9]) - p.x, float(t[11]) - p.z).length())
	return best


## A place of the test area with a cover object: open ground (forest cover of the grid below 0.2) or forest (above 0.6), nearest
## the site.
func _place_for(forest: bool) -> Vector3:
	var routes: StrategicRoutes = demo.sim.war.routes
	var best := Vector3.INF
	var best_d := INF
	for rec: Dictionary in _layer.values():
		var t: Array = rec.transform
		var p := Vector3(t[9], t[10], t[11])
		var c := routes.cover_at(p)
		if (forest and c < 0.6) or (not forest and c > 0.2):
			continue
		var d := Vector2(p.x - _site.def.x, p.z - _site.def.z).length()
		if d < best_d:
			best_d = d
			best = p
	return best


var _shots_cover := 0
var _shots_tree := 0
var _shots_total := 0


func _on_shot(shot: Dictionary) -> void:
	_shots_total += 1
	if shot.blocker == "tree":
		_shots_tree += 1
		var e: Vector3 = shot.end
		if _cover_dist(e) < 4.5:
			_shots_cover += 1


## Samples the soldiers of `squads` twice a second for `seconds` of simulation: exposure to the threat each one knows (the
## soldier's own cover test at his position), soldiers within 3 m of a layer object, blocked soldiers.
func _watch(squads: Array, seconds: float) -> Dictionary:
	var m := {"samples": 0, "threatened": 0, "protected": 0, "at_cover_object": 0, "blocked": 0, "in_cover_state": 0}
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(2.0)
	while demo.sim.state.time - t0 < seconds:
		await _physics(15)
		for sq: SquadState in squads:
			for id in sq.members:
				var u := demo.sim.state.get_unit(id)
				if u == null or not u.alive:
					continue
				m.samples += 1
				var threat := u.target_last_pos if u.target_last_pos.is_finite() and demo.sim.state.time - u.target_seen_at < 6.0 else u.threat_pos
				if threat.is_finite():
					m.threatened += 1
					if demo.sim.brain._evaluate_spot(u, u.position, threat).protected:
						m.protected += 1
				if u.cover_pos.is_finite() and _cover_dist(u.cover_pos) < 3.5:
					m.at_cover_object += 1
				if u.move_state == UnitState.MoveState.BLOCKED:
					m.blocked += 1
				if u.tactic == UnitState.Tactic.IN_COVER:
					m.in_cover_state += 1
	CoreDemo.apply_time_scale(1.0)
	m["protected_share"] = snappedf(float(m.protected) / maxi(int(m.threatened), 1), 0.01)
	m["at_cover_share"] = snappedf(float(m.at_cover_object) / maxi(int(m.samples), 1), 0.01)
	return m


func _clear_squads(squads: Array) -> void:
	for sq: SquadState in squads:
		for id in sq.members:
			demo.sim.state.remove_unit(id)
	demo.sim.state.war.contacts.clear()
	demo.sim.war.intel.rebuild()
	await _physics(10)


func _tough(squads: Array) -> void:
	for sq: SquadState in squads:
		for id in sq.members:
			demo.sim.state.get_unit(id).max_health = 400.0
			demo.sim.state.get_unit(id).health = 400.0


func _fight(center: Vector3, tag: String) -> Dictionary:
	if not center.is_finite():
		failures.append("%s: no place in the test area" % tag)
		return {}
	# The heading across the place with a clear sight line between the two sides (eye to chest, 100 m).
	var dir := Vector3(1, 0, 0.3).normalized()
	var line := demo.sim.combat.line
	for k in 12:
		var d := Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0))
		var pa := demo.on_ground(center.x - d.x * 50.0, center.z - d.z * 50.0, 0.0)
		var pb := demo.on_ground(center.x + d.x * 50.0, center.z + d.z * 50.0, 0.0)
		if line.sight(pa + Vector3.UP * 1.6, pb + Vector3.UP * 1.1).visible:
			dir = d
			break
	var a := _cs.spawn(0, center - dir * 50.0, dir, 8, tag + "A")
	var b := _cs.spawn(1, center + dir * 50.0, -dir, 8, tag + "B")
	for sq: SquadState in [a, b]:
		demo.sim.squads.order_hold([sq.id])
	_tough([a, b])
	_shots_cover = 0
	_shots_tree = 0
	_shots_total = 0
	if not demo.sim.state.shot_fired.is_connected(_on_shot):
		demo.sim.state.shot_fired.connect(_on_shot)
	demo.rts_camera.frame(center, 0.6, 70.0)
	await _seconds(2.0)
	var m := await _watch([a, b], 45.0)
	m["shots"] = _shots_total
	m["shots_stopped_by_vegetation"] = _shots_tree
	m["shots_stopped_by_cover_objects"] = _shots_cover
	m["alive"] = [a.members.size(), b.members.size()]
	m["at"] = _v(center)
	_png("%s_fight" % tag)
	await _clear_squads([a, b])
	return m


func _a_open() -> Dictionary:
	var m := await _fight(_place_for(false), "open")
	_expect(not m.is_empty() and int(m.get("shots", 0)) > 20, "a_open: no fight happened %s" % str(m))
	return m


func _b_forest() -> Dictionary:
	var m := await _fight(_place_for(true), "forest")
	_expect(not m.is_empty() and int(m.get("shots", 0)) > 10, "b_forest: no fight happened %s" % str(m))
	return m


func _c_road() -> Dictionary:
	var out := {}
	var n := demo.sim.state.roads.nearest(_site.def, 900.0, 0, 0.0)
	_expect(not n.is_empty(), "c_road: no road near the test area")
	if n.is_empty():
		return out
	var rp: Vector3 = n.pos
	var d2: Vector2 = n.dir
	var along := Vector3(d2.x, 0, d2.y)
	var across := Vector3(-d2.y, 0, d2.x)
	var enemy := _cs.spawn(1, rp + along * 140.0 + across * 30.0, -along, 4, "CRE")
	var sq := _cs.spawn(0, rp - across * 45.0, across, 6, "CRS")
	sq.behaviour = SquadBehaviour.COMBAT
	_tough([sq])
	var goal := demo.on_ground(rp.x + across.x * 50.0, rp.z + across.z * 50.0, 0.0)
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(goal)
	var t0 := demo.sim.state.time
	var stuck := 0
	CoreDemo.apply_time_scale(2.0)
	while demo.sim.state.time - t0 < 150.0:
		await _physics(15)
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			if u and u.move_state == UnitState.MoveState.BLOCKED:
				stuck += 1
		var c := demo.sim.squads._centroid(sq)
		if Vector2(c.x - goal.x, c.z - goal.z).length() < 12.0 and not sq.interrupted:
			break
	CoreDemo.apply_time_scale(1.0)
	var c2 := demo.sim.squads._centroid(sq)
	out = {"road_at": _v(rp), "crossed_in_s": snappedf(demo.sim.state.time - t0, 0.1), "left_m": snappedf(Vector2(c2.x - goal.x, c2.z - goal.z).length(), 1.0),
		"halts": sq.interrupts, "blocked_samples": stuck, "alive": sq.members.size(), "state": demo.sim.squads.describe_order(sq).text}
	_png("road_crossing")
	_expect(float(out.left_m) < 30.0, "c_road: the squad did not get across %s" % str(out))
	await _clear_squads([sq, enemy])
	return out


func _d_two_threats() -> Dictionary:
	var walls := _objects(CoverLayer.IDS.wall, _site.def, 1)
	var c: Vector3 = walls[0].pos if not walls.is_empty() else _site.def
	var sq := _cs.spawn(0, c, Vector3.FORWARD, 8, "DTS")
	var e1 := _cs.spawn(1, c + Vector3(120, 0, 30), Vector3.LEFT, 3, "DT1")
	var e2 := _cs.spawn(1, c + Vector3(-40, 0, 120), Vector3.BACK, 3, "DT2")
	_tough([sq, e1, e2])
	demo.rts.select_squads([sq.id])
	demo.rts.order_tactic(SquadState.Tactic.DEFEND, c)
	await _until(func() -> bool: return false, 40.0, 2.0)
	var t1: Vector3 = demo.sim.state.get_unit(e1.members[0]).position
	var t2: Vector3 = demo.sim.state.get_unit(e2.members[0]).position
	var vs1 := 0
	var vs2 := 0
	var either := 0
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if u == null:
			continue
		var p1: bool = demo.sim.brain._evaluate_spot(u, u.position, t1).protected
		var p2: bool = demo.sim.brain._evaluate_spot(u, u.position, t2).protected
		vs1 += int(p1)
		vs2 += int(p2)
		either += int(p1 or p2)
	var out := {"at": _v(c), "protected_vs_east": vs1, "protected_vs_north": vs2, "protected_from_one": either, "of": sq.members.size(),
		"tactic": sq.tactic_name(), "why": sq.tactic_why}
	_png("two_threats")
	await _clear_squads([sq, e1, e2])
	return out


func _e_modes() -> Dictionary:
	var out := {}
	var c := _place_for(false)
	if not c.is_finite():
		c = _site.def
	for b: int in [SquadBehaviour.AWARE, SquadBehaviour.COMBAT, SquadBehaviour.STEALTH]:
		var enemy := _cs.spawn(1, c + Vector3(0, 0, -220), Vector3.BACK, 4, "EME")
		var sq := _cs.spawn(0, c + Vector3(-60, 0, 0), Vector3.RIGHT, 6, "EMS")
		sq.behaviour = b
		demo.sim.war.intel.report_seen(demo.sim.state.get_unit(sq.members[0]), demo.sim.state.get_unit(enemy.members[0]), 4)
		await _until(func() -> bool: return demo.sim.tactics.threat_pos(sq).is_finite(), 10.0, 1.0)
		var threat := demo.sim.tactics.threat_pos(sq)
		for id in enemy.members:
			demo.sim.state.remove_unit(id)
		var goal := demo.on_ground(c.x + 60.0, c.z, 0.0)
		demo.sim.squads.order_move([sq.id], goal)
		var t := await _until(func() -> bool: return sq.status != SquadState.Status.MOVING and not demo.sim.squads.marching(sq), 90.0, 2.0)
		await _physics(30)
		var prot := 0
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			if demo.sim.brain._evaluate_spot(u, u.position, threat).protected:
				prot += 1
		out[sq.behaviour_name()] = {"time_s": snappedf(t, 0.1), "protected_at_end": prot, "of": sq.members.size(), "state": demo.sim.squads.describe_order(sq).text}
		await _clear_squads([sq])
	return out


## Vehicle access: cross-country plans of an APC from the open place of the test area to eight points 350 m round it (the
## router's legs avoid every solid, the cover objects included). Run with and without --no-natural-cover to compare.
func _n_vehicles() -> Dictionary:
	var out := {"ok": 0, "of": 0, "length_m": 0.0, "ms_max": 0.0, "reasons": {}}
	var c := _place_for(false)
	if not c.is_finite():
		c = _site.def
	var def := VehicleDefs.get_def(&"apc")
	var router := demo.sim.vehicles.router
	for k in 8:
		var a := k * TAU / 8.0 + 0.2
		var to := demo.on_ground(c.x + cos(a) * 350.0, c.z + sin(a) * 350.0, 0.0)
		var res := router.plan(c, to, def)
		out.of += 1
		out.ms_max = maxf(float(out.ms_max), float(res.get("ms", 0.0)))
		if res.ok:
			out.ok += 1
			var pts: PackedVector3Array = res.points
			for i in range(1, pts.size()):
				out.length_m += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		else:
			out.reasons[String(res.get("reason", "?"))] = int(out.reasons.get(String(res.get("reason", "?")), 0)) + 1
	out.length_m = snappedf(float(out.length_m), 1.0)
	out["roads_clear"] = _roads_clear()
	_expect(int(out.roads_clear.within_road_m) == 0, "n_vehicles: cover objects on or beside roads %s" % str(out.roads_clear))
	return out


## Layer objects within their footprint + 1 m of a road surface, or within 40 m of a bridge (none allowed).
func _roads_clear() -> Dictionary:
	var roads := demo.sim.state.roads
	var near_road := 0
	var near_bridge := 0
	for rec: Dictionary in _layer.values():
		var t: Array = rec.transform
		var p := Vector3(t[9], t[10], t[11])
		var foot: Vector2 = CoverLayer.FOOT[int(rec.mesh)] * Vector3(t[0], t[1], t[2]).length()
		var n := roads.nearest(p, 30.0, 0, 0.0)
		if not n.is_empty() and float(n.dist) < (n.road as RoadNetwork.Road).width * 0.5 + maxf(foot.x, foot.y) * (0.0 if int(rec.mesh) == CoverLayer.IDS.timber else 1.0) + 1.0:
			near_road += 1
		if roads.bridge_at(p, 40.0) != null:
			near_bridge += 1
	return {"within_road_m": near_road, "near_bridge": near_bridge, "objects": _layer.size()}


## Frame times over the test area: RTS height and a soldier's eye height, 8 s each; and how long the cover layer took to load.
func _q_perf() -> Dictionary:
	var out := {}
	var c := _place_for(true)
	if not c.is_finite():
		c = _site.def
	for v: Array in [["rts", 70.0], ["ground", 0.0]]:
		if float(v[1]) > 0.0:
			_tcam.current = false
			demo.rts_camera.camera.make_current()
			demo.rts_camera.frame(c, 0.6, float(v[1]))
		else:
			_cam(c + Vector3.UP * 1.6, 4.0, 0.7, 2.0)
		await _seconds(4.0)
		var frames: Array = []
		var t := Time.get_ticks_usec()
		var end := Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < end:
			await tree.process_frame
			var n := Time.get_ticks_usec()
			frames.append((n - t) / 1000.0)
			t = n
		frames.sort()
		out[v[0]] = {"median_ms": snappedf(frames[frames.size() / 2], 0.1), "p95_ms": snappedf(frames[int(frames.size() * 0.95)], 0.1), "max_ms": snappedf(frames[-1], 0.1)}
	var tl := Time.get_ticks_usec()
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CoverLayer.path(demo.config.world_name)))
	out["layer_parse_ms"] = snappedf((Time.get_ticks_usec() - tl) / 1000.0, 0.1)
	out["layer_bytes"] = FileAccess.get_file_as_bytes(CoverLayer.path(demo.config.world_name)).size()
	out["layer_records"] = (j.records as Dictionary).size() if j is Dictionary else 0
	var ov: RefCounted = demo.sim.structures.vegetation.overrides if demo.sim.structures and demo.sim.structures.vegetation else null
	out["overrides_load_ms"] = ov.stats.get("layer_load_ms", -1) if ov else -1
	return out


## Screenshots of the fight on open ground: soldiers in cover behind the layer's objects (RTS close, then first person through
## one of them), and a squad bounding from cover to cover.
func _z_fight() -> Dictionary:
	var out := {}
	var center := _place_for(false)
	if not center.is_finite():
		return {"skipped": "no open place"}
	var dir := Vector3(1, 0, 0.3).normalized()
	var line := demo.sim.combat.line
	for k in 12:
		var d := Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0))
		if line.sight(demo.on_ground(center.x - d.x * 50.0, center.z - d.z * 50.0, 0.0) + Vector3.UP * 1.6, demo.on_ground(center.x + d.x * 50.0, center.z + d.z * 50.0, 0.0) + Vector3.UP * 1.1).visible:
			dir = d
			break
	var a := _cs.spawn(0, center - dir * 50.0, dir, 8, "ZA")
	var b := _cs.spawn(1, center + dir * 50.0, -dir, 8, "ZB")
	_tough([a, b])
	demo.sim.squads.order_hold([a.id, b.id])
	demo.rts_camera.frame(center, 0.6, 60.0)
	await _until(func() -> bool: return false, 25.0, 1.0)
	# A soldier of either side in cover at a layer object.
	var pick: UnitState = null
	for sq: SquadState in [a, b]:
		for id in sq.members:
			var u := demo.sim.state.get_unit(id)
			if u and u.tactic == UnitState.Tactic.IN_COVER and _cover_dist(u.position) < 4.0:
				pick = u
				break
		if pick:
			break
	out["soldier_in_cover_at_object"] = pick != null
	var focus: Vector3 = pick.position if pick else center
	demo.rts_camera.camera.make_current()
	demo.rts_camera.frame(focus, atan2(dir.x, dir.z) + PI, 20.0)
	await _seconds(2.0)
	_png("fight_cover_rts")
	if pick and pick.faction == 0:
		demo.game.possess(pick.id)
		await _seconds(2.5)
		_png("fight_cover_fps")
		demo.game.enter_rts()
	# Squad A bounds 60 m forward: one team covers, the other moves cover to cover.
	demo.rts.select_squads([a.id])
	var res := demo.rts.order_tactic(SquadState.Tactic.BOUND, demo.on_ground(center.x + dir.x * 10.0, center.z + dir.z * 10.0, 0.0))
	await _until(func() -> bool: return false, 12.0, 1.0)
	var c := demo.sim.squads._centroid(a)
	demo.rts_camera.frame(c, atan2(dir.x, dir.z) + PI * 0.75, 45.0)
	await _seconds(2.0)
	_png("fight_bound_rts")
	out["bound"] = {"accepted": res.ok, "tactic": a.tactic_name(), "why": a.tactic_why}
	await _clear_squads([a, b])
	return out

## ROAD-QUALITY-01: the main roads' transition between road mesh, collision and terrain, measured in the real game on ref_20km.
##
##   Godot.exe --path . --resolution 1600x900 --log-file rq.log res://scenes/game/world_ref_20km.tscn -- --road-quality-test
##     [--only survey,cross,squads,along,shots] [--sites=a,b] [--shot-tag=before] [--shots]
##
## survey: every SURVEY_STEP_M along the meshed roads (and round every junction), vertical rays find where the road collider ends on
##   each side and how high its edge stands above the terrain just outside it (the lip a soldier walks against), the bank beyond and
##   the gap under the carriageway. Bridge decks are skipped; their approaches are marked.
## cross / squads / along: near-tier soldiers (SoldierBody + NavigationAgent) cross the road both ways, step from the road onto the
##   shoulder and back, and walk along it, at the fixed SITES. A leg passes only when the soldier arrives without any stuck handling:
##   no ledge hop, no stuck stage, no squad recovery, no stall longer than STALL_PASS_S. Natural banks steeper than the infantry
##   grade limit are reported as such (status NATURAL), never as a road defect.
## Prints "RQ <check> <json>"; writes res://benchmarks/raw/road_quality_test[_<tag>].json and screenshots to docs/road_quality01/.
class_name RoadQualitySelfTest
extends NavInf01SelfTest

const SURVEY_STEP_M := 20.0
const STALL_PASS_S := 2.0
const ARRIVE_M := 2.5
## Fixed crossing sites (chosen from the baseline survey; the same before and after a fix): name, category, a point near the road
## (snapped to the nearest meshed road at run time) and the side whose shoulder the road <-> shoulder legs use (+1 / -1 of the
## road's left normal).
const SITES: Array = [
	["navinf04_verge", "embankment", Vector3(-150.7, 0, -1317.3), -1],
	["fvs_parallel", "two_roads", Vector3(-385.6, 0, 1759.6), -1],
	["vestlia_gully", "straight", Vector3(-5123.5, 0, 1614.2), 1],
	["fvst_straight", "straight", Vector3(709.0, 0, 7301.1), -1],
	["fvsv_straight", "straight", Vector3(-4034.5, 0, 5307.0), -1],
	["fvon_straight", "straight", Vector3(3571.0, 0, 460.6), 1],
	["rv2_fill", "embankment", Vector3(-642.8, 0, -6875.0), -1],
	["rv2_curve_fill", "curve", Vector3(-801.7, 0, -6865.0), -1],
	["rv1_curve", "curve", Vector3(1101.3, 0, 4464.9), 1],
	["culvert_west", "culvert", Vector3(-8648.0, 0, -1824.7), -1],
	["junction_rv1", "junction", Vector3(-396.3, 0, 1707.3), 1],
	["junction_sentrum_v", "junction", Vector3(-2463.9, 0, -1226.6), -1],
	["junction_elvetun", "junction", Vector3(-3006.8, 0, -7485.7), 1],
	["junction_ostby", "junction", Vector3(3248.3, 0, 1884.3), -1],
	["bridge_appr_rv1", "bridge_approach", Vector3(1124.8, 0, 4496.6), 1],
	["bridge_appr_rv2", "bridge_approach", Vector3(158.3, 0, -6749.2), -1],
]
## Sites where a whole squad crosses (formation and local avoidance).
const SQUAD_SITES: Array[String] = ["navinf04_verge", "vestlia_gully", "rv1_curve", "junction_elvetun"]
## Sites where soldiers walk along the road and along the terrain beside it.
const ALONG_SITES: Array[String] = ["navinf04_verge", "rv2_curve_fill", "rv1_curve", "fvsv_straight", "junction_ostby", "bridge_appr_rv1"]

var shot_tag := ""
var _sites_only: Array = []
var _extra_sites: Array = []


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/road_quality01"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
		elif a.begins_with("--shot-tag="):
			shot_tag = a.trim_prefix("--shot-tag=")
		elif a.begins_with("--sites="):
			_sites_only = a.trim_prefix("--sites=").split(",")
		elif a.begins_with("--at="):
			# Extra places to look at (shots only): --at=x:z:side;x:z:side
			for spec in a.trim_prefix("--at=").split(";"):
				var v := spec.split(":")
				_extra_sites.append(["at_%s_%s" % [v[0], v[1]], "probe", Vector3(float(v[0]), 0, float(v[1])), int(v[2]) if v.size() > 2 else 1])
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	lof = combat.line
	brain = demo.sim.brain
	def = combat.weapon(&"rifle")
	war = demo.sim.state.war
	ws = demo.sim.war
	SoldierBody.require_mouse_capture = false
	tree.create_timer(3000.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: road quality test did not finish")
		_finish_rq())
	await _physics(60)
	_load_world_data()
	_pause_ai(true)
	brain.enabled = false
	results["shoulders"] = {"enabled": not "--no-road-shoulders" in OS.get_cmdline_user_args(), "tag": shot_tag}
	for id in ["survey", "cross", "squads", "along", "shots", "nav_climb", "probe", "perf"]:
		if only.is_empty() and id in ["shots", "nav_climb", "probe", "perf"]:
			continue
		if only.is_empty() or only.has(id):
			_open_all_bridges()
			_log_rq(id, await call("_rq_" + id))
	_finish_rq()


func _log_rq(check: String, data: Dictionary) -> void:
	results[check] = data
	if data.has("status"):
		_case_status[check] = data.status
	var short := data.duplicate()
	short.erase("rows")
	short.erase("legs")
	print("RQ %s %s" % [check, JSON.stringify(short)])


func _finish_rq() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["harness_failures"] = failures
	results["case_status"] = _case_status
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var path := "res://benchmarks/raw/road_quality_test%s.json" % (("_" + shot_tag) if shot_tag != "" else "")
	# Checks run separately (survey, crossings, screenshots) add to the file of their tag instead of replacing it.
	var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))) if FileAccess.file_exists(path) else null
	if old is Dictionary:
		for k in results:
			old[k] = results[k]
		results = old
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("RQ %s %s" % ["COMPLETE" if failures.is_empty() else "HARNESS_FAIL", JSON.stringify({"cases": _case_status, "failures": failures, "output": path})])
	demo.shutdown_cleanup()
	tree.quit()


# --- Geometry probes ---------------------------------------------------------------------------------------------------

## The world roads that have a Road Generator mesh (roads.json "mesh"; in RoadNetwork their classes are primary / secondary).
func _mesh_roads() -> Array:
	return _net().world.filter(func(r: RoadNetwork.Road) -> bool: return r.cls == &"primary" or r.cls == &"secondary")


static func _is_road_collider(c: Object) -> bool:
	if c == null or not c is Node:
		return false
	var n := String((c as Node).name)
	return n.begins_with("road_mesh") or n.begins_with("intersection_mesh")


## Height of the road collider at (x, z) (NAN: none). Other colliders (terrain pieces, structures) are looked through.
func _road_y(space: PhysicsDirectSpaceState3D, x: float, z: float, y_ref: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y_ref + 25.0, z), Vector3(x, y_ref - 25.0, z))
	var ex: Array[RID] = []
	for k in 5:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		if _is_road_collider(hit.collider):
			return float(hit.position.y)
		ex.append(hit.rid)
	return NAN


func _th(x: float, z: float) -> float:
	return float(demo.terrain.data.get_height(Vector3(x, 0.0, z)))


## Where the road collider ends going out from `o` along `dir` (from `from_m` to `to_m`): {edge_m, edge_y} (edge_m < 0: none found).
func _edge_along(space: PhysicsDirectSpaceState3D, o: Vector3, dir: Vector3, from_m: float, to_m: float) -> Dictionary:
	var last := -1.0
	var last_y := NAN
	var s := from_m
	var miss := -1.0
	while s <= to_m:
		var y := _road_y(space, o.x + dir.x * s, o.z + dir.z * s, o.y)
		if is_nan(y):
			if last >= 0.0:
				miss = s
				break
		else:
			last = s
			last_y = y
		s += 0.1
	if last < 0.0 or miss < 0.0:
		# No road, or the surface goes on past to_m (a junction or another road): no edge here.
		return {"edge_m": -1.0}
	if miss > 0.0:
		var lo := last
		var hi := miss
		for k in 6:
			var mid := (lo + hi) * 0.5
			var y := _road_y(space, o.x + dir.x * mid, o.z + dir.z * mid, o.y)
			if is_nan(y):
				hi = mid
			else:
				lo = mid
				last_y = y
		last = lo
	return {"edge_m": last, "edge_y": last_y}


## One cross-section side: the lip at the collider edge, the terrain's fall over the first 3 m beyond it and the steepest grade of
## the bank 3-15 m out.
func _section(space: PhysicsDirectSpaceState3D, o: Vector3, dir: Vector3, from_m: float, to_m: float) -> Dictionary:
	var e := _edge_along(space, o, dir, from_m, to_m)
	if float(e.edge_m) < 0.0:
		return {}
	var em: float = e.edge_m
	var ey: float = e.edge_y
	var p := o + dir * (em + 0.05)
	var t0 := _th(p.x, p.z)
	if is_nan(t0):
		return {}
	var t05 := _th(o.x + dir.x * (em + 0.5), o.z + dir.z * (em + 0.5))
	var t3 := _th(o.x + dir.x * (em + 3.0), o.z + dir.z * (em + 3.0))
	var bank := 0.0
	var prev := t3
	for k in range(4, 16):
		var tk := _th(o.x + dir.x * (em + k), o.z + dir.z * (em + k))
		if is_nan(tk) or is_nan(prev):
			break
		bank = maxf(bank, absf(tk - prev))
		prev = tk
	var t15 := _th(o.x + dir.x * (em + 15.0), o.z + dir.z * (em + 15.0))
	return {"edge_m": snappedf(em, 0.01), "edge_y": ey, "lip": snappedf(ey - t0, 0.01), "near_grade": snappedf((t05 - t3) / 2.5, 0.01),
		"bank_grade": snappedf(bank, 0.01), "rise15": snappedf(t15 - ey, 0.1)}


func _rq_survey() -> Dictionary:
	var space := demo.get_world_3d().direct_space_state
	var rows := []
	var t0 := Time.get_ticks_msec()
	var net := _net()
	var juncs := _junction_centres()
	var culverts := _culverts()
	var n_sections := 0
	for r: RoadNetwork.Road in _mesh_roads():
		var pts := r.points
		var hw := r.width * 0.5
		var acc := 0.0
		var next := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := Vector2(b.x - a.x, b.z - a.z).length()
			while next <= acc + seg:
				var u := (next - acc) / maxf(seg, 0.001)
				var p := a.lerp(b, u)
				next += SURVEY_STEP_M
				if net.bridge_at(p, 1.0) != null:
					continue
				var t := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
				var nrm := Vector3(-t.z, 0, t.x)
				var cy := _road_y(space, p.x, p.z, p.y)
				if is_nan(cy):
					continue
				n_sections += 1
				var cat := _category(r, i, p, juncs)
				for cv: Vector3 in culverts.get(r.name, []):
					if _flat(cv, p) < 15.0:
						cat = "culvert"
				for side: float in [-1.0, 1.0]:
					var s := _section(space, Vector3(p.x, cy, p.z), nrm * side, maxf(hw - 1.5, 0.0), hw + 6.0)
					if s.is_empty():
						continue
					s["road"] = r.name
					s["x"] = snappedf(p.x, 0.1)
					s["z"] = snappedf(p.z, 0.1)
					s["side"] = int(side)
					s["cat"] = cat
					s["gap_centre"] = snappedf(cy - _th(p.x, p.z), 0.01)
					s["over_w"] = snappedf(float(s.edge_m) - hw, 0.01)
					s.erase("edge_y")
					rows.append(s)
			acc += seg
	# Junctions: radial sections from the intersection centre.
	for c: Vector3 in juncs:
		var cy := _road_y(space, c.x, c.z, c.y)
		if is_nan(cy):
			continue
		for k in 24:
			var ang := TAU * k / 24.0
			var dir := Vector3(cos(ang), 0, sin(ang))
			var s := _section(space, Vector3(c.x, cy, c.z), dir, 0.0, 40.0)
			if s.is_empty():
				continue
			s["road"] = "junction"
			s["x"] = snappedf(c.x, 0.1)
			s["z"] = snappedf(c.z, 0.1)
			s["side"] = k
			s["cat"] = "junction_radial"
			s.erase("edge_y")
			rows.append(s)
	return _survey_summary(rows, n_sections, Time.get_ticks_msec() - t0)


func _survey_summary(rows: Array, n_sections: int, ms: int) -> Dictionary:
	var lips := rows.map(func(x: Dictionary) -> float: return float(x.lip))
	lips.sort()
	var n := lips.size()
	var pct := func(q: float) -> float: return lips[clampi(int(n * q), 0, n - 1)] if n > 0 else NAN
	var by_cat := {}
	for r: Dictionary in rows:
		var c: String = r.cat
		if not by_cat.has(c):
			by_cat[c] = {"n": 0, "over_035": 0, "max": -9.0}
		by_cat[c].n += 1
		if float(r.lip) > 0.35:
			by_cat[c].over_035 += 1
		by_cat[c].max = maxf(by_cat[c].max, float(r.lip))
	# Worst places, one per 100 m cell.
	var cells := {}
	for r: Dictionary in rows:
		if float(r.lip) <= 0.2:
			continue
		var key := "%s_%d_%d" % [r.road, floori(float(r.x) / 100.0), floori(float(r.z) / 100.0)]
		if not cells.has(key) or float(cells[key].lip) < float(r.lip):
			cells[key] = r
	var worst := cells.values()
	worst.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.lip) > float(q.lip))
	# Natural banks steeper than the infantry limit (not lips): 100 m cells.
	var steep := {}
	for r: Dictionary in rows:
		if float(r.bank_grade) > WorldSim.INFANTRY_MAX_GRADE:
			var key := "%s_%d_%d" % [r.road, floori(float(r.x) / 100.0), floori(float(r.z) / 100.0)]
			if not steep.has(key) or float(steep[key].bank_grade) < float(r.bank_grade):
				steep[key] = r
	var steep_l := steep.values()
	steep_l.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.bank_grade) > float(q.bank_grade))
	var gaps := rows.filter(func(x: Dictionary) -> bool: return x.has("gap_centre")).map(func(x: Dictionary) -> float: return float(x.gap_centre))
	gaps.sort()
	var ow := rows.filter(func(x: Dictionary) -> bool: return x.has("over_w")).map(func(x: Dictionary) -> float: return float(x.over_w))
	ow.sort()
	var out := {"sections": n_sections, "edges": n, "ms": ms, "lip_median": pct.call(0.5), "lip_p90": pct.call(0.9), "lip_p99": pct.call(0.99),
		"lip_max": lips[n - 1] if n > 0 else NAN, "lip_min": lips[0] if n > 0 else NAN,
		"over_020": lips.filter(func(x: float) -> bool: return x > 0.2).size(), "over_035": lips.filter(func(x: float) -> bool: return x > 0.35).size(),
		"over_050": lips.filter(func(x: float) -> bool: return x > 0.5).size(), "over_100": lips.filter(func(x: float) -> bool: return x > 1.0).size(),
		"buried_010": lips.filter(func(x: float) -> bool: return x < -0.1).size(),
		"gap_centre_median": gaps[gaps.size() / 2] if gaps.size() > 0 else NAN, "gap_centre_max": gaps[gaps.size() - 1] if gaps.size() > 0 else NAN,
		"mesh_over_width_median": ow[ow.size() / 2] if ow.size() > 0 else NAN,
		"by_cat": by_cat, "worst": worst.slice(0, 40), "steep_natural_cells": steep_l.size(), "steep_natural": steep_l.slice(0, 30), "rows": rows}
	out["status"] = "PASS" if n > 1000 else "FAIL"
	if n <= 1000:
		failures.append("survey: only %d edges measured (road colliders missing?)" % n)
	return out


## Culvert points of the meshed roads (roads.json), by road name: streams under the road keep their channel beside it.
func _culverts() -> Dictionary:
	var out := {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s/source/roads.json" % demo.config.world_name))
	if not data is Dictionary:
		return out
	for r: Dictionary in data.roads:
		if not r.get("mesh", false):
			continue
		var pts: Array = []
		for k in r.get("culverts", []):
			var q: Array = r.points[int(k)]
			pts.append(Vector3(q[0], q[1], q[2]))
		out[r.name] = pts
	return out


func _junction_centres() -> Array:
	var out := []
	for inter in _find_nodes(demo.get_tree().root, func(n: Node) -> bool: return n is RoadIntersection):
		out.append((inter as Node3D).global_position)
	return out


func _find_nodes(root: Node, pred: Callable) -> Array:
	var out := []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if pred.call(n):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _category(r: RoadNetwork.Road, i: int, p: Vector3, juncs: Array) -> String:
	for c: Vector3 in juncs:
		if _flat(c, p) < 40.0:
			return "junction"
	for span: Array in r.bridges:
		for k in [int(span[0]), int(span[1])]:
			if _flat(r.points[k], p) < 40.0:
				return "bridge_approach"
	var pts := r.points
	var i0 := maxi(i - 3, 0)
	var i1 := mini(i + 4, pts.size() - 1)
	if i1 - i0 >= 2:
		var d0 := Vector2(pts[i0 + 1].x - pts[i0].x, pts[i0 + 1].z - pts[i0].z)
		var d1 := Vector2(pts[i1].x - pts[i1 - 1].x, pts[i1].z - pts[i1 - 1].z)
		if absf(d0.angle_to(d1)) > deg_to_rad(12.0):
			return "curve"
	return "straight"


## The nearest meshed road point to `q`: {road, p (centre on the polyline, road surface height), nrm (left normal), hw}.
func _snap(q: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for r: RoadNetwork.Road in _mesh_roads():
		var pts := r.points
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var c := Geometry2D.get_closest_point_to_segment(Vector2(q.x, q.z), a, b)
			var d := c.distance_to(Vector2(q.x, q.z))
			if d < bd:
				bd = d
				var u := 0.0 if a.distance_to(b) < 0.01 else a.distance_to(c) / a.distance_to(b)
				var t := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
				best = {"road": r.name, "p": pts[i].lerp(pts[i + 1], u), "nrm": Vector3(-t.z, 0, t.x), "t": t, "hw": r.width * 0.5, "d": d}
	return best


# --- Near-tier movement ------------------------------------------------------------------------------------------------

func _site_list() -> Array:
	if not _extra_sites.is_empty():
		return _extra_sites
	return SITES.filter(func(s: Array) -> bool: return _sites_only.is_empty() or _sites_only.has(s[0]))


## The geometry of a site: road centre, collider edges on both sides, start / goal points of the legs.
func _site_geo(s: Array) -> Dictionary:
	var sn := _snap(s[2])
	var space := demo.get_world_3d().direct_space_state
	var p: Vector3 = sn.p
	var cy := _road_y(space, p.x, p.z, p.y)
	var c := Vector3(p.x, cy if not is_nan(cy) else p.y, p.z)
	var nrm: Vector3 = sn.nrm
	var hw: float = sn.hw
	var geo := {"name": s[0], "cat": s[1], "road": sn.road, "centre": c, "nrm": nrm, "t": sn.t, "side": int(s[3]), "hw": hw}
	for side: int in [-1, 1]:
		var sec := _section(space, c, nrm * side, maxf(hw - 1.5, 0.0), hw + 6.0)
		geo["sec%d" % side] = sec
		var em: float = float(sec.get("edge_m", hw + 2.0))
		geo["edge%d" % side] = em
	return geo


func _off(geo: Dictionary, side: int, beyond_edge: float) -> Vector3:
	var em: float = geo["edge%d" % side]
	var c: Vector3 = geo.centre
	var p: Vector3 = c + (geo.nrm as Vector3) * side * (em + beyond_edge)
	return demo.on_ground(p.x, p.z, 0.0)


## A point at the bank beyond the edge is natural ground the soldier is not expected to climb when the bank there is steeper
## than the infantry grade limit.
func _natural_block(geo: Dictionary, side: int) -> bool:
	var sec: Dictionary = geo.get("sec%d" % side, {})
	return float(sec.get("near_grade", 0.0)) > WorldSim.INFANTRY_MAX_GRADE or float(sec.get("bank_grade", 0.0)) > WorldSim.INFANTRY_MAX_GRADE


## One soldier (or a squad of n) walks from a to b in the near tier through the ordinary move order. Measures arrival, the longest
## stall, ledge hops, stuck stages and squad recoveries.
func _leg(a: Vector3, b: Vector3, n := 1, max_s := 45.0) -> Dictionary:
	await _fresh()
	_camera_on(a.lerp(b, 0.5), 40.0)
	await _seconds(1.0)
	var sq := _spawn(0, a, n)
	var ids: Array = Array(sq.members)
	var t_wait := 0.0
	while t_wait < 6.0:
		var all_body := true
		for id in ids:
			if not _u(id).has_body:
				all_body = false
		if all_body and demo.detail.ground.ready_at(a):
			break
		await _seconds(0.25)
		t_wait += 0.25
	await _seconds(0.5)
	var hops0 := SoldierBody.ledge_hops
	var stuck0 := SoldierBody.stuck_log.size()
	var stuck_last0: Variant = SoldierBody.stuck_log.back() if stuck0 > 0 else null
	var rec0: int = demo.sim.squads.member_recoveries
	var fail0: int = demo.sim.squads.member_failures
	var all_body0 := ids.all(func(id: int) -> bool: return _u(id).has_body)
	demo.sim.squads.order_move([sq.id], b)
	var t_start := demo.sim.state.time
	var track := {}
	for id in ids:
		track[id] = {"pos": _u(id).position, "since": t_start, "stalls": [], "max_y_jump": 0.0, "y": _u(id).position.y, "reasons": {}, "blocked": false}
	var each := func(t: float) -> void:
		for id in ids:
			var u := _u(id)
			var tr: Dictionary = track[id]
			if absf(u.position.y - tr.y) > tr.max_y_jump:
				tr.max_y_jump = absf(u.position.y - tr.y)
			tr.y = u.position.y
			if u.move_state == UnitState.MoveState.BLOCKED:
				tr.blocked = true
			if u.nav_reason != "" and (tr.reasons as Dictionary).size() < 6:
				tr.reasons["%s @ %d,%d" % [u.nav_reason.left(60), roundi(u.position.x), roundi(u.position.z)]] = true
			if _flat(u.position, tr.pos) > 0.3 or u.order != UnitState.Order.MOVE:
				if t - tr.since > 0.5 and tr.since - t_start > 1.5:
					(tr.stalls as Array).append([tr.pos, t - tr.since])
				tr.pos = u.position
				tr.since = t
	var stop := func() -> bool:
		if demo.sim.state.time - t_start < 1.0:
			return false
		return ids.all(func(id: int) -> bool: return _u(id).order != UnitState.Order.MOVE)
	var w := await _run_until(max_s, 4.0, each, stop)
	var arrived := 0
	var rows := []
	var max_stall := 0.0
	for id in ids:
		var u := _u(id)
		var d := _flat(u.position, b)
		var ok := u.move_state == UnitState.MoveState.ARRIVED and d <= (ARRIVE_M if n == 1 else 25.0)
		if ok:
			arrived += 1
		# A stall counts on the way only: standing at the end of the walk (inside the arrival radius, on its formation slot) is
		# the order finishing, not a soldier held up by the ground.
		var tr: Dictionary = track[id]
		if tr.since - t_start > 1.5:
			(tr.stalls as Array).append([tr.pos, demo.sim.state.time - tr.since])
		tr.stall = 0.0
		tr.stall_at = []
		for st: Array in tr.stalls:
			if _flat(st[0], u.position) > 3.0 and float(st[1]) > float(tr.stall):
				tr.stall = float(st[1])
				tr.stall_at = [snappedf((st[0] as Vector3).x, 0.1), snappedf((st[0] as Vector3).z, 0.1)]
		max_stall = maxf(max_stall, float(tr.stall))
		rows.append({"d": snappedf(d, 0.1), "ms": u.move_state, "why": u.nav_reason, "body": u.has_body, "pos": [snappedf(u.position.x, 0.1), snappedf(u.position.y, 0.01), snappedf(u.position.z, 0.1)],
			"stall_s": snappedf(float(track[id].stall), 0.1), "stall_at": track[id].stall_at,
			"reasons": (track[id].reasons as Dictionary).keys()})
	var stuck_new := SoldierBody.stuck_log.size() - stuck0
	if stuck_new == 0 and SoldierBody.stuck_log.size() > 0 and SoldierBody.stuck_log.back() != stuck_last0:
		stuck_new = 1
	var stuck_rows := SoldierBody.stuck_log.slice(maxi(SoldierBody.stuck_log.size() - stuck_new, 0)).map(func(x: Dictionary) -> Array: return x.pos)
	var blocked := ids.filter(func(id: int) -> bool: return track[id].blocked).size()
	var out := {"n": n, "arrived": arrived, "blocked": blocked, "t": snappedf(demo.sim.state.time - t_start, 0.1), "max_stall_s": snappedf(max_stall, 0.1),
		"hops": SoldierBody.ledge_hops - hops0, "stuck": stuck_new, "recoveries": demo.sim.squads.member_recoveries - rec0,
		"failures": demo.sim.squads.member_failures - fail0, "bodies": all_body0, "stuck_at": stuck_rows, "speed": w.get("speed", 0.0), "units": rows}
	# member_recoveries is global (any squad); this leg's own soldiers count through "blocked".
	out["clean"] = arrived == n and out.hops == 0 and out.stuck == 0 and blocked == 0 and max_stall <= STALL_PASS_S
	return out


func _leg_row(geo: Dictionary, leg: String, a: Vector3, b: Vector3, natural: bool, n := 1) -> Dictionary:
	# A start or goal in water or beside a bridge deck (the river bank under it) is not road-side ground.
	for p: Vector3 in [a, b]:
		if sm.is_wet(p.x, p.z) or (_net().bridge_at(p, 8.0) != null and leg.begins_with("along_shoulder")):
			natural = true
	var r := await _leg(a, b, n)
	r["site"] = geo.name
	r["cat"] = geo.cat
	r["leg"] = leg
	r["from"] = [snappedf(a.x, 0.1), snappedf(a.z, 0.1)]
	r["to"] = [snappedf(b.x, 0.1), snappedf(b.z, 0.1)]
	r["status"] = "PASS" if r.clean else ("NATURAL" if natural else "FAIL")
	print("RQ leg %s %s %s arrived %d/%d stall %.1f hops %d stuck %d blocked %d" % [geo.name, leg, r.status, r.arrived, n, r.max_stall_s, r.hops, r.stuck, r.blocked])
	return r


func _rq_cross() -> Dictionary:
	var legs := []
	for s: Array in _site_list():
		var geo := _site_geo(s)
		var side: int = geo.side
		var nat_m := _natural_block(geo, -1)
		var nat_p := _natural_block(geo, 1)
		var far_m := _off(geo, -1, 6.0)
		var far_p := _off(geo, 1, 6.0)
		var c: Vector3 = geo.centre
		var shoulder := _off(geo, side, 3.0)
		legs.append(await _leg_row(geo, "cross_+", far_m, far_p, nat_m or nat_p))
		legs.append(await _leg_row(geo, "cross_-", far_p, far_m, nat_m or nat_p))
		legs.append(await _leg_row(geo, "road_to_shoulder", c, shoulder, _natural_block(geo, side)))
		legs.append(await _leg_row(geo, "shoulder_to_road", shoulder, c, _natural_block(geo, side)))
		results["geo_" + String(geo.name)] = {"road": geo.road, "centre": [snappedf(c.x, 0.1), snappedf(c.y, 0.01), snappedf(c.z, 0.1)],
			"sec-1": geo["sec-1"], "sec1": geo["sec1"]}
	return _legs_summary(legs)


func _rq_squads() -> Dictionary:
	var legs := []
	for s: Array in _site_list():
		if not SQUAD_SITES.has(s[0]):
			continue
		var geo := _site_geo(s)
		var nat := _natural_block(geo, -1) or _natural_block(geo, 1)
		legs.append(await _leg_row(geo, "squad_+", _off(geo, -1, 10.0), _off(geo, 1, 10.0), nat, 6))
		legs.append(await _leg_row(geo, "squad_-", _off(geo, 1, 10.0), _off(geo, -1, 10.0), nat, 6))
	return _legs_summary(legs)


## Road following: 60 m along the road surface and 60 m along the terrain just beyond the shoulder edge.
func _rq_along() -> Dictionary:
	var legs := []
	for s: Array in _site_list():
		if not ALONG_SITES.has(s[0]) and _sites_only.is_empty():
			continue
		var geo := _site_geo(s)
		var c: Vector3 = geo.centre
		var t: Vector3 = geo.t
		var a := c - t * 30.0
		var b := c + t * 30.0
		legs.append(await _leg_row(geo, "along_road", demo.on_ground(a.x, a.z, 0.0), demo.on_ground(b.x, b.z, 0.0), false))
		var side: int = geo.side
		var off: Vector3 = (geo.nrm as Vector3) * side * (float(geo["edge%d" % side]) + 1.5)
		legs.append(await _leg_row(geo, "along_shoulder", demo.on_ground(a.x + off.x, a.z + off.z, 0.0), demo.on_ground(b.x + off.x, b.z + off.z, 0.0), _natural_block(geo, side)))
	return _legs_summary(legs)


func _legs_summary(legs: Array) -> Dictionary:
	var n_pass := legs.filter(func(l: Dictionary) -> bool: return l.status == "PASS").size()
	var n_nat := legs.filter(func(l: Dictionary) -> bool: return l.status == "NATURAL").size()
	var fails := legs.filter(func(l: Dictionary) -> bool: return l.status == "FAIL").map(func(l: Dictionary) -> String: return "%s/%s" % [l.site, l.leg])
	var hops := 0
	var stuck := 0
	for l: Dictionary in legs:
		hops += int(l.hops)
		stuck += int(l.stuck)
	return {"status": "PASS" if fails.is_empty() and not legs.is_empty() else "FAIL", "legs_n": legs.size(), "pass": n_pass, "natural": n_nat,
		"fail": fails, "hops": hops, "stuck": stuck, "legs": legs}


## Cross-section profiles at the sites (or --at places): road collider and terrain height every 0.25 m out to 8 m beyond the edge.
func _rq_probe() -> Dictionary:
	var space := demo.get_world_3d().direct_space_state
	var out := {}
	for s: Array in _site_list():
		var geo := _site_geo(s)
		var c: Vector3 = geo.centre
		for side: int in [-1, 1]:
			var nrm: Vector3 = (geo.nrm as Vector3) * side
			var rows := []
			var k := 0.0
			while k <= float(geo["edge%d" % side]) + 8.0:
				var p := c + nrm * k
				var ry := _road_y(space, p.x, p.z, c.y)
				rows.append([k, snappedf(ry, 0.01) if not is_nan(ry) else null, snappedf(_th(p.x, p.z), 0.01)])
				k += 0.25
			out["%s_%d" % [geo.name, side]] = rows
			print("RQ probe %s side %d edge %.2f: %s" % [geo.name, side, float(geo["edge%d" % side]), JSON.stringify(rows)])
			var st := {"rays": 0, "edges": 0, "no_edge": 0}
			# Called by name: the test also runs against older RoadShoulders versions (before / after screenshots).
			var rs: Variant = RoadShoulders
			var e: Variant = rs.call("_edge", space, c - Vector3.UP * 0.2, nrm, float(geo.hw), st)
			print("RQ probe %s side %d RoadShoulders._edge %s (hw %.2f)" % [geo.name, side, str(e), float(geo.hw)])
		_camera_on(c, 40.0)
		await _seconds(3.0)
		var a := _off(geo, 1, 6.0)
		var b := _off(geo, -1, 6.0)
		var map := demo.get_world_3d().navigation_map
		for pair: Array in [[a, b], [b, a]]:
			var path := NavigationServer3D.map_get_path(map, pair[0], pair[1], true)
			var pts := []
			for q: Vector3 in path:
				pts.append([snappedf(q.x, 0.1), snappedf(q.y, 0.01), snappedf(q.z, 0.1)])
			print("RQ probe %s navpath %s -> %s: %s" % [geo.name, str(pair[0]), str(pair[1]), JSON.stringify(pts)])
	return {"status": "INFO", "profiles": out.size()}


## What the shoulders cost at run time: the start-up apply (from the cache) and the per-chunk vegetation pass (RoadShoulders.fix_chunk,
## run on the main thread when a chunk loads), timed over the chunks loaded round a road site.
func _rq_perf() -> Dictionary:
	_camera_on(Vector3(-150.7, 0, -1317.3), 40.0)
	await _seconds(4.0)
	var veg := demo.vegetation
	var rs_class: Variant = RoadShoulders
	var times := PackedFloat32Array()
	var inst := 0
	for loc in veg.chunks:
		var ch: VegetationChunk = veg.chunks[loc]
		var t0 := Time.get_ticks_usec()
		RoadShoulders.fix_chunk(ch)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		for cell in ch.cells:
			if RoadShoulders.touched.has(cell):
				for mesh_id in ch.cells[cell]:
					inst += (ch.cells[cell][mesh_id] as PackedFloat32Array).size() / VegetationChunk.FLOATS_PER_INSTANCE
	# The part of fix_chunk ROAD-QUALITY-01 added: one under_road lookup per instance in an eased cell.
	var under: Dictionary = rs_class.get("under_road") if rs_class.get("under_road") != null else {}
	var sp: float = rs_class.get("_spacing") if rs_class.get("_spacing") != null else 1.0
	var t_look := Time.get_ticks_usec()
	var hits := 0
	for loc in veg.chunks:
		var ch: VegetationChunk = veg.chunks[loc]
		for cell in ch.cells:
			if not RoadShoulders.touched.has(cell):
				continue
			for mesh_id in ch.cells[cell]:
				var buf: PackedFloat32Array = ch.cells[cell][mesh_id]
				for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
					var k := i * VegetationChunk.FLOATS_PER_INSTANCE
					if under.get(Vector2i(roundi(buf[k + 3] / sp), roundi(buf[k + 11] / sp)), false):
						hits += 1
	var look_ms := (Time.get_ticks_usec() - t_look) / 1000.0
	var sorted := times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum := 0.0
	for v in sorted:
		sum += v
	return {"status": "INFO", "chunks": n, "instances_in_touched_cells": inst, "fix_chunk_ms_mean": snappedf(sum / maxf(n, 1), 0.01),
		"fix_chunk_ms_p95": snappedf(sorted[int(n * 0.95)] if n > 0 else 0.0, 0.01), "fix_chunk_ms_max": snappedf(sorted[n - 1] if n > 0 else 0.0, 0.01),
		"added_lookup_ms_total": snappedf(look_ms, 0.01), "added_lookup_ms_per_chunk": snappedf(look_ms / maxf(n, 1), 0.01), "instances_sunk": hits,
		"under_road_vertices": (rs_class.get("under_road") as Dictionary).size() if rs_class.get("under_road") != null else 0, "touched_cells": RoadShoulders.touched.size()}


# --- Navigation climb consistency ---------------------------------------------------------------------------------------

## The navmesh lets a path climb agent_max_climb (rounded to its 0.25 m cell height) while a SoldierBody steps up step_height: a
## step between the two is on the navmesh but not walkable. Reports both values and the navmesh's own number.
func _rq_nav_climb() -> Dictionary:
	var probe := SoldierBody.new()
	var body_step: float = probe.step_height
	var hop: float = probe.ledge_hop_m
	probe.free()
	var climb := []
	for an in _find_nodes(demo.get_tree().root, func(n: Node) -> bool: return n is AreaNavigation):
		var nm := (an as NavigationRegion3D).navigation_mesh
		if nm:
			climb.append({"region": String(an.name), "agent_max_climb": nm.agent_max_climb, "cell_height": nm.cell_height, "agent_max_slope": nm.agent_max_slope})
	return {"status": "INFO", "body_step_height": body_step, "ledge_hop_m": hop, "navmesh": climb}


# --- Screenshots ------------------------------------------------------------------------------------------------------

## Low-angle views across the road edge at the sites (the same frames before and after a change).
func _rq_shots() -> Dictionary:
	var cam := Camera3D.new()
	cam.fov = 55.0
	demo.add_child(cam)
	var prev := demo.get_viewport().get_camera_3d()
	var taken := []
	for s: Array in _site_list():
		var geo := _site_geo(s)
		var side: int = geo.side
		var c: Vector3 = geo.centre
		var nrm: Vector3 = geo.nrm
		var t: Vector3 = geo.t
		var edge := c + nrm * side * float(geo["edge%d" % side])
		_camera_on(edge, 40.0)
		await _seconds(2.5)
		# From beyond the shoulder, looking back along and across the edge.
		var eye := edge + nrm * side * 9.0 - t * 10.0
		eye.y = maxf(_th(eye.x, eye.z), edge.y) + 3.2
		cam.global_position = eye
		cam.look_at(edge + t * 6.0 + Vector3.UP * 0.2, Vector3.UP)
		cam.make_current()
		await _seconds(1.5)
		var nm := "rq_%s%s" % [geo.name, ("_" + shot_tag) if shot_tag != "" else ""]
		_save_png(nm)
		taken.append(nm)
	cam.clear_current()
	if prev:
		prev.make_current()
	cam.queue_free()
	return {"status": "INFO", "shots": taken}


func _save_png(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	if img:
		img.save_jpg(ProjectSettings.globalize_path("%s/%s.jpg" % [_shot_dir, nm]), 0.88)
		print("RQ shot ", nm)

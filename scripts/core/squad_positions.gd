## Squad-level position search for the tactics layer (AI-SQUAD-01): firing posts, cover
## for a moving team, flank routes and how exposed a route is to a known enemy position.
##
## Everything here is a measurement on world data the squad can legitimately use - terrain
## height, structures, rocks and trunks (CombatBrain.cover_spots), line-of-sight checks
## against a position the squad *believes* the enemy to be at (a contact, a sighting, a
## position the player chose). Nothing reads an unobserved enemy soldier.
##
## It runs when a tactic is planned or a leg is issued (a few times per squad per fight), never
## per frame, and each search is bounded (max_candidates evaluations).
class_name SquadPositions
extends RefCounted

var sim: WorldSim
## Candidates evaluated per post search at most.
var max_candidates := 22
## Minimum spacing between posts of one plan (m), and from other soldiers' reserved spots.
var post_spacing_m := 2.6
## Steepest slope a flank / leg point may have (degrees).
var max_slope_deg := 32.0

var searches := 0
var evals := 0
var usec := 0
var usec_max := 0
var flank_plans := 0
var flank_usec := 0


func _init(p_sim: WorldSim) -> void:
	sim = p_sim


# --- Ground ------------------------------------------------------------------------------

func ground(p: Vector3) -> Vector3:
	if sim.terrain:
		var h: float = sim.terrain.data.get_height(p)
		if not is_nan(h):
			return Vector3(p.x, h, p.z)
	return p


## Dry, walkable, not inside a structure, on the strategic route grid.
func valid_ground(p: Vector3) -> bool:
	var st := sim.structures
	if st != null:
		if st._wet(p.x, p.z, p.y - 0.25) or st.blocks_point(Vector2(p.x, p.z), 0.7):
			return false
	if sim.terrain:
		var h0: float = sim.terrain.data.get_height(p)
		var h1: float = sim.terrain.data.get_height(p + Vector3(2.0, 0.0, 0.0))
		var h2: float = sim.terrain.data.get_height(p + Vector3(0.0, 0.0, 2.0))
		if is_nan(h0) or is_nan(h1) or is_nan(h2):
			return false
		if absf(h1 - h0) / 2.0 > tan(deg_to_rad(max_slope_deg)) or absf(h2 - h0) / 2.0 > tan(deg_to_rad(max_slope_deg)):
			return false
	var routes: StrategicRoutes = sim.war.routes if sim.war else null
	if routes != null and routes.ready and not routes.passable(p):
		return false
	return true


## p, or the nearest valid ground within max_r (INF when there is none).
func nearest_valid(p: Vector3, max_r := 18.0) -> Vector3:
	var g := ground(p)
	if valid_ground(g):
		return g
	var r := 3.0
	while r <= max_r:
		for k in 8:
			var a := k * TAU / 8.0 + r
			var c := ground(p + Vector3(cos(a), 0.0, sin(a)) * r)
			if valid_ground(c):
				return c
		r += 3.0
	return Vector3.INF


## No wet or blocked ground and no cliff on the straight line (samples every 5 m).
func segment_clear(a: Vector3, b: Vector3) -> bool:
	var n := maxi(1, ceili(_flat(a, b) / 5.0))
	var prev := a
	for k in range(1, n + 1):
		var q := ground(a.lerp(b, float(k) / n))
		if not valid_ground(q):
			return false
		if _flat(prev, q) > 0.5 and absf(q.y - prev.y) / _flat(prev, q) > tan(deg_to_rad(40.0)):
			return false
		prev = q
	return true


## A walking path from a to b exists and is not much longer than the straight line. With a
## body near the camera the navigation mesh is asked; otherwise the straight line must be clear
## (the abstract tier walks straight).
func reachable(a: Vector3, b: Vector3, unit_id := -1, detour := 2.2) -> bool:
	var body := sim.body_of(unit_id) as SoldierBody if unit_id >= 0 else null
	if body and body.nav:
		var map := body.nav.get_navigation_map()
		if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
			var path := NavigationServer3D.map_get_path(map, a, b, true)
			if path.is_empty() or _flat(path[path.size() - 1], b) > 1.5:
				return false
			var length := 0.0
			for i in range(1, path.size()):
				length += path[i - 1].distance_to(path[i])
			return length <= _flat(a, b) * detour + 6.0
	return segment_clear(a, b)


# --- Exposure ----------------------------------------------------------------------------

## Fraction (0..1) of the points along a polyline that a rifleman at `enemy` could see (eye
## 1.5 m, target at 1.0 m) within `range_m`, sampled every `step` metres. 0 = hidden all the
## way. `enemy` is a believed position (a contact), never a hidden soldier's true one.
func route_exposure(points: Array, enemy: Vector3, range_m := 260.0, step := 12.0) -> float:
	var seen := 0
	var total := 0
	var line := sim.combat.line
	var eye := enemy + Vector3.UP * 1.5
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var n := maxi(1, ceili(_flat(a, b) / step))
		for k in range(1, n + 1):
			var q := a.lerp(b, float(k) / n)
			total += 1
			if _flat(q, enemy) > range_m:
				continue
			if line.sight(eye, ground(q) + Vector3.UP * 1.0).visible:
				seen += 1
	return float(seen) / maxi(total, 1)


# --- Flank ---------------------------------------------------------------------------------

## A route from `from` round one side of a believed enemy position `target`: via an outer
## point and a staging point beside the enemy, 30 m short of it. Returns
## {ok, reason, points, length, exposure, side, detour}. Every point is on valid ground, every leg
## walkable (navigation or a clear line), detour and exposure bounded by the caller.
func plan_flank(from: Vector3, target: Vector3, side: int, lateral := 75.0, unit_id := -1) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	flank_plans += 1
	var dir := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var direct := dir.length()
	var name := "left" if side < 0 else "right"
	if direct < 40.0:
		return {"ok": false, "reason": "%s: too close to flank" % name}
	dir /= direct
	var lat := Vector3(-dir.z, 0.0, dir.x) * side
	# Outer point: a third of the way, well out to the side; staging point: beside the enemy.
	var mid := nearest_valid(from + dir * direct * 0.35 + lat * lateral * 0.7, 20.0)
	var stage := nearest_valid(target + lat * lateral - dir * 30.0, 20.0)
	if not mid.is_finite() or not stage.is_finite():
		return {"ok": false, "reason": "%s: no walkable ground on that side" % name}
	var pts: Array = [from, mid, stage]
	var length := 0.0
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		if not reachable(a, b, unit_id if i == 1 else -1, 1.8):
			return {"ok": false, "reason": "%s: leg %d is not walkable (water, cliff or structure)" % [name, i]}
		length += _flat(a, b)
	var exposure := route_exposure(pts, target)
	flank_usec += Time.get_ticks_usec() - t0
	return {"ok": true, "reason": "", "points": pts.slice(1), "length": length, "exposure": exposure, "side": side,
		"detour": length / maxf(direct, 1.0), "name": name}


# --- Posts -----------------------------------------------------------------------------------

## Firing / cover posts for `count` soldiers around `center` within `radius`, against a
## threat at `threat`. opts:
##   los: Vector3 - a position the posts should see (a believed enemy position)
##   mode: "fire" (fire from protected posts with a view), "cover" (protection first, a view is
##         not needed: a moving team's halting points)
##   reserved: Array[Vector3] - spots other soldiers hold (cover or post), kept 2 m clear
##   avoid: Array[Vector3] - spots used recently (not chosen again)
##   unit_id: soldier whose body asks the navigation mesh for reachability
##   min_enemy_m: posts closer than this to `los`/`threat` are refused
## Returns up to `count` dictionaries {p, kind, protected, can_fire, los} (fewer when there is
## not enough good ground - the caller fills with spread positions).
func find_posts(count: int, center: Vector3, radius: float, threat: Vector3, opts := {}) -> Array:
	var t0 := Time.get_ticks_usec()
	searches += 1
	var mode: String = opts.get("mode", "fire")
	var los_to: Vector3 = opts.get("los", Vector3.INF)
	var reserved: Array = opts.get("reserved", [])
	var avoid: Array = opts.get("avoid", [])
	var uid: int = opts.get("unit_id", -1)
	var min_enemy: float = opts.get("min_enemy_m", 25.0)
	var line := sim.combat.line
	var cands: Array = sim.brain.cover_spots(center, radius, threat, center, max_candidates)
	# Open ground candidates in an arc across the threat direction, so a plan always has
	# somewhere to put people even where there is no cover at all.
	var tdir := Vector3(threat.x - center.x, 0.0, threat.z - center.z)
	tdir = tdir.normalized() if tdir.length() > 0.1 else Vector3.FORWARD
	var side := Vector3(-tdir.z, 0.0, tdir.x)
	for k in range(-3, 4):
		cands.append({"p": ground(center + side * k * post_spacing_m * 1.4 - tdir * 1.5), "kind": "open", "d": absf(k) * post_spacing_m * 1.4})
	var scored: Array = []
	for c: Dictionary in cands:
		var p: Vector3 = c.p
		evals += 1
		if not valid_ground(p):
			continue
		if _near_any(p, reserved, 2.0) or _near_any(p, avoid, 3.0):
			continue
		if threat.is_finite() and _flat(p, threat) < min_enemy:
			continue
		var ev := sim.brain._evaluate_spot(null, p, threat) if threat.is_finite() else {"protected": false, "can_fire": true}
		var los := true
		if los_to.is_finite():
			los = line.sight(p + Vector3.UP * 1.5, los_to + Vector3.UP * 1.2).visible or line.sight(p + Vector3.UP * 1.0, los_to + Vector3.UP * 1.0).visible
		var score := 0.0
		score += 3.0 if ev.protected else 0.0
		if mode == "fire":
			score += 2.0 if ev.can_fire else (0.5 if ev.protected else 0.0)
			score += 3.5 if los else -6.0
		else:
			score += 0.0 if ev.protected else -1.0
		score -= 0.045 * _flat(p, center)
		match String(c.kind):
			"structure":
				score += 1.2
			"rock":
				score += 0.8
			"terrain":
				score += 0.4
			"open":
				score -= 0.6
		scored.append({"p": p, "kind": c.kind, "protected": ev.protected, "can_fire": ev.can_fire, "los": los, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var out: Array = []
	for s: Dictionary in scored:
		if out.size() >= count:
			break
		if mode == "fire" and los_to.is_finite() and not s.los:
			continue
		var clash := false
		for o: Dictionary in out:
			if _flat(o.p, s.p) < post_spacing_m:
				clash = true
				break
		if clash:
			continue
		if uid >= 0 and not reachable(center, s.p, uid):
			continue
		out.append(s)
	var dt := Time.get_ticks_usec() - t0
	usec += dt
	usec_max = maxi(usec_max, dt)
	return out


## Fills `posts` (from find_posts) up to `count` with spread ground positions across `dir` around
## `center` so every soldier of a plan has a distinct place.
func fill_open(posts: Array, count: int, center: Vector3, dir: Vector3, spacing := 3.2) -> Array:
	var out := posts.duplicate()
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.1 else Vector3.FORWARD
	var side := Vector3(-d.z, 0.0, d.x)
	var k := 0
	var guard := 0
	while out.size() < count and guard < 40:
		guard += 1
		var off := (k + 1) / 2 * (1 if k % 2 == 1 else -1)
		k += 1
		var p := nearest_valid(center + side * off * spacing, 8.0)
		if not p.is_finite():
			continue
		var clash := false
		for o: Dictionary in out:
			if _flat(o.p, p) < spacing * 0.7:
				clash = true
				break
		if not clash:
			out.append({"p": p, "kind": "open", "protected": false, "can_fire": true, "los": true, "score": 0.0})
	return out


## Pairs soldiers with posts so the paths cross little: both sorted across `axis` (the lateral
## axis of the plan); returns post indices per soldier index.
func assign(unit_positions: Array, posts: Array, axis: Vector3) -> Array:
	var ui: Array = range(unit_positions.size())
	var pi: Array = range(posts.size())
	ui.sort_custom(func(a: int, b: int) -> bool: return (unit_positions[a] as Vector3).dot(axis) < (unit_positions[b] as Vector3).dot(axis))
	pi.sort_custom(func(a: int, b: int) -> bool: return (posts[a].p as Vector3).dot(axis) < (posts[b].p as Vector3).dot(axis))
	var result: Array = []
	result.resize(unit_positions.size())
	for j in ui.size():
		result[ui[j]] = pi[mini(j, pi.size() - 1)]
	return result


func _near_any(p: Vector3, list: Array, r: float) -> bool:
	for q: Vector3 in list:
		if _flat(p, q) < r:
			return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

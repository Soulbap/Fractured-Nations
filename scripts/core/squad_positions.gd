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
			# AI-ASSAULT-01: a bound's posts are where the team covers the next bound from - cover it can also fire from
			# (judged by the same _evaluate_spot, no extra sight line). Plain cover hid the halted team from the enemy it was
			# meant to cover against: 20 aimed shots from halted attackers in a whole assault.
			if mode == "cover_fire" and ev.can_fire:
				score += 2.0
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


## GAMEPLAY-02 (controls) / COMBAT-COVER-03: positions for `count` soldiers placed by the player along the frontage a -> b (a
## right-drag, or the line cover_line_near found along a wall for a single click), facing `facing`. Company of Heroes style: the
## player points roughly, the squad finds the cover.
##  1. Nominal places evenly along the line (never closer than PLACE_GAP; a short line gives ranks behind it).
##  2. Cover spots round the line (CombatBrain.cover_spots: the lee faces and corners of walls, buildings, sandbags, rocks, logs,
##     terrain), each judged by CoverEval against the believed threats (`opts.threats`; none known: the facing, "assumed").
##  3. Soldiers and spots are paired best first over the whole squad (heavy before light cover, a line of fire, near the
##     soldier's nominal place - within `snap` m), never two within PLACE_GAP.
##  4. Soldiers left over look for cover farther out (`overflow` m from their place or the line: the squad stays together), the
##     rest stay on the line (on valid ground).
## Returns [{p, kind, protected, can_fire, level, fire, partial, concealed, assumed}] in the order along the line. Bounded: one cover
## search per call. opts: threats (Array of Vector3), snap (m; default from the spacing), overflow (m), ids (the soldiers placed:
## a spot another soldier stands on is skipped).
const PLACE_GAP := 1.3


func placement(count: int, a: Vector3, b: Vector3, facing: Vector3, cover := true, opts := {}) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var f := Vector3(facing.x, 0.0, facing.z)
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var seg := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := seg.length()
	var along := seg / length if length > 0.3 else Vector3(-f.z, 0.0, f.x)
	var mid := ground((a + b) * 0.5)
	# The line's places; a short line takes several ranks behind it.
	var per_rank := count if count <= 1 or length >= PLACE_GAP * (count - 1) else maxi(1, floori(length / PLACE_GAP) + 1)
	var ranks := ceili(float(count) / per_rank)
	var gap := length / (per_rank - 1) if per_rank > 1 else 0.0
	var nominal: Array = []
	for i in count:
		var r := i / per_rank
		var k := i % per_rank
		var in_rank := mini(per_rank, count - r * per_rank)
		var start := a + along * ((per_rank - in_rank) * gap * 0.5) if per_rank > 1 else mid
		nominal.append(ground(start + along * k * gap - f * r * PLACE_GAP * 1.2))
	var threats: Array = opts.get("threats", [])
	var assumed := mid + f * 120.0
	var main_threat: Vector3 = threats[0] if not threats.is_empty() else assumed
	var snap := float(opts.get("snap", clampf(gap * 0.45, 1.2, 3.0) if ranks == 1 else 1.2))
	var overflow := float(opts.get("overflow", snap + 5.0))
	var cands: Array = []
	if cover and sim.brain != null:
		for c: Dictionary in sim.brain.cover_spots(mid, length * 0.5 + overflow + 1.0, main_threat, mid, 72):
			var p: Vector3 = ground(c.p)
			if not valid_ground(p) or _occupied(p, opts.get("ids", [])):
				continue
			var ev := sim.brain.cover_eval.judge_all(p, threats, assumed)
			if int(ev.level) >= CoverEval.Level.LIGHT:
				cands.append(_place_rec(p, String(c.kind), ev))
	# Best pairs first over the whole squad: protection, fire, then nearness to the soldier's own place on the line.
	var chosen: Array = []
	chosen.resize(count)
	var taken: Array = []
	for pass_i in 2:
		var limit := snap if pass_i == 0 else overflow
		var pairs: Array = []
		for i in count:
			if chosen[i] != null:
				continue
			var want: Vector3 = nominal[i]
			for ci in cands.size():
				var c: Dictionary = cands[ci]
				var d := _flat(c.p, want)
				if pass_i == 1:
					d = minf(d, _seg_dist(c.p, a, b) + 1.0)
				if d > limit:
					continue
				var s := float(c.level) * 2.0 + (1.0 if int(c.fire) == CoverEval.Fire.CLEAR else 0.0) - d * (0.45 if pass_i == 0 else 0.7)
				pairs.append([s, i, ci])
		pairs.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
		var used := {}
		for e: Array in pairs:
			var i: int = e[1]
			var ci: int = e[2]
			if chosen[i] != null or used.has(ci):
				continue
			var c: Dictionary = cands[ci]
			if _near_any(c.p, taken, PLACE_GAP):
				continue
			chosen[i] = c
			used[ci] = true
			taken.append(c.p)
	for i in count:
		if chosen[i] != null:
			continue
		var want: Vector3 = nominal[i]
		var p := want if valid_ground(want) else nearest_valid(want, 4.0)
		if not p.is_finite():
			p = want
		# never two soldiers on one spot: step along the line until it is free
		var guard := 0
		while _near_any(p, taken, PLACE_GAP * 0.9) and guard < 6:
			guard += 1
			p = ground(p + along * PLACE_GAP * (1 if guard % 2 == 1 else -1) * guard)
		var ev := sim.brain.cover_eval.judge_all(p, threats, assumed) if cover and sim.brain != null else {}
		chosen[i] = _place_rec(p, "open", ev)
		taken.append(p)
	for i in count:
		var c: Dictionary = (chosen[i] as Dictionary).duplicate()
		c["assumed"] = threats.is_empty()
		out.append(c)
	# In the order along the line (place_plan pairs soldiers with places across the line's axis).
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return (x.p as Vector3).dot(along) < (y.p as Vector3).dot(along))
	return out


## Another soldier (not one of `ids`) stands within a metre of p.
func _occupied(p: Vector3, ids: Array) -> bool:
	for o: UnitState in sim.brain.units_near(p, 1.0):
		if o.alive and o.kind == UnitState.Kind.SOLDIER and not ids.has(o.id):
			return true
	return false


func _place_rec(p: Vector3, kind: String, ev: Dictionary) -> Dictionary:
	return {"p": p, "kind": kind, "protected": bool(ev.get("protected", false)), "can_fire": bool(ev.get("can_fire", true)),
		"level": int(ev.get("level", CoverEval.Level.UNKNOWN)), "fire": int(ev.get("fire", CoverEval.Fire.UNKNOWN)),
		"partial": bool(ev.get("partial", false)), "concealed": bool(ev.get("concealed", false)), "stand": bool(ev.get("stand", false))}


## COMBAT-COVER-03 single click: the line along the cover the player pointed at, or {} for open ground (a plain move). The solid
## (a wall, a building, a sandbag position, a rock, a log: box solids, structures and large rocks) nearest the click within `snap`
## m wins; the soldiers go to the face on the click's side (clicked on the solid itself: the face towards the squad), so the solid
## stands between them and the far side: `facing` points through it. The line is centred on the click along that face, as long as
## the squad needs (1.4 m a soldier) and no longer than the face. Returns {a, b, facing, kind, length, overflow}.
func cover_line_near(click: Vector3, squad_at: Vector3, count: int, snap: float) -> Dictionary:
	var best := {}
	var best_d := snap
	var line := sim.combat.line
	if line != null and line.vegetation != null:
		var bk := LineOfFire.BUCKET
		var seen := {}
		for bx in range(floori((click.x - snap - LineOfFire.REACH) / bk), floori((click.x + snap + LineOfFire.REACH) / bk) + 1):
			for bz in range(floori((click.z - snap - LineOfFire.REACH) / bk), floori((click.z + snap + LineOfFire.REACH) / bk) + 1):
				var cell := Vector2i(floori(bx * bk / line.vegetation.cell_size_m), floori(bz * bk / line.vegetation.cell_size_m))
				if not line.cell_ready(cell):
					line.warm(cell)
				var data: PackedFloat32Array = line._buckets.get(Vector2i(bx, bz), PackedFloat32Array())
				for i in range(0, data.size(), LineOfFire.STRIDE):
					var c := Vector3(data[i], data[i + 2], data[i + 1])
					if data[i + 5] > 1.5:
						if data[i + 4] < 0.5 or maxf(data[i + 7], data[i + 8]) < 0.6:
							continue
						var key := Vector4(data[i], data[i + 1], data[i + 6], data[i + 7])
						if seen.has(key):
							continue
						seen[key] = true
						var basis := Basis(Vector3.UP, data[i + 6])
						var d := _box_dist(click, c, basis, data[i + 7], data[i + 8])
						if d < best_d:
							best_d = d
							best = {"c": c, "basis": basis, "hx": data[i + 7], "hz": data[i + 8], "kind": "box"}
					elif data[i + 5] > 0.5 and data[i + 3] >= 0.9:
						var d := maxf(_flat(click, c) - data[i + 3], 0.0)
						if d < best_d:
							best_d = d
							best = {"c": c, "basis": Basis(), "hx": data[i + 3] * 0.8, "hz": data[i + 3] * 0.8, "kind": "rock"}
	var st := sim.structures
	if st != null and st.state != null and line != null:
		for e: Dictionary in line.structures_near(click, snap):
			var s := st.state.get_structure(int(e.id))
			if s == null or float(e.d) >= best_d:
				continue
			var def := StructureCatalog.get_def(s.type_id)
			if def == null:
				continue
			for ii in s.instances.size():
				if s.is_line() and s.is_removed(ii):
					continue
				var xf: Transform3D = s.instances[ii]
				if _flat(xf.origin, click) > snap + StructureManager.MAX_REACH:
					continue
				for box: AABB in def.get_collision_boxes():
					if box.size.y < 0.5:
						continue
					var bc := xf * Vector3(box.get_center().x, box.position.y, box.get_center().z)
					var basis := xf.basis.orthonormalized()
					var d := _box_dist(click, bc, basis, box.size.x * 0.5, box.size.z * 0.5)
					if d < best_d:
						best_d = d
						best = {"c": bc, "basis": basis, "hx": box.size.x * 0.5, "hz": box.size.z * 0.5, "kind": "structure"}
	if best.is_empty():
		return {}
	var basis: Basis = best.basis
	var centre: Vector3 = best.c
	var lc: Vector3 = basis.inverse() * (click - centre)
	var hx: float = best.hx
	var hz: float = best.hz
	if absf(lc.x) <= hx and absf(lc.z) <= hz:
		# On the solid itself: the face towards the squad.
		lc = basis.inverse() * (squad_at - centre)
	# The face the point lies beyond (relative to the box's proportions).
	var axis := 0 if absf(lc.z) / maxf(hz, 0.1) >= absf(lc.x) / maxf(hx, 0.1) else 1
	var side := signf(lc.z if axis == 0 else lc.x)
	if side == 0.0:
		side = 1.0
	var along_h := hx if axis == 0 else hz
	var across_h := hz if axis == 0 else hx
	var want := maxf(count - 1, 0) * 1.4 * 0.5
	var span_h := minf(want, along_h + 0.4)
	var at := clampf(lc.x if axis == 0 else lc.z, -along_h - 0.4 + span_h, along_h + 0.4 - span_h)
	var off := across_h + 1.0
	var pa := centre + basis * CoverEval._local(axis, at - span_h, side * off)
	var pb := centre + basis * CoverEval._local(axis, at + span_h, side * off)
	var nrm := basis * CoverEval._local(axis, 0.0, -side)
	return {"a": ground(pa), "b": ground(pb), "facing": Vector3(nrm.x, 0.0, nrm.z).normalized(), "kind": String(best.kind),
		"length": span_h * 2.0, "overflow": maxf(want - span_h, 0.0)}


## The believed threats a squad of faction f near p is judged against: `extra` (its assessed threat) first, then its faction's
## contacts within r (IntelSim - never true positions), best first, at most `n`, at least 35 degrees apart as seen from p.
func threats_for(faction: int, p: Vector3, r := 350.0, n := 3, extra := Vector3.INF) -> Array:
	var out: Array = []
	if extra.is_finite():
		out.append(extra)
	var war := sim.war
	if war != null and war.enabled and war.intel != null:
		for c: ContactState in war.intel.contacts_near(faction, p, r):
			if out.size() >= n:
				break
			var dir := Vector2(c.pos.x - p.x, c.pos.z - p.z)
			var apart := true
			for q: Vector3 in out:
				if absf(rad_to_deg(dir.angle_to(Vector2(q.x - p.x, q.z - p.z)))) < 35.0:
					apart = false
					break
			if apart:
				out.append(c.pos)
	return out


## Distance on the ground from p to the footprint of a box (0 inside).
static func _box_dist(p: Vector3, c: Vector3, basis: Basis, hx: float, hz: float) -> float:
	var l := basis.inverse() * (p - c)
	return Vector2(maxf(absf(l.x) - hx, 0.0), maxf(absf(l.z) - hz, 0.0)).length()


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var l2 := ab.length_squared()
	var t := clampf(ap.dot(ab) / l2, 0.0, 1.0) if l2 > 1e-6 else 0.0
	return (ap - ab * t).length()


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


## GAMEPLAY-03A: how much of a post the enemy can see from where it is believed to be - the share of three viewpoints
## (the believed threat's bearing and 25 degrees either side, 60-300 m out, at eye height) from which a soldier at the post
## is visible at the chest or the head, by the same sight rule soldiers use (terrain, structures, trunks, foliage layers).
## 0 = hidden from all, 1 = seen from all. Cover (what stops bullets) is measured separately (CombatBrain._evaluate_spot).
## One sight per viewpoint at 1.35 m (between chest and head); cached per 2 m post cell and 25 m threat cell for a minute
## (the ground and the trees do not move; a new structure clears the cache).
func exposure(p: Vector3, threat: Vector3) -> float:
	if not threat.is_finite():
		return 0.5
	var key := Vector4i(roundi(p.x / 2.0), roundi(p.z / 2.0), roundi(threat.x / 25.0), roundi(threat.z / 25.0))
	var now := sim.state.time
	var hit: Array = _exposure_cache.get(key, [])
	if not hit.is_empty() and now - float(hit[1]) < 60.0 and int(hit[2]) == sim.state.construction.count():
		exposure_cached += 1
		return float(hit[0])
	exposure_evals += 1
	var t0 := Time.get_ticks_usec()
	var line := sim.combat.line
	var d := clampf(_flat(p, threat), 60.0, 300.0)
	var dir := Vector3(threat.x - p.x, 0.0, threat.z - p.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var seen := 0
	for ang: float in [0.0, 25.0, -25.0]:
		var v := ground(p + dir.rotated(Vector3.UP, deg_to_rad(ang)) * d) + Vector3.UP * 1.6
		if line.sight(v, p + Vector3.UP * 1.35).visible:
			seen += 1
	exposure_usec += Time.get_ticks_usec() - t0
	if _exposure_cache.size() > 4000:
		_exposure_cache.clear()
	_exposure_cache[key] = [seen / 3.0, now, sim.state.construction.count()]
	return seen / 3.0


var exposure_evals := 0
var exposure_cached := 0
var exposure_usec := 0
var _exposure_cache := {}


func _near_any(p: Vector3, list: Array, r: float) -> bool:
	for q: Vector3 in list:
		if _flat(p, q) < r:
			return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Fortification slots (GAMEPLAY-01C) ---------------------------------------------------

var slot_searches := 0
var slot_usec := 0
var slot_usec_max := 0


## Free fortification slots (DefenceDefs) of faction's operational structures within radius of center, best first: each
## {p, kind "slot", protected, can_fire, los, slot, access, facing, elevated, role, score}. A slot is taken when a living
## soldier of the faction holds it in his record (UnitState.fort_slot), except soldiers in `mine` (unit id -> true: the
## squad that is planning may keep its own slots). With a threat direction, slots whose sector does not face it are left
## out; without one, slots are spread round center. `base_anchor` decides which side of a wall is "behind" it; dist_w how much
## nearer slots are preferred (score per metre: a defence of a spot wants the nearest, a garrison the whole base).
func fort_slots(center: Vector3, radius: float, faction: int, threat: Vector3, mine := {}, base_anchor := Vector3.INF, dist_w := 0.01) -> Array:
	var t0 := Time.get_ticks_usec()
	slot_searches += 1
	var taken := {}
	sim.brain._ensure_grid()
	for u: UnitState in sim.brain._near(center, radius + 12.0):
		if u.faction == faction and u.fort_slot != "" and not mine.has(u.id):
			taken[u.fort_slot] = true
	var tdir := Vector3.ZERO
	if threat.is_finite():
		tdir = Vector3(threat.x - center.x, 0.0, threat.z - center.z)
		tdir = tdir.normalized() if tdir.length() > 1.0 else Vector3.ZERO
	var out: Array = []
	for s: StructureState in sim.state.construction.structures.values():
		if s.faction != faction or not DefenceDefs.has(s.type_id) or not s.is_operational() or s.instances.is_empty():
			continue
		var c := s.site_center()
		if _flat(c, center) > radius + (60.0 if s.is_line() else 8.0):
			continue
		for e: Dictionary in slots_of_structure(s, base_anchor):
			if taken.has(e.slot) or _flat(e.p, center) > radius:
				continue
			var score := -dist_w * _flat(e.p, center)
			if tdir != Vector3.ZERO:
				var dot: float = (e.facing as Vector3).dot(tdir)
				if dot < cos(deg_to_rad(minf(float(e.arc) * 0.5 + 25.0, 179.0))):
					continue
				score += 2.0 * dot
			if bool(e.elevated):
				score += 0.6
			e["score"] = score
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var dt := Time.get_ticks_usec() - t0
	slot_usec += dt
	slot_usec_max = maxi(slot_usec_max, dt)
	return out


## Every slot of one structure in world space (taken or not), as fort_slots returns them (without a score). Lines: behind
## every n-th module, on the side towards base_anchor (both sides when there is none).
func slots_of_structure(s: StructureState, base_anchor := Vector3.INF) -> Array:
	# The slots of a structure only change when it or its surroundings do (its modules, owner, other structures placed or
	# removed): cached per structure.
	var key := "%d|%d|%d|%d|%s" % [s.instances.size(), s.removed.size(), s.faction, sim.state.construction.count(), str(s.instances[0].origin) if not s.instances.is_empty() else ""]
	var c: Dictionary = _slot_cache.get(s.id, {})
	if c.get("key", "") != key:
		c = {"key": key, "list": _compute_slots(s)}
		_slot_cache[s.id] = c
	var out: Array = []
	for e: Dictionary in c.list:
		if base_anchor.is_finite() and e.has("mirror") and _flat(e.p, base_anchor) > _flat(e.mirror, base_anchor):
			continue
		out.append(e.duplicate())
	return out


var _slot_cache := {}


func _compute_slots(s: StructureState) -> Array:
	var out: Array = []
	if DefenceDefs.is_line(s.type_id):
		var rule := DefenceDefs.line_rule(s.type_id)
		var every := int(rule.every)
		for i in s.instances.size():
			if s.is_removed(i) or i % every != every / 2:
				continue
			var xf: Transform3D = s.instances[i]
			for side in 2:
				var sgn := 1.0 if side == 0 else -1.0
				var p: Vector3 = xf * Vector3(0.0, 0.0, sgn * float(rule.back))
				var facing := (xf.origin - p)
				facing.y = 0.0
				facing = facing.normalized()
				var g := ground(p)
				if not _slot_ground(g):
					continue
				out.append({"p": g, "kind": "slot", "protected": true, "can_fire": true, "los": true, "slot": "%d:%d:%d" % [s.id, i, side],
					"access": g, "facing": facing, "arc": float(rule.arc), "elevated": false, "role": "", "structure": s.id,
					"mirror": xf * Vector3(0.0, 0.0, -sgn * float(rule.back))})
		return out
	var xf0: Transform3D = s.instances[0]
	var slots := DefenceDefs.slots_of(s.type_id)
	for k in slots.size():
		var d: Dictionary = slots[k]
		var lp: Vector3 = d.p
		var elevated := lp.y > 0.5
		var p: Vector3 = xf0 * lp
		if not elevated:
			p = ground(p)
		var acc: Vector3 = xf0 * (d.get("access", lp) as Vector3)
		acc = ground(acc)
		if not valid_ground(acc):
			acc = nearest_valid(acc, 6.0)
			if not acc.is_finite():
				continue
		var facing := xf0.basis * DefenceDefs.yaw_dir(float(d.yaw))
		facing.y = 0.0
		out.append({"p": p, "kind": "slot", "protected": true, "can_fire": true, "los": true, "slot": "%d:%d" % [s.id, k], "access": acc,
			"facing": facing.normalized(), "arc": float(d.get("arc", 120.0)), "elevated": elevated, "role": String(d.get("role", "")), "structure": s.id})
	return out


## The world slot a key names, or {} when it no longer exists or cannot be used by `faction` (structure gone, not
## operational, captured, module removed).
## Only that one slot is computed (soldiers in slots ask every tactics step: a HESCO perimeter has hundreds).
func slot_by_key(key: String, faction: int) -> Dictionary:
	var parts := key.split(":")
	if parts.size() < 2:
		return {}
	var s := sim.state.construction.get_structure(int(parts[0]))
	if s == null or s.faction != faction or not s.is_operational() or s.instances.is_empty():
		return {}
	var k := int(parts[1])
	if DefenceDefs.is_line(s.type_id):
		if parts.size() < 3 or k < 0 or k >= s.instances.size() or s.is_removed(k):
			return {}
		var rule := DefenceDefs.line_rule(s.type_id)
		var xf: Transform3D = s.instances[k]
		var sgn := 1.0 if int(parts[2]) == 0 else -1.0
		var p: Vector3 = ground(xf * Vector3(0.0, 0.0, sgn * float(rule.back)))
		var facing := xf.origin - p
		facing.y = 0.0
		return {"p": p, "slot": key, "access": p, "facing": facing.normalized(), "arc": float(rule.arc), "elevated": false, "role": "", "structure": s.id}
	var slots := DefenceDefs.slots_of(s.type_id)
	if k < 0 or k >= slots.size():
		return {}
	var d: Dictionary = slots[k]
	var xf0: Transform3D = s.instances[0]
	var lp: Vector3 = d.p
	var elevated := lp.y > 0.5
	var p0: Vector3 = xf0 * lp
	var facing0 := xf0.basis * DefenceDefs.yaw_dir(float(d.yaw))
	facing0.y = 0.0
	var acc := ground(xf0 * (d.get("access", lp) as Vector3))
	if not valid_ground(acc):
		acc = nearest_valid(acc, 6.0)  # the same access point the slot search gave
		if not acc.is_finite():
			return {}
	return {"p": p0 if elevated else ground(p0), "slot": key, "access": acc, "facing": facing0.normalized(),
		"arc": float(d.get("arc", 120.0)), "elevated": elevated, "role": String(d.get("role", "")), "structure": s.id}


## A slot behind a wall: dry, not inside a footprint (a soldier's own radius only: slots stand close to their wall).
func _slot_ground(p: Vector3) -> bool:
	var st := sim.structures
	if st != null and (st._wet(p.x, p.z, p.y - 0.25) or st.blocks_point(Vector2(p.x, p.z), 0.3)):
		return false
	return true

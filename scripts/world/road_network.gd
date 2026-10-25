## The road network (WORLD-PLAYTEST-01): the one road definition the game reads.
##
## World roads come from the generated world's roads.json, the same file the world build
## turned into Road Generator meshes, terrain grading and paint. Player-built roads are
## construction records (StructureState of a StructureDef.Surface.ROAD type in
## WorldState.construction, saved with the base); their graded centre line is part of the
## record, so this class needs no terrain. Every consumer asks this class:
##   - StrategicRoutes marks road cells (cheaper travel, cut into slopes) and re-marks the
##     cells of a changed area when a road is built or removed (`changed`);
##   - construction snaps new roads to roads, road ends and junctions (nearest());
##   - StructureManager grades and paints built roads from the same records.
## Paved areas (StructureDef.Surface.AREA: vehicle yards, motor pools) are not roads: they
## are graded and paved by StructureManager but never become road cells here, so they open
## no navigation shortcut. Buildings never need a road; roads only make travel faster.
## Vehicles will route on the same polylines (class, width and grade per road).
class_name RoadNetwork
extends RefCounted

## Roads were added or removed inside rect (XZ, metres).
signal changed(rect: Rect2)
## NAVIGATION N1-C1: the state of a bridge changed (set_bridge_state / load_bridge_states). Navigation owners drop what they derived
## from it; nothing reads a second copy of the state.
signal bridge_changed(bridge: Bridge)

## Spatial index cell (m).
const GRID := 64.0
## NAVIGATION N1-C1 bridge states. OPEN: usable. CLOSED: temporarily shut (traffic stops, the bridge can be opened again).
## DISABLED: out of service. Both are logical states only: the deck stays standing and visible, and a vehicle already on the
## deck finishes its crossing; nothing new enters (see Bridge.is_open and blocking_bridge_at).
enum BridgeState { OPEN, CLOSED, DISABLED }
const BRIDGE_STATE_NAMES: Array[String] = ["open", "closed", "disabled"]
## A vehicle needs this much deck width beyond its own body (m) to use a bridge.
const DECK_CLEARANCE_M := 1.0
## Travel cost per metre on the strategic grid for the generator's road classes.
const WORLD_COST := {&"primary": 0.4, &"secondary": 0.42, &"local": 0.45, &"street": 0.45, &"track": 0.5}


class Road:
	## World roads: -(index + 1); built roads: the structure id.
	var key := 0
	var name := ""
	var cls: StringName
	## Centre line, y = road surface (world: the graded profile; built: the record profile).
	var points := PackedVector3Array()
	## Full surface width (carriageway and shoulders), m.
	var width := 0.0
	## Bridge spans as [first, last] point indices (world roads only).
	var bridges: Array = []
	## ROAD-QUALITY-01: the world road has a Road Generator mesh (roads.json "mesh"; its collider is the surface soldiers walk
	## on), and the point indices of its culverts.
	var mesh := false
	var culverts: Array = []
	var built := false
	var travel_cost := 0.45
	var bounds := Rect2()

	func update_bounds() -> void:
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in points:
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
		bounds = Rect2(lo, hi - lo).grow(width * 0.5)


## One bridge of the world roads: a span of a road.json road ("bridges": [first, last] point indices). Identity is the road's
## index in roads.json plus the span's index, so it survives save/load, restarts and near/far tiers (the generated world is
## never regenerated; a regenerated world with other roads is detected on load by the saved bridge centre).
class Bridge:
	var id := ""
	var name := ""
	var road_key := 0
	var first := 0
	var last := 0
	## Deck width (m): the road's full surface width. No load rating exists in the data, so none is modelled.
	var width := 0.0
	var length_m := 0.0
	var center := Vector3.ZERO
	## Deck area (XZ), grown by the deck's half width.
	var bounds := Rect2()
	var state := RoadNetwork.BridgeState.OPEN
	var reason := ""
	## Deck segments [a2: Vector2, b2: Vector2, half width] for the exact membership test.
	var segs: Array = []

	func is_open() -> bool:
		return state == RoadNetwork.BridgeState.OPEN

	func state_name() -> String:
		return RoadNetwork.BRIDGE_STATE_NAMES[state]

	## True when a vehicle of this width fits on the deck.
	func admits(vehicle_width: float) -> bool:
		return vehicle_width + RoadNetwork.DECK_CLEARANCE_M <= width

	## True when q (XZ) lies on the deck strip: between the first and last deck point along the road and within half the deck
	## width (plus pad) of the centre line. Unlike the physical deck test (a capsule that reaches 4.5 m onto the bank at each
	## end) this has square ends, so a walker at the lip is not yet "on" the deck.
	func strip_contains(q: Vector2, pad := 0.0) -> bool:
		var n := segs.size()
		for i in n:
			var s: Array = segs[i]
			var a: Vector2 = s[0]
			var ab: Vector2 = (s[1] as Vector2) - a
			var l2 := maxf(ab.length_squared(), 1e-6)
			var t := (q - a).dot(ab) / l2
			var lo := -pad / sqrt(l2) if i == 0 else 0.0
			var hi := 1.0 + pad / sqrt(l2) if i == n - 1 else 1.0
			if (i == 0 and t < lo) or (i == n - 1 and t > hi):
				continue
			t = clampf(t, 0.0, 1.0)
			if q.distance_to(a + ab * t) <= (s[2] as float) + pad:
				return true
		return false

	## Distance (m) from p (XZ) to the deck centre line.
	func distance_to(q: Vector2) -> float:
		var best := INF
		for s: Array in segs:
			var a: Vector2 = s[0]
			var ab: Vector2 = (s[1] as Vector2) - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			best = minf(best, q.distance_to(a + ab * t))
		return best


var world: Array[Road] = []
## NAVIGATION N1-C1: every bridge of the world roads, id -> Bridge, and the ones that are not open.
var bridges: Array[Bridge] = []
var _bridge_by_id := {}
var _blocking: Array[Bridge] = []
## structure id -> Road
var built := {}
var construction: ConstructionState
## Vector2i -> Array[Road]
var _grid := {}
## Bridge decks of the world roads: [a, b (Vector3, road surface), half width, bounds].
var _decks: Array = []
## Vector2i (GRID cell) -> Array of _decks entries (one cell lookup per abstract step).
var _deck_grid := {}


# --- Building the network ------------------------------------------------------------

## Reads the world roads of a generated world (src: its source folder, with the slash).
func load_world(src: String) -> int:
	world.clear()
	_grid.clear()
	_decks.clear()
	_deck_grid.clear()
	bridges.clear()
	_bridge_by_id.clear()
	_blocking.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(src + "roads.json"))
	if data is Dictionary:
		# WORLD-SETTLEMENT-02: the settlement layer replaces the generated streets with its local roads.
		data = SettlementLayer.patch_roads(data, src.trim_suffix("/").get_base_dir().get_file())
		for i in data.roads.size():
			var r: Dictionary = data.roads[i]
			if r.points.size() < 2:
				continue
			var road := Road.new()
			road.key = -(i + 1)
			road.name = r.name
			road.cls = StringName(r["class"])
			for p: Array in r.points:
				road.points.append(Vector3(p[0], p[1], p[2]))
			road.width = float(r.lane_m) * float(r.lanes) + 2.0 * float(r.shoulder_m)
			road.bridges = r.get("bridges", [])
			road.mesh = bool(r.get("mesh", false))
			road.culverts = r.get("culverts", [])
			road.travel_cost = WORLD_COST.get(road.cls, 0.45)
			road.update_bounds()
			world.append(road)
			_index(road)
			for si in road.bridges.size():
				var sp: Array = road.bridges[si]
				var br := Bridge.new()
				br.id = "bridge_r%d_s%d" % [i, si]
				br.name = ("%s bridge" % road.name) if road.bridges.size() == 1 else ("%s bridge %d" % [road.name, si + 1])
				br.road_key = road.key
				br.first = int(sp[0])
				br.last = int(sp[1])
				br.width = road.width
				br.center = (road.points[br.first] + road.points[br.last]) * 0.5
				bridges.append(br)
				_bridge_by_id[br.id] = br
				for k in range(int(sp[0]), int(sp[1])):
					# Road Generator surface 0.2 m above the profile (paved), deck flush else.
					var lift := 0.2 if r.mesh else 0.05
					var a := road.points[k] + Vector3.UP * lift
					var b := road.points[k + 1] + Vector3.UP * lift
					var bb := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(road.width * 0.5 + 0.5)
					var entry := [a, b, road.width * 0.5 + 0.5, bb, br]
					br.length_m += Vector2(b.x - a.x, b.z - a.z).length()
					br.segs.append([Vector2(a.x, a.z), Vector2(b.x, b.z), road.width * 0.5 + 0.5])
					br.bounds = bb if br.segs.size() == 1 else br.bounds.merge(bb)
					_decks.append(entry)
					for gx in range(floori(bb.position.x / GRID), floori(bb.end.x / GRID) + 1):
						for gz in range(floori(bb.position.y / GRID), floori(bb.end.y / GRID) + 1):
							if not _deck_grid.has(Vector2i(gx, gz)):
								_deck_grid[Vector2i(gx, gz)] = []
							_deck_grid[Vector2i(gx, gz)].append(entry)
	for r in built.values():
		_index(r)
	return world.size()


## Follows the built roads of a construction state (existing ones are added now).
func bind_construction(c: ConstructionState) -> void:
	if construction:
		construction.structure_added.disconnect(_on_added)
		construction.structure_removed.disconnect(_on_removed)
		construction.cleared.disconnect(_on_cleared)
	construction = c
	c.structure_added.connect(_on_added)
	c.structure_removed.connect(_on_removed)
	c.cleared.connect(_on_cleared)
	_on_cleared()
	for s in c.all():
		_on_added(s)


func _on_added(s: StructureState) -> void:
	var def := StructureCatalog.get_def(s.type_id)
	if def == null or def.surface != StructureDef.Surface.ROAD or s.profile.size() < 2:
		return
	var road := Road.new()
	road.key = s.id
	road.name = "%s #%d" % [def.display_name, s.id]
	road.cls = def.id
	road.points = s.profile
	road.width = def.surface_width
	road.built = true
	road.travel_cost = def.travel_cost
	road.update_bounds()
	built[s.id] = road
	_index(road)
	changed.emit(road.bounds)


func _on_removed(s: StructureState) -> void:
	var road: Road = built.get(s.id)
	if road == null:
		return
	built.erase(s.id)
	_unindex(road)
	changed.emit(road.bounds)


func _on_cleared() -> void:
	if built.is_empty():
		return
	var rect := Rect2()
	var first := true
	for road: Road in built.values():
		_unindex(road)
		rect = road.bounds if first else rect.merge(road.bounds)
		first = false
	built.clear()
	changed.emit(rect)


func all_roads() -> Array[Road]:
	var out: Array[Road] = world.duplicate()
	for r: Road in built.values():
		out.append(r)
	return out


func _cells_of(r: Road) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var b := r.bounds
	for x in range(floori(b.position.x / GRID), floori(b.end.x / GRID) + 1):
		for z in range(floori(b.position.y / GRID), floori(b.end.y / GRID) + 1):
			out.append(Vector2i(x, z))
	return out


func _index(r: Road) -> void:
	for c in _cells_of(r):
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append(r)


func _unindex(r: Road) -> void:
	for c in _cells_of(r):
		var list: Array = _grid.get(c, [])
		list.erase(r)
		if list.is_empty():
			_grid.erase(c)


# --- Queries --------------------------------------------------------------------------

## Roads whose bounds touch rect.
func roads_in(rect: Rect2) -> Array[Road]:
	var seen := {}
	var out: Array[Road] = []
	for x in range(floori(rect.position.x / GRID), floori(rect.end.x / GRID) + 1):
		for z in range(floori(rect.position.y / GRID), floori(rect.end.y / GRID) + 1):
			for r: Road in _grid.get(Vector2i(x, z), []):
				if not seen.has(r) and r.bounds.intersects(rect):
					seen[r] = true
					out.append(r)
	return out


## The closest point on any road centre line within radius of p (XZ):
## {pos: Vector3 (y = road surface), dir: Vector2 (along the road), road: Road,
##  segment: int, t: float, dist: float, end: int (-1 none, 0 first point, 1 last point)}
## or {} when nothing is in reach. Road ends within end_snap_m win over the line, so a new
## road continues an existing one instead of meeting it a metre short.
func nearest(p: Vector3, radius: float, exclude_key := 0, end_snap_m := 6.0) -> Dictionary:
	var q := Vector2(p.x, p.z)
	var line_best := {}
	var line_d := radius
	var end_best := {}
	var end_d := minf(radius, end_snap_m)
	for r: Road in roads_in(Rect2(q, Vector2.ZERO).grow(radius)):
		if r.key == exclude_key:
			continue
		var pts := r.points
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var ab := b - a
			var l2 := ab.length_squared()
			var t := 0.0 if l2 < 1e-6 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
			var c := a + ab * t
			var d := q.distance_to(c)
			if d < line_d:
				line_d = d
				line_best = {"pos": Vector3(c.x, lerpf(pts[i].y, pts[i + 1].y, t), c.y),
					"dir": ab.normalized() if l2 > 1e-6 else Vector2.RIGHT, "road": r, "segment": i, "t": t, "dist": d, "end": -1}
		for e in [0, 1]:
			var ep := pts[0] if e == 0 else pts[pts.size() - 1]
			var de := q.distance_to(Vector2(ep.x, ep.z))
			if de < end_d:
				end_d = de
				var other := pts[1] if e == 0 else pts[pts.size() - 2]
				end_best = {"pos": ep, "dir": Vector2(ep.x - other.x, ep.z - other.z).normalized(), "road": r,
					"segment": 0 if e == 0 else pts.size() - 2, "t": float(e), "dist": de, "end": e}
	return end_best if not end_best.is_empty() else line_best


## Height of the bridge deck at p (XZ), NAN when p is not on a bridge. The abstract tier
## walks over bridges with it (the terrain under a deck is the river channel).
func deck_height(p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	for d: Array in _deck_grid.get(Vector2i(floori(p.x / GRID), floori(p.z / GRID)), []):
		if not (d[3] as Rect2).has_point(q):
			continue
		var a: Vector3 = d[0]
		var b: Vector3 = d[1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if q.distance_to(a2 + ab * t) <= d[2]:
			return lerpf(a.y, b.y, t)
	return NAN


## The bridge whose deck lies under p (XZ), within `pad` metres of the deck edge; null when none. Open or not.
func bridge_at(p: Vector3, pad := 0.0) -> Bridge:
	var q := Vector2(p.x, p.z)
	var gx := floori(p.x / GRID)
	var gz := floori(p.z / GRID)
	var reach := 0 if pad <= 0.0 else ceili(pad / GRID)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for d: Array in _deck_grid.get(Vector2i(gx + dx, gz + dz), []):
				if pad <= 0.0 and not (d[3] as Rect2).has_point(q):
					continue
				var a: Vector3 = d[0]
				var b: Vector3 = d[1]
				var a2 := Vector2(a.x, a.z)
				var ab := Vector2(b.x, b.z) - a2
				var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				if q.distance_to(a2 + ab * t) <= d[2] + pad:
					return d[4]
	return null


## The closed or disabled bridge whose deck lies under p (within pad); null when p is on no blocked deck. This is the one test
## navigation uses to refuse a deck; `deck_height` keeps answering for the physical deck (a vehicle on it still has ground).
func blocking_bridge_at(p: Vector3, pad := 0.0) -> Bridge:
	if _blocking.is_empty():
		return null
	var q := Vector2(p.x, p.z)
	for b: Bridge in _blocking:
		if not b.bounds.grow(pad).has_point(q):
			continue
		if b.strip_contains(q, pad):
			return b
	return null


## False when p lies on the deck of a closed or disabled bridge.
func deck_open(p: Vector3) -> bool:
	return _blocking.is_empty() or blocking_bridge_at(p) == null


func blocked_bridge_count() -> int:
	return _blocking.size()


func blocked_bridges() -> Array[Bridge]:
	return _blocking


func get_bridge(id: String) -> Bridge:
	return _bridge_by_id.get(id)


## Bridges whose deck area touches rect.
func bridges_in(rect: Rect2) -> Array[Bridge]:
	var out: Array[Bridge] = []
	for b: Bridge in bridges:
		if b.bounds.intersects(rect):
			out.append(b)
	return out


## The one writer of a bridge's state. Returns false for an unknown bridge or no change. `why` is shown with the state.
func set_bridge_state(id: String, state: BridgeState, why := "") -> bool:
	var b: Bridge = _bridge_by_id.get(id)
	if b == null or (b.state == state and b.reason == why):
		return false
	var was_open := b.is_open()
	b.state = state
	b.reason = why if state != BridgeState.OPEN else ""
	if b.is_open():
		_blocking.erase(b)
	elif was_open:
		_blocking.append(b)
	bridge_changed.emit(b)
	return true


## Saved form: only the bridges that are not open ({id: {"state", "why", "name", "c": [x, z]}}). The centre guards against a
## regenerated world whose roads (and so bridge ids) differ.
func bridge_states() -> Dictionary:
	var out := {}
	for b: Bridge in _blocking:
		out[b.id] = {"state": int(b.state), "why": b.reason, "name": b.name, "c": [snappedf(b.center.x, 0.1), snappedf(b.center.z, 0.1)]}
	return out


## Applies saved states: the bridges in `d` take their state, all others are open. Returns the number of bridges whose state
## changed. A saved entry whose id is unknown or whose centre moved more than 5 m is ignored with a warning.
func load_bridge_states(d: Dictionary) -> int:
	var changed_n := 0
	var wanted := {}
	for id in d:
		var b: Bridge = _bridge_by_id.get(String(id))
		var e: Dictionary = d[id]
		var c: Array = e.get("c", [])
		if b == null or (c.size() == 2 and Vector2(b.center.x - float(c[0]), b.center.z - float(c[1])).length() > 5.0):
			push_warning("RoadNetwork: saved state of unknown bridge %s ignored" % id)
			continue
		wanted[b.id] = e
	for b: Bridge in bridges:
		var e: Dictionary = wanted.get(b.id, {})
		var s: int = int(e.get("state", BridgeState.OPEN))
		if set_bridge_state(b.id, s, String(e.get("why", ""))):
			changed_n += 1
	return changed_n


## First point (index >= from_i) of a polyline that lies on a closed or disabled deck, skipping the deck `except` (the one the
## traveller stands on). {index, bridge} or {}. Points are tested against the blocked decks only, so it costs nothing while all
## bridges are open.
func blocked_on_route(pts: PackedVector3Array, from_i := 0, except: Bridge = null, pad := 0.0) -> Dictionary:
	if _blocking.is_empty():
		return {}
	for k in range(maxi(from_i, 0), pts.size()):
		var b := blocking_bridge_at(pts[k], pad)
		if b != null and b != except:
			return {"index": k, "bridge": b}
	return {}


## A point beside a bridge (within reach of a deck, off it) moved sideways onto the deck,
## y = deck surface; INF when no deck is in reach. A column marching over a bridge keeps
## its file offsets on land; over the river the soldiers close up onto the deck.
func onto_deck(p: Vector3, reach := 25.0) -> Vector3:
	var q := Vector2(p.x, p.z)
	var best := Vector3.INF
	var best_d := INF
	for gx in range(floori((p.x - reach) / GRID), floori((p.x + reach) / GRID) + 1):
		for gz in range(floori((p.z - reach) / GRID), floori((p.z + reach) / GRID) + 1):
			for d: Array in _deck_grid.get(Vector2i(gx, gz), []):
				# N1-C1: nobody is moved onto the deck of a closed or disabled bridge.
				if not (d[4] as Bridge).is_open():
					continue
				var a: Vector3 = d[0]
				var b: Vector3 = d[1]
				var a2 := Vector2(a.x, a.z)
				var ab := Vector2(b.x, b.z) - a2
				var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var c := a2 + ab * t
				var dist := q.distance_to(c)
				if dist < reach and dist < best_d:
					best_d = dist
					var half: float = d[2] - 1.0
					var off := q - c
					if off.length() > half:
						off = off.normalized() * half
					var r := c + off
					best = Vector3(r.x, lerpf(a.y, b.y, t), r.y)
	return best


## True when p lies on a road surface (within half its width plus margin).
func on_road(p: Vector3, margin := 0.0) -> bool:
	var n := nearest(p, 40.0, 0, 0.0)
	return not n.is_empty() and n.dist <= (n.road as Road).width * 0.5 + margin


func total_length_m(only_built := false) -> float:
	var total := 0.0
	for r: Road in (built.values() if only_built else all_roads()):
		total += length_of(r.points)
	return total


# --- Geometry shared with construction ----------------------------------------------------

## Centripetal Catmull-Rom curve through the control points (XZ), sampled about every
## `step` metres; y is interpolated linearly between the control points (callers replace
## it with the graded profile). Two control points give a straight road.
static func spline(ctrl: PackedVector3Array, step := 2.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ctrl.size()
	if n < 2:
		return ctrl.duplicate()
	for i in n - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, n - 1)]
		if i == 0:
			p0 = p1 * 2.0 - p2
		if i + 2 > n - 1:
			p3 = p2 * 2.0 - p1
		var seg := Vector2(p2.x - p1.x, p2.z - p1.z).length()
		var k := maxi(1, ceili(seg / step))
		for j in k:
			var t := float(j) / k
			var c := _catmull(Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z), Vector2(p3.x, p3.z), t)
			out.append(Vector3(c.x, lerpf(p1.y, p2.y, t), c.y))
	out.append(ctrl[n - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	# Centripetal parametrisation (alpha 0.5): no loops or cusps on uneven spacing.
	var t0 := 0.0
	var t1 := t0 + pow(maxf(p0.distance_to(p1), 0.01), 0.5)
	var t2 := t1 + pow(maxf(p1.distance_to(p2), 0.01), 0.5)
	var t3 := t2 + pow(maxf(p2.distance_to(p3), 0.01), 0.5)
	var u := lerpf(t1, t2, t)
	var a1 := p0 * ((t1 - u) / (t1 - t0)) + p1 * ((u - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - u) / (t2 - t1)) + p2 * ((u - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - u) / (t3 - t2)) + p3 * ((u - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - u) / (t2 - t0)) + a2 * ((u - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - u) / (t3 - t1)) + a3 * ((u - t1) / (t3 - t1))
	return b1 * ((t2 - u) / (t2 - t1)) + b2 * ((u - t1) / (t2 - t1))


## Road profile along a sampled centre line whose y is the ground: a moving average over
## smooth_m, the grade limited to max_grade, pinned heights kept exactly (index -> y, used
## where the road joins another road). The same rules as the world generator's grading.
static func grade(line: PackedVector3Array, max_grade: float, pins := {}, smooth_m := 24.0) -> PackedVector3Array:
	var n := line.size()
	var out := line.duplicate()
	if n < 2:
		return out
	var seg := PackedFloat32Array()
	seg.resize(n - 1)
	var total := 0.0
	for i in n - 1:
		seg[i] = maxf(Vector2(line[i + 1].x - line[i].x, line[i + 1].z - line[i].z).length(), 0.05)
		total += seg[i]
	var ds := total / (n - 1)
	var win := maxi(1, int(smooth_m * 0.5 / ds))
	var h := PackedFloat32Array()
	h.resize(n)
	for i in n:
		h[i] = line[i].y
	for _pass in 3:
		var sm := h.duplicate()
		for i in n:
			var a := maxi(0, i - win)
			var b := mini(n - 1, i + win)
			var acc := 0.0
			for j in range(a, b + 1):
				acc += h[j]
			sm[i] = acc / (b - a + 1)
		h = sm
		for i: int in pins:
			h[i] = pins[i]
	for _pass in 4:
		for i in range(1, n):
			h[i] = clampf(h[i], h[i - 1] - max_grade * seg[i - 1], h[i - 1] + max_grade * seg[i - 1])
		for i in range(n - 2, -1, -1):
			h[i] = clampf(h[i], h[i + 1] - max_grade * seg[i], h[i + 1] + max_grade * seg[i])
		for i: int in pins:
			h[i] = pins[i]
	for i in n:
		out[i].y = h[i]
	return out


static func length_of(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in pts.size() - 1:
		total += Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
	return total


## Tightest curve radius (m) of a centre line, measured over chords of about `chord` m.
static func min_radius(pts: PackedVector3Array, chord := 12.0) -> float:
	var n := pts.size()
	if n < 3:
		return INF
	var step := maxi(1, int(chord / maxf(length_of(pts) / (n - 1), 0.1)))
	var best := INF
	for i in range(step, n - step):
		var a := Vector2(pts[i - step].x, pts[i - step].z)
		var b := Vector2(pts[i].x, pts[i].z)
		var c := Vector2(pts[i + step].x, pts[i + step].z)
		var cross := absf((b - a).cross(c - a))
		if cross < 1e-6:
			continue
		best = minf(best, a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * cross))
	return best

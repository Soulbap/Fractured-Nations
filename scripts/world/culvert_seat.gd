## WORLD-DETAIL-02: seats the culvert ends of the generated world (RoadStructures/Culvert_*, placed by ReferenceWorldBuilder on
## the terrain as it was before the settlement layer, the road shoulders and the relief changed it) at the foot of the road
## fill on the terrain soldiers now walk on: the pipe mouth at the toe of the embankment, facing away from the road, its invert a
## little below the ground. In memory at game start, after the terrain layers (like RoadShoulders: the generated scene and the
## manifest are untouched). The culvert mesh (tools/blender/env/make_culvert_v2.py) is a pipe with a mitred end lying in the
## fill slope and a stone apron; its buried length reaches back under the road, pitched down towards the road until the ground
## covers it. Ends without a fill to lie in (a road at grade) or at a junction are not shown. At a stream the mouth stays at
## the last dry point. `--legacy-culverts` keeps the old placement.
class_name CulvertSeat
extends RefCounted

## Search for the toe from the road mesh edge (RoadNetwork width / 2 + 2 m gutter) outward to this far (m).
const SEARCH_M := 14.0
const STEP_M := 0.5
## The toe: the ground falls less than this per step (the fill slope ends) - or the lowest point within SEARCH_M.
const FLAT_DROP := 0.06
## Pipe invert below the ground at the mouth (m).
const SINK := 0.08
## The pipe of make_culvert_v2.py: crown above the origin, buried length behind the mouth.
const CROWN := 0.81
const PIPE_M := 4.5
## Steepest pitch towards the road and the extra sinking allowed before an end is left out.
const MAX_PITCH := deg_to_rad(16.0)
const MAX_EXTRA_SINK := 0.35


static func enabled() -> bool:
	return not "--legacy-culverts" in OS.get_cmdline_user_args()


## Re-seats every culvert end under `root`; returns {seated, skipped}.
static func apply(root: Node, terrain: Terrain3D, roads: RoadNetwork, structures: StructureManager = null) -> Dictionary:
	var out := {"seated": 0, "skipped": 0}
	if root == null or terrain == null or not enabled():
		return out
	for n in root.get_children():
		var cv := n as Node3D
		if cv == null or not String(cv.name).begins_with("Culvert_"):
			continue
		var p := cv.global_position
		var near := roads.nearest(p, 25.0, 0, 0.0)
		if near.is_empty():
			cv.visible = false
			out.skipped += 1
			out["no_road"] = int(out.get("no_road", 0)) + 1
			continue
		var rd: RoadNetwork.Road = near.road
		var c: Vector3 = near.pos
		var d: Vector2 = near.dir
		var nrm := Vector2(-d.y, d.x)
		if nrm.dot(Vector2(p.x - c.x, p.z - c.z)) < 0.0:
			nrm = -nrm
		var start := rd.width * 0.5 + 2.5
		var best := Vector3.INF
		var prev := NAN
		var lowest := Vector3(0, INF, 0)
		var s := start
		while s <= start + SEARCH_M:
			var q := Vector2(c.x, c.z) + nrm * s
			# At a junction the walk can reach another road: stop before its edge.
			var other := roads.nearest(Vector3(q.x, 0, q.y), 20.0, rd.key, 0.0)
			if not other.is_empty() and float(other.dist) < (other.road as RoadNetwork.Road).width * 0.5 + 3.0:
				break
			var h: float = terrain.data.get_height(Vector3(q.x, 0, q.y))
			# A stream at the foot of the fill: the mouth stays on the bank.
			if not is_nan(h) and structures and structures._wet(q.x, q.y, h + 0.05):
				if is_nan(prev):
					break
				best = Vector3(q.x - nrm.x * STEP_M, prev, q.y - nrm.y * STEP_M)
				break
			if not is_nan(h):
				if h < lowest.y:
					lowest = Vector3(q.x, h, q.y)
				if not is_nan(prev) and prev - h < FLAT_DROP and s > start + 1.0:
					best = Vector3(q.x, h, q.y)
					break
				prev = h
			s += STEP_M
		if not best.is_finite():
			best = lowest
		var clash := roads.nearest(best if best.is_finite() else p, 20.0, 0, 0.0)
		if not best.is_finite() or best.y == INF or (not clash.is_empty() and clash.road != rd
				and float(clash.dist) < (clash.road as RoadNetwork.Road).width * 0.5 + 2.5):
			# No clean place (a junction): the end is not shown rather than standing on a road.
			cv.visible = false
			out.skipped += 1
			out["no_place"] = int(out.get("no_place", 0)) + 1
			continue
		# Mouth faces away from the road (the mesh's +Z); the buried pipe dips towards the road until the ground covers its crown.
		var out_dir := Vector3(nrm.x, 0.0, nrm.y)
		var fit := _fit(best, out_dir, best.y - SINK, terrain, roads)
		if not fit.is_finite():
			# No fill to lie in (the road at grade, a shallow bank): a culvert end there makes no sense - not shown.
			cv.visible = false
			out.skipped += 1
			out["no_fill"] = int(out.get("no_fill", 0)) + 1
			continue
		var to_road := -out_dir * cos(fit.x) + Vector3.DOWN * sin(fit.x)
		cv.global_transform = Transform3D(Basis.looking_at(to_road, Vector3.UP), Vector3(best.x, fit.y, best.z))
		out.seated += 1
	return out


## Pitch (towards the road) and base height that keep the pipe covered, or Vector2.INF. Under the road (its mesh with the
## gutter) the crown lies 0.1 m under the ground; in the fill the pipe may show a little as it enters the slope (0.45 m of the
## crown within 2 m of the mouth, 0.15 m beyond).
static func _fit(best: Vector3, out_dir: Vector3, base: float, terrain: Terrain3D, roads: RoadNetwork) -> Vector2:
	var need := 0.0
	for k in range(1, 10):
		var y := PIPE_M * k / 9.0
		var q := best - out_dir * y
		var g: float = terrain.data.get_height(q)
		if is_nan(g):
			continue
		var nq := roads.nearest(q, 15.0, 0, 0.0)
		var under_road := not nq.is_empty() and float(nq.dist) < (nq.road as RoadNetwork.Road).width * 0.5 + 2.0
		var allow := -0.1 if under_road else (0.45 if y < 2.0 else 0.15)
		need = maxf(need, (base + CROWN - allow - g) / y)
	var pitch := atan(maxf(need, 0.0))
	if pitch > MAX_PITCH:
		# Steeper than the pipe may lie: sink the whole end a little more; past that, it does not fit.
		var extra := (tan(pitch) - tan(MAX_PITCH)) * PIPE_M
		if extra > MAX_EXTRA_SINK:
			return Vector2.INF
		return Vector2(MAX_PITCH, base - extra)
	return Vector2(pitch, base)

## A coarse picture of where each faction believes the enemy is, and how exposed its own ground is
## (AI-COMBAT-STRAT-01).
##
## Not a simulation: a sparse grid of 250 m cells rebuilt from the faction's contacts (IntelSim - what it has
## been told, never the world) and its objectives every few seconds. Per faction:
##   threat[cell]   the strength x confidence of the believed enemy, each contact spread over the cells its
##                  uncertainty circle reaches (so an old report is a faint wide smudge, a fresh one a spike);
## and the objectives' own pull is read directly from the objective records.
## Uses: the believed threat on and around an objective (how pressed is it), the risk of a route (an attack
## is not sent through a known enemy concentration), and a ranking of the faction's exposed objectives.
## Cost: contacts per faction <= 40, a handful of cells each, once per refresh_s.
class_name StrategicInfluence
extends RefCounted

const CELL := 250.0

var ws: WarSim
var refresh_s := 6.0
## faction -> {Vector2i cell: believed enemy strength (confidence-weighted)}.
var threat := {}
var _t := -100.0
var usec := 0
var usec_max := 0
var refreshes := 0


func _init(p_ws: WarSim) -> void:
	ws = p_ws


func update() -> void:
	var now := ws.sim.state.time
	if now - _t < refresh_s:
		return
	_t = now
	var t0 := Time.get_ticks_usec()
	refreshes += 1
	threat.clear()
	for f in ws.war.contacts:
		var grid := {}
		for c: ContactState in ws.war.contacts[f].values():
			if c.status == ContactState.Status.LOST:
				continue
			var value := float(c.strength) * c.conf
			var r := clampf(c.unc, 20.0, 600.0)
			var c0 := _cell(c.pos - Vector3(r, 0, r))
			var c1 := _cell(c.pos + Vector3(r, 0, r))
			var cells := (c1.x - c0.x + 1) * (c1.y - c0.y + 1)
			var share := value / float(maxi(cells, 1))
			for x in range(c0.x, c1.x + 1):
				for z in range(c0.y, c1.y + 1):
					grid[Vector2i(x, z)] = float(grid.get(Vector2i(x, z), 0.0)) + share
		threat[f] = grid
	var dt := Time.get_ticks_usec() - t0
	usec += dt
	usec_max = maxi(usec_max, dt)


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


## Believed enemy strength around p within r (m), from the faction's own picture.
func threat_at(f: int, p: Vector3, r: float) -> float:
	var grid: Dictionary = threat.get(f, {})
	if grid.is_empty():
		return 0.0
	var c0 := _cell(p - Vector3(r, 0, r))
	var c1 := _cell(p + Vector3(r, 0, r))
	var sum := 0.0
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			sum += float(grid.get(Vector2i(x, z), 0.0))
	return sum


## Believed enemy strength along a route (polyline), sampled every 150 m within `lateral` m of the line:
## the most threatened cell on the way counts, not the average (one strong group is a wall).
func route_risk(f: int, pts: Array, lateral := 200.0) -> float:
	var worst := 0.0
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var n := maxi(1, ceili(WarSim._flat(a, b) / 150.0))
		for k in range(0, n + 1):
			worst = maxf(worst, threat_at(f, a.lerp(b, float(k) / n), lateral))
	return worst


## The faction's objectives ranked by the believed enemy strength within `radius` of them: its exposed front.
func exposed(f: int, radius := 600.0) -> Array:
	var out := []
	for o: ObjectiveState in ws.war.owned_by(f):
		var t := threat_at(f, o.position, radius)
		if t > 0.05:
			out.append({"objective": o, "threat": t})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.threat * a.objective.value > b.threat * b.objective.value)
	return out


## Cells above `min_value` for the overlay and the inspector: [{cell centre, value}], strongest first.
func hot_cells(f: int, min_value := 0.3, limit := 12) -> Array:
	var out := []
	for cell: Vector2i in threat.get(f, {}):
		var v: float = threat[f][cell]
		if v >= min_value:
			out.append({"pos": Vector3((cell.x + 0.5) * CELL, 0.0, (cell.y + 0.5) * CELL), "value": v})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.value > b.value)
	return out.slice(0, limit)

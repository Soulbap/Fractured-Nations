## Creates the starting situation of the persistent war (WORLD-SANDBOX-01) on ref_20km:
## three factions, twelve strategic objectives at real places, the starting squads and
## each HQ's HESCO perimeter (built with the construction system, so it is real cover,
## navigation obstacle and line-of-sight blocker).
##
## The map is split by the river Hovedelva (north-south, four road bridges). North (the
## player) and South share the west bank; East holds the east bank. The HQs are the
## world's three base sites; the other objectives are the two towns, three bridges,
## the industrial site and villages / junctions between them.
class_name SandboxSetup
extends RefCounted

## [name, kind, source, value, radius, owner]; source: "site:<i>" (base site), a
## settlement name from sites.json, or "bridge:<i>" (bridges from north to south).
const OBJECTIVES := [
	["North HQ", "hq", "site:0", 3, 200.0, 0],
	["South HQ", "hq", "site:1", 3, 200.0, 1],
	["East HQ", "hq", "site:2", 3, 200.0, 2],
	["Sentrum", "town", "Sentrum", 3, 250.0, -1],
	["Østby", "town", "Østby", 2, 220.0, 2],
	["North Bridge", "bridge", "bridge:0", 2, 140.0, 0],
	["Centre Bridge", "bridge", "bridge:1", 2, 140.0, -1],
	["South Bridge", "bridge", "bridge:2", 2, 140.0, -1],
	["Verket", "town", "Verket", 2, 200.0, 1],
	["Elvetun", "village", "Elvetun", 1, 160.0, 0],
	["Haugen", "village", "Haugen", 1, 160.0, -1],
	["Ødegård", "village", "Ødegård", 1, 160.0, 2],
]
## [faction name, player, profile, reserves, starting squads per objective name]
const FACTIONS := [
	["North", true, &"", 32, {"North HQ": 3, "Elvetun": 1, "North Bridge": 1}],
	["South", false, &"aggressive", 40, {"South HQ": 4, "Verket": 1}],
	["East", false, &"defensive", 40, {"East HQ": 3, "Østby": 1, "Ødegård": 1}],
]
const SQUAD_SIZE := 8


static func create(demo: CoreDemo, routes: StrategicRoutes) -> Dictionary:
	var sim := demo.sim
	var war := sim.state.war
	war.active = true
	war.player_faction = 0
	var settlements := {}
	var src := "res://worlds/%s/source/" % demo.config.world_name
	var sites: Variant = JSON.parse_string(FileAccess.get_file_as_string(src + "sites.json"))
	if sites is Dictionary:
		for s: Dictionary in sites.settlements:
			settlements[String(s.name)] = Vector3(s.pos[0], s.pos[1], s.pos[2])
	var bridges := routes.bridges.duplicate()
	bridges.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	var by_name := {}
	var id := 1
	for d: Array in OBJECTIVES:
		var src_key: String = d[2]
		var p := Vector3.INF
		if src_key.begins_with("site:"):
			p = demo.sites[int(src_key.substr(5))].position
		elif src_key.begins_with("bridge:"):
			var i := int(src_key.substr(7))
			if i < bridges.size():
				p = bridges[i]
		elif settlements.has(src_key):
			p = settlements[src_key]
		if not p.is_finite():
			push_warning("SandboxSetup: no place for %s" % d[0])
			continue
		var o := ObjectiveState.new()
		o.id = id
		id += 1
		o.obj_name = d[0]
		o.kind = StringName(d[1])
		o.position = demo.on_ground(p.x, p.z, 0.0)
		o.value = d[3]
		o.radius = d[4]
		o.owner = d[5]
		if o.owner >= 0:
			o.history.append([0.0, o.owner])
		war.objectives[o.id] = o
		by_name[o.obj_name] = o
	var squads := 0
	for i in FACTIONS.size():
		var d: Array = FACTIONS[i]
		var f := FactionState.new()
		f.id = i
		f.faction_name = d[0]
		f.player = d[1]
		f.profile_id = d[2]
		f.reserves = d[3]
		f.reserves_start = d[3]
		f.next_reinforcement_at = sim.war.reinforce_interval_s
		f.next_decision_at = 20.0 + i * 7.0
		# AI-WAR-LOGISTICS-01: the economy starts after the first strategic decision, with its own stagger.
		f.econ_next_at = 30.0 + i * 5.0
		war.factions[f.id] = f
		var hq: ObjectiveState = by_name.get("%s HQ" % f.faction_name)
		f.hq_objective = hq.id if hq else -1
	for i in FACTIONS.size():
		var f := war.faction(i)
		var placement: Dictionary = FACTIONS[i][4]
		for oname: String in placement:
			var o: ObjectiveState = by_name.get(oname)
			if o == null:
				continue
			for k in placement[oname]:
				var a: float = k * 2.1 + i
				var spot := o.position + Vector3(cos(a), 0, sin(a)) * minf(o.radius * 0.35, 14.0 + k * 6.0)
				var sq := sim.war.spawn_squad(f, spot, SQUAD_SIZE)
				sq.station_objective = o.id
				squads += 1
	var base_info := {}
	var centre: ObjectiveState = by_name.get("Sentrum")
	for f: FactionState in war.factions.values():
		var hq := war.objective(f.hq_objective)
		if hq and demo.structures:
			_fortify(demo, hq)
			# AI-WAR-LOGISTICS-01: the AI factions start with a real main base (the player builds his own).
			if not f.player and not sim.war.bases.is_disabled():
				base_info[f.faction_name] = sim.war.bases.create_start_base(f, hq.position, centre.position if centre else Vector3.ZERO)
	sim.war.log_event(-1, "info", "The war begins: North (you), South (aggressive), East (defensive)")
	return {"objectives": war.objectives.size(), "factions": war.factions.size(), "squads": squads, "bases": base_info,
		"soldiers": sim.state.count_of(UnitState.Kind.SOLDIER)}


## A 56 x 56 m HESCO perimeter with an 8 m entrance on each side, round the HQ centre.
static func _fortify(demo: CoreDemo, hq: ObjectiveState) -> void:
	var cs := demo.sim.state.construction
	var c := hq.position
	var h := 28.0
	var gap := 4.0
	var sides := [
		[Vector2(-h, -h), Vector2(h, -h)], [Vector2(h, -h), Vector2(h, h)],
		[Vector2(h, h), Vector2(-h, h)], [Vector2(-h, h), Vector2(-h, -h)],
	]
	for s: Array in sides:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		for seg: Array in [[a, mid - dir * gap], [mid + dir * gap, b]]:
			var p0: Vector2 = seg[0]
			var p1: Vector2 = seg[1]
			# A road that crosses the perimeter keeps its way through: the wall is left open there (a gate), else no vehicle
			# could drive in or out of the HQ (found by the AI-WAR-LOGISTICS-01 exit test).
			var length := p0.distance_to(p1)
			var run_start := -1.0
			var t := 0.0
			while t <= length + 0.01:
				var q := p0.lerp(p1, t / maxf(length, 0.01))
				var open := demo.sim.state.roads.on_road(Vector3(c.x + q.x, 0.0, c.z + q.y), 6.0)
				if not open and run_start < 0.0:
					run_start = t
				if (open or t >= length) and run_start >= 0.0:
					var run_end := t if open else length
					if run_end - run_start >= 3.0:
						var r0 := p0.lerp(p1, run_start / maxf(length, 0.01))
						var r1 := p0.lerp(p1, run_end / maxf(length, 0.01))
						cs.add_line(&"hesco", PackedVector3Array([demo.on_ground(c.x + r0.x, c.z + r0.y, 0.0), demo.on_ground(c.x + r1.x, c.z + r1.y, 0.0)]))
					run_start = -1.0
				t += 1.0

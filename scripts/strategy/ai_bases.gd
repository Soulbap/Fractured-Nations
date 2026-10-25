## AI faction bases (AI-WAR-LOGISTICS-01): the starting compound and limited later construction, through the
## same construction system the player uses (StructureManager.check_building for placement and groundwork,
## ConstructionState.add_building for the record, `clearings_for` for the cleared trees), so an AI building is a
## real, persistent, attackable structure that BaseSim picks up as a facility (inventory, queues, base group).
##
## * `create_start_base` builds the faction's main base beside its headquarters when the sandbox is created
##   (HQ, barracks, supply depot, vehicle depot, ammunition magazine, fuel point) and places the starting stockpile
##   and starting trucks (FactionProfile) - the scenario's initial situation, like the starting squads.
## * Later construction (forward depot, second barracks, field defences) is *paid* from the main base's supplies
##   (BUILD_COST, a data table; the player's construction is free in the sandbox, the table is shared so it can be
##   switched on for him), takes BUILD_TIME_S, is placed on ground check_building accepts, never within
##   MIN_GAP_M of another structure, and is a construction site (StructureState.site, GAMEPLAY-01B: the same record the
##   player's construction uses) until finished, so the same building is not ordered twice and a save in the middle of
##   construction restores it.
class_name AiBases
extends RefCounted

## Supplies (kg) a building costs the AI faction, paid from its base stores when the order is given. GAMEPLAY-01B: the one
## cost table of player and AI construction (BuildCosts).
const BUILD_COST := BuildCosts.COST
const BUILD_TIME_S := {
	&"supply_depot": 150.0, &"supply_storage": 90.0, &"barracks_block": 180.0, &"vehicle_depot": 210.0, &"ammo_magazine": 120.0,
	&"fuel_point": 70.0, &"repair_bay": 100.0, &"sandbag_fighting_position": 30.0,
	&"command_post": 150.0, &"fighting_position": 45.0, &"mg_emplacement": 60.0, &"guard_tower_steel": 90.0,
}
## GAMEPLAY-01E: the three base templates an AI faction may build (existing buildings only, built one after the other
## through request(): the same paid sites as every AI order). `reserve`: supplies the faction keeps beyond the template.
const TEMPLATES := {
	"outpost": {"name": "Forward Outpost", "items": [&"command_post", &"fighting_position", &"guard_tower_steel", &"fighting_position"], "reserve": 1200.0},
	"defensive": {"name": "Defensive Base", "items": [&"command_post", &"supply_storage", &"fighting_position", &"mg_emplacement", &"guard_tower_steel", &"fighting_position"], "reserve": 1800.0},
	"main": {"name": "Main Base", "items": [&"command_post", &"barracks_block", &"supply_depot", &"fighting_position", &"guard_tower_steel"], "reserve": 1500.0},
}
## Expansion limits: at most `ai_base_limit` bases beyond the first (scenario rule, default 2), one expansion at a time per
## faction, EXPAND_COOLDOWN_S between starts, none before EXPAND_FIRST_S, never closer than EXPAND_GAP_M to an own base.
const EXPAND_COOLDOWN_S := 900.0
const EXPAND_FIRST_S := 300.0
const EXPAND_GAP_M := 1500.0
## Free ground kept between a new building's centre and any other structure's footprint edge (m).
const MIN_GAP_M := 7.0
## The starting compound: [type, local x, local z] in a frame whose -Z is the front of the buildings.
const START_LAYOUT := [
	[&"vehicle_depot", -50.0, -30.0], [&"supply_depot", 6.0, -30.0], [&"fuel_point", 52.0, -28.0],
	[&"hq_building", 0.0, 32.0], [&"barracks_block", -48.0, 32.0], [&"ammo_magazine", 52.0, 30.0],
]

var ws: WarSim
var sim: WorldSim
var stats := {"started": 0, "finished": 0, "refused": 0, "refunded": 0}
## `--no-ai-bases` starts the sandbox without AI bases (the old layout, for comparison tests only).
static var disabled := false


func _init(p_ws: WarSim) -> void:
	ws = p_ws
	sim = p_ws.sim


func is_disabled() -> bool:
	return disabled or "--no-ai-bases" in OS.get_cmdline_user_args()


func _sm() -> StructureManager:
	return sim.structures


# --- Starting base ----------------------------------------------------------------------------------------------------

## Builds faction f's main base round `anchor` (the HQ objective position): tries 16 directions and four
## orientations from 70 m outwards until the whole compound fits, else the largest part that does. The stockpile
## goes into the first supply depot (LogisticsSim's starter rule) and `start_trucks` trucks stand at the vehicle
## depot. Returns {ok, placed, missing, center}.
func create_start_base(f: FactionState, anchor: Vector3, toward: Vector3) -> Dictionary:
	if _sm() == null:
		return {"ok": false, "reason": "no construction system", "placed": 0}
	var best_plan: Array = []
	var best_center := Vector3.INF
	var best_yaw := 0.0
	var p := ws.profile(f)
	var base_dir := atan2(toward.z - anchor.z, toward.x - anchor.x)
	# Two passes: the compound must stand within 120 m of a road (the vehicles live on roads); only when no such place
	# holds the whole compound is any buildable place accepted.
	for need_road in [true, false]:
		for dist: float in [75.0, 100.0, 130.0, 160.0, 200.0]:
			for k in 24:
				var a := base_dir + (k / 2 + 1) * (TAU / 24.0) * (1.0 if k % 2 == 0 else -1.0) if k > 0 else base_dir
				var c := Vector3(anchor.x + cos(a) * dist, 0.0, anchor.z + sin(a) * dist)
				c.y = ws._ground(c).y
				for yaw: float in [0.0, PI * 0.5, PI, -PI * 0.5]:
					# The yard lies in front of the buildings (local -Z): a road must pass within 90 m of its middle.
					if need_road and sim.state.roads.nearest(c + Basis(Vector3.UP, yaw) * Vector3(-15.0, 0.0, -58.0), 90.0, 0, 0.0).is_empty():
						continue
					var plan := _plan_layout(c, yaw)
					if plan.size() > best_plan.size():
						best_plan = plan
						best_center = c
						best_yaw = yaw
					if plan.size() == START_LAYOUT.size():
						break
				if best_plan.size() == START_LAYOUT.size():
					break
			if best_plan.size() == START_LAYOUT.size():
				break
		if best_plan.size() == START_LAYOUT.size():
			break
	if best_plan.is_empty():
		return {"ok": false, "reason": "no buildable ground near the headquarters", "placed": 0}
	var cs := sim.state.construction
	_clear_yard(best_center, best_yaw)
	var placed := 0
	var vdepot: StructureState = null
	for e: Dictionary in best_plan:
		var s := cs.add_building(e.type, e.pos, e.yaw, f.id)
		cs.add_clearings(_sm().clearings_for(s, true))
		placed += 1
		if e.type == &"vehicle_depot":
			vdepot = s
	# Stock: the shared starting stockpile into the first supply depot (placed by LogisticsSim's rule when a
	# store is added; AI factions are not the player's faction, so it is given here, once).
	var lg := sim.state.logistics
	if not lg.starter_given.get(f.id, false):
		var depot := sim.logistics.nearest_store(best_center, f.id, &"", &"supply")
		if depot:
			lg.starter_given[f.id] = true
			for item in FacilityDefs.START_STOCK:
				depot.inventory.add(item, FacilityDefs.START_STOCK[item] * p.start_stock_mult)
			sim.logistics._event(f.id, "%s: the starting stockpile arrives" % sim.logistics.store_name(depot))
	# The starting trucks.
	var trucks := 0
	if vdepot:
		for i in p.start_trucks:
			if sim.logistics.bases._finish_vehicle(vdepot, VehicleDefs.TRUCK):
				trucks += 1
				sim.logistics.bases.stats.vehicles_acquired -= 1
				f.ledger.vehicles_bought = int(f.ledger.vehicles_bought) - 1
	return {"ok": true, "placed": placed, "missing": START_LAYOUT.size() - placed, "center": best_center, "yaw": best_yaw, "trucks": trucks}


## Trees are cleared on the yard in front of the compound and along a lane from it to the nearest road point, so the
## vehicles (whose cross-country planner knows no trees) reach the road: records like the construction clearings
## ({c: [x, z], yaw, h: [half x, half z]}), applied by the vegetation streamer.
func _clear_yard(center: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var yard := center + basis * Vector3(-15.0, 0.0, -58.0)
	var list: Array = [{"c": [yard.x, yard.z], "yaw": -yaw, "h": [42.0, 28.0], "trees": true}]
	var road := sim.state.roads.nearest(yard, 100.0, 0, 0.0)
	if not road.is_empty():
		var rp: Vector3 = road.pos
		var d := Vector2(rp.x - yard.x, rp.z - yard.z)
		if d.length() > 20.0:
			var mid := Vector2(yard.x, yard.z) + d * 0.5
			list.append({"c": [mid.x, mid.y], "yaw": atan2(d.y, d.x), "h": [d.length() * 0.5 + 6.0, 8.0], "trees": true})
	sim.state.construction.add_clearings(list)


## The buildings of START_LAYOUT that check_building accepts at `center` with `yaw` (all of them or fewer);
## each entry {type, pos, yaw}. Nothing is built.
func _plan_layout(center: Vector3, yaw: float) -> Array:
	var out: Array = []
	var basis := Basis(Vector3.UP, yaw)
	for e: Array in START_LAYOUT:
		var def := StructureCatalog.get_def(e[0])
		if def == null:
			continue
		var pos: Vector3 = center + basis * Vector3(e[1], 0.0, e[2])
		pos.y = ws._ground(pos).y
		var chk := _sm().check_building(def, pos, yaw, -1, true)
		if not chk.ok:
			continue
		out.append({"type": e[0], "pos": chk.xform.origin, "yaw": yaw})
	# A wall (the HQ's HESCO perimeter) must not cross the compound, its yard or the lane out: the vehicles could not leave
	# (found with the exit test: trucks stopped at a wall that cut the yard).
	if out.size() == START_LAYOUT.size() and _walled(center, basis):
		return []
	return out


## True when a structure stands on the compound's footprint including the yard in front of it (sampled on a 6 m grid).
func _walled(center: Vector3, basis: Basis) -> bool:
	var x := -78.0
	while x <= 78.0:
		var z := -82.0
		while z <= 52.0:
			var q: Vector3 = center + basis * Vector3(x, 0.0, z)
			if _sm().blocks_point(Vector2(q.x, q.z), 2.5):
				return true
			z += 6.0
		x += 6.0
	return false


# --- Later construction ------------------------------------------------------------------------------------------------

## Orders a building for faction f near `near`: finds a site (ring search 25-140 m, never within MIN_GAP_M of
## another structure or a pending order), pays BUILD_COST from the faction's bases (nearest store with the
## supplies first) and queues it. Returns {ok, reason, pos}.
func request(f: FactionState, type_id: StringName, near: Vector3, why: String, need_road := false, face := Vector3.ZERO) -> Dictionary:
	if _sm() == null:
		return {"ok": false, "reason": "no construction system"}
	var def := StructureCatalog.get_def(type_id)
	if def == null or not BUILD_COST.has(type_id):
		return {"ok": false, "reason": "unknown building"}
	# GAMEPLAY-04B: the AI builds only what its faction has developed (the player's rule).
	var lock := ws.dev.structure_lock(f.id, type_id)
	if lock != "":
		stats.refused += 1
		return {"ok": false, "reason": lock}
	var bs := sim.logistics.bases
	var bid := _payer_base(f, near, BUILD_COST[type_id])
	if bid < 0:
		stats.refused += 1
		return {"ok": false, "reason": "not enough supplies (%d kg needed)" % roundi(BUILD_COST[type_id])}
	var site := find_site(def, near, 25.0, 140.0, need_road, face)
	if not site.ok:
		stats.refused += 1
		return {"ok": false, "reason": "no buildable site near (%.0f, %.0f): %s" % [near.x, near.z, site.reason]}
	if not bs.pay(bid, {&"supplies": BUILD_COST[type_id]}):
		return {"ok": false, "reason": "payment failed"}
	# GAMEPLAY-01B: the order is a construction site like the player's (the same record, footprint and look); the AI's
	# builders are an abstract crew that finishes it in BUILD_TIME_S (update()).
	var need := BuildCosts.work_of(def)
	var s := sim.state.construction.add_site(type_id, site.pos, site.yaw, f.id, need, {"bases": {bid: {"supplies": BUILD_COST[type_id]}}},
		need / float(BUILD_TIME_S.get(type_id, 120.0)))
	sim.state.construction.add_clearings(_sm().clearings_for(s, true))
	s.site["why"] = why
	stats.started += 1
	ws.log_event(f.id, "build", "%s ordered near (%.0f, %.0f): %s" % [FacilityDefs.display_name(type_id) if FacilityDefs.has(type_id) else String(type_id), site.pos.x, site.pos.z, why], site.pos)
	return {"ok": true, "reason": "", "pos": site.pos}


## GAMEPLAY-01F: an AI faction repairs a damaged structure of its own: paid from its bases (the repair cost), worked by an
## abstract crew that takes REPAIR_TIME_S like its construction. {ok, reason}.
const REPAIR_TIME_S := 90.0


func request_repair(f: FactionState, s: StructureState, why: String) -> Dictionary:
	if s == null or s.faction != f.id or s.is_site() or not s.repair.is_empty():
		return {"ok": false, "reason": "nothing to repair"}
	var cost := StructureHealth.repair_cost(s)
	var need := StructureHealth.repair_work(s)
	if need <= 0.0:
		return {"ok": false, "reason": "undamaged"}
	var bid := _payer_base(f, s.position, cost)
	if bid < 0 or not sim.logistics.bases.pay(bid, {&"supplies": cost}):
		return {"ok": false, "reason": "not enough supplies (%d kg)" % roundi(cost)}
	sim.state.construction.start_repair(s, need, {"bases": {bid: {"supplies": cost}}}, need / REPAIR_TIME_S)
	s.repair["why"] = why
	stats["repairs"] = int(stats.get("repairs", 0)) + 1
	var what := FacilityDefs.display_name(s.type_id) if FacilityDefs.has(s.type_id) else String(s.type_id)
	ws.log_event(f.id, "build", "Repair of %s ordered (%d kg): %s" % [what, roundi(cost), why], s.position)
	return {"ok": true, "reason": ""}


## A base of f that can pay `supplies` (the one nearest `near`); -1 when none can.
func _payer_base(f: FactionState, near: Vector3, supplies: float) -> int:
	var best := -1
	var best_d := INF
	for b: Dictionary in sim.logistics.bases.bases_of(f.id):
		if sim.logistics.bases.base_stock(b.id).supplies < supplies:
			continue
		var d := Vector2(near.x - b.anchor.x, near.z - b.anchor.z).length()
		if d < best_d:
			best_d = d
			best = b.id
	return best


## A site for `def` on a ring search round `near` (5 rings, 10 directions, turned a little every call). The cheap filters (passable, not
## crowded, a road within 70 m when need_road: stores that trucks must reach) run first; at most MAX_CHECKS full placement checks
## (check_building, about a millisecond each) are made per call, so a search never costs a visible frame - a failed search is tried
## again, from other directions, at the next economic decision.
const MAX_CHECKS := 10
var _phase := 0.0


func find_site(def: StructureDef, near: Vector3, min_r: float, max_r: float, need_road := false, face := Vector3.ZERO) -> Dictionary:
	var reason := "ground"
	var checks := 0
	_phase += 0.61
	for r: float in [min_r, min_r + 20.0, min_r + 45.0, min_r + 75.0, max_r]:
		for k in 10:
			var a := TAU * k / 10.0 + r * 0.013 + _phase
			var c := Vector3(near.x + cos(a) * r, 0.0, near.z + sin(a) * r)
			c.y = ws._ground(c).y
			if not ws.routes.passable(c):
				reason = "impassable"
				continue
			if need_road and sim.state.roads.nearest(c, 70.0, 0, 0.0).is_empty():
				reason = "no road within 70 m"
				continue
			if _crowded(c, def):
				reason = "too close to other structures"
				continue
			if checks >= MAX_CHECKS:
				return {"ok": false, "reason": "no site found in %d placement checks (%s)" % [MAX_CHECKS, reason]}
			checks += 1
			var yaw := fposmod(a + PI * 0.5, TAU) - PI
			if face != Vector3.ZERO:
				yaw = atan2(-face.x, -face.z)  # GAMEPLAY-01E: a fortification faces the threat
			if need_road:
				# The front of the building (its dock) faces the nearest road point, so trucks drive straight in.
				var rd := sim.state.roads.nearest(c, 70.0, 0, 0.0)
				if not rd.is_empty():
					var to_road: Vector3 = rd.pos - c
					yaw = atan2(-to_road.x, -to_road.z)
			var chk := _sm().check_building(def, c, yaw, -1, true)
			if chk.ok:
				return {"ok": true, "pos": chk.xform.origin, "yaw": yaw}
			reason = chk.reason
	return {"ok": false, "reason": reason}


## Another structure (built or pending) closer than the footprints plus MIN_GAP_M.
func _crowded(c: Vector3, def: StructureDef) -> bool:
	var half := def.size.length() * 0.35
	for s: StructureState in sim.state.construction.all():
		var sd := StructureCatalog.get_def(s.type_id)
		if sd == null or s.is_line():
			continue
		var d := Vector2(s.position.x - c.x, s.position.z - c.z).length()
		if d < half + sd.size.length() * 0.35 + MIN_GAP_M:
			return true
	for b: Dictionary in ws.war.builds:
		if Vector2(b.pos.x - c.x, b.pos.z - c.z).length() < half + 25.0:
			return true
	return false


# --- Expansion (GAMEPLAY-01E) ----------------------------------------------------------------------------------------------
# A limited, conservative extension of the construction above: a faction that can afford it, has squads to spare and is not
# at its base limit chooses one held objective far from its bases and not under threat, and builds a template there one
# paid site after the other; when the command post stands, the base exists (BaseSim) and becomes a target (WarSim.sync_bases);
# when the template is complete one squad garrisons it. Every step is a record in WarState.expansions (saved).

func template_cost(t: String) -> float:
	var c := 0.0
	for it: StringName in TEMPLATES[t].items:
		c += BuildCosts.cost_of(StructureCatalog.get_def(it))
	return c


func active_expansion(f: int) -> Dictionary:
	for e: Dictionary in ws.war.expansions:
		if int(e.faction) == f and (e.state == "building" or e.state == "garrison"):
			return e
	return {}


## Whether faction f should expand now and where: {ok, why, template, objective, pos, cost}. Reads its own stock, squads and
## the threat it believes (IntelSim / threatened objectives), never the enemy's real positions.
func plan_expansion(f: FactionState, supplies: float, squads: int) -> Dictionary:
	var now := sim.state.time
	if not bool(ws.war.rule("ai_expansion", false)):
		return {"ok": false, "why": "expansion off in this scenario"}
	if not active_expansion(f.id).is_empty():
		return {"ok": false, "why": "an expansion is under way"}
	if now < maxf(f.expand_next_at, EXPAND_FIRST_S):
		return {"ok": false, "why": "cooldown (%d s)" % roundi(maxf(f.expand_next_at, EXPAND_FIRST_S) - now)}
	var bs := sim.logistics.bases
	# Established bases (founded by a command post, with an area) count; a forward supply store is no base of this kind.
	var nbases := 0
	for b: Dictionary in bs.bases_of(f.id):
		if float(b.get("radius", 0.0)) > 0.0 or bs.base_kind(int(b.id)) == "Main base":
			nbases += 1
	var limit := int(ws.war.rule("ai_base_limit", 2))
	if nbases >= 1 + limit:
		return {"ok": false, "why": "base limit (%d bases)" % nbases}
	if squads < 3:
		return {"ok": false, "why": "too few squads to hold another base (%d)" % squads}
	var barracks := bs.facility_of_kind(f.id, &"barracks")
	var t := "outpost"
	if barracks == null or not barracks.is_operational():
		t = "main"  # the faction lost its barracks: rebuild where it can recruit again
	elif supplies >= template_cost("defensive") + float(TEMPLATES.defensive.reserve) + 1500.0:
		t = "defensive"
	var cost := template_cost(t)
	if supplies < cost + float(TEMPLATES[t].reserve):
		return {"ok": false, "why": "%s needs %d kg + a reserve of %d (have %d)" % [TEMPLATES[t].name, roundi(cost), roundi(TEMPLATES[t].reserve), roundi(supplies)]}
	var best: ObjectiveState = null
	var best_sc := -INF
	var main_bid := bs.main_base(f.id)
	var main_at: Vector3 = sim.state.construction.bases[main_bid].anchor if main_bid >= 0 else Vector3.INF
	for o: ObjectiveState in ws.war.owned_by(f.id):
		if o.is_base() or o.is_hq() or ws.threatened.get(o.id, false):
			continue
		# GAMEPLAY-04G: a scenario outpost (a checkpoint, a roadblock) is a post, not a base site - New Game's posts next to
		# the player's start were turned into fortified bases within half an hour.
		if o.kind == &"outpost":
			continue
		if ws.intel.threat_near(f.id, o.position, o.radius + 600.0) > 0:
			continue
		var gap := INF
		for b: Dictionary in bs.bases_of(f.id):
			if float(b.get("radius", 0.0)) > 0.0 or bs.base_kind(int(b.id)) == "Main base":
				gap = minf(gap, WarSim._flat(b.anchor, o.position))
		for e: Dictionary in ws.war.expansions:
			if int(e.faction) == f.id and e.state != "failed":
				gap = minf(gap, WarSim._flat(e.pos, o.position))
		if gap < EXPAND_GAP_M:
			continue
		var front := INF
		for x: ObjectiveState in ws.war.all_objectives():
			if x.owner != f.id and not x.is_base():
				front = minf(front, WarSim._flat(x.position, o.position))
		var sc := 2.0 * o.value + clampf(3000.0 / maxf(front, 500.0), 0.0, 3.0) - (WarSim._flat(main_at, o.position) / 6000.0 if main_at.is_finite() else 0.0)
		if sc > best_sc:
			best_sc = sc
			best = o
	if best == null:
		return {"ok": false, "why": "no held objective far enough from the bases and free of reported enemy"}
	# The base stands at the edge of the objective, on the side of the faction's main base.
	var dir := (main_at - best.position) if main_at.is_finite() else Vector3(1, 0, 0)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 1.0 else Vector3(1, 0, 0)
	var pos := ws._ground(best.position + dir * (best.radius * 0.6 + 40.0))
	return {"ok": true, "why": "%s near %s (value %d, score %.1f)" % [TEMPLATES[t].name, best.obj_name, best.value, best_sc], "template": t,
		"objective": best.id, "pos": pos, "cost": cost}


## Starts a planned expansion: the command post site first (paid, crewed like every AI order). {ok, reason}.
func start_expansion(f: FactionState, plan: Dictionary) -> Dictionary:
	var o := ws.war.objective(int(plan.objective))
	var why := "%s at %s" % [TEMPLATES[plan.template].name, o.obj_name if o else "?"]
	var res := request(f, &"command_post", plan.pos, why, true)
	if not res.ok:
		res = request(f, &"command_post", plan.pos, why, false)
	f.expand_next_at = sim.state.time + (EXPAND_COOLDOWN_S if res.ok else 240.0)
	if not res.ok:
		return res
	var site := -1
	for s: StructureState in sim.state.construction.all():
		if s.is_site() and s.faction == f.id and s.type_id == &"command_post" and WarSim._flat(s.position, res.pos) < 1.0:
			site = s.id
	var e := {"id": ws.war.next_expansion_id, "faction": f.id, "template": plan.template, "objective": int(plan.objective), "pos": res.pos, "site": site,
		"base": -1, "next": 1, "state": "building", "why": why, "started": snappedf(sim.state.time, 0.1), "ended": -1.0, "retry": 0.0}
	ws.war.next_expansion_id += 1
	ws.war.expansions.append(e)
	ws.log_event(f.id, "build", "Expansion: %s begins (%d kg)" % [why, roundi(float(plan.cost))], res.pos)
	return {"ok": true, "reason": ""}


## Once a second: expansions advance from what their structures do - the command post finished (the base exists), the next
## template building ordered when the last one stands and the stores can pay, a garrison when the template is complete; a
## command post destroyed or cancelled before it stood ends the expansion.
func update_expansions() -> void:
	var now := sim.state.time
	var cs := sim.state.construction
	var bs := sim.logistics.bases
	for e: Dictionary in ws.war.expansions:
		if e.state != "building" and e.state != "garrison":
			continue
		var f := ws.war.faction(int(e.faction))
		var cp := cs.get_structure(int(e.site))
		if f == null or cp == null or cp.faction != int(e.faction):
			e.state = "failed"
			e.ended = snappedf(now, 0.1)
			e.why = str(e.why) + ": the command post was lost before the base stood"
			ws.log_event(int(e.faction), "build", "Expansion failed: %s" % e.why, e.pos)
			continue
		if cp.is_site():
			continue
		e.base = cp.base_id
		var b: Dictionary = cs.bases.get(cp.base_id, {})
		if b.is_empty():
			continue
		var items: Array = TEMPLATES[e.template].items
		if e.state == "building":
			if not pending_of(int(e.faction), &"", b.anchor, BaseSim.reach_of(b) + 40.0).is_empty() or now < float(e.get("retry", 0.0)):
				continue
			if int(e.next) >= items.size():
				e.state = "garrison"
				continue
			var item: StringName = items[int(e.next)]
			var face := Vector3.ZERO
			var threat := _threat_dir(int(e.faction), b.anchor)
			var fdef := StructureCatalog.get_def(item)
			if DefenceDefs.has(item):
				face = threat
			var near: Vector3 = b.anchor + (threat * 45.0 if face != Vector3.ZERO else Vector3.ZERO)
			var res := request(f, item, near, "%s: %s" % [e.why, fdef.display_name if fdef else String(item)], FacilityDefs.is_store(item), face)
			if res.ok:
				e.next = int(e.next) + 1
			else:
				e.retry = now + 30.0
		elif e.state == "garrison":
			var sq := _garrison_squad(f, b.anchor)
			if sq != null:
				ws.release_squads([sq.id], "garrison of a new base")
				sim.tactics.assign_garrison(sq, int(b.id), SquadState.Owner.SQUAD)
				e.state = "done"
				e.ended = snappedf(now, 0.1)
				ws.log_event(int(e.faction), "build", "%s established: %s garrisons it" % [e.why, sq.squad_name], b.anchor)
			elif now - float(e.get("retry", 0.0)) > 60.0:
				e.retry = now


## A squad to garrison a new base: a free squad of the faction (no operation, no garrison, not recovering), the nearest.
func _garrison_squad(f: FactionState, at: Vector3) -> SquadState:
	var best: SquadState = null
	var best_d := INF
	var p := ws.profile(f)
	for sid in ws._free_squads(f, p):
		var sq := sim.state.get_squad(sid)
		if sq == null or sq.garrison_base >= 0:
			continue
		var d := WarSim._flat(ws.squad_center(sq), at)
		if d < best_d:
			best_d = d
			best = sq
	return best


## Direction from p to the nearest objective the faction does not hold (where an attack would come from); ZERO without one.
func _threat_dir(f: int, p: Vector3) -> Vector3:
	var best := INF
	var dir := Vector3.ZERO
	for o: ObjectiveState in ws.war.all_objectives():
		if o.owner == f or o.owner < 0:
			continue
		var d := WarSim._flat(o.position, p)
		if d < best:
			best = d
			dir = Vector3(o.position.x - p.x, 0.0, o.position.z - p.z).normalized()
	return dir


## Once a second: the AI factions' construction sites get their crew's work (GAMEPLAY-01B), and orders of the old
## pending-record kind (saves from before GAMEPLAY-01B) whose time has come are placed (re-checked; a site that went bad
## refunds its cost).
func update() -> void:
	update_expansions()
	var cs := sim.state.construction
	for s: StructureState in cs.all():
		if s.needs_work() and float(s.work_record().get("crew", 0.0)) > 0.0:
			var what := FacilityDefs.display_name(s.type_id) if FacilityDefs.has(s.type_id) else String(s.type_id)
			var repairing := not s.is_site()
			# GAMEPLAY-01F: an AI repair crew stops while the faction believes enemies are close (work resumes later).
			if repairing and ws.intel.threat_near(s.faction, s.position, 250.0) > 0:
				s.repair["why"] = "work stopped: enemy reported near"
				continue
			if cs.add_work(s, float(s.work_record().crew)):
				stats.finished += 1
				ws.log_event(s.faction, "build", "%s %s at (%.0f, %.0f)" % [what, "repaired" if repairing else "finished", s.position.x, s.position.z], s.position)
	if ws.war.builds.is_empty():
		return
	var now := sim.state.time
	var keep: Array = []
	for b: Dictionary in ws.war.builds:
		if now < float(b.done):
			keep.append(b)
			continue
		var type_id := StringName(b.type)
		var def := StructureCatalog.get_def(type_id)
		var chk := _sm().check_building(def, b.pos, b.yaw, -1, true) if def and _sm() else {"ok": false, "reason": "no construction system"}
		if chk.ok:
			var s := sim.state.construction.add_building(type_id, chk.xform.origin, b.yaw, int(b.faction))
			sim.state.construction.add_clearings(_sm().clearings_for(s, true))
			stats.finished += 1
			ws.log_event(int(b.faction), "build", "%s finished at (%.0f, %.0f)" % [FacilityDefs.display_name(type_id) if FacilityDefs.has(type_id) else String(type_id), b.pos.x, b.pos.z], b.pos)
		else:
			stats.refunded += 1
			var base_id := int(b.paid_base)
			if sim.state.construction.bases.has(base_id):
				sim.logistics.bases.refund(base_id, {&"supplies": float(b.cost)})
			ws.log_event(int(b.faction), "build", "construction at (%.0f, %.0f) failed (%s): supplies refunded" % [b.pos.x, b.pos.z, chk.reason], b.pos)
	ws.war.builds = keep


## Pending orders of faction f of a type (all types: &"") near p (r = INF: anywhere): its construction sites and old
## pending records, each as {faction, type, pos}.
func pending_of(f: int, type_id := &"", p := Vector3.INF, r := INF) -> Array:
	var out := []
	for s: StructureState in sim.state.construction.all():
		if not s.is_site() or s.faction != f or (type_id != &"" and s.type_id != type_id):
			continue
		if p.is_finite() and Vector2(s.position.x - p.x, s.position.z - p.z).length() > r:
			continue
		out.append({"faction": f, "type": String(s.type_id), "pos": s.position, "id": s.id})
	for b: Dictionary in ws.war.builds:
		if int(b.faction) != f or (type_id != &"" and StringName(b.type) != type_id):
			continue
		if p.is_finite() and Vector2(b.pos.x - p.x, b.pos.z - p.z).length() > r:
			continue
		out.append(b)
	return out

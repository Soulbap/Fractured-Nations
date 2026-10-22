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
##   MIN_GAP_M of another structure, and is a pending record (WarState.builds) until finished, so the same
##   building is not ordered twice and a save in the middle of construction restores it.
class_name AiBases
extends RefCounted

## Supplies (kg) a building costs the AI faction, paid from its base stores when the order is given.
const BUILD_COST := {
	&"supply_depot": 450.0, &"supply_storage": 200.0, &"barracks_block": 550.0, &"vehicle_depot": 750.0,
	&"ammo_magazine": 320.0, &"fuel_point": 160.0, &"repair_bay": 260.0, &"sandbag_fighting_position": 45.0,
}
const BUILD_TIME_S := {
	&"supply_depot": 150.0, &"supply_storage": 90.0, &"barracks_block": 180.0, &"vehicle_depot": 210.0, &"ammo_magazine": 120.0,
	&"fuel_point": 70.0, &"repair_bay": 100.0, &"sandbag_fighting_position": 30.0,
}
## Free ground kept between a new building's centre and any other structure's footprint edge (m).
const MIN_GAP_M := 7.0
## The starting compound: [type, local x, local z] in a frame whose -Z is the front of the buildings.
const START_LAYOUT := [
	[&"vehicle_depot", -26.0, -22.0], [&"supply_depot", 4.0, -22.0], [&"fuel_point", 32.0, -20.0],
	[&"hq_building", 0.0, 12.0], [&"barracks_block", -32.0, 12.0], [&"ammo_magazine", 32.0, 10.0],
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
	for dist: float in [75.0, 100.0, 130.0, 160.0]:
		for k in 16:
			var a := base_dir + (k / 2 + 1) * (TAU / 16.0) * (1.0 if k % 2 == 0 else -1.0) if k > 0 else base_dir
			var c := Vector3(anchor.x + cos(a) * dist, 0.0, anchor.z + sin(a) * dist)
			c.y = ws._ground(c).y
			for yaw: float in [0.0, PI * 0.5, PI, -PI * 0.5]:
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
	if best_plan.is_empty():
		return {"ok": false, "reason": "no buildable ground near the headquarters", "placed": 0}
	var cs := sim.state.construction
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
	return out


# --- Later construction ------------------------------------------------------------------------------------------------

## Orders a building for faction f near `near`: finds a site (ring search 25-140 m, never within MIN_GAP_M of
## another structure or a pending order), pays BUILD_COST from the faction's bases (nearest store with the
## supplies first) and queues it. Returns {ok, reason, pos}.
func request(f: FactionState, type_id: StringName, near: Vector3, why: String) -> Dictionary:
	if _sm() == null:
		return {"ok": false, "reason": "no construction system"}
	var def := StructureCatalog.get_def(type_id)
	if def == null or not BUILD_COST.has(type_id):
		return {"ok": false, "reason": "unknown building"}
	var bs := sim.logistics.bases
	var bid := _payer_base(f, near, BUILD_COST[type_id])
	if bid < 0:
		stats.refused += 1
		return {"ok": false, "reason": "not enough supplies (%d kg needed)" % roundi(BUILD_COST[type_id])}
	var site := find_site(def, near, 25.0, 140.0)
	if not site.ok:
		stats.refused += 1
		return {"ok": false, "reason": "no buildable site near (%.0f, %.0f): %s" % [near.x, near.z, site.reason]}
	if not bs.pay(bid, {&"supplies": BUILD_COST[type_id]}):
		return {"ok": false, "reason": "payment failed"}
	var rec := {"faction": f.id, "type": String(type_id), "pos": site.pos, "yaw": site.yaw, "done": sim.state.time + BUILD_TIME_S[type_id],
		"cost": BUILD_COST[type_id], "paid_base": bid, "why": why, "id": ws.war.next_mission_id}
	ws.war.next_mission_id += 1
	ws.war.builds.append(rec)
	stats.started += 1
	ws.log_event(f.id, "build", "%s ordered near (%.0f, %.0f): %s" % [FacilityDefs.display_name(type_id) if FacilityDefs.has(type_id) else String(type_id), site.pos.x, site.pos.z, why], site.pos)
	return {"ok": true, "reason": "", "pos": site.pos}


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


func find_site(def: StructureDef, near: Vector3, min_r: float, max_r: float) -> Dictionary:
	var reason := "ground"
	for r: float in [min_r, min_r + 20.0, min_r + 45.0, min_r + 75.0, max_r]:
		var n := clampi(int(r / 8.0), 8, 20)
		for k in n:
			var a := TAU * k / n + r * 0.013
			var c := Vector3(near.x + cos(a) * r, 0.0, near.z + sin(a) * r)
			c.y = ws._ground(c).y
			if not ws.routes.passable(c):
				reason = "impassable"
				continue
			if _crowded(c, def):
				reason = "too close to other structures"
				continue
			var yaw := fposmod(a + PI * 0.5, TAU) - PI
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


## Once a second: orders whose time has come are placed (re-checked; a site that went bad refunds its cost).
func update() -> void:
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


## Pending orders of faction f of a type (all types: &"") near p (r = INF: anywhere).
func pending_of(f: int, type_id := &"", p := Vector3.INF, r := INF) -> Array:
	var out := []
	for b: Dictionary in ws.war.builds:
		if int(b.faction) != f or (type_id != &"" and StringName(b.type) != type_id):
			continue
		if p.is_finite() and Vector2(b.pos.x - p.x, b.pos.z - p.z).length() > r:
			continue
		out.append(b)
	return out

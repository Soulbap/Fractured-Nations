## Bases and what their facilities do (LOGISTICS-01 / BASE-02), part of LogisticsSim.
##
## A base is nothing but a name for facilities that stand close together (a facility is a
## placed structure whose type is in FacilityDefs; its `base_id` points at an entry of
## ConstructionState.bases). There are no tiers, no required buildings and no layout: a lone
## fuel point is an outpost, a headquarters with a barracks and depots is a main base, and
## the player may build anything anywhere. Everything below reads the structures the
## construction system already owns.
##
## Facility functions (costs are configurable constants, paid from the base's own stores):
##   barracks       recruit an infantry squad (supplies + ammunition, personnel from the
##                  faction's finite reserves, 60 s)                         -> WarSim.spawn_squad
##   vehicle depot  acquire a truck or APC (supplies + fuel, limited stock, 30 s) -> add_vehicle
##   depots / HQ    store supplies, receive deliveries, load, refuel and resupply
## Optional automation (plain rules, visible and overridable): keep a depot's stock above a
## threshold by sending an assigned truck from another depot; refuel idle vehicles.
class_name BaseSim
extends RefCounted

## Facilities this close to a base's anchor (m) join it.
const JOIN_M := 220.0
## Infantry squad recruited at a barracks.
const SQUAD_SIZE := 8
const RECRUIT_TIME_S := 60.0
const RECRUIT_COST := {&"supplies": 320.0, &"ammo": 192.0}
const RECRUIT_QUEUE_MAX := 2
## Vehicles a vehicle depot can hand out: type -> {cost, time, stock at construction}.
const VEHICLES := {
	&"truck_6x6": {"cost": {&"supplies": 600.0, &"fuel": 150.0}, "time": 30.0, "stock": 3},
	&"apc_8x8": {"cost": {&"supplies": 1500.0, &"fuel": 200.0}, "time": 45.0, "stock": 2},
}
const REPAIR_SUPPLIES_PER_HP := 0.5
const RULE_TICK_S := 5.0

var sim: WorldSim
var lsim: LogisticsSim
var _tick := 0.0
var _rule_timer := 0.0
var stats := {"squads_recruited": 0, "vehicles_acquired": 0, "deliveries_by_rule": 0, "soldiers_replaced": 0, "bases_captured": 0}


func _init(p_lsim: LogisticsSim) -> void:
	lsim = p_lsim
	sim = p_lsim.sim


func _cs() -> ConstructionState:
	return sim.state.construction


func bind() -> void:
	_cs().structure_added.connect(_on_added)
	_cs().structure_completed.connect(_on_added)
	_cs().structure_removed.connect(_on_removed)
	for s in _cs().all():
		_on_added(s)


# --- Bases -------------------------------------------------------------------------------------

func _on_added(s: StructureState) -> void:
	# GAMEPLAY-01B: a construction site is no facility yet - no base is founded or joined before it is finished.
	if not FacilityDefs.has(s.type_id) or s.is_site():
		return
	var cs := _cs()
	if s.base_id < 0 or not cs.bases.has(s.base_id):
		# BASE-01: a facility inside a base's area belongs to it; a proximity group is joined within JOIN_M.
		var best := -1
		var best_d := INF
		for b: Dictionary in cs.bases.values():
			if b.faction != s.faction:
				continue
			var d := Vector2(s.position.x - b.anchor.x, s.position.z - b.anchor.z).length()
			if d < reach_of(b) and d < best_d:
				best_d = d
				best = b.id
		if best < 0:
			var founds := FacilityDefs.founds_base(s.type_id)
			var nb := cs.add_base(_free_base_name(s.faction), s.faction, s.position,
				FacilityDefs.area_of(s.type_id) if founds else 0.0, s.id if founds else -1)
			best = nb.id
			if founds:
				lsim._event(s.faction, "%s established (area %d m)" % [nb.name, roundi(nb.radius)])
		elif FacilityDefs.founds_base(s.type_id) and float(cs.bases[best].get("radius", 0.0)) <= 0.0:
			# A command post in a proximity group turns it into an established base round the post.
			cs.bases[best]["radius"] = FacilityDefs.area_of(s.type_id)
			cs.bases[best]["founder"] = s.id
			cs.bases[best]["anchor"] = s.position
		s.base_id = best
	_update_anchor(s.base_id)
	var kind := FacilityDefs.kind_of(s.type_id)
	if kind == &"vehicle" and not s.facility.has("stock"):
		var st := {}
		for t in VEHICLES:
			st[String(t)] = VEHICLES[t].stock
		s.facility["stock"] = st


func _on_removed(s: StructureState) -> void:
	if s.base_id < 0 or not _cs().bases.has(s.base_id):
		return
	if facilities_of(s.base_id).is_empty():
		_cs().bases.erase(s.base_id)
	else:
		# A base without its command post keeps its area (the anchor stays where it was).
		if int(_cs().bases[s.base_id].get("founder", -1)) == s.id:
			_cs().bases[s.base_id]["founder"] = -1
		_update_anchor(s.base_id)


func _update_anchor(bid: int) -> void:
	var list := facilities_of(bid)
	if list.is_empty() or not _cs().bases.has(bid):
		return
	if float(_cs().bases[bid].get("radius", 0.0)) > 0.0:
		return  # BASE-01: an established base's area does not move
	var c := Vector3.ZERO
	for s in list:
		c += s.position
	_cs().bases[bid]["anchor"] = c / list.size()


func facilities_of(bid: int) -> Array[StructureState]:
	var out: Array[StructureState] = []
	for s in _cs().all():
		if s.base_id == bid and FacilityDefs.has(s.type_id) and not s.is_site():
			out.append(s)
	return out


func bases_of(faction: int) -> Array:
	var out := []
	for b: Dictionary in _cs().bases.values():
		if b.faction == faction:
			out.append(b)
	out.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return a.id < c.id)
	return out


func rename(bid: int, new_name: String) -> void:
	if _cs().bases.has(bid) and new_name.strip_edges() != "":
		_cs().bases[bid]["name"] = new_name.strip_edges()


## How far from its anchor a base takes in facilities: its area, or JOIN_M for a proximity group.
static func reach_of(b: Dictionary) -> float:
	var r := float(b.get("radius", 0.0))
	return r if r > 0.0 else JOIN_M


## BASE-01: the established base (one with an area) of `faction` whose area contains p, or -1.
func base_area_at(p: Vector3, faction: int) -> int:
	var best := -1
	var best_d := INF
	for b: Dictionary in bases_of(faction):
		var r := float(b.get("radius", 0.0))
		var d := Vector2(p.x - b.anchor.x, p.z - b.anchor.z).length()
		if r > 0.0 and d <= r and d < best_d:
			best_d = d
			best = b.id
	return best


## BASE-01 ownership rules for a building `faction` wants to place at p ("" = allowed). A command post
## founds a base: not inside or overlapping one of the faction's own bases, nor on ground another
## faction holds (its base areas, the objectives it owns). Every other facility belongs to a base: it
## must stand inside one of the faction's base areas. Structures that are no facility (walls, fences,
## roads) are not restricted.
func placement_rule(type_id: StringName, p: Vector3, faction: int) -> String:
	if not FacilityDefs.has(type_id):
		return ""
	var q := Vector2(p.x, p.z)
	if FacilityDefs.founds_base(type_id):
		var area := FacilityDefs.area_of(type_id)
		for b: Dictionary in _cs().bases.values():
			var d := q.distance_to(Vector2(b.anchor.x, b.anchor.z))
			if int(b.faction) == faction and d < reach_of(b) + area * 0.5:
				return "too close to %s (one command post per base)" % b.name
			if int(b.faction) != faction and d < reach_of(b) + area:
				return "too close to %s's %s" % [WorldState.faction_name(int(b.faction)), b.name]
		for o: ObjectiveState in sim.state.war.objectives.values():
			if o.owner >= 0 and o.owner != faction and q.distance_to(Vector2(o.position.x, o.position.z)) < o.radius:
				return "%s is held by %s" % [o.obj_name, WorldState.faction_name(o.owner)]
		# GAMEPLAY-01B: a command post still being built claims its area too.
		for s: StructureState in _cs().all():
			if s.is_site() and FacilityDefs.founds_base(s.type_id) and s.faction == faction and q.distance_to(Vector2(s.position.x, s.position.z)) < FacilityDefs.area_of(s.type_id) + area * 0.5:
				return "too close to the command post under construction (one command post per base)"
		return ""
	if base_area_at(p, faction) < 0:
		return "outside the base area" if not bases_of(faction).is_empty() else "no base: place a command post first"
	return ""


## BASE-01 facility properties of a base: soldier capacity (beds), parking bays, guard posts.
func capacity(bid: int) -> int:
	var n := 0
	for s in facilities_of(bid):
		if s.is_operational():
			n += FacilityDefs.beds_of(s.type_id)
	return n


## Every parking bay of the base: [{pos, yaw, structure, slot}] (y = the pad's ground).
func parking_spots(bid: int) -> Array:
	var out := []
	for s in facilities_of(bid):
		for i in FacilityDefs.slots_of(s.type_id):
			var sp := FacilityDefs.parking_spot(s, i)
			var p: Vector3 = sp.pos
			p.y = s.position.y
			sp["pos"] = p
			sp["structure"] = s.id
			sp["slot"] = i
			out.append(sp)
	return out


## The first parking bay of the base with no vehicle on it ({} when the base has none free).
func free_parking_spot(bid: int) -> Dictionary:
	for sp: Dictionary in parking_spots(bid):
		var taken := false
		for id in lsim.vsim.ids:
			var u: UnitState = sim.state.units.get(id)
			if u and Vector2(u.position.x - sp.pos.x, u.position.z - sp.pos.z).length() < 2.5:
				taken = true
				break
		if not taken:
			return sp
	return {}


## Positions of the base's guard posts (for defence orders: SquadTactics DEFEND at a post).
func guard_posts(bid: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s in facilities_of(bid):
		if FacilityDefs.kind_of(s.type_id) == &"guard" and s.is_operational():
			out.append(s.position)
	return out


func base_of_position(p: Vector3, faction: int, radius := JOIN_M) -> int:
	var best := -1
	var best_d := radius
	for b: Dictionary in bases_of(faction):
		var d := Vector2(p.x - b.anchor.x, p.z - b.anchor.z).length()
		if d < best_d:
			best_d = d
			best = b.id
	return best


## "Main base" (has a headquarters), "Base" (several kinds of facility) or "Outpost".
func base_kind(bid: int) -> String:
	var kinds := {}
	for s in facilities_of(bid):
		kinds[FacilityDefs.kind_of(s.type_id)] = true
	if kinds.has(&"hq"):
		return "Main base"
	return "Base" if kinds.size() >= 3 else "Outpost"


## The faction's main base (the one with a headquarters, else the one with most facilities), -1 when it has none.
func main_base(faction: int) -> int:
	var best := -1
	var best_score := -1
	for b: Dictionary in bases_of(faction):
		var sc := facilities_of(b.id).size() + (100 if base_kind(b.id) == "Main base" else 0)
		if sc > best_score:
			best_score = sc
			best = b.id
	return best


## The first facility of a kind in the faction's bases (the nearest to `near` when given), or null.
func facility_of_kind(faction: int, kind: StringName, near := Vector3.INF) -> StructureState:
	var best: StructureState = null
	var best_d := INF
	for b: Dictionary in bases_of(faction):
		for s in facilities_of(b.id):
			if FacilityDefs.kind_of(s.type_id) != kind:
				continue
			var d := 0.0 if not near.is_finite() else Vector2(s.position.x - near.x, s.position.z - near.z).length()
			if d < best_d:
				best_d = d
				best = s
	return best


## A base falls to another faction (its objective was captured): the buildings, their stores and their pending
## orders change hands intact - the stock is the captor's loot and leaves the old owner's books (the old owner's
## ledger records it) - queued recruits and vehicles are cancelled first (resources back into the stores, the
## personnel back into the old faction's reserves, so nobody is lost or created). Vehicles standing there keep
## their own faction. Returns {ok, loot, facilities}.
func capture_base(bid: int, new_faction: int) -> Dictionary:
	var b: Dictionary = _cs().bases.get(bid, {})
	if b.is_empty() or int(b.faction) == new_faction:
		return {"ok": false}
	var old: int = b.faction
	var loot := {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}
	var n := 0
	for s in facilities_of(bid):
		while not s.facility.get("queue", []).is_empty():
			cancel_queue(s.id, 0)
		s.faction = new_faction
		n += 1
		if s.inventory != null:
			for k in loot:
				loot[k] += s.inventory.get_qty(StringName(k))
	# GAMEPLAY-01D: the base's other structures (towers, positions, walls inside its area) are captured with it - intact,
	# damage included; roads and paved areas stay as they are.
	var reach := reach_of(b)
	for s: StructureState in _cs().all():
		if s.faction != old or FacilityDefs.has(s.type_id):
			continue
		var def := StructureCatalog.get_def(s.type_id)
		if def == null or def.is_surface():
			continue
		if Vector2(s.site_center().x - b.anchor.x, s.site_center().z - b.anchor.z).length() <= reach:
			s.faction = new_faction
			n += 1
	b["faction"] = new_faction
	var of := sim.state.war.faction(old)
	if of:
		for k in loot:
			of.ledger["lost_with_bases"][k] = float(of.ledger["lost_with_bases"][k]) + loot[k]
	stats.bases_captured += 1
	# GAMEPLAY-05: a generated name carries the old owner ("South base 2" held by North read as an enemy base in every
	# list); it takes the new owner's next number. Named places (scenario bases) keep their names.
	var old_name := String(b.name)
	if old_name.begins_with(WorldState.faction_name(old) + " base"):
		b["name"] = _free_base_name(new_faction)
	var renamed := "" if String(b.name) == old_name else " (now %s)" % b.name
	lsim._event(new_faction, "%s captured%s: %d facilities, %d supplies, %d ammunition, %d fuel" % [old_name, renamed, n, roundi(loot.supplies), roundi(loot.ammo), roundi(loot.fuel)])
	lsim._event(old, "%s was lost to %s" % [old_name, WorldState.faction_name(new_faction)])
	return {"ok": true, "loot": loot, "facilities": n}


## "<Faction> base <n>" with the first number no base of that name uses.
func _free_base_name(f: int) -> String:
	var used := {}
	for x: Dictionary in _cs().bases.values():
		used[String(x.name)] = true
	var n := 1
	while used.has("%s base %d" % [WorldState.faction_name(f), n]):
		n += 1
	return "%s base %d" % [WorldState.faction_name(f), n]


## Everything the player may want to know about a base.
func summary(bid: int) -> Dictionary:
	var b: Dictionary = _cs().bases.get(bid, {})
	if b.is_empty():
		return {}
	var counts := {}
	for s in facilities_of(bid):
		var n := FacilityDefs.display_name(s.type_id)
		counts[n] = counts.get(n, 0) + 1
	var stock := base_stock(bid)
	var vehicles := []
	var soldiers := 0
	var activities: Array[String] = []
	for id in lsim.vsim.ids:
		var u: UnitState = sim.state.units.get(id)
		if u and u.faction == b.faction and Vector2(u.position.x - b.anchor.x, u.position.z - b.anchor.z).length() < JOIN_M:
			vehicles.append(id)
			if not u.veh.job.is_empty():
				activities.append("%s %s" % [u.unit_name, lsim.describe_job(u)])
	for u: UnitState in sim.state.units.values():
		if u.kind == UnitState.Kind.SOLDIER and u.faction == b.faction and u.alive and Vector2(u.position.x - b.anchor.x, u.position.z - b.anchor.z).length() < JOIN_M:
			soldiers += 1
	for s in facilities_of(bid):
		for q: Dictionary in s.facility.get("queue", []):
			activities.append("%s: %s (%d s left)" % [FacilityDefs.display_name(s.type_id), q.get("what", "queued"), maxi(0, roundi(float(q.done) - sim.state.time))])
	return {"id": bid, "name": b.name, "faction": b.faction, "kind": base_kind(bid), "facilities": counts, "stock": stock, "vehicles": vehicles, "soldiers": soldiers, "activities": activities, "anchor": b.anchor,
		"radius": float(b.get("radius", 0.0)), "capacity": capacity(bid), "parking": parking_spots(bid).size(), "guard_posts": guard_posts(bid).size()}


func describe(bid: int) -> String:
	var sm := summary(bid)
	if sm.is_empty():
		return ""
	var fac := []
	for k in sm.facilities:
		fac.append("%s x%d" % [k, sm.facilities[k]] if sm.facilities[k] > 1 else k)
	var stock: Dictionary = sm.stock
	var st := "ammo %d kg, fuel %d l, supplies %d kg" % [roundi(stock.ammo), roundi(stock.fuel), roundi(stock.supplies)]
	return "%s - %s: %s | stock: %s | %d vehicles, %d soldiers (capacity %d), %d parking bays" % [sm.name, sm.kind, ", ".join(fac), st, sm.vehicles.size(), sm.soldiers, sm.capacity, sm.parking]


# --- Base stock: one view over the stores of a base ------------------------------------------------

func base_stores(bid: int) -> Array[StructureState]:
	var out: Array[StructureState] = []
	for s in facilities_of(bid):
		# GAMEPLAY-01F: a disabled store keeps what it holds but gives nothing out and takes nothing in until repaired.
		if s.inventory != null and s.is_operational():
			out.append(s)
	return out


func base_stock(bid: int) -> Dictionary:
	var t := {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}
	for s in base_stores(bid):
		for k in t:
			t[k] += s.inventory.get_qty(StringName(k))
	return t


func can_pay(bid: int, cost: Dictionary) -> bool:
	var stock := base_stock(bid)
	for k in cost:
		if stock.get(String(k), 0.0) < float(cost[k]) - 0.001:
			return false
	return true


## Pays a cost from the base's stores (stores of the facility first); atomic: all or nothing.
func pay(bid: int, cost: Dictionary, first: StructureState = null) -> bool:
	if not can_pay(bid, cost):
		return false
	var stores := base_stores(bid)
	if first and stores.has(first):
		stores.erase(first)
		stores.push_front(first)
	for k in cost:
		var left := float(cost[k])
		for s in stores:
			if left <= 0.0:
				break
			left -= s.inventory.take(StringName(k), left)
	return true


func refund(bid: int, cost: Dictionary, first: StructureState = null) -> void:
	var stores := base_stores(bid)
	if first and stores.has(first):
		stores.erase(first)
		stores.push_front(first)
	for k in cost:
		var left := float(cost[k])
		for s in stores:
			if left <= 0.0:
				break
			var put: float = s.inventory.add(StringName(k), left)
			left -= put
			Inventory.audit.refunded[StringName(k)] = float(Inventory.audit.refunded.get(StringName(k), 0.0)) + put


## GAMEPLAY-01B: everything faction f can spend - its pool (FactionState.pool, the stock without a building) plus the
## stores of all its bases.
func faction_stock(faction: int) -> Dictionary:
	var t := {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}
	var f := sim.state.war.faction(faction)
	if f:
		for k in t:
			t[k] += f.pool.get_qty(StringName(k))
	for b: Dictionary in bases_of(faction):
		var st := base_stock(b.id)
		for k in t:
			t[k] += st[k]
	return t


func faction_can_pay(faction: int, cost: Dictionary) -> bool:
	var stock := faction_stock(faction)
	for k in cost:
		if stock.get(String(k), 0.0) < float(cost[k]) - 0.001:
			return false
	return true


## Pays a cost for faction f, atomically: the pool first, then the stores of base `bid` (the base the order is for, -1
## none), then the other bases. Returns what came from where ({"pool": {item: qty}, "bases": {base id: {item: qty}}}) so a
## refund puts it back exactly there, or {} when the faction cannot pay.
func faction_pay(faction: int, cost: Dictionary, bid := -1) -> Dictionary:
	if not faction_can_pay(faction, cost):
		return {}
	var f := sim.state.war.faction(faction)
	var paid := {"pool": {}, "bases": {}}
	var order: Array = []
	if bid >= 0 and _cs().bases.has(bid):
		order.append(bid)
	for b: Dictionary in bases_of(faction):
		if not order.has(b.id):
			order.append(b.id)
	for k in cost:
		var left := float(cost[k])
		if f:
			var got := f.pool.take(StringName(k), left)
			if got > 0.0:
				paid.pool[String(k)] = got
				left -= got
		for b in order:
			if left <= 0.001:
				break
			for s in base_stores(b):
				if left <= 0.001:
					break
				var got := s.inventory.take(StringName(k), left)
				if got > 0.0:
					left -= got
					if not paid.bases.has(b):
						paid.bases[b] = {}
					paid.bases[b][String(k)] = float(paid.bases[b].get(String(k), 0.0)) + got
	return paid


## Puts a faction_pay record back where it came from (a base that no longer exists, or is full: into the pool).
func faction_refund(faction: int, paid: Dictionary) -> void:
	var f := sim.state.war.faction(faction)
	for k: String in paid.get("pool", {}):
		if f:
			var q := float(paid.pool[k])
			f.pool.add(StringName(k), q)
			Inventory.audit.refunded[StringName(k)] = float(Inventory.audit.refunded.get(StringName(k), 0.0)) + q
	var bl: Dictionary = paid.get("bases", {})
	for b in bl:
		var bid := int(b)
		for k: String in bl[b]:
			var left := float(bl[b][k])
			if _cs().bases.has(bid) and int(_cs().bases[bid].faction) == faction:
				for s in base_stores(bid):
					if left <= 0.001:
						break
					var put := s.inventory.add(StringName(k), left)
					left -= put
					Inventory.audit.refunded[StringName(k)] = float(Inventory.audit.refunded.get(StringName(k), 0.0)) + put
			if left > 0.001 and f:
				f.pool.add(StringName(k), left)
				Inventory.audit.refunded[StringName(k)] = float(Inventory.audit.refunded.get(StringName(k), 0.0)) + left


## Supplies that arrive for faction f from an explicit source (a cache, income): into its supply stores when it has one
## with room, the rest into its pool. Returns {item: qty} that went into stores.
func faction_deposit(faction: int, items: Dictionary) -> Dictionary:
	var f := sim.state.war.faction(faction)
	var stored := {}
	for k in items:
		var left := float(items[k])
		for s in _supply_stores(faction, StringName(k)):
			if left <= 0.001:
				break
			var put := s.inventory.add(StringName(k), left)
			left -= put
			stored[String(k)] = float(stored.get(String(k), 0.0)) + put
		if left > 0.001 and f:
			f.pool.add(StringName(k), left)
	return stored


## The faction's operational supply-type stores that accept `item` (supply depots and storage), main base first.
func _supply_stores(faction: int, item: StringName) -> Array[StructureState]:
	var out: Array[StructureState] = []
	var mb := main_base(faction)
	for b: Dictionary in bases_of(faction):
		for s in base_stores(b.id):
			if FacilityDefs.kind_of(s.type_id) == &"supply" and s.inventory.accepts(item):
				if b.id == mb:
					out.push_front(s)
				else:
					out.append(s)
	return out


## GAMEPLAY-01B: the pool moves into the faction's first supply depot once one is operational (Inventory.transfer: nothing
## is created or lost). Returns the quantities moved.
func _settle_pool(f: FactionState) -> Dictionary:
	if f.pool.is_empty():
		return {}
	var moved := {}
	var into: StructureState = null
	for item in Inventory.ITEMS:
		for s in _supply_stores(f.id, item):
			var q := Inventory.transfer(f.pool, s.inventory, item, f.pool.get_qty(item))
			if q > 0.0:
				moved[String(item)] = float(moved.get(String(item), 0.0)) + q
				into = s
	if moved.is_empty():
		return {}
	var parts: Array[String] = []
	for k: String in moved:
		parts.append("%d %s %s" % [roundi(moved[k]), Inventory.UNITS[StringName(k)], Inventory.NAMES[StringName(k)]])
	lsim._event(f.id, "%s now holds the supplies carried so far: %s" % [lsim.store_name(into), ", ".join(parts)])
	return moved


func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d %s %s" % [roundi(cost[k]), Inventory.UNITS[StringName(k)], Inventory.NAMES[StringName(k)]])
	return ", ".join(parts)


# --- Barracks: recruiting ---------------------------------------------------------------------------

## Queues a squad at a barracks. Returns {ok, reason}.
func recruit(barracks_id: int) -> Dictionary:
	var s := lsim.structure(barracks_id)
	if s == null or FacilityDefs.kind_of(s.type_id) != &"barracks":
		return {"ok": false, "reason": "That is not a barracks"}
	if not s.is_operational():
		return {"ok": false, "reason": "The barracks is not operational (%s)" % s.condition_text()}
	var war := sim.state.war
	var f := war.faction(s.faction)
	if f == null or sim.war == null:
		return {"ok": false, "reason": "No war: nobody to recruit"}
	var q: Array = s.facility.get("queue", [])
	if q.size() >= RECRUIT_QUEUE_MAX:
		return {"ok": false, "reason": "The barracks is training %d squads already" % q.size()}
	if f.reserves < SQUAD_SIZE:
		return {"ok": false, "reason": "No personnel left in reserve (%d)" % f.reserves}
	# GAMEPLAY-01B: a New Game player trains no more soldiers than his bases have beds for.
	if f.player and war.rule("bed_limit", false):
		var beds := 0
		for b: Dictionary in bases_of(f.id):
			beds += capacity(b.id)
		var have := soldiers_of(f.id) + queued_recruits(f.id)
		if have + SQUAD_SIZE > beds:
			return {"ok": false, "reason": "Not enough beds: %d soldiers and recruits, %d beds (a barracks adds 32)" % [have, beds]}
	var entry := {"kind": "squad", "what": "training a squad", "done": sim.state.time + RECRUIT_TIME_S, "n": SQUAD_SIZE}
	if f.player and war.rule("build_costs", false):
		# The player pays from everything the faction holds (pool and bases), the barracks' base first.
		var paid := faction_pay(f.id, RECRUIT_COST, s.base_id)
		if paid.is_empty():
			var st := faction_stock(f.id)
			return {"ok": false, "reason": "Not enough: a squad needs %s (you have %d kg supplies, %d kg ammunition)" % [cost_text(RECRUIT_COST), roundi(st.supplies), roundi(st.ammo)]}
		entry["paid"] = paid
	elif not pay(s.base_id, RECRUIT_COST, s):
		return {"ok": false, "reason": "Not enough supplies at the base: a squad needs %s" % cost_text(RECRUIT_COST)}
	f.reserves -= SQUAD_SIZE
	q.append(entry)
	s.facility["queue"] = q
	lsim._event(s.faction, "%s: training a squad of %d (%d s)" % [lsim.store_name(s), SQUAD_SIZE, roundi(RECRUIT_TIME_S)])
	return {"ok": true, "reason": ""}


## GAMEPLAY-01E: replacements for a depleted squad at a barracks - the squad keeps its identity, the new soldiers join it.
## The same rules as recruiting a squad, per soldier: an operational barracks, personnel from the faction's reserves, the
## recruiting cost (RECRUIT_COST per SQUAD_SIZE soldiers) paid like a recruit (the player from everything he holds, an AI
## faction from the base), the bed limit, and time (RECRUIT_TIME_S per SQUAD_SIZE, at least REPLENISH_MIN_S). The squad
## must stand at the base (within JOIN_M of the barracks) and is never filled above SQUAD_SIZE. Cancel refunds it like a
## recruit. Returns {ok, reason, n}.
const REPLENISH_MIN_S := 20.0


func replenish(barracks_id: int, squad_id: int) -> Dictionary:
	var s := lsim.structure(barracks_id)
	if s == null or FacilityDefs.kind_of(s.type_id) != &"barracks":
		return {"ok": false, "reason": "That is not a barracks"}
	if not s.is_operational():
		return {"ok": false, "reason": "The barracks is not operational (%s)" % s.condition_text()}
	var war := sim.state.war
	var f := war.faction(s.faction)
	var sq := sim.state.get_squad(squad_id)
	if f == null or sim.war == null:
		return {"ok": false, "reason": "No war: nobody to recruit"}
	if sq == null or sq.members.is_empty() or sq.faction != s.faction:
		return {"ok": false, "reason": "No such squad of yours"}
	var n := SQUAD_SIZE - sq.members.size() - queued_for_squad(sq.id)
	if n <= 0:
		return {"ok": false, "reason": "%s is at full strength (%d)" % [sq.squad_name, SQUAD_SIZE] if queued_for_squad(sq.id) == 0 else "%s already has replacements on the way" % sq.squad_name}
	var c := sim.war.squad_center(sq)
	if Vector2(c.x - s.position.x, c.z - s.position.z).length() > JOIN_M:
		return {"ok": false, "reason": "%s must come to the base first (%.0f m from the barracks)" % [sq.squad_name, Vector2(c.x - s.position.x, c.z - s.position.z).length()]}
	var q: Array = s.facility.get("queue", [])
	if q.size() >= RECRUIT_QUEUE_MAX:
		return {"ok": false, "reason": "The barracks is busy (%d in training)" % q.size()}
	if f.reserves < n:
		return {"ok": false, "reason": "Not enough personnel in reserve (%d, %d needed)" % [f.reserves, n]}
	if f.player and war.rule("bed_limit", false):
		var beds := 0
		for b: Dictionary in bases_of(f.id):
			beds += capacity(b.id)
		var have := soldiers_of(f.id) + queued_recruits(f.id)
		if have + n > beds:
			return {"ok": false, "reason": "Not enough beds: %d soldiers and recruits, %d beds" % [have, beds]}
	var cost := {}
	for k in RECRUIT_COST:
		cost[k] = roundf(float(RECRUIT_COST[k]) * n / SQUAD_SIZE)
	var entry := {"kind": "replenish", "what": "replacements for %s (%d)" % [sq.squad_name, n], "n": n, "squad": sq.id,
		"done": sim.state.time + maxf(REPLENISH_MIN_S, RECRUIT_TIME_S * n / SQUAD_SIZE), "cost": {"supplies": cost[&"supplies"], "ammo": cost[&"ammo"]}}
	if f.player and war.rule("build_costs", false):
		var paid := faction_pay(f.id, cost, s.base_id)
		if paid.is_empty():
			return {"ok": false, "reason": "Not enough: %d replacements need %s" % [n, cost_text(cost)]}
		entry["paid"] = paid
	elif not pay(s.base_id, cost, s):
		return {"ok": false, "reason": "Not enough supplies at the base: %d replacements need %s" % [n, cost_text(cost)]}
	f.reserves -= n
	q.append(entry)
	s.facility["queue"] = q
	lsim._event(s.faction, "%s: %d replacements for %s (%d s)" % [lsim.store_name(s), n, sq.squad_name, roundi(float(entry.done) - sim.state.time)])
	return {"ok": true, "reason": "", "n": n}


## Replacements queued for a squad at all barracks.
func queued_for_squad(squad_id: int) -> int:
	var n := 0
	for s in _cs().all():
		for e: Dictionary in s.facility.get("queue", []):
			if e.kind == "replenish" and int(e.get("squad", -1)) == squad_id:
				n += int(e.n)
	return n


func cancel_queue(structure_id: int, index := 0) -> bool:
	var s := lsim.structure(structure_id)
	if s == null:
		return false
	var q: Array = s.facility.get("queue", [])
	if index >= q.size():
		return false
	var e: Dictionary = q[index]
	q.remove_at(index)
	if e.kind == "squad" or e.kind == "replenish":
		if e.has("paid"):
			faction_refund(s.faction, e.paid)
		elif e.kind == "replenish":
			refund(s.base_id, {&"supplies": float(e.cost.supplies), &"ammo": float(e.cost.ammo)}, s)
		else:
			refund(s.base_id, RECRUIT_COST, s)
		var f := sim.state.war.faction(s.faction)
		if f:
			f.reserves += int(e.n)
	else:
		refund(s.base_id, VEHICLES[StringName(e.type)].cost, s)
		var st: Dictionary = s.facility.get("stock", {})
		st[e.type] = int(st.get(e.type, 0)) + 1
	s.facility["queue"] = q
	return true


# --- Vehicle depot: acquiring vehicles --------------------------------------------------------------

func acquire_vehicle(depot_id: int, type_id: StringName) -> Dictionary:
	var s := lsim.structure(depot_id)
	if s == null or FacilityDefs.kind_of(s.type_id) != &"vehicle":
		return {"ok": false, "reason": "That is not a vehicle depot"}
	if not VEHICLES.has(type_id):
		return {"ok": false, "reason": "Unknown vehicle"}
	if not s.is_operational():
		return {"ok": false, "reason": "The depot is not operational (%s)" % s.condition_text()}
	var q: Array = s.facility.get("queue", [])
	if q.size() >= 2:
		return {"ok": false, "reason": "The depot is busy (%d vehicles being prepared)" % q.size()}
	var st: Dictionary = s.facility.get("stock", {})
	if int(st.get(String(type_id), 0)) <= 0:
		return {"ok": false, "reason": "No %s left at this depot" % VehicleDefs.get_def(type_id).display_name}
	var v: Dictionary = VEHICLES[type_id]
	if not pay(s.base_id, v.cost, s):
		return {"ok": false, "reason": "Not enough at the base: %s needs %s" % [VehicleDefs.get_def(type_id).display_name, cost_text(v.cost)]}
	st[String(type_id)] = int(st[String(type_id)]) - 1
	s.facility["stock"] = st
	q.append({"kind": "vehicle", "type": String(type_id), "what": "preparing a %s" % VehicleDefs.get_def(type_id).short_name, "done": sim.state.time + float(v.time)})
	s.facility["queue"] = q
	lsim._event(s.faction, "%s: preparing a %s (%d s)" % [lsim.store_name(s), VehicleDefs.get_def(type_id).short_name, roundi(v.time)])
	return {"ok": true, "reason": ""}


# --- Per tick -----------------------------------------------------------------------------------------

## Living soldiers of a faction (squad members) and the recruits its barracks are training.
func soldiers_of(faction: int) -> int:
	var n := 0
	for sq: SquadState in sim.state.squads.values():
		if sq.faction == faction:
			n += sq.members.size()
	return n


func queued_recruits(faction: int) -> int:
	var n := 0
	for b: Dictionary in bases_of(faction):
		for s in facilities_of(b.id):
			for e: Dictionary in s.facility.get("queue", []):
				if e.kind == "squad" or e.kind == "replenish":
					n += int(e.n)
	return n


func update(dt: float) -> void:
	_tick -= dt
	if _tick <= 0.0:
		_tick = 1.0
		_process_queues()
		for f: FactionState in sim.state.war.factions.values():
			_settle_pool(f)
	_rule_timer -= dt
	if _rule_timer <= 0.0:
		_rule_timer = RULE_TICK_S
		_run_rules()


func _process_queues() -> void:
	var now := sim.state.time
	for s in _cs().all():
		var q: Array = s.facility.get("queue", [])
		if q.is_empty():
			continue
		var keep: Array = []
		for e: Dictionary in q:
			if not s.is_operational():
				# GAMEPLAY-01F: a disabled facility's queue waits (it resumes when the building is repaired).
				e["done"] = float(e.done) + 1.0
				keep.append(e)
				continue
			if now < float(e.done):
				keep.append(e)
				continue
			if e.kind == "squad":
				_finish_squad(s)
			elif e.kind == "replenish":
				if not _finish_replenish(s, e):
					e["done"] = now + 10.0
					keep.append(e)
			else:
				if not _finish_vehicle(s, StringName(e.type)):
					# No free spot at the depot: try again in a few seconds.
					e["done"] = now + 5.0
					keep.append(e)
		s.facility["queue"] = keep


func _finish_squad(s: StructureState) -> void:
	var f := sim.state.war.faction(s.faction)
	if f == null:
		return
	var def := StructureCatalog.get_def(s.type_id)
	var front := def.bounds().position.z if def else -4.0
	var at := s.position + Basis(Vector3.UP, s.yaw) * Vector3(0.0, 0.0, front - 5.0)
	at.y = lsim.vsim.ground_at(at)
	# AI-WAR-LOGISTICS-01: an AI faction's recruits first replace the casualties of a depleted squad resting at the
	# base (the squad is rebuilt, not duplicated); what is left forms a new squad. The player's recruits always
	# form a new squad (the player decides about his own squads).
	var left := SQUAD_SIZE
	if not f.player:
		left = _fill_depleted(f, s, at, SQUAD_SIZE)
	if left <= 0:
		lsim._event(s.faction, "%d replacements join squads at %s" % [SQUAD_SIZE, lsim.store_name(s)])
		return
	var sq := sim.war.spawn_squad(f, at, left)
	sq.station_objective = -1
	sq.origin = "recruit"
	sq.born_at = sim.state.time
	f.ledger.squads_recruited = int(f.ledger.squads_recruited) + 1
	stats.squads_recruited += 1
	lsim._event(s.faction, "Squad %s is ready at %s" % [sq.squad_name, lsim.store_name(s)])


## GAMEPLAY-01E: replacements are ready - they join their squad when it stands at the base (else the entry waits, saying
## why); a squad that no longer exists gets a new squad instead (they are paid for). Returns false to wait.
func _finish_replenish(s: StructureState, e: Dictionary) -> bool:
	var f := sim.state.war.faction(s.faction)
	if f == null:
		return true
	var def := StructureCatalog.get_def(s.type_id)
	var front := def.bounds().position.z if def else -4.0
	var at := s.position + Basis(Vector3.UP, s.yaw) * Vector3(0.0, 0.0, front - 5.0)
	at.y = lsim.vsim.ground_at(at)
	var n := int(e.n)
	var sq := sim.state.get_squad(int(e.get("squad", -1)))
	if sq == null or sq.members.is_empty():
		var nsq := sim.war.spawn_squad(f, at, n)
		nsq.origin = "recruit"
		lsim._event(s.faction, "%d replacements form squad %s at %s (their squad was lost)" % [n, nsq.squad_name, lsim.store_name(s)])
		return true
	var c := sim.war.squad_center(sq)
	if Vector2(c.x - s.position.x, c.z - s.position.z).length() > JOIN_M + 80.0:
		e["what"] = "replacements for %s waiting: the squad is away from the base" % sq.squad_name
		return false
	n = mini(n, SQUAD_SIZE - sq.members.size())
	var ids := sim.war.spawn_recruits(f, at, n, sq.squad_name)
	var joined := sim.state.add_to_squad(sq.id, ids)
	sim.combat.apply_composition(sq, ids)
	sim.tactics.validate(sq)
	sim.squads._reapply(sq)
	stats.soldiers_replaced = int(stats.get("soldiers_replaced", 0)) + joined
	f.ledger["replenished"] = int(f.ledger.get("replenished", 0)) + joined
	lsim._event(s.faction, "%d replacements joined %s at %s (%d soldiers)" % [joined, sq.squad_name, lsim.store_name(s), sq.members.size()])
	return true


## Recruits (n) join depleted squads of faction f that stand within the base: the most depleted first, up to
## SQUAD_SIZE each. Returns the recruits that found no squad to join.
func _fill_depleted(f: FactionState, barracks: StructureState, at: Vector3, n: int) -> int:
	var b: Dictionary = _cs().bases.get(barracks.base_id, {})
	var anchor: Vector3 = b.get("anchor", barracks.position)
	var cands: Array = []
	for sq: SquadState in sim.state.all_squads():
		if sq.faction != f.id or sq.op_id >= 0 or sq.members.size() >= SQUAD_SIZE - 1 or sq.members.is_empty():
			continue
		if sq.tactic_owner == SquadState.Owner.PLAYER:
			continue
		if Vector2(sim.war.squad_center(sq).x - anchor.x, sim.war.squad_center(sq).z - anchor.z).length() > JOIN_M:
			continue
		cands.append(sq)
	cands.sort_custom(func(a: SquadState, c: SquadState) -> bool: return a.members.size() < c.members.size())
	for sq: SquadState in cands:
		if n <= 0:
			break
		var take := mini(n, SQUAD_SIZE - sq.members.size())
		if take <= 0:
			continue
		var ids := sim.war.spawn_recruits(f, at, take)
		var joined := sim.state.add_to_squad(sq.id, ids)
		sim.combat.apply_composition(sq, ids)
		sim.tactics.validate(sq)
		n -= joined
		stats.soldiers_replaced = int(stats.get("soldiers_replaced", 0)) + joined
	return n


func _finish_vehicle(s: StructureState, type_id: StringName) -> bool:
	# A free bay in front of the depot (sideways slots, checked for other vehicles).
	var def := VehicleDefs.get_def(type_id)
	for slot in 8:
		var p := FacilityDefs.dock_point(s, slot)
		p.y = lsim.vsim.ground_at(p)
		if not lsim.vsim.spot_valid(p):
			continue
		var clear := true
		for id in lsim.vsim.ids:
			var o: UnitState = sim.state.units.get(id)
			if o and Vector2(o.position.x - p.x, o.position.z - p.z).length() < 8.0:
				clear = false
				break
		if not clear:
			continue
		var yaw := s.yaw  # facing out of the depot front
		var u := sim.state.add_vehicle(type_id, s.faction, p, yaw)
		u.veh.fuel = def.fuel_capacity
		var bf := sim.state.war.faction(s.faction)
		if bf:
			bf.ledger.vehicles_bought = int(bf.ledger.vehicles_bought) + 1
		if sim.detail:
			sim.detail.create_missing_proxies()
		stats.vehicles_acquired += 1
		lsim._event(s.faction, "%s is ready at %s" % [u.unit_name, lsim.store_name(s)])
		return true
	return false


# --- Optional automation ------------------------------------------------------------------------------

## Keeps `target` depot's `item` above `below` by sending `vehicle` to fetch `qty` from `source`.
func add_rule_restock(target: int, source: int, item: StringName, below: float, qty: float, vehicle: int) -> Dictionary:
	var lg := sim.state.logistics
	var r := {"id": lg.next_rule_id, "kind": "restock", "target": target, "source": source, "item": String(item), "below": below, "qty": qty,
		"vehicle": vehicle, "enabled": true, "pause_until": 0.0, "last": "waiting", "runs": 0}
	lg.next_rule_id += 1
	lg.rules.append(r)
	return r


## Refuels `vehicle` at `depot` whenever it is idle with less than `below_frac` of a tank.
func add_rule_refuel(vehicle: int, depot: int, below_frac := 0.3) -> Dictionary:
	var lg := sim.state.logistics
	var r := {"id": lg.next_rule_id, "kind": "refuel", "vehicle": vehicle, "depot": depot, "below": below_frac,
		"enabled": true, "pause_until": 0.0, "last": "waiting", "runs": 0}
	lg.next_rule_id += 1
	lg.rules.append(r)
	return r


func set_rule_enabled(id: int, on: bool) -> void:
	for r: Dictionary in sim.state.logistics.rules:
		if r.id == id:
			r["enabled"] = on
			r["last"] = "waiting" if on else "disabled by the player"


func remove_rule(id: int) -> void:
	var rules := sim.state.logistics.rules
	for i in rules.size():
		if rules[i].id == id:
			rules.remove_at(i)
			return


## The player gave a vehicle an order of their own: its rules step aside for a while.
func on_manual_order(vehicle_id: int) -> void:
	for r: Dictionary in sim.state.logistics.rules:
		if int(r.get("vehicle", -1)) == vehicle_id:
			r["pause_until"] = sim.state.time + 180.0
			r["last"] = "paused: the player gave the vehicle an order"


func describe_rule(r: Dictionary) -> String:
	var u := sim.state.get_unit(int(r.vehicle))
	var vn := u.unit_name if u else "?"
	var on := "on" if r.enabled else "OFF"
	if r.kind == "restock":
		var t := lsim.structure(int(r.target))
		var s := lsim.structure(int(r.source))
		return "[%s] %s keeps %s above %d at %s from %s (%s) - %s" % [on, vn, Inventory.NAMES[StringName(r.item)], roundi(r.below), lsim.store_name(t) if t else "?", lsim.store_name(s) if s else "?", "%d deliveries" % int(r.runs), r.last]
	var d := lsim.structure(int(r.depot))
	return "[%s] %s refuels at %s below %d %% fuel (%d times) - %s" % [on, vn, lsim.store_name(d) if d else "?", roundi(float(r.below) * 100.0), int(r.runs), r.last]


func _run_rules() -> void:
	var now := sim.state.time
	for r: Dictionary in sim.state.logistics.rules:
		if not r.enabled or now < float(r.get("pause_until", 0.0)):
			continue
		var u := sim.state.get_unit(int(r.vehicle))
		if u == null or u.veh == null or not u.alive:
			r["last"] = "vehicle lost"
			continue
		# Only an idle vehicle takes a rule job.
		if u.player_controlled or not u.veh.job.is_empty() or u.order != UnitState.Order.NONE or u.veh.phase != VehicleState.Phase.NONE or u.veh.convoy_id >= 0:
			continue
		if r.kind == "restock":
			var t := lsim.structure(int(r.target))
			var s := lsim.structure(int(r.source))
			if t == null or s == null or t.inventory == null:
				r["last"] = "depot missing"
				continue
			var item := StringName(r.item)
			if t.inventory.get_qty(item) >= float(r.below):
				r["last"] = "stock fine (%d)" % roundi(t.inventory.get_qty(item))
				continue
			if s.inventory.get_qty(item) <= 0.0:
				r["last"] = "source is out of %s" % Inventory.NAMES[item]
				continue
			if not u.veh.cargo.is_empty():
				continue
			var res := lsim.order_delivery(u.id, s.id, t.id, item, float(r.qty), false, true)
			r["last"] = "sent %s" % u.unit_name if res.ok else "cannot: %s" % res.reason
			if res.ok:
				r["runs"] = int(r.runs) + 1
				stats.deliveries_by_rule += 1
		elif r.kind == "refuel":
			var d := u.veh.def()
			if u.veh.fuel < d.fuel_capacity * float(r.below):
				var res := lsim.order_refuel(u.id, int(r.depot), true)
				r["last"] = "refuelling" if res.ok else "cannot: %s" % res.reason
				if res.ok:
					r["runs"] = int(r.runs) + 1

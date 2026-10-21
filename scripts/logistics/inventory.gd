## The one supply inventory (LOGISTICS-01): depots, vehicle cargo and anything else that
## holds supplies is an Inventory, and quantities only ever move between two of them through
## `Inventory.transfer`, which takes from one and adds to the other in a single step (so a
## transfer can neither duplicate nor lose supplies).
##
## Three supply types with a gameplay purpose:
##   ammo      combat ammunition in kg (soldiers' spare rounds: AMMO_ROUNDS_PER_KG)
##   fuel      vehicle fuel in litres (vehicles' tanks)
##   supplies  general stores in kg (recruiting, vehicles, repairs)
## Capacity is one number for the whole inventory (kg / litres together); `allowed` limits
## what a store accepts (a fuel point holds fuel only).
class_name Inventory
extends RefCounted

const AMMO := &"ammo"
const FUEL := &"fuel"
const SUPPLIES := &"supplies"
const ITEMS: Array[StringName] = [AMMO, FUEL, SUPPLIES]
const NAMES := {&"ammo": "ammunition", &"fuel": "fuel", &"supplies": "supplies"}
const UNITS := {&"ammo": "kg", &"fuel": "l", &"supplies": "kg"}
## Spare rounds one kilogram of the ammunition supply type stands for.
const AMMO_ROUNDS_PER_KG := 5.0

var items := {AMMO: 0.0, FUEL: 0.0, SUPPLIES: 0.0}
var capacity := INF
## Item types the store accepts (empty = all).
var allowed: Array[StringName] = []


static func make(p_capacity: float, p_allowed: Array[StringName] = []) -> Inventory:
	var inv := Inventory.new()
	inv.capacity = p_capacity
	inv.allowed = p_allowed
	return inv


func get_qty(item: StringName) -> float:
	return items.get(item, 0.0)


func total() -> float:
	var t := 0.0
	for k in items:
		t += items[k]
	return t


func free_space() -> float:
	return maxf(capacity - total(), 0.0) if is_finite(capacity) else INF


func accepts(item: StringName) -> bool:
	return allowed.is_empty() or allowed.has(item)


## Quantity that could be added right now.
func room_for(item: StringName) -> float:
	return free_space() if accepts(item) else 0.0


func add(item: StringName, qty: float) -> float:
	var q := minf(maxf(qty, 0.0), room_for(item))
	items[item] = get_qty(item) + q
	return q


func take(item: StringName, qty: float) -> float:
	var q := minf(maxf(qty, 0.0), get_qty(item))
	items[item] = get_qty(item) - q
	return q


## Moves up to `qty` of `item` from src to dst: as much as src has and dst has room for.
## Returns the quantity actually moved.
static func transfer(src: Inventory, dst: Inventory, item: StringName, qty: float) -> float:
	if src == null or dst == null or src == dst:
		return 0.0
	var q := minf(minf(qty, src.get_qty(item)), dst.room_for(item))
	if q <= 0.0:
		return 0.0
	src.items[item] = src.get_qty(item) - q
	dst.items[item] = dst.get_qty(item) + q
	return q


func is_empty() -> bool:
	return total() <= 0.001


## "ammunition 120 kg, fuel 400 l" (non-empty types) or "empty".
func summary() -> String:
	var parts: Array[String] = []
	for k in ITEMS:
		if get_qty(k) > 0.5:
			parts.append("%s %d %s" % [NAMES[k], roundi(get_qty(k)), UNITS[k]])
	return ", ".join(parts) if not parts.is_empty() else "empty"


func to_dict() -> Dictionary:
	var al := []
	for a in allowed:
		al.append(String(a))
	return {"items": {"ammo": snappedf(get_qty(AMMO), 0.001), "fuel": snappedf(get_qty(FUEL), 0.001), "supplies": snappedf(get_qty(SUPPLIES), 0.001)},
		"cap": capacity if is_finite(capacity) else -1.0, "allowed": al}


static func from_dict(d: Dictionary) -> Inventory:
	var inv := Inventory.new()
	inv.copy_from(d)
	return inv


func copy_from(d: Dictionary) -> void:
	var it: Dictionary = d.get("items", {})
	items = {AMMO: float(it.get("ammo", 0.0)), FUEL: float(it.get("fuel", 0.0)), SUPPLIES: float(it.get("supplies", 0.0))}
	var c: float = float(d.get("cap", -1.0))
	capacity = c if c >= 0.0 else INF
	allowed = []
	for a in d.get("allowed", []):
		allowed.append(StringName(a))

## The strategic layer of WorldState (WORLD-SANDBOX-01): factions, strategic objectives,
## operations and the war log. Plain data, saved and loaded with the units and squads, so
## the war resumes exactly where it was. WarSim is the only code that changes it.
class_name WarState
extends RefCounted

## False in the old test layouts (no war); true in the sandbox.
var active := false
var player_faction := 0
## id -> FactionState / ObjectiveState / OperationState
var factions := {}
var objectives := {}
var operations := {}
var next_op_id := 1
## War log: {t, faction (-1 = everyone), kind, text}. Most recent last, at most MAX_LOG.
var events: Array = []
const MAX_LOG := 200
## AI-INTEL-01: each faction's picture of the enemy. faction id -> {contact id: ContactState}.
## Beliefs, not world state: they only change through IntelSim (reports and ageing).
var contacts := {}
var next_contact_id := 1
## Reports on their way to the faction (observed, not yet received): IntelSim.
var intel_pending: Array = []
## AI-WAR-LOGISTICS-01: supply missions of the AI factions (a truck takes supplies from a depot to a squad, an
## operation or another depot): dictionaries, see WarLogistics. Saved with the war.
var missions: Array = []
var next_mission_id := 1
## AI-WAR-LOGISTICS-01: buildings ordered by AI factions that are still under construction (AiBases).
var builds: Array = []
## AI-WAR-LOGISTICS-01: objective id -> time before which no new counterattack is launched there (after one ended).
var counter_cool := {}
## GAMEPLAY-01B: the scenario this war was created from (ScenarioDef id; Continue restarts it before loading) and its
## economy / progression rules (a copy of ScenarioDef.rules, saved, so a loaded game keeps the rules it began with).
var scenario_id := "dev"
var rules := {}
## GAMEPLAY-01B supply caches: {id, name, pos, radius, supplies, ammo, state ("intact" / "securing" / "depleted"),
## faction (who is securing it), progress 0..1, known (faction ids that know where it is), taken_by, taken_at}.
var caches: Array = []
## GAMEPLAY-01B: early-game hints already completed or dismissed by the player (hint id -> true).
var guide := {}


## A rule of the scenario (WarState.rules), or `fallback` when the war has none (old saves, test layouts).
func rule(key: String, fallback: Variant = false) -> Variant:
	return rules.get(key, fallback)


func faction(id: int) -> FactionState:
	return factions.get(id)


func objective(id: int) -> ObjectiveState:
	return objectives.get(id)


func operation(id: int) -> OperationState:
	return operations.get(id)


func all_objectives() -> Array:
	var out := objectives.values()
	out.sort_custom(func(a: ObjectiveState, b: ObjectiveState) -> bool: return a.id < b.id)
	return out


func active_operations(faction_id := -1) -> Array:
	var out := []
	for o: OperationState in operations.values():
		if o.is_active() and (faction_id < 0 or o.faction == faction_id):
			out.append(o)
	out.sort_custom(func(a: OperationState, b: OperationState) -> bool: return a.id < b.id)
	return out


func owned_by(faction_id: int) -> Array:
	return all_objectives().filter(func(o: ObjectiveState) -> bool: return o.owner == faction_id)


func to_dict() -> Dictionary:
	var f := []
	for x: FactionState in factions.values():
		f.append(x.to_dict())
	var o := []
	for x: ObjectiveState in all_objectives():
		o.append(x.to_dict())
	var p := []
	for x: OperationState in operations.values():
		p.append(x.to_dict())
	var cl := []
	for tbl: Dictionary in contacts.values():
		for c: ContactState in tbl.values():
			cl.append(c.to_dict())
	return {"active": active, "player_faction": player_faction, "factions": f, "objectives": o, "operations": p,
		"next_op_id": next_op_id, "log": events.duplicate(true), "contacts": cl, "next_contact": next_contact_id,
		"intel_pending": intel_pending.duplicate(true), "missions": missions.duplicate(true), "next_mission": next_mission_id, "builds": builds.duplicate(true), "counter_cool": counter_cool.duplicate(),
		"scenario": scenario_id, "rules": rules.duplicate(true), "caches": caches.duplicate(true), "guide": guide.duplicate()}


func from_dict(d: Dictionary) -> void:
	active = d.get("active", false)
	player_faction = d.get("player_faction", 0)
	factions.clear()
	objectives.clear()
	operations.clear()
	for x in d.get("factions", []):
		var fs := FactionState.from_dict(x)
		factions[fs.id] = fs
	for x in d.get("objectives", []):
		var os := ObjectiveState.from_dict(x)
		objectives[os.id] = os
	for x in d.get("operations", []):
		var op := OperationState.from_dict(x)
		operations[op.id] = op
	next_op_id = d.get("next_op_id", 1)
	events = d.get("log", []).duplicate(true)
	contacts.clear()
	for x in d.get("contacts", []):
		var c := ContactState.from_dict(x)
		if not contacts.has(c.faction):
			contacts[c.faction] = {}
		contacts[c.faction][c.id] = c
	next_contact_id = d.get("next_contact", 1)
	intel_pending = d.get("intel_pending", []).duplicate(true)
	missions = d.get("missions", []).duplicate(true)
	next_mission_id = d.get("next_mission", 1)
	builds = d.get("builds", []).duplicate(true)
	counter_cool = d.get("counter_cool", {}).duplicate()
	scenario_id = String(d.get("scenario", "dev"))
	rules = d.get("rules", {}).duplicate(true)
	caches = d.get("caches", []).duplicate(true)
	guide = d.get("guide", {}).duplicate()

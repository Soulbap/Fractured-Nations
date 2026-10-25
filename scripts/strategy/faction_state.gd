## One of the three warring factions (WORLD-SANDBOX-01): identity, strategic profile,
## finite reserves and war statistics. Plain data inside WarState (saved with the world).
## Soldiers and squads stay in WorldState.units / squads with their `faction` index.
class_name FactionState
extends RefCounted

var id := 0
var faction_name := ""
## True for the faction the player commands (no strategic AI, every order is the player's).
var player := false
## FactionProfile id (assets/strategy/<id>.tres) the strategic AI reads.
var profile_id: StringName = &""
## Objective that is the faction's headquarters: reserves arrive there.
var hq_objective := -1
## Soldiers still available as replacements (finite); arrive as new squads at the HQ.
var reserves := 0
var reserves_start := 0
var next_reinforcement_at := 0.0
## No new offensive before this time (after a failed attack: recovery).
var recovery_until := 0.0
var next_decision_at := 0.0
var squad_counter := 0
## War statistics.
var casualties := 0
var kills := 0
var objectives_captured := 0
var objectives_lost := 0
var ops_started := 0
var ops_succeeded := 0
var ops_failed := 0
## Last strategic decision (debug / map).
var last_decision := ""
## AI-COMBAT-STRAT-01: strategic focus - what the faction committed to (defence / attack), on which
## objective, until when; keeps it from changing its mind at every decision (saved).
var focus_kind := ""
var focus_objective := -1
var focus_since := 0.0
var focus_until := 0.0
var focus_utility := 0.0
var focus_why := ""
## AI-INTEL-01: the last strategic decisions with what they were based on (runtime, newest
## last, at most WarSim.DECISIONS_MAX).
var decisions: Array = []
## AI-WAR-LOGISTICS-01: what the economy took in from explicit sources and spent (saved; WarEconomy), the
## last economic decision in words (runtime), and when the next economic / logistic decisions are due.
var ledger := {"in": {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}, "manpower": 0, "squads_recruited": 0, "vehicles_bought": 0,
	"lost_with_bases": {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}}
var econ_note := ""
var econ_next_at := 0.0
var supply_next_at := 0.0
var econ_actions: Array = []
## GAMEPLAY-01B: the faction's stock that has no building yet (New Game before the first supply depot): an
## Inventory without capacity limit. Filled only by explicit sources (scenario start, caches, income while there
## is no depot) and refunds; paid from by BaseSim.faction_pay; emptied into the first supply depot with
## Inventory.transfer (BaseSim._settle_pool), so nothing is created or lost on the way.
var pool := Inventory.make(INF)
## GAMEPLAY-01B recovery after the loss of every soldier: when the replacement section arrives (-1: none due), how
## many came so far, and where the faction's soldiers started (the arrival point while it has no base).
var recovery_at := -1.0
## GAMEPLAY-01E: no new AI base expansion before this time (cooldown after one began).
var expand_next_at := 0.0
var recoveries := 0
var home := Vector3.INF
## GAMEPLAY-04B Military Development (MilitaryDevelopment): {"done": [ids], "active": [{id, progress, paid, started, why}]}.
var dev := {}
## GAMEPLAY-04D: weapons the faction holds in store, not carried by anyone (WeaponDef id -> count). A soldier re-equipped
## at a base hands his old weapon in here and draws the new one from here before anything is bought (SquadEquipment).
var armory := {}
## GAMEPLAY-04D: weapon types the faction has registered (a recovered weapon delivered to a base with a supply depot); a
## weapon with WeaponDef.needs_discovery cannot be procured or developed before (MilitaryDevelopment.weapon_lock).
var discovered: Array = []


func to_dict() -> Dictionary:
	return {"id": id, "name": faction_name, "player": player, "profile": profile_id, "hq": hq_objective,
		"reserves": reserves, "reserves_start": reserves_start, "next_reinf": next_reinforcement_at,
		"recovery_until": recovery_until, "next_decision": next_decision_at, "squad_counter": squad_counter,
		"casualties": casualties, "kills": kills, "captured": objectives_captured, "lost": objectives_lost,
		"ops_started": ops_started, "ops_succeeded": ops_succeeded, "ops_failed": ops_failed, "last_decision": last_decision,
		"focus": [focus_kind, focus_objective, focus_since, focus_until, focus_utility, focus_why],
		"ledger": ledger.duplicate(true), "econ_next": econ_next_at, "supply_next": supply_next_at,
		"pool": pool.to_dict(), "recovery_at": recovery_at, "expand_next": expand_next_at, "recoveries": recoveries, "home": home,
		"dev": dev.duplicate(true), "armory": armory.duplicate(), "discovered": discovered.duplicate()}


static func from_dict(d: Dictionary) -> FactionState:
	var f := FactionState.new()
	f.id = d.get("id", 0)
	f.faction_name = d.get("name", "")
	f.player = d.get("player", false)
	f.profile_id = StringName(d.get("profile", ""))
	f.hq_objective = d.get("hq", -1)
	f.reserves = d.get("reserves", 0)
	f.reserves_start = d.get("reserves_start", 0)
	f.next_reinforcement_at = d.get("next_reinf", 0.0)
	f.recovery_until = d.get("recovery_until", 0.0)
	f.next_decision_at = d.get("next_decision", 0.0)
	f.squad_counter = d.get("squad_counter", 0)
	f.casualties = d.get("casualties", 0)
	f.kills = d.get("kills", 0)
	f.objectives_captured = d.get("captured", 0)
	f.objectives_lost = d.get("lost", 0)
	f.ops_started = d.get("ops_started", 0)
	f.ops_succeeded = d.get("ops_succeeded", 0)
	f.ops_failed = d.get("ops_failed", 0)
	f.last_decision = d.get("last_decision", "")
	var fc: Array = d.get("focus", ["", -1, 0.0, 0.0, 0.0, ""])
	f.focus_kind = fc[0]
	f.focus_objective = fc[1]
	f.focus_since = fc[2]
	f.focus_until = fc[3]
	f.focus_utility = fc[4]
	f.focus_why = fc[5]
	if d.has("ledger"):
		f.ledger = d.ledger.duplicate(true)
	f.econ_next_at = d.get("econ_next", 0.0)
	f.supply_next_at = d.get("supply_next", 0.0)
	if d.get("pool") is Dictionary:
		f.pool = Inventory.from_dict(d.pool)
	f.recovery_at = d.get("recovery_at", -1.0)
	f.expand_next_at = d.get("expand_next", 0.0)
	f.recoveries = d.get("recoveries", 0)
	f.home = d.get("home", Vector3.INF)
	f.dev = d.get("dev", {}).duplicate(true)
	f.armory = d.get("armory", {}).duplicate()
	f.discovered = d.get("discovered", []).duplicate()
	return f

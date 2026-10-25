## GAMEPLAY-04A: the New Game opening as a few phases read from the world (owned by WarSim: `WarSim.intro`). Nothing is
## scripted or spawned here: the phases come from the scenario (ScenarioDef.intro, copied into WarState.guide at creation
## so a save keeps them) and each one is complete when its condition holds in the world, whatever order the player does
## things in. The tracker shows the first phase not complete; finished phases are announced once. Hiding the guide (the
## tracker's x) changes nothing in the world.
##
## WarState.guide keys: "intro" [phase dicts], "briefing", "intro_done" [phase ids], "intro_complete_at", "off" (hidden),
## and the UI's own marks "fps", "map", "dev_opened".
##
## Conditions ("done"): "moved:<m>" a player squad is that far from where the faction started; "clear:<objective>" no
## enemy soldier within the objective's radius + 40 m (or the player owns it); "owned:<objective>"; "cache:<name>" the
## player secured that cache; "base" the player has a base; "dev_started" a development project begun or finished;
## "fps" / "map" the player used first person / the map; "rearmed" a player squad finished a REARM.
class_name IntroGuide
extends RefCounted

var ws: WarSim
var _t := 0.0


func _init(p_ws: WarSim) -> void:
	ws = p_ws


## Copies the scenario's introduction into the war (SandboxSetup).
static func setup(war: WarState, scenario: ScenarioDef) -> void:
	if scenario.intro.is_empty():
		return
	war.guide["intro"] = scenario.intro.duplicate(true)
	war.guide["briefing"] = scenario.briefing
	war.guide["intro_done"] = []


func phases() -> Array:
	return ws.war.guide.get("intro", [])


func done_ids() -> Array:
	if not ws.war.guide.has("intro_done"):
		ws.war.guide["intro_done"] = []
	return ws.war.guide["intro_done"]


func active() -> bool:
	return not phases().is_empty()


## True once every non-optional phase is done.
func complete() -> bool:
	return active() and ws.war.guide.has("intro_complete_at")


## The first phase that is not done (skipping optional tips), or {} when the introduction is over.
func current() -> Dictionary:
	for p: Dictionary in phases():
		if not bool(p.get("optional", false)) and not done_ids().has(String(p.id)):
			return p
	return {}


func is_done(p: Dictionary) -> bool:
	return done_ids().has(String(p.id))


func update(dt: float) -> void:
	if not active() or complete():
		return
	_t += dt
	if _t < 1.0:
		return
	_t = 0.0
	var all := true
	for p: Dictionary in phases():
		if is_done(p):
			continue
		if met(String(p.get("done", ""))):
			done_ids().append(String(p.id))
			if not bool(p.get("optional", false)):
				ws.log_event(ws.war.player_faction, "objective_done", "Objective complete: %s" % p.title)
		elif not bool(p.get("optional", false)):
			all = false
	if all:
		ws.war.guide["intro_complete_at"] = snappedf(ws.sim.state.time, 0.1)
		ws.log_event(ws.war.player_faction, "objective_done", "Foothold established. The region is yours to fight for: capture ground, take up opportunities, expand.")


## Where a phase points (its target), or Vector3.INF.
func target_pos(p: Dictionary) -> Vector3:
	var t := String(p.get("target", ""))
	if t.begins_with("objective:"):
		var o := _objective(t.substr(10))
		return o.position if o else Vector3.INF
	if t.begins_with("cache:"):
		for c: Dictionary in ws.war.caches:
			if String(c.name) == t.substr(6):
				return c.pos
	return Vector3.INF


func _objective(oname: String) -> ObjectiveState:
	for o: ObjectiveState in ws.war.objectives.values():
		if o.obj_name == oname:
			return o
	return null


## Whether a condition holds in the world now.
func met(cond: String) -> bool:
	var pf := ws.war.player_faction
	var f := ws.war.faction(pf)
	var key := cond.get_slice(":", 0)
	var arg := cond.substr(key.length() + 1) if cond.contains(":") else ""
	match key:
		"moved":
			if f == null or not f.home.is_finite():
				return false
			for sq: SquadState in ws.squads_of(pf):
				if WarSim._flat(ws.squad_center(sq), f.home) >= float(arg):
					return true
			return false
		"clear":
			var o := _objective(arg)
			if o == null:
				return false
			if o.owner == pf:
				return true
			ws.sim.brain._ensure_grid()
			for u: UnitState in ws.sim.brain._near(o.position, o.radius + 40.0):
				if u.alive and u.faction != pf and u.kind == UnitState.Kind.SOLDIER:
					return false
			return true
		"owned":
			var o := _objective(arg)
			return o != null and o.owner == pf
		"cache":
			for c: Dictionary in ws.war.caches:
				if String(c.name) == arg:
					return int(c.get("taken_by", -1)) == pf
			return false
		"base":
			return not ws.sim.logistics.bases.bases_of(pf).is_empty()
		"dev_started":
			if not ws.dev.enabled():
				return true
			if not ws.dev.active_of(pf).is_empty():
				return true
			for id in f.dev.get("done", []):
				var d := DevelopmentDef.by_id(StringName(id))
				if d and not d.initial:
					return true
			return false
		"fps", "map", "rearmed":
			return bool(ws.war.guide.get(key, false))
	return false

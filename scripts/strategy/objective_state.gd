## A strategic control point (WORLD-SANDBOX-01): a real place in the world (base site,
## town, bridge, junction) with an owner and a capture state. Plain data inside WarState.
##
## Capture (WarSim): only soldiers inside `radius` count. One faction present alone (at
## least WarSim.capture_min soldiers) that does not own it raises its capture progress;
## two or more factions present make it contested (progress frozen); the owner alone
## present drains an attacker's progress. Progress 1.0 transfers ownership. Defenders
## therefore have to be killed or driven out before a point changes hands.
class_name ObjectiveState
extends RefCounted

var id := 0
var obj_name := ""
## &"hq", &"town", &"village", &"bridge", &"junction"
var kind: StringName = &"village"
var position := Vector3.ZERO
var radius := 150.0
## Strategic value 1..3 (AI priorities, map symbol size).
var value := 1
## Owning faction, -1 = nobody.
var owner := -1
## Faction building up capture progress (-1 none) and its progress 0..1.
var capture_faction := -1
var capture_progress := 0.0
var contested := false
var last_change_at := -1.0e9
## [[time, owner], ...] ownership changes (most recent last, at most 20).
var history: Array = []
## Soldiers present per faction at the last capture update (runtime and map display).
var presence := {}
## GAMEPLAY-01D: kind &"base" - the strategic target of one base (ConstructionState.bases id). Created and kept in step
## with the base by WarSim.sync_bases; its owner is the base's ownership (captured like any objective).
var base_id := -1
## GAMEPLAY-04A: squads its owner keeps stationed here whatever its profile says (a scenario outpost such as New Game's
## checkpoint: WarSim._free_squads never sends them away).
var hold := 0


func to_dict() -> Dictionary:
	return {"id": id, "name": obj_name, "kind": kind, "position": position, "radius": radius, "value": value,
		"owner": owner, "capture_faction": capture_faction, "capture_progress": capture_progress,
		"contested": contested, "last_change_at": last_change_at, "history": history.duplicate(true), "presence": presence.duplicate(),
		"base_id": base_id, "hold": hold}


static func from_dict(d: Dictionary) -> ObjectiveState:
	var o := ObjectiveState.new()
	o.id = d.get("id", 0)
	o.obj_name = d.get("name", "")
	o.kind = StringName(d.get("kind", "village"))
	o.position = d.get("position", Vector3.ZERO)
	o.radius = d.get("radius", 150.0)
	o.value = d.get("value", 1)
	o.owner = d.get("owner", -1)
	o.capture_faction = d.get("capture_faction", -1)
	o.capture_progress = d.get("capture_progress", 0.0)
	o.contested = d.get("contested", false)
	o.last_change_at = d.get("last_change_at", -1.0e9)
	o.history = d.get("history", []).duplicate(true)
	o.presence = d.get("presence", {}).duplicate()
	o.base_id = d.get("base_id", -1)
	o.hold = d.get("hold", 0)
	return o


func is_base() -> bool:
	return kind == &"base"


func is_hq() -> bool:
	return kind == &"hq"

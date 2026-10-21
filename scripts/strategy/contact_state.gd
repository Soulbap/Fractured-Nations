## One item of a faction's battlefield picture (AI-INTEL-01): what the faction believes about
## an enemy group, built only from reports (a soldier saw it, heard it, took fire from it, or
## the faction's own soldiers hold an objective the enemy stands in). It is a belief, not a
## copy of the enemy: `pos` is where the enemy was last reported and is never updated from
## the world while nobody observes it; confidence falls and the uncertainty circle grows with
## the time since the last evidence. Plain data inside WarState (saved with the world).
class_name ContactState
extends RefCounted

enum Kind { UNKNOWN, INFANTRY, VEHICLE }
## How the last evidence arrived. SEEN is the best; a lesser source never overwrites a fresh
## better one.
enum Source { SEEN, FIRE, HEARD, OBJECTIVE }
## OBSERVED: seen very recently. REPORTED: believed, not currently watched. STALE: old, low
## confidence (still counted at its confidence). LOST: dropped from the table.
enum Status { OBSERVED, REPORTED, STALE, LOST }

const KIND_NAMES: Array[String] = ["unknown", "infantry", "vehicle"]
const SOURCE_NAMES: Array[String] = ["seen", "took fire", "heard", "held ground"]
const STATUS_NAMES: Array[String] = ["observed", "reported", "stale", "lost"]
## Evidence value, best first.
const SOURCE_RANK: Array[int] = [3, 2, 0, 1]
const MAX_IDS := 12

var id := 0
## The faction that holds this belief.
var faction := 0
## Which enemy faction it is believed to be (-1: not identified, e.g. heard gunfire).
var enemy_faction := -1
var kind := Kind.UNKNOWN
var source := Source.SEEN
var status := Status.REPORTED
## Last reported position (centre of the believed group).
var pos := Vector3.ZERO
## Time of the last evidence (when it was observed) and when the faction received it.
var t_seen := 0.0
var t_report := 0.0
var t_first := 0.0
## Confidence and uncertainty radius (m) at the last evidence, and now (recomputed by the sweep).
var conf0 := 1.0
var unc0 := 10.0
var conf := 1.0
var unc := 10.0
## Estimated enemy soldiers in the group.
var strength := 1
## Enemy unit ids reported as part of this contact (at most MAX_IDS, with the time each was
## last reported). Only a means of telling groups apart and counting; positions are not kept.
var ids := PackedInt32Array()
var ids_t := PackedFloat32Array()
## No second investigation before this time.
var investigated_until := 0.0
## Number of reports merged into it.
var reports := 1


func to_dict() -> Dictionary:
	return {"id": id, "f": faction, "ef": enemy_faction, "kind": kind, "src": source, "status": status, "pos": pos,
		"t_seen": t_seen, "t_report": t_report, "t_first": t_first, "conf0": conf0, "unc0": unc0, "conf": conf, "unc": unc,
		"strength": strength, "ids": Array(ids), "ids_t": Array(ids_t), "inv": investigated_until, "reports": reports}


static func from_dict(d: Dictionary) -> ContactState:
	var c := ContactState.new()
	c.id = d.get("id", 0)
	c.faction = d.get("f", 0)
	c.enemy_faction = d.get("ef", -1)
	c.kind = d.get("kind", Kind.UNKNOWN)
	c.source = d.get("src", Source.SEEN)
	c.status = d.get("status", Status.REPORTED)
	c.pos = d.get("pos", Vector3.ZERO)
	c.t_seen = d.get("t_seen", 0.0)
	c.t_report = d.get("t_report", 0.0)
	c.t_first = d.get("t_first", 0.0)
	c.conf0 = d.get("conf0", 1.0)
	c.unc0 = d.get("unc0", 10.0)
	c.conf = d.get("conf", 1.0)
	c.unc = d.get("unc", 10.0)
	c.strength = d.get("strength", 1)
	c.ids = PackedInt32Array(d.get("ids", []))
	c.ids_t = PackedFloat32Array(d.get("ids_t", []))
	c.investigated_until = d.get("inv", 0.0)
	c.reports = d.get("reports", 1)
	return c


func kind_name() -> String:
	return KIND_NAMES[kind]


func source_name() -> String:
	return SOURCE_NAMES[source]


func status_name() -> String:
	return STATUS_NAMES[status]


## One line for the map and the inspector.
func describe(now: float) -> String:
	var who := WorldState.faction_name(enemy_faction) + " " if enemy_faction >= 0 else ""
	return "#%d %s%s ~%d · %s · conf %d%% ±%d m · %ds ago · %s" % [id, who, kind_name(), strength, status_name(), roundi(conf * 100.0), roundi(unc), roundi(now - t_seen), source_name()]

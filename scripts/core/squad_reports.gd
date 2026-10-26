## QOL-01 squad notices: what the player should hear about their squads, as war events the HUD toasts and the map list
## show - each one carries the squad (a click selects it and frames the camera on it).
##
## Not a second state: once a second it compares each squad of the player's side with what it was (SquadControl.
## describe_order, the squad's assessment, its fallen) and reports the changes that need attention - under attack after a
## quiet spell, casualties (gathered for a few seconds), arrived, blocked / march stopped; SquadTactics.notice adds the
## tactical ones (move interrupted, resumed, broken off, pressing on). Each kind of each squad at most once per
## REPEAT_S, so a long fight is one line, not a stream. Texts name the squad and where it is, never an enemy position
## the squad does not know (the believed threat is the squad's own assessment, and the text does not place it).
## Runtime only: after a load the first pass takes the current state as known, without notices.
class_name SquadReports
extends RefCounted

const INTERVAL_S := 1.0
## A squad that has been quiet this long is "under attack" again when fired on.
const QUIET_S := 45.0
## Casualties within this window are reported together.
const CASUALTY_GATHER_S := 5.0
const REPEAT_S := 25.0

var sim: WorldSim
var enabled := true
## Every notice made (tests, and outside the war where there is no war log): {t, squad, kind, text}.
var log: Array = []
var counts := {}
## Cost of the passes (us), for the performance check.
var usec := 0
var usec_max := 0
var passes := 0
var _t := 0.0
## squad id -> {state, fallen, fire_at, pending_cas, cas_at, sent: {kind: t}}
var _last := {}


func _init(p_sim: WorldSim) -> void:
	sim = p_sim


func connect_signals() -> void:
	sim.tactics.notice.connect(_on_tactic_notice)
	sim.state.restored.connect(func() -> void: _last.clear())


func update(delta: float) -> void:
	if not enabled:
		return
	_t += delta
	if _t < INTERVAL_S:
		return
	_t = 0.0
	var t0 := Time.get_ticks_usec()
	_pass()
	var dt := Time.get_ticks_usec() - t0
	usec += dt
	usec_max = maxi(usec_max, dt)
	passes += 1


func _pass() -> void:
	var now := sim.state.time
	var alive := {}
	for sq: SquadState in sim.state.all_squads():
		if sq.members.is_empty() or not _mine(sq):
			continue
		alive[sq.id] = true
		var a := sim.tactics.assessment(sq)
		var d := sim.squads.describe_order(sq)
		var st: Dictionary = _last.get(sq.id, {})
		if st.is_empty():
			_last[sq.id] = {"state": d.state, "fallen": sq.fallen.size(), "fire_at": now if int(a.get("under_fire", 0)) > 0 else -1000.0,
				"pending_cas": 0, "cas_at": 0.0, "sent": {}}
			continue
		# Under attack after a quiet spell.
		if int(a.get("under_fire", 0)) > 0:
			if now - float(st.fire_at) > QUIET_S:
				_send(sq, "under_attack", "%s is under fire%s" % [sq.squad_name, _where(sq)], st, now)
			st.fire_at = now
		# Casualties, gathered.
		var fallen := sq.fallen.size()
		if fallen > int(st.fallen):
			if int(st.pending_cas) == 0:
				st.cas_at = now
			st.pending_cas = int(st.pending_cas) + fallen - int(st.fallen)
		st.fallen = fallen
		if int(st.pending_cas) > 0 and now - float(st.cas_at) >= CASUALTY_GATHER_S:
			var sn := SquadPanel.strength(sq)
			_send(sq, "casualties", "%s: %d casualt%s, %d/%d left" % [sq.squad_name, st.pending_cas, "y" if int(st.pending_cas) == 1 else "ies", sn.x, sn.y], st, now, true)
			st.pending_cas = 0
		# Order state changes that need the player.
		var prev: String = st.state
		if d.state != prev:
			match String(d.state):
				"arrived":
					if prev == "moving" and sq.op_id < 0:
						_send(sq, "arrived", "%s reached its destination" % sq.squad_name, st, now)
				"blocked":
					_send(sq, "blocked", "%s: %s" % [sq.squad_name, d.text], st, now)
				"route_blocked":
					_send(sq, "blocked", "%s: %s" % [sq.squad_name, d.text], st, now)
			st.state = d.state
		_last[sq.id] = st
	for id in _last.keys():
		if not alive.has(id):
			_last.erase(id)


func _on_tactic_notice(sq: SquadState, kind: String, text: String) -> void:
	if not enabled or sq == null or not _mine(sq):
		return
	var st: Dictionary = _last.get(sq.id, {"sent": {}})
	_send(sq, kind, text, st, sim.state.time, kind == "interrupted" or kind == "resumed")
	if _last.has(sq.id):
		_last[sq.id] = st


## The player's side (outside the war: every squad, the log only).
func _mine(sq: SquadState) -> bool:
	var war := sim.state.war
	return not war.active or sq.faction == war.player_faction


func _send(sq: SquadState, kind: String, text: String, st: Dictionary, now: float, always := false) -> void:
	var sent: Dictionary = st.get("sent", {})
	if not always and now - float(sent.get(kind, -1000.0)) < REPEAT_S:
		return
	sent[kind] = now
	st["sent"] = sent
	counts[kind] = int(counts.get(kind, 0)) + 1
	log.append({"t": snappedf(now, 0.1), "squad": sq.id, "kind": kind, "text": text})
	if log.size() > 200:
		log.pop_front()
	if sim.war and sim.war.enabled:
		sim.war.log_event(sq.faction, "squad_" + kind, text, sim.war.squad_center(sq), {"squad": sq.id})


## " near <objective>" when the squad stands within 600 m of one, else "".
func _where(sq: SquadState) -> String:
	if sim.war == null or not sim.war.enabled:
		return ""
	var c := sim.war.squad_center(sq)
	var best := ""
	var best_d := 600.0
	for o: ObjectiveState in sim.state.war.all_objectives():
		var dd := Vector2(c.x - o.position.x, c.z - o.position.z).length()
		if dd < best_d:
			best_d = dd
			best = o.obj_name
	return (" near %s" % best) if best != "" else ""

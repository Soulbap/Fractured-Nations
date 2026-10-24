## The tactical view's selection and command panel (AI-SQUAD-01, UI-01C): one integrated surface at the
## bottom centre, shown only while at least one squad is selected.
##
## Left: the selection - emblem, callsign (or the number of squads), soldiers, what it is doing now,
## health / ammunition / suppression of the living members, formation and rules of engagement.
## Right: the orders that exist in the game, grouped MOVE / COMBAT / DEFENCE / SQUAD, each with its
## icon and hotkey. A tactic button arms the order (the next left click gives its target; Esc or a
## right click cancels); the hotkeys give the same order at the cursor at once. Every button calls the
## RTSController function its key calls, so what the player commands is what the squads do on their
## own. The footer says what is armed, whether the last order was accepted and, if not, why.
class_name TacticalPanel
extends FNPanel

var rts: RTSController
var sim: WorldSim

var _buttons := {}
var _emblem: FNUnitEmblem
var _title: Label
var _subtitle: Label
var _status: FNStatusIndicator
var _health: FNMeter
var _ammo: FNMeter
var _supp: FNMeter
var _settings: Label
var _support_text := ""
var _feedback: FNStatusIndicator
var _timer := 0.0
var _fb_text := ""
var _fb_until := 0.0

## Button keys for the orders that are not tactics.
const HOLD := -2
const FOLLOW := -3
const REGROUP := -4
const FORMATION := -5
const ROE := -6

## [group, key, icon, title, hotkey, tooltip]
const ENTRIES := [
	["MOVE", SquadState.Tactic.BOUND, &"bound", "Bound", "Shift+RMB", "Move by bounds: one fire team covers while the other moves (Shift+right click, or arm and click)"],
	["MOVE", FOLLOW, &"follow", "Follow", "F", "Follow a soldier or squad: click the one to follow"],
	["MOVE", HOLD, &"hold", "Hold", "H", "Stop and hold the current position"],
	["MOVE", REGROUP, &"regroup", "Regroup", "G", "Reassemble on the leader (waits for calm); Shift+G at the cursor"],
	["COMBAT", SquadState.Tactic.ASSAULT, &"assault", "Assault", "Z", "Attack the position: one fire team suppresses while the other advances, then the squad occupies it"],
	["COMBAT", SquadState.Tactic.SUPPRESS, &"suppress", "Suppress", "K", "Pin a position with fire from a covered post with a line to it"],
	["COMBAT", SquadState.Tactic.FLANK, &"flank", "Flank", "L", "Round the position by a covered route while the other team keeps it pinned"],
	["DEFENCE", SquadState.Tactic.DEFEND, &"defend", "Defend", "J", "Move to the spot (or stay) and hold it from firing posts"],
	["DEFENCE", SquadState.Tactic.WITHDRAW, &"withdraw", "Withdraw", "Bksp", "Break contact towards the spot (or a safe place), one team covering the other (Backspace)"],
	["DEFENCE", RTSController.GARRISON, &"base", "Garrison", "O", "Garrison one of your bases: click it. The squad mans its towers, positions and walls and stays until given another order"],
	["SQUAD", FORMATION, &"formation", "Line", "V", "V: line / column. Shift+V cycles line, column, wedge, staggered, dispersed and auto. [ ] change the spacing"],
	["SQUAD", ROE, &"roe_free", "Fire free", "Y", "Rules of engagement: weapons free / hold fire (a soldier that is hit still defends himself)"],
]
const TACTICS := [SquadState.Tactic.BOUND, SquadState.Tactic.ASSAULT, SquadState.Tactic.SUPPRESS, SquadState.Tactic.FLANK,
	SquadState.Tactic.DEFEND, SquadState.Tactic.WITHDRAW]


func _init() -> void:
	super(Color.TRANSPARENT, FNUI.S4)


func _ready() -> void:
	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", FNUI.S3)
	add_child(outer)
	var main := HBoxContainer.new()
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_theme_constant_override("separation", FNUI.S5)
	outer.add_child(main)
	main.add_child(_build_summary())
	var rule := ColorRect.new()
	rule.color = Color(FNUI.LINE_STRONG, 0.6)
	rule.custom_minimum_size = Vector2(1, 0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(rule)
	main.add_child(_build_commands())
	var foot_rule := ColorRect.new()
	foot_rule.color = Color(FNUI.LINE, 0.9)
	foot_rule.custom_minimum_size = Vector2(0, 1)
	foot_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(foot_rule)
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override("separation", FNUI.S5)
	outer.add_child(foot)
	_feedback = FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_feedback)
	foot.add_child(FNKeyHint.new("RMB", "Move"))
	foot.add_child(FNKeyHint.new("Esc", "Deselect"))
	foot.add_child(FNKeyHint.new("F1", "Controls"))


func _build_summary() -> Control:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.custom_minimum_size = Vector2(184, 0)
	v.add_theme_constant_override("separation", FNUI.S3 - 1)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", FNUI.S3)
	v.add_child(head)
	_emblem = FNUnitEmblem.new(Vector2(32, 22))
	head.add_child(_emblem)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_theme_constant_override("separation", -1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	_title = FNUI.label("", FNUI.HEADLINE, FNUI.INK, "title")
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(_title)
	_subtitle = FNUI.label("", FNUI.CAPTION, FNUI.INK_2, "caps")
	_subtitle.clip_text = true
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(_subtitle)
	_status = FNStatusIndicator.new(FNUI.ICON_M, FNUI.BODY)
	v.add_child(_status)
	_health = FNMeter.new("Health", FNUI.OK)
	_ammo = FNMeter.new("Ammunition", FNUI.INFO)
	_supp = FNMeter.new("Suppression", FNUI.ALERT)
	for m in [_health, _ammo, _supp]:
		v.add_child(m)
	_settings = FNUI.label("", FNUI.CAPTION, FNUI.INK_3, "caps")
	v.add_child(_settings)
	return v


func _build_commands() -> Control:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var groups := HBoxContainer.new()
	groups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	groups.add_theme_constant_override("separation", FNUI.S4 + 2)
	v.add_child(groups)
	var by_name := {}
	for e: Array in ENTRIES:
		if not by_name.has(e[0]):
			by_name[e[0]] = FNCommandGroup.new(e[0])
			groups.add_child(by_name[e[0]])
		var key: int = e[1]
		var b := FNCommandButton.new(e[2], e[3], e[4], e[5])
		b.pressed.connect(_on_button.bind(key))
		by_name[e[0]].add(b)
		_buttons[key] = b
	return v


func _on_button(key: int) -> void:
	match key:
		HOLD:
			rts.order_hold()
		FOLLOW:
			rts.arm_follow()
		REGROUP:
			rts.order_regroup()
		FORMATION:
			rts.toggle_formation()
		ROE:
			rts.toggle_roe()
		_:
			rts.arm_tactic(key)
	_timer = 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or sim == null or rts == null:
		return
	_timer = 0.15
	var sqs := rts.selected_squads()
	if sqs.is_empty():
		return
	var squads: Array[SquadState] = []
	for sid in sqs:
		var sq := sim.state.get_squad(sid)
		if sq:
			squads.append(sq)
	if squads.is_empty():
		return
	_refresh_summary(squads)
	_refresh_buttons(squads)
	_refresh_feedback()
	size = Vector2.ZERO


func _refresh_summary(squads: Array[SquadState]) -> void:
	var first := squads[0]
	var alive := 0
	var total := 0
	var names: Array[String] = []
	for sq in squads:
		alive += maxi(0, sq.members.size() - sq.fallen.size())
		total += sq.members.size()
		names.append(sq.squad_name.to_upper())
	_emblem.color = WorldState.faction_color(first.faction)
	if squads.size() == 1:
		_title.text = first.squad_name.to_upper()
		_subtitle.text = "Infantry squad · %d/%d soldiers" % [alive, total]
	else:
		_title.text = "%d SQUADS" % squads.size()
		_subtitle.text = "%d/%d soldiers · %s" % [alive, total, " ".join(names)]
	# One status for the selection: the shared one, else the most urgent one in contact, else "mixed".
	var st := SquadPanel.squad_status(sim, first)
	for sq in squads.slice(1):
		var other := SquadPanel.squad_status(sim, sq)
		if other.text == st.text:
			continue
		if other.engaged and not st.engaged:
			st = other
		elif not st.engaged:
			st = {"icon": &"tactic", "text": "MIXED ORDERS", "color": FNUI.NEUTRAL, "engaged": false}
	_status.set_status(st.icon, st.text, st.color)
	_emblem.frame_color = st.color if st.engaged else Color.TRANSPARENT
	# Health, ammunition and suppression of the living members.
	var hp := 0.0
	var hp_max := 0.0
	var rounds := 0
	var capacity := 0
	var supp := 0.0
	var n := 0
	# GAMEPLAY-02D: the support weapons the selection carries (machine guns and their rounds, rockets, grenades).
	var mgs := 0
	var mg_rounds := 0
	var mg_cap := 0
	var rockets := 0
	var nades := 0
	for sq in squads:
		for id in sq.members:
			var u := sim.state.get_unit(id)
			if u == null or not u.alive:
				continue
			n += 1
			hp += u.health
			hp_max += u.max_health
			supp += clampf(u.suppression_at(sim.state.time), 0.0, 1.0)
			if u.weapon_id != &"":
				var def := sim.combat.weapon(u.weapon_id)
				if def:
					rounds += u.mag + u.reserve
					capacity += def.magazine_size + def.reserve_start
					if def.role == &"lmg":
						mgs += 1
						mg_rounds += u.mag + u.reserve
						mg_cap += def.magazine_size + def.reserve_start
			rockets += u.sec_ammo if u.sec_id != &"" else 0
			nades += u.grenades
	var h := hp / hp_max if hp_max > 0.0 else 0.0
	_health.set_value(h, "%d%%" % roundi(h * 100.0), FNUI.OK if h >= 0.6 else (FNUI.WARN if h >= 0.3 else FNUI.DANGER))
	_health.critical = h < 0.3
	if capacity > 0:
		var a := clampf(float(rounds) / capacity, 0.0, 1.0)
		_ammo.set_value(a, "%d%%" % roundi(a * 100.0), FNUI.INFO if a >= 0.3 else FNUI.WARN)
	else:
		_ammo.set_value(-1.0, "—")
	var s := supp / maxi(n, 1)
	_supp.set_value(s, "%d%%" % roundi(s * 100.0), FNUI.DANGER if s >= 0.6 else FNUI.ALERT)
	_supp.critical = s >= 0.6
	var form := "Auto" if first.formation_auto else first.formation_name()
	var support: Array[String] = []
	if mgs > 0:
		support.append("MG %d (%d%%)" % [mgs, roundi(100.0 * mg_rounds / maxi(mg_cap, 1))])
	if rockets > 0:
		support.append("rockets %d" % rockets)
	if nades > 0:
		support.append("grenades %d" % nades)
	_support_text = "  ·  ".join(support)
	_settings.text = "Formation %s  ·  %s  ·  spacing %.1f m%s" % [form, first.roe_name(), first.spacing,
		"  ·  in operation" if first.op_id >= 0 else ("  ·  garrison %s" % sim.state.construction.bases[first.garrison_base].name if sim.state.construction.bases.has(first.garrison_base) else "")]
	if _support_text != "":
		_settings.text += "
" + _support_text


func _refresh_buttons(squads: Array[SquadState]) -> void:
	# Tactics need the squad on its feet: a squad with a soldier aboard a vehicle never runs one.
	var can_tactic := false
	for sq in squads:
		var aboard := false
		for id in sq.members:
			var u := sim.state.get_unit(id)
			if u and u.vehicle_id >= 0:
				aboard = true
				break
		if not aboard:
			can_tactic = true
	for key in _buttons:
		var b: FNCommandButton = _buttons[key]
		var is_tactic := TACTICS.has(key)
		if is_tactic:
			b.set_enabled(can_tactic)
		b.armed = (is_tactic and key == rts.armed_tactic) or (key == FOLLOW and rts.follow_pick) or (key == RTSController.GARRISON and rts.armed_tactic == key)
		var now := false
		for sq in squads:
			match key:
				HOLD:
					now = now or (sq.order == SquadState.Order.HOLD and sq.tactic == SquadState.Tactic.NONE)
				FOLLOW:
					now = now or sq.order == SquadState.Order.FOLLOW
				REGROUP:
					now = now or sq.order == SquadState.Order.REGROUP or sq.tactic == SquadState.Tactic.REGROUP
				FORMATION, ROE:
					pass
				RTSController.GARRISON:
					now = now or sq.garrison_base >= 0
				_:
					now = now or sq.tactic == key
		b.current = now
	var first := squads[0]
	var hold_fire := first.roe == SquadState.Roe.HOLD_FIRE
	var roe_b: FNCommandButton = _buttons[ROE]
	roe_b.set_face(&"roe_hold" if hold_fire else &"roe_free", "Hold fire" if hold_fire else "Fire free")
	roe_b.icon_rect.modulate = FNUI.ARMED if hold_fire else FNUI.INK
	var form_b: FNCommandButton = _buttons[FORMATION]
	form_b.set_face(&"formation", "Auto" if first.formation_auto else first.formation_name())


## Footer: an armed order first, then the result of the last order (8 s), then the controller's
## message (3 s), else a quiet reminder.
func _refresh_feedback() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if rts.tactic_feedback != _fb_text:
		_fb_text = rts.tactic_feedback
		_fb_until = now + 8.0
	if rts.armed_tactic >= 0:
		var tname := "Garrison" if rts.armed_tactic == RTSController.GARRISON else SquadState.TACTIC_NAMES[rts.armed_tactic]
		_feedback.set_status(&"tactic", "%s armed — click the target  ·  Esc or right click cancels" % tname, FNUI.ARMED)
	elif rts.follow_pick:
		_feedback.set_status(&"follow", "Follow armed — click the soldier or squad to follow  ·  Esc cancels", FNUI.ARMED)
	elif now < _fb_until and _fb_text != "":
		_feedback.set_status(&"tactic" if rts.tactic_feedback_ok else &"blocked", _fb_text, FNUI.OK if rts.tactic_feedback_ok else FNUI.DANGER)
	elif rts.current_message() != "":
		_feedback.set_status(&"idle", rts.current_message(), FNUI.INK_2)
	else:
		_feedback.set_status(&"moving", "Right click to move  ·  arm an order or use its key at the cursor", FNUI.INK_3)

## The tactical view's selection and command panel (AI-SQUAD-01, UI-01C, QOL-01): one compact surface at the
## bottom right, shown only while at least one squad is selected.
##
## Left: the selection - emblem, callsign (or the number of squads), soldiers, what it is doing now,
## health / ammunition / suppression of the living members, formation and rules of engagement.
## Right: the orders that exist in the game as a grid of icon tiles (hotkey in the corner, name and help in the tooltip),
## one row each for MOVE / COMBAT / SQUAD and the behaviour MODE (QOL-01: one long bar of labelled buttons left the
## panel wide and half empty). A tactic button arms the order (the next left click gives its target; Esc or a
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
## QOL-01: the order line under the status (SquadControl.describe_order) and the BEHAVIOUR group (its aside says when the
## situation makes the squad act in another mode).
var _order: Label
var _mode_note: Label
var _fb_text := ""
var _fb_until := 0.0

## Button keys for the orders that are not tactics.
const HOLD := -2
const FOLLOW := -3
const REGROUP := -4
const FORMATION := -5
const ROE := -6
## GAMEPLAY-04D: open the equipment screen for the selected squad.
const EQUIP := -7
## QOL-01: behaviour mode buttons are BEHAVIOUR - mode (SquadBehaviour SAFE..STEALTH -> -20..-23).
const BEHAVIOUR := -20
## QOL-01: the rows of the command grid, in order.
const ROWS := ["MOVE", "COMBAT", "SQUAD", "MODE"]

## [group, key, icon, title, hotkey, tooltip]
const ENTRIES := [
	["MOVE", SquadState.Tactic.BOUND, &"bound", "Bound", "", "BOUND\nMove in bounds: one fire team covers from where it stands while the other moves, then they swap. Slower than a move, safer near the enemy. Shift+right click on the ground, or arm and click."],
	["MOVE", FOLLOW, &"follow", "Follow", "F", "FOLLOW\nKeep behind a soldier or squad (click the one to follow) until given another order."],
	["MOVE", HOLD, &"hold", "Hold", "H", "HOLD\nStop where the squad stands and stay there; soldiers still return fire and take cover nearby. Cancels the current order or tactic."],
	["MOVE", REGROUP, &"regroup", "Regroup", "G", "REGROUP\nReassemble on the leader once it is calm (Shift+G: at the cursor). Use after a fight has scattered the squad."],
	["COMBAT", SquadState.Tactic.ASSAULT, &"assault", "Assault", "Z", "ASSAULT\nMove toward the target using coordinated fire and movement: one fire team suppresses while the other advances, then the squad clears and occupies the position. Z at the cursor, or arm and click."],
	["COMBAT", SquadState.Tactic.SUPPRESS, &"suppress", "Suppress", "K", "SUPPRESS\nPin the area with fire from a covered post that has a line to it; enemies there keep their heads down and shoot worse. Uses ammunition steadily. K at the cursor, or arm and click."],
	["COMBAT", SquadState.Tactic.FLANK, &"flank", "Flank", "L", "FLANK\nOne fire team keeps the position pinned while the other goes round it by a covered route and attacks from the side. L at the cursor, or arm and click."],
	["COMBAT", SquadState.Tactic.DEFEND, &"defend", "Defend", "J", "DEFEND\nHold the selected area: the squad takes firing posts, fortification slots first, facing the known threat, and falls back a line if it must. J at the cursor, or arm and click."],
	["COMBAT", SquadState.Tactic.WITHDRAW, &"withdraw", "Withdraw", "BS", "WITHDRAW\nBreak contact toward the spot (or the nearest safe place): one team covers while the other pulls back. Backspace at the cursor, or arm and click."],
	["SQUAD", RTSController.GARRISON, &"garrison", "Garrison", "O", "GARRISON\nAssign the squad to one of your bases (click it): it mans towers, positions and walls and defends the base until given another order."],
	["SQUAD", RTSController.REARM, &"rearm", "Rearm", "R", "REARM\nSearch nearby equipment and ammunition (caches, stashes, the fallen, your base stores within 30 m), refill the soldiers and carry spare weapons in the squad cargo. Hand found weapons in at a base with a Supply Depot to register them. R at the cursor, or arm and click."],
	["SQUAD", EQUIP, &"equipment", "Equip", "", "EQUIP\nChange soldiers' roles and weapons: from the squad cargo anywhere, from the armoury or procured at a base."],
	["SQUAD", FORMATION, &"formation", "Form", "V", "FORMATION\nV: line / column. Shift+V cycles line, column, wedge, staggered, dispersed and auto (auto spreads out in contact). [ and ] change the spacing."],
	["SQUAD", ROE, &"roe_free", "Fire", "Y", "RULES OF ENGAGEMENT\nWeapons free: soldiers engage enemies they see. Hold fire: they observe and report, and only fire when hit."],
	["MODE", BEHAVIOUR - 0, &"beh_safe", "Safe", "", SquadBehaviour.HINTS[0]],
	["MODE", BEHAVIOUR - 1, &"beh_aware", "Aware", "", SquadBehaviour.HINTS[1]],
	["MODE", BEHAVIOUR - 2, &"beh_combat", "Combat", "", SquadBehaviour.HINTS[2]],
	["MODE", BEHAVIOUR - 3, &"beh_stealth", "Stealth", "", SquadBehaviour.HINTS[3]],
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
	foot.add_child(FNKeyHint.new("RMB drag", "Place"))
	foot.add_child(FNKeyHint.new("F1", "Controls"))


func _build_summary() -> Control:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.custom_minimum_size = Vector2(200, 0)
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
	_order = FNUI.label("", FNUI.CAPTION + 1, FNUI.INK_2, "body")
	_order.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order.max_lines_visible = 2
	_order.custom_minimum_size = Vector2(200, 0)
	v.add_child(_order)
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
	v.add_theme_constant_override("separation", FNUI.S2)
	var rows := {}
	for n: String in ROWS:
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", FNUI.S2)
		var cap := FNUI.label(n if n != "MODE" else "MODE  X", FNUI.CAPTION - 1, FNUI.INK_3, "caps")
		cap.custom_minimum_size = Vector2(52, 0)
		cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(cap)
		v.add_child(h)
		rows[n] = h
	for e: Array in ENTRIES:
		var key: int = e[1]
		var b := FNCommandButton.new(e[2], e[3], e[4], e[5], true)
		b.pressed.connect(_on_button.bind(key))
		(rows[e[0]] as HBoxContainer).add_child(b)
		_buttons[key] = b
	_mode_note = FNUI.label("", FNUI.CAPTION - 1, FNUI.ALERT, "caps")
	_mode_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	(rows["MODE"] as HBoxContainer).add_child(_mode_note)
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
		EQUIP:
			var hud := get_parent() as GameHUD
			if hud and hud.equipment:
				hud.equipment.open_for(rts.selected_squads()[0] if not rts.selected_squads().is_empty() else -1)
		_ when key <= BEHAVIOUR and key > BEHAVIOUR - 4:
			rts.set_behaviour(BEHAVIOUR - key)
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
	_refresh_order(squads)
	_refresh_feedback()
	size = Vector2.ZERO


func _refresh_summary(squads: Array[SquadState]) -> void:
	var first := squads[0]
	var alive := 0
	var total := 0
	var names: Array[String] = []
	for sq in squads:
		var sn := SquadPanel.strength(sq)
		alive += sn.x
		total += sn.y
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


## QOL-01: what the order is doing in words (the first squad's), and the mode the situation makes it act in.
func _refresh_order(squads: Array[SquadState]) -> void:
	var first := squads[0]
	var d := sim.squads.describe_order(first)
	var text: String = d.text
	if squads.size() > 1:
		text = "%s: %s (+%d)" % [first.squad_name, text, squads.size() - 1]
	_order.text = text
	_order.tooltip_text = text
	var col: Color = FNUI.INK_2
	match String(d.state):
		"interrupted":
			col = FNUI.ALERT
		"blocked", "route_blocked":
			col = FNUI.DANGER
	_order.add_theme_color_override("font_color", col)
	var now_b := sim.tactics.behaviour_now(first)
	_mode_note.text = ("acting %s" % SquadBehaviour.name_of(now_b)) if now_b != first.behaviour else ""


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
		b.armed = (is_tactic and key == rts.armed_tactic) or (key == FOLLOW and rts.follow_pick) or ((key == RTSController.GARRISON or key == RTSController.REARM) and rts.armed_tactic == key)
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
				RTSController.REARM:
					now = now or sq.rearm_at.is_finite()
				EQUIP:
					pass
				_ when key <= BEHAVIOUR and key > BEHAVIOUR - 4:
					now = now or sq.behaviour == BEHAVIOUR - key
				_:
					now = now or sq.tactic == key
		b.current = now
		if key <= BEHAVIOUR and key > BEHAVIOUR - 4:
			# QOL-01: the chosen mode reads at a glance (accent icon on the selected surface), not only by its underline.
			b.icon_rect.modulate = FNUI.ACCENT if now else FNUI.INK_2
			b.add_theme_stylebox_override("normal", FNUI.state_style(&"selected" if now else &"normal"))
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
		var tname := RTSController._armed_name(rts.armed_tactic)
		_feedback.set_status(&"tactic", "%s armed — click the target  ·  Esc or right click cancels" % tname, FNUI.ARMED)
	elif rts.follow_pick:
		_feedback.set_status(&"follow", "Follow armed — click the soldier or squad to follow  ·  Esc cancels", FNUI.ARMED)
	elif now < _fb_until and _fb_text != "":
		_feedback.set_status(&"tactic" if rts.tactic_feedback_ok else &"blocked", _fb_text, FNUI.OK if rts.tactic_feedback_ok else FNUI.DANGER)
	elif rts.current_message() != "":
		_feedback.set_status(&"idle", rts.current_message(), FNUI.INK_2)
	else:
		_feedback.set_status(&"moving", "Right click to move  ·  arm an order or use its key at the cursor", FNUI.INK_3)

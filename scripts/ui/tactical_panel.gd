## The tactical view's squad card (AI-SQUAD-01, UI-01C, QOL-01, UI-UX-03): one compact surface at the bottom right, shown only
## while at least one squad is selected.
##
## UI-UX-03: the card was 550 x 200 logical px at 100 % (two thirds of the screen width at the default 125 % scale on 1080p), with
## every command and every behaviour as a labelled tile. Now, top to bottom:
##   header    emblem, callsign (or the number of squads), soldiers, status;
##   order     what the order is doing (SquadControl.describe_order), one line;
##   state     health / ammunition / suppression as small bars, the support weapons, the mode the situation makes it act in;
##   orders    the movement and combat orders as one row of icon tiles (name, help and hotkey in the tooltip, hotkey in the corner);
##   settings  Formation, Behaviour and Fire as dropdowns showing the current value ("Mixed" for a mixed selection) and a
##             Squad menu for the rarer orders (garrison, rearm, equipment, spacing, frame the camera);
##   footer    what is armed, whether the last order was accepted and why not.
## A tactic tile arms the order (the next left click gives its target; Esc or a right click cancels); the hotkeys give the same
## order at the cursor at once. Every control calls the RTSController function its key calls, so what the player commands is
## what the squads do on their own.
class_name TacticalPanel
extends FNPanel

var rts: RTSController
var sim: WorldSim

var _buttons := {}
var _emblem: FNUnitEmblem
var _title: Label
var _strength: Label
var _subtitle: Label
var _status: FNStatusIndicator
var _health: MiniMeter
var _ammo: MiniMeter
var _supp: MiniMeter
## The selection's settings and support weapons in words (tests read it).
var _settings: Label
var _support: Label
var _feedback: FNStatusIndicator
var _timer := 0.0
var _order: Label
var _mode_note: Label
var _fb_text := ""
var _fb_until := 0.0
var formation_dd: FNDropdown
var behaviour_dd: FNDropdown
var roe_dd: FNDropdown
var squad_dd: FNDropdown

## Button keys for the orders that are not tactics.
const HOLD := -2
const FOLLOW := -3
const REGROUP := -4
const FORMATION := -5
const ROE := -6
## GAMEPLAY-04D: open the equipment screen for the selected squad.
const EQUIP := -7
## UI-UX-03 Squad menu entries.
const FOCUS := -8
const SPACING_UP := -9
const SPACING_DOWN := -10
## QOL-01: behaviour modes are BEHAVIOUR - mode (SquadBehaviour SAFE..STEALTH -> -20..-23).
const BEHAVIOUR := -20
## The Formation dropdown's Auto entry (formations are SquadState.Formation 0..4).
const FORMATION_AUTO := -1

## The order row: [key, icon, title, hotkey, tooltip]; null = a gap between the groups.
const ORDERS := [
	[SquadState.Tactic.BOUND, &"bound", "Bound", "⇧", "BOUND  (Shift+right click)\nMove in bounds: one fire team covers from where it stands while the other moves, then they swap. Slower than a move, safer near the enemy."],
	[FOLLOW, &"follow", "Follow", "F", "FOLLOW  (F)\nKeep behind a soldier or squad (click the one to follow) until given another order."],
	[HOLD, &"hold", "Hold", "H", "HOLD  (H)\nStop where the squad stands and stay there; soldiers still return fire and take cover nearby. Cancels the current order or tactic."],
	[REGROUP, &"regroup", "Regroup", "G", "REGROUP  (G)\nReassemble on the leader once it is calm (Shift+G: at the cursor). Use after a fight has scattered the squad."],
	null,
	[SquadState.Tactic.ASSAULT, &"assault", "Assault", "Z", "ASSAULT  (Z)\nMove toward the target using coordinated fire and movement: one fire team suppresses while the other advances, then the squad clears and occupies the position."],
	[SquadState.Tactic.SUPPRESS, &"suppress", "Suppress", "K", "SUPPRESS  (K)\nPin the area with fire from a covered post that has a line to it; enemies there keep their heads down and shoot worse. Uses ammunition steadily."],
	[SquadState.Tactic.FLANK, &"flank", "Flank", "L", "FLANK  (L)\nOne fire team keeps the position pinned while the other goes round it by a covered route and attacks from the side."],
	[SquadState.Tactic.DEFEND, &"defend", "Defend", "J", "DEFEND  (J)\nHold the selected area: the squad takes firing posts, fortification slots first, facing the known threat, and falls back a line if it must."],
	[SquadState.Tactic.WITHDRAW, &"withdraw", "Withdraw", "⌫", "WITHDRAW  (Backspace)\nBreak contact toward the spot (or the nearest safe place): one team covers while the other pulls back."],
]
const TACTICS := [SquadState.Tactic.BOUND, SquadState.Tactic.ASSAULT, SquadState.Tactic.SUPPRESS, SquadState.Tactic.FLANK,
	SquadState.Tactic.DEFEND, SquadState.Tactic.WITHDRAW]
const FORMATION_HINTS := ["Abreast, facing the front: the most rifles to the front.", "One behind the other: roads, woods, narrow ground.",
	"An arrowhead: all-round view when the front is unknown.", "Two offset files: a road march with some frontage.",
	"Wide gaps: under artillery or fire from above."]


## UI-UX-03: one small labelled bar (HP, AMMO, SUP) of the state row.
class MiniMeter extends Control:
	var caption := ""
	var value := 0.0
	var color := FNUI.OK
	var critical := false

	func _init(p_caption: String) -> void:
		caption = p_caption
		custom_minimum_size = Vector2(62, 12)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_value(v: float, col: Color, tip: String) -> void:
		if not is_equal_approx(v, value) or col != color:
			value = v
			color = col
			queue_redraw()
		tooltip_text = tip

	func _draw() -> void:
		var f := FNUI.caps_font()
		draw_string(f, Vector2(0, 9), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION - 1, FNUI.INK_2)
		var x := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION - 1).x + 3.0
		var r := Rect2(x, 4, size.x - x, 4)
		draw_rect(r, Color(FNUI.LINE, 0.9))
		if value >= 0.0:
			draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(value, 0.0, 1.0), r.size.y)), color)


func _init() -> void:
	super(Color.TRANSPARENT, FNUI.S3 + 1)


func _ready() -> void:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", FNUI.S2)
	add_child(v)
	# Header: emblem, callsign, strength, status.
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", FNUI.S3)
	v.add_child(head)
	_emblem = FNUnitEmblem.new(Vector2(24, 16))
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_emblem)
	_title = FNUI.label("", FNUI.TITLE, FNUI.INK, "title")
	head.add_child(_title)
	_strength = FNUI.label("", FNUI.LABEL, FNUI.INK_2, "number")
	_strength.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_strength)
	_status = FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.alignment = BoxContainer.ALIGNMENT_END
	_status.text_label.clip_text = true
	_status.text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_status)
	_subtitle = FNUI.label("", FNUI.CAPTION, FNUI.INK_3, "caps")
	_subtitle.clip_text = true
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle.visible = false
	v.add_child(_subtitle)
	_order = FNUI.label("", FNUI.CAPTION + 1, FNUI.INK_2, "body")
	_order.clip_text = true
	_order.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_order.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_order)
	# State row: three bars and the support weapons.
	var state := HBoxContainer.new()
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.add_theme_constant_override("separation", FNUI.S4)
	v.add_child(state)
	_health = MiniMeter.new("HP")
	_ammo = MiniMeter.new("AMMO")
	_supp = MiniMeter.new("SUPP")
	for m in [_health, _ammo, _supp]:
		state.add_child(m)
	_support = FNUI.label("", FNUI.CAPTION - 1, FNUI.INK_3, "caps")
	_support.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_support.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_support.clip_text = true
	_support.mouse_filter = Control.MOUSE_FILTER_PASS
	state.add_child(_support)
	_settings = FNUI.label("", FNUI.CAPTION, FNUI.INK_3, "caps")
	_settings.visible = false
	v.add_child(_settings)
	v.add_child(_rule())
	# Orders: movement | combat.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	v.add_child(row)
	for e in ORDERS:
		if e == null:
			var gap := ColorRect.new()
			gap.color = Color(FNUI.LINE_STRONG, 0.6)
			gap.custom_minimum_size = Vector2(1, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var m := MarginContainer.new()
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			m.add_theme_constant_override("margin_left", 3)
			m.add_theme_constant_override("margin_right", 3)
			m.add_child(gap)
			row.add_child(m)
			continue
		var key: int = e[0]
		var b := FNCommandButton.new(e[1], e[2], e[3], e[4], true)
		b.make_icon_only()
		b.pressed.connect(_on_button.bind(key))
		row.add_child(b)
		_buttons[key] = b
	# Settings: Formation, Behaviour, Fire, Squad.
	var set_row := HBoxContainer.new()
	set_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_row.add_theme_constant_override("separation", 3)
	v.add_child(set_row)
	formation_dd = FNDropdown.new("", "FORMATION  (V: line / column, Shift+V: next)\nHow the squad arranges itself on the move and at a halt. Auto: column on roads and in woods, wedge in the open, dispersed under fire. [ and ] change the spacing.")
	var fitems := [{"id": FORMATION_AUTO, "text": "Auto", "icon": &"formation", "key": "", "tip": "Auto: column on roads and in woods, wedge in the open, dispersed under fire."}]
	for f in SquadState.FORMATION_NAMES.size():
		fitems.append({"id": f, "text": SquadState.FORMATION_NAMES[f], "icon": &"formation", "key": "V" if f <= 1 else "", "tip": FORMATION_HINTS[f]})
	formation_dd.set_items(fitems)
	formation_dd.chosen.connect(_on_formation)
	set_row.add_child(formation_dd)
	behaviour_dd = FNDropdown.new("", "BEHAVIOUR  (X: next)\nHow the squad operates: Safe marches fast and relaxed, Aware is the default, Combat fights from cover, Stealth avoids being seen. The current order continues.")
	var bitems := []
	for b in SquadBehaviour.NAMES.size():
		bitems.append({"id": b, "text": SquadBehaviour.name_of(b).capitalize(), "icon": SquadBehaviour.ICONS[b], "key": "", "tip": SquadBehaviour.HINTS[b]})
	behaviour_dd.set_items(bitems)
	behaviour_dd.chosen.connect(func(id: Variant) -> void:
		rts.set_behaviour(int(id))
		_timer = 0.0)
	set_row.add_child(behaviour_dd)
	roe_dd = FNDropdown.new("", "RULES OF ENGAGEMENT  (Y: toggle)\nWeapons free: soldiers engage enemies they see. Hold fire: they observe and report, and only fire when hit.")
	roe_dd.set_items([
		{"id": SquadState.Roe.WEAPONS_FREE, "text": "Fire free", "icon": &"roe_free", "key": "Y", "tip": "Weapons free: soldiers engage enemies they see."},
		{"id": SquadState.Roe.HOLD_FIRE, "text": "Hold fire", "icon": &"roe_hold", "key": "Y", "tip": "Hold fire: observe and report, fire only when hit."}])
	roe_dd.chosen.connect(func(id: Variant) -> void:
		rts.set_roe(rts.selected_squads(), int(id))
		_timer = 0.0)
	set_row.add_child(roe_dd)
	squad_dd = FNDropdown.new("", "SQUAD ORDERS\nGarrison a base, rearm from nearby equipment, change roles and weapons, spacing, frame the camera.")
	squad_dd.set_items([
		{"id": RTSController.GARRISON, "text": "Garrison base", "icon": &"garrison", "key": "O", "tip": "Assign the squad to one of your bases (click it): it mans towers, positions and walls and defends the base until given another order."},
		{"id": RTSController.REARM, "text": "Rearm here", "icon": &"rearm", "key": "R", "tip": "Search nearby equipment and ammunition (caches, stashes, the fallen, your base stores within 30 m), refill the soldiers and carry spare weapons in the squad cargo."},
		{"id": EQUIP, "text": "Equipment", "icon": &"equipment", "key": "", "tip": "Change soldiers' roles and weapons: from the squad cargo anywhere, from the armoury or procured at a base."},
		{"id": SPACING_UP, "text": "Spacing wider", "icon": &"formation", "key": "]", "tip": "More room between the soldiers."},
		{"id": SPACING_DOWN, "text": "Spacing closer", "icon": &"formation", "key": "[", "tip": "Less room between the soldiers."},
		{"id": FOCUS, "text": "Show on screen", "icon": &"focus", "key": "C", "tip": "Frame the tactical camera on the selection."}])
	squad_dd.chosen.connect(func(id: Variant) -> void: _on_button(int(id)))
	squad_dd.fit_items = false
	squad_dd.custom_minimum_size.x = 76
	squad_dd.value_label.text = "SQUAD"
	squad_dd.value_label.clip_text = false
	squad_dd.icon_rect.texture = FNIcons.texture(&"more", FNUI.ICON_S)
	squad_dd.icon_rect.visible = true
	set_row.add_child(squad_dd)
	_mode_note = FNUI.label("", FNUI.CAPTION - 1, FNUI.ALERT, "caps")
	_mode_note.visible = false
	v.add_child(_mode_note)
	_feedback = FNStatusIndicator.new(FNUI.ICON_S, FNUI.CAPTION)
	_feedback.text_label.clip_text = true
	_feedback.text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_feedback.custom_minimum_size = Vector2(0, 12)
	v.add_child(_feedback)


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(FNUI.LINE, 0.9)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _on_formation(id: Variant) -> void:
	var sqs := rts.selected_squads()
	if sqs.is_empty():
		return
	var f := int(id)
	for sid in sqs:
		sim.state.get_squad(sid).formation_auto = f == FORMATION_AUTO
	# Auto starts from a wedge (as Shift+V does); SquadControl re-shapes it from the terrain and the situation.
	sim.squads.set_formation(sqs, SquadState.Formation.WEDGE if f == FORMATION_AUTO else f)
	rts._say("Formation: %s" % ("Auto (column on roads and in woods, wedge in the open, dispersed under fire)" if f == FORMATION_AUTO else SquadState.FORMATION_NAMES[f]))
	_timer = 0.0


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
		FOCUS:
			rts.focus_selection()
		SPACING_UP:
			rts.change_spacing(0.5)
		SPACING_DOWN:
			rts.change_spacing(-0.5)
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
	_strength.text = "%d/%d" % [alive, total]
	if squads.size() == 1:
		_title.text = first.squad_name.to_upper()
		_subtitle.visible = false
		tooltip_text = ""
	else:
		_title.text = "%d SQUADS" % squads.size()
		_subtitle.text = " · ".join(names)
		_subtitle.visible = true
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
	_health.set_value(h, FNUI.OK if h >= 0.6 else (FNUI.WARN if h >= 0.3 else FNUI.DANGER), "Health %d%%" % roundi(h * 100.0))
	if capacity > 0:
		var a := clampf(float(rounds) / capacity, 0.0, 1.0)
		_ammo.set_value(a, FNUI.INFO if a >= 0.3 else FNUI.WARN, "Ammunition %d%%" % roundi(a * 100.0))
	else:
		_ammo.set_value(-1.0, FNUI.INFO, "No ammunition data")
	var s := supp / maxi(n, 1)
	_supp.set_value(s, FNUI.DANGER if s >= 0.6 else FNUI.ALERT, "Suppression %d%%" % roundi(s * 100.0))
	var support: Array[String] = []
	if mgs > 0:
		support.append("MG %d" % mgs)
	if rockets > 0:
		support.append("RKT %d" % rockets)
	if nades > 0:
		support.append("GR %d" % nades)
	_support.text = " · ".join(support)
	_support.tooltip_text = "Machine guns %d (%d%% rounds) · rockets %d · grenades %d" % [mgs, roundi(100.0 * mg_rounds / maxi(mg_cap, 1)), rockets, nades]
	var form := "Auto" if first.formation_auto else first.formation_name()
	_settings.text = "Formation %s  ·  %s  ·  spacing %.1f m%s" % [form, first.roe_name(), first.spacing,
		"  ·  in operation" if first.op_id >= 0 else ("  ·  garrison %s" % sim.state.construction.bases[first.garrison_base].name if sim.state.construction.bases.has(first.garrison_base) else "")]
	if not support.is_empty():
		_settings.text += "\n" + _support.tooltip_text


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
	_mode_note.text = ("Acting %s now" % SquadBehaviour.name_of(now_b)) if now_b != first.behaviour else ""
	_mode_note.visible = _mode_note.text != ""


## The value every selected squad shares, else null (the dropdown reads "Mixed").
static func _shared(squads: Array[SquadState], f: Callable) -> Variant:
	var v: Variant = f.call(squads[0])
	for sq in squads.slice(1):
		if f.call(sq) != v:
			return null
	return v


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
		b.armed = (is_tactic and key == rts.armed_tactic) or (key == FOLLOW and rts.follow_pick)
		var now := false
		for sq in squads:
			match key:
				HOLD:
					now = now or (sq.order == SquadState.Order.HOLD and sq.tactic == SquadState.Tactic.NONE)
				FOLLOW:
					now = now or sq.order == SquadState.Order.FOLLOW
				REGROUP:
					now = now or sq.order == SquadState.Order.REGROUP or sq.tactic == SquadState.Tactic.REGROUP
				_:
					now = now or sq.tactic == key
		b.current = now
	formation_dd.set_value(_shared(squads, func(sq: SquadState) -> int: return FORMATION_AUTO if sq.formation_auto else sq.formation))
	behaviour_dd.set_value(_shared(squads, func(sq: SquadState) -> int: return sq.behaviour))
	var roe: Variant = _shared(squads, func(sq: SquadState) -> int: return sq.roe)
	roe_dd.set_value(roe)
	roe_dd.value_label.add_theme_color_override("font_color", FNUI.ARMED if roe == SquadState.Roe.HOLD_FIRE else (FNUI.INK if roe != null else FNUI.WARN))
	var now_b := sim.tactics.behaviour_now(squads[0])
	if now_b != squads[0].behaviour and squads.size() == 1:
		behaviour_dd.value_label.add_theme_color_override("font_color", FNUI.ALERT)
	# The Squad menu's armed orders read amber on the menu button.
	var armed_squad := rts.armed_tactic == RTSController.GARRISON or rts.armed_tactic == RTSController.REARM
	squad_dd.value_label.add_theme_color_override("font_color", FNUI.ARMED if armed_squad else FNUI.INK)


## Footer: an armed order first, then the result of the last order (8 s), then the controller's
## message (3 s), else a quiet reminder.
func _refresh_feedback() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if rts.tactic_feedback != _fb_text:
		_fb_text = rts.tactic_feedback
		_fb_until = now + 8.0
	if rts.armed_tactic >= 0:
		var tname := RTSController._armed_name(rts.armed_tactic)
		_feedback.set_status(&"tactic", "%s armed — click the target · Esc cancels" % tname, FNUI.ARMED)
	elif rts.follow_pick:
		_feedback.set_status(&"follow", "Follow armed — click the soldier or squad · Esc cancels", FNUI.ARMED)
	elif now < _fb_until and _fb_text != "":
		_feedback.set_status(&"tactic" if rts.tactic_feedback_ok else &"blocked", _fb_text, FNUI.OK if rts.tactic_feedback_ok else FNUI.DANGER)
	elif rts.current_message() != "":
		_feedback.set_status(&"idle", rts.current_message(), FNUI.INK_2)
	else:
		_feedback.set_status(&"moving", "RMB move · RMB drag place · keys at the cursor", FNUI.INK_3)
	_feedback.tooltip_text = _feedback.text_label.text

## Compact tactical-order bar for the selected squads (AI-SQUAD-01), bottom centre of the
## tactical view. It appears only while at least one squad is selected.
##
## A button arms an order (the next left click gives its target; Esc or a right click cancels);
## the hotkeys on the buttons give the same order at the cursor at once. Orders go through
## RTSController.order_tactic - the same SquadTactics calls the AI uses - so what the player
## commands is what the squads do on their own. The second line shows what each selected squad
## is doing now, the third whether the last order was accepted and, if not, why it cannot be
## executed.
class_name TacticalPanel
extends PanelContainer

var rts: RTSController
var sim: WorldSim

var _buttons := {}
var _status: Label
var _feedback: Label
var _title: Label
var _timer := 0.0
var _fb_text := ""
var _fb_until := 0.0

const ENTRIES := [
	[SquadState.Tactic.ASSAULT, "Assault", "Z", "Attack the position: one fire team suppresses while the other advances, then the squad occupies it"],
	[SquadState.Tactic.SUPPRESS, "Suppress", "K", "Pin a position with fire from a covered post with a line to it"],
	[SquadState.Tactic.FLANK, "Flank", "L", "Round the position by a covered route while the other team keeps it pinned"],
	[SquadState.Tactic.DEFEND, "Defend", "J", "Move to the spot (or stay) and hold it from firing posts"],
	[SquadState.Tactic.WITHDRAW, "Withdraw", "Back", "Break contact towards the spot (or a safe place), one team covering the other"],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 0)
	add_theme_stylebox_override("panel", FieldManual.panel(FieldManual.OLIVE, 0.91, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	_title = Label.new()
	FieldManual.style_label(_title, 13, FieldManual.OLIVE)
	box.add_child(_title)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	box.add_child(row)
	for e: Array in ENTRIES:
		row.add_child(_make_button(e[1].to_upper() + "  " + e[2], e[3], func() -> void: rts.arm_tactic(e[0]), e[0]))
	row.add_child(_make_button("REGROUP  G", "Reassemble on the leader (waits for calm)", func() -> void: rts.order_regroup(), -2))
	row.add_child(_make_button("ROE  Y", "Hold fire / weapons free (a soldier that is hit still defends itself)", func() -> void: rts.toggle_roe(), -3))
	_status = Label.new()
	FieldManual.style_label(_status, 12, FieldManual.SECONDARY)
	box.add_child(_status)
	_feedback = Label.new()
	FieldManual.style_label(_feedback, 12, FieldManual.SUCCESS)
	box.add_child(_feedback)


func _make_button(text: String, tip: String, on_press: Callable, key: int) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	FieldManual.style_button(b, FieldManual.AMBER)
	b.pressed.connect(on_press)
	_buttons[key] = b
	return b


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or sim == null or rts == null:
		return
	_timer = 0.2
	var sqs := rts.selected_squads()
	if sqs.is_empty():
		return
	var strength := 0
	for sid in sqs:
		var selected: SquadState = sim.state.get_squad(sid)
		if selected:
			strength += maxi(0, selected.members.size() - selected.fallen.size())
	_title.text = "COMMAND DECK  ·  %d SQUAD%s  ·  %d READY" % [sqs.size(), "" if sqs.size() == 1 else "S", strength]
	for key in _buttons:
		var b: Button = _buttons[key]
		b.modulate = Color(1.0, 0.9, 0.3) if key == rts.armed_tactic else Color.WHITE
	var lines: Array[String] = []
	for sid in sqs.slice(0, 3):
		var sq := sim.state.get_squad(sid)
		if sq == null:
			continue
		var a := sim.tactics.assessment(sq)
		var eff := ("  eff %.2f" % a.eff) if not a.is_empty() and int(a.n) > 0 else ""
		var supp := ("  supp %.2f" % a.supp) if not a.is_empty() and float(a.supp) > 0.05 else ""
		var what := sim.tactics.short_text(sq)
		if what == "":
			what = sq.order_name()
		lines.append("%s  ·  %s%s%s" % [sq.squad_name.to_upper(), what, eff, supp])
	if sqs.size() > 3:
		lines.append("+%d more" % (sqs.size() - 3))
	_status.text = "\n".join(lines)
	if rts.tactic_feedback != _fb_text:
		_fb_text = rts.tactic_feedback
		_fb_until = Time.get_ticks_msec() / 1000.0 + 8.0
	var show_fb := Time.get_ticks_msec() / 1000.0 < _fb_until
	_feedback.text = _fb_text if show_fb else ""
	_feedback.modulate = Color(0.6, 1.0, 0.6) if rts.tactic_feedback_ok else Color(1.0, 0.6, 0.5)
	_feedback.visible = show_fb and _fb_text != ""
	size = Vector2.ZERO

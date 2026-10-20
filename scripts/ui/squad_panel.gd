## Compact squad list for the tactical view (UNIT-01A): one row per squad with its
## size, order and progress. Click selects the squad, Shift+click adds it. Reads
## WorldState only; the rows are rebuilt when squads change and refreshed a few times
## per second. COMBAT-01b: living / fallen, how many are fighting, and a button per row
## for the rules of engagement (FREE = weapons free, HOLD = hold fire; Y in the
## tactical view does the same for the selected squads).
class_name SquadPanel
extends PanelContainer

var rts: RTSController
var sim: WorldSim

var _list: VBoxContainer
## COMBAT-02: the rows scroll when they would grow into the HUD text below.
var _scroll: ScrollContainer
## Lowest screen y the panel may reach (set by the HUD each frame).
var max_bottom := INF
var _buttons := {}
var _roe_buttons := {}
var _rows := {}
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var title := Label.new()
	title.text = "SQUADS  (click select, Shift add, FREE / HOLD = fire)"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.8, 0.85, 0.7)
	box.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or sim == null or rts == null:
		return
	_timer = 0.25
	var squads := sim.state.all_squads()
	var ids := {}
	for sq: SquadState in squads:
		ids[sq.id] = true
		if not _buttons.has(sq.id):
			_add_row(sq)
	for id in _buttons.keys():
		if not ids.has(id):
			_rows[id].queue_free()
			_rows.erase(id)
			_buttons.erase(id)
			_roe_buttons.erase(id)
	var selected := rts.selected_squads()
	# Height: all rows when they fit above max_bottom, else scroll.
	var rows_h := _list.get_combined_minimum_size().y
	var room := max_bottom - global_position.y - 40.0
	_scroll.custom_minimum_size = Vector2(_list.get_combined_minimum_size().x + 12.0, clampf(rows_h, 24.0, maxf(room, 60.0)))
	size = Vector2.ZERO
	for sq: SquadState in squads:
		var b: Button = _buttons[sq.id]
		b.text = row_text(sq)
		b.modulate = Color(1.0, 1.0, 0.55) if selected.has(sq.id) else Color.WHITE
		var r: Button = _roe_buttons[sq.id]
		var hold := sq.roe == SquadState.Roe.HOLD_FIRE
		r.text = "HOLD" if hold else "FREE"
		r.modulate = Color(1.0, 0.7, 0.25) if hold else Color(0.55, 1.0, 0.55)


func _add_row(sq: SquadState) -> void:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(360, 0)
	var sid := sq.id
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			rts.select_squads([sid], ev.shift_pressed)
			accept_event())
	var roe := Button.new()
	roe.focus_mode = Control.FOCUS_NONE
	roe.add_theme_font_size_override("font_size", 13)
	roe.custom_minimum_size = Vector2(54, 0)
	roe.tooltip_text = "Rules of engagement: FREE = weapons free, HOLD = hold fire (Y)"
	roe.pressed.connect(func() -> void:
		var s := sim.state.get_squad(sid)
		if s:
			rts.set_roe([sid], SquadState.Roe.HOLD_FIRE if s.roe == SquadState.Roe.WEAPONS_FREE else SquadState.Roe.WEAPONS_FREE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(b)
	row.add_child(roe)
	_list.add_child(row)
	_rows[sq.id] = row
	_buttons[sq.id] = b
	_roe_buttons[sq.id] = roe


func row_text(sq: SquadState) -> String:
	var progress := ""
	match sq.status:
		SquadState.Status.MOVING:
			progress = "moving"
		SquadState.Status.DONE:
			progress = "in position" if sq.order != SquadState.Order.HOLD else "holding"
		SquadState.Status.PARTIAL:
			progress = "%d blocked" % sq.blocked.size()
	var order := sq.order_name()
	if sq.order == SquadState.Order.FOLLOW:
		var t := sim.squads.follow_target(sq)
		var other := sim.state.get_squad(sq.follow_squad_id)
		order = "Follow %s" % (other.squad_name if other else (t.unit_name if t else "?"))
	var detached := "  %d detached" % sq.detached.size() if not sq.detached.is_empty() else ""
	var fallen := " +%d fallen" % sq.fallen.size() if not sq.fallen.is_empty() else ""
	var fighting := 0
	var under_fire := 0
	var cover := 0
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u == null:
			continue
		if u.ai_state == UnitState.AiState.ENGAGING:
			fighting += 1
		if u.under_fire_until >= sim.state.time:
			under_fire += 1
		if u.tactic == UnitState.Tactic.IN_COVER or u.tactic == UnitState.Tactic.SEEK_COVER:
			cover += 1
	var parts: Array[String] = []
	if fighting > 0:
		parts.append("%d engaging" % fighting)
	if under_fire > 0:
		parts.append("%d under fire" % under_fire)
	if cover > 0:
		parts.append("%d to / in cover" % cover)
	var combat := ("  | " + ", ".join(parts)) if not parts.is_empty() else ""
	return "%s  [%s]  %d%s  %s  %s %s%s%s" % [sq.squad_name, WorldState.faction_name(sq.faction).left(1), sq.members.size(), fallen,
		sq.formation_name(), order, ("· " + progress) if progress != "" else "", detached, combat]

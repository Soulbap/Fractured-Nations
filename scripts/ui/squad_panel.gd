## The tactical view's TASK FORCE roster (UNIT-01A, UI-01C): one FNUnitRow per squad the player
## may command - emblem, callsign, strength, status and a hold-fire flag. Click selects the
## squad, Shift+click adds it; selected rows are marked (several at once). Reads WorldState only;
## rows are added / removed when squads change and refreshed a few times per second. The header
## carries the player's side, so the faction is part of the roster instead of a separate badge.
class_name SquadPanel
extends FNPanel

var rts: RTSController
var sim: WorldSim

## COMBAT-02: the rows scroll when they would grow into the HUD below.
var _scroll: ScrollContainer
var _list: VBoxContainer
var _header: FNSectionHeader
var _chip: Label
## Lowest screen y the panel may reach (set by the HUD each frame).
var max_bottom := INF
var _rows := {}
var _timer := 0.0

const WIDTH := 214.0


func _init() -> void:
	super(Color.TRANSPARENT, FNUI.S4)


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", FNUI.S3)
	add_child(box)
	_header = FNSectionHeader.new("Task Force", "", FNUI.INK)
	_header.tooltip_text = "Click a squad to select it, Shift+click to add it. Ctrl+click a soldier in the field selects his squad."
	_header.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or sim == null or rts == null:
		return
	_timer = 0.25
	if _chip == null:
		var pf := rts.player_faction
		accent = WorldState.faction_color(pf)
		_chip = _header.add_chip(WorldState.faction_name(pf), WorldState.faction_color(pf))
	# Only the squads the player may command (all of them in the old test layouts).
	var squads := sim.state.all_squads().filter(func(sq: SquadState) -> bool: return rts._can_command(sq.leader_id))
	var ids := {}
	var soldiers := 0
	for sq: SquadState in squads:
		ids[sq.id] = true
		soldiers += maxi(0, sq.members.size() - sq.fallen.size())
		if not _rows.has(sq.id):
			_add_row(sq)
	for id in _rows.keys():
		if not ids.has(id):
			_rows[id].queue_free()
			_rows.erase(id)
	_header.aside.text = "%d SQUAD%s · %d" % [squads.size(), "" if squads.size() == 1 else "S", soldiers]
	var selected := rts.selected_squads()
	for sq: SquadState in squads:
		_refresh_row(_rows[sq.id], sq, selected.has(sq.id))
	# Height: all rows when they fit above max_bottom, else scroll (the scroll bar gets its own gutter).
	var rows_h := _list.get_combined_minimum_size().y
	var room := max_bottom - global_position.y - 36.0
	var h := clampf(rows_h, 24.0, maxf(room, 50.0))
	_scroll.custom_minimum_size = Vector2(WIDTH - 2.0 * FNUI.S4, h)
	_list.custom_minimum_size.x = WIDTH - 2.0 * FNUI.S4 - (5.0 if rows_h > h else 0.0)
	size = Vector2.ZERO


func _add_row(sq: SquadState) -> void:
	var row := FNUnitRow.new()
	row.emblem.color = WorldState.faction_color(sq.faction)
	var sid := sq.id
	row.activated.connect(func(shift: bool) -> void: rts.select_squads([sid], shift))
	_list.add_child(row)
	_rows[sq.id] = row


func _refresh_row(row: FNUnitRow, sq: SquadState, is_selected: bool) -> void:
	var st := squad_status(sim, sq, true)
	row.selected = is_selected
	row.callsign.text = sq.squad_name.to_upper()
	row.set_strength(maxi(0, sq.members.size() - sq.fallen.size()), sq.members.size())
	row.status.set_status(st.icon, st.text, st.color)
	row.emblem.frame_color = st.color if st.engaged else Color.TRANSPARENT
	row.flag.visible = sq.roe == SquadState.Roe.HOLD_FIRE
	row.tooltip_text = "%s · %s · %s · %s formation%s" % [sq.squad_name, st.text.capitalize(), sq.roe_name(), sq.formation_name(),
		" · in an operation" if sq.op_id >= 0 else ""]


## What a squad is doing, for every RTS surface (roster, command panel, field tag): an icon, one
## short uppercase word or two, the status colour, and whether it is in contact. Combat state
## (engaged, under fire) wins over the order, a blocked route over the order. brief: a tactic
## without its phase (the roster's narrow column).
static func squad_status(p_sim: WorldSim, sq: SquadState, brief := false) -> Dictionary:
	var fighting := 0
	var under_fire := 0
	for id in sq.members:
		var u := p_sim.state.get_unit(id)
		if u == null:
			continue
		if u.ai_state == UnitState.AiState.ENGAGING:
			fighting += 1
		if u.under_fire_until >= p_sim.state.time:
			under_fire += 1
	if fighting > 0:
		return {"icon": &"engaged", "text": "ENGAGED", "color": FNUI.DANGER, "engaged": true}
	if under_fire > 0:
		return {"icon": &"under_fire", "text": "UNDER FIRE", "color": FNUI.ALERT, "engaged": true}
	if sq.status == SquadState.Status.PARTIAL:
		return {"icon": &"blocked", "text": "BLOCKED", "color": FNUI.ALERT, "engaged": false}
	if sq.tactic != SquadState.Tactic.NONE:
		var what := sq.tactic_name() if brief else p_sim.tactics.short_text(sq)
		return {"icon": TACTIC_ICONS.get(sq.tactic, &"tactic"), "text": what.to_upper(), "color": FNUI.INFO, "engaged": false}
	match sq.order:
		SquadState.Order.MOVE:
			if sq.status == SquadState.Status.MOVING:
				return {"icon": &"moving", "text": "MOVING", "color": FNUI.OK, "engaged": false}
			return {"icon": &"move", "text": "ARRIVED", "color": FNUI.NEUTRAL, "engaged": false}
		SquadState.Order.HOLD:
			return {"icon": &"hold", "text": "HOLD", "color": FNUI.NEUTRAL, "engaged": false}
		SquadState.Order.FOLLOW:
			return {"icon": &"follow", "text": "FOLLOW", "color": FNUI.INFO, "engaged": false}
		SquadState.Order.REGROUP:
			return {"icon": &"regroup", "text": "REGROUP", "color": FNUI.INFO, "engaged": false}
	return {"icon": &"idle", "text": "IDLE", "color": FNUI.WARN, "engaged": false}


const TACTIC_ICONS := {
	SquadState.Tactic.DEFEND: &"defend", SquadState.Tactic.SUPPRESS: &"suppress", SquadState.Tactic.ASSAULT: &"assault",
	SquadState.Tactic.FLANK: &"flank", SquadState.Tactic.BOUND: &"bound", SquadState.Tactic.REPOSITION: &"move",
	SquadState.Tactic.WITHDRAW: &"withdraw", SquadState.Tactic.REGROUP: &"regroup",
}


## One line per squad as plain text (tests and logs read it).
func row_text(sq: SquadState) -> String:
	var order := sq.order_name().to_upper()
	if sq.tactic != SquadState.Tactic.NONE:
		order = sim.tactics.short_text(sq).to_upper()
	elif sq.order == SquadState.Order.FOLLOW:
		order = "FOLLOW"
	var fighting := 0
	var under_fire := 0
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u == null:
			continue
		if u.ai_state == UnitState.AiState.ENGAGING:
			fighting += 1
		if u.under_fire_until >= sim.state.time:
			under_fire += 1
	if order == "NONE":
		order = "IDLE"
	var state := "ENGAGED" if fighting > 0 else ("UNDER FIRE" if under_fire > 0 else order)
	if sq.status == SquadState.Status.PARTIAL:
		state = "BLOCKED"
	var effective := maxi(0, sq.members.size() - sq.fallen.size())
	var mark := "◆" if fighting > 0 or under_fire > 0 else "●"
	return "%s  %d/%d   %s %s" % [sq.squad_name.to_upper(), effective, sq.members.size(), mark, state]

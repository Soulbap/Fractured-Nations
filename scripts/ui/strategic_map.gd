## The strategic map (WORLD-SANDBOX-01, readability pass WORLD-SANDBOX-01B): the whole
## 20 x 20 km world from above, for commanding the player's faction. It is a view of the
## same WorldState as the RTS and FPS cameras, not a separate simulation: markers are
## drawn from unit, squad, objective and operation records, and every order goes through
## WarSim / SquadControl.
##
## Shows the terrain (the world's own macro preview), territory (each objective's area of
## control in its owner's colour), objectives with owner, capture progress, contested and
## threatened state, the player's squads, enemy forces the player's faction knows about
## (WarSim intelligence - never every enemy), and the player's operations with routes.
##
## Positions are never moved for display. Every squad marker is drawn where the squad
## really is (the centre of its living soldiers). When markers would overlap on screen
## they are drawn as one group marker at the group's real centre, with the number of
## squads and soldiers; zooming in separates them as soon as their real distance allows.
## Three levels of detail follow the zoom smoothly:
##   strategic   (whole map)  compact markers, squads standing at an objective are shown
##                            as a garrison badge on that objective;
##   operational (a few km)   individual squad symbols with names, routes, labels;
##   close       (a base)     squads at their positions plus every soldier as a dot.
##
## The tactical (RTS) camera is drawn where it is, with a faint wedge showing where it
## looks (its horizontal field of view); this is the player's camera, not anybody's sight.
##
## Controls (H shows them on the map): wheel zoom towards the cursor; middle-drag or WASD
## pan, a middle click (no drag) moves the tactical camera there; Home whole map; LMB select (drag = box, Shift adds, double-click a group zooms
## in); RMB order the selected squads (enemy / neutral objective = attack, own = reinforce,
## ground = move); buttons for the other orders; G (or "View") jumps the tactical camera
## there; , and . change the time compression; M / Esc close.
class_name StrategicMap
extends Control

signal closed

var sim: WorldSim
var demo: CoreDemo
var faction := 0
## World metres per screen pixel = 1 / zoom; view_center in world x / z. Setting zoom
## from outside jumps there; the wheel animates towards _zoom_target.
var zoom := 0.04:
	set(v):
		zoom = v
		if not _zoom_anim:
			_zoom_target = v
		queue_redraw()
var view_center := Vector2.ZERO:
	set(v):
		view_center = v
		queue_redraw()
var selected_squads: Array[int] = []
var selected_objective := -1
var selected_op := -1
## LOGISTICS-01: selected vehicles and facility (structure id).
var selected_vehicles: Array[int] = []
var selected_structure := -1
## Order waiting for a click on the map (from the Attack / Defend / Reinforce / Move
## buttons), -1 = none.
var pending_order := -1
var show_help := false
## AI-OBS-01 developer inspector: the faction whose picture is shown (-1 off), whether the
## true positions of all squads are drawn as well (clearly marked, never normal information),
## and the squad inspected on the map (any faction while the truth layer is on).
var dbg_faction := -1
var dbg_truth := false
var dbg_squad := -1
var half := 10000.0
const PANEL_W := 360.0
const ZOOM_MAX := 2.0
## Zoom (pixels per metre) where the levels of detail change.
const OPERATIONAL_ZOOM := 0.09
const CLOSE_ZOOM := 0.45
const TERRITORY_RES := 256

var _bg: Texture2D
var _territory: ImageTexture
var _territory_key := ""
## Territory cells -> index of the nearest objective in reach (-1 none); geometry only,
## built once - an ownership change only recolours.
var _cell_objective := PackedInt32Array()
var _cell_objs: Array = []
var _zoom_target := 0.04
var _zoom_anim := false
var _zoom_anchor := Vector2.INF
var _zoom_min := 0.03
var _drag_from := Vector2.INF
var _pan_from := Vector2.INF
## Middle button: where it went down, and whether it moved far enough to be a drag.
var _mid_press := Vector2.INF
var _mid_dragged := false
## A middle press that moves less than this (px) is a click, not a pan.
const MIDDLE_CLICK_PX := 5.0
var _box := false
var _last_real_us := 0
var _redraw_t := 0.0
## Squad groups of the last draw (screen positions, members), for clicks.
var _groups: Array = []
## Operation label rectangles of the last draw: op id -> Rect2.
var _op_rects := {}
## Screen rectangles already taken by labels and markers in this draw (label placement).
var _taken: Array[Rect2] = []
var _ops_box: VBoxContainer
var _buttons := {}
var _panel_bg: PanelContainer

const COL_ATTACK := Color(1.0, 0.45, 0.35)
const COL_REINFORCE := Color(0.55, 0.95, 0.55)
const COL_MOVE := Color(0.85, 0.9, 1.0)
const COL_SELECT := Color(0.92, 0.95, 0.90)
const COL_THREAT := Color(1.0, 0.3, 0.25)
const COL_CONTESTED := Color(1.0, 0.82, 0.2)


func setup(p_demo: CoreDemo) -> void:
	demo = p_demo
	sim = demo.sim
	faction = sim.state.war.player_faction
	half = demo.config.half_size()
	var path := "res://worlds/%s/source/preview_macro.png" % demo.config.world_name
	if ResourceLoader.exists(path):
		_bg = load(path)
	_build_panel()
	fit_all()


func _ready() -> void:
	# WORLD-PLAYTEST-01: the map covers the whole window, so the 3D world is not drawn
	# while it is open (frame time goes to the simulation when time is compressed).
	visibility_changed.connect(func() -> void:
		if is_inside_tree():
			get_viewport().disable_3d = is_visible_in_tree())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	# Smooth territory borders and background when zoomed in.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## Whole map in view.
func _panel_active() -> bool:
	return not selected_squads.is_empty() or selected_objective >= 0 or selected_op >= 0 or not selected_vehicles.is_empty() or selected_structure >= 0


## UI-01C: the panels lie over the map's empty sides (the map is square, the window wide), so the map
## keeps its place and scale when the inspector opens.
func _panel_width() -> float:
	return 0.0


func fit_all() -> void:
	var vs := get_viewport_rect().size if is_inside_tree() else Vector2(1600, 900)
	zoom = minf((vs.x - _panel_width() - 40.0) / (half * 2.0), (vs.y - 60.0) / (half * 2.0))
	_zoom_min = zoom * 0.85
	view_center = Vector2(0.0, 0.0)


func map_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size.x - _panel_width(), size.y))


func to_screen(p: Vector3) -> Vector2:
	return map_rect().get_center() + (Vector2(p.x, p.z) - view_center) * zoom


func _to_world2(s: Vector2) -> Vector2:
	return view_center + (s - map_rect().get_center()) / zoom


func to_world(s: Vector2) -> Vector3:
	var w := _to_world2(s)
	var h: float = sim.terrain.data.get_height(Vector3(w.x, 0, w.y)) if sim.terrain else 0.0
	return Vector3(w.x, 0.0 if is_nan(h) else h, w.y)


## 0 strategic, 1 operational, 2 close.
func detail_level() -> int:
	return 0 if zoom < OPERATIONAL_ZOOM else (1 if zoom < CLOSE_ZOOM else 2)


## Animated zoom by `factor` keeping the world point under `anchor` (screen) in place.
func zoom_by(factor: float, anchor: Vector2) -> void:
	_zoom_target = clampf(_zoom_target * factor, _zoom_min, ZOOM_MAX)
	_zoom_anchor = anchor


func _process(_delta: float) -> void:
	if not visible:
		_last_real_us = 0
		return
	# Real time: time compression must not speed up panning or zooming.
	var now_us := Time.get_ticks_usec()
	var dt := clampf((now_us - _last_real_us) / 1.0e6, 0.0, 0.1) if _last_real_us > 0 else 0.016
	_last_real_us = now_us
	var moved := false
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1
	if pan != Vector2.ZERO and has_focus():
		view_center += pan * dt * 600.0 / zoom
		moved = true
	if absf(zoom - _zoom_target) > _zoom_target * 0.002:
		var anchor := _zoom_anchor if _zoom_anchor.is_finite() else map_rect().get_center()
		var before := _to_world2(anchor)
		_zoom_anim = true
		zoom = exp(lerpf(log(zoom), log(_zoom_target), 1.0 - exp(-dt * 14.0)))
		_zoom_anim = false
		view_center += before - _to_world2(anchor)
		moved = true
	elif zoom != _zoom_target:
		_zoom_anim = true
		zoom = _zoom_target
		_zoom_anim = false
	var clamped := view_center.clamp(Vector2(-half, -half), Vector2(half, half))
	if clamped != view_center:
		view_center = clamped
	_redraw_t -= dt
	if _redraw_t <= 0.0:
		_redraw_t = 0.1
		_refresh_panel()
		moved = true
	if moved or _box:
		queue_redraw()


func _selection_text() -> String:
	var war := sim.state.war
	var lines: Array[String] = []
	var op := war.operation(selected_op)
	if op:
		return _operation_text(op)
	if not selected_vehicles.is_empty() or selected_structure >= 0:
		var vl: Array[String] = []
		for vid in selected_vehicles:
			var vu := sim.state.get_unit(vid)
			if vu and vu.veh:
				vl.append("[b]%s[/b]  %s" % [vu.unit_name, sim.vehicles.describe(vu)])
		var st := sim.logistics.structure(selected_structure)
		if st:
			vl.append("[b]%s[/b]  %s" % [sim.logistics.store_name(st), st.inventory.summary() if st.inventory else ""])
			if st.base_id >= 0:
				vl.append(sim.logistics.bases.describe(st.base_id))
		if not selected_squads.is_empty():
			vl.append("%d squad(s) selected too: RMB = transport them there" % selected_squads.size())
		return "\n".join(vl)
	if not selected_squads.is_empty():
		var n := 0
		var rows: Array[String] = []
		for sid in selected_squads:
			var sq := sim.state.get_squad(sid)
			if sq == null:
				continue
			n += sq.members.size()
			if rows.size() < 5:
				rows.append("  %s  %d soldiers · %s" % [sq.squad_name, sq.members.size(), _squad_status(sq)])
		lines.append("[b]Selected: %d squad%s, %d soldiers[/b]" % [selected_squads.size(), "" if selected_squads.size() == 1 else "s", n])
		lines.append_array(rows)
		if selected_squads.size() > 5:
			lines.append("  ... and %d more" % (selected_squads.size() - 5))
		var o := war.objective(selected_objective)
		if o:
			lines.append("Target: [b]%s[/b] (%s)" % [o.obj_name, _owner_text(o)])
		return "\n".join(lines)
	var obj := war.objective(selected_objective)
	if obj:
		lines.append("[b]%s[/b]  %s, value %d" % [obj.obj_name, obj.kind, obj.value])
		lines.append("Owner: %s" % _owner_text(obj))
		if obj.contested:
			lines.append("[color=#ffd040]CONTESTED - fighting inside, capture paused[/color]")
		elif _threatened(obj):
			lines.append("[color=#ff6a5a]THREATENED - enemy forces reported nearby[/color]")
		if obj.capture_faction >= 0:
			lines.append("Being taken by %s: %d %%" % [_fac(obj.capture_faction), int(obj.capture_progress * 100)])
		var own: int = obj.presence.get(faction, 0)
		lines.append("Your soldiers there: %d · enemies reported near: %d" % [own, sim.war.threat_near(faction, obj.position, obj.radius + 400.0)])
		return "\n".join(lines)
	return "[color=#aab]Nothing selected.[/color]"


func _hint_text() -> String:
	if pending_order >= 0:
		var what := "a point on the map" if pending_order == OperationState.Type.MOVE else "an objective"
		return "%s: click %s. RMB or Esc cancels." % [OperationState.TYPE_NAMES[pending_order], what]
	if not selected_squads.is_empty():
		if selected_objective >= 0:
			return "Choose Attack, Defend or Reinforce for the target, or RMB anywhere for the default order."
		return "RMB: enemy or neutral objective = attack, own = reinforce, ground = move. Click an objective to make it the target."
	if selected_op >= 0:
		return "View (G) jumps to its squads. Cancel releases them."
	if not selected_vehicles.is_empty():
		return "RMB: drive there (by road where possible). With squads selected too: they board and are driven. G: show it in the tactical view."
	return "Click a squad, vehicle or facility, or drag a box around several. Click an objective or an operation for details."


func _squad_status(sq: SquadState) -> String:
	var op := sim.state.war.operation(sq.op_id)
	var parts: Array[String] = []
	if op:
		parts.append("%s #%d (%s)" % [op.type_name(), op.id, op.phase_name()])
	elif sq.station_objective >= 0 and sim.state.war.objective(sq.station_objective):
		parts.append("garrison %s" % sim.state.war.objective(sq.station_objective).obj_name)
	else:
		parts.append(sq.order_name().to_lower() if sq.order != SquadState.Order.NONE else "idle")
	if _fighting(sq):
		parts.append("[color=#ff8a70]in contact[/color]")
	return ", ".join(parts)


func _owner_text(o: ObjectiveState) -> String:
	return (_fac(o.owner) + (" (you)" if o.owner == faction else "")) if o.owner >= 0 else "neutral"


## Details of one operation: target, squads and strength, phase, march progress with an
## arrival estimate only when the measured progress supports one, and the outcome.
func _operation_text(op: OperationState) -> String:
	var war := sim.state.war
	var obj := war.objective(op.target_objective)
	var lines: Array[String] = []
	var target := obj.obj_name if obj else "point (%.1f, %.1f) km" % [op.target_pos.x / 1000.0, op.target_pos.z / 1000.0]
	lines.append("[b]%s #%d → %s[/b]%s" % [op.type_name().to_upper(), op.id, target, "" if op.player_ordered else "  [color=#889](AI)[/color]"])
	var now := sim.state.time
	if not op.is_active():
		var col := "#90e090" if op.phase == OperationState.Phase.COMPLETED else ("#ff6060" if op.phase == OperationState.Phase.FAILED else "#bbbbbb")
		lines.append("[color=%s]%s[/color]: %s" % [col, op.phase_name().to_upper(), op.outcome])
		lines.append("Lasted %s · lost %d of %d soldiers" % [_dur(op.ended_at - op.started_at), op.losses, op.start_strength])
		return "\n".join(lines)
	lines.append("Phase: [b]%s[/b] for %s · %s" % [op.phase_name(), _dur(now - op.phase_since), _phase_meaning(op)])
	var soldiers := 0
	var names: Array[String] = []
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq:
			soldiers += sq.members.size()
			names.append("%s %d" % [sq.squad_name, sq.members.size()])
	lines.append("Squads: %s" % ", ".join(names))
	lines.append("Strength: %d of %d soldiers (%d lost)" % [soldiers, op.start_strength, op.losses])
	var mi := sim.war.march_info(op)
	if op.phase == OperationState.Phase.MOVING and mi.rem >= 0.0:
		var done: float = 1.0 - mi.rem / maxf(mi.total, 1.0)
		var eta := "arrival: estimating ..."
		if mi.eta >= 0.0:
			eta = "arrival in about %s" % _dur(ceilf(mi.eta / 60.0) * 60.0)
		elif now - op.started_at >= 20.0:
			eta = "arrival: unknown (%s)" % ("in contact" if Array(op.squads).any(func(s: int) -> bool: return _fighting(sim.state.get_squad(s))) else "halted or slowed")
		lines.append("March: %.1f of %.1f km left (%d %%) · %s" % [mi.rem / 1000.0, mi.total / 1000.0, int(done * 100.0), eta])
	if obj:
		var cap := ""
		if obj.capture_faction >= 0:
			cap = " · being taken by %s %d %%" % [_fac(obj.capture_faction), int(obj.capture_progress * 100)]
		lines.append("Target: %s%s%s" % [_owner_text(obj), "  [color=#ffd040]contested[/color]" if obj.contested else "", cap])
	return "\n".join(lines)


func _phase_meaning(op: OperationState) -> String:
	match op.phase:
		OperationState.Phase.MOVING:
			return "marching to the staging point" if op.type == OperationState.Type.ATTACK else "marching to the target"
		OperationState.Phase.ENGAGING:
			return "assaulting the objective"
		OperationState.Phase.SECURING:
			return "holding while it is captured" if op.type == OperationState.Type.ATTACK else "holding the objective"
	return ""


static func _dur(s: float) -> String:
	if s < 60.0:
		return "%d s" % int(s)
	if s < 3600.0:
		return "%d min" % int(s / 60.0)
	return "%d h %02d min" % [int(s / 3600.0), int(s / 60.0) % 60]


# --- Panels (UI-01C kit) --------------------------------------------------------------------------
#
# Left column: the command panel (side, war time and speed, every faction's objectives), the map
# layers, and the operations with the last few events. Right: the inspector, only while something is
# selected - a header, the facts as fields and meters, the orders as buttons and a one-line hint.
# Bottom centre: the map keys. The map itself fills the window behind them and keeps its proportions.

const COLUMN_W := 214.0
const INSPECTOR_W := 252.0
## Map layers the player can switch (each one is drawn by its own pass in _draw).
const LAYERS := [
	["territory", &"territory", "Territory"], ["objectives", &"objective", "Objectives"], ["friendly", &"soldiers", "Friendly forces"],
	["contacts", &"contact", "Enemy contacts"], ["operations", &"operation", "Operations"], ["logistics", &"vehicle", "Logistics & bases"],
	["camera", &"drive", "Tactical camera"], ["grid", &"layers", "Grid"],
]
var layers := {"territory": true, "objectives": true, "friendly": true, "contacts": true, "operations": true, "logistics": true, "camera": true, "grid": true}

var _cmd_panel: FNPanel
var _cmd_rows: VBoxContainer
var _clock: FNStatusIndicator
var _layer_buttons := {}
var _ops_panel: FNPanel
var _ops_head: FNSectionHeader
var _events: VBoxContainer
var _insp: FNPanel
var _insp_box: VBoxContainer
var _insp_sig := ""
var _insp_cmds: GridContainer
var _insp_hint: Label
var _keys: FNPanel


func _build_panel() -> void:
	theme = FNUI.theme()
	# Command panel.
	_cmd_panel = FNPanel.new(WorldState.faction_color(faction), FNUI.S4)
	_cmd_panel.custom_minimum_size = Vector2(COLUMN_W, 0)
	add_child(_cmd_panel)
	var cv := VBoxContainer.new()
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_theme_constant_override("separation", FNUI.S3)
	_cmd_panel.add_child(cv)
	var head := FNSectionHeader.new("Command", "you", FNUI.INK)
	head.add_chip(WorldState.faction_name(faction), WorldState.faction_color(faction))
	cv.add_child(head)
	_clock = FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
	cv.add_child(_clock)
	_cmd_rows = VBoxContainer.new()
	_cmd_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cmd_rows.add_theme_constant_override("separation", FNUI.S2)
	cv.add_child(_cmd_rows)
	# Layers.
	_header_panel_layers()
	# Operations and recent events.
	_ops_panel = FNPanel.new(Color.TRANSPARENT, FNUI.S4)
	_ops_panel.custom_minimum_size = Vector2(COLUMN_W, 0)
	add_child(_ops_panel)
	var ov := VBoxContainer.new()
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_theme_constant_override("separation", FNUI.S3)
	_ops_panel.add_child(ov)
	_ops_head = FNSectionHeader.new("Operations", "", FNUI.INK)
	ov.add_child(_ops_head)
	_ops_box = VBoxContainer.new()
	_ops_box.add_theme_constant_override("separation", FNUI.S2)
	ov.add_child(_ops_box)
	ov.add_child(FNSectionHeader.new("Recent", "", FNUI.INK_3))
	_events = VBoxContainer.new()
	_events.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_events.add_theme_constant_override("separation", 1)
	ov.add_child(_events)
	# Inspector.
	_insp = FNPanel.new(Color.TRANSPARENT, FNUI.S4)
	_insp.custom_minimum_size = Vector2(INSPECTOR_W, 0)
	_panel_bg = _insp
	add_child(_insp)
	var iv := VBoxContainer.new()
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_theme_constant_override("separation", FNUI.S3)
	_insp.add_child(iv)
	_insp_box = VBoxContainer.new()
	_insp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_insp_box.add_theme_constant_override("separation", FNUI.S2)
	iv.add_child(_insp_box)
	_insp_cmds = GridContainer.new()
	_insp_cmds.columns = 3
	_insp_cmds.add_theme_constant_override("h_separation", FNUI.S2)
	_insp_cmds.add_theme_constant_override("v_separation", FNUI.S2)
	iv.add_child(_insp_cmds)
	for b: Array in [["attack", &"assault", "Attack", "", "Attack an objective: click it (or select it first)"],
			["defend", &"defend", "Defend", "", "Defend an objective"],
			["reinforce", &"recruit", "Reinforce", "", "Reinforce an own objective"],
			["move", &"move", "Move", "RMB", "Move to a point on the map"],
			["cancel", &"blocked", "Cancel", "", "Cancel the operation and release its squads"],
			["view", &"drive", "View", "G", "Show the selection in the tactical view"]]:
		var btn := FNCommandButton.new(b[1], b[2], b[3], b[4])
		btn.custom_minimum_size = Vector2(0, 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = b[0]
		btn.pressed.connect(func() -> void: _button(key))
		_insp_cmds.add_child(btn)
		_buttons[key] = btn
	_insp_hint = FNUI.label("", FNUI.CAPTION, FNUI.INK_2, "body")
	_insp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_hint.custom_minimum_size = Vector2(INSPECTOR_W - 2 * FNUI.S4, 0)
	iv.add_child(_insp_hint)
	# Keys, bottom centre.
	_keys = FNPanel.new(Color.TRANSPARENT, FNUI.S3)
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kh := HBoxContainer.new()
	kh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kh.add_theme_constant_override("separation", FNUI.S5)
	for k: Array in [["LMB", "Select"], ["RMB", "Order"], ["Wheel", "Zoom"], ["MMB", "Pan / camera"], ["Home", "Whole map"], ["H", "Controls"], ["M", "Close"]]:
		kh.add_child(FNKeyHint.new(k[0], k[1]))
	_keys.add_child(kh)
	add_child(_keys)


func _header_panel_layers() -> void:
	var lp := FNPanel.new(Color.TRANSPARENT, FNUI.S4)
	lp.custom_minimum_size = Vector2(COLUMN_W, 0)
	lp.name = "Layers"
	add_child(lp)
	var lv := VBoxContainer.new()
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_theme_constant_override("separation", FNUI.S2)
	lp.add_child(lv)
	lv.add_child(FNSectionHeader.new("Map layers", "", FNUI.INK))
	for l: Array in LAYERS:
		var key: String = l[0]
		var b := FNCategoryTile.new(l[1], l[2], "")
		b.custom_minimum_size = Vector2(0, 19)
		b.selected = layers[key]
		b.count_label.text = "ON" if layers[key] else "OFF"
		b.pressed.connect(func() -> void: set_layer(key, not layers[key]))
		lv.add_child(b)
		_layer_buttons[key] = b


## Switches a map layer (presentation only; nothing in the simulation depends on it).
func set_layer(key: String, on: bool) -> void:
	layers[key] = on
	var b: FNCategoryTile = _layer_buttons.get(key)
	if b:
		b.selected = on
		b.count_label.text = "ON" if on else "OFF"
	queue_redraw()


func _layout_panels() -> void:
	var vs := size
	var y := float(FNUI.EDGE)
	_cmd_panel.size = Vector2.ZERO
	_cmd_panel.position = Vector2(FNUI.EDGE, y)
	y += _cmd_panel.size.y + FNUI.S3
	var lp: Control = get_node("Layers")
	lp.size = Vector2.ZERO
	lp.position = Vector2(FNUI.EDGE, y)
	y += lp.size.y + FNUI.S3
	_ops_panel.size = Vector2.ZERO
	_ops_panel.position = Vector2(FNUI.EDGE, maxf(y, vs.y - _ops_panel.size.y - FNUI.EDGE))
	_insp.size = Vector2.ZERO
	_insp.position = Vector2(vs.x - _insp.size.x - FNUI.EDGE, FNUI.EDGE)
	_keys.size = Vector2.ZERO
	_keys.position = Vector2(roundf((vs.x - _keys.size.x) * 0.5), vs.y - _keys.size.y - FNUI.EDGE)
	_keys.visible = not show_help


func _refresh_panel() -> void:
	_layout_panels()
	var panel_was_visible := _insp.visible
	_insp.visible = _panel_active()
	if panel_was_visible != _insp.visible:
		queue_redraw()
	var war := sim.state.war
	var t := sim.state.time
	_clock.set_status(&"clock", "War time %d:%02d  ·  speed %s" % [int(t / 3600.0), int(t / 60.0) % 60, TimeCompression.label()], FNUI.INK_2)
	_clock.text_label.uppercase = false
	var rows := []
	for f: FactionState in war.factions.values():
		var objs := war.owned_by(f.id).size()
		if f.id == faction:
			var soldiers := 0
			for sq: SquadState in sim.war.squads_of(f.id):
				soldiers += sq.members.size()
			rows.append([f.id, f.faction_name, "%d obj" % objs, "%d soldiers · %d reserve · %d fallen" % [soldiers, f.reserves, f.casualties]])
		else:
			rows.append([f.id, f.faction_name, "%d obj" % objs, "AI · %s" % sim.war.profile(f).display_name.to_lower()])
	var key := str(rows)
	if _cmd_rows.get_meta("key", "") != key:
		_cmd_rows.set_meta("key", key)
		for c in _cmd_rows.get_children():
			c.queue_free()
		for r: Array in rows:
			var h := HBoxContainer.new()
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_theme_constant_override("separation", FNUI.S3)
			var e := FNUnitEmblem.new(Vector2(14, 9))
			e.kind = &"none"
			e.color = WorldState.faction_color(r[0])
			h.add_child(e)
			var v := VBoxContainer.new()
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_theme_constant_override("separation", -2)
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var top := HBoxContainer.new()
			top.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var n := FNUI.label(r[1], FNUI.LABEL, WorldState.faction_color(r[0]).lightened(0.35), "caps")
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top.add_child(n)
			top.add_child(FNUI.label(r[2], FNUI.LABEL, FNUI.INK, "number"))
			v.add_child(top)
			v.add_child(FNUI.label(r[3], FNUI.CAPTION, FNUI.INK_3, "body"))
			h.add_child(v)
			_cmd_rows.add_child(h)
	_refresh_inspector()
	_refresh_ops()
	_refresh_events()
	var has_sel := not selected_squads.is_empty()
	for k in ["attack", "defend", "reinforce", "move"]:
		(_buttons[k] as FNCommandButton).visible = has_sel
		(_buttons[k] as FNCommandButton).set_enabled(has_sel)
		(_buttons[k] as FNCommandButton).armed = pending_order == {"attack": OperationState.Type.ATTACK, "defend": OperationState.Type.DEFEND,
			"reinforce": OperationState.Type.REINFORCE, "move": OperationState.Type.MOVE}[k]
	var op := war.operation(selected_op)
	var can_cancel: bool = (op and op.is_active()) or selected_squads.any(func(s: int) -> bool:
		var sq := sim.state.get_squad(s)
		return sq != null and sq.op_id >= 0)
	(_buttons["cancel"] as FNCommandButton).set_enabled(can_cancel)
	(_buttons["cancel"] as FNCommandButton).visible = has_sel or op != null
	(_buttons["view"] as FNCommandButton).set_enabled(has_sel or selected_objective >= 0 or op != null or not selected_vehicles.is_empty() or selected_structure >= 0)
	_insp_hint.text = _hint_text()


## The inspector's content as a list of specs; rebuilt only when it changes.
func _refresh_inspector() -> void:
	if not _insp.visible:
		return
	var spec := _inspector_spec()
	var sig := str(spec)
	if sig == _insp_sig:
		return
	_insp_sig = sig
	# Out of the box at once (a freed-later child would still count towards the panel's height).
	for c in _insp_box.get_children():
		_insp_box.remove_child(c)
		c.queue_free()
	for it: Array in spec:
		match it[0]:
			"head":
				var h := HBoxContainer.new()
				h.mouse_filter = Control.MOUSE_FILTER_IGNORE
				h.add_theme_constant_override("separation", FNUI.S3)
				var frame := PanelContainer.new()
				frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
				frame.custom_minimum_size = Vector2(30, 26)
				frame.add_theme_stylebox_override("panel", FNUI.box(Color(it[4], 0.16), Color(it[4], 0.8), 1, 2, 0))
				frame.add_child(FNIcons.rect(it[1], FNUI.ICON_M, Color(it[4]).lightened(0.4)))
				h.add_child(frame)
				var v := VBoxContainer.new()
				v.mouse_filter = Control.MOUSE_FILTER_IGNORE
				v.add_theme_constant_override("separation", -1)
				v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var tl := FNUI.label(it[2], FNUI.TITLE, FNUI.INK, "title")
				tl.clip_text = true
				tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				v.add_child(tl)
				var sl := FNUI.label(it[3], FNUI.CAPTION, FNUI.INK_2, "caps")
				sl.clip_text = true
				sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				v.add_child(sl)
				h.add_child(v)
				_insp_box.add_child(h)
			"status":
				var s := FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
				s.set_status(it[1], it[2], it[3])
				_insp_box.add_child(s)
			"field":
				var f := FNField.new(it[1], "", it[3], 64.0)
				f.set_value(it[2], it[4])
				_insp_box.add_child(f)
			"meter":
				var m := FNMeter.new(it[1], it[4])
				m.custom_minimum_size = Vector2(INSPECTOR_W - 2 * FNUI.S4, 11)
				m.value_w = 44.0
				m.set_value(it[2], it[3], it[4])
				_insp_box.add_child(m)
			"section":
				_insp_box.add_child(FNSectionHeader.new(it[1], it[2] if it.size() > 2 else "", FNUI.INK_3))
			"text":
				var l := FNUI.label(it[1], FNUI.CAPTION, it[2], "body")
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size = Vector2(INSPECTOR_W - 2 * FNUI.S4, 0)
				_insp_box.add_child(l)
	_insp.size = Vector2.ZERO


## What the inspector shows for the selection: an operation, vehicles / a facility (with its base),
## squads, or an objective. Only data the records hold.
func _inspector_spec() -> Array:
	var war := sim.state.war
	var out := []
	var op := war.operation(selected_op)
	if op:
		var obj := war.objective(op.target_objective)
		var target := obj.obj_name if obj else "point %.1f, %.1f km" % [op.target_pos.x / 1000.0, op.target_pos.z / 1000.0]
		out.append(["head", &"operation", "%s → %s" % [op.type_name(), target], "Operation #%d%s" % [op.id, "" if op.player_ordered else " · AI"], _op_color(op)])
		if not op.is_active():
			var col := FNUI.OK if op.phase == OperationState.Phase.COMPLETED else (FNUI.DANGER if op.phase == OperationState.Phase.FAILED else FNUI.INK_2)
			out.append(["status", &"check" if op.phase == OperationState.Phase.COMPLETED else &"blocked", op.phase_name(), col])
			out.append(["text", op.outcome, FNUI.INK_2])
			out.append(["field", "Lasted", _dur(op.ended_at - op.started_at), &"clock", FNUI.INK])
			out.append(["field", "Losses", "%d of %d soldiers" % [op.losses, op.start_strength], &"soldiers", FNUI.INK])
			return out
		var now := sim.state.time
		out.append(["status", &"tactic", "%s · %s" % [op.phase_name(), _dur(now - op.phase_since)], FNUI.INFO])
		out.append(["text", _phase_meaning(op).capitalize() if _phase_meaning(op) != "" else "", FNUI.INK_2])
		var soldiers := 0
		var names: Array[String] = []
		for sid in op.squads:
			var sq := sim.state.get_squad(sid)
			if sq:
				soldiers += sq.members.size()
				names.append("%s %d" % [sq.squad_name, sq.members.size()])
		out.append(["field", "Squads", ", ".join(names), &"soldiers", FNUI.INK])
		out.append(["meter", "Strength", float(soldiers) / maxf(op.start_strength, 1.0), "%d / %d" % [soldiers, op.start_strength],
			FNUI.OK if op.losses == 0 else FNUI.WARN])
		var mi := sim.war.march_info(op)
		if op.phase == OperationState.Phase.MOVING and mi.rem >= 0.0:
			var done: float = 1.0 - mi.rem / maxf(mi.total, 1.0)
			out.append(["meter", "March", done, "%.1f km left" % (mi.rem / 1000.0), FNUI.INFO])
			var eta := "estimating …"
			if mi.eta >= 0.0:
				eta = "about %s" % _dur(ceilf(mi.eta / 60.0) * 60.0)
			elif now - op.started_at >= 20.0:
				eta = "unknown (%s)" % ("in contact" if Array(op.squads).any(func(s: int) -> bool: return _fighting(sim.state.get_squad(s))) else "halted or slowed")
			out.append(["field", "Arrival", eta, &"clock", FNUI.INK])
		if obj:
			out.append(["field", "Target", _owner_plain(obj) + ("  ·  contested" if obj.contested else ""), &"objective", FNUI.WARN if obj.contested else FNUI.INK])
			if obj.capture_faction >= 0:
				out.append(["meter", "Capture", obj.capture_progress, "%d %%" % int(obj.capture_progress * 100), WorldState.faction_color(obj.capture_faction)])
		return out
	if not selected_vehicles.is_empty() or selected_structure >= 0:
		for vid in selected_vehicles.slice(0, 3):
			var vu := sim.state.get_unit(vid)
			if vu == null or vu.veh == null:
				continue
			var d := vu.veh.def()
			out.append(["head", &"vehicle", vu.unit_name, d.display_name, FNUI.INFO])
			out.append(["status", &"moving" if vu.order == UnitState.Order.MOVE else &"idle", vu.veh.status_name() + ((" · " + vu.veh.reason) if vu.veh.reason != "" else ""),
				FNUI.OK if vu.veh.reason == "" else FNUI.ALERT])
			out.append(["meter", "Fuel", vu.veh.fuel / maxf(d.fuel_capacity, 1.0), "%d l" % roundi(vu.veh.fuel), FNUI.INFO])
			out.append(["meter", "Cargo", vu.veh.cargo.total() / maxf(vu.veh.cargo.capacity, 1.0), "%d / %d" % [roundi(vu.veh.cargo.total()), roundi(vu.veh.cargo.capacity)], FNUI.NEUTRAL])
			if not vu.veh.job.is_empty():
				out.append(["field", "Job", sim.logistics.describe_job(vu), &"route", FNUI.ARMED])
		if selected_vehicles.size() > 3:
			out.append(["text", "… and %d more vehicles" % (selected_vehicles.size() - 3), FNUI.INK_2])
		var st := sim.logistics.structure(selected_structure)
		if st:
			var b := sim.logistics.bases.summary(st.base_id) if st.base_id >= 0 else {}
			out.append(["head", &"base" if not b.is_empty() else &"logistics", sim.logistics.store_name(st), ("%s · %s" % [b.name, b.kind]) if not b.is_empty() else "Facility",
				WorldState.faction_color(st.faction)])
			if st.inventory:
				out.append(["meter", "Store", st.inventory.total() / maxf(st.inventory.capacity, 1.0), "%d / %d" % [roundi(st.inventory.total()), roundi(st.inventory.capacity)], FNUI.NEUTRAL])
			if not b.is_empty():
				out.append(["section", "Base", b.name])
				var n := 0
				for k in b.facilities:
					n += int(b.facilities[k])
				out.append(["field", "Buildings", "%d · %d beds · %d bays" % [n, b.capacity, b.parking], &"building", FNUI.INK])
				out.append(["field", "Garrison", "%d soldiers · %d vehicles" % [b.soldiers, b.vehicles.size()], &"soldiers", FNUI.INK])
				out.append(["field", "Stock", "ammo %d kg · fuel %d l · supplies %d kg" % [roundi(b.stock.ammo), roundi(b.stock.fuel), roundi(b.stock.supplies)], &"cargo", FNUI.INK])
				for a: String in b.activities.slice(0, 3):
					out.append(["text", a, FNUI.ARMED])
		if not selected_squads.is_empty():
			out.append(["text", "%d squad(s) selected too: RMB = transport them there" % selected_squads.size(), FNUI.INFO])
		return out
	if not selected_squads.is_empty():
		var n := 0
		var alive := 0
		for sid in selected_squads:
			var sq := sim.state.get_squad(sid)
			if sq:
				n += sq.members.size() + sq.fallen.size()
				alive += sq.members.size()
		var first := sim.state.get_squad(selected_squads[0])
		var title := first.squad_name if selected_squads.size() == 1 and first else "%d squads" % selected_squads.size()
		out.append(["head", &"infantry", title, "Infantry · %d soldiers" % alive, WorldState.faction_color(faction)])
		if selected_squads.size() == 1 and first:
			var st := SquadPanel.squad_status(sim, first)
			out.append(["status", st.icon, st.text, st.color])
			out.append(["field", "Task", _squad_plain(first), &"operation", FNUI.INK])
			out.append(["meter", "Strength", float(alive) / maxf(n, 1.0), "%d / %d" % [alive, n], FNUI.OK if alive == n else FNUI.WARN])
		else:
			for sid in selected_squads.slice(0, 5):
				var sq := sim.state.get_squad(sid)
				if sq:
					out.append(["field", sq.squad_name, "%d · %s" % [sq.members.size(), _squad_plain(sq)], &"", FNUI.INK])
			if selected_squads.size() > 5:
				out.append(["text", "… and %d more" % (selected_squads.size() - 5), FNUI.INK_2])
		var o := war.objective(selected_objective)
		if o:
			out.append(["field", "Target", "%s (%s)" % [o.obj_name, _owner_plain(o)], &"objective", FNUI.ARMED])
		return out
	var obj2 := war.objective(selected_objective)
	if obj2:
		var col := WorldState.faction_color(obj2.owner) if obj2.owner >= 0 else FNUI.NEUTRAL
		out.append(["head", &"hq" if obj2.kind == &"hq" else (&"bridge" if obj2.kind == &"bridge" else &"objective"), obj2.obj_name,
			"%s · value %d" % [String(obj2.kind), obj2.value], col])
		out.append(["field", "Owner", _owner_plain(obj2), &"territory", col.lightened(0.3)])
		if obj2.contested:
			out.append(["status", &"engaged", "Contested · capture paused", FNUI.WARN])
		elif _threatened(obj2):
			out.append(["status", &"under_fire", "Threatened · enemy reported nearby", FNUI.ALERT])
		else:
			out.append(["status", &"check", "Quiet", FNUI.OK])
		if obj2.capture_faction >= 0:
			out.append(["meter", "Capture", obj2.capture_progress, "%d %%" % int(obj2.capture_progress * 100), WorldState.faction_color(obj2.capture_faction)])
		out.append(["field", "Your troops", "%d soldiers there" % int(obj2.presence.get(faction, 0)), &"soldiers", FNUI.INK])
		out.append(["field", "Enemy", "%d reported near" % sim.war.threat_near(faction, obj2.position, obj2.radius + 400.0), &"contact", FNUI.INK])
	return out


func _owner_plain(o: ObjectiveState) -> String:
	return (WorldState.faction_name(o.owner) + (" (you)" if o.owner == faction else "")) if o.owner >= 0 else "neutral"


func _squad_plain(sq: SquadState) -> String:
	var op := sim.state.war.operation(sq.op_id)
	if op:
		return "%s #%d · %s" % [op.type_name(), op.id, op.phase_name()]
	if sq.station_objective >= 0 and sim.state.war.objective(sq.station_objective):
		return "Garrison %s" % sim.state.war.objective(sq.station_objective).obj_name
	return sq.order_name() if sq.order != SquadState.Order.NONE else "Idle"


func _refresh_events() -> void:
	var evs := sim.war.events_for(faction, 3)
	var key := str(evs.map(func(e: Dictionary) -> String: return "%s%s" % [e.t, e.text]))
	if _events.get_meta("key", "") == key:
		return
	_events.set_meta("key", key)
	for c in _events.get_children():
		c.queue_free()
	for e: Dictionary in evs:
		var col := FNUI.INK_2
		match e.kind:
			"captured":
				col = FNUI.WARN
			"contested", "threat", "attack":
				col = FNUI.ALERT
			"op_done", "reinforcements":
				col = FNUI.OK
			"op_failed":
				col = FNUI.DANGER
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", FNUI.S3)
		var epos: Vector3 = e.get("pos", Vector3.INF)
		if epos.is_finite():
			# GAMEPLAY-01D: a warning with a place - a click centres the map on it.
			h.mouse_filter = Control.MOUSE_FILTER_STOP
			h.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			h.tooltip_text = "Click: show on the map"
			h.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					focus_on(epos))
		var tl := FNUI.label("%02d:%02d" % [int(e.t / 3600.0) % 24, int(e.t / 60.0) % 60], FNUI.CAPTION, FNUI.INK_3, "number")
		tl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(tl)
		var l := FNUI.label(e.text, FNUI.CAPTION, col, "body")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(COLUMN_W - 60, 0)
		h.add_child(l)
		_events.add_child(h)


func _refresh_ops() -> void:
	var war := sim.state.war
	var ops := war.active_operations(faction)
	# Recently ended operations stay listed (greyed) for five minutes with their outcome.
	var ended := []
	for o: OperationState in war.operations.values():
		if o.faction == faction and not o.is_active() and sim.state.time - o.ended_at < 300.0:
			ended.append(o)
	ended.sort_custom(func(a: OperationState, b: OperationState) -> bool: return a.ended_at > b.ended_at)
	ended = ended.slice(0, 3)
	_ops_head.aside.text = "%d active" % ops.size()
	var key := str((ops + ended).map(func(o: OperationState) -> String: return "%d.%d.%d.%d" % [o.id, o.phase, o.squads.size(), o.losses])) + str(selected_op)
	if _ops_box.get_meta("key", "") == key:
		return
	_ops_box.set_meta("key", key)
	for c in _ops_box.get_children():
		c.queue_free()
	if ops.is_empty() and ended.is_empty():
		var l := FNUI.label("No operations. Select squads, then RMB on a target.", FNUI.CAPTION, FNUI.INK_3, "body")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(COLUMN_W - 2 * FNUI.S4, 0)
		_ops_box.add_child(l)
	for op: OperationState in ops + ended:
		var obj := war.objective(op.target_objective)
		var soldiers := 0
		for sid in op.squads:
			var sq := sim.state.get_squad(sid)
			if sq:
				soldiers += sq.members.size()
		var oid := op.id
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", FNUI.S2)
		var b := FNCategoryTile.new(&"operation", "#%d %s %s" % [op.id, op.type_name(), obj.obj_name if obj else "point"],
			("%s · %d sq" % [op.phase_name(), op.squads.size()]) if op.is_active() else op.phase_name())
		b.icon_rect.modulate = _op_color(op)
		b.selected = op.id == selected_op
		b.tooltip_text = "%s #%d · %s · %d squads, %d soldiers" % [op.type_name(), op.id, op.phase_name(), op.squads.size(), soldiers]
		if not op.is_active():
			b.modulate.a = 0.55
		b.pressed.connect(func() -> void: select_operation(oid))
		row.add_child(b)
		if op.is_active():
			var go := FNUI.action_button(&"route", "", "Show the target")
			go.pressed.connect(func() -> void: go_to(op.target_pos))
			row.add_child(go)
			var x := FNUI.action_button(&"blocked", "", "Cancel the operation")
			x.pressed.connect(func() -> void: sim.war.cancel(oid, "cancelled by the player"))
			row.add_child(x)
		_ops_box.add_child(row)


static func _fac(f: int) -> String:
	return "[color=#%s]%s[/color]" % [WorldState.faction_color(f).to_html(false), WorldState.faction_name(f)]


# --- Orders -----------------------------------------------------------------------------

func select_operation(op_id: int) -> void:
	selected_op = op_id
	selected_squads.clear()
	selected_objective = -1
	pending_order = -1
	_refresh_panel()
	queue_redraw()


func _button(key: String) -> void:
	match key:
		"attack", "defend", "reinforce":
			var type: int = {"attack": OperationState.Type.ATTACK, "defend": OperationState.Type.DEFEND, "reinforce": OperationState.Type.REINFORCE}[key]
			if selected_objective >= 0:
				order(type, selected_objective)
			else:
				pending_order = type
		"move":
			pending_order = OperationState.Type.MOVE
		"cancel":
			var op := sim.state.war.operation(selected_op)
			if op and op.is_active():
				sim.war.cancel(op.id, "cancelled by the player")
			for sid in selected_squads:
				var sq := sim.state.get_squad(sid)
				if sq and sq.op_id >= 0:
					sim.war.cancel(sq.op_id, "cancelled by the player")
		"view":
			go_to_selection()
	_refresh_panel()


## Gives the selected squads an operation (the player's command): they leave whatever
## they were doing. The new operation becomes the selection, so its route and status show.
func order(type: OperationState.Type, objective_id := -1, point := Vector3.INF) -> OperationState:
	pending_order = -1
	if selected_squads.is_empty():
		return null
	var op := sim.war.start_operation(faction, type, selected_squads.duplicate(), objective_id, point, true)
	if op:
		selected_objective = -1
	return op


func _order_at(sp: Vector2) -> void:
	# LOGISTICS-01: vehicles (with squads: a transport order) go where the map is clicked.
	if not selected_vehicles.is_empty():
		var dest := to_world(sp)
		var texts: Array[String] = []
		if selected_squads.is_empty():
			texts = sim.vehicles.order_group(selected_vehicles, dest).texts
		else:
			texts = sim.vehicles.transport.order_group(selected_vehicles, selected_squads, dest).texts
			sim.war.release_squads(selected_squads, "transport order")
		for t in texts:
			sim.war.log_event(faction, "logistics", t)
		return
	if selected_squads.is_empty():
		return
	var oid := _objective_at(sp)
	var war := sim.state.war
	if oid >= 0:
		var o := war.objective(oid)
		order(OperationState.Type.REINFORCE if o.owner == faction else OperationState.Type.ATTACK, oid)
	else:
		order(OperationState.Type.MOVE, -1, to_world(sp))


## Centres the map on p (zoomed in to at least the objective level).
func focus_on(p: Vector3) -> void:
	if not p.is_finite():
		return
	view_center = Vector2(p.x, p.z)
	queue_redraw()


func go_to(p: Vector3) -> void:
	demo.rts_camera.frame(p, demo.rts_camera.yaw, 120.0)
	close()


## Middle click: the tactical camera jumps to p, keeping its heading, tilt and zoom (so its
## height above the ground). RTSCamera keeps the camera above the terrain and in front of
## structures. The map stays open.
func move_camera_to(p: Vector3) -> void:
	if not p.is_finite():
		return
	var lim := half - 10.0
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	demo.rts_camera.frame(p, demo.rts_camera.yaw)
	queue_redraw()


func go_to_selection() -> void:
	if not selected_vehicles.is_empty():
		var vu := sim.state.get_unit(selected_vehicles[0])
		if vu:
			demo.rts.select(selected_vehicles.duplicate())
			go_to(vu.position)
			return
	var st := sim.logistics.structure(selected_structure)
	if st:
		demo.rts.select([])
		demo.rts.selected_structure = st.id
		go_to(st.position)
		return
	if not selected_squads.is_empty():
		var sq := sim.state.get_squad(selected_squads[0])
		if sq:
			demo.rts.select_squads(selected_squads.duplicate())
			go_to(sim.war.squad_center(sq))
			return
	var op := sim.state.war.operation(selected_op)
	if op:
		var ids := Array(op.squads)
		var sq := sim.state.get_squad(ids[0]) if not ids.is_empty() else null
		if sq and op.is_active():
			demo.rts.select_squads(ids)
			go_to(sim.war.squad_center(sq))
		else:
			go_to(op.target_pos)
		return
	var o := sim.state.war.objective(selected_objective)
	if o:
		go_to(o.position)


func close() -> void:
	visible = false
	pending_order = -1
	closed.emit()


# --- Input ------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not map_rect().has_point(mb.position):
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				zoom_by(1.35 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.35, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_pan_from = mb.position
				_mid_press = mb.position
				_mid_dragged = false
			else:
				if _mid_press.is_finite() and not _mid_dragged:
					move_camera_to(to_world(mb.position))
				_pan_from = Vector2.INF
				_mid_press = Vector2.INF
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click:
				_double_click(mb.position)
				_drag_from = Vector2.INF
			elif mb.pressed:
				_drag_from = mb.position
				_box = false
			elif _drag_from.is_finite():
				if _box:
					_box_select(Rect2(_drag_from, mb.position - _drag_from).abs(), mb.shift_pressed)
				else:
					_click(mb.position, mb.shift_pressed)
				_drag_from = Vector2.INF
				_box = false
			_refresh_panel()
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if pending_order >= 0:
				pending_order = -1
			else:
				_order_at(mb.position)
			_refresh_panel()
			queue_redraw()
			accept_event()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		zoom_by(mg.factor, mg.position)
		accept_event()
	elif event is InputEventPanGesture:
		view_center += (event as InputEventPanGesture).delta * 12.0 / zoom
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pan_from.is_finite():
			if not _mid_dragged and _mid_press.is_finite() and mm.position.distance_to(_mid_press) > MIDDLE_CLICK_PX:
				# A drag after all: catch up with the movement held back below the threshold.
				_mid_dragged = true
				view_center -= (mm.position - _mid_press - mm.relative) / zoom
			if _mid_dragged or not _mid_press.is_finite():
				view_center -= mm.relative / zoom
				queue_redraw()
		elif _drag_from.is_finite() and mm.position.distance_to(_drag_from) > 6.0:
			_box = true
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_G:
				go_to_selection()
				accept_event()
			KEY_HOME:
				fit_all()
				queue_redraw()
				accept_event()
			KEY_H:
				show_help = not show_help
				queue_redraw()
				accept_event()
			KEY_I:
				# Off -> each faction in turn -> off.
				var ids: Array = sim.state.war.factions.keys()
				ids.sort()
				var i := ids.find(dbg_faction)
				dbg_faction = -1 if i + 1 >= ids.size() and dbg_faction >= 0 else ids[i + 1 if dbg_faction >= 0 else 0]
				if dbg_faction < 0:
					dbg_truth = false
					dbg_squad = -1
				queue_redraw()
				accept_event()
			KEY_T:
				if dbg_faction >= 0:
					dbg_truth = not dbg_truth
					if not dbg_truth:
						dbg_squad = -1
					queue_redraw()
					accept_event()
			KEY_ESCAPE:
				if pending_order >= 0:
					pending_order = -1
					_refresh_panel()
					accept_event()


func _click(sp: Vector2, add: bool) -> void:
	if pending_order >= 0:
		var oid := _objective_at(sp)
		if pending_order == OperationState.Type.MOVE:
			order(OperationState.Type.MOVE, -1, to_world(sp))
		elif oid >= 0:
			order(pending_order, oid)
		return
	for id in _op_rects:
		if (_op_rects[id] as Rect2).has_point(sp):
			select_operation(id)
			return
	if dbg_truth:
		var best := -1
		var bd := 16.0
		for sq: SquadState in sim.state.all_squads():
			if sq.faction == faction or sq.members.is_empty():
				continue
			var d := to_screen(sim.war.squad_center(sq)).distance_to(sp)
			if d < bd:
				bd = d
				best = sq.id
		if best >= 0:
			dbg_squad = best
			return
	var lg := _logistics_at(sp)
	if not lg.is_empty():
		selected_op = -1
		selected_objective = -1
		if lg.kind == "veh":
			if not add:
				selected_vehicles.clear()
				selected_structure = -1
			if selected_vehicles.has(lg.id):
				selected_vehicles.erase(lg.id)
			else:
				selected_vehicles.append(lg.id)
		else:
			selected_structure = lg.id
			if not add:
				selected_vehicles.clear()
				selected_squads.clear()
		return
	var g := _group_at(sp)
	if not g.is_empty():
		if not add:
			selected_squads.clear()
			selected_vehicles.clear()
			selected_structure = -1
		for sid in g.ids:
			if not selected_squads.has(sid):
				selected_squads.append(sid)
		selected_objective = -1
		selected_op = -1
		return
	var oid := _objective_at(sp)
	selected_op = -1
	if oid >= 0 and not selected_squads.is_empty() and not add:
		# Squads stay selected: the objective becomes their target for the buttons.
		selected_objective = oid
		return
	if not add:
		selected_squads.clear()
		selected_vehicles.clear()
		selected_structure = -1
	selected_objective = oid


## Double-click on a group of several squads zooms in until they separate.
func _double_click(sp: Vector2) -> void:
	var g := _group_at(sp)
	if g.is_empty() or g.ids.size() < 2:
		return
	view_center = _to_world2(g.pos)
	_zoom_anchor = map_rect().get_center()
	_zoom_target = clampf(maxf(zoom * 3.0, OPERATIONAL_ZOOM * 1.2), _zoom_min, ZOOM_MAX)


func _box_select(r: Rect2, add: bool) -> void:
	if not add:
		selected_squads.clear()
		selected_vehicles.clear()
		selected_structure = -1
	for vu: UnitState in _my_vehicles():
		if r.has_point(to_screen(vu.position)) and not selected_vehicles.has(vu.id):
			selected_vehicles.append(vu.id)
	# Real squad positions, not where their (group) markers are drawn.
	for sq: SquadState in sim.war.squads_of(faction):
		if not sq.members.is_empty() and r.has_point(to_screen(sim.war.squad_center(sq))) and not selected_squads.has(sq.id):
			selected_squads.append(sq.id)
	selected_objective = -1
	selected_op = -1


func _group_at(sp: Vector2) -> Dictionary:
	var best := {}
	var bd := 18.0
	# Grouped for the current view (the last drawn groups may be from before a jump).
	for g: Dictionary in squad_groups():
		var d: float = (g.draw_at as Vector2).distance_to(sp)
		if d < bd:
			bd = d
			best = g
	return best


## The id of the squad marker under sp (-1 none). For a group, its first squad.
func _squad_at(sp: Vector2) -> int:
	var g := _group_at(sp)
	return g.ids[0] if not g.is_empty() else -1


func _objective_at(sp: Vector2) -> int:
	var best := -1
	var bd := 18.0
	for o: ObjectiveState in sim.state.war.objectives.values():
		var d := to_screen(o.position).distance_to(sp)
		if d < maxf(bd, o.radius * zoom):
			bd = d
			best = o.id
	return best


# --- Grouping (presentation only) -------------------------------------------------------------

## Squads of the player's faction grouped by screen distance at the current zoom. Each
## group sits at the mean of its squads' real positions. Nothing in the simulation is
## changed. At the strategic level a group inside an objective is shown as that
## objective's garrison badge.
func squad_groups() -> Array:
	var level := detail_level()
	# UI-01C.1: never closer than a marker is wide (22 px symbol + stack offset), so markers do not overlap.
	var r_px: float = [30.0, 28.0, 28.0][level]
	var items := []
	for sq: SquadState in sim.war.squads_of(faction):
		if sq.members.is_empty():
			continue
		items.append({"sq": sq, "p": to_screen(sim.war.squad_center(sq))})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.sq.members.size() > b.sq.members.size())
	var groups := []
	for it: Dictionary in items:
		var g: Dictionary = {}
		for gg: Dictionary in groups:
			if (gg.pos as Vector2).distance_to(it.p) < r_px:
				g = gg
				break
		if g.is_empty():
			g = {"ids": [], "pos": Vector2.ZERO, "sum": Vector2.ZERO, "soldiers": 0, "fighting": false, "selected": 0, "badge": -1}
			groups.append(g)
		g.ids.append(it.sq.id)
		g.sum += it.p
		g.pos = g.sum / g.ids.size()
		g.soldiers += it.sq.members.size()
		if _fighting(it.sq):
			g.fighting = true
		if selected_squads.has(it.sq.id):
			g.selected += 1
	for g: Dictionary in groups:
		g.draw_at = g.pos
		if level == 0:
			for o: ObjectiveState in sim.state.war.objectives.values():
				var op := to_screen(o.position)
				if op.distance_to(g.pos) < maxf(o.radius * zoom, 12.0):
					g.badge = o.id
					g.draw_at = op + Vector2(_objective_size(o) + 12.0, -_objective_size(o) - 4.0)
					break
	return groups


func _fighting(sq: SquadState) -> bool:
	if sq == null:
		return false
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u and (u.ai_state == UnitState.AiState.ENGAGING or u.under_fire_until > sim.state.time):
			return true
	return false


func _threatened(o: ObjectiveState) -> bool:
	return o.owner == faction and not o.contested and sim.war.threat_near(faction, o.position, o.radius + 600.0) > 0


# --- Drawing ----------------------------------------------------------------------------

func _draw() -> void:
	var r := map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.07))
	var tl := to_screen(Vector3(-half, 0, -half))
	var br := to_screen(Vector3(half, 0, half))
	var map_area := Rect2(tl, br - tl)
	if _bg:
		draw_texture_rect(_bg, map_area, false, Color(0.86, 0.89, 0.86))
	_update_territory()
	if _territory and layers.territory:
		# Territory is strongest on the overview and fades when zoomed in, where the
		# terrain itself matters more.
		var a := clampf(remap(log(zoom), log(0.05), log(1.0), 0.75, 0.3), 0.3, 0.75)
		draw_texture_rect(_territory, map_area, false, Color(1, 1, 1, a))
	if layers.grid:
		_draw_grid(map_area)
	draw_rect(map_area, Color(FNUI.LINE_STRONG, 0.8), false, 1.0)
	var font := FNUI.font("semibold")
	var war := sim.state.war
	var level := detail_level()
	_taken.clear()
	# Objectives below everything that moves.
	if layers.objectives:
		for o: ObjectiveState in war.all_objectives():
			_draw_objective(o, font, level)
		_draw_caches(font)
		_draw_stashes(font)
	# Operations of the player's faction: routes, then their labels.
	_op_rects.clear()
	var label_slots := {}
	var ops := war.active_operations(faction) if layers.operations else []
	for op: OperationState in ops:
		_draw_operation_route(op)
	for op: OperationState in ops:
		_draw_operation_label(op, font, label_slots)
	if layers.contacts:
		_draw_known_enemies(font)
	if dbg_truth:
		_draw_truth(font)
	# Bases, facilities and vehicles under the squads; their boxes are taken before the squad labels.
	if layers.logistics:
		_draw_logistics_layer(font, level)
	_groups = squad_groups() if layers.friendly else []
	# Markers first, then their labels where there is room.
	# Close in, each soldier as a dot under its squad's marker (from 1 px/m the
	# formation is wider than the symbol).
	if level == 2 and zoom >= 1.0:
		_draw_soldier_dots()
	for g: Dictionary in _groups:
		_draw_group(g, font, level)
	# Labels by priority: selected, then groups, then single squads.
	var order := _groups.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.selected * 100 + a.ids.size() > b.selected * 100 + b.ids.size())
	for g: Dictionary in order:
		_draw_group_label(g, font)
	if layers.camera:
		_draw_camera()
	if _box and _drag_from.is_finite():
		var m := get_local_mouse_position()
		var br2 := Rect2(_drag_from, m - _drag_from).abs()
		draw_rect(br2, Color(1, 1, 1, 0.1), true)
		draw_rect(br2, Color(1, 1, 1, 0.8), false, 1.0)
	if pending_order >= 0:
		var m := get_local_mouse_position()
		var col := _type_color(pending_order)
		draw_arc(m, 12.0, 0.0, TAU, 20, col, 2.0)
		_text(font, m + Vector2(16, -8), OperationState.TYPE_NAMES[pending_order].to_upper(), 12, col)
	_draw_scale(font)
	if dbg_faction >= 0:
		_draw_inspector(font, r)
	_draw_help(font, r)


## GAMEPLAY-01B: the supply caches the faction knows - an amber diamond with name and content (securing: progress), a
## hollow grey one once taken.
func _draw_caches(font: Font) -> void:
	for c: Dictionary in sim.state.war.caches:
		if not (c.known as Array).has(faction):
			continue
		var s := to_screen(c.pos)
		var depleted: bool = c.state == "depleted"
		var col := Color(FNUI.INK_3, 0.8) if depleted else FNUI.ARMED
		var d := 6.0
		var pts := PackedVector2Array([s + Vector2(0, -d), s + Vector2(d, 0), s + Vector2(0, d), s + Vector2(-d, 0)])
		if depleted:
			pts.append(pts[0])
			draw_polyline(pts, col, 1.5)
		else:
			draw_colored_polygon(PackedVector2Array([s + Vector2(0, -d - 1.5), s + Vector2(d + 1.5, 0), s + Vector2(0, d + 1.5), s + Vector2(-d - 1.5, 0)]), Color(0, 0, 0, 0.7))
			draw_colored_polygon(pts, col)
		var txt := String(c.name)
		if depleted:
			txt += " (taken)"
		elif c.state == "securing":
			txt += " · securing %d%%" % roundi(float(c.progress) * 100.0)
		else:
			txt += " · %d kg" % roundi(float(c.supplies))
		_text(font, s + Vector2(10, 4), txt, 11, col)


## GAMEPLAY-05: equipment the faction knows of (finds, cache equipment, the fallen's weapons) - a small green square, amber when it
## holds a weapon type not registered yet. Markers whose labels would overlap are one (a fight leaves many); a named find is
## labelled, the fallen only by count. The tactical view lists the contents.
func _draw_stashes(font: Font) -> void:
	if demo == null or demo.sim.war == null:
		return
	var fs := sim.state.war.faction(faction)
	var groups: Array = []
	for st: Dictionary in demo.sim.war.equip.known_stashes(faction):
		var sp := to_screen(st.pos)
		var g: Dictionary = {}
		for x: Dictionary in groups:
			var dd: Vector2 = (x.s as Vector2) - sp
			if absf(dd.x) <= 170.0 and absf(dd.y) <= 16.0:
				g = x
				break
		if g.is_empty():
			g = {"s": sp, "n": 0, "name": "", "new": false}
			groups.append(g)
		g.n = int(g.n) + 1
		if st.kind != "fallen" and String(g.name) == "":
			g.name = String(st.name)
		for k in st.items:
			if fs != null and int(st.items[k]) > 0 and not fs.discovered.has(String(k)):
				g.new = true
	for g: Dictionary in groups:
		var col: Color = FNUI.ARMED if g.new else FNUI.OK
		var sp: Vector2 = g.s
		draw_rect(Rect2(sp - Vector2(5, 5), Vector2(10, 10)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(sp - Vector2(3.5, 3.5), Vector2(7, 7)), col)
		var txt := String(g.name) if String(g.name) != "" else ("Fallen equipment" if int(g.n) == 1 else "Fallen equipment ×%d" % int(g.n))
		if String(g.name) != "" and int(g.n) > 1:
			txt += " +%d" % (int(g.n) - 1)
		if g.new:
			txt += " · new type"
		_text(font, sp + Vector2(9, 4), txt, 10, col)


## The tactical camera: its position, a faint wedge of its horizontal field of view
## pointing where it looks, and a small cross on the point it orbits (its focus).
func _draw_camera() -> void:
	var rig: RTSCamera = demo.rts_camera
	var cam3d := rig.camera
	var cp := to_screen(cam3d.global_position)
	var fwd3 := -cam3d.global_transform.basis.z
	var dir := Vector2(fwd3.x, fwd3.z)
	if dir.length() < 0.01:
		dir = Vector2(-sin(rig.yaw), -cos(rig.yaw))
	dir = dir.normalized()
	var vs := get_viewport_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	var half_h := atan(tan(deg_to_rad(cam3d.fov) * 0.5) * aspect)
	# Reach: a little past the focus, never shorter than a readable marker.
	var reach := maxf(Vector2(cam3d.global_position.x - rig.focus.x, cam3d.global_position.z - rig.focus.z).length() * 1.6 * zoom, 46.0)
	var pts := PackedVector2Array([cp])
	for k in 9:
		pts.append(cp + dir.rotated(lerpf(-half_h, half_h, k / 8.0)) * reach)
	draw_colored_polygon(pts, Color(1, 1, 1, 0.09))
	draw_line(cp, pts[1], Color(1, 1, 1, 0.45), 1.2, true)
	draw_line(cp, pts[pts.size() - 1], Color(1, 1, 1, 0.45), 1.2, true)
	draw_polyline(pts.slice(1), Color(1, 1, 1, 0.18), 1.0, true)
	var fp := to_screen(rig.focus)
	draw_line(fp + Vector2(-5, 0), fp + Vector2(5, 0), Color(1, 1, 1, 0.7), 1.2)
	draw_line(fp + Vector2(0, -5), fp + Vector2(0, 5), Color(1, 1, 1, 0.7), 1.2)
	draw_circle(cp, 4.5, Color(0.05, 0.06, 0.07, 0.9))
	draw_circle(cp, 3.0, Color.WHITE)


func _draw_grid(area: Rect2) -> void:
	var c := Color(1, 1, 1, 0.06)
	var step := 2 if zoom < 0.15 else 1
	for k in range(-10, 11, step):
		var x := to_screen(Vector3(k * 1000.0, 0, 0)).x
		var y := to_screen(Vector3(0, 0, k * 1000.0)).y
		draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), c, 1.0)
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), c, 1.0)


func _draw_scale(font: Font) -> void:
	var m_per_bar := 1000.0
	for s: float in [5000.0, 2000.0, 1000.0, 500.0, 200.0, 100.0, 50.0]:
		if s * zoom <= 180.0:
			m_per_bar = s
			break
	var px := m_per_bar * zoom
	# Inside the map's lower left corner (the left column covers the window edge).
	var br := to_screen(Vector3(half, 0, half))
	var tl := to_screen(Vector3(-half, 0, -half))
	var at := Vector2(clampf(tl.x, COLUMN_W + 2.0 * FNUI.EDGE, size.x) + 12.0, minf(br.y, size.y) - 14.0)
	draw_line(at, at + Vector2(px, 0), Color.WHITE, 2.0)
	draw_line(at + Vector2(0, -4), at + Vector2(0, 4), Color.WHITE, 2.0)
	draw_line(at + Vector2(px, -4), at + Vector2(px, 4), Color.WHITE, 2.0)
	_text(font, at + Vector2(0, -8), ("%d km" % int(m_per_bar / 1000.0)) if m_per_bar >= 1000.0 else "%d m" % int(m_per_bar), 12, Color.WHITE)


func _draw_help(font: Font, r: Rect2) -> void:
	if not show_help:
		return
	var rows := [
		["Wheel", "zoom towards the cursor"],
		["Middle-drag, WASD", "pan     Home: whole map"],
		["Middle click", "move the tactical camera there (wedge = where it looks)"],
		["LMB", "select a squad, group, objective or operation"],
		["LMB drag, Shift", "box select, add to selection"],
		["Double-click group", "zoom in until its squads separate"],
		["RMB", "order selected squads: enemy / neutral objective = attack,"],
		["", "own objective = reinforce, ground = move"],
		["Buttons", "Attack / Defend / Reinforce / Move, then click a target"],
		["G", "view the selection in the tactical view"],
		["I / T", "developer: AI inspector (faction picture + decisions) / true positions"],
		[", and .", "time speed 1-16x (first person is always 1x)"],
		["F5 / F9", "save / load the whole war"],
		["M / Esc", "close the map     H: hide this"],
	]
	var box := Rect2(Vector2.ZERO, Vector2(minf(470.0, r.size.x - 32.0), 30.0 + rows.size() * 15.0))
	box.position = ((size - box.size) * 0.5).round()
	draw_style_box(FNUI.panel_style(), box)
	var body := FNUI.font("regular", false)
	_text(FNUI.caps_font(), box.position + Vector2(12, 18), "MAP CONTROLS", FNUI.LABEL, FNUI.INK, 0)
	var y := box.position.y + 36.0
	for row: Array in rows:
		draw_string(FNUI.caps_font(), Vector2(box.position.x + 12, y), String(row[0]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION, FNUI.ARMED)
		draw_string(body, Vector2(box.position.x + 130, y), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION + 1, FNUI.INK)
		y += 15.0


## Text with a dark outline (readable on any terrain).
func _text(font: Font, p: Vector2, t: String, fs: int, col: Color, outline := 4) -> void:
	draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.85 * col.a))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Territory: each cell belongs to the nearest objective within its reach (1.6 km + 0.6 km
## per value point), coloured by that objective's owner; boundaries between owners are
## drawn stronger. The nearest-objective map is built once; an ownership change only
## recolours it.
func _update_territory() -> void:
	var war := sim.state.war
	var key := ""
	for o: ObjectiveState in war.all_objectives():
		key += "%d:%d," % [o.id, o.owner]
	if key == _territory_key and _territory:
		return
	_territory_key = key
	var n := TERRITORY_RES
	if _cell_objective.size() != n * n:
		_cell_objs = war.all_objectives()
		_cell_objective.resize(n * n)
		for z in n:
			for x in n:
				var p := Vector2(-half + (x + 0.5) * half * 2.0 / n, -half + (z + 0.5) * half * 2.0 / n)
				var best := -1
				var bd := INF
				for i in _cell_objs.size():
					var o: ObjectiveState = _cell_objs[i]
					var raw := p.distance_to(Vector2(o.position.x, o.position.z))
					if raw < 1600.0 + 600.0 * o.value and raw < bd:
						bd = raw
						best = i
				_cell_objective[z * n + x] = best
	var owner := PackedInt32Array()
	owner.resize(n * n)
	for i in n * n:
		var k := _cell_objective[i]
		owner[i] = (_cell_objs[k] as ObjectiveState).owner if k >= 0 else -1
	var data := PackedByteArray()
	data.resize(n * n * 4)
	for z in n:
		for x in n:
			var i := z * n + x
			var f := owner[i]
			if f < 0:
				continue
			var edge := (x > 0 and owner[i - 1] != f) or (x < n - 1 and owner[i + 1] != f) \
					or (z > 0 and owner[i - n] != f) or (z < n - 1 and owner[i + n] != f)
			var c := WorldState.faction_color(f)
			data[i * 4] = int(c.r * 255.0)
			data[i * 4 + 1] = int(c.g * 255.0)
			data[i * 4 + 2] = int(c.b * 255.0)
			data[i * 4 + 3] = 235 if edge else 72
	_territory = ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data))


func _objective_size(o: ObjectiveState) -> float:
	return 6.0 + o.value * 2.0


func _draw_objective(o: ObjectiveState, font: Font, level: int) -> void:
	var p := to_screen(o.position)
	var col := WorldState.faction_color(o.owner) if o.owner >= 0 else Color(0.85, 0.85, 0.85)
	var s := _objective_size(o)
	var zone := o.radius * zoom
	var rr := maxf(zone, s + 3.0)
	# The capture zone itself only once it is larger than the symbol.
	if zone > s + 6.0:
		draw_circle(p, zone, Color(col, 0.12))
		draw_arc(p, zone, 0.0, TAU, 48, Color(col, 0.7), 1.5)
	match o.kind:
		&"hq":
			draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), Color(0.08, 0.08, 0.08, 0.9), true)
			draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), col, false, 2.5)
			_star(p, s * 0.7, col)
		&"bridge":
			draw_rect(Rect2(p - Vector2(s, s * 0.45), Vector2(s * 2.0, s * 0.9)), Color(0.08, 0.08, 0.08, 0.9), true)
			draw_line(p + Vector2(-s, -s * 0.45), p + Vector2(s, -s * 0.45), col, 2.0)
			draw_line(p + Vector2(-s, s * 0.45), p + Vector2(s, s * 0.45), col, 2.0)
		&"base":
			# GAMEPLAY-01D: a base - a walled square with a flag.
			draw_rect(Rect2(p - Vector2(s, s * 0.8), Vector2(s * 2.0, s * 1.6)), Color(0.08, 0.08, 0.08, 0.9), true)
			draw_rect(Rect2(p - Vector2(s, s * 0.8), Vector2(s * 2.0, s * 1.6)), col, false, 2.0)
			for k in 3:
				draw_rect(Rect2(p + Vector2(-s + k * s * 0.8, -s * 0.8 - 3.0), Vector2(s * 0.4, 3.0)), col, true)
			draw_line(p + Vector2(-s * 0.2, s * 0.45), p + Vector2(-s * 0.2, -s * 0.45), col, 1.5)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 0.2, -s * 0.45), p + Vector2(s * 0.5, -s * 0.25), p + Vector2(-s * 0.2, -s * 0.05)]), col)
		&"town":
			draw_circle(p, s, Color(0.08, 0.08, 0.08, 0.9))
			draw_arc(p, s, 0.0, TAU, 20, col, 2.5)
			draw_circle(p, s * 0.4, col)
		_:
			var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
			draw_colored_polygon(pts, Color(0.08, 0.08, 0.08, 0.9))
			pts.append(pts[0])
			draw_polyline(pts, col, 2.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
	if o.capture_faction >= 0 and o.capture_progress > 0.0:
		draw_arc(p, rr + 5.0, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 5.0)
		draw_arc(p, rr + 5.0, -PI * 0.5, -PI * 0.5 + TAU * o.capture_progress, 32, WorldState.faction_color(o.capture_faction), 4.0)
	var tag := ""
	var tag_col := Color.WHITE
	if o.contested:
		draw_arc(p, rr + 10.0, 0.0, TAU, 32, Color(COL_CONTESTED, 0.45 + 0.55 * pulse), 3.0)
		tag = "CONTESTED"
		tag_col = COL_CONTESTED
	elif _threatened(o):
		var tp := p + Vector2(-s - 9.0, -s - 6.0)
		var tri := PackedVector2Array([tp + Vector2(0, -8), tp + Vector2(7, 5), tp + Vector2(-7, 5)])
		draw_colored_polygon(tri, Color(COL_THREAT, 0.6 + 0.4 * pulse))
		draw_string(font, tp + Vector2(-2.5, 4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
		tag = "THREATENED"
		tag_col = COL_THREAT
	if o.id == selected_objective:
		draw_arc(p, rr + 14.0, 0.0, TAU, 32, COL_SELECT, 2.0)
	var fs := 13 if level == 0 else 14
	var label := o.obj_name
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_taken.append(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0))
	# Below the symbol, else beside it, else above (objective names always show).
	var h := float(fs + 4) + (13.0 if tag != "" else 0.0)
	var cands: Array[Vector2] = [p + Vector2(-w * 0.5, rr + 17.0), p + Vector2(rr + 8.0, 5.0), p + Vector2(-rr - 8.0 - w, 5.0), p + Vector2(-w * 0.5, -rr - 10.0 - (13.0 if tag != "" else 0.0))]
	var lp := _place(cands, w, fs, h, true)
	_text(font, lp, label, fs, Color(1, 1, 1))
	if tag != "":
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_text(font, lp + Vector2((w - tw) * 0.5, 13.0), tag, 10, tag_col, 3)


## The first candidate text position (baseline left) whose box (w x h) is not taken yet;
## reserves it. force: use the first candidate when none is free, else return INF.
func _place(cands: Array[Vector2], w: float, fs: int, h: float, force: bool) -> Vector2:
	for c: Vector2 in cands:
		var r := Rect2(c + Vector2(0, -fs), Vector2(w, h))
		var free := true
		for q: Rect2 in _taken:
			if q.intersects(r):
				free = false
				break
		if free:
			_taken.append(r)
			return c
	if not force:
		return Vector2.INF
	_taken.append(Rect2(cands[0] + Vector2(0, -fs), Vector2(w, h)))
	return cands[0]


func _star(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * TAU / 10.0
		pts.append(p + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)


## One squad: a NATO infantry symbol (frame with a cross). Several squads drawn as one
## group: stacked frames with "squads · soldiers". Selected squads are outlined in yellow.
func _draw_group(g: Dictionary, font: Font, level: int) -> void:
	var p: Vector2 = g.draw_at
	var col := WorldState.faction_color(faction)
	var n: int = g.ids.size()
	var sel: int = g.selected
	var small := level == 0
	var half_size := Vector2(8, 5) if small else Vector2(11, 7)
	if g.badge >= 0:
		# Garrison badge: a short leader line to the objective it stands in.
		var op := to_screen(sim.state.war.objective(g.badge).position)
		draw_line(op, p, Color(col.lightened(0.3), 0.6), 1.0)
	if n > 1:
		for k: int in [2, 1]:
			var off := Vector2(3, -3) * k
			draw_rect(Rect2(p - half_size + off, half_size * 2.0), Color(col.darkened(0.6), 0.95), true)
			draw_rect(Rect2(p - half_size + off, half_size * 2.0), col.lightened(0.2), false, 1.0)
	var rect := Rect2(p - half_size, half_size * 2.0)
	draw_rect(rect, Color(col.darkened(0.55), 0.6 if level == 2 and zoom >= 1.0 else 0.95), true)
	var outline := COL_SELECT if sel > 0 else col.lightened(0.3)
	draw_rect(rect, outline, false, 2.5 if sel > 0 else 1.5)
	if sel > 0 and sel < n:
		# Only some of the group's squads are selected.
		draw_rect(rect.grow(3.0), Color(COL_SELECT, 0.5), false, 1.0)
	draw_line(rect.position, rect.end, col.lightened(0.4), 1.2)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), col.lightened(0.4), 1.2)
	if g.fighting:
		_swords(p + Vector2(half_size.x + 5, -half_size.y - 4), Color(1.0, 0.45, 0.3))
	_taken.append(rect.grow(2.0).merge(rect.grow(2.0).grow_individual(0, 6.0 if n > 1 else 0.0, 6.0 if n > 1 else 0.0, 0)))
	g.half = half_size


## The group's label: below the marker, else to its right, else above - the first place
## not taken by another label or marker. A single squad without room goes without a
## label at this zoom (its name shows in the panel when selected, and on the map when
## zoomed in); groups always get theirs, and so does everything at the close level.
func _draw_group_label(g: Dictionary, font: Font) -> void:
	var p: Vector2 = g.draw_at
	var n: int = g.ids.size()
	var small := detail_level() == 0
	var half_size: Vector2 = g.half
	var t := ""
	if n > 1:
		t = "%d sq · %d" % [n, g.soldiers]
	elif small:
		t = str(g.soldiers)
	else:
		var sq := sim.state.get_squad(g.ids[0])
		t = "%s · %d" % [sq.squad_name, g.soldiers] if sq else ""
	var fs := 10 if small else 11
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var right := p + Vector2(half_size.x + (8.0 if n > 1 else 4.0), 4)
	var cands: Array[Vector2] = [p + Vector2(-tw * 0.5, half_size.y + 12), right, p + Vector2(-tw * 0.5, -half_size.y - (10.0 if n > 1 else 4.0))]
	if g.badge >= 0:
		cands = [right, p + Vector2(-tw * 0.5, -half_size.y - 10.0)]
	var at := _place(cands, tw, fs, fs + 3, n > 1 or detail_level() == 2)
	if not at.is_finite():
		return
	_text(font, at, t, fs, COL_SELECT if g.selected > 0 else Color.WHITE, 3)


func _swords(p: Vector2, col: Color) -> void:
	draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), col, 2.0)
	draw_line(p + Vector2(5, -5), p + Vector2(-5, 5), col, 2.0)


## Close level: every soldier of the player's faction as a dot where it actually is.
func _draw_soldier_dots() -> void:
	var col := WorldState.faction_color(faction).lightened(0.35)
	var r := map_rect()
	for sq: SquadState in sim.war.squads_of(faction):
		var sel := selected_squads.has(sq.id)
		for id in sq.members:
			var u := sim.state.get_unit(id)
			if u == null or not u.alive:
				continue
			var p := to_screen(u.position)
			if r.has_point(p):
				draw_circle(p, 3.0, Color(0, 0, 0, 0.7))
				draw_circle(p, 2.0, COL_SELECT if sel else col)


## The contacts the map draws now: the inspected faction's while the developer inspector is on,
## else the player's faction's; each with its screen position, only those on the screen.
func contact_markers() -> Array:
	var f := dbg_faction if dbg_faction >= 0 else faction
	var out := []
	var area := map_rect().grow(60.0)
	for c: ContactState in sim.war.intel.contacts_of(f):
		var p := to_screen(c.pos)
		if area.has_point(p):
			out.append({"c": c, "p": p})
	return out


## The contact picture of a faction (AI-INTEL-01): for the player, what its own soldiers have
## reported (never the real enemy positions); for the developer inspector, the picture of the
## chosen faction. Marker: filled diamond = observed now, outlined = reported, faded and small =
## stale; a circle shows how far the enemy may have moved since (uncertainty); "?" = group not
## identified (heard / fired upon). Text: believed strength, with "?" when not observed now.
func _draw_known_enemies(font: Font) -> void:
	var f := dbg_faction if dbg_faction >= 0 else faction
	var now := sim.state.time
	for m: Dictionary in contact_markers():
		var c: ContactState = m.c
		var p: Vector2 = m.p
		var col := WorldState.faction_color(c.enemy_faction) if c.enemy_faction >= 0 else Color(0.82, 0.82, 0.78)
		var a := clampf(0.3 + c.conf * 0.7, 0.3, 1.0)
		var ur := c.unc * zoom
		if ur > 8.0:
			draw_circle(p, ur, Color(col, 0.07 * a))
			draw_arc(p, ur, 0.0, TAU, 48, Color(col.lightened(0.25), 0.5 * a), 1.5)
		var observed := c.status == ContactState.Status.OBSERVED
		var r := 6.0 if c.status == ContactState.Status.STALE else 10.0
		var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)])
		if c.enemy_faction < 0:
			draw_arc(p, r, 0.0, TAU, 20, Color(col, a), 2.0)
		else:
			if observed:
				draw_colored_polygon(pts, Color(col.darkened(0.45), 0.9 * a))
			else:
				draw_colored_polygon(pts, Color(col.darkened(0.7), 0.35 * a))
			draw_polyline(pts, Color(col.lightened(0.2), a), 2.0 if observed else 1.5)
		_taken.append(Rect2(p - Vector2(11, 11), Vector2(22, 22)))
		var t := "%d%s" % [c.strength, "" if observed else "?"]
		if dbg_faction >= 0:
			t = "#%d %s ~%d %d%% %ds %s" % [c.id, c.kind_name().left(3), c.strength, roundi(c.conf * 100.0), roundi(now - c.t_seen), c.source_name()]
			_text(font, p + Vector2(r + 3, 4), t, 11, Color(1, 1, 1, a), 3)
		else:
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			_text(font, p + Vector2(-tw * 0.5, 4), t, 11, Color(1, 1, 1, a), 3)


## Developer only: where every other faction's squads really are, hollow and labelled TRUTH,
## to compare with the inspected faction's belief. Never used by any decision.
func _draw_truth(font: Font) -> void:
	var area := map_rect().grow(40.0)
	for sq: SquadState in sim.state.all_squads():
		if sq.faction == faction or sq.members.is_empty():
			continue
		var p := to_screen(sim.war.squad_center(sq))
		if not area.has_point(p):
			continue
		var col := WorldState.faction_color(sq.faction)
		var sel := sq.id == dbg_squad
		var rect := Rect2(p - Vector2(6, 6), Vector2(12, 12))
		draw_rect(rect, Color(col, 0.25), true)
		draw_rect(rect, COL_SELECT if sel else Color(col.lightened(0.3), 0.95), false, 2.0 if sel else 1.5)
		if zoom >= OPERATIONAL_ZOOM or sel:
			_text(font, p + Vector2(9, -9), "TRUTH %s %d" % [sq.squad_name, sq.members.size()], 10, Color(col.lightened(0.4), 0.95), 3)


## Developer inspector (I): the chosen faction's picture and last decisions, and why the
## inspected squad does what it does.
func _draw_inspector(font: Font, r: Rect2) -> void:
	var f := sim.state.war.faction(dbg_faction)
	if f == null:
		return
	var lines: Array[String] = ["AI INSPECTOR  %s   (I next faction / off,  T true positions %s,  click a TRUTH square to inspect its squad)" % [WorldState.faction_name(dbg_faction).to_upper(), "ON" if dbg_truth else "off"]]
	var sq: SquadState = sim.state.get_squad(dbg_squad)
	if sq == null and selected_squads.size() == 1:
		sq = sim.state.get_squad(selected_squads[0])
	if sq:
		lines.append("")
		lines.append_array(sim.war.explain_squad(sq))
	lines.append("")
	lines.append_array(sim.war.explain_faction(f))
	var fs := 12
	var lh := 15.0
	var w := minf(r.size.x - 32.0, 760.0)
	var h := lines.size() * lh + 14.0
	var box := Rect2(Vector2(16, r.size.y - h - 64.0), Vector2(w, h))
	draw_rect(box, Color(0.04, 0.05, 0.06, 0.9), true)
	draw_rect(box, Color(0.35, 0.5, 0.6), false, 1.0)
	var y := box.position.y + 16.0
	for i in lines.size():
		var t: String = lines[i]
		if t.length() > 128:
			t = t.substr(0, 127) + "…"
		draw_string(font, Vector2(box.position.x + 8, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.9, 0.55) if i == 0 else Color(0.9, 0.93, 0.9))
		y += lh


func _op_color(op: OperationState) -> Color:
	return _type_color(op.type)


func _type_color(t: int) -> Color:
	match t:
		OperationState.Type.ATTACK:
			return COL_ATTACK
		OperationState.Type.REINFORCE:
			return COL_REINFORCE
		OperationState.Type.MOVE:
			return COL_MOVE
	return WorldState.faction_color(faction).lightened(0.35)


## Remaining route of every squad of the operation as an even dashed line (constant
## dash length on screen), an arrowhead at the end, and the attack's staging point. The
## selected operation is drawn stronger, the others fainter.
func _draw_operation_route(op: OperationState) -> void:
	var col := _op_color(op)
	var sel := op.id == selected_op
	var alpha := 1.0 if sel or selected_op < 0 else 0.45
	var width := 3.0 if sel else 2.0
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq == null or sq.members.is_empty():
			continue
		var pts := PackedVector2Array([to_screen(sim.war.squad_center(sq))])
		for i in range(sq.route_i, sq.route.size()):
			pts.append(to_screen(sq.route[i]))
		if pts.size() < 2:
			pts.append(to_screen(op.target_pos))
		_dashed(pts, Color(0, 0, 0, 0.5 * alpha), width + 2.0)
		_dashed(pts, Color(col, 0.95 * alpha), width)
		var a := pts[pts.size() - 2]
		var b := pts[pts.size() - 1]
		if a.distance_to(b) > 1.0:
			var d := (b - a).normalized()
			var nrm := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([b, b - d * 10.0 + nrm * 5.0, b - d * 10.0 - nrm * 5.0]), Color(col, alpha))
	if op.type == OperationState.Type.ATTACK and op.staging_pos.is_finite() and op.phase == OperationState.Phase.MOVING:
		draw_arc(to_screen(op.staging_pos), 5.0, 0.0, TAU, 12, Color(col, alpha), 2.0)
	if sel:
		var tp := to_screen(op.target_pos)
		draw_arc(tp, 20.0, 0.0, TAU, 32, Color(col, 0.9), 2.0)


func _dashed(pts: PackedVector2Array, col: Color, width: float) -> void:
	var on := 9.0
	var off := 6.0
	var carry := 0.0
	var drawing := true
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.01:
			continue
		var d := (b - a) / seg
		var t := 0.0
		while t < seg:
			var left := (on if drawing else off) - carry
			var e := minf(t + left, seg)
			if drawing:
				draw_line(a + d * t, a + d * e, col, width)
			carry += e - t
			if carry >= (on if drawing else off) - 0.001:
				carry = 0.0
				drawing = not drawing
			t = e


## Label of an operation at its target, stacked above the objective when several
## operations share it. The label is clickable (selects the operation).
func _draw_operation_label(op: OperationState, font: Font, slots: Dictionary) -> void:
	var col := _op_color(op)
	var key := op.target_objective if op.target_objective >= 0 else -1000 - op.id
	var k: int = slots.get(key, 0)
	slots[key] = k + 1
	var tp := to_screen(op.target_pos)
	var obj := sim.state.war.objective(op.target_objective)
	var lift := (_objective_size(obj) if obj else 6.0) + 24.0
	var label := "%s #%d · %s" % [op.type_name().to_upper(), op.id, op.phase_name()]
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var box := Rect2(tp + Vector2(-w * 0.5 - 6.0, -lift - 18.0 * (k + 1)), Vector2(w + 12.0, 16.0))
	var sel := op.id == selected_op
	draw_rect(box, Color(0.05, 0.06, 0.07, 0.85), true)
	draw_rect(box, COL_SELECT if sel else Color(col, 0.9), false, 2.0 if sel else 1.0)
	draw_string(font, box.position + Vector2(6, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col.lightened(0.2))
	_op_rects[op.id] = box
	_taken.append(box)


# --- Vehicles, facilities, roads and bases (LOGISTICS-01) ------------------------------------------

const FACILITY_LETTERS := {&"hq": "H", &"barracks": "B", &"supply": "S", &"vehicle": "V", &"ammo": "A", &"fuel": "F", &"repair": "R", &"storage": "C", &"training": "T",
	&"parking": "P", &"guard": "G"}


## Vehicles of the player's faction, in id order.
func _my_vehicles() -> Array:
	var out := []
	for id in sim.vehicles.ids:
		var u: UnitState = sim.state.units.get(id)
		if u and u.alive and u.faction == faction:
			out.append(u)
	return out


## What the logistics layer has under a screen position: {kind: "veh" | "str", id}.
func _logistics_at(sp: Vector2) -> Dictionary:
	var best := {}
	var bd := 14.0
	for u: UnitState in _my_vehicles():
		var d := to_screen(u.position).distance_to(sp)
		if d < bd:
			bd = d
			best = {"kind": "veh", "id": u.id}
	if best.is_empty() and detail_level() >= 1:
		for s in sim.logistics.stores(faction):
			var d2 := to_screen(s.position).distance_to(sp)
			if d2 < 14.0 and d2 < bd:
				bd = d2
				best = {"kind": "str", "id": s.id}
		for s2 in sim.state.construction.all():
			if s2.faction == faction and FacilityDefs.has(s2.type_id) and s2.inventory == null:
				var d3 := to_screen(s2.position).distance_to(sp)
				if d3 < 14.0 and d3 < bd:
					bd = d3
					best = {"kind": "str", "id": s2.id}
	return best


func _draw_logistics_layer(font: Font, level: int) -> void:
	var net: RoadNetwork = sim.state.roads
	# Roads the player built: the world's roads are part of the map picture already.
	if zoom >= 0.05:
		for r: RoadNetwork.Road in net.built.values():
			var pts := PackedVector2Array()
			for i in range(0, r.points.size(), 3):
				pts.append(to_screen(r.points[i]))
			if pts.size() >= 2:
				draw_polyline(pts, Color(0, 0, 0, 0.65), 5.0)
				draw_polyline(pts, Color(0.95, 0.85, 0.5, 0.95), 3.0)
	# Bases: a ring and the name; the facilities as lettered squares when close enough.
	for b: Dictionary in sim.logistics.bases.bases_of(faction):
		var p := to_screen(b.anchor)
		var kind := sim.logistics.bases.base_kind(b.id)
		var col := WorldState.faction_color(faction).lightened(0.3)
		if level == 0:
			draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color(0, 0, 0, 0.7), true)
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), col, false, 2.0)
			# GAMEPLAY-01D: a base with its own objective is already named by the objective symbol.
			var own_obj := sim.war.base_objective(int(b.id))
			_text(font, p + Vector2(10, 5), b.name if kind == "Main base" and (own_obj == null or not own_obj.is_base()) else "", 12, col)
		else:
			# BASE-01: an established base shows its area; a proximity group half its join distance.
			var radius_px := (float(b.radius) if float(b.get("radius", 0.0)) > 0.0 else BaseSim.JOIN_M * 0.5) * zoom
			draw_arc(p, maxf(radius_px, 14.0), 0.0, TAU, 40, Color(col, 0.5), 1.5)
			var bt := "%s (%s)" % [b.name, kind]
			var bw := font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var r_px := maxf(radius_px, 14.0)
			var at := _place([p + Vector2(-bw * 0.5, -r_px - 5.0), p + Vector2(-bw * 0.5, r_px + 15.0), p + Vector2(r_px + 6.0, 4.0)] as Array[Vector2], bw, 12, 15.0, true)
			_text(font, at, bt, 12, col)
	if level >= 1:
		for s in sim.state.construction.all():
			if s.faction != faction or not FacilityDefs.has(s.type_id):
				continue
			var p2 := to_screen(s.position)
			var letter: String = FACILITY_LETTERS.get(FacilityDefs.kind_of(s.type_id), "?")
			var sel: bool = s.id == selected_structure
			var edge := COL_SELECT if sel else Color(0.75, 0.85, 1.0, 0.9)
			var sd := StructureCatalog.get_def(s.type_id)
			var fp: Vector2 = sd.footprint() if sd else Vector2(8, 8)
			var box := Rect2(p2 - Vector2(6, 6), Vector2(12, 12))
			if fp.length() * zoom >= 22.0:
				# UI-01C.1: the building's own footprint, turned as it stands, so close buildings do not pile up.
				var ax := Vector3(cos(s.yaw), 0, -sin(s.yaw)) * fp.x * 0.5
				var az := Vector3(sin(s.yaw), 0, cos(s.yaw)) * fp.y * 0.5
				var poly := PackedVector2Array([to_screen(s.position + ax + az), to_screen(s.position + ax - az), to_screen(s.position - ax - az), to_screen(s.position - ax + az)])
				draw_colored_polygon(poly, Color(0.08, 0.1, 0.12, 0.85))
				poly.append(poly[0])
				draw_polyline(poly, edge, 2.0 if sel else 1.2, true)
				box = Rect2(poly[0], Vector2.ZERO)
				for q in poly:
					box = box.expand(q)
			else:
				draw_rect(box, Color(0.08, 0.1, 0.12, 0.85), true)
				draw_rect(box, edge, false, 2.0 if sel else 1.0)
			_taken.append(box)
			var lw := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			_text(font, p2 + Vector2(-lw * 0.5, 4), letter, 11, Color.WHITE, 2)
			if s.inventory != null and sel and level >= 1:
				var st := "%d / %d / %d" % [roundi(s.inventory.get_qty(Inventory.AMMO)), roundi(s.inventory.get_qty(Inventory.FUEL)), roundi(s.inventory.get_qty(Inventory.SUPPLIES))]
				var sw := font.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
				_text(font, Vector2(p2.x - sw * 0.5, box.end.y + 12.0), st, 10, Color(0.85, 0.9, 1.0))
	# Selected vehicles' routes, then every vehicle.
	for id in selected_vehicles:
		var u := sim.state.get_unit(id)
		if u == null or u.veh == null or u.veh.route.is_empty():
			continue
		var pts2 := PackedVector2Array([to_screen(u.position)])
		var step := maxi(1, u.veh.route.size() / 400)
		for i in range(u.veh.route_i, u.veh.route.size(), step):
			pts2.append(to_screen(u.veh.route[i]))
		pts2.append(to_screen(u.veh.route[u.veh.route.size() - 1]))
		_dashed(pts2, Color(0, 0, 0, 0.55), 5.0)
		_dashed(pts2, Color(0.55, 0.9, 1.0, 0.95), 3.0)
		draw_arc(pts2[pts2.size() - 1], 9.0, 0.0, TAU, 20, Color(0.55, 0.9, 1.0), 2.0)
	for u: UnitState in _my_vehicles():
		var p3 := to_screen(u.position)
		var sel2 := selected_vehicles.has(u.id)
		var fwd := Vector2(-sin(u.yaw), -cos(u.yaw))
		var nrm := Vector2(-fwd.y, fwd.x)
		var big := 9.0 if level == 0 else 12.0
		var is_apc := u.veh.type_id == VehicleDefs.APC
		var col2 := WorldState.faction_color(faction).lightened(0.25)
		var poly := PackedVector2Array([p3 + fwd * big, p3 + nrm * big * 0.6 - fwd * big * 0.6, p3 - nrm * big * 0.6 - fwd * big * 0.6])
		if is_apc:
			poly = PackedVector2Array([p3 + fwd * big + nrm * big * 0.5, p3 + fwd * big - nrm * big * 0.5, p3 - fwd * big - nrm * big * 0.5, p3 - fwd * big + nrm * big * 0.5])
		draw_colored_polygon(poly, Color(0, 0, 0, 0.75))
		var inner := PackedVector2Array()
		for q in poly:
			inner.append(p3 + (q - p3) * 0.78)
		draw_colored_polygon(inner, col2)
		if sel2:
			draw_arc(p3, big + 5.0, 0.0, TAU, 24, COL_SELECT, 2.0)
		var tag := ("APC" if is_apc else "TRK")
		if u.veh.cargo.total() > 1.0:
			tag += "+"
		if not u.veh.occupants.is_empty():
			tag += " %d" % u.veh.occupants.size()
		_taken.append(Rect2(p3 - Vector2(big, big), Vector2(big, big) * 2.0))
		if level >= 1 or sel2:
			var vt := "%s %s" % [tag, u.veh.status_name() if u.veh.status != VehicleState.Status.DRIVING else "%d km/h" % roundi(absf(u.veh.speed) * 3.6)]
			var vw := font.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var vat := _place([p3 + Vector2(big + 4.0, 4.0), p3 + Vector2(-vw - big - 4.0, 4.0), p3 + Vector2(-vw * 0.5, big + 14.0), p3 + Vector2(-vw * 0.5, -big - 4.0)] as Array[Vector2], vw, 11, 14.0, sel2)
			if vat.is_finite():
				_text(font, vat, vt, 11, col2)
